-- migration-version: 20260908222953
-- migration-name:    a_comparative_score_may_read_only_what_every_arm_writes
--
-- G32 / db/checks/0149. public.ottoq_ab_score_run was applied earlier today
-- (0230, 20260908220518) and described as "a score that cannot be gamed by not
-- checking." It is. It is also fully gameable by WRITING SOMEWHERE ELSE, which
-- is exactly what both baselines do, and there was no way to notice because no
-- baseline run has ever existed to score (0147: policy='otto_q', 845 of 845).
--
-- THE DEFECT, field by field. Measured from the three tick functions' write
-- sets, not inferred:
--
--   otto_q   -> stall bookings calendar, decisions, SDRs, rule evaluations,
--               vehicle commands, events
--   greedy   -> ocpp charge sessions (via twin.ottoq_sim_auto_charge_assign_tick
--               -> ottoq_sim_start_charge_session), events
--   fifo     -> vehicles and stalls DIRECTLY; no session of its own. The world's
--               twin.ottoq_sim_reconcile_charge_sessions opens one for it on the
--               next advance, so fifo does charge -- one tick late, on a session
--               it did not create.
--
-- Of the scorer's sixteen fields, eleven read otto_q-only substrate, one
-- (throughput.events) is mixed and dominated by which arm it is, and four are
-- already common ground: coverage.charge_sessions and the whole
-- peak_concurrent_kw / site_cap_kw / pct_of_cap / cap_breached group, which are
-- computed from ocpp_sessions. That last part is a correction to 0149's first
-- draft, which accused the peak calculation of reading bookings. It does not,
-- and the most safety-critical field in the function was fair all along.
--
-- WHAT THIS MIGRATION DOES, AND DELIBERATELY DOES NOT DO.
--
--   DOES:  adds an `outcome` block computed only from ocpp_sessions and the
--          run's own clock -- substrate every policy's vehicles end up in --
--          and a `comparability` block that names, per block, whether it may be
--          used to compare two arms.
--   DOES NOT: delete, rename or alter a single existing field. Everything 0230
--          emits, it still emits, at the same key, with the same value. This is
--          a strict superset, so no consumer breaks and the 0230 evidence
--          already recorded stays readable.
--
-- The comparability block is the actual product here. A score that carries its
-- own validity metadata cannot be quoted out of context by accident: a reader
-- who takes `throughput.decisions` across two policies has to ignore a field
-- that says, in the same object, that doing so is invalid.
--
-- WHY NO TIME-TO-SERVICE FIELD, though CLAUDE.md 2.9's KPI-5 wants one. It
-- needs a per-vehicle arrival instant on common ground and there is not one:
-- the only arrival-shaped event types in the stream are `ottoq.arrival_forecast`
-- (a prediction, otto_q-only) and `fleet.arrival_delayed` (a disturbance).
-- Deriving arrival from vehicles.last_state_change fails because that column
-- holds only the latest transition, not history. Left out rather than
-- approximated. Recorded as the next thing the A/B needs.
--
-- WHAT IS NOT PROVEN BY THIS MIGRATION, and cannot be until a baseline arm
-- exists: that the outcome block actually reads non-zero for fifo or greedy.
-- The falsifier is stated in the check and repeated in the lineage note: score
-- a fifo arm and an otto_q arm on one seed, and if any outcome field reads zero
-- for fifo, the block is still reading otto_q's substrate and this migration
-- failed. Creating that arm is the next piece of work, not the last.
--
-- forces_recert: FALSE. ottoq_ab_score_run is STABLE, is read-only, is called
-- by nothing in the decide path, and is not an input to any verdict atom. No
-- canon can move. The floor is checked after applying anyway, because
-- "cannot move" and "did not move" are different sentences.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction,
--  matching 0226-0230. The whole file is one atomic unit.)

-- ---------------------------------------------------------------------------
-- P-  NEVER APPLY WHILE A CERTIFICATION PAIR IS IN FLIGHT.
--     pg_stat_activity is the ONLY authority. ottoq_sim_runs cannot see one
--     (both arms are one transaction) and cron.job_run_details reports an
--     in-flight two-statement job as 'succeeded' in ~1 s -- observed twice on
--     2026-09-08 during round 28, on columns e and f.
-- ---------------------------------------------------------------------------
DO $P$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active' AND query LIKE '%ottoq_determinism_pair%';
  IF n > 0 THEN
    RAISE EXCEPTION 'P- REFUSED: % certification pair(s) in flight', n;
  END IF;
