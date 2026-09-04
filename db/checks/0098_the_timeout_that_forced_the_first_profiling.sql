-- =====================================================================
-- 0098  The timeout that forced the first profiling
-- =====================================================================
-- 0186 closed the day-bucket defect and, in doing so, pushed
-- ottoq_kpi_five past the client's 60 s timeout. That timeout is the
-- reason the CLI got profiled at all. It has been slow since long before
-- tonight and nobody had ever timed it - including me, in the four
-- migrations I shipped through it today.
--
-- SECTION 1 — 0186: THE DAY-BUCKET FIX
-- ---------------------------------------------------------------------
--   buckets earlier than their run's window opens    12  ->  0
--   dispatches_counted                          68,166  ->  68,166
--   view rows                                    1,183  ->  606
--
-- I wrote "run totals unchanged - that is the check" into the migration
-- header. IT IS TOO STRONG and the file was corrected before commit.
-- Measured:
--
--                    exact (unrounded)   before      after
--   hours             93,710.888622    93,710.90   93,710.89
--   hours_clipped     42,678.703525    42,680.51   42,677.93
--
-- The CREDITED QUANTITY is unchanged exactly - the slicing is a partition
-- of [credit_from, credit_to], so the slices sum to the same seconds. The
-- PUBLISHED totals move because the view rounds per bucket and the bucket
-- count fell from 1,183 to 606. Both differences sit inside the rounding
-- envelope, and against the exact value the new view is CLOSER on both:
-- hours drift 0.0014 against 0.0114, clipped 0.77 against 1.81.
--
-- The real checks are the exact quantity, dispatches_counted holding
-- (no double-counting), and 12 -> 0.
--
-- SECTION 2 — WHAT THE TIMEOUT EXPOSED
-- ---------------------------------------------------------------------
--   ottoq_kpi_five(one run)     54,609 ms
--
-- Per view, measured individually with the run filter:
--
--   KPI 1  ottoq_kpi_asset_hours_available_per_day     1.5 ms
--   KPI 2  ottoq_kpi_service_point_turns               4.1 ms
--   KPI 4  ottoq_kpi_touch_events_per_turn        22,330 ms   <--
--   KPI 5  ottoq_kpi_p95_time_to_service             356 ms
--   KPI 3  ottoq_kpi_peak_site_kw                    0.4 ms
--
-- KPI 4's plan named the cause outright:
--
--   Parallel Seq Scan on ottoq_events     Rows Removed by Filter: 1,235,759
--   Parallel Seq Scan on ottoq_decisions  Rows Removed by Filter:   666,590
--   Join Filter: (NOT (e.sim_run_id IS DISTINCT FROM b.sim_run_id))
--
-- The view joined its aggregate CTEs with IS NOT DISTINCT FROM so a
-- production row (sim_run_id NULL) would match. The planner cannot
-- propagate a run filter through that operator, so the filter reached
-- ottoq_stall_bookings by index and NOT the other two tables. Both were
-- scanned in full, on every call, for every run.
--
-- ATTRIBUTION, honestly. 0186 was the TRIGGER, not the cause. But 0185 IS
-- partly responsible and that is mine: surfacing the audit block added a
-- SECOND read of KPI 4, taking the CLI from about one 22 s scan to two.
-- A 2x regression on top of a 22 s defect I had not measured.
--
-- Also recorded: ottoq_events holds ~2.49M rows. CLAUDE.md Part 3 says
-- 20,799, true at the 2026-08-18 pull and now two orders of magnitude
-- stale. A view that scans the whole table gets worse every day the twin
-- runs, which is why this was survivable a month ago and is not now.
--
-- SECTION 3 — 0187, AND WHY THE OBVIOUS FIX IS NOT ENOUGH
-- ---------------------------------------------------------------------
-- Suitable indexes existed the whole time and were unreachable:
--   ottoq_events_keep_sim_run_id_idx (sim_run_id) WHERE sim_run_id IS NOT NULL
--   idx_decisions_run_tick           (sim_run_id, tick_seq)
--
-- Rewriting as (a = b OR (a IS NULL AND b IS NULL)) fixes
-- ottoq_decisions - bitmap index scan - but NOT ottoq_events, whose index
-- is PARTIAL on sim_run_id IS NOT NULL, so an OR-branch naming IS NULL
-- makes it unusable. Measured 13,192 ms: better, still wrong. Worth
-- recording because it is the fix most people would ship.
--
-- Keeping the two cases in SEPARATE expressions works - the non-null
-- branch is a plain equality the partial index serves, and the null
-- branch is reported "never executed":
--
--   22,330 ms  ->  6.991 ms      (~3,000x)
--
-- NO VALUE MOVED. Checksum over every column of all 597 rows, before and
-- after: 241093e014e86e907aaa1f577eddd0ea, identical. A performance
-- migration that moves a number is a behaviour migration in disguise, so
-- the check has to be the whole view, not a spot sample.
--
--   ottoq_kpi_five(one run)   54,609 ms  ->  6,934 ms
--
-- SECTION 4 — WHAT IS STILL UNEXPLAINED. NOT GUESSED AT.
-- ---------------------------------------------------------------------
-- The CLI is 6,934 ms. The views it reads, timed individually and
-- multiplied by the number of times ottoq_kpi_five reads each:
--
--   KPI 5   370 ms x 4 (p95, p50, returns_unserved, audit) = 1,480 ms
--   KPI 4     7 ms x 2                                     =    14 ms
--   KPI 2     4 ms x 2                                     =     8 ms
--   KPI 1   1.5 ms x 2                                     =     3 ms
--   KPI 3   0.4 ms x 3                                     =     1 ms
--                                                    total ~ 1,506 ms
--
-- That leaves ROUGHLY 5.4 SECONDS UNATTRIBUTED. Tested and excluded:
-- generic plans from the function parameter - KPI 1 via PREPARE/EXECUTE
-- is 1.485 ms and KPI 5 is 370 ms, the same as with a constant, so
-- parameterisation is not it.
--
-- I do not know what the remaining time is. Candidates not yet measured:
-- EXPLAIN ANALYZE overhead on a scalar function call, planning of ~15
-- correlated subqueries, jsonb_build_object assembly. Recorded as an open
-- question rather than a plausible story, because a plausible story about
-- performance is how a 22-second view survived this long.
--
-- SECTION 5 — STILL OPEN
-- ---------------------------------------------------------------------
-- - The 5.4 s above.
-- - KPI 5's plan: Index Scan on ottoq_itinerary_legs by vehicle_id with
--   sim_run_id applied as a FILTER afterwards, discarding 3,065 rows per
--   loop across 118 loops. A composite (sim_run_id, vehicle_id) index
--   would fix it. Different table, different index decision, own
--   migration.
-- - KPI 1's date_trunc resolves in the SESSION timezone, so day KEYS are
--   session-zone dependent. Real reproducibility hazard on a per-day KPI,
--   harmless today because every reader is UTC. Fixing it means choosing
--   a canonical bucket zone - a definitional choice.
-- - KPI 5's denominator over the 345 historical past-horizon rows.
-- - KPI 4's turns filter is still an inline COPY of KPI 2's.
-- =====================================================================

