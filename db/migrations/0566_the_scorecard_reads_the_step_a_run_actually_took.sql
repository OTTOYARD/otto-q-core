-- migration-version: 20260929184316
-- migration-name:    the_scorecard_reads_the_step_a_run_actually_took
--
-- 0566  **The throughput scorecard reads the step a run actually took, and extrapolates no daily rate from a short run.**
--       Lane A, phase 1, follow-up to 0565 (applied 20260929183923, 1:39 PM CT).
--
-- ══ §1 WHY (read on the live scorecards 0565 backfilled, 2026-09-29) ════════════════════════════════════════════════
--
--   * step_min was the NOMINAL step (tick_interval_seconds x time_scale / 60). The certification harness takes the
--     nominal 30 minutes, but a cockpit demo run advances the clock in much smaller steps: run 4b0999db (812 ticks,
--     demo_speed_x 8) moved 0.51 sim-minutes per tick and was labelled 30, so its caveat said the opposite of the truth.
--   * served_per_day and turns_per_charger_per_day were scaled to 24 hours from any horizon. The 0.29-hour demo run
--     e9e3b922 read 75 fast-charger turns per charger per day from 9 sessions.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_throughput_scorecard(run), CREATE OR REPLACE, scorecard_version '0566':
--     step_min          the step the run actually took: (horizon - start) / ticks. step_min_nominal keeps the old value.
--     per-day rates     served_per_day and turns_per_charger_per_day only when the run covers 6 hours or more, and a
--                       caveat says so when it does not.
--   public.ottoq_throughput_scores_latest   the newest scorecard per run (score_id order), the view readers should use.
--   Every finished twin-depot run is rescored (origin 'rescore_0566'). The 0565 rows stay: the table is append-only
--   evidence, and a scorecard_version tells the two apart.
--
-- ══ §3 WHAT THE CORRECTION SHOWS (a signal, not a claim) ══════════════════════════════════════════════════════════
--
--   At a 0.51-minute step, the demo run 4b0999db (busy_day, 6.9 sim-hours from its start) turned each fast charger
--   20.5 times a day, served a best hour of 27 and a door-to-door p50 of 155 minutes. The 30-minute certified day
--   (ff680f5f) read 6.7 turns, a best hour of 12 and 540 minutes. Different seeds and different windows of the day, so
--   this is not a comparison, but it points where 0565 section 4 did: at decision timing.
--
-- ══ §4 WHEN TO APPLY ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   Any time. It replaces one read function no engine path calls, adds one view and scores finished runs: forces_recert
--   and forces_dial_restart FALSE.
--
-- ROLLBACK: re-create 0565's ottoq_throughput_scorecard body; DROP VIEW public.ottoq_throughput_scores_latest; the
--   rescore rows stay (append-only evidence). DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0566_the_scorecard_reads_the_step_a_run_actually_took'.

BEGIN;

-- ── P1: 0565 is applied, and its scorecard is the one this replaces ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_throughput_scores') IS NULL
     OR to_regprocedure('public.ottoq_throughput_score_write(uuid,text)') IS NULL THEN
    RAISE EXCEPTION '0566 P1: 0565 is not applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_throughput_scorecard(uuid)')
                    AND prosrc ~ $re$'scorecard_version', '0565'$re$) THEN
    RAISE EXCEPTION '0566 P1: ottoq_throughput_scorecard is not 0565''s body; this replaces that one only';
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF to_regclass('public.ottoq_throughput_scores_latest') IS NOT NULL THEN
    RAISE EXCEPTION '0566 P2: ottoq_throughput_scores_latest already exists; this file has already been applied';
  END IF;
END $fresh$;