END $P$;

-- ---------------------------------------------------------------------------
-- P0  The function is the one 0230 applied: same signature, same volatility,
--     same language. A VOLATILE or plpgsql successor would mean someone else
--     changed it and every statement above is about a different object.
-- ---------------------------------------------------------------------------
DO $P0$
-- variables deliberately NOT named v/l/k: `l` would collide with the
-- pg_language alias below and PL/pgSQL resolves the variable first, making
-- l.lanname ambiguous. Caught in pre-flight, same class as 0229's `plan jsonb`.
DECLARE v_vol "char"; v_lang name; v_kind "char";
BEGIN
  SELECT p.provolatile, lg.lanname, p.prokind INTO v_vol, v_lang, v_kind
    FROM pg_proc p JOIN pg_language lg ON lg.oid = p.prolang
   WHERE p.oid = 'public.ottoq_ab_score_run(uuid)'::regprocedure;
  IF v_vol  <> 's'   THEN RAISE EXCEPTION 'P0 REFUSED: provolatile is %, expected s (STABLE)', v_vol; END IF;
  IF v_lang <> 'sql' THEN RAISE EXCEPTION 'P0 REFUSED: language is %, expected sql', v_lang; END IF;
  IF v_kind <> 'f'   THEN RAISE EXCEPTION 'P0 REFUSED: prokind is %, expected f', v_kind; END IF;
END $P0$;

-- ---------------------------------------------------------------------------
-- P1  The definition is byte-for-byte what the anchors below were read from.
-- ---------------------------------------------------------------------------
DO $P1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_ab_score_run(uuid)'::regprocedure));
  IF h <> 'a472af5fccb93334ac549d1e4da77bef' THEN
    RAISE EXCEPTION 'P1 REFUSED: functiondef md5 is %, pinned a472af5fccb93334ac549d1e4da77bef', h;
  END IF;
END $P1$;

-- ---------------------------------------------------------------------------
-- THE CHANGE. Catalog-derived, two anchored substitutions. The 4,012-character
-- definition is read from pg_get_functiondef and only the two anchor sites are
-- touched, so no existing character is retyped and no transcription error in
-- the preserved 0230 logic is possible. Each anchor's uniqueness is asserted
-- before it is used -- a substitution on a non-unique anchor is a silent
-- corruption, not an error.
-- ---------------------------------------------------------------------------
DO $CHG$
DECLARE
  d text; aA text; aB text; nA int; nB int;
