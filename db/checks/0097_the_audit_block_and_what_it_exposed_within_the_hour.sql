-- =====================================================================
-- 0097  The audit block, and what it exposed within the hour
-- =====================================================================
-- 0185 surfaced the diagnostic columns 0182/0183/0184 added. The first
-- payload it produced contained a number that should not have been there.
--
-- SECTION 1 — 0185 WORKS, AND THE IDENTITIES HOLD
-- ---------------------------------------------------------------------
-- Measured across every round-13 run:
--
--   KPI 4  touch_events = operator + override            true
--   KPI 2  turns_completed + bookings_not_a_turn
--            = bookings_seen                             true
--   KPI 1  horizon_source = 'run_horizon' on every row   true
--
-- The first two are the reversibility contract: a reader can reconstruct
-- the pre-correction number from the payload alone, so 0182/0183/0184 are
-- corrections rather than merely smaller numbers. The third is the
-- reproducibility contract: no KPI 1 row on a certified run was bounded
-- by now().
--
-- One round-13 payload, in full (run 85034701, busy_day 424242 24t):
--
--   headline    turns_per_point_per_day 2.34 on 2026-09-01
--   audit       turns_completed 370, bookings_not_a_turn 680,
--               bookings_seen 1050, points_used_max_day 158
--
-- So the pre-0183 number for this run was 1050/158 = 6.65 against a true
-- 2.34 — a 2.84x overstatement, readable straight off the payload. That
-- is what the audit block is for.
--
-- SECTION 2 — WHAT IT EXPOSED: KPI 1 FILES HOURS UNDER A DAY THEY DID NOT
--             HAPPEN ON
-- ---------------------------------------------------------------------
-- The same payload carried:
--
--   audit.asset_hours_available_per_day.days     2
--   audit.service_point_turns...days             1
--   asset_hours_available_per_day  { "2026-08-31": 5.00,
--                                    "2026-09-01": 148.50 }
--
-- The run's window is 2026-09-01 02:00 -> 14:00. Not one minute of it
-- falls on 2026-08-31. Yet 5.00 asset-hours are filed there.
--
-- CAUSE. KPI 1 buckets on date_trunc('day', dispatched_at) — the day the
-- dispatch STARTED. 0182 correctly clamped the credited interval to
-- [sim_clock_start, sim_clock_current], but left the bucket label alone.
-- For a dispatch created by the deployment prime at, say, 08-31 22:40,
-- the credited interval is [09-01 02:00, ...] — entirely on 09-01 — while
-- the label still reads 08-31. The label and the interval disagree.
--
-- MEASURED across all twelve round-13 arm rows:
--
--   day-buckets earlier than their run's own window opens    12
--   hours filed in those buckets                          58.00
--   hours total                                         1,910.86
--                                                         (3.0%)
--
-- The RUN TOTAL is unaffected — every hour is counted once, and 0182's
-- clamp is doing its job. What is wrong is the per-day breakdown, which
-- is the entire unit of a KPI named asset_hours_available_per_DAY. A
-- reader taking "2026-08-31: 5.00" as an operational fact would be
-- reading hours that happened the following morning.
--
-- This is the 0182/0183/0184 family again in its mildest form: a number
-- whose LABEL does not describe what it measures. It was invisible until
-- the audit block put `days` next to a one-day run.
--
-- NOT FIXED HERE. The fix is to bucket by the credited interval rather
-- than by dispatched_at, splitting a dispatch that spans midnight across
-- the days it actually occupies. That changes the day KEYS in the
-- ottoq_kpi_five payload, so it is its own migration with its own check —
-- 0186 — not a line appended to 0185.
--
-- SECTION 3 — WHAT IS STILL OPEN
-- ---------------------------------------------------------------------
-- - KPI 5's denominator over the 345 historical past-horizon dispatch
--   rows. 0185 now surfaces returns_measured, returns_unserved and
--   returns_deferred_beyond_horizon, so the population is at least
--   visible; whether the historical rows distorted it is unexamined.
-- - KPI 2's points_used denominator (per booked point / per turned point
--   / per installed point) — a definitional choice, deliberately not
--   decided inside a defect fix. 0185 now exposes both counts so it can
--   be decided on evidence: on run 85034701, 158 points saw a booking
--   and 146 completed a turn.
-- - KPI 4's turns filter is still an inline COPY of KPI 2's.
-- - The pg_cron stall mechanism (round 12) is still unnamed.
-- =====================================================================

-- §1 — the three identities. All must be true.
WITH r13 AS (SELECT sim_run_id FROM public.ottoq_sim_runs
              WHERE run_by='cert_harness' AND started_at >= '2026-09-03 23:16:00+00')
SELECT
  (SELECT bool_and(touch_events = touch_events_operator + touch_events_override)
     FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id IN (SELECT sim_run_id FROM r13))      AS kpi4_numerator_identity,
  (SELECT bool_and(turns_completed + bookings_not_a_turn = bookings_seen)
     FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id IN (SELECT sim_run_id FROM r13))        AS kpi2_reversibility,
  (SELECT bool_and(horizon_source = 'run_horizon')
     FROM public.ottoq_kpi_asset_hours_available_per_day WHERE sim_run_id IN (SELECT sim_run_id FROM r13)) AS kpi1_all_run_bounded;

-- §2 — the day-bucket defect. buckets_before_window_opens must become 0
-- once 0186 lands; until then it is the size of the mislabelling.
WITH r13 AS (SELECT sim_run_id, sim_clock_start FROM public.ottoq_sim_runs
              WHERE run_by='cert_harness' AND started_at >= '2026-09-03 23:16:00+00')
SELECT count(*) FILTER (WHERE k.day < (r13.sim_clock_start AT TIME ZONE 'UTC')::date) AS buckets_before_window_opens,
       round(sum(k.asset_hours_available) FILTER (WHERE k.day < (r13.sim_clock_start AT TIME ZONE 'UTC')::date), 2) AS hours_in_those_buckets,
       round(sum(k.asset_hours_available), 2) AS hours_total,
       round(100.0 * sum(k.asset_hours_available) FILTER (WHERE k.day < (r13.sim_clock_start AT TIME ZONE 'UTC')::date)
             / NULLIF(sum(k.asset_hours_available),0), 1) AS pct_mislabelled
  FROM public.ottoq_kpi_asset_hours_available_per_day k JOIN r13 USING (sim_run_id);

-- §1 evidence — the payload the audit block produces
SELECT jsonb_pretty(public.ottoq_kpi_five('85034701-a556-4853-b148-b8d40c35b490'::uuid)) AS payload;
