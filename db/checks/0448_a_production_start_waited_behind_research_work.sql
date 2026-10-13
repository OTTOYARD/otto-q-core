-- 0448  **A production start waited behind research work.** ottoq_production_start neither cancelled a running check nor
--        took the world lock, as the operator door does, so a session started inside a research arm got no tick until
--        the arm ended. -> G437, 0719. (The study's DC-4, step 3.)
--        Measured 2026-10-13, read-only, from 20:39:40 UTC to 20:42:12 UTC (each query's now()).
--
-- ══ §1 RESEARCH ARMS HOLD THE ONLY SCHEDULER FOR HOURS (reproduce: (1)) ══════════════════════════════════════════════
--
--   7 days to 20:41:06 UTC: the throughput sweep runner (job 783) ran 21 times for longer than two minutes, 43.25 hours
--   in all (26% of the week), the longest 2 h 26 m 09 s; the recert runner (job 746) 19 times, 1.45 hours, the longest
--   12 m 26 s. pg_cron runs one job at a time here, so the depot tick (job 10, */2), which drives a production session
--   through twin.ottoq_world_advance, does not fire while one runs (G141, measured in the study: 0 of about 1,299
--   expected depot ticks inside the sweep's arms).
--
-- ══ §2 EVERY ARM TAKES THE WORLD LOCK; ONLY THE OPERATOR DOOR TAKES IT BACK (reproduce: (2)) ═══════════════════════
--
--   public.ottoq_try_world_lock takes pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')). It is called by the
--   throughput sweep runner and arm, the dial pair and the dial experiment runner; the recert runner takes the same key
--   in its own command. public.ottoq_operator_start_run cancels every backend holding that lock and every active
--   hand-run pair, then waits on the lock itself, so a demo never waits on research. public.ottoq_production_start
--   (md5 c0ae7ec6...) checks for a running run at the depot and inserts its own, and does neither. The runners yield to
--   any running run once the session has committed, so the gap is exactly an arm already in flight when a person
--   presses start: up to the 2 h 26 m measured above with a live depot and no decide path, agent or world step.
--
--   Not changed, and noted for Chase with the 0701 family: ottoq_production_start and ottoq_production_stop are
--   EXECUTE-able by PUBLIC, anon and authenticated. Not exploitable today, read from the catalog: both run as the caller,
--   and anon and authenticated hold no SELECT, INSERT or UPDATE on ottoq_sim_runs or ottoq_scenarios, so an anonymous
--   call fails at its first read. No app or edge function calls either (a search of every repository under /home/user).
--
-- ══ QUERIES ══

-- (1) the research runners' long runs over the last 7 days
SELECT jobid, count(*) FILTER (WHERE end_time - start_time > interval '2 minutes') AS long_runs,
       round(extract(epoch FROM sum(end_time - start_time) FILTER (WHERE end_time - start_time > interval '2 minutes')) / 3600, 2) AS long_hours,
       max(end_time - start_time) AS longest
  FROM cron.job_run_details WHERE jobid IN (746, 783) AND start_time > now() - interval '7 days'
 GROUP BY 1;

-- (2) who takes the world lock, and whether production start does (comments stripped)
SELECT p.proname,
       regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'ottoq_try_world_lock|pg_try_advisory|pg_advisory' AS takes_the_world,
       regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'pg_cancel_backend' AS cancels_checks
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('ottoq_throughput_sweep_runner', 'ottoq_throughput_sweep_arm', 'ottoq_dial_pair',
                     'ottoq_dial_experiment_runner', 'ottoq_operator_start_run', 'ottoq_production_start',
                     'ottoq_world_yield_to_start')
 ORDER BY 1;
