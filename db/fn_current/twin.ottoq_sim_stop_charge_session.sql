-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: d1c3c6e01319dc74c2c0317e465d96fe
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
  -- 0011-TETHER: DCFC stalls are robot-served. StopTransaction is NOT the unplug.
  v_is_dcfc boolean := false; v_tether boolean := false;
  v_demate_s numeric := 11.5;   -- robot disconnect time, one named knob (see below)
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
    -- 0011-TETHER: a tethered car IS the "vehicle that does not point back" -- the robot
    -- is still holding it and vehicles.current_stall_id is already NULL. Without this
    -- guard the strand-cleaner below would hand the plug away mid-demate. The tether
    -- RECORD (not a clock) is the test: ottoq_release_expired_tethers is the single
    -- releaser and it clears the record and the stall together, so deferring to it
    -- cannot strand the stall.
    UPDATE stalls s SET current_vehicle_id = NULL
     WHERE s.id = v_session.stall_id
       AND s.current_vehicle_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM vehicles v
                        WHERE v.id = s.current_vehicle_id AND v.current_stall_id = s.id)
       AND NOT EXISTS (SELECT 1 FROM vehicles tv
                        WHERE tv.id = s.current_vehicle_id
                          AND tv.robotic_tether_stall_id = s.id
                          AND tv.robotic_tether_until IS NOT NULL);
    RETURN;
  END IF;

  v_duration_s := EXTRACT(EPOCH FROM (v_clock - v_session.started_at));
  v_avg_power := CASE WHEN v_duration_s > 0 THEN
    (v_session.energy_delivered_kwh * 3600.0 / v_duration_s) ELSE 0 END;
  SELECT id, fleet_operator_id, current_soc, display_name, COALESCE(target_soc, public.ottoq_default_target_soc()) AS target_soc
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

  -- S3a AUTO RE-ROUTE: fault interrupted the charge with the vehicle still under target →
  -- re-queue so OTTO-Q reassigns a healthy charger; otherwise proceed to disposition.
  -- 0011-TETHER moved this ABOVE the stall release, because the release now depends on it.
  -- Nothing about the expression itself changed.
  v_requeue := (p_reason LIKE 'fault%' AND v_vehicle.current_soc < v_vehicle.target_soc - 5);

  -- ═══════════════════ 0011-TETHER: STOPTRANSACTION IS NOT THE UNPLUG ═══════════════════
  -- DCFC stalls are served by the OTTO-CHARGE ARM. When the session closes the car is
  -- still physically on the end of a cable and the robot needs 11.5 s to demate
  -- (unlatch 2.0 + extract 3.0 + retract 6.5, from armStateMachine.ts in
  -- ottoyarddepot-sim -- keep the two in step). So the plug is NOT handed to the next
  -- vehicle here; ottoq_release_expired_tethers frees it once the window passes.
  --
  -- WHY THE REQUEUE PATH IS EXCLUDED: on a fault-with-low-SoC the block below physically
  -- relocates the car to a booked temp stall. Holding the DCFC stall as well would leave
  -- one vehicle occupying two stalls, which is exactly what the overlap guard exists to
  -- prevent. That path therefore keeps releasing the stall, unchanged from today.
  SELECT (s.stall_type = 'dcfc'::stall_type) INTO v_is_dcfc
    FROM stalls s WHERE s.id = v_session.stall_id;
  -- ...AND ONLY IF THE ARM ACTUALLY LATCHED. A session that opened no mate --
  -- because the car was already at target -- has nothing to disconnect from, and
  -- a demate cycle here would be the arm withdrawing a plug it never inserted.
  -- v_tether governs the stall release, the tether write AND the demate cycle
  -- below, so this one conjunct covers all three: a car that was never connected
  -- is released to move immediately, which is exactly right.
  v_tether := COALESCE(v_is_dcfc, false) AND NOT v_requeue
              AND EXISTS (SELECT 1 FROM twin.arm_cycles c
                           WHERE c.session_id = v_session.id
                             AND c.direction = 'mate'
                             AND c.outcome = 'latched');

  -- ONE KNOB, NOT TWO LITERALS. The disconnect time was hardcoded here as
  -- interval '11.5 seconds', duplicating the value in armStateMachine.ts
  -- (unlatch 2.0 + extract 3.0 + retract 6.5) in the ottoyarddepot-sim repo with nothing
  -- linking them -- retune the arm and the orchestration silently disagrees about how
  -- long the car is mated. It is now the named policy 'robotic_demate_seconds',
  -- overridable per run or per depot, with 11.5 as the default so behaviour is
  -- unchanged until someone deliberately changes it. The renderer remains the physical
  -- source of truth; this is the value OTTO-Q reserves the plug for.
  v_demate_s := GREATEST(0, COALESCE(
    (public.ottoq_arm_timings(p_sim_run_id)->>'demate_seconds')::numeric, 11.5));

  IF NOT v_tether THEN
    UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_session.stall_id;
  END IF;

  -- The fault-requeue path physically relocates this car to a temp stall. Any
  -- charge lease it is holding points at the DCFC stall it is leaving, and a
  -- stale lease would both freeze the car and misreport which stall the robot
  -- has. Drop it, and close whatever cycle was open on that plinth.
  IF v_requeue THEN
    -- ═══════ THROUGH THE FRONT DOOR, NOT AROUND IT ═══════
    -- This is the founder's malfunction case exactly: the charger has died under
    -- a car that still needs charge, so the arm must let go and the car must be
    -- relocated to a temporary stall. It used to clear the tether inline and mark
    -- the cycle 'abandoned' -- which says the world stopped underneath it rather
    -- than that the charger failed and the arm was ordered to release. That
    -- charged the arm's reliability record with somebody else's fault, emitted no
    -- safety event, and never set the disposition flag a supervisor needs.
    --
    -- Must stay AHEAD of the relocation below: since the arm interlock trigger
    -- exists, moving the car with a live tether would be refused outright.
    PERFORM twin.ottoq_arm_emergency_release(
      v_session.vehicle_id,
      'charger fault: ' || COALESCE(NULLIF(p_fault_message, ''), p_reason, 'unspecified'),
      'twin_charger_fault', p_sim_run_id, v_clock);

    -- Belt, for a cycle left open on this plinth with no tether behind it. Scoped
    -- to THIS vehicle: the old predicate was stall-only and would have abandoned
    -- another car's cycle on the same plinth.
    UPDATE twin.arm_cycles SET ended_at = v_clock, outcome = COALESCE(outcome, 'abandoned')
     WHERE stall_id = v_session.stall_id AND vehicle_id = v_session.vehicle_id
       AND ended_at IS NULL;
  END IF;
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
    -- 0011-TETHER: the tether is written in the SAME statement that nulls current_stall_id.
    -- That ordering is load-bearing: trg_sync_stall_occupancy is an AFTER UPDATE trigger on
    -- vehicles that frees the old stall whenever current_stall_id changes, and it reads NEW.
    -- Setting the tether in a later statement would let the trigger release the plug first.
    UPDATE vehicles SET current_state = 'charge_complete_holding'::vehicle_state,
                        -- KEEP THE STALL WHILE THE ARM UNLATCHES. Nulling this here is what
                        -- deadlocked the world tick against ottoq_arm_interlock_guard. The car
                        -- is physically still in the stall until the demate tether expires, and
                        -- ottoq_release_expired_tethers clears both the stall and this pointer
                        -- when it does. Because this no longer CHANGES current_stall_id on the
                        -- tethered path, trg_sync_stall_occupancy does not fire, so the original
                        -- 0011-TETHER hazard (the plug being freed before the tether is written)
                        -- cannot occur either.
                        current_stall_id = CASE WHEN v_tether
                          THEN v_session.stall_id ELSE NULL END, last_state_change = v_clock,
                        robotic_tether_until = CASE WHEN v_tether
                          THEN v_clock + make_interval(secs => v_demate_s) ELSE robotic_tether_until END,
                        robotic_tether_stall_id = CASE WHEN v_tether
                          THEN v_session.stall_id ELSE robotic_tether_stall_id END,
                        robotic_tether_direction = CASE WHEN v_tether
                          THEN 'demate' ELSE robotic_tether_direction END,
                        robotic_tether_phase = CASE WHEN v_tether
                          THEN 'unlatch' ELSE robotic_tether_phase END
     WHERE id = v_session.vehicle_id;
  END IF;

  -- ═══════════ THE ARM LETS GO ═══════════
  -- The demate window already existed as a deadline; this gives it a lifecycle
  -- with the same shape as the inbound one, so the cockpit and OTTO-Q read the
  -- arm the same way in both directions. Never allowed to abort the close.
  IF v_tether THEN
    BEGIN
      PERFORM twin.ottoq_arm_begin_cycle(p_sim_run_id, v_session.vehicle_id,
                                         v_session.stall_id, p_session_id, 'demate', v_clock);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm demate begin: %', SQLERRM;
    END;
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

