-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: 531b8f5dbd029888bd8e1276203af120
CREATE OR REPLACE FUNCTION twin.ottoq_sim_bay_fault_handler(p_depot_id uuid, p_sim_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed bigint; v_rec RECORD; v_n int := 0;
  v_protected int := 0; v_deferred int := 0; v_injected int := 0; v_repaired int := 0;
  v_rate numeric; v_outage numeric; v_lane text; v_new_state vehicle_state;
  v_gate jsonb; v_ends timestamptz; v_remaining numeric; v_cause text;
BEGIN
  IF p_depot_id IS NULL OR p_sim_clock IS NULL THEN RETURN 0; END IF;

  -- Fault INJECTION is now opt-in and lands on the STALL, never on the vehicle.
  -- Default 0: the twin no longer invents faults, so nothing is evicted unless a bay is
  -- genuinely out of service. Set bay_fault_rate_per_tick > 0 to exercise resilience.
  v_rate   := GREATEST(0, COALESCE(ottoq_policy_get(p_sim_run_id, 'bay_fault_rate_per_tick', 0), 0));
  v_outage := GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id, 'bay_fault_outage_min', 45), 45));
  v_seed   := abs(hashtextextended(p_depot_id::text || p_sim_clock::text || 'bayflt', 23));

  -- ───── (0) REPAIR: a faulted bay comes back; capacity can never be lost permanently ─────
  UPDATE stalls s
     SET status = 'available',
         equipment_config = COALESCE(s.equipment_config,'{}'::jsonb) - 'bay_fault'
   WHERE s.depot_id = p_depot_id
     AND s.stall_type IN ('wash_bay'::stall_type,'detail_bay'::stall_type,'service_bay'::stall_type)
     AND s.status = 'maintenance'
     AND (s.equipment_config #>> '{bay_fault,repair_at}') IS NOT NULL
     AND (s.equipment_config #>> '{bay_fault,repair_at}')::timestamptz <= p_sim_clock;
  GET DIAGNOSTICS v_repaired = ROW_COUNT;

  -- ───── (1) INJECT a GENUINE bay fault on the STALL (opt-in) ─────
  -- Never faults the last healthy bay of its type, so a lane can never drop to zero
  -- capacity and wedge the flow.
  IF v_rate > 0 THEN
    FOR v_rec IN
      SELECT s.id, s.stall_code
        FROM stalls s
       WHERE s.depot_id = p_depot_id
         AND s.stall_type IN ('wash_bay'::stall_type,'detail_bay'::stall_type,'service_bay'::stall_type)
         AND s.status NOT IN ('maintenance','closed')
         AND (SELECT COUNT(*) FROM stalls s2
               WHERE s2.depot_id = s.depot_id AND s2.stall_type = s.stall_type
                 AND s2.status NOT IN ('maintenance','closed')) > 1
    LOOP
      IF ottoq_sim_seeded_random(v_seed, 'inj:'||v_rec.id::text) < v_rate THEN
        UPDATE stalls
           SET status = 'maintenance',
               equipment_config = COALESCE(equipment_config,'{}'::jsonb)
                 || jsonb_build_object('bay_fault', jsonb_build_object(
                      'faulted_at', p_sim_clock,
                      'repair_at',  p_sim_clock + make_interval(mins => v_outage::int),
                      'injected_by','twin_bay_fault_handler'))
         WHERE id = v_rec.id;
        v_injected := v_injected + 1;
      END IF;
    END LOOP;
  END IF;

  -- ───── (2) EVICTION — LAST RESORT, ZONE-C ONLY ─────
  FOR v_rec IN
    SELECT v.id, v.current_state, v.current_stall_id, v.fleet_operator_id, v.config,
           st.id AS stall_id, st.stall_code, st.status AS stall_status,
           (v.config->>'service_ends_at')::timestamptz AS ends_at,
           (st.id IS NOT NULL AND st.status IN ('maintenance','closed'))      AS stall_faulted,
           (COALESCE((v.config->>'flagged_issue')::boolean, false)
             AND COALESCE(v.config->>'flagged_issue_type','') IN
                 ('bay_fault','equipment_failure','tech_hold','tech_flag'))   AS tech_flagged
      FROM vehicles v
      LEFT JOIN stalls st ON st.id = v.current_stall_id
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND v.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
  LOOP
    v_ends      := v_rec.ends_at;
    v_remaining := CASE WHEN v_ends IS NULL THEN NULL
                        ELSE ROUND(EXTRACT(EPOCH FROM (v_ends - p_sim_clock))/60.0, 1) END;

    -- THE GATE. No genuine fault and no tech flag => the incumbent stays put, full stop.
    IF NOT (v_rec.stall_faulted OR v_rec.tech_flagged) THEN
      IF v_ends IS NULL OR v_ends > p_sim_clock THEN
        v_protected := v_protected + 1;   -- mid-service and protected
      END IF;
      CONTINUE;
    END IF;

    v_cause := CASE WHEN v_rec.stall_faulted
                    THEN 'bay_fault_' || COALESCE(v_rec.stall_status,'unknown')
                    ELSE 'tech_flag_' || COALESCE(v_rec.config->>'flagged_issue_type','unspecified') END;

    -- Route the Zone-C exception through the in-depot reassignment gate.
    v_gate := ottoq_indepot_reassignment_guard(v_rec.id, p_sim_run_id, 'resource_fault',
                jsonb_build_object('cause', v_cause, 'stall_id', v_rec.stall_id,
                                   'stall_code', v_rec.stall_code,
                                   'from_state', v_rec.current_state::text,
                                   'service_ends_at', v_ends,
                                   'remaining_min', v_remaining));
    IF NOT COALESCE((v_gate->>'allowed')::boolean, false) THEN
      v_deferred := v_deferred + 1;   -- awaiting tech approval; incumbent stays in the bay
      CONTINUE;
    END IF;

    IF v_rec.current_state = 'in_service_bay' THEN
      v_lane := 'service'; v_new_state := 'staged_awaiting_service'::vehicle_state;
    ELSE
      v_lane := 'wash';    v_new_state := 'charge_complete_holding'::vehicle_state;
    END IF;

    -- Free the space physically. Status stays 'maintenance' so the faulted bay is not
    -- handed straight back out; ottoq_release_vacated_spaces skips maintenance/closed.
    IF v_rec.stall_id IS NOT NULL THEN
      UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_rec.stall_id;
    END IF;

    UPDATE vehicles
       SET current_state    = v_new_state,
           last_state_change = p_sim_clock,
           current_stall_id  = NULL,
           config = jsonb_set(
                      (COALESCE(config,'{}'::jsonb) - 'service_ends_at'),
                      '{svc_step}', to_jsonb(CASE WHEN v_lane='service' THEN 'need_service' ELSE 'need_wash' END))
                    || jsonb_build_object('bay_eviction', jsonb_build_object(
                         'at', p_sim_clock, 'cause', v_cause,
                         'stall_code', v_rec.stall_code,
                         'interrupted_with_min_remaining', v_remaining,
                         'gate_mode', v_gate->>'mode'))
     WHERE id = v_rec.id;

    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='bay_fault_handler',
      p_event_type:='twin.bay_fault_reroute', p_entity_type:='vehicle', p_entity_id:=v_rec.id,
      p_fleet_operator_id:=v_rec.fleet_operator_id, p_depot_id:=p_depot_id,
      p_payload:=jsonb_build_object(
        'lane', v_lane, 'from_state', v_rec.current_state::text,
        'disposition', 'evicted_by_bay_fault_via_reassignment_gate',
        'cause', v_cause, 'stall_id', v_rec.stall_id, 'stall_code', v_rec.stall_code,
        'stall_status', v_rec.stall_status,
        'service_ends_at', v_ends, 'interrupted_with_min_remaining', v_remaining,
        'gate_allowed', true, 'gate_mode', v_gate->>'mode',
        'doctrine', 'in_depot_reassignment_gate: Zone-C resource_fault exception'),
      p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  -- One summary per tick, and only when something actually happened (event-write
  -- amplification is the known tick-cost driver).
  IF v_n > 0 OR v_deferred > 0 OR v_injected > 0 OR v_repaired > 0 THEN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='bay_fault_handler',
      p_event_type:='twin.bay_fault_summary', p_entity_type:='depot', p_entity_id:=p_depot_id,
      p_payload:=jsonb_build_object('evicted', v_n, 'deferred_awaiting_tech', v_deferred,
        'protected_mid_service', v_protected, 'faults_injected', v_injected,
        'bays_repaired', v_repaired, 'rate_per_tick', v_rate, 'outage_min', v_outage),
      p_severity:=CASE WHEN v_n > 0 THEN 'warning' ELSE 'info' END,
      p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  END IF;

  RETURN v_n;

-- Never abort the tick.
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_sim_bay_fault_handler: FAILED sqlstate=% msg=% depot=% run=%',
    SQLSTATE, SQLERRM, p_depot_id, p_sim_run_id;
  RETURN 0;
END;
$function$

