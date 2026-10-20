-- tests/fixtures/reported_work_stub.sql: the production seam a robot or technician reports finished work through, as
-- live, for tests/test_reported_work_closes_its_leg_sql.py (db/migrations/0752, G466). Loaded after
-- tests/fixtures/agent_charge_order_stub.sql (vehicles, stalls, runs, visit needs, the policy reader) and
-- tests/fixtures/bay_exit_leg_stub.sql (the itinerary tables, the live leg helpers, leg trigger and SDR emitter, the
-- operation catalog's bay rows and the event writer's stand-in). Read from the live catalog on 2026-10-18 between 12:37
-- and 1:11 AM CT (the test asserts each md5 of prosrc):
--   public.ottoq_ingest_service_complete e64f5376, public.ottoq_mark_visit_atoms_done be7dc4f2,
--   public.ottoq_close_atom_leg efd2dbb8,
-- and the operation catalog's rows for the work done in place and the charges, as live. Two stand-ins, noted where
-- defined: the wear ledger's credit and the task_completion probe, each recording its call in
-- public.reported_work_calls.
SET client_min_messages = warning;

INSERT INTO public.ottoq_operation_catalog (pack_id, operation_code, leg_type, svc_code, emits_sdr)
VALUES ('robotaxi', 'sensor_clean', 'sensor_clean', 'sensor_clean', true),
       ('robotaxi', 'software_update', 'software_update', 'software_update', true),
       ('robotaxi', 'interior_tidy', 'interior_tidy', 'interior_tidy', true),
       ('robotaxi', 'item_retrieval', 'item_retrieval', 'item_retrieval', true),
       ('robotaxi', 'remote_diagnostics', 'remote_diagnostics', 'remote_diagnostics', true),
       ('robotaxi', 'triage_check', 'triage_check', 'triage_check', true),
       ('robotaxi', 'inspect', 'inspect', 'interior_inspection', true),
       ('robotaxi', 'readiness_check', NULL, 'readiness_check', true),
       ('robotaxi', 'charge_dcfc', 'charge_dcfc', 'charge', true),
       ('robotaxi', 'charge_l2', 'charge_l2', 'charge', true)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.reported_work_calls (n bigserial PRIMARY KEY, fn text, vehicle_id uuid, svc text,
                                                       sim_run_id uuid, depot_id uuid, started_at timestamptz,
                                                       ended_at timestamptz);

-- stand-in: the live credit resets the wear ledger and the need profile's due dates; here it records the call
CREATE OR REPLACE FUNCTION public.ottoq_wear_mark_serviced(p_vehicle_id uuid, p_sim_run_id uuid, p_service text,
                                                           p_clock timestamp with time zone)
RETURNS boolean LANGUAGE sql
AS $$ INSERT INTO public.reported_work_calls (fn, vehicle_id, svc, sim_run_id, ended_at)
      VALUES ('wear', p_vehicle_id, p_service, p_sim_run_id, p_clock) RETURNING true $$;

-- stand-in: the live probe asks the shield at task_completion and logs its verdicts; here it records the call and
-- returns no verdict, as the shield's advisory answer is read by nobody on this path
CREATE OR REPLACE FUNCTION public.ottoq_probe_task_completion(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid,
                                                              p_svc text, p_started_at timestamp with time zone,
                                                              p_ends_at timestamp with time zone)
RETURNS TABLE (rule_code text, passed boolean, reason text, severity text, enforcement text, would_block boolean,
               had_a_stall boolean)
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.reported_work_calls (fn, vehicle_id, svc, sim_run_id, depot_id, started_at, ended_at)
  VALUES ('probe', p_vehicle_id, p_svc, p_sim_run_id, p_depot_id, p_started_at, p_ends_at);
  RETURN;
END $$;

