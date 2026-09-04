-- 0105 — THE 60-MINUTE WAIT WAS THE CLOCK AND THE COLD START
--
-- 0104 §4 named an undiagnosed defect: OTTO-Q showed a p95 wait of
-- 7.1-60 min while no resource exceeded 20% utilisation, and recorded
-- that queueing could not explain it. This check diagnoses it.
--
-- It is diagnosed. It is not a scheduling defect and it is not
-- contention. It is two things, both of which invalidate 0104's
-- comparison rather than OTTO-Q's engine.
--
-- Run under examination: cd8e0796-8f5e-47e1-846a-c24ed72a4c42
--   (busy_day, seed 171717, 48 ticks, 682 done legs — the busiest
--    recorded run, the same one 0104 §2 measured utilisation on).
--   Its pair twin ed6ad879-f127-4baa-9f34-5f645dd684b2 returns
--   identical figures on every query below, as it must.
--
-- =====================================================================
-- FINDING 1 — 0104's WAIT METRIC DID NOT MEASURE WAITING
-- =====================================================================
-- 0191's ottoq_baseline_fifo takes l.planned_start_sim as the leg's
-- readiness time, for BOTH arms. planned_start_sim is not a readiness
-- time. It is a plan the engine itself produced, and the engine
-- routinely beats it:
--
--   leg_type   legs   avg(actual_start - planned_start)   started early
--   inspect     106            -66.4 min                    88 of 106
--   wash         12            -92.9 min                     8 of 12
--   detail       15           -113.3 min                    14 of 15
--   charge_l2    62             -2.1 min                     6 of 62
--   charge_dcfc  33              0.0 min                     0 of 33
--
-- A negative mean is the whole finding. `actual_start - planned_start`
-- measures adherence to a self-authored plan, in a system that mostly
-- runs ahead of it. It is not a wait.
--
-- Worse for the comparison: the FIFO arm was handed the same
-- planned_start_sim as its ready_at, then assigned by
--   v_start := GREATEST(ready_at, stall.free_at)
-- With stalls idle, free_at <= ready_at always, so v_start = ready_at
-- and the wait is 0. FIFO's "p95 wait 0.0" in 0104 was not a result.
-- The metric could not have produced any other number on an uncontended
-- day. A check that cannot fail is not a check, and a baseline that
-- cannot lose is not a baseline.
--
-- 0104's TURNS comparison (+7% for OTTO-Q) is unaffected — it counts
-- completions, not waits. 0104's WAIT comparison is withdrawn by this
-- check. It is not corrected to a better number; it is withdrawn,
-- because the two arms were never measuring the same quantity.
--
-- =====================================================================
-- FINDING 2 — THE HONEST METRIC, AND WHAT IT SAYS
-- =====================================================================
-- The readiness signal that exists is ottoq_visit_needs.arrived_at.
-- Arrival at depot -> first service operation actually starting is
-- exactly CLAUDE.md 2.9 KPI 5 (p95_time_to_service). Measured over the
-- 123 visits in this run (122 reached service; 1 did not):
--
--   mean 92.7 min | p50 60.0 | p95 240.0 | max 300.0
--
-- The p95 is 240 minutes, not 60. 0104 under-reported the real delay
-- by 4x while reporting it against a baseline pinned at zero.
--
-- =====================================================================
-- FINDING 3 — EVERY WAIT IS A WHOLE NUMBER OF TICKS
-- =====================================================================
--   wait_min   visits   exact multiple of 30
--       30       20            20
--       57       20             0
--       60       32            32
--       90       15            15
--      120       12            12
--      150        5             5
--      180        3             3
--      210        7             7
--      240        4             4
--      270        2             2
--      300        2             2
--
-- 102 of 122 are exact multiples of 30 minutes. 30 minutes is one tick:
-- the run covers 1,440 sim-minutes in 48 ticks. The minimum observed
-- wait is exactly one tick, and all 123 arrivals land exactly on a tick
-- boundary (0 mid-tick arrivals). So the floor is not rounding — it is
-- decision latency. A vehicle seen on tick N is served no earlier than
-- tick N+1.
--
-- Two separable questions follow, neither answered here and neither
-- guessed at:
--   (a) can the decide path assign within the arrival tick at all, or
--       is one-tick deferral structural?
--   (b) is 30 sim-min the right decision resolution? At this cadence
--       KPI 5 has a hard floor of 30 minutes no matter how empty the
--       depot is, which is a KPI-5 ceiling set by the clock.
--
-- Recorded as an open question, not a defect. Deferring an assignment
-- by one decision cycle may be correct; 30 minutes per cycle is a
-- scenario parameter, not an engine property.
--
-- =====================================================================
-- FINDING 4 — THE TAIL IS A COLD START, NOT A QUEUE
-- =====================================================================
--   tick   arrivals   service starts
--     0       34            0
--     1       32           18
--     2       25           17
--     3        8           24
--     4        9           28
--     5        1           23
--     6        4           25
--     7        0           31
--     8        3           29
--     9+       0          27, 24, 25, 18, 11, 10, 11, 7, 6, 2, 1, ...
--
-- 91 of 123 arrivals (74%) land in the first three ticks — 90 sim-
-- minutes. After tick 8 (4 sim-hours) there are no arrivals at all for
-- the remaining 20 hours. Tick 0 serves nobody.
--
-- Every wait over 90 minutes belongs to a vehicle that arrived between
-- 02:00 and 05:00 sim-time. The tail is the initial burst draining at
-- ~25 starts per tick. It is a cold-start queue, and it is the only
-- queue in the run.
--
-- =====================================================================
-- FINDING 5 — "busy_day" IS NOT A DAY
-- =====================================================================
-- This is the finding that matters most, and it invalidates the
-- scenario rather than any one number.
--
-- busy_day is a 90-minute mass arrival followed by roughly 20 hours of
-- an empty depot. 0104 §2 reported utilisation over 24 hours and got
-- 0.7-20%. Restricting to each resource's own active window barely
-- moves it:
--
--   stall_type    stalls   stall-hours   util/24h   util/active window
--   service_bay      2         0.3         0.6%          50.0%  (0.3h window)
--   wash_bay         3         6.9         9.6%          23.7%
--   dcfc            10        14.3         5.9%           7.1%
--   l2              30         6.9         1.0%           1.4%
--   staging        113         5.8         0.2%           0.7%
--
-- 95 charge legs against 40 charge points across a 20-hour window is
-- 2.4 turns per point per day. Nothing queues because nothing can.
--
-- =====================================================================
-- VERDICT
-- =====================================================================
-- The 60-minute p95 is fully explained: ~30 minutes of it is the
-- decision clock, and the remainder is a cold-start burst draining.
-- Neither is a scheduling failure, and NEITHER IS CONTENTION. 0104 §4
-- is closed.
--
-- What replaces it is a larger problem. Three of our load-shaped claims
-- were about an artefact:
--   - "20% peak utilisation" was measured across 20 hours of an empty
--     depot AND across an active window that is barely busier;
--   - "OTTO-Q p95 wait 7.1-60 min" measured plan adherence, not waiting;
--   - "FIFO p95 wait 0.0" was arithmetically forced by the metric.
--
-- The scenario cannot measure scheduling, because it never schedules
-- anything scarce. Its arrivals are also tick-quantised: 0 of 123
-- arrive mid-tick, so the twin cannot currently express "arrived four
-- minutes after the decision cycle," which is the ordinary real case.
-- ottoq_vehicle_dispatches carries an arrival_jitter_min column, so
-- jitter exists as a concept upstream and is not reaching visits.
--
-- =====================================================================
-- WHAT THIS MAKES NECESSARY (not done here)
-- =====================================================================
-- 1. Withdraw the 0104 wait comparison. Done above.
-- 2. Re-base the baseline's ready_at on arrived_at (KPI 5's definition)
--    so both arms measure the same quantity, and so FIFO can lose.
-- 3. A scenario with arrivals spread across a real duty cycle instead
--    of a 90-minute cold start, sized so a resource actually saturates.
-- 4. Sub-tick arrival jitter, so time-to-service is not floor-limited
--    by arrival quantisation.
--
-- =====================================================================
-- QUERIES (all read-only; every figure above regenerates from these)
-- =====================================================================

