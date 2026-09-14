-- db/checks/0230
-- G23 / G63: THE PURGE FINALLY RAN UNDER pg_cron, AND THE FLAT COUNTER IS THE
-- CORRECT ANSWER -- WHICH TOOK MORE WORK TO ESTABLISH THAN THE FIX DID
--
-- Tasks #87 and #127, closed 2026-09-14.
--
-- ===========================================================================
-- A. THE TRAP I NEARLY WALKED INTO
--
-- At 12:57 UTC I read cron.job_run_details for job 625 and found:
--
--   runid 184451, start 2026-09-14 09:00:00.191+00, status FAILED
--   ERROR:  invalid transaction termination
--   CONTEXT: PL/pgSQL function ottoq_retention_purge_runs(...) line 152 at COMMIT
--
-- which reads as "the fix did not work." It is not. THE FIX WAS APPLIED AFTER
-- THE FIRING:
--
--   job 625 fired   2026-09-14 09:00:00.19 UTC
--   0294 applied    2026-09-14 09:45:51    (+45 min)
--   0295 applied    2026-09-14 09:55:29    (+55 min)
--
-- The 09:00 run executed the OLD definition. Line 152 of the CURRENT source is
-- a blank line; the live procedure has no COMMIT there at all. A failure
-- record is a statement about the code that was live WHEN IT RAN, and nothing
-- in cron.job_run_details says which version that was. Same class as every
-- other instrument defect in this build: it answers a slightly different
-- question than the one being asked.
--
-- ===========================================================================
-- B. WHY WAITING FOR TOMORROW WOULD HAVE BEEN THE LAZY ANSWER
--
-- The next scheduled firing was 2026-09-15 09:00 UTC. Waiting a day to learn
-- whether a fix works is not a plan. But the obvious cheap test does not work
-- either: BOTH COMMITs in the procedure (lines 166 and 181) sit behind
-- `IF NOT p_dry_run`, so a dry run exercises NEITHER, and the one thing still
-- unverified was precisely whether a procedure invoked by pg_cron may COMMIT
-- at all in this deployment.
--
-- So the test had to be a real pass in pg_cron's real execution context:
--
--   SELECT cron.schedule('ottoq-purge-probe-g63', '0 13 * * *',
--     $$CALL public.ottoq_retention_purge_runs(300, 2000, '48 hours', false);$$);
--
-- -- the IDENTICAL command to job 625, three minutes out, with nothing in
-- flight (0 running sim runs, 0 r%_ cert jobs). Unscheduled immediately after.
--
-- RESULT, jobid 628, runid 184940:
--
--   status      succeeded
--   start       2026-09-14 13:00:00.207+00
--   end         2026-09-14 13:00:13.240+00   (13.0 s)
--   message     CALL
--
-- BOTH COMMIT SITES WERE EXERCISED. Line 166 sits after the DELETE and before
-- `EXIT WHEN v_n = 0`, so it executes at least once per table even when the
-- DELETE removes nothing; line 181 executes because p_dry_run is false. A
-- procedure called by pg_cron can COMMIT here. 0294 (the cursor portal) and
-- 0295 (the SET clause) were both real causes and both are gone:
--
--   kind        PROCEDURE          (was a FUNCTION)
--   proconfig   (none)             (0295 removed the SET clause)
--   cron cmd    CALL public...     (not SELECT)
--   the loop    array_agg + FOR v_i IN 1..n, no open portal   (0294)
--
-- ===========================================================================
-- C. AND THEN THE COUNTER DID NOT MOVE, WHICH IS THE RIGHT ANSWER
--
-- The closing bar for this task was deliberately TWO conditions --
-- status='succeeded' AND a rising purged_at count -- because a job that runs
-- and does nothing is exactly what #87 was reopened for. Measured:
--
--   ottoq_sim_runs with purged_at NOT NULL   959  ->  959   (flat)
--   ottoq_retention_state.pass_deleted   5,911,079 -> 5,911,079  (flat)
--
-- By the stated bar that is a FAILURE. It is not, and the difference is the
-- selection query (lines 103-108):
--
--   SELECT array_agg(sr.sim_run_id) INTO v_doomed
--     FROM ottoq_sim_runs sr
--    WHERE sr.status <> 'running'
--      AND COALESCE(sr.run_by,'') <> 'production_live'
--      AND sr.started_at < v_cut
--      AND EXISTS (SELECT 1 FROM ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id);
--
-- Evaluated against the live database at the same moment:
--
--   effective keep_interval (from ottoq_retention_policy)   48:00:00
--   doomed runs                                             959
--   of those, purged_at IS NULL  (i.e. anything left to do)    0
--   of those, purged_at NOT NULL                            959
--
-- Every run the purge selected had already been purged by an earlier pass. It
-- deleted nothing because there was nothing to delete. Flat is correct.
--
-- ===========================================================================
-- D. THE THING NOT TO "OPTIMIZE", AND WHY IT IS WRITTEN DOWN HERE
--
-- The obvious next thought is that v_doomed should exclude purged_at IS NOT
-- NULL, so the nightly pass stops re-scanning 959 finished runs for 13 seconds.
-- THAT WOULD BE A CORRECTNESS BUG, and the reason is worth stating before
-- someone (me) acts on it:
--
--   IF v_n > 0 AND NOT v_stamped THEN
--     UPDATE ottoq_sim_runs SET purged_at = now()
--      WHERE sim_run_id = ANY(v_doomed) AND purged_at IS NULL;
--     v_stamped := true;
--   END IF;
--
-- v_stamped is ONE boolean for the whole call, and the UPDATE stamps EVERY
-- doomed run at once, on the FIRST row deleted anywhere in the batch. So
-- purged_at means "this run was in a batch where purging began" -- NOT "this
-- run is fully purged." A pass cut short by p_time_budget_s leaves runs
-- stamped and incompletely purged ON PURPOSE (0251: stamping early is what
-- makes ottoq_kpi_five tell the truth about a run whose rows are going away).
-- Filtering them out of v_doomed would strand those rows forever.
--
-- The 13 seconds is the price of that design, and it scales with the archive.
-- If it ever matters, the fix is a separate per-run completion marker, not a
-- filter on purged_at. Recorded, not done.
--
-- ===========================================================================
-- E. RE-MEASURE