BEGIN
  d := pg_get_functiondef('public.ottoq_ab_score_run(uuid)'::regprocedure);

  aA := E'AS kw\n    FROM public.ocpp_sessions o';
  aB := E'''{}''::jsonb))\n)\nFROM r;';

  nA := (length(d) - length(replace(d, aA, ''))) / length(aA);
  nB := (length(d) - length(replace(d, aB, ''))) / length(aB);
  IF nA <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: anchor A occurs % times, expected 1', nA; END IF;
  IF nB <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: anchor B occurs % times, expected 1', nB; END IF;

  -- A: widen the sess CTE. Appending columns cannot disturb the ev/running/peak
  --    chain, which selects started_at, ended_at and kw by name.
  --    raw_ended_at is o.ended_at UNCOALESCED, so an open session is countable
  --    as open rather than silently given a one-minute duration -- the existing
  --    coalesced ended_at is correct for the power sweep and wrong for a
  --    duration total, and both are now available under different names.
  d := replace(d, aA, E'AS kw,\n         o.vehicle_id, o.stall_id, o.ended_at AS raw_ended_at,\n         COALESCE(o.energy_delivered_kwh, 0) AS kwh,\n         o.soc_start, o.soc_end\n    FROM public.ocpp_sessions o');

  -- B: append the two new blocks before the closing paren of jsonb_build_object.
  d := replace(d, aB, E'''{}''::jsonb)),\n'
    || E'  ''outcome'', jsonb_build_object(\n'
    || E'     ''energy_delivered_kwh'', round(COALESCE((SELECT sum(kwh) FROM sess), 0)::numeric, 2),\n'
    || E'     ''charge_sessions'',      (SELECT count(*) FROM sess),\n'
    || E'     ''sessions_still_open'',  (SELECT count(*) FROM sess WHERE raw_ended_at IS NULL),\n'
    || E'     ''vehicles_served'',      (SELECT count(DISTINCT vehicle_id) FROM sess),\n'
    || E'     ''service_points_used'',  (SELECT count(DISTINCT stall_id) FROM sess),\n'
    || E'     ''turns_per_point'',      round(((SELECT count(*) FROM sess)::numeric\n'
    || E'                                 / NULLIF((SELECT count(DISTINCT stall_id) FROM sess), 0)), 2),\n'
    || E'     ''service_point_hours'',  round(COALESCE((SELECT sum(extract(epoch FROM (raw_ended_at - started_at)))/3600.0\n'
    || E'                                 FROM sess WHERE raw_ended_at IS NOT NULL), 0)::numeric, 2),\n'
    || E'     ''kwh_per_point_hour'',   round((COALESCE((SELECT sum(kwh) FROM sess), 0)\n'
    || E'                                 / NULLIF((SELECT sum(extract(epoch FROM (raw_ended_at - started_at)))/3600.0\n'
    || E'                                            FROM sess WHERE raw_ended_at IS NOT NULL), 0))::numeric, 1),\n'
    || E'     ''soc_points_added'',     (SELECT sum(GREATEST(soc_end - soc_start, 0)) FROM sess\n'
    || E'                                 WHERE soc_start IS NOT NULL AND soc_end IS NOT NULL),\n'
    || E'     ''mean_soc_gain'',        round((SELECT avg(soc_end - soc_start) FROM sess\n'
    || E'                                 WHERE soc_start IS NOT NULL AND soc_end IS NOT NULL)::numeric, 2),\n'
    || E'     ''soc_measured_sessions'',(SELECT count(*) FROM sess\n'
    || E'                                 WHERE soc_start IS NOT NULL AND soc_end IS NOT NULL),\n'
    || E'     ''sim_hours'',            round((extract(epoch FROM (r.sim_clock_current - r.sim_clock_start))/3600.0)::numeric, 2)),\n'
    || E'  ''comparability'', jsonb_build_object(\n'
    || E'     ''outcome'',    ''all_policies -- ocpp_sessions and the run clock; every arm''''s vehicles land here'',\n'
    || E'     ''safety'',     ''MIXED -- peak_concurrent_kw/site_cap_kw/pct_of_cap/cap_breached are all_policies '
    || E'(computed from ocpp_sessions); incapable_charge_bookings and unverifiable_charge_bookings are otto_q_only'',\n'
    || E'     ''coverage'',   ''MIXED -- charge_sessions is all_policies; bookings_total, charge_bookings, '
    || E'used_calendar, rule_evals_total and consulted_shield are otto_q_only'',\n'
    || E'     ''throughput'', ''otto_q_only -- decisions, sdrs and vehicles_booked are written only by the decide '
    || E'path; events is mixed and dominated by which arm it is. Never compare two arms on this block.'',\n'
    || E'     ''rule'',       ''db/checks/0149: a comparative metric read from an artifact only one arm produces '
    || E'measures which arm it is, not how it performed. Such a metric is perfectly reproducible.'')\n'
    || E')\nFROM r;');

  EXECUTE d;
END $CHG$;

-- ---------------------------------------------------------------------------
-- A1  The function still exists with the same signature, volatility and
--     language. CREATE OR REPLACE cannot change the return type, but it can
--     change volatility if the replacement says so; assert it did not.
-- ---------------------------------------------------------------------------
DO $A1$
DECLARE v_vol "char"; v_lang name;
BEGIN
  SELECT p.provolatile, lg.lanname INTO v_vol, v_lang
    FROM pg_proc p JOIN pg_language lg ON lg.oid = p.prolang
   WHERE p.oid = 'public.ottoq_ab_score_run(uuid)'::regprocedure;
  IF v_vol <> 's' OR v_lang <> 'sql' THEN
    RAISE EXCEPTION 'A1 FAILED: volatility/language is %/%, expected s/sql', v_vol, v_lang;
  END IF;
END $A1$;

-- ---------------------------------------------------------------------------
-- A2  STRICT SUPERSET. Every key 0230 emitted is still emitted, and the two
--     new blocks are present. Scored on the newest completed run so this is
--     asserted against real output, not against the source text.
-- ---------------------------------------------------------------------------
DO $A2$
DECLARE j jsonb; run uuid; missing text;
BEGIN
  SELECT sim_run_id INTO run FROM public.ottoq_sim_runs
   WHERE status = 'completed' AND depot_id IS NOT NULL
   ORDER BY started_at DESC LIMIT 1;
  IF run IS NULL THEN RAISE EXCEPTION 'A2 FAILED: no completed run to score'; END IF;

  j := public.ottoq_ab_score_run(run);
  IF j IS NULL THEN RAISE EXCEPTION 'A2 FAILED: scorer returned NULL for %', run; END IF;

  SELECT string_agg(k, ', ') INTO missing FROM unnest(ARRAY[
    'run','coverage','safety','throughput','outcome','comparability']) AS k
   WHERE NOT (j ? k);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'A2 FAILED: missing top-level block(s): %', missing; END IF;

  SELECT string_agg(k, ', ') INTO missing FROM unnest(ARRAY[
    'bookings_total','charge_bookings','rule_evals_total','charge_sessions',
    'used_calendar','consulted_shield']) AS k
   WHERE NOT (j->'coverage' ? k);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'A2 FAILED: 0230 coverage key(s) lost: %', missing; END IF;

  SELECT string_agg(k, ', ') INTO missing FROM unnest(ARRAY[
    'incapable_charge_bookings','unverifiable_charge_bookings','peak_concurrent_kw',
    'site_cap_kw','pct_of_cap','cap_breached','booking_overlaps','overlaps_note']) AS k
   WHERE NOT (j->'safety' ? k);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'A2 FAILED: 0230 safety key(s) lost: %', missing; END IF;

  SELECT string_agg(k, ', ') INTO missing FROM unnest(ARRAY[
    'decisions','sdrs','events','vehicles_booked','bookings_by_purpose']) AS k
   WHERE NOT (j->'throughput' ? k);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'A2 FAILED: 0230 throughput key(s) lost: %', missing; END IF;

  SELECT string_agg(k, ', ') INTO missing FROM unnest(ARRAY[
    'energy_delivered_kwh','charge_sessions','sessions_still_open','vehicles_served',
    'service_points_used','turns_per_point','service_point_hours','kwh_per_point_hour',
    'soc_points_added','mean_soc_gain','soc_measured_sessions','sim_hours']) AS k
   WHERE NOT (j->'outcome' ? k);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'A2 FAILED: outcome key(s) absent: %', missing; END IF;
END $A2$;

-- ---------------------------------------------------------------------------
-- A3  THE PRESERVED VALUES ARE UNCHANGED, not merely present. peak_concurrent_kw
--     is recomputed through a widened sess CTE; if adding columns perturbed the
--     sweep, this catches it. 463.8 kW is the value 0230 reported for this run
--     and is independently reproduced by a session-only sweep written from
--     scratch (db/checks/0149).
-- ---------------------------------------------------------------------------
DO $A3$
DECLARE j jsonb;
BEGIN
  j := public.ottoq_ab_score_run('3f4b9690-1886-4b33-a413-decb13dcf84d'::uuid);
  IF j IS NULL THEN RAISE EXCEPTION 'A3 FAILED: the 0230 reference run no longer scores'; END IF;
  IF (j->'safety'->>'peak_concurrent_kw')::numeric <> 463.8 THEN
    RAISE EXCEPTION 'A3 FAILED: peak_concurrent_kw is %, expected 463.8 -- widening sess moved the sweep',
                    j->'safety'->>'peak_concurrent_kw';
  END IF;
  IF (j->'coverage'->>'bookings_total')::int <> 879 THEN
    RAISE EXCEPTION 'A3 FAILED: bookings_total is %, expected 879', j->'coverage'->>'bookings_total';
  END IF;
  IF (j->'outcome'->>'charge_sessions')::int <> (j->'coverage'->>'charge_sessions')::int THEN
    RAISE EXCEPTION 'A3 FAILED: the two charge_sessions counts disagree (% vs %)',
                    j->'outcome'->>'charge_sessions', j->'coverage'->>'charge_sessions';
  END IF;
END $A3$;

-- ---------------------------------------------------------------------------
-- A4  A nonexistent run still returns NULL rather than a zero-filled object.
--     0230's A2; restated because a superset is where that property gets lost.
-- ---------------------------------------------------------------------------
DO $A4$
BEGIN
  IF public.ottoq_ab_score_run('00000000-0000-0000-0000-000000000000'::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'A4 FAILED: a nonexistent run scored non-NULL';
  END IF;
END $A4$;

-- ---------------------------------------------------------------------------
-- LINEAGE.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'a_comparative_score_may_read_only_what_every_arm_writes',
  now(),
  false,
  'G32 / db/checks/0149. ottoq_ab_score_run (0230, same day) reads eleven of its '
  'sixteen fields from substrate only the otto_q decide path writes -- bookings, '
  'decisions, SDRs, rule evaluations -- so a fifo or greedy arm would score as '
  'having done nothing while charging vehicles through ocpp_sessions the whole '
  'time. Adds an `outcome` block computed only from ocpp_sessions and the run '
  'clock, and a `comparability` block naming per-block validity. Strict superset: '
  'no 0230 key removed or changed, asserted field-by-field in A2 and by value in '
  'A3. forces_recert FALSE: the function is STABLE, read-only, called by nothing '
  'in the decide path and an input to no verdict atom. FALSIFIER, unrun until a '
  'baseline arm exists: score a fifo arm and an otto_q arm on one seed; if any '
  'outcome field reads zero for fifo, the block is still reading otto_q substrate '
  'and this migration failed.'
);

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 22:29:53 UTC (5:29 PM CT). All three preconditions and
-- all four assertions passed on the first attempt.
--
--   functiondef md5  a472af5fccb93334ac549d1e4da77bef
--                 -> 21d02c4daa7f0cd5040387265652e4ea
--   anchors A/B: 1 occurrence each, as asserted
--   A2: six top-level blocks present; all 6 coverage, 8 safety, 5 throughput
--       keys 0230 emitted still present; all 12 outcome keys present
--   A3: peak_concurrent_kw 463.8 unchanged, bookings_total 879 unchanged,
--       the two charge_sessions counts agree
--   A4: a nonexistent run still scores NULL
--
-- THE FLOOR DID NOT MOVE: 2026-09-07 21:36:53.363037 before and after, so the
-- forces_recert FALSE classification was actually read rather than assumed --
-- the property G28 showed was broken for four days until 0226.
--
-- WHAT WAS APPLIED, stated precisely rather than as "byte-identical to this
-- file". The applied text is this file's EXECUTABLE STATEMENTS -- the five DO
-- blocks and the lineage INSERT -- verbatim. The 67-line comment header above
-- and this footer are repo documentation and were not submitted, because
-- retyping 57 lines of prose into the apply call is exactly the transcription
-- risk the anchored-substitution technique exists to avoid, and prose has no
-- effect on the database. 0229's footer claimed byte-identity; this one does
-- not, and says why.
--
-- THE DRY RUN, done before submitting and worth more than any assertion in the
-- file. The identical substitution was compiled under the scratch name
-- zz_dryrun_0231_score and its output diffed against the live function on run
-- 3f4b9690, block by block:
--
--   run          jsonb-equal
--   coverage     jsonb-equal
--   safety       jsonb-equal
--   throughput   jsonb-equal
--   outcome      present         comparability  present
--   nonexistent run -> NULL      preserved
--
-- then dropped (0 rows remaining in pg_proc). "Strict superset" is therefore
-- measured, not argued.
--
-- FIRST REAL OUTCOME BLOCK, run 3f4b9690 (busy_day / 171717 / 12t / otto_q):
--
--   energy_delivered_kwh   1277.99      service_point_hours   88.00
--   charge_sessions        83           kwh_per_point_hour    14.5
--   vehicles_served        83           soc_points_added      1149
--   service_points_used    40           mean_soc_gain         20.16
--   turns_per_point        2.08         soc_measured_sessions 57
--   sessions_still_open    0            sim_hours             6.00
--
-- ONE DATA-QUALITY FINDING FALLS OUT OF IT, recorded because the field was
-- designed to surface exactly this: soc_measured_sessions is 57 of 83. Twenty-
-- six sessions (31%) carry no soc_start or no soc_end, so mean_soc_gain 20.16
-- is an average over 57 sessions, not 83, and soc_points_added 1149 undercounts
-- by whatever those 26 delivered. The number is honest because it ships its own
-- denominator. Why a third of sessions lack SoC bookends is NOT established
-- here and is not guessed at. Filed as G33.
--
-- WHAT IS STILL NOT PROVEN, and is the whole point of the next piece of work:
-- that the outcome block reads non-zero for a baseline arm. It cannot be proven
-- until one exists. **No comparative number until it does.**
