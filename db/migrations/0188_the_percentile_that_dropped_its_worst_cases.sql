-- =====================================================================
-- 0188  The percentile that dropped its worst cases
-- =====================================================================
-- forces_recert = FALSE. View only; sole reader ottoq_kpi_five.
-- KPI 5 is the last of the five this campaign had not audited.
--
-- THE NUMBER
-- ---------------------------------------------------------------------
-- Run 9291ec6d: 94 dispatches. Fifty of them carry a return time past the
-- run's horizon and are dropped from the population. KPI 5 publishes
--
--   p95_time_to_service_min   1.2      returns_measured   21
--
-- A p95 of 1.2 minutes is an excellent number. It is computed over 21 of
-- that run's 94 dispatches, and the ones that did not make it in are
-- exactly those STILL OUT when the run ended - the dispatches most likely
-- to have had a long time-to-service, or none at all. Removing them
-- cannot raise the percentile. It can only lower it.
--
-- The KPI looks good BECAUSE its worst cases were removed. Same shape as
-- 0182, 0183 and 0184, by a different route: not a wrong formula, a
-- silently trimmed population.
--
-- THE EXCLUSION IS CORRECT. ITS INVISIBILITY IS NOT.
-- ---------------------------------------------------------------------
-- The `pairs` CTE gates
--   d.actual_return_at IS NOT NULL AND d.actual_return_at <= r.sim_clock_current
-- and that gate is right: a dispatch that never came home has no
-- time-to-service, and inventing one would be worse. After 0181 such a
-- dispatch carries actual_return_at NULL and is excluded for the honest
-- reason rather than the wall-clock one - but still excluded.
--
-- What is missing is any way to SEE the exclusion. returns_unserved and
-- returns_deferred_beyond_horizon count only rows already inside `pairs`;
-- by construction neither can ever account for a dispatch that never
-- entered it. A reader sees returns_measured = 21 and has no way to learn
-- that 94 dispatches existed.
--
-- Measured across all 601 runs with a horizon:
--
--   runs                                              601
--   runs with at least one past-horizon dispatch       52
--   dispatches dropped by the horizon gate            345   (0.51%)
--   worst single run                               100.0%   dropped
--
-- Four runs have EVERY dispatch dropped - b54929ce (91), f653bef9 (44),
-- 3eeb5dc5 (25), e8a0ba01 (12). Those runs do not appear in the view at
-- all, so ottoq_kpi_five reports p95 null for them. Null is the honest
-- value, but it arrives silently: nothing distinguishes "this run had 91
-- dispatches and not one could be measured" from "this run had none".
--
-- THE FIX
-- ---------------------------------------------------------------------
-- Four columns appended - the 0182 / 0183 / 0184 / 0185 pattern:
--
--   dispatches_total                  the run's actual dispatch count
--   dispatches_admitted               what the percentile is computed over
--   dispatches_never_returned         actual_return_at IS NULL (post-0181)
--   dispatches_returned_past_horizon  the 0181 residue (pre-0181 rows)
--
-- and the view is driven from the per-run totals rather than from
-- `pairs`, so a run whose entire population was excluded APPEARS, with a
-- NULL percentile and a stated dispatches_total, instead of vanishing.
--
-- p95, p50 and max stay NULL when nothing was admitted: a percentile over
-- an empty set is undefined, not zero. The counts COALESCE to 0, because
-- "zero returns measured" is a fact and NULL there would be a second
-- silence.
--
-- CHANGES FOR EXISTING CONSUMERS, stated rather than discovered later:
-- the four runs above previously returned NULL for returns_unserved
-- through ottoq_kpi_five and now return 0. Every other run is unchanged -
-- the check is a checksum over the seven original columns of all 597
-- pre-existing rows, e6c7983378589856da7f66ca53398fab.
--
-- NOT FIXED HERE: the plan for this view does an Index Scan on
-- ottoq_itinerary_legs by vehicle_id with sim_run_id applied as a filter
-- afterwards, discarding 3,065 rows per loop across 118 loops - 356 ms
-- per read, and ottoq_kpi_five reads it four times. A composite
-- (sim_run_id, vehicle_id) index would fix it. Different table, different
-- index decision, and 0187 showed what happens when an index question is
-- settled in a hurry.
-- =====================================================================

