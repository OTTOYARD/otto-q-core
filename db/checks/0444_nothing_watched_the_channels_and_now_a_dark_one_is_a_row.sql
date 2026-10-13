-- 0444  **Nothing watched the channels, and now a dark one is a row.** The premises of db/migrations/0707 (the channel
--        watchdog), and what to read once it runs. Read-only.
--
--        Measured 2026-10-13 between 19:22 and 19:31 UTC (2:22-2:31 PM CT), while run 02ac27b3 (busy_day, the twin
--        depot, wake gate on) was ticking. Finding G433.
--
-- ══ §1 WHO CALLS OUT, AND WHO READS THE REPLY (reproduce: (1)) ══
--
--   10 functions in public/ottoq/twin call net.http_post (8 names; ottoq_energy_mpc_replan has 3 overloads). The
--   energy-MPC replan reads its own reply from net._http_response; ottoq_energy_mpc_ingest and
--   ottoq_oem_webhook_collect_responses collect replies too. The agent's dispatches (ottoq_sim_decide_and_dispatch,
--   ottoq_cron_tick, ottoq_cuopt_refresh) and the twin ingest refresh never read theirs. net._http_response has no URL
--   column, so a reply cannot be traced back to its call. 0 functions call pg_notify; 0 read cron.job_run_details.
--   (The study's lane said every dispatch swallowed its error; 3 of the 10 match EXCEPTION WHEN OTHERS THEN NULL / RAISE
--   WARNING / RETURN / PERFORM. The finding that holds is the one above: nobody reads the result.)
--
-- ══ §2 integration_health IS SOMETHING ELSE (reproduce: (2)) ══
--
--   public.integration_health: 0 rows, no comment, read or written by no function or view. Keyed UNIQUE by
--   integration_name, with platform av_platform (waymo, motional, tesla, cruise, zoox, aurora, nuro, uber_av, generic,
--   not_applicable) and circuit_state (closed, open, half_open): the OEM-integration circuit breaker. 0707 leaves it
--   alone rather than claim circuit-breaker semantics nothing enforces.
--
-- ══ §3 WHAT DARK LOOKED LIKE TODAY (reproduce: (3), (4)) ══
--
--   Cron, 6 hours to 19:24 UTC: ottoq-depot-tick (*/2) longest gap 3 min 25 s; every minute job 2 min 25 s; the
--   recertification runner (job 746) ran 144.6 s, cancelled by the operator door at 19:19:24 (G141). 2 of the last
--   3,000 runs failed, both "canceling statement due to user request". pg_net, by hour: 15:00 UTC 267 replies, 51 timed
--   out; 18:00 UTC 350, 18 timed out, 1 error status; 19:00 UTC (part) 109, 6. Every timeout read "Timeout of 20000 ms",
--   the agent dispatch's own timeout. The model ledger, 24 hours to 19:25 UTC: nvidia_nemotron 119 rows, 112 enacted, 6 fallback, 1 noop
--   (mean latency 58,186 ms); cpsat_service 347 solved with zero proposals, 52 answered, 28 enacted.
--
-- ══ §4 WHAT HEALTHY LOOKS LIKE, FOR THE THRESHOLDS (reproduce: (5)) ══
--
--   Gaps between agent passes (ottoq_agent_pass_evidence) and between CP-SAT calls with a status, per run:
--     176b2912   79 passes, p50 49.2 s, p95 94.8 s, max 103.3 s      77 CP-SAT calls, max 103.2 s, 0 non-200
--     57188f55  288 passes, p50  7.9 s, p95 61.4 s, max 111.7 s     286 calls, max 109.5 s, 0 non-200
--     02ac27b3   27 passes (first 5 minutes), max 54.3 s              27 calls, max 54.3 s, 0 non-200
--   So amber at 3 minutes and red at 10 sit well clear of a healthy run. Live ticks are due every few seconds (02ac27b3:
--   73 ticks in its first 6 minutes), so a tick 2 minutes overdue is already unusual.
--
-- ══ §5 THE COST (reproduce: (6)) ══
--
--   cron.job_run_details: 84,846 rows, 278 MB, one index (runid). The watchdog's cron read takes the newest 1,500
--   runids through that index: 13.8 ms on live at 19:30 UTC (21 active jobs, 1,500 rows sorted in 121 kB).

\echo '=== 0444 (1): functions that call out through pg_net, and whether they read the reply ==='
SELECT n.nspname || '.' || p.proname AS fn,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'net\.http_post', 'g')) AS posts,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'PERFORM\s+net\.http_post', 'g')) AS performs,
       p.prosrc ~ 'net\._http_response' AS reads_replies
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'net\.http_post'
 ORDER BY 1;
