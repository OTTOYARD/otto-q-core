-- migration-version: 20260819235000
-- migration-name:    twin_deterministic_cursor_order
-- 0050 — C7 FOLLOW-UP #4, found by re-certification #4 (arms a4ce46d4 / 523f770e):
-- 11 of 20 ticks identical, every vehicle SoC paired at the first divergence
-- (sim-min 360) — the remaining diff was a pure STALL-ASSIGNMENT PERMUTATION:
-- the same stalls paired to a vehicle queue shifted by one position.
--
-- ROOT CAUSE: eleven per-tick processing loops across five twin functions
-- iterate `FOR r IN SELECT ...` with NO ORDER BY. Postgres then returns rows
-- in physical heap order, which drifts between runs as updates relocate
-- tuples — so the order in which vehicles claim shared resources (stalls,
-- chargers, capacity slots) is not a function of the seed. All per-entity
-- randomness was already order-independent (seeded + entity-salted); only
-- the RESOURCE-CLAIM order leaked.
--
-- FIX: every such cursor gets a run-stable ORDER BY on fleet/stall identity
-- (vehicle.id / stall.id — fixed across runs), NEVER on per-run-random keys
-- (dispatch/session UUIDs) and never on real-clock columns. Processing order
-- becomes a pure function of world state. Bodies otherwise byte-identical to
-- their current production versions (0045/0047/0048).

-- ── twin.ottoq_sim_advance_deployed_telemetry — 1 cursor ordered ──
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
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42') || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), 42));

  FOR v_dispatch IN
    SELECT d.*, v.battery_capacity_kwh, v.current_soc AS v_soc,
           v.min_soc_threshold, v.current_state AS v_state,
           v.display_name, v.fleet_operator_id AS v_fleet_op,
           (v.config->>'consumption_scalar')::numeric AS v_cons_scalar
      FROM ottoq_vehicle_dispatches d
      JOIN vehicles v ON v.id = d.vehicle_id
     WHERE d.status IN ('active','returning')
       AND (p_sim_run_id IS NULL OR d.sim_run_id = p_sim_run_id)
     ORDER BY d.vehicle_id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
  LOOP
    v_salt := v_dispatch.vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now);
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
;

-- ── twin.ottoq_sim_advance_charge_sessions — 1 cursor ordered ──
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
     ORDER BY s.vehicle_id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
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