CREATE OR REPLACE VIEW public.ottoq_kpi_p95_time_to_service AS
WITH tot AS (
  -- 0188: the run's ACTUAL population, admitted or not. This drives the
  -- view so a run whose whole population was excluded still appears.
  SELECT d.sim_run_id,
         count(*)                                                          AS dispatches_total,
         count(*) FILTER (WHERE d.actual_return_at IS NULL)                AS dispatches_never_returned,
         count(*) FILTER (WHERE d.actual_return_at > r.sim_clock_current)  AS dispatches_returned_past_horizon,
         count(*) FILTER (WHERE d.actual_return_at IS NOT NULL
                            AND d.actual_return_at <= r.sim_clock_current) AS dispatches_admitted
    FROM ottoq_vehicle_dispatches d
    JOIN ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
   GROUP BY d.sim_run_id
), pairs AS (
  SELECT d.dispatch_id,
         d.sim_run_id,
         d.actual_return_at,
         r.sim_clock_current AS run_reached,
         min(l.actual_start_sim)  FILTER (WHERE l.actual_start_sim  >= d.actual_return_at) AS first_op_active_at,
         min(l.planned_start_sim) FILTER (WHERE l.planned_start_sim >= d.actual_return_at) AS first_work_planned_at
    FROM ottoq_vehicle_dispatches d
    JOIN ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
    LEFT JOIN ottoq_itinerary_legs l
           ON l.sim_run_id = d.sim_run_id AND l.vehicle_id = d.vehicle_id
          AND (l.leg_type <> ALL (ARRAY['taxi'::text, 'stage'::text]))
   WHERE d.actual_return_at IS NOT NULL AND d.actual_return_at <= r.sim_clock_current
   GROUP BY d.dispatch_id, d.sim_run_id, d.actual_return_at, r.sim_clock_current
), agg AS (
  SELECT sim_run_id,
         round(percentile_cont(0.95::double precision) WITHIN GROUP (ORDER BY ((EXTRACT(epoch FROM first_op_active_at - actual_return_at) / 60.0)::double precision))::numeric, 1) AS p95,
         count(*) FILTER (WHERE first_op_active_at IS NOT NULL) AS measured,
         count(*) FILTER (WHERE first_op_active_at IS NULL AND first_work_planned_at IS NOT NULL
                            AND first_work_planned_at < run_reached)                       AS unserved,
         round(percentile_cont(0.50::double precision) WITHIN GROUP (ORDER BY ((EXTRACT(epoch FROM first_op_active_at - actual_return_at) / 60.0)::double precision))::numeric, 1) AS p50,
         round(max(EXTRACT(epoch FROM first_op_active_at - actual_return_at) / 60.0), 1)   AS max_min,
         count(*) FILTER (WHERE first_op_active_at IS NULL
                            AND (first_work_planned_at IS NULL OR first_work_planned_at >= run_reached)) AS deferred
    FROM pairs GROUP BY sim_run_id
)
SELECT
  t.sim_run_id,
  a.p95                        AS p95_time_to_service_min,
  COALESCE(a.measured, 0)      AS returns_measured,
  COALESCE(a.unserved, 0)      AS returns_unserved,
  a.p50                        AS p50_time_to_service_min,
  a.max_min                    AS max_time_to_service_min,
  COALESCE(a.deferred, 0)      AS returns_deferred_beyond_horizon,
  -- 0188: the population the percentile was drawn FROM. Without these, a
  -- p95 of 1.2 min over 21 of 94 dispatches is indistinguishable from a
  -- p95 of 1.2 min over all of them.
  t.dispatches_total,
  t.dispatches_admitted,
  t.dispatches_never_returned,
  t.dispatches_returned_past_horizon
FROM tot t LEFT JOIN agg a USING (sim_run_id);

COMMENT ON VIEW public.ottoq_kpi_p95_time_to_service IS
  'Canonical KPI 5 (CLAUDE.md 2.9). Recall-complete to first-op-active, over dispatches that RETURNED WITHIN THE RUN WINDOW. 0188: that exclusion is correct - a dispatch that never came home has no time-to-service - but it was invisible, and the excluded dispatches are exactly the ones most likely to have had a long one, so the percentile can only be biased low. Run 9291ec6d published p95 1.2 min over 21 of its 94 dispatches. dispatches_total / dispatches_admitted / dispatches_never_returned / dispatches_returned_past_horizon make the population visible. The view is now driven from per-run totals, so a run whose entire population was excluded appears with a NULL percentile and a stated total instead of vanishing (four such runs exist). p95/p50/max stay NULL when nothing was admitted - a percentile over an empty set is undefined, not zero.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_percentile_that_dropped_its_worst_cases', false,
        'public.ottoq_kpi_p95_time_to_service - canonical KPI 5, the last of the five this campaign had not audited - gates its population on actual_return_at IS NOT NULL AND <= sim_clock_current. The gate is CORRECT: a dispatch that never came home has no time-to-service and inventing one would be worse. Its INVISIBILITY is the defect, and the excluded dispatches are exactly those still out when the run ended, i.e. the ones most likely to have had a long time-to-service or none - so removing them cannot raise the percentile, only lower it. Run 9291ec6d publishes p95 1.2 min with returns_measured 21, computed over 21 of that run 94 dispatches, 50 of which were dropped by the horizon gate. Measured across 601 runs with a horizon: 52 runs have at least one past-horizon dispatch, 345 dispatches dropped in total (0.51 percent), worst single run 100 percent. Four runs have every dispatch dropped (b54929ce 91, f653bef9 44, 3eeb5dc5 25, e8a0ba01 12) and did not appear in the view at all, so ottoq_kpi_five reported p95 null for them - honest but silent, indistinguishable from a run with no dispatches. returns_unserved and returns_deferred_beyond_horizon count only rows already inside the pairs CTE, so by construction neither could ever account for a dispatch that never entered it. Fixed by appending dispatches_total, dispatches_admitted, dispatches_never_returned and dispatches_returned_past_horizon, and by driving the view from per-run totals so an entirely-excluded run appears with a NULL percentile and a stated total. p95/p50/max stay NULL when nothing was admitted because a percentile over an empty set is undefined, not zero; the counts COALESCE to 0 because zero returns measured is a fact and NULL there would be a second silence. Consumer change stated rather than discovered later: those four runs previously returned NULL for returns_unserved through ottoq_kpi_five and now return 0; every other run is unchanged, checked by a checksum over the seven original columns of all 597 pre-existing rows, e6c7983378589856da7f66ca53398fab. Not fixed here: the plan does an Index Scan on ottoq_itinerary_legs by vehicle_id with sim_run_id filtered afterwards, discarding 3065 rows per loop across 118 loops - 356 ms per read and ottoq_kpi_five reads it four times; a composite (sim_run_id, vehicle_id) index would fix it, but that is a different table and 0187 showed what happens when an index question is settled in a hurry. forces_recert=false: view only, sole reader ottoq_kpi_five.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