-- did the last scheduled purge succeed, and how long did it take?
SELECT d.jobid, j.jobname, d.status, left(COALESCE(d.return_message,''),120) AS msg,
       d.start_time, round(extract(epoch FROM (d.end_time - d.start_time))::numeric, 2) AS seconds
  FROM cron.job_run_details d JOIN cron.job j ON j.jobid = d.jobid
 WHERE j.command ~ 'retention_purge'
 ORDER BY d.start_time DESC LIMIT 10;

-- the two facts that make a flat counter readable: how many runs the purge
-- would select, and how many of those still have work outstanding.
WITH pol AS (
  SELECT COALESCE((SELECT keep_interval FROM public.ottoq_retention_policy
                    WHERE policy_key = 'engine_rows' AND enabled), interval '48 hours') AS keep
), doomed AS (
  SELECT sr.sim_run_id, sr.purged_at
    FROM public.ottoq_sim_runs sr, pol
   WHERE sr.status <> 'running'
     AND COALESCE(sr.run_by,'') <> 'production_live'
     AND sr.started_at < now() - pol.keep
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id)
)
SELECT (SELECT keep FROM pol)                             AS effective_keep,
       count(*)                                           AS doomed_runs,
       count(*) FILTER (WHERE purged_at IS NULL)          AS still_to_do,
       count(*) FILTER (WHERE purged_at IS NOT NULL)      AS already_stamped
  FROM doomed;

-- the running totals the bar is judged against
SELECT (SELECT count(*) FROM public.ottoq_sim_runs WHERE purged_at IS NOT NULL) AS purged_runs,
       (SELECT count(*) FROM public.ottoq_sim_runs)                             AS total_runs,
       (SELECT pass_deleted FROM public.ottoq_retention_state
         WHERE table_name = 'engine_rows')                                      AS pass_deleted;

-- and the four properties of the fix, so a regression names itself
SELECT p.oid::regprocedure AS sig,
       CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION -- REGRESSION' END AS kind,
       COALESCE(array_to_string(p.proconfig,' | '), '(none)') AS proconfig_must_be_none,
       (SELECT count(*) FROM cron.job j
         WHERE j.jobid = 625 AND j.command LIKE 'CALL %') AS job_625_uses_call,
       (position('FOR v_i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP' in p.prosrc) > 0)
         AS loops_by_index_not_cursor
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
