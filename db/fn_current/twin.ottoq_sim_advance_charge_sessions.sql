-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 977001ed0a44238b41a8e51e4dd00495
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_charge_sessions(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS TABLE(out_session_id uuid, out_action text, out_new_soc numeric, out_charge_rate_kw numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_session       RECORD;
  v_vehicle       RECORD;
  v_charger       RECORD;
  v_elapsed_min   NUMERIC;
  v_rate_kw       NUMERIC;
  v_kwh_delta     NUMERIC;
  v_new_soc       NUMERIC;
  v_target_soc    NUMERIC;
  v_battery_temp  NUMERIC;
  v_ambient_temp  NUMERIC;
  v_fault_mode    TEXT;
  v_fault_card    JSONB;
  v_last_update   TIMESTAMPTZ;
  v_seed          BIGINT;
BEGIN
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42'), 42));

  -- VEHICLE-FIRST DOCTRINE: charging is NEVER held back. Every active session charges
  -- at its full physical rate; peak shaving is the BESS's job (see ottoq_energy_orchestrate).

  -- ═══════ REAP THE ORPHANS FIRST ═══════
  -- Scoping the loop below to this run is correct, and on its own it would
  -- strand every active session whose run has ended: nothing else closes them,
  -- and they would hold their chargers Occupied forever. The unfiltered loop was
  -- accidentally the only reaper.
  --
  -- TERMINAL STATES ARE ENUMERATED. The vocabulary is initializing / running /
  -- paused / completed / failed / aborted; reaping anything merely "not running"
  -- would cancel the live sessions of a PAUSED run, so an operator pausing the
  -- cockpit would return to an empty depot. An unrecognised future status is
  -- left alone rather than destroyed.
  --
  -- Closed by direct UPDATE rather than through ottoq_sim_stop_charge_session,
  -- which is PHYSICS — it writes a robotic tether, opens a demate arm cycle and
  -- emits StopTransaction. A session whose world has ended is not demating, it
  -- is being reaped; dressing that up as a physical event is how one run's arm
  -- records came to describe another run's vehicles.
  WITH orphan AS (
    SELECT s.id, s.stall_id
      FROM ocpp_sessions s
      LEFT JOIN ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
     WHERE s.status = 'active'
       AND s.id_token LIKE 'TWIN-%'
       AND s.sim_run_id IS DISTINCT FROM p_sim_run_id
       AND (r.sim_run_id IS NULL
            OR r.status IN ('completed', 'failed', 'aborted'))
  ), closed AS (
    UPDATE ocpp_sessions s
       SET status = 'cancelled'::ocpp_session_status,
           ended_at = COALESCE(s.ended_at, p_sim_clock_now),
           stopped_reason = 'orphaned_run',
           updated_at = NOW()
      FROM orphan o WHERE s.id = o.id
    RETURNING s.stall_id
  )
  UPDATE ottoq_ocpp_chargers c
     SET station_state = 'Available', station_state_changed_at = p_sim_clock_now
   WHERE c.charger_id IN (SELECT ocpp_charger_id FROM stalls WHERE id IN (SELECT stall_id FROM closed))
     AND c.station_state = 'Occupied';

  FOR v_session IN
    SELECT s.*, st.ocpp_charger_id, st.stall_type
      FROM ocpp_sessions s
      JOIN stalls st ON st.id = s.stall_id
     WHERE s.status = 'active'
       AND s.id_token LIKE 'TWIN-%'
       -- THIS RUN'S SESSIONS ONLY. Everything below uses p_sim_run_id for the
       -- seed, the variability profile, the fault deck and every recorded event;
       -- selecting other runs' sessions here made all of that describe vehicles
       -- this run never touched, and advanced them against a clock that could be
       -- days away from their own.
       AND s.sim_run_id IS NOT DISTINCT FROM p_sim_run_id
  LOOP
    SELECT v.current_soc, v.battery_capacity_kwh, v.inlet_max_kw, v.fleet_operator_id,
           v.target_soc, (v.config->>'battery_soh_pct')::NUMERIC AS soh, v.display_name,
           (v.config->>'charge_curve_scalar')::NUMERIC AS curve_scalar
      INTO v_vehicle FROM vehicles v WHERE id = v_session.vehicle_id;

    SELECT max_kw, ocpp_identifier INTO v_charger
      FROM ottoq_ocpp_chargers WHERE charger_id = v_session.ocpp_charger_id;

    v_last_update := COALESCE((v_session.last_meter_value->>'at')::timestamptz, v_session.started_at);
    v_elapsed_min := EXTRACT(EPOCH FROM (p_sim_clock_now - v_last_update)) / 60.0;
    IF v_elapsed_min <= 0 THEN CONTINUE; END IF;
    v_elapsed_min := LEAST(v_elapsed_min, 90);

    v_target_soc := LEAST(COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc()), public.ottoq_target_soc_cap(v_session.stall_type::TEXT, v_session.started_at));
    v_ambient_temp := COALESCE(v_session.ambient_temp_c, 22);
    v_battery_temp := v_ambient_temp + 5
      + ottoq_sim_seeded_random(v_seed, 'btemp:' || v_session.id::text) * 8
      + LEAST(15, EXTRACT(EPOCH FROM (p_sim_clock_now - v_session.started_at)) / 600.0 * 5);

    v_rate_kw := ottoq_sim_compute_charge_rate(
      p_soc_pct := v_vehicle.current_soc, p_battery_temp_c := v_battery_temp,
      p_ambient_temp_c := v_ambient_temp, p_charger_max_kw := v_charger.max_kw,
      p_vehicle_max_kw := v_vehicle.inlet_max_kw, p_battery_capacity_kwh := v_vehicle.battery_capacity_kwh,
      p_battery_soh_pct := COALESCE(v_vehicle.soh, 95), p_noise_seed := v_seed,
      p_noise_salt := v_session.id::text || ':' || p_sim_clock_now::text);

    -- charge_time variability only (calibrated platform curve); NO energy throttle.
    v_rate_kw := v_rate_kw / GREATEST(0.2, ottoq_profile_rate_mult(p_sim_run_id, 'charge_time'));
    -- per-vehicle charge-curve scalar (condition card drawn at run boot)
    v_rate_kw := v_rate_kw * COALESCE(v_vehicle.curve_scalar, 1.0);

    v_kwh_delta := v_rate_kw * (v_elapsed_min / 60.0);

    -- ═══════ THE PACK CANNOT TAKE MORE THAN IT HAS ROOM FOR ═══════
    -- Without this, the full window is metered at the full rate and the SoC
    -- derivation below silently discards everything past target: 1407.8 kWh of
    -- 3346.8 kWh metered across the first 68 sessions, 42%, worst case a 90 kWh
    -- pack billed 136.8 kWh in one 30-minute tick.
    --
    -- Bounded on CUMULATIVE energy since soc_start, which is the exact quantity
    -- the SoC expression below integrates, so the two agree by construction and
    -- its LEAST(v_target_soc, ...) becomes a guard that can no longer bind.
    -- A car already at or above target gets a bound of 0 and meters nothing,
    -- which is the "already full" case closing itself.
    IF COALESCE(v_vehicle.battery_capacity_kwh, 0) > 0 THEN
      v_kwh_delta := LEAST(
        v_kwh_delta,
        GREATEST(0,
          ((v_target_soc - COALESCE(v_session.soc_start, v_vehicle.current_soc, 0)) / 100.0)
            * v_vehicle.battery_capacity_kwh
          - COALESCE(v_session.energy_delivered_kwh, 0)));
    END IF;

    -- ═══════════ SoC IS DERIVED FROM CUMULATIVE ENERGY, NOT INCREMENTED ═══════════
    -- THE DEFECT. This read `v_vehicle.current_soc + (v_kwh_delta / capacity) * 100`,
    -- i.e. it incremented the value STORED on the vehicle. public.vehicles.current_soc
    -- is an INTEGER column, so ROUND(38.17, 1) was written back as 38, and the next tick
    -- read 38 and added the same fraction again. Any session whose per-tick gain was
    -- under half a point could never move at all.
    -- MEASURED on run 128c12f6, three live DCFC sessions at an ~8 s tick:
    --   DCFC-03  106 kW / 135 kWh -> 0.175 pts/tick -> frozen at 46% (15.4 kWh absorbed)
    --   DCFC-09   68 kW /  90 kWh -> 0.167 pts/tick -> frozen at 38% (11.7 kWh absorbed)
    --   DCFC-08  170 kW /  90 kWh -> 0.42  pts/tick -> moving, and losing ~40% of every
    --                                                  tick's energy to the same rounding
    -- Because the charge curve TAPERS, every session eventually falls under the
    -- threshold and sticks. No vehicle could ever reach target, so no charge could ever
    -- complete, so the depot could never turn a vehicle around.
    --
    -- THE FIX. Derive SoC from the session's cumulative delivered energy against
    -- soc_start. The cumulative total is monotonic, so it crosses each whole point no
    -- matter how small the per-tick slice is, and no energy is lost to rounding. Storing
    -- a whole number is fine; ACCUMULATING in one was not.
    -- Falls back to the incremental form if capacity is missing, so a bad row cannot
    -- turn this into a division error mid-tick.
    IF COALESCE(v_vehicle.battery_capacity_kwh, 0) > 0 THEN
      -- Floored at the battery's existing charge: a charge session may raise SoC
      -- or leave it alone, never lower it. LEAST still prevents overshoot.
      v_new_soc := GREATEST(
        COALESCE(v_vehicle.current_soc, 0),
        LEAST(v_target_soc,
          COALESCE(v_session.soc_start, v_vehicle.current_soc)
            + ((COALESCE(v_session.energy_delivered_kwh, 0) + v_kwh_delta)
               / v_vehicle.battery_capacity_kwh) * 100.0));
    ELSE
      -- No battery capacity on the row, so no gain can be derived. Leave the
      -- pack exactly as it is rather than clamping it down to the target.
      v_new_soc := v_vehicle.current_soc;
    END IF;

    v_fault_card := ottoq_twin_deal_fault_card(p_sim_run_id, v_session.id, v_session.soc_start, v_target_soc, p_sim_clock_now);

    IF (v_fault_card->>'will_fault')::boolean
       AND v_new_soc >= (v_fault_card->>'trigger_soc')::numeric
       AND v_new_soc < v_target_soc - 0.5 THEN
      v_fault_mode := v_fault_card->>'fault_mode';

      PERFORM ottoq_sim_emit_ocpp(v_session.id, v_session.ocpp_charger_id, v_session.vehicle_id,
        p_sim_run_id, p_sim_clock_now, 'cs_to_csms', 'MeterValues', jsonb_build_object(
          'connectorId', 1, 'transactionId', v_session.transaction_id,
          'sampledValue', jsonb_build_array(
            jsonb_build_object('value', v_rate_kw, 'measurand', 'Power.Active.Import', 'unit', 'kW'),
            jsonb_build_object('value', v_new_soc, 'measurand', 'SoC', 'unit', 'Percent'),
            jsonb_build_object('value', v_battery_temp, 'measurand', 'Temperature', 'unit', 'Celsius', 'location', 'battery')),
          'fault_imminent', TRUE, 'timestamp', p_sim_clock_now));

      UPDATE vehicles SET current_soc = ROUND(v_new_soc::numeric, 1),
                          current_soc_updated_at = p_sim_clock_now, current_soc_source = 'oem_telemetry'
       WHERE id = v_session.vehicle_id;

      UPDATE ocpp_sessions SET energy_delivered_kwh = energy_delivered_kwh + v_kwh_delta,
             fault_count = fault_count + 1, last_fault_message = v_fault_mode, updated_at = p_sim_clock_now
       WHERE id = v_session.id;

      PERFORM ottoq_sim_stop_charge_session(p_session_id := v_session.id, p_reason := v_fault_mode,
        p_sim_clock_now := p_sim_clock_now,
        p_fault_message := 'Calibrated fault injection per ChargerHelp mix: ' || v_fault_mode,
        p_sim_run_id := p_sim_run_id);

      out_session_id := v_session.id; out_action := 'faulted:' || v_fault_mode;
      out_new_soc := v_new_soc; out_charge_rate_kw := v_rate_kw; RETURN NEXT; CONTINUE;
    END IF;

    PERFORM ottoq_sim_emit_ocpp(v_session.id, v_session.ocpp_charger_id, v_session.vehicle_id,
      p_sim_run_id, p_sim_clock_now, 'cs_to_csms', 'MeterValues', jsonb_build_object(
        'connectorId', 1, 'transactionId', v_session.transaction_id,
        'sampledValue', jsonb_build_array(
          jsonb_build_object('value', v_rate_kw, 'measurand', 'Power.Active.Import', 'unit', 'kW'),
          jsonb_build_object('value', v_new_soc, 'measurand', 'SoC', 'unit', 'Percent'),
          jsonb_build_object('value', v_kwh_delta, 'measurand', 'Energy.Active.Import.Interval', 'unit', 'kWh'),
          jsonb_build_object('value', v_battery_temp, 'measurand', 'Temperature', 'unit', 'Celsius', 'location', 'battery')),
        'timestamp', p_sim_clock_now));

    UPDATE vehicles SET current_soc = ROUND(v_new_soc::numeric, 1),
           current_soc_updated_at = p_sim_clock_now, current_soc_source = 'oem_telemetry'
     WHERE id = v_session.vehicle_id;

    UPDATE ocpp_sessions
       SET energy_delivered_kwh = COALESCE(energy_delivered_kwh, 0) + v_kwh_delta,
           peak_power_kw = GREATEST(COALESCE(peak_power_kw, 0), v_rate_kw),
           connector_temp_c_max = GREATEST(COALESCE(connector_temp_c_max, v_battery_temp), v_battery_temp),
           meter_values_count = COALESCE(meter_values_count, 0) + 1,
           last_meter_value = jsonb_build_object('at', p_sim_clock_now, 'power_kw', ROUND(v_rate_kw::numeric, 2),
             'soc_pct', ROUND(v_new_soc::numeric, 1), 'battery_temp_c', ROUND(v_battery_temp::numeric, 1)),
           updated_at = p_sim_clock_now
     WHERE id = v_session.id;

    IF v_new_soc >= v_target_soc - 0.5 THEN
      PERFORM ottoq_sim_stop_charge_session(p_session_id := v_session.id, p_reason := 'completed',
        p_sim_clock_now := p_sim_clock_now, p_sim_run_id := p_sim_run_id);
      -- CHEMISTRY: a session that actually finished at/above 99% IS the periodic balance
      -- charge — stamp it so NMC packs resume their protective 90% nightly target.
      IF v_new_soc >= 99 THEN
        BEGIN PERFORM ottoq_record_balance_charge(v_session.vehicle_id, p_sim_clock_now);
        EXCEPTION WHEN OTHERS THEN RAISE WARNING 'balance stamp: %', SQLERRM; END;
      END IF;
      out_session_id := v_session.id; out_action := 'completed';
      out_new_soc := v_new_soc; out_charge_rate_kw := v_rate_kw; RETURN NEXT; CONTINUE;
    END IF;

    out_session_id := v_session.id; out_action := 'advanced';
    out_new_soc := v_new_soc; out_charge_rate_kw := v_rate_kw; RETURN NEXT;
  END LOOP;
END;
$function$

