-- =====================================================================
-- 0092  The KPI that reported more hours than the window could hold
-- =====================================================================
-- Run 2026-09-03 CT, after 0181 and 0182. Everything below is measured;
-- the SQL that produced each number is inline.
--
-- SECTION 1 — THE NUMBER THAT STARTED IT
-- ---------------------------------------------------------------------
-- Grid-fixture certification pair cebe53e1 / 61af80b0.
--   sim window   2026-09-01 02:00 -> 05:00   (3.00 h)
--   assets       4
--   ceiling      4 x 3 = 12 asset-hours
--   KPI 1 said   141.02
--
-- 11.75x the maximum the world could physically produce. Both arms
-- reported 141.02 to the hundredth, which is the diagnostic tell: the
-- error is SHARED, not random, so no equality check between arms could
-- ever have seen it.
--
-- SECTION 2 — THE WRITE (0181)
-- ---------------------------------------------------------------------
-- public.ottoq_sim_release_depot, the run finalizer:
--
--   UPDATE ottoq_vehicle_dispatches
--      SET status='completed',
--          actual_return_at = COALESCE(actual_return_at, now()),
--          return_trigger   = COALESCE(return_trigger, 'run_stopped')
--    WHERE sim_run_id = p_sim_run_id AND status IN ('active','returning');
--
-- The four dispatches on cebe53e1, read before the fix:
--
--   wash_cadence        sched 03:00  actual 09-01 03:00        <- sim clock
--   surplus_to_demand   sched 04:30  actual 09-01 04:30        <- sim clock
--   overnight_prestage  sched 05:30  actual 09-03 21:55:54.346204
--   overnight_prestage  sched 05:30  actual 09-03 21:55:54.346204
--
-- 2026-09-03 21:55:54.346204 is ottoq_sim_runs.started_at for that run,
-- to the microsecond. Both dispatches whose scheduled return fell past
-- the horizon (05:30 > 05:00) were still 'active' at teardown, so the
-- finalizer marked them 'completed' and stamped the wall clock.
--
-- Two defects in one statement:
--   (a) STATUS. A dispatch still out when the run stopped did not come
--       home. 'completed' is a claim the run has no evidence for.
--   (b) CLOCK. now() is not the run's clock, so the row cannot
--       regenerate from a seed.
--
-- The same function already gets both right six statements above, on
-- itinerary legs: status 'amended' (never 'done'), actual_end_sim from
-- sim_clock_current. And twin.ottoq_sim_seed_fleet already used status
-- 'aborted' for exactly this case, with the comment "superseded-run
-- leftovers never actually returned: abort, don't complete." The reseed
-- path was right; the teardown path was wrong. 0181 makes them agree.
--
-- SECTION 3 — WHY THE DETERMINISM PAIR IS BLIND TO THIS BY CONSTRUCTION
-- ---------------------------------------------------------------------
-- Worth recording as a limit of the instrument, not of this defect.
--
-- endst DOES cover the column. ottoq_boot_state_fingerprint's `dp` CTE
-- hashes whole dispatch rows minus only dispatch_id / sim_run_id /
-- created_at / the correlation id - actual_return_at, status and
-- return_trigger are all inside that md5. Coverage was never the issue.
--
-- ottoq_determinism_pair runs BOTH ARMS IN ONE TRANSACTION, and now() in
-- Postgres is transaction start time. So arm A and arm B are stamped
-- with the IDENTICAL wall clock and every hash agrees. Confirmed on the
-- rows: cebe53e1 and 61af80b0 both carry started_at
-- 2026-09-03 21:55:54.346204 - two runs, one transaction.
--
--   A WALL-CLOCK LEAK INSIDE THE PAIR'S OWN TRANSACTION IS INVISIBLE TO
--   THE PAIR NO MATTER WHICH CANON COVERS IT.
--
-- Only inter-ROUND comparison can catch this class. That is also the
-- evidence behind 0181's forces_recert=false: endst carries this column
-- and reproduced byte-identically across rounds 11 and 12, hours apart -
-- impossible unless the teardown write lands after the fingerprint.
--
-- SECTION 4 — THE READER (0182)
-- ---------------------------------------------------------------------
-- KPI 1 never joined ottoq_sim_runs, so it had no horizon at all:
--
--   sum(COALESCE(actual_return_at, scheduled_return_at) - dispatched_at)
--
-- Three leaks, all four dispatches showing all three:
--   (1) wall-clock ends            -> 0181's defect
--   (2) scheduled_return_at 05:30  -> 30 min past a horizon of 05:00
--   (3) dispatched_at ~01:2x-01:4x -> before sim_clock_start 02:00; the
--                                     deployment prime asserting a
--                                     starting world, not observed time
--
-- (1) and (2) are the horizon-artifact class 0170/0172/0176/0178. (3) is
-- the same rule read backwards: a run may not be judged on what happened
-- before it began either.
--
-- 0182 credits only the overlap with [sim_clock_start, sim_clock_current],
-- clamped at zero, and appends four columns so the clamp is auditable:
-- horizon, horizon_source, hours_clipped_to_window,
-- dispatches_open_at_horizon. hours_clipped_to_window = 0 means the
-- number is unchanged from the old formula.
--
-- SECTION 5 — MEASURED RESULT
-- ---------------------------------------------------------------------
-- 5a. The pair that started it, recomputed (no rows were mutated):
--
--   SELECT sim_run_id, asset_hours_available, hours_clipped_to_window,
--          horizon, horizon_source
--     FROM public.ottoq_kpi_asset_hours_available_per_day
--    WHERE sim_run_id IN ('cebe53e1-3c55-4699-ae20-701bbcbb3561',
--                         '61af80b0-1f01-4266-bd6d-8a1c825fd1b6');
--
--   both arms:  9.50 h   clipped 131.52   horizon 09-01 05:00   run_horizon
--   against the 12.00 ceiling. Was 141.02.
--
-- 5b. THE SWEEP - is the fix general, or tuned to one run? 587 runs with
--     a well-formed window, each compared to its own assets x hours
--     ceiling:
--
--       runs_scored            587
--       over_ceiling_before     16
--       over_ceiling_after       1
--       worst_ratio_before   11.75x
--       worst_ratio_after     1.00x
--       total_hours_clipped  41692.1
--
--     The one remaining is not a leak and was chased down rather than
--     rounded past: run f653bef9, 44 assets, window 0.0963 h, ceiling
--     4.2364, reported 4.24 - an excess of 0.003585 h = 12.9 seconds.
--     asset_hours_available is round(...,2), i.e. 18-second granularity,
--     so a value pinned exactly at the ceiling can round up past it by
--     up to 18 s. Bounded, explainable, and a property of the display
--     rounding rather than the arithmetic.
--
-- 5c. THE FIX, EXERCISED LIVE. twin.ottoq_grid_smoke(424242, 6,
--     'grid-0169-smoke', 'grid_smoke') - 11.0 s, all 16 checks passed,
--     including pair_verdict_passed (outcome=passed, equal=true), so the
--     teardown change did not break teardown and the arms still agree.
--     Its two fresh runs, 05d1cf98 and d2f80255:
--
--       dispatches                4     each
--       status 'aborted'          2     (still out at the horizon)
--       status 'completed'        2     (returned inside the window)
--       actual_return_at past horizon   0
--       KPI 1                     9.50 h,  clipped 2.66
--
--     Clip fell 131.52 -> 2.66: what remains is the legitimate horizon
--     and prime clamp, no longer a wall clock.
--
-- 5d. THE STANDING INVARIANT, whole table:
--
--       aborted rows                          4
--       aborted rows carrying a return time   0
--       past-horizon rows, all history      345
--       past-horizon rows since 0181          0
--
--     345 historical rows carry a return time past their run's horizon.
--     They are NOT backfilled, deliberately: db/canons/README.md forbids
--     rewriting a point-in-time record, and 0182 makes the KPI correct
--     over them without mutating them. Fixing the reader rather than
--     editing the ledger is the right shape, and 5a proves it works -
--     cebe53e1 now reports 9.50 with its original rows untouched.
--
-- SECTION 6 — A FALSE NEGATIVE THIS WOULD HAVE PLANTED
-- ---------------------------------------------------------------------
-- The finalizer sets return_trigger = COALESCE(return_trigger,
-- 'run_stopped'). Both aborted dispatches on the fresh runs already
-- carried a trigger from dispatch time ('overnight_prestage'), so the
-- COALESCE kept it and:
--
--   run_stopped rows = 0   while   aborted rows = 2
--
-- Keeping the original trigger is correct - it is real data and the
-- finalizer should not overwrite it - but it means
-- return_trigger='run_stopped' is NOT the marker for "this run cut the
-- dispatch short." STATUS IS. Anyone auditing by trigger will conclude
-- it never happens. Same family as 0062's comment-grep and 0066 section
-- 6: a query whose shape guarantees the answer it finds.
--
-- SECTION 7 — 0066 SECTION 5, CLOSED
-- ---------------------------------------------------------------------
-- twin.ottoq_sim_seed_fleet's reseed abort had no sim-domain guard while
-- the ocpp_sessions reset four lines below it is twin-only by token
-- convention (cs.id_token LIKE 'TWIN-%', verified in source). So a depot
-- reseed would have aborted a PRODUCTION dispatch - sim_run_id IS NULL -
-- for any vehicle homed at that depot.
--
-- Exposure measured before the fix, and this corrects a sharper framing
-- given earlier in this campaign: the table holds 66,754 dispatch rows
-- and 0 of them are production. There was no production dispatch to
-- harm. The mechanism was real; the blast radius was empty - the same
-- standing as 0066 section 4, not a live defect.
--
-- 0181 adds `AND d.sim_run_id IS NOT NULL` to both overloads anyway,
-- because the vehicle and asset feeds that will write those rows are the
-- next thing to land. A guard added before the first real row is a
-- guard; added after, it is an incident report.
--
-- SECTION 8 — WHAT IS NOT CLAIMED
-- ---------------------------------------------------------------------
-- - 0181's prediction (all six certification columns reproduce round 12
--   exactly) is PUBLISHED, NOT YET VERIFIED. It needs a full round. The
--   grid smoke in 5c is one 6-tick fixture pair, not the six-column
--   matrix, and does not test it.
-- - The four diagnostic columns do NOT reach ottoq_kpi_five, which
--   projects only day -> asset_hours_available. A correction invisible
--   from the one command that ships the number is half a fix. That is
--   the next migration, and it changes the run-ID payload shape.
-- - The other four canonical KPIs were not audited for the same class.
--   KPI 5 (p95_time_to_service) is known to gate actual_return_at <=
--   sim_clock_current, so it dropped the bad rows instead of eating
--   them - a different wrong answer from the same write, and its
--   denominator over the 345 historical rows has not been re-examined.
-- =====================================================================

