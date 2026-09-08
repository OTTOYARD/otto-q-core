-- ---------------------------------------------------------------------------
-- 0126 — where the tick actually spends its time, and why the drift is not one
--        bad query.
--
-- Task G19: a certification pair on a FIXED column — busy_day / 314159 / 12
-- ticks, flagship, pinned sim start — went from 389 s on 09-01 to 812 s on
-- 09-08. Same seed, same world, same everything.
--
-- Three hypotheses had already been refuted by measurement (the metronome,
-- missing sim_run_id indexes, and the leg_id index 0216 added — which fixed a
-- real unbounded scan and moved the pair zero seconds). This check records the
-- decomposition that replaced guessing, taken 2026-09-08.
-- ---------------------------------------------------------------------------

-- Q1. THE INSTRUMENT ALREADY EXISTED AND NOBODY HAD LOOKED AT IT.
--     ottoq_tick_clock_log carries one row per tick with real_started_at /
--     real_ended_at written from clock_timestamp() — NOT now(). That matters:
--     the whole pair runs in one transaction, so now() is frozen and
--     ottoq_events.recorded_at is useless for timing (every row in an arm
--     carries the same instant). clock_timestamp() is not.
SELECT tick_seq, tick_compute_ms, real_started_at, real_ended_at
FROM public.ottoq_tick_clock_log
WHERE sim_run_id = '5861ea1d-10f6-46ff-8ad8-0145ab5def44'   -- round 25, pair 1, arm a
ORDER BY tick_seq;

-- Q2. AND IT ONLY COVERS HALF THE TICK. ottoq_sim_advance_tick is two calls:
--
--       ottoq_sim_advance_tick_world(run)    <- tick_compute_ms measures this
--       ottoq_sim_decide_and_dispatch(run)   <- measured by NOTHING
--
--     So the gap between one tick's real_ended_at and the next tick's
--     real_started_at IS the decide half. On round 25 pair 1 arm a: twelve
--     ticks, 26.1 s of instrumented world compute inside a 235 s arm. The
--     other 209 s is the decide path, and nothing was watching it.

-- Q3. THE DECOMPOSITION, per tick, averaged over every flagship 314159/12t
--     certification arm, by day. This is the G19 result.
--
--       day     world(s)  decide(s)  total(s)
--       08-30     0.97      6.0        7.0
--       08-31     1.13      7.1        8.3
--       09-01     1.69      9.1       10.8
--       09-02     2.37      7.6        9.9
--       09-03     2.78     12.5       15.3
--       09-04     3.17     12.7       15.9
--       09-05     3.61     15.3       18.9
--       09-06     3.61     18.4       22.0
--       09-07     3.94     16.6       20.5
--       09-08     3.35     20.2       23.6
--
--     Two facts, and the second is the one that matters:
--
--     (a) decide_and_dispatch is ~6x the world half in absolute terms — 20 s of
--         a 23.6 s tick. Any fix that moves the number has to be there.
--     (b) BOTH HALVES GREW BY THE SAME FACTOR, ~3.4x. Two independent code
--         paths do not degrade in lockstep unless what they SHARE degraded.
--         That is what rules out a single bad query, and it is why the leg_id
--         index — a genuine unbounded scan in one of them — bought nothing.
--
--     Arithmetic closes: 12 ticks x 23.6 s x 2 arms = 566 s, plus ~250 s of
--     reset / boot / teardown / verdict = the 812 s pair.
WITH runs AS (
  SELECT r.sim_run_id, r.started_at::date AS day
  FROM public.ottoq_sim_runs r
  WHERE r.run_by='cert_harness' AND r.depot_id='11111111-1111-1111-1111-111111111111'
    AND r.random_seed=314159 AND r.scenario_code='busy_day' AND r.tick_count=12
    AND r.started_at > now() - interval '9 days'
), t AS (
  SELECT ru.day, l.tick_compute_ms,
         EXTRACT(epoch FROM (l.real_started_at
                 - lag(l.real_ended_at) OVER (PARTITION BY l.sim_run_id ORDER BY l.tick_seq))) AS gap_s
  FROM public.ottoq_tick_clock_log l JOIN runs ru ON ru.sim_run_id = l.sim_run_id
)
SELECT day, count(*) AS ticks,
       round(avg(tick_compute_ms)/1000.0, 2) AS world_s,
       round(avg(gap_s)::numeric, 1)          AS decide_s,
       round((avg(tick_compute_ms)/1000.0 + avg(gap_s))::numeric, 1) AS total_s
FROM t GROUP BY day ORDER BY day;

-- Q4. WHAT THE SHARED-SUBSTRATE READING RULES IN AND OUT.
--     Bloat: worst is ottoq_stall_bookings at 16.9% dead tuples and
--     ottoq_itinerary_legs at 13.7%; everything else under 2%, and autovacuum
--     has run 941 and 1,210 times on those two. Not a 3.4x.
--     Cache: shared_buffers is 1 GB against a 15 GB database and the pair's hit
--     ratio is 99.48% — but that is a RATIO. The absolute figure is 183,901,558
--     blocks read from disk over 314 pair calls, ~4.6 GB per pair. A 0.5% miss
--     rate on a very large number of touches is still a great deal of I/O, so
--     this one is only PARTLY refuted and remains the leading candidate.
SELECT relname, n_live_tup, n_dead_tup,
       CASE WHEN n_live_tup>0 THEN round(100.0*n_dead_tup/n_live_tup,1) END AS dead_pct,
       autovacuum_count, last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname='public'
  AND relname IN ('ottoq_stall_bookings','ottoq_itinerary_legs','ottoq_decisions',
                  'ottoq_events','ottoq_rule_evaluations','ottoq_vehicle_commands')
ORDER BY n_dead_tup DESC;

-- Q5. THE NEXT STEP IS AN INSTRUMENT, NOT ANOTHER GUESS.
--     The bigger half of every tick has no timing of its own and its cost is
--     inferred from a subtraction. ottoq_sim_decide_and_dispatch should record
--     a decide_compute_ms the way advance_tick_world records tick_compute_ms —
--     an additive write to a table no verdict atom hashes, so it cannot move a
--     canon. Only once the decide half is broken down further does another fix
--     attempt make sense. Two have already been spent on guesses.
SELECT 'ottoq_tick_clock_log columns today' AS note,
       string_agg(column_name, ', ' ORDER BY ordinal_position) AS cols
FROM information_schema.columns
WHERE table_schema='public' AND table_name='ottoq_tick_clock_log';
