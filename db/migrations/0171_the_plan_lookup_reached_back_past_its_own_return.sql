-- 0171  The plan lookup reached back past its own return. KPI only; forces_recert = false.
--
-- 0170 stated a prediction so it could be falsified, and it was. Predicted after
-- applying: returns_unserved 0, returns_deferred_beyond_horizon 32 across the
-- last 25 runs. Measured: 12 and 20. The total reconstructed correctly, so the
-- split was wrong, not the accounting.
--
-- CAUSE. 0170 computed
--
--   min(l.planned_start_sim) AS first_work_planned_at
--
-- over every service leg of the VEHICLE in the run, with no lower bound - while
-- the aggregate directly above it, first_op_active_at, is correctly bounded by
--
--   FILTER (WHERE l.actual_start_sim >= d.actual_return_at)
--
-- The row being described is a DISPATCH - one return - not a vehicle. A vehicle
-- that returns twice in a run has two rows, and the second one inherited the
-- first one's plan timestamp, which naturally predates it and so read as "work
-- was due inside the horizon and never happened."
--
-- Measured on the 12 misclassified rows: 12 of 12 are vehicles with more than
-- one return, 12 of 12 have a plan timestamp predating the return being
-- described, and 12 of 12 have NO planned work at all after that return. Nothing
-- was owed to them; they were counted as failures anyway.
--
-- This is the third time today I have written an aggregate that reaches past the
-- entity it describes: the 0078 §5.3 query read vehicles.current_state (live
-- shared state) to characterise one run, db/checks/0080 §4.4 records the same
-- reflex catching me mid-diagnosis, and now this. It is the family 0145 and 0146
-- fixed in the engine - a read that is not scoped to the thing it is about.
-- The engine's version was harder to see; mine keep being one FILTER clause.
--
-- FIX. Bound the plan lookup by the same return that bounds the activity lookup.
-- Nothing else changes.

CREATE OR REPLACE VIEW public.ottoq_kpi_p95_time_to_service AS
WITH pairs AS (
  SELECT d.dispatch_id,
         d.sim_run_id,
         d.actual_return_at,
         r.sim_clock_current AS run_reached,
         min(l.actual_start_sim)  FILTER (WHERE l.actual_start_sim  >= d.actual_return_at)
           AS first_op_active_at,
         -- 0171: bounded by THIS return, exactly as first_op_active_at is.
         min(l.planned_start_sim) FILTER (WHERE l.planned_start_sim >= d.actual_return_at)
           AS first_work_planned_at
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
       count(*) FILTER (WHERE first_op_active_at IS NULL
                          AND first_work_planned_at IS NOT NULL
                          AND first_work_planned_at < run_reached) AS returns_unserved,
       round(percentile_cont(0.50) WITHIN GROUP (
         ORDER BY EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS p50_time_to_service_min,
       round(max(EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS max_time_to_service_min,
       count(*) FILTER (WHERE first_op_active_at IS NULL
                          AND (first_work_planned_at IS NULL
                               OR first_work_planned_at >= run_reached))
         AS returns_deferred_beyond_horizon
  FROM pairs
 GROUP BY sim_run_id;

COMMENT ON VIEW public.ottoq_kpi_p95_time_to_service IS
  'CLAUDE.md 2.9 KPI 5: recall-complete -> first op ACTIVE, measured on ottoq_itinerary_legs.actual_start_sim (the physical start), never the calendar claim (0167). Set-based since 0168. returns_unserved counts only work DUE inside the run horizon (0170); work planned past the run end is returns_deferred_beyond_horizon. Both plan and activity lookups are bounded by the return they describe (0171) - a vehicle returning twice in a run must not inherit its earlier return''s plan.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_plan_lookup_reached_back_past_its_own_return', false,
        'KPI only. 0170''s plan lookup was unbounded and a vehicle''s second return inherited its first return''s planned_start_sim, misclassifying 12 rows as unserved when nothing was owed after that return. Bounded by the return, matching the activity lookup beside it. Found because 0170 published a falsifiable prediction and missed it.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
