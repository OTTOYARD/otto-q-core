-- GENERATED / SNAPSHOT FILE — DO NOT EDIT. Changes go in db/migrations/.
-- ---------------------------------------------------------------------------
-- Snapshot of the live otto-q-core brain (Supabase gxdrcyphqjzjsuhxuqtg).
-- Nothing reads this file at runtime. Editing it changes NOTHING about the
-- running system. To change the brain: add a numbered file in db/migrations/,
-- apply it per scripts/APPLYING.md, then re-export this baseline.
-- Baseline date: 2026-08-04 (export captured 2026-08-03; verified live 2026-08-04).
-- ---------------------------------------------------------------------------

-- ============================================================================
-- OTTO-Q-CORE  |  Supabase project gxdrcyphqjzjsuhxuqtg
-- USER-DEFINED FUNCTIONS / PROCEDURES  (schema: twin)
-- ----------------------------------------------------------------------------
-- Exported verbatim via pg_get_functiondef(oid). Read-only snapshot.
-- Count: 71 user-defined routines (extension-owned routines are EXCLUDED
--        via pg_depend deptype='e').
-- Order: proname, oid.  Each routine is preceded by "-- ===== <name> =====".
--
-- NOTE: the `twin` schema was NOT part of the 2026-07-13 snapshot. This is the
--       FIRST capture of this schema. Its diff will therefore show as all-new.
--       `db/functions.sql` remains public-schema only so its diff against the
--       2026-07-13 export stays clean and comparable.
-- ============================================================================

