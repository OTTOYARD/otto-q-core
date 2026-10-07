-- tests/fixtures/agent_charge_order_stub.sql -- the engine 0614 patches, as far as 0614 touches it.
-- GENERATED from the live catalog on 2026-10-07 (column lists by format_type; enum labels from pg_enum). The five
-- functions 0614 patches are pg_get_functiondef's output, byte for byte, so 0614's md5 premises pass against them; the
-- helpers they call are the live bodies, except ottoq_policy_set, ottoq_effective_target_soc_at and
-- ottoq_certification_in_flight, which are minimal stand-ins (noted where they are defined). Used by
-- tests/test_agent_charge_order_sql.py on a scratch PostgreSQL. PostGIS is absent: stalls.absolute_point is text here.
SET client_min_messages = warning;
CREATE SCHEMA IF NOT EXISTS twin; CREATE SCHEMA IF NOT EXISTS ottoq; CREATE SCHEMA IF NOT EXISTS extensions;
DO $roles$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;
CREATE TYPE public.stall_type AS ENUM ('dcfc', 'l2', 'wash_bay', 'detail_bay', 'service_bay', 'staging', 'parking', 'safety');
CREATE TYPE public.vehicle_category AS ENUM ('autonomous', 'retail', 'delivery_bot', 'humanoid', 'shuttle');
CREATE TYPE public.vehicle_state AS ENUM ('offline', 'deployed', 'en_route_to_depot', 'arrived_at_gate', 'staged_awaiting_service', 'charging_dcfc', 'charging_l2', 'charge_complete_holding', 'in_wash_bay', 'in_detail_bay', 'in_service_bay', 'service_complete_holding', 'staged_for_departure', 'en_route_to_deployment', 'emergency_staged', 'tow_requested', 'out_of_service');
CREATE TYPE public.av_platform AS ENUM ('waymo', 'motional', 'tesla', 'cruise', 'zoox', 'aurora', 'nuro', 'uber_av', 'generic', 'not_applicable');
CREATE TYPE public.priority_tier AS ENUM ('standard', 'priority', 'vip');
CREATE TYPE public.ottoq_decide_tick_result AS (tick_seq bigint, sim_clock timestamp with time zone, requests_built integer, enacted integer, overridden integer, deferred integer, errored integer, shield_disarmed integer, total_latency_ms integer);

CREATE TABLE public.fleet_operators (id uuid PRIMARY KEY, name text, company text, slug text, contact_name text, contact_email text, contact_phone text, contract_tier text, priority priority_tier, monthly_rate_per_vehicle numeric(10,2), default_target_soc integer, default_service_sequence jsonb, webhook_url text, api_key_hash text, fleet_api_config jsonb, notification_preferences jsonb, is_active boolean, created_at timestamp with time zone, updated_at timestamp with time zone, auth_user_id uuid, progression_acceptance_mode text, oem_acceptance_timeout_seconds integer, oem_acceptance_on_timeout text, oem_flag_inbound_secret text);
CREATE TABLE public.ottoq_cert_lineage (name text UNIQUE, forces_recert boolean, note text, classified_at timestamp with time zone, forces_dial_restart boolean);
CREATE TABLE public.ottoq_decisions (decision_id uuid DEFAULT gen_random_uuid(), decision_seq bigserial, decision_request_id uuid, sim_run_id uuid, tick_seq bigint, sim_clock timestamp with time zone, depot_id uuid, snapshot_id uuid, action_context text, resolved_action_context text, entity_type text, entity_id uuid, gate text, failed_gate text, context_frame jsonb, shield_delta jsonb, proposed_action jsonb, enacted_action jsonb, overridden boolean, override_rule_code text, override_rule_codes text[], override_reason text, override_id uuid, rule_results jsonb, shield_verdict jsonb, shield_disarm_flags jsonb, safe_default_taken boolean, safe_default_shielded boolean, deploy_readiness text, handshake_outcome text, committed_kw_before numeric, committed_kw_after numeric, propose_latency_ms integer, shield_latency_ms integer, enact_latency_ms integer, total_latency_ms integer, outcome_status text, l2_engine text, confidence numeric, created_at timestamp with time zone DEFAULT now());
CREATE TABLE public.ottoq_external_proposals (proposal_id uuid DEFAULT gen_random_uuid(), sim_run_id uuid, depot_id uuid, action_context text, entity_type text, entity_id uuid, proposal jsonb, source text, status text, created_at timestamp with time zone DEFAULT now(), expires_at timestamp with time zone, declared_source text, submitted_by_role text, submitted_by uuid, tick_seq integer, disposition_reason text, disposed_at timestamp with time zone, disposed_tick integer);
CREATE TABLE public.ottoq_fleet_operator_slas (sla_id uuid DEFAULT gen_random_uuid(), fleet_operator_id uuid, contract_reference text, effective_from timestamp with time zone, effective_until timestamp with time zone, status text, version integer, min_soc_at_deployment_pct numeric, preferred_soc_at_deployment_pct numeric, max_charge_target_pct numeric, min_charge_target_pct numeric, max_visit_duration_minutes integer, max_queue_wait_minutes integer, expected_visit_duration_minutes integer, max_concurrent_vehicles_at_depot integer, max_queue_depth integer, max_overnight_stage_count integer, required_services_before_deploy text[], blocked_services text[], oem_acceptance_required boolean, oem_acceptance_timeout_seconds integer, oem_acceptance_on_timeout text, oem_webhook_callback_url text, oem_acceptance_mode text, maintenance_window_start time without time zone, maintenance_window_end time without time zone, allow_maintenance_during_peak boolean, reporting_email text, reporting_webhook text, reporting_frequency text, reports_must_be_signed boolean, audit_retention_days integer, pii_redaction_required boolean, penalty_schedule jsonb, notes text, signed_by_oem text, signed_by_depot text, signed_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone, return_reserve_soc_pct numeric);
CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, depot_id uuid, ocpp_identifier text, vendor text, model text, serial_number text, firmware_version text, ocpp_protocol_version text, station_state text, station_state_changed_at timestamp with time zone, last_heartbeat_at timestamp with time zone, max_kw numeric, num_connectors integer, connector_states jsonb, last_fault_code text, last_fault_at timestamp with time zone, last_fault_payload jsonb, installed_at timestamp with time zone, decommissioned_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone);
CREATE TABLE public.ottoq_policy_param_catalog (param_key text PRIMARY KEY, description text, default_value numeric, min_value numeric, max_value numeric, affects text, min_exclusive numeric, max_exclusive numeric, agent_writable boolean, agent_min_value numeric, agent_max_value numeric, agent_max_drift_pct numeric);
CREATE TABLE public.ottoq_policy_params (scope_type text, scope_id uuid, param_key text, param_value numeric, updated_by text, updated_at timestamp with time zone, PRIMARY KEY (scope_type, scope_id, param_key));
CREATE TABLE public.ottoq_proposer_precedence (source text PRIMARY KEY, rank integer, holds_tick boolean, greedy_yields boolean, note text, added_at timestamp with time zone, added_by text);
CREATE TABLE public.ottoq_run_scope_registry (table_schema text, table_name text, column_name text, class text, note text, registered_at timestamp with time zone DEFAULT now());
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial PRIMARY KEY, taken_at timestamp with time zone DEFAULT now(), label text, object_kind text, schema_name text, object_name text, definition text, def_md5 text);
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, sim_run_seq bigint, scenario_id uuid, scenario_code text, started_at timestamp with time zone, ended_at timestamp with time zone, last_tick_at timestamp with time zone, next_tick_due_at timestamp with time zone, sim_clock_start timestamp with time zone, sim_clock_current timestamp with time zone, sim_clock_end timestamp with time zone, time_scale numeric, tick_interval_seconds integer, tick_count integer, depot_id uuid, random_seed bigint, status text, failure_reason text, events_generated bigint, vehicles_simulated integer, charge_sessions integer, tasks_completed integer, anomalies_injected integer, emergencies_triggered integer, rule_evaluations bigint, rule_failures bigint, predictions_emitted bigint, recommendations_made bigint, timeline_cursor integer, validation_status text, validation_notes text, validation_assertions jsonb, run_by text, notes text, payload jsonb, policy text, ab_group_id uuid, crn_streams jsonb, demo_speed_x numeric, purged_at timestamp with time zone);
CREATE TABLE public.ottoq_stall_bookings (booking_id uuid DEFAULT gen_random_uuid(), sim_run_id uuid, stall_id uuid, vehicle_id uuid, visit_id uuid, leg_id uuid, purpose text, during tstzrange, state text, booked_at timestamp with time zone, booked_by text, released_at timestamp with time zone, release_reason text, source text, decision_id uuid, need_code text, need_atom text, need_source text, leg_source text, why text, decision_link text, booked_at_sim timestamp with time zone);
CREATE TABLE public.ottoq_visit_needs (visit_id uuid DEFAULT gen_random_uuid(), vehicle_id uuid, sim_run_id uuid, depot_id uuid, arrived_at timestamp with time zone, visit_key text, archetype text, urgency text, dispatch_due_at timestamp with time zone, target_soc numeric, atoms jsonb, status text, source text, meta jsonb, created_at timestamp with time zone DEFAULT now());
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid, stall_code text, stall_type stall_type, display_name text, relative_x double precision, relative_y double precision, heading_degrees smallint, absolute_lat double precision, absolute_lng double precision, absolute_point text, distance_from_entrance integer, status text, current_vehicle_id uuid, equipment_config jsonb, fiducial_marker_id text, uwb_beacon_id text, created_at timestamp with time zone, updated_at timestamp with time zone, zone text, reserved_for_mission_id uuid, connector_type text, connector_max_kw numeric, supported_inlet_types text[], ocpp_charger_id uuid, stall_kind text, canopy_code text, covered boolean, stall_width_ft numeric, stall_depth_ft numeric, reserved_by uuid, reserved_at timestamp with time zone, reservation_expires_at timestamp with time zone, staging_role text);
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, fleet_operator_id uuid, retail_member_id uuid, home_depot_id uuid, category vehicle_category, vin text, make text, model text, year smallint, license_plate text, color text, display_name text, battery_capacity_kwh numeric(6,2), max_charge_rate_kw numeric(6,2), connector_type text, target_soc integer, current_soc integer, min_soc_threshold integer, platform av_platform, av_api_vehicle_id text, av_dispatch_capable boolean, current_state vehicle_state, current_stall_id uuid, current_depot_id uuid, last_state_change timestamp with time zone, default_service_sequence jsonb, config jsonb, is_active boolean, created_at timestamp with time zone, updated_at timestamp with time zone, inlet_type text, inlet_max_kw numeric, current_soc_updated_at timestamp with time zone, current_soc_source text, owning_sim_run_id uuid, robotic_tether_until timestamp with time zone, robotic_tether_stall_id uuid, robotic_tether_direction text, robotic_tether_phase text, vehicle_class_code text);

-- live bodies of the helpers 0614's SQL reads
CREATE OR REPLACE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric)
 RETURNS numeric LANGUAGE plpgsql STABLE SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v numeric; v_depot uuid; v_seen text;
BEGIN
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN
    v_seen := COALESCE(current_setting('ottoq.run_scope_reads', true), '');
    IF strpos(v_seen, ',' || p_sim_run_id::text || ':' || p_param_key || ',') = 0 THEN
      PERFORM set_config('ottoq.run_scope_reads',
                         CASE WHEN v_seen = '' THEN ',' ELSE v_seen END || p_sim_run_id::text || ':' || p_param_key || ',', true);
    END IF;
    RETURN v;
  END IF;
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NOT NULL THEN
    SELECT param_value INTO v FROM ottoq_policy_params
     WHERE scope_type='depot' AND scope_id=v_depot AND param_key=p_param_key;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='global' AND scope_id='00000000-0000-0000-0000-000000000000'::uuid
     AND param_key=p_param_key;
  RETURN COALESCE(v, p_default);
