-- migration-version: 20260819210000
-- migration-name:    twin_determinism_charge_session_salts
-- 0047 — C7 FOLLOW-UP: the two salt sites the 0045 census missed, found by the
-- 0045 standing cert itself.
--
-- RE-CERT RESULT THAT FOUND THIS (post-0045, arms 2ab6ab11 / e12faa29, both
-- seed 424242 / policy otto_q / identical cadence): 10 of 20 aligned ticks
-- identical (was 0 of 20 pre-0045), all 100 vehicle SoCs paired at first
-- divergence (sim-min 330) — the 0045 salt-domain fix holds. The single
-- diverging vehicle (c8663fd7: charging_dcfc in A, arrived_at_gate in B)
-- traces to charge-session RATE NOISE shifting a session's completion tick,
-- which shifts a stall hand-off. The noise draws here are salted with
-- (a) the SESSION UUID — gen_random_uuid(), unique per run — and
-- (b) the ABSOLUTE sim clock, exactly the 0045 defect class.
-- FIX: identify a session by (vehicle, run-relative start offset) and the
-- tick by its run-relative offset, via twin.ottoq_sim_clock_salt (0045 §1).
-- Bodies below are byte-identical to their 2026-08-19 captures in
-- db/fn_current/ except the four salt expressions.

-- ── twin.ottoq_sim_advance_charge_sessions (2 salt sites patched) ──
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
      + ottoq_sim_seeded_random(v_seed, 'btemp:' || v_session.vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, v_session.started_at)) * 8
      + LEAST(15, EXTRACT(EPOCH FROM (p_sim_clock_now - v_session.started_at)) / 600.0 * 5);

    v_rate_kw := ottoq_sim_compute_charge_rate(
      p_soc_pct := v_vehicle.current_soc, p_battery_temp_c := v_battery_temp,
      p_ambient_temp_c := v_ambient_temp, p_charger_max_kw := v_charger.max_kw,
      p_vehicle_max_kw := v_vehicle.inlet_max_kw, p_battery_capacity_kwh := v_vehicle.battery_capacity_kwh,
      p_battery_soh_pct := COALESCE(v_vehicle.soh, 95), p_noise_seed := v_seed,
      p_noise_salt := v_session.vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, v_session.started_at) || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now));

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
;


-- ── twin.ottoq_sim_start_charge_session (2 salt sites patched) ──
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
    abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42'), 42)), 'ambient:' || p_vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, v_clock));
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
    p_noise_salt := p_vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, v_clock));

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
;
