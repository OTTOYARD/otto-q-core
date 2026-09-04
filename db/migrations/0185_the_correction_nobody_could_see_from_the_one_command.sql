-- =====================================================================
-- 0185  The correction nobody could see from the one command
-- =====================================================================
-- forces_recert = FALSE. Reader only; ottoq_kpi_five is the run-ID CLI
-- and no engine path calls it.
--
-- 0182, 0183 and 0184 each appended diagnostic columns so their
-- corrections would be auditable rather than merely smaller. None of them
-- reach ottoq_kpi_five, which projects the headline columns alone. So
-- four of the five canonical KPIs carry an audit trail that is invisible
-- from the one command that ships the number - which is the same failure
-- mode as the defects themselves: a number with no way to check it.
--
-- 0092 §8, 0093 §4 and 0094 §5 each recorded this as owed. This pays it.
--
-- THE PAYLOAD SHAPE CHANGES. That is why this is its own migration and
-- not a line inside 0184. Every existing key keeps its name, type and
-- meaning; one new top-level key, "audit", is added. A consumer reading
-- the headline keys is unaffected; a consumer enumerating keys sees one
-- more.
--
-- WHAT EACH FIELD IS FOR
-- ---------------------------------------------------------------------
-- asset_hours (KPI 1, 0182)
--   hours_clipped_to_window     what the pre-0182 formula would have
--                               added. 0 means the number is unchanged
--                               from the old definition.
--   horizon_source              'run_horizon' or 'wall_clock'. Anything
--                               but run_horizon means the bound came
--                               from now() and the number is NOT
--                               reproducible from the run ID.
--   dispatches_open_at_horizon  assets still out when time ran out.
--
-- service_point_turns (KPI 2, 0183)
--   turns_completed + bookings_not_a_turn reproduces the pre-0183
--   number exactly, so the correction is reversible by inspection.
--   The three release reasons say WHY each excluded booking was not a
--   turn. points_used vs points_with_a_turn exposes the per-point
--   denominator question 0183 deliberately did not decide.
--
-- touch_events (KPI 4, 0184)
--   turns + bookings_not_a_turn reproduces the pre-0184 denominator.
--   operator + override must equal touch_events - if it does not, the
--   headline has drifted from its own numerator again, which is the
--   defect 0184 fixed.
--
-- p95_time_to_service (KPI 5)
--   returns_measured is the denominator the percentile is actually
--   computed over. returns_unserved and returns_deferred_beyond_horizon
--   are the two ways a return leaves that denominator. A p95 quoted
--   without returns_measured is a percentile over an unknown population;
--   this makes the population visible. KPI 5 was NOT changed by this
--   campaign - these columns already existed and were simply not
--   surfaced.
--
-- peak_site_kw (KPI 3)
--   snapshots is the sample count behind a 15-minute rolling max. A peak
--   over three samples and a peak over three hundred are different
--   claims.
--
-- GRAIN. KPI 1 and KPI 2 are per run per DAY; their audit figures are
-- run-level aggregates, with `days` given so the grain is not guessed.
-- Counts are summed; point counts are the per-day maximum and named
-- _max_day, because summing distinct stalls across days would
-- double-count them.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ottoq_kpi_five(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'sim_run_id', p_run,
    'run_key', (SELECT jsonb_build_object(
                  'policy_name', a.policy, 'pack_id', a.pack_id,
                  'scenario_seed', a.random_seed, 'config_hash', a.config_hash,
                  'engine_hash', a.engine_hash, 'scenario', a.scenario)
                  FROM public.ottoq_run_archives a WHERE a.sim_run_id = p_run),
    'asset_hours_available_per_day',
      COALESCE((SELECT jsonb_object_agg(day, asset_hours_available ORDER BY day)
         FROM public.ottoq_kpi_asset_hours_available_per_day WHERE sim_run_id = p_run), '{}'::jsonb),
    'service_point_turns_per_point_per_day',
      COALESCE((SELECT jsonb_object_agg(day, turns_per_point_per_day ORDER BY day)
         FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id = p_run), '{}'::jsonb),
    'peak_site_kw',
      (SELECT peak_site_kw_15min FROM public.ottoq_kpi_peak_site_kw WHERE sim_run_id = p_run),
    'peak_site_kw_demand',   /* 0138 */
      (SELECT peak_site_kw_demand_15min FROM public.ottoq_kpi_peak_site_kw_demand WHERE sim_run_id = p_run),
    'touch_events_per_turn',
      (SELECT touch_events_per_turn FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = p_run),
    'p95_time_to_service_min',
      (SELECT p95_time_to_service_min FROM public.ottoq_kpi_p95_time_to_service WHERE sim_run_id = p_run),
    'p50_time_to_service_min',
      (SELECT p50_time_to_service_min FROM public.ottoq_kpi_p95_time_to_service WHERE sim_run_id = p_run),
    'returns_unserved',
      (SELECT returns_unserved FROM public.ottoq_kpi_p95_time_to_service WHERE sim_run_id = p_run),

    /* 0185: the audit trail 0182/0183/0184 built and nobody could see.
       A correction invisible from the command that ships the number is
       half a fix. Every headline key above is unchanged. */
    'audit', jsonb_build_object(
      'asset_hours_available_per_day',
        (SELECT jsonb_build_object(
            'days',                       count(*),
            'hours_clipped_to_window',    sum(hours_clipped_to_window),
            'dispatches_open_at_horizon', sum(dispatches_open_at_horizon),
            'dispatches_counted',         sum(dispatches_counted),
            'horizon',                    max(horizon),
            'horizon_source', CASE WHEN bool_and(horizon_source = 'run_horizon')
                                   THEN 'run_horizon' ELSE 'wall_clock' END)
           FROM public.ottoq_kpi_asset_hours_available_per_day WHERE sim_run_id = p_run),
      'service_point_turns_per_point_per_day',
        (SELECT jsonb_build_object(
            'days',                     count(*),
            'turns_completed',          sum(turns_completed),
            'bookings_not_a_turn',      sum(bookings_not_a_turn),
            'released_never_occupied',  sum(released_never_occupied),
            'released_by_teardown',     sum(released_by_teardown),
            'released_no_show',         sum(released_no_show),
            'bookings_seen',            sum(bookings_seen),
            'points_used_max_day',      max(points_used),
            'points_with_a_turn_max_day', max(points_with_a_turn))
           FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id = p_run),
      'touch_events_per_turn',
        (SELECT jsonb_build_object(
            'touch_events',          touch_events,
            'turns',                 turns,
            'bookings_not_a_turn',   bookings_not_a_turn,
            'touch_events_operator', touch_events_operator,
            'touch_events_override', touch_events_override)
           FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = p_run),
      'p95_time_to_service_min',
        (SELECT jsonb_build_object(
            'returns_measured',                returns_measured,
            'returns_unserved',                returns_unserved,
            'returns_deferred_beyond_horizon', returns_deferred_beyond_horizon,
            'max_time_to_service_min',         max_time_to_service_min)
           FROM public.ottoq_kpi_p95_time_to_service WHERE sim_run_id = p_run),
      'peak_site_kw',
        (SELECT jsonb_build_object('snapshots', snapshots)
           FROM public.ottoq_kpi_peak_site_kw WHERE sim_run_id = p_run)),

    'provenance', jsonb_build_object(
      'reproducible_from_run_id', jsonb_build_array(
         'asset_hours_available_per_day', 'service_point_turns_per_point_per_day',
         'peak_site_kw', 'peak_site_kw_demand', 'touch_events_per_turn',
         'p95_time_to_service_min', 'p50_time_to_service_min', 'returns_unserved'),
      'not_reproducible', '[]'::jsonb,
      'why', 'peak_site_kw was carried as not-reproducible on the argument that it is grid import net of a twin battery that was not deterministic. Measured over the last 40 certified determinism pairs at 0167: peak_site_kw equal in 40, differing in 0; peak_site_kw_demand equal in 40, differing in 0. The old text was stale and is retired. Re-run that count before quoting this line.',
      'evidence', 'db/checks/0077; count re-runnable from ottoq_kpi_peak_site_kw joined to the arm pairs in ottoq_sim_runs.validation_notes',
      'audit_note', '0185. The audit block carries the diagnostic columns 0182/0183/0184 added so their corrections are checkable from this payload rather than only from the views. Reversibility: KPI 1 asset_hours + audit.hours_clipped_to_window is the pre-0182 number; KPI 2 audit.turns_completed + audit.bookings_not_a_turn is the pre-0183 numerator; KPI 4 audit.turns + audit.bookings_not_a_turn is the pre-0184 denominator. audit.asset_hours.horizon_source must read run_horizon - anything else means the bound came from now() and the number is NOT reproducible from this run ID. audit.touch_events_operator + audit.touch_events_override must equal audit.touch_events, or the headline has drifted from its own numerator. KPI 1 and KPI 2 are per-day views; their audit figures are run-level, counts summed and point counts given as the per-day maximum (_max_day) because distinct stalls cannot be summed across days.',
      'run_key_note', 'config_hash keys the CONFIGURATION (ottoq_run_config_key: scenario, seed, policy, depot, horizon, clock, effective params). engine_hash keys the ENGINE (applied migration set). Two runs sharing config_hash but not engine_hash are the same experiment on different code. NULL engine_hash means archived before 0167.')
  );
