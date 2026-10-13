-- tests/fixtures/world_advance_stub.sql -- what 0718 meets. twin.ottoq_world_advance is the live definition of
-- 2026-10-13 (pg_get_functiondef, byte for byte: md5 3489fb1392073751df4f601d45dc7731), so 0718's md5 premise and its
-- anchors run against exactly what they will meet. Every function it calls, and the three the certified world calls
-- that it did not, is a stub that writes its name to t_calls, so a test reads the order the tick called them in.
-- public.ottoq_sim_advance_tick_world is NOT the live body: it is a stub that calls the live definition's 28 callees
-- (comment-stripped census, 2026-10-13), which is all 0718's V3 parity check reads. Used by
-- tests/test_world_advance_parity_sql.py.
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS twin; CREATE SCHEMA IF NOT EXISTS ottoq; CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE public.t_inflight (n int NOT NULL DEFAULT 0); INSERT INTO public.t_inflight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql
  AS 'SELECT n FROM public.t_inflight';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial, label text, object_kind text, schema_name text,
  object_name text, definition text, def_md5 text, captured_at timestamptz DEFAULT now());
CREATE TYPE public.vehicle_state AS ENUM ('arrived_at_gate', 'charge_complete_holding', 'charging');
CREATE TABLE public.depots (id uuid PRIMARY KEY, feed_mode text);
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid, run_by text, status text,
  started_at timestamptz, last_tick_at timestamptz, next_tick_due_at timestamptz, sim_clock_current timestamptz,
  tick_interval_seconds int DEFAULT 120, tick_count int DEFAULT 0, policy text, payload jsonb);
CREATE TABLE public.ottoq_ocpp_chargers (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid,
  station_state text, last_heartbeat_at timestamptz);
CREATE TABLE public.ottoq_vehicle_dispatches (dispatch_id uuid PRIMARY KEY, sim_run_id uuid, status text);
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, home_depot_id uuid, category text, current_state public.vehicle_state,
  current_stall_id uuid, current_soc numeric, target_soc numeric, last_state_change timestamptz);
CREATE TABLE public.t_calls (seq bigserial PRIMARY KEY, fn text NOT NULL);
CREATE FUNCTION public.ottoq_policy_get(uuid, text, numeric) RETURNS numeric LANGUAGE sql AS 'SELECT $3';
CREATE FUNCTION public.ottoq_default_target_soc() RETURNS numeric LANGUAGE sql AS 'SELECT 100::numeric';

