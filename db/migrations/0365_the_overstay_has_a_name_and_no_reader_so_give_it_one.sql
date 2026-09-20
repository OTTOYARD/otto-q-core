-- migration-version: 20260920033500
-- migration-name:    the_overstay_has_a_name_and_no_reader_so_give_it_one
--
-- 0365  `window_elapsed_occupied` HAS ONE WRITER AND ZERO READERS. MAKE THE
--       OVERSTAY COUNTABLE BEFORE ANYTHING ACTS ON IT.
--
-- Fixes the **measurement** half of G81. Deliberately changes no engine
-- behaviour: this is 2.9a's measured-before-enforced doctrine applied to a
-- finding whose population nobody has ever counted.
--
-- ══ 1. WHAT G81 ESTABLISHED ════════════════════════════════════════════════
--
-- `ottoq.ottoq_release_expired_bookings` releases a booking whose window has
-- elapsed **while the vehicle is still occupying the stall**, and stamps
-- `release_reason = 'window_elapsed_occupied'`. The engine therefore *recognises*
-- the overstay and names it precisely.
--
-- Nothing reads the name. Searched exhaustively: the string occurs in **one**
-- object in the whole database -- the function that writes it -- with no other
-- function, no view, no matview, and nothing in `edge-functions/`, `bridge/`,
-- `proposer/` or `metrics/`.
--
-- Measured on Arm A `3fb415d8`: **`window_elapsed_occupied` = 162** against plain
-- **`window_elapsed` = 143**. More bookings expire with the asset still plugged in
-- than expire cleanly, so this is the normal case rather than an edge case.
--
-- The consequence, from G80: the calendar forgets a stall the world still holds,
-- so every downstream reader sees a free stall that is not free, and **41**
-- `assignment_refused_occupied` preflight refusals follow on one run.
--
-- ══ 2. WHY A FUNCTION AND NOT A VIEW, AND WHY NOT THE FRAME YET ════════════
--
-- **A function taking `sim_run_id`**, matching `ottoq_kpi_five(uuid)`, which is
-- this repo's idiom for a run-scoped answer. A view would have had to pick its own
-- run -- and the obvious `WHERE r.status = 'running'` makes it silently empty the
-- moment the run ends, so it could never examine the run you just finished. That
-- is the failure mode of an instrument you consult after the fact, which is when
-- an overstay is usually investigated.
--
-- **It does NOT touch the decision frame, and that restraint is the point.**
-- Teaching `ottoq_build_decision_frame` to publish overstays would change what
-- every proposer sees and therefore what the engine does -- a behaviour change on
-- the assignment path, justified by a population **nobody has counted per run
-- yet**. G80 reached its third revision precisely because it moved faster than its
-- evidence. So: count first, then decide. The frame change is a separate file that
-- should cite this function's output.
--
-- ══ 3. THE CLOCK, WHICH IS WHERE THIS WOULD OTHERWISE GO WRONG ════════════
--
-- Coverage is judged against the RUN'S OWN `sim_clock_current`, falling back to
-- `sim_clock_start`, and **never `now()`**. `ottoq_stall_bookings.during` is a SIM
-- range (0357 documented all four of that table's timestamps), and wall time runs
-- *ahead* of the sim clock -- 4h46m on the run that caught G77 -- so a `now()`
-- comparison would judge every booking expired and report the entire depot as
-- overstaying. That is G77's defect exactly, and it is the reason this file states
-- its clock instead of assuming one.
--
-- ══ 4. WHAT COUNTS AS AN OVERSTAY HERE ════════════════════════════════════
--
-- A stall that is **physically occupied** (`stalls.current_vehicle_id` is set) and
-- for which **no booking covers the sim clock** for that same vehicle on that same
-- stall in that run.
--
-- Physical occupancy is the anchor rather than the vehicle's own `current_stall_id`
-- because G81's negative check showed the two agree -- 57 of 57 on the twin depot,
-- zero empty and zero naming a different vehicle -- so either would do, and the
-- stall is the side the assignment path actually collides with.
--
-- `last_release_reason` is reported where a released booking for that pair exists,
-- so `window_elapsed_occupied` is visible as the cause rather than inferred. It is
-- NULL when a vehicle occupies a stall it never had a booking for at all, which is
-- a different condition and must not be silently merged with the first.
--
-- ALL STALL TYPES, not just charge. An overstay on a wash bay or a staging place is
-- still a stall the calendar thinks is free; `stall_type` is returned so a reader
-- can narrow, rather than the function deciding which ones matter.
--
-- ══ 5. CLASSIFICATION ══════════════════════════════════════════════════════
--
-- `forces_recert: FALSE`. It adds one read-only function and changes no engine
-- behaviour, no table and no existing routine. P4 asserts nothing on the tick path
-- gains a caller of it.
--
-- ══════════════════════════════════════════════════════════════════════════════

-- P0/P1. No certification scheduled or in flight.
DO $inflight$
DECLARE v_jobs text; v_pairs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0365 P0: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0365 P1: % certification pair(s) are active', v_pairs;
  END IF;

  RAISE NOTICE '0365 P0/P1: no certification scheduled, no pair running';
END $inflight$;

-- P2. THE PREMISE, asserted rather than trusted to a header. If something has
-- started reading `window_elapsed_occupied` since G81 was filed, then the signal
-- is no longer orphaned and this file should be re-justified rather than applied
-- on a stale finding.
DO $premise$
DECLARE v_readers int;
BEGIN
  SELECT count(*) INTO v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE position('window_elapsed_occupied' in p.prosrc) > 0
     AND p.proname <> 'ottoq_release_expired_bookings';
  IF v_readers > 0 THEN
    RAISE EXCEPTION '0365 P2: % routine(s) other than the writer now reference '
                    'window_elapsed_occupied -- G81 is stale, re-justify before applying',
                    v_readers;
  END IF;
  RAISE NOTICE '0365 P2: the signal still has exactly one writer and no readers';
END $premise$;

-- P3. The columns this function reads must exist. A renamed column would make the
-- function raise at RUNTIME, and a measurement instrument that errors on use is
-- worse than none because it discredits the finding.
DO $cols$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(t || '.' || c, ', ') INTO v_missing
    FROM (VALUES ('stalls','current_vehicle_id'), ('stalls','stall_type'),
                 ('stalls','depot_id'), ('stalls','stall_code'),
                 ('ottoq_stall_bookings','during'), ('ottoq_stall_bookings','state'),
                 ('ottoq_stall_bookings','release_reason'),
                 ('ottoq_stall_bookings','released_at'),
                 ('ottoq_sim_runs','sim_clock_current'),
                 ('ottoq_sim_runs','sim_clock_start')) AS x(t, c)
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = x.t AND column_name = x.c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0365 P3: missing column(s): %', v_missing;
  END IF;
  RAISE NOTICE '0365 P3: every column the function reads exists';
END $cols$;

-- ══ THE FUNCTION ═════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_stall_overstays(p_sim_run_id uuid)
 RETURNS TABLE (
   stall_id            uuid,
   stall_code          text,
   stall_type          text,
   depot_id            uuid,
   vehicle_id          uuid,
   vehicle_state       text,
   last_release_reason text,
   last_released_at    timestamptz,
   last_window_end     timestamptz,
   overstay_minutes    numeric,
   sim_clock           timestamptz)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH r AS (
    --: NEVER now(). `during` is a SIM range (0357) and wall time runs ahead of the
    --: sim clock, so a wall comparison would call the whole depot overstaying --
    --: G77's defect.
    SELECT sr.sim_run_id,
           COALESCE(sr.sim_clock_current, sr.sim_clock_start) AS clk
      FROM public.ottoq_sim_runs sr
     WHERE sr.sim_run_id = p_sim_run_id
  ), occupied AS (
    --: Physical occupancy is the anchor. G81's negative check found
    --: stalls.current_vehicle_id and vehicles.current_stall_id agree 57 of 57, and
    --: the stall is the side the assignment path collides with.
    SELECT s.id, s.stall_code, s.stall_type::text AS stype, s.depot_id,
           s.current_vehicle_id AS veh
      FROM public.stalls s
     WHERE s.current_vehicle_id IS NOT NULL
  ), uncovered AS (
    SELECT o.*, r.clk, r.sim_run_id
      FROM occupied o CROSS JOIN r
     WHERE NOT EXISTS (
       SELECT 1 FROM public.ottoq_stall_bookings b
        WHERE b.sim_run_id = r.sim_run_id
          AND b.stall_id   = o.id
          AND b.vehicle_id = o.veh
          AND b.state IN ('held','active')
          AND b.during @> r.clk)
  )
  SELECT u.id, u.stall_code, u.stype, u.depot_id, u.veh,
         v.current_state::text,
         --: the released booking that explains it, newest first. NULL means the
         --: vehicle occupies a stall it never held a booking for, which is a
         --: DIFFERENT condition and is deliberately not merged with an overstay.
         last_b.release_reason,
         last_b.released_at,
         upper(last_b.during),
         CASE WHEN last_b.during IS NOT NULL
              THEN round(extract(epoch from (u.clk - upper(last_b.during))) / 60.0, 1) END,
         u.clk
    FROM uncovered u
    LEFT JOIN public.vehicles v ON v.id = u.veh
    LEFT JOIN LATERAL (
      SELECT b.release_reason, b.released_at, b.during
        FROM public.ottoq_stall_bookings b
       WHERE b.sim_run_id = u.sim_run_id
         AND b.stall_id   = u.id
         AND b.vehicle_id = u.veh
         AND b.released_at IS NOT NULL
       ORDER BY b.released_at DESC
       LIMIT 1) AS last_b ON true;
$function$;

COMMENT ON FUNCTION public.ottoq_stall_overstays(uuid) IS
'0365, the measurement half of G81. Lists stalls that are PHYSICALLY OCCUPIED while no booking covers the run''s sim clock for that vehicle on that stall -- an overstay. Exists because the engine already detects this and names it: ottoq_release_expired_bookings stamps release_reason = ''window_elapsed_occupied'', and that string occurs in exactly ONE object in the whole database, the function that writes it. No other routine, no view, no matview, nothing in edge-functions/, bridge/, proposer/ or metrics/. One writer, zero readers. Measured on run 3fb415d8: 162 window_elapsed_occupied against 143 clean window_elapsed, so more bookings expire with the asset still plugged in than expire cleanly. The consequence (G80) is that the calendar forgets a stall the world still holds, so downstream readers see a free stall that is not free and 41 assignment_refused_occupied preflight refusals followed on one run. A FUNCTION rather than a view because a view must pick its own run, and the obvious WHERE status = ''running'' would make it silently empty the moment a run ends -- useless for the after-the-fact investigation an overstay usually gets. Judges coverage against the run''s own sim_clock_current (fallback sim_clock_start) and NEVER now(): during is a SIM range and wall time runs ahead, so a wall comparison would report the entire depot overstaying, which is G77 exactly. last_release_reason is NULL when the vehicle occupies a stall it never had a booking for -- a different condition, deliberately not merged. All stall types are returned with stall_type so the reader narrows, rather than this function deciding which matter. DELIBERATELY DOES NOT TOUCH THE DECISION FRAME: publishing overstays to proposers changes engine behaviour on the assignment path, and that wants this function''s counts first. Count, then decide.';

-- P4. POST-CHECK. It is callable, it is honest on a nonexistent run, and nothing
-- on the tick path has gained a caller -- the last of these is what keeps the
-- forces_recert:FALSE classification true.
DO $post$
DECLARE v_n int; v_run uuid; v_rows int; v_callers int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_stall_overstays';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0365 P4: expected 1 ottoq_stall_overstays, found %', v_n;
  END IF;

  --: an unknown run must return zero rows, not raise. An instrument that throws
  --: on a purged run id is one nobody will use after the fact.
  SELECT count(*) INTO v_rows
    FROM public.ottoq_stall_overstays('00000000-0000-0000-0000-000000000000'::uuid);
  IF v_rows <> 0 THEN
    RAISE EXCEPTION '0365 P4: a nonexistent run returned % row(s); it must return none', v_rows;
  END IF;

  SELECT count(*) INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE position('ottoq_stall_overstays' in p.prosrc) > 0
     AND p.proname <> 'ottoq_stall_overstays';
  IF v_callers > 0 THEN
    RAISE EXCEPTION '0365 P4: % routine(s) already call this -- it is meant to be '
                    'read by people first, and a caller changes the recert case', v_callers;
  END IF;

  --: exercise it against the newest twin-depot run so the file proves it runs on
  --: real data rather than only on an empty argument
  SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
   WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY sr.started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    SELECT count(*) INTO v_rows FROM public.ottoq_stall_overstays(v_run);
    RAISE NOTICE '0365 P4: callable, honest on an unknown run, no callers; % overstay row(s) on run %',
                 v_rows, v_run;
  ELSE
    RAISE NOTICE '0365 P4: callable, honest on an unknown run, no callers; no twin-depot run to exercise';
  END IF;
END $post$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0365_the_overstay_has_a_name_and_no_reader_so_give_it_one', false,
  'forces_recert FALSE: adds one read-only STABLE function and changes no engine behaviour, no table and '
  'no existing routine; P4 asserts nothing on the tick path calls it. Fixes the MEASUREMENT half of G81. '
  'ottoq_release_expired_bookings stamps release_reason = ''window_elapsed_occupied'' when a booking''s '
  'window elapses while the vehicle still occupies the stall -- so the engine recognises the overstay and '
  'names it -- and that string occurs in exactly ONE object in the whole database, the function that '
  'writes it: one writer, zero readers, confirmed across pg_proc, pg_views, pg_matviews and the repo''s '
  'TypeScript and Python. Measured on run 3fb415d8: 162 window_elapsed_occupied against 143 clean '
  'window_elapsed, so more bookings expire with the asset still plugged in than expire cleanly, and G80 '
  'measured the price at 41 assignment_refused_occupied preflight refusals. A FUNCTION taking sim_run_id '
  'rather than a view, matching ottoq_kpi_five''s idiom: a view must pick its own run and the obvious '
  'status = ''running'' filter would make it silently empty the moment the run ends, which is exactly when '
  'an overstay gets investigated. Coverage is judged against the run''s own sim_clock_current with a '
  'sim_clock_start fallback and NEVER now() -- during is a SIM range (0357) and wall time runs ahead of '
  'the sim clock, so a wall comparison would report the entire depot overstaying, which is G77''s defect. '
  'DELIBERATELY DOES NOT TOUCH ottoq_build_decision_frame: publishing overstays to proposers would change '
  'engine behaviour on the assignment path, and G80 reached its third revision by moving faster than its '
  'evidence, so the population gets counted before anything acts on it. Also deliberate: '
  'last_release_reason is NULL when a vehicle occupies a stall it never had a booking for, a different '
  'condition that must not be silently merged with an overstay.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