$function$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_correction_nobody_could_see_from_the_one_command', false,
        'public.ottoq_kpi_five - the run-ID CLI - projected only the headline columns, so the diagnostic columns 0182, 0183 and 0184 appended to make their corrections auditable never reached it. Four of the five canonical KPIs carried an audit trail invisible from the one command that ships the number, which is the same failure mode as the defects themselves: a number with no way to check it. 0092 s8, 0093 s4 and 0094 s5 each recorded this as owed. Adds one top-level key, audit, carrying per-KPI diagnostics; every existing key keeps its name, type and meaning, so a consumer reading the headline keys is unaffected while one enumerating keys sees one more - the payload shape change is why this is its own migration rather than a line inside 0184. Reversibility is the point: asset_hours + audit.hours_clipped_to_window is the pre-0182 number, audit.turns_completed + audit.bookings_not_a_turn is the pre-0183 numerator, audit.turns + audit.bookings_not_a_turn is the pre-0184 denominator, so every correction can be undone by inspection from the payload alone. audit.asset_hours.horizon_source reading anything but run_horizon means the bound came from now() and the number is not reproducible from the run ID. KPI 5 was not changed by this campaign - returns_measured, returns_unserved and returns_deferred_beyond_horizon already existed and were simply not surfaced, and a p95 quoted without its denominator is a percentile over an unknown population. peak_site_kw gains snapshots, because a 15-minute rolling max over three samples and over three hundred are different claims. Grain is stated rather than guessed: KPI 1 and KPI 2 are per-day views, so their audit figures are run-level with counts summed and point counts as the per-day maximum, since distinct stalls cannot be summed across days. forces_recert=false: reader only, no engine path calls it.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