-- ── twin.ottoq_sim_advance_service_flow — 3 cursors ordered ──
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
  -- 0009 (DEFECT 1) HONEST COMPLETION CREDIT. Four working sets and three counters.
  -- v_bay_caps    = what this bay is PHYSICALLY ABLE to do (unchanged from the pre-image).
  -- v_outstanding = what THIS VEHICLE actually still had open on THIS visit, read before
  --                 the atoms are marked done.
  -- v_flag_svcs   = the technician flag that admitted it, where the flag names the work.
  -- v_credit      = v_bay_caps INTERSECT (v_outstanding UNION v_flag_svcs)  <-- the fix.
  v_bay_caps    TEXT[];  v_outstanding TEXT[];  v_flag_svcs TEXT[];  v_credit TEXT[];
  v_credited    INT := 0;  v_suppressed  INT := 0;  v_credit_none INT := 0;
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
     ORDER BY v.id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
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
      -- ASK THE ARM FIRST. 'charge_complete_holding' is one of this loop's
      -- candidate states and it is also the demate window, so a car can be
      -- re-placed here with the arm still attached to it.
      IF v_s IS NOT NULL
         AND twin.ottoq_arm_refuse_move(v_rec.id, 'service_flow.stranded_recharge',
                                        v_s, p_sim_run_id, p_sim_clock_now) THEN
        v_s := NULL;
      END IF;
      IF v_s IS NOT NULL THEN
        -- ONE STALL PER VEHICLE, RELEASE BEFORE CLAIM. See the migration header.
        UPDATE stalls SET current_vehicle_id = NULL,
               status = CASE WHEN status = 'occupied' THEN 'available' ELSE status END
         WHERE current_vehicle_id = v_rec.id AND id <> v_s;
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
     ORDER BY id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
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

    -- ═══════ 0009 FIX (DEFECT 1) — CREDIT ONLY THE WORK THIS VEHICLE ACTUALLY HAD ═══════
    -- WAS: every bay exit credited a FIXED array regardless of why the car was in the bay,
    -- so a vehicle in for ONE job was recorded as having had up to FOUR. The exact pre-image
    -- line is quoted in this file's header, not here, so §POST can grep the live body for it.
    -- Registered as GAP 5 by 0005 and left open; this is that pass.
    --
    -- STEP A — the bay's CAPABILITY set. Byte-for-byte the three arrays from the pre-image.
    -- 0009 does not retune what a bay can do; it only stops claiming the bay did all of it.
    v_bay_caps := CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
                       WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
                       ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END;

    -- STEP B — what the vehicle ACTUALLY had outstanding, from its own visit record.
    -- ORDER IS LOAD-BEARING: this must be read BEFORE ottoq_mark_visit_atoms_done below,
    -- which flips these same atoms to 'done'. Read it after and the answer is always empty.
    -- The visit selector is IDENTICAL to ottoq_mark_visit_atoms_done's own (vehicle +
    -- status open/in_progress + newest created_at), so the wear ledger and the visit ledger
    -- can never disagree about WHICH visit they are discussing. "Outstanding" uses the
    -- depot's own existing definition, already live in STEP 2 of this same function:
    --     COALESCE(status,'pending') NOT IN ('done','cancelled','skipped')
    -- No new vocabulary is invented anywhere in this block.
    SELECT COALESCE(array_agg(DISTINCT a->>'svc'), ARRAY[]::text[])
      INTO v_outstanding
      FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = (SELECT n2.visit_id FROM ottoq_visit_needs n2
                          WHERE n2.vehicle_id = v_rec.id
                            AND n2.status IN ('open','in_progress')
                          ORDER BY n2.created_at DESC LIMIT 1)
       AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped');
    v_outstanding := COALESCE(v_outstanding, ARRAY[]::text[]);

    -- STEP C — THE TECHNICIAN FLAG IS REAL WORK TOO, AND IGNORING IT WOULD BE A NEW LIE.
    -- STEP 2 of this function admits a vehicle to the wash/detail lane on
    -- `flagged_issue_type` ALONE, with no atom required. Atoms-only credit would leave that
    -- car's body soil never reset -- and post-0008 ONLY an exterior_wash may reset it -- so
    -- the depot would wash it, still grade it dirty, and wash it again, forever. ONE mapping,
    -- and only where the flag NAMES the work: 'wash_due' -> exterior_wash.
    -- 'minor_cosmetic' is deliberately NOT mapped (GAP 1): a detail does not repair cosmetic
    -- damage, and inventing that equivalence would be the same disease this file removes.
    v_flag_svcs := CASE WHEN v_rec.config->>'flagged_issue_type' = 'wash_due'
                        THEN ARRAY['exterior_wash'] ELSE ARRAY[]::text[] END;

    -- STEP D — THE CREDIT SET: what this bay CAN do  ∩  what this vehicle ACTUALLY had.
    -- If a vehicle genuinely had all four due it still gets all four: the bug being fixed is
    -- unconditionality, not breadth.
    v_credit := ARRAY(SELECT t.svc FROM unnest(v_bay_caps) AS t(svc)
                       WHERE t.svc = ANY(v_outstanding || v_flag_svcs));

    PERFORM ottoq_mark_visit_atoms_done(v_rec.id,
      CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
           WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
           ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END, v_end_ts);
    -- wear truth follows completion (mark_serviced was dead: soil/PM/calibration never reset)
    -- 0009: the fixed array is gone. One call per service the vehicle REALLY had -- the same
    -- one-real-atom-per-call shape 0005 §3 uses on the non-bay path, and the same shape the
    -- real-telemetry seam public.ottoq_ingest_service_complete uses (FOREACH over the codes
    -- the OEM actually reported). An empty credit set yields zero rows from unnest, so the
    -- PERFORM makes NO call at all: total, never an error, never able to abort decide_tick.
    -- ottoq_mark_visit_atoms_done above is left BYTE-FOR-BYTE UNCHANGED on purpose. It is
    -- already correctly intersected -- it only touches atoms that exist on the visit -- so it
    -- was never part of this defect, and narrowing it would be scope creep.
    PERFORM ottoq_wear_mark_serviced(v_rec.id, p_sim_run_id, s, v_end_ts)
      FROM unnest(v_credit) AS s;
    v_credited    := v_credited + COALESCE(array_length(v_credit, 1), 0);
    v_suppressed  := v_suppressed + COALESCE(array_length(v_bay_caps, 1), 0)
                                  - COALESCE(array_length(v_credit, 1), 0);
    IF COALESCE(array_length(v_credit, 1), 0) = 0 THEN v_credit_none := v_credit_none + 1; END IF;
    PERFORM ottoq_record_event(p_actor_type := 'av_vehicle', p_actor_id := v_rec.id::text, p_event_type := 'twin.service_completed',
      p_entity_type := 'vehicle', p_entity_id := v_rec.id, p_payload := jsonb_build_object('from', v_rec.current_state, 'self_healed', (v_rec.config->>'service_ends_at') IS NULL,
        -- 0009 RUNTIME PROOF, carried on an event that was already being written, so the
        -- write-rate budget (~852-960 B/event) is not disturbed by a new event type.
        'bay_capable', to_jsonb(v_bay_caps), 'credited', to_jsonb(v_credit),
        'suppressed_n', COALESCE(array_length(v_bay_caps,1),0) - COALESCE(array_length(v_credit,1),0)),
      p_severity := 'debug', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END LOOP;

  -- 0009: ONE summary event per CALL, and only when a bay exit credited NOTHING -- i.e. a
  -- vehicle sat in a bay yet no outstanding work and no naming flag could be found for it.
  -- That is a gap a human should see, not something to paper over with a false credit.
  -- Silent in the normal case, so the event budget is unchanged on the happy path.
  IF v_credit_none > 0 THEN
    PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow',
      p_event_type := 'twin.bay_credit_none', p_entity_type := 'depot', p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('exits_crediting_nothing', v_credit_none,
        'services_credited', v_credited, 'services_suppressed', v_suppressed,
        'note', 'a bay exit found no outstanding work and no naming flag; nothing was credited, which is the honest answer -- investigate why the car was admitted'),
      p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END IF;

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
     ORDER BY v.id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
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
    -- 0048 REORDER: PHYSICAL TRUTH BEFORE THE STATE FLIP. This vehicle-state
    -- UPDATE used to run BEFORE the stall handoff below. That made
    -- trg_reassignment_guard (BEFORE UPDATE ON stalls) see the vehicle already
    -- in a protected in-bay state while it was still standing on its OLD stall,
    -- so the guard vetoed the release, silently restored the old pointer, and
    -- the very next place-statement violated idx_stalls_one_vehicle_per_stall
    -- and killed the whole tick (measured: cert arm 44252690, vehicle a6e9c009,
    -- charge_complete_holding on a wash bay, admitted to its booked service
    -- bay). Handoff first -- while the state is still a holding state the guard
    -- does not protect -- then the state write. Both statements byte-identical
    -- to the pre-image; only their order changed.

    IF v_rec.booked_stall IS NOT NULL
       AND NOT twin.ottoq_arm_refuse_move(v_rec.id, 'service_flow.bay_admit',
                                          v_rec.booked_stall, p_sim_run_id, p_sim_clock_now) THEN
      -- CLAIMABILITY IS CHECKED BEFORE THE RELEASE, not after. The original guard
      -- below defends the TARGET bay from a second vehicle, which is the opposite
      -- direction from idx_stalls_one_vehicle_per_stall -- that index is
      -- UNIQUE(current_vehicle_id), i.e. one STALL per VEHICLE. Both directions now
      -- hold: the bay cannot be stolen, and the car cannot be in two places.
      -- Hoisted ahead of the release so a bay we cannot claim never leaves the car
      -- standing in no stall at all.
      IF EXISTS (SELECT 1 FROM stalls s
                  WHERE s.id = v_rec.booked_stall
                    AND (s.current_vehicle_id IS NULL OR s.current_vehicle_id = v_rec.id)) THEN
        UPDATE stalls SET current_vehicle_id = NULL,
               status = CASE WHEN status = 'occupied' THEN 'available' ELSE status END
         WHERE current_vehicle_id = v_rec.id AND id <> v_rec.booked_stall;
        UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
         WHERE id = v_rec.booked_stall
           AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id);
        IF FOUND THEN
          UPDATE vehicles SET current_stall_id = v_rec.booked_stall WHERE id = v_rec.id;
        END IF;
      END IF;
    END IF;
    UPDATE vehicles
       SET current_state = (CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN 'in_detail_bay' ELSE 'in_wash_bay' END)::vehicle_state,
           last_state_change = p_sim_clock_now,
           config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('washing'::text)), '{service_ends_at}', to_jsonb((p_sim_clock_now +
               ((CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))
                      THEN v_detail_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'detail_time', v_rec.id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0)
                      ELSE v_wash_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'wash_time', v_rec.id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0) END) || ' minutes')::interval)::text))
     WHERE id = v_rec.id;
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
    -- 0048 REORDER: PHYSICAL TRUTH BEFORE THE STATE FLIP. This vehicle-state
    -- UPDATE used to run BEFORE the stall handoff below. That made
    -- trg_reassignment_guard (BEFORE UPDATE ON stalls) see the vehicle already
    -- in a protected in-bay state while it was still standing on its OLD stall,
    -- so the guard vetoed the release, silently restored the old pointer, and
    -- the very next place-statement violated idx_stalls_one_vehicle_per_stall
    -- and killed the whole tick (measured: cert arm 44252690, vehicle a6e9c009,
    -- charge_complete_holding on a wash bay, admitted to its booked service
    -- bay). Handoff first -- while the state is still a holding state the guard
    -- does not protect -- then the state write. Both statements byte-identical
    -- to the pre-image; only their order changed.

    -- HONOUR THE RESERVATION PHYSICALLY. Claiming the booked bay is what lets
    -- ottoq.ottoq_activate_present_bookings flip the row held -> active next tick -- the
    -- RUNTIME proof the reservation was kept rather than silently expired. Guarded so it
    -- can never steal a bay another vehicle is standing in, so it cannot double-book.
    IF v_rec.booked_stall IS NOT NULL
       AND NOT twin.ottoq_arm_refuse_move(v_rec.id, 'service_flow.bay_admit',
                                          v_rec.booked_stall, p_sim_run_id, p_sim_clock_now) THEN
      -- CLAIMABILITY IS CHECKED BEFORE THE RELEASE, not after. The original guard
      -- below defends the TARGET bay from a second vehicle, which is the opposite
      -- direction from idx_stalls_one_vehicle_per_stall -- that index is
      -- UNIQUE(current_vehicle_id), i.e. one STALL per VEHICLE. Both directions now
      -- hold: the bay cannot be stolen, and the car cannot be in two places.
      -- Hoisted ahead of the release so a bay we cannot claim never leaves the car
      -- standing in no stall at all.
      IF EXISTS (SELECT 1 FROM stalls s
                  WHERE s.id = v_rec.booked_stall
                    AND (s.current_vehicle_id IS NULL OR s.current_vehicle_id = v_rec.id)) THEN
        UPDATE stalls SET current_vehicle_id = NULL,
               status = CASE WHEN status = 'occupied' THEN 'available' ELSE status END
         WHERE current_vehicle_id = v_rec.id AND id <> v_rec.booked_stall;
        UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
         WHERE id = v_rec.booked_stall
           AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id);
        IF FOUND THEN
          UPDATE vehicles SET current_stall_id = v_rec.booked_stall WHERE id = v_rec.id;
        END IF;
      END IF;
    END IF;
    UPDATE vehicles SET current_state = 'in_service_bay'::vehicle_state, last_state_change = p_sim_clock_now,
           config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('servicing'::text)), '{service_ends_at}', to_jsonb((p_sim_clock_now + ((v_svc_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'maintenance_time', v_rec.id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0)) || ' minutes')::interval)::text))
     WHERE id = v_rec.id;
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
;

