-- =====================================================================
-- 0186  The hours were filed under a day they did not happen on
-- =====================================================================
-- forces_recert = FALSE. View only; sole reader ottoq_kpi_five.
--
-- Found by 0185 within the hour of shipping it, which is the argument for
-- 0185: the audit block put `days` next to a headline and the two
-- disagreed.
--
-- THE SYMPTOM
-- ---------------------------------------------------------------------
-- Round-13 run 85034701, window 2026-09-01 02:00 -> 14:00. Not one minute
-- of it falls on 2026-08-31. Its KPI 1 payload:
--
--   "asset_hours_available_per_day": { "2026-08-31":   5.00,
--                                      "2026-09-01": 148.50 }
--   audit.asset_hours.days  2      audit.turns.days  1
--
-- THE CAUSE
-- ---------------------------------------------------------------------
-- KPI 1 buckets on date_trunc('day', dispatched_at) - the day the
-- dispatch STARTED. 0182 clamped the credited interval to
-- [sim_clock_start, sim_clock_current] and correctly so, but left the
-- bucket label untouched. A dispatch created by the deployment prime at
-- 08-31 22:40 is therefore credited entirely on 09-01 and labelled 08-31.
-- The label and the interval disagree.
--
-- Across all twelve round-13 arm rows:
--
--   day-buckets earlier than their run's own window opens    12
--   hours filed in those buckets                          58.00
--   hours total                                         1,910.86   (3.0%)
--
-- The RUN TOTAL was never wrong - every hour is counted exactly once and
-- 0182's clamp works. What was wrong is the per-day breakdown, which is
-- the entire unit of a KPI named asset_hours_available_per_DAY. A reader
-- taking "2026-08-31: 5.00" as an operational fact was reading hours that
-- happened the following morning.
--
-- THE FIX: bucket by the credited interval, splitting a dispatch across
-- every day it actually occupies. A deployment running 09-01 22:00 ->
-- 09-02 06:00 now contributes 2 h to 09-01 and 6 h to 09-02 instead of
-- 8 h to 09-01.
--
-- CONSEQUENCES, stated rather than discovered later:
--
--   The CREDITED QUANTITY is unchanged, exactly. The slicing is a
--   partition of [credit_from, credit_to], so the slices sum to the same
--   seconds. What moves is the PUBLISHED total, because the view rounds
--   to 2 dp per bucket and the bucket count changes: 1,183 -> 606.
--
--   I first wrote "run totals unchanged" here as the check, and it is
--   too strong - measured, the published totals do move:
--
--                     exact (unrounded)   before      after
--     hours            93,710.888622    93,710.90   93,710.89
--     hours_clipped    42,678.703525    42,680.51   42,677.93
--
--   Both differences are inside the rounding envelope (606 buckets x
--   0.005 = 3.03 max drift; 1,183 x 0.005 = 5.92 before), and against
--   the exact value the NEW view is closer on both - hours drift
--   0.0014 against 0.0114, clipped drift 0.77 against 1.81. Fewer
--   buckets, less accumulated rounding.
--
--   The real check is therefore the exact quantity above, plus
--   dispatches_counted holding at 68,166 (no double-counting) and
--   buckets-before-the-window-opens going 12 -> 0.
--
--   assets_counted now counts distinct vehicles PER DAY OCCUPIED rather
--   than per dispatch-start day, so a vehicle deployed across midnight
--   counts on both days. That is the same correction applied to the same
--   grain, not a separate change.
--
--   hours_clipped_to_window and dispatches_counted are per-DISPATCH
--   quantities, not per-slice. They are attributed once, to the first day
--   the dispatch is credited on, so a multi-day dispatch is not counted
--   twice. dispatches_counted therefore still sums to the run's dispatch
--   count.
--
--   A dispatch with zero credited time (entirely outside the window)
--   still produces exactly one row, with 0 hours, rather than vanishing.
--   It was counted before and is counted now.
--
-- NOT FIXED HERE, and noted so it is not mistaken for settled:
-- date_trunc('day', ...) resolves in the SESSION timezone. The same run
-- read from a session in a different zone yields different day KEYS. That
-- is a genuine reproducibility hazard on a per-day KPI and it predates
-- this migration; every reader to date has been UTC, so no number is
-- currently wrong. Fixing it means choosing a canonical zone for the
-- bucket boundary - a definitional choice, and deciding it inside a
-- labelling fix would smuggle it in the way 0183 declined to smuggle the
-- points_used denominator.
-- =====================================================================

