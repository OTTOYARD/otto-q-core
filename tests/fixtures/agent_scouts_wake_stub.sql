-- tests/fixtures/agent_scouts_wake_stub.sql -- the world 0703, 0704 and 0705 meet, in miniature. ottoq_agent_board is the
-- live definition of 2026-10-13 (pg_get_functiondef, byte for byte: md5 8613653559d1cb10eacacbe3c73293fc), so 0704's md5
-- premise and its substitution run against exactly what they will meet. Everything else is a minimal stand-in, noted
-- where it is defined. Used by tests/test_agent_scouts_wake_sql.py.
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS twin; CREATE SCHEMA IF NOT EXISTS ottoq; CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS cron;
CREATE TABLE cron.job (jobid bigserial PRIMARY KEY, jobname text UNIQUE, schedule text, command text);
-- stand-in for pg_cron's cron.schedule(name, schedule, command): upsert by name
CREATE FUNCTION cron.schedule(p_name text, p_schedule text, p_command text) RETURNS bigint LANGUAGE sql AS $f$
  INSERT INTO cron.job (jobname, schedule, command) VALUES (p_name, p_schedule, p_command)
  ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command RETURNING jobid $f$;

-- stand-in: nothing is in flight in a scratch database
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
INSERT INTO public.ottoq_cert_lineage VALUES ('0699_the_twin_apps_determinism_canon_card_reads_again', false, 'stub', now(), false);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial, label text, object_kind text, schema_name text,
  object_name text, definition text, def_md5 text, captured_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_model_call_ledger (call_id bigserial PRIMARY KEY);
CREATE TABLE public.ottoq_run_scope_registry (table_schema text, table_name text, column_name text, class text, note text,
  registered_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_policy_param_catalog (param_key text PRIMARY KEY, description text, default_value numeric,
  min_value numeric, max_value numeric, affects text, min_exclusive numeric, max_exclusive numeric, agent_writable boolean,
  agent_min_value numeric, agent_max_value numeric, agent_max_drift_pct numeric);
CREATE TABLE public.ottoq_policy_params (scope_type text, scope_id uuid, param_key text, param_value numeric,
  updated_by text, updated_at timestamptz DEFAULT now(), PRIMARY KEY (scope_type, scope_id, param_key));
-- stand-in: run scope, then the default (the live function also reads depot and global tiers)
CREATE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric) RETURNS numeric
LANGUAGE sql STABLE AS $f$
  SELECT COALESCE((SELECT param_value FROM public.ottoq_policy_params
                    WHERE scope_type = 'run' AND scope_id = p_sim_run_id AND param_key = p_param_key), p_default) $f$;

CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid, status text, tick_count bigint,
  sim_clock_current timestamptz, sim_clock_start timestamptz, started_at timestamptz, last_tick_at timestamptz,
  run_by text, scenario_code text, random_seed bigint, policy text, payload jsonb);
CREATE TABLE public.fleet_operators (id uuid PRIMARY KEY, name text);
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, fleet_operator_id uuid, home_depot_id uuid, current_depot_id uuid,
  category text DEFAULT 'autonomous', display_name text, current_soc numeric, current_state text);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid, stall_type text, stall_code text, status text,
  current_vehicle_id uuid, reserved_by uuid, ocpp_charger_id uuid);
CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, depot_id uuid, station_state text,
  decommissioned_at timestamptz);
CREATE TABLE public.ottoq_fleet_operator_slas (sla_id uuid DEFAULT gen_random_uuid(), fleet_operator_id uuid, status text,
  version integer, effective_from timestamptz, effective_until timestamptz, max_queue_wait_minutes integer);
CREATE TABLE public.ottoq_vehicle_dispatches (dispatch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid,
  sim_run_id uuid, dispatched_at timestamptz, returning_started_at timestamptz, actual_return_at timestamptz,
  soc_at_dispatch_pct numeric, return_trigger text, scheduled_return_at timestamptz);
CREATE TABLE public.ottoq_visit_needs (visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid, sim_run_id uuid,
  depot_id uuid, arrived_at timestamptz, urgency text, status text, atoms jsonb, created_at timestamptz DEFAULT now());
CREATE TABLE public.schedule_tasks (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid, depot_id uuid,
  status text, service_code text, created_at timestamptz);
CREATE TABLE public.ottoq_dr_calls (dr_call_id bigserial, depot_id uuid, sim_run_id uuid, call_status text,
  expires_at timestamptz, program text, reason text, required_load_cap_kw numeric);
