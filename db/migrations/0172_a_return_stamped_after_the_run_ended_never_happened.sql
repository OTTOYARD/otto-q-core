-- 0172  A return stamped after the run ended never happened. KPI only; forces_recert = false.
--
-- The 48-tick pair (sim_run_seq 1773/1774) reported returns_deferred_beyond_horizon = 7
-- when a longer horizon should contain MORE of the plan and defer LESS. Chasing
-- that discrepancy instead of explaining it away found phantom returns.
--
-- All 7 carried actual_return_at = 2026-09-02 23:55 UTC on a run whose sim clock
-- reached 2026-09-02 02:00 - a return stamped nearly 22 hours after the run
-- ended. The timestamps identify themselves:
--
--   pair            fired (wall clock UTC)   latest actual_return_at   phantom rows
--   1773/1774 48t   09-03 00:07 / 00:21          09-02 23:55                7
--   1769/1770 24t   09-02 23:06 / 23:13          09-02 23:01                3
--   1771/1772 24t   09-02 23:22 / 23:29          09-01 11:00                0
--   1765..1768 12t  09-02 22:40 - 22:56          09-01 06:30 / 07:30        0
--
-- 09-02 23:55 is exactly when the h48 job fired. 09-02 23:01 is exactly when the
-- 6:01 PM CT pair fired. This is transaction now() landing in a SIM-CLOCK column
-- - twin.ottoq_sim_seed_fleet carries
--     actual_return_at = COALESCE(actual_return_at, NOW())
-- and the count grows with horizon (0 at 12 ticks, 3 at 24, 7 at 48) because a
-- longer run leaves more assets still deployed when it stops.
--
-- WHY THE PAIR HARNESS CANNOT SEE IT: ottoq_determinism_pair runs both arms in
-- ONE transaction, and now() is transaction start time in Postgres - constant
-- across both arms. A wall-clock leak that would differ between two separately
-- fired runs is pinned to a single value inside a pair, so it can never make the
-- arms disagree. Same family as 0137 and 0143; new in that the harness's own
-- single-transaction design is what conceals it.
--
-- WHAT THIS IS NOT. It is not a determinism defect, and the evidence says so
-- rather than the argument: the busy_day/171717/24t canons reproduced EXACTLY
-- across pairs fired at 4:40 PM and 6:01 PM CT (ec5c38aa / 8221f656 / 096b099e /
-- da9c269c, db/canons/round8.md), with different wall clocks and therefore
-- different now() values. The fingerprint already ignores this column - the
-- id-and-timestamp-blindness 0137 and 0139 built. Certification is unaffected
-- and no canon needs re-taking.
--
-- What it does pollute is the KPI, which reads actual_return_at directly. Seven
-- assets that never returned inside the run were counted as returns and filed
-- as deferred.
--
-- FIX HERE (KPI): a dispatch whose return is stamped after the run's clock did
-- not return during the run. It is not served, not unserved, not deferred - it
-- is not a return. Excluded.
--
-- FIX NOT HERE (twin): twin.ottoq_sim_seed_fleet should stamp the sim clock, not
-- NOW(). That is a twin change, it moves seeded world state, and it therefore
-- needs forces_recert = true and its own round. Recorded in db/checks/0082 as
-- the next round's work rather than smuggled in beside a view change.

CREATE OR REPLACE VIEW public.ottoq_kpi_p95_time_to_service AS
WITH pairs AS (
  SELECT d.dispatch_id,
         d.sim_run_id,
         d.actual_return_at,
         r.sim_clock_current AS run_reached,
         min(l.actual_start_sim)  FILTER (WHERE l.actual_start_sim  >= d.actual_return_at)
           AS first_op_active_at,
         min(l.planned_start_sim) FILTER (WHERE l.planned_start_sim >= d.actual_return_at)
           AS first_work_planned_at
    FROM ottoq_vehicle_dispatches d
    JOIN ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
    LEFT JOIN ottoq_itinerary_legs l
      ON  l.sim_run_id = d.sim_run_id
      AND l.vehicle_id = d.vehicle_id
      AND l.leg_type NOT IN ('taxi','stage')
   WHERE d.actual_return_at IS NOT NULL
     -- 0172: a return stamped after the run's clock did not happen in the run.
     AND d.actual_return_at <= r.sim_clock_current
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
  'CLAUDE.md 2.9 KPI 5: recall-complete -> first op ACTIVE, on ottoq_itinerary_legs.actual_start_sim (0167). Set-based (0168). returns_unserved is work DUE inside the horizon and not delivered; work planned past the run end is returns_deferred_beyond_horizon (0170). Plan and activity lookups are bounded by the return they describe (0171). Dispatches whose actual_return_at postdates the run clock are excluded - they never returned in-run; twin.ottoq_sim_seed_fleet stamps NOW() there (0172).';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_return_stamped_after_the_run_ended_never_happened', false,
        'KPI only. Excludes dispatches whose actual_return_at postdates the run''s sim clock - transaction now() leaking from twin.ottoq_sim_seed_fleet into a sim-clock column, 0 rows at 12 ticks, 3 at 24, 7 at 48. Not a determinism defect: the 24-tick canons reproduced exactly across pairs fired 81 minutes apart, so the fingerprint already ignores the column. The twin-side fix belongs to its own forces_recert round.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