-- live: public.ottoq_mark_visit_atoms_done (prosrc md5 be7dc4f2393b0b451543e12450f2df88)
CREATE OR REPLACE FUNCTION public.ottoq_mark_visit_atoms_done(p_vehicle uuid, p_svcs text[], p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_visit uuid; v_atoms jsonb; v_new jsonb := '[]'::jsonb; v_a jsonb; v_n int := 0;
BEGIN
  SELECT visit_id, atoms INTO v_visit, v_atoms FROM ottoq_visit_needs
   WHERE vehicle_id = p_vehicle AND status IN ('open','in_progress') AND COALESCE(ottoq_visit_needs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = ottoq_visit_needs.depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
   ORDER BY created_at DESC LIMIT 1;
  IF v_visit IS NULL THEN RETURN 0; END IF;
  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF v_a->>'svc' = ANY(p_svcs) AND COALESCE(v_a->>'status','pending') <> 'done' THEN
      v_a := v_a || jsonb_build_object('status','done','done_at', to_jsonb(p_clock));
      v_n := v_n + 1;
    END IF;
    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;
  IF v_n > 0 THEN UPDATE ottoq_visit_needs SET atoms = v_new, status = 'in_progress' WHERE visit_id = v_visit; END IF;
  RETURN v_n;
END; $function$;

-- live: public.ottoq_close_atom_leg (prosrc md5 efd2dbb8701e59a2be02500e53c03191)
CREATE OR REPLACE FUNCTION public.ottoq_close_atom_leg(p_sim_run_id uuid, p_vehicle uuid, p_svc text, p_started timestamp with time zone, p_ended timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_leg uuid; v_planned_end timestamptz;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN; END IF;
  SELECT leg_id, planned_end_sim INTO v_leg, v_planned_end FROM ottoq_itinerary_legs
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle
     AND (leg_type = p_svc
          /* 0504 (G232): or the leg the planner tagged with this atom. The inspection lane's two kinds of `inspect`
             leg differ only by that tag (interior_inspection, readiness_check), so the type alone never found an
             inspection's leg, and the readiness check's `inspect` closed it instead (25 of 91 on b0fdc92b, a median
             84.8 minutes after the inspection ended). Bay legs stay with the service flow that opens and closes them. */
          OR (duration_basis->>'atom' = p_svc AND leg_type NOT IN ('wash','detail','service')))
     AND status IN ('planned','active')
   ORDER BY seq, planned_start_sim, planned_end_sim, leg_id /* 0129 */ LIMIT 1;
  IF v_leg IS NULL THEN RETURN; END IF;
  UPDATE ottoq_itinerary_legs
     SET status = 'done',
         -- 0511 (G236): a leg nothing bound to a stall (an inspection on the charger, work done where the car stood)
         -- records where the car was when the work finished, so its signed service record names the place.
         to_stall_id = COALESCE(to_stall_id, (SELECT v.current_stall_id FROM vehicles v WHERE v.id = p_vehicle)),
         actual_start_sim = COALESCE(actual_start_sim, p_started),
         actual_end_sim = p_ended,
         deviation_s = CASE WHEN v_planned_end IS NULL THEN NULL
                            ELSE EXTRACT(EPOCH FROM (p_ended - v_planned_end))::int END
   WHERE leg_id = v_leg;
END; $function$;

-- live: public.ottoq_ingest_service_complete (prosrc md5 e64f53765109e6cad248150cc6f75bc3)
CREATE OR REPLACE FUNCTION public.ottoq_ingest_service_complete(p_vehicle_id uuid, p_source text DEFAULT 'production'::text, p_actor text DEFAULT 'depot_tech'::text, p_services text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh    vehicles%ROWTYPE;
  v_run    ottoq_sim_runs%ROWTYPE;
  v_clock  timestamptz;
  v_s      text;
  v_before int; v_after int;
BEGIN
  SELECT * INTO v_veh FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'vehicle_not_found'); END IF;

  SELECT * INTO v_run FROM ottoq_sim_runs
   WHERE depot_id = v_veh.home_depot_id AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
  v_clock := COALESCE(v_run.sim_clock_current, now());

  IF p_services IS NOT NULL AND array_length(p_services, 1) > 0 THEN
    IF v_veh.current_state IN ('deployed','en_route_to_deployment','offline') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'vehicle_not_in_depot', 'state', v_veh.current_state::text);
    END IF;
    SELECT COUNT(*) INTO v_before FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = vn.depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
       AND a->>'svc' = ANY(p_services) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
    PERFORM ottoq_mark_visit_atoms_done(p_vehicle_id, p_services, v_clock);
    SELECT COUNT(*) INTO v_after FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = vn.depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
       AND a->>'svc' = ANY(p_services) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
    -- ══════ 0004: the sim-run precondition is GONE. See §4 header. ══════
    -- v_run.sim_run_id may be NULL here; ottoq_wear_mark_serviced treats that as
    -- "no wear row" and still moves the profile's due dates, which is the whole point.
    IF v_before - v_after > 0 THEN
      FOREACH v_s IN ARRAY p_services LOOP
        BEGIN PERFORM ottoq_wear_mark_serviced(p_vehicle_id, v_run.sim_run_id, v_s, v_clock);
        EXCEPTION WHEN OTHERS THEN
          -- 0004: was `THEN NULL`. Loud, named, still non-fatal.
          RAISE WARNING 'ottoq_ingest_service_complete: wear/profile reset FAILED SAFELY for vehicle % service %: % %',
                        p_vehicle_id, v_s, SQLSTATE, SQLERRM;
        END;
      END LOOP;
    END IF;
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type := 'depot_tech', p_actor_id := p_actor,
        p_event_type := 'ops.services_completed_reported', p_entity_type := 'vehicle', p_entity_id := p_vehicle_id,
        p_payload := jsonb_build_object('services', to_jsonb(p_services), 'atoms_matched', v_before - v_after,
                                        'state', v_veh.current_state::text, 'source', p_source),
        p_severity := CASE WHEN v_before - v_after = 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'production', p_data_source := 'production',
        p_sim_run_id := v_run.sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN jsonb_build_object('ok', v_before - v_after > 0, 'vehicle_id', p_vehicle_id,
      'services_reported', to_jsonb(p_services), 'atoms_matched', v_before - v_after,
      'note', CASE WHEN v_before - v_after = 0 THEN 'no open workflow atoms matched the reported services' ELSE NULL END);
  END IF;

  IF v_veh.current_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_in_bay', 'state', v_veh.current_state::text);
  END IF;
  UPDATE vehicles SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{service_done}', 'true'::jsonb)
   WHERE id = p_vehicle_id;
  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type := 'depot_tech', p_actor_id := p_actor,
      p_event_type := 'ops.service_marked_complete', p_entity_type := 'vehicle', p_entity_id := p_vehicle_id,
      p_payload := jsonb_build_object('state', v_veh.current_state::text, 'source', p_source),
      p_severity := 'info', p_ingest_source := 'production', p_data_source := 'production',
      p_sim_run_id := v_run.sim_run_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN jsonb_build_object('ok', true, 'vehicle_id', p_vehicle_id, 'state', v_veh.current_state::text);
END;
$function$;