-- §1 — plan adherence is negative: planned_start_sim is not readiness.
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id)
SELECT s.stall_type, l.leg_type, count(*) AS legs,
       round(avg(EXTRACT(epoch FROM l.actual_start_sim - l.planned_start_sim)/60.0)::numeric,1) AS avg_dev_min,
       count(*) FILTER (WHERE l.actual_start_sim < l.planned_start_sim) AS started_early
  FROM ottoq_itinerary_legs l JOIN stalls s ON s.id = l.to_stall_id, run
 WHERE l.sim_run_id = run.id AND l.status='done'
   AND l.actual_start_sim IS NOT NULL AND l.planned_start_sim IS NOT NULL
   AND l.leg_type <> ALL (ARRAY['taxi','stage','depart'])
 GROUP BY 1,2 ORDER BY avg_dev_min;

-- §2 — the honest metric: arrival -> first service start (KPI 5).
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id),
v AS (SELECT visit_id, vehicle_id, arrived_at FROM ottoq_visit_needs, run WHERE sim_run_id = run.id),
fo AS (
  SELECT v.visit_id, v.arrived_at, min(l.actual_start_sim) AS first_start
    FROM v LEFT JOIN ottoq_itinerary_legs l
      ON l.vehicle_id = v.vehicle_id AND l.sim_run_id = (SELECT id FROM run)
     AND l.actual_start_sim >= v.arrived_at
     AND l.leg_type <> ALL (ARRAY['taxi','stage','depart'])
   GROUP BY 1,2)
