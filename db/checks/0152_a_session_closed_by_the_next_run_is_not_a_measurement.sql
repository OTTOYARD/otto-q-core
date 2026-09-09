-- =====================================================================
-- 0152 — A charge session closed by the NEXT run is not a measurement.
--        63% of the benchmark lane's sessions end before they start.
--
-- Finding id: G36 (with G36b unexplained, deliberately)
-- Opened:     2026-09-08 22:5x UTC (5:5x PM CT)
-- Found by:   scoring the first real CRN policy pair with 0231's outcome
--             block. The otto_q arm reported 0.0 kW peak while having
--             delivered 128.79 kWh, which is not possible.
-- Status:     OPEN — fix drafted as migration 0233 for the one mechanism
--             that is conclusively diagnosed
--
-- ---------------------------------------------------------------------
-- 1. THE PAIR THAT FOUND IT
-- ---------------------------------------------------------------------
-- First true CRN policy pair in this database's history. Same seed
-- (555001), same ab_group (02310000-...-0003), so ottoq_cert_arm seeds
-- both arms' worlds from the same hash(seed || ab_group || 'wave'):
--
--   otto_q  049eb402-20e9-406c-aec5-f4cc59928c48   12 ticks
--   fifo    612dabbf-ccdc-4050-9e76-6e33b6d62b67   12 ticks
--
-- 0231's outcome block on the two arms:
--
--   field                   otto_q     fifo
--   ---------------------   --------   --------
--   energy_delivered_kwh      128.79     577.98
--   charge_sessions               15         18
--   sessions_still_open            0          9
--   service_point_hours       -83.87       7.50     <-- negative
--   kwh_per_point_hour          -1.5       77.1     <-- negative
--   soc_points_added            NULL        462
--   mean_soc_gain               NULL      51.33
--   soc_measured_sessions          0          9
--   peak_concurrent_kw           0.0      657.9     <-- impossible
--
-- 0.0 kW peak with 15 sessions and 128.79 kWh delivered is not a bad
-- policy. It is a broken instrument, and the instrument is the data.
--
-- DO NOT READ THAT TABLE AS A COMPARISON. It is not one. It is the
-- evidence for §2.

-- ---------------------------------------------------------------------
-- 2. THE RAW ROWS
-- ---------------------------------------------------------------------
SELECT 'a_session_health' AS check, r.policy,
       count(*)                                              AS sessions,
       count(*) FILTER (WHERE o.ended_at IS NULL)            AS open_sessions,
       count(*) FILTER (WHERE o.ended_at < o.started_at)     AS ended_before_started,
       count(*) FILTER (WHERE COALESCE(o.avg_power_kw,0)=0)  AS zero_avg_kw,
       count(*) FILTER (WHERE o.soc_end IS NULL)             AS null_soc_end,
       min(o.started_at) AS first_start, max(o.ended_at) AS last_end
FROM public.ocpp_sessions o JOIN public.ottoq_sim_runs r ON r.sim_run_id=o.sim_run_id
WHERE r.ab_group_id='02310000-0000-4000-8000-000000000003'::uuid
GROUP BY r.policy;
-- Observed:
--   otto_q  15 sessions, 0 open, 15 ended_before_started, 15 zero_avg_kw,
--           15 null_soc_end, first_start 2026-09-09 03:17:38 (SIM),
--           last_end 2026-09-08 22:48:10  <-- WALL CLOCK
--   fifo    18 sessions, 9 open,  0 ended_before_started,  9 zero_avg_kw,
--            9 null_soc_end
--
-- 2026-09-08 22:48:10 is the wall-clock instant the fifo arm was
-- launched. Every one of the otto_q arm's sessions was closed, with a
-- wall-clock timestamp, BY THE NEXT ARM'S DEPOT RESET.

-- ---------------------------------------------------------------------
-- 3. THE MECHANISM, QUOTED
-- ---------------------------------------------------------------------
-- public.ottoq_benchmark_reset, line 12, verbatim:
--
--   UPDATE ocpp_sessions SET status='completed', ended_at=now()
--    WHERE depot_id=p_depot AND status='active';
--
-- Three separate wrongs in one statement:
--
--   i.   ended_at=now() is the WALL clock. started_at is SIM time. A
--        12-tick arm advances the sim clock six hours, so the session
--        ends roughly six hours before it began. The worst delta on this
--        depot is -05:59:28 -- one sim shift exactly.
--   ii.  status='completed' is a lie. The session was force-killed by an
--        unrelated run's setup. The enum offers 'cancelled', which is
--        what ottoq_sim_release_depot correctly uses.
--   iii. No stopped_reason, no soc_end, no avg_power_kw. The row is
--        marked finished while carrying none of the measurements that
--        make a finished session meaningful -- which is why
--        peak_concurrent_kw summed to 0.0.
--
-- It is the only function in the database that closes a session with a
-- literal now():
SELECT 'b_wallclock_closers' AS check,
       coalesce(string_agg(DISTINCT n.nspname||'.'||p.proname, ', '),'none') AS fns
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('public','twin','ottoq')
  AND p.prosrc ~* 'UPDATE\s+(public\.)?ocpp_sessions[^;]*ended_at\s*=\s*now\(\)';