-- ── twin.ottoq_sim_bay_fault_handler — 2 cursors ordered ──
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
  v_seed   := abs(hashtextextended(p_depot_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock) || 'bayflt', 23));

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
     ORDER BY s.id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
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
     ORDER BY v.id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
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
;

-- ── twin.ottoq_sim_vehicle_exception_handler — 4 cursors ordered ──
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
  v_appr_n int := 0;      -- 0002: approval rows resolved alongside a technician decision
  v_tow_min numeric;      -- 0002: tow-retrieval dwell, compared in an EXPLICIT clock domain
BEGIN
  v_seed := abs(hashtextextended(p_depot_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock) || 'vexc', 17));
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
     ORDER BY id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
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
                            -- 0002: SIM-DOMAIN tow stamp. vehicles.last_state_change is
                            -- overwritten with NOW() by the BEFORE UPDATE trigger on
                            -- vehicles, so it can never be compared to a sim clock.
                            'tow_requested_at', p_sim_clock,
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
     ORDER BY id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
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
                      jsonb_set(
                        jsonb_set(config, '{exception,status}',
                          to_jsonb(CASE WHEN v_sev='critical' THEN 'auto_staged' ELSE 'pending_approval' END)),
                        -- 0002: the deferred path reaches tow_requested LATER than
                        -- flagged_at, so it needs its own sim-domain stamp too.
                        '{exception,tow_requested_at}', to_jsonb(p_sim_clock)),
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
     ORDER BY id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
  LOOP
    UPDATE vehicles SET config = jsonb_set(config, '{exception,status}', to_jsonb('technician_approved'::text))
     WHERE id = v_rec.id;

    -- ══════════ 0002 (b): "TECHNICIAN APPROVED" IS NOW ONE FACT ══════════
    -- This loop used to flip config.exception.status to 'technician_approved' and stop
    -- there, leaving the matching ottoq_ops_approvals row sitting at 'pending' forever.
    -- The system therefore held two contradictory beliefs about the same event: the
    -- vehicle record said a technician had approved, the approvals ledger said nobody
    -- had. Both writes are now in the SAME statement sequence inside the SAME plpgsql
    -- transaction -- both happen or neither does.
    -- CLOCK DOMAIN: decided_at is stamped in the SAME domain the row was requested in
    -- (§4 tags every new row; rows without the tag are real-domain). The decision itself
    -- was reached on the sim clock -- config.exception.flagged_at is sim-domain -- so the
    -- sim instant is always recorded in the payload as well, in both branches.
    UPDATE ottoq_ops_approvals ap
       SET status      = 'approved',
           decided_at  = CASE WHEN ap.payload->>'requested_at_sim' IS NOT NULL
                              THEN p_sim_clock ELSE now() END,
           decided_by  = 'auto_gate:technician_approved_offline_inspection',
           payload     = COALESCE(ap.payload,'{}'::jsonb) || jsonb_build_object(
                           'decision', jsonb_build_object(
                             'verdict','approved',
                             'reason','technician_approved_vehicle_offline_same_transaction',
                             'decided_at_sim', p_sim_clock,
                             'decider','twin.ottoq_sim_vehicle_exception_handler'))
     WHERE ap.vehicle_id    = v_rec.id
       AND ap.status        = 'pending'
       AND ap.approval_type = 'indepot_reassign';
    GET DIAGNOSTICS v_appr_n = ROW_COUNT;

    PERFORM ottoq_record_event(
      p_actor_type:='command_center_operator', p_actor_id:='technician_in_loop', p_event_type:='vehicle.technician_approved',
      p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id, p_depot_id:=p_depot_id,
      p_payload:= jsonb_build_object('action','approved_offline_inspection',
                                     'approvals_resolved', v_appr_n),
      p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  -- ══════════ 0002 (b2): THE auto_staged PATH ══════════
  -- A 'critical' fault sets config.exception.status straight to 'auto_staged' -- the
  -- system took the vehicle offline WITHOUT waiting for a human. If a pending approval
  -- row is still sitting there asking permission, that row is asking about something
  -- that has already happened. RESOLVE IT (rather than never creating it): the request
  -- was real, it was audited, and the ledger should record how it ended. Recording it as
  -- approved-because-superseded keeps the audit trail honest and stops the row from
  -- barring the vehicle from ever resuming its outstanding work.
  -- The vehicle is already in tow_requested here, so this can never cut live work: the
  -- deferred-resume loop above only ever looks at 'deferred_awaiting_tech' vehicles.
  UPDATE ottoq_ops_approvals ap
     SET status     = 'approved',
         decided_at = CASE WHEN ap.payload->>'requested_at_sim' IS NOT NULL
                           THEN p_sim_clock ELSE now() END,
         decided_by = 'auto_gate:auto_staged_supersedes_request',
         payload    = COALESCE(ap.payload,'{}'::jsonb) || jsonb_build_object(
                        'decision', jsonb_build_object(
                          'verdict','approved',
                          'reason','vehicle_already_auto_staged_request_is_moot',
                          'decided_at_sim', p_sim_clock,
                          'decider','twin.ottoq_sim_vehicle_exception_handler'))
   WHERE ap.status = 'pending'
     AND ap.approval_type = 'indepot_reassign'
     AND EXISTS (SELECT 1 FROM vehicles v
                  WHERE v.id = ap.vehicle_id
                    AND v.home_depot_id = p_depot_id
                    AND v.category = 'autonomous'
                    AND v.current_state = 'tow_requested'
                    AND v.config->'exception'->>'status' = 'auto_staged');

  -- (3) TOW RETRIEVAL -- never closed, never gated. A genuinely broken vehicle always leaves.
  --
  -- ══════════ 0002: THE CLOCK-DOMAIN BUG THAT KEPT BROKEN VEHICLES PINNED ══════════
  -- WAS: "last_state_change <= p_sim_clock - tow_retrieval_min".
  -- vehicles.last_state_change is REAL-clock: the BEFORE UPDATE trigger on vehicles
  -- overwrites it with NOW() on every state change, so whatever a caller assigns is
  -- discarded. p_sim_clock is SIM-clock. Comparing them is meaningless, and in the
  -- measured run it was never true -- tow retrieval fired ZERO times, which is why
  -- ottoq.ottoq_readmit_resumed_visits (which needs the emergency_staged /
  -- retrieved_staged pair that ONLY tow retrieval produces) was double-dead.
  -- This is the 7th instance of this bug class in this codebase.
  --
  -- NOW: every comparison names its domain and compares like with like.
  --   SIM  branch: exception.tow_requested_at (stamped above, sim) vs p_sim_clock (sim).
  --                Falls back to exception.flagged_at, also sim-domain, for rows that
  --                entered tow_requested before this migration.
  --   REAL branch: rows with neither stamp (legacy, or written by some other path) are
  --                compared last_state_change (real) vs now() (real). Without this a
  --                legacy vehicle would wait forever for a stamp that will never be
  --                written, because nothing updates it once it is already tow_requested.
  v_tow_min := GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'tow_retrieval_min',25),25), 0);
  FOR v_rec IN
    SELECT vh.id, vh.fleet_operator_id FROM vehicles vh
     WHERE vh.home_depot_id = p_depot_id AND vh.category = 'autonomous'
       AND vh.current_state = 'tow_requested'
       AND COALESCE(vh.config->'exception'->>'status','auto_staged') IN ('auto_staged','technician_approved')
       AND CASE
             WHEN COALESCE(NULLIF(vh.config->'exception'->>'tow_requested_at',''),
                           NULLIF(vh.config->'exception'->>'flagged_at','')) IS NOT NULL
               THEN COALESCE(NULLIF(vh.config->'exception'->>'tow_requested_at','')::timestamptz,
                             NULLIF(vh.config->'exception'->>'flagged_at','')::timestamptz)
                      <= p_sim_clock - (v_tow_min || ' minutes')::interval    -- SIM  vs SIM
             ELSE vh.last_state_change
                      <= now()       - (v_tow_min || ' minutes')::interval    -- REAL vs REAL
           END
     ORDER BY vh.id   -- 0050: run-stable cursor order (fleet/stall identity, never heap order)
  LOOP
    v_plan := ottoq_stage_after_tow_retrieval(v_rec.id, p_sim_run_id, p_depot_id, p_sim_clock);
    v_stall := NULLIF(v_plan->>'stall_id','')::uuid;
    IF v_stall IS NOT NULL THEN
      UPDATE vehicles
         SET current_state = 'emergency_staged'::vehicle_state, current_stall_id = v_stall,
             last_state_change = p_sim_clock,
             config = jsonb_set(COALESCE(config,'{}'::jsonb), '{exception,status}', to_jsonb('retrieved_staged'::text))
       WHERE id = v_rec.id;
      -- YOU CANNOT TOW A CAR THAT IS STILL PLUGGED IN. If this vehicle faulted
      -- while the arm had hold of it, refusing the move would trap it on the
      -- charger for the length of the incident -- an interlock that makes the
      -- emergency worse. So this path RELEASES rather than asks, through the same
      -- sanctioned door the charger-fault path uses: critical event, cycle closed
      -- as 'emergency_released', vehicle flagged awaiting supervisor disposition.
      -- No-op when the car was never tethered.
      PERFORM twin.ottoq_arm_emergency_release(
        v_rec.id, 'vehicle exception: retrieved and staged',
        'twin_vehicle_exception', p_sim_run_id, p_sim_clock);
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

-- 0002 (house rule 4): this function is reached from twin.ottoq_world_advance and,
-- through it, from the tick. It had no handler of its own -- an error propagated out and
-- the caller's blanket handler reported it as an anonymous twin failure. It now fails
-- loudly and by name, and can never take a tick down with it.
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'twin.ottoq_sim_vehicle_exception_handler FAILED SAFELY: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$
;