-- ── 1. the scorecard, reading the step the run actually took ──
CREATE OR REPLACE FUNCTION public.ottoq_throughput_scorecard(p_run uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE
  v_five   jsonb;
  v_wait   jsonb;
  v_svc    jsonb;
  v_errors jsonb := '{}'::jsonb;
  v_out    jsonb;
BEGIN
  -- The KPI functions this reuses are read as they are. One that fails on a run (ottoq_kpi_five raises "field name
  -- must not be null" on the August production run e8a0ba01) is reported under kpi_errors, never allowed to take the
  -- throughput numbers down with it.
  BEGIN v_five := public.ottoq_kpi_five(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('kpi_five', SQLERRM); END;
  BEGIN v_wait := public.ottoq_kpi_charge_wait(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('charge_wait', SQLERRM); END;
  BEGIN v_svc := public.ottoq_kpi_service_completion(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('service_completion', SQLERRM); END;

  WITH r AS (
    SELECT sr.sim_run_id, sr.depot_id, sr.scenario_code, sr.random_seed, sr.tick_count, sr.policy, sr.status,
           sr.sim_clock_start, sr.sim_clock_current,
           round((sr.tick_interval_seconds * COALESCE(sr.time_scale, 1) / 60.0)::numeric, 2) AS step_min_nominal,
           round((extract(epoch FROM (sr.sim_clock_current - sr.sim_clock_start)) / 60.0
                  / NULLIF(sr.tick_count, 0))::numeric, 2) AS step_min,
           GREATEST(extract(epoch FROM (sr.sim_clock_current - sr.sim_clock_start)) / 3600.0, 0)::numeric AS horizon_h
      FROM public.ottoq_sim_runs sr
     WHERE sr.sim_run_id = p_run
  ), o AS (
    SELECT * FROM public.ottoq_visit_outcomes(p_run)
  ), s AS (
    SELECT * FROM o WHERE departed_at IS NOT NULL
  ), grp AS (
    SELECT g.tier_group,
           count(*)                                                       AS visits,
           count(*) FILTER (WHERE g.departed_at IS NOT NULL)              AS served,
           count(*) FILTER (WHERE g.in_depot_at_horizon)                  AS in_depot,
           percentile_cont(0.5)  WITHIN GROUP (ORDER BY g.door_min)       AS p50,
           percentile_cont(0.95) WITHIN GROUP (ORDER BY g.door_min)       AS p95,
           count(*) FILTER (WHERE g.due_at IS NOT NULL AND g.departed_at IS NOT NULL) AS due_served,
           count(*) FILTER (WHERE g.on_time)                              AS on_time
      FROM o g
     GROUP BY g.tier_group
  ), peak AS (
    SELECT COALESCE(max(n), 0) AS n
      FROM (SELECT (SELECT count(*) FROM s s2
                     WHERE s2.departed_at >= s1.departed_at
                       AND s2.departed_at <  s1.departed_at + interval '60 minutes') AS n
              FROM s s1) z
  ), sess AS (
    SELECT st.stall_type, x.stall_id, x.started_at, x.ended_at, x.energy_delivered_kwh, x.avg_power_kw
      FROM public.ocpp_sessions x
      JOIN public.stalls st ON st.id = x.stall_id
     WHERE x.sim_run_id = p_run AND x.started_at IS NOT NULL
  ), dc AS (
    SELECT count(*)                                                                          AS sessions,
           count(DISTINCT stall_id)                                                          AS chargers_used,
           sum(extract(epoch FROM (ended_at - started_at)) / 3600.0) FILTER (WHERE ended_at IS NOT NULL) AS hours,
           sum(energy_delivered_kwh)                                                         AS kwh,
           avg(avg_power_kw)                                                                 AS mean_kw,
           avg(extract(epoch FROM (ended_at - started_at)) / 60.0) FILTER (WHERE ended_at IS NOT NULL) AS mean_min
      FROM sess
     WHERE stall_type = 'dcfc'
  ), fleet AS (
    SELECT count(*) AS dcfc_at_depot FROM public.stalls st, r WHERE st.depot_id = r.depot_id AND st.stall_type = 'dcfc'
  ), ar AS (
    SELECT a.engine_hash, a.config_hash FROM public.ottoq_run_archives a WHERE a.sim_run_id = p_run LIMIT 1
  )
  SELECT jsonb_build_object(
    'sim_run_id', r.sim_run_id,
    'scorecard_version', '0566',
    'run', jsonb_build_object(
       'scenario', r.scenario_code, 'seed', r.random_seed, 'ticks', r.tick_count, 'policy', r.policy,
       'status', r.status, 'depot_id', r.depot_id, 'sim_start', r.sim_clock_start, 'horizon', r.sim_clock_current,
       'horizon_h', round(r.horizon_h, 2),
       'engine_hash', (SELECT engine_hash FROM ar), 'config_hash', (SELECT config_hash FROM ar)),
    'step_min', r.step_min,
    'step_min_nominal', r.step_min_nominal,
    'throughput', jsonb_build_object(
       'visits',              (SELECT count(*) FROM o),
       'visits_served',       (SELECT count(*) FROM s),
       'vehicles_served',     (SELECT count(DISTINCT vehicle_id) FROM s),
       'in_depot_at_horizon', (SELECT count(*) FROM o WHERE in_depot_at_horizon),
       'served_per_day',      CASE WHEN r.horizon_h >= 6
                                   THEN round((SELECT count(*) FROM s) * 24.0 / r.horizon_h, 1) END,
       'peak_hour_served',    (SELECT n FROM peak)),
    'by_tier_group', COALESCE((SELECT jsonb_object_agg(tier_group, jsonb_build_object(
       'visits', visits, 'served', served, 'in_depot', in_depot,
       'door_p50_min', round(p50::numeric, 0), 'door_p95_min', round(p95::numeric, 0),
       'due_served', due_served, 'on_time', on_time,
       'on_time_pct', CASE WHEN due_served > 0 THEN round(100.0 * on_time / due_served, 1) END)) FROM grp), '{}'::jsonb),
    'timeliness', jsonb_build_object(
       'door_p50_min', (SELECT round((percentile_cont(0.5)  WITHIN GROUP (ORDER BY door_min))::numeric, 0) FROM s),
       'door_p95_min', (SELECT round((percentile_cont(0.95) WITHIN GROUP (ORDER BY door_min))::numeric, 0) FROM s),
       'due_served',   (SELECT count(*) FROM s WHERE due_at IS NOT NULL),
       'on_time',      (SELECT count(*) FROM s WHERE on_time),
       'on_time_pct',  (SELECT CASE WHEN count(*) FILTER (WHERE due_at IS NOT NULL) > 0
                                    THEN round(100.0 * count(*) FILTER (WHERE on_time)
                                               / count(*) FILTER (WHERE due_at IS NOT NULL), 1) END FROM s),
       'late_p50_min', (SELECT round((percentile_cont(0.5)  WITHIN GROUP (ORDER BY late_min))::numeric, 0) FROM s
                         WHERE late_min IS NOT NULL),
       'late_p95_min', (SELECT round((percentile_cont(0.95) WITHIN GROUP (ORDER BY late_min))::numeric, 0) FROM s
                         WHERE late_min IS NOT NULL)),
    'rule9', jsonb_build_object(
       'departures',                  (SELECT count(*) FROM s),
       'left_below_target',           (SELECT count(*) FROM s
                                        WHERE soc_out IS NOT NULL AND soc_out < COALESCE(target_soc, 100) - 1),
       'left_with_needed_work_open',  (SELECT count(*) FROM s WHERE needed_open_at_departure > 0),
       'charge_unknown_at_departure', (SELECT count(*) FROM s WHERE soc_out IS NULL),
       'atoms_cleared_by_triage',     (SELECT COALESCE(sum(cleared_by_triage), 0) FROM o),
       'done_atoms_without_a_time',   (SELECT COALESCE(sum(done_without_time), 0) FROM o)),
    'fast_chargers', jsonb_build_object(
       'at_depot',                  (SELECT dcfc_at_depot FROM fleet),
       'used',                      dc.chargers_used,
       'sessions',                  dc.sessions,
       'turns_per_charger_per_day', CASE WHEN r.horizon_h >= 6 AND (SELECT dcfc_at_depot FROM fleet) > 0
                                         THEN round(dc.sessions * 24.0 / r.horizon_h
                                                    / (SELECT dcfc_at_depot FROM fleet), 2) END,
       'busy_pct',                  CASE WHEN r.horizon_h > 0 AND (SELECT dcfc_at_depot FROM fleet) > 0
                                         THEN round(100.0 * COALESCE(dc.hours, 0)
                                                    / (r.horizon_h * (SELECT dcfc_at_depot FROM fleet)), 1) END,
       'mean_session_min',          round(dc.mean_min::numeric, 1),
       'mean_kw',                   round(dc.mean_kw::numeric, 1),
       'kwh_per_session_hour',      round((dc.kwh / NULLIF(dc.hours, 0))::numeric, 1)),
    'l2_sessions', (SELECT count(*) FROM sess WHERE stall_type = 'l2'),
    'charge_wait', v_wait,
    'service_completion', CASE WHEN v_svc IS NOT NULL THEN
                            jsonb_build_object('must_do', v_svc->'must_do', 'must_do_done', v_svc->'must_do_done',
                                               'pct', v_svc->'service_completion_pct') END,
    'kpi', CASE WHEN v_five IS NOT NULL THEN
             jsonb_build_object('peak_site_kw', v_five->'peak_site_kw',
                                'peak_site_kw_demand', v_five->'peak_site_kw_demand',
                                'touch_events_per_turn', v_five->'touch_events_per_turn',
                                'p95_time_to_service_min', v_five->'p95_time_to_service_min') END,
    'kpi_errors', v_errors,
    'comparability', jsonb_build_object(
       'all_policies', 'visits, dispatches and charge sessions: every arm''s vehicles produce them, because the policy only proposes and the kernel disposes (0261)',
       'rule', 'db/checks/0149: a comparative metric read from an artifact only one arm produces measures which arm it is'),
    'caveats', (SELECT jsonb_agg(u.c ORDER BY u.o) FROM unnest(ARRAY[
       format('Times are quantized to the run''s %s-minute steps. A visit needs about three steps (arrive, plug, close) before it can leave, so coarse steps add time to every visit.', r.step_min),
       CASE WHEN r.horizon_h < 6 THEN format('The run covers %s hours, under 6, so per-day rates are not extrapolated from it.', round(r.horizon_h, 2)) END,
       'tier_group groups the generator''s visit archetypes. It is not yet a commercial tier.',
       'A visit still in the depot at the horizon is counted in in_depot_at_horizon and kept out of every time percentile.'])
       WITH ORDINALITY AS u(c, o) WHERE u.c IS NOT NULL))
    INTO v_out
  FROM r, dc;
  RETURN v_out;
END $fn$;

-- ── 2. the newest scorecard per run ──
CREATE VIEW public.ottoq_throughput_scores_latest
WITH (security_invoker = true) AS
SELECT DISTINCT ON (t.sim_run_id) t.*
  FROM public.ottoq_throughput_scores t
 ORDER BY t.sim_run_id, t.score_id DESC;
REVOKE ALL ON public.ottoq_throughput_scores_latest FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_throughput_scores_latest TO authenticated, service_role;
COMMENT ON VIEW public.ottoq_throughput_scores_latest IS
'0566. The newest scorecard per run in public.ottoq_throughput_scores (highest score_id). Read this, not the table: the table keeps every scorecard ever written, including superseded versions.';

-- ── 3. rescore every finished twin-depot run ──
DO $rescore$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN SELECT sr.sim_run_id
             FROM public.ottoq_sim_runs sr
            WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
              AND sr.status NOT IN ('running', 'paused', 'initializing')
              AND EXISTS (SELECT 1 FROM public.ottoq_visit_needs v WHERE v.sim_run_id = sr.sim_run_id)
            ORDER BY sr.started_at, sr.sim_run_id
  LOOP
    PERFORM public.ottoq_throughput_score_write(r.sim_run_id, 'rescore_0566');
    n := n + 1;
  END LOOP;
  RAISE NOTICE '0566: rescored % run(s)', n;
END $rescore$;

-- ── V1: every latest scorecard is 0566's, its step is the one the run took, and no short run carries a daily rate ──
DO $verify$
DECLARE
  v_bad     bigint;
  v_a       uuid;
  v_b       uuid;
  v_sc_a    jsonb;
  v_sc_b    jsonb;
BEGIN
  SELECT count(*) INTO v_bad FROM public.ottoq_throughput_scores_latest l
   WHERE l.scorecard->>'scorecard_version' <> '0566';
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0566 V1: % run(s) have a latest scorecard that is not 0566''s', v_bad;
  END IF;

  SELECT count(*) INTO v_bad
    FROM public.ottoq_throughput_scores_latest l
    JOIN public.ottoq_sim_runs sr USING (sim_run_id)
   WHERE sr.tick_count > 0
     AND (l.scorecard->>'step_min')::numeric
         <> round((extract(epoch FROM (sr.sim_clock_current - sr.sim_clock_start)) / 60.0 / sr.tick_count)::numeric, 2);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0566 V1: % scorecard(s) carry a step that is not the run''s own', v_bad;
  END IF;

  SELECT count(*) INTO v_bad FROM public.ottoq_throughput_scores_latest l
   WHERE (l.scorecard #>> '{run,horizon_h}')::numeric < 6
     AND (l.scorecard #> '{throughput,served_per_day}' <> 'null'::jsonb
          OR l.scorecard #> '{fast_chargers,turns_per_charger_per_day}' <> 'null'::jsonb);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0566 V1: % run(s) under 6 hours still carry a per-day rate', v_bad;
  END IF;

  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_scores_latest l, jsonb_array_elements(l.scorecard->'caveats') c
              WHERE c = 'null'::jsonb) THEN
    RAISE EXCEPTION '0566 V1: a caveat list carries a null';
  END IF;

  -- The certified day's step is the nominal 30 minutes; the determinism pair must still score identically.
  SELECT a.sim_run_id, b.sim_run_id INTO v_a, v_b
    FROM public.ottoq_sim_runs a
    JOIN public.ottoq_sim_runs b
      ON b.scenario_code = a.scenario_code AND b.random_seed = a.random_seed AND b.tick_count = a.tick_count
     AND b.started_at = a.started_at AND b.sim_run_id > a.sim_run_id
   WHERE a.depot_id = '11111111-1111-1111-1111-111111111111' AND b.depot_id = a.depot_id
     AND a.run_by = 'cert_harness' AND b.run_by = 'cert_harness'
     AND a.validation_status = 'passed' AND b.validation_status = 'passed'
     AND EXISTS (SELECT 1 FROM public.ottoq_throughput_scores_latest t WHERE t.sim_run_id = a.sim_run_id)
     AND EXISTS (SELECT 1 FROM public.ottoq_throughput_scores_latest t WHERE t.sim_run_id = b.sim_run_id)
   ORDER BY a.tick_count DESC, a.started_at DESC
   LIMIT 1;
  IF v_a IS NULL THEN
    RAISE NOTICE '0566 V1: no passed determinism pair survives on the twin depot; determinism unchecked here';
  ELSE
    SELECT scorecard INTO v_sc_a FROM public.ottoq_throughput_scores_latest WHERE sim_run_id = v_a;
    SELECT scorecard INTO v_sc_b FROM public.ottoq_throughput_scores_latest WHERE sim_run_id = v_b;
    IF (v_sc_a->>'step_min')::numeric <> 30 THEN
      RAISE EXCEPTION '0566 V1: the certified pair % steps % minutes, not 30', v_a, v_sc_a->>'step_min';
    END IF;
    v_sc_a := (v_sc_a - 'sim_run_id') || jsonb_build_object('charge_wait', (v_sc_a->'charge_wait') - 'sim_run_id');
    v_sc_b := (v_sc_b - 'sim_run_id') || jsonb_build_object('charge_wait', (v_sc_b->'charge_wait') - 'sim_run_id');
    IF v_sc_a IS DISTINCT FROM v_sc_b THEN
      RAISE EXCEPTION '0566 V1: the two arms of passed pair % / % score differently', v_a, v_b;
    END IF;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0566_the_scorecard_reads_the_step_a_run_actually_took', false, false,
  'Replaces the read function ottoq_throughput_scorecard (0565) so it reports the step a run actually took and extrapolates no daily rate from a run under 6 hours; adds the view ottoq_throughput_scores_latest and rescored finished runs. No engine path, runner or determinism pair calls either, so no certified digest can move.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
