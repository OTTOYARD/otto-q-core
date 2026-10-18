-- Stub for db/migrations/0754 (tests/test_arm_half_hour_sql.py): the sweep scorer's 30-minute peak, as live. It holds
-- what public.ottoq_arm_peak_profile and public.ottoq_dial_arm_metrics read, with every table and function they do not
-- need for the peak reduced to a constant, and the two scorers themselves byte for byte as live (prosrc md5 917cfc1b and
-- 8a852c7d, read 2026-10-18 between 2:01 and 2:08 AM CT). Loaded on its own, in an empty database.

CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS extensions;

CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY, depot_id uuid NOT NULL, status text NOT NULL DEFAULT 'completed',
  sim_clock_start timestamptz NOT NULL, sim_clock_current timestamptz, tick_count integer);

CREATE TABLE public.site_energy_snapshots (
  snapshot_id bigserial PRIMARY KEY, sim_run_id uuid, depot_id uuid, timestamp timestamptz NOT NULL,
  grid_import_kw numeric, bess_output_kw numeric, current_rate_per_kwh numeric);

-- the twin depot's NES demand rows, as live (block 1,000 kW; summer 21.40 / 21.78, winter 20.34 / 20.73 per kW)
CREATE TABLE public.ottoq_depot_tariffs (
  tariff_row_id bigserial PRIMARY KEY, depot_id uuid NOT NULL, active boolean NOT NULL DEFAULT true, season text,
  season_months integer[] NOT NULL, effective_from date NOT NULL, block_kw numeric, demand_first_block_usd_kw numeric,
  demand_excess_usd_kw numeric);
INSERT INTO public.ottoq_depot_tariffs (depot_id, season, season_months, effective_from, block_kw,
                                        demand_first_block_usd_kw, demand_excess_usd_kw)
VALUES ('11111111-1111-1111-1111-111111111111', 'summer', '{6,7,8,9}', '2024-10-01', 1000, 21.40, 21.78),
       ('11111111-1111-1111-1111-111111111111', 'winter', '{1,2,3,4,5,10,11,12}', '2024-10-01', 1000, 20.34, 20.73);

-- what the scorer reads beside the energy, empty or constant
CREATE TABLE public.ottoq_ab_runs (
  sim_run_id uuid, scored_at timestamptz, deploys_total integer, trips_completed integer, vehicles_turned_around integer,
  median_turnaround_min numeric, ready_or_deployed_pct numeric, throughput_per_hr numeric, charge_sessions integer);
CREATE TABLE public.ottoq_bess_units (depot_id uuid, roundtrip_efficiency_pct numeric, current_soc_kwh numeric);
INSERT INTO public.ottoq_bess_units VALUES ('11111111-1111-1111-1111-111111111111', 0.96, 1500);
CREATE TABLE public.ottoq_rule_evaluations (sim_run_id uuid, passed boolean, severity text);
CREATE TABLE public.ottoq_rule_evaluation_effect (sim_run_id uuid, passed boolean, severity text, effect text);
CREATE TABLE public.ottoq_dr_calls (sim_run_id uuid);
CREATE TABLE public.ottoq_decisions (sim_run_id uuid, action_context text, outcome_status text);
CREATE TABLE public.ottoq_charge_duration_ledger (
  sim_run_id uuid, stopped_reason text, booked_to timestamptz, ended_at timestamptz, charger_type text);