END;
$function$;
CREATE OR REPLACE FUNCTION public.ottoq_charge_wait_min(p_config jsonb, p_last_state_change timestamp with time zone, p_clock timestamp with time zone, p_sim_run_id uuid)
 RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT GREATEST(COALESCE(EXTRACT(EPOCH FROM (p_clock - p_last_state_change)) / 60.0, 0), 0)
       + CASE WHEN p_config #>> '{charge_wait,run}' = p_sim_run_id::text
               AND jsonb_typeof(p_config #> '{charge_wait,banked_min}') = 'number'
              THEN GREATEST((p_config #>> '{charge_wait,banked_min}')::numeric, 0)
              ELSE 0 END
$function$;
CREATE OR REPLACE FUNCTION public.ottoq_charge_wait_since(p_config jsonb, p_last_state_change timestamp with time zone, p_sim_run_id uuid)
 RETURNS timestamp with time zone LANGUAGE plpgsql STABLE
AS $function$
BEGIN
  IF p_config #>> '{charge_wait,run}' = p_sim_run_id::text THEN
    RETURN COALESCE((p_config #>> '{charge_wait,since}')::timestamptz, p_last_state_change);
  END IF;
  RETURN p_last_state_change;
EXCEPTION WHEN OTHERS THEN
  RETURN p_last_state_change;
END $function$;
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_fault_open(p_config jsonb)
 RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT COALESCE(jsonb_typeof(p_config->'exception') = 'object', false)
$function$;
CREATE OR REPLACE FUNCTION public.ottoq_default_target_soc()
 RETURNS numeric LANGUAGE sql STABLE SET search_path TO 'public', 'extensions'
AS $function$
  SELECT public.ottoq_policy_get(NULL, 'vehicle_target_soc_default', 100);
$function$;
-- STAND-IN: the live function also reads an owner's verified charge limit (0605); none exists here.
CREATE OR REPLACE FUNCTION public.ottoq_effective_target_soc_at(p_vehicle_id uuid, p_as_of timestamp with time zone)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT LEAST(public.ottoq_default_target_soc(),
    COALESCE((SELECT s.max_charge_target_pct FROM ottoq_fleet_operator_slas s
               WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status='active'
                 AND s.effective_from <= p_as_of AND (s.effective_until IS NULL OR s.effective_until > p_as_of)
               ORDER BY s.version DESC LIMIT 1), 100))
  FROM vehicles v WHERE v.id = p_vehicle_id;
$function$;
-- STAND-IN: the live probe counts certification rigs in pg_stat_activity; here only the simulation setting.
CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean DEFAULT true)
 RETURNS integer LANGUAGE sql STABLE
AS $function$
  SELECT CASE WHEN current_setting('ottoq.simulate_certification_in_flight', true) = 'on' THEN 1 ELSE 0 END;
$function$;
-- STAND-IN: the live setter clamps to the catalog, judges policy_write and logs; here it writes the row.
CREATE OR REPLACE FUNCTION public.ottoq_policy_set(p_scope_type text, p_scope_id uuid, p_param_key text, p_param_value numeric, p_by text)
 RETURNS jsonb LANGUAGE plpgsql
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM ottoq_policy_param_catalog WHERE param_key = p_param_key) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_param');
  END IF;
  INSERT INTO ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
  VALUES (p_scope_type, p_scope_id, p_param_key, p_param_value, p_by, now())
  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by;
  RETURN jsonb_build_object('ok', true, 'applied', p_param_value);
END $function$;

-- the five functions 0614 patches, as the live database held them on 2026-10-07 (pg_get_functiondef, byte for byte)
SET check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.ottoq_decide_tick(p_sim_run_id uuid)
 RETURNS ottoq_decide_tick_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_clock timestamptz; v_tick bigint; v_snapshot_id uuid;
  v_seat int; /* 0261 */
  v_req RECORD; v_ctx jsonb; v_proposal jsonb; v_action jsonb;
  v_blocks int; v_block_codes text[]; v_rule_rows jsonb; v_disarm jsonb;
  v_outcome text; v_over boolean; v_safe boolean;
  v_t0 timestamptz; v_prop_ms int; v_shield_ms int; v_enact_ms int;
  v_built int := 0; v_enacted int := 0; v_overc int := 0; v_deferred int := 0; v_errored int := 0; v_disn int := 0;
  v_bess RECORD; v_energy RECORD;
  v_total_fleet int; v_curr_deployed int; v_target_pct numeric; v_demand_target int; v_deploy_budget int;
  v_charge_cap_kw numeric; v_ev_committed_kw numeric := 0; v_stage_stall uuid;
  v_charge_leg RECORD; v_bkg uuid;
  v_cmd_id uuid; v_cmd_status text; v_cmd_code text; v_cmd_detail text; /* 0493 */
  v_stage_leg_id uuid; v_stage_until timestamptz;
  v_bay_leg_id uuid; v_bay_leg_type text; v_bay_dur interval; v_bay_until timestamptz;
  v_bay_bkg uuid; v_bay_purpose text;
  -- P1 (needs-card space routing)
  v_need RECORD; v_space jsonb;
  v_wash_phys int; v_svc_phys int; v_wash_open int; v_svc_open int;
  -- 0003 (bay work recovery): resumption budget per lane per tick.
  v_res_share numeric; v_wash_res_cap int; v_svc_res_cap int;
  v_wash_res_used int := 0; v_svc_res_used int := 0;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count INTO v_depot, v_clock, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN ROW(0,NULL,0,0,0,0,0,0,0)::ottoq_decide_tick_result; END IF;
  v_snapshot_id := ottoq_capture_decision_snapshot(p_sim_run_id, v_tick, v_depot, v_clock);
  v_seat := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int; /* 0261 */

  -- P1 BAY RELEASE. twin.ottoq_sim_advance_service_flow STEP 1 moves a vehicle OUT of a bay
  -- back to staged_awaiting_service and never clears stalls.current_vehicle_id or
  -- vehicles.current_stall_id; nothing else clears a bay either. Physical bay occupancy is
  -- switched ON below, so without this sweep the 3 wash / 2 service bays would fill and
  -- NEVER free - a permanent depot deadlock after five vehicles. Release-only: this call can
  -- free a space but can never claim one, and it never touches dcfc/l2 stalls.
  -- BOOKING LIFECYCLE. Promote held -> active for every booking whose vehicle is now
  -- physically standing on its stall, BEFORE the release sweep below. This is what gives
  -- 'active' a meaning, and what lets the sweep close a REAL occupancy as 'done' (with its
  -- window truncated to the true end) instead of lumping it in with forward reservations
  -- that nobody ever used. Release-only and non-fatal, like the sweep itself.
  PERFORM ottoq.ottoq_activate_present_bookings(p_sim_run_id, v_clock);

  -- HONOUR OR RE-PLAN, NEVER LET IT ROT (2026-08-02). Runs BEFORE the release sweep on
  -- purpose: a bay reservation whose vehicle is still bolted to a charger is slid forward
  -- to when the car can actually be there, so the sweep below never sees it as a no-show.
  -- Bounded defers + explicit give-up: it can free a window or move one, never claim one.
  PERFORM ottoq.ottoq_reconcile_bay_reservations(p_sim_run_id, v_depot, v_clock);

  PERFORM ottoq.ottoq_release_vacated_spaces(p_sim_run_id, v_depot, v_clock);

  -- NO BAY ENTRY WITHOUT A BOOKING. twin.ottoq_sim_advance_service_flow STEP 2 admits
  -- vehicles into wash/detail/service bays on STAFF capacity and claims no stall at all,
  -- so those occupancies were invisible to the forward calendar -- which is how 22
  -- vehicles came to be "in" 2 physical service bays. OTTO-Q reconciles here: book what
  -- is physically there, in place, against a real stall. Release-only for chargers,
  -- non-fatal, and it never moves a vehicle that is already standing in a real bay.
  PERFORM ottoq.ottoq_bind_unbooked_bay_occupants(p_sim_run_id, v_depot, v_clock);

  SELECT lmp_usd_per_mwh INTO v_energy FROM ottoq_grid_snapshots WHERE sim_run_id=p_sim_run_id ORDER BY sim_clock_at DESC LIMIT 1;

  -- (1) ENERGY / BESS
  FOR v_bess IN SELECT bess_id, current_soc_pct FROM ottoq_bess_units WHERE depot_id = v_depot ORDER BY bess_id   /* 0054: run-stable cursor order */ LOOP
    v_built := v_built + 1; v_t0 := clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := jsonb_build_object('depot_id',v_depot,'now_ts',v_clock,'sim_run_id',p_sim_run_id,  /* 0136 */'bess_id',v_bess.bess_id,
              'bess_soc_pct',v_bess.current_soc_pct,'lmp_usd_mwh',COALESCE(v_energy.lmp_usd_per_mwh,40));
    v_proposal := ottoq_l2_propose_bess(v_bess.bess_id, v_depot, v_ctx);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN
      v_deferred := v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'bess_dispatch','bess',v_bess.bess_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE;
    END IF;
    v_ctx := v_ctx || jsonb_build_object('requested_kw', v_proposal->>'requested_kw', 'action', v_proposal->>'action');
    v_t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('bess_dispatch','bess',v_bess.bess_id,v_ctx,NULL,v_depot);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_bess(v_bess.bess_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1; END IF;
    v_t0 := clock_timestamp();
    IF v_outcome='enacted' THEN PERFORM ottoq_apply_bess_setpoint(v_bess.bess_id, (v_action->>'requested_kw')::numeric, 250, v_clock); END IF;
    v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'bess_dispatch','bess_dispatch','bess',v_bess.bess_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- (2) DEPLOY-READINESS
  SELECT COUNT(*) INTO v_total_fleet FROM vehicles WHERE category='autonomous' AND home_depot_id=v_depot;
  SELECT COUNT(*) INTO v_curr_deployed FROM vehicles
    WHERE category='autonomous' AND home_depot_id=v_depot AND current_state IN ('deployed','en_route_to_deployment');
  SELECT COALESCE((s.fleet_overrides->>'target_deployed_fraction')::numeric, 0.55) INTO v_target_pct
    FROM ottoq_sim_runs r LEFT JOIN ottoq_sim_scenarios s ON s.scenario_code = COALESCE(r.scenario_code,'normal_day')
   WHERE r.sim_run_id = p_sim_run_id;
  v_demand_target := FLOOR(v_total_fleet * ottoq_deploy_target_fraction(EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int, public.ottoq_deploy_peak_fraction(p_sim_run_id) /* 0434: the dispatcher's resolution, not this function's 0.55 */));
  v_deploy_budget := GREATEST(v_demand_target - v_curr_deployed, 0);

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='staged_for_departure'
       AND public.ottoq_departure_clear(v.id, p_sim_run_id, v_clock, true)   /* 0543 (CLAUDE.md rule 9) */
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
             WHERE vn.vehicle_id = v.id AND (vn.sim_run_id = p_sim_run_id OR vn.sim_run_id IS NULL) AND vn.status IN ('open','in_progress')
               AND ((a->>'svc' = 'software_update' AND COALESCE(a->>'status','pending') = 'in_progress')
                 OR (COALESCE((a->>'must_do')::boolean,false) AND a->>'svc' <> 'readiness_check'
                     AND COALESCE(a->>'status','pending') IN ('pending','in_progress'))))
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn2 WHERE vn2.vehicle_id = v.id
             AND vn2.status IN ('open','in_progress') AND COALESCE(vn2.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */ AND vn2.urgency = 'overnight_hold'
             AND vn2.dispatch_due_at IS NOT NULL AND vn2.dispatch_due_at > v_clock)
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn3, jsonb_array_elements(vn3.atoms) a3
             WHERE vn3.vehicle_id = v.id AND vn3.status IN ('open','in_progress') AND COALESCE(vn3.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
               AND COALESCE((a3->>'requires_tech_greenlight')::boolean,false)
               AND NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                     WHERE ap.vehicle_id = v.id AND ap.approval_type = 'tech_greenlight'
                       AND ap.status = 'approved' AND ap.created_at >= vn3.created_at))
       AND NOT EXISTS (SELECT 1 FROM ottoq_decisions d
             WHERE d.sim_run_id = p_sim_run_id
               AND d.entity_id = v.id
               AND d.action_context = 'redeployment'
               AND d.outcome_status = 'enacted'
               AND d.sim_clock >= COALESCE(v.last_state_change, '-infinity'::timestamptz))
     ORDER BY v.current_soc DESC, v.id LIMIT GREATEST(v_deploy_budget,0)
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('redeployment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    -- A1: cuOpt/Nemotron may propose the redeploy; heuristic is the safe fallback.
    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'redeployment', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_deploy(v_req.vehicle_id, v_depot, v_ctx));
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'redeployment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE; END IF;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('redeployment','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_deploy(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      -- BRAIN/TWIN SEPARATION: OTTO-Q does NOT mutate vehicle state. It emits the
      -- command below; ottoq_sim_dispatch_vehicle (twin) performs the transition
      -- atomically with the dispatch record. Writing 'en_route_to_deployment'
      -- here created a limbo the rate-limited twin could not drain (task #169).
      -- (0075) The 'dispatch' command was a NO-OP: confirm_commands has no 'dispatch' verb and
      -- nothing consumes it. The twin dispatches via ottoq_sim_auto_dispatch_tick, which ranks by
      -- ottoq_brain_deploy_rank (reading THIS decision). Emitting it 965x against 91 real
      -- dispatches corrupted the audit ledger. The decision row below IS the deploy signal.
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,deploy_readiness,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'redeployment','redeployment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,CASE WHEN v_outcome='enacted' THEN 'ready' ELSE 'held' END,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- P0 (2026-08-03): A REOPENED NEED IS A FIRST-CLASS DEMAND.
  -- ottoq.ottoq_readmit_resumed_visits was unreachable: its emergency_staged /
  -- retrieved_staged pair is produced ONLY by tow retrieval, whose dwell gate compares a
  -- REAL-clock last_state_change (clobbered by the BEFORE UPDATE trigger) against the SIM
  -- clock and is therefore never true. This stage is keyed on the NEED instead, so a
  -- cut-short charge competes for a plug in the SAME tick, through the SAME intake
  -- cursors below, as a fresh arrival. Self-silencing; can never abort the tick.
  PERFORM ottoq.ottoq_readmit_reopened_needs(p_sim_run_id, v_depot, v_clock);

  -- (3) STALL ASSIGNMENT
  -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Advance the cuOpt deferral
  -- ledger EXACTLY ONCE per decide tick, before the candidate cursor is opened.
  -- roll() step 1 releases every vehicle that a PREVIOUS tick held, so a hold can
  -- never span two consecutive decide ticks; step 2 then consumes this tick's
  -- freshly armed rows. roll() swallows its own errors: if the ledger is broken
  -- the engine simply behaves exactly as it did before this change.
  PERFORM public.ottoq_cuopt_defer_roll(p_sim_run_id, v_tick);
  v_charge_cap_kw := public.ottoq_ev_charge_allowance_kw(p_sim_run_id, v_depot, v_clock);  /* 0132; 0433: the cap is on grid import, so a DR call admits cap - building + solar + sustainable BESS */
  IF v_charge_cap_kw IS NOT NULL THEN
    SELECT COALESCE(SUM(LEAST(COALESCE(st.connector_max_kw,50), COALESCE(vv.inlet_max_kw,250)) * CASE WHEN COALESCE(st.connector_max_kw,50)<=50 THEN 1.0 WHEN COALESCE(vv.current_soc,50)<55 THEN 0.85 WHEN COALESCE(vv.current_soc,50)<75 THEN 0.55 ELSE 0.30 END),0) INTO v_ev_committed_kw
      FROM vehicles vv JOIN stalls st ON st.id = vv.current_stall_id
     WHERE vv.home_depot_id = v_depot AND vv.current_state IN ('charging_dcfc','charging_l2');
  END IF;

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Hold this vehicle out of the local
       -- greedy path for EXACTLY ONE decide tick while a cuOpt solve is in flight,
       -- so the optimizer's answer is not pre-empted by the stall it was solving for.
       -- ottoq_cuopt_defer_hold is READ-ONLY and goes FALSE the moment a usable
       -- proposal exists for this vehicle (right of FIRST REFUSAL, not veto) -- the
       -- vehicle then enters the cursor normally and the proposal is ENACTED here.
       -- It also goes FALSE unconditionally on the next decide tick. No vehicle can
       -- starve: see public.ottoq_cuopt_defer_roll / _arm.
       AND NOT public.ottoq_cuopt_defer_hold(p_sim_run_id, v.id, v_tick)
       -- 0557 (G291, CLAUDE.md rule 9): a car with an open vehicle fault is repaired before it charges. It waits in
       -- staging for the service bay, and this cursor reads a staged car by where it is parked, not what it waits for.
       AND NOT public.ottoq_vehicle_fault_open(v.config)
       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
                 SELECT 1 FROM stalls s2
                   JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                  WHERE s2.depot_id = v_depot
                    AND s2.stall_type::text IN ('dcfc','l2')
                    AND s2.current_vehicle_id IS NULL
                    AND c2.station_state = 'Available'
                    AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                         OR s2.reservation_expires_at <= v_clock))))
       -- 0493 (G210): the deriver's charge rule, below the visit target minus 1 (ottoq_derive_visit_needs and
       -- ottoq_reassess_charge_needs). At the target minus 1 the gate intake (3b) took the car as needing no charge
       -- while this cursor sent it to a charger, in the same tick.
       AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0123 */
              ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) - 1
     ORDER BY COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                 WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0123 */
                 ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) DESC,
              /* 0546 (G271): a car with no open visit is not an immediate dispatch. As NULL it sorted, NULLS LAST,
                 after every car with a visit whatever it had waited: the boot cars G271 found at 91-98%. */
              /* 0261: under a baseline seat the queue order IS the policy: fifo by
                 arrival, greedy by depletion. Both keys are NULL for seat 0 and sort
                 nothing; the immediate_dispatch key above stays first for every seat. */
              CASE WHEN v_seat = 1 THEN v.last_state_change END ASC NULLS FIRST,
              CASE WHEN v_seat = 2 THEN v.current_soc END ASC,
              /* 0545 (G271, CLAUDE.md rule 9): OTTO-Q's seat takes the highest response ratio first, (minutes
                 waited in this state + points to charge) / points to charge. Lowest charge first starved a car that
                 needed only a top-off to 100%, which rule 9 keeps until it is full: nine cars sat the whole day at
                 91-98% on 9eab647f. The ratio rises for every car the longer it waits, so none starves. NULL for
                 the baseline seats, which keep their own keys above. */
              CASE WHEN v_seat = 0 THEN
                /* 0551 (G279): the wait is the car's whole wait in this run's episode, public.ottoq_charge_wait_min:
                   the minutes in its current waiting state plus those it banked earlier. A charger fault, or a move
                   from the gate to staging or to a bay, used to restart it at zero. */
                (public.ottoq_charge_wait_min(v.config, v.last_state_change, v_clock, p_sim_run_id)
                 + GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1))
                / GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1)
              END DESC NULLS LAST,
              v.current_soc ASC, v.id
     -- charging_staff gate: general techs plug in / unplug and do the interior
     -- clean at the stall, so STAFF (not stalls) cap how many cars can be on
     -- charge at once. Neutral staffing (cap >= the 45 physical charge stalls)
     -- leaves the cursor unbounded, so this is a no-op until the knob moves.
     LIMIT (CASE
              WHEN ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', 45) >= 45
                THEN 2147483647
              ELSE GREATEST(0,
                     ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', 45)
                     - (SELECT count(*) FROM vehicles vc
                         WHERE vc.home_depot_id = v_depot
                           AND vc.current_state IN ('charging_dcfc','charging_l2')))
            END)
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('stall_assignment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    v_proposal := ottoq_honour_reservation_proposal(p_sim_run_id, v_req.vehicle_id, v_depot, v_ctx);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      IF (SELECT current_stall_id FROM vehicles WHERE id = v_req.vehicle_id) IS NULL THEN
        -- DOCTRINE (Chase 2026-07-28): never a gate queue; temp vs perimeter is chosen by
          -- PURPOSE and duration, not by whichever staging stall sorts first.
          DECLARE v_disp jsonb; v_hold jsonb;
          BEGIN
            v_disp := ottoq_arrival_disposition(p_sim_run_id, v_depot, v_req.vehicle_id, v_clock);
            IF (v_disp->>'action') IN ('perimeter_hold','temp_stage_await_resource','temp_stage_tech_hold','quarantine') THEN
              v_hold := ottoq_book_hold_stall(
                          p_sim_run_id, v_depot, v_req.vehicle_id,
                          COALESCE((v_disp->>'stage_from')::timestamptz, v_clock),
                          COALESCE((v_disp->>'stage_until')::timestamptz, v_clock + interval '30 minutes'));
              IF COALESCE((v_hold->>'booked')::boolean, false) THEN
                SELECT b.stall_id INTO v_stage_stall
                  FROM ottoq_stall_bookings b WHERE b.booking_id = (v_hold->>'booking_id')::uuid;
                IF v_stage_stall IS NOT NULL
                   AND ottoq_reserve_stall(v_stage_stall, v_req.vehicle_id, v_clock, 900) THEN
                  -- 0039: emit command instead of direct UPDATE
                  PERFORM ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'proceed_to_stall',
                          jsonb_build_object('stall_id', v_stage_stall, 'new_state', 'staged_awaiting_service'), v_clock);
                ELSE
                  -- 0471 (G203): the car is not going to this stall, so the hold is released now instead of keeping
                  -- the stall off the calendar for every other car until its window runs out.
                  UPDATE ottoq_stall_bookings
                     SET state = 'released', released_at = v_clock, release_reason = 'reserve_refused_decide_tick'
                   WHERE booking_id = (v_hold->>'booking_id')::uuid AND state = 'held';
                END IF;
              END IF;
            END IF;
          END;
      END IF;
      CONTINUE; END IF;
    v_ctx := v_ctx || jsonb_build_object('stall_id', v_proposal->>'stall_id', 'requested_kw', v_proposal->>'requested_kw');
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_stall(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal;
      /* 0132: THE SITE POWER CAP IS A CONSTRAINT, NOT A NOTE. Refuse before the stall is
         reserved and before any command is emitted, so a refusal costs nothing and still
         falls through to the decision INSERT with its own reason code. */
      IF v_charge_cap_kw IS NOT NULL
         AND public.ottoq_policy_get(p_sim_run_id, 'enforce_site_charge_cap', 1) >= 1
         AND (COALESCE(v_ev_committed_kw,0) + COALESCE((v_action->>'requested_kw')::numeric,0)) > v_charge_cap_kw THEN
        v_outcome:='deferred_site_power_cap'; v_deferred:=v_deferred+1;
      ELSIF ottoq_reserve_stall((v_action->>'stall_id')::uuid, v_req.vehicle_id, v_clock, 600) THEN
        -- 0039: old-stall cleanup handled by twin on begin_charge confirmation
        -- 0039: emit charge command instead of direct UPDATE
        v_cmd_id := ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'begin_charge',
                jsonb_build_object(
                  'stall_id', (v_action->>'stall_id')::text,
                  'stall_type', v_action->>'stall_type',
                  'new_state', CASE WHEN v_action->>'stall_type'='dcfc' THEN 'charging_dcfc' ELSE 'charging_l2' END,
                  /* 0066: folded in from the duplicate emit removed below, so this one
                     command carries everything both used to. Nothing reads requested_kw
                     off a command -- ottoq_claim_tick_kw takes the real figure from
                     v_action on the next line -- but the record keeps it. */
                  'requested_kw', v_action->>'requested_kw'
                ), v_clock);
      -- 0039: charge stall claim handled by twin on command confirmation
        -- 0493 (G226): THE EMISSION GATE'S ANSWER IS READ. The gate refuses what ottoq_validate_assignment refuses,
        -- most often a live calendar booking held by another car. Everything below used to run anyway: the decision
        -- read enacted, the kW was claimed, and ottoq_record_enacted_booking superseded the other car's booking and
        -- booked this car on a charger it was not going to (57 of 217 on busy_day/171717/48, verdict 383). A refused
        -- command now claims, starts, plans and books nothing, the reservation taken above is released, and the
        -- refusal reactor reroutes it as before.
        SELECT c.status, c.reason_code, c.reason_detail INTO v_cmd_status, v_cmd_code, v_cmd_detail
          FROM public.ottoq_vehicle_commands c WHERE c.command_id = v_cmd_id;
        IF v_cmd_status = 'refused' THEN
          UPDATE public.stalls
             SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
           WHERE id = (v_action->>'stall_id')::uuid AND reserved_by = v_req.vehicle_id AND current_vehicle_id IS NULL;
          v_action := jsonb_build_object('verb', 'charger_refused', 'reason', COALESCE(v_cmd_code, 'refused'),
                                         'stall_type', v_action->>'stall_type', 'refused_detail', v_cmd_detail,
                                         'command_id', v_cmd_id);
          v_outcome := 'deferred_stale_entity'; v_deferred := v_deferred + 1;
        ELSE
        PERFORM ottoq_claim_tick_kw(p_sim_run_id, v_tick, v_depot, (v_action->>'requested_kw')::numeric, v_req.vehicle_id);
        PERFORM ottoq_start_concurrent_atoms(v_req.vehicle_id, v_clock);
        PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_req.vehicle_id, v_clock);

        -- FORWARD AVAILABILITY / P0: ENACTMENT AND CALENDAR ARE ONE ACT.
        -- Every stall assignment that reaches this line - cuopt, deterministic, greedy and
        -- reservation_honoured all return through v_action above - is now recorded on the
        -- forward calendar in THIS transaction, against the EXACT stall enacted.
        --
        -- Previously the booking sat inside "IF v_charge_leg.leg_id IS NOT NULL", and the planner
        -- emits a charge leg only when the visit-need manifest carries an svc='charge' atom. When
        -- it does not, that branch never ran: 51 enacted charge assignments, 0 charge bookings,
        -- 0% end-to-end coverage. The booking no longer depends on a planned leg existing.
        --
        -- The leg is still PREFERRED when present, for two reasons: it carries the real timed
        -- window, and stamping to_stall_id is the existing sentinel that removes the leg from both
        -- booking cursors (ottoq_book_workflow / ottoq_find_and_book_stall), suppressing the second
        -- independent stall search. The calendar still RECORDS the decision, it never re-derives it.
        SELECT l.leg_id, l.leg_type, l.planned_start_sim, l.planned_end_sim
          INTO v_charge_leg
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id  = p_sim_run_id
           AND l.vehicle_id  = v_req.vehicle_id
           AND l.status      = 'planned'
           AND l.to_stall_id IS NULL
           AND l.leg_type IN ('charge_dcfc','charge_l2')
           AND l.planned_start_sim IS NOT NULL
           AND l.planned_end_sim   IS NOT NULL
           AND l.planned_end_sim   > v_clock
         ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;

        -- p_purpose is left NULL so the purpose is derived from the stall ACTUALLY taken, not from
        -- what the planner intended. The helper supersedes phantom overlaps, is idempotent on
        -- (run, stall, vehicle, purpose, window), and can never abort this tick.
        v_bkg := ottoq.ottoq_record_enacted_booking(
                   p_sim_run_id, (v_action->>'stall_id')::uuid, v_req.vehicle_id, v_clock,
                   v_charge_leg.leg_id, v_charge_leg.planned_start_sim, v_charge_leg.planned_end_sim,
                   NULL, COALESCE(v_action->>'source','deterministic'));

        IF v_bkg IS NOT NULL AND v_charge_leg.leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs
             SET to_stall_id = (v_action->>'stall_id')::uuid
           WHERE leg_id = v_charge_leg.leg_id;
        END IF;

        v_outcome:='enacted'; v_enacted:=v_enacted+1;
        v_ev_committed_kw := v_ev_committed_kw + COALESCE((v_action->>'requested_kw')::numeric,0);
        END IF;  -- 0493 (G226): the refused command's branch opens above the kW claim
        /* ══════════ 0066: THE DUPLICATE begin_charge EMIT IS REMOVED HERE ══════════
           This line used to emit a SECOND begin_charge for the same vehicle, stall and
           tick as the one already emitted at the top of this branch -- same branch, no
           conditional between them, so both always fired. Measured in re-cert #18 arm A:
           589 refusals on the surviving variant, 584 on this one. It halved the refusal
           reactor (LIMIT 20 per tick against an unbounded backlog) by making it re-read
           decisions it had already handled, and it manufactured the byte-tied duplicate
           command rows that broke the supersede ordering in #16 and forced 0062.
           The surviving emit above now carries requested_kw as well. */
      ELSE v_action:=ottoq_l1_safe_default_stall(v_req.vehicle_id,v_ctx); v_outcome:='deferred_stale_entity'; v_deferred:=v_deferred+1; END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- (3b) GATE INTAKE — NO-CHARGE ARRIVALS
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') <> 'done'))
       -- 0493 (G210): nothing else sent this car to a stall this tick. The charge step (3) runs first, and when both
       -- took a car the door kept one of the two by command type, not by what the car needed. 0472 gave the
       -- inspection seam the same guard.
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands vc
                        WHERE vc.vehicle_id = v.id AND vc.sim_run_id = p_sim_run_id
                          AND vc.issued_at = v_clock AND vc.status = 'issued'
                          AND vc.payload ? 'stall_id')
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id   /* 0054: the sibling cursors' own fairness idiom, made explicit here too */
  LOOP
    -- 0467 (G199): take the first stall, in the intake's own order, that the emission gate accepts.
    -- ottoq_emit_vehicle_command refuses pre-flight whatever ottoq_validate_assignment refuses (pointer,
    -- reservation, stall status, and a live calendar booking held by another car at this moment). The pick
    -- asked only the pointer, so 51 of 61 intakes on 317d4331 were refused and rerouted. OFFSET 0 keeps the
    -- validator above the sort, so it runs only until it finds a stall; the outer ORDER BY pins the choice.
    SELECT c.id INTO v_stage_stall
      FROM (SELECT s.id, (s.staging_role = 'temp') AS temp_first, s.distance_from_entrance AS dist
              FROM stalls s
             WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
               AND s.zone IS DISTINCT FROM 'arrival_inspection'
               AND s.current_vehicle_id IS NULL
               AND (s.reserved_by IS NULL OR s.reservation_expires_at <= v_clock)
             ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id
            OFFSET 0) c
     WHERE COALESCE((ottoq.ottoq_validate_assignment(v_req.vehicle_id, c.id, 'proceed_to_stall',
                                                     v_clock, p_sim_run_id)->>'ok')::boolean, false)
     ORDER BY c.temp_first DESC, c.dist NULLS LAST, c.id LIMIT 1;
    IF v_stage_stall IS NOT NULL AND ottoq_reserve_stall(v_stage_stall, v_req.vehicle_id, v_clock, 900) THEN
      -- 0039: emit command instead of direct UPDATE — twin owns vehicle state
      PERFORM ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'proceed_to_stall',
              jsonb_build_object('stall_id', v_stage_stall,
                                 'reason', 'gate_intake',   -- 0467 (G199): from the second command, removed below
                                 'new_state', 'staged_awaiting_service',
                                 'svc_step', CASE WHEN EXISTS (SELECT 1 FROM ottoq_visit_needs vn2, jsonb_array_elements(vn2.atoms) a2
                                                               WHERE vn2.vehicle_id = v_req.vehicle_id AND vn2.status IN ('open','in_progress') AND COALESCE(vn2.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
                                                                 AND a2->>'svc' IN ('mechanical_pm','fault_repair','sensor_calibration')
                                                                 AND COALESCE((a2->>'must_do')::boolean,false)
                                                                 AND COALESCE(a2->>'status','pending') = 'pending')
                                                THEN 'need_service' ELSE 'need_deploy' END), v_clock);
      -- 0039: stall claim now handled by twin on command confirmation
      PERFORM ottoq_start_concurrent_atoms(v_req.vehicle_id, v_clock);
      v_built := v_built + 1; v_enacted := v_enacted + 1;
      PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_req.vehicle_id, v_clock);
      -- CALENDAR (staging). The single biggest gap: the whole service-only intake path
      -- enacted a stall and wrote NOTHING to the forward-occupancy calendar.
      -- We RECORD the stall the intake ALREADY picked above. We must NOT call
      -- ottoq_book_hold_stall here: it runs its OWN independent search, which is exactly
      -- the decision/calendar divergence fixed on 2026-08-01.
      SELECT l.leg_id INTO v_stage_leg_id
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.leg_type = 'stage' AND l.to_stall_id IS NULL
         AND l.planned_end_sim > v_clock
       ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;
      -- The car holds this staging stall until its itinerary is done: nothing in (4) or (5)
      -- clears stalls.current_vehicle_id, only (3)'s charge branch and redeploy do.
      -- Hard-capped so a runaway itinerary can never reserve a space indefinitely.
      SELECT max(l.planned_end_sim) INTO v_stage_until
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.planned_end_sim > v_clock;
      v_stage_until := GREATEST(
        LEAST(
          COALESCE(v_stage_until,
                   v_clock + make_interval(mins => ottoq_policy_get(p_sim_run_id,'staging_hold_default_min',30)::int)),
          v_clock + make_interval(mins => ottoq_policy_get(p_sim_run_id,'staging_hold_max_min',480)::int)),
        v_clock + interval '1 minute');
      -- 0476 (G206): recorded through the enacted-booking seam on the stall already picked, which runs no search of its
      -- own. A bare ottoq_book_stall collided with the car's own live hold on that stall (the validator exempts it) and
      -- the intake went on with no booking, 3 of 46 on 49c45bd4. The seam supersedes the car's own overlapping booking
      -- and truncates an overlapping done one first, as it does for every other enacted placement.
      v_bkg := ottoq.ottoq_record_enacted_booking(p_sim_run_id, v_stage_stall, v_req.vehicle_id, v_clock,
                 v_stage_leg_id, v_clock, v_stage_until, 'staging', 'gate_intake_staging');
      IF v_bkg IS NOT NULL THEN
        UPDATE public.ottoq_stall_bookings SET source = COALESCE(source, 'gate_intake_staging')
         WHERE booking_id = v_bkg;
      END IF;
      IF v_bkg IS NOT NULL AND v_stage_leg_id IS NOT NULL THEN
        -- same sentinel the charge path uses: a stamped to_stall_id removes the leg from
        -- ottoq_book_workflow's cursor, so no second independent search can re-derive it.
        UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stage_stall
         WHERE leg_id = v_stage_leg_id;
      END IF;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','gate_intake_no_charge','vehicle',v_req.vehicle_id,
              jsonb_build_object('stall_id',v_stage_stall,'staging_pick','temp_first'),
              jsonb_build_object('verb','gate_intake','stall_id',v_stage_stall),
              jsonb_build_object('verb','gate_intake','stall_id',v_stage_stall,'booking_id',v_bkg),
              'enacted',0,0);
      -- 0467 (G199): a second proceed_to_stall to the same stall used to follow here, carrying only
      -- `reason` (now on the command above). Refused, the two became two reroutes to two stalls; the door kept
      -- one by stall id and the other's hour-long reservation and booking stayed behind (49 on 317d4331).
    END IF;
  END LOOP;

  -- (4) CHARGE DISPOSITION
  -- ═══════════ 0011-TETHER: THE IN-DEPOT MOVE DOOR ═══════════
  -- The founder decision is that a mated vehicle is blocked from ALL movement, not
  -- redeployment only. This cursor is the charge-stall -> wash-bay door, and it reads
  -- exactly the state a just-finished DCFC car is in, so without the predicate below a
  -- car would be sent to a wash bay while the arm is still retracting the cable.
  -- ottoq_vehicle_is_tethered is STABLE, NULL-safe and never raises, and fails OPEN, so
  -- it can only remove a candidate from this tick -- never abort the tick.
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='charge_complete_holding'
       AND NOT public.ottoq_vehicle_is_tethered(v.id, v_clock)
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('task_start','vehicle',v_req.vehicle_id,v_depot,v_clock) || jsonb_build_object('requires_charging','false','service','wash');
    v_proposal := ottoq_l2_propose_charge_disposition(v_req.vehicle_id, v_depot, v_ctx || jsonb_build_object('sim_run_id', p_sim_run_id));
    v_prop_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE; END IF;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('task_start','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_charge_disposition(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      IF COALESCE(v_action->>'verb','admit_wash') = 'skip_wash' THEN
        -- SERVICE-NEED ROUTING (2026-08-01): no wash/detail work outstanding, so do
        -- NOT burn one of the depot's 3 wash bays on a clean car. Advance the vehicle
        -- inside the SAME atomic visit to what it does still need. Nothing is booked
        -- and no stall is claimed, so the calendar cannot over-report.
        -- 0039: emit staging command instead of direct UPDATE
        PERFORM ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'stage',
                jsonb_build_object('reason','no_wash_need','next_step',COALESCE(v_action->>'next_step','need_deploy')), v_clock);
        v_action := COALESCE(v_action,'{}'::jsonb) || jsonb_build_object('bay_booked', false, 'bay_stall_type', 'none');
      ELSE
      -- BAY ENTRY MOVED BELOW THE HELPER (Phase 3). It used to happen HERE, before any
      -- bay had been claimed or booked: if ottoq_enact_space_assignment then found no free
      -- bay, the vehicle was already 'in_wash_bay' with no stall and no calendar row --
      -- a bay physically occupied while the calendar showed it free. The state flip and
      -- the enter_wash command are now gated on the booking, exactly as (4b) already was.
      -- CALENDAR (wash/detail bay). CHOOSE + CLAIM + RECORD, one act.
      -- ottoq_enact_space_assignment picks the bay, reserves it, writes
      -- vehicles.current_stall_id and books the window in THIS transaction. The bay entry
      -- below is GATED on that result: no free bay means no entry, and the miss is recorded
      -- on the decision row as verb 'hold_no_bay'. The calendar can under-report a REFUSAL
      -- but it can no longer report a bay as free while a vehicle is standing in it.
      SELECT l.leg_id, l.leg_type, (l.planned_end_sim - l.planned_start_sim)
        INTO v_bay_leg_id, v_bay_leg_type, v_bay_dur
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.to_stall_id IS NULL
         AND l.leg_type IN ('wash','detail')
       ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;
      IF v_bay_leg_id IS NULL THEN
        -- FALLBACK -- THIS IS WHY leg_id WAS NULL ON EVERY ENACTED BOOKING (11 of 11 on
        -- run 4332b898, against 94 of 94 on the planner path). The forward planner
        -- ottoq_book_workflow books the leg AHEAD of time and stamps to_stall_id, so the
        -- cursor above (to_stall_id IS NULL) found nothing and enactment booked a SECOND
        -- row on a possibly different stall with no leg. Adopt the planned leg instead:
        -- ottoq_enact_space_assignment honours its reservation and
        -- ottoq_record_enacted_booking adopts that row rather than duplicating it.
        SELECT l.leg_id, l.leg_type, (l.planned_end_sim - l.planned_start_sim)
          INTO v_bay_leg_id, v_bay_leg_type, v_bay_dur
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
           AND l.status IN ('planned','active')
           AND l.leg_type IN ('wash','detail')
         ORDER BY (l.status = 'active') DESC, l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;
      END IF;
      -- TOTAL allow-list leg_type -> purpose. Only the two wash-lane leg types can reach
      -- here; nothing is ever passed through to the CLOSED 9-label purpose CHECK.
      -- (no detail_bay stalls are seeded - detail shares the wash lane, as in ottoq_book_workflow)
      v_bay_purpose := CASE WHEN COALESCE(v_action->>'bay_kind', v_bay_leg_type) = 'detail' THEN 'detail' ELSE 'wash' END;
      v_bay_until := v_clock + GREATEST(
        COALESCE(v_bay_dur,
                 make_interval(mins => ottoq_policy_get(p_sim_run_id,'wash_bay_default_min',25)::int)),
        interval '1 minute');
      v_space := ottoq.ottoq_enact_space_assignment(p_sim_run_id, v_depot, v_req.vehicle_id,
                     'wash_bay', v_bay_purpose, v_clock, v_bay_until,
                     v_bay_leg_id, 'charge_disposition');
      v_bay_bkg := NULLIF(v_space->>'booking_id','')::uuid;
      IF v_bay_bkg IS NOT NULL AND v_bay_leg_id IS NOT NULL THEN
        UPDATE public.ottoq_itinerary_legs
           SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                               WHERE b.booking_id = v_bay_bkg)
         WHERE leg_id = v_bay_leg_id;
      END IF;
      IF COALESCE((v_space->>'assigned')::boolean, false) THEN
        -- ENTRY AND CALENDAR ARE ONE ACT. A real wash bay has been claimed AND booked in
        -- this transaction, so the command names the stall, the booking and the leg.
      -- 0039: vehicle state update handled by twin on 'enter_wash' command confirmation
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'enter_wash',
                jsonb_build_object('stall_id',   v_space->>'stall_id',
                                   'booking_id', v_space->>'booking_id',
                                   'leg_id',     v_bay_leg_id,
                                   'purpose',    v_bay_purpose), v_clock);
        v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('bay_booked', v_bay_bkg IS NOT NULL,
                                          'bay_purpose', v_bay_purpose,
                                          'bay_stall_type', 'wash_bay',
                                          'stall_id', v_space->>'stall_id',
                                          'booking_id', v_space->>'booking_id',
                                          'leg_id', v_bay_leg_id);
      ELSE
        -- NO BAY -> DO NOT ENTER ONE. The vehicle is left exactly where this proposer's own
        -- 'wash_lane_full_hold' abstain leaves it (charge_complete_holding) and is retried
        -- next tick. No state write, no command, no booking. Throughput cannot regress:
        -- this branch is only reachable when there is genuinely no bookable wash bay, and
        -- release step (b) hard-frees stale bay stalls earlier in this same tick.
        v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
                                          'bay_purpose', v_bay_purpose,
                                          'bay_stall_type', 'wash_bay');
        v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; v_deferred := v_deferred + 1;
      END IF;
      END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- ══════════════════════════════════════════════════════════════════════════════════
  -- (4b) NEEDS-CARD SPACE ROUTING  —  P1, 2026-08-01
  --
  -- WHAT THIS CLOSES. Before this block the engine literally could not decide "send this
  -- vehicle to the wash bay". The ONLY door into in_wash_bay/in_detail_bay was section (4),
  -- whose cursor is current_state='charge_complete_holding'. Measured on run c177c1ca over
  -- 573 ticks: ZERO admit_wash decisions, 5 skip_wash — while 371 vehicles were promoted
  -- straight from staged_awaiting_service to staged_for_departure by (5), a state from which
  -- no wash/detail door existed at all. That is the whole reason 51 of 51 (and 209 of 209
  -- before) enacted assignments were charging while 3 wash bays sat 100 pct idle.
  --
  -- WHAT IT DOES. For each vehicle HOLDING in staging, read public.ottoq_vehicle_needs_card,
  -- take the highest-priority must-do need that requires a SPACE, and place the vehicle into
  -- the space that need's lane requires — through ottoq_enact_space_assignment, so choosing
  -- the stall and writing the forward-calendar booking are ONE act against the SAME stall
  -- (the P0 rule, now extended past chargers).
  --
  -- SPACE MAP is read from service_cadence_policy.lane, never hardcoded, and is TOTAL:
  --   lane 'wash_bay'    (exterior_wash)                        -> wash_bay,    purpose 'wash'
  --   lane 'detail'      (interior_deep_clean)                  -> wash_bay,    purpose 'detail'
  --        ^ zero detail_bay stalls are seeded; detail shares the wash lane, exactly as
  --          ottoq_book_workflow and twin STEP 2 already do.
  --   lane 'service_bay' (fault_repair, sensor_calibration,
  --                       mechanical_pm, cosmetic_repair)       -> service_bay, purpose 'service'
  --   lane 'anchor'      (charge)      -> NOT HANDLED HERE, see CHARGE FIREWALL.
  --   lane 'cabin'/'exterior'/'digital'/'gate' -> NO SPACE AT ALL. That work overlaps
  --        charging and is already started at the stall by ottoq_start_concurrent_atoms;
  --        spending one of 3 wash or 2 service bays on it would be a straight loss.
  --   any lane the catalogue gains later -> no space, silently skipped. TOTAL FUNCTION
  --        (the 2026-08-01 leg_type lesson): an unknown lane can never reach a CHECK.
  --
  -- ══ ORDERING / PRIORITY RULE ══
  --   WITHIN a vehicle : lowest service_cadence_policy.sequence_order wins, so the visit is
  --     worked in the catalogue's own order (fault_repair 30 -> wash 40 -> detail 45 ->
  --     calibration 55 -> pm 60 -> cosmetic 70). One space at a time; the vehicle comes back
  --     through this block on a later tick for the next item, inside ONE atomic visit.
  --   ACROSS vehicles  : 1. urgency rank DESC (critical > overdue > due > due_soon > ok)
  --                      2. (0545, G270: fits_window left this ordering. Under rule 9 no car leaves
  --                         unfinished, and a car past its deploy time never "fits", so it sorted
  --                         the latest cars last. Earliest deadline first below.) Was: do not burn a scarce bay on work that
  --                         provably cannot finish before the vehicle is due out
  --                      3. minutes_to_deploy ASC — earliest deadline first (EDF)
  --                      4. open_must_do_min ASC — shortest job first, so a scarce bay
  --                         clears more vehicles per hour
  --                      5. vehicle_id — deterministic, seed-stable tiebreak
  --
  -- ══ CHARGE FIREWALL — five independent reasons this cannot regress charging ══
  --  1. Sections (1),(2),(3),(3b) are byte-for-byte unchanged by this migration, including
  --     Gate B in ottoq_honour_reservation_proposal and the cuOpt 'source' passthrough.
  --  2. This block only ever asks for 'wash_bay' or 'service_bay', and
  --     ottoq_enact_space_assignment REFUSES 'dcfc'/'l2' outright. No path built here can
  --     reserve, occupy or book a charger.
  --  3. Any vehicle whose card still lists 'charge' in must_do_now is SKIPPED and left to
  --     section (3). Charge is the anchor leg (sequence_order 10): energy first, then bays.
  --  4. It runs AFTER (3), so every charge decision this tick is already made and its stalls
  --     already reserved before one bay is considered.
  --  5. Separate staff pools: charging is capped by 'charging_staff', wash by
  --     LEAST(cleaning_staff, wash_supervisor), service by 'service_staff'. Bay work cannot
  --     consume a charging tech.
  --  NET EFFECT ON CHARGING IS POSITIVE: today a vehicle in a bay still holds the l2/dcfc
  --  stall it charged on, because nothing clears it. Occupying the bay moves
  --  vehicles.current_stall_id, which fires trg_sync_stall_occupancy and hands that charger
  --  straight back to section (3). Chargers are freed sooner, never later.
  --
  -- ══ ANTI-STARVATION ══ wash and service headroom are computed with the TWIN'S OWN
  -- capacity formulas, verbatim, so this block can never admit past the lane the twin itself
  -- would allow, and the two lanes are counted separately so neither can starve the other.
  --
  -- ══ IN-DEPOT REASSIGNMENT / ZONES ══ the cursor is restricted to current_state
  -- 'staged_awaiting_service', a HOLDING state. It structurally cannot pick up a vehicle that
  -- is charging, washing or being serviced, so it can never re-route work in progress and
  -- therefore never needs ottoq_indepot_reassignment_guard — this is forward progression to
  -- the next due leg of the same visit, which is exactly what (4) and (5) already do. Zone C
  -- (malfunction / congestion / flag) vehicles are skipped and left to the exception path
  -- that owns them. Zone is NOT required to be 'A' here: ottoq_approach_zone fails closed to
  -- 'B' for any vehicle with no approach-band row, which is every in-depot vehicle, so an
  -- A-only test would silently disable the whole block.
  --
  -- ══ COST ══ ottoq_vehicle_needs_card is a 116-row / ~250 ms view. It is evaluated ONCE per
  -- tick and only after two cheap pre-checks find both a waiting vehicle and lane headroom.
  -- ══════════════════════════════════════════════════════════════════════════════════
  SELECT count(*) FILTER (WHERE s.stall_type = 'wash_bay'::stall_type),
         count(*) FILTER (WHERE s.stall_type = 'service_bay'::stall_type)
    INTO v_wash_phys, v_svc_phys
    FROM stalls s
   WHERE s.depot_id = v_depot AND s.status NOT IN ('maintenance','closed');

  IF COALESCE(v_wash_phys,0) + COALESCE(v_svc_phys,0) > 0
     AND EXISTS (SELECT 1 FROM vehicles v
                  WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
                    AND v.current_state = 'staged_awaiting_service') THEN

    v_wash_open := GREATEST(0,
      LEAST(ottoq_sim_lane_capacity(p_sim_run_id,'cleaning_staff', GREATEST(COALESCE(v_wash_phys,0),1)),
            ottoq_depot_staffing_count(v_depot,'wash_supervisor'))
      - (SELECT count(*) FROM vehicles
          WHERE home_depot_id = v_depot AND current_state IN ('in_wash_bay','in_detail_bay')));
    v_svc_open := GREATEST(0,
      ottoq_sim_lane_capacity(p_sim_run_id,'service_staff', GREATEST(COALESCE(v_svc_phys,0),1))
      - (SELECT count(*) FROM vehicles
          WHERE home_depot_id = v_depot AND current_state = 'in_service_bay'));

    -- ══════════════ 0003 ANTI-STARVATION BUDGET ══════════════
    -- Resumed bay work outranks fresh work at equal urgency (see the cursor below), so
    -- without a ceiling a queue of interrupted vehicles could take an entire lane and
    -- fresh arrivals would wait. This caps how many of THIS TICK'S admissions per lane
    -- may go to resumption -- but ONLY while fresh candidates are actually competing for
    -- that same lane (fresh_waiting_lane > 0 in the loop). With no fresh demand the cap
    -- does not bite and idle bays are never held empty on principle.
    --   GREATEST(1, ...) is load-bearing: the defect being fixed is bay recovery of ZERO,
    --   so resumption must never be budgeted down to nothing.
    --   share 0.5 => at most half a lane's free bays (rounded up) per tick. With the
    --   depot's 3 wash / 2 service bays that is 1-2 per lane per tick, and the loop runs
    --   every tick, so five interrupted vehicles clear in a handful of ticks.
    v_res_share := LEAST(GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'bay_resume_share_max',0.5),0.5), 0), 1);
    v_wash_res_cap := GREATEST(1, CEIL(COALESCE(v_wash_open,0) * v_res_share))::int;
    v_svc_res_cap  := GREATEST(1, CEIL(COALESCE(v_svc_open,0)  * v_res_share))::int;

    IF COALESCE(v_wash_open,0) + COALESCE(v_svc_open,0) > 0 THEN
      FOR v_need IN
        WITH card AS (
          SELECT c.vehicle_id, c.overall_urgency, c.must_do_now, c.minutes_to_deploy,
                 c.fits_window, c.open_must_do_min,
                 -- 0003: the ledger detector and the energy grade, read straight off the card.
                 c.owed_bay_svcs, c.rebook_owed, c.energy_urgency, c.soc_deficit_to_target
            FROM public.ottoq_vehicle_needs_card c
           WHERE c.depot_id = v_depot
             -- CHARGE FIRST (full-service visit doctrine, anchor leg): if energy is still a
             -- must-do, this vehicle belongs to section (3), not to a bay.
             --
             -- ══════════════ 0003: ONE NARROW EXCEPTION, AND WHY ══════════════
             -- MEASURED (run 093c20f4, vehicle 0ea2ccfe): its end-of-run card read
             -- must_do_now = {charge, interior_deep_clean, software_update}. The detail bay
             -- it had been pulled out of was still owed AND still must-do, and this single
             -- predicate excluded it anyway -- for the whole rest of the run.
             -- The exception is deliberately the narrowest one that fixes that case:
             --   (a) the vehicle OWES interrupted bay work (ledger, not cadence);
             --   (b) energy is not 'critical' -- a vehicle that will miss its SLA on charge
             --       is still section (3)'s, always;
             --   (c) there is NO free, available, unreserved charger at this depot RIGHT NOW.
             -- (c) is the load-bearing one. Section (3) has already run this tick with the
             -- very same availability predicate; if a plug existed this vehicle would be on
             -- it. So the bay costs the depot no charging whatsoever -- it is time the car
             -- would otherwise spend parked in staging waiting for a plug that does not exist.
             -- The moment a charger frees, the exception stops applying to new vehicles, and
             -- a car already in a bay is finishing an atomic leg, not being held off energy.
             AND ( NOT ('charge' = ANY (COALESCE(c.must_do_now, '{}'::text[]))
                        OR COALESCE(c.soc_pct, 0) < public.ottoq_effective_target_soc_at(c.vehicle_id, v_clock) - 1)   /* 0543: the one charge rule (G244); the card's deficit is to 100 and left a car at 99% to neither */
                   OR ( COALESCE(c.rebook_owed, false)
                        AND COALESCE(c.energy_urgency, 'ok') <> 'critical'
                        AND NOT EXISTS (
                              SELECT 1 FROM stalls s3
                                JOIN ottoq_ocpp_chargers c3 ON c3.charger_id = s3.ocpp_charger_id
                               WHERE s3.depot_id = v_depot
                                 AND s3.stall_type::text IN ('dcfc','l2')
                                 AND s3.current_vehicle_id IS NULL
                                 AND c3.station_state = 'Available'
                                 AND (s3.reserved_by IS NULL OR s3.reserved_by = c.vehicle_id
                                      OR s3.reservation_expires_at <= v_clock)) ) )
        ), spaced AS (
          SELECT k.vehicle_id, k.overall_urgency, k.minutes_to_deploy, k.fits_window,
                 k.open_must_do_min, x.svc, p.lane, p.sequence_order,
                 -- 0003: is THIS pick a resumption of work the depot already took away?
                 COALESCE(x.svc = ANY (COALESCE(k.owed_bay_svcs, '{}'::text[])), false) AS is_resume,
                 -- 0003: EFFECTIVE urgency. A job that was booked, started and then
                 -- interrupted was must-do when it was booked, so it is at least 'due' --
                 -- even if the twin has since reset its cadence clock by crediting a
                 -- 0.46-minute service as finished (run 093c20f4, vehicle 5cee8fb3). Floor
                 -- it at 'due' (rank 3) and no higher: fresh 'overdue'/'critical' work still
                 -- wins outright, so this can never starve a genuinely urgent new arrival.
                 -- overall_urgency itself is NOT touched -- too many readers depend on it.
                 GREATEST(public.ottoq_urgency_rank(k.overall_urgency),
                          CASE WHEN x.svc = ANY (COALESCE(k.owed_bay_svcs, '{}'::text[]))
                               THEN public.ottoq_urgency_rank('due') ELSE 0 END) AS eff_rank,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash_bay'
                             WHEN 'detail'      THEN 'wash_bay'
                             WHEN 'service_bay' THEN 'service_bay' END AS stall_type,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash'
                             WHEN 'detail'      THEN 'detail'
                             WHEN 'service_bay' THEN 'service' END AS purpose,
                 CASE p.lane WHEN 'wash_bay'    THEN 'in_wash_bay'
                             WHEN 'detail'      THEN 'in_detail_bay'
                             WHEN 'service_bay' THEN 'in_service_bay' END AS new_state,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash_time'
                             WHEN 'detail'      THEN 'detail_time'
                             WHEN 'service_bay' THEN 'maintenance_time' END AS time_key,
                 CASE p.lane WHEN 'wash_bay'    THEN 9
                             WHEN 'detail'      THEN 25
                             ELSE 40 END AS base_min
            FROM card k
            -- 0543 (CLAUDE.md rule 9): the card's must-do list and every wash or detail service still open on the car's
            -- visit. Every service OTTO-Q finds a car to need is required, and a staged car has no other door to those
            -- bays: the service flow's wash lane takes only cars coming off a charger.
            CROSS JOIN LATERAL (SELECT DISTINCT u.svc
                                  FROM unnest(COALESCE(k.must_do_now, '{}'::text[])
                                              || ARRAY(SELECT a->>'svc'
                                                         FROM ottoq_visit_needs vn
                                                         CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
                                                         JOIN public.service_cadence_policy cp
                                                           ON cp.svc = a->>'svc' AND cp.is_active
                                                          AND cp.lane IN ('wash_bay','detail')
                                                        WHERE vn.vehicle_id = k.vehicle_id AND vn.sim_run_id = p_sim_run_id
                                                          AND vn.status IN ('open','in_progress')
                                                          AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))) AS u(svc)) AS x(svc)
            JOIN public.service_cadence_policy p ON p.svc = x.svc AND p.is_active
           WHERE p.lane IN ('wash_bay','detail','service_bay')
        ), pick AS (
          -- SEQUENCE inside the visit: the catalogue's own order -- except that 0003 puts
          -- UNFINISHED work first. If a vehicle both owes an interrupted job and has fresh
          -- cadence work due, finish what the depot already started. That is the atomic
          -- full-service visit read literally.
          SELECT DISTINCT ON (s.vehicle_id) s.*
            FROM spaced s
           ORDER BY s.vehicle_id, s.is_resume DESC, s.sequence_order, s.svc
        ), ranked AS (
          SELECT pk.vehicle_id, pk.svc, pk.lane, pk.stall_type, pk.purpose, pk.new_state,
                 pk.time_key, pk.base_min, pk.overall_urgency, pk.minutes_to_deploy,
                 pk.fits_window, pk.open_must_do_min, pk.sequence_order, pk.is_resume,
                 pk.eff_rank, v.fleet_operator_id
            FROM pick pk
            JOIN vehicles v ON v.id = pk.vehicle_id
           WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
             AND v.current_state = 'staged_awaiting_service'
             AND COALESCE(public.ottoq_approach_zone(pk.vehicle_id, p_sim_run_id),'B') <> 'C'
        )
        SELECT rk.*,
               -- 0003: how many FRESH candidates are competing for this same lane this tick.
               -- Window functions are evaluated over the whole qualifying set BEFORE the
               -- LIMIT, so this is the true competing demand, not just what fits in 20 rows.
               -- The resumption budget below only bites when this is > 0.
               count(*) FILTER (WHERE NOT rk.is_resume) OVER (PARTITION BY rk.stall_type)
                 AS fresh_waiting_lane
               -- 0169: rank over the WHOLE qualifying set so the loop can see the
               -- candidates the tick budget excludes, instead of dropping them
               -- before they are ever named. Same ordering as the LIMIT it replaces.
               , row_number() OVER (ORDER BY rk.eff_rank DESC,
                                             rk.is_resume DESC,
                                             rk.minutes_to_deploy ASC NULLS LAST,
                                             rk.open_must_do_min ASC NULLS LAST,
                                             rk.vehicle_id) AS seat_rank
               , count(*) OVER () AS seat_qualified
          FROM ranked rk
         ORDER BY rk.eff_rank DESC,
                  rk.is_resume DESC,
                  rk.minutes_to_deploy ASC NULLS LAST,
                  rk.open_must_do_min ASC NULLS LAST,
                  rk.vehicle_id
      LOOP
        -- 0169: the tick budget, recorded rather than silent. A vehicle past the
        -- budget was never considered; noop_no_candidate would be a lie about it.
        IF v_need.seat_rank > public.ottoq_policy_get(p_sim_run_id, 'decide_seat_batch', 20) THEN
          INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
          VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','vehicle',v_need.vehicle_id,
                  jsonb_build_object('seat_rank',v_need.seat_rank,'seat_qualified',v_need.seat_qualified,
                                     'seat_batch',public.ottoq_policy_get(p_sim_run_id,'decide_seat_batch',20),
                                     'stall_type',v_need.stall_type,'lane',v_need.lane),
                  '{}'::jsonb,'{}'::jsonb,'deferred_tick_budget',0,0);
          CONTINUE;
        END IF;
        IF v_need.stall_type = 'wash_bay'    AND COALESCE(v_wash_open,0) <= 0 THEN CONTINUE; END IF;
        IF v_need.stall_type = 'service_bay' AND COALESCE(v_svc_open,0)  <= 0 THEN CONTINUE; END IF;
        -- 0003 ANTI-STARVATION: hold resumption to its per-lane share of THIS tick's
        -- admissions, and only while fresh work is actually queued for the same lane.
        -- Skipping here is a pure CONTINUE: the vehicle keeps its place in the next tick's
        -- cursor with its 'due' floor intact, so nothing is dropped, only sequenced.
        IF COALESCE(v_need.is_resume,false) AND COALESCE(v_need.fresh_waiting_lane,0) > 0 THEN
          IF v_need.stall_type = 'wash_bay'    AND v_wash_res_used >= COALESCE(v_wash_res_cap,1) THEN CONTINUE; END IF;
          IF v_need.stall_type = 'service_bay' AND v_svc_res_used  >= COALESCE(v_svc_res_cap,1)  THEN CONTINUE; END IF;
        END IF;

        v_built := v_built + 1; v_t0 := clock_timestamp();
        v_over := false; v_safe := false; v_block_codes := '{}'; v_rule_rows := NULL;
        v_ctx := ottoq_build_decision_context('task_start','vehicle',v_need.vehicle_id,v_depot,v_clock)
                 || jsonb_build_object('need', v_need.svc, 'lane', v_need.lane,
                      'stall_type', v_need.stall_type, 'purpose', v_need.purpose,
                      'overall_urgency', v_need.overall_urgency,
                      'minutes_to_deploy', v_need.minutes_to_deploy,
                      'fits_window', v_need.fits_window,
                      'open_must_do_min', v_need.open_must_do_min,
                      'sequence_order', v_need.sequence_order,
                      -- 0003: make bay RECOVERY countable straight off the decision row.
                      'is_resume', COALESCE(v_need.is_resume,false),
                      'eff_urgency_rank', v_need.eff_rank,
                      'fresh_waiting_lane', v_need.fresh_waiting_lane,
                      'resume_cap_lane', CASE WHEN v_need.stall_type = 'wash_bay'
                                              THEN v_wash_res_cap ELSE v_svc_res_cap END,
                      'requires_charging','false','service', v_need.purpose);
        v_proposal := jsonb_build_object('abstain', false, 'verb','assign_stall',
                        'resolved_action_context','stall_assignment', 'source','needs_card',
                        'vehicle_id', v_need.vehicle_id, 'stall_type', v_need.stall_type,
                        'purpose', v_need.purpose, 'need', v_need.svc, 'requested_kw', 0,
                        -- 0003: recorded on the PROPOSAL, not on the booking. p_source of
                        -- ottoq.ottoq_enact_space_assignment is deliberately left at the
                        -- existing literal 'needs_card' -- inventing a new vocabulary value
                        -- for a downstream writer is exactly the 2026-08-01 leg_type trap.
                        'is_resume', COALESCE(v_need.is_resume,false));
        v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

        v_t0 := clock_timestamp();
        SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
               jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
          INTO v_blocks, v_block_codes, v_rule_rows
          FROM ottoq_shield_probe('task_start','vehicle',v_need.vehicle_id,v_ctx,v_need.fleet_operator_id,v_depot);
        v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

        v_t0 := clock_timestamp();
        IF COALESCE(v_blocks,0) > 0 THEN
          -- SHIELD BLOCKS => take NO space. The vehicle stays in staging and section (5)
          -- handles it exactly as today. Bays are ADDITIVE, so a refusal here can only ever
          -- return the engine to its pre-P1 behaviour - never worse.
          v_action := jsonb_build_object('verb','hold_no_space','reason','shield_block');
          v_safe := true; v_over := true; v_outcome := 'overridden_to_default'; v_overc := v_overc + 1;
        ELSE
          -- TIMING BELONGS TO THE TWIN. ottoq_sim_service_minutes is the exact function
          -- twin STEP 2 uses for its own admissions, so routing a car here cannot invent a
          -- new dwell regime. The planner's timed leg is preferred whenever one exists.
          -- 0549 (G278): the leg's length from now, not its planned end. A car seated now is
          -- served now; asking for the bay until a leg planned hours later held the bay until then.
          SELECT l.leg_id, v_clock + (l.planned_end_sim - l.planned_start_sim) INTO v_bay_leg_id, v_bay_until
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_need.vehicle_id
             AND l.status = 'planned' AND l.to_stall_id IS NULL
             AND l.leg_type = public.ottoq_svc_to_leg_type(v_need.svc)
             AND l.planned_end_sim IS NOT NULL AND l.planned_end_sim > v_clock
           ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;
          v_bay_until := GREATEST(
            COALESCE(v_bay_until,
                     v_clock + make_interval(mins => GREATEST(
                       ottoq_sim_service_minutes(p_sim_run_id, v_need.time_key, v_need.base_min)::int, 1))),
            v_clock + interval '1 minute');

          v_space := ottoq.ottoq_enact_space_assignment(
                       p_sim_run_id, v_depot, v_need.vehicle_id, v_need.stall_type,
                       v_need.purpose, v_clock, v_bay_until, v_bay_leg_id, 'needs_card');
          -- 0553 (G283): a bay held for a car that cannot be here before this one would finish gives way to it.
          -- ottoq_yield_bay_holds moves those holds to their car's ETA; then the assignment is tried once more.
          IF NOT COALESCE((v_space->>'assigned')::boolean, false)
             AND COALESCE(v_space->>'reason', '') = 'no_free_space' THEN
            IF ottoq.ottoq_yield_bay_holds(p_sim_run_id, v_depot, v_need.stall_type, v_clock, v_bay_until,
                                           v_need.vehicle_id) > 0 THEN
              v_space := ottoq.ottoq_enact_space_assignment(
                           p_sim_run_id, v_depot, v_need.vehicle_id, v_need.stall_type,
                           v_need.purpose, v_clock, v_bay_until, v_bay_leg_id, 'needs_card')
                         || jsonb_build_object('yielded_holds', true);
            END IF;
          END IF;

          IF COALESCE((v_space->>'assigned')::boolean, false) THEN
               -- 0039: bay entry handled by twin on command confirmation below
            IF v_need.stall_type = 'wash_bay' THEN
              v_wash_open := v_wash_open - 1;
              IF COALESCE(v_need.is_resume,false) THEN v_wash_res_used := v_wash_res_used + 1; END IF;
            ELSE
              v_svc_open := v_svc_open - 1;
              IF COALESCE(v_need.is_resume,false) THEN v_svc_res_used := v_svc_res_used + 1; END IF;
            END IF;
            v_action := v_proposal || v_space
                        || jsonb_build_object('verb','assign_stall',
                             'stall_id', v_space->>'stall_id',
                             'bay_booked', (v_space->>'booking_id') IS NOT NULL,
                             -- 0003: THE P0 NUMERATOR. A true here is one unit of
                             -- "cut-short bay work re-booked into a space it holds".
                             'resumed_bay_work', COALESCE(v_need.is_resume,false),
                             'resumed_need', CASE WHEN COALESCE(v_need.is_resume,false)
                                                  THEN v_need.svc ELSE NULL END);
            v_outcome := 'enacted'; v_enacted := v_enacted + 1;
            -- 0081: a bay assignment must SEAT the vehicle. proceed_to_stall only moves
            -- current_stall_id and leaves current_state unchanged, so the wash/service never
            -- started, section (5) yanked the still-staged vehicle back out, and the booking
            -- died 'bay_exit_before_planned_end' -- measured 28x in one run. enter_wash /
            -- enter_service carry the state transition (in_wash_bay / in_detail_bay /
            -- in_service_bay) exactly like sections (4) and (5) already emit for their bays.
            PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_need.vehicle_id,
              CASE WHEN v_need.stall_type = 'service_bay' THEN 'enter_service' ELSE 'enter_wash' END,
              jsonb_build_object('stall_id',   v_space->>'stall_id',
                                 'booking_id', v_space->>'booking_id',
                                 'leg_id',     v_bay_leg_id,
                                 'purpose',    v_need.purpose,
                                 'reason',     'needs_card_' || v_need.purpose,
                                 'need',       v_need.svc), v_clock);
          ELSE
            v_action := v_proposal || COALESCE(v_space,'{}'::jsonb)
                        || jsonb_build_object('verb','hold_no_space',
                             'resumed_bay_work', COALESCE(v_need.is_resume,false));
            v_outcome := 'noop_no_candidate'; v_deferred := v_deferred + 1;
          END IF;
        END IF;
        v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
        -- action_context 'task_start' matches the probe context used by (4) and (5) for bay
        -- admissions; resolved_action_context 'stall_assignment' is the HONEST classification
        -- because a space really was claimed AND booked - which is also what makes bays
        -- finally countable in the enacted_stall_by_space_type metric that read 51/51 charging.
        INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
        VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','stall_assignment','vehicle',v_need.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
      END LOOP;
    END IF;
  END IF;

  -- (5) SERVICE SEQUENCING
  -- 0081: SERVICE SEQUENCING must not promote a vehicle that still owes must-do WASH or
  -- DETAIL work. That work belongs to (4b), which routes it to the wash lane. Before this guard,
  -- ottoq_l2_propose_service saw no service_bay atom on a wash-due vehicle, returned
  -- 'promote_ready', and emitted stage(ready:true) in the SAME tick (4b) routed it to the wash
  -- bay -- the vehicle oscillated and the wash never ran. Skip wash/detail-must-do vehicles here;
  -- (4b) seats them, and this loop re-sees them on a later tick once the wash is done.
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.fleet_operator_id, v.config->>'svc_step' AS svc_step
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='staged_awaiting_service'
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                        WHERE n.vehicle_id = v.id AND n.status IN ('open','in_progress') AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
                          AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
                          AND COALESCE(a->>'must_do','false') = 'true'
                          AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('task_start','vehicle',v_req.vehicle_id,v_depot,v_clock) || jsonb_build_object('svc_step', v_req.svc_step, 'requires_charging','false','service','service');
    -- A1: cuOpt/Nemotron may propose the service order; heuristic is the fallback.
    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'service_sequencing', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_service(v_req.vehicle_id, v_depot, v_ctx));
    v_prop_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('task_start','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_service(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      IF v_action->>'verb'='admit_service' THEN
        -- BAY ENTRY MOVED BELOW THE HELPER (Phase 3) -- same defect and same fix as (4).
        -- CALENDAR (service bay). CHOOSE + RECORD ONLY, never gating - same contract as (4).
        SELECT l.leg_id, (l.planned_end_sim - l.planned_start_sim)
          INTO v_bay_leg_id, v_bay_dur
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
           AND l.status = 'planned' AND l.to_stall_id IS NULL
           AND l.leg_type IN ('service','mechanical_pm','fault_repair','sensor_calibration','cosmetic_repair')
         ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;
        IF v_bay_leg_id IS NULL THEN
          -- FALLBACK: adopt the leg the forward planner already booked (see section (4)).
          SELECT l.leg_id, (l.planned_end_sim - l.planned_start_sim)
            INTO v_bay_leg_id, v_bay_dur
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
             AND l.status IN ('planned','active')
             AND l.leg_type IN ('service','mechanical_pm','fault_repair','sensor_calibration','cosmetic_repair')
           ORDER BY (l.status = 'active') DESC, l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;
        END IF;
        -- TOTAL allow-list: all five of those leg types collapse to the single legal
        -- purpose 'service'. The leg_type itself is NEVER passed through.
        v_bay_until := v_clock + GREATEST(
          COALESCE(v_bay_dur,
                   make_interval(mins => ottoq_policy_get(p_sim_run_id,'service_bay_default_min',45)::int)),
          interval '1 minute');
        v_space := ottoq.ottoq_enact_space_assignment(p_sim_run_id, v_depot, v_req.vehicle_id,
                       'service_bay', 'service', v_clock, v_bay_until,
                       v_bay_leg_id, 'service_sequencing');
        v_bay_bkg := NULLIF(v_space->>'booking_id','')::uuid;
        IF v_bay_bkg IS NOT NULL AND v_bay_leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs
             SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                                 WHERE b.booking_id = v_bay_bkg)
           WHERE leg_id = v_bay_leg_id;
        END IF;
        IF COALESCE((v_space->>'assigned')::boolean, false) THEN
      -- 0039: vehicle state update handled by twin on 'enter_service' command confirmation
          PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'enter_service',
                  jsonb_build_object('stall_id',   v_space->>'stall_id',
                                     'booking_id', v_space->>'booking_id',
                                     'leg_id',     v_bay_leg_id,
                                     'purpose',    'service'), v_clock);
          v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                      || jsonb_build_object('bay_booked', v_bay_bkg IS NOT NULL,
                                            'bay_purpose', 'service',
                                            'bay_stall_type', 'service_bay',
                                            'stall_id', v_space->>'stall_id',
                                            'booking_id', v_space->>'booking_id',
                                            'leg_id', v_bay_leg_id);
        ELSE
          -- NO BAY -> DO NOT ENTER ONE. Identical in effect to this proposer's own
          -- 'hold_in_queue': the vehicle stays in staged_awaiting_service and is retried.
          v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                      || jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
                                            'bay_purpose', 'service',
                                            'bay_stall_type', 'service_bay');
          v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; v_deferred := v_deferred + 1;
        END IF;
      ELSIF v_action->>'verb' = 'hold_in_queue' THEN
        -- SERVICE-NEED HOLD: must-do bay work outstanding and no free bay (or the
        -- shield blocked). Leave the vehicle in staged_awaiting_service - no state
        -- write at all - so the service queue keeps it instead of redeploying a
        -- vehicle with mandatory work open. The proposer bounds this with a
        -- patience threshold, so a hold can never strand a vehicle.
        NULL;
      ELSE
      -- 0469 (G200): no command. This emitted stage {ready: true} every tick for every ready car (7,686 on
        -- 317d4331) and the door maps stage to no transition; the release happens in the service flow's
        -- readiness gate, which reads the car's step. The decision row below still records the verdict.
        NULL;
      END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- A3: close the external-proposal lifecycle for this tick — consumed
  -- (entity got an enacted decision) → 'enacted'; past-freshness → 'expired'.
  UPDATE ottoq_external_proposals p
     SET status='enacted', disposition_reason='enacted_by_kernel',
         disposed_at=clock_timestamp(), disposed_tick=v_tick
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted'
                    AND d.enacted_action->>'source' = p.source);
  -- honest pre-emption: the entity was decided this tick, but NOT by this proposal
  UPDATE ottoq_external_proposals p
     SET status='superseded', disposition_reason='entity_decided_by_other_proposal',
         disposed_at=clock_timestamp(), disposed_tick=v_tick
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted');
  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, v_tick, v_clock, false);

  -- ══════════════════ BUILD 3: THE INSPECT SEAM (ADDITIVE) ══════════════════
  -- 177 inspect legs ended the prior run still 'planned' across 110 arriving vehicles
  -- while 14 inspection stalls per depot sat idle, because (1) the needs card never
  -- emits 'interior_inspection', (2) this tick's bay loop filters to lanes
  -- wash_bay/detail/service_bay and inspection is lane 'cabin', and (3) inspection
  -- stalls are stall_type='staging' so no caller could address them.
  -- Placed HERE, last, on purpose: charging (3), the bay loop and service sequencing
  -- (5) have all already run, so the seam can only take vehicles nothing else claimed.
  -- It never raises (see the handler inside) -- the 2026-08-01 leg_type lesson.
  v_enacted := v_enacted + COALESCE(
    ottoq.ottoq_enact_inspection_seam(p_sim_run_id, v_depot, v_tick, v_snapshot_id, v_clock), 0);

  PERFORM ottoq.ottoq_link_bookings_to_decisions(p_sim_run_id, v_tick);

  RETURN ROW(v_tick, v_clock, v_built, v_enacted, v_overc, v_deferred, v_errored, v_disn,
             (SELECT COALESCE(SUM(total_latency_ms),0) FROM ottoq_decisions WHERE sim_run_id=p_sim_run_id AND tick_seq=v_tick))::ottoq_decide_tick_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_stall_assignment(p_vehicle_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc   numeric := COALESCE((p_context->>'current_soc')::numeric, 50);
  v_now   timestamptz := COALESCE(NULLIF(p_context->>'now_ts','')::timestamptz, now());
  v_inlet text; v_inlet_kw numeric; v_want_type text; v_urgency text;
  v_stall RECORD; v_eff_kw numeric; v_headroom_kw numeric;
  v_run uuid; v_mode int; v_prefer_fit boolean;
  v_due timestamptz; v_target_soc numeric; v_batt_kwh numeric;
  v_fit_kw numeric; v_hours_needed numeric; v_hours_available numeric;
  v_want_kw numeric; v_ceiling numeric; v_wait_reason text := NULL; v_seat int; /* 0261 */
  v_veh_target numeric;   /* 0446 */
  v_kind_match int; v_n_dcfc int; v_n_want int;   /* 0548 (G277) */
BEGIN
  SELECT r0.sim_run_id INTO v_run FROM public.ottoq_sim_runs r0
   WHERE r0.status='running' AND r0.depot_id=p_depot_id ORDER BY r0.started_at DESC LIMIT 1;
  /* 0261: a non-zero proposer seat owns the in-tick fallback too, so a baseline arm
     is the baseline all the way down. Seat 0 is the text below, untouched. */
  v_seat := COALESCE(public.ottoq_policy_get(v_run, 'proposer_seat', 0), 0)::int;
  IF v_seat <> 0 THEN
    RETURN public.ottoq_l2_propose_stall_seat(p_vehicle_id, p_depot_id, p_context, v_seat);
  END IF;

  /* 0159: the visit need is where the asset states its deadline and target. */
  SELECT vn.urgency, vn.dispatch_due_at, vn.target_soc INTO v_urgency, v_due, v_target_soc
    FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
     AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(v_run,'00000000-0000-0000-0000-000000000000'::uuid)   /* 0124 */
   ORDER BY vn.created_at DESC LIMIT 1;
  v_want_type := CASE WHEN v_soc < 45 OR v_urgency = 'immediate_dispatch' THEN 'dcfc' ELSE 'l2' END;

  SELECT inlet_type, inlet_max_kw, battery_capacity_kwh, target_soc INTO v_inlet, v_inlet_kw, v_batt_kwh, v_veh_target
    FROM vehicles WHERE id = p_vehicle_id;

  /* 0156: headroom by EN.001's own arithmetic; v_ceiling is the absolute cap. */
  SELECT LEAST(d.service_max_kw, d.dcfc_max_concurrent_kw * (1 - COALESCE(d.dcfc_safety_margin_pct,10.0)/100.0)),
         LEAST(d.service_max_kw, d.dcfc_max_concurrent_kw * (1 - COALESCE(d.dcfc_safety_margin_pct,10.0)/100.0))
         - COALESCE(public.ottoq_depot_current_demand_kw(p_depot_id, v_now), 0)
    INTO v_ceiling, v_headroom_kw
    FROM depots d WHERE d.id = p_depot_id;
  v_headroom_kw := COALESCE(NULLIF(p_context->>'headroom_kw','')::numeric, v_headroom_kw);

  v_mode := public.ottoq_policy_get(v_run, 'charge_downgrade_policy', 1)::int;
  IF v_mode = 0 THEN
    v_prefer_fit := false; v_wait_reason := 'policy_wait_for_wanted';
  ELSIF v_mode = 2 THEN
    v_prefer_fit := true;
    SELECT max(LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
               * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                      WHEN v_soc < 55 THEN 0.85 WHEN v_soc < 75 THEN 0.55 ELSE 0.30 END)
      INTO v_fit_kw FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id=s.ocpp_charger_id
     WHERE s.depot_id=p_depot_id AND s.stall_type IN ('dcfc','l2') AND s.current_vehicle_id IS NULL
       AND c.station_state='Available'
       AND (v_headroom_kw IS NULL OR (LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
               * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                      WHEN v_soc < 55 THEN 0.85 WHEN v_soc < 75 THEN 0.55 ELSE 0.30 END) <= v_headroom_kw);
    SELECT max(LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
               * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                      WHEN v_soc < 55 THEN 0.85 WHEN v_soc < 75 THEN 0.55 ELSE 0.30 END)
      INTO v_want_kw FROM stalls s WHERE s.depot_id=p_depot_id AND s.stall_type::text = v_want_type;
    IF v_due IS NOT NULL AND v_fit_kw IS NOT NULL AND v_fit_kw > 0 AND v_batt_kwh IS NOT NULL THEN
      v_hours_needed := (v_batt_kwh * GREATEST(COALESCE(v_target_soc, public.ottoq_default_target_soc()) - v_soc, 0) / 100.0) / v_fit_kw;
      v_hours_available := EXTRACT(epoch FROM (v_due - v_now)) / 3600.0;
      /* Hold ONLY if the slow point misses the deadline AND the fast point is
         physically grantable here - without the guard this reintroduces 0156. */
      IF v_hours_needed > v_hours_available
         AND v_want_kw IS NOT NULL AND (v_ceiling IS NULL OR v_want_kw <= v_ceiling) THEN
        v_prefer_fit := false; v_wait_reason := 'slow_point_misses_due_at';
      END IF;
    END IF;
  ELSE
    v_prefer_fit := true;
  END IF;

  WITH cand AS (
    SELECT s.id, s.stall_type, s.connector_max_kw, s.relative_y, s.reserved_by,
           (LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
            * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                   WHEN v_soc < 55 THEN 0.85 WHEN v_soc < 75 THEN 0.55 ELSE 0.30 END) AS eff_kw
      FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type IN ('dcfc','l2') AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= v_now)
       AND c.station_state = 'Available' AND c.last_heartbeat_at >= v_now - INTERVAL '90 seconds'
       /* 0446 (G179): the session stops at LEAST(target, this stall type's cap now) - 0.5, so a stall that
          would stop the session before it starts is not a candidate. Without this, a vehicle at the DCFC
          daytime cap kept its DCFC reservation and looped on it, delivering nothing. */
       AND v_soc < LEAST(COALESCE(v_veh_target, public.ottoq_default_target_soc()),
                         public.ottoq_target_soc_cap(s.stall_type::text, v_now)) - 0.5
       /* 0494 (G226): the calendar is a gate too. The pick asked only the pointer, so a charger promised to an
          arriving car looked free, and each car in the charge step's cursor was offered it and refused at the
          emission gate in turn (22 in one tick on busy_day/171717/12 under 0493). A candidate is now a charger the
          gate accepts for this car at this moment, the call ottoq_emit_vehicle_command makes next (0467 did the
          same for the gate intake). */
       AND COALESCE((ottoq.ottoq_validate_assignment(p_vehicle_id, s.id, 'begin_charge', v_now, v_run)->>'ok')::boolean, false)
       AND (v_inlet IS NULL OR s.connector_type = v_inlet
         OR (s.connector_type = 'Multi' AND v_inlet = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
         OR (s.connector_type = 'NACS'  AND v_inlet IN ('NACS','Tesla_Proprietary'))))
  SELECT id, stall_type, connector_max_kw, eff_kw,
         (v_headroom_kw IS NULL OR eff_kw <= v_headroom_kw) AS fits
    INTO v_stall FROM cand
   /* v_prefer_fit false makes the first key constant, collapsing the ordering
      to the pre-0156 one exactly. */
   ORDER BY (v_prefer_fit AND (v_headroom_kw IS NULL OR eff_kw <= v_headroom_kw)) DESC,
            COALESCE(reserved_by = p_vehicle_id, false) DESC,
            (stall_type::text = v_want_type) DESC, relative_y ASC NULLS LAST, id
   LIMIT 1;

  IF v_stall.id IS NULL THEN RETURN jsonb_build_object('abstain', true, 'reason', 'no_compatible_available_stall'); END IF;

  /* 0548 (G277, research wing): at charge_kind_match = 1 a car that wants an L2 does not take a free fast charger
     while the cars waiting that want one are at least as many as the free fast chargers. It waits for an L2 (an
     abstention, as when no charger is free), and the fast charger goes to a car that wants it later in this tick.
     A spare fast charger is still taken, so no charger idles for the rule. At 0 (the default) nothing below changes. */
  v_kind_match := COALESCE(public.ottoq_policy_get(v_run, 'charge_kind_match', 0), 0)::int;
  IF v_kind_match = 1 AND v_want_type = 'l2' AND v_stall.stall_type::text = 'dcfc'
     AND (SELECT s0.reserved_by FROM stalls s0 WHERE s0.id = v_stall.id) IS DISTINCT FROM p_vehicle_id THEN
    SELECT count(*) INTO v_n_dcfc
      FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type::text = 'dcfc' AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= v_now)
       AND c.station_state = 'Available' AND c.last_heartbeat_at >= v_now - INTERVAL '90 seconds';
    SELECT count(*) INTO v_n_want
      FROM vehicles w
     WHERE w.home_depot_id = p_depot_id AND w.category = 'autonomous' AND w.id <> p_vehicle_id
       AND w.current_state IN ('arrived_at_gate', 'staged_awaiting_service')
       AND w.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = w.id AND vn.status IN ('open','in_progress')
                AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                  = COALESCE(v_run,'00000000-0000-0000-0000-000000000000'::uuid)
              ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) - 1
       AND (w.current_soc < 45
            OR COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                  WHERE vn.vehicle_id = w.id AND vn.status IN ('open','in_progress')
                    AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                      = COALESCE(v_run,'00000000-0000-0000-0000-000000000000'::uuid)
                  ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false));
    IF v_n_want > 0 AND v_n_want >= v_n_dcfc THEN
      RETURN jsonb_build_object('abstain', true, 'reason', 'fast_charger_kept_for_a_car_that_wants_one',
        'rationale', jsonb_build_object('soc', v_soc, 'wanted_type', v_want_type, 'urgency', v_urgency,
                                        'kept_stall_id', v_stall.id, 'free_fast_chargers', v_n_dcfc,
                                        'cars_wanting_one', v_n_want, 'charge_kind_match', v_kind_match));
    END IF;
  END IF;
  v_eff_kw := v_stall.eff_kw;
  RETURN jsonb_build_object('abstain', false, 'resolved_action_context', 'stall_assignment', 'verb', 'assign_stall',
    'vehicle_id', p_vehicle_id, 'stall_id', v_stall.id, 'stall_type', v_stall.stall_type,
    'requested_kw', ROUND(v_eff_kw::numeric, 1),
    'rationale', jsonb_build_object('soc', v_soc, 'wanted_type', v_want_type, 'inlet', v_inlet,
      'urgency', v_urgency, 'eff_draw_kw', ROUND(v_eff_kw::numeric, 1),
      'headroom_kw', ROUND(v_headroom_kw::numeric, 1), 'fits_headroom', v_stall.fits,
      'downgrade_policy', v_mode, 'held_for_wanted', COALESCE(v_wait_reason,'-'),
      'power_downgrade', (v_stall.stall_type::text <> v_want_type AND v_stall.fits AND v_prefer_fit)));
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_depot_queue(p_depot_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(queue_kind text, queue_position integer, queue_depth integer, vehicle_id uuid, vehicle_ref text, current_soc numeric, target_soc numeric, is_immediate boolean, waiting_since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'ottoq', 'extensions'
AS $function$
  WITH z AS (
    SELECT COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) AS run,
           -- 0551 (G284): the run's own clock, as the decide tick reads it. now() is the wall clock, hours from a sim
           -- run's, and read every reservation as expired.
           COALESCE((SELECT r.sim_clock_current FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id), now()) AS clock,
           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int AS seat),
  -- sect.3 STALL ASSIGNMENT -- mirrored: ottoq_decide_tick's charge cursor, its filter and its keys (0493, 0545 (c),
  -- 0546 (c), 0551). Not mirrored: the one-tick cuOpt deferral and the charging-staff LIMIT, which hold a car back from
  -- this tick without moving its place.
  charge AS (
    SELECT v.id, v.display_name, v.current_soc, v.last_state_change,
           public.ottoq_charge_wait_since(v.config, v.last_state_change, p_sim_run_id) AS waiting_since,
           COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                          = (SELECT run FROM z)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1),
                    public.ottoq_default_target_soc()) AS target_soc,
           -- 0546 (c): a car with no open visit is not an immediate dispatch.
           COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                          = (SELECT run FROM z)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) AS is_immediate,
           -- 0545 (c) on 0551's clock: (minutes waited + points to charge) / points to charge.
           (public.ottoq_charge_wait_min(v.config, v.last_state_change, (SELECT clock FROM z), p_sim_run_id)
            + GREATEST(public.ottoq_effective_target_soc_at(v.id, (SELECT clock FROM z)) - v.current_soc, 1))
           / GREATEST(public.ottoq_effective_target_soc_at(v.id, (SELECT clock FROM z)) - v.current_soc, 1) AS ratio
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.category = 'autonomous'
       AND NOT public.ottoq_vehicle_fault_open(v.config)   -- 0557 (G291): as the cursor
       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
                 SELECT 1 FROM stalls s2
                   JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                  WHERE s2.depot_id = p_depot_id
                    AND s2.stall_type::text IN ('dcfc','l2')
                    AND s2.current_vehicle_id IS NULL
                    AND c2.station_state = 'Available'
                    AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                         OR s2.reservation_expires_at <= (SELECT clock FROM z)))))
  ),
  charge_q AS (
    SELECT 'charge'::text AS qk,
           (row_number() OVER (ORDER BY c.is_immediate DESC,
                                        CASE WHEN (SELECT seat FROM z) = 1 THEN c.last_state_change END ASC NULLS FIRST,
                                        CASE WHEN (SELECT seat FROM z) = 2 THEN c.current_soc END ASC,
                                        CASE WHEN (SELECT seat FROM z) = 0 THEN c.ratio END DESC NULLS LAST,
                                        c.current_soc ASC, c.id))::int AS pos,
           (count(*)    OVER ())::int AS depth,
           c.id, c.display_name, c.current_soc, c.target_soc, c.is_immediate, c.waiting_since
      FROM charge c
     WHERE c.current_soc < c.target_soc - 1   -- 0493: the engine's charge rule
  ),
  -- sect.3b GATE INTAKE -- mirrored.
  gate_q AS (
    SELECT 'gate_intake'::text AS qk,
           (row_number() OVER (ORDER BY v.last_state_change ASC NULLS FIRST, v.id))::int AS pos,
           (count(*)    OVER ())::int AS depth,
           v.id, v.display_name, v.current_soc,
           NULL::numeric AS target_soc, NULL::boolean AS is_immediate, v.last_state_change
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                        = (SELECT run FROM z)
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge'
                                         AND COALESCE(a->>'status','pending') <> 'done'))
  )
  -- every reference qualified with u.: the RETURNS TABLE columns are OUT
  -- parameters and an unqualified current_soc would be ambiguous against them.
  SELECT u.qk, u.pos, u.depth, u.id, u.display_name, u.current_soc,
         u.target_soc, u.is_immediate, u.waiting_since
    FROM (SELECT * FROM charge_q UNION ALL SELECT * FROM gate_q) u
   ORDER BY u.qk, u.pos;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_run_learning(p_sim_run_id uuid, p_lookback_ticks integer DEFAULT 20, p_detail boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_zero    constant uuid := '00000000-0000-0000-0000-000000000000';
  v_depot   uuid; v_clock timestamptz; v_tick bigint; v_status text; v_seat int;
  v_look    int := LEAST(GREATEST(COALESCE(p_lookback_ticks, 20), 1), 500);
  v_chg     jsonb; v_down jsonb; v_free int := 0;
  v_head    jsonb; v_waiting int := 0; v_need int := 0; v_batch int; v_priority jsonb;
  v_recent  jsonb; v_run jsonb; v_plan jsonb; v_run_plan jsonb; v_live boolean;
  v_refusals jsonb; v_dispatched jsonb;
  v_off int; v_used int; v_moved int; v_lost int;
  v_code text; v_text text;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'run_required'); END IF;
  SELECT r.depot_id, r.sim_clock_current, r.tick_count, r.status
    INTO v_depot, v_clock, v_tick, v_status
    FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'run_not_found'); END IF;
  v_clock := COALESCE(v_clock, now());
  v_tick  := COALESCE(v_tick, 0);
  v_seat  := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int;
  -- Stalls, chargers and cars are one depot's rows shared by every run, so the chargers and the queue below are the
  -- depot NOW. That is the run's own state only while it is running; `live` says which.
  v_live  := (v_status = 'running');

  -- ── chargers: the frame's `offerable` (0265/0498), counted by type, and the ones that are down ──
  WITH s AS (
    SELECT st.id, st.stall_type::text AS kind, COALESCE(st.display_name, st.stall_code) AS name,
           (st.current_vehicle_id IS NOT NULL) AS in_use,
           (st.current_vehicle_id IS NULL AND st.reserved_by IS NOT NULL
            AND COALESCE(st.reservation_expires_at, 'infinity'::timestamptz) > v_clock) AS reserved,
           COALESCE(c.station_state = 'Faulted', false) AS faulted,
           (c.station_state = 'Available' AND c.last_heartbeat_at >= v_clock - interval '90 seconds') AS charger_ok,
           c.last_fault_code, c.station_state_changed_at, c.last_fault_payload ->> 'repair_minutes' AS repair_min,
           cal.vehicle_id AS cal_holder
      FROM stalls st
      LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = st.ocpp_charger_id
      LEFT JOIN LATERAL (
        SELECT b.vehicle_id FROM ottoq_stall_bookings b
         WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = st.id
           AND b.state IN ('held','active','done','interrupted') AND b.during @> v_clock
         ORDER BY lower(b.during), b.vehicle_id, b.booking_id LIMIT 1) cal ON true
     WHERE st.depot_id = v_depot AND st.stall_type::text IN ('dcfc','l2')
  ), f AS (
    SELECT s.*, (NOT s.in_use AND NOT s.reserved AND COALESCE(s.charger_ok, false) AND s.cal_holder IS NULL) AS free
      FROM s
  )
  SELECT (SELECT jsonb_object_agg(q.kind, jsonb_build_object(
                   'total', q.n, 'free', q.nf, 'in_use', q.nu, 'reserved', q.nr,
                   'held_by_calendar', q.ncal, 'faulted', q.nflt, 'not_heartbeating', q.nhb))
            FROM (SELECT kind, count(*) n, count(*) FILTER (WHERE free) nf, count(*) FILTER (WHERE in_use) nu,
                         count(*) FILTER (WHERE reserved) nr,
                         count(*) FILTER (WHERE NOT in_use AND NOT reserved AND NOT faulted
                                            AND COALESCE(charger_ok, false) AND cal_holder IS NOT NULL) ncal,
                         count(*) FILTER (WHERE faulted) nflt,
                         count(*) FILTER (WHERE NOT faulted AND NOT COALESCE(charger_ok, false)) nhb
                    FROM f GROUP BY kind) q),
         (SELECT count(*) FROM f WHERE free),
         (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'stall_id', f.id, 'name', f.name, 'kind', f.kind, 'fault_code', f.last_fault_code,
                   'back_at', CASE WHEN f.repair_min ~ '^[0-9]+(\.[0-9]+)?$'
                                   THEN f.station_state_changed_at + (f.repair_min || ' minutes')::interval END)
                   ORDER BY f.name, f.id), '[]'::jsonb)
            FROM f WHERE f.faulted)
    INTO v_chg, v_free, v_down;

  -- ── the kernel's charge queue, in the order ottoq_decide_tick seats it (P1 pins the fragments mirrored) ──
  WITH q AS (
    SELECT v.id, COALESCE(v.display_name, v.id::text) AS name, v.current_state::text AS state,
           v.current_soc, v.last_state_change,
           COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) AS visit_target,
           COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) AS immediate,
           public.ottoq_charge_wait_min(v.config, v.last_state_change, v_clock, p_sim_run_id) AS wait_min,
           GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1) AS gap,
           EXISTS (SELECT 1 FROM stalls s2
                    WHERE s2.reserved_by = v.id AND s2.reservation_expires_at > v_clock
                      AND s2.stall_type::text IN ('dcfc','l2')) AS holds_charger
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND NOT public.ottoq_vehicle_fault_open(v.config)
       AND v.current_state::text IN ('arrived_at_gate','staged_awaiting_service')
  ), o AS (
    SELECT q.*, row_number() OVER (
             ORDER BY q.immediate DESC,
                      CASE WHEN v_seat = 1 THEN q.last_state_change END ASC NULLS FIRST,
                      CASE WHEN v_seat = 2 THEN q.current_soc END ASC,
                      CASE WHEN v_seat = 0 THEN (q.wait_min + q.gap) / q.gap END DESC NULLS LAST,
                      q.current_soc ASC, q.id) AS pos
      FROM q WHERE q.current_soc < q.visit_target - 1
  )
  SELECT count(*), count(*) FILTER (WHERE NOT o.holds_charger),
         COALESCE(jsonb_agg(jsonb_build_object(
           'pos', o.pos, 'vehicle_id', o.id, 'name', o.name, 'state', o.state,
           'soc', round(o.current_soc::numeric, 1), 'target_soc', o.visit_target,
           'wait_min', round(o.wait_min::numeric, 1), 'immediate', o.immediate, 'holds_charger', o.holds_charger)
           ORDER BY o.pos) FILTER (WHERE o.pos <= 24), '[]'::jsonb),
         COALESCE(jsonb_agg(to_jsonb(o.id) ORDER BY o.pos) FILTER (WHERE NOT o.holds_charger), '[]'::jsonb)
    INTO v_waiting, v_need, v_head, v_priority
    FROM o;

  -- The batch: plan as many cars as there are free chargers, at least one (a plan for the head of the line is still
  -- worth having when a charger frees mid-pass) and at most the 8 a 30-second tick can solve (proposer/README.md).
  v_batch := GREATEST(1, LEAST(8, LEAST(v_need, v_free)));
  v_priority := COALESCE((SELECT jsonb_agg(e.value ORDER BY e.ord)
                            FROM jsonb_array_elements(v_priority) WITH ORDINALITY e(value, ord)
                           WHERE e.ord <= 24), '[]'::jsonb);

  -- ── each source's offers, in the last v_look ticks and over the run ──
  WITH p AS (
    SELECT x.source, x.status, x.disposition_reason, x.tick_seq,
           COALESCE(x.proposal ->> 'abstain', '') IN ('true','t','1') AS abstain,
           (COALESCE(x.proposal ->> 'promotion_count', '') ~ '^[1-9][0-9]*$') AS moved,
           x.source IN (SELECT pp.source FROM ottoq_proposer_precedence pp WHERE pp.holds_tick) AS planner
      FROM ottoq_external_proposals x
     WHERE x.sim_run_id = p_sim_run_id AND x.action_context = 'stall_assignment'
  ), agg AS (
    SELECT p.source, (p.tick_seq >= v_tick - v_look) AS recent,
           count(*) FILTER (WHERE NOT p.abstain) AS offered,
           count(*) FILTER (WHERE NOT p.abstain AND p.status = 'enacted') AS used,
           count(*) FILTER (WHERE NOT p.abstain AND p.moved) AS moved,
           count(*) FILTER (WHERE NOT p.abstain AND p.moved AND p.status = 'enacted') AS moved_used,
           count(*) FILTER (WHERE NOT p.abstain AND p.status = 'superseded') AS superseded,
           count(*) FILTER (WHERE NOT p.abstain AND p.status = 'expired') AS expired,
           count(*) FILTER (WHERE NOT p.abstain AND p.status = 'pending') AS pending,
           count(*) FILTER (WHERE p.abstain) AS abstained,
           bool_or(p.planner) AS planner
      FROM p GROUP BY p.source, (p.tick_seq >= v_tick - v_look)
  ), refused AS (
    SELECT x.source, x.recent, jsonb_object_agg(x.reason, x.n) AS by_reason, sum(x.n)::int AS n
      FROM (SELECT p.source, (p.tick_seq >= v_tick - v_look) AS recent,
                   COALESCE(p.disposition_reason, 'unstated') AS reason, count(*)::int AS n
              FROM p WHERE NOT p.abstain AND p.status = 'refused'
             GROUP BY 1, 2, 3) x
     GROUP BY x.source, x.recent
  ), per AS (
    SELECT a.source, a.recent, a.planner,
           jsonb_build_object('planner', a.planner, 'offered', a.offered, 'used', a.used, 'moved', a.moved,
                              'moved_then_used', a.moved_used, 'refused', COALESCE(r.n, 0),
                              'refused_by_reason', COALESCE(r.by_reason, '{}'::jsonb),
                              'superseded', a.superseded, 'expired', a.expired, 'pending', a.pending,
                              'abstained', a.abstained) AS j,
           a.offered, a.used, a.moved, COALESCE(r.n, 0) AS refused
      FROM agg a LEFT JOIN refused r ON r.source = a.source AND r.recent = a.recent
  )
  SELECT
    -- recent window, per source
    (SELECT COALESCE(jsonb_object_agg(per.source, per.j), '{}'::jsonb) FROM per WHERE per.recent),
    -- whole run, per source (recent and older summed)
    (SELECT COALESCE(jsonb_object_agg(t.source, jsonb_build_object(
              'planner', t.planner, 'offered', t.offered, 'used', t.used, 'moved', t.moved, 'refused', t.refused)), '{}'::jsonb)
       FROM (SELECT per.source, bool_or(per.planner) planner, sum(per.offered)::int offered, sum(per.used)::int used,
                    sum(per.moved)::int moved, sum(per.refused)::int refused
               FROM per GROUP BY per.source) t),
    -- recent window, the planners together
    (SELECT jsonb_build_object('offered', COALESCE(sum(per.offered), 0)::int, 'used', COALESCE(sum(per.used), 0)::int,
                               'moved', COALESCE(sum(per.moved), 0)::int, 'refused', COALESCE(sum(per.refused), 0)::int,
                               'refused_by_reason', COALESCE((
                                 SELECT jsonb_object_agg(k, n) FROM (
                                   SELECT e.key k, sum(e.value::int)::int n
                                     FROM per p3, jsonb_each_text(p3.j -> 'refused_by_reason') e
                                    WHERE p3.recent AND p3.planner GROUP BY e.key) z), '{}'::jsonb))
       FROM per WHERE per.recent AND per.planner),
    -- the whole run, the planners together
    (SELECT jsonb_build_object('offered', COALESCE(sum(per.offered), 0)::int, 'used', COALESCE(sum(per.used), 0)::int,
                               'moved', COALESCE(sum(per.moved), 0)::int, 'refused', COALESCE(sum(per.refused), 0)::int)
       FROM per WHERE per.planner)
    INTO v_recent, v_run, v_plan, v_run_plan;

  v_off   := COALESCE((v_plan ->> 'offered')::int, 0);
  v_used  := COALESCE((v_plan ->> 'used')::int, 0);
  v_moved := COALESCE((v_plan ->> 'moved')::int, 0);
  v_lost  := COALESCE((v_plan -> 'refused_by_reason' ->> 'stall_occupied')::int, 0)
           + COALESCE((v_plan -> 'refused_by_reason' ->> 'stall_reserved')::int, 0);

  -- ── the lesson, one line, for the agent and the cockpit ──
  IF NOT v_live THEN
    v_code := 'run_ended';
    v_text := format('This run has ended. Planner offers over the run: %s made, %s used, %s moved to an equal charger, '
                     '%s refused.', v_run_plan ->> 'offered', v_run_plan ->> 'used', v_run_plan ->> 'moved',
                     v_run_plan ->> 'refused');
  ELSIF v_need = 0 THEN
    v_code := 'no_one_waiting';
    v_text := 'No car waits for a charger.';
  ELSIF v_need > v_free THEN
    v_code := 'more_cars_than_chargers';
    v_text := format('%s cars wait for %s free chargers. The planner plans only the next %s in the kernel''s service '
                     'order. An offer refused for stall_occupied or stall_reserved here is a capacity finding, not a '
                     'planner fault: the charger went to a car ahead in line.', v_need, v_free, v_batch);
  ELSIF v_lost > 0 THEN
    v_code := 'offers_lost_their_charger';
    v_text := format('%s of the last %s planner offers lost their charger before use and %s moved to an equal free '
                     'charger. %s free chargers for %s waiting cars.', v_lost, v_off, v_moved, v_free, v_need);
  ELSE
    v_code := 'chargers_free';
    v_text := format('%s free chargers for %s waiting cars. Planner offers in the last %s ticks: %s made, %s used.',
                     v_free, v_need, v_look, v_off, v_used);
  END IF;

  IF NOT COALESCE(p_detail, true) THEN
    RETURN jsonb_build_object(
      'ok', true, 'live', v_live, 'tick', v_tick, 'window_ticks', v_look,
      'chargers', (SELECT jsonb_object_agg(k.key, jsonb_build_object('free', k.value -> 'free', 'total', k.value -> 'total',
                                                                     'faulted', k.value -> 'faulted'))
                     FROM jsonb_each(COALESCE(v_chg, '{}'::jsonb)) k),
      'waiting_for_a_charger', v_need, 'batch_max_assets', v_batch,
      'planner_offers_recent', v_plan,
      'lesson', jsonb_build_object('code', v_code, 'text', v_text));
  END IF;

  -- ── the last refusals, and the car each charger went to ──
  SELECT COALESCE(jsonb_agg(z.j ORDER BY z.k DESC, z.pid), '[]'::jsonb) INTO v_refusals
    FROM (
      SELECT COALESCE(x.disposed_tick, x.tick_seq) AS k, x.proposal_id::text AS pid,
             jsonb_build_object(
               'tick', COALESCE(x.disposed_tick, x.tick_seq), 'source', x.source,
               'vehicle_id', x.entity_id, 'vehicle', COALESCE(vv.display_name, x.entity_id::text),
               'stall_id', st.id, 'stall', COALESCE(st.display_name, st.stall_code), 'kind', st.stall_type::text,
               'reason', COALESCE(x.disposition_reason, 'unstated'),
               'went_to', (SELECT jsonb_build_object('vehicle_id', d.entity_id,
                                                     'vehicle', COALESCE(dv.display_name, d.entity_id::text),
                                                     'tick', d.tick_seq,
                                                     -- the offer's own car already had the charger: a plan for a
                                                     -- car the kernel had just seated
                                                     'same_car', d.entity_id = x.entity_id,
                                                     'path', CASE WHEN d.enacted_action ->> 'source' IN
                                                                        (SELECT pp.source FROM ottoq_proposer_precedence pp WHERE pp.holds_tick)
                                                                  THEN 'planner'
                                                                  WHEN d.enacted_action ->> 'source' = 'greedy_constrained' THEN 'local_optimizer'
                                                                  ELSE 'kernel' END)
                             FROM ottoq_decisions d LEFT JOIN vehicles dv ON dv.id = d.entity_id
                            WHERE d.sim_run_id = p_sim_run_id
                              AND d.tick_seq BETWEEN COALESCE(x.disposed_tick, x.tick_seq) - 60 AND COALESCE(x.disposed_tick, x.tick_seq)
                              AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
                              AND d.enacted_action ->> 'stall_id' = st.id::text
                            ORDER BY d.tick_seq DESC, d.decision_seq DESC LIMIT 1)) AS j
        FROM ottoq_external_proposals x
        LEFT JOIN vehicles vv ON vv.id = x.entity_id
        LEFT JOIN stalls st ON st.id::text = x.proposal ->> 'stall_id'
       WHERE x.sim_run_id = p_sim_run_id AND x.action_context = 'stall_assignment' AND x.status = 'refused'
         AND COALESCE(x.proposal ->> 'abstain', '') NOT IN ('true','t','1')
       ORDER BY COALESCE(x.disposed_tick, x.tick_seq) DESC, x.proposal_id
       LIMIT 6) z;

  -- ── the last assignments that passed every layer ──
  SELECT COALESCE(jsonb_agg(z.j ORDER BY z.t DESC, z.s DESC), '[]'::jsonb) INTO v_dispatched
    FROM (
      SELECT d.tick_seq AS t, d.decision_seq AS s,
             jsonb_build_object(
               'tick', d.tick_seq, 'vehicle_id', d.entity_id, 'vehicle', COALESCE(dv.display_name, d.entity_id::text),
               'stall_id', st.id, 'stall', COALESCE(st.display_name, st.stall_code), 'kind', st.stall_type::text,
               'source', COALESCE(d.enacted_action ->> 'source', 'kernel'),
               'moved_from_offer', COALESCE(d.enacted_action ->> 'promotion_source' = 'adjacent_equivalent', false),
               'path', CASE WHEN d.enacted_action ->> 'source' IN
                                  (SELECT pp.source FROM ottoq_proposer_precedence pp WHERE pp.holds_tick) THEN 'planner'
                            WHEN d.enacted_action ->> 'source' = 'greedy_constrained' THEN 'local_optimizer'
                            ELSE 'kernel' END) AS j
        FROM ottoq_decisions d
        LEFT JOIN vehicles dv ON dv.id = d.entity_id
        LEFT JOIN stalls st ON st.id::text = d.enacted_action ->> 'stall_id'
       WHERE d.sim_run_id = p_sim_run_id AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
       ORDER BY d.tick_seq DESC, d.decision_seq DESC
       LIMIT 6) z;

  RETURN jsonb_build_object(
    'ok', true, 'live', v_live,
    'run', jsonb_build_object('sim_run_id', p_sim_run_id, 'status', v_status, 'tick', v_tick, 'clock', v_clock),
    'window_ticks', v_look,
    'chargers', COALESCE(v_chg, '{}'::jsonb),
    'chargers_free', v_free,
    'chargers_down', v_down,
    'queue', jsonb_build_object('waiting', v_waiting, 'waiting_for_a_charger', v_need,
                                'order', CASE v_seat WHEN 1 THEN 'fifo' WHEN 2 THEN 'greedy' ELSE 'otto_q' END,
                                'head', v_head),
    'batch', jsonb_build_object('max_assets', v_batch, 'priority', v_priority),
    'offers', jsonb_build_object('recent', v_recent, 'run', v_run, 'planners_recent', v_plan, 'planners_run', v_run_plan),
    'refusals', v_refusals,
    'dispatched', v_dispatched,
    'lesson', jsonb_build_object('code', v_code, 'text', v_text),
    'basis', jsonb_build_object(
      'chargers', 'dcfc and l2 stalls at the run''s depot. free = no car on it, no live reservation, OCPP charger Available '
                  'with a heartbeat inside 90 s of the sim clock, and no booking of the run covering the clock: the '
                  'decision frame''s own offerable (0265/0498). Read from the depot now, so they are this run''s only '
                  'while live is true.',
      'queue', 'ottoq_decide_tick''s stall-assignment cursor and order (0545/0551; seat 1 fifo, seat 2 greedy), less the '
               'one-tick first-refusal hold, the free-charger test on a staged car and the charging-staff limit. '
               'waiting_for_a_charger leaves out a car that already holds a live charger reservation.',
      'batch', 'max_assets = free chargers, 1..8; priority = the queue''s first 24 cars without a charger reservation.',
      'offers', 'ottoq_external_proposals for stall_assignment. offered excludes abstentions; moved = promoted at least '
                'once (0358 candidates or 0613 adjacent rescue); refused_by_reason is the disposer''s reason.',
      'refusals', 'went_to is the latest assignment of that charger, at most 60 ticks before the refusal; same_car means '
                  'the offer''s own car already had it.'));
EXCEPTION WHEN OTHERS THEN
  -- A read for advisors and a cockpit: a fault in it must never take the agent's board or the solver pass down.
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END
$function$;

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

  RETURN v_board;
END; $function$;

SET check_function_bodies = on;
