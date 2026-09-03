-- 0170  "Unserved" counted the horizon, not the engine. KPI only; forces_recert = false.
--
-- 0167 gave returns_unserved its first honest definition: an asset that returned
-- and had no service operation go ACTIVE afterwards. Across the last 25 runs it
-- reported 32, and 0079 §4 called that a finding with an unidentified cause.
--
-- It is not a finding about the engine. Diagnosed in db/checks/0080 and §1 below,
-- ALL 32 are artefacts of the run horizon, in two kinds:
--
--   16  arrived on the run's FINAL TICK. A 12-tick run starting 02:00 ends at
--       08:00; an asset arriving at 08:00 has no tick left to be served in.
--   16  had their work PLANNED BEYOND the run's end - 16 of 16, average 330
--       minutes after arrival, against a 6-hour run.
--
-- The contrast with served returns is what settles it:
--
--                    work planned inside horizon   avg minutes return -> planned
--   served (2894)          2886  (99.7%)                    66
--   unserved (16)             0  (0%)                      330
--
-- Perfect separation and a 5x difference in lead time. These assets were not
-- failed by the scheduler; their work was scheduled for later than the run
-- lasted, and the run stopped first. The genuine stranding count over the last
-- 25 runs is ZERO.
--
-- A KPI that grows when you SHORTEN the run is measuring the instrument, not the
-- system - exactly what p95_time_to_service was doing before 0167 when it could
-- only ever return 0. Same defect, same fix: measure what the engine was
-- actually asked to do.
--
-- returns_unserved now counts only assets whose work was DUE inside the horizon
-- and did not happen. The horizon cases are not hidden - they move to
-- returns_deferred_beyond_horizon, a new column, so the total is still
-- reconstructable and a reader can see the split rather than take the smaller
-- number on trust.
--
-- The horizon marker is ottoq_sim_runs.sim_clock_current - where the run
-- actually reached (08:00 for a 12-tick run, 14:00 for 24). NOT sim_clock_end,
-- which is a nominal 24-hour marker reading 09-02 02:00 on every run above and
-- would classify nothing as beyond the horizon.
--
-- Column ORDER is fixed by the pre-0167 view: CREATE OR REPLACE VIEW may append
-- but may not rename or reorder. returns_unserved keeps its name and position
-- and changes meaning; the new column goes on the end.

CREATE OR REPLACE VIEW public.ottoq_kpi_p95_time_to_service AS
WITH pairs AS (
  SELECT d.dispatch_id,
         d.sim_run_id,
         d.actual_return_at,
         r.sim_clock_current AS run_reached,
         min(l.actual_start_sim) FILTER (WHERE l.actual_start_sim >= d.actual_return_at)
           AS first_op_active_at,
         -- the earliest work this asset was PLANNED to receive, service only
         min(l.planned_start_sim) AS first_work_planned_at
    FROM ottoq_vehicle_dispatches d
    JOIN ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
    LEFT JOIN ottoq_itinerary_legs l
      ON  l.sim_run_id = d.sim_run_id
      AND l.vehicle_id = d.vehicle_id
      AND l.leg_type NOT IN ('taxi','stage')   -- moves and parking are not service
   WHERE d.actual_return_at IS NOT NULL
   GROUP BY d.dispatch_id, d.sim_run_id, d.actual_return_at, r.sim_clock_current
)
SELECT sim_run_id,
       round(percentile_cont(0.95) WITHIN GROUP (
         ORDER BY EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS p95_time_to_service_min,
       count(*) FILTER (WHERE first_op_active_at IS NOT NULL) AS returns_measured,
       -- 0170: owed INSIDE the horizon and not delivered. A NULL plan means
       -- nothing was owed at all, which is not a failure either.
       count(*) FILTER (WHERE first_op_active_at IS NULL
                          AND first_work_planned_at IS NOT NULL
                          AND first_work_planned_at < run_reached) AS returns_unserved,
       round(percentile_cont(0.50) WITHIN GROUP (
         ORDER BY EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS p50_time_to_service_min,
       round(max(EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS max_time_to_service_min,
       -- 0170: not a failure - the run ended before the work was due. Kept
       -- visible so the old total is still reconstructable.
       count(*) FILTER (WHERE first_op_active_at IS NULL
                          AND (first_work_planned_at IS NULL
                               OR first_work_planned_at >= run_reached))
         AS returns_deferred_beyond_horizon
  FROM pairs
 GROUP BY sim_run_id;

COMMENT ON VIEW public.ottoq_kpi_p95_time_to_service IS
  'CLAUDE.md 2.9 KPI 5: recall-complete -> first op ACTIVE, measured on ottoq_itinerary_legs.actual_start_sim (the physical start), never the calendar claim (0167). Set-based since 0168. Since 0170 returns_unserved counts only work DUE inside the run horizon; work planned past the run end is returns_deferred_beyond_horizon, which is a property of the horizon and not of the engine.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('unserved_counted_the_horizon_not_the_engine', false,
        'KPI only. returns_unserved excludes assets whose work was planned beyond the run horizon - all 32 such cases over the last 25 runs, leaving a genuine stranding count of zero - and those move to the new returns_deferred_beyond_horizon column so the split stays visible. No engine function is touched.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
