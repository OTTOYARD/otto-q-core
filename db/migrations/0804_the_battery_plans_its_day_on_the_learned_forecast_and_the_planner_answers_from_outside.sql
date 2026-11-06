-- migration-version: PENDING
-- migration-name:    the_battery_plans_its_day_on_the_learned_forecast_and_the_planner_answers_from_outside
--
-- 0804  **The battery plans its day on the learned forecast, and the planner answers from outside.** (B1, the production
--        battery planner's second piece)
--
-- ══ §0 WHY NOW ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-11-05: "let's not sleep on the agent/AI with BESS usage angle (Forward planning/analyzing, etc.)"; and
--   2026-11-06 (read by 13:20 UTC): "Yes, just keep building", to a report whose asks included the go-ahead for the
--   production battery planner. 0803 gave the depot a load forecast learned from its own days. This file puts it in front
--   of the planner the research lab measured.
--
-- ══ §1 WHAT THE RESEARCH LAB FOUND, AND WHAT PRODUCTION LACKS ═══════════════════════════════════════════════════════
--
--   On six 36-hour lab days billed from 6 PM, a planner that budgets the battery over the whole horizon (a linear program,
--   lab/research/p2_capacity/battery_lp.py) on the learned forecast plus its 80th-percentile out-of-sample miss saved
--   $226 a day on the day plan, on all six seeds (planner_36h_lab_2026-11-06.md). The planner cannot run in the database
--   (no LP solver there); ottoq-intelligence is where the depot's solvers run, called through an edge function, and it now
--   carries the lab's planner as POST /optimize/battery-plan (app/optimizers/battery_planner.py, ottoyard/ottoq-intelligence
--   claude/battery-planner: on three ticks of a lab day it returns the lab planner's objective to 1e-6 and its setpoints to
--   the 0.1 kW the lab stored). The orchestrator already follows an outside plan (FR-1, energy_mpc_follow = 1), and since
--   0799 only while it is fresh and never during a demand-response call. What is missing is everything between: the
--   request, the call and the landing. ottoq_energy_mpc_replan, the old request builder, forecasts crudely, prices every
--   step at a flat $0.06, holds no reserve, waits on the answer with pg_sleep and carries a credential as a default
--   argument; nothing calls it. This file leaves it alone and builds the seam beside it.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_bess_planner_request(run, depot, clock, day_plan, model): the planner's request, as
--       /optimize/battery-plan reads it, or NULL when the depot has no usable learned forecast (0803) or no battery:
--         the site before the battery, per step of bess_planner_step_min (5) over bess_planner_horizon_h (36) or to the
--           run's end: the learned forecast's upper band for the next 8 half hours, then the depot's learned day (its mean
--           by half hour, or with bess_planner_beyond = 1 its quantile across days), the day plan's own net forecast
--           where the depot has no day for a half hour; the next half hour never under what the site drew last (the lab's
--           guard);
--         the energy price per step (the twin's own tariff lookup, as the day plan and the bill read it);
--         the billing periods: from the later of the month's start and the run's start plus bess_plan_bill_from_min (the
--           day plan's window), with the peak already billed (the day plan's ratchet) and a margin of max(100 kW, 10% of
--           it) under which every half hour wholly in the future is planned; a new month, a new period;
--         the grid draws of the last half hour (for the windows that straddle now);
--         the battery as it stands, its floor and ceiling, its power and its one-way efficiency (G172's fraction);
--         a floor per step from the demand-response reserve as the depot's dials hold it (bess_plan_dr_reserve_kwh from
--           bess_plan_dr_reserve_lead_h before the window, declining to nothing through it, summer only), read at each
--           step's own clock, so a horizon past midnight holds tomorrow's as tomorrow comes;
--         the day plan's demand rate per kW, its replacement cost (the energy left at the end) and its wear per kWh.
--   (b) public.ottoq_bess_planner_fire(run, depot, clock, tick, day_plan): writes the request into a 'pending' row of
--       ottoq_energy_plan (source 'bess_planner', plan_start_clock the next step's end, so the next tick reads its step 0)
--       and asks the edge function ottoq-battery-planner for it with net.http_post (fire and forget, the anon key from
--       the vault as the agent's fire does). The function is handed only the plan's id; it reads the request from the row,
--       so a caller with the anon key can only make a plan the depot already asked for. No key, no call: the row waits.
--   (c) public.ottoq_bess_planner_land(plan, response, http_status, latency): the edge function's answer, checked before
--       it is taken (HTTP 200, solved, one setpoint a step, every setpoint inside the battery's power) and landed as the
--       run's one 'ready' plan, older ones superseded; an answer older than a plan already landed is superseded on arrival;
--       anything else 'failed', with its reason. Every call is a row of ottoq_model_call_ledger (provider
--       'intelligence_battery_planner', role 'planner'). The service role's alone.
--   (d) One anchored insertion in public.ottoq_energy_orchestrate, before its last RETURN: with bess_planner_enabled on,
--       every bess_planner_every_ticks ticks the orchestrator fires the next plan from the plan it just solved, inside its
--       own block (a failure is a warning, never a stopped tick). The battery follows a landed plan only where
--       energy_mpc_follow is on too, under 0799's rules, inside its own limits; otherwise the day plan decides, as it does
--       until the first plan lands and whenever the planner is late. A plan is followed at the step its clock is in, so a
--       plan that lands a tick or two late is followed from its later steps; one older than energy_mpc_max_plan_age_steps
--       steps (0799, 3 at the default: 15 minutes of 5-minute steps) is not. A fast demo whose ticks outrun the edge
--       function's round trip would leave the day plan deciding; the ledger's latency says when to raise that dial.
--   (e) Five dials, all a person's (rule 10), none agent-writable: bess_planner_enabled (0..1, 0), bess_planner_every_ticks
--       (1..12, 1), bess_planner_horizon_h (2..48, 36), bess_planner_step_min (1..30, 5; a divisor of 30 or 5 is used) and
--       bess_planner_beyond (0..1, 0).
--   The cars are never touched: the plan moves only the battery's setpoint, and the orchestrator's charge cap for the
--   fleet is computed as before. With bess_planner_enabled off nothing runs.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; 0799 and 0803 applied, the orchestrator the body 0803 leaves on 0799's
--   (prosrc md5 5d607e3c); none of this file's functions or dials exists. The pre-image to ottoq_schema_snapshots as
--   '0804_pre'. The anchor matches once, read with bare newlines.
--   V1 the orchestrator less its insertion is its pre-image. V2 on the twin's latest run, rolled back with its rows: with
--   a synthetic learned forecast the request is well formed (as many prices, floors and loads as steps; the floors inside
--   the battery; a billing period), the fire writes one pending plan carrying it, a good answer lands it 'ready', a second
--   good answer for an older plan is superseded on arrival, and a bad one fails with its reason; each a ledger row.
--   Skipped with a notice when the twin depot has no run. V3 the patched orchestrator is byte for byte the body the
--   research lab ran.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: with bess_planner_enabled off (the default and every certified arm)
--   the orchestrator decides exactly as before; with it on, it writes engine rows (ottoq_energy_plan) that the battery
--   reads only where energy_mpc_follow is on, which no certified arm sets.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0804_pre';
--   DROP FUNCTION public.ottoq_bess_planner_land(uuid,jsonb,integer,integer),
--     public.ottoq_bess_planner_fire(uuid,uuid,timestamptz,bigint,jsonb),
--     public.ottoq_bess_planner_request(uuid,uuid,timestamptz,jsonb,bigint);
--   DELETE FROM public.ottoq_policy_params WHERE param_key LIKE 'bess_planner_%';
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key LIKE 'bess_planner_%';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0804_the_battery_plans_its_day_on_the_learned_forecast_and_the_planner_answers_from_outside'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0804 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0804_the_battery_plans_its_day_on_the_learned_forecast_and_the_planner_answers_from_outside') THEN
    RAISE EXCEPTION '0804 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0799_plan_follow_yields_to_a_live_grid_call_and_follows_a_plan_only_while_it_is_fresh')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                     WHERE name = '0803_the_battery_learns_its_load_forecast_from_the_depots_own_days') THEN
    RAISE EXCEPTION '0804 P1: 0799 (plan-follow only while fresh, never in a call) and 0803 (the learned forecast) come first';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'))
     IS DISTINCT FROM '5d607e3cfc88c7cc5a459407b4445532' THEN
    RAISE EXCEPTION '0804 P1: public.ottoq_energy_orchestrate is not the body 0803 leaves on 0799''s (5d607e3c)';
  END IF;
  IF to_regproc('public.ottoq_bess_planner_request') IS NOT NULL OR to_regproc('public.ottoq_bess_planner_fire') IS NOT NULL
     OR to_regproc('public.ottoq_bess_planner_land') IS NOT NULL THEN
    RAISE EXCEPTION '0804 P1: a function of this file already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key LIKE 'bess_planner_%') THEN
    RAISE EXCEPTION '0804 P1: a bess_planner_ dial is already catalogued';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0804_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure;

-- ══ (e) the dials ═══════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bess_planner_enabled',
        '0804 (B1): 1 = the energy orchestrator asks the battery planner (ottoq-intelligence /optimize/battery-plan, through '
        'the edge function ottoq-battery-planner) for the battery''s plan over the horizon, on the depot''s learned load '
        'forecast (0803), every bess_planner_every_ticks ticks. The battery follows a landed plan only where '
        'energy_mpc_follow is 1 (0799: only while fresh, never during a demand-response call); otherwise the day plan '
        'decides. It moves only the battery. 0 = no request. A person''s dial (rule 10).',
        0, 0, 1, 'public.ottoq_energy_orchestrate', false),
       ('bess_planner_every_ticks',
        '0804 (B1): the battery planner is asked every this many ticks (1 = every tick). A person''s dial.',
        1, 1, 12, 'public.ottoq_energy_orchestrate', false),
       ('bess_planner_horizon_h',
        '0804 (B1): hours the battery planner plans over, or to the run''s end if sooner (36 = the research lab''s 36-hour '
        'days, which planned to their end). A person''s dial.',
        36, 2, 48, 'public.ottoq_bess_planner_request', false),
       ('bess_planner_step_min',
        '0804 (B1): minutes in a step of the battery''s plan; a divisor of 30 (demand is billed on 30-minute windows), else '
        '5 is used. A person''s dial.',
        5, 1, 30, 'public.ottoq_bess_planner_request', false),
       ('bess_planner_beyond',
        '0804 (B1): beyond the learned forecast''s 4 hours the planner reads the depot''s learned day by half hour: 0 = its '
        'mean, 1 = its quantile across days (the model''s, 0.8). A person''s dial.',
        0, 0, 1, 'public.ottoq_bess_planner_request', false);