-- ===== ottoq_demand_rebook_after_eviction =====
CREATE OR REPLACE FUNCTION twin.ottoq_demand_rebook_after_eviction(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_fleet_operator_id uuid, p_clock timestamp with time zone, p_reason text, p_min_lost numeric, p_purpose text, p_from_state text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_visit uuid; v_atoms int := 0;
BEGIN
  SELECT n.visit_id,
         (SELECT count(*) FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a
           WHERE lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'))
    INTO v_visit, v_atoms
    FROM public.ottoq_visit_needs n
   WHERE n.vehicle_id = p_vehicle_id
     AND n.status = 'open'
     AND n.meta ? 'reopen'
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a
                  WHERE lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'))
   ORDER BY n.created_at DESC
   LIMIT 1;

  IF v_visit IS NULL THEN
    -- Nothing outstanding: the eviction did not lose work. Say so, do not fabricate a demand.
    RETURN 0;
  END IF;

  UPDATE public.ottoq_visit_needs
     SET meta = COALESCE(meta,'{}'::jsonb) || jsonb_build_object(
           'rebook_required',  true,
           'rebook_due_from',  p_clock,
           'rebook_reason',    p_reason,
           'rebook_priority',  'high',
           'rebook_min_lost',  COALESCE(p_min_lost, 0),
           'rebook_purpose',   p_purpose,
           'rebook_from_state',p_from_state,
           'rebook_demanded_at', p_clock)
   WHERE visit_id = v_visit;

  BEGIN
    PERFORM public.ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_actor_id := 'demand_rebook_after_eviction',
      p_event_type := 'ottoq.rebook_demanded',
      p_entity_type := 'vehicle', p_entity_id := p_vehicle_id,
      p_fleet_operator_id := p_fleet_operator_id, p_depot_id := p_depot_id,
      p_payload := jsonb_build_object('visit_id', v_visit, 'reason', p_reason,
                     'min_lost', COALESCE(p_min_lost,0), 'purpose', p_purpose,
                     'from_state', p_from_state, 'atoms_outstanding', v_atoms,
                     'doctrine','atomic_visit_work_cut_short_must_get_a_space'),
      p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
      p_sim_run_id := p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rebook_demanded stamp dropped: % %', SQLSTATE, SQLERRM;
  END;

  RETURN 1;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_demand_rebook_after_eviction FAILED: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$

-- ===== ottoq_opportunistic_scan =====
CREATE OR REPLACE FUNCTION twin.ottoq_opportunistic_scan(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_seed bigint; v_plan jsonb; v_appr_p numeric; v_gl_p numeric;
  v_rec RECORD; v_n int := 0;
  v_p numeric; v_scan jsonb; v_enact jsonb; v_stall uuid;
BEGIN
  SELECT depot_id, COALESCE(random_seed,42) INTO v_depot, v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  v_plan := ottoq_feed_plan('service_manifest');
  v_appr_p := COALESCE((v_plan->>'opportunistic_approve_p')::numeric, 0.70);
  v_gl_p := COALESCE((v_plan->>'greenlight_approve_p')::numeric, 0.92);

  -- OTTO-Q owns the decision half
  v_scan := ottoq_plan_opportunistic_charges(p_sim_run_id, v_depot, p_clock, v_seed);
  v_n := COALESCE((v_scan->>'raised')::int, 0);

  -- TWIN: the simulated tech verdict
  FOR v_rec IN
    SELECT ap.approval_id, ap.approval_type, ap.vehicle_id, v.current_soc, COALESCE(v.target_soc,80) AS veh_target
      FROM ottoq_ops_approvals ap JOIN vehicles v ON v.id = ap.vehicle_id
     WHERE ap.depot_id = v_depot AND ap.status = 'pending' AND ap.decide_after <= p_clock AND ap.expires_at > p_clock
  LOOP
    v_p := (CASE WHEN v_rec.approval_type = 'tech_greenlight' THEN v_gl_p ELSE v_appr_p END);
    IF ottoq_sim_seeded_random(v_seed, v_rec.approval_id::text || ':decide') < v_p THEN
      UPDATE ottoq_ops_approvals SET status='approved', decided_at=p_clock, decided_by='twin_tech_sim'
       WHERE approval_id = v_rec.approval_id;
      IF v_rec.approval_type = 'opportunistic_charge' THEN
        UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               last_state_change = p_clock
         WHERE id = v_rec.vehicle_id
           AND current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding');

        v_enact := ottoq_enact_opportunistic_charge(p_sim_run_id, v_rec.vehicle_id,
                     v_rec.current_soc, v_rec.veh_target, p_clock);

        v_stall := NULLIF(v_enact->>'stall_id','')::uuid;
        IF v_stall IS NOT NULL THEN
          UPDATE vehicles SET current_stall_id = v_stall WHERE id = v_rec.vehicle_id;
          UPDATE stalls SET current_vehicle_id = v_rec.vehicle_id, status = 'occupied'
           WHERE id = v_stall;
        END IF;
      END IF;
    ELSE
      UPDATE ottoq_ops_approvals SET status='declined', decided_at=p_clock, decided_by='twin_tech_sim'
       WHERE approval_id = v_rec.approval_id;
    END IF;
  END LOOP;
  UPDATE ottoq_ops_approvals SET status='expired'
   WHERE depot_id = v_depot AND status = 'pending' AND expires_at <= p_clock;
  RETURN v_n;
END; $function$

-- ===== ottoq_report_charger_fault =====
CREATE OR REPLACE FUNCTION twin.ottoq_report_charger_fault(p_charger_id uuid, p_actor text DEFAULT 'depot_tech'::text, p_fault_code text DEFAULT 'TECH_CONFIRMED_FAULT'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_run uuid; v_clock timestamptz;
  v_stall RECORD; v_veh RECORD; v_plan jsonb;
  v_moved int := 0; v_parked int := 0; v_out jsonb := '[]'::jsonb;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_ocpp_chargers WHERE charger_id = p_charger_id;
  IF v_depot IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason','charger_not_found'); END IF;
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM ottoq_sim_runs
   WHERE depot_id = v_depot AND status='running' ORDER BY started_at DESC LIMIT 1;
  v_clock := COALESCE(v_clock, now());

  -- WORLD FACT: the hardware failed.
  UPDATE ottoq_ocpp_chargers
     SET station_state='Faulted', last_fault_code=p_fault_code, station_state_changed_at=now()
   WHERE charger_id = p_charger_id;

  FOR v_stall IN
    SELECT s.id, s.current_vehicle_id, s.reserved_by, s.stall_type::text AS stype
      FROM stalls s WHERE s.ocpp_charger_id = p_charger_id
  LOOP
    FOR v_veh IN
      SELECT v.* FROM vehicles v
       WHERE v.id IN (v_stall.current_vehicle_id, v_stall.reserved_by) AND v.id IS NOT NULL
    LOOP
      -- WORLD FACT: this stall leaves the pool. Vacate before re-placing.
      UPDATE stalls SET reserved_by=NULL, reserved_at=NULL, reservation_expires_at=NULL,
             current_vehicle_id=NULL, status='maintenance'
       WHERE id = v_stall.id;

      -- DECISION (OTTO-Q): where does the displaced vehicle go?
      v_plan := ottoq_replan_after_charger_fault(
                  v_veh.id, v_run, v_depot, v_stall.stype, p_charger_id, p_fault_code, v_clock);

      IF (v_plan->>'disposition') = 'requeued_same_class' THEN
        v_moved := v_moved + 1;
      ELSIF (v_plan->>'disposition') = 'temp_parked_awaiting_charger' THEN
        v_parked := v_parked + 1;
      END IF;
      v_out := v_out || jsonb_build_array(v_plan);
    END LOOP;
    -- stall with no vehicle on it: still take it out of the pool
    UPDATE stalls SET status='maintenance' WHERE id=v_stall.id AND status <> 'maintenance';
  END LOOP;

  BEGIN
    PERFORM ottoq_record_event(p_actor_type:='depot_tech', p_actor_id:=p_actor,
      p_event_type:='ops.charger_fault_confirmed', p_entity_type:='system',
      p_payload:=jsonb_build_object('charger_id',p_charger_id,'fault',p_fault_code,'note',p_note,
        'requeued',v_moved,'temp_parked',v_parked,'dispositions',v_out),
      p_severity:='warning', p_ingest_source:='production', p_data_source:='production',
      p_sim_run_id:=v_run);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok',true,'charger_id',p_charger_id,'fault',p_fault_code,
    'requeued_same_class',v_moved,'temp_parked',v_parked,'vehicles',v_out);
END
$function$

-- ===== ottoq_sim_advance_all_energy =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_all_energy(p_depot_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric)
 RETURNS TABLE(out_weather_id uuid, out_grid_id uuid, out_bess_count integer, out_site_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_weather  UUID;
  v_grid     UUID;
  v_bess_n   INTEGER;
  v_site     UUID;
BEGIN
  v_weather := ottoq_sim_advance_weather_and_solar(p_depot_id, p_sim_run_id, p_sim_clock_now);
  v_grid    := ottoq_sim_advance_grid             (p_depot_id, p_sim_run_id, p_sim_clock_now);
  SELECT COUNT(*) INTO v_bess_n
    FROM ottoq_sim_advance_bess(p_depot_id, p_sim_run_id, p_sim_clock_now, p_tick_minutes);
  v_site    := ottoq_sim_advance_site_energy(p_depot_id, p_sim_run_id, p_sim_clock_now, p_tick_minutes);

  IF v_site IS NOT NULL AND p_sim_run_id IS NOT NULL THEN
    UPDATE site_energy_snapshots SET sim_run_id = p_sim_run_id WHERE id = v_site;
  END IF;

  out_weather_id := v_weather;
  out_grid_id    := v_grid;
  out_bess_count := v_bess_n;
  out_site_id    := v_site;
  RETURN NEXT;
END;
$function$

-- ===== ottoq_sim_advance_bess =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_bess(p_depot_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric)
 RETURNS TABLE(out_bess_id uuid, out_target_kw numeric, out_actual_kw numeric, out_soc_pct numeric, out_temp_c numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_bess           RECORD;
  v_solar_kw       NUMERIC;
  v_ambient        NUMERIC;
  v_target_kw      NUMERIC;
  v_step           RECORD;
BEGIN
  -- Pull latest solar + ambient (within last tick window)
  SELECT COALESCE(SUM(ac_power_kw), 0) INTO v_solar_kw
    FROM ottoq_solar_output
   WHERE depot_id = p_depot_id
     AND sim_clock_at >= p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
     AND sim_clock_at <= p_sim_clock_now;

  SELECT ambient_temp_c INTO v_ambient
    FROM ottoq_weather_snapshots
   WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now
   ORDER BY sim_clock_at DESC LIMIT 1;
  v_ambient := COALESCE(v_ambient, 22);

  FOR v_bess IN SELECT bess_id, bess_identifier FROM ottoq_bess_units WHERE depot_id = p_depot_id LOOP
    -- OTTO-Q energy control: OBEY OTTO-Q's battery order if present (sign corrected: OTTO-Q +=discharge).
    v_target_kw := NULL;
    SELECT -setpoint_kw INTO v_target_kw FROM ottoq_energy_commands
      WHERE sim_run_id = p_sim_run_id AND depot_id = p_depot_id AND command_type = 'bess_setpoint_kw'
        AND status IN ('executed','pending') ORDER BY issued_at DESC, created_at DESC LIMIT 1;
    IF v_target_kw IS NULL THEN  -- no OTTO-Q order (baseline/dumb run) → autonomous default
      v_target_kw := ottoq_sim_bess_default_target_kw(v_bess.bess_id, p_sim_clock_now, v_solar_kw,
                       (SELECT COALESCE(s.total_ev_charging_kw,0) + COALESCE(s.building_load_kw,0) + COALESCE(s.lighting_load_kw,0)
                          FROM site_energy_snapshots s
                         WHERE s.sim_run_id = p_sim_run_id AND s.timestamp <= p_sim_clock_now
                         ORDER BY s.timestamp DESC LIMIT 1),
                       (SELECT MAX(s2.grid_import_kw) FROM site_energy_snapshots s2
                         WHERE s2.sim_run_id = p_sim_run_id AND s2.timestamp <= p_sim_clock_now))
                   * ottoq_profile_rate_mult(p_sim_run_id, 'bess_aggressiveness');   -- A.10 knob (×)
    END IF;
    SELECT * INTO v_step FROM ottoq_sim_bess_step(
      v_bess.bess_id, p_sim_run_id, p_sim_clock_now, p_tick_minutes,
      v_target_kw, v_ambient, 'default_policy');
    out_bess_id    := v_bess.bess_id;
    out_target_kw  := v_target_kw;
    out_actual_kw  := v_step.out_actual_power_kw;
    out_soc_pct    := v_step.out_soc_pct_new;
    out_temp_c     := v_step.out_temp_c_new;
    RETURN NEXT;
  END LOOP;
END;
$function$

-- ===== ottoq_sim_advance_charge_sessions =====
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

  FOR v_session IN
    SELECT s.*, st.ocpp_charger_id
      FROM ocpp_sessions s
      JOIN stalls st ON st.id = s.stall_id
     WHERE s.status = 'active'
       AND s.id_token LIKE 'TWIN-%'
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

    v_target_soc := COALESCE(v_vehicle.target_soc, 90);
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
    v_new_soc := LEAST(v_target_soc,
      v_vehicle.current_soc + (v_kwh_delta / v_vehicle.battery_capacity_kwh) * 100.0);

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

-- ===== ottoq_sim_advance_clock =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_clock(p_sim_run_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_new_clock TIMESTAMPTZ;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'sim run % not found', p_sim_run_id; END IF;
  IF v_run.status <> 'running' THEN RETURN NULL; END IF;

  v_new_clock := v_run.sim_clock_current + (v_run.time_scale || ' minutes')::INTERVAL;

  IF v_new_clock >= v_run.sim_clock_end THEN
    UPDATE ottoq_sim_runs
       SET sim_clock_current = sim_clock_end, status = 'completed', ended_at = NOW(),
           last_tick_at = NOW(), tick_count = tick_count + 1, next_tick_due_at = NULL
     WHERE sim_run_id = p_sim_run_id;
    PERFORM ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_actor_id := 'otto_twin',
      p_event_type := 'twin.sim_run_completed', p_entity_type := 'sim_run', p_entity_id := p_sim_run_id,
      p_depot_id := v_run.depot_id,
      p_payload := jsonb_build_object('scenario_code', v_run.scenario_code,
                     'tick_count', v_run.tick_count + 1, 'events_generated', v_run.events_generated),
      p_severity := 'info', p_ingest_source := 'twin',
      p_data_source := 'twin', p_sim_run_id := p_sim_run_id
    );
    RETURN NULL;
  END IF;

  UPDATE ottoq_sim_runs
     SET sim_clock_current = v_new_clock, last_tick_at = NOW(),
         next_tick_due_at = NOW() + (tick_interval_seconds || ' seconds')::INTERVAL,
         tick_count = tick_count + 1
   WHERE sim_run_id = p_sim_run_id;
  RETURN v_new_clock;
END;
$function$

-- ===== ottoq_sim_advance_deployed_telemetry =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_deployed_telemetry(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric)
 RETURNS TABLE(out_vehicle_id uuid, out_action text, out_new_soc numeric, out_new_state text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_ret_should boolean; v_ret_trigger text; v_ret_urgency text; v_ret_ev jsonb;
  v_ret_deferrable boolean; v_book jsonb; v_eta_min numeric;
  v_dispatch        RECORD;
  v_active_frac     NUMERIC;
  v_avg_speed       NUMERIC;
  v_discharge_kw    NUMERIC;
  v_kwh_consumed    NUMERIC;
  v_miles           NUMERIC;
  v_new_soc         NUMERIC;
  v_seed            BIGINT;
  v_salt            TEXT;
  v_dtc             TEXT;
  v_incident        RECORD;
  v_ambient         NUMERIC;
  v_battery_temp    NUMERIC;
  v_should_return   BOOLEAN;
  v_min_soc_thresh  NUMERIC;
  v_incident_id     UUID;
  v_webhook_id      UUID;
  v_eta_card       JSONB;
  v_progress       NUMERIC;
BEGIN
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42') || p_sim_clock_now::text, 42));

  FOR v_dispatch IN
    SELECT d.*, v.battery_capacity_kwh, v.current_soc AS v_soc,
           v.min_soc_threshold, v.current_state AS v_state,
           v.display_name, v.fleet_operator_id AS v_fleet_op,
           (v.config->>'consumption_scalar')::numeric AS v_cons_scalar
      FROM ottoq_vehicle_dispatches d
      JOIN vehicles v ON v.id = d.vehicle_id
     WHERE d.status IN ('active','returning')
       AND (p_sim_run_id IS NULL OR d.sim_run_id = p_sim_run_id)
  LOOP
    v_salt := v_dispatch.vehicle_id::text || ':' || p_sim_clock_now::text;
    v_min_soc_thresh := COALESCE(v_dispatch.min_soc_threshold, 20);

    v_active_frac := LEAST(1.0, (0.40 + ottoq_sim_seeded_random(v_seed, 'active:' || v_salt) * 0.45)
                     * ottoq_profile_rate_mult(p_sim_run_id, 'idle_fraction'));
    v_avg_speed   := 20 + ottoq_sim_seeded_random(v_seed, 'speed:' || v_salt) * 70;

    v_ambient := COALESCE(
      ottoq_sample_calibrated('ambient_temp_c','global', v_seed, 'amb:'||v_salt),
      22);

    v_discharge_kw := ottoq_sim_compute_discharge_rate(
      v_avg_speed, v_ambient, v_dispatch.battery_capacity_kwh,
      v_active_frac, NULL, v_seed, 'disch:'||v_salt);
    v_discharge_kw := ottoq_apply_profile(p_sim_run_id, 'soh_spread', v_discharge_kw, v_discharge_kw * 0.85);
    -- per-vehicle consumption scalar (condition card drawn at run boot)
    v_discharge_kw := v_discharge_kw * COALESCE(v_dispatch.v_cons_scalar, 1.0);
    v_kwh_consumed := v_discharge_kw * (p_tick_minutes / 60.0);
    v_miles := (v_avg_speed * v_active_frac * p_tick_minutes / 60.0) * 0.621371;

    v_new_soc := GREATEST(0,
      v_dispatch.v_soc - (v_kwh_consumed / v_dispatch.battery_capacity_kwh) * 100.0);

    v_battery_temp := v_ambient + 4 + v_active_frac * 6
      + ottoq_sim_seeded_random(v_seed, 'btemp:'||v_salt) * 4;

    v_dtc := ottoq_sim_maybe_spawn_dtc(v_seed, v_salt, p_tick_minutes, v_active_frac,
                                       ottoq_profile_rate_mult(p_sim_run_id, 'dtc'));

    v_incident := NULL;
    IF v_miles > 0 THEN
      SELECT * INTO v_incident FROM ottoq_sim_maybe_incident(v_seed, v_salt, v_miles,
                                       ottoq_profile_rate_mult(p_sim_run_id, 'incident') * ottoq_twin_incident_weather_mult(p_sim_run_id, p_sim_clock_now),
                                       ottoq_apply_profile(p_sim_run_id, 'incident_severity', 0, 0),
                                       ottoq_profile_rate_mult(p_sim_run_id, 'breakdown_rate'));
    END IF;

    IF v_incident.out_kind IS NOT NULL THEN
      v_incident_id := gen_random_uuid();
      INSERT INTO ottoq_vehicle_incidents (
        incident_id, vehicle_id, sim_run_id, occurred_at,
        incident_type, severity,
        speed_kmh_at_event, soc_pct_at_event,
        description, requires_tow, resolution_status
      ) VALUES (
        v_incident_id, v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
        v_incident.out_kind, v_incident.out_sev,
        v_avg_speed, v_new_soc,
        'Auto-generated by deployment simulator (DMV-calibrated rate)',
        v_incident.out_requires_tow, 'open');

      PERFORM ottoq_record_event(
        p_actor_type    := 'av_vehicle',
        p_actor_id      := v_dispatch.vehicle_id::text,
        p_event_type    := CASE WHEN v_incident.out_sev IN ('major','safety_critical')
                                THEN 'anomaly.critical_detected'
                                ELSE 'anomaly.detected' END,
        p_entity_type   := 'vehicle',
        p_entity_id     := v_dispatch.vehicle_id,
        p_fleet_operator_id := v_dispatch.v_fleet_op,
        p_payload       := jsonb_build_object(
          'incident_type', v_incident.out_kind,
          'severity', v_incident.out_sev,
          'requires_tow', v_incident.out_requires_tow,
          'soc_at_event', v_new_soc,
          'speed_at_event', v_avg_speed),
        p_severity      := CASE
                             WHEN v_incident.out_sev = 'major' THEN 'critical'
                             WHEN v_incident.out_sev = 'moderate' THEN 'warning'
                             ELSE 'info' END,
        p_ingest_source := 'twin',
        p_data_source   := 'twin',
        p_sim_run_id    := p_sim_run_id);

      IF v_incident.out_requires_tow THEN
        UPDATE vehicles SET current_state = 'tow_requested'::vehicle_state,
                            last_state_change = p_sim_clock_now,
                            current_soc = ROUND(v_new_soc::numeric,1),
                            current_soc_updated_at = p_sim_clock_now
         WHERE id = v_dispatch.vehicle_id;
        UPDATE ottoq_vehicle_dispatches SET status = 'aborted',
                                            actual_return_at = p_sim_clock_now
         WHERE dispatch_id = v_dispatch.dispatch_id;
        out_vehicle_id := v_dispatch.vehicle_id;
        out_action := 'incident:' || v_incident.out_kind;
        out_new_soc := v_new_soc; out_new_state := 'tow_requested';
        RETURN NEXT;
        CONTINUE;
      END IF;
    END IF;

    IF v_dispatch.status = 'active' THEN
      v_eta_card := ottoq_twin_deal_eta_card(p_sim_run_id, v_dispatch.dispatch_id, (p_sim_clock_now::date - DATE '2020-01-01')::int);
      IF (v_eta_card->>'will_delay')::boolean AND NOT COALESCE((v_eta_card->>'applied')::boolean, false) THEN
        v_progress := CASE WHEN v_dispatch.scheduled_return_at > v_dispatch.dispatched_at
          THEN EXTRACT(EPOCH FROM (p_sim_clock_now - v_dispatch.dispatched_at))
               / NULLIF(EXTRACT(EPOCH FROM (v_dispatch.scheduled_return_at - v_dispatch.dispatched_at)),0)
          ELSE 1 END;
        IF v_progress >= (v_eta_card->>'trigger_progress')::numeric THEN
          UPDATE ottoq_vehicle_dispatches
             SET scheduled_return_at = scheduled_return_at + ((v_eta_card->>'delay_min') || ' minutes')::interval
           WHERE dispatch_id = v_dispatch.dispatch_id;
          v_dispatch.scheduled_return_at := v_dispatch.scheduled_return_at + ((v_eta_card->>'delay_min') || ' minutes')::interval;
          UPDATE ottoq_variability_cards SET meta = meta || '{"applied":true}'::jsonb
           WHERE sim_run_id=p_sim_run_id AND var_key='eta_delay' AND scope_instance=v_dispatch.dispatch_id::text;
          BEGIN
            PERFORM ottoq_record_event(
              p_actor_type:='av_vehicle', p_actor_id:=v_dispatch.vehicle_id::text,
              p_event_type:='fleet.arrival_delayed', p_entity_type:='vehicle', p_entity_id:=v_dispatch.vehicle_id,
              p_fleet_operator_id:=v_dispatch.v_fleet_op,
              p_payload:=jsonb_build_object('cause', v_eta_card->>'cause', 'delay_min', (v_eta_card->>'delay_min')::numeric,
                'new_eta', v_dispatch.scheduled_return_at),
              p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
          EXCEPTION WHEN OTHERS THEN NULL; END;
        END IF;
      END IF;
    END IF;

    UPDATE vehicles
       SET current_soc = ROUND(v_new_soc::numeric, 1),
           current_soc_updated_at = p_sim_clock_now,
           current_soc_source = 'oem_telemetry',
           last_state_change = p_sim_clock_now
     WHERE id = v_dispatch.vehicle_id;

    PERFORM ottoq_sim_emit_telemetry(
      v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
      v_new_soc, v_battery_temp, v_avg_speed * v_active_frac,
      v_discharge_kw, v_dispatch.v_state::text,
      CASE WHEN v_dtc IS NOT NULL THEN ARRAY[v_dtc] ELSE NULL END);

    -- AP-3: need-driven return decision (evaluator scoped to the real run)
    SELECT er.should_return, er.return_trigger, er.urgency, er.is_deferrable, er.evidence
      INTO v_ret_should, v_ret_trigger, v_ret_urgency, v_ret_deferrable, v_ret_ev
      FROM ottoq_evaluate_return_need(
             v_dispatch.vehicle_id, v_dispatch.sim_run_id, p_sim_clock_now,
             p_tick_minutes, v_new_soc) er;
    v_should_return := COALESCE(v_ret_should, false);

    IF v_should_return AND v_dispatch.status = 'active' THEN
      -- AP-4: THE RETURN HANDSHAKE. Telemetry was just emitted (the vehicle's "return to
      -- depot" notification). OTTO-Q now books the appointment BEFORE the state flip:
      -- builds the workflow, reserves the stall, communicates the selection back.
      v_eta_min := ottoq_return_eta_minutes(v_dispatch.vehicle_id, NULL, p_sim_run_id);
      BEGIN
        v_book := ottoq_book_appointment(
                  v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
                  v_ret_trigger, v_ret_urgency, COALESCE(v_ret_deferrable, false),
                  v_eta_min, v_new_soc, NULL);
      EXCEPTION WHEN OTHERS THEN
        -- one bad vehicle must never abort the whole telemetry step (tick hot path)
        v_book := jsonb_build_object('secured', false, 'reason', 'booking_error');
      END;

      -- Gate departure on securing a resource. Non-deferrable needs (reserve breach, fault)
      -- depart immediately regardless; a deferrable need with no free stall keeps the car
      -- deployed and earning, retrying next tick. That deferral is bounded by the SoC ladder:
      -- as charge drains, the trigger escalates to a non-deferrable low_soc_reserve return
      -- before any safety margin is at risk.
      IF COALESCE((v_book->>'secured')::boolean, false) OR NOT COALESCE(v_ret_deferrable, false) THEN
        UPDATE ottoq_vehicle_dispatches
           SET status = 'returning',
               return_trigger = COALESCE(v_ret_trigger, 'need_unspecified'),
               returning_started_at = p_sim_clock_now,
               return_eta_minutes   = v_eta_min,
               scheduled_return_at  = p_sim_clock_now + (v_eta_min || ' minutes')::interval,
               return_evidence = COALESCE(v_ret_ev, '{}'::jsonb) || jsonb_build_object(
                 'decided_at', p_sim_clock_now,
                 'soc_at_decision', v_new_soc,
                 'reserve', v_min_soc_thresh,
                 'eta_minutes_is_a_parameter', true,
                 'appointment', v_book)
         WHERE dispatch_id = v_dispatch.dispatch_id;
        UPDATE vehicles SET current_state = 'en_route_to_depot'::vehicle_state,
                            last_state_change = p_sim_clock_now
         WHERE id = v_dispatch.vehicle_id;
        out_action := CASE WHEN COALESCE((v_book->>'secured')::boolean, false)
                           THEN 'returning:booked=' || COALESCE(v_book->>'stall_type','?')
                           ELSE 'returning:unbooked_nondeferrable' END;
      ELSE
        out_action := 'deferred:no_capacity';
      END IF;
    ELSIF v_dispatch.status = 'returning'
          AND p_sim_clock_now >= COALESCE(
                v_dispatch.returning_started_at
                  + (COALESCE(v_dispatch.return_eta_minutes, 30) || ' minutes')::interval,
                v_dispatch.scheduled_return_at + INTERVAL '5 minutes') THEN
      v_webhook_id := ottoq_sim_emit_arrival_webhook(
        v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
        v_dispatch.dispatch_id, v_new_soc);

      UPDATE ottoq_vehicle_dispatches
         SET status = 'completed',
             actual_return_at = p_sim_clock_now,
             actual_duration_min = EXTRACT(EPOCH FROM (p_sim_clock_now - dispatched_at)) / 60.0,
             arrival_jitter_min = EXTRACT(EPOCH FROM (p_sim_clock_now - COALESCE(
                 returning_started_at + (COALESCE(return_eta_minutes,30) || ' minutes')::interval,
                 scheduled_return_at))) / 60.0,
             soc_at_return_pct = v_new_soc,
             miles_driven = (SELECT COALESCE(SUM(speed_kmh) / 60.0 * 0.621371, 0)
                              FROM ottoq_telemetry_packets
                             WHERE sim_run_id = p_sim_run_id
                               AND vehicle_id = v_dispatch.vehicle_id
                               AND sim_clock_at >= v_dispatch.dispatched_at)
       WHERE dispatch_id = v_dispatch.dispatch_id;
      UPDATE vehicles SET current_state = 'arrived_at_gate'::vehicle_state,
                          current_soc = GREATEST(2, LEAST(100,
                            ottoq_apply_profile(p_sim_run_id, 'soc_on_arrival', v_new_soc, v_new_soc) - ottoq_twin_arrival_soc_drain(p_sim_run_id, p_sim_clock_now))),
                          last_state_change = p_sim_clock_now
       WHERE id = v_dispatch.vehicle_id;
      out_action := 'arrived:webhook=' || COALESCE(LEFT(v_webhook_id::text, 8), 'null');
    ELSE
      out_action := 'advancing';
    END IF;

    out_vehicle_id := v_dispatch.vehicle_id;
    out_new_soc := v_new_soc;
    out_new_state := (SELECT current_state::text FROM vehicles WHERE id = v_dispatch.vehicle_id);
    RETURN NEXT;
  END LOOP;
END;
$function$

-- ===== ottoq_sim_advance_flow_contract =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_flow_contract(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_tick bigint; v_rec RECORD; v_delta numeric; v_n int := 0;
BEGIN
  SELECT depot_id, tick_count INTO v_depot, v_tick FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  FOR v_rec IN
    SELECT DISTINCT vn.vehicle_id
      FROM ottoq_visit_needs vn
      JOIN vehicles v ON v.id = vn.vehicle_id
      JOIN LATERAL jsonb_array_elements(vn.atoms) a ON true
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
       AND a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
       AND v.current_state NOT IN ('charging_dcfc','charging_l2')
       AND v.current_soc >= COALESCE((a->>'target_soc')::numeric, 80) - 2
  LOOP
    PERFORM ottoq_mark_visit_atoms_done(v_rec.vehicle_id, ARRAY['charge'], p_clock);
    v_n := v_n + 1;
  END LOOP;

  FOR v_rec IN
    SELECT l.itinerary_id, l.vehicle_id, MIN(l.planned_start_sim) AS first_late
      FROM ottoq_itinerary_legs l
      JOIN vehicles v ON v.id = l.vehicle_id
     WHERE l.sim_run_id = p_sim_run_id AND l.status = 'planned'
       AND l.planned_start_sim < p_clock - interval '20 minutes'
       AND v.current_state NOT IN ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay','in_service_bay')
       AND NOT EXISTS (SELECT 1 FROM ottoq_itinerary_legs l2
                        WHERE l2.itinerary_id = l.itinerary_id AND l2.status = 'active')
     GROUP BY 1, 2
  LOOP
    v_delta := EXTRACT(EPOCH FROM (p_clock - v_rec.first_late));
    UPDATE ottoq_itinerary_legs
       SET planned_start_sim = planned_start_sim + (v_delta::text || ' seconds')::interval,
           planned_end_sim   = planned_end_sim   + (v_delta::text || ' seconds')::interval
     WHERE itinerary_id = v_rec.itinerary_id AND status = 'planned';
    INSERT INTO ottoq_decisions (sim_run_id, tick_seq, sim_clock, depot_id, action_context,
           resolved_action_context, entity_type, entity_id, context_frame, proposed_action,
           enacted_action, outcome_status, propose_latency_ms, total_latency_ms)
    VALUES (p_sim_run_id, v_tick, p_clock, v_depot, 'task_start', 'itinerary_amended',
           'vehicle', v_rec.vehicle_id,
           jsonb_build_object('shift_s', round(v_delta)),
           jsonb_build_object('verb','amend_plan'),
           jsonb_build_object('verb','amend_plan','shift_s',round(v_delta)),
           'enacted', 0, 0);
    v_n := v_n + 1;
  END LOOP;

  UPDATE ottoq_itinerary_legs l SET status = 'skipped'
   WHERE l.sim_run_id = p_sim_run_id AND l.status = 'planned'
     AND EXISTS (SELECT 1 FROM vehicles v WHERE v.id = l.vehicle_id
                   AND v.current_state IN ('deployed','en_route_to_deployment'));
  RETURN v_n;
END; $function$

-- ===== ottoq_sim_advance_grid =====
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

-- ===== ottoq_sim_advance_service_flow =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_service_flow(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric, p_depot_id uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid)
 RETURNS TABLE(out_washing integer, out_servicing integer, out_staged integer, out_ready integer, out_overflow integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wash_cap    INT;  v_svc_cap     INT;  v_deploy_cap  INT;
  v_wash_dur    NUMERIC; v_detail_dur NUMERIC; v_svc_dur NUMERIC;
  v_in_wash     INT;  v_in_svc      INT;  v_admitted    INT;
  v_order       TEXT;  v_rec         RECORD;  v_needs_svc   BOOLEAN;  v_overflow    INT := 0;
  v_hour        INT;  v_fleet       INT;  v_deployed    INT;  v_target      INT;
  v_pressure    BOOLEAN := FALSE;  v_fasttracked INT := 0;  v_recharged   INT := 0;
  v_floor       NUMERIC;  v_end_ts      TIMESTAMPTZ;  v_feed_sim BOOLEAN := TRUE;
  -- DEPARTURE READINESS GATE (2026-08-02)
  v_ncand       INT := 0;  v_gate_on BOOLEAN := TRUE;
  v_patience_dep NUMERIC;  v_hardcap NUMERIC;  v_relcap INT;
  v_held        INT := 0;  v_esc_gate INT := 0;  v_override INT := 0;
BEGIN
  v_wash_cap   := ottoq_sim_lane_capacity(p_sim_run_id, 'cleaning_staff', 3);
  v_svc_cap    := ottoq_sim_lane_capacity(p_sim_run_id, 'service_staff', 2);
  v_deploy_cap := ottoq_sim_lane_capacity(p_sim_run_id, 'deploy_staff', 20);
  v_wash_dur   := ottoq_sim_service_minutes(p_sim_run_id, 'wash_time', 9);
  v_detail_dur := ottoq_sim_service_minutes(p_sim_run_id, 'detail_time', 25);
  v_svc_dur    := ottoq_sim_service_minutes(p_sim_run_id, 'maintenance_time', 40);
  v_floor      := ottoq_policy_get(p_sim_run_id, 'deploy_floor_soc', 80);
  SELECT COALESCE(d.feed_mode,'sim')='sim' INTO v_feed_sim FROM depots d WHERE d.id = p_depot_id;
  v_feed_sim := COALESCE(v_feed_sim, TRUE);

  SELECT COALESCE((knobs #>> ARRAY['_policy','scheduling_algorithm']), 'calibrated')
    INTO v_order FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  v_order := COALESCE(v_order, 'calibrated');

  -- ───── STEP 0: re-charge stranded under-floor vehicles (deadlock breaker) ─────
  FOR v_rec IN
    SELECT v.id FROM vehicles v
     WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
       AND v.current_state IN ('charge_complete_holding','staged_awaiting_service','staged_for_departure')
       AND v.current_soc < v_floor
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
              WHERE n.vehicle_id = v.id AND n.sim_run_id = p_sim_run_id
                AND a->>'svc' = 'charge' AND COALESCE(a->>'status','open') <> 'done')
       AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
              WHERE d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning'))
  LOOP
    -- DOCTRINE (Chase 2026-07-28): never bounce a vehicle to the gate.
    -- SPLIT 2026-07-29: the CHOICE (re-queue for charge + pick/hold/reserve the temp
    -- stall) moved to ottoq_replan_stranded_undercharge. The twin only executes the
    -- returned plan: the flag write and the physical occupancy write.
    DECLARE v_dec jsonb; v_s uuid;
    BEGIN
      v_dec := ottoq_replan_stranded_undercharge(v_rec.id, p_sim_run_id, p_depot_id, p_sim_clock_now);

      UPDATE vehicles
         SET current_state = 'staged_awaiting_service'::vehicle_state,
             last_state_change = p_sim_clock_now,
             config = jsonb_set(config, '{svc_step}',
                                to_jsonb(COALESCE(v_dec->>'svc_step', 'need_charge')))
       WHERE id = v_rec.id;

      v_s := NULLIF(v_dec->>'stall_id', '')::uuid;
      IF v_s IS NOT NULL THEN
        UPDATE vehicles SET current_stall_id = v_s WHERE id = v_rec.id;
        UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
         WHERE id = v_s;
      END IF;
    END;
    v_recharged := v_recharged + 1;
  END LOOP;
  IF v_recharged > 0 THEN
    PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.recharge_stranded',
      p_entity_type := 'depot', p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('recharged', v_recharged, 'floor', v_floor),
      p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END IF;

  -- ───── STEP 1: complete in-progress services (elapsed timer OR null-timer stuck) ─────
  FOR v_rec IN
    SELECT id, current_state, config FROM vehicles
     WHERE home_depot_id = p_depot_id
       AND current_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
       AND ( COALESCE((config->>'service_done')::boolean, FALSE)
          OR ( v_feed_sim AND (
                 (config->>'service_ends_at') IS NULL
              OR (config->>'service_ends_at')::timestamptz <= p_sim_clock_now ) ) )
  LOOP
    v_end_ts := COALESCE((v_rec.config->>'service_ends_at')::timestamptz, p_sim_clock_now);
    -- T3 RENDER CONTRACT: the drive OUT of the bay to staging. Origin left NULL so the
    -- emitter resolves it from leg history to the bay the entry leg targeted, closing
    -- the route. Destination is a render target only; staged_awaiting_service holds no
    -- stall. Never allowed to abort the transition.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        (SELECT s.id FROM stalls s
          WHERE s.depot_id = p_depot_id AND s.stall_type = 'staging'::stall_type
          ORDER BY (s.current_vehicle_id IS NOT NULL), s.stall_code
          OFFSET (abs(hashtext(v_rec.id::text)) % 20) LIMIT 1),
        p_sim_clock_now,
        CASE WHEN v_rec.current_state IN ('in_wash_bay','in_detail_bay')
             THEN 'exit_wash_to_staging' ELSE 'exit_service_to_staging' END,
        'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (bay exit): %', SQLERRM;
    END;
    IF v_rec.current_state IN ('in_wash_bay','in_detail_bay') THEN
      v_needs_svc := COALESCE((v_rec.config->>'flagged_issue')::boolean, FALSE);
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb(CASE WHEN v_needs_svc THEN 'need_service' ELSE 'need_deploy' END)), '{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion'
       WHERE id = v_rec.id;
    ELSE
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('need_deploy'::text)), '{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion'
       WHERE id = v_rec.id;
    END IF;
    PERFORM ottoq_itin_leg_close(p_sim_run_id, v_rec.id, ARRAY['wash','detail','service'], v_end_ts);
    PERFORM ottoq_mark_visit_atoms_done(v_rec.id,
      CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
           WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
           ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END, v_end_ts);
    -- wear truth follows completion (mark_serviced was dead: soil/PM/calibration never reset)
    PERFORM ottoq_wear_mark_serviced(v_rec.id, p_sim_run_id, s, v_end_ts)
      FROM unnest(CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
                       WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
                       ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END) AS s;
    PERFORM ottoq_record_event(p_actor_type := 'av_vehicle', p_actor_id := v_rec.id::text, p_event_type := 'twin.service_completed',
      p_entity_type := 'vehicle', p_entity_id := v_rec.id, p_payload := jsonb_build_object('from', v_rec.current_state, 'self_healed', (v_rec.config->>'service_ends_at') IS NULL),
      p_severity := 'debug', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END LOOP;

  -- ───── STEP 1.5: deploy-pressure fast-track past OPTIONAL wash ─────
  v_hour     := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_fleet    := (SELECT COUNT(*) FROM vehicles WHERE category='autonomous' AND home_depot_id=p_depot_id);
  v_deployed := (SELECT COUNT(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_sim_run_id AND status IN ('active','returning'));
  v_target   := FLOOR(v_fleet * ottoq_deploy_target_fraction(v_hour, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.55)));
  v_pressure := v_deployed < v_target;
  IF v_pressure THEN
    FOR v_rec IN
      SELECT v.id FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
         AND v.current_state = 'charge_complete_holding' AND v.current_soc >= v_floor
         AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
             WHERE n.vehicle_id = v.id AND n.sim_run_id = p_sim_run_id
               AND (a->>'must_do')::boolean = TRUE AND a->>'svc' NOT IN ('charge','readiness_check')
               AND COALESCE(a->>'status','open') <> 'done')
    LOOP
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(config, '{svc_step}', to_jsonb('need_deploy'::text)) WHERE id = v_rec.id;
      v_fasttracked := v_fasttracked + 1;
    END LOOP;
    IF v_fasttracked > 0 THEN
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.deploy_pressure_fasttrack',
        p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('fasttracked', v_fasttracked, 'deployed', v_deployed, 'target', v_target, 'hour_cst', v_hour),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- ───── STEP 2: admit waiting vehicles into lanes (capacity-gated, ordered) ─────
  SELECT COUNT(*) INTO v_in_wash FROM vehicles WHERE home_depot_id = p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay');
  v_admitted := 0;
  FOR v_rec IN
    -- M1_need_gated_wash: admit ONLY vehicles that actually have wash/detail
    -- work outstanding. Previously any holding vehicle was admitted to fill capacity.
    -- BOOKING-AWARE (2026-08-02), same reasoning as the service cursor below: the wash
    -- lane also ignored the forward calendar and picked a bay by OFFSET n % 3. The need
    -- gate and the ordering expression are preserved EXACTLY; a booking-holder key is
    -- prepended, and the vehicle's own reserved bay is surfaced for the travel leg.
    SELECT q.id, q.config, q.booked_stall FROM (
      SELECT v.id, v.config,
             (SELECT b2.stall_id
                FROM ottoq_stall_bookings b2 JOIN stalls sb ON sb.id = b2.stall_id
               WHERE b2.sim_run_id = p_sim_run_id AND b2.vehicle_id = v.id
                 AND b2.state = 'held' AND b2.purpose IN ('wash','detail')
                 AND sb.depot_id = p_depot_id AND sb.stall_type = 'wash_bay'::stall_type
                 AND sb.status NOT IN ('maintenance','closed')
                 AND lower(b2.during) <= p_sim_clock_now AND upper(b2.during) > p_sim_clock_now
               ORDER BY lower(b2.during) LIMIT 1) AS booked_stall,
             CASE v_order WHEN 'soc_optimized' THEN v.current_soc WHEN 'priority_weighted' THEN -COALESCE((v.config->>'seed_idx')::numeric, 0) ELSE EXTRACT(EPOCH FROM v.last_state_change) END AS ord
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.current_state = 'charge_complete_holding'
         AND (EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                       WHERE n.vehicle_id = v.id AND n.status IN ('open','in_progress')
                         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
              OR v.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))
    ) q
     ORDER BY (q.booked_stall IS NULL), q.ord
     -- wash_supervisor_pool: the 8-10 min exterior wash needs a supervisor as well
     -- as a free lane (founder spec: "a couple of wash bay supervisors").
     LIMIT GREATEST(0, LEAST(v_wash_cap, ottoq_depot_staffing_count(p_depot_id,'wash_supervisor')) - v_in_wash)
  LOOP
    -- T3 RENDER CONTRACT: the drive to the wash building. Render-only; picks a
    -- door for the leg, claims nothing. Origin left NULL on purpose (it is NULL on
    -- every path into charge_complete_holding) so the emitter resolves it from leg history.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        COALESCE(v_rec.booked_stall,
        (SELECT s.id FROM stalls s WHERE s.depot_id = p_depot_id
          AND s.stall_type = 'wash_bay'::stall_type
          ORDER BY (s.status IN ('maintenance','closed')), (s.current_vehicle_id IS NOT NULL), (EXISTS (SELECT 1 FROM ottoq_stall_bookings b3 WHERE b3.stall_id = s.id AND b3.sim_run_id = p_sim_run_id AND b3.state IN ('held','active','done') AND b3.during && tstzrange(p_sim_clock_now, p_sim_clock_now + make_interval(mins => GREATEST(v_wash_dur, v_detail_dur)::int), '[)'))), s.stall_code LIMIT 1)),
        p_sim_clock_now, 'taxi_to_wash', 'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (wash): %', SQLERRM;
    END;
    UPDATE vehicles
       SET current_state = (CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN 'in_detail_bay' ELSE 'in_wash_bay' END)::vehicle_state,
           last_state_change = p_sim_clock_now,
           config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('washing'::text)), '{service_ends_at}', to_jsonb((p_sim_clock_now +
               ((CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))
                      THEN v_detail_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'detail_time', v_rec.id::text || ':' || p_sim_clock_now::text, p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0)
                      ELSE v_wash_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'wash_time', v_rec.id::text || ':' || p_sim_clock_now::text, p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0) END) || ' minutes')::interval)::text))
     WHERE id = v_rec.id;
    IF v_rec.booked_stall IS NOT NULL THEN
      UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
       WHERE id = v_rec.booked_stall
         AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id);
      IF FOUND THEN
        UPDATE vehicles SET current_stall_id = v_rec.booked_stall WHERE id = v_rec.id;
      END IF;
    END IF;
    PERFORM ottoq_itin_leg_open(p_sim_run_id, p_depot_id, v_rec.id, p_sim_clock_now,
      CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN 'detail' ELSE 'wash' END,
      NULL, (SELECT (config->>'service_ends_at')::timestamptz FROM vehicles WHERE id = v_rec.id),
      jsonb_build_object('kind', 'distribution', 'corpus', 'service_ops', 'base_min', CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN v_detail_dur ELSE v_wash_dur END),
      'service_flow');
    v_admitted := v_admitted + 1;
  END LOOP;

  SELECT COUNT(*) INTO v_in_svc FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'in_service_bay';
  -- BOOKING-AWARE ADMISSION (2026-08-02). This cursor was blind to the forward calendar:
  -- it ordered purely by last_state_change and sent the car to an ARBITRARY bay
  -- (OFFSET n % 2), so a vehicle holding a live reservation got no priority and was often
  -- not even routed to the bay it had been promised. Reservations then rotted to
  -- no_show_grace_elapsed (37.3% of bay bookings). It now surfaces the vehicle's own open
  -- booking and admits booking-holders FIRST. Capacity is still staff-gated byte-for-byte:
  -- this changes WHO gets the slot and WHICH bay, never HOW MANY.
  FOR v_rec IN
    SELECT * FROM (
      SELECT v.id,
             (SELECT b2.stall_id
                FROM ottoq_stall_bookings b2 JOIN stalls sb ON sb.id = b2.stall_id
               WHERE b2.sim_run_id = p_sim_run_id AND b2.vehicle_id = v.id
                 AND b2.state = 'held' AND b2.purpose = 'service'
                 AND sb.depot_id = p_depot_id AND sb.stall_type = 'service_bay'::stall_type
                 AND sb.status NOT IN ('maintenance','closed')
                 AND lower(b2.during) <= p_sim_clock_now AND upper(b2.during) > p_sim_clock_now
               ORDER BY lower(b2.during) LIMIT 1) AS booked_stall,
             v.last_state_change AS lsc
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.current_state = 'staged_awaiting_service'
         AND v.config->>'svc_step' = 'need_service'
    ) q
     ORDER BY (q.booked_stall IS NULL), q.lsc LIMIT GREATEST(0, v_svc_cap - v_in_svc)
  LOOP
    -- T3 RENDER CONTRACT: the drive to the service bays (OFFICE-01 complex, far west).
    -- Render-only; claims no bay. Capacity remains staff-gated exactly as before.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        COALESCE(v_rec.booked_stall,
        (SELECT s.id FROM stalls s WHERE s.depot_id = p_depot_id
          AND s.stall_type = 'service_bay'::stall_type
          ORDER BY (s.status IN ('maintenance','closed')), (s.current_vehicle_id IS NOT NULL), (EXISTS (SELECT 1 FROM ottoq_stall_bookings b3 WHERE b3.stall_id = s.id AND b3.sim_run_id = p_sim_run_id AND b3.state IN ('held','active','done') AND b3.during && tstzrange(p_sim_clock_now, p_sim_clock_now + make_interval(mins => v_svc_dur::int), '[)'))), s.stall_code LIMIT 1)),
        p_sim_clock_now, 'taxi_to_service', 'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (service): %', SQLERRM;
    END;
    UPDATE vehicles SET current_state = 'in_service_bay'::vehicle_state, last_state_change = p_sim_clock_now,
           config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('servicing'::text)), '{service_ends_at}', to_jsonb((p_sim_clock_now + ((v_svc_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'maintenance_time', v_rec.id::text || ':' || p_sim_clock_now::text, p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0)) || ' minutes')::interval)::text))
     WHERE id = v_rec.id;
    -- HONOUR THE RESERVATION PHYSICALLY. Claiming the booked bay is what lets
    -- ottoq.ottoq_activate_present_bookings flip the row held -> active next tick -- the
    -- RUNTIME proof the reservation was kept rather than silently expired. Guarded so it
    -- can never steal a bay another vehicle is standing in, so it cannot double-book.
    IF v_rec.booked_stall IS NOT NULL THEN
      UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
       WHERE id = v_rec.booked_stall
         AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id);
      IF FOUND THEN
        UPDATE vehicles SET current_stall_id = v_rec.booked_stall WHERE id = v_rec.id;
      END IF;
    END IF;
    PERFORM ottoq_itin_leg_open(p_sim_run_id, p_depot_id, v_rec.id, p_sim_clock_now, 'service', NULL,
      (SELECT (config->>'service_ends_at')::timestamptz FROM vehicles WHERE id = v_rec.id),
      jsonb_build_object('kind', 'distribution', 'corpus', 'service_ops', 'base_min', v_svc_dur), 'service_flow');
  END LOOP;

  -- ═════ STEP 3: RELEASE TO DEPARTURE — READINESS GATE (2026-08-02) ═════
  -- DOCTRINE (full-service visit): a visit is ATOMIC. 'staged_for_departure' must mean
  -- "this vehicle would be dispatched if asked" — nothing weaker. Before this gate the
  -- transition was UNCONDITIONAL, so vehicles at 28-29% SoC were staged as READY.
  -- That is not merely cosmetic: 'staged_for_departure' is NOT in ottoq_decide_tick's
  -- charging cursor (which reads 'arrived_at_gate' and 'staged_awaiting_service'), so
  -- staging an undercharged car REMOVED IT FROM THE CHARGE QUEUE, while
  -- ottoq_plan_dispatch_tick(deploy_plan) would refuse it anyway (soc >= 80 + no open
  -- must-do work). Dead inventory that could never leave and could never be fixed.
  --
  -- THE GATE IS THE DISPATCHER'S OWN ADMISSION PREDICATE, MOVED ONE STEP EARLIER.
  -- It is therefore never stricter than what the dispatcher accepts, so it cannot
  -- create a new deadlock class:
  --     soc >= ready_soc   AND   no open must-do work left in this run's visit
  -- ready_soc comes from the NEEDS CARD (ottoq_vehicle_needs_card.min_ready_soc_pct),
  -- not a bare SoC literal, so it follows the per-vehicle need profile; it falls back
  -- to the deploy_floor_soc policy when the card has no row for the vehicle — a TOTAL
  -- function: a missing card must never block a vehicle. The card also supplies
  -- must_do_now / fits_window / minutes_to_deploy as EVIDENCE on the hold receipt.
  -- The card is read ONCE per call for the whole candidate set: the view materialises
  -- the entire fleet regardless of its WHERE clause (measured 192 ms for a
  -- single-vehicle probe), so a per-vehicle read would cost seconds per tick.
  --
  -- NOT AN ENERGY GATE. Vehicle-first doctrine is untouched — nothing is held back for
  -- price or grid reasons. This is READINESS only: the vehicle is not finished.
  --
  -- ESCAPE HATCHES — nothing can sit forever:
  --   0. policy deploy_ready_gate_enabled = 0  → gate off, pre-2026-08-02 behaviour.
  --   1. a held vehicle is ROUTED TO THE REMEDY, never parked: svc_step := 'need_charge'
  --      (ottoq_decide_tick's charge cursor consumes staged_awaiting_service on SoC
  --      alone — no atom required) or 'need_service' (STEP 2 above consumes it).
  --      Both consumers verified in live source. The loop closes: charge →
  --      charge_complete_holding → STEP 1.5/STEP 2 → need_deploy → re-gated.
  --   2. deploy_gate_patience_min (default 45 sim-min) → config.flagged_issue +
  --      flagged_issue_type='deploy_gate_stuck' so a technician sees it, counted in a
  --      WARNING summary event.
  --   3. deploy_gate_hard_cap_min (default 240 sim-min — longer than any bounded demo)
  --      → released anyway, stamped config.deploy_gate_override with a CRITICAL audit
  --      event. Loud and countable, never silent.
  -- Event budget: ONE summary event per call (plus one per rare override), not one per
  -- vehicle — event-write amplification is the known tick-cost driver.
  v_gate_on      := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_ready_gate_enabled',1),1) > 0;
  v_patience_dep := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_gate_patience_min',45),45);
  v_hardcap      := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_gate_hard_cap_min',240),240);
  v_relcap       := GREATEST(1, CEIL(v_deploy_cap * COALESCE(p_tick_minutes, 30) / 30.0))::int;
  v_admitted := 0;

  SELECT COUNT(*) INTO v_ncand FROM vehicles v
   WHERE v.home_depot_id = p_depot_id AND v.current_state = 'staged_awaiting_service'
     AND v.config->>'svc_step' = 'need_deploy';

  IF v_ncand > 0 THEN
    FOR v_rec IN
      WITH cand AS (
        SELECT v.id, v.current_soc, v.config, v.last_state_change
          FROM vehicles v
         WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
           AND v.current_state = 'staged_awaiting_service'
           AND v.config->>'svc_step' = 'need_deploy'
      ), card AS (
        SELECT c.vehicle_id, c.min_ready_soc_pct, c.must_do_now, c.fits_window, c.minutes_to_deploy
          FROM ottoq_vehicle_needs_card c
         WHERE v_gate_on
      ), ev AS (
        SELECT cd.id, cd.current_soc, cd.config, cd.last_state_change,
               GREATEST(v_floor, COALESCE(k.min_ready_soc_pct, v_floor)) AS ready_soc,
               COALESCE(k.must_do_now, '{}'::text[])                     AS card_must,
               k.fits_window, k.minutes_to_deploy,
               -- IDENTICAL predicate to ottoq_plan_dispatch_tick(deploy_plan)
               EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                        WHERE vn.vehicle_id = cd.id AND vn.sim_run_id = p_sim_run_id
                          AND vn.status IN ('open','in_progress')
                          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE COALESCE((a->>'must_do')::boolean,false) = true
                                         AND a->>'svc' <> 'readiness_check'
                                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')))
                                                                          AS work_open
          FROM cand cd LEFT JOIN card k ON k.vehicle_id = cd.id
      )
      SELECT ev.*,
             ((NOT v_gate_on) OR (ev.current_soc >= ev.ready_soc AND NOT ev.work_open)) AS ready
        FROM ev
       ORDER BY (CASE WHEN (NOT v_gate_on) OR (ev.current_soc >= ev.ready_soc AND NOT ev.work_open) THEN 0 ELSE 1 END),
                ev.last_state_change, ev.id
    LOOP
      IF v_rec.ready THEN
        -- deploy_cap_per_minute: v_deploy_cap is calibrated as releases per 30-MINUTE
        -- tick; rescale to the real tick length so throughput cannot change with tick size.
        IF v_admitted < v_relcap THEN
          UPDATE vehicles SET current_state = 'staged_for_departure'::vehicle_state, last_state_change = p_sim_clock_now,
                 config = jsonb_set(config, '{svc_step}', to_jsonb('ready'::text)) - 'deploy_gate'
           WHERE id = v_rec.id;
          v_admitted := v_admitted + 1;
        END IF;   -- over cap: stays need_deploy, retried next tick (unchanged behaviour)
      ELSE
        DECLARE
          v_since TIMESTAMPTZ; v_reason TEXT; v_missing TEXT[]; v_held_min NUMERIC; v_remedy TEXT;
        BEGIN
          v_since    := COALESCE((v_rec.config #>> '{deploy_gate,held_since}')::timestamptz, p_sim_clock_now);
          v_held_min := GREATEST(0, EXTRACT(EPOCH FROM (p_sim_clock_now - v_since))/60.0);
          v_reason   := CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN 'soc_below_ready' ELSE 'must_do_work_open' END;
          v_remedy   := CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN 'need_charge'     ELSE 'need_service' END;
          v_missing  := (CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN ARRAY['charge'] ELSE ARRAY[]::text[] END)
                        || COALESCE(v_rec.card_must, ARRAY[]::text[]);

          IF v_held_min >= v_hardcap THEN
            UPDATE vehicles SET current_state = 'staged_for_departure'::vehicle_state, last_state_change = p_sim_clock_now,
                   config = (jsonb_set(config, '{svc_step}', to_jsonb('ready'::text)) - 'deploy_gate')
                          || jsonb_build_object('deploy_gate_override', jsonb_build_object(
                               'at', p_sim_clock_now, 'held_min', round(v_held_min,1), 'reason', v_reason,
                               'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                               'missing', to_jsonb(v_missing), 'hard_cap_min', v_hardcap))
             WHERE id = v_rec.id;
            v_override := v_override + 1;
            PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
              p_event_type := 'twin.deploy_gate_override', p_entity_type := 'vehicle', p_entity_id := v_rec.id,
              p_payload := jsonb_build_object('held_min', round(v_held_min,1), 'hard_cap_min', v_hardcap,
                'reason', v_reason, 'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                'missing', to_jsonb(v_missing),
                'note', 'escape hatch 3: released past the readiness gate so the twin cannot wedge; this is a DEFECT to investigate, not a normal path'),
              p_severity := 'critical', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
          ELSE
            UPDATE vehicles
               SET config = jsonb_set(config, '{svc_step}', to_jsonb(v_remedy))
                          || jsonb_build_object('deploy_gate', jsonb_build_object(
                               'held_since', v_since, 'held_min', round(v_held_min,1),
                               'reason', v_reason, 'remedy', v_remedy,
                               'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                               'missing', to_jsonb(v_missing),
                               'card_must_do_now', to_jsonb(COALESCE(v_rec.card_must, ARRAY[]::text[])),
                               'fits_window', v_rec.fits_window,
                               'minutes_to_deploy', v_rec.minutes_to_deploy))
                          || CASE WHEN v_held_min >= v_patience_dep
                                  THEN jsonb_build_object('flagged_issue', true,
                                                          'flagged_issue_type', 'deploy_gate_stuck')
                                  ELSE '{}'::jsonb END
             WHERE id = v_rec.id;   -- last_state_change deliberately UNTOUCHED (queue order + patience metric)
            v_held := v_held + 1;
            IF v_held_min >= v_patience_dep THEN v_esc_gate := v_esc_gate + 1; END IF;
          END IF;
        END;
      END IF;
    END LOOP;

    IF v_held > 0 OR v_override > 0 THEN
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
        p_event_type := 'twin.deploy_gate_summary', p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('candidates', v_ncand, 'released', v_admitted,
          'held', v_held, 'escalated', v_esc_gate, 'overridden', v_override,
          'floor', v_floor, 'patience_min', v_patience_dep, 'hard_cap_min', v_hardcap,
          'gate_enabled', v_gate_on),
        p_severity := CASE WHEN v_override > 0 THEN 'critical'
                           WHEN v_esc_gate > 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- overflow now counts need_charge too: a vehicle held by the readiness gate is still
  -- waiting in staging and must not vanish from the queue telemetry.
  SELECT COUNT(*) INTO v_overflow FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'staged_awaiting_service' AND config->>'svc_step' IN ('need_service','need_deploy','need_charge');
  IF v_overflow > 0 THEN
    DECLARE v_patience NUMERIC := GREATEST(1, 10 + ottoq_apply_profile(p_sim_run_id, 'queue_patience', 0, 0)); v_escalated INT;
    BEGIN
      SELECT COUNT(*) INTO v_escalated FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'staged_awaiting_service'
         AND config->>'svc_step' IN ('need_service','need_deploy','need_charge') AND EXTRACT(EPOCH FROM (p_sim_clock_now - last_state_change))/60.0 > v_patience;
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.staging_overflow',
        p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('overflow', v_overflow, 'escalated', v_escalated, 'patience_min', ROUND(v_patience,1), 'wash_cap', v_wash_cap, 'svc_cap', v_svc_cap, 'deploy_cap', v_deploy_cap, 'gate_held', v_held),
        p_severity := CASE WHEN v_escalated > 0 THEN 'warning' ELSE 'info' END, p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END;
  END IF;

  out_washing   := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay'));
  out_servicing := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='in_service_bay');
  out_staged    := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='staged_awaiting_service');
  out_ready     := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='staged_for_departure');
  out_overflow  := v_overflow;
  RETURN NEXT;
END;
$function$

-- ===== ottoq_sim_advance_site_energy =====
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

-- ===== ottoq_sim_advance_visit_atoms =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_visit_atoms(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_seed bigint; v_rec RECORD; v_new jsonb; v_a jsonb; v_b jsonb;
  v_changed boolean; v_total int := 0;
  v_triage_done boolean; v_conf numeric; v_roll numeric; v_verdict text;
  v_escalations jsonb; v_tick bigint; v_feed_sim boolean := true;
BEGIN
  SELECT depot_id, COALESCE(random_seed,42), tick_count INTO v_depot, v_seed, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  SELECT COALESCE(d.feed_mode,'sim')='sim' INTO v_feed_sim FROM depots d WHERE d.id = v_depot;
  v_feed_sim := COALESCE(v_feed_sim, true);

  FOR v_rec IN
    SELECT vn.vehicle_id
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
       AND v.current_state IN ('charging_dcfc','charging_l2','charge_complete_holding',
                               'staged_awaiting_service','staged_for_departure','arrived_at_gate')
       -- M3_cabin_at_charger: cabin work (interior tidy) is performed BY A
       -- TECHNICIAN AT THE CHARGER during the session, so it may only start while the
       -- vehicle is plugged in. Previously it could start in any of six states —
       -- including at the gate and while staged for departure — which is why only 5.8%
       -- of interior cleans actually overlapped a charge. charge_complete_holding is
       -- kept ONLY as a catch-up: without it a vehicle whose charge finished before the
       -- tech arrived would never be cleaned and SLA.004 would block its deploy forever.
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE COALESCE(a->>'status','pending') = 'pending'
                      AND a->>'svc' <> 'readiness_check'
                      AND ( (a->>'concurrency' = 'cabin'
                               AND v.current_state IN ('charging_dcfc','charging_l2',
                                                       'charge_complete_holding'))
                         OR (a->>'concurrency' IN ('exterior','digital')) ))
     ORDER BY (vn.urgency = 'immediate_dispatch') DESC,
              (v.current_state IN ('charging_dcfc','charging_l2')) DESC,
              v.last_state_change ASC
     LIMIT 30
  LOOP
    PERFORM ottoq_start_concurrent_atoms(v_rec.vehicle_id, p_clock);
  END LOOP;

  FOR v_rec IN
    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
       AND (EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE a->>'status' = 'in_progress' AND (a->>'ends_at')::timestamptz <= p_clock)
         OR (v.current_state = 'staged_for_departure'
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'svc' = 'readiness_check' AND COALESCE(a->>'status','pending') = 'pending')))
  LOOP
    v_new := '[]'::jsonb; v_changed := false; v_triage_done := false; v_escalations := '[]'::jsonb;
    FOR v_a IN SELECT * FROM jsonb_array_elements(v_rec.atoms) LOOP
      IF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock THEN
        v_a := v_a || jsonb_build_object('status','done','done_at', v_a->'ends_at');
        v_changed := true; v_total := v_total + 1;
        -- N2/M4c: close the matching flow-contract leg with real times
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc',
                (v_a->>'started_at')::timestamptz, (v_a->>'ends_at')::timestamptz);
        IF v_a->>'svc' = 'triage_check' THEN v_triage_done := true; END IF;
        IF COALESCE((v_a->>'requires_tech_greenlight')::boolean,false) THEN
          INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, visit_id, sim_run_id, depot_id,
                 payload, requested_at, decide_after, expires_at, priority)
          SELECT 'tech_greenlight', v_rec.vehicle_id, v_rec.visit_id, p_sim_run_id, v_depot,
                 jsonb_build_object('svc', v_a->>'svc', 'est_min', v_a->>'est_min'),
                 p_clock,
                 p_clock + ((15 + floor(ottoq_sim_seeded_random(v_seed, v_rec.vehicle_id::text || ':glDelay') * 45))::text || ' minutes')::interval,
                 p_clock + interval '120 minutes', 'high'
          WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                             WHERE ap.vehicle_id = v_rec.vehicle_id AND ap.approval_type = 'tech_greenlight'
                               AND (ap.status = 'pending' OR ap.decided_at > p_clock - interval '60 minutes'));
        END IF;
      ELSIF v_a->>'svc' = 'readiness_check' AND COALESCE(v_a->>'status','pending') = 'pending'
         AND v_rec.current_state = 'staged_for_departure' THEN
        v_a := v_a || jsonb_build_object('status','done','done_at', to_jsonb(p_clock));
        v_changed := true; v_total := v_total + 1;
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, 'inspect',
                p_clock - interval '3 minutes', p_clock);
      END IF;
      v_new := v_new || jsonb_build_array(v_a);
    END LOOP;

    IF v_triage_done AND v_feed_sim THEN
      v_b := v_new; v_new := '[]'::jsonb;
      FOR v_a IN SELECT * FROM jsonb_array_elements(v_b) LOOP
        IF COALESCE((v_a->>'confirm_required')::boolean,false)
           AND COALESCE(v_a->>'status','pending') = 'pending' THEN
          v_conf := COALESCE((v_a->>'confidence')::numeric, 0.6);
          v_roll := ottoq_sim_seeded_random(v_seed, v_rec.vehicle_id::text || ':' || (v_a->>'svc') || ':verdict');
          v_verdict := CASE WHEN v_roll < v_conf THEN 'confirm'
                            WHEN v_roll < v_conf + (1 - v_conf) * 0.7 THEN 'clear'
                            ELSE 'escalate' END;
          IF v_verdict = 'confirm' THEN
            v_a := v_a || jsonb_build_object('confirm_required', false, 'triage_verdict', 'confirm');
          ELSIF v_verdict = 'clear' THEN
            v_a := v_a || jsonb_build_object('status','cancelled','confirm_required',false,
                     'triage_verdict','clear','cleared_by_triage',true);
            PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc', p_clock, p_clock);
          ELSE
            v_a := v_a || jsonb_build_object('confirm_required', false, 'triage_verdict', 'escalate');
            IF v_a->>'svc' = 'interior_tidy' THEN
              v_escalations := v_escalations || jsonb_build_array(jsonb_build_object(
                'svc','interior_deep_clean','must_do',false,'deferrable',true,'est_min',20,
                'concurrency','bay','requires_bay','detail','carryover_eligible',true,'from_escalation',true));
            ELSIF v_a->>'svc' = 'sensor_clean' THEN
              v_escalations := v_escalations || jsonb_build_array(jsonb_build_object(
                'svc','sensor_calibration','must_do',false,'deferrable',true,'est_min',30,
                'concurrency','bay','requires_bay','service_bay','carryover_eligible',true,'from_escalation',true));
            ELSIF v_a->>'svc' = 'cosmetic_repair' THEN
              v_a := v_a || jsonb_build_object('requires_tech_greenlight', true);
            END IF;
          END IF;
          INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,action_context,resolved_action_context,
                 entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
          VALUES (p_sim_run_id, v_tick, p_clock, v_depot, 'task_start', 'triage_verdict',
                 'vehicle', v_rec.vehicle_id,
                 jsonb_build_object('svc', v_a->>'svc', 'confidence', v_conf),
                 jsonb_build_object('verb','triage'),
                 jsonb_build_object('verb','triage_' || v_verdict, 'svc', v_a->>'svc'),
                 'enacted', 0, 0);
        END IF;
        v_new := v_new || jsonb_build_array(v_a);
      END LOOP;
      IF jsonb_array_length(v_escalations) > 0 THEN
        FOR v_a IN SELECT * FROM jsonb_array_elements(v_escalations) LOOP
          IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) e WHERE e->>'svc' = v_a->>'svc') THEN
            v_new := v_new || jsonb_build_array(v_a);
          END IF;
        END LOOP;
      END IF;
      v_changed := true;
    END IF;

    IF v_changed THEN UPDATE ottoq_visit_needs SET atoms = v_new WHERE visit_id = v_rec.visit_id; END IF;
  END LOOP;

  UPDATE ottoq_visit_needs vn SET status =
    CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                       WHERE COALESCE((a->>'carryover_eligible')::boolean,false)
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
         THEN 'carried_over' ELSE 'complete' END
  FROM vehicles v
  WHERE v.id = vn.vehicle_id AND vn.depot_id = v_depot
    AND vn.status IN ('open','in_progress')
    AND v.current_state IN ('deployed','en_route_to_deployment');
  RETURN v_total;