-- stand-in for the kernel's charge line: the test sets its rows directly
CREATE TABLE public.stub_kernel_line (sim_run_id uuid, vehicle_id uuid, kernel_pos integer, wait_min numeric, soc numeric);
CREATE FUNCTION public.ottoq_charge_queue_kernel_order(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS TABLE(vehicle_id uuid, kernel_pos integer, wait_min numeric, gap numeric, immediate boolean, soc numeric,
              visit_target numeric, holds_charger boolean)
LANGUAGE sql STABLE AS $f$
  SELECT l.vehicle_id, l.kernel_pos, l.wait_min, NULL::numeric, false, l.soc, 100::numeric, false
    FROM public.stub_kernel_line l WHERE l.sim_run_id = p_sim_run_id ORDER BY l.kernel_pos $f$;
-- stand-in: rule 9's one target is 100 for every car here
CREATE FUNCTION public.ottoq_effective_target_soc_at(uuid, timestamptz) RETURNS numeric LANGUAGE sql STABLE AS 'SELECT 100::numeric';

-- what the live board reads, as empty stand-ins, so it can be called
CREATE TABLE public.ottoq_itinerary_legs (sim_run_id uuid, status text, deviation_s numeric);
CREATE TABLE public.ottoq_decisions (sim_run_id uuid, tick_seq bigint, action_context text, resolved_action_context text,
  outcome_status text, sim_clock timestamptz);
CREATE TABLE public.site_energy_snapshots (depot_id uuid, sim_run_id uuid, timestamp timestamptz, building_load_kw numeric,
  total_ev_charging_kw numeric, solar_generation_kw numeric);
CREATE TABLE public.ottoq_bess_units (depot_id uuid, current_soc_pct numeric, current_power_kw numeric);
CREATE TABLE public.ottoq_energy_commands (sim_run_id uuid, depot_id uuid, command_type text, reason text,
  issued_at timestamptz, tick_seq bigint, command_id bigserial);
CREATE TABLE public.ottoq_ops_approvals (depot_id uuid, status text, approval_type text);
CREATE TABLE public.ottoq_sim_scenarios (scenario_code text, fleet_overrides jsonb);
CREATE FUNCTION public.ottoq_predict_arrivals(uuid, timestamptz, uuid, integer) RETURNS TABLE(predicted_charge_kw numeric)
  LANGUAGE sql AS 'SELECT 0::numeric';
CREATE FUNCTION public.ottoq_agent_review(uuid, integer) RETURNS jsonb LANGUAGE sql AS $f$SELECT '{"stub":"review"}'::jsonb$f$;
CREATE FUNCTION public.ottoq_agent_asset_depth(uuid, uuid, timestamptz, integer, integer) RETURNS jsonb
  LANGUAGE sql AS $f$SELECT '{"assets":{"stub":true}}'::jsonb$f$;
CREATE FUNCTION public.ottoq_agent_board_grounding(uuid, uuid, timestamptz) RETURNS jsonb
  LANGUAGE sql AS $f$SELECT '{"stub":"grounding"}'::jsonb$f$;
CREATE FUNCTION public.ottoq_agent_charge_queue_board(uuid, uuid, timestamptz) RETURNS jsonb
  LANGUAGE sql AS $f$SELECT '{"stub":"charge_queue"}'::jsonb$f$;

-- the live board, byte for byte (2026-10-13)
CREATE OR REPLACE FUNCTION public.ottoq_agent_board(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run RECORD; v_depot uuid; v_clock timestamptz; v_board jsonb;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count, scenario_code, random_seed
    INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.depot_id IS NULL THEN RETURN NULL; END IF;
  v_depot := v_run.depot_id; v_clock := v_run.sim_clock_current;

  SELECT jsonb_build_object(
    'sim_clock', v_clock, 'tick', v_run.tick_count, 'scenario', v_run.scenario_code,
    'fleet', (SELECT jsonb_object_agg(current_state, n) FROM (
        SELECT current_state, count(*) n FROM vehicles
        WHERE home_depot_id = v_depot AND category='autonomous' GROUP BY 1) f),
    'inbound_60m', (SELECT count(*) FROM vehicles v JOIN ottoq_vehicle_dispatches d ON d.vehicle_id = v.id
        WHERE v.home_depot_id = v_depot AND v.current_state='en_route_to_depot'
          AND d.actual_return_at IS NULL AND d.scheduled_return_at <= v_clock + interval '60 minutes'),
    'needs', jsonb_build_object(
      'open_visits_by_urgency', (SELECT jsonb_object_agg(urgency, n) FROM (
          SELECT urgency, count(*) n FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status IN ('open','in_progress') GROUP BY 1) u),
      'pending_atoms', (SELECT jsonb_object_agg(svc, n) FROM (
          SELECT a->>'svc' svc, count(*) n FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
          WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
            AND COALESCE(a->>'status','pending') = 'pending' GROUP BY 1 ORDER BY n DESC LIMIT 8) p),
      'carryovers', (SELECT count(*) FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status='carried_over' AND created_at > now() - interval '1 day')),
    'flow', jsonb_build_object(
      'legs', (SELECT jsonb_object_agg(status, n) FROM (
          SELECT status, count(*) n FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id GROUP BY 1) l),
      'avg_abs_deviation_min', (SELECT round(avg(abs(deviation_s))/60.0,1) FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id AND deviation_s IS NOT NULL),
      'amendments_recent', (SELECT count(*) FROM ottoq_decisions
          WHERE sim_run_id = p_sim_run_id AND resolved_action_context='itinerary_amended'
            AND sim_clock > v_clock - interval '2 hours')),
    'energy', jsonb_build_object(
      'site', (SELECT jsonb_build_object('grid_kw', round(COALESCE(building_load_kw,0)+COALESCE(total_ev_charging_kw,0)-COALESCE(solar_generation_kw,0)),
                       'ev_kw', round(COALESCE(total_ev_charging_kw,0)), 'solar_kw', round(COALESCE(solar_generation_kw,0)))
          FROM site_energy_snapshots WHERE depot_id = v_depot AND sim_run_id = p_sim_run_id
          ORDER BY timestamp DESC LIMIT 1),
      'bess', (SELECT jsonb_build_object('soc', current_soc_pct, 'power_kw', current_power_kw)
          FROM ottoq_bess_units WHERE depot_id = v_depot LIMIT 1),
      'bess_plan', (SELECT reason FROM ottoq_energy_commands
          WHERE COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
            AND depot_id = v_depot AND command_type='bess_setpoint_kw'
          ORDER BY issued_at DESC, tick_seq DESC NULLS LAST, command_id DESC LIMIT 1),
      'forecast_charge_kw_60m', (SELECT round(COALESCE(predicted_charge_kw,0))
          FROM ottoq_predict_arrivals(v_depot, v_clock, p_sim_run_id, 60))),
    'approvals_pending', (SELECT jsonb_object_agg(approval_type, n) FROM (
        SELECT approval_type, count(*) n FROM ottoq_ops_approvals
        WHERE depot_id = v_depot AND status='pending' GROUP BY 1) a),
    'exceptions', (SELECT count(*) FROM vehicles
        WHERE home_depot_id = v_depot AND current_state IN ('tow_requested','emergency_staged')),
    'assignment_last_tick', (SELECT jsonb_object_agg(outcome_status, n) FROM (
        SELECT outcome_status, count(*) n FROM ottoq_decisions
        WHERE sim_run_id = p_sim_run_id AND tick_seq = v_run.tick_count
          AND action_context='stall_assignment' GROUP BY 1) o),
    'policy', jsonb_build_object(
      'deploy_peak_fraction', ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',  --: 0432: the dispatcher's own default
        COALESCE((SELECT (s.fleet_overrides->>'target_deployed_fraction')::numeric FROM ottoq_sim_scenarios s
                   WHERE s.scenario_code = COALESCE(v_run.scenario_code,'normal_day') LIMIT 1), 0.90)),
      'energy_demand_factor_peak', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_peak',0.50),
      'energy_demand_factor_expensive', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_expensive',0.35))
  ) INTO v_board;

  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_review_enabled',0),0) >= 1 THEN
    v_board := v_board || jsonb_build_object('review', public.ottoq_agent_review(p_sim_run_id, 3));
  END IF;

  --: 0350. THE PER-ASSET HALF, gated and concatenated for the identical reason
  --: 0342 gated the return leg: at the default of 0 the board is byte-identical
  --: to its pre-0350 self, so no certification arm moves (A1 asserts it).
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_asset_depth_enabled',0),0) >= 1 THEN
    v_board := v_board || public.ottoq_agent_asset_depth(p_sim_run_id, v_depot, v_clock, 10, 10);
  END IF;

  --: 0432. THE GROUNDING HALF -- what is true now, the agent's own last writes and changes, the
  --: service queue, resources, energy limits, recent flow, and the work side's demand as read-only.
  --: Gated and CONCATENATED like 0342/0350: at the default of 0 the key is absent, not present-and-null.
  --: ottoq_agentic_arm sets it to 1 on every armed run.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_board_grounding_enabled',0),0) >= 1 THEN
    v_board := v_board || jsonb_build_object('grounding',
                 public.ottoq_agent_board_grounding(p_sim_run_id, v_depot, v_clock));
  END IF;

  --: 0614. THE CHARGE LINE, so the agent can order it. Gated and concatenated like 0342/0350/0432: at the
  --: default of 0 the key is absent, and a baseline seat never carries it.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_charge_order',0),0) >= 1
     AND COALESCE(ottoq_policy_get(p_sim_run_id,'proposer_seat',0),0) = 0 THEN
    v_board := v_board || jsonb_build_object('charge_queue',
                 public.ottoq_agent_charge_queue_board(p_sim_run_id, v_depot, v_clock));
  END IF;

  --: 0629. A PRODUCTION SESSION SAYS SO. The agent is armed there and proposes; every write under its name to a setting
  --: the session reads is refused (ottoq_policy_set, production_never_self_tunes, CLAUDE.md rule 10). The board says it
  --: first, so the agent does not spend its moves on dials. Absent on every other run, so a twin board is unchanged.
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id AND r.run_by = 'production_live') THEN
    v_board := v_board || jsonb_build_object('production', jsonb_build_object(
      'live', true,
      'dials', 'read_only',
      'note', 'A production session with real vehicles. You propose; the kernel disposes. No set_policy or ops_action '
              'reaches this session: every write under your name is refused (production_never_self_tunes). Your charge '
              'order and your solver objective are proposals the kernel checks before it takes them.'));
  END IF;

  RETURN v_board;
END; $function$
;