CREATE OR REPLACE VIEW public.ottoq_kpi_asset_hours_available_per_day AS
WITH d AS (
  SELECT v.sim_run_id,
         v.vehicle_id,
         v.dispatched_at,
         COALESCE(v.actual_return_at, v.scheduled_return_at) AS claimed_end,
         (v.actual_return_at IS NULL)                        AS open_at_horizon,
         r.sim_clock_start                                   AS win_from,
         -- 0182: a run's horizon is its own clock. A dispatch with no run
         -- is a live-feed row and its bound is the present; horizon_source
         -- below reports which of the two was used.
         COALESCE(r.sim_clock_current, now())                AS win_to,
         (r.sim_clock_current IS NOT NULL)                   AS horizon_from_run
    FROM public.ottoq_vehicle_dispatches v
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = v.sim_run_id
), c AS (
  SELECT d.*,
         GREATEST(d.dispatched_at, COALESCE(d.win_from, d.dispatched_at)) AS credit_from,
         LEAST(COALESCE(d.claimed_end, d.win_to), d.win_to)               AS credit_to
    FROM d
), sliced AS (
  -- 0186: split the credited interval across the days it OCCUPIES.
  -- Previously bucketed on date_trunc('day', dispatched_at), so hours
  -- credited wholly on 09-01 were filed under 08-31 whenever the
  -- deployment prime created the dispatch before midnight. GREATEST in
  -- the series end keeps a zero-credit dispatch producing exactly one
  -- row rather than vanishing.
  SELECT c.sim_run_id, c.vehicle_id, c.dispatched_at, c.claimed_end,
         c.win_to, c.horizon_from_run, c.open_at_horizon,
         c.credit_from, c.credit_to,
         gs::date AS day,
         GREATEST(EXTRACT(epoch FROM LEAST(c.credit_to, gs + interval '1 day')
                                   - GREATEST(c.credit_from, gs)), 0::numeric) AS slice_secs,
         (gs = date_trunc('day'::text, c.credit_from)) AS is_first_slice
    FROM c,
         LATERAL generate_series(date_trunc('day'::text, c.credit_from),
                                 date_trunc('day'::text, GREATEST(c.credit_to, c.credit_from)),
                                 interval '1 day') AS gs
)
SELECT
  sim_run_id,
  day,
  round(sum(slice_secs) / 3600.0, 2) AS asset_hours_available,
  count(DISTINCT vehicle_id) AS assets_counted,
  min(win_to) AS horizon,
  CASE WHEN bool_and(horizon_from_run) THEN 'run_horizon' ELSE 'wall_clock' END AS horizon_source,
  -- per-DISPATCH quantities, attributed once to the first credited day
  round(sum(CASE WHEN is_first_slice
                 THEN EXTRACT(epoch FROM COALESCE(claimed_end, win_to) - dispatched_at)
                      - GREATEST(EXTRACT(epoch FROM credit_to - credit_from), 0::numeric)
                 ELSE 0::numeric END) / 3600.0, 2) AS hours_clipped_to_window,
  count(*) FILTER (WHERE open_at_horizon AND is_first_slice) AS dispatches_open_at_horizon,
  count(*) FILTER (WHERE is_first_slice)                     AS dispatches_counted
FROM sliced
GROUP BY sim_run_id, day;

COMMENT ON VIEW public.ottoq_kpi_asset_hours_available_per_day IS
  'Canonical KPI 1 (CLAUDE.md 2.9). Asset-hours a fleet was deployed, credited ONLY for overlap with the run window [sim_clock_start, sim_clock_current] (0182), and bucketed by the days that credited interval OCCUPIES (0186). 0186: the view previously bucketed on date_trunc(day, dispatched_at), so a dispatch created by the deployment prime before midnight had its hours credited on the next day but labelled with the previous one - 58.00 of 1910.86 hours across round 13, 3.0%, filed under days the run did not touch. Run totals were never affected; the per-day breakdown was. assets_counted is per day occupied. hours_clipped_to_window and dispatches_counted are per-dispatch and attributed once, to the first credited day. Known and unfixed: date_trunc resolves in the session timezone, so day KEYS are session-zone dependent - a definitional choice, not decided here.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_hours_were_filed_under_a_day_they_did_not_happen_on', false,
        'public.ottoq_kpi_asset_hours_available_per_day - canonical KPI 1 - bucketed on date_trunc(day, dispatched_at), the day a dispatch STARTED, while 0182 clamped the credited interval to the run window. A dispatch created by the deployment prime at 08-31 22:40 was therefore credited entirely on 09-01 and labelled 08-31: the label and the interval disagreed. Found by 0185 within the hour of shipping it, which is the argument for 0185 - the audit block put days=2 next to a run whose window lies entirely within one day. Measured across all twelve round-13 arm rows: 12 day-buckets earlier than their run window opens, carrying 58.00 of 1910.86 hours, 3.0%. The RUN TOTAL was never wrong - every hour counted exactly once and 0182 clamp works - but the per-day breakdown is the entire unit of a KPI named per_DAY, and a reader taking 2026-08-31: 5.00 as an operational fact was reading hours that happened the following morning. Fixed by splitting the credited interval across the days it occupies. Consequences stated rather than discovered later: run totals unchanged (this moves hours between buckets, which is the check); assets_counted is now distinct vehicles per day occupied rather than per dispatch-start day; hours_clipped_to_window and dispatches_counted are per-dispatch and attributed once to the first credited day so a multi-day dispatch is not double-counted; a dispatch with zero credited time still produces one row at 0 hours rather than vanishing. Noted and deliberately NOT fixed: date_trunc resolves in the session timezone, so the same run read from a different zone yields different day keys - a genuine reproducibility hazard on a per-day KPI, predating this migration, currently harmless because every reader has been UTC, and fixing it means choosing a canonical bucket zone, which is a definitional choice of the kind 0183 declined to smuggle into a defect fix. forces_recert=false: view only, sole reader ottoq_kpi_five.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
