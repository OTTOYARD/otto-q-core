-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: e91eb3a811f96809202bc7b77a72ff41
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

    -- ═══════ DRAIN IS DERIVED FROM CUMULATIVE ENERGY, NOT DECREMENTED ═══════
    -- SAME DEFECT AS THE CHARGE SIDE, AND MORE DAMAGING. This read
    -- `v_dispatch.v_soc - ...`, i.e. it decremented the value STORED on the vehicle,
    -- and public.vehicles.current_soc is an INTEGER. At the live tick rate a deployed
    -- car burns well under half a SoC point per tick, so ROUND() wrote the same whole
    -- number back every time and the vehicle never lost any charge at all.
    -- MEASURED on run 128c12f6: over 94 sim-seconds, five deployed vehicles had
    -- current_soc_updated_at advancing every tick -- the code was running and writing --
    -- while current_soc sat unchanged at 97/95/90/89/97.
    -- CONSEQUENCE: robotaxis that never discharge never need to come back, so the depot
    -- receives no organic return demand. That silently contradicts the whole point of
    -- unscripted arrivals.
    -- FIX: derive from the dispatch's own cumulative energy against soc_at_dispatch_pct
    -- (both already exist and are numeric). Monotonic, so it crosses each whole point no
    -- matter how thin the per-tick slice is. Falls back to the old expression when the
    -- dispatch has no recorded starting SoC, so nothing regresses.
    IF v_dispatch.soc_at_dispatch_pct IS NOT NULL
       AND COALESCE(v_dispatch.battery_capacity_kwh, 0) > 0 THEN
      v_new_soc := GREATEST(0,
        v_dispatch.soc_at_dispatch_pct
          - ((COALESCE(v_dispatch.energy_consumed_kwh, 0) + v_kwh_consumed)
             / v_dispatch.battery_capacity_kwh) * 100.0);
    ELSE
      v_new_soc := GREATEST(0,
        v_dispatch.v_soc - (v_kwh_consumed / v_dispatch.battery_capacity_kwh) * 100.0);
    END IF;

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
          -- 0009 (DEFECT 2a). This is the FIRST of the two writers that move
          -- scheduled_return_at away from the dispatch-time plan, and until now it moved it
          -- SILENTLY -- from the row alone you could not tell the column had stopped being
          -- the plan. The move itself is legitimate (a real modelled delay) and is left
          -- byte-for-byte; what is added is the RECORD of it. The plan itself is now safe in
          -- its own generated column, planned_return_at, which nothing may overwrite.
          -- CLOCK DOMAIN: p_sim_clock_now is the SIM clock. So is scheduled_return_at.
          UPDATE ottoq_vehicle_dispatches
             SET scheduled_return_at = scheduled_return_at + ((v_eta_card->>'delay_min') || ' minutes')::interval,
                 eta_refreshed_at    = p_sim_clock_now,
                 eta_source          = 'twin_eta_delay_card:' || COALESCE(v_eta_card->>'cause','unknown')
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

    -- Persist the running total the SoC above is derived from. energy_consumed_kwh is an
    -- existing numeric column that NOTHING else assigns (verified across this function
    -- and the whole schema), so this introduces no double counting.
    UPDATE ottoq_vehicle_dispatches
       SET energy_consumed_kwh = COALESCE(energy_consumed_kwh, 0) + v_kwh_consumed
     WHERE dispatch_id = v_dispatch.dispatch_id;

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
               -- 0009 (DEFECT 2a). The SECOND writer, and the destructive one: it does not
               -- adjust the plan, it REPLACES it. Measured 2026-08-05 on live data: 116 of 116
               -- dispatch rows that reached this branch ended with
               -- scheduled_return_at = returning_started_at + EXACTLY 30 min, one distinct
               -- ETA value across the whole table. Grading that against the arrival it itself
               -- caused is circular; there was no training signal. The write is left standing
               -- (twelve other live functions READ this column as "current best arrival
               -- estimate"), but the plan is now preserved independently in planned_return_at,
               -- and the refresh is stamped, so plan / live-ETA / actual are three separate
               -- observable facts. CLOCK DOMAIN: every timestamp written here is the SIM
               -- clock. created_at is the ONLY wall-clock column on this table.
               eta_refreshed_at     = p_sim_clock_now,
               eta_source           = 'policy_constant:return_eta_minutes',
               return_evidence = COALESCE(v_ret_ev, '{}'::jsonb) || jsonb_build_object(
                 'decided_at', p_sim_clock_now,
                 'soc_at_decision', v_new_soc,
                 'reserve', v_min_soc_thresh,
                 'eta_minutes_is_a_parameter', true,
                 -- 0009: the divergence, computed at the exact moment of the refresh, so a
                 -- later reader never has to reconstruct what the plan had been.
                 'eta_source', 'policy_constant:return_eta_minutes',
                 'planned_return_at', planned_return_at,
                 'live_return_at', p_sim_clock_now + (v_eta_min || ' minutes')::interval,
                 'plan_minus_live_min', ROUND((EXTRACT(EPOCH FROM (planned_return_at
                     - (p_sim_clock_now + (v_eta_min || ' minutes')::interval))) / 60.0)::numeric, 1),
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