-- §1 — the day-bucket defect is closed and nothing double-counts
WITH r13 AS (SELECT sim_run_id, sim_clock_start FROM public.ottoq_sim_runs
              WHERE run_by='cert_harness' AND started_at >= '2026-09-03 23:16:00+00')
SELECT count(*) FILTER (WHERE k.day < (r13.sim_clock_start AT TIME ZONE 'UTC')::date) AS buckets_before_window_opens,
       round(sum(k.asset_hours_available),2) AS r13_hours
  FROM public.ottoq_kpi_asset_hours_available_per_day k JOIN r13 USING (sim_run_id);

SELECT sum(dispatches_counted) AS dispatches_counted_all_runs  -- must be 68166
  FROM public.ottoq_kpi_asset_hours_available_per_day;

-- §1 — the exact, unrounded quantity the view rounds. This is the check
-- that "run totals unchanged" should have been.
WITH d AS (
  SELECT v.sim_run_id, v.dispatched_at,
         COALESCE(v.actual_return_at, v.scheduled_return_at) AS claimed_end,
         r.sim_clock_start AS win_from, COALESCE(r.sim_clock_current, now()) AS win_to
    FROM public.ottoq_vehicle_dispatches v
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = v.sim_run_id
), c AS (
  SELECT d.*, GREATEST(d.dispatched_at, COALESCE(d.win_from, d.dispatched_at)) AS credit_from,
              LEAST(COALESCE(d.claimed_end, d.win_to), d.win_to)               AS credit_to FROM d
)
SELECT round(sum(GREATEST(EXTRACT(epoch FROM credit_to - credit_from),0::numeric))/3600.0, 6) AS exact_hours,
       round(sum(EXTRACT(epoch FROM COALESCE(claimed_end, win_to) - dispatched_at)
                 - GREATEST(EXTRACT(epoch FROM credit_to - credit_from),0::numeric))/3600.0, 6) AS exact_clipped
  FROM c;

-- §3 — 0187 moved no value. Must equal 241093e014e86e907aaa1f577eddd0ea.
SELECT count(*) AS rows,
       md5(string_agg(coalesce(sim_run_id::text,'NULL')||'|'||touch_events||'|'||turns||'|'||
                      coalesce(touch_events_per_turn::text,'NULL')||'|'||bookings_not_a_turn||'|'||
                      touch_events_operator||'|'||touch_events_override,
                      E'\n' ORDER BY sim_run_id)) AS view_checksum
  FROM public.ottoq_kpi_touch_events_per_turn;

-- §2/§3 — the plan must show an Index Scan, never a Seq Scan, on
-- ottoq_events. A Seq Scan here means the pushdown was lost again.
EXPLAIN (ANALYZE, TIMING OFF, SUMMARY ON)
SELECT touch_events_per_turn FROM public.ottoq_kpi_touch_events_per_turn
 WHERE sim_run_id = '85034701-a556-4853-b148-b8d40c35b490';

-- §4 — the CLI end to end. 54,609 ms before 0187; 6,934 ms after.
EXPLAIN (ANALYZE, TIMING OFF, SUMMARY ON)
SELECT public.ottoq_kpi_five('85034701-a556-4853-b148-b8d40c35b490'::uuid);
