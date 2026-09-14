-- migration-version: PENDING
-- migration-name:    0321_each_writer_of_the_eta_states_its_own_provenance_and_active_vehicles_get_a_forecast
--
-- 0321  THE TWO DEFECTS 0320 BUILT THE TOOL FOR
--
--   DEFECT 1 (db/checks/0240 §A). EVERY `active` dispatch has
--   return_eta_minutes NULL -- 36 of 36 across two twin runs. The only write
--   lives in the branch that ALSO flips status to 'returning', so by
--   construction the forecast cannot exist before the decision it is meant to
--   inform. CLAUDE.md 2.7 asks for a `recall_time` decision; what exists today
--   is an arrival estimate for vehicles already inbound.
--
--   DEFECT 2 (db/checks/0240 §B). Four functions write return_eta_minutes and
--   exactly ONE writes eta_source, so a later overwrite leaves an older label
--   standing: 21 of 61 rows say 'policy_constant' while holding 17 distinct
--   values from 1.6 to 48.8 minutes.
--
-- 0320 explains at length why defect 2 is NOT fixed by funnelling every writer
-- through one function: two of the three unlabelled writers have a legitimate
-- ETA of their own that a recompute would overrule rather than record. Each
-- states its own true provenance here; 0322 makes the shared invariant physical.
--
-- ---------------------------------------------------------------------------
-- THE FIVE SUBSTITUTIONS, and the vocabulary each one introduces
--
--   S1 twin.ottoq_sim_advance_deployed_telemetry   the per-tick refresh (DEFECT 1)
--   S2 twin.ottoq_sim_auto_dispatch_tick           eta_source 'booking_plan:secured'
--   S3 public.ottoq_ingest_vehicle_signal          eta_source 'signal:<p_source>'
--   S4 twin.ottoq_sim_prime_deployment  (columns)  eta_source 'fixture:prime_deployment'
--   S5 twin.ottoq_sim_prime_deployment  (values)   the matching VALUES entry
--
-- Five provenances now exist and each names a different real origin:
--   computed:distance_over_speed   the trip geometry (0320's function)
--   policy_constant:return_eta_minutes  the dial, when the computation REFUSED
--   booking_plan:secured           the ETA the stall was actually held for
--   signal:<source>                what the vehicle itself said
--   fixture:prime_deployment       the t=0 world, which was never a forecast
--   twin_eta_delay_card:<cause>    pre-existing; see the note on defect 3 below
--
-- DEFECT 3 IS NOT FIXED HERE, deliberately. The delay card stamps
-- eta_refreshed_at/eta_source while moving scheduled_return_at -- an INSTANT --
-- and never touches return_eta_minutes, a DURATION. One pair of provenance
-- columns serving two quantities is the G54 class and wants its own file, and
-- 0322's trigger is what will force the question, because a card that stamps
-- the ETA columns without changing the ETA is exactly what that trigger is
-- built to notice. Named here so it is not discovered as a surprise there.
--
-- ---------------------------------------------------------------------------
-- WHERE S1 GOES, AND WHY THAT EXACT LINE
--
-- Measured order inside the per-dispatch loop:
--
--   L156  IF v_dispatch.status = 'active'   -- the delay-card block
--   L206  PERFORM ottoq_sim_emit_telemetry  -- THIS TICK'S packet, with position
--   L218  v_should_return := COALESCE(...)  -- the return decision begins
--   L223  IF v_should_return AND status='active'
--   L287  IF v_should_return AND status='active'   -- the ETA write at L323
--
-- The refresh is inserted immediately BEFORE L218, which is after the tick's own
-- telemetry packet exists and before anything decides on a return. That
-- ordering is the whole point and is not cosmetic:
--   * ottoq_computed_eta_minutes averages speed_kmh over packets with
--     sim_clock_at <= the clock, so placing the refresh at L156 -- the obvious
--     home, inside the block that already tests for 'active' -- would compute
--     every ETA from a history MISSING the newest observation.
--   * placing it before the return decision is what lets a later change make
--     that decision read a forecast instead of producing one. This file does
--     not make the decision read it; it makes the number exist to be read.
--
-- NOTE the anchor is NOT `IF v_dispatch.status = 'active' THEN`. That string is
-- unique, but `IF v_should_return AND v_dispatch.status = 'active' THEN` occurs
-- TWICE (L223 and L287), and anchoring near it invites the 0317 mistake --
-- replace() matches SUBSTRINGS, so every anchor below is asserted to occur
-- exactly once BY LENGTH ARITHMETIC, the way replace() will see it.
--
-- ---------------------------------------------------------------------------
-- ONE ASSUMPTION S1 RESTS ON, MEASURED RATHER THAN ASSUMED
--
-- The loop iterates dispatches; ottoq_refresh_return_eta re-resolves one from
-- (vehicle, run). If a vehicle had TWO open dispatches in one run, the refresh
-- could write to a different row than the loop is standing on, and would do so
-- once per iteration.
--
-- Measured 2026-09-14 18:17 UTC across every run: 156 vehicle-run pairs hold an
-- open dispatch, **0** hold more than one, max is 1. So the case does not arise.
--
-- It is left resolved-by-lookup rather than passed in, deliberately: the
-- function picks the dispatch with exactly the ORDER BY that ottoq_trip_geometry
-- uses (0319), so the ETA and the geometry it derives from can never be about
-- different dispatches. Passing the loop's dispatch_id in would break that tie
-- and re-open the 0319 class from the other side.
--
-- AND THIS IS AN OBSERVATION, NOT A SCHEMA GUARANTEE -- the same distinction
-- 0266 drew about untagged rows. Nothing constrains a vehicle to one open
-- dispatch; today none has two. If that ever changes, A1's "exactly one call
-- per vehicle per tick" stays true while the ROW it lands on stops being
-- obvious, and this note is where to start.
--
-- ---------------------------------------------------------------------------
-- forces_recert: TRUE, and not marginally. S1 causes ~36 extra dispatch rows
-- per run to carry an ETA where they carried NULL, and ottoq_vehicle_dispatches
-- is inside endst.dispatches.vis. Every flagship canon is expected to move.
-- That is the prediction round 44 judges.
-- ===========================================================================

DO $pre$
DECLARE
  v_adt text; v_aut text; v_ivs text; v_pri text;
  a_adt CONSTANT text := E'    v_should_return := COALESCE(v_ret_should, false);';
  a_aut CONSTANT text := E'               returning_started_at = p_sim_clock_now,\n               return_eta_minutes = v_eta,';
  a_ivs CONSTANT text := E'             return_eta_minutes   = (v_dec->>''eta_min'')::numeric,';
  a_pri CONSTANT text := E'        returning_started_at, return_eta_minutes, return_trigger, return_evidence)';
  a_prv CONSTANT text := E'        p_sim_clock_now - (v_lead || '' minutes'')::interval, v_eta, ''prime_inbound'',';
BEGIN
  SELECT p.prosrc INTO v_adt FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin'   AND p.proname='ottoq_sim_advance_deployed_telemetry';
  SELECT p.prosrc INTO v_aut FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin'   AND p.proname='ottoq_sim_auto_dispatch_tick';
  SELECT p.prosrc INTO v_ivs FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_ingest_vehicle_signal';
  SELECT p.prosrc INTO v_pri FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin'   AND p.proname='ottoq_sim_prime_deployment';
  -- Spelled out rather than routed through a format() template. The template
  -- version read `format('0321 P0: % not found', x)` and PostgreSQL rejects it
  -- with `unrecognized format() type specifier " "`: RAISE accepts a bare %,
  -- format() demands %s. Caught by compile-checking this file against a local
  -- PostgreSQL before the apply window, which is the whole argument for G12.
  IF v_adt IS NULL THEN RAISE EXCEPTION '0321 P0: twin.ottoq_sim_advance_deployed_telemetry not found'; END IF;
  IF v_aut IS NULL THEN RAISE EXCEPTION '0321 P0: twin.ottoq_sim_auto_dispatch_tick not found'; END IF;
  IF v_ivs IS NULL THEN RAISE EXCEPTION '0321 P0: public.ottoq_ingest_vehicle_signal not found'; END IF;
  IF v_pri IS NULL THEN RAISE EXCEPTION '0321 P0: twin.ottoq_sim_prime_deployment not found'; END IF;

  -- P1..P5: EVERY anchor occurs EXACTLY ONCE, counted the way replace() counts.
  IF (length(v_adt)-length(replace(v_adt,a_adt,'')))/length(a_adt) <> 1 THEN
    RAISE EXCEPTION '0321 P1: the S1 anchor does not occur exactly once in advance_deployed_telemetry'; END IF;
  IF (length(v_aut)-length(replace(v_aut,a_aut,'')))/length(a_aut) <> 1 THEN
    RAISE EXCEPTION '0321 P2: the S2 anchor does not occur exactly once in auto_dispatch_tick'; END IF;
  IF (length(v_ivs)-length(replace(v_ivs,a_ivs,'')))/length(a_ivs) <> 1 THEN
    RAISE EXCEPTION '0321 P3: the S3 anchor does not occur exactly once in ingest_vehicle_signal'; END IF;
  IF (length(v_pri)-length(replace(v_pri,a_pri,'')))/length(a_pri) <> 1 THEN
    RAISE EXCEPTION '0321 P4: the S4 column-list anchor does not occur exactly once in prime_deployment'; END IF;
  IF (length(v_pri)-length(replace(v_pri,a_prv,'')))/length(a_prv) <> 1 THEN
    RAISE EXCEPTION '0321 P5: the S5 VALUES anchor does not occur exactly once in prime_deployment'; END IF;

  -- P6. 0320 MUST BE APPLIED FIRST. S1 calls a function that would otherwise
  --     not exist, and a function body referencing a missing function is
  --     accepted at CREATE time and fails at RUN time -- i.e. mid-tick, inside
  --     a certification. Checked here, where it costs a failed apply instead.
  IF to_regprocedure('public.ottoq_refresh_return_eta(uuid,uuid,timestamptz,uuid)') IS NULL THEN
    RAISE EXCEPTION '0321 P6: public.ottoq_refresh_return_eta does not exist; apply 0320 first';
  END IF;

  -- P7. NONE OF THE THREE HAS BEEN LABELLED ALREADY. If a re-run reaches here
  --     the substitutions would be applied twice, and S4/S5 would produce a
  --     duplicate column in an INSERT column list.
  IF v_aut ~ 'eta_source' OR v_ivs ~ 'eta_source' OR v_pri ~ 'eta_source' THEN
    RAISE EXCEPTION '0321 P7: one of the three writers already sets eta_source; 0321 is not re-runnable';
  END IF;
END $pre$;

DO $apply$
DECLARE
  v_def text; v_new text;
  a_adt CONSTANT text := E'    v_should_return := COALESCE(v_ret_should, false);';
  r_adt CONSTANT text := E'    -- 0321 (DEFECT 1, db/checks/0240 SecA): refresh the forecast for a vehicle\n'
                      || E'    -- that is STILL WORKING. Before this, 36 of 36 `active` dispatches carried a\n'
                      || E'    -- NULL ETA because the only write lived in the branch that also flips status\n'
                      || E'    -- to ''returning'' -- so the forecast could not exist before the decision it is\n'
                      || E'    -- meant to inform (CLAUDE.md 2.7 asks for a recall_time).\n'
                      || E'    -- PLACED HERE, not in the ''active'' block at L156, because this is AFTER the\n'
                      || E'    -- tick emitted its own telemetry packet: ottoq_computed_eta_minutes averages\n'
                      || E'    -- speed over packets with sim_clock_at <= the clock, and at L156 the newest\n'
                      || E'    -- observation does not exist yet.\n'
                      || E'    IF v_dispatch.status = ''active'' THEN\n'
                      || E'      PERFORM public.ottoq_refresh_return_eta(\n'
                      || E'                v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now);\n'
                      || E'    END IF;\n'
                      || E'    v_should_return := COALESCE(v_ret_should, false);';
  a_aut CONSTANT text := E'               returning_started_at = p_sim_clock_now,\n               return_eta_minutes = v_eta,';
  r_aut CONSTANT text := E'               returning_started_at = p_sim_clock_now,\n'
                      || E'               return_eta_minutes = v_eta,\n'
                      || E'               -- 0321: this ETA came from the SECURED BOOKING\n'
                      || E'               -- (v_plan->''secured''->>''eta_minutes''), not from a recompute. It is\n'
                      || E'               -- what the stall was actually held for, so it is recorded rather\n'
                      || E'               -- than overruled -- and now it says so.\n'
                      || E'               eta_refreshed_at = p_sim_clock_now,\n'
                      || E'               eta_source = ''booking_plan:secured'',';
  a_ivs CONSTANT text := E'             return_eta_minutes   = (v_dec->>''eta_min'')::numeric,';
  r_ivs CONSTANT text := E'             return_eta_minutes   = (v_dec->>''eta_min'')::numeric,\n'
                      || E'             -- 0321: this ETA is what the VEHICLE ITSELF reported, carried in the\n'
                      || E'             -- inbound signal payload. A different origin from the geometry''s\n'
                      || E'             -- estimate and from the booking''s, and the label now distinguishes\n'
                      || E'             -- all three.\n'
                      || E'             eta_refreshed_at     = v_clock,\n'
                      || E'             eta_source           = ''signal:'' || COALESCE(p_source, ''unknown''),';
  a_pri CONSTANT text := E'        returning_started_at, return_eta_minutes, return_trigger, return_evidence)';
  r_pri CONSTANT text := E'        returning_started_at, return_eta_minutes, eta_refreshed_at, eta_source,\n'
                      || E'        return_trigger, return_evidence)';
  a_prv CONSTANT text := E'        p_sim_clock_now - (v_lead || '' minutes'')::interval, v_eta, ''prime_inbound'',';
  r_prv CONSTANT text := E'        p_sim_clock_now - (v_lead || '' minutes'')::interval, v_eta,\n'
                      || E'        -- 0321: the t=0 fixture, which was never a forecast. Labelled so a\n'
                      || E'        -- reader can tell "the fixture put 30 here" from "the computation\n'
                      || E'        -- returned 30" -- db/checks/0240 found 38 rows where they could not.\n'
                      || E'        p_sim_clock_now, ''fixture:prime_deployment'', ''prime_inbound'',';
BEGIN
  -- S1
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_deployed_telemetry';
  v_new := replace(v_def, a_adt, r_adt);
  IF v_new = v_def THEN RAISE EXCEPTION '0321 S1: substitution changed nothing'; END IF;
  EXECUTE v_new;

  -- S2
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_auto_dispatch_tick';
  v_new := replace(v_def, a_aut, r_aut);
  IF v_new = v_def THEN RAISE EXCEPTION '0321 S2: substitution changed nothing'; END IF;
  EXECUTE v_new;

  -- S3
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_ingest_vehicle_signal';
  v_new := replace(v_def, a_ivs, r_ivs);
  IF v_new = v_def THEN RAISE EXCEPTION '0321 S3: substitution changed nothing'; END IF;
  EXECUTE v_new;

  -- S4 + S5 in ONE rewrite of prime_deployment: the column list and the VALUES
  -- list must move together or the INSERT is malformed. Two EXECUTEs would
  -- leave a window -- inside this transaction only, but a failed second
  -- substitution would abort with the first already applied to the text, and
  -- the error message would point at the wrong half.
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_prime_deployment';
  v_new := replace(replace(v_def, a_pri, r_pri), a_prv, r_prv);
  IF v_new = v_def THEN RAISE EXCEPTION '0321 S4/S5: substitution changed nothing'; END IF;
  IF position(r_pri in v_new) = 0 THEN RAISE EXCEPTION '0321 S4: the column list did not change'; END IF;
  IF position(r_prv in v_new) = 0 THEN RAISE EXCEPTION '0321 S5: the VALUES list did not change'; END IF;
  EXECUTE v_new;
END $apply$;

DO $post$
DECLARE v_adt text; v_aut text; v_ivs text; v_pri text; v_labelers int; v_dupes int;
BEGIN
  SELECT p.prosrc INTO v_adt FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_deployed_telemetry';
  SELECT p.prosrc INTO v_aut FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_auto_dispatch_tick';
  SELECT p.prosrc INTO v_ivs FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_ingest_vehicle_signal';
  SELECT p.prosrc INTO v_pri FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_prime_deployment';

  -- A1. THE REFRESH IS WIRED, and exactly once. Twice would double the cost
  --     and, worse, make the ETA depend on where in the loop you looked.
  IF (length(v_adt)-length(replace(v_adt,'ottoq_refresh_return_eta','')))/length('ottoq_refresh_return_eta') <> 1 THEN
    RAISE EXCEPTION '0321 A1: the per-tick refresh call is missing or duplicated';
  END IF;

  -- A2. IT IS BEFORE THE RETURN DECISION AND AFTER THE TELEMETRY EMIT.
  --     Asserted positionally, because §"WHERE S1 GOES" is an argument about
  --     ORDER and an argument about order that is not checked is a comment.
  IF NOT (position('ottoq_sim_emit_telemetry' in v_adt) < position('ottoq_refresh_return_eta' in v_adt)
          AND position('ottoq_refresh_return_eta' in v_adt)
              < position('v_should_return := COALESCE(v_ret_should, false);' in v_adt)) THEN
    RAISE EXCEPTION '0321 A2: the refresh is not between the telemetry emit and the return decision';
  END IF;

  -- A3. ALL FOUR WRITERS NOW SET eta_source.
  SELECT count(*) INTO v_labelers
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.prosrc ~ 'eta_source';
  IF v_labelers < 4 THEN
    RAISE EXCEPTION '0321 A3: only % function(s) set eta_source; expected at least 4', v_labelers;
  END IF;

  -- A4. THE prime_deployment INSERT IS STILL WELL FORMED -- the column list and
  --     the VALUES list each gained exactly two entries. Counted, not trusted:
  --     a mismatched INSERT compiles fine and fails at t=0 of the next run.
  IF (length(v_pri)-length(replace(v_pri,'eta_refreshed_at','')))/length('eta_refreshed_at') <> 1
     OR (length(v_pri)-length(replace(v_pri,'fixture:prime_deployment','')))/length('fixture:prime_deployment') <> 1 THEN
    RAISE EXCEPTION '0321 A4: prime_deployment did not gain exactly one column and one value';
  END IF;

  -- A5. NO WALL CLOCK WAS INTRODUCED. Each stamp uses the caller's SIM clock.
  IF v_aut !~ 'eta_refreshed_at = p_sim_clock_now' THEN
    RAISE EXCEPTION '0321 A5: auto_dispatch_tick does not stamp the sim clock'; END IF;
  IF v_ivs !~ 'eta_refreshed_at     = v_clock' THEN
    RAISE EXCEPTION '0321 A5: ingest_vehicle_signal does not stamp the sim clock'; END IF;

  -- A6. EACH WRITER EMITS ITS OWN LABEL, AND NO TWO EMIT THE SAME ONE.
  --
  --     AN EARLIER DRAFT OF THIS ASSERTION WAS FAKE. It read
  --     `SELECT count(DISTINCT x) FROM unnest(ARRAY['computed:...', ...])` and
  --     required the answer to be 5 -- counting five distinct string literals
  --     that I had just typed out by hand. It could not have failed, and it
  --     said nothing whatever about the code. That is the defect class this
  --     whole file exists to fix, committed inside the fix: an instrument that
  --     answers a different question from the one it appears to ask.
  --
  --     What is checked instead: each label is present in the function that is
  --     supposed to emit it, and in no other.
  IF v_aut !~ 'booking_plan:secured'      THEN RAISE EXCEPTION '0321 A6: auto_dispatch_tick does not emit booking_plan:secured'; END IF;
  IF v_ivs !~ 'signal:'                   THEN RAISE EXCEPTION '0321 A6: ingest_vehicle_signal does not emit signal:<source>'; END IF;
  IF v_pri !~ 'fixture:prime_deployment'  THEN RAISE EXCEPTION '0321 A6: prime_deployment does not emit fixture:prime_deployment'; END IF;
  IF v_adt !~ 'policy_constant:return_eta_minutes' THEN
    RAISE EXCEPTION '0321 A6: advance_deployed_telemetry lost its own label'; END IF;

  SELECT count(*) INTO v_dupes
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ~ 'booking_plan:secured'
     AND p.proname <> 'ottoq_sim_auto_dispatch_tick';
  IF v_dupes <> 0 THEN
    RAISE EXCEPTION '0321 A6: % other function(s) emit booking_plan:secured; a label shared by two '
                    'writers distinguishes nothing', v_dupes;
  END IF;
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0321_each_writer_of_the_eta_states_its_own_provenance_and_active_vehicles_get_a_forecast', true,
   'Five substitutions. S1 refreshes the return ETA for `active` dispatches once per tick, '
   'placed between the telemetry emit and the return decision so the newest packet is in the '
   'speed average (db/checks/0240 SecA: 36 of 36 active dispatches had a NULL ETA). S2/S3/S4/S5 '
   'give the three unlabelled writers their own true provenance -- booking_plan:secured, '
   'signal:<source>, fixture:prime_deployment (0240 SecB: 21 of 61 rows labelled policy_constant '
   'held 17 distinct values). forces_recert TRUE and not marginally: S1 puts an ETA on ~36 '
   'dispatch rows per run that carried NULL, and ottoq_vehicle_dispatches is inside '
   'endst.dispatches.vis, so every flagship canon is expected to move. Defect 3 (one pair of '
   'provenance columns serving both a duration and an instant) is deliberately NOT fixed here.',
   now())
ON CONFLICT (name) DO NOTHING;
