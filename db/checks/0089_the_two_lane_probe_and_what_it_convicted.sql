-- =====================================================================
-- 0089  The two-lane probe, and what it convicted
-- =====================================================================
-- 0177 scoped the cold-start guard to the run's own depot and was
-- described, honestly at the time, as unblocking the two-lane cadence.
-- This is the probe that tested that claim. It FAILED, and the failure
-- is worth more than the pass would have been.
--
-- §1  THE PROBE, AND THE GUARD THAT ALMOST WASN'T
-- ---------------------------------------------------------------------
-- Design: fire a flagship pair; while it is DEMONSTRABLY mid-flight, run
-- a grid-fixture smoke against a different depot. Solo the smoke takes
-- ~10 s. Success = both complete, each reproduces its own canon, neither
-- blocks the other.
--
-- "Demonstrably" mattered. A probe that ran the two lanes SEQUENTIALLY
-- and reported them as concurrent would be worthless - the same defect
-- class as 0175, a check reporting about a world it did not run. So the
-- probe blocks until it can SEE the flagship active, and refuses rather
-- than proceed:
--
--   WHILE v_waited < 35 LOOP
--     IF EXISTS (SELECT 1 FROM pg_stat_activity WHERE ... state='active')
--       THEN RETURN; END IF;
--     PERFORM pg_sleep(1); v_waited := v_waited + 1;
--   END LOOP;
--   RAISE EXCEPTION 'flagship lane never started - probe would not be concurrent';
--
-- It refused. And it was WRONG to: the flagship had started on time
-- (cron lane1 fired 17:02:00, confirmed running at 17:02:42).
--
-- WHY THE GUARD WAS BLIND. pg_stat_activity's per-backend information is
-- refreshed ONCE PER TRANSACTION - documented behaviour, not a bug. All
-- 35 one-second samples inside that single DO block read the same frozen
-- snapshot taken before the flagship started. The remedy is
-- pg_stat_clear_snapshot() between samples, or sampling from separate
-- transactions.
--
-- Stated at the strength the evidence supports: this is the documented
-- behaviour and it exactly matches what was observed (35 blind samples
-- while the backend was provably active). It was not isolated in a
-- controlled experiment. The next probe uses pg_stat_clear_snapshot()
-- so the guard is correct by construction either way.
--
-- The guard still did its job in the direction that matters: it refused
-- rather than silently reporting a sequential run as a concurrent one.
--
-- §2  WHAT THE PROBE FOUND WHEN IT DID RUN
-- ---------------------------------------------------------------------
-- Run against the live flagship pair, the fixture smoke went past 60 s
-- and was killed by the client. Not slowness:
--
--   pid 2932935  144 s  IO/DataFileRead              <- the flagship pair
--   pid 2932980   75 s  Lock/transactionid  by [2932935]  <- fixture lane
--   pid 2933042    9 s  Lock/transactionid  by [2932935]  <- a demo run
--
--   pid 2932980  tuple ExclusiveLock  vehicle_need_profile  page 32 tuple 2
--   pid 2932980  transactionid ShareLock  xid 9596158  NOT GRANTED
--
-- The fixture lane held a tuple lock on vehicle_need_profile and waited
-- for the flagship pair's transaction to commit.
--
-- READ THE THIRD LINE AGAIN. ottoq_start_demo_run - nobody's
-- certification, an ordinary demo path - was blocked by the same
-- transaction. A certification pair currently stalls the demo backend
-- for its entire ~11-minute duration. That is a production-facing
-- consequence of a testing habit, and it was invisible until two lanes
-- were run on purpose.
SELECT a.pid, a.state, a.wait_event_type, a.wait_event,
       cardinality(pg_blocking_pids(a.pid)) AS blocked_by_n,
       pg_blocking_pids(a.pid) AS blockers,
       left(regexp_replace(a.query,'\s+',' ','g'), 80) AS q
  FROM pg_stat_activity a
 WHERE a.pid <> pg_backend_pid() AND a.backend_type='client backend' AND a.state='active'
 ORDER BY a.query_start;

-- §3  THE CAUSE — 0180
-- ---------------------------------------------------------------------
-- ottoq_run_boot_draw section 1c (the 0109 watermark sweep):
--
--   UPDATE public.vehicle_need_profile p
--      SET wear_km_applied = NULL, wear_km_applied_run = NULL
--    WHERE p.wear_km_applied_run IS DISTINCT FROM p_sim_run_id
--      AND (p.wear_km_applied IS NOT NULL OR p.wear_km_applied_run IS NOT NULL);
--
-- NO DEPOT FILTER, NO VEHICLE FILTER. Every other write in that function
-- is scoped `WHERE v.home_depot_id = v_run.depot_id` - section 1's fleet
-- CTE, 1d's fleet CTE, 1e, 1f. Only this one sweeps the whole table.
--
-- The intent is correct and kept: a watermark the anchor could not reach
-- belongs to a PREVIOUS run and must be cleared so the start state is a
-- function of the seed alone. Reaching into other depots' rows to
-- achieve that is not correct - those rows are not this run's history,
-- and touching them takes a lock every other depot's run queues behind.
--
-- FIFTH INSTANCE OF ONE CLASS, AND THE FIRST THAT IS A WRITE:
--   0145  the pre-flight validator read every run's calendar
--   0053  the sweep for that class
--   0054  the energy orchestrator summed every run's and depot's sessions
--   0177  the cold-start guard counted every depot's vehicles
--   0180  the watermark sweep CLEARED every depot's rows
--
-- The first four were unscoped READS: they produced wrong answers. An
-- unscoped WRITE does something worse - it serialises every concurrent
-- run in the database behind one transaction. 0177 was necessary and NOT
-- SUFFICIENT, and there was no way to learn that except by spending the
-- probe.
SELECT position('0180: ONLY THIS DEPOT' in pg_get_functiondef(p.oid)) > 0 AS scoped_by_0180
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_run_boot_draw';

-- §4  WHAT THE RE-RUN MUST SHOW
-- ---------------------------------------------------------------------
-- After 0180 and its recertification round, the probe is re-run. Success
-- is NOT "the smoke finished quickly" - wall time is a proxy and proxies
-- are how the first version of a check goes wrong. Success is:
--
--   * both lanes complete
--   * each reproduces its OWN canon (flagship vs grid fixture)
--   * pg_blocking_pids() is EMPTY for both, sampled with
--     pg_stat_clear_snapshot() between reads
--
-- The third condition is the actual claim. A fast run that happened not
-- to collide proves nothing about isolation.
SELECT 'probe re-run criteria' AS what,
       'both complete + each reproduces its own canon + pg_blocking_pids empty for both' AS pass_condition;