CREATE FUNCTION public.ottoq_kpi_five(p_run uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.ottoq_run_reward_terms(p_kpi jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.ottoq_kpi_charge_wait(p_run uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.ottoq_kpi_supply_gap(p_run uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric) RETURNS numeric
  LANGUAGE sql STABLE AS $$ SELECT p_default $$;

-- the two scorers, as live
CREATE OR REPLACE FUNCTION public.ottoq_arm_peak_profile(p_run uuid, p_depot uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
/* 0577: the sweep scorer's 30-minute peak and monthly demand charge (ottoq_dial_arm_metrics, 0439: the same samples,
   forward window and tariff row), over the windows that start at least 0, 30, 60, 90, 120, 180 and 240 minutes after the run's
   sim_clock_start, and the minute each peak window starts. Read-only. At 0 it equals the scorer (0577 V1). */
WITH r AS (
  SELECT x.sim_clock_start AS t0,
         EXTRACT(MONTH FROM (x.sim_clock_start AT TIME ZONE 'America/Chicago'))::int AS mon
    FROM public.ottoq_sim_runs x WHERE x.sim_run_id = p_run
), w AS (
  SELECT s.t, avg(s.g) OVER (ORDER BY s.t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30
    FROM (SELECT e.timestamp AS t, GREATEST(COALESCE(e.grid_import_kw, 0), 0) AS g
            FROM public.site_energy_snapshots e
           WHERE e.sim_run_id = p_run AND e.depot_id = p_depot) s
), tar AS (
  SELECT t.block_kw, t.demand_first_block_usd_kw AS r1, t.demand_excess_usd_kw AS r2
    FROM public.ottoq_depot_tariffs t, r
   WHERE t.depot_id = p_depot AND t.active AND r.mon = ANY (t.season_months)
   ORDER BY t.effective_from DESC LIMIT 1
), o AS (
  SELECT m.k, (SELECT max(w.g30) FROM w, r WHERE w.t >= r.t0 + make_interval(mins => m.k)) AS peak
    FROM unnest(ARRAY[0, 30, 60, 90, 120, 180, 240]) AS m(k)
), o2 AS (
  SELECT o.k, o.peak,
         (SELECT round(EXTRACT(EPOCH FROM min(w.t - r.t0)) / 60.0)::int FROM w, r
           WHERE w.t >= r.t0 + make_interval(mins => o.k) AND w.g30 = o.peak)                         AS starts_min,
         CASE WHEN tar.r1 IS NULL OR o.peak IS NULL THEN NULL
              ELSE tar.r1 * LEAST(o.peak, COALESCE(tar.block_kw, o.peak))
                   + COALESCE(tar.r2, tar.r1) * GREATEST(0, o.peak - COALESCE(tar.block_kw, o.peak)) END AS demand
    FROM o LEFT JOIN tar ON true
)
SELECT jsonb_build_object(
  'offsets_min',             jsonb_agg(o2.k ORDER BY o2.k),
  'peak_30min_kw',           jsonb_object_agg(o2.k::text, round(o2.peak, 1)),
  'demand_charge_usd_month', jsonb_object_agg(o2.k::text, round(o2.demand, 2)),
  'starts_min',              jsonb_object_agg(o2.k::text, o2.starts_min))
  FROM o2
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_dial_arm_metrics(p_run uuid, p_depot uuid, p_soc_start_kwh numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0439: what an arm cost and what it produced, read BEFORE its teardown. Energy is integrated over the arm's own
   snapshots, time-weighted; the peak is the NES NCP_30min basis (highest 30-consecutive-minute mean of grid
   import); the demand charge is the depot's own tariff for the sim month, amortised over the day plan's
   bess_plan_demand_amortization_days; battery wear is discharged kWh x bess_plan_degradation_usd_kwh; and the
   battery's end state is charged back at what refilling it would cost (cheapest rate the arm saw / round trip),
   so a policy that simply ends the day emptier cannot look cheaper for it. c_tz is the same constant 0435 uses. */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  r ottoq_sim_runs%ROWTYPE; v_ab ottoq_ab_runs%ROWTYPE;
  v_kpi jsonb; v_terms jsonb; v_month int;
  v_grid_kwh numeric; v_cost numeric; v_peak30 numeric; v_dis numeric; v_chg numeric; v_min_rate numeric; v_samples int;
  v_block numeric; v_r1 numeric; v_r2 numeric; v_demand numeric;
  v_amort numeric; v_deg numeric; v_rt_raw numeric; v_rt numeric; v_soc_end numeric; v_terminal numeric;
  v_evals bigint; v_fail bigint; v_crit bigint; v_crit_ref bigint; v_crit_unp bigint; v_dr int; v_defer bigint;
  v_bk_n int; v_bk_out int; v_bk_n_dc int; v_bk_out_dc int; v_bk_n_l2 int; v_bk_out_l2 int; v_bk_p50 numeric;   -- 0520
BEGIN
  SELECT * INTO r FROM ottoq_sim_runs WHERE sim_run_id = p_run;
  IF NOT FOUND THEN RAISE EXCEPTION 'ottoq_dial_arm_metrics: run % not found', p_run; END IF;

  v_kpi   := public.ottoq_kpi_five(p_run);
  v_terms := public.ottoq_run_reward_terms(v_kpi);

  WITH s AS (
    SELECT e.timestamp AS t, GREATEST(COALESCE(e.grid_import_kw, 0), 0) AS g, COALESCE(e.bess_output_kw, 0) AS b,
           e.current_rate_per_kwh AS rate,
           EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt
      FROM site_energy_snapshots e
     WHERE e.sim_run_id = p_run AND e.depot_id = p_depot
  ), s2 AS (
    -- the last sample has no successor; it holds for the arm's mean interval. Gaps beyond an hour are capped.
    SELECT t, g, b, rate, LEAST(COALESCE(dt, (SELECT avg(dt) FROM s WHERE dt IS NOT NULL), 0), 1.0) AS dt FROM s
  ), w AS (
    SELECT avg(g) OVER (ORDER BY t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30 FROM s2
  )
  SELECT count(*), sum(g * dt), sum(g * dt * rate), (SELECT max(g30) FROM w),
         sum(GREATEST(b, 0) * dt), sum(GREATEST(-b, 0) * dt), min(rate)
    INTO v_samples, v_grid_kwh, v_cost, v_peak30, v_dis, v_chg, v_min_rate
    FROM s2;

  v_month := EXTRACT(MONTH FROM (r.sim_clock_start AT TIME ZONE c_tz))::int;
  SELECT t.block_kw, t.demand_first_block_usd_kw, t.demand_excess_usd_kw INTO v_block, v_r1, v_r2
    FROM ottoq_depot_tariffs t
   WHERE t.depot_id = p_depot AND t.active AND v_month = ANY (t.season_months)
   ORDER BY t.effective_from DESC LIMIT 1;
  v_demand := CASE WHEN v_r1 IS NULL OR v_peak30 IS NULL THEN NULL
                   ELSE v_r1 * LEAST(v_peak30, COALESCE(v_block, v_peak30))
                        + COALESCE(v_r2, v_r1) * GREATEST(0, v_peak30 - COALESCE(v_block, v_peak30)) END;

  v_amort := GREATEST(1, COALESCE(public.ottoq_policy_get(p_run, 'bess_plan_demand_amortization_days', 30), 30));
  v_deg   := GREATEST(0, COALESCE(public.ottoq_policy_get(p_run, 'bess_plan_degradation_usd_kwh', 0.02), 0.02));
  SELECT avg(b.roundtrip_efficiency_pct), sum(b.current_soc_kwh) INTO v_rt_raw, v_soc_end
    FROM ottoq_bess_units b WHERE b.depot_id = p_depot;
  -- G172: the column holds a fraction (0.96) under a percent's name; read either, exactly as 0435 does
  v_rt := LEAST(1.0, GREATEST(0.5, CASE WHEN v_rt_raw IS NULL THEN 0.96 WHEN v_rt_raw <= 1 THEN v_rt_raw ELSE v_rt_raw / 100 END));
  v_terminal := CASE WHEN p_soc_start_kwh IS NULL OR v_soc_end IS NULL OR v_min_rate IS NULL THEN NULL
                     ELSE (p_soc_start_kwh - v_soc_end) * v_min_rate / v_rt END;

  SELECT count(*), count(*) FILTER (WHERE NOT passed), count(*) FILTER (WHERE NOT passed AND severity = 'safety_critical')
    INTO v_evals, v_fail, v_crit
    FROM ottoq_rule_evaluations WHERE sim_run_id = p_run;
  -- 0430: what the shield recommended beside what the engine did. A safety-critical failure the engine REFUSED
  -- did not happen; any other effect (recorded_only, an advisory posture, an unresolvable one) may have.
  SELECT count(*) FILTER (WHERE e.effect = 'refused'), count(*) FILTER (WHERE e.effect IS DISTINCT FROM 'refused')
    INTO v_crit_ref, v_crit_unp
    FROM public.ottoq_rule_evaluation_effect e
   WHERE e.sim_run_id = p_run AND NOT e.passed AND e.severity = 'safety_critical';
  SELECT count(*) INTO v_dr FROM ottoq_dr_calls WHERE sim_run_id = p_run;
  SELECT count(*) INTO v_defer FROM ottoq_decisions
   WHERE sim_run_id = p_run AND action_context = 'stall_assignment' AND outcome_status = 'deferred_site_power_cap';
  SELECT * INTO v_ab FROM ottoq_ab_runs WHERE sim_run_id = p_run ORDER BY scored_at DESC LIMIT 1;
  -- 0520 (G240): the booking window's own measure. Of the arm's completed charges that held a booking, how many
  -- outlasted it -- read from 0514's ledger, which records each stop's booking as it stood at the stop. The calendar
  -- itself cannot answer this at the end of an arm: a booking's end moves after its charge stops.
  SELECT count(*), count(*) FILTER (WHERE l.ended_at > l.booked_to),
         count(*) FILTER (WHERE l.charger_type = 'dcfc'), count(*) FILTER (WHERE l.charger_type = 'dcfc' AND l.ended_at > l.booked_to),
         count(*) FILTER (WHERE l.charger_type = 'l2'),   count(*) FILTER (WHERE l.charger_type = 'l2' AND l.ended_at > l.booked_to),
         percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (l.ended_at - l.booked_to)) / 60.0)
           FILTER (WHERE l.ended_at > l.booked_to)
    INTO v_bk_n, v_bk_out, v_bk_n_dc, v_bk_out_dc, v_bk_n_l2, v_bk_out_l2, v_bk_p50
    FROM public.ottoq_charge_duration_ledger l
   WHERE l.sim_run_id = p_run AND l.stopped_reason = 'completed' AND l.booked_to IS NOT NULL;

  RETURN jsonb_build_object(
    -- the five 2.9 KPIs exactly as the reward reads them (per-day KPIs at their maximum day), and the safety floor
    'asset_hours_available_per_day',         v_terms->'asset_hours_available_per_day',
    'service_point_turns_per_point_per_day', v_terms->'service_point_turns_per_point_per_day',
    'peak_site_kw',                          v_terms->'peak_site_kw',
    'touch_events_per_turn',                 v_terms->'touch_events_per_turn',
    'p95_time_to_service_min',               v_terms->'p95_time_to_service_min',
    'returns_unserved',                      NULLIF(v_kpi->>'returns_unserved', '')::numeric,
    -- 0644 (G392): returned cars with no operation started by the arm's end, unserved plus deferred past it
    'returns_not_served',                    NULLIF(v_kpi->>'returns_unserved', '')::numeric
                                             + NULLIF(v_kpi #>> '{audit,p95_time_to_service_min,returns_deferred_beyond_horizon}', '')::numeric,
    'kpi_purged',                            (v_kpi->'purged') IS NOT NULL AND jsonb_typeof(v_kpi->'purged') <> 'null',
    -- the shield
    'rule_evaluations', v_evals, 'rule_failures', v_fail, 'safety_critical_failures', v_crit,
    'safety_critical_refused', v_crit_ref, 'safety_critical_unprevented', v_crit_unp,
    -- operations, from the arm's ottoq_ab_runs row
    'deploys', v_ab.deploys_total, 'trips_completed', v_ab.trips_completed,
    'vehicles_turned_around', v_ab.vehicles_turned_around, 'median_turnaround_min', v_ab.median_turnaround_min,
    'ready_or_deployed_pct', v_ab.ready_or_deployed_pct, 'throughput_per_hr', v_ab.throughput_per_hr,
    'charge_sessions', v_ab.charge_sessions,
    -- energy, realised
    'energy_samples', v_samples,
    'grid_import_kwh', round(v_grid_kwh, 2), 'energy_cost_usd', round(v_cost, 2),
    'peak_30min_kw', round(v_peak30, 1), 'demand_charge_usd_month', round(v_demand, 2),
    'demand_usd_per_day', round(v_demand / v_amort, 2),
    'bess_discharged_kwh', round(v_dis, 1), 'bess_charged_kwh', round(v_chg, 1),
    'bess_degradation_usd', round(v_dis * v_deg, 2),
    'soc_start_kwh', round(p_soc_start_kwh, 1), 'soc_end_kwh', round(v_soc_end, 1),
    'terminal_soc_usd', round(v_terminal, 2),
    'site_cost_usd_per_day', round(v_cost + v_demand / v_amort + v_dis * v_deg + v_terminal, 2),
    'dr_calls', v_dr, 'dr_deferred_assignments', v_defer,
    -- provenance of the arithmetic
    'amortization_days', v_amort, 'degradation_usd_kwh', v_deg, 'roundtrip', v_rt,
    'sim_min_per_tick', round(EXTRACT(EPOCH FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / NULLIF(r.tick_count, 0), 4),
    'ticks', r.tick_count)
    -- 0520 (G240): charges that outlasted the booking they held; lower is better
    || jsonb_build_object(
    'charges_completed_booked', v_bk_n, 'charges_outlasting_booking', v_bk_out,
    'charge_outlast_pct',      round(100.0 * v_bk_out / NULLIF(v_bk_n, 0), 2),
    'charge_outlast_pct_dcfc', round(100.0 * v_bk_out_dc / NULLIF(v_bk_n_dc, 0), 2),
    'charge_outlast_pct_l2',   round(100.0 * v_bk_out_l2 / NULLIF(v_bk_n_l2, 0), 2),
    'charge_overrun_p50_min',  round(v_bk_p50, 1))
    -- 0529 (G254): the wait for a charger (0501), beside KPI 5 and reported with every arm; not a guardrail
    || (SELECT jsonb_build_object(
          'charge_wait_p50_min',        cw->'p50_wait_min',
          'charge_wait_p95_min',        cw->'p95_wait_min',
          'charge_wait_p95_floor_min',  cw->'p95_wait_floor_min',
          'charges_waiting_at_horizon', cw->'waiting_at_horizon',
          'visits_owing_a_charge',      cw->'visits_owing_a_charge')
          FROM (SELECT public.ottoq_kpi_charge_wait(p_run) AS cw) z)
    -- 0530 (G255): the work side's demand against the cars actually out; an experiment's primary can be the unmet part
    || (SELECT jsonb_build_object(
          'demand_car_hours',       sg->'demand_car_hours',
          'deployed_car_hours',     sg->'deployed_car_hours',
          'unmet_demand_car_hours', sg->'unmet_demand_car_hours',
          'unmet_demand_pct',       sg->'unmet_demand_pct',
          'peak_shortfall',         sg->'peak_shortfall')
          FROM (SELECT public.ottoq_kpi_supply_gap(p_run) AS sg) y);
END
$function$;
