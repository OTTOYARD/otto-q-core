-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: ec6fc85ada1fa81c6e75a9313994b182
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_site_energy(p_depot_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed             BIGINT;
  v_salt             TEXT;
  v_solar_ac_kw      NUMERIC := 0;
  v_bess_kw          NUMERIC := 0;
  v_chargers_kw      NUMERIC;
  v_building_kw      NUMERIC;
  v_grid_kw          NUMERIC;
  v_ambient          NUMERIC := 22;
  v_dcfc_cap_kw      NUMERIC := 1800;
  v_service_cap_kw   NUMERIC := 2500;
  v_dcfc_load_kw     NUMERIC := 0;
  v_dr_cap_kw        NUMERIC;
  v_dr_call_id       UUID;
  v_tariff_label     TEXT;
  v_tariff_rate      NUMERIC;
  v_snap_id          UUID := gen_random_uuid();
  v_peak_15min       NUMERIC;
BEGIN
  v_seed := abs(hashtextextended(p_depot_id::text || p_sim_clock_now::text || 'site', 11));
  v_salt := to_char(p_sim_clock_now, 'YYYYMMDD-HH24MISS');

  SELECT ambient_temp_c INTO v_ambient
    FROM ottoq_weather_snapshots
   WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now
   ORDER BY sim_clock_at DESC LIMIT 1;
  v_ambient := COALESCE(v_ambient, 22);

  WITH latest AS (
    SELECT MAX(sim_clock_at) AS t FROM ottoq_solar_output
     WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now
  )
  SELECT COALESCE(SUM(ac_power_kw), 0) INTO v_solar_ac_kw
    FROM ottoq_solar_output, latest
   WHERE depot_id = p_depot_id AND sim_clock_at = latest.t;

  SELECT COALESCE(SUM(current_power_kw), 0) INTO v_bess_kw
    FROM ottoq_bess_units WHERE depot_id = p_depot_id;

  v_chargers_kw := ottoq_sim_compute_charger_load_kw(p_depot_id, p_sim_clock_now);
  v_building_kw := ottoq_sim_compute_building_load_kw(p_depot_id, p_sim_clock_now, v_ambient, v_seed, v_salt);

  SELECT COALESCE(SUM(((cs.last_meter_value->>'power_kw'))::numeric), 0) INTO v_dcfc_load_kw
    FROM ocpp_sessions cs
    JOIN stalls s ON s.id = cs.stall_id
   WHERE cs.depot_id = p_depot_id
     AND s.stall_type::text = 'dcfc'
     AND cs.status = 'active'::ocpp_session_status
     AND cs.started_at <= p_sim_clock_now
     AND (cs.ended_at IS NULL OR cs.ended_at >= p_sim_clock_now);

  v_grid_kw := v_chargers_kw + v_building_kw - v_solar_ac_kw + v_bess_kw;

  SELECT dr_call_id, required_load_cap_kw INTO v_dr_call_id, v_dr_cap_kw
    FROM ottoq_dr_calls
   WHERE depot_id = p_depot_id AND call_status = 'active'
     AND expires_at > p_sim_clock_now LIMIT 1;

  SELECT out_label, out_rate_usd_kwh INTO v_tariff_label, v_tariff_rate
    FROM ottoq_sim_current_tariff(p_depot_id, p_sim_clock_now);

  -- 15-min peak from THIS run's trailing snapshots (sim_run scoped → no cross-run bleed)
  SELECT COALESCE(MAX(grid_import_kw - grid_export_kw), 0) INTO v_peak_15min
    FROM site_energy_snapshots
   WHERE depot_id = p_depot_id
     AND timestamp >= p_sim_clock_now - INTERVAL '15 minutes'
     AND timestamp <= p_sim_clock_now
     AND (CASE WHEN p_sim_run_id IS NULL THEN TRUE ELSE sim_run_id = p_sim_run_id END);
  v_peak_15min := GREATEST(v_peak_15min, v_grid_kw);

  INSERT INTO site_energy_snapshots (
    id, depot_id, timestamp,
    grid_import_kw, grid_export_kw,
    solar_generation_kw, bess_output_kw,
    total_ev_charging_kw, building_load_kw,
    lighting_load_kw,
    peak_demand_kw_15min, billing_period_peak_kw,
    current_tariff_label, current_rate_per_kwh
  ) VALUES (
    v_snap_id, p_depot_id, p_sim_clock_now,
    ROUND(GREATEST(0, v_grid_kw)::numeric, 1),
    ROUND(GREATEST(0, -v_grid_kw)::numeric, 1),
    ROUND(v_solar_ac_kw::numeric, 1),
    ROUND(-v_bess_kw::numeric, 1),
    ROUND(v_chargers_kw::numeric, 1),
    ROUND(v_building_kw::numeric, 1),
    ROUND(0::numeric, 1),
    ROUND(v_peak_15min::numeric, 1),
    ROUND(GREATEST(v_peak_15min,
       (SELECT COALESCE(MAX(billing_period_peak_kw), 0)
          FROM site_energy_snapshots
         WHERE depot_id = p_depot_id
           AND timestamp >= date_trunc('month', p_sim_clock_now)
           AND (CASE WHEN p_sim_run_id IS NULL THEN TRUE ELSE sim_run_id = p_sim_run_id END)))::numeric, 1),
    (CASE
       WHEN v_tariff_label IN ('peak','super_peak')                THEN 'on_peak'
       WHEN v_tariff_label IN ('off_peak','mid_peak','on_peak',
                               'super_off_peak')                   THEN v_tariff_label
       ELSE 'mid_peak'
     END)::tariff_label,
    v_tariff_rate);

  IF v_dcfc_load_kw > v_dcfc_cap_kw THEN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='site_energy_balance',
      p_event_type:='twin.dcfc_cap_exceeded', p_entity_type:='depot', p_entity_id:=p_depot_id,
      p_payload:=jsonb_build_object('dcfc_kw', v_dcfc_load_kw, 'cap_kw', v_dcfc_cap_kw),
      p_severity:='critical', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  ELSIF v_dcfc_load_kw > v_dcfc_cap_kw * 0.90 THEN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='site_energy_balance',
      p_event_type:='twin.dcfc_cap_approached', p_entity_type:='depot', p_entity_id:=p_depot_id,
      p_payload:=jsonb_build_object('dcfc_kw', v_dcfc_load_kw, 'cap_kw', v_dcfc_cap_kw,
                                    'utilization_pct', ROUND(v_dcfc_load_kw/v_dcfc_cap_kw*100, 1)),
      p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  END IF;

  IF v_grid_kw > v_service_cap_kw THEN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='site_energy_balance',
      p_event_type:='twin.service_cap_exceeded', p_entity_type:='depot', p_entity_id:=p_depot_id,
      p_payload:=jsonb_build_object('grid_kw', v_grid_kw, 'cap_kw', v_service_cap_kw),
      p_severity:='critical', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  ELSIF v_grid_kw > v_service_cap_kw * 0.90 THEN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='site_energy_balance',
      p_event_type:='twin.service_cap_approached', p_entity_type:='depot', p_entity_id:=p_depot_id,
      p_payload:=jsonb_build_object('grid_kw', v_grid_kw, 'cap_kw', v_service_cap_kw),
      p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  END IF;

  IF v_dr_call_id IS NOT NULL THEN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='site_energy_balance',
      p_event_type:='twin.dr_compliance', p_entity_type:='depot', p_entity_id:=p_depot_id,
      p_payload:=jsonb_build_object('dr_call_id', v_dr_call_id, 'required_cap_kw', v_dr_cap_kw,
        'actual_grid_kw', v_grid_kw, 'compliant', v_grid_kw <= v_dr_cap_kw,
        'overage_kw', GREATEST(0, v_grid_kw - v_dr_cap_kw)),
      p_severity:=CASE WHEN v_grid_kw > v_dr_cap_kw THEN 'warning' ELSE 'info' END,
      p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  END IF;

  RETURN v_snap_id;
END;
$function$

