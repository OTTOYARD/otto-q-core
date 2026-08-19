-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: ee334e23ddb819483810abc33418b3ad
CREATE OR REPLACE FUNCTION twin.ottoq_sim_start_charge_session(p_vehicle_id uuid, p_stall_id uuid, p_sim_run_id uuid, p_target_soc numeric DEFAULT NULL::numeric, p_sim_clock_now timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_session_id      UUID := gen_random_uuid();
  v_vehicle         RECORD;
  v_stall           RECORD;
  v_charger         ottoq_ocpp_chargers%ROWTYPE;
  v_clock           TIMESTAMPTZ;
  v_target_soc      NUMERIC;
  v_charge_kind     TEXT;
  v_state           vehicle_state;
  v_ambient_temp    NUMERIC;
  v_battery_temp    NUMERIC;
  v_init_rate       NUMERIC;
BEGIN
  v_clock := COALESCE(p_sim_clock_now, NOW());

  SELECT id, fleet_operator_id, current_soc, target_soc, battery_capacity_kwh, current_stall_id,
         inlet_max_kw, max_charge_rate_kw, current_depot_id,
         (config->>'battery_soh_pct')::NUMERIC AS soh, display_name
    INTO v_vehicle FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'vehicle % not found', p_vehicle_id; END IF;

  SELECT s.id, s.depot_id, s.ocpp_charger_id, s.connector_max_kw, s.stall_type
    INTO v_stall FROM stalls s WHERE s.id = p_stall_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'stall % not found', p_stall_id; END IF;
  IF v_stall.ocpp_charger_id IS NULL THEN RAISE EXCEPTION 'stall % has no associated charger', p_stall_id; END IF;

  SELECT * INTO v_charger FROM ottoq_ocpp_chargers WHERE charger_id = v_stall.ocpp_charger_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'charger for stall % not found', p_stall_id; END IF;

  v_ambient_temp := ottoq_sample_calibrated('ambient_temp_c', 'global',
    COALESCE(EXTRACT(EPOCH FROM v_clock)::BIGINT, 42), 'ambient:' || p_vehicle_id::text || ':' || v_clock::text);
  v_ambient_temp := COALESCE(v_ambient_temp, 20);
  v_battery_temp := v_ambient_temp + 5 + ottoq_sim_seeded_random(42, 'btemp:' || p_vehicle_id::text) * 10;

  v_target_soc := LEAST(COALESCE(p_target_soc, v_vehicle.target_soc, public.ottoq_default_target_soc()), public.ottoq_target_soc_cap(v_stall.stall_type::TEXT, COALESCE(p_sim_clock_now, NOW())));
  v_charge_kind := CASE WHEN v_charger.max_kw > 50 THEN 'dcfc' ELSE 'l2' END;
  v_state := (CASE WHEN v_charger.max_kw > 50 THEN 'charging_dcfc' ELSE 'charging_l2' END)::vehicle_state;

  v_init_rate := ottoq_sim_compute_charge_rate(
    p_soc_pct := v_vehicle.current_soc, p_battery_temp_c := v_battery_temp,
    p_ambient_temp_c := v_ambient_temp, p_charger_max_kw := v_charger.max_kw,
    p_vehicle_max_kw := v_vehicle.inlet_max_kw, p_battery_capacity_kwh := v_vehicle.battery_capacity_kwh,
    p_battery_soh_pct := COALESCE(v_vehicle.soh, 95),
    p_noise_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42'), 42)),
    p_noise_salt := p_vehicle_id::text || ':' || v_clock::text);

  INSERT INTO ocpp_sessions (
    id, depot_id, stall_id, vehicle_id, sim_run_id,
    charge_point_id, transaction_id, evse_id, connector_id,
    status, started_at, soc_start,
    max_rate_limit_kw, ambient_temp_c, id_token,
    last_meter_value, peak_power_kw, meter_values_count
  ) VALUES (
    v_session_id, v_stall.depot_id, p_stall_id, p_vehicle_id, p_sim_run_id,
    v_charger.ocpp_identifier,
    'TXN-' || to_char(v_clock AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS') || '-' || substr(v_session_id::text, 1, 8),
    1, 1,
    'active', v_clock, v_vehicle.current_soc,
    LEAST(v_charger.max_kw, v_vehicle.inlet_max_kw), v_ambient_temp,
    'TWIN-' || substr(v_vehicle.id::text, 1, 8),
    jsonb_build_object('at', v_clock, 'power_kw', 0::numeric,
      'soc_pct', ROUND(v_vehicle.current_soc::numeric, 1), 'battery_temp_c', ROUND(v_battery_temp::numeric, 1)),
    ROUND(v_init_rate::numeric, 2), 1
  );

  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StatusNotification', jsonb_build_object('connectorId', 1, 'connectorStatus', 'Occupied', 'evseId', 1, 'timestamp', v_clock));
  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'Authorize', jsonb_build_object('idToken', jsonb_build_object('idToken', 'TWIN-' || substr(p_vehicle_id::text, 1, 8), 'type', 'ISO14443'), 'timestamp', v_clock));
  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StartTransaction', jsonb_build_object('connectorId', 1, 'idTag', 'TWIN-' || substr(p_vehicle_id::text, 1, 8),
      'meterStart', 0, 'soc_start_pct', v_vehicle.current_soc, 'target_soc_pct', v_target_soc, 'timestamp', v_clock, 'ambient_temp_c', v_ambient_temp));

  UPDATE ottoq_ocpp_chargers SET station_state = 'Occupied', station_state_changed_at = v_clock WHERE charger_id = v_charger.charger_id;
  UPDATE stalls SET current_vehicle_id = p_vehicle_id WHERE id = p_stall_id;
  UPDATE vehicles SET current_state = v_state, current_stall_id = p_stall_id, current_depot_id = v_stall.depot_id, last_state_change = v_clock WHERE id = p_vehicle_id;

  -- ═══════════ THE ARM REACHES IN ═══════════
  -- StartTransaction is not the plug going in any more than StopTransaction was
  -- it coming out. On a robot-served DCFC stall the arm now has to unstow,
  -- approach, align, insert and latch before this car is connected, and OTTO-Q
  -- must refuse to move it for that whole window. Opening the cycle also writes
  -- the tether, so there is no instant where the robot is moving and the car
  -- reads movable. Never allowed to abort the session.
  -- ...BUT NOT FOR A CAR THAT NEEDS NOTHING. A session opened for a vehicle
  -- already at its target completes on the next tick with 0.00 kWh delivered,
  -- and the demate behind it abandons this mate mid-approach. The live run of
  -- 2026-08-13 produced 25 demates against 20 latches that way -- five
  -- disconnects from a connector that was never inserted. The arm only reaches
  -- when there is charge to move.
  IF v_stall.stall_type = 'dcfc'::stall_type
     AND COALESCE(v_vehicle.current_soc, 0) < v_target_soc THEN
    BEGIN
      PERFORM twin.ottoq_arm_begin_cycle(p_sim_run_id, p_vehicle_id, p_stall_id,
                                         v_session_id, 'mate', v_clock);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm mate begin: %', SQLERRM;
    END;
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'twin_charge_orchestrator',
    p_event_type := 'charge.session_started', p_entity_type := 'ocpp_session', p_entity_id := v_session_id,
    p_fleet_operator_id := v_vehicle.fleet_operator_id, p_depot_id := v_stall.depot_id,
    p_payload := jsonb_build_object('vehicle_display_name', v_vehicle.display_name, 'charger', v_charger.ocpp_identifier,
      'charge_kind', v_charge_kind, 'soc_start', v_vehicle.current_soc, 'soc_target', v_target_soc,
      'max_rate_kw', LEAST(v_charger.max_kw, v_vehicle.inlet_max_kw), 'initial_rate_kw', ROUND(v_init_rate::numeric,1),
      'ambient_temp_c', v_ambient_temp, 'battery_temp_c', v_battery_temp, 'battery_soh_pct', v_vehicle.soh),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);

  -- T3 RENDER CONTRACT: the taxi TO this charger. Emitted with the origin the
  -- vehicle still holds, so the renderer can interpolate the drive instead of
  -- teleporting the car into the stall. Never allowed to abort the session.
  BEGIN
    PERFORM ottoq_itin_travel_leg(p_sim_run_id, v_stall.depot_id, p_vehicle_id,
                                  v_vehicle.current_stall_id, p_stall_id, v_clock,
                                  'taxi_to_charger', 'twin_charge_orchestrator');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (charge): %', SQLERRM;
  END;

  PERFORM ottoq_itin_leg_open(p_sim_run_id, v_stall.depot_id, p_vehicle_id, v_clock,
    CASE WHEN v_charger.max_kw > 50 THEN 'charge_dcfc' ELSE 'charge_l2' END,
    p_stall_id,
    v_clock + (ottoq_estimate_charge_minutes(
      v_vehicle.current_soc, v_target_soc, v_charger.max_kw, v_vehicle.inlet_max_kw,
      v_vehicle.battery_capacity_kwh, v_battery_temp, COALESCE(v_vehicle.soh, 95),
      GREATEST(0.2, ottoq_profile_rate_mult(p_sim_run_id, 'charge_time'))) || ' minutes')::interval,
    jsonb_build_object('kind', 'charge_curve', 'start_soc', v_vehicle.current_soc, 'target_soc', v_target_soc,
      'charger_kw', v_charger.max_kw, 'vehicle_kw', v_vehicle.inlet_max_kw,
      'pack_kwh', v_vehicle.battery_capacity_kwh, 'battery_temp_c', ROUND(v_battery_temp::numeric, 1),
      'soh_pct', COALESCE(v_vehicle.soh, 95)),
    'twin_charge_orchestrator');

  RETURN v_session_id;
END;
$function$

