-- =====================================================================
-- 0182  KPI 1 reported more hours than the window could hold
-- =====================================================================
-- forces_recert = FALSE. View only. The sole reader is
-- public.ottoq_kpi_five (the run-ID CLI); nothing on the engine path
-- reads it, so no canon can move. Verified, not assumed.
--
-- THE NUMBER
-- ---------------------------------------------------------------------
-- Grid-fixture pair cebe53e1 / 61af80b0. Run window 02:00 -> 05:00 sim,
-- three hours, four assets. Physical ceiling: 4 x 3 = 12 asset-hours.
--
--   ottoq_kpi_asset_hours_available_per_day  ->  141.02
--
-- Eleven and three quarter times the maximum the world could produce.
-- Both arms report 141.02 identically, which is the tell: the error is
-- shared, not random.
--
-- WHERE IT CAME FROM
-- ---------------------------------------------------------------------
--   sum(COALESCE(actual_return_at, scheduled_return_at) - dispatched_at)
--
-- with no reference to the run at all - the view never joined
-- ottoq_sim_runs, so it had no idea when the run started or stopped.
-- Three separate leaks, and the four dispatches show all of them:
--
--   trigger             dispatched  end used            term
--   wash_cadence        01:20:33    03:00:00 (sim)       1.657 h
--   overnight_prestage  01:30:35    09-03 21:55:54 (!)  68.422 h
--   overnight_prestage  01:43:37    09-03 21:55:54 (!)  68.205 h
--   surplus_to_demand   01:45:44    04:30:00 (sim)       2.738 h
--                                                      -------
--                                                      141.02 h
--
--   (1) The wall-clock ends are 0181's defect - the teardown stamped
--       now() on dispatches that were still out. 0181 stops the write;
--       this stops the view crediting it.
--   (2) scheduled_return_at may lie PAST the horizon. After 0181 the
--       two prestage rows fall back to 05:30 on a run that reached
--       05:00 - smaller, still 30 minutes the run never simulated.
--   (3) dispatched_at may lie BEFORE sim_clock_start. Every one of the
--       four starts at ~01:2x-01:4x on a run that began at 02:00: that
--       is the deployment prime asserting a starting world, not time
--       the run observed. All four terms are inflated at the front.
--
-- (1) and (2) are the horizon-artifact class - 0170 / 0172 / 0176 /
-- 0178, "a run may only be judged on what it had time to do." (3) is
-- the same rule read backwards: nor on what happened before it began.
--
-- THE FIX
-- ---------------------------------------------------------------------
-- Credit each dispatch only for its overlap with the run's own window:
--
--   credit_from = GREATEST(dispatched_at, sim_clock_start)
--   credit_to   = LEAST(COALESCE(actual_return_at, scheduled_return_at),
--                       sim_clock_current)
--
-- clamped at zero so a dispatch entirely outside the window contributes
-- nothing rather than a negative. Recomputed for cebe53e1:
--
--   wash_cadence        02:00 -> 03:00   1.00 h
--   overnight_prestage  02:00 -> 05:00   3.00 h
--   overnight_prestage  02:00 -> 05:00   3.00 h
--   surplus_to_demand   02:00 -> 04:30   2.50 h
--                                       ------
--                                        9.50 h   against a 12.00 ceiling
--
-- The clamp is not hidden. Four columns are appended so a reader can
-- see what it did - the 0176 precedent, which declared end_soc_source
-- rather than quietly reading live state:
--
--   horizon                     the upper bound actually used
--   horizon_source              'run_horizon' | 'wall_clock'
--   hours_clipped_to_window     hours the old formula would have added
--   dispatches_open_at_horizon  dispatches still out when time ran out
--
-- hours_clipped_to_window = 0 means the clamp changed nothing and the
-- number is the same one the old view produced. That is what makes this
-- auditable instead of merely smaller.
--
-- PRODUCTION ROWS SURVIVE. The join to ottoq_sim_runs is a LEFT join and
-- the bound falls back to now() for a dispatch with no run - a live feed
-- has no horizon but it does have a present. horizon_source names which
-- was used, so a wall-clock bound can never be mistaken for a
-- reproducible one. An inner join here would have silently dropped every
-- production dispatch the vehicle and asset feeds are about to write.
--
-- NOT DONE HERE, AND DELIBERATELY: ottoq_kpi_five projects only day ->
-- asset_hours_available, so the four new columns do not reach the CLI.
-- A correction nobody can see from the one command that ships the number
-- is half a fix. Surfacing them changes the run-ID payload shape and
-- gets its own migration and its own check.
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
         -- below reports which of the two was used, so a wall-clock bound
         -- can never be read as a reproducible one.
         COALESCE(r.sim_clock_current, now())                AS win_to,
         (r.sim_clock_current IS NOT NULL)                   AS horizon_from_run
    FROM public.ottoq_vehicle_dispatches v
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = v.sim_run_id
), c AS (
  SELECT d.*,
         GREATEST(d.dispatched_at, COALESCE(d.win_from, d.dispatched_at)) AS credit_from,
         LEAST(COALESCE(d.claimed_end, d.win_to), d.win_to)               AS credit_to
    FROM d
)
SELECT
  sim_run_id,
  date_trunc('day'::text, dispatched_at)::date AS day,
  -- 0182: overlap with the run's own window only. Previously
  -- sum(COALESCE(actual_return_at, scheduled_return_at) - dispatched_at)
  -- with no join to the run at all, which reported 141.02 asset-hours on
  -- a 3-hour 4-asset window whose ceiling is 12.
  round(sum(GREATEST(EXTRACT(epoch FROM credit_to - credit_from), 0::numeric)) / 3600.0, 2) AS asset_hours_available,
  count(DISTINCT vehicle_id) AS assets_counted,
  min(win_to) AS horizon,
  CASE WHEN bool_and(horizon_from_run) THEN 'run_horizon' ELSE 'wall_clock' END AS horizon_source,
  round(sum(  EXTRACT(epoch FROM COALESCE(claimed_end, win_to) - dispatched_at)
            - GREATEST(EXTRACT(epoch FROM credit_to - credit_from), 0::numeric)) / 3600.0, 2)
      AS hours_clipped_to_window,
  count(*) FILTER (WHERE open_at_horizon) AS dispatches_open_at_horizon,
  count(*) AS dispatches_counted