-- ══ (a) the request ═════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_planner_request(p_sim_run_id uuid, p_depot_id uuid,
    p_sim_clock timestamp with time zone, p_day_plan jsonb DEFAULT NULL, p_model_id bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0804: the battery planner's request at this moment, {request, model_id, beyond}: request is the body
   ottoq-intelligence's POST /optimize/battery-plan reads. NULL when the depot has no usable learned forecast (0803), no
   battery, or less than half an hour of run left. Step j covers (clock + j steps, clock + j + 1 steps]. Design: 0804 §2(a). */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  v_plan jsonb := p_day_plan; v_lf jsonb; b record;
  v_step numeric; v_win int; v_m int; v_hmax numeric; v_end timestamptz; v_beyond text;
  v_rt numeric; v_eff numeric; v_lo numeric; v_hi numeric; v_e0 numeric;
  v_load numeric[] := ARRAY[]::numeric[]; v_price numeric[] := ARRAY[]::numeric[]; v_floor numeric[] := ARRAY[]::numeric[];
  v_past numeric[]; v_last_pre numeric; j int; hh int; v_t timestamptz; v_tmp numeric; v_x numeric;
  v_bill_from timestamptz; v_next_month timestamptz; v_s1 int; v_e1 int; v_sunk numeric; v_periods jsonb := '[]'::jsonb;
  v_dr_kwh numeric; v_dr_s numeric; v_dr_e numeric; v_lead numeric; v_summer boolean; v_hf numeric; v_r numeric;
  v_month int; v_season text;
BEGIN
  IF v_plan IS NULL OR NOT COALESCE((v_plan->>'ok')::boolean, false) OR v_plan->'forecast' IS NULL THEN
    v_plan := public.ottoq_bess_day_plan(p_sim_run_id, p_depot_id, p_sim_clock, NULL);
  END IF;
  IF NOT COALESCE((v_plan->>'ok')::boolean, false) THEN RETURN NULL; END IF;
  v_lf := public.ottoq_bess_learned_forecast(p_sim_run_id, p_depot_id, p_sim_clock, v_plan, p_model_id);
  IF v_lf IS NULL THEN RETURN NULL; END IF;

  -- the battery, as the day plan reads it
  SELECT capacity_kwh AS cap, current_soc_pct AS soc, COALESCE(soc_min_floor_pct, 10) AS fl,
         COALESCE(soc_max_ceiling_pct, 90) AS ce, COALESCE(max_charge_kw, 500) AS pc, COALESCE(max_discharge_kw, 500) AS pd,
         roundtrip_efficiency_pct AS rt
    INTO b FROM ottoq_bess_units WHERE depot_id = p_depot_id ORDER BY bess_id LIMIT 1;
  IF b.cap IS NULL OR b.soc IS NULL THEN RETURN NULL; END IF;
  v_rt := LEAST(1.0, GREATEST(0.5, CASE WHEN b.rt IS NULL THEN 0.96 WHEN b.rt <= 1 THEN b.rt ELSE b.rt / 100.0 END));  -- G172
  v_eff := sqrt(v_rt);
  v_lo := b.cap * b.fl / 100.0; v_hi := b.cap * b.ce / 100.0; v_e0 := b.cap * b.soc / 100.0;

  -- the steps
  v_step := ottoq_policy_get(p_sim_run_id, 'bess_planner_step_min', 5);
  IF v_step NOT IN (1, 2, 3, 5, 6, 10, 15, 30) THEN v_step := 5; END IF;
  v_win := (30 / v_step)::int;
  v_hmax := LEAST(48, GREATEST(2, COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_planner_horizon_h', 36), 36)));
  SELECT r.sim_clock_end INTO v_end FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  v_m := floor(EXTRACT(EPOCH FROM (LEAST(p_sim_clock + make_interval(secs => v_hmax * 3600),
                                         COALESCE(v_end, 'infinity'::timestamptz)) - p_sim_clock)) / (v_step * 60))::int;
  IF v_m < v_win THEN RETURN NULL; END IF;
  v_beyond := CASE WHEN COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_planner_beyond', 0), 0) >= 0.5
                   THEN 'pre_upper_kw' ELSE 'pre_mean_kw' END;

  -- what the site drew last (the guard) and the grid over the last half hour (the windows that straddle now)
  SELECT COALESCE(e.total_ev_charging_kw, 0) + COALESCE(e.building_load_kw, 0) + COALESCE(e.lighting_load_kw, 0)
         - COALESCE(e.solar_generation_kw, 0)
    INTO v_last_pre
    FROM site_energy_snapshots e
   WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id AND e.timestamp <= p_sim_clock
   ORDER BY e.timestamp DESC LIMIT 1;
  v_last_pre := COALESCE(v_last_pre, 0);
  SELECT COALESCE(array_agg(g ORDER BY t), ARRAY[]::numeric[]) INTO v_past
    FROM (SELECT e.timestamp AS t, round(GREATEST(COALESCE(e.grid_import_kw, 0), 0), 1) AS g
            FROM site_energy_snapshots e
           WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id AND e.timestamp <= p_sim_clock
           ORDER BY e.timestamp DESC LIMIT v_win - 1) z;

  -- the demand-response reserve as the depot holds it (0435, 0797)
  v_dr_kwh := GREATEST(0, COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_reserve_kwh', 600), 600));
  v_dr_s := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_start_hour', 14);
  v_dr_e := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_end_hour', 20);
  v_lead := COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_reserve_lead_h', 24), 24);
  v_month := EXTRACT(MONTH FROM p_sim_clock AT TIME ZONE c_tz)::int;
  SELECT t.season INTO v_season FROM ottoq_depot_tariffs t
   WHERE t.depot_id = p_depot_id AND t.active AND v_month = ANY(t.season_months)
   ORDER BY t.effective_from DESC, t.tariff_row_id LIMIT 1;
  v_summer := COALESCE(v_season = 'summer', false);

  FOR j IN 0..v_m - 1 LOOP
    v_t := p_sim_clock + make_interval(secs => v_step * 60 * (j + 1));       -- the step's end
    hh := floor(j * v_step / 30.0)::int;                                     -- its half hour from now
    IF hh < 8 THEN
      v_x := (v_lf->'pre_upper_kw'->>hh)::numeric;
    ELSE
      v_x := (v_lf->'profile'->(hh % 48)->>v_beyond)::numeric;
    END IF;
    IF v_x IS NULL THEN                                                      -- no learned day for this half hour
      v_x := COALESCE((v_plan->'forecast'->'net_kw'->>hh)::numeric, v_last_pre);
    END IF;
    IF j < v_win THEN v_x := GREATEST(v_x, v_last_pre); END IF;              -- the next half hour never under the last draw
    v_load := v_load || round(v_x, 1);
    SELECT t.out_rate_usd_kwh INTO v_tmp FROM twin.ottoq_sim_current_tariff(p_depot_id, v_t) t;
    v_price := v_price || COALESCE(v_tmp, 0.10);
    v_hf := EXTRACT(HOUR FROM v_t AT TIME ZONE c_tz) + EXTRACT(MINUTE FROM v_t AT TIME ZONE c_tz) / 60.0;
    v_r := CASE WHEN NOT v_summer OR v_dr_kwh <= 0 OR v_dr_e <= v_dr_s THEN 0
                WHEN v_hf < v_dr_s - v_lead THEN 0
                WHEN v_hf < v_dr_s THEN v_dr_kwh
                WHEN v_hf < v_dr_e THEN v_dr_kwh * (v_dr_e - v_hf) / (v_dr_e - v_dr_s)
                ELSE 0 END;
    v_floor := v_floor || round(CASE WHEN v_r > 0 THEN LEAST(v_hi, v_lo + v_r / v_eff) ELSE v_lo END, 1);
  END LOOP;

  -- the billing periods: the day plan's window, a new month a new period
  v_bill_from := GREATEST(date_trunc('month', p_sim_clock),
                  COALESCE((SELECT r.sim_clock_start FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id),
                           '-infinity'::timestamptz)
                  + make_interval(mins => GREATEST(0, ottoq_policy_get(p_sim_run_id, 'bess_plan_bill_from_min', 0))::int));
  v_next_month := date_trunc('month', p_sim_clock) + interval '1 month';
  v_s1 := ceil(EXTRACT(EPOCH FROM (v_bill_from - p_sim_clock)) / (v_step * 60))::int;
  v_e1 := LEAST(v_m, ceil(EXTRACT(EPOCH FROM (v_next_month - p_sim_clock)) / (v_step * 60))::int);
  v_sunk := CASE WHEN v_s1 <= 0 THEN COALESCE((v_plan->>'ratchet_kw')::numeric, 0) ELSE 0 END;
  IF v_s1 < v_e1 THEN
    v_periods := v_periods || jsonb_build_array(jsonb_build_object('start', v_s1, 'end', v_e1, 'sunk_kw', v_sunk,
                                                                   'margin_kw', GREATEST(100, 0.10 * v_sunk)));
  END IF;
  IF v_e1 < v_m THEN
    v_periods := v_periods || jsonb_build_array(jsonb_build_object('start', v_e1, 'end', v_m, 'sunk_kw', 0, 'margin_kw', 100));
  END IF;
  IF jsonb_array_length(v_periods) = 0 THEN                                  -- billing starts beyond the horizon
    v_periods := jsonb_build_array(jsonb_build_object('start', v_m, 'end', v_m, 'sunk_kw', 0, 'margin_kw', 0));
  END IF;

  RETURN jsonb_build_object(
    'model_id', v_lf->'model_id', 'beyond', v_beyond,
    'request', jsonb_build_object(
      'load_kw', to_jsonb(v_load), 'price_usd_kwh', to_jsonb(v_price), 'step_min', v_step,
      'battery', jsonb_build_object('soc_kwh', round(v_e0, 1), 'floor_kwh', round(v_lo, 1), 'ceiling_kwh', round(v_hi, 1),
                                    'max_charge_kw', b.pc, 'max_discharge_kw', b.pd, 'eff_one_way', v_eff),
      'demand_usd_kw', COALESCE((v_plan->>'demand_usd_per_kw_day')::numeric, 0),
      'periods', v_periods, 'past_grid_kw', to_jsonb(v_past), 'window_steps', v_win, 'soc_floor_kwh', to_jsonb(v_floor),
      'wear_usd_kwh', COALESCE((v_plan->>'degradation_usd_kwh')::numeric, 0.02),
      'terminal_usd_kwh', COALESCE((v_plan->>'replacement_usd_kwh')::numeric, 0)));
END;
$function$;

-- ══ (b) the fire ════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_planner_fire(p_sim_run_id uuid, p_depot_id uuid,
    p_sim_clock timestamp with time zone, p_tick_seq bigint DEFAULT NULL, p_day_plan jsonb DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0804: write the planner's request as a 'pending' plan and ask the edge function ottoq-battery-planner for it (fire and
   forget). Returns the plan's id, or NULL when there is no request (no usable learned forecast, no battery). The edge
   function reads the request from the row, never from the caller; without the vault's anon key the row waits. */
DECLARE v_q jsonb; v_req jsonb; v_id uuid; v_step numeric; v_m int; v_k text; v_rid bigint;
BEGIN
  v_q := public.ottoq_bess_planner_request(p_sim_run_id, p_depot_id, p_sim_clock, p_day_plan, NULL);
  IF v_q IS NULL THEN RETURN NULL; END IF;
  v_req := v_q->'request';
  v_step := (v_req->>'step_min')::numeric;
  v_m := jsonb_array_length(v_req->'load_kw');
  INSERT INTO ottoq_energy_plan (sim_run_id, depot_id, plan_start_clock, tick_minutes, horizon_steps, bess_setpoint_kw,
                                 forecast_load_kw, solver, status, source, plan_state, detail)
  VALUES (p_sim_run_id, p_depot_id, p_sim_clock + make_interval(secs => v_step * 60), v_step, v_m, ARRAY[]::numeric[],
          ARRAY(SELECT x::numeric FROM jsonb_array_elements_text(v_req->'load_kw') WITH ORDINALITY u(x, o) ORDER BY o),
          'glop', 'pending', 'bess_planner', 'pending',
          jsonb_build_object('request', v_req, 'model_id', v_q->'model_id', 'beyond', v_q->'beyond',
                             'tick_seq', p_tick_seq, 'fired_clock', p_sim_clock, 'fired_at', clock_timestamp()))
  RETURNING id INTO v_id;
  BEGIN
    SELECT decrypted_secret INTO v_k FROM vault.decrypted_secrets WHERE name = 'ottoq_anon_key' LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_k := NULL;
  END;
  IF v_k IS NOT NULL THEN
    v_rid := net.http_post(
      url := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-battery-planner',
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_k, 'apikey', v_k),
      body := jsonb_build_object('plan_id', v_id),
      timeout_milliseconds := 20000);
    UPDATE ottoq_energy_plan SET request_id = v_rid WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$function$;

-- ══ (c) the landing ═════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_planner_land(p_plan_id uuid, p_response jsonb, p_http_status integer DEFAULT 200,
    p_latency_ms integer DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0804: take the planner's answer for a pending plan, checked first: HTTP 200, solved (optimal or feasible), one setpoint
   a step, every setpoint inside the battery's power. A good answer becomes the run's one 'ready' plan (older ones
   superseded), unless a plan that starts later has already landed (then it is superseded on arrival); anything else
   'failed' with its reason. Every call is a row of ottoq_model_call_ledger. The edge function's (the service role's). */
DECLARE
  p record; b record; v_sp numeric[]; v_grid numeric[]; v_err text; v_state text; v_peak numeric;
BEGIN
  SELECT * INTO p FROM ottoq_energy_plan WHERE id = p_plan_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_such_plan'); END IF;
  IF p.source <> 'bess_planner' OR p.plan_state <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_pending', 'state', p.plan_state);
  END IF;
  SELECT COALESCE(max_charge_kw, 500) AS pc, COALESCE(max_discharge_kw, 500) AS pd INTO b
    FROM ottoq_bess_units WHERE depot_id = p.depot_id ORDER BY bess_id LIMIT 1;
  IF jsonb_typeof(p_response->'setpoint_kw') = 'array' THEN
    v_sp := ARRAY(SELECT round(x::numeric, 1) FROM jsonb_array_elements_text(p_response->'setpoint_kw') WITH ORDINALITY u(x, o) ORDER BY o);
  END IF;
  IF jsonb_typeof(p_response->'grid_kw') = 'array' THEN
    v_grid := ARRAY(SELECT round(x::numeric, 1) FROM jsonb_array_elements_text(p_response->'grid_kw') WITH ORDINALITY u(x, o) ORDER BY o);
  END IF;
  IF jsonb_typeof(p_response->'peak_kw') = 'array' THEN
    SELECT max(x::numeric) INTO v_peak FROM jsonb_array_elements_text(p_response->'peak_kw') x;
  END IF;
  v_err := CASE
    WHEN COALESCE(p_http_status, 0) <> 200 THEN 'http_' || COALESCE(p_http_status::text, 'none')
    WHEN COALESCE(p_response->>'status', '') NOT IN ('optimal', 'feasible') THEN 'status_' || COALESCE(p_response->>'status', 'none')
    WHEN COALESCE(cardinality(v_sp), 0) <> p.horizon_steps THEN 'steps_' || COALESCE(cardinality(v_sp), 0) || '_of_' || p.horizon_steps
    WHEN EXISTS (SELECT 1 FROM unnest(v_sp) x WHERE x > b.pd + 1 OR x < -b.pc - 1) THEN 'setpoint_outside_the_batterys_power'
  END;
  v_state := CASE
    WHEN v_err IS NOT NULL THEN 'failed'
    WHEN EXISTS (SELECT 1 FROM ottoq_energy_plan q WHERE q.sim_run_id = p.sim_run_id AND q.source = 'bess_planner'
                    AND q.plan_state = 'ready' AND q.plan_start_clock > p.plan_start_clock) THEN 'superseded'
    ELSE 'ready' END;
  IF v_state = 'ready' THEN
    UPDATE ottoq_energy_plan SET plan_state = 'superseded'
     WHERE sim_run_id = p.sim_run_id AND plan_state = 'ready' AND id <> p.id;
  END IF;
  UPDATE ottoq_energy_plan
     SET bess_setpoint_kw = CASE WHEN v_err IS NULL THEN v_sp ELSE ARRAY[]::numeric[] END,
         grid_import_kw = CASE WHEN v_err IS NULL THEN v_grid END,
         predicted_peak_kw = CASE WHEN v_err IS NULL THEN round(v_peak, 1) END,
         solver = COALESCE(p_response->>'solver', solver), status = COALESCE(p_response->>'status', 'error'),
         latency_ms = p_latency_ms, plan_state = v_state,
         -- the request is the row's until it is answered; after, its md5 stands for it (a request is some 20 kB a tick)
         detail = (COALESCE(detail, '{}'::jsonb) - 'request') || jsonb_build_object(
           'request_md5', md5((detail->'request')::text),
           'landed_at', clock_timestamp(), 'http_status', p_http_status, 'error', v_err,
           'objective_usd', p_response->'objective_usd', 'solve_ms', p_response->'solve_ms', 'peak_kw', p_response->'peak_kw')
   WHERE id = p.id;
  BEGIN
    PERFORM public.ottoq_log_model_call(
      p_provider := 'intelligence_battery_planner', p_role := 'planner',
      p_outcome := CASE WHEN v_err IS NULL THEN 'answered' ELSE 'error' END,
      p_sim_run_id := p.sim_run_id, p_depot_id := p.depot_id, p_tick_seq := (p.detail->>'tick_seq')::bigint,
      p_sim_clock := (p.detail->>'fired_clock')::timestamptz, p_model := 'battery_planner_glop',
      p_endpoint := '/optimize/battery-plan', p_http_status := p_http_status, p_latency_ms := p_latency_ms,
      p_proposals_out := CASE WHEN v_err IS NULL THEN 1 ELSE 0 END, p_rationale_present := false,
      p_detail := jsonb_build_object('plan_id', p.id, 'state', v_state, 'error', v_err, 'steps', p.horizon_steps,
                                     'model_id', p.detail->'model_id', 'objective_usd', p_response->'objective_usd',
                                     'solve_ms', p_response->'solve_ms', 'path', 'edge:ottoq-battery-planner'),
      p_source_kind := 'live');
  EXCEPTION WHEN OTHERS THEN
    NULL;   -- evidence never fails the landing it records
  END;
  RETURN jsonb_build_object('ok', v_err IS NULL, 'state', v_state, 'error', v_err, 'plan_id', p.id);
END;
$function$;

REVOKE ALL ON FUNCTION public.ottoq_bess_planner_fire(uuid,uuid,timestamptz,bigint,jsonb),
                       public.ottoq_bess_planner_land(uuid,jsonb,integer,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_bess_planner_land(uuid,jsonb,integer,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_bess_planner_request(uuid,uuid,timestamptz,jsonb,bigint) TO anon, authenticated, service_role;

-- ══ (d) the orchestrator's one insertion ════════════════════════════════════════════════════════════════════════════
CREATE TEMP TABLE _0804_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0804_patch VALUES
(1,
$o$  RETURN round(v_charge_cap,1);
END;
$o$,
$n$  /* 0804 (B1): ask the battery planner for the next plan, on the learned forecast and the plan just solved, every
     bess_planner_every_ticks ticks; the battery follows a landed plan only where energy_mpc_follow is on (0799). It moves
     only the battery, and a failure is a warning, never a stopped tick. */
  IF ottoq_policy_get(p_sim_run_id, 'bess_planner_enabled', 0) >= 0.5
     AND COALESCE(p_tick_seq, 0) % GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_planner_every_ticks', 1), 1))::int = 0 THEN
    BEGIN
      PERFORM public.ottoq_bess_planner_fire(p_sim_run_id, p_depot_id, p_sim_clock, p_tick_seq, v_day_plan);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0804: the battery planner was not asked at tick %: %', p_tick_seq, SQLERRM;
    END;
  END IF;
  RETURN round(v_charge_cap,1);
END;
$n$);

UPDATE _0804_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  FOR p IN SELECT * FROM _0804_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0804: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0804: the orchestrator is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the orchestrator less its insertion is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  v_body := (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  FOR p IN SELECT * FROM _0804_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '5d607e3cfc88c7cc5a459407b4445532' THEN
    RAISE EXCEPTION '0804 V1: the orchestrator less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: request, fire and landing on the twin's latest run, rolled back with their rows ──
DO $v2$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_mid bigint; v_q jsonb; v_req jsonb; v_m int; v_p1 uuid; v_p2 uuid; v_l jsonb;
  v_resp jsonb; v_n int; v_lo numeric; v_hi numeric; v_calls0 bigint; v_plan jsonb;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
    FROM ottoq_sim_runs r WHERE r.depot_id = c_twin AND r.sim_clock_start IS NOT NULL
   ORDER BY r.started_at DESC NULLS LAST LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0804 V2: skipped, the twin depot has no run to probe';
    RETURN;
  END IF;
  v_calls0 := (SELECT count(*) FROM public.ottoq_model_call_ledger WHERE provider = 'intelligence_battery_planner');
  BEGIN
    -- a synthetic learned forecast (EV 300 kW at every half hour, a flat learned day), so the request is built whatever
    -- the log holds; the day plan as the twin solves it at the run's clock, with an end that leaves 6 hours to plan
    INSERT INTO public.ottoq_bess_forecast_models (depot_id, note, usable, quantile, lam, fold_by, runs, n_folds, n_examples,
                                                   features, per_half_hour, profile)
    SELECT c_twin, '0804 V2 (rolled back)', true, 0.8, 10, 'run_day', ARRAY[v_run], 3, 0, ARRAY['1'],
           (SELECT jsonb_agg(jsonb_build_object('h', h, 'n', 0, 'mu', to_jsonb(array_fill(0::float8, ARRAY[9])),
                                                'sd', to_jsonb(array_fill(1::float8, ARRAY[9])),
                                                'w', to_jsonb(ARRAY[300::float8, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
                                                'offset_kw', 50) ORDER BY h) FROM generate_series(0, 7) h),
           (SELECT jsonb_agg(jsonb_build_object('b', b, 'n_days', 3, 'pre_mean_kw', 400, 'pre_upper_kw', 450,
                                                'ev_mean_kw', 350, 'ev_upper_kw', 400) ORDER BY b) FROM generate_series(0, 47) b)
    RETURNING model_id INTO v_mid;
    UPDATE ottoq_sim_runs SET sim_clock_end = v_clock + interval '6 hours' WHERE sim_run_id = v_run;
    v_plan := public.ottoq_bess_day_plan(v_run, c_twin, v_clock, NULL);
    IF NOT COALESCE((v_plan->>'ok')::boolean, false) THEN
      RAISE NOTICE '0804 V2: skipped, the twin''s day plan does not solve at run % (%)', v_run, v_plan;
      RAISE EXCEPTION USING ERRCODE = 'P0804', MESSAGE = 'roll back';
    END IF;
    v_q := public.ottoq_bess_planner_request(v_run, c_twin, v_clock, v_plan, v_mid);
    v_req := v_q->'request';
    v_m := jsonb_array_length(v_req->'load_kw');
    SELECT (v_req->'battery'->>'floor_kwh')::numeric, (v_req->'battery'->>'ceiling_kwh')::numeric INTO v_lo, v_hi;
    IF v_m <> 72 OR jsonb_array_length(v_req->'price_usd_kwh') <> v_m OR jsonb_array_length(v_req->'soc_floor_kwh') <> v_m
       OR jsonb_array_length(v_req->'periods') < 1 OR (v_req->>'window_steps')::int <> 6
       OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_req->'soc_floor_kwh') x WHERE x::numeric < v_lo - 0.1 OR x::numeric > v_hi + 0.1)
       OR (SELECT count(*) FROM jsonb_array_elements_text(v_req->'load_kw') WITH ORDINALITY u(x, o)
            WHERE o > 48 AND x::numeric <> 400) > 0 THEN                    -- beyond 4 hours, the learned day's mean
      RAISE EXCEPTION '0804 V2: the request is not well formed: % steps, periods %, floor % - %', v_m, v_req->'periods', v_lo, v_hi;
    END IF;
    -- the fire: one pending plan carrying the request (UPDATE the model to be the depot's latest usable, as the fire reads it)
    v_p1 := public.ottoq_bess_planner_fire(v_run, c_twin, v_clock, 1, v_plan);
    v_p2 := public.ottoq_bess_planner_fire(v_run, c_twin, v_clock + interval '5 minutes', 2, v_plan);
    IF v_p1 IS NULL OR v_p2 IS NULL OR (SELECT count(*) FROM ottoq_energy_plan WHERE id IN (v_p1, v_p2)
                                          AND plan_state = 'pending' AND source = 'bess_planner'
                                          AND detail ? 'request') <> 2 THEN
      RAISE EXCEPTION '0804 V2: the fire did not write two pending plans carrying their requests';
    END IF;
    -- the later plan lands first, then the earlier one: superseded on arrival; then a bad answer fails
    v_resp := jsonb_build_object('status', 'optimal', 'solver', 'glop', 'objective_usd', 1.0, 'solve_ms', 5,
                                 'peak_kw', jsonb_build_array(500), 'grid_kw', to_jsonb(array_fill(400::numeric, ARRAY[71])),
                                 'setpoint_kw', to_jsonb(array_fill(0::numeric, ARRAY[71])));
    v_l := public.ottoq_bess_planner_land(v_p2, v_resp, 200, 900);
    IF v_l->>'state' <> 'ready' THEN RAISE EXCEPTION '0804 V2: a good answer did not land ready: %', v_l; END IF;
    v_l := public.ottoq_bess_planner_land(v_p1, v_resp || jsonb_build_object('setpoint_kw', to_jsonb(array_fill(0::numeric, ARRAY[72]))), 200, 950);
    IF v_l->>'state' <> 'superseded' THEN RAISE EXCEPTION '0804 V2: an older answer was not superseded on arrival: %', v_l; END IF;
    v_p1 := public.ottoq_bess_planner_fire(v_run, c_twin, v_clock + interval '10 minutes', 3, v_plan);
    v_l := public.ottoq_bess_planner_land(v_p1, v_resp, 200, 100);
    IF v_l->>'state' <> 'failed' OR v_l->>'error' NOT LIKE 'steps_%' THEN
      RAISE EXCEPTION '0804 V2: an answer with the wrong number of steps did not fail: %', v_l;
    END IF;
    v_l := public.ottoq_bess_planner_land(v_p1, v_resp, 200, 100);
    IF v_l->>'reason' <> 'not_pending' THEN RAISE EXCEPTION '0804 V2: a landed plan was landed twice: %', v_l; END IF;
    v_n := (SELECT count(*) FROM public.ottoq_model_call_ledger WHERE provider = 'intelligence_battery_planner') - v_calls0;
    IF v_n <> 3 THEN RAISE EXCEPTION '0804 V2: % ledger rows for three landings', v_n; END IF;
    RAISE NOTICE '0804 V2: run %, % steps, periods %, the first floors %', v_run, v_m, v_req->'periods',
      (SELECT jsonb_agg(x) FROM (SELECT x FROM jsonb_array_elements(v_req->'soc_floor_kwh') x LIMIT 6) z);
    RAISE EXCEPTION USING ERRCODE = 'P0804', MESSAGE = 'roll back the probe';
  EXCEPTION WHEN SQLSTATE 'P0804' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models WHERE note = '0804 V2 (rolled back)')
     OR (SELECT count(*) FROM public.ottoq_model_call_ledger WHERE provider = 'intelligence_battery_planner') <> v_calls0 THEN
    RAISE EXCEPTION '0804 V2: the probe''s rows were not rolled back';
  END IF;
END $v2$;

-- ── V3: the patched orchestrator is byte for byte the body the research lab ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure)
     IS DISTINCT FROM '3b94f1c73b4a4903ec94adc9e628bba3' THEN
    RAISE EXCEPTION '0804 V3: the patched orchestrator is not the body the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0804_the_battery_plans_its_day_on_the_learned_forecast_and_the_planner_answers_from_outside', false, false,
        'B1. The battery planner''s request on the learned forecast (0803), fired from the orchestrator behind '
        'bess_planner_enabled (default 0) to the edge function ottoq-battery-planner and landed by '
        'ottoq_bess_planner_land as the run''s one ready plan, each call a ledger row; followed only where '
        'energy_mpc_follow is on (0799). With the dial off the orchestrator decides as before.',
        now());

COMMIT;
