-- ---------------------------------------------------------------------------
-- 0200 — THE PURGE THAT IS SCHEDULED IS NOT THE PURGE G23 MEANS, AND THE ONE
-- G23 MEANS HAS BEEN REFUSING TO RUN SINCE 0260.
--
-- Found 2026-09-13 14:0x-14:1x UTC, immediately after 0266 applied, while
-- setting up the "ONE observed purge pass" that db/checks/0196 makes the
-- precondition for round 42. Two facts, either of which alone would have made
-- that pass worthless.
-- ---------------------------------------------------------------------------

-- 1. THERE ARE TWO PURGES AND ONLY ONE IS SCHEDULED.
SELECT jobid, jobname, schedule, active, command FROM cron.job
 WHERE command ILIKE '%purge%' OR jobname ILIKE '%purge%' OR jobname ILIKE '%retention%';
-- MEASURED: exactly one row.
--   jobid 11 | ottoq-retention-nightly | '0 8 * * *' | active
--   CALL public.ottoq_retention_purge_worker(90, 2000, '48 hours',
--        ARRAY['ottoq_events','ottoq_rule_evaluations','ottoq_incident_reports']);
--
-- ottoq_retention_purge_worker(int,int,interval,text[]) handles EXACTLY THREE
-- tables, each behind its own `IF '<name>' = ANY (p_tables) THEN` guard, read
-- from its body: ottoq_events, ottoq_rule_evaluations, ottoq_incident_reports.
-- It never touches ottoq_itinerary_legs, ottoq_stall_bookings,
-- ottoq_visit_needs or ottoq_vehicle_dispatches.
--
-- NONE OF ITS THREE TABLES APPEARS IN endst. The boot/end-state fingerprint has
-- seven top-level keys -- visit_needs, bookings, legs, dispatches, chargers,
-- calibration, world -- and events, rule evaluations and incident reports are in
-- none of them. So waiting for 08:00 UTC and calling THAT the observed pass
-- would have moved neither the residue column nor any engine column, and 0196's
-- P1-P3 would have been "judged" against an event that cannot touch them.
-- That is the vacuous-assertion failure at round scale: a pass that reads green
-- both before and after, measuring nothing.
--
-- The purge 0196 means is public.ottoq_retention_purge_runs(int,int,interval,bool)
-- -- the RUN-SCOPED one, which walks ottoq_run_scope_registry class='engine'
-- intersected with ottoq_retention_engine_allowlist. IT IS NOT ON CRON AT ALL.

-- 2. AND IT REFUSES TO RUN. Measured by calling it in dry-run mode:
--   CALL public.ottoq_retention_purge_runs(5, 100, '48 hours', true);
--   ERROR: P0001: purge refused: 1 blocking run-scope defect(s).
SELECT * FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
-- MEASURED: one row.
--   public | ottoq_proposer_fire_log | tick_seq
--          | 'engine/stamp table has no FK to ottoq_sim_runs' | block
-- Root cause and fix: db/migrations/0267. 0260 created the fire log, registered
-- tick_seq class='stamp', and gave the table no foreign keys at all.
--
-- NOTE THE SEVERITY VALUE. It is 'block', not 'blocking'. I first checked this
-- with `WHERE severity='blocking'`, got 0, and reported the window clear to
-- purge. The purge's own guard is what corrected me. That was the THIRD time in
-- one afternoon I invented a vocabulary instead of reading it -- after the
-- migration-version sentinels and the missing Section C in db/checks/0199 -- and
-- this one was load-bearing: it produced a false "clean".