END; $function$

-- ===== ottoq_sim_advance_wear_counters =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_wear_counters(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric, p_tick_seq bigint, p_dispatch_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot        uuid;
  v_precip       numeric := 0;
  v_day          text;
  v_soil_rate    numeric;  v_soil_decay numeric;  v_litter_p numeric;
  v_precip_coup  numeric;
  v_attempted    int := 0;  v_written int := 0; v_nseed bigint;
BEGIN
  SELECT depot_id, COALESCE(random_seed, 42) INTO v_depot, v_nseed FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  -- R2: NO CARD DEALING. A prior design called ottoq_twin_climate_stress at the
  -- top of every tick, which transitively INSERTs a precip_mm row into
  -- ottoq_variability_cards on a cache miss. On an idle tick the substrate would
  -- become the first caller of the sim-day and deal a card the control arm never
  -- creates — and because the generator branches on YESTERDAY's card, the day can
  -- flip wet/dry, which scales the ETA card, which writes scheduled_return_at.
  -- A substrate claiming byte-identity must not deal cards. Pure read; absent = 0.
  v_day := to_char(p_sim_clock_now, 'YYYY-MM-DD');
  BEGIN
    SELECT (value)::numeric INTO v_precip
      FROM ottoq_variability_cards
     WHERE sim_run_id = p_sim_run_id AND var_key = 'precip_mm'
       AND bucket_key = 'day:' || v_day
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_precip := 0; END;
  v_precip := COALESCE(v_precip, 0);

  -- versioned parameters, not COALESCE literals buried in un-versioned source
  v_soil_rate   := COALESCE(ottoq_policy_get(p_sim_run_id,'soil_rate_per_km',        0.0016), 0.0016);
  v_soil_decay  := COALESCE(ottoq_policy_get(p_sim_run_id,'soil_decay_per_tick',     0.010),  0.010);
  v_litter_p    := COALESCE(ottoq_policy_get(p_sim_run_id,'litter_p_per_active_min', 0.004),  0.004);
  v_precip_coup := COALESCE(ottoq_policy_get(p_sim_run_id,'precip_soil_coupling',    0.5),    0.5);

  SELECT COALESCE(array_length(p_dispatch_ids,1),0) INTO v_attempted;

  -- R1: operate on the dispatch ids SNAPSHOTTED BY THE CALLER BEFORE telemetry
  -- ran. ottoq_sim_advance_deployed_telemetry flips returning->completed inside
  -- its own loop, so a fresh SELECT ... WHERE status IN ('active','returning')
  -- here would miss the final tick of every dispatch — mean trip 4.86 ticks, so
  -- ~20.6% of drive-ticks dropped, biased toward the leg home, making PM and
  -- calibration come due LATE while the substrate audits itself as correct.
  WITH moving AS (
    SELECT d.vehicle_id,
           COALESCE((
             SELECT tp.speed_kmh FROM ottoq_telemetry_packets tp
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
              ORDER BY tp.sim_clock_at DESC LIMIT 1), 0) AS speed_kmh,
           COALESCE((
             SELECT ottoq_dtc_severity_rank(dc.severity)
               FROM ottoq_telemetry_packets tp
               CROSS JOIN LATERAL unnest(COALESCE(tp.dtc_codes, ARRAY[]::text[])) AS code
               JOIN ottoq_dtc_catalog dc ON dc.dtc_code = code
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
                AND tp.sim_clock_at > p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
              ORDER BY 1 ASC LIMIT 1), 99) AS tick_worst_rank,
           COALESCE((
             SELECT count(*) FROM ottoq_telemetry_packets tp
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
                AND tp.sim_clock_at > p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
                AND COALESCE(array_length(tp.dtc_codes,1),0) > 0), 0) AS tick_dtc_rows,
           COALESCE((SELECT (vv.config->>'soil_rate')::numeric FROM vehicles vv WHERE vv.id = d.vehicle_id), 1.0) AS veh_soil_scalar
      FROM ottoq_vehicle_dispatches d
     WHERE d.dispatch_id = ANY(p_dispatch_ids)
  ), calc AS (
    SELECT m.vehicle_id,
           (m.speed_kmh * p_tick_minutes / 60.0) AS km_tick,
           CASE WHEN m.speed_kmh > 0 THEN p_tick_minutes / 60.0 ELSE 0 END AS hours_tick,
           m.tick_worst_rank, m.tick_dtc_rows, m.veh_soil_scalar
      FROM moving m
  ), upsert AS (
    INSERT INTO ottoq_vehicle_wear AS w (
      vehicle_id, sim_run_id, drive_km_total, drive_hours_total,
      soil_index, cabin_litter_events, open_dtc_count, worst_open_dtc_rank,
      last_advanced_tick, last_advanced_sim_clock, km_per_tick_ema, drive_ticks_observed)
    SELECT c.vehicle_id, p_sim_run_id, c.km_tick, c.hours_tick,
           LEAST(1.0, GREATEST(0, c.km_tick * v_soil_rate * c.veh_soil_scalar * (1 + v_precip * v_precip_coup))),
           CASE WHEN c.hours_tick > 0
                  AND ottoq_sim_seeded_random(
                        abs(hashtextextended(v_nseed::text || c.vehicle_id::text, 7)),
                        'litter:' || p_tick_seq::text)
                      < LEAST(0.95, v_litter_p * p_tick_minutes * (1 + v_precip * v_precip_coup))
                THEN 1 ELSE 0 END,
           c.tick_dtc_rows, c.tick_worst_rank,
           p_tick_seq, p_sim_clock_now, c.km_tick, CASE WHEN c.hours_tick > 0 THEN 1 ELSE 0 END
      FROM calc c
    ON CONFLICT (vehicle_id, sim_run_id) DO UPDATE SET
      -- R3: COMPOSITE IDEMPOTENCY FENCE. A prior design fenced on
      -- last_advanced_tick alone against a vehicle-only key; p_tick_seq is a
      -- PER-RUN counter restarting at 1, so the second soak run matched
      -- tick-for-tick and updated ZERO rows silently. Keyed per run, the fence is
      -- exact: re-running the same tick of the same run is a no-op, a different
      -- run is a different row.
      drive_km_total    = w.drive_km_total    + EXCLUDED.drive_km_total,
      drive_hours_total = w.drive_hours_total + EXCLUDED.drive_hours_total,
      -- R4: soil DECAYS. Measured 17.1 km/tick at the default rate saturates the
      -- index at 1.0 in ~37 ticks = 0.76 sim-days — INSIDE the 48-tick soak meant
      -- to calibrate it. Once pinned, both wash thresholds are permanently
      -- exceeded and non-deferrable sensor_clean fires for every arrival.
      soil_index = LEAST(1.0, GREATEST(0,
                     w.soil_index
                     + EXCLUDED.soil_index
                     -- soil_decay_tick_invariant: the policy value is calibrated
                     -- PER 30-MINUTE TICK; rescale to the actual tick length so
                     -- changing tick size cannot change how dirty the fleet gets.
                     - (v_soil_decay * COALESCE(p_tick_minutes, 30) / 30.0))),
      cabin_litter_events = w.cabin_litter_events + EXCLUDED.cabin_litter_events,
      open_dtc_count      = w.open_dtc_count      + EXCLUDED.open_dtc_count,
      -- R5: LEAST is monotone toward severity, so a later 'info' can never
      -- overwrite a stored 'safety_critical'. Cleared only via mark_serviced.
      worst_open_dtc_rank = LEAST(w.worst_open_dtc_rank, EXCLUDED.worst_open_dtc_rank),
      last_advanced_tick      = EXCLUDED.last_advanced_tick,
      last_advanced_sim_clock = EXCLUDED.last_advanced_sim_clock,
      km_per_tick_ema  = (w.km_per_tick_ema * 0.7) + (EXCLUDED.km_per_tick_ema * 0.3),
      drive_ticks_observed = w.drive_ticks_observed + EXCLUDED.drive_ticks_observed,
      updated_at = now()
    WHERE w.last_advanced_tick IS DISTINCT FROM p_tick_seq
    RETURNING 1
  )
  SELECT count(*) INTO v_written FROM upsert;

  RETURN COALESCE(v_written,0);
END;
$function$

-- ===== ottoq_sim_advance_weather_and_solar =====
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

-- ===== ottoq_sim_auto_charge_assign_tick =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_auto_charge_assign_tick(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle    RECORD;
  v_stall_id   UUID;
  v_count      INTEGER := 0;
  v_session_id UUID;
  v_target_soc NUMERIC;
  v_seed       BIGINT;
BEGIN
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42') || p_sim_clock_now::text || 'assign', 13));

  FOR v_vehicle IN
    SELECT id, current_soc, target_soc, fleet_operator_id, inlet_type, home_depot_id
      FROM vehicles
     WHERE current_state = 'arrived_at_gate'
       AND category = 'autonomous'
       AND current_soc < 85
     ORDER BY current_soc ASC                          -- lowest SOC first (most urgent)
  LOOP
    v_stall_id := NULL;                                -- FIX 3: never inherit the previous vehicle's stall

    -- DCFC if low SOC; L2 otherwise
    IF v_vehicle.current_soc < 50 THEN
      SELECT s.id INTO v_stall_id
        FROM stalls s
        LEFT JOIN ocpp_sessions cs
               ON cs.stall_id = s.id
              AND cs.status = 'active'::ocpp_session_status   -- FIX 1: real label, index-usable
              AND cs.sim_run_id = p_sim_run_id                -- FIX 2: run-scoped
              AND (cs.ended_at IS NULL OR cs.ended_at > p_sim_clock_now)
       WHERE s.depot_id = v_vehicle.home_depot_id
         AND s.stall_type = 'dcfc'::stall_type
         AND s.current_vehicle_id IS NULL                     -- physically empty too
         AND cs.id IS NULL
       ORDER BY ottoq_sim_seeded_random(v_seed, 'dcfc:' || s.id::text)
       LIMIT 1;
    END IF;

    IF v_stall_id IS NULL THEN
      SELECT s.id INTO v_stall_id
        FROM stalls s
        LEFT JOIN ocpp_sessions cs
               ON cs.stall_id = s.id
              AND cs.status = 'active'::ocpp_session_status
              AND cs.sim_run_id = p_sim_run_id
              AND (cs.ended_at IS NULL OR cs.ended_at > p_sim_clock_now)
       WHERE s.depot_id = v_vehicle.home_depot_id
         AND s.stall_type = 'l2'::stall_type
         AND s.current_vehicle_id IS NULL
         AND cs.id IS NULL
       ORDER BY ottoq_sim_seeded_random(v_seed, 'l2:' || s.id::text)
       LIMIT 1;
    END IF;

    -- Couldn't find a free stall — leave vehicle queued at gate. THIS IS THE POINT:
    -- a naive assigner must feel charger scarcity, which it never did before.
    IF v_stall_id IS NULL THEN CONTINUE; END IF;

    -- A.10: target_soc knob shifts the charge target (clamped 50-100%)
    v_target_soc := GREATEST(50, LEAST(100,
      ottoq_apply_profile(p_sim_run_id, 'target_soc', COALESCE(v_vehicle.target_soc, 90), COALESCE(v_vehicle.target_soc, 90))));

    BEGIN
      v_session_id := ottoq_sim_start_charge_session(
        v_vehicle.id, v_stall_id, p_sim_run_id, v_target_soc, p_sim_clock_now);
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;        -- lost a race, or uniq_ocpp_active_session_per_stall fired; skip this tick
    END;

    v_count := v_count + 1;

    PERFORM ottoq_record_event(
      p_actor_type    := 'ottoq_engine',
      p_actor_id      := 'twin_auto_charge_assigner',
      p_event_type    := 'twin.auto_charge_assign',
      p_entity_type   := 'vehicle',
      p_entity_id     := v_vehicle.id,
      p_payload       := jsonb_build_object(
        'session_id', v_session_id, 'soc_at_assign', v_vehicle.current_soc,
        'target_soc', v_target_soc),
      p_severity      := 'info',
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  END LOOP;

  RETURN v_count;
END;
$function$

-- ===== ottoq_sim_auto_dispatch_tick =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_auto_dispatch_tick(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE; v_scenario ottoq_sim_scenarios%ROWTYPE;
  v_hour INTEGER; v_dispatch_mult NUMERIC := 1.0; v_target_deployed_pct NUMERIC := 0.90;
  v_total_fleet INTEGER; v_currently_deployed INTEGER; v_desired_deployed INTEGER;
  v_to_dispatch INTEGER; v_vehicle RECORD; v_count INTEGER := 0; v_seed BIGINT;
  v_recall_on boolean; v_win_start int; v_win_end int; v_hyst int; v_holdout_pct int;
  v_to_recall int; v_cap int; v_recalled int := 0;
  v_sec RECORD; v_eta numeric;
  v_release_cap int; v_valved int := 0; v_forced boolean;
  v_plan jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  SELECT s.* INTO v_scenario FROM ottoq_sim_scenarios s
   WHERE s.scenario_code = COALESCE(v_run.scenario_code, 'normal_day') LIMIT 1;
  IF v_scenario.scenario_code IS NULL THEN
    SELECT * INTO v_scenario FROM ottoq_sim_scenarios WHERE scenario_code = 'normal_day';
  END IF;
  v_dispatch_mult       := COALESCE((v_scenario.fleet_overrides->>'dispatch_rate_multiplier')::numeric, 1.0);
  v_target_deployed_pct := COALESCE((v_scenario.fleet_overrides->>'target_deployed_fraction')::numeric, 0.90);

  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_seed := abs(hashtextextended(COALESCE(v_run.random_seed, 42)::text || p_sim_clock_now::text || 'disp', 7));

  SELECT COUNT(*) INTO v_total_fleet FROM vehicles
   WHERE category = 'autonomous' AND home_depot_id = v_run.depot_id;
  SELECT COUNT(*) INTO v_currently_deployed
    FROM ottoq_vehicle_dispatches
   WHERE sim_run_id = p_sim_run_id AND status IN ('active', 'returning');

  v_desired_deployed := FLOOR(v_total_fleet * ottoq_deploy_target_fraction(
      v_hour, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction', v_target_deployed_pct)) * v_dispatch_mult);

  v_to_dispatch := GREATEST(0, v_desired_deployed - v_currently_deployed);

  -- (1) DEPLOY toward the target. OTTO-Q ranks and paces; the twin departs them.
  IF v_to_dispatch > 0 THEN
    v_plan := ottoq_plan_dispatch_tick(
                'deploy_plan', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                p_hour := v_hour, p_seed := v_seed, p_to_dispatch := v_to_dispatch);
    v_release_cap := COALESCE((v_plan->>'cap')::int, 1);
    v_forced      := COALESCE((v_plan->>'forced')::boolean, false);

    FOR v_vehicle IN
      SELECT t.value::uuid AS id
        FROM jsonb_array_elements_text(COALESCE(v_plan->'release','[]'::jsonb)) WITH ORDINALITY AS t(value, ord)
       ORDER BY t.ord
    LOOP
      PERFORM ottoq_sim_dispatch_vehicle(v_vehicle.id, p_sim_run_id, p_sim_clock_now);
      v_count := v_count + 1;
    END LOOP;

    IF jsonb_array_length(COALESCE(v_plan->'hold','[]'::jsonb)) > 0 THEN
      v_valved := COALESCE((ottoq_plan_dispatch_tick(
                    'deploy_hold', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                    p_vehicles := v_plan->'hold', p_forced := v_forced)->>'held')::int, 0);
    END IF;

    IF v_valved > 0 THEN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'rush_valve',
        p_event_type := 'twin.rush_valve_hold', p_entity_type := 'system',
        p_payload := jsonb_build_object('held', v_valved, 'released', v_count,
          'cap', v_release_cap, 'forced', v_forced, 'hour_cst', v_hour),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := p_sim_run_id);
    END IF;

    IF v_count > 0 THEN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'twin_auto_dispatcher',
        p_event_type := 'twin.auto_dispatch_emit', p_entity_type := 'system',
        p_payload := jsonb_build_object('count', v_count, 'hour_cst', v_hour, 'scenario', v_scenario.scenario_code,
          'total_fleet', v_total_fleet, 'desired', v_desired_deployed, 'deployed', v_currently_deployed),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- (2) OVERNIGHT SURPLUS RECALL. Twin measures the surplus (a demand fact) and
  -- applies the world writes; OTTO-Q ranks it and secures the appointments.
  v_recall_on   := ottoq_policy_get(p_sim_run_id,'overnight_recall_enabled',1) > 0;
  v_win_start   := ottoq_policy_get(p_sim_run_id,'overnight_recall_start_hour',22)::int;
  v_win_end     := ottoq_policy_get(p_sim_run_id,'overnight_recall_end_hour',3)::int;
  v_hyst        := ottoq_policy_get(p_sim_run_id,'overnight_recall_hysteresis',2)::int;
  v_holdout_pct := ottoq_policy_get(p_sim_run_id,'overnight_holdout_pct',1)::int;

  IF v_recall_on AND (v_hour >= v_win_start OR v_hour < 6) THEN
    v_to_recall := GREATEST(0, v_currently_deployed - v_desired_deployed - v_hyst);
    IF v_to_recall > 0 THEN
      v_plan := ottoq_plan_dispatch_tick(
                  'recall', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                  p_hour := v_hour, p_to_recall := v_to_recall, p_holdout_pct := v_holdout_pct,
                  p_win_start := v_win_start, p_win_end := v_win_end,
                  p_tick_minutes_actual := COALESCE((v_run.payload->>'tick_minutes_actual')::numeric,
                                                    (v_run.tick_interval_seconds::numeric * COALESCE(v_run.time_scale,1))/60.0,
                                                    30));
      v_cap := COALESCE((v_plan->>'cap')::int, 0);

      FOR v_sec IN
        SELECT t.value AS d
          FROM jsonb_array_elements(COALESCE(v_plan->'secured','[]'::jsonb)) WITH ORDINALITY AS t(value, ord)
         ORDER BY t.ord
      LOOP
        v_eta := (v_sec.d->>'eta_minutes')::numeric;
        UPDATE ottoq_vehicle_dispatches
           SET status='returning', return_trigger='surplus_to_demand',
               returning_started_at = p_sim_clock_now,
               return_eta_minutes = v_eta,
               scheduled_return_at = p_sim_clock_now + (v_eta || ' minutes')::interval,
               return_evidence = jsonb_build_object('decided_at',p_sim_clock_now,
                 'soc_at_decision',(v_sec.d->>'soc_at_decision')::int,'hour_cst',v_hour,
                 'reason','overnight_surplus_to_demand','appointment',v_sec.d->'appointment',
                 'desired_deployed',v_desired_deployed,'currently_deployed',v_currently_deployed)
         WHERE dispatch_id = (v_sec.d->>'dispatch_id')::uuid;
        UPDATE vehicles SET current_state='en_route_to_depot'::vehicle_state, last_state_change=p_sim_clock_now
         WHERE id = (v_sec.d->>'vehicle_id')::uuid;
        v_recalled := v_recalled + 1;
      END LOOP;

      IF v_recalled > 0 THEN
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='overnight_recall',
          p_event_type:='twin.overnight_surplus_recall', p_entity_type:='system',
          p_payload:=jsonb_build_object('recalled',v_recalled,'hour_cst',v_hour,
            'desired',v_desired_deployed,'deployed_before',v_currently_deployed,'cap',v_cap,
            'holdout_active', NOT (v_hour >= v_win_end AND v_hour < v_win_start)),
          p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
      END IF;
    END IF;
  END IF;

  RETURN v_count;
END;
$function$

-- ===== ottoq_sim_bay_fault_handler =====
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

-- ===== ottoq_sim_bess_apply_degradation =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_bess_apply_degradation(p_bess_id uuid, p_tick_minutes numeric, p_kwh_throughput numeric, p_seed bigint)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_capacity       NUMERIC;
  v_fce_delta      NUMERIC;
  v_cycle_fade     NUMERIC;
  v_cal_fade       NUMERIC;
  v_noise          NUMERIC;
  v_delta_soh      NUMERIC;
BEGIN
  SELECT capacity_kwh INTO v_capacity FROM ottoq_bess_units WHERE bess_id = p_bess_id;
  IF v_capacity IS NULL OR v_capacity = 0 THEN RETURN 0; END IF;

  -- FCE = full-cycle equivalent (kWh throughput / (2 × capacity))
  v_fce_delta := p_kwh_throughput / (2.0 * v_capacity);

  -- Cycle fade: 0.005% per FCE × small noise
  v_noise      := 0.9 + ottoq_sim_seeded_random(p_seed, 'soh') * 0.2;
  v_cycle_fade := -0.00005 * v_fce_delta * v_noise * 100;     -- in % units

  -- Calendar fade: 0.5%/yr → per-minute = 0.5/525600
  v_cal_fade   := -(0.5 / 525600.0) * p_tick_minutes;

  v_delta_soh  := v_cycle_fade + v_cal_fade;

  -- Apply to unit
  UPDATE ottoq_bess_units
     SET current_soh_pct      = GREATEST(60, current_soh_pct + v_delta_soh),
         current_cycle_count  = current_cycle_count + v_fce_delta,
         lifetime_kwh_charged = lifetime_kwh_charged
                              + GREATEST(0, p_kwh_throughput / 2.0),       -- half is charge
         lifetime_kwh_discharged = lifetime_kwh_discharged
                                  + GREATEST(0, p_kwh_throughput / 2.0),
         updated_at = NOW()
   WHERE bess_id = p_bess_id;

  RETURN v_delta_soh;
END;
$function$

-- ===== ottoq_sim_bess_compute_max_power_kw =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_bess_compute_max_power_kw(p_bess_id uuid, p_direction text, p_temp_c numeric DEFAULT NULL::numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v               ottoq_bess_units%ROWTYPE;
  v_nameplate     NUMERIC;
  v_soc_factor    NUMERIC := 1.0;
  v_soh_factor    NUMERIC;
  v_temp_factor   NUMERIC := 1.0;
  v_temp          NUMERIC;
BEGIN
  SELECT * INTO v FROM ottoq_bess_units WHERE bess_id = p_bess_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_temp := COALESCE(p_temp_c, v.current_temperature_c, 25);

  IF p_direction = 'charge' THEN
    v_nameplate := v.max_charge_kw;
    -- Taper as we approach ceiling
    IF v.current_soc_pct > 90 THEN
      v_soc_factor := GREATEST(0, (v.soc_max_ceiling_pct - v.current_soc_pct)
                                   / (v.soc_max_ceiling_pct - 90));
    END IF;
  ELSE
    v_nameplate := v.max_discharge_kw;
    -- Taper as we approach floor
    IF v.current_soc_pct < 15 THEN
      v_soc_factor := GREATEST(0, (v.current_soc_pct - v.soc_min_floor_pct)
                                   / (15 - v.soc_min_floor_pct));
    END IF;
  END IF;

  v_soh_factor := COALESCE(v.current_soh_pct, 100) / 100.0;

  -- Thermal derate
  IF v_temp > 45 THEN
    v_temp_factor := GREATEST(0.3, 1.0 - (v_temp - 45) * 0.02);
  ELSIF v_temp < 5 THEN
    v_temp_factor := GREATEST(0.3, 1.0 - (5 - v_temp) * 0.025);
  END IF;

  RETURN GREATEST(0, v_nameplate * v_soc_factor * v_soh_factor * v_temp_factor);
END;
$function$

-- ===== ottoq_sim_bess_default_target_kw =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_bess_default_target_kw(p_bess_id uuid, p_sim_clock_now timestamp with time zone, p_solar_ac_kw numeric DEFAULT 0)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v     ottoq_bess_units%ROWTYPE;
  v_hr  INTEGER;
BEGIN
  SELECT * INTO v FROM ottoq_bess_units WHERE bess_id = p_bess_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_hr := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  -- Discharge in peak hours when SOC healthy
  IF v_hr BETWEEN 14 AND 19 AND v.current_soc_pct > 30 THEN
    RETURN -1 * LEAST(v.max_discharge_kw * 0.7, v.max_discharge_kw);
  END IF;

  -- Charge from solar surplus
  IF p_solar_ac_kw > 200 AND v.current_soc_pct < 90 THEN
    RETURN LEAST(p_solar_ac_kw * 0.6, v.max_charge_kw * 0.8);
  END IF;

  -- Off-peak top-up at night
  IF v_hr BETWEEN 0 AND 5 AND v.current_soc_pct < 70 THEN
    RETURN v.max_charge_kw * 0.5;
  END IF;

  RETURN 0;
END;
$function$

-- ===== ottoq_sim_bess_default_target_kw =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_bess_default_target_kw(p_bess_id uuid, p_sim_clock_now timestamp with time zone, p_solar_ac_kw numeric DEFAULT 0, p_site_load_kw numeric DEFAULT NULL::numeric, p_peak_so_far_kw numeric DEFAULT NULL::numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v          ottoq_bess_units%ROWTYPE;
  v_hr       INTEGER;
  v_want     NUMERIC;
  v_headroom NUMERIC;
BEGIN
  SELECT * INTO v FROM ottoq_bess_units WHERE bess_id = p_bess_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_hr := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  -- Discharge in peak hours when SOC healthy  (unchanged)
  IF v_hr BETWEEN 14 AND 19 AND v.current_soc_pct > 30 THEN
    RETURN -1 * LEAST(v.max_discharge_kw * 0.7, v.max_discharge_kw);
  END IF;

  -- Charge from solar surplus  (unchanged: surplus generation, adds no grid draw)
  IF p_solar_ac_kw > 200 AND v.current_soc_pct < 90 THEN
    RETURN LEAST(p_solar_ac_kw * 0.6, v.max_charge_kw * 0.8);
  END IF;

  -- Off-peak top-up at night -- NOW DEMAND-LIMITED
  IF v_hr BETWEEN 0 AND 5 AND v.current_soc_pct < 70 THEN
    v_want := v.max_charge_kw * 0.5;

    -- Unknown site conditions (no history yet, or a legacy 3-arg caller):
    -- behave exactly as before so nothing silently changes.
    IF p_site_load_kw IS NULL OR p_peak_so_far_kw IS NULL OR p_peak_so_far_kw <= 0 THEN
      RETURN v_want;
    END IF;

    -- Standard demand limiting: charge only into headroom under the peak this
    -- site has ALREADY hit. Never sets a new peak.
    v_headroom := GREATEST(0, p_peak_so_far_kw - p_site_load_kw);
    RETURN LEAST(v_want, v_headroom);
  END IF;

  RETURN 0;
END;
$function$

-- ===== ottoq_sim_bess_step =====
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

-- ===== ottoq_sim_build_arrival_payload =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_build_arrival_payload(p_oem text, p_vehicle record, p_sim_clock_now timestamp with time zone, p_arrival_soc numeric, p_dispatch_id uuid, p_seed bigint, p_complete boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_payload JSONB;
  v_drop_optional BOOLEAN := NOT p_complete;
  v_odo NUMERIC := COALESCE((p_vehicle.config->>'lifetime_miles')::numeric, 0)
                  + COALESCE((SELECT SUM(miles_driven) FROM ottoq_vehicle_dispatches
                              WHERE vehicle_id = p_vehicle.id AND status = 'completed'), 0);
BEGIN
  IF p_oem = 'waymo' THEN
    v_payload := jsonb_build_object(
      'vehicle_id',   p_vehicle.av_api_vehicle_id,
      'arrival_at',   to_char(p_sim_clock_now AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'gate_id',      'OTTOYARD-NASH-GATE-INGRESS',
      'soc_pct',      ROUND(p_arrival_soc::numeric, 1)
    );
    IF NOT v_drop_optional THEN
      v_payload := v_payload
        || jsonb_build_object(
             'estimated_service_minutes',
               FLOOR(15 + ottoq_sim_seeded_random(p_seed, 'svc') * 30)::int,
             'flags',
               CASE WHEN (p_vehicle.config->>'flagged_issue')::boolean
                 THEN jsonb_build_array(p_vehicle.config->>'flagged_issue_type')
                 ELSE '[]'::jsonb END,
             'odometer_mi',  ROUND(v_odo::numeric, 1),
             'heading_deg',  FLOOR(ottoq_sim_seeded_random(p_seed, 'hdg') * 360)::int,
             'health_status', CASE
               WHEN (p_vehicle.config->>'battery_soh_pct')::numeric > 90 THEN 'green'
               WHEN (p_vehicle.config->>'battery_soh_pct')::numeric > 85 THEN 'yellow'
               ELSE 'amber' END);
    END IF;

  ELSIF p_oem = 'tesla' THEN
    v_payload := jsonb_build_object(
      'id',                  p_vehicle.av_api_vehicle_id,
      'arrival_timestamp',   EXTRACT(EPOCH FROM p_sim_clock_now)::bigint,
      'gate',                'NASH-A',
      'soc',                 ROUND(p_arrival_soc::numeric, 0)
    );
    IF NOT v_drop_optional THEN
      v_payload := v_payload
        || jsonb_build_object(
             'est_charge_min', FLOOR(20 + ottoq_sim_seeded_random(p_seed, 'tsl_chg') * 40)::int,
             'alerts',
               CASE WHEN (p_vehicle.config->>'flagged_issue')::boolean
                 THEN jsonb_build_array(p_vehicle.config->>'flagged_issue_type')
                 ELSE '[]'::jsonb END,
             'odo_km',         ROUND((v_odo * 1.60934)::numeric, 1),
             'drive_state',    'parked',
             'vehicle_state',  'online');
    END IF;

  ELSIF p_oem = 'zoox' THEN
    v_payload := jsonb_build_object(
      'vehicle_uuid',     p_vehicle.id::text,
      'gate_arrival_ts',  to_char(p_sim_clock_now AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'gate_node',        'ottoyard_nashville_gate_a',
      'soc_pct',          ROUND(p_arrival_soc::numeric, 2)
    );
    IF NOT v_drop_optional THEN
      v_payload := v_payload
        || jsonb_build_object(
             'telemetry_burst', jsonb_build_object(
                'battery_temp_c', ROUND((28 + ottoq_sim_seeded_random(p_seed,'zx_bt') * 12)::numeric, 1),
                'motor_temp_c',   ROUND((35 + ottoq_sim_seeded_random(p_seed,'zx_mt') * 20)::numeric, 1),
                'cabin_temp_c',   ROUND((19 + ottoq_sim_seeded_random(p_seed,'zx_ct') * 6)::numeric, 1)
              ),
             'next_dispatch_eta_min',
               FLOOR(45 + ottoq_sim_seeded_random(p_seed, 'zx_eta') * 120)::int,
             'cargo_state',  'empty',
             'sensor_health', CASE
               WHEN ottoq_sim_seeded_random(p_seed, 'zx_sh') > 0.05 THEN 'nominal'
               ELSE 'degraded_lidar_3' END);
    END IF;
  END IF;

  v_payload := v_payload
    || jsonb_build_object('_internal_dispatch_id', p_dispatch_id::text,
                          '_schema_version',       (SELECT payload_schema_version FROM ottoq_oem_webhook_patterns WHERE oem_name = p_oem));

  RETURN v_payload;
END;
$function$

-- ===== ottoq_sim_cell_temp_c =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_cell_temp_c(p_ambient_c numeric, p_poa_wm2 numeric, p_wind_kmh numeric DEFAULT 5)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- T_cell = T_amb + (NOCT - 20) × POA / 800 × wind_factor
  -- NOCT = 45°C typical; wind reduces cell temp slightly
  SELECT p_ambient_c
       + (45.0 - 20.0) * (p_poa_wm2 / 800.0)
         * GREATEST(0.65, 1.0 - 0.02 * LEAST(p_wind_kmh, 20));
$function$

-- ===== ottoq_sim_clear_sky_ghi_wm2 =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_clear_sky_ghi_wm2(p_elev_deg numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_air_mass   NUMERIC;
  v_solar_const NUMERIC := 1361.0;        -- TOA solar constant W/m²
  v_ghi        NUMERIC;
BEGIN
  IF p_elev_deg <= 0 THEN
    RETURN 0;                              -- below horizon
  END IF;

  -- Air mass (Kasten-Young for low elevations)
  v_air_mass := 1.0 / (SIN(RADIANS(p_elev_deg))
                       + 0.50572 * POWER(GREATEST(p_elev_deg + 6.07995, 0.01), -1.6364));

  -- Atmospheric attenuation × cos(zenith) = sin(elevation)
  v_ghi := v_solar_const
         * POWER(0.7, POWER(v_air_mass, 0.678))
         * SIN(RADIANS(p_elev_deg));

  RETURN GREATEST(0, v_ghi);
END;
$function$

-- ===== ottoq_sim_cloud_attenuated_ghi =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_cloud_attenuated_ghi(p_clear_sky_ghi numeric, p_cloud_pct numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT GREATEST(0,
    p_clear_sky_ghi * (1.0 - 0.75 * POWER(LEAST(p_cloud_pct, 100) / 100.0, 3.4)));
$function$

-- ===== ottoq_sim_compute_building_load_kw =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_compute_building_load_kw(p_depot_id uuid, p_sim_clock_now timestamp with time zone, p_ambient_c numeric, p_seed bigint, p_salt text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hour      INTEGER;
  v_dow       INTEGER;
  v_hvac_kw   NUMERIC;
  v_lighting_kw NUMERIC;
  v_service_kw NUMERIC;
  v_wash_kw   NUMERIC;
  v_base_kw   NUMERIC := 6;
  v_noise     NUMERIC;
BEGIN
  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_dow  := EXTRACT(DOW  FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  -- HVAC: U-shaped vs ambient (heating cold + cooling hot), modulated by hour
  v_hvac_kw := 14 + 1.2 * GREATEST(0, p_ambient_c - 22)        -- AC ramp
                  + 1.5 * GREATEST(0, 18 - p_ambient_c);        -- heat ramp
  IF v_hour BETWEEN 22 AND 5 THEN
    v_hvac_kw := v_hvac_kw * 0.55;                              -- setback at night
  END IF;

  -- Lighting: perimeter on at night, interior modulates with hour
  v_lighting_kw := CASE
    WHEN v_hour BETWEEN 20 AND 23 OR v_hour BETWEEN 0 AND 5 THEN 16
    WHEN v_hour BETWEEN 6 AND 8 OR v_hour BETWEEN 18 AND 19    THEN 9
    ELSE 4 END;

  -- Service bays: peak during business hours
  v_service_kw := CASE
    WHEN v_hour BETWEEN 7 AND 19 THEN 25 + ottoq_sim_seeded_random(p_seed, p_salt || '_svc') * 60
    ELSE                                  ottoq_sim_seeded_random(p_seed, p_salt || '_svc') * 8 END;

  -- Wash bays: midday peak
  v_wash_kw := CASE
    WHEN v_hour BETWEEN 9 AND 17 THEN ottoq_sim_seeded_random(p_seed, p_salt || '_wash') * 95
    ELSE                              ottoq_sim_seeded_random(p_seed, p_salt || '_wash') * 15 END;

  v_noise := 0.9 + ottoq_sim_seeded_random(p_seed, p_salt || '_bld_n') * 0.2;
  RETURN (v_base_kw + v_hvac_kw + v_lighting_kw + v_service_kw + v_wash_kw) * v_noise;
END;
$function$

-- ===== ottoq_sim_compute_charger_load_kw =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_compute_charger_load_kw(p_depot_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(SUM(((last_meter_value->>'power_kw'))::numeric), 0)
    FROM ocpp_sessions cs
   WHERE cs.depot_id = p_depot_id
     AND cs.status = 'active'::ocpp_session_status
     AND cs.started_at <= p_sim_clock_now
     AND (cs.ended_at IS NULL OR cs.ended_at >= p_sim_clock_now)
     AND cs.sim_run_id = ottoq_depot_running_run(p_depot_id);
$function$

-- ===== ottoq_sim_compute_discharge_rate =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_compute_discharge_rate(p_speed_kmh numeric, p_ambient_temp_c numeric, p_battery_capacity_kwh numeric, p_active_fraction numeric, p_vehicle_class text DEFAULT NULL::text, p_noise_seed bigint DEFAULT 0, p_noise_salt text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_base_drive_kw    NUMERIC;
  v_hvac_kw          NUMERIC;
  v_accessory_kw     NUMERIC := 0.3;  -- AV compute + sensors always-on
  v_thermal_factor   NUMERIC := 1.0;
  v_noise_factor     NUMERIC;
BEGIN
  -- Base drive consumption — rough EPA-ish curve, scales with speed
  -- ~3 mi/kWh at city, ~3.5 at highway → 0.28-0.35 kWh/mi.
  -- Power = energy per distance × speed.
  --   At 30 km/h:  0.33 kWh/mi × 18.6 mi/h = 6.1 kW
  --   At 80 km/h:  0.29 kWh/mi × 49.7 mi/h = 14.4 kW
  --   At 110 km/h: 0.35 kWh/mi × 68.4 mi/h = 23.9 kW
  v_base_drive_kw := 0.28 * (p_speed_kmh / 1.609) + 0.0002 * power(p_speed_kmh, 2);

  -- HVAC load — peaks at temperature extremes
  v_hvac_kw := GREATEST(0,
    0.5 + 0.15 * GREATEST(0, abs(COALESCE(p_ambient_temp_c, 22) - 22) - 5)
  );
  -- Cap HVAC at ~5 kW
  v_hvac_kw := LEAST(v_hvac_kw, 5);

  -- Battery efficiency drops at temperature extremes (cold ohmic losses)
  IF p_ambient_temp_c < 5 THEN
    v_thermal_factor := 1.0 + (5 - p_ambient_temp_c) * 0.02;  -- up to +50% in deep cold
  ELSIF p_ambient_temp_c > 35 THEN
    v_thermal_factor := 1.0 + (p_ambient_temp_c - 35) * 0.015;
  END IF;

  -- Random noise per reading
  v_noise_factor := 0.92 + ottoq_sim_seeded_random(p_noise_seed,
    COALESCE(p_noise_salt, 'discharge:' || p_speed_kmh::text)) * 0.16;

  -- Weighted by active fraction
  RETURN ROUND(
    ((v_base_drive_kw * p_active_fraction + v_hvac_kw + v_accessory_kw)
       * v_thermal_factor * v_noise_factor)::NUMERIC,
    3
  );
END;
$function$

-- ===== ottoq_sim_confirm_commands =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_confirm_commands(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed bigint; v_n int := 0; v_rec RECORD; v_delay numeric; v_due timestamptz;
  v_stall_id uuid; v_stype text;
BEGIN
  SELECT COALESCE(random_seed,42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  FOR v_rec IN
    SELECT command_id, vehicle_id, command_type, payload, issued_at FROM ottoq_vehicle_commands
     WHERE sim_run_id = p_sim_run_id AND status = 'issued'
  LOOP
    v_delay := 1 + ottoq_sim_seeded_random(v_seed, v_rec.command_id::text || ':conf') * 2;  -- 1-3 min
    v_due := v_rec.issued_at + (v_delay::text || ' minutes')::interval;
    IF v_due > p_clock THEN CONTINUE; END IF;

    -- apply when the instruction asks the twin to perform the move (the world
    -- obeying an order, not the world deciding)
    v_stall_id := NULLIF(v_rec.payload->>'stall_id','')::uuid;
    IF COALESCE((v_rec.payload->>'apply_required')::boolean, false) AND v_stall_id IS NOT NULL THEN
      SELECT s.stall_type::text INTO v_stype FROM stalls s WHERE s.id = v_stall_id;
      UPDATE stalls SET current_vehicle_id = NULL, status = 'available'
       WHERE current_vehicle_id = v_rec.vehicle_id AND id <> v_stall_id;
      UPDATE vehicles
         SET current_stall_id = v_stall_id,
             current_state = CASE
               WHEN v_rec.command_type = 'begin_charge' AND v_stype = 'dcfc' THEN 'charging_dcfc'::vehicle_state
               WHEN v_rec.command_type = 'begin_charge'                      THEN 'charging_l2'::vehicle_state
               ELSE 'staged_awaiting_service'::vehicle_state END,
             last_state_change = v_due
       WHERE id = v_rec.vehicle_id;
      UPDATE stalls SET current_vehicle_id = v_rec.vehicle_id, status = 'occupied'
       WHERE id = v_stall_id;
    END IF;

    UPDATE ottoq_vehicle_commands
       SET status = 'executed',
           confirmed_at = v_due,
           confirmed_by = CASE WHEN COALESCE((v_rec.payload->>'apply_required')::boolean,false)
                               THEN 'twin_executor' ELSE 'twin_auto_tech' END,
           executed_at  = v_due
     WHERE command_id = v_rec.command_id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END; $function$

-- ===== ottoq_sim_current_tariff =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_current_tariff(p_depot_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS TABLE(out_label text, out_rate_usd_kwh numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hour    INTEGER;
  v_dow     INTEGER;
  v_month   INTEGER;
  v_season  TEXT;
BEGIN
  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_dow  := EXTRACT(DOW  FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_month := EXTRACT(MONTH FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  v_season := CASE
    WHEN v_month BETWEEN 6 AND 9  THEN 'summer'
    WHEN v_month BETWEEN 12 AND 12 OR v_month BETWEEN 1 AND 2 THEN 'winter'
    ELSE 'shoulder' END;

  SELECT label, rate_usd_per_kwh
    INTO out_label, out_rate_usd_kwh
    FROM ottoq_tariff_windows
   WHERE depot_id = p_depot_id
     AND active
     AND v_hour >= hour_start AND v_hour < hour_end
     AND (season = v_season OR season = 'all')
   ORDER BY rate_usd_per_kwh DESC                       -- super-peak wins over peak
   LIMIT 1;
  IF NOT FOUND THEN
    out_label := 'unknown';
    out_rate_usd_kwh := 0.10;
  END IF;
  RETURN NEXT;
END;
$function$

-- ===== ottoq_sim_dispatch_vehicle =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_dispatch_vehicle(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_dispatch_id     UUID := gen_random_uuid();
  v_vehicle         RECORD;
  v_planned_min     NUMERIC;
  v_seed            BIGINT;
BEGIN
  SELECT current_soc, fleet_operator_id, current_state INTO v_vehicle
    FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'vehicle % not found', p_vehicle_id;
  END IF;

  v_seed := abs(hashtextextended(p_vehicle_id::text || p_sim_clock_now::text, 42));

  -- Sample trip duration from NYC TLC trip_duration_minutes distribution
  -- (For deployment durations longer than typical taxi trips, scale up.)
  v_planned_min := COALESCE(
    ottoq_sample_calibrated('trip_duration_minutes', 'global', v_seed, 'dispatch'),
    30
  );
  -- AV deployments are continuous shifts of multiple trips. Scale up.
  v_planned_min := v_planned_min * (2 + ottoq_sim_seeded_random(v_seed, 'multiplier') * 6)
                 * ottoq_profile_rate_mult(p_sim_run_id, 'trip_duration');   -- A.10 trip_duration knob (×)

  INSERT INTO ottoq_vehicle_dispatches (
    dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at,
    planned_duration_min, soc_at_dispatch_pct, status
  ) VALUES (
    v_dispatch_id, p_vehicle_id, p_sim_run_id, v_vehicle.fleet_operator_id,
    p_sim_clock_now,
    p_sim_clock_now + (v_planned_min || ' minutes')::INTERVAL,
    v_planned_min, v_vehicle.current_soc, 'active'
  );

  -- T3 RENDER CONTRACT: the taxi OUT to the gate. Emitted before the state write
  -- while current_stall_id still holds the origin. Never aborts the dispatch.
  BEGIN
    PERFORM ottoq_itin_travel_leg(
      p_sim_run_id,
      (SELECT home_depot_id FROM vehicles WHERE id = p_vehicle_id),
      p_vehicle_id,
      (SELECT current_stall_id FROM vehicles WHERE id = p_vehicle_id),
      (SELECT s.id FROM stalls s
        WHERE s.depot_id = (SELECT home_depot_id FROM vehicles WHERE id = p_vehicle_id)
          AND s.stall_type = 'staging'::stall_type
        ORDER BY s.relative_x DESC, s.id LIMIT 1),   -- exit is west/high-x per lane doctrine
      p_sim_clock_now, 'taxi_to_gate', 'twin_dispatcher');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (dispatch): %', SQLERRM;
  END;

  UPDATE vehicles
     SET current_state = 'deployed'::vehicle_state,
           -- feed-agent service_manifest: clear at deployment so the NEXT
           -- visit rolls a fresh per-visit manifest (frozen-manifest fix)
           config = (COALESCE(config, '{}'::jsonb) - 'service_manifest' - 'service_manifest_meta'),
         last_state_change = p_sim_clock_now,
         current_stall_id = NULL
   WHERE id = p_vehicle_id;

  -- the visit is over: close its itinerary, supersede unserviced needs and
  -- release any stall this car was still holding (AP-1b / B5)
  BEGIN PERFORM ottoq_release_visit_artifacts(p_vehicle_id, p_sim_run_id, p_sim_clock_now, 'redeployed');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release visit artifacts: %', SQLERRM; END;

  PERFORM ottoq_record_event(
    p_actor_type    := 'oem_dispatch_webhook',
    p_actor_id      := 'twin_dispatch_sim',
    p_event_type    := 'twin.vehicle_arrived',  -- reusing arrival type for dispatch logging
    p_entity_type   := 'vehicle',
    p_entity_id     := p_vehicle_id,
    p_fleet_operator_id := v_vehicle.fleet_operator_id,
    p_payload       := jsonb_build_object(
      'dispatch_id', v_dispatch_id,
      'planned_duration_min', v_planned_min,
      'soc_at_dispatch', v_vehicle.current_soc,
      'mode', 'deployment_start'
    ),
    p_severity      := 'info',
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id
  );

  RETURN v_dispatch_id;
END;
$function$

-- ===== ottoq_sim_emit_arrival_webhook =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_emit_arrival_webhook(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_dispatch_id uuid, p_arrival_soc numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle           RECORD;
  v_oem               TEXT;
  v_pattern           ottoq_oem_webhook_patterns%ROWTYPE;
  v_seed              BIGINT;
  v_webhook_id        UUID := gen_random_uuid();
  v_payload           JSONB;
  v_payload_complete  BOOLEAN;
  v_missing_fields    TEXT[];
  v_attempt           INTEGER := 1;
  v_max_retries       INTEGER;
  v_latency_ms        INTEGER;
  v_total_latency_ms  INTEGER := 0;
  v_roll_auth         NUMERIC;
  v_roll_rate         NUMERIC;
  v_roll_timeout      NUMERIC;
  v_roll_5xx          NUMERIC;
  v_roll_dup          NUMERIC;
  v_roll_ooo          NUMERIC;
  v_roll_complete     NUMERIC;
  v_delivery          TEXT;
  v_http_status       INTEGER;
  v_validation        TEXT;
  v_is_duplicate      BOOLEAN := FALSE;
  v_is_ooo            BOOLEAN := FALSE;
  v_failed_first      BOOLEAN := FALSE;
  v_backoff_ms        INTEGER[];
  v_jitter_pct        NUMERIC;
BEGIN
  SELECT v.*, fo.fleet_operator_id, fo.av_platform, fo.av_api_vehicle_id, fo.make, fo.config
    INTO v_vehicle
    FROM vehicles v
   CROSS JOIN LATERAL (SELECT v.fleet_operator_id, v.platform::text AS av_platform,
                              v.av_api_vehicle_id, v.make, v.config) fo
   WHERE v.id = p_vehicle_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'vehicle % not found', p_vehicle_id;
  END IF;

  v_oem := LOWER(v_vehicle.av_platform);
  SELECT * INTO v_pattern FROM ottoq_oem_webhook_patterns WHERE oem_name = v_oem AND active = TRUE;
  IF NOT FOUND THEN
    -- No pattern → drop silently (real OEM not yet onboarded)
    RETURN NULL;
  END IF;

  -- LIVE DELIVERY ROUTE: a real signed HTTP POST when this OEM is onboarded live.
  IF v_pattern.live_delivery_enabled
     AND v_pattern.live_endpoint_url IS NOT NULL
     AND v_pattern.live_endpoint_url LIKE 'https://%' THEN
    v_payload := ottoq_sim_build_arrival_payload(v_oem, v_vehicle, p_sim_clock_now, p_arrival_soc, p_dispatch_id,
                   abs(hashtextextended(p_vehicle_id::text || p_sim_clock_now::text || 'arrival', 42)), TRUE);
    PERFORM ottoq_oem_deliver_live(v_webhook_id, p_sim_run_id, p_vehicle_id, v_pattern.fleet_operator_id,
                   v_oem, v_pattern.live_endpoint_url, v_payload, v_pattern.signing_secret_ref, p_sim_clock_now);
    RETURN v_webhook_id;
  END IF;

  v_seed         := abs(hashtextextended(p_vehicle_id::text || p_sim_clock_now::text || 'arrival', 42));
  v_max_retries  := COALESCE((v_pattern.retry_policy->>'max_retries')::int, 3);
  v_backoff_ms   := ARRAY(SELECT (jsonb_array_elements_text(v_pattern.retry_policy->'backoff_ms'))::int);
  v_jitter_pct   := COALESCE((v_pattern.retry_policy->>'jitter_pct')::numeric, 15);

  -- ----- Payload completeness roll -----
  v_roll_complete   := ottoq_sim_seeded_random(v_seed, 'complete');
  v_payload_complete := v_roll_complete < v_pattern.payload_completeness_pct;

  IF NOT v_payload_complete THEN
    -- Pick 1-2 optional fields to omit
    v_missing_fields := ARRAY(
      SELECT jsonb_array_elements_text(v_pattern.optional_fields)
      ORDER BY ottoq_sim_seeded_random(v_seed, 'miss_' || jsonb_array_elements_text(v_pattern.optional_fields))
      LIMIT 1 + FLOOR(ottoq_sim_seeded_random(v_seed, 'miss_n') * 2)::int
    );
  END IF;

  v_payload := ottoq_sim_build_arrival_payload(
    v_oem, v_vehicle, p_sim_clock_now, p_arrival_soc, p_dispatch_id, v_seed, v_payload_complete);

  -- ----- Out-of-order delivery roll -----
  v_roll_ooo := ottoq_sim_seeded_random(v_seed, 'ooo');
  v_is_ooo   := v_roll_ooo < v_pattern.out_of_order_pct;

  -- ----- Attempt loop (handles retries) -----
  LOOP
    v_latency_ms := ottoq_sim_sample_lognormal_ms(
      v_pattern.latency_mean_ms, v_pattern.latency_p99_ms, v_seed,
      'lat_' || v_attempt::text);
    v_total_latency_ms := v_total_latency_ms + v_latency_ms;

    v_roll_timeout := ottoq_sim_seeded_random(v_seed, 'timeout_' || v_attempt::text);
    v_roll_auth    := ottoq_sim_seeded_random(v_seed, 'auth_'    || v_attempt::text);
    v_roll_rate    := ottoq_sim_seeded_random(v_seed, 'rate_'    || v_attempt::text);
    v_roll_5xx     := ottoq_sim_seeded_random(v_seed, '5xx_'     || v_attempt::text);

    -- Failure mode cascade
    IF v_roll_timeout < v_pattern.network_timeout_pct THEN
      v_delivery := 'timed_out';   v_http_status := NULL;
    ELSIF v_roll_auth < v_pattern.auth_failure_pct THEN
      v_delivery := 'auth_failed'; v_http_status := 401;
    ELSIF v_roll_rate < v_pattern.rate_limit_pct THEN
      v_delivery := 'rate_limited';v_http_status := 429;
    ELSIF v_roll_5xx < v_pattern.server_error_5xx_pct THEN
      v_delivery := 'server_error';v_http_status := 502;
    ELSE
      v_delivery := 'delivered';   v_http_status := 200;
    END IF;

    -- Log this attempt (whether success or fail)
    INSERT INTO ottoq_oem_webhook_log (
      webhook_id, sim_run_id, vehicle_id, fleet_operator_id,
      oem_name, webhook_type, http_method, endpoint_url,
      payload, payload_complete, payload_missing_fields,
      attempt_num, is_retry, is_duplicate, is_out_of_order, parent_webhook_id,
      latency_ms, http_status, delivery_status, delivery_mode,
      validation_result, sim_clock_emitted_at, sim_clock_delivered_at,
      data_source
    ) VALUES (
      CASE WHEN v_attempt = 1 THEN v_webhook_id ELSE gen_random_uuid() END,
      p_sim_run_id, p_vehicle_id, v_pattern.fleet_operator_id,
      v_oem, 'arrival', 'POST', v_pattern.webhook_endpoint,
      v_payload, v_payload_complete, v_missing_fields,
      v_attempt, v_attempt > 1, FALSE, v_is_ooo,
      CASE WHEN v_attempt > 1 THEN v_webhook_id ELSE NULL END,
      v_latency_ms, v_http_status, v_delivery, 'simulated',
      CASE
        WHEN v_delivery = 'delivered' AND v_payload_complete THEN 'accepted'
        WHEN v_delivery = 'delivered' AND NOT v_payload_complete THEN 'accepted_partial'
        WHEN v_delivery = 'auth_failed' THEN 'rejected_auth'
        WHEN v_delivery IN ('rate_limited','server_error','timed_out') THEN 'pending_retry'
        ELSE 'rejected_other'
      END,
      p_sim_clock_now + (v_total_latency_ms - v_latency_ms || ' milliseconds')::interval,
      CASE WHEN v_delivery = 'delivered'
           THEN p_sim_clock_now + (v_total_latency_ms || ' milliseconds')::interval
           ELSE NULL END,
      'twin'
    );

    EXIT WHEN v_delivery = 'delivered';
    EXIT WHEN v_delivery = 'auth_failed';     -- auth fail terminates
    EXIT WHEN v_attempt >= v_max_retries;     -- exhausted retries

    -- Apply backoff
    IF array_length(v_backoff_ms, 1) >= v_attempt THEN
      v_total_latency_ms := v_total_latency_ms + v_backoff_ms[v_attempt]
                          + FLOOR(v_backoff_ms[v_attempt] * v_jitter_pct / 100.0
                                  * (ottoq_sim_seeded_random(v_seed, 'jit_' || v_attempt::text) - 0.5) * 2)::int;
    END IF;

    v_attempt := v_attempt + 1;
    v_failed_first := TRUE;
  END LOOP;

  -- ----- Duplicate send roll (only on success) -----
  IF v_delivery = 'delivered' THEN
    v_roll_dup := ottoq_sim_seeded_random(v_seed, 'dup');
    IF v_roll_dup < v_pattern.duplicate_send_pct THEN
      v_is_duplicate := TRUE;
      INSERT INTO ottoq_oem_webhook_log (
        webhook_id, sim_run_id, vehicle_id, fleet_operator_id,
        oem_name, webhook_type, http_method, endpoint_url,
        payload, payload_complete,
        attempt_num, is_retry, is_duplicate, parent_webhook_id,
        latency_ms, http_status, delivery_status, delivery_mode,
        validation_result, sim_clock_emitted_at, sim_clock_delivered_at,
        data_source
      ) VALUES (
        gen_random_uuid(),
        p_sim_run_id, p_vehicle_id, v_pattern.fleet_operator_id,
        v_oem, 'arrival', 'POST', v_pattern.webhook_endpoint,
        v_payload, v_payload_complete,
        1, FALSE, TRUE, v_webhook_id,
        ottoq_sim_sample_lognormal_ms(v_pattern.latency_mean_ms, v_pattern.latency_p99_ms, v_seed, 'dup_lat'),
        200, 'delivered', 'simulated',
        'rejected_duplicate',
        p_sim_clock_now + (FLOOR(2000 + ottoq_sim_seeded_random(v_seed, 'dup_off') * 8000) || ' milliseconds')::interval,
        p_sim_clock_now + (FLOOR(2000 + ottoq_sim_seeded_random(v_seed, 'dup_off') * 8000) + 200 || ' milliseconds')::interval,
        'twin'
      );
    END IF;
  END IF;

  -- Emit canonical twin event for forensic replay
  PERFORM ottoq_record_event(
    p_actor_type    := 'oem_dispatch_webhook',
    p_actor_id      := v_oem || '_arrival_mock',
    p_event_type    := 'twin.oem_webhook_emitted',
    p_entity_type   := 'vehicle',
    p_entity_id     := p_vehicle_id,
    p_fleet_operator_id := v_pattern.fleet_operator_id,
    p_payload       := jsonb_build_object(
      'webhook_id',        v_webhook_id,
      'oem',               v_oem,
      'delivery_status',   v_delivery,
      'attempts',          v_attempt,
      'total_latency_ms',  v_total_latency_ms,
      'payload_complete',  v_payload_complete,
      'is_duplicate',      v_is_duplicate,
      'is_out_of_order',   v_is_ooo,
      'soc_at_arrival',    p_arrival_soc
    ),
    p_severity      := CASE WHEN v_delivery = 'delivered' THEN 'info' ELSE 'warning' END,
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id
  );

  RETURN v_webhook_id;
END;
$function$

-- ===== ottoq_sim_emit_depot_heartbeats =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_emit_depot_heartbeats(p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n integer;
BEGIN
  UPDATE vehicles
     SET current_soc_updated_at = p_sim_clock
   WHERE home_depot_id = p_depot_id AND category = 'autonomous'
     AND current_state IN (
       'arrived_at_gate','staged_awaiting_service','charging_dcfc','charging_l2',
       'charge_complete_holding','in_wash_bay','in_detail_bay','in_service_bay',
       'service_complete_holding','staged_for_departure'
     );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$

-- ===== ottoq_sim_emit_ocpp =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_emit_ocpp(p_session_id uuid, p_charger_id uuid, p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock timestamp with time zone, p_direction text, p_message_type text, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_msg_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO ottoq_ocpp_messages (
    message_id, ocpp_session_id, charger_id, vehicle_id, sim_run_id,
    sim_clock_at, direction, message_type, payload, data_source
  ) VALUES (
    v_msg_id, p_session_id, p_charger_id, p_vehicle_id, p_sim_run_id,
    p_sim_clock, p_direction, p_message_type, p_payload, 'twin'
  );
  RETURN v_msg_id;
END;
$function$

-- ===== ottoq_sim_emit_telemetry =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_emit_telemetry(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock timestamp with time zone, p_soc_pct numeric, p_battery_temp_c numeric, p_speed_kmh numeric, p_instant_power_kw numeric, p_state text, p_dtc_codes text[] DEFAULT NULL::text[], p_force_integrity text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id               UUID := gen_random_uuid();
  v_integrity_roll   NUMERIC;
  v_integrity        TEXT;
  v_dropped_reason   TEXT;
  v_signal           NUMERIC;
  v_seed             BIGINT;
  v_tire_p           NUMERIC[];
  v_ambient_temp     NUMERIC;
  v_fleet_op_id      UUID;
BEGIN
  SELECT fleet_operator_id INTO v_fleet_op_id FROM vehicles WHERE id = p_vehicle_id;
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42') || p_vehicle_id::text, 42));

  -- Telemetry integrity dice — 85% full / 12% partial / 3% dropped (baseline).
  -- A.10: telemetry_dropout knob scales the dropped + partial bands.
  v_integrity_roll := ottoq_sim_seeded_random(v_seed,
    'integrity:' || p_sim_clock::text);

  DECLARE v_dm NUMERIC := ottoq_profile_rate_mult(p_sim_run_id, 'telemetry_dropout');
  BEGIN
    IF p_force_integrity IS NOT NULL THEN
      v_integrity := p_force_integrity;
    ELSIF v_integrity_roll < 0.03 * v_dm THEN
      v_integrity := 'dropped';
      v_dropped_reason := CASE
        FLOOR(ottoq_sim_seeded_random(v_seed, 'dropreason:' || p_sim_clock::text) * 4)::int
        WHEN 0 THEN 'rf_dropout'
        WHEN 1 THEN 'cellular_handoff'
        WHEN 2 THEN 'oem_api_5xx'
        ELSE        'vehicle_compute_busy'
      END;
    ELSIF v_integrity_roll < 0.15 * v_dm THEN
      v_integrity := 'partial';
    ELSE
      v_integrity := 'full';
    END IF;
  END;

  -- Signal strength — correlated with integrity outcome
  v_signal := CASE v_integrity
    WHEN 'full'    THEN 65 + ottoq_sim_seeded_random(v_seed, 'sig:'||p_sim_clock::text) * 35
    WHEN 'partial' THEN 25 + ottoq_sim_seeded_random(v_seed, 'sig:'||p_sim_clock::text) * 35
    ELSE                0 + ottoq_sim_seeded_random(v_seed, 'sig:'||p_sim_clock::text) * 25
  END;

  -- Tire pressures — small thermal-cycle drift around 35 PSI
  v_tire_p := ARRAY[
    34 + ottoq_sim_seeded_random(v_seed, 'tire0:'||p_sim_clock::text) * 4,
    34 + ottoq_sim_seeded_random(v_seed, 'tire1:'||p_sim_clock::text) * 4,
    34 + ottoq_sim_seeded_random(v_seed, 'tire2:'||p_sim_clock::text) * 4,
    34 + ottoq_sim_seeded_random(v_seed, 'tire3:'||p_sim_clock::text) * 4
  ];

  -- Sample real ambient from NOAA calibration
  v_ambient_temp := ottoq_sample_calibrated('ambient_temp_c', 'global', v_seed,
    'amb:' || p_sim_clock::text);

  -- Dropped packets carry only the dropout record
  IF v_integrity = 'dropped' THEN
    INSERT INTO ottoq_telemetry_packets (
      packet_id, vehicle_id, sim_run_id, fleet_operator_id,
      packet_at, sim_clock_at, vehicle_state,
      packet_integrity, dropped_reason, signal_strength_pct, data_source
    ) VALUES (
      v_id, p_vehicle_id, p_sim_run_id, v_fleet_op_id,
      NOW(), p_sim_clock, p_state,
      v_integrity, v_dropped_reason, v_signal, 'twin'
    );
    RETURN v_id;
  END IF;

  INSERT INTO ottoq_telemetry_packets (
    packet_id, vehicle_id, sim_run_id, fleet_operator_id,
    packet_at, sim_clock_at,
    soc_pct, soc_source, battery_temp_c, ambient_temp_c,
    tire_pressures_psi, speed_kmh,
    instant_power_kw, vehicle_state,
    dtc_codes, signal_strength_pct, packet_integrity, data_source
  ) VALUES (
    v_id, p_vehicle_id, p_sim_run_id, v_fleet_op_id,
    NOW(), p_sim_clock,
    p_soc_pct, 'oem_telemetry', p_battery_temp_c, v_ambient_temp,
    v_tire_p, p_speed_kmh,
    p_instant_power_kw, p_state,
    p_dtc_codes, v_signal, v_integrity, 'twin'
  );

  RETURN v_id;
END;
$function$

-- ===== ottoq_sim_end_run =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_end_run(p_sim_run_id uuid, p_status text DEFAULT 'aborted'::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run ottoq_sim_runs%ROWTYPE;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'sim run % not found', p_sim_run_id; END IF;
  UPDATE ottoq_sim_runs
     SET status = p_status, ended_at = NOW(), failure_reason = p_reason, next_tick_due_at = NULL
   WHERE sim_run_id = p_sim_run_id;
  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type := 'twin.sim_run_ended', p_entity_type := 'sim_run', p_entity_id := p_sim_run_id,
    p_depot_id := v_run.depot_id,
    p_payload := jsonb_build_object('status', p_status, 'reason', p_reason),
    p_severity := CASE WHEN p_status = 'failed' THEN 'error' ELSE 'info' END,
    p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id
  );
END;
$function$

-- ===== ottoq_sim_energy_controller =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_energy_controller(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_cmd RECORD; v_bess RECORD; v_n integer := 0; v_note text;
BEGIN
  FOR v_cmd IN
    SELECT * FROM ottoq_energy_commands
     WHERE sim_run_id = p_sim_run_id AND depot_id = p_depot_id AND status = 'pending'
     ORDER BY issued_at, created_at
  LOOP
    v_note := NULL;
    IF v_cmd.command_type = 'bess_setpoint_kw' THEN
      -- actuate every BESS unit at the depot to OTTO-Q's signalled dispatch (+discharge/-charge)
      FOR v_bess IN SELECT bess_id FROM ottoq_bess_units WHERE depot_id = p_depot_id LOOP
        BEGIN
          PERFORM ottoq_apply_bess_setpoint(v_bess.bess_id, COALESCE(v_cmd.setpoint_kw,0), 250, p_sim_clock);
        EXCEPTION WHEN OTHERS THEN v_note := 'bess apply skipped: ' || SQLERRM;
        END;
      END LOOP;
      -- supersede any older active BESS directive
      UPDATE ottoq_energy_commands SET status='superseded'
       WHERE sim_run_id=p_sim_run_id AND depot_id=p_depot_id AND command_type='bess_setpoint_kw'
         AND status='executed' AND command_id <> v_cmd.command_id;
    ELSIF v_cmd.command_type IN ('charge_cap_kw','load_shed','tou_shift') THEN
      -- directive: supersede older same-type directives; charging path reads the latest 'executed'
      UPDATE ottoq_energy_commands SET status='superseded'
       WHERE sim_run_id=p_sim_run_id AND depot_id=p_depot_id AND command_type=v_cmd.command_type
         AND status='executed' AND command_id <> v_cmd.command_id;
    END IF;

    UPDATE ottoq_energy_commands
       SET status='executed', executed_at=p_sim_clock, executed_note=COALESCE(v_note,'ok')
     WHERE command_id = v_cmd.command_id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$

-- ===== ottoq_sim_generate_arrival_manifests =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_generate_arrival_manifests(p_depot_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int := 0; v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT id FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND current_state = 'arrived_at_gate'
       AND NOT (COALESCE(config,'{}'::jsonb) ? 'service_manifest')
  LOOP
    PERFORM ottoq_sim_generate_service_manifest(v_rec.id, p_sim_run_id, NULL);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$

-- ===== ottoq_sim_generate_service_manifest =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_generate_service_manifest(p_vehicle_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid, p_seed bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc numeric; v_target numeric; v_cycles int; v_seed bigint; v_m jsonb := '[]'::jsonb;
  v_depot uuid; v_clock timestamptz; v_run uuid; v_plan jsonb; v_visit text;
  v_precip_stress numeric := 0; v_boost numeric := 0;
  v_probs jsonb; v_clamp_lo numeric := 0.005; v_clamp_hi numeric := 0.90;
  v_p numeric; v_conf numeric;
  v_hour int; v_urgency text; v_due timestamptz; v_visit_target numeric;
  v_is_night boolean; v_tail_scale numeric; v_insp_p numeric; v_night_start int; v_night_end int;
  v_fault boolean := false; v_ota boolean := false;
  v_band_lo numeric; v_band_hi numeric;
  v_sla_floor numeric; v_sim_day int;
  v_carry jsonb; v_carry_visit uuid; v_atom jsonb;
  v_archetype text;
  v_wear RECORD; v_soil numeric := 0; v_cap numeric; v_inlet_kw numeric; v_soh numeric;
  v_curve numeric; v_svcspd numeric; v_pm_int numeric; v_calib_int numeric; v_washcad int;
  v_pm_prog numeric := 0; v_calib_prog numeric := 0;
  v_wash_min int; v_deep_min int; v_pm_min int; v_calib_min int; v_charge_min int := 0;
BEGIN
  SELECT current_soc, COALESCE(target_soc,85), COALESCE((config->>'cycles_since_wash')::int,0),
         home_depot_id, COALESCE(last_state_change, now()),
         battery_capacity_kwh, inlet_max_kw,
         (config->>'battery_soh_pct')::numeric, (config->>'charge_curve_scalar')::numeric,
         (config->>'service_speed_scalar')::numeric, (config->>'pm_interval_km')::numeric,
         (config->>'calib_interval_h')::numeric, (config->>'wash_cadence_cycles')::int
    INTO v_soc, v_target, v_cycles, v_depot, v_clock,
         v_cap, v_inlet_kw, v_soh, v_curve, v_svcspd, v_pm_int, v_calib_int, v_washcad
    FROM vehicles WHERE id = p_vehicle_id;
  IF v_soc IS NULL THEN RETURN NULL; END IF;
  SELECT w.soil_index,
         w.drive_km_total    - COALESCE(w.km_at_last_pm,0)             AS km_since_pm,
         w.drive_hours_total - COALESCE(w.hours_at_last_calibration,0) AS h_since_calib
    INTO v_wear FROM ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND (p_sim_run_id IS NULL OR w.sim_run_id = p_sim_run_id)
   ORDER BY w.updated_at DESC LIMIT 1;
  v_soil := COALESCE(v_wear.soil_index, 0);

  v_run := COALESCE(p_sim_run_id,
    (SELECT sim_run_id FROM ottoq_sim_runs r
      WHERE r.status = 'running' AND r.depot_id = v_depot
      ORDER BY started_at DESC LIMIT 1));

  v_plan := ottoq_feed_plan('service_manifest');

  IF p_seed IS NOT NULL THEN
    v_seed := p_seed;
  ELSIF v_run IS NOT NULL THEN
    SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = v_run;
  ELSE
    v_seed := abs(hashtextextended(p_vehicle_id::text || 'manifest', 13));
  END IF;
  v_visit := p_vehicle_id::text || ':' || to_char(v_clock, 'YYYYMMDDHH24MISS');
  v_sim_day := (v_clock::date - DATE '2020-01-01');

  IF v_run IS NOT NULL AND v_plan IS NOT NULL THEN
    v_precip_stress := COALESCE((ottoq_twin_climate_stress(v_run, v_sim_day)->>'precip_stress')::numeric, 0);
    v_boost := v_precip_stress * COALESCE((v_plan->>'precip_soil_coupling')::numeric, 0.6);
  END IF;

  v_probs := COALESCE(v_plan->'probabilities', jsonb_build_object(
    'interior_tidy',0.35,'sensor_clean',0.20,'interior_deep_clean',0.10,
    'exterior_wash',0.20,'sensor_calibration',0.04,'mechanical_pm',0.05,'cosmetic_repair',0.02));
  -- LONG TAIL (Chase): random flags / sensors / recalibrations / services must be a
  -- much smaller share than the charge+interior mainline. Scale the discretionary
  -- draws down at source so every downstream IF inherits it. Plan-overridable.
  v_tail_scale := GREATEST(0, COALESCE((v_plan->>'long_tail_scale')::numeric, 0.5));
  v_probs := v_probs || jsonb_build_object(
    'sensor_clean',        COALESCE((v_probs->>'sensor_clean')::numeric,0.20)        * v_tail_scale,
    'interior_deep_clean', COALESCE((v_probs->>'interior_deep_clean')::numeric,0.10) * v_tail_scale,
    'sensor_calibration',  COALESCE((v_probs->>'sensor_calibration')::numeric,0.04)  * v_tail_scale,
    'mechanical_pm',       COALESCE((v_probs->>'mechanical_pm')::numeric,0.05)       * v_tail_scale,
    'cosmetic_repair',     COALESCE((v_probs->>'cosmetic_repair')::numeric,0.02)     * v_tail_scale);
  IF v_plan IS NOT NULL THEN
    v_clamp_lo := COALESCE((v_plan->'probability_clamp'->>0)::numeric, 0.005);
    v_clamp_hi := COALESCE((v_plan->'probability_clamp'->>1)::numeric, 0.90);
  END IF;
  v_band_lo := COALESCE((v_plan->>'confirm_band_lo')::numeric, 0.40);
  v_band_hi := COALESCE((v_plan->>'confirm_band_hi')::numeric, 0.75);

  -- ===== URGENCY (time-of-day shaped; fault overrides to tech_hold) =====
  v_fault := ottoq_sim_seeded_random(v_seed, v_visit || ':fault') < COALESCE((v_plan->>'fault_repair_p')::numeric, 0.02);
  v_hour := EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int;
  IF v_fault THEN
    v_urgency := 'tech_hold';
  ELSIF v_hour >= 22 OR v_hour < 4 THEN
    v_urgency := CASE WHEN ottoq_sim_seeded_random(v_seed, v_visit || ':urg')
                        < COALESCE((v_plan->>'overnight_hold_p_night')::numeric, 0.75)
                 THEN 'overnight_hold' ELSE 'standard' END;
  ELSE
    v_urgency := CASE WHEN ottoq_sim_seeded_random(v_seed, v_visit || ':urg')
                        < COALESCE((v_plan->>'immediate_dispatch_p_day')::numeric, 0.30)
                 THEN 'immediate_dispatch' ELSE 'standard' END;
  END IF;
  v_due := CASE v_urgency
    WHEN 'immediate_dispatch' THEN v_clock + interval '45 minutes'
    WHEN 'overnight_hold' THEN
      (((v_clock AT TIME ZONE 'America/Chicago')::date
        + CASE WHEN v_hour >= 4 THEN 1 ELSE 0 END) + time '07:00') AT TIME ZONE 'America/Chicago'
    ELSE NULL END;
  -- quick-turn partial target: surge vehicles top to SLA floor + margin, not full
  BEGIN
    SELECT min_soc_at_deployment_pct INTO v_sla_floor
      FROM ottoq_get_active_sla((SELECT fleet_operator_id FROM vehicles WHERE id = p_vehicle_id));
  EXCEPTION WHEN OTHERS THEN v_sla_floor := NULL; END;
  v_sla_floor := COALESCE(v_sla_floor, 80);
  v_visit_target := CASE WHEN v_urgency = 'immediate_dispatch'
                         THEN GREATEST(v_sla_floor + 5, 70) ELSE v_target END;

  -- condition-coherent interval progress + card-dealt durations (v4)
  v_pm_prog    := CASE WHEN COALESCE(v_pm_int,0)    > 0 THEN COALESCE(v_wear.km_since_pm,0)   / v_pm_int    ELSE 0 END;
  v_calib_prog := CASE WHEN COALESCE(v_calib_int,0) > 0 THEN COALESCE(v_wear.h_since_calib,0) / v_calib_int ELSE 0 END;
  -- founder_spec_durations: exterior wash is an 8-10 MINUTE bay job (taxi from the
  -- charger, wash, exit rear). Clamped to the band so the twin's variance stays inside it.
  v_wash_min  := GREATEST(8, LEAST(10, round(9 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'wash_time',        v_visit, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1))))::int;
  v_deep_min  := GREATEST(12, round(20 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'detail_time',      v_visit, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_pm_min    := GREATEST(20, round(40 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'maintenance_time', v_visit, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;
  IF v_soc < v_visit_target - 1 THEN
    v_charge_min := GREATEST(8, round(COALESCE(
      ottoq_estimate_charge_minutes(v_soc, v_visit_target, 150, COALESCE(v_inlet_kw,150),
                                    COALESCE(v_cap,75), 25, COALESCE(v_soh,95),
                                    GREATEST(0.2, (CASE WHEN v_run IS NULL THEN 1.0 ELSE ottoq_profile_rate_mult(v_run,'charge_time') END)
                                                  / GREATEST(0.2, COALESCE(v_curve,1.0)))), 25)))::int;
  END IF;

  -- ===== ATOMS (v2 set preserved + N2 additions; enriched fields are additive) =====
  IF v_soc < v_visit_target - 1 THEN
    v_m := v_m || jsonb_build_object('svc','charge','must_do',true,'deferrable',false,
      'target_soc',v_visit_target,'est_min',v_charge_min,'concurrency','anchor');
  END IF;
  v_m := v_m || jsonb_build_object('svc','readiness_check','must_do',true,'deferrable',false,
      'est_min',3,'concurrency','gate','predecessors',jsonb_build_array('*'));
  -- ===== DAY / NIGHT SHAPE (Chase requirement 4) =====
  -- Night window is plan-tunable; default 20:00-06:00 local.
  v_night_start := COALESCE((v_plan->>'night_start_hour')::int, 20);
  v_night_end   := COALESCE((v_plan->>'night_end_hour')::int, 6);
  v_is_night    := (v_hour >= v_night_start OR v_hour < v_night_end);

  -- INTERIOR INSPECTION — the atom that pairs with charge to make the 90-95%.
  -- concurrency 'cabin' means it runs AT the charging stall while the car charges,
  -- which is exactly "simultaneous interior inspection at that same charging stall".
  -- This is an INSPECTION, not a clean; interior_tidy below stays as the
  -- soil-triggered escalation when the inspection would find real mess.
  v_insp_p := CASE WHEN v_is_night
                   THEN COALESCE((v_plan->>'night_interior_inspection_p')::numeric, 0.95)
                   ELSE COALESCE((v_plan->>'day_interior_inspection_p')::numeric, 0.93) END;
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':insp') < v_insp_p THEN
    v_m := v_m || jsonb_build_object('svc','interior_inspection','must_do',true,'deferrable',false,
      'est_min', (3 + round(2 * ottoq_sim_seeded_random(v_seed, v_visit || ':inspmin')))::int,
      'concurrency','cabin','at_charge_stall',true);
  END IF;

  -- interior tidy (camera-triggered, rain-coupled, gray-band triage)
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'interior_tidy')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':tidy') < v_p THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_visit || ':tidyconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','interior_tidy','must_do',true,'deferrable',false,
      -- founder_spec_durations: 3-5 min at the charger, seeded (was a flat 5)
      'est_min', (3 + round(2 * ottoq_sim_seeded_random(v_seed, v_visit || ':tidymin')))::int,
      'concurrency','cabin','confidence',v_conf,
      'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi);
  END IF;
  -- item retrieval (rider report = certain, never triaged)
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':item') < COALESCE((v_plan->>'item_retrieval_p')::numeric, 0.06) THEN
    v_m := v_m || jsonb_build_object('svc','item_retrieval','must_do',true,'deferrable',false,
      'est_min',4,'concurrency','cabin','confidence',1.0,'confirm_required',false);
  END IF;
  -- sensor clean (perception integrity, rain-coupled, gray-band triage)
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'sensor_clean')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':sclean') < v_p THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_visit || ':scleanconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','sensor_clean','must_do',true,'deferrable',false,
      'est_min',5,'concurrency','exterior','confidence',v_conf,
      'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi);
  END IF;
  -- remote diagnostics (digital, runs during charge dwell)
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':diag') < COALESCE((v_plan->>'remote_diagnostics_p')::numeric, 0.05) THEN
    v_m := v_m || jsonb_build_object('svc','remote_diagnostics','must_do',false,'deferrable',true,
      'est_min',5,'concurrency','digital');
  END IF;
  -- fleet OTA wave (run-day card; OTTO-Q staggers fleet-wide in M3)
  v_ota := ottoq_sim_seeded_random(v_seed, 'ota_wave:' || v_sim_day::text) < COALESCE((v_plan->>'ota_wave_daily_p')::numeric, 0.08);
  IF v_ota THEN
    v_m := v_m || jsonb_build_object('svc','software_update','must_do',false,'deferrable',true,
      'est_min', 15 + floor(ottoq_sim_seeded_random(v_seed, v_visit || ':otamin') * 30)::int,
      'concurrency','digital','blocks_dispatch_while_running',true);
  END IF;
  -- deep clean (deferrable, carryover-eligible)
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'interior_deep_clean')::numeric * (1 + v_boost * 0.5)));
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':deep') < v_p THEN
    v_m := v_m || jsonb_build_object('svc','interior_deep_clean','must_do',false,'deferrable',true,
      'est_min',v_deep_min,'concurrency','bay','requires_bay','detail','carryover_eligible',true);
  END IF;
  -- exterior wash (rain OR cadence, deferrable, precedes calibration)
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'exterior_wash')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  -- M5_wash_rotation: deterministic thirds. Every vehicle carries a stable
  -- group (0/1/2); the group whose number matches the calendar day gets washed. That is
  -- exactly 1/3 of the fleet per night and each vehicle every 3rd night (~2x/week),
  -- which is the founder rule. Deterministic => CRN-safe and reproducible across seeds.
  -- Exceptions: a visibly dirty vehicle (soil/rain) is washed off-rotation, and a long
  -- backstop catches anything the rotation somehow missed. cycles>=1 stops a vehicle
  -- visiting twice in one night from being washed twice.
  -- WASH = EVERY 3rd NIGHT, and only at night (Chase). The rotation is a calendar
  -- third of the fleet per night, so each vehicle washes every 3rd day. The old
  -- `v_cycles >= 1` precondition counted DISPATCHES, not days: it made the interval
  -- trip-dependent (measured 2.07 days, not 3.0) and on the benchmark depot — where
  -- ottoq_benchmark_reset strips the counter from vehicle config — it was
  -- permanently shut, producing 0 washes in 688 visits. Dirt accrues with time and
  -- exposure, so soil_index is the only condition signal kept.
  IF (v_is_night
       AND COALESCE((SELECT (config->>'wash_group')::int FROM vehicles WHERE id = p_vehicle_id),
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3)) = (v_sim_day % 3))
     OR v_soil >= COALESCE((v_plan->>'wash_soil_override')::numeric, 0.75)
     -- wash_backstop_cycles: safety net only. Ignores the stale per-vehicle cadence
     -- (2-4, calibrated for the retired probability policy) so the calendar rotation owns
     -- the wash share; this catches only a vehicle that somehow missed several rotations.
     OR v_cycles >= COALESCE((v_plan->>'wash_backstop_cycles')::int, 9) THEN
    v_m := v_m || jsonb_build_object('svc','exterior_wash','must_do',false,'deferrable',true,
      'est_min',v_wash_min,'concurrency','bay','requires_bay','wash_bay','carryover_eligible',true);
  END IF;
  -- NIGHT WALK-AROUND (Chase): "perimeter/long term parking where a full walk around
  -- inspection can occur by a technician, before sitting for a few hours before early
  -- morning re-deployment." concurrency 'hold' = performed while the vehicle sits on
  -- the perimeter, so it costs no bay and no charger. Deliberately NOT flagged
  -- requires_tech_greenlight: that flag routes a vehicle into a tech HOLD on arrival,
  -- and this is routine overnight work, not an exception.
  IF v_is_night
     AND ottoq_sim_seeded_random(v_seed, v_visit || ':walkaround')
         < COALESCE((v_plan->>'night_walkaround_p')::numeric, 0.90) THEN
    v_m := v_m || jsonb_build_object('svc','perimeter_walkaround','must_do',true,'deferrable',false,
      'est_min', (10 + round(5 * ottoq_sim_seeded_random(v_seed, v_visit || ':walkmin')))::int,
      'concurrency','hold','at_perimeter',true);
  END IF;
  -- sensor calibration (dedicated slot, AFTER wash)
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':calib') < LEAST(0.95, (v_probs->>'sensor_calibration')::numeric
        * CASE WHEN v_calib_prog >= 1.0 THEN 12 WHEN v_calib_prog >= 0.8 THEN 4 ELSE 0.5 END) THEN
    v_m := v_m || jsonb_build_object('svc','sensor_calibration','must_do',false,'deferrable',true,
      'est_min',v_calib_min,'slot','dedicated_service','concurrency','bay','requires_bay','service_bay',
      'predecessors',jsonb_build_array('exterior_wash'),'carryover_eligible',true);
  END IF;
  -- mechanical PM
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':pm') < LEAST(0.95, (v_probs->>'mechanical_pm')::numeric
        * CASE WHEN v_pm_prog >= 1.0 THEN 12 WHEN v_pm_prog >= 0.8 THEN 4 ELSE 0.5 END) THEN
    v_m := v_m || jsonb_build_object('svc','mechanical_pm','must_do',false,'deferrable',true,
      'est_min',v_pm_min,'concurrency','bay','requires_bay','service_bay','carryover_eligible',true);
  END IF;
  -- cosmetic/damage (gray-band triage; offline candidate)
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':cosmetic') < (v_probs->>'cosmetic_repair')::numeric THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_visit || ':cosconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','cosmetic_repair','must_do',false,'deferrable',true,
      'est_min',60,'disposition','offline_candidate','concurrency','bay','requires_bay','service_bay',
      'confidence',v_conf,'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi,
      'carryover_eligible',true);
  END IF;
  -- fault repair (drawn above; forces tech_hold + technician green-light)
  IF v_fault THEN
    v_m := v_m || jsonb_build_object('svc','fault_repair','must_do',true,'deferrable',false,
      'est_min', 30 + floor(ottoq_sim_seeded_random(v_seed, v_visit || ':faultmin') * 90)::int,
      'concurrency','bay','requires_bay','service_bay','requires_tech_greenlight',true);
  END IF;

  -- ===== CARRYOVER: re-attach unfinished deferrables from the last visit =====
  -- (activates fully once M2 marks atoms done; mechanism is in place now)
  SELECT visit_id, atoms INTO v_carry_visit, v_carry
    FROM ottoq_visit_needs
   WHERE vehicle_id = p_vehicle_id AND status = 'carried_over'
   ORDER BY created_at DESC LIMIT 1;
  IF v_carry IS NOT NULL THEN
    FOR v_atom IN SELECT * FROM jsonb_array_elements(v_carry) LOOP
      IF COALESCE((v_atom->>'carryover_eligible')::boolean, false)
         AND NOT COALESCE((v_atom->>'done')::boolean, false)
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_atom->>'svc') THEN
        v_m := v_m || (v_atom || jsonb_build_object('carried',true));
      END IF;
    END LOOP;
    UPDATE ottoq_visit_needs SET status = 'complete',
           meta = COALESCE(meta,'{}'::jsonb) || jsonb_build_object('carryover_consumed_by', v_visit)
     WHERE visit_id = v_carry_visit;
  END IF;

  -- coarse archetype label (analytics/provenance lens over the generative draw)
  v_archetype := CASE
    WHEN v_fault THEN 'E_tech_hold_fault'
    WHEN v_ota THEN 'J_ota_wave'
    WHEN v_urgency = 'overnight_hold' THEN 'C_overnight'
    WHEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'charge') THEN 'M_pass_through_or_P_triage'
    WHEN v_urgency = 'immediate_dispatch'
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'interior_tidy') THEN 'A_charge_clean_go'
    WHEN v_urgency = 'immediate_dispatch' THEN 'D_charge_and_go'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'mechanical_pm') THEN 'B_full_service'
    ELSE 'std_mixed' END;

  -- ===== DUAL-WRITE: contract table (new) + config manifest (compat) =====
  UPDATE ottoq_visit_needs SET status = 'superseded'
   WHERE vehicle_id = p_vehicle_id AND status IN ('open','in_progress');
  INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key,
                                 archetype, urgency, dispatch_due_at, target_soc, atoms, meta)
  VALUES (p_vehicle_id, v_run, v_depot, v_clock, v_visit,
          v_archetype, v_urgency, v_due, v_visit_target, v_m,
          jsonb_build_object('plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
                             'crn', v_run IS NOT NULL, 'precip_stress', round(v_precip_stress,3),
                             'wet_boost', round(v_boost,3), 'soc_at_arrival', v_soc,
                             'sla_floor', v_sla_floor, 'generator', 'v4_condition'))
  ON CONFLICT (vehicle_id, visit_key) DO UPDATE
    SET atoms = EXCLUDED.atoms, urgency = EXCLUDED.urgency, archetype = EXCLUDED.archetype,
        dispatch_due_at = EXCLUDED.dispatch_due_at, target_soc = EXCLUDED.target_soc,
        meta = EXCLUDED.meta, status = 'open';

  UPDATE vehicles SET config = jsonb_set(
      jsonb_set(COALESCE(config,'{}'::jsonb), '{service_manifest}', v_m),
      '{service_manifest_meta}', jsonb_build_object(
        'visit', v_visit,
        'plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
        'crn', v_run IS NOT NULL,
        'precip_stress', round(v_precip_stress, 3),
        'wet_boost', round(v_boost, 3),
        'urgency', v_urgency,
        'generator', 'v4_condition'))
   WHERE id = p_vehicle_id;
  RETURN v_m;
END;
$function$

-- ===== ottoq_sim_lane_capacity =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_lane_capacity(p_sim_run_id uuid, p_lane_staff_key text, p_physical integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_knobs   JSONB;
  v_master  NUMERIC;
  v_lane    NUMERIC;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN p_physical; END IF;
  SELECT knobs INTO v_knobs FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  IF v_knobs IS NULL THEN RETURN p_physical; END IF;
  v_master := COALESCE((v_knobs #>> ARRAY['_rates','staffing_level'])::numeric, 1);
  v_lane   := COALESCE((v_knobs #>> ARRAY['_rates', p_lane_staff_key])::numeric, 1);
  -- Any positive staffing keeps at least ONE lane open (understaffing slows the
  -- flow + grows staging; it never fully gridlocks). Zero staffing = closed.
  IF v_master * v_lane <= 0 THEN RETURN 0; END IF;
  RETURN GREATEST(1, FLOOR(p_physical * v_master * v_lane))::int;
END;
$function$

-- ===== ottoq_sim_materialize_schedule =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_materialize_schedule(p_sim_run_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot   UUID;
  v_clock   TIMESTAMPTZ;
  v_day     DATE;
  v_vehicle RECORD;
  v_sched   UUID;
  v_count   INTEGER := 0;
  v_svc_def UUID;
  v_wash_def UUID;
BEGIN
  SELECT depot_id, sim_clock_current INTO v_depot, v_clock FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  v_day := v_clock::date;

  SELECT id INTO v_svc_def  FROM service_definitions WHERE code = 'inspection'    LIMIT 1;
  SELECT id INTO v_wash_def FROM service_definitions WHERE code = 'exterior_wash' LIMIT 1;

  FOR v_vehicle IN
    SELECT v.id, v.fleet_operator_id, v.current_state, v.config->>'svc_step' AS svc_step
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','service_complete_holding',
                               'staged_awaiting_service','staged_for_departure')
  LOOP
    -- ensure a vehicle_schedules row for (vehicle, day)
    SELECT id INTO v_sched FROM vehicle_schedules
     WHERE vehicle_id = v_vehicle.id AND depot_id = v_depot AND scheduled_date = v_day LIMIT 1;
    IF v_sched IS NULL THEN
      INSERT INTO vehicle_schedules (vehicle_id, depot_id, scheduled_date, arrival_time, status, planned_services)
      VALUES (v_vehicle.id, v_depot, v_day, v_clock, 'in_progress',
              jsonb_build_array('exterior_wash','inspection'))
      RETURNING id INTO v_sched;
    END IF;

    -- WASH task: completed once the vehicle is past the wash bay
    INSERT INTO schedule_tasks (vehicle_schedule_id, schedule_id, vehicle_id, depot_id, service_definition_id,
        service_code, sequence_order, scheduled_start, scheduled_end, status,
        actual_end)
    SELECT v_sched, v_sched, v_vehicle.id, v_depot, v_wash_def, 'exterior_wash', 1, v_clock, v_clock,
        (CASE WHEN v_vehicle.current_state IN ('in_wash_bay','in_detail_bay') THEN 'in_progress' ELSE 'completed' END)::task_status,
        (CASE WHEN v_vehicle.current_state IN ('in_wash_bay','in_detail_bay') THEN NULL ELSE v_clock END)
    WHERE NOT EXISTS (SELECT 1 FROM schedule_tasks t WHERE t.vehicle_schedule_id = v_sched AND t.service_code = 'exterior_wash');

    -- SERVICE/INSPECTION task: completed once past the service bay
    INSERT INTO schedule_tasks (vehicle_schedule_id, schedule_id, vehicle_id, depot_id, service_definition_id,
        service_code, sequence_order, scheduled_start, scheduled_end, status, actual_end)
    SELECT v_sched, v_sched, v_vehicle.id, v_depot, v_svc_def, 'inspection', 2, v_clock, v_clock,
        (CASE WHEN v_vehicle.current_state IN ('staged_for_departure','service_complete_holding') OR v_vehicle.svc_step IN ('need_deploy','ready')
              THEN 'completed' WHEN v_vehicle.current_state = 'in_service_bay' THEN 'in_progress' ELSE 'pending' END)::task_status,
        (CASE WHEN v_vehicle.current_state IN ('staged_for_departure','service_complete_holding') OR v_vehicle.svc_step IN ('need_deploy','ready')
              THEN v_clock ELSE NULL END)
    WHERE NOT EXISTS (SELECT 1 FROM schedule_tasks t WHERE t.vehicle_schedule_id = v_sched AND t.service_code = 'inspection');

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$

-- ===== ottoq_sim_maybe_ignite_dr_call =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_maybe_ignite_dr_call(p_depot_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_ambient_temp_c numeric, p_seed bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hour     INTEGER;
  v_roll     NUMERIC;
  v_prob     NUMERIC := 0;
  v_existing UUID;
  v_call_id  UUID;
  v_dur_min  NUMERIC;
  v_cap_kw   NUMERIC;
BEGIN
  -- Don't ignite if already active
  SELECT dr_call_id INTO v_existing
    FROM ottoq_dr_calls
   WHERE depot_id = p_depot_id AND call_status = 'active'
     AND expires_at > p_sim_clock_now LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  -- Probability model: hot afternoon peak hours
  IF p_ambient_temp_c >= 32 AND v_hour BETWEEN 14 AND 19 THEN
    v_prob := 0.030 + (p_ambient_temp_c - 32) * 0.012;
  ELSIF p_ambient_temp_c >= 30 AND v_hour BETWEEN 15 AND 18 THEN
    v_prob := 0.010;
  ELSIF p_ambient_temp_c <= -5 AND v_hour BETWEEN 6 AND 9 THEN
    -- Winter morning event
    v_prob := 0.015;
  END IF;

  -- A.8: scale DR-ignition probability by the run's variability profile
  v_prob := v_prob * ottoq_profile_rate_mult(p_sim_run_id, 'dr_ignition');
  v_roll := ottoq_sim_seeded_random(p_seed, 'dr_ignite');
  IF v_roll >= v_prob THEN RETURN NULL; END IF;

  -- Sample duration (90-240 min, Weibull-shaped via U^0.75)
  v_dur_min := 90 + POWER(ottoq_sim_seeded_random(p_seed, 'dr_dur'), 0.75) * 150;
  -- Sample required load cap (50-400 kW reduction)
  v_cap_kw  := 50 + ottoq_sim_seeded_random(p_seed, 'dr_cap') * 350;

  v_call_id := gen_random_uuid();
  INSERT INTO ottoq_dr_calls (
    dr_call_id, depot_id, sim_run_id, issued_at, expires_at,
    duration_minutes, required_load_cap_kw, reason, program, call_status
  ) VALUES (
    v_call_id, p_depot_id, p_sim_run_id, p_sim_clock_now,
    p_sim_clock_now + (v_dur_min || ' minutes')::interval,
    v_dur_min, v_cap_kw,
    CASE WHEN p_ambient_temp_c >= 32 THEN 'heat_demand_response'
         WHEN p_ambient_temp_c <= -5 THEN 'cold_winter_morning'
         ELSE 'contingency' END,
    'TVA_VOLUNTARY', 'active');

  PERFORM ottoq_record_event(
    p_actor_type    := 'external_sensor',
    p_actor_id      := 'tva_dr_program',
    p_event_type    := 'twin.dr_call_issued',
    p_entity_type   := 'depot',
    p_entity_id     := p_depot_id,
    p_payload       := jsonb_build_object(
      'dr_call_id', v_call_id,
      'duration_min', v_dur_min,
      'required_cap_kw', v_cap_kw,
      'reason', CASE WHEN p_ambient_temp_c >= 32 THEN 'heat'
                     WHEN p_ambient_temp_c <= -5 THEN 'cold'
                     ELSE 'contingency' END,
      'temp_c', p_ambient_temp_c),
    p_severity      := 'warning',
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id);

  RETURN v_call_id;
END;
$function$

-- ===== ottoq_sim_maybe_incident =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_maybe_incident(p_seed bigint, p_salt text, p_miles_this_tick numeric, p_rate_mult numeric DEFAULT 1, p_severity_shift numeric DEFAULT 0, p_breakdown_mult numeric DEFAULT 1)
 RETURNS TABLE(out_kind text, out_sev text, out_requires_tow boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  -- DMV-calibrated: ~1 collision per ~1-5 million miles for major operators.
  -- Use 1 per 2M miles as baseline = 5e-7 per mile.
  v_per_mile NUMERIC := 0.0000005;
  v_roll     NUMERIC;
  v_pick     NUMERIC;
BEGIN
  IF p_miles_this_tick <= 0 THEN RETURN; END IF;
  v_roll := ottoq_sim_seeded_random(p_seed, 'inc_roll:' || p_salt);
  -- A.10: breakdown_rate also lifts the overall incident probability slightly
  IF v_roll >= (v_per_mile * p_miles_this_tick * COALESCE(p_rate_mult, 1) * COALESCE(p_breakdown_mult, 1)) THEN RETURN; END IF;

  -- A.10: incident_severity shifts the pick toward more severe outcomes
  v_pick := LEAST(1, GREATEST(0, ottoq_sim_seeded_random(p_seed, 'inc_pick:' || p_salt) + COALESCE(p_severity_shift, 0)));
  IF v_pick < 0.55 THEN
    -- 55% are minor collisions
    out_kind := 'collision_minor'; out_sev := 'minor'; out_requires_tow := FALSE;
  ELSIF v_pick < 0.80 THEN
    -- 25% moderate
    out_kind := 'collision_moderate'; out_sev := 'moderate'; out_requires_tow := TRUE;
  ELSIF v_pick < 0.88 THEN
    out_kind := 'breakdown_electrical'; out_sev := 'moderate'; out_requires_tow := TRUE;
  ELSIF v_pick < 0.94 THEN
    out_kind := 'tire_failure'; out_sev := 'minor'; out_requires_tow := TRUE;
  ELSIF v_pick < 0.98 THEN
    out_kind := 'stranded_low_soc'; out_sev := 'moderate'; out_requires_tow := TRUE;
  ELSE
    out_kind := 'collision_major'; out_sev := 'major'; out_requires_tow := TRUE;
  END IF;
  RETURN NEXT;
END;
$function$

-- ===== ottoq_sim_maybe_spawn_dtc =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_maybe_spawn_dtc(p_seed bigint, p_salt text, p_tick_minutes numeric, p_active_fraction numeric, p_rate_mult numeric DEFAULT 1)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  -- Calibrate: CA DMV median ~5000 mi per disengagement-equivalent event.
  -- At 50 km/h avg, that's ~5000 mi / 31 mph = 161 hours of driving = ~9700
  -- active-drive-minutes per event. So per active-drive minute, p ≈ 1/9700.
  v_per_active_min NUMERIC := 0.0001;
  v_effective_p    NUMERIC;
  v_roll           NUMERIC;
  v_pick           NUMERIC;
BEGIN
  v_effective_p := v_per_active_min * p_tick_minutes * p_active_fraction * COALESCE(p_rate_mult, 1);
  v_roll := ottoq_sim_seeded_random(p_seed, 'dtc_roll:' || p_salt);
  IF v_roll >= v_effective_p THEN RETURN NULL; END IF;

  -- Sample from DTC catalog weighted by category mix calibrated to DMV
  -- cause distribution (perception 28, planning 25, hardware 18, software 14,
  -- weather_road 10, operator 5).
  v_pick := ottoq_sim_seeded_random(p_seed, 'dtc_pick:' || p_salt);
  RETURN (
    SELECT dtc_code FROM ottoq_dtc_catalog
     WHERE category = CASE
       WHEN v_pick < 0.28 THEN 'perception'
       WHEN v_pick < 0.53 THEN 'planning'
       WHEN v_pick < 0.71 THEN 'hardware'
       WHEN v_pick < 0.85 THEN 'software'
       WHEN v_pick < 0.95 THEN 'weather_road'
       ELSE                    'operator'
     END
     ORDER BY ottoq_sim_seeded_random(p_seed, 'dtc_idx:' || p_salt || dtc_code)
     LIMIT 1
  );
END;
$function$

-- ===== ottoq_sim_overnight_service_drain =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_overnight_service_drain(p_depot_id uuid, p_sim_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hour int; v_n int := 0;
  v_rec RECORD; v_item jsonb; v_dur numeric;
  v_plan jsonb; v_adms jsonb; v_adm jsonb; v_vid uuid; v_i int;
BEGIN
  v_hour := EXTRACT(HOUR FROM (p_sim_clock AT TIME ZONE 'America/Chicago'))::int;

  -- (A) ALWAYS complete elapsed drains (never strand a job past dawn)
  FOR v_rec IN
    SELECT id, config FROM vehicles
     WHERE home_depot_id = p_depot_id AND category='autonomous'
       AND config->>'svc_step' = 'overnight_draining'
       AND (config->>'service_ends_at') IS NOT NULL
       AND (config->>'service_ends_at')::timestamptz <= p_sim_clock
  LOOP
    UPDATE vehicles
       SET current_state = 'staged_for_departure'::vehicle_state, last_state_change = p_sim_clock,
           config = jsonb_set(
                      jsonb_set((v_rec.config - 'draining_item' - 'service_ends_at'),
                        '{deferred_services}',
                        COALESCE((SELECT jsonb_agg(e)
                                    FROM jsonb_array_elements(COALESCE(v_rec.config->'deferred_services','[]'::jsonb)) e
                                   WHERE e IS DISTINCT FROM (v_rec.config->'draining_item')), '[]'::jsonb)),
                      '{svc_step}', to_jsonb('ready'::text))
     WHERE id = v_rec.id;
    PERFORM ottoq_record_event(
      p_actor_type:='command_center_operator', p_actor_id:='overnight_tech_crew',
      p_event_type:='twin.deferred_service_completed', p_entity_type:='vehicle', p_entity_id:=v_rec.id,
      p_depot_id:=p_depot_id, p_payload:=jsonb_build_object('item', v_rec.config->'draining_item', 'hour_cst', v_hour),
      p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  -- (B) OTTO-Q decides window, headroom and WHICH vehicles. Called AFTER (A) because
  --     the headroom count depends on (A)'s completions.
  v_plan := ottoq_plan_overnight_drain_admissions(p_depot_id, p_sim_clock, p_sim_run_id);
  v_adms := COALESCE(v_plan->'admissions', '[]'::jsonb);

  FOR v_i IN 0 .. jsonb_array_length(v_adms) - 1 LOOP
    v_adm  := v_adms->v_i;
    v_vid  := (v_adm->>'vehicle_id')::uuid;
    v_item := v_adm->'item';
    v_dur  := (v_adm->>'dur_min')::numeric;
    UPDATE vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock,
           config = jsonb_set(jsonb_set(jsonb_set(config,
                      '{svc_step}', to_jsonb('overnight_draining'::text)),
                      '{service_ends_at}', to_jsonb((p_sim_clock + (v_dur || ' minutes')::interval)::text)),
                      '{draining_item}', v_item)
     WHERE id = v_vid;
    PERFORM ottoq_record_event(
      p_actor_type:='command_center_operator', p_actor_id:='overnight_tech_crew',
      p_event_type:='twin.deferred_service_started', p_entity_type:='vehicle', p_entity_id:=v_vid,
      p_depot_id:=p_depot_id, p_payload:=jsonb_build_object('item', v_item, 'dur_min', v_dur, 'hour_cst', v_hour),
      p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$function$

-- ===== ottoq_sim_poa_irradiance =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_poa_irradiance(p_ghi_wm2 numeric, p_elev_deg numeric, p_panel_tilt_deg numeric, p_panel_azimuth numeric, p_solar_azimuth numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_zenith_deg   NUMERIC;
  v_aoi_cos      NUMERIC;          -- cos of angle of incidence
BEGIN
  IF p_elev_deg <= 0 OR p_ghi_wm2 <= 0 THEN
    RETURN 0;
  END IF;
  v_zenith_deg := 90.0 - p_elev_deg;

  -- Simplified isotropic AOI: cos(AOI) = cos(zenith)*cos(tilt) + sin(zenith)*sin(tilt)*cos(azim_diff)
  v_aoi_cos := COS(RADIANS(v_zenith_deg)) * COS(RADIANS(p_panel_tilt_deg))
             + SIN(RADIANS(v_zenith_deg)) * SIN(RADIANS(p_panel_tilt_deg))
               * COS(RADIANS(p_solar_azimuth - p_panel_azimuth));

  -- POA = GHI × max(cos_AOI, 0) / cos(zenith)  — simplified (ignore diffuse)
  IF v_aoi_cos <= 0 OR COS(RADIANS(v_zenith_deg)) < 0.05 THEN
    RETURN 0;
  END IF;

  RETURN p_ghi_wm2 * (v_aoi_cos / COS(RADIANS(v_zenith_deg)));
END;
$function$

-- ===== ottoq_sim_prime_deployment =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_prime_deployment(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_fraction numeric DEFAULT 0.92)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE; v_total INTEGER; v_count INTEGER := 0; v_vehicle RECORD;
  v_seed BIGINT; v_planned NUMERIC; v_elapsed NUMERIC; v_remaining NUMERIC;
  v_dispatched TIMESTAMPTZ; v_return TIMESTAMPTZ; v_did UUID;
  v_limit INTEGER; v_pool INTEGER;
  -- STAGGER (2026-08-02)
  v_frac NUMERIC; v_inbound_frac NUMERIC; v_k INTEGER := 0; v_eta NUMERIC;
  v_lead NUMERIC; v_inbound INTEGER := 0; v_j INTEGER := 0; v_is_inbound BOOLEAN;
  v_fp_src TEXT := ''; v_fp TEXT; v_off NUMERIC;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN 0; END IF;
  v_seed := abs(hashtextextended(COALESCE(v_run.random_seed, 42)::text || 'prime', 11));
  PERFORM set_config('ottoq.skip_wash_bump', '1', true); -- boot prime <> a deploy cycle
  SELECT COUNT(*) INTO v_total FROM vehicles WHERE home_depot_id = v_run.depot_id AND category = 'autonomous';

  -- the target IS the cap now, not just a sizing hint for the seed
  v_limit := GREATEST(0, LEAST(v_total, CEIL(v_total * COALESCE(p_fraction, 0.92))::int));

  -- ─────────────────────────────────────────────────────────────────────────────
  -- BOOT-PRIME STAGGER (2026-08-02). WHY, precisely:
  --
  --  (1) Returns in this world are NEED-driven, not timer-driven -- the trigger that
  --      actually fires is 'service_interval_due' in ottoq_evaluate_return_need
  --      (measured: 22 of 23 real returns on run 55206b42, 50 of 51 on b3755871).
  --      So spreading scheduled_return_at alone does nothing for arrivals.
  --  (2) THE DEAD FRONT IS STRUCTURAL, NOT STOCHASTIC. Every primed vehicle booted
  --      'active'. A vehicle can only arrive return_eta_minutes (policy, 30) AFTER it
  --      decides to return, and nothing boots already inbound -- so the first ~30
  --      sim-min of every run were arrival-free BY CONSTRUCTION, which is exactly the
  --      2 of 10 empty buckets on the cert run.
  --
  -- THE FIX, in two deterministic parts:
  --  A. STRATIFIED TRIP MATURITY. Each primed vehicle gets a low-discrepancy position
  --     frac = ((rank-1) + jitter)/n through its own trip, instead of two unrelated
  --     i.i.d. draws. elapsed = planned*frac and remaining = planned*(1-frac), so the
  --     dispatch record is internally COHERENT for the first time (elapsed + remaining
  --     = planned; previously remaining was an independent 0.3x-3.0x draw off planned).
  --  B. INBOUND SLICE. The most-mature tail of the cohort (prime_inbound_fraction,
  --     default 0.30) boots as status='returning' / en_route_to_depot with its
  --     returning_started_at back-dated by a STRATIFIED lead across [0, eta), so their
  --     arrivals land uniformly across the first eta sim-minutes. This is what fills
  --     the structural dead front: at 08:00 a real depot has cars already driving home.
  --
  -- DETERMINISM: every draw is ottoq_sim_seeded_random(v_seed, <stable key>); rank is
  -- row_number() over that same seeded order with vehicle id as an absolute tiebreak;
  -- the fingerprint below is built from RELATIVE minute offsets (never wall-clock), so
  -- two runs of the same seed must produce byte-identical fingerprints.
  -- ─────────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_pool
    FROM vehicles v
   WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous'
     AND v.current_soc >= 80
     AND v.current_state IN ('staged_for_departure','en_route_to_deployment','offline')
     AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
                      WHERE d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning'));
  v_limit := LEAST(v_limit, COALESCE(v_pool,0));
  IF v_limit = 0 THEN RETURN 0; END IF;

  v_inbound_frac := LEAST(0.60, GREATEST(0, COALESCE(ottoq_policy_get(p_sim_run_id,'prime_inbound_fraction',0.30), 0.30)));
  v_eta          := GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id,'return_eta_minutes',30), 30));
  v_k            := LEAST(v_limit, FLOOR(v_limit * v_inbound_frac)::int);

  FOR v_vehicle IN
    SELECT q.id, q.current_soc, q.fleet_operator_id, q.rn,
           ((q.rn - 1)::numeric + q.jit) / v_limit AS frac
      FROM (
        SELECT v.id, v.current_soc, v.fleet_operator_id,
               row_number() OVER (ORDER BY ottoq_sim_seeded_random(v_seed, 'prime:' || v.id::text), v.id) AS rn,
               ottoq_sim_seeded_random(v_seed, 'pf:' || v.id::text) AS jit
          FROM vehicles v
         WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous'
           AND v.current_soc >= 80
           AND v.current_state IN ('staged_for_departure','en_route_to_deployment','offline')
           AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
                            WHERE d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning'))
      ) q
     WHERE q.rn <= v_limit
     ORDER BY q.rn
  LOOP
    v_planned := GREATEST(1,
        COALESCE(ottoq_sample_calibrated('trip_duration_minutes','global', v_seed, 'pt:'||v_vehicle.id::text), 30)
      * (2 + ottoq_sim_seeded_random(v_seed, 'pm:'||v_vehicle.id::text) * 6)
      * ottoq_profile_rate_mult(p_sim_run_id, 'trip_duration'));

    v_frac      := LEAST(0.999, GREATEST(0, v_vehicle.frac));
    v_elapsed   := v_planned * v_frac;
    v_remaining := v_planned * (1 - v_frac);
    v_is_inbound := (v_vehicle.rn > v_limit - v_k);
    v_did := gen_random_uuid();

    IF v_is_inbound THEN
      v_j    := v_j + 1;
      -- stratified lead so the slice's arrivals tile [now, now + eta) evenly
      v_lead := v_eta * ((v_j - 1)::numeric + ottoq_sim_seeded_random(v_seed, 'pl:'||v_vehicle.id::text)) / GREATEST(v_k,1);
      -- a car cannot have started driving home before it was dispatched
      v_elapsed    := GREATEST(v_elapsed, v_lead + 1);
      v_dispatched := p_sim_clock_now - (v_elapsed || ' minutes')::interval;
      v_return     := p_sim_clock_now + ((v_eta - v_lead) || ' minutes')::interval;

      INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
        dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status,
        returning_started_at, return_eta_minutes, return_trigger, return_evidence)
      VALUES (v_did, v_vehicle.id, p_sim_run_id, v_vehicle.fleet_operator_id,
        v_dispatched, v_return, v_planned, v_vehicle.current_soc, 'returning',
        p_sim_clock_now - (v_lead || ' minutes')::interval, v_eta, 'prime_inbound',
        jsonb_build_object('boot_prime', true, 'stratum', v_j, 'strata', v_k,
                           'lead_min', round(v_lead,3), 'eta_min', v_eta,
                           'arrives_in_min', round(v_eta - v_lead, 3)));

      UPDATE vehicles SET current_state = 'en_route_to_depot'::vehicle_state,
             config = (COALESCE(config, '{}'::jsonb) - 'service_manifest' - 'service_manifest_meta'),
             last_state_change = p_sim_clock_now, current_stall_id = NULL
       WHERE id = v_vehicle.id;
      v_inbound := v_inbound + 1;
    ELSE
      v_dispatched := p_sim_clock_now - (v_elapsed   || ' minutes')::interval;
      v_return     := p_sim_clock_now + (v_remaining || ' minutes')::interval;

      INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
        dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
      VALUES (v_did, v_vehicle.id, p_sim_run_id, v_vehicle.fleet_operator_id,
        v_dispatched, v_return, v_planned, v_vehicle.current_soc, 'active');

      UPDATE vehicles SET current_state = 'deployed'::vehicle_state,
             config = (COALESCE(config, '{}'::jsonb) - 'service_manifest' - 'service_manifest_meta'),
             last_state_change = p_sim_clock_now, current_stall_id = NULL
       WHERE id = v_vehicle.id;
    END IF;

    -- SEED-DETERMINISM FINGERPRINT: relative minute offsets only, never wall clock.
    v_off   := round(EXTRACT(EPOCH FROM (v_return - p_sim_clock_now))/60.0, 3);
    v_fp_src := v_fp_src || v_vehicle.id::text || ':'
                || CASE WHEN v_is_inbound THEN 'R' ELSE 'A' END || ':' || v_off::text || '|';
    v_count := v_count + 1;
  END LOOP;

  v_fp := md5(v_fp_src);

  IF v_count > 0 THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('boot_prime_stagger',
             jsonb_build_object('ok', true, 'primed', v_count, 'inbound', v_inbound,
               'inbound_fraction', v_inbound_frac, 'eta_min', v_eta, 'pool', v_pool,
               'cap', v_limit, 'seed', v_run.random_seed, 'prime_fingerprint', v_fp))
     WHERE sim_run_id = p_sim_run_id;

    PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'twin_prime_deployment',
      p_event_type := 'twin.deployment_primed', p_entity_type := 'system',
      p_payload := jsonb_build_object('count', v_count, 'fleet', v_total, 'fraction', p_fraction,
        'cap', v_limit, 'inbound', v_inbound, 'inbound_fraction', v_inbound_frac,
        'eta_min', v_eta, 'prime_fingerprint', v_fp, 'stagger', 'stratified_v1'),
      p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END IF;
  RETURN v_count;
END;
$function$

-- ===== ottoq_sim_pv_dc_power_kw =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_pv_dc_power_kw(p_nameplate_dc_kw numeric, p_poa_wm2 numeric, p_cell_temp_c numeric, p_soiling numeric, p_temp_coeff numeric DEFAULT '-0.0040'::numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT GREATEST(0,
    p_nameplate_dc_kw
      * (p_poa_wm2 / 1000.0)
      * (1.0 + p_temp_coeff * (p_cell_temp_c - 25.0))
      * p_soiling);
$function$

-- ===== ottoq_sim_reconcile_charge_sessions =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_reconcile_charge_sessions(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; rec RECORD; v_n int := 0;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  FOR rec IN
    SELECT v.id AS vid, v.current_stall_id AS sid, COALESCE(v.target_soc, 90) AS tsoc
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.current_state IN ('charging_dcfc','charging_l2')
       AND v.current_stall_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM ocpp_sessions s
                        WHERE s.vehicle_id = v.id AND s.status = 'active' AND s.id_token LIKE 'TWIN-%')
  LOOP
    PERFORM ottoq_sim_start_charge_session(rec.vid, rec.sid, p_sim_run_id, rec.tsoc, p_sim_clock_now);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $function$

-- ===== ottoq_sim_record_twin_event =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_record_twin_event(p_sim_run_id uuid, p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_occurred_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_event_id UUID;
BEGIN
  v_event_id := ottoq_record_event(
    p_actor_type := p_actor_type, p_actor_id := 'otto_twin', p_event_type := p_event_type,
    p_entity_type := p_entity_type, p_entity_id := p_entity_id, p_payload := p_payload,
    p_fleet_operator_id := p_fleet_operator_id, p_depot_id := p_depot_id,
    p_severity := p_severity, p_correlation_id := p_correlation_id,
    p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id
  );
  UPDATE ottoq_sim_runs SET events_generated = events_generated + 1 WHERE sim_run_id = p_sim_run_id;
  RETURN v_event_id;
END;
$function$

-- ===== ottoq_sim_recover_chargers =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_recover_chargers(p_depot_id uuid, p_sim_clock timestamp with time zone, p_repair_minutes numeric DEFAULT 75)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n integer;
BEGIN
  UPDATE ottoq_ocpp_chargers
     SET station_state = 'Available',
         station_state_changed_at = p_sim_clock,
         last_heartbeat_at = p_sim_clock,
         last_fault_code = NULL
   WHERE depot_id = p_depot_id
     AND station_state = 'Faulted'
     AND station_state_changed_at <=
         p_sim_clock - (COALESCE((last_fault_payload->>'repair_minutes')::numeric,
                                 p_repair_minutes) || ' minutes')::interval;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$

-- ===== ottoq_sim_sample_carbon_intensity =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_sample_carbon_intensity(p_seed bigint, p_salt text, p_hour integer)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_solar_fraction NUMERIC;
  v_nuclear        NUMERIC := 0.40;
  v_gas            NUMERIC := 0.25;
  v_coal           NUMERIC := 0.20;
  v_hydro          NUMERIC := 0.10;
  v_solar          NUMERIC := 0.05;
  v_noise          NUMERIC;
BEGIN
  -- Solar fraction peaks midday
  v_solar_fraction := CASE
    WHEN p_hour BETWEEN 9 AND 16 THEN 0.05 + 0.10 * (1 - ABS(p_hour - 12.5) / 4.0)
    ELSE 0.0 END;
  v_solar := GREATEST(0.02, v_solar_fraction);
  v_coal  := 0.20 - v_solar_fraction * 0.7;             -- solar mostly displaces coal
  v_gas   := 0.25 - v_solar_fraction * 0.3;

  v_noise := (ottoq_sim_seeded_random(p_seed, p_salt || '_carbon') - 0.5) * 30;

  -- gCO2/kWh weighted:
  --   nuclear: 12, gas: 490, coal: 820, hydro: 24, solar: 45
  RETURN GREATEST(150,
    v_nuclear * 12
    + v_gas    * 490
    + v_coal   * 820
    + v_hydro  * 24
    + v_solar  * 45
    + v_noise);
END;
$function$

-- ===== ottoq_sim_sample_cloud_pct =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_sample_cloud_pct(p_seed bigint, p_salt text, p_hour_of_day integer)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_u1      NUMERIC;
  v_u2      NUMERIC;
  v_beta    NUMERIC;
  v_hour_factor NUMERIC;
BEGIN
  -- Beta(α=2, β=2) gives a symmetric distribution around 50% — Nashville annual mean
  -- Realized via ratio-of-uniforms approximation
  v_u1 := GREATEST(1e-9, ottoq_sim_seeded_random(p_seed, p_salt || '_c1'));
  v_u2 := GREATEST(1e-9, ottoq_sim_seeded_random(p_seed, p_salt || '_c2'));

  -- Two-uniform Beta-like sampler
  v_beta := POWER(v_u1, 1.0/2.0);
  v_beta := v_beta / (v_beta + POWER(v_u2, 1.0/2.0));

  -- Diurnal bias: afternoon cloud development +10%, dawn -10%
  v_hour_factor := CASE
    WHEN p_hour_of_day BETWEEN 13 AND 18 THEN  0.10
    WHEN p_hour_of_day BETWEEN  4 AND  8 THEN -0.10
    ELSE 0
  END;

  RETURN GREATEST(0, LEAST(100, (v_beta + v_hour_factor) * 100));
END;
$function$

-- ===== ottoq_sim_sample_frequency_hz =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_sample_frequency_hz(p_seed bigint, p_salt text, p_rate_mult numeric DEFAULT 1)
 RETURNS TABLE(out_status text, out_freq_hz numeric)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_roll NUMERIC;
  v_freq NUMERIC;
BEGIN
  v_roll := ottoq_sim_seeded_random(p_seed, p_salt || '_freq_roll');
  v_freq := 60.0 + (ottoq_sim_seeded_random(p_seed, p_salt || '_freq') - 0.5) * 0.05;

  IF v_roll < 0.0005 * COALESCE(p_rate_mult, 1) THEN   -- ~once a week excursion (× knob)
    v_freq := v_freq + (CASE WHEN ottoq_sim_seeded_random(p_seed, p_salt||'_dir') > 0.5
                              THEN 1 ELSE -1 END) * (0.10 + ottoq_sim_seeded_random(p_seed, p_salt||'_mag') * 0.15);
    out_status := 'excursion';
  ELSE
    out_status := 'nominal';
  END IF;
  out_freq_hz := ROUND(v_freq::numeric, 3);
  RETURN NEXT;
END;
$function$

-- ===== ottoq_sim_sample_lmp_usd_mwh =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_sample_lmp_usd_mwh(p_seed bigint, p_salt text, p_hour integer, p_temp_c numeric, p_dow_idx integer, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_plan jsonb; v_seed bigint; v_clock timestamptz; v_day date; v_month int;
  v_season text; v_base numeric; v_shape numeric; v_idx int;
  v_day_mult numeric; v_resid numeric; v_spike numeric := 1.0;
  v_storm numeric := 1.0; v_u numeric; v_lmp numeric;
  v_temp_bump numeric; v_card numeric;
  -- legacy locals
  l_shape numeric; l_noise numeric; l_dow numeric;
BEGIN
  v_plan := CASE WHEN p_sim_run_id IS NOT NULL THEN ottoq_feed_plan('lmp_usd_mwh') END;

  IF v_plan IS NULL THEN
    -- ── legacy path (pre-agent behavior, unchanged) ──
    l_shape := CASE
      WHEN p_hour BETWEEN 0  AND 5  THEN 0.55 + 0.05 * ABS(3 - p_hour)
      WHEN p_hour BETWEEN 6  AND 9  THEN 1.10 + 0.15 * (p_hour - 6)
      WHEN p_hour BETWEEN 10 AND 13 THEN 1.40 + 0.05 * (p_hour - 10)
      WHEN p_hour BETWEEN 14 AND 16 THEN 1.85 + 0.10 * (p_hour - 14)
      WHEN p_hour BETWEEN 17 AND 19 THEN 2.40 + 0.15 * (19 - p_hour)
      WHEN p_hour BETWEEN 20 AND 22 THEN 1.45 - 0.10 * (p_hour - 20)
      ELSE 0.90 END;
    v_temp_bump := GREATEST(0, p_temp_c - 30) * 8.0 + GREATEST(0, -5 - p_temp_c) * 5.0;
    l_dow := CASE WHEN p_dow_idx IN (0, 6) THEN 0.85 ELSE 1.0 END;
    l_noise := (ottoq_sim_seeded_random(p_seed, p_salt || '_lmp_n') - 0.5) * 0.5;
    IF ottoq_sim_seeded_random(p_seed, p_salt || '_lmp_spike') < 0.01 THEN l_noise := l_noise + 1.5; END IF;
    RETURN GREATEST(8, (32.0 * l_shape + v_temp_bump) * (1 + l_noise) * l_dow);
  END IF;

  -- ── plan path: MISO-calibrated, run-seed CRN ──
  SELECT COALESCE(random_seed, 42), COALESCE(sim_clock_current, now())
    INTO v_seed, v_clock FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  v_day := (v_clock AT TIME ZONE 'America/Chicago')::date;
  v_month := EXTRACT(MONTH FROM v_day)::int;
  v_season := CASE WHEN v_month IN (6,7,8,9) THEN 'summer'
                   WHEN v_month IN (12,1,2)  THEN 'winter'
                   ELSE 'shoulder' END;

  v_base := (v_plan->'seasonal_mean_usd_mwh'->>v_season)::numeric;
  -- local CST hour -> EST HE array position: ((h+1) % 24) + 1
  v_idx := ((p_hour + 1) % 24) + 1;
  v_shape := (v_plan->'hourly_shape_est_he1_24'->v_season->>(v_idx - 1))::numeric;

  -- day-regime card (one draw per sim-day, persisted, CRN on run seed)
  SELECT value INTO v_card FROM ottoq_variability_cards
   WHERE sim_run_id = p_sim_run_id AND var_key = 'lmp_day_regime'
     AND scope_instance = 'grid' AND bucket_key = 'day:' || v_day::text;
  IF v_card IS NULL THEN
    v_u := ottoq_sim_seeded_random(v_seed, 'lmp_day:' || v_day::text);
    v_card := LEAST(GREATEST(1 + (v_u - 0.5) * 2 * (v_plan->'day_regime'->>'sigma_rel')::numeric,
              (v_plan->'day_regime'->'clamp'->>0)::numeric), (v_plan->'day_regime'->'clamp'->>1)::numeric);
    INSERT INTO ottoq_variability_cards(sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, meta, drawn_at_clock, drawn_at_tick)
    VALUES (p_sim_run_id, 'lmp_day_regime', 'grid', 'day', 'day:' || v_day::text, round(v_card, 4),
            jsonb_build_object('plan', 'lmp_usd_mwh.v1', 'season', v_season), v_clock, 0)
    ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO NOTHING;
  END IF;
  v_day_mult := v_card;

  -- winter-storm day card (the Jan-2024/25/26 precedent regime: sustained multi-hour)
  IF v_season = 'winter' THEN
    SELECT value INTO v_card FROM ottoq_variability_cards
     WHERE sim_run_id = p_sim_run_id AND var_key = 'lmp_storm_day'
       AND scope_instance = 'grid' AND bucket_key = 'day:' || v_day::text;
    IF v_card IS NULL THEN
      v_u := ottoq_sim_seeded_random(v_seed, 'lmp_storm:' || v_day::text);
      IF v_u < (v_plan->'spike'->>'storm_p_day_winter')::numeric THEN
        v_card := (v_plan->'spike'->'storm_mult_range'->>0)::numeric
                + ottoq_sim_seeded_random(v_seed, 'lmp_storm_mag:' || v_day::text)
                  * ((v_plan->'spike'->'storm_mult_range'->>1)::numeric - (v_plan->'spike'->'storm_mult_range'->>0)::numeric);
      ELSE
        v_card := 1.0;
      END IF;
      INSERT INTO ottoq_variability_cards(sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, meta, drawn_at_clock, drawn_at_tick)
      VALUES (p_sim_run_id, 'lmp_storm_day', 'grid', 'day', 'day:' || v_day::text, round(v_card, 2),
              jsonb_build_object('plan', 'lmp_usd_mwh.v1', 'storm', v_card > 1.0), v_clock, 0)
      ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO NOTHING;
    END IF;
    v_storm := GREATEST(v_card, 1.0);
  END IF;

  -- within-hour residual (CRN: seed + day + hour)
  v_u := ottoq_sim_seeded_random(v_seed, 'lmp_h:' || v_day::text || ':' || p_hour::text);
  v_resid := LEAST(GREATEST(1 + (v_u - 0.5) * 2 * (v_plan->'residual'->>'sigma_rel')::numeric,
             (v_plan->'residual'->'clamp'->>0)::numeric), (v_plan->'residual'->'clamp'->>1)::numeric);

  -- routine hourly spike (computed: ~1% of hours >$100)
  v_u := ottoq_sim_seeded_random(v_seed, 'lmp_spk:' || v_day::text || ':' || p_hour::text);
  IF v_u < (v_plan->'spike'->>'p_hour')::numeric THEN
    v_spike := (v_plan->'spike'->'mult_range'->>0)::numeric
             + ottoq_sim_seeded_random(v_seed, 'lmp_spkm:' || v_day::text || ':' || p_hour::text)
               * ((v_plan->'spike'->'mult_range'->>1)::numeric - (v_plan->'spike'->'mult_range'->>0)::numeric);
  END IF;

  -- temperature scarcity proxy (declared assumption, scaled from evidence)
  v_temp_bump := GREATEST(0, p_temp_c - 32) * (v_plan->'temp_coupling'->>'heat_per_c_above_32')::numeric
               + GREATEST(0, -p_temp_c) * (v_plan->'temp_coupling'->>'cold_per_c_below_0')::numeric;

  v_lmp := (v_base * v_shape * v_day_mult * v_resid + v_temp_bump) * GREATEST(v_spike, v_storm);
  RETURN LEAST(GREATEST(v_lmp, (v_plan->>'floor_usd_mwh')::numeric),
               (v_plan->'spike'->>'ceiling_usd_mwh')::numeric);
END;
$function$

-- ===== ottoq_sim_sample_lognormal_ms =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_sample_lognormal_ms(p_mean_ms integer, p_p99_ms integer, p_seed bigint, p_salt text)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_u1     NUMERIC;
  v_u2     NUMERIC;
  v_z      NUMERIC;          -- standard normal
  v_mu     NUMERIC;          -- lognormal mu
  v_sigma  NUMERIC;          -- lognormal sigma
  v_x      NUMERIC;          -- sampled lognormal
BEGIN
  -- Solve mu, sigma from mean and p99
  --   E[X] = exp(mu + sigma^2/2)
  --   p99(X) = exp(mu + 2.326*sigma)
  -- Use simple inversion: sigma ~ ln(p99/mean) / 1.826
  v_sigma := GREATEST(0.2, LN(GREATEST(p_p99_ms::numeric, p_mean_ms::numeric * 1.5) / p_mean_ms::numeric) / 1.826);
  v_mu    := LN(p_mean_ms::numeric) - (v_sigma * v_sigma / 2.0);

  v_u1 := GREATEST(1e-9, ottoq_sim_seeded_random(p_seed, p_salt || '_u1'));
  v_u2 := ottoq_sim_seeded_random(p_seed, p_salt || '_u2');

  -- Box-Muller transform
  v_z := SQRT(-2.0 * LN(v_u1)) * COS(2.0 * PI() * v_u2);

  v_x := EXP(v_mu + v_sigma * v_z);
  RETURN GREATEST(10, LEAST(60000, ROUND(v_x)::integer));   -- clamp [10ms, 60s]
END;
$function$

-- ===== ottoq_sim_sample_precip_state =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_sample_precip_state(p_seed bigint, p_salt text, p_prev_state text, p_cloud_pct numeric, p_rate_mult numeric DEFAULT 1, p_sim_run_id uuid DEFAULT NULL::uuid, p_sim_clock timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(out_state text, out_mm_per_hr numeric)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_plan jsonb; v_budget numeric; v_seed bigint; v_day int; v_mo int; v_hour int;
  v_n_h int; v_start int; v_u numeric; v_int numeric;
  v_roll numeric; v_rain_prob numeric;
BEGIN
  v_plan := CASE WHEN p_sim_run_id IS NOT NULL AND p_sim_clock IS NOT NULL
                 THEN ottoq_feed_plan('precip_unified') END;

  IF v_plan IS NULL THEN
    -- ── legacy path (pre-agent literals, unchanged) ──
    v_roll := ottoq_sim_seeded_random(p_seed, p_salt || '_pr');
    v_rain_prob := (p_cloud_pct / 100.0) * 0.15;
    IF p_prev_state IN ('rain', 'heavy_rain', 'storm') THEN
      v_rain_prob := v_rain_prob * 4.0 + 0.3;
    ELSIF p_prev_state = 'drizzle' THEN
      v_rain_prob := v_rain_prob * 2.0 + 0.10;
    END IF;
    v_rain_prob := v_rain_prob * COALESCE(p_rate_mult, 1);
    IF v_roll < v_rain_prob THEN
      v_int := ottoq_sim_seeded_random(p_seed, p_salt || '_int');
      IF v_int < 0.05 THEN out_state := 'storm'; out_mm_per_hr := 15 + v_int * 30;
      ELSIF v_int < 0.20 THEN out_state := 'heavy_rain'; out_mm_per_hr := 5 + v_int * 10;
      ELSIF v_int < 0.55 THEN out_state := 'rain'; out_mm_per_hr := 1 + v_int * 4;
      ELSE out_state := 'drizzle'; out_mm_per_hr := 0.2 + v_int * 0.8; END IF;
    ELSE out_state := 'dry'; out_mm_per_hr := 0; END IF;
    RETURN NEXT; RETURN;
  END IF;

  -- ── plan path: the day's budget card is the single truth ──
  v_budget := ottoq_precip_daily_mm(p_sim_run_id, p_sim_clock);
  IF v_budget < (v_plan->>'wet_day_threshold_mm')::numeric THEN
    out_state := 'dry'; out_mm_per_hr := 0; RETURN NEXT; RETURN;
  END IF;

  SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  v_day  := (p_sim_clock::date - DATE '2020-01-01');
  v_mo   := EXTRACT(MONTH FROM p_sim_clock AT TIME ZONE 'America/Chicago')::int;
  v_hour := EXTRACT(HOUR FROM p_sim_clock AT TIME ZONE 'America/Chicago')::int;

  -- wet-window length by budget (declared assumption)
  v_n_h := CASE WHEN v_budget < 2 THEN (v_plan->'hourly_disaggregation'->'wet_hours_by_budget'->>'lt2mm')::int
                WHEN v_budget < 10 THEN (v_plan->'hourly_disaggregation'->'wet_hours_by_budget'->>'lt10mm')::int
                WHEN v_budget < 25 THEN (v_plan->'hourly_disaggregation'->'wet_hours_by_budget'->>'lt25mm')::int
                ELSE (v_plan->'hourly_disaggregation'->'wet_hours_by_budget'->>'gte25mm')::int END;

  -- window start: summer convective afternoon bias, else any hour (day-stable draw)
  v_u := ottoq_sim_seeded_random(v_seed, 'precip_win:' || v_day);
  IF v_mo BETWEEN 6 AND 9 THEN
    v_start := (v_plan->'hourly_disaggregation'->'summer_convective_start_hours'->>0)::int
             + floor(v_u * ((v_plan->'hourly_disaggregation'->'summer_convective_start_hours'->>1)::int
                          - (v_plan->'hourly_disaggregation'->'summer_convective_start_hours'->>0)::int + 1))::int;
  ELSE
    v_start := floor(v_u * (24 - v_n_h))::int;
  END IF;

  IF v_hour >= v_start AND v_hour < v_start + v_n_h THEN
    -- intensity = budget/hours × hour jitter (run-seeded, CRN)
    v_u := ottoq_sim_seeded_random(v_seed, 'precip_hr:' || v_day || ':' || v_hour);
    v_int := (v_budget / v_n_h) * ((v_plan->'hourly_disaggregation'->'intensity_jitter'->>0)::numeric
           + v_u * ((v_plan->'hourly_disaggregation'->'intensity_jitter'->>1)::numeric
                  - (v_plan->'hourly_disaggregation'->'intensity_jitter'->>0)::numeric));
    out_mm_per_hr := round(v_int, 2);
    out_state := CASE
      WHEN v_int < (v_plan->'hourly_disaggregation'->'state_thresholds_mm_hr'->>'drizzle')::numeric THEN 'drizzle'
      WHEN v_int < (v_plan->'hourly_disaggregation'->'state_thresholds_mm_hr'->>'rain')::numeric THEN 'rain'
      WHEN v_int < (v_plan->'hourly_disaggregation'->'state_thresholds_mm_hr'->>'heavy_rain')::numeric THEN 'heavy_rain'
      ELSE 'storm' END;
  ELSE
    out_state := 'dry'; out_mm_per_hr := 0;
  END IF;
  RETURN NEXT;
END;
$function$

-- ===== ottoq_sim_sample_voltage_event =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_sample_voltage_event(p_seed bigint, p_salt text, p_rate_mult numeric DEFAULT 1)
 RETURNS TABLE(out_status text, out_voltage_v numeric)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_roll NUMERIC;
  v_m    NUMERIC := COALESCE(p_rate_mult, 1);
BEGIN
  v_roll := ottoq_sim_seeded_random(p_seed, p_salt || '_volt');

  IF v_roll < 0.000008 * v_m THEN          -- ~1-2 per year per hour-bucket (× knob)
    out_status := 'brownout';
    out_voltage_v := 380 + ottoq_sim_seeded_random(p_seed, p_salt || '_v') * 40;
  ELSIF v_roll < 0.0002 * v_m THEN          -- ~1-3 per month (× knob)
    out_status := 'sag';
    out_voltage_v := 440 + ottoq_sim_seeded_random(p_seed, p_salt || '_v') * 30;
  ELSIF v_roll < 0.0004 * v_m THEN
    out_status := 'swell';
    out_voltage_v := 500 + ottoq_sim_seeded_random(p_seed, p_salt || '_v') * 20;
  ELSE
    out_status := 'nominal';
    out_voltage_v := 478 + ottoq_sim_seeded_random(p_seed, p_salt || '_v') * 5;
  END IF;
  RETURN NEXT;
END;
$function$

-- ===== ottoq_sim_seed_fleet =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seed_fleet(p_depot_id uuid, p_seed bigint DEFAULT 42)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed BIGINT := COALESCE(p_seed, 42);
  v_hour INT := EXTRACT(HOUR FROM (NOW() AT TIME ZONE 'America/Chicago'))::int;
  v_deploy_frac NUMERIC := ottoq_deploy_target_fraction(v_hour, 0.90);
BEGIN
  -- superseded-run leftovers never actually returned: abort, don't "complete"
  -- (completed requires return_trigger + feeds turnaround metrics)
  UPDATE ottoq_vehicle_dispatches d
     SET status = 'aborted',
         actual_return_at = COALESCE(actual_return_at, NOW()),
         return_trigger = COALESCE(return_trigger, 'run_reseed_abort')
    FROM vehicles v
   WHERE d.vehicle_id = v.id AND v.home_depot_id = p_depot_id
     AND d.status IN ('active','returning');

  UPDATE ocpp_sessions cs
     SET status = 'completed', ended_at = COALESCE(ended_at, NOW())
   WHERE cs.depot_id = p_depot_id AND cs.status = 'active'::ocpp_session_status
     AND cs.id_token LIKE 'TWIN-%';

  UPDATE vehicles v
     SET current_state = CASE
           -- deploy pool: the first v_deploy_frac by seeded rank → prime sends OUT
           WHEN r.rn <= FLOOR(r.total * v_deploy_frac) THEN 'staged_for_departure'::vehicle_state
           -- service cohort, weighted charge-first (a returning wave at the gate)
           WHEN r.svcroll < 0.55 THEN 'arrived_at_gate'::vehicle_state
           WHEN r.svcroll < 0.78 THEN 'charge_complete_holding'::vehicle_state
           ELSE 'staged_awaiting_service'::vehicle_state
         END,
         current_soc = CASE
           WHEN r.rn <= FLOOR(r.total * v_deploy_frac) THEN ROUND(86 + r.socroll * 13)::int
           WHEN r.svcroll < 0.55 THEN ROUND(12 + r.socroll * 35)::int   -- gate: LOW, charge-first
           WHEN r.svcroll < 0.78 THEN ROUND(88 + r.socroll * 11)::int   -- holding: high
           ELSE ROUND(78 + r.socroll * 20)::int                          -- awaiting: mid/high
         END,
         current_stall_id = NULL, current_soc_updated_at = NOW(), current_soc_source = 'oem_telemetry',
         last_state_change = NOW() - ((r.stagger * 90)::text || ' minutes')::interval,
         config = CASE
           WHEN r.rn > FLOOR(r.total * v_deploy_frac) AND r.svcroll >= 0.78
             THEN jsonb_set(COALESCE(v.config,'{}'::jsonb) - 'service_ends_at' - 'flagged_issue_type' - 'exception' - 'draining_item',
                            '{svc_step}', to_jsonb('need_service'::text))
           ELSE COALESCE(v.config,'{}'::jsonb) - 'svc_step' - 'service_ends_at' - 'flagged_issue_type' - 'exception' - 'draining_item'
         END
    FROM (
      SELECT id,
             row_number() OVER (ORDER BY ottoq_sim_seeded_random(v_seed, 'lane:'||id::text)) AS rn,
             count(*) OVER () AS total,
             ottoq_sim_seeded_random(v_seed, 'soc:'||id::text)     AS socroll,
             ottoq_sim_seeded_random(v_seed, 'stagger:'||id::text) AS stagger,
             ottoq_sim_seeded_random(v_seed, 'svc:'||id::text)     AS svcroll
        FROM vehicles WHERE home_depot_id = p_depot_id AND category = 'autonomous'
    ) r
   WHERE v.id = r.id;

  UPDATE ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = NOW(), last_fault_code = NULL
   WHERE depot_id = p_depot_id;
  UPDATE stalls SET status = 'available', current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
   WHERE depot_id = p_depot_id;
  RETURN;
END;
$function$

-- ===== ottoq_sim_seed_fleet =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seed_fleet(p_depot_id uuid, p_seed bigint DEFAULT 42, p_hour integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed BIGINT := COALESCE(p_seed, 42);
  v_hour INT := COALESCE(p_hour, EXTRACT(HOUR FROM (NOW() AT TIME ZONE 'America/Chicago'))::int);
  v_deploy_frac NUMERIC := ottoq_deploy_target_fraction(v_hour, 0.90);
BEGIN
  -- superseded-run leftovers never actually returned: abort, don't "complete"
  -- (completed requires return_trigger + feeds turnaround metrics)
  UPDATE ottoq_vehicle_dispatches d
     SET status = 'aborted',
         actual_return_at = COALESCE(actual_return_at, NOW()),
         return_trigger = COALESCE(return_trigger, 'run_reseed_abort')
    FROM vehicles v
   WHERE d.vehicle_id = v.id AND v.home_depot_id = p_depot_id
     AND d.status IN ('active','returning');

  UPDATE ocpp_sessions cs
     SET status = 'completed', ended_at = COALESCE(ended_at, NOW())
   WHERE cs.depot_id = p_depot_id AND cs.status = 'active'::ocpp_session_status
     AND cs.id_token LIKE 'TWIN-%';

  UPDATE vehicles v
     SET current_state = CASE
           WHEN r.rn <= FLOOR(r.total * v_deploy_frac) THEN 'staged_for_departure'::vehicle_state
           -- thin gate trickle (was 0.55): avoids the t0 entrance stack
           WHEN r.svcroll < 0.20 THEN 'arrived_at_gate'::vehicle_state
           WHEN r.svcroll < 0.65 THEN 'charge_complete_holding'::vehicle_state
           ELSE 'staged_awaiting_service'::vehicle_state
         END,
         current_soc = CASE
           WHEN r.rn <= FLOOR(r.total * v_deploy_frac) THEN ROUND(86 + r.socroll * 13)::int
           WHEN r.svcroll < 0.20 THEN ROUND(12 + r.socroll * 35)::int   -- gate: LOW, charge-first
           WHEN r.svcroll < 0.65 THEN ROUND(88 + r.socroll * 11)::int   -- holding: high
           ELSE ROUND(78 + r.socroll * 20)::int                          -- awaiting: mid/high
         END,
         current_stall_id = NULL, current_soc_updated_at = NOW(), current_soc_source = 'oem_telemetry',
         last_state_change = NOW() - ((r.stagger * 90)::text || ' minutes')::interval,
         config = CASE
           WHEN r.rn > FLOOR(r.total * v_deploy_frac) AND r.svcroll >= 0.65
             THEN jsonb_set(COALESCE(v.config,'{}'::jsonb) - 'service_ends_at' - 'flagged_issue_type' - 'exception' - 'draining_item',
                            '{svc_step}', to_jsonb('need_service'::text))
           ELSE COALESCE(v.config,'{}'::jsonb) - 'svc_step' - 'service_ends_at' - 'flagged_issue_type' - 'exception' - 'draining_item'
         END
    FROM (
      SELECT id,
             row_number() OVER (ORDER BY ottoq_sim_seeded_random(v_seed, 'lane:'||id::text)) AS rn,
             count(*) OVER () AS total,
             ottoq_sim_seeded_random(v_seed, 'soc:'||id::text)     AS socroll,
             ottoq_sim_seeded_random(v_seed, 'stagger:'||id::text) AS stagger,
             ottoq_sim_seeded_random(v_seed, 'svc:'||id::text)     AS svcroll
        FROM vehicles WHERE home_depot_id = p_depot_id AND category = 'autonomous'
    ) r
   WHERE v.id = r.id;

  UPDATE ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = NOW(), last_fault_code = NULL
   WHERE depot_id = p_depot_id;
  UPDATE stalls SET status = 'available', current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
   WHERE depot_id = p_depot_id;
  RETURN;
END;
$function$

-- ===== ottoq_sim_seeded_random =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seeded_random(p_seed bigint, p_salt text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hash BIGINT;
BEGIN
  -- Combine seed + salt into a deterministic hash, normalize to [0,1)
  v_hash := abs(hashtextextended(p_seed::text || ':' || p_salt, p_seed));
  RETURN (v_hash % 1000000)::NUMERIC / 1000000.0;
END;
$function$

-- ===== ottoq_sim_service_minutes =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_service_minutes(p_sim_run_id uuid, p_time_key text, p_base_min numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_knobs JSONB; v_m NUMERIC;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN p_base_min; END IF;
  SELECT knobs INTO v_knobs FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  v_m := COALESCE((v_knobs #>> ARRAY['_rates', p_time_key])::numeric, 1);
  RETURN GREATEST(1, p_base_min * v_m);
END;
$function$

-- ===== ottoq_sim_solar_elevation_deg =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_solar_elevation_deg(p_at_utc timestamp with time zone, p_lat numeric, p_lng numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_n            INTEGER;          -- day-of-year (1-366)
  v_decl_deg     NUMERIC;          -- solar declination
  v_lst_hours    NUMERIC;          -- local solar time, decimal hours
  v_hour_ang_deg NUMERIC;
  v_lat_rad      NUMERIC;
  v_decl_rad     NUMERIC;
  v_hra_rad      NUMERIC;
  v_sin_elev     NUMERIC;
  v_elev_rad     NUMERIC;
BEGIN
  v_n        := EXTRACT(DOY FROM p_at_utc);
  v_decl_deg := 23.45 * SIN(RADIANS(360.0/365.0 * (v_n + 284)));

  -- Local solar time ≈ UTC hour + lng/15 + EoT (we ignore EoT for ±15 min)
  v_lst_hours := EXTRACT(EPOCH FROM p_at_utc) / 3600.0;
  v_lst_hours := (v_lst_hours + p_lng / 15.0) - FLOOR((v_lst_hours + p_lng / 15.0) / 24) * 24;

  v_hour_ang_deg := 15.0 * (v_lst_hours - 12.0);

  v_lat_rad  := RADIANS(p_lat);
  v_decl_rad := RADIANS(v_decl_deg);
  v_hra_rad  := RADIANS(v_hour_ang_deg);

  v_sin_elev := SIN(v_lat_rad) * SIN(v_decl_rad)
              + COS(v_lat_rad) * COS(v_decl_rad) * COS(v_hra_rad);

  v_elev_rad := ASIN(GREATEST(-1.0, LEAST(1.0, v_sin_elev)));
  RETURN DEGREES(v_elev_rad);
END;
$function$

-- ===== ottoq_sim_start_charge_session =====
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

  v_target_soc := COALESCE(p_target_soc, v_vehicle.target_soc, 90);
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

-- ===== ottoq_sim_start_run =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_start_run(p_scenario_code text, p_sim_clock_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_time_scale numeric DEFAULT NULL::numeric, p_random_seed bigint DEFAULT NULL::bigint, p_run_by text DEFAULT 'otto_twin'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_scenario   ottoq_scenarios%ROWTYPE;
  v_run_id     UUID := gen_random_uuid();
  v_clock_start TIMESTAMPTZ;
  v_clock_end  TIMESTAMPTZ;
  v_time_scale NUMERIC;
  v_seed       BIGINT;
BEGIN
  SELECT * INTO v_scenario FROM ottoq_scenarios
   WHERE scenario_code = p_scenario_code AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OTTOQ_SCENARIO_NOT_FOUND: %', p_scenario_code USING ERRCODE = 'P0001';
  END IF;
  v_clock_start := COALESCE(p_sim_clock_start, date_trunc('day', NOW()) + INTERVAL '6 hours');
  v_clock_end   := v_clock_start + (v_scenario.sim_duration_minutes || ' minutes')::INTERVAL;
  v_time_scale  := COALESCE(p_time_scale, v_scenario.default_time_scale);
  v_seed        := COALESCE(p_random_seed, v_scenario.random_seed);

  INSERT INTO ottoq_sim_runs (
    sim_run_id, scenario_id, scenario_code, started_at, last_tick_at, next_tick_due_at,
    sim_clock_start, sim_clock_current, sim_clock_end,
    time_scale, tick_interval_seconds, depot_id, random_seed, status, run_by
  ) VALUES (
    v_run_id, v_scenario.scenario_id, v_scenario.scenario_code, NOW(), NULL, NOW(),
    v_clock_start, v_clock_start, v_clock_end,
    v_time_scale, v_scenario.tick_interval_seconds, v_scenario.depot_id, v_seed, 'running', p_run_by
  );

  PERFORM ottoq_record_event(
    p_actor_type    := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type    := 'twin.sim_run_started', p_entity_type := 'sim_run', p_entity_id := v_run_id,
    p_depot_id      := v_scenario.depot_id,
    p_payload       := jsonb_build_object(
                        'scenario_code', p_scenario_code, 'category', v_scenario.category,
                        'sim_duration_minutes', v_scenario.sim_duration_minutes,
                        'time_scale', v_time_scale, 'random_seed', v_seed,
                        'sim_clock_start', v_clock_start, 'sim_clock_end', v_clock_end),
    p_severity      := 'info',
    p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := v_run_id
  );
  RETURN v_run_id;
END;
$function$

-- ===== ottoq_sim_stop_charge_session =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_stop_charge_session(p_session_id uuid, p_reason text DEFAULT 'completed'::text, p_sim_clock_now timestamp with time zone DEFAULT NULL::timestamp with time zone, p_fault_message text DEFAULT NULL::text, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_session ocpp_sessions%ROWTYPE;
  v_clock TIMESTAMPTZ;
  v_duration_s NUMERIC; v_avg_power NUMERIC; v_vehicle RECORD;
  v_new_status ocpp_session_status;
  v_requeue boolean := false; v_temp_hold jsonb; v_temp_stall uuid; v_fault_depot uuid;
  v_repair_min numeric;
BEGIN
  v_clock := COALESCE(p_sim_clock_now, NOW());
  SELECT * INTO v_session FROM ocpp_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_session.status <> 'active' THEN
    -- Session already closed elsewhere. Do NOT repeat the accounting, but DO
    -- make sure the physical resources were actually released (this is the
    -- path that used to strand chargers as Occupied on empty stalls).
    UPDATE ottoq_ocpp_chargers c
       SET station_state = 'Available', station_state_changed_at = v_clock
     WHERE c.charger_id IN (SELECT ocpp_charger_id FROM stalls WHERE id = v_session.stall_id)
       AND c.station_state = 'Occupied'
       AND NOT EXISTS (SELECT 1 FROM ocpp_sessions s2
                        WHERE s2.stall_id = v_session.stall_id AND s2.status = 'active');
    UPDATE stalls s SET current_vehicle_id = NULL
     WHERE s.id = v_session.stall_id
       AND s.current_vehicle_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM vehicles v
                        WHERE v.id = s.current_vehicle_id AND v.current_stall_id = s.id);
    RETURN;
  END IF;

  v_duration_s := EXTRACT(EPOCH FROM (v_clock - v_session.started_at));
  v_avg_power := CASE WHEN v_duration_s > 0 THEN
    (v_session.energy_delivered_kwh * 3600.0 / v_duration_s) ELSE 0 END;
  SELECT id, fleet_operator_id, current_soc, display_name, COALESCE(target_soc,85) AS target_soc
    INTO v_vehicle FROM vehicles WHERE id = v_session.vehicle_id;

  v_new_status := (CASE
    WHEN p_reason = 'completed' THEN 'completed'
    WHEN p_reason LIKE 'fault%' THEN 'faulted'
    ELSE 'cancelled' END)::ocpp_session_status;

  UPDATE ocpp_sessions SET
    status = v_new_status, ended_at = v_clock, soc_end = v_vehicle.current_soc,
    avg_power_kw = v_avg_power, stopped_reason = p_reason,
    last_fault_message = p_fault_message, updated_at = NOW()
   WHERE id = p_session_id;

  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StopTransaction', jsonb_build_object(
      'transactionId', v_session.transaction_id,
      'meterStop', v_session.energy_delivered_kwh,
      'soc_end_pct', v_vehicle.current_soc, 'reason', p_reason,
      'energy_delivered_kwh', v_session.energy_delivered_kwh,
      'duration_seconds', v_duration_s, 'timestamp', v_clock));
  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StatusNotification', jsonb_build_object(
      'connectorId',1,'connectorStatus','Available','evseId',1,'timestamp',v_clock));

  -- feed-agent: the fault card dealt for this session carries the drawn
  -- repair duration (fitted repair_days grid x staffed-depot x fault mode)
  IF p_reason LIKE 'fault%' AND p_sim_run_id IS NOT NULL THEN
    SELECT (meta->>'repair_minutes')::numeric INTO v_repair_min
      FROM ottoq_variability_cards
     WHERE sim_run_id = p_sim_run_id AND var_key = 'charger_fault'
       AND scope_instance = p_session_id::text
       AND bucket_key = 'session:' || p_session_id::text;
  END IF;

  UPDATE ottoq_ocpp_chargers c SET
    station_state = CASE WHEN p_reason LIKE 'fault%' THEN 'Faulted' ELSE 'Available' END,
    station_state_changed_at = v_clock,
    last_fault_code = CASE WHEN p_reason LIKE 'fault%' THEN p_reason ELSE c.last_fault_code END,
    last_fault_at = CASE WHEN p_reason LIKE 'fault%' THEN v_clock ELSE c.last_fault_at END,
    last_fault_payload = CASE WHEN p_reason LIKE 'fault%' THEN
      jsonb_build_object('reason',p_reason,'message',p_fault_message,'session_id',p_session_id,
                         'repair_minutes', v_repair_min)
      ELSE c.last_fault_payload END
   WHERE charger_id IN (SELECT ocpp_charger_id FROM stalls WHERE id = v_session.stall_id);

  UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_session.stall_id;

  -- S3a AUTO RE-ROUTE: fault interrupted the charge with the vehicle still under target →
  -- re-queue so OTTO-Q reassigns a healthy charger; otherwise proceed to disposition.
  v_requeue := (p_reason LIKE 'fault%' AND v_vehicle.current_soc < v_vehicle.target_soc - 5);
  IF v_requeue THEN
    -- DOCTRINE (Chase 2026-07-28): a vehicle is NEVER queued at the gate. A charger
      -- dying mid-charge is temp-staging case 3(a): give it a booked temp stall and let
      -- OTTO-Q re-route it to a healthy charger from there.
      SELECT s.depot_id INTO v_fault_depot FROM stalls s WHERE s.id = v_session.stall_id;
      v_temp_hold := ottoq_book_hold_stall(p_sim_run_id, v_fault_depot, v_session.vehicle_id,
                                           v_clock, v_clock + interval '30 minutes');
      IF COALESCE((v_temp_hold->>'booked')::boolean, false) THEN
        SELECT b.stall_id INTO v_temp_stall FROM ottoq_stall_bookings b
         WHERE b.booking_id = (v_temp_hold->>'booking_id')::uuid;
        UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               current_stall_id = v_temp_stall, last_state_change = v_clock
         WHERE id = v_session.vehicle_id;
        UPDATE stalls SET current_vehicle_id = v_session.vehicle_id, status = 'occupied'
         WHERE id = v_temp_stall;
      ELSE
        -- Staging genuinely full: still not the gate. Hold state without a stall and
        -- let the next tick place it; this is the only degraded path and it is visible.
        UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               current_stall_id = NULL, last_state_change = v_clock
         WHERE id = v_session.vehicle_id;
      END IF;
  ELSE
    UPDATE vehicles SET current_state = 'charge_complete_holding'::vehicle_state,
                        current_stall_id = NULL, last_state_change = v_clock
     WHERE id = v_session.vehicle_id;
  END IF;

  -- A2-B2: close the charge leg; deviation_s = actual vs physics-planned end.
  PERFORM ottoq_itin_leg_close(p_sim_run_id, v_session.vehicle_id,
    ARRAY['charge_dcfc','charge_l2'], v_clock, 'done');

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'twin_charge_orchestrator',
    p_event_type := CASE WHEN p_reason LIKE 'fault%' THEN 'charge.session_faulted'
                                                     ELSE 'charge.session_completed' END,
    p_entity_type := 'ocpp_session', p_entity_id := p_session_id,
    p_fleet_operator_id := v_vehicle.fleet_operator_id, p_depot_id := v_session.depot_id,
    p_payload := jsonb_build_object('reason',p_reason,'fault_message',p_fault_message,
      'vehicle',v_vehicle.display_name,'soc_start',v_session.soc_start,
      'soc_end',v_vehicle.current_soc,'energy_kwh',v_session.energy_delivered_kwh,
      'duration_s',v_duration_s,'avg_power_kw',ROUND(v_avg_power::numeric,2),
      'repair_minutes', v_repair_min,
      'auto_rerouted', v_requeue),
    p_severity := CASE WHEN p_reason LIKE 'fault%' THEN 'warning' ELSE 'info' END,
    p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
END;
$function$

-- ===== ottoq_sim_vehicle_exception_handler =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_vehicle_exception_handler(p_depot_id uuid, p_sim_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed bigint; v_rec RECORD; v_sev text; v_n int := 0;
  v_per_tick numeric;
  v_approve_delay_min numeric := 12; v_stall uuid;
  v_plan jsonb;
  v_gate jsonb; v_mid boolean; v_ends timestamptz; v_remaining numeric;
  v_stall_code text; v_defer_max numeric; v_resume_reason text; v_evict jsonb;
  v_immob boolean; v_immob_share numeric; v_defer_max_crit numeric;
  v_booking uuid; v_starts timestamptz; v_reopened int; v_budget numeric;
  v_bk_hi timestamptz; v_purpose text;
  v_roll numeric; v_si_share numeric; v_si boolean; v_fault_class text;
  v_defer_max_immob numeric; v_defer_class text;
BEGIN
  v_seed := abs(hashtextextended(p_depot_id::text || p_sim_clock::text || 'vexc', 17));
  v_per_tick  := COALESCE(ottoq_policy_get(p_sim_run_id, 'vehicle_fault_rate_per_tick', 0.004), 0.004);
  v_defer_max := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_defer_max_min', 45), 45);
  -- A critical-but-mobile fault is deferred on a MUCH shorter budget than a major one.
  v_defer_max_crit := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_defer_max_min_critical', 10), 10);
  -- An IMMOBILIZING but charge-safe fault gets the longest bounded budget: the vehicle is not
  -- going anywhere without a tow, so the plug may as well finish. BOUNDED -- never open-ended.
  v_defer_max_immob := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_defer_max_min_immobilizing', 180), 180);
  -- TUNABLE ASSUMPTION, not a measured fact: the share of CRITICAL faults that immobilize the
  -- vehicle. In production this is the OEM fault code's drivable/not-drivable bit.
  v_immob_share := COALESCE(ottoq_policy_get(p_sim_run_id, 'vehicle_fault_immobilizing_share', 0.35), 0.35);
  -- ══════════════ P2: FAULT CLASS TAXONOMY ══════════════
  -- `immobilizing` and `service_incompatible` are DERIVED from ONE roll against a documented
  -- class taxonomy, not rolled independently -- physics correlates them, and in production this
  -- is a single lookup from the OEM fault code. Ordering the classes by cumulative share on the
  -- SAME roll key ('immob:'||id) that phase 10/11 used means the immobilizing bit is
  -- BIT-IDENTICAL to before and service_incompatible is a STRICT SUBSET of it -- so any change
  -- in evictions is provably the narrowed predicate, not a re-drawn seed.
  --   roll <  0.099  hv_battery_thermal      immobilizing=Y  service_incompatible=Y
  --   roll <  0.18   charge_system_fault     immobilizing=Y  service_incompatible=Y
  --   roll <  0.282  drive_actuator_failure  immobilizing=Y  service_incompatible=N
  --   roll <  0.35   steering_brake_fault    immobilizing=Y  service_incompatible=N
  --   roll <  0.65   compute_stack_fault     immobilizing=N  service_incompatible=N
  --   else           sensor_suite_fault      immobilizing=N  service_incompatible=N
  v_si_share := LEAST(COALESCE(ottoq_policy_get(p_sim_run_id,'vehicle_fault_service_incompatible_share',0.18),0.18),
                      v_immob_share);

  FOR v_rec IN
    SELECT id, current_state, current_stall_id, fleet_operator_id, config, last_state_change
      FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND current_state IN ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay',
                             'in_service_bay','charge_complete_holding','staged_awaiting_service')
       AND NOT jsonb_exists(config, 'exception')
  LOOP
    IF ottoq_sim_seeded_random(v_seed, 'roll:'||v_rec.id::text) < v_per_tick THEN
      v_sev := CASE WHEN ottoq_sim_seeded_random(v_seed,'sev:'||v_rec.id::text) < 0.35 THEN 'critical' ELSE 'major' END;
      v_roll := ottoq_sim_seeded_random(v_seed,'immob:'||v_rec.id::text);
      -- Only a critical fault can be immobilizing (unchanged predicate, unchanged draw).
      v_immob := (v_sev = 'critical') AND v_roll < v_immob_share;
      v_si    := (v_sev = 'critical') AND v_roll < v_si_share;
      v_fault_class := CASE
        WHEN v_sev <> 'critical'                THEN 'non_critical_' || v_sev
        WHEN v_roll < v_si_share * 0.55         THEN 'hv_battery_thermal'
        WHEN v_roll < v_si_share                THEN 'charge_system_fault'
        WHEN v_roll < v_si_share + (v_immob_share - v_si_share) * 0.6 THEN 'drive_actuator_failure'
        WHEN v_roll < v_immob_share             THEN 'steering_brake_fault'
        WHEN v_roll < 0.65                      THEN 'compute_stack_fault'
        ELSE 'sensor_suite_fault' END;

      v_mid := v_rec.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','charging_dcfc','charging_l2');

      -- Remaining work for the AUDIT STAMP. Booking window first, config second, else unknown.
      v_ends := NULL; v_starts := NULL; v_booking := NULL;
      SELECT b.booking_id, lower(b.during), upper(b.during), b.purpose INTO v_booking, v_starts, v_ends, v_purpose
        FROM ottoq_stall_bookings b
       WHERE b.vehicle_id = v_rec.id AND b.sim_run_id = p_sim_run_id
         AND b.state IN ('held','active') AND b.during @> p_sim_clock
       ORDER BY upper(b.during) DESC LIMIT 1;
      IF v_ends IS NULL THEN
        v_ends := NULLIF(v_rec.config->>'service_ends_at','')::timestamptz;
      END IF;
      v_remaining := CASE WHEN v_ends IS NULL THEN NULL
                          ELSE round(EXTRACT(epoch FROM (v_ends - p_sim_clock))::numeric / 60.0, 2) END;

      -- GATE THE YANK. Both bits are on the wire now, so the guard can tell "cannot drive"
      -- apart from "the service cannot continue here".
      IF v_mid THEN
        v_gate := ottoq_indepot_reassignment_guard(
                    v_rec.id, p_sim_run_id, 'vehicle_fault',
                    jsonb_build_object('severity', v_sev, 'from_state', v_rec.current_state::text,
                                       'immobilizing', v_immob,
                                       'service_incompatible', v_si,
                                       'fault_class', v_fault_class,
                                       'service_ends_at', v_ends, 'min_remaining', v_remaining,
                                       'source','vehicle_exception_handler'));
      ELSE
        v_gate := jsonb_build_object('allowed', true, 'mode', 'not_in_service');
      END IF;

      IF NOT COALESCE((v_gate->>'allowed')::boolean, true) THEN
        -- DEFERRED: the vehicle STAYS in its bay and finishes the atomic visit.
        UPDATE vehicles
           SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{exception}',
                 jsonb_build_object('type','vehicle_fault','severity',v_sev,'flagged_at',p_sim_clock,
                   'status','deferred_awaiting_tech','gate_mode', v_gate->>'mode',
                   'defer_class', v_gate->>'defer_class', 'immobilizing', v_immob,
                   'service_incompatible', COALESCE((v_gate->>'service_incompatible')::boolean, v_si),
                   'fault_class', v_fault_class,
                   'approval_id', v_gate->>'approval_id', 'service_ends_at', v_ends,
                   'deferred_from_state', v_rec.current_state::text,
                   'deferred_with_min_remaining', v_remaining))
         WHERE id = v_rec.id;
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='vehicle_exception_handler',
          p_event_type:='ottoq.bay_eviction_deferred',
          p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id,
          p_depot_id:=p_depot_id,
          p_payload:= jsonb_build_object('severity',v_sev,'from_state',v_rec.current_state::text,
            'gate_mode', v_gate->>'mode', 'defer_class', v_gate->>'defer_class',
            'immobilizing', v_immob, 'service_incompatible', COALESCE((v_gate->>'service_incompatible')::boolean, v_si),
            'fault_class', v_fault_class, 'approval_id', v_gate->>'approval_id',
            'min_remaining', v_remaining, 'disposition','work_protected_eviction_deferred'),
          p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
        v_n := v_n + 1;
        CONTINUE;
      END IF;

      -- ALLOWED: perform the yank, now fully audited.
      SELECT stall_code INTO v_stall_code FROM stalls WHERE id = v_rec.current_stall_id;

      -- ══════════ THE WORK MUST SURVIVE AS DUE, AND MUST BE RE-BOOKED ══════════
      v_reopened := 0;
      IF v_mid THEN
        v_reopened := public.ottoq_reopen_visit_atoms(
                        v_rec.id,
                        ottoq.ottoq_state_service_atoms(v_rec.current_state::text),
                        COALESCE(v_starts, v_rec.last_state_change),
                        'vehicle_fault_eviction');
        IF v_booking IS NOT NULL THEN
          UPDATE ottoq_stall_bookings b
             SET state='interrupted', released_at=p_sim_clock,
                 release_reason='vehicle_fault_eviction',
                 during = tstzrange(lower(b.during),
                            GREATEST(lower(b.during) + interval '1 second',
                                     LEAST(upper(b.during), p_sim_clock)), '[)')
           WHERE b.booking_id = v_booking AND b.state IN ('held','active');
          PERFORM ottoq.ottoq_emit_booking_interrupted(
            p_sim_run_id, p_depot_id, v_booking, v_rec.id, v_rec.current_stall_id,
            v_purpose, p_sim_clock, 'vehicle_fault_eviction',
            EXTRACT(epoch FROM (v_ends - v_starts))::numeric,
            EXTRACT(epoch FROM (p_sim_clock - v_starts))::numeric,
            v_reopened, 0, 'vehicle_exception_handler');
        END IF;
        PERFORM twin.ottoq_demand_rebook_after_eviction(
                  p_sim_run_id, p_depot_id, v_rec.id, v_rec.fleet_operator_id,
                  p_sim_clock, 'vehicle_fault_eviction', v_remaining, v_purpose,
                  v_rec.current_state::text);
      END IF;

      v_evict := jsonb_build_object('at', p_sim_clock, 'cause','vehicle_fault','severity',v_sev,
                   'stall_code', v_stall_code, 'stall_id', v_rec.current_stall_id,
                   'from_state', v_rec.current_state::text,
                   'interrupted_with_min_remaining', v_remaining,
                   'gate_mode', v_gate->>'mode', 'gate_approval_id', v_gate->>'approval_id',
                   'immobilizing', v_immob,
                   'service_incompatible', COALESCE((v_gate->>'service_incompatible')::boolean, v_si),
                   'evict_basis', v_gate->>'evict_basis', 'fault_class', v_fault_class,
                   'atoms_reopened', v_reopened,
                   'booking_closed', v_booking, 'was_mid_service', v_mid);

      IF v_rec.current_stall_id IS NOT NULL THEN
        UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_rec.current_stall_id;
      END IF;
      UPDATE vehicles
         SET current_state = 'tow_requested'::vehicle_state, current_stall_id = NULL, last_state_change = p_sim_clock,
             config = jsonb_set(
                        jsonb_set(COALESCE(config,'{}'::jsonb), '{exception}',
                          jsonb_build_object('type','vehicle_fault','severity',v_sev,'flagged_at',p_sim_clock,
                            'immobilizing', v_immob, 'service_incompatible', v_si, 'fault_class', v_fault_class,
                            'status', CASE WHEN v_sev='critical' THEN 'auto_staged' ELSE 'pending_approval' END)),
                        '{bay_eviction}', v_evict)
       WHERE id = v_rec.id;

      PERFORM ottoq_record_event(
        p_actor_type:='ottoq_engine', p_actor_id:='vehicle_exception_handler',
        p_event_type:= CASE WHEN v_sev='critical' THEN 'vehicle.exception_auto_staged' ELSE 'vehicle.exception_proposed' END,
        p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id, p_depot_id:=p_depot_id,
        p_payload:= jsonb_build_object('severity',v_sev,'from_state',v_rec.current_state::text,
          'disposition', CASE WHEN v_sev='critical' THEN 'auto_offline_override' ELSE 'staged_pending_technician_approval' END,
          'immobilizing', v_immob, 'service_incompatible', v_si, 'fault_class', v_fault_class,
          'gate_mode', v_gate->>'mode'),
        p_severity:= CASE WHEN v_sev='critical' THEN 'critical' ELSE 'warning' END,
        p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

      IF v_mid THEN
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='vehicle_exception_handler',
          p_event_type:='ottoq.bay_eviction',
          p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id,
          p_depot_id:=p_depot_id, p_payload:= v_evict,
          p_severity:= CASE WHEN v_sev='critical' THEN 'critical' ELSE 'warning' END,
          p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
      END IF;
      v_n := v_n + 1;
    END IF;
  END LOOP;

  -- DEFERRED RESUME -- THE ESCAPE HATCH. A deferred fault is never forgotten and never
  -- deadlocks: it is carried out as soon as the protected work is done, the vehicle has left
  -- the space on its own, a technician approved, or the bounded defer budget expires.
  FOR v_rec IN
    SELECT id, current_state, current_stall_id, fleet_operator_id, config, last_state_change
      FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND config->'exception'->>'status' = 'deferred_awaiting_tech'
  LOOP
    v_ends       := NULLIF(v_rec.config->'exception'->>'service_ends_at','')::timestamptz;
    v_mid        := v_rec.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','charging_dcfc','charging_l2');
    v_sev        := COALESCE(v_rec.config->'exception'->>'severity','major');
    v_defer_class:= COALESCE(v_rec.config->'exception'->>'defer_class','');
    v_immob      := COALESCE((v_rec.config->'exception'->>'immobilizing')::boolean, false);
    v_fault_class:= v_rec.config->'exception'->>'fault_class';
    -- THREE BUDGETS, ALL BOUNDED. Immobilizing-but-charge-safe gets the longest one because the
    -- vehicle cannot leave without a tow anyway; it still expires, so nothing deadlocks.
    v_budget     := CASE WHEN v_defer_class = 'immobilizing_awaiting_tow' THEN v_defer_max_immob
                         WHEN v_sev='critical' THEN v_defer_max_crit
                         ELSE v_defer_max END;
    v_resume_reason := NULL;
    IF NOT v_mid THEN
      v_resume_reason := 'left_service_state';
    ELSIF v_ends IS NOT NULL AND v_ends <= p_sim_clock THEN
      v_resume_reason := 'service_window_complete';
    ELSIF EXISTS (SELECT 1 FROM ottoq_ops_approvals a
                   WHERE a.approval_id = NULLIF(v_rec.config->'exception'->>'approval_id','')::uuid
                     AND a.status = 'approved') THEN
      v_resume_reason := 'technician_approved';
    ELSIF (v_rec.config->'exception'->>'flagged_at')::timestamptz
            <= p_sim_clock - (v_budget || ' minutes')::interval THEN
      v_resume_reason := CASE WHEN v_defer_class = 'immobilizing_awaiting_tow' THEN 'immobilizing_defer_budget_expired'
                              WHEN v_sev='critical' THEN 'critical_defer_budget_expired'
                              ELSE 'defer_budget_expired' END;
    END IF;

    IF v_resume_reason IS NULL THEN CONTINUE; END IF;

    SELECT stall_code INTO v_stall_code FROM stalls WHERE id = v_rec.current_stall_id;

    -- Work survives here too: if the vehicle is STILL mid-service when the deferral is
    -- carried out, the eviction IS cutting live work and must re-plan AND re-book it.
    v_reopened := 0; v_booking := NULL; v_starts := NULL; v_bk_hi := NULL; v_purpose := NULL;
    v_remaining := 0;
    IF v_mid THEN
      SELECT b.booking_id, lower(b.during), upper(b.during), b.purpose INTO v_booking, v_starts, v_bk_hi, v_purpose
        FROM ottoq_stall_bookings b
       WHERE b.vehicle_id = v_rec.id AND b.sim_run_id = p_sim_run_id
         AND b.state IN ('held','active') AND b.during @> p_sim_clock
       ORDER BY upper(b.during) DESC LIMIT 1;
      -- ══════════ P2 MEASUREMENT FIX: STOP STAMPING ZERO ══════════
      -- This path hardcoded `interrupted_with_min_remaining = 0`, which is why
      -- `deferred_awaiting_tech` appeared to destroy 0.00 minutes. MEASURED (phase 11,
      -- reconstructed from each deferral's own min_remaining minus elapsed defer time):
      -- 24 of the 45 deferred resumes closed a LIVE booking and really destroyed ~1,359.78
      -- minutes -- 2.1x the immobilizing path's 641.30, invisible because of this constant.
      -- The window upper bound is read BEFORE the clipping UPDATE below, so this is the true
      -- remaining work at the moment the space was taken away.
      v_remaining := GREATEST(
        COALESCE(round(EXTRACT(epoch FROM (COALESCE(v_bk_hi, v_ends) - p_sim_clock))::numeric / 60.0, 2), 0), 0);
      v_reopened := public.ottoq_reopen_visit_atoms(
                      v_rec.id,
                      ottoq.ottoq_state_service_atoms(v_rec.current_state::text),
                      COALESCE(v_starts, v_rec.last_state_change),
                      'vehicle_fault_eviction_deferred_resumed');
      IF v_booking IS NOT NULL THEN
        UPDATE ottoq_stall_bookings b
           SET state='interrupted', released_at=p_sim_clock,
               release_reason='vehicle_fault_eviction_deferred_resumed',
               during = tstzrange(lower(b.during),
                          GREATEST(lower(b.during) + interval '1 second',
                                   LEAST(upper(b.during), p_sim_clock)), '[)')
         WHERE b.booking_id = v_booking AND b.state IN ('held','active');
        PERFORM ottoq.ottoq_emit_booking_interrupted(
          p_sim_run_id, p_depot_id, v_booking, v_rec.id, v_rec.current_stall_id,
          v_purpose, p_sim_clock, 'vehicle_fault_eviction_deferred_resumed',
          EXTRACT(epoch FROM (v_bk_hi - v_starts))::numeric,
          EXTRACT(epoch FROM (p_sim_clock - v_starts))::numeric,
          v_reopened, 0, 'vehicle_exception_handler_deferred_resume');
      END IF;
      PERFORM twin.ottoq_demand_rebook_after_eviction(
                p_sim_run_id, p_depot_id, v_rec.id, v_rec.fleet_operator_id,
                p_sim_clock, 'vehicle_fault_eviction_deferred_resumed', v_remaining, v_purpose,
                v_rec.current_state::text);
    END IF;

    v_evict := jsonb_build_object('at', p_sim_clock, 'cause','vehicle_fault_deferred_resumed',
                 'severity', v_sev, 'stall_code', v_stall_code, 'stall_id', v_rec.current_stall_id,
                 'from_state', v_rec.current_state::text, 'resume_reason', v_resume_reason,
                 'gate_mode','deferred_awaiting_tech',
                 'defer_class', v_defer_class, 'immobilizing', v_immob, 'fault_class', v_fault_class,
                 'defer_budget_min', v_budget,
                 'deferred_at', v_rec.config->'exception'->>'flagged_at',
                 'atoms_reopened', v_reopened, 'booking_closed', v_booking,
                 'interrupted_with_min_remaining', v_remaining, 'was_mid_service', v_mid);

    IF v_rec.current_stall_id IS NOT NULL THEN
      UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_rec.current_stall_id;
    END IF;
    UPDATE vehicles
       SET current_state = 'tow_requested'::vehicle_state, current_stall_id = NULL,
           last_state_change = p_sim_clock,
           config = jsonb_set(
                      jsonb_set(config, '{exception,status}',
                        to_jsonb(CASE WHEN v_sev='critical' THEN 'auto_staged' ELSE 'pending_approval' END)),
                      '{bay_eviction}', v_evict)
     WHERE id = v_rec.id;

    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='vehicle_exception_handler',
      p_event_type:='ottoq.bay_eviction',
      p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id,
      p_depot_id:=p_depot_id, p_payload:= v_evict,
      p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  FOR v_rec IN
    SELECT id, fleet_operator_id FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND config->'exception'->>'status' = 'pending_approval'
       AND (config->'exception'->>'flagged_at')::timestamptz <= p_sim_clock - (v_approve_delay_min || ' minutes')::interval
  LOOP
    UPDATE vehicles SET config = jsonb_set(config, '{exception,status}', to_jsonb('technician_approved'::text))
     WHERE id = v_rec.id;
    PERFORM ottoq_record_event(
      p_actor_type:='command_center_operator', p_actor_id:='technician_in_loop', p_event_type:='vehicle.technician_approved',
      p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id, p_depot_id:=p_depot_id,
      p_payload:= jsonb_build_object('action','approved_offline_inspection'),
      p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  -- (3) TOW RETRIEVAL -- never closed, never gated. A genuinely broken vehicle always leaves.
  FOR v_rec IN
    SELECT id, fleet_operator_id FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND current_state = 'tow_requested'
       AND COALESCE(config->'exception'->>'status','auto_staged') IN ('auto_staged','technician_approved')
       AND last_state_change <= p_sim_clock - (COALESCE(ottoq_policy_get(p_sim_run_id,'tow_retrieval_min',25),25) || ' minutes')::interval
  LOOP
    v_plan := ottoq_stage_after_tow_retrieval(v_rec.id, p_sim_run_id, p_depot_id, p_sim_clock);
    v_stall := NULLIF(v_plan->>'stall_id','')::uuid;
    IF v_stall IS NOT NULL THEN
      UPDATE vehicles
         SET current_state = 'emergency_staged'::vehicle_state, current_stall_id = v_stall,
             last_state_change = p_sim_clock,
             config = jsonb_set(COALESCE(config,'{}'::jsonb), '{exception,status}', to_jsonb('retrieved_staged'::text))
       WHERE id = v_rec.id;
      UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied' WHERE id = v_stall;
      PERFORM ottoq_record_event(
        p_actor_type:='ottoq_engine', p_actor_id:='incident_triage',
        p_event_type:='vehicle.tow_retrieved_staged',
        p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id,
        p_depot_id:=p_depot_id,
        p_payload:=jsonb_build_object('reserved_stall_id', v_stall),
        p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
      v_n := v_n + 1;
    END IF;
  END LOOP;

  -- (4) SWEEPER
  UPDATE stalls s SET current_vehicle_id = NULL, status = 'available'
   WHERE s.depot_id = p_depot_id AND s.stall_type = 'staging' AND s.current_vehicle_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.id = s.current_vehicle_id AND v.current_stall_id = s.id);

  -- (5) RE-ADMIT TO THE INTERRUPTED VISIT  --  PHASE 11.
  v_n := v_n + COALESCE(ottoq.ottoq_readmit_resumed_visits(p_sim_run_id, p_depot_id, p_sim_clock), 0);

  RETURN v_n;
END;
$function$

-- ===== ottoq_sim_wash_triage =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_wash_triage(p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_released int := 0; v_rec RECORD; v_manifest jsonb;
  v_wash_cap int; v_in_wash int;
  v_verdict jsonb; v_deferred jsonb;
BEGIN
  UPDATE vehicles SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{cycles_since_wash}', to_jsonb(0))
   WHERE home_depot_id = p_depot_id AND category = 'autonomous'
     AND current_state IN ('in_wash_bay','in_detail_bay');

  v_wash_cap := ottoq_sim_lane_capacity(NULL, 'cleaning_staff', 3);
  SELECT count(*) INTO v_in_wash FROM vehicles
   WHERE home_depot_id = p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay');

  FOR v_rec IN
    SELECT id, config FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND current_state = 'charge_complete_holding'
  LOOP
    v_manifest := v_rec.config->'service_manifest';
    IF v_manifest IS NULL OR jsonb_typeof(v_manifest) <> 'array' THEN
      IF (SELECT COALESCE(feed_mode,'sim') FROM depots WHERE id = p_depot_id) = 'sim' THEN
        v_manifest := ottoq_sim_generate_service_manifest(v_rec.id, NULL, NULL);
      END IF;
    END IF;
    IF v_manifest IS NULL THEN CONTINUE; END IF;

    -- DECISION HANDOFF: OTTO-Q returns the routing verdict; twin enacts it
    v_verdict := ottoq_decide_wash_triage(v_rec.id, p_depot_id, v_manifest,
                                          v_wash_cap, v_in_wash, p_sim_clock);

    v_in_wash  := COALESCE((v_verdict->>'in_wash_after')::int, v_in_wash);
    v_released := v_released + COALESCE((v_verdict->>'released_delta')::int, 0);

    v_deferred := v_verdict->'deferred_services';
    IF v_deferred IS NOT NULL AND jsonb_typeof(v_deferred) = 'array'
       AND jsonb_array_length(v_deferred) > 0 THEN
      UPDATE vehicles SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{deferred_services}', v_deferred)
       WHERE id = v_rec.id;
    END IF;

    IF v_verdict->>'next_state' IS NOT NULL AND v_verdict->>'svc_step' IS NOT NULL THEN
      UPDATE vehicles
         SET current_state = (v_verdict->>'next_state')::vehicle_state,
             last_state_change = p_sim_clock,
             config = jsonb_set(COALESCE(config,'{}'::jsonb), '{svc_step}', to_jsonb(v_verdict->>'svc_step'))
       WHERE id = v_rec.id;
    END IF;
  END LOOP;
  RETURN v_released;
END; $function$

-- ===== ottoq_world_advance =====
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
  BEGIN PERFORM ottoq_sim_confirm_commands(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance confirm_commands: %', SQLERRM; END;
  END IF;

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
  BEGIN PERFORM ottoq_sim_reconcile_charge_sessions(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance reconcile_charge: %', SQLERRM; END;
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
       AND vv.current_soc >= COALESCE(vv.target_soc, 85);
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
$function$
