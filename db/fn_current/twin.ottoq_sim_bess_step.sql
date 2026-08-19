-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: e1e1ae535e573d21997f51b8f968f962
CREATE OR REPLACE FUNCTION twin.ottoq_sim_bess_step(p_bess_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric, p_target_power_kw numeric, p_ambient_temp_c numeric DEFAULT NULL::numeric, p_dispatch_reason text DEFAULT 'manual'::text)
 RETURNS TABLE(out_actual_power_kw numeric, out_soc_pct_new numeric, out_temp_c_new numeric, out_soh_pct_new numeric, out_thermal_derated boolean, out_soc_limited boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v              ottoq_bess_units%ROWTYPE;
  v_seed         BIGINT;
  v_max_kw       NUMERIC;
  v_actual_kw    NUMERIC;
  v_kwh_delta    NUMERIC;
  v_one_way_eff  NUMERIC;
  v_thermal_derated BOOLEAN := FALSE;
  v_soc_limited     BOOLEAN := FALSE;
  v_new_soc_kwh  NUMERIC;
  v_new_soc_pct  NUMERIC;
  v_aux_load     NUMERIC;
  v_aux_noise    NUMERIC;
  v_new_temp     NUMERIC;
  v_target_temp  NUMERIC;
  v_thermal_lag  NUMERIC := 0.18;            -- per tick (~5 min tau time)
  v_kwh_through  NUMERIC;
  v_delta_soh    NUMERIC;
  v_ambient      NUMERIC;
  v_thermal_noise NUMERIC;
  v_bms_margin   NUMERIC;
BEGIN
  SELECT * INTO v FROM ottoq_bess_units WHERE bess_id = p_bess_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'bess % not found', p_bess_id;
  END IF;

  v_seed   := abs(hashtextextended(p_bess_id::text || p_sim_clock_now::text, 23));
  v_ambient := COALESCE(p_ambient_temp_c, v.current_temperature_c, 22);
  v_one_way_eff := SQRT(COALESCE(v.roundtrip_efficiency_pct, 0.96));   -- per-direction

  -- BMS safety margin: 95-100% of theoretical max (jittered)
  v_bms_margin := 0.95 + ottoq_sim_seeded_random(v_seed, 'bms') * 0.05;

  IF p_target_power_kw > 0 THEN
    v_max_kw    := ottoq_sim_bess_compute_max_power_kw(p_bess_id, 'charge', v.current_temperature_c) * v_bms_margin;
    v_actual_kw := LEAST(p_target_power_kw, v_max_kw);
    IF v.current_temperature_c > 45 OR v.current_temperature_c < 5 THEN
      v_thermal_derated := TRUE;
    END IF;
    IF v.current_soc_pct >= v.soc_max_ceiling_pct - 0.05 THEN
      v_actual_kw    := 0;
      v_soc_limited  := TRUE;
    END IF;
  ELSIF p_target_power_kw < 0 THEN
    v_max_kw    := ottoq_sim_bess_compute_max_power_kw(p_bess_id, 'discharge', v.current_temperature_c) * v_bms_margin;
    v_actual_kw := -LEAST(ABS(p_target_power_kw), v_max_kw);
    IF v.current_temperature_c > 45 OR v.current_temperature_c < 5 THEN
      v_thermal_derated := TRUE;
    END IF;
    IF v.current_soc_pct <= v.soc_min_floor_pct + 0.05 THEN
      v_actual_kw    := 0;
      v_soc_limited  := TRUE;
    END IF;
  ELSE
    v_actual_kw := 0;
  END IF;

  -- Apply round-trip efficiency
  -- Charging: kWh stored = power_in × eff
  -- Discharging: kWh removed from pack = |power_out| / eff (need to pull more from pack to deliver)
  v_kwh_delta := CASE
    WHEN v_actual_kw > 0 THEN v_actual_kw * (p_tick_minutes / 60.0) * v_one_way_eff
    WHEN v_actual_kw < 0 THEN v_actual_kw * (p_tick_minutes / 60.0) / v_one_way_eff
    ELSE 0 END;

  -- Auxiliary load (BMS + HVAC + comms) — always pulls from pack
  v_aux_noise  := 0.85 + ottoq_sim_seeded_random(v_seed, 'aux') * 0.30;
  v_aux_load   := v.auxiliary_load_kw * v_aux_noise;
  v_kwh_delta  := v_kwh_delta - (v_aux_load * (p_tick_minutes / 60.0));

  v_new_soc_kwh := v.current_soc_kwh + v_kwh_delta;
  v_new_soc_kwh := GREATEST(0, LEAST(v.capacity_kwh, v_new_soc_kwh));
  v_new_soc_pct := v_new_soc_kwh / v.capacity_kwh * 100.0;

  -- Thermal model: heat from |P| × (1 - one_way_eff)
  v_target_temp := v_ambient + 3.0 + (ABS(v_actual_kw) / v.max_charge_kw) * 12.0;
  v_thermal_noise := (ottoq_sim_seeded_random(v_seed, 'noise') - 0.5) * 3.0;
  v_new_temp := v.current_temperature_c
              + (v_target_temp - v.current_temperature_c) * v_thermal_lag
              + v_thermal_noise;

  -- Throughput in kWh (for SOH calc)
  v_kwh_through := ABS(v_actual_kw) * (p_tick_minutes / 60.0);
  v_delta_soh := ottoq_sim_bess_apply_degradation(p_bess_id, p_tick_minutes, v_kwh_through, v_seed);

  -- Persist unit state
  UPDATE ottoq_bess_units
     SET current_soc_kwh           = ROUND(v_new_soc_kwh::numeric, 2),
         current_soc_pct           = ROUND(v_new_soc_pct::numeric, 2),
         current_temperature_c     = ROUND(v_new_temp::numeric, 2),
         current_power_kw          = ROUND(v_actual_kw::numeric, 2),
         current_state             = CASE
                                       WHEN v_actual_kw > 0  THEN 'charging'
                                       WHEN v_actual_kw < 0  THEN 'discharging'
                                       ELSE 'idle' END,    -- 'idle' is the unit-level vocabulary
         current_state_updated_at  = p_sim_clock_now,
         last_heartbeat_at         = p_sim_clock_now,
         updated_at                = NOW()
   WHERE bess_id = p_bess_id;

  -- Snapshot to time-series
  INSERT INTO bess_snapshots (
    id, depot_id, system_id, timestamp, soc_percent,
    capacity_kwh, usable_capacity_kwh, current_output_kw,
    max_discharge_kw, max_charge_kw,
    grid_import_kw, grid_export_kw,
    temperature_c, health_percent, cycle_count, status
  ) VALUES (
    gen_random_uuid(), v.depot_id, v.bess_id, p_sim_clock_now, ROUND(v_new_soc_pct::numeric, 2),
    v.capacity_kwh,
    v.capacity_kwh * (v.soc_max_ceiling_pct - v.soc_min_floor_pct) / 100,
    ROUND(v_actual_kw::numeric, 2),
    v.max_discharge_kw, v.max_charge_kw,
    0, 0,                                                   -- grid linkage in A.5.4
    ROUND(v_new_temp::numeric, 2),
    ROUND(LEAST(100, v.current_soh_pct + v_delta_soh)::numeric, 3),
    ROUND((v.current_cycle_count + (v_kwh_through / (2 * v.capacity_kwh)))::numeric, 4),
    (CASE WHEN v_actual_kw > 0 THEN 'charging'
          WHEN v_actual_kw < 0 THEN 'discharging'
          ELSE 'standby' END)::bess_status
  );

  -- Emit events for noteworthy conditions
  IF v_thermal_derated THEN
    PERFORM ottoq_record_event(
      p_actor_type    := 'bess_controller',
      p_actor_id      := v.bess_identifier,
      p_event_type    := 'twin.bess_thermal_derate',
      p_entity_type   := 'depot',
      p_entity_id     := v.depot_id,
      p_payload       := jsonb_build_object(
        'temp_c', v.current_temperature_c,
        'requested_kw', p_target_power_kw,
        'actual_kw', v_actual_kw),
      p_severity      := 'warning',
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  END IF;

  IF v_soc_limited THEN
    PERFORM ottoq_record_event(
      p_actor_type    := 'bess_controller',
      p_actor_id      := v.bess_identifier,
      p_event_type    := 'twin.bess_soc_limit',
      p_entity_type   := 'depot',
      p_entity_id     := v.depot_id,
      p_payload       := jsonb_build_object(
        'soc_pct', v.current_soc_pct,
        'direction', CASE WHEN p_target_power_kw > 0 THEN 'charge' ELSE 'discharge' END),
      p_severity      := 'warning',
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type    := 'bess_controller',
    p_actor_id      := v.bess_identifier,
    p_event_type    := 'twin.bess_dispatch',
    p_entity_type   := 'depot',
    p_entity_id     := v.depot_id,
    p_payload       := jsonb_build_object(
      'target_kw',      p_target_power_kw,
      'actual_kw',      v_actual_kw,
      'soc_pct_after',  ROUND(v_new_soc_pct::numeric, 2),
      'soh_pct_after',  ROUND(LEAST(100, v.current_soh_pct + v_delta_soh)::numeric, 3),
      'temp_c_after',   ROUND(v_new_temp::numeric, 2),
      'reason',         p_dispatch_reason),
    p_severity      := 'info',
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id);

  out_actual_power_kw := ROUND(v_actual_kw::numeric, 2);
  out_soc_pct_new     := ROUND(v_new_soc_pct::numeric, 2);
  out_temp_c_new      := ROUND(v_new_temp::numeric, 2);
  out_soh_pct_new     := ROUND(LEAST(100, v.current_soh_pct + v_delta_soh)::numeric, 3);
  out_thermal_derated := v_thermal_derated;
  out_soc_limited     := v_soc_limited;
  RETURN NEXT;
END;
$function$

