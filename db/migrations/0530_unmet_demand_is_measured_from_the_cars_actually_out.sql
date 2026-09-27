-- migration-version: 20260927153902
-- migration-name:    unmet_demand_is_measured_from_the_cars_actually_out
--
-- 0530  **G255: nothing on the scorecard measured whether the depot met the work side's demand. On the day's full busy
--       day the work side wanted 451.3 car-hours on the road and the depot delivered 168.8: 62.6% unmet, from 10 AM
--       on. `ottoq_kpi_supply_gap(run)` measures it from the signed event stream against the dispatcher's own target,
--       and every dial arm now carries it.** `db/checks/0397`.
--
-- ══ §1 WHAT WAS MISSING ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The work side's demand is already in the engine: `ottoq_deploy_target_now` (0434) is the dispatcher's own target,
--   FLOOR(autonomous fleet x the hour's fraction at the resolved peak x the scenario's dispatch multiplier). KPI 1
--   (asset hours available) counts hours on dispatch records with no denominator, so a day that met a third of its
--   demand and a day that met all of it are told apart only by someone who knows what the target was. On `6ddd827e`
--   the depot had 37 of 45 cars out at 8 AM and 44 of 49 at 9, then 21 of 50 at 10, 13-14 of 48-49 from 11 to 1, and
--   7-10 of 49-52 from 2 to 5 PM (0397 §1). KPI 1 read 184.6 hours and no KPI read the gap.
--
-- ══ §2 WHAT THIS ADDS ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_kpi_supply_gap(p_run)`: each car's time in `deployed`, rebuilt from its `vehicle.state_changed`
--   transitions (every car has one at the run's first clock, so the timeline is complete), sampled each sim-minute of
--   the run against `ottoq_deploy_target_now` at that minute. Reported: demand, deployed and unmet car-hours (unmet =
--   the sum of max(0, target - deployed)), the unmet share, the peak shortfall, and the hour-by-hour mean target and
--   deployed count. A companion to the five, as 0501's charge wait is: physical on one side, the dispatcher's own
--   target on the other. The target reads today's fleet count and scenario multiplier, so a run whose fleet has since
--   changed is compared with today's fleet; the twin depot's fleet has been 116 throughout.
--   `ottoq_dial_arm_metrics` adds `demand_car_hours`, `deployed_car_hours`, `unmet_demand_car_hours`,
--   `unmet_demand_pct` and `peak_shortfall`, so an experiment can take unmet demand as its primary metric.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   A new read-only function; the arm metrics only gain keys. No arm can change.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0530 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_met text;
BEGIN
  IF to_regprocedure('public.ottoq_kpi_supply_gap(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0530 P2: public.ottoq_kpi_supply_gap(uuid) already exists';
  END IF;
  IF to_regprocedure('public.ottoq_deploy_target_now(uuid,uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0530 P2: the dispatcher''s target function (0434) is missing';
  END IF;
  v_met := pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);
  IF (length(v_met) - length(replace(v_met, '''visits_owing_a_charge'',      cw->''visits_owing_a_charge'')', '')))
       / length('''visits_owing_a_charge'',      cw->''visits_owing_a_charge'')') <> 1 THEN
    RAISE EXCEPTION '0530 P2: the arm metrics are not 0529''s';
  END IF;
  -- every car has a state at the run's first clock on the reference runs, so a timeline rebuilt from transitions is
  -- complete: one per car of the fleet on the full day, and on a harness arm
  IF (SELECT count(DISTINCT e.entity_id) FROM public.ottoq_events e JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
       WHERE e.sim_run_id = '6ddd827e-b549-43cf-8154-4d1bfb20cabf' AND (e.event_type || '') = 'vehicle.state_changed'
         AND e.payload->'diff' ? 'current_state' AND e.sim_clock_at <= r.sim_clock_start + interval '1 minute') <> 116 THEN
    RAISE EXCEPTION '0530 P2: not every car has a state at 6ddd827e''s first clock';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0530_pre', 'function', 'public', 'ottoq_dial_arm_metrics',
       pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure));

CREATE FUNCTION public.ottoq_kpi_supply_gap(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  -- 0530 (G255): the work side's demand against the cars actually out. Each car's time in `deployed` is rebuilt from its
  -- signed state transitions; each sim-minute of the run is compared with the dispatcher's own target at that minute.
  -- MATERIALIZED where a CTE feeds the per-minute count: inlined, the interval set is rebuilt from the events once per
  -- minute, and a full day took 32 s instead of 91 ms (0397 §2).
  WITH r AS MATERIALIZED (SELECT sim_run_id, depot_id, sim_clock_start, sim_clock_current
                            FROM public.ottoq_sim_runs WHERE sim_run_id = p_run),
  tr AS (SELECT e.entity_id AS car, e.sim_clock_at AS t, e.event_seq,
                e.payload->'diff'->'current_state'->>'to' AS st
           FROM public.ottoq_events e
          -- the run as a parameter, and `|| ''` keeps the planner on the per-run index (0527, 0396 §6)
          WHERE e.sim_run_id = p_run AND (e.event_type || '') = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'),
  iv AS (SELECT car, st, t AS t0, lead(t) OVER (PARTITION BY car ORDER BY t, event_seq) AS t1 FROM tr),
  dep AS MATERIALIZED (SELECT iv.car, iv.t0, COALESCE(iv.t1, r.sim_clock_current) AS t1 FROM iv, r
                        WHERE iv.st = 'deployed' AND COALESCE(iv.t1, r.sim_clock_current) > iv.t0),
  mins AS (SELECT gs AS m FROM r, generate_series(r.sim_clock_start, r.sim_clock_current - interval '1 minute', interval '1 minute') gs),
  hours AS (SELECT DISTINCT date_trunc('hour', m) AS h FROM mins),
  tgt AS MATERIALIZED (SELECT h.h, public.ottoq_deploy_target_now(r.sim_run_id, r.depot_id, h.h) AS target FROM hours h, r),
  per_min AS MATERIALIZED (SELECT mins.m, t.target, (SELECT count(*) FROM dep WHERE dep.t0 <= mins.m AND dep.t1 > mins.m) AS deployed
                             FROM mins JOIN tgt t ON t.h = date_trunc('hour', mins.m))
  SELECT CASE WHEN (SELECT count(*) FROM r) = 0 THEN NULL ELSE jsonb_build_object(
    'sim_run_id', p_run,
    'minutes', (SELECT count(*) FROM per_min),
    'demand_car_hours', (SELECT round(sum(target) / 60.0, 1) FROM per_min),
    'deployed_car_hours', (SELECT round(sum(deployed) / 60.0, 1) FROM per_min),
    'unmet_demand_car_hours', (SELECT round(sum(GREATEST(0, target - deployed)) / 60.0, 1) FROM per_min),
    'unmet_demand_pct', (SELECT round(100.0 * sum(GREATEST(0, target - deployed)) / NULLIF(sum(target), 0), 1) FROM per_min),
    'peak_shortfall', (SELECT max(target - deployed) FROM per_min),
    'by_hour_ct', (SELECT jsonb_object_agg(hh, jsonb_build_object('target', tg, 'deployed', dp) ORDER BY hh) FROM (
                     SELECT to_char(m AT TIME ZONE 'America/Chicago', 'HH24') AS hh, round(avg(target), 0) AS tg,
                            round(avg(deployed), 0) AS dp FROM per_min GROUP BY 1) z),
    'meaning', 'Demand is the dispatcher''s own target (ottoq_deploy_target_now: fleet x the hour''s fraction at the '
               'resolved peak x the scenario''s multiplier), read each sim-minute; deployed is the cars in state '
               'deployed at that minute, rebuilt from the signed vehicle.state_changed stream. Unmet = the sum of '
               'max(0, target - deployed). A companion to the five KPIs; the target reads today''s fleet and scenario.')
  END
$function$;

COMMENT ON FUNCTION public.ottoq_kpi_supply_gap(uuid) IS
  '0530 (G255). The work side''s demand against the cars actually out, per sim-minute, from the signed event stream and '
  'the dispatcher''s own target. Read one run per call (0396 §6).';

-- ── the arm metrics: unmet demand travels with every pair ──
DO $patch_metrics$
DECLARE
  v_def text;
  v_old text := $o$'visits_owing_a_charge',      cw->'visits_owing_a_charge')
          FROM (SELECT public.ottoq_kpi_charge_wait(p_run) AS cw) z);$o$;
  v_new text := $n$'visits_owing_a_charge',      cw->'visits_owing_a_charge')
          FROM (SELECT public.ottoq_kpi_charge_wait(p_run) AS cw) z)
    -- 0530 (G255): the work side's demand against the cars actually out; an experiment's primary can be the unmet part
    || (SELECT jsonb_build_object(
          'demand_car_hours',       sg->'demand_car_hours',
          'deployed_car_hours',     sg->'deployed_car_hours',
          'unmet_demand_car_hours', sg->'unmet_demand_car_hours',
          'unmet_demand_pct',       sg->'unmet_demand_pct',
          'peak_shortfall',         sg->'peak_shortfall')
          FROM (SELECT public.ottoq_kpi_supply_gap(p_run) AS sg) y);$n$;
  n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0530: metrics patch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch_metrics$;

DO $verify$
DECLARE v_met text;
BEGIN
  v_met := pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);
  -- V1: the function exists and the arm metrics carry unmet demand
  IF to_regprocedure('public.ottoq_kpi_supply_gap(uuid)') IS NULL
     OR position('''unmet_demand_car_hours'', sg->''unmet_demand_car_hours''' IN v_met) = 0
     OR position('public.ottoq_kpi_supply_gap(p_run)' IN v_met) = 0 THEN
    RAISE EXCEPTION '0530 V1: the function or the arm metrics are not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule): no arm can change.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0530_unmet_demand_is_measured_from_the_cars_actually_out', false, false,
  'A new read-only function (the work side''s demand against the cars actually out, G255) and new keys in the dial arm '
  'metrics. Not on the certified path; no arm can change.', now())
ON CONFLICT (name) DO NOTHING;

-- V3: read-only. (a) 6ddd827e: 553 minutes, demand 451.3 car-hours, deployed 168.8, unmet 282.5 (62.6%), peak
--     shortfall 46. (b) The arm metrics of G240's pair 76 carry the same figures the function reads for that arm. (c)
--     One full day reads in under 2 seconds (91 ms when measured).
DO $v3$
DECLARE v_msg text; v_t0 timestamptz; v_ms numeric; v_sg jsonb; v_arm jsonb; v_fn jsonb;
BEGIN
  BEGIN
    v_t0 := clock_timestamp();
    v_sg := public.ottoq_kpi_supply_gap('6ddd827e-b549-43cf-8154-4d1bfb20cabf');
    v_ms := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
    IF (v_sg->>'minutes')::int <> 553 OR (v_sg->>'demand_car_hours')::numeric <> 451.3
       OR (v_sg->>'deployed_car_hours')::numeric <> 168.8 OR (v_sg->>'unmet_demand_car_hours')::numeric <> 282.5
       OR (v_sg->>'unmet_demand_pct')::numeric <> 62.6 OR (v_sg->>'peak_shortfall')::int <> 46 OR v_ms > 2000 THEN
      RAISE EXCEPTION '0530 V3 FAILED (a, c): 6ddd827e read % in % ms', v_sg - 'meaning' - 'by_hour_ct', round(v_ms);
    END IF;
    SELECT public.ottoq_dial_arm_metrics(p.run_a, x.depot_id, NULL), public.ottoq_kpi_supply_gap(p.run_a)
      INTO v_arm, v_fn
      FROM public.ottoq_dial_pair_ledger p JOIN public.ottoq_dial_experiments x ON x.experiment_id = p.experiment_id
     WHERE p.pair_id = 76;
    IF v_arm->'unmet_demand_car_hours' IS DISTINCT FROM v_fn->'unmet_demand_car_hours'
       OR v_arm->'deployed_car_hours' IS DISTINCT FROM v_fn->'deployed_car_hours'
       OR v_arm->'unmet_demand_car_hours' IS NULL THEN
      RAISE EXCEPTION '0530 V3 FAILED (b): the arm metrics read % against the function''s %',
        v_arm->'unmet_demand_car_hours', v_fn->'unmet_demand_car_hours';
    END IF;
    RAISE EXCEPTION '0530 V3 PASSED: 6ddd827e demand % car-hours, deployed %, unmet % (% pct), peak shortfall %, in % ms; pair 76''s control arm unmet %',
      v_sg->'demand_car_hours', v_sg->'deployed_car_hours', v_sg->'unmet_demand_car_hours', v_sg->'unmet_demand_pct',
      v_sg->'peak_shortfall', round(v_ms), v_arm->'unmet_demand_car_hours';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0530 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0530 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0530_pre' as is; then
--   DROP FUNCTION public.ottoq_kpi_supply_gap(uuid).
COMMIT;
