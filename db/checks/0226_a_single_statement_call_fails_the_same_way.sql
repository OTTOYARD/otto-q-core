-- 0226  A SINGLE-STATEMENT CALL FAILS THE SAME WAY
--
-- The probe that refuted migration 0293's diagnosis, and the corrected one.
-- Read with the APPLIED banner at the foot of
-- db/migrations/0293_the_nightly_run_purge_has_never_once_run.sql.
--
-- ===========================================================================
-- A. THE DEFECT. cron job 625, ottoq-run-purge-nightly, has NEVER successfully
-- run. Its first automated firing, 2026-09-14 09:00 UTC, failed in 0.26 s:
--
--   ERROR:  invalid transaction termination
--   CONTEXT:  PL/pgSQL function ottoq_retention_purge_runs(...) line 152 at COMMIT
--
-- 939 runs carry purged_at, exactly the figure recorded when the job was
-- scheduled, and 37 eligible runs are untouched.
--
SELECT 'A. every firing of job 625, ever' AS section;
SELECT jobid, status, start_time,
       round(EXTRACT(EPOCH FROM (end_time - start_time))::numeric, 3) AS seconds,
       left(COALESCE(return_message,''), 100) AS msg
  FROM cron.job_run_details WHERE jobid = 625 ORDER BY start_time;

-- ===========================================================================
-- B. THE FIRST DIAGNOSIS, AND WHY IT WAS WRONG.
--
-- 0293 compared job 625 against job 11 and found:
--
--   jobid  stmts  result
--   11         1  succeeded, 71 s
--   625        2  failed at the first COMMIT
--
-- and concluded the two-statement command was the cause, because a
-- multi-statement submission runs in an implicit transaction block and a
-- procedure cannot commit inside one. That is a true statement about
-- PostgreSQL. It is not what was happening here.
--
-- THE TWO JOBS DIFFERED IN TWO WAYS: statement count AND the procedure called.
-- 0293's own header names the confound -- "they are different procedures" --
-- and then reasons past it. Naming a confound is not controlling for it.
--
-- ===========================================================================
-- C. THE PROBE THAT SETTLED IT. Scheduled immediately after 0293 applied, to
-- verify the fix. It did the opposite, which is what a probe is for.
--
--   cron.schedule('ottoq-0293-probe', '* * * * *',
--     'CALL public.ottoq_retention_purge_runs(60, 2000, ''999 days'', false);')
--
-- ONE statement. No SET. A 999-day keep window, so ZERO rows match (verified
-- beforehand: the oldest unpurged run is 2026-06-20, about three months old),
-- which means it deletes nothing while still reaching the COMMIT -- because the
-- loop's COMMIT sits BEFORE its `EXIT WHEN v_n = 0`.
--
-- It fired twice and failed both times with the same error at the same line.
-- Unscheduled immediately afterwards (jobid 626 no longer exists).
--
-- ===========================================================================
-- D. THE REAL CAUSE, located by line number.
--
--   line 111   FOR v_reg IN
--   line 112     SELECT g.table_name, g.column_name FROM ottoq_run_scope_registry ...
--   line 118   LOOP
--   line 119     LOOP
--   line 152       COMMIT;          <-- inside a query-driven FOR loop
--   line 154     END LOOP;
--   line 155   END LOOP;
--   line 167   COMMIT;              <-- outside both loops; this one is fine
--
-- PL/pgSQL runs `FOR rec IN <query> LOOP` over an internal cursor, and a
-- procedure may not commit while one is open.
--
-- THE CORRECTED A/B, differing in the right variable:
--
SELECT 'D. the corrected A/B' AS section;
SELECT p.oid::regprocedure::text AS procedure,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'FOR\s+\w+\s+IN', 'g')) AS for_in_query_loops,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'COMMIT', 'g'))         AS commits
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_retention_purge_runs','ottoq_retention_purge_worker')
 ORDER BY 1;