-- Observed: public.ottoq_benchmark_reset. One.

-- ---------------------------------------------------------------------
-- 4. SCALE, AND THE SPLIT BETWEEN WHAT IS PROVEN AND WHAT IS NOT
-- ---------------------------------------------------------------------
SELECT 'c_negative_durations' AS check,
       coalesce(d.slug,'?') AS depot,
       coalesce(o.stopped_reason,'<null>') AS stopped_reason,
       o.status::text AS status, count(*) AS n,
       min(o.ended_at - o.started_at) AS worst_delta
FROM public.ocpp_sessions o LEFT JOIN public.depots d ON d.id=o.depot_id
WHERE o.ended_at < o.started_at
GROUP BY 2,3,4 ORDER BY 5 DESC;
-- Observed 2026-09-08, three distinct populations:
--
--   nashville-flagship  sim_reset                      cancelled  1378  -2d 14:58:28
--   benchmark-crn       <null>                         completed    55     -05:59:28
--   nashville-flagship  vehicle_departed_orphan_sweep  cancelled     8  -2d 12:59:47
--
-- As a share of each depot: benchmark-crn 55 of 88 sessions, 63%.
-- nashville-flagship 1,386 of 49,174, 2.8%.
--
-- G36, PROVEN: the 55 benchmark rows are ottoq_benchmark_reset. NULL
-- reason and status='completed' are its signature -- no other closer
-- leaves either -- and -05:59:28 is exactly the sim shift a 12-tick arm
-- advances. Migration 0233 fixes this one.
--
-- G36b, NOT PROVEN AND NOT GUESSED AT: the 1,378 flagship rows come from
-- public.ottoq_sim_release_depot, identified by stopped_reason. But that
-- function is NOT making the wall-clock mistake -- line 39 reads
--
--   ended_at = (SELECT COALESCE(r.sim_clock_current, now())
--                 FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id)
--
-- which is the run's own sim clock, correctly, and is even annotated
-- /* 0194 */ as a prior fix. Why a run's own final sim clock should
-- precede its own sessions' start times by up to two and a half days is
-- NOT established here. Naming the function is not diagnosing it, and
-- the difference matters: 0233 must not "fix" a function whose defect is
-- not understood. Filed as its own finding with the query above as its
-- starting point.
--
-- The 8 orphan-sweep rows are public.ottoq_reconcile_charger_states and
-- are likewise unexplained. Same treatment.
--
-- ---------------------------------------------------------------------
-- 5. THE INSIGHT THAT OUTLIVES THE FIX
-- ---------------------------------------------------------------------
-- Every cert arm sets sim_clock_start = now() and advances six sim hours
-- over twelve ticks. So each run's sim clock is an INDEPENDENT TIMELINE
-- anchored at its own wall-clock start. Two runs minutes apart in real
-- time produce sim timestamps that overlap, interleave, and disagree
-- about ordering.
--
-- Those run-relative instants are stored in one column of one shared
-- table -- ocpp_sessions.started_at and .ended_at -- as though they were
-- absolute. So:
--
--   ANY QUERY THAT COMPARES TIMESTAMPS ACROSS RUNS IS COMPARING
--   POSITIONS ON DIFFERENT TIMELINES.
--
-- Within one run they are sound, which is why the flagship's own metrics
-- have held up. The exposure is anything that spans runs: a rolling
-- 15-minute peak_site_kw window that crosses a run boundary, a
-- cross-run duration total, and the force-close in §3, which is a
-- cross-run write. This is the same family as G34 (db/checks/0150) and
-- 0145: run-scoped facts handled as though they were global.
--
-- ---------------------------------------------------------------------
-- 6. WHAT THIS COSTS THE A/B, STATED PRECISELY
-- ---------------------------------------------------------------------
-- The two arms' session records are damaged in DIFFERENT WAYS DEPENDING
-- ON RUN ORDER:
--
--   the arm that ran FIRST   -> force-closed by the second arm's reset,
--                               wall-clock ended_at, no meters
--   the arm that ran LAST    -> sessions left 'active' forever, never
--                               finalised, no soc_end, no avg_power_kw
--
-- Neither is a measurement, and swapping the order swaps the damage. A
-- comparison built on this measures which arm went second.
--
-- So 0147 §7's freeze stands and gains a fourth condition. No
-- comparative number until: (a) the arms solve the same problem,
-- (b) the world is held constant, (c) the score reads only common
-- ground -- shipped in 0231 -- and now (d) both arms' records survive
-- the other arm.
--
-- What DID work, and is worth recording as a success rather than buried
-- among defects: 0231's outcome block read a baseline arm and returned
-- non-zero on every field (fifo: 577.98 kWh, 18 sessions, 18 vehicles,
-- 462 SoC points). That was 0231's stated falsifier and it PASSED. The
-- instrument works; it is the substrate underneath that is broken, and
-- the instrument is what proved it -- soc_measured_sessions and
-- sessions_still_open, both added by 0231 specifically so a number would
-- carry its own coverage, are what made §2 legible at a glance.
-- =====================================================================