-- 3. WHAT THE PASS WILL ACTUALLY DO, measured before running it, so the
--    prediction is on the record rather than fitted afterwards.
WITH keep AS (
  SELECT COALESCE((SELECT keep_interval FROM public.ottoq_retention_policy
                    WHERE policy_key='engine_rows' AND enabled), interval '48 hours') AS k
), doomed AS (
  SELECT sr.sim_run_id FROM public.ottoq_sim_runs sr CROSS JOIN keep
   WHERE sr.status <> 'running' AND COALESCE(sr.run_by,'') <> 'production_live'
     AND sr.started_at < now() - keep.k
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id)
)
SELECT (SELECT count(*) FROM doomed) AS doomed_runs,
       (SELECT count(*) FROM public.ottoq_itinerary_legs l JOIN public.vehicles v ON v.id = l.vehicle_id
         WHERE v.home_depot_id='11111111-1111-1111-1111-111111111111'::uuid
           AND l.status IN ('planned','active') AND l.sim_run_id IS NOT NULL
           AND l.sim_run_id IN (SELECT sim_run_id FROM doomed)) AS flagship_foreign_live_legs_doomed;
-- MEASURED 2026-09-13 14:06 UTC, keep_interval 48:00:00:
--   939 doomed runs; 7,300,205 rows across the seven allow-listed tables:
--     ottoq_bay_binding_witness 1,494,446   ottoq_variability_cards 1,443,556
--     ottoq_rule_evaluations    1,257,969   ottoq_events            1,095,187
--     ottoq_stall_bookings        915,817   ottoq_itinerary_legs      591,871
--     ottoq_comms_messages        517,359
--   FLAGSHIP FOREIGN LIVE LEGS: 9, ALL owned by doomed runs, ALL from ONE run.
--   Those are the same nine db/checks/0193 named -- run 9291ec6d's pre-janitor
--   backlog. The purge deletes them, endst.legs.fgn moves, and 0266's residue
--   column is what reports it. The test is live, not vacuous.
--
--   ottoq_sim_runs IS NOT IN THE ALLOWLIST. The purge deletes a doomed run's
--   CHILD rows and always leaves the run header -- so validation_notes survives,
--   and neither ottoq_cert_matrix nor ottoq_cert_residue loses a single pair.
--   Confirmed against the allowlist's seven tables; the run table is not among
--   them. Nor are ottoq_visit_needs or ottoq_vehicle_dispatches, so of endst's
--   four row sections the purge can move only `legs` and `bookings`.

-- 4. AND THE TABLE ORDER MATTERS FOR PLANNING THE PASS.
--    The FOR loop is
--      ORDER BY pg_total_relation_size(...) DESC, g.table_name
--    so it walks rule_evaluations (5657 MB), events (3441 MB), stall_bookings
--    (1168 MB), variability_cards (789 MB), comms_messages (670 MB),
--    bay_binding_witness (431 MB), and ottoq_itinerary_legs (346 MB) LAST.
--    A single time-budgeted call therefore CANNOT reach the nine legs. "One
--    observed pass" for G23's purposes means running it to completion, or until
--    legs is reached -- not one CALL. Recorded because a single 90-second call
--    would have deleted a great many rows, changed nothing the residue column
--    can see, and looked like a completed pass.

-- ---------------------------------------------------------------------------
-- THE STANDING FINDING: A GUARD WHOSE ONLY READER IS A PROCEDURE NOBODY RUNS
-- IS A GUARD NOBODY READS.
--
-- ottoq_check_run_scope_registry() correctly detected 0260's missing FK from the
-- moment 0260 applied on 2026-09-12. Nothing surfaced it for a day, because its
-- only acting caller is ottoq_retention_purge_runs, and that has not
-- successfully run since. tests/test_migration_hygiene.py cannot see it (it is
-- schema shape, not file content); scripts/check-drift.sql cannot see it (same
-- reason); CI never connects to a database at all.
--
-- This is the concrete argument for G12 ("CI runs the SQL"), and it is now the
-- second distinct defect this week found only by executing something rather than
-- reading it. The cheap interim measure, which costs one query in
-- scripts/round-report.sql: print
--     SELECT * FROM public.ottoq_check_run_scope_registry() WHERE severity='block';
-- in every round report, so a blocking defect surfaces at the next round rather
-- than at the next purge attempt.
-- ---------------------------------------------------------------------------
