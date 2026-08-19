-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: d7246f7b7274c9cd607e127d6ba86253
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_weather_and_solar(p_depot_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed             BIGINT;
  v_salt             TEXT;
  v_depot            RECORD;
  v_lat              NUMERIC;
  v_lng              NUMERIC;
  v_elev_deg         NUMERIC;
  v_azim_deg         NUMERIC;
  v_clear_ghi        NUMERIC;
  v_cloud_pct        NUMERIC;
  v_ambient_c        NUMERIC;
  v_wind_kmh         NUMERIC;
  v_wind_dir_deg     NUMERIC;
  v_humidity_pct     NUMERIC;
  v_precip_state     TEXT;
  v_precip_mm        NUMERIC;
  v_prev_precip      TEXT;
  v_actual_ghi       NUMERIC;
  v_dni              NUMERIC;
  v_dhi              NUMERIC;
  v_poa_avg          NUMERIC;
  v_label            TEXT;
  v_weather_id       UUID := gen_random_uuid();
  v_is_day           BOOLEAN;
  v_hour_of_day      INTEGER;
  v_canopy           RECORD;
  v_canopy_poa       NUMERIC;
  v_cell_temp        NUMERIC;
  v_new_soiling      NUMERIC;
  v_dc_kw            NUMERIC;
  v_ac_kw            NUMERIC;
  v_clipped          BOOLEAN;
  v_blip             BOOLEAN;
  v_inv_eff          NUMERIC := 0.96;
BEGIN
  -- Depot location
  SELECT origin_lat, origin_lng INTO v_lat, v_lng
    FROM depots WHERE id = p_depot_id;
  IF NOT FOUND THEN
    -- Fall back to Nashville flagship
    v_lat := 36.1397; v_lng := -86.7728;
  END IF;

  v_seed        := abs(hashtextextended(p_depot_id::text || p_sim_clock_now::text || 'wx', 17));
  v_salt        := to_char(p_sim_clock_now, 'YYYYMMDD-HH24MISS');
  v_hour_of_day := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  -- Sun geometry
  v_elev_deg := ottoq_sim_solar_elevation_deg(p_sim_clock_now, v_lat, v_lng);
  -- Azimuth (simplified — symmetric around solar noon, south-positive)
  v_azim_deg := 180 + 15.0 * (v_hour_of_day - 12);
  v_is_day   := v_elev_deg > 0;

  -- Clear-sky GHI
  v_clear_ghi := ottoq_sim_clear_sky_ghi_wm2(v_elev_deg);

  -- Sample atmospheric state
  v_cloud_pct := COALESCE(ottoq_twin_deal(p_sim_run_id, 'cloud_cover_pct', 'global', p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), ottoq_sim_sample_cloud_pct(v_seed, v_salt, v_hour_of_day));
  -- A.8: shape through the run's variability profile (cloud has no calibration
  -- row, so pass explicit mean 50 so Chaos spread widens around the real center),
  -- then re-clamp to a valid 0-100 range.
  v_cloud_pct := GREATEST(0, LEAST(100,
    ottoq_apply_profile(p_sim_run_id, 'cloud_cover_pct', v_cloud_pct, 50)));

  -- per-DAY ambient regime via the lifespan card engine: one draw per sim-day from the real
  -- NOAA distribution, HELD across the day; the diurnal swing below adds intra-day variation.
  v_ambient_c := COALESCE(
    ottoq_twin_deal(p_sim_run_id, 'ambient_temp_c', 'global', p_sim_clock_now,
      (p_sim_clock_now::date - DATE '2020-01-01'), 0,
      'month:' || to_char(p_sim_clock_now AT TIME ZONE 'America/Chicago', 'MM')),
    22);

  -- Feed-agent ambient_temp_c: AR(1) day-to-day persistence (NOAA-computed
  -- phi=0.72). Blend the fresh marginal draw with yesterday's realized
  -- anomaly; variance-preserving; card value updated so tomorrow chains off
  -- realized state. Idempotent via the ar1 meta flag.
  DECLARE
    v_plan_t jsonb := ottoq_feed_plan('ambient_temp_c');
    v_phi numeric; v_mu numeric; v_mu_y numeric; v_yest numeric;
    v_mo text; v_mo_y text; v_blend numeric; v_meta_flag text;
    v_day_n int := (p_sim_clock_now::date - DATE '2020-01-01');
  BEGIN
    IF v_plan_t IS NOT NULL THEN
      SELECT meta->>'ar1' INTO v_meta_flag FROM ottoq_variability_cards
       WHERE sim_run_id = p_sim_run_id AND var_key = 'ambient_temp_c'
         AND scope_instance = 'global' AND bucket_key = 'day:' || v_day_n;
      IF v_meta_flag IS NULL THEN
        v_phi  := COALESCE((v_plan_t->>'ar1_phi')::numeric, 0.72);
        v_mo   := to_char(p_sim_clock_now AT TIME ZONE 'America/Chicago', 'MM');
        v_mo_y := to_char((p_sim_clock_now - interval '1 day') AT TIME ZONE 'America/Chicago', 'MM');
        v_mu   := (v_plan_t->'monthly'->v_mo->>'mean_c')::numeric;
        v_mu_y := COALESCE((v_plan_t->'monthly'->v_mo_y->>'mean_c')::numeric, v_mu);
        SELECT value INTO v_yest FROM ottoq_variability_cards
         WHERE sim_run_id = p_sim_run_id AND var_key = 'ambient_temp_c'
           AND scope_instance = 'global' AND bucket_key = 'day:' || (v_day_n - 1);
        IF v_yest IS NOT NULL AND v_mu IS NOT NULL THEN
          v_blend := v_mu + v_phi * (v_yest - v_mu_y)
                   + sqrt(1 - v_phi * v_phi) * (v_ambient_c - v_mu);
          v_blend := LEAST(GREATEST(v_blend, (v_plan_t->'monthly'->v_mo->>'record_lo')::numeric),
                            (v_plan_t->'monthly'->v_mo->>'record_hi')::numeric);
          UPDATE ottoq_variability_cards
             SET value = round(v_blend, 2),
                 meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object('ar1', true, 'raw_draw', round(v_ambient_c, 2))
           WHERE sim_run_id = p_sim_run_id AND var_key = 'ambient_temp_c'
             AND scope_instance = 'global' AND bucket_key = 'day:' || v_day_n;
          v_ambient_c := v_blend;
        ELSE
          UPDATE ottoq_variability_cards
             SET meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object('ar1', true)
           WHERE sim_run_id = p_sim_run_id AND var_key = 'ambient_temp_c'
             AND scope_instance = 'global' AND bucket_key = 'day:' || v_day_n;
        END IF;
      END IF;
    END IF;
  END;

  -- Add diurnal temperature swing: ±5°C peak-to-peak around the calibrated mean
  v_ambient_c := v_ambient_c
               + COALESCE((ottoq_feed_plan('ambient_temp_c')->'monthly'
                   ->to_char(p_sim_clock_now AT TIME ZONE 'America/Chicago', 'MM')->>'diurnal_half_c')::numeric, 5.0)
                 * SIN(RADIANS(15.0 * (v_hour_of_day - 14)));   -- peak ~2 PM

  -- A.8: shape ambient through the profile (uses calibrated mean 23.24 for
  -- variance widening; honors shift/floor/ceiling from heat_wave/winter_storm).
  v_ambient_c := ottoq_apply_profile(p_sim_run_id, 'ambient_temp_c', v_ambient_c);

  v_wind_kmh := COALESCE(
    ottoq_twin_deal(p_sim_run_id, 'wind_speed_kmh', 'global', p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0),
    ottoq_sample_calibrated('wind_speed_kmh', 'global', v_seed, 'wind:' || v_salt),
    7);
  -- A.8: shape wind (calibration mean 7.63); clamp non-negative.
  v_wind_kmh := GREATEST(0, ottoq_apply_profile(p_sim_run_id, 'wind_speed_kmh', v_wind_kmh));
  v_wind_dir_deg := ottoq_sim_seeded_random(v_seed, 'wd') * 360;
  -- (A.10 humidity shaping applied just below, after the base clamp)
  v_humidity_pct := 40 + ottoq_sim_seeded_random(v_seed, 'rh') * 50
                  + (v_cloud_pct - 50) * 0.2;
  v_humidity_pct := GREATEST(10, LEAST(100,
    ottoq_apply_profile(p_sim_run_id, 'humidity_pct', v_humidity_pct, 65)));

  -- Get prev precip state
  SELECT precip_state INTO v_prev_precip
    FROM ottoq_weather_snapshots
   WHERE depot_id = p_depot_id
     AND sim_clock_at < p_sim_clock_now
   ORDER BY sim_clock_at DESC LIMIT 1;
  v_prev_precip := COALESCE(v_prev_precip, 'dry');

  SELECT * INTO v_precip_state, v_precip_mm
    FROM ottoq_sim_sample_precip_state(v_seed, v_salt, v_prev_precip, v_cloud_pct,
           ottoq_profile_rate_mult(p_sim_run_id, 'precip'),
           p_sim_run_id, p_sim_clock_now);   -- feed-agent: daily-budget disaggregation

  -- rain implies overcast: raise cloud before GHI attenuation (computed below)
  IF v_precip_mm > 0 THEN
    v_cloud_pct := GREATEST(v_cloud_pct, 75);
  END IF;

  -- Actual GHI after cloud attenuation
  v_actual_ghi := ottoq_sim_cloud_attenuated_ghi(v_clear_ghi, v_cloud_pct);
  v_dni        := v_actual_ghi * 0.7;     -- approximation
  v_dhi        := v_actual_ghi * 0.3;

  -- POA (depot-level average, south-facing 30° tilt) for snapshot record
  v_poa_avg := ottoq_sim_poa_irradiance(v_actual_ghi, v_elev_deg, 30, 180, v_azim_deg);

  -- Conditions label
  v_label := CASE
    WHEN v_precip_state IN ('storm','heavy_rain') THEN 'storm'
    WHEN v_precip_state IN ('rain','drizzle')     THEN 'rain'
    WHEN v_cloud_pct > 80                          THEN 'overcast'
    WHEN v_cloud_pct > 40                          THEN 'partly_cloudy'
    WHEN v_humidity_pct > 90 AND v_ambient_c < 15  THEN 'foggy'
    ELSE                                                 'clear' END;

  -- Insert weather snapshot
  INSERT INTO ottoq_weather_snapshots (
    snapshot_id, depot_id, sim_run_id, sim_clock_at,
    solar_elevation_deg, solar_azimuth_deg, air_mass,
    ambient_temp_c, cloud_cover_pct, wind_speed_kmh, wind_direction_deg,
    relative_humidity_pct, precip_mm_per_hr, precip_state,
    ghi_wm2, dni_wm2, dhi_wm2, poa_wm2,
    conditions_label, is_daytime, data_source
  ) VALUES (
    v_weather_id, p_depot_id, p_sim_run_id, p_sim_clock_now,
    ROUND(v_elev_deg::numeric, 2), ROUND(v_azim_deg::numeric, 2),
    CASE WHEN v_elev_deg > 0 THEN ROUND((1.0 / SIN(RADIANS(v_elev_deg)))::numeric, 2) ELSE NULL END,
    ROUND(v_ambient_c::numeric, 1), ROUND(v_cloud_pct::numeric, 1),
    ROUND(v_wind_kmh::numeric, 1), ROUND(v_wind_dir_deg::numeric, 0),
    ROUND(v_humidity_pct::numeric, 1), ROUND(v_precip_mm::numeric, 2), v_precip_state,
    ROUND(v_actual_ghi::numeric, 1), ROUND(v_dni::numeric, 1), ROUND(v_dhi::numeric, 1),
    ROUND(v_poa_avg::numeric, 1),
    v_label, v_is_day, 'twin');

  -- Emit anomaly if storm or extreme temp
  IF v_label = 'storm' OR v_ambient_c > 38 OR v_ambient_c < -10 THEN
    PERFORM ottoq_record_event(
      p_actor_type    := 'external_sensor',
      p_actor_id      := 'twin_weather_generator',
      p_event_type    := 'twin.weather_anomaly',
      p_entity_type   := 'depot',
      p_entity_id     := p_depot_id,
      p_payload       := jsonb_build_object(
        'label', v_label, 'temp_c', v_ambient_c, 'precip_mm_hr', v_precip_mm,
        'wind_kmh', v_wind_kmh, 'cloud_pct', v_cloud_pct),
      p_severity      := 'warning',
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  END IF;

  -- ----- Now compute per-canopy solar output -----
  FOR v_canopy IN SELECT * FROM ottoq_canopy_state WHERE depot_id = p_depot_id LOOP

    -- Soiling: drifts down ~0.05% per hour on dry days, resets toward 1.0 after rain
    IF v_precip_mm >= 1.0 THEN
      v_new_soiling := LEAST(1.00, v_canopy.current_soiling + 0.03);
    ELSE
      v_new_soiling := GREATEST(0.85,
        v_canopy.current_soiling - 0.0005 * (1 + ottoq_sim_seeded_random(v_seed, 'so:' || v_canopy.canopy_code)));
    END IF;
    -- A.10: solar_soiling knob — shape the soiling derate (mean 1.0 = clean), clamp valid range
    v_new_soiling := GREATEST(0.40, LEAST(1.00,
      ottoq_apply_profile(p_sim_run_id, 'solar_soiling', v_new_soiling, 1.0)));

    v_canopy_poa := ottoq_sim_poa_irradiance(
      v_actual_ghi, v_elev_deg, v_canopy.tilt_deg, v_canopy.azimuth_deg, v_azim_deg);
    v_cell_temp  := ottoq_sim_cell_temp_c(v_ambient_c, v_canopy_poa, v_wind_kmh);

    v_dc_kw := ottoq_sim_pv_dc_power_kw(
      v_canopy.nameplate_dc_kw, v_canopy_poa, v_cell_temp, v_new_soiling);

    -- Inverter blip — rare random momentary fault
    v_blip := ottoq_sim_seeded_random(v_seed, 'blip:' || v_canopy.canopy_code) < 0.005;

    IF v_blip THEN
      v_ac_kw   := 0;
      v_clipped := FALSE;
    ELSE
      v_ac_kw   := v_dc_kw * v_inv_eff;
      v_clipped := v_ac_kw > v_canopy.nameplate_ac_kw;
      IF v_clipped THEN v_ac_kw := v_canopy.nameplate_ac_kw; END IF;
    END IF;

    INSERT INTO ottoq_solar_output (
      output_id, depot_id, sim_run_id, weather_snapshot_id,
      canopy_structure_id, canopy_code, sim_clock_at,
      irradiance_poa_wm2, ambient_temp_c, cell_temp_c, soiling_factor,
      nameplate_dc_kw, nameplate_ac_kw,
      dc_power_kw, ac_power_kw, inverter_efficiency,
      inverter_clipped, inverter_blip, data_source
    ) VALUES (
      gen_random_uuid(), p_depot_id, p_sim_run_id, v_weather_id,
      v_canopy.structure_id, v_canopy.canopy_code, p_sim_clock_now,
      ROUND(v_canopy_poa::numeric, 1),
      ROUND(v_ambient_c::numeric, 1),
      ROUND(v_cell_temp::numeric, 1),
      ROUND(v_new_soiling::numeric, 4),
      v_canopy.nameplate_dc_kw, v_canopy.nameplate_ac_kw,
      ROUND(v_dc_kw::numeric, 2), ROUND(v_ac_kw::numeric, 2), v_inv_eff,
      v_clipped, v_blip, 'twin');

    -- Persist soiling state
    UPDATE ottoq_canopy_state
       SET current_soiling = v_new_soiling,
           last_rain_clean_at = CASE WHEN v_precip_mm >= 1.0 THEN p_sim_clock_now
                                      ELSE last_rain_clean_at END,
           last_updated_at = NOW()
     WHERE canopy_code = v_canopy.canopy_code;

    IF v_blip THEN
      PERFORM ottoq_record_event(
        p_actor_type    := 'solar_controller',
        p_actor_id      := 'twin_solar_canopy_' || v_canopy.canopy_code,
        p_event_type    := 'twin.solar_inverter_blip',
        p_entity_type   := 'structure',
        p_entity_id     := v_canopy.structure_id,
        p_payload       := jsonb_build_object(
          'canopy_code', v_canopy.canopy_code,
          'dc_kw_at_fault', v_dc_kw,
          'lost_ac_kw', v_dc_kw * v_inv_eff),
        p_severity      := 'warning',
        p_ingest_source := 'twin',
        p_data_source   := 'twin',
        p_sim_run_id    := p_sim_run_id);
    END IF;
  END LOOP;

  -- Lightweight tick event (debug-severity, doesn't pollute info log)
  PERFORM ottoq_record_event(
    p_actor_type    := 'external_sensor',
    p_actor_id      := 'twin_weather_generator',
    p_event_type    := 'twin.weather_tick',
    p_entity_type   := 'depot',
    p_entity_id     := p_depot_id,
    p_payload       := jsonb_build_object(
      'weather_snapshot_id', v_weather_id,
      'label',     v_label,
      'temp_c',    ROUND(v_ambient_c::numeric, 1),
      'cloud_pct', ROUND(v_cloud_pct::numeric, 1),
      'ghi_wm2',   ROUND(v_actual_ghi::numeric, 1),
      'precip',    v_precip_state),
    p_severity      := 'debug',
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id);

  RETURN v_weather_id;
END;
$function$

