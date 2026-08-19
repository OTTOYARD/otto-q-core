-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: 617a867d3686400f45b20485fca77445
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_grid(p_depot_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed           BIGINT;
  v_salt           TEXT;
  v_hour           INTEGER;
  v_dow            INTEGER;
  v_demand_mw      NUMERIC;
  v_lmp            NUMERIC;
  v_carbon         NUMERIC;
  v_tariff         RECORD;
  v_volt           RECORD;
  v_freq           RECORD;
  v_ambient        NUMERIC;
  v_dr_call_id     UUID;
  v_dr_call        ottoq_dr_calls%ROWTYPE;
  v_snap_id        UUID := gen_random_uuid();
  v_supply_mw      NUMERIC;
  v_reserve_pct    NUMERIC;
  v_shape          NUMERIC;
  v_dr_cap         NUMERIC;
  v_local_load_kw  NUMERIC;
  v_eng_cap        NUMERIC;
  v_load_util      NUMERIC;
  v_load_bo_mult   NUMERIC;
BEGIN
  v_seed  := abs(hashtextextended(p_depot_id::text || p_sim_clock_now::text || 'grid', 31));
  v_salt  := to_char(p_sim_clock_now, 'YYYYMMDD-HH24');
  v_hour  := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_dow   := EXTRACT(DOW  FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  SELECT ambient_temp_c INTO v_ambient
    FROM ottoq_weather_snapshots
   WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now
   ORDER BY sim_clock_at DESC LIMIT 1;
  v_ambient := COALESCE(v_ambient, 22);

  SELECT (profile_data->>(v_hour::text))::numeric INTO v_shape
    FROM ottoq_calibration_profiles
   WHERE profile_name = 'hourly_grid_demand_shape' LIMIT 1;
  v_shape := COALESCE(v_shape, 1.0);
  v_demand_mw := LEAST(40000, GREATEST(10000, COALESCE(
    ottoq_twin_deal(p_sim_run_id, 'grid_demand_mw', 'grid', p_sim_clock_now,
      (p_sim_clock_now::date - DATE '2020-01-01'), 0),
    21000))) * v_shape
    * ottoq_profile_rate_mult(p_sim_run_id, 'grid_demand_mw');
  v_demand_mw := v_demand_mw * (1
    + COALESCE((ottoq_twin_climate_stress(p_sim_run_id, (p_sim_clock_now::date - DATE '2020-01-01'))->>'heat_stress')::numeric,0) * 0.15
    + COALESCE((ottoq_twin_climate_stress(p_sim_run_id, (p_sim_clock_now::date - DATE '2020-01-01'))->>'cold_stress')::numeric,0) * 0.12);

  v_reserve_pct := 0.12 + ottoq_sim_seeded_random(v_seed, 'rm') * 0.10
                 - GREATEST(0, v_ambient - 32) * 0.005;
  v_supply_mw   := v_demand_mw * (1 + v_reserve_pct);

  v_lmp    := ottoq_sim_sample_lmp_usd_mwh(v_seed, v_salt, v_hour, v_ambient, v_dow, p_sim_run_id);
  v_lmp    := GREATEST(8, ottoq_apply_profile(p_sim_run_id, 'lmp_usd_mwh', v_lmp, 45));
  v_carbon := ottoq_sim_sample_carbon_intensity(v_seed, v_salt, v_hour);
  v_carbon := GREATEST(50, ottoq_apply_profile(p_sim_run_id, 'carbon_intensity', v_carbon, 380));

  SELECT * INTO v_tariff FROM ottoq_sim_current_tariff(p_depot_id, p_sim_clock_now);

  -- FID-B: local feeder load-responsiveness (SAME engineering cap EN.001 enforces)
  v_local_load_kw := ottoq_sim_compute_charger_load_kw(p_depot_id, p_sim_clock_now);
  SELECT dcfc_max_concurrent_kw * (1 - COALESCE(dcfc_safety_margin_pct, 10.0)/100.0)
    INTO v_eng_cap FROM depots WHERE id = p_depot_id;
  v_load_util := CASE WHEN COALESCE(v_eng_cap, 0) > 0 THEN v_local_load_kw / v_eng_cap ELSE 0 END;
  v_load_bo_mult := LEAST(3.0, 1 + GREATEST(0, v_load_util - 0.70) * 6.0);

  SELECT * INTO v_volt FROM ottoq_sim_sample_voltage_event(v_seed, v_salt,
    ottoq_profile_rate_mult(p_sim_run_id, 'brownout_rate') * v_load_bo_mult);
  SELECT * INTO v_freq FROM ottoq_sim_sample_frequency_hz(v_seed, v_salt,
    ottoq_profile_rate_mult(p_sim_run_id, 'freq_excursion_rate'));

  v_dr_call_id := ottoq_sim_maybe_ignite_dr_call(p_depot_id, p_sim_run_id, p_sim_clock_now,
                                                 v_ambient, v_seed);
  IF v_dr_call_id IS NOT NULL THEN
    SELECT * INTO v_dr_call FROM ottoq_dr_calls WHERE dr_call_id = v_dr_call_id;
    v_dr_cap := v_dr_call.required_load_cap_kw;
  END IF;

  UPDATE ottoq_dr_calls
     SET call_status = 'cleared', cleared_at = p_sim_clock_now
   WHERE depot_id = p_depot_id AND call_status = 'active'
     AND expires_at <= p_sim_clock_now;

  INSERT INTO ottoq_grid_snapshots (
    snapshot_id, depot_id, sim_run_id, sim_clock_at,
    region_demand_mw, region_supply_mw, reserve_margin_pct,
    generation_mix, carbon_intensity_gco2_per_kwh,
    voltage_v, frequency_hz, voltage_status, frequency_status,
    lmp_usd_per_mwh, current_tariff_label, current_rate_usd_per_kwh,
    active_dr_call_id, dr_required_load_cap_kw,
    data_source
  ) VALUES (
    v_snap_id, p_depot_id, p_sim_run_id, p_sim_clock_now,
    ROUND(v_demand_mw::numeric, 0), ROUND(v_supply_mw::numeric, 0),
    ROUND(v_reserve_pct::numeric, 4),
    jsonb_build_object('nuclear', 0.40, 'gas', 0.25, 'coal', 0.20, 'hydro', 0.10, 'solar', 0.05),
    ROUND(v_carbon::numeric, 1),
    ROUND(v_volt.out_voltage_v::numeric, 1),
    ROUND(v_freq.out_freq_hz::numeric, 3),
    v_volt.out_status,
    v_freq.out_status,
    ROUND(v_lmp::numeric, 2),
    v_tariff.out_label,
    ROUND(v_tariff.out_rate_usd_kwh::numeric, 4),
    v_dr_call_id, v_dr_cap,
    'twin');

  IF v_volt.out_status IN ('sag','brownout','swell') THEN
    PERFORM ottoq_record_event(
      p_actor_type    := 'external_sensor',
      p_actor_id      := 'grid_meter',
      p_event_type    := CASE v_volt.out_status
                           WHEN 'sag' THEN 'twin.grid_voltage_sag'
                           WHEN 'brownout' THEN 'twin.grid_brownout'
                           ELSE 'twin.grid_voltage_sag' END,
      p_entity_type   := 'depot',
      p_entity_id     := p_depot_id,
      p_payload       := jsonb_build_object(
        'voltage_v', v_volt.out_voltage_v,
        'status',    v_volt.out_status,
        'lmp_usd_mwh', v_lmp,
        'demand_mw', v_demand_mw,
        'local_load_kw', ROUND(v_local_load_kw::numeric, 1),
        'local_load_util', ROUND(v_load_util::numeric, 3),
        'load_brownout_mult', ROUND(v_load_bo_mult::numeric, 2)),
      p_severity      := CASE v_volt.out_status WHEN 'brownout' THEN 'critical' ELSE 'warning' END,
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  END IF;

  IF v_freq.out_status = 'excursion' THEN
    PERFORM ottoq_record_event(
      p_actor_type    := 'external_sensor',
      p_actor_id      := 'grid_meter',
      p_event_type    := 'twin.grid_frequency_excursion',
      p_entity_type   := 'depot',
      p_entity_id     := p_depot_id,
      p_payload       := jsonb_build_object(
        'frequency_hz', v_freq.out_freq_hz,
        'deviation_hz', ABS(v_freq.out_freq_hz - 60.0)),
      p_severity      := 'warning',
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  END IF;

  RETURN v_snap_id;
END;
$function$