SELECT count(*) AS visits, count(first_start) AS reached_service,
       round(avg(EXTRACT(epoch FROM first_start-arrived_at)/60.0)::numeric,1) AS mean_min,
       round(percentile_cont(0.50) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM first_start-arrived_at)/60.0)::numeric,1) AS p50_min,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM first_start-arrived_at)/60.0)::numeric,1) AS p95_min,
       round(max(EXTRACT(epoch FROM first_start-arrived_at)/60.0)::numeric,1) AS max_min
  FROM fo;

-- §3 — the wait is quantised to the tick, and arrivals are tick-aligned.
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id),
v AS (SELECT visit_id, vehicle_id, arrived_at FROM ottoq_visit_needs, run WHERE sim_run_id = run.id),
fo AS (
  SELECT v.arrived_at, min(l.actual_start_sim) AS first_start
    FROM v LEFT JOIN ottoq_itinerary_legs l
      ON l.vehicle_id = v.vehicle_id AND l.sim_run_id = (SELECT id FROM run)
     AND l.actual_start_sim >= v.arrived_at
     AND l.leg_type <> ALL (ARRAY['taxi','stage','depart'])
   GROUP BY v.visit_id, v.arrived_at)
SELECT round(EXTRACT(epoch FROM first_start-arrived_at)/60.0)::int AS wait_min, count(*) AS visits,
       count(*) FILTER (WHERE (EXTRACT(epoch FROM first_start-arrived_at)/60.0)::numeric % 30 = 0) AS multiple_of_one_tick
  FROM fo WHERE first_start IS NOT NULL GROUP BY 1 ORDER BY 1;

WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id)
SELECT count(*) AS visits,
       count(*) FILTER (WHERE EXTRACT(epoch FROM arrived_at)::bigint % 1800 = 0) AS on_tick_boundary,
       count(*) FILTER (WHERE EXTRACT(epoch FROM arrived_at)::bigint % 1800 <> 0) AS mid_tick
  FROM ottoq_visit_needs, run WHERE sim_run_id = run.id;

-- §4 — arrivals and service starts per tick: the cold start, visible.
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id,
                    '2026-09-01 02:00:00+00'::timestamptz AS t0),
arr AS (SELECT floor(EXTRACT(epoch FROM vn.arrived_at - run.t0)/1800)::int AS tick, count(*) AS arrivals
          FROM ottoq_visit_needs vn, run WHERE vn.sim_run_id = run.id GROUP BY 1),
st AS (SELECT floor(EXTRACT(epoch FROM l.actual_start_sim - run.t0)/1800)::int AS tick, count(*) AS starts
         FROM ottoq_itinerary_legs l, run
        WHERE l.sim_run_id = run.id AND l.actual_start_sim IS NOT NULL
          AND l.leg_type <> ALL (ARRAY['taxi','stage','depart']) GROUP BY 1)
SELECT COALESCE(arr.tick, st.tick) AS tick, COALESCE(arrivals,0) AS arrivals,
       COALESCE(starts,0) AS service_starts
  FROM arr FULL JOIN st ON arr.tick = st.tick ORDER BY 1;

-- §5 — utilisation over 24h AND over each resource's own active window.
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id),
inv AS (SELECT s.stall_type, count(*) AS stalls FROM stalls s
         WHERE s.depot_id = (SELECT depot_id FROM ottoq_sim_runs, run WHERE sim_run_id = run.id)
         GROUP BY 1),
busy AS (SELECT s.stall_type,
                sum(EXTRACT(epoch FROM l.actual_end_sim - l.actual_start_sim))/3600.0 AS stall_hours,
                min(l.actual_start_sim) AS first_start, max(l.actual_end_sim) AS last_end
           FROM ottoq_itinerary_legs l JOIN stalls s ON s.id = l.to_stall_id, run
          WHERE l.sim_run_id = run.id AND l.status='done'
            AND l.actual_start_sim IS NOT NULL AND l.actual_end_sim IS NOT NULL
            AND l.leg_type <> ALL (ARRAY['taxi','stage','depart'])
          GROUP BY 1)
SELECT b.stall_type, i.stalls, round(b.stall_hours::numeric,1) AS stall_hours_used,
       round((b.stall_hours/(i.stalls*24.0)*100)::numeric,1) AS util_24h_pct,
       round((EXTRACT(epoch FROM b.last_end-b.first_start)/3600.0)::numeric,1) AS active_window_h,
       round((b.stall_hours/(i.stalls*GREATEST(EXTRACT(epoch FROM b.last_end-b.first_start)/3600.0,0.01))*100)::numeric,1) AS util_active_pct
  FROM busy b JOIN inv i USING (stall_type) ORDER BY util_active_pct DESC;
