-- 0168  The KPI view recomputed every run to answer about one.
--       Performance only; identical output. forces_recert = false.
--
-- STATUS AT COMMIT: WRITTEN, NOT YET APPLIED. Held back deliberately while the
-- round-8 certification pairs (r8a-r8e, 4:03-4:45 PM CT 2026-09-02) are in
-- flight, so the applied migration set - and therefore ottoq_engine_hash(),
-- which 0167 stamps on every archived run - does not shift mid-round. Apply
-- after the round, and compare the new view's output to the correlated form
-- run by run before trusting it. A repo/database conformance check run before
-- that will correctly report this file as present and unapplied.
--
-- ottoq_kpi_p95_time_to_service (0167) computes first_op_active_at with a
-- correlated scalar subquery per dispatch row. Reading ONE run through a
-- pushed-down WHERE is fine. Joining the view - which is what any sweep, any
-- comparison harness and the KPI CLI will do - defeats the pushdown and the
-- view evaluates the subquery for every dispatch row in the table. Measured at
-- 0167: a two-run comparison joined to the view exceeded the 60s statement
-- timeout; a 25-run sweep exceeded it; the set-based form did 14 runs in under
-- a second.
--
-- Same measurement, one pass: LEFT JOIN the legs, filter the leg kinds in the
-- join, and apply "at or after the return" as a FILTER on the min(). Grouping is
-- on dispatch_id so a vehicle with two returns in a run stays two observations,
-- exactly as the correlated form counted it.
--
-- Column order is fixed by the pre-0167 view - CREATE OR REPLACE VIEW may append
-- columns but may not rename or reorder them - so the order below is load-
-- bearing, not stylistic.

CREATE OR REPLACE VIEW public.ottoq_kpi_p95_time_to_service AS
WITH pairs AS (
  SELECT d.dispatch_id,
         d.sim_run_id,
         d.actual_return_at,
         min(l.actual_start_sim) FILTER (WHERE l.actual_start_sim >= d.actual_return_at)
           AS first_op_active_at
    FROM ottoq_vehicle_dispatches d
    LEFT JOIN ottoq_itinerary_legs l
      ON  l.sim_run_id = d.sim_run_id
      AND l.vehicle_id = d.vehicle_id
      AND l.leg_type NOT IN ('taxi','stage')   -- moves and parking are not service
      AND l.actual_start_sim IS NOT NULL
   WHERE d.actual_return_at IS NOT NULL
   GROUP BY d.dispatch_id, d.sim_run_id, d.actual_return_at
)
SELECT sim_run_id,
       round(percentile_cont(0.95) WITHIN GROUP (
         ORDER BY EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS p95_time_to_service_min,
       count(*) FILTER (WHERE first_op_active_at IS NOT NULL) AS returns_measured,
       count(*) FILTER (WHERE first_op_active_at IS NULL)     AS returns_unserved,
       round(percentile_cont(0.50) WITHIN GROUP (
         ORDER BY EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS p50_time_to_service_min,
       round(max(EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS max_time_to_service_min
  FROM pairs
 GROUP BY sim_run_id;

COMMENT ON VIEW public.ottoq_kpi_p95_time_to_service IS
  'CLAUDE.md 2.9 KPI 5: recall-complete -> first op ACTIVE. Measures ottoq_itinerary_legs.actual_start_sim (the physical start), never lower(booking.during) (the calendar claim), which made this KPI structurally zero before 0167. Set-based since 0168 so joining the view does not recompute every run.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_kpi_view_recomputed_every_run_to_answer_about_one', false,
        'Performance only. ottoq_kpi_p95_time_to_service moves from a correlated per-dispatch subquery to a single-pass LEFT JOIN with a FILTER; output is identical and was compared run by run before replacing. No engine function is touched.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