SELECT count(*) FILTER (WHERE p.prosrc ~ 'pg_notify\s*\(') AS fns_notifying,
       count(*) FILTER (WHERE p.prosrc ~ 'cron\.job_run_details') AS fns_reading_cron_runs,
       count(*) FILTER (WHERE p.prosrc ~ 'net\._http_response') AS fns_reading_replies
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin');

\echo '=== 0444 (2): integration_health is the OEM circuit breaker, empty and unreferenced ==='
SELECT (SELECT count(*) FROM public.integration_health) AS rows_,
       (SELECT count(*) FROM pg_proc p WHERE p.prosrc ILIKE '%integration_health%') AS fn_refs,
       (SELECT count(*) FROM pg_class c WHERE c.relkind = 'v' AND pg_get_viewdef(c.oid) ILIKE '%integration_health%') AS view_refs;

\echo '=== 0444 (3): cron, last 6 hours: runs, failures, longest gap, longest run, per job ==='
WITH d AS (SELECT jobid, start_time, end_time, status,
                  lag(start_time) OVER (PARTITION BY jobid ORDER BY start_time) AS prev
             FROM cron.job_run_details
            WHERE runid > (SELECT max(runid) FROM cron.job_run_details) - 3000
              AND start_time > now() - interval '6 hours')
SELECT d.jobid, j.jobname, j.schedule, count(*) AS runs, count(*) FILTER (WHERE d.status <> 'succeeded') AS not_ok,
       max(d.start_time - d.prev) AS max_gap, round(max(extract(epoch FROM d.end_time - d.start_time))::numeric, 1) AS max_s
  FROM d JOIN cron.job j USING (jobid)
 GROUP BY d.jobid, j.jobname, j.schedule ORDER BY d.jobid;

\echo '=== 0444 (4): pg_net replies by hour (kept 6 hours) ==='
SELECT date_trunc('hour', created) AS hour_utc, count(*) AS replies,
       count(*) FILTER (WHERE status_code BETWEEN 200 AND 299) AS ok_2xx,
       count(*) FILTER (WHERE status_code >= 400) AS error_status, count(*) FILTER (WHERE timed_out) AS timed_out
  FROM net._http_response GROUP BY 1 ORDER BY 1 DESC;

\echo '=== 0444 (5): gaps between agent passes and between CP-SAT calls, per run, last 6 hours ==='
WITH e AS (SELECT sim_run_id, recorded_at AS at, lag(recorded_at) OVER (PARTITION BY sim_run_id ORDER BY recorded_at) AS prev
             FROM public.ottoq_agent_pass_evidence WHERE recorded_at > now() - interval '6 hours'),
     c AS (SELECT sim_run_id, called_at AS at, http_status, lag(called_at) OVER (PARTITION BY sim_run_id ORDER BY called_at) AS prev
             FROM public.ottoq_model_call_ledger
            WHERE provider = 'cpsat_service' AND http_status IS NOT NULL AND called_at > now() - interval '6 hours')
SELECT 'agent_pass' AS what, left(sim_run_id::text, 8) AS run, count(*) AS n, NULL::bigint AS not_200,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY extract(epoch FROM at - prev))::numeric, 1) AS p95_gap_s,
       round(max(extract(epoch FROM at - prev))::numeric, 1) AS max_gap_s
  FROM e GROUP BY 2
UNION ALL
SELECT 'cpsat_call', left(sim_run_id::text, 8), count(*), count(*) FILTER (WHERE http_status <> 200),
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY extract(epoch FROM at - prev))::numeric, 1),
       round(max(extract(epoch FROM at - prev))::numeric, 1)
  FROM c GROUP BY 2
 ORDER BY 2, 1;

\echo '=== 0444 (6): the watchdog cron read, timed ==='
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
WITH fl AS (SELECT COALESCE(max(d.runid), 0) - 1500 AS f FROM cron.job_run_details d),
runs AS (SELECT d.jobid, d.start_time, d.status,
                d.start_time - lag(d.start_time) OVER (PARTITION BY d.jobid ORDER BY d.start_time) AS gap
           FROM cron.job_run_details d WHERE d.runid > (SELECT f FROM fl) AND d.start_time <= now())
SELECT cj.jobname, (SELECT max(r.start_time) FROM runs r WHERE r.jobid = cj.jobid),
       (SELECT max(r.gap) FROM runs r WHERE r.jobid = cj.jobid AND r.start_time > now() - interval '1 hour')
  FROM cron.job cj WHERE cj.active;

\echo '=== 0444 (7), after 0707: the six channels now, and every change of status today ==='
SELECT channel, status, reason, status_since, checked_at FROM public.ottoq_channel_health_now ORDER BY channel;
SELECT channel, prev_status, status, reason, checked_at
  FROM public.ottoq_channel_health
 WHERE checked_at > date_trunc('day', now()) AND prev_status IS DISTINCT FROM status
 ORDER BY health_id;