CREATE FUNCTION public.ottoq_sim_advance_visit_atoms(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_visit_atoms'); END$s$;
CREATE FUNCTION public.ottoq_opportunistic_scan(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_opportunistic_scan'); END$s$;
CREATE FUNCTION public.ottoq_sim_advance_flow_contract(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_flow_contract'); END$s$;
CREATE FUNCTION public.ottoq_sim_prearrival_contracts(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_prearrival_contracts'); END$s$;
CREATE FUNCTION public.ottoq_sim_confirm_commands(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_confirm_commands'); END$s$;
CREATE FUNCTION public.ottoq_sim_reconcile_charge_sessions(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_reconcile_charge_sessions'); END$s$;
CREATE FUNCTION public.ottoq_energy_orchestrate(uuid, uuid, timestamptz, integer) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_energy_orchestrate'); END$s$;
CREATE FUNCTION public.ottoq_sim_energy_controller(uuid, uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_energy_controller'); END$s$;
CREATE FUNCTION public.ottoq_sim_advance_charge_sessions(uuid, timestamptz) RETURNS SETOF integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_charge_sessions'); RETURN; END$s$;
CREATE FUNCTION public.ottoq_sim_advance_all_energy(uuid, uuid, timestamptz, numeric) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_all_energy'); END$s$;
CREATE FUNCTION public.ottoq_sim_advance_deployed_telemetry(uuid, timestamptz, numeric) RETURNS SETOF integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_deployed_telemetry'); RETURN; END$s$;
CREATE FUNCTION public.ottoq_sim_advance_wear_counters(uuid, timestamptz, numeric, integer, uuid[]) RETURNS integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_wear_counters'); RETURN 0; END$s$;
CREATE FUNCTION public.ottoq_comms_advance(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_comms_advance'); END$s$;
CREATE FUNCTION public.ottoq_sim_advance_service_flow(uuid, timestamptz, numeric, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_service_flow'); END$s$;
CREATE FUNCTION public.ottoq_sim_overnight_service_drain(uuid, timestamptz, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_overnight_service_drain'); END$s$;
CREATE FUNCTION public.ottoq_sim_emit_depot_heartbeats(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_emit_depot_heartbeats'); END$s$;
CREATE FUNCTION public.ottoq_sim_recover_chargers(uuid, timestamptz, integer) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_recover_chargers'); END$s$;
CREATE FUNCTION public.ottoq_reconcile_charger_states(uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_reconcile_charger_states'); END$s$;
CREATE FUNCTION public.ottoq_oem_webhook_collect_responses() RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_oem_webhook_collect_responses'); END$s$;
CREATE FUNCTION public.ottoq_admit_stranded_vehicles(uuid, uuid, timestamptz, integer, integer) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_admit_stranded_vehicles'); END$s$;
CREATE FUNCTION public.ottoq_sim_generate_arrival_manifests(uuid, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_generate_arrival_manifests'); END$s$;
CREATE FUNCTION public.ottoq_sim_wash_triage(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_wash_triage'); END$s$;
CREATE FUNCTION public.ottoq_sim_vehicle_exception_handler(uuid, timestamptz, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_vehicle_exception_handler'); END$s$;
CREATE FUNCTION public.ottoq_sim_bay_fault_handler(uuid, timestamptz, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_bay_fault_handler'); END$s$;
CREATE FUNCTION public.ottoq_sim_decide_and_dispatch(uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_decide_and_dispatch'); END$s$;
CREATE FUNCTION ottoq.ottoq_owner_orders_tick(uuid, timestamptz) RETURNS integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_owner_orders_tick'); RETURN 0; END$s$;
CREATE FUNCTION twin.ottoq_arm_advance_cycles(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_arm_advance_cycles'); END$s$;
CREATE FUNCTION public.ottoq_release_expired_tethers(timestamptz) RETURNS integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_release_expired_tethers'); RETURN 0; END$s$;
CREATE FUNCTION public.ottoq_sim_advance_tick_world(p_sim_run_id uuid) RETURNS void LANGUAGE plpgsql AS $c$
BEGIN
  PERFORM ottoq_admit_stranded_vehicles();
  PERFORM ottoq_arm_advance_cycles();
  PERFORM ottoq_comms_advance();
  PERFORM ottoq_energy_orchestrate();
  PERFORM ottoq_oem_webhook_collect_responses();
  PERFORM ottoq_opportunistic_scan();
  PERFORM ottoq_owner_orders_tick();
  PERFORM ottoq_policy_get();
  PERFORM ottoq_reconcile_charger_states();
  PERFORM ottoq_release_expired_tethers();
  PERFORM ottoq_sim_advance_all_energy();
  PERFORM ottoq_sim_advance_charge_sessions();
  PERFORM ottoq_sim_advance_deployed_telemetry();
  PERFORM ottoq_sim_advance_flow_contract();
  PERFORM ottoq_sim_advance_service_flow();
  PERFORM ottoq_sim_advance_visit_atoms();
  PERFORM ottoq_sim_advance_wear_counters();
  PERFORM ottoq_sim_bay_fault_handler();
  PERFORM ottoq_sim_confirm_commands();
  PERFORM ottoq_sim_emit_depot_heartbeats();
  PERFORM ottoq_sim_energy_controller();
  PERFORM ottoq_sim_generate_arrival_manifests();
  PERFORM ottoq_sim_overnight_service_drain();
  PERFORM ottoq_sim_prearrival_contracts();
  PERFORM ottoq_sim_reconcile_charge_sessions();
  PERFORM ottoq_sim_recover_chargers();
  PERFORM ottoq_sim_vehicle_exception_handler();
  PERFORM ottoq_sim_wash_triage();
END
$c$;
-- the live definition, byte for byte
CREATE OR REPLACE FUNCTION twin.ottoq_world_advance()
 RETURNS TABLE(run_id uuid, sim_clock timestamp with time zone, tick_minutes numeric, telemetry_emitted integer, charge_advanced integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_now timestamptz := now();
  v_tick_minutes numeric;
  v_tel int := 0; v_chg int := 0;
  v_wear_ids uuid[]; v_feed_sim boolean := true;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs
   WHERE run_by = 'production_live' AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
  IF NOT FOUND THEN RAISE WARNING 'ottoq_world_advance: no running production run'; RETURN; END IF;
  SELECT COALESCE(d.feed_mode,'sim')='sim' INTO v_feed_sim FROM depots d WHERE d.id=v_run.depot_id;
  v_feed_sim := COALESCE(v_feed_sim, true);

  v_tick_minutes := GREATEST(0.25, LEAST(10,
    EXTRACT(EPOCH FROM (v_now - COALESCE(v_run.last_tick_at, v_now - interval '2 minutes'))) / 60.0));

  -- ===== PRE-TELEMETRY ORCHESTRATION (mirror of advance_tick_world) =====
  BEGIN PERFORM ottoq_sim_advance_visit_atoms(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance visit_atoms: %', SQLERRM; END;
  BEGIN PERFORM ottoq_opportunistic_scan(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance opportunistic: %', SQLERRM; END;
  BEGIN PERFORM ottoq_sim_advance_flow_contract(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance flow_contract: %', SQLERRM; END;
  IF v_feed_sim THEN
  BEGIN PERFORM ottoq_sim_prearrival_contracts(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance prearrival: %', SQLERRM; END;
  -- 0654: with twin_operator_door on, the twin's operators answer in their own job (twin.ottoq_twin_operators_beat)
  IF ottoq_policy_get(v_run.sim_run_id, 'twin_operator_door', 0) < 1 THEN
  BEGIN PERFORM ottoq_sim_confirm_commands(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance confirm_commands: %', SQLERRM; END;
  END IF;
  END IF;

  -- 0445 (G178): the battery is dispatched below, after reconciliation starts this tick's sessions

  IF v_feed_sim THEN
  BEGIN UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_now
          WHERE depot_id = v_run.depot_id AND station_state <> 'Faulted';
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance early heartbeat: %', SQLERRM; END;
  END IF;
  IF v_feed_sim THEN
  BEGIN PERFORM ottoq_sim_reconcile_charge_sessions(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance reconcile_charge: %', SQLERRM; END;
  END IF;
  /* 0445 (G178): the battery answers the load it will see -- after reconciliation, before delivery. */
  -- OTTO-Q ENERGY ORCHESTRATION (the #1 demand-shave edge) — gated + defensive
  IF (v_run.policy IS NULL OR v_run.policy = 'otto_q')
     AND ottoq_policy_get(v_run.sim_run_id,'energy_orchestration_enabled',1) > 0 THEN
    BEGIN PERFORM ottoq_energy_orchestrate(v_run.sim_run_id, v_run.depot_id, v_now, v_run.tick_count + 1);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance energy_orchestrate: %', SQLERRM; END;
  END IF;
  IF v_feed_sim THEN
  BEGIN PERFORM ottoq_sim_energy_controller(v_run.sim_run_id, v_run.depot_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance energy_controller: %', SQLERRM; END;
  END IF;
  IF v_feed_sim THEN
  BEGIN SELECT COUNT(*) INTO v_chg FROM ottoq_sim_advance_charge_sessions(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN v_chg := -1; RAISE WARNING 'world_advance charge: %', SQLERRM; END;
  BEGIN PERFORM ottoq_sim_advance_all_energy(v_run.depot_id, v_run.sim_run_id, v_now, v_tick_minutes);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance energy: %', SQLERRM; END;
  ELSE v_chg := 0;
  END IF;

  -- TELEMETRY (carries the AP-3/AP-4 return handshake + booking at need-fire)
  SELECT array_agg(d.dispatch_id) INTO v_wear_ids
    FROM ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = v_run.sim_run_id AND d.status IN ('active','returning');
  IF v_feed_sim THEN
  BEGIN SELECT COUNT(*) INTO v_tel FROM ottoq_sim_advance_deployed_telemetry(v_run.sim_run_id, v_now, v_tick_minutes);
  EXCEPTION WHEN OTHERS THEN v_tel := -1; RAISE WARNING 'world_advance telemetry: %', SQLERRM; END;
  BEGIN PERFORM ottoq_sim_advance_wear_counters(v_run.sim_run_id, v_now, v_tick_minutes, v_run.tick_count + 1,
                                                COALESCE(v_wear_ids, ARRAY[]::uuid[]));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance wear: %', SQLERRM; END;
  ELSE v_tel := 0;
  END IF;
  BEGIN PERFORM ottoq_comms_advance(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance comms: %', SQLERRM; END;

  -- SERVICE PIPELINE + OVERNIGHT
  BEGIN PERFORM ottoq_sim_advance_service_flow(v_run.sim_run_id, v_now, v_tick_minutes, v_run.depot_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance service_flow: %', SQLERRM; END;
  IF v_feed_sim THEN
  BEGIN PERFORM ottoq_sim_overnight_service_drain(v_run.depot_id, v_now, v_run.sim_run_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance overnight_drain: %', SQLERRM; END;
  END IF;

  -- CLOCK ADVANCE
  UPDATE ottoq_sim_runs
     SET sim_clock_current = v_now, last_tick_at = v_now,
         next_tick_due_at = v_now + (tick_interval_seconds || ' seconds')::interval,
         tick_count = tick_count + 1
   WHERE sim_run_id = v_run.sim_run_id;

  -- INFRA RECONCILE
  IF v_feed_sim THEN
  BEGIN PERFORM ottoq_sim_emit_depot_heartbeats(v_run.depot_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance heartbeats: %', SQLERRM; END;
  UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_now
   WHERE depot_id = v_run.depot_id AND station_state <> 'Faulted';
  BEGIN PERFORM ottoq_sim_recover_chargers(v_run.depot_id, v_now, 50);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance recover_chargers: %', SQLERRM; END;
  END IF;
  BEGIN PERFORM ottoq_reconcile_charger_states(v_run.depot_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance charger reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_oem_webhook_collect_responses();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance webhook reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_admit_stranded_vehicles(v_run.depot_id, v_run.sim_run_id, v_now, 80, 12);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance admit_stranded: %', SQLERRM; END;

  -- GATE + SERVICE INTAKE HANDLERS
  IF v_feed_sim THEN
  BEGIN PERFORM ottoq_sim_generate_arrival_manifests(v_run.depot_id, v_run.sim_run_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance arrival_manifests: %', SQLERRM; END;
  END IF;
  BEGIN PERFORM ottoq_sim_wash_triage(v_run.depot_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance wash_triage: %', SQLERRM; END;
  IF v_feed_sim THEN
  BEGIN PERFORM ottoq_sim_vehicle_exception_handler(v_run.depot_id, v_now, v_run.sim_run_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance exception_handler: %', SQLERRM; END;
  BEGIN PERFORM ottoq_sim_bay_fault_handler(v_run.depot_id, v_now, v_run.sim_run_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance bay_fault: %', SQLERRM; END;
  END IF;

  -- gate disposition (target-aware): an arrival already at/above its OWN charge
  -- target needs no charge -> hold for onward disposition (wash/deploy).
  BEGIN
    UPDATE vehicles vv SET current_state='charge_complete_holding'::vehicle_state, last_state_change=v_now
     WHERE vv.home_depot_id=v_run.depot_id AND vv.category='autonomous'
       AND vv.current_state='arrived_at_gate' AND vv.current_stall_id IS NULL
       AND vv.current_soc >= COALESCE(vv.target_soc, public.ottoq_default_target_soc());
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance gate_holding: %', SQLERRM; END;

  -- PRODUCTION BRAIN: same decider as the demo path (decide_tick + auto_dispatch recall,
  -- cuOpt + Nemotron, every effect shield-gated). Defensive: a hiccup never aborts the tick.
  -- hand the decider the SAME elapsed time the physics just used (was recomputed
  -- from tick_interval_seconds * time_scale = 30 min, vs ~2 min of real elapsed time).
  UPDATE ottoq_sim_runs
     SET payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('tick_minutes_actual', v_tick_minutes)
   WHERE sim_run_id = v_run.sim_run_id;
  BEGIN PERFORM ottoq_sim_decide_and_dispatch(v_run.sim_run_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance decider: %', SQLERRM; END;

  run_id := v_run.sim_run_id; sim_clock := v_now; tick_minutes := v_tick_minutes;
  telemetry_emitted := v_tel; charge_advanced := v_chg;
  RETURN NEXT;
END;
$function$;
RESET check_function_bodies;
