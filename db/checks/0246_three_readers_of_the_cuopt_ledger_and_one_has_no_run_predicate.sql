-- ============================================================================
-- 0246 — THREE FUNCTIONS READ THE cuOpt LEDGER. TWO SCOPE THE READ TO A RUN.
--        ONE HAS NO PREDICATE AT ALL.
-- ============================================================================
-- Measured 2026-09-14 20:36 UTC, read-only, round 44 flagship lane in flight.
--
-- WHY THIS AUDIT EXISTS, AND WHY IT COMES BEFORE THE FIX. CLAUDE.md rule 6
-- carries db/checks/0231's finding -- cuopt_invocation_log is registered
-- class='engine' and ottoq_purge_prior_runs has been deleting from it -- and
-- names the fix: reclassify it to 'evidence'. It then attaches a warning that is
-- the whole reason for this file: "prior-run rows surviving would expose any
-- unscoped cuOpt reader (the 0145/0146 class), and that audit happens there
-- anyway."
--
-- That warning is exactly right and it inverts the usual order. TODAY the purge
-- hides the defect: an unscoped reader sums a table that has just been emptied
-- of prior runs, so it reads low and looks plausible. Reclassify first and the
-- same reader silently starts summing every run that ever executed -- the fix
-- would CREATE the wrong number rather than reveal it.
--
-- HOW THE READERS WERE FOUND, and the method rule that decided it (0235: read
-- the assignment before measuring the value). Six functions mention the table.
-- A mention is not a read and a body that mentions sim_run_id somewhere is not
-- a body that SCOPES THIS READ -- workload_harness_metrics is 22,475 characters
-- long. So the predicate beside each read was inspected, not inferred:
--
--   public.workload_harness_metrics
--     FROM cuopt_invocation_log cl
--      WHERE cl.stage='edge' AND cl.sim_run_id = p_sim_run_id        SCOPED
--
--   twin.ottoq_grid_assert
--     FROM public.cuopt_invocation_log WHERE sim_run_id = p_run      SCOPED
--
--   public.ottoq_intelligence_status
--     WITH cuopt AS (
--       SELECT count(*) AS rows_all,
--              count(*) FILTER (WHERE http_status IS NOT NULL) AS answered
--         FROM public.cuopt_invocation_log
--     )                                                            UNSCOPED
--
-- The other three are writers or a trigger, not readers: cuopt_log_gate and
-- ottoq_cron_tick INSERT, cuopt_invocation_log_append_only is the 94-character
-- trigger body enforcing append-only.
--
-- THE FINDING, STATED AT ITS ACTUAL SIZE. ottoq_intelligence_status is a status
-- surface, and a status surface arguably WANTS a lifetime figure -- so this is
-- not automatically a scoping bug the way 0145 and 0146 were. What it is, for
-- certain, is the one place in the database that publishes a cuOpt count, and it
-- publishes `rows_all` -- the number CLAUDE.md rule 6 forbids quoting, because a
-- row is not an invocation:
--
--                                  rows      http_status IS NOT NULL
--   db/checks/0220, ~12:00 UTC   20,533                           16
--   this file,       20:36 UTC   21,756                           16
--
-- 1,223 rows in an afternoon, essentially all stage='sql_gate' -- the gate
-- recording that it declined to call anything -- and the count of actual calls
-- to the NVIDIA endpoint did not move, and has not since 2026-08-30.
--
-- Its own neighbouring comment says "A5 asserts the expensive ledger is not in
-- this read path; the live aggregate is an 11-second, 1.5 GB scan and this
-- function is meant to be called casually." A count(*) over the whole of
-- cuopt_invocation_log IS in this read path. That claim wants re-checking on its
-- own terms; it is not settled here.
--
-- WHAT THIS MEANS FOR THE cuOpt CUT SEQUENCE. The reclassification needs two
-- things done first, and neither is in migration 0327 (which corrects only the
-- table's false comment and changes no row and no class):
--
--   1. ottoq_intelligence_status decides what it publishes -- the answered
--      count, a run-scoped count, or a lifetime count that SAYS it is rows and
--      not invocations. Any of the three is defensible; publishing `rows_all`
--      under a cuOpt heading is not.
--
--   2. A retention rule replaces the purge. Unpinned from ottoq_purge_prior_runs
--      with nothing in its place, ~1,200 rows an afternoon is roughly 800k rows
--      a month of the least informative rows in the database. The nightly
--      ottoq_retention_purge_runs allowlist holds 7 tables and NOT this one, so
--      the rule has to be written, not pointed at. Shape: age out stage='sql_gate'
--      rows, keep every row carrying an http_status.
-- ============================================================================

-- 1. The three readers and the predicate beside each read. Read the substring
--    around the reference -- do NOT conclude from prosrc ~ 'sim_run_id' that a
--    22 KB function scopes THIS read.
SELECT n.nspname||'.'||p.proname AS fn,
       (p.prosrc ~* 'insert\s+into\s+(public\.)?cuopt_invocation_log') AS writes,
       (p.prosrc ~* '(from|join)\s+(public\.)?cuopt_invocation_log')   AS reads,
       length(p.prosrc)                                               AS src_len,
       substring(p.prosrc from greatest(1, position('cuopt_invocation_log' in p.prosrc) - 200)
                          for 420)                                    AS around_the_reference
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq')
   AND p.prosrc ~* 'cuopt_invocation_log'
 ORDER BY 1;

-- 2. The gap the status surface publishes: rows against calls.
SELECT count(*)                                              AS rows_all,
       count(*) FILTER (WHERE stage = 'sql_gate')            AS gate_rows,
       count(*) FILTER (WHERE stage = 'edge')                AS edge_rows,
       count(*) FILTER (WHERE http_status IS NOT NULL)       AS reached_nvidia,
       min(called_at)                                        AS earliest_surviving,
       max(called_at) FILTER (WHERE http_status IS NOT NULL) AS last_real_call
  FROM public.cuopt_invocation_log;

-- 3. The deletion, and the independent witness that it is deletion rather than
--    a table that simply started late.
SELECT (SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='cuopt_invocation_log') AS ins,
       (SELECT n_tup_del FROM pg_stat_user_tables WHERE relname='cuopt_invocation_log') AS del,
       (SELECT min(called_at)::date FROM public.cuopt_invocation_log)                   AS cuopt_log_earliest,
       (SELECT min(fired_at)::date  FROM public.ottoq_cuopt_fire_log)                   AS fire_log_earliest,
       (SELECT class FROM public.ottoq_run_scope_registry
         WHERE table_schema='public' AND table_name='cuopt_invocation_log'
           AND column_name='sim_run_id')                                                AS registry_class;

-- 4. The purge selects by class and never by name -- the basis of the whole
--    finding, asserted from the live source rather than from the file.
SELECT p.oid::regprocedure::text                    AS purge_fn,
       (p.prosrc ~* 'cuopt')                        AS mentions_cuopt_expect_false,
       (p.prosrc ~* 'ottoq_run_scope_registry')     AS reads_registry_expect_true
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_purge_prior_runs';