-- 5a — the pair that started it
SELECT sim_run_id, asset_hours_available, hours_clipped_to_window, horizon, horizon_source
  FROM public.ottoq_kpi_asset_hours_available_per_day
 WHERE sim_run_id IN ('cebe53e1-3c55-4699-ae20-701bbcbb3561',
                      '61af80b0-1f01-4266-bd6d-8a1c825fd1b6');

-- 5b — the sweep: every run against its own ceiling
WITH per_run AS (
  SELECT k.sim_run_id,
         sum(k.asset_hours_available)   AS hours_now,
         sum(k.hours_clipped_to_window) AS hours_clipped,
         max(k.assets_counted)          AS assets,
         EXTRACT(epoch FROM r.sim_clock_current - r.sim_clock_start)/3600.0 AS win_h
    FROM public.ottoq_kpi_asset_hours_available_per_day k
    JOIN public.ottoq_sim_runs r USING (sim_run_id)
   WHERE r.sim_clock_current > r.sim_clock_start
   GROUP BY k.sim_run_id, r.sim_clock_start, r.sim_clock_current
)
SELECT count(*)                                                         AS runs_scored,
       count(*) FILTER (WHERE hours_now + hours_clipped > assets*win_h) AS over_ceiling_before,
       count(*) FILTER (WHERE hours_now                > assets*win_h)  AS over_ceiling_after,
       round(max((hours_now+hours_clipped)/NULLIF(assets*win_h,0)),2)   AS worst_ratio_before,
       round(max( hours_now              /NULLIF(assets*win_h,0)),2)    AS worst_ratio_after,
       round(sum(hours_clipped),1)                                      AS total_hours_clipped
  FROM per_run;

-- 5c — the fix exercised live (11.0 s, 16 of 16 passed)
SELECT * FROM twin.ottoq_grid_smoke(424242, 6, 'grid-0169-smoke', 'grid_smoke');

-- 5d — the standing invariant. past_horizon_since_0181 must stay 0.
SELECT count(*) FILTER (WHERE d.status='aborted')                                    AS aborted_total,
       count(*) FILTER (WHERE d.status='aborted' AND d.actual_return_at IS NOT NULL)  AS aborted_with_a_return_time,
       count(*) FILTER (WHERE d.actual_return_at > r.sim_clock_current)               AS past_horizon_all_history,
       count(*) FILTER (WHERE d.actual_return_at > r.sim_clock_current
                          AND r.started_at > (SELECT max(classified_at) FROM public.ottoq_cert_lineage
                                               WHERE name='the_teardown_recorded_a_return_that_never_happened'))
                                                                                      AS past_horizon_since_0181,
       count(*) FILTER (WHERE d.sim_run_id IS NULL)                                   AS production_rows
  FROM public.ottoq_vehicle_dispatches d
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id;