--
-- The sibling that succeeds nightly has NO query-driven loop and eight COMMITs.
--
-- AND THE OTHER CLASSIC CAUSE IS RULED OUT, not assumed away: 2D000 also fires
-- when a COMMIT sits inside a block with an EXCEPTION handler. It does not here.
--
SELECT 'D2. no exception handler encloses line 152' AS section;
SELECT n, ln FROM (
  SELECT (row_number() OVER ())::int AS n, l AS ln
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace,
         LATERAL regexp_split_to_table(p.prosrc, E'\n') l
   WHERE ns.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs') t
 WHERE ln ~ 'EXCEPTION|^\s*BEGIN|FOR .* IN|LOOP|COMMIT'
 ORDER BY n;
-- Expect: one BEGIN (line 14, the procedure body) and three RAISE EXCEPTION
-- (lines 26, 37, 49). No handler, and none of them encloses the COMMIT.
--
-- ===========================================================================
-- E. WHY THIS COULD NOT BE CAUGHT WITHOUT A CRON FIRING.
--
-- The Supabase management SQL channel cannot execute a COMMIT-ing procedure at
-- all: it wraps every submission in a transaction, so a bare CALL raises the
-- same 2D000 for an unrelated reason and tells you nothing. It also pools
-- connections, so pg_temp objects do not survive between statements and a
-- scratch procedure cannot be built up and then called. Every attempt to test
-- this from that channel is a false negative.
--
-- The only instrument that answers the question is a real pg_cron firing, and
-- a transient job with a keep window that matches nothing is a safe one. That
-- is the technique to reuse; it cost two minutes and one wrong belief.
--
-- ===========================================================================
-- F. THE REMEDY, specified and NOT applied here (filed as G63).
--
-- Hoist the registry query out of the loop so no cursor is open across the
-- COMMIT, and iterate by index:
--
--   SELECT array_agg(g.table_name ORDER BY <the existing ORDER BY>),
--          array_agg(g.column_name ORDER BY <the same>)
--     INTO v_tabs, v_cols
--     FROM public.ottoq_run_scope_registry g
--     JOIN public.ottoq_retention_engine_allowlist a ON a.table_name = g.table_name
--    WHERE g.class = 'engine' AND g.table_schema = 'public'
--      AND to_regclass('public.' || g.table_name) IS NOT NULL;
--
--   FOR i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP   -- integer loop,
--     ...                                                      -- no cursor
--
-- The ORDER BY must be preserved exactly -- it purges the largest tables first,
-- which is what makes the time budget spend itself where it matters.
--
-- NOT DONE HERE deliberately: this procedure DELETEs rows, and rewriting it
-- belongs in its own reviewed window rather than the tail of another change.
--
-- UNTIL THEN, THE JOB FAILS NIGHTLY AT 09:00 UTC. 0293 made its command a
-- single statement and moved the timeout onto the procedure -- both correct in
-- themselves, neither the cause, and neither a fix.

-- ===========================================================================
-- G. CORRECTION, 09:55 UTC. SECTIONS D AND F WERE BOTH INCOMPLETE, AND
--    SECTION C's SAFETY CLAIM WAS WRONG.
--
-- D said the cursor loop was "the real cause". It was A real cause, not the
-- only one. After 0294 removed it the job still failed -- at line 166 rather
-- than 152, which is THE SAME in-loop COMMIT displaced by fourteen lines of new
-- comment. There were two independent causes:
--
--   1. COMMIT inside the query-driven FOR loop.     Original. 0294 removed it.
--   2. A SET clause on the procedure.               ADDED BY 0293. A PostgreSQL
--      procedure carrying one may not execute transaction control at all.
--
-- Each alone was sufficient, so fixing the first while introducing the second
-- left the symptom unchanged and made a correct fix look like a failed one.
--
-- RESET statement_timeout at 09:49; the probe SUCCEEDED at 09:50 in 62 seconds.
-- 0295 captures that.
--
-- The control arm carried the answer the whole time:
--
SELECT 'G. proconfig is the discriminator' AS section;
SELECT p.oid::regprocedure::text AS procedure,
       COALESCE(array_to_string(p.proconfig,' | '), '(none)') AS set_clause
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_retention_purge_runs','ottoq_retention_purge_worker')
 ORDER BY 1;
-- All three must read (none). The sibling that has always worked never had one.
--
-- ---------------------------------------------------------------------------
-- AND SECTION C's PROBE WAS NOT THE NO-OP IT CLAIMS. IT PURGED 20 RUNS.
--
-- C asserts a 999-day keep window "deletes nothing" because zero rows are that
-- old. Zero rows ARE that old. The procedure never uses the parameter:
--
--   SELECT keep_interval INTO v_keep
--     FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled;
--   v_keep := COALESCE(v_keep, p_keep);        -- p_keep is the FALLBACK
--
-- ottoq_retention_policy has an enabled engine_rows row of 48:00:00, so every
-- probe firing ran the REAL retention window. The two that succeeded purged 20
-- runs between them.
--
-- Measured afterwards rather than assumed: 20 runs, all started 2026-09-12
-- 04:05-06:20, youngest 2 days 3.5 h; 20 of 20 had a row in ottoq_run_archives,
-- 0 were status='running', 0 were run_by='production_live'; and 91139ad8,
-- 5712f828 and 36e5cc68 -- the runs this session's G60 evidence rests on -- are
-- untouched. So it did exactly what the nightly job is designed to do, on
-- exactly its intended population, about ten hours early, with every guard
-- holding. The outcome is fine. The claim was not, and the difference between
-- those two is eligibility, which is luck rather than care.
--
-- THE RULE: NEVER CALL THIS PROCEDURE TO TEST IT. Its keep window comes from
-- ottoq_retention_policy, not from the caller, so there is no safe
-- parameterisation -- p_keep is inert whenever that table has an enabled row. A
-- future probe must disable the policy row inside a rolled-back transaction, or
-- run against a scratch database, or not run.
--
SELECT 'G2. the parameter the probe thought it was setting' AS section;
SELECT (SELECT keep_interval::text FROM public.ottoq_retention_policy
         WHERE policy_key='engine_rows' AND enabled)          AS policy_wins,
       '999 days'                                             AS what_the_caller_passed,
       (SELECT count(*) FROM public.ottoq_sim_runs WHERE purged_at IS NOT NULL) AS purged_total;