FROM c
GROUP BY sim_run_id, (date_trunc('day'::text, dispatched_at)::date);

COMMENT ON VIEW public.ottoq_kpi_asset_hours_available_per_day IS
  'Canonical KPI 1 (CLAUDE.md 2.9). Asset-hours a fleet was deployed, credited ONLY for overlap with the run window [sim_clock_start, sim_clock_current]. 0182: the prior definition summed COALESCE(actual_return_at, scheduled_return_at) - dispatched_at with no join to the run, so it credited wall-clock teardown stamps (0181), scheduled returns past the horizon, and prime-time before the run began - 141.02 asset-hours on a 3-hour 4-asset window with a ceiling of 12. hours_clipped_to_window reports what the clamp removed; 0 means the number is unchanged from the old formula. horizon_source is wall_clock only for dispatches with no run (live feed), never for a run-scoped row.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('kpi_one_reported_more_hours_than_the_window_could_hold', false,
        'public.ottoq_kpi_asset_hours_available_per_day - canonical KPI 1 - summed COALESCE(actual_return_at, scheduled_return_at) - dispatched_at with no join to ottoq_sim_runs, so it had no horizon at all. Measured on grid-fixture pair cebe53e1/61af80b0: 141.02 asset-hours reported on a 3-hour window with 4 assets, whose physical ceiling is 12 - 11.75x the maximum the world could produce, and identical on both arms because the error is shared rather than random. Three leaks: wall-clock teardown stamps (0181 defect), scheduled_return_at past the horizon, and dispatched_at before sim_clock_start from the deployment prime. Fixed by crediting only the overlap with [sim_clock_start, sim_clock_current], clamped at zero: cebe53e1 recomputes to 9.50 against the 12.00 ceiling. Four diagnostic columns appended per the 0176 precedent (horizon, horizon_source, hours_clipped_to_window, dispatches_open_at_horizon) so the clamp is auditable rather than merely smaller; hours_clipped_to_window = 0 means the number is unchanged from the old formula. LEFT join keeps production dispatches (sim_run_id IS NULL) - an inner join would have silently dropped every row the vehicle and asset feeds are about to write - and horizon_source names when the bound was now() rather than a run clock. forces_recert=false: view only, and the sole reader is ottoq_kpi_five (the run-ID CLI), verified against pg_proc and pg_views - nothing on the engine path reads it. Follow-on, not done here: ottoq_kpi_five projects only day -> asset_hours_available, so the diagnostics do not reach the CLI; surfacing them changes the run-ID payload shape and gets its own migration.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
