-- migration-version: 20260819180000
-- migration-name:    twin_determinism_and_playback
-- 0045 — C7 TWIN HARDENING: the determinism fix, the standing cert, the
--        canonical event vocabulary, the playback timeline, and the A/B
--        retention decision.
--
-- Run 3 / Phase C7 (CLAUDE.md). NOT YET APPLIED TO PRODUCTION — apply after
-- founder merge, then re-run the determinism certification (TWIN_CORE.md §2).
--
-- THE FINDING THIS FIXES (measured live 2026-08-19, runs 6727b04e / a1e3bdb3,
-- both seed 424242 / policy otto_q / identical harness): the twin is NOT
-- deterministic under fixed seed. Root cause: eleven RNG-salt sites in nine
-- twin functions salt ottoq_sim_seeded_random / hashtextextended with the
-- ABSOLUTE sim clock, and every run anchors its sim clock to real now() at
-- start — so two same-seed runs draw entirely different streams. Measured
-- damage at fixed seed: 68/100 vehicle SoCs diverged within the first common
-- frame; throughput 8.1 vs 7.1 /hr; peak 662 vs 588 kW; 120 vs 107 dispatches.
-- THE FIX: salt with the run-relative sim offset (twin.ottoq_sim_clock_salt),
-- which is identical across same-seed runs by construction. Each patched body
-- below is byte-identical to its 2026-08-19 capture in db/fn_current/ except
-- the salt expression(s).

-- ============================================================================
-- §1  THE SALT DOMAIN — run-relative, never absolute
-- ============================================================================
CREATE OR REPLACE FUNCTION twin.ottoq_sim_clock_salt(p_sim_run_id uuid, p_clock timestamp with time zone)
RETURNS text LANGUAGE sql STABLE AS $fn$
  -- Whole seconds since the run''s own sim_clock_start: pure function of
  -- (run, sim clock), identical across same-seed runs regardless of the wall
  -- clock at start. Falls back to the absolute text (the old behavior) only
  -- when the run row is unknown, so nothing regresses on edge paths.
  SELECT COALESCE(
    (SELECT floor(EXTRACT(EPOCH FROM (p_clock - r.sim_clock_start)))::text
       FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id),
    p_clock::text);
$fn$;

-- ============================================================================
-- §2  THE NINE PATCHED TICK FUNCTIONS (11 salt sites total)
-- ============================================================================
-- ── twin.ottoq_sim_advance_deployed_telemetry (salt-domain fix; 2 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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

-- ── twin.ottoq_sim_advance_grid (salt-domain fix; 1 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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
  v_seed  := abs(hashtextextended(p_depot_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now) || 'grid', 31));
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
;

-- ── twin.ottoq_sim_advance_site_energy (salt-domain fix; 1 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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
  v_seed := abs(hashtextextended(p_depot_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now) || 'site', 11));
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
;

-- ── twin.ottoq_sim_advance_weather_and_solar (salt-domain fix; 1 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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

  v_seed        := abs(hashtextextended(p_depot_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now) || 'wx', 17));
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
;

-- ── twin.ottoq_sim_bay_fault_handler (salt-domain fix; 1 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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
;

-- ── twin.ottoq_sim_bess_step (salt-domain fix; 1 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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

  v_seed   := abs(hashtextextended(p_bess_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), 23));
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
;

-- ── twin.ottoq_sim_dispatch_vehicle (salt-domain fix; 1 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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

  -- ═══════════════════ 0019: THE DOOR, NOT JUST THE QUEUE ═══════════════════
  -- ottoq.ottoq_plan_dispatch_tick already declines to SELECT a flagged vehicle.
  -- This is the same rule stated where the dispatch row is actually written, so
  -- that no present or future caller of this function can route around it. Under
  -- normal operation the planner filters first and this branch is never taken;
  -- if it is ever taken, the event below says so out loud rather than silently.
  IF public.ottoq_rider_flag_due(p_vehicle_id, p_sim_run_id, p_sim_clock_now) THEN
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type    := 'ottoq_engine',
        p_actor_id      := 'rider_flag_hold',
        p_event_type    := 'twin.dispatch_refused_rider_flag',
        p_entity_type   := 'vehicle',
        p_entity_id     := p_vehicle_id,
        p_payload       := jsonb_build_object(
          'reason', 'vehicle owes a due rider-flagged cleaning',
          'doctrine', 'always_hold_no_vehicle_leaves_owing_known_work',
          'sim_clock', p_sim_clock_now),
        p_severity      := 'warning',
        p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id    := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN NULL;
  END IF;

  v_seed := abs(hashtextextended(p_vehicle_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), 42));

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
;

-- ── twin.ottoq_sim_emit_arrival_webhook (salt-domain fix; 2 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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
                   abs(hashtextextended(p_vehicle_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now) || 'arrival', 42)), TRUE);
    PERFORM ottoq_oem_deliver_live(v_webhook_id, p_sim_run_id, p_vehicle_id, v_pattern.fleet_operator_id,
                   v_oem, v_pattern.live_endpoint_url, v_payload, v_pattern.signing_secret_ref, p_sim_clock_now);
    RETURN v_webhook_id;
  END IF;

  v_seed         := abs(hashtextextended(p_vehicle_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now) || 'arrival', 42));
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
;

-- ── twin.ottoq_sim_vehicle_exception_handler (salt-domain fix; 1 site(s) patched; body otherwise byte-identical
--    to the 2026-08-19 capture in db/fn_current/) ──
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

-- ============================================================================
-- §3  THE STANDING DETERMINISM CERT — digest + verdict (extends the existing
--     cert harness: ottoq_cert_arm_start/step/finish drive the paired arms;
--     these two functions make the comparison a one-liner and a property test)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_twin_run_digest(p_run uuid)
RETURNS TABLE(tick_seq bigint, sim_min numeric, struct_hash text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions' AS $fn$
  -- Canonical per-tick structural digest over the content-hashed decision
  -- snapshots: vehicle (id,state,SoC,stall) + stall occupancy + session power,
  -- keyed by sim-minute offset. Timestamp-free, so it compares across runs.
  SELECT s.tick_seq::bigint,
         round(EXTRACT(EPOCH FROM (s.sim_clock - sr.sim_clock_start))/60.0)::numeric,
         md5(veh.d || '#' || st.d || '#' || se.d)
    FROM ottoq_decision_snapshots s
    JOIN ottoq_sim_runs sr ON sr.sim_run_id = s.sim_run_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(string_agg((v->>'id')||':'||(v->>'state')||':'||COALESCE(round((v->>'soc')::numeric,1)::text,'-')||':'||COALESCE(v->>'stall_id','-'), '|' ORDER BY v->>'id'), '') AS d
        FROM jsonb_array_elements(COALESCE(s.frame->'vehicles','[]'::jsonb)) v) veh ON true
    LEFT JOIN LATERAL (
      SELECT COALESCE(string_agg((x->>'id')||':'||COALESCE(x->>'status','-')||':'||COALESCE(x->>'vehicle_id','-'), '|' ORDER BY x->>'id'), '') AS d
        FROM jsonb_array_elements(COALESCE(s.frame->'stalls','[]'::jsonb)) x) st ON true
    LEFT JOIN LATERAL (
      SELECT COALESCE(string_agg(COALESCE(x->>'stall_id','-')||':'||COALESCE(x->>'status','-')||':'||COALESCE(round((x->>'power_kw')::numeric,1)::text,'-'), '|' ORDER BY x->>'stall_id'), '') AS d
        FROM jsonb_array_elements(COALESCE(s.frame->'sessions','[]'::jsonb)) x) se ON true
   WHERE s.sim_run_id = p_run
   ORDER BY s.tick_seq;
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_twin_determinism_verdict(p_run_a uuid, p_run_b uuid)
RETURNS TABLE(ticks_compared int, ticks_identical int, ticks_divergent int,
              only_in_a int, only_in_b int, deterministic boolean, first_divergence_sim_min numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions' AS $fn$
  WITH a AS (SELECT * FROM public.ottoq_twin_run_digest(p_run_a)),
       b AS (SELECT * FROM public.ottoq_twin_run_digest(p_run_b)),
       j AS (SELECT a.sim_min AS ma, b.sim_min AS mb,
                    a.struct_hash AS ha, b.struct_hash AS hb
               FROM a FULL OUTER JOIN b ON a.sim_min = b.sim_min)
  SELECT count(*) FILTER (WHERE ma IS NOT NULL AND mb IS NOT NULL)::int,
         count(*) FILTER (WHERE ha = hb)::int,
         count(*) FILTER (WHERE ma IS NOT NULL AND mb IS NOT NULL AND ha <> hb)::int,
         count(*) FILTER (WHERE mb IS NULL)::int,
         count(*) FILTER (WHERE ma IS NULL)::int,
         (count(*) FILTER (WHERE ha IS DISTINCT FROM hb) = 0),
         min(COALESCE(ma, mb)) FILTER (WHERE ha IS DISTINCT FROM hb)
    FROM j;
$fn$;

-- ============================================================================
-- §4  CANONICAL EVENT VOCABULARY (C7.2) — the five canonical types the
--     132-type catalog lacks, registered properly. Existing impl-flavored
--     types remain the emitters'' vocabulary; the audit mapping lives in
--     TWIN_CORE.md §3. recall_issued / recall_refused are emitted by C9;
--     touch_event supersedes the KPI-4 actor-type enumeration when adopted.
-- ============================================================================
INSERT INTO public.ottoq_event_types_catalog (event_type, category, description, emitter, default_severity, introduced_in)
VALUES
 ('move_start',    'state_change', 'Canonical: an inter-point move (scheduled operation) began.',        'kernel (C7)', 'info',    '0045'),
 ('move_end',      'state_change', 'Canonical: an inter-point move completed.',                          'kernel (C7)', 'info',    '0045'),
 ('recall_issued', 'action',       'Canonical: the Recall Decision recalled an asset from work (C9).',   'recall (C9)', 'info',    '0045'),
 ('recall_refused','business_event','Canonical: the work side refused a recall — first-class, triggers re-solve (C9).', 'recall (C9)', 'warning', '0045'),
 ('touch_event',   'audit',        'Canonical: a human physically intervened on an asset or point. Supersedes actor-type enumeration for KPI-4 once emitters adopt it.', 'kernel (C7)', 'info', '0045')
ON CONFLICT (event_type) DO NOTHING;

-- ============================================================================
-- §5  PLAYBACK TIMELINE (C7.4) — the render seam of CLAUDE.md 2.8:
--     (entity_id, event_type, t_start, t_end, from_pose, to_pose), versioned,
--     pure SQL over legs + stall geometry. Zero Isaac anything in the path;
--     any renderer (the in-house 3D layer or a future OpenUSD reattachment)
--     consumes this view and nothing deeper.
-- ============================================================================
CREATE OR REPLACE VIEW public.ottoq_twin_playback_timeline
  WITH (security_invoker = true) AS
SELECT l.sim_run_id,
       'v1'::text            AS playback_schema_version,
       l.vehicle_id          AS entity_id,
       'vehicle'::text       AS entity_kind,
       CASE WHEN oc.is_movement THEN 'move' ELSE COALESCE(oc.operation_code, l.leg_type) END AS event_type,
       COALESCE(l.actual_start_sim, l.planned_start_sim) AS t_start,
       COALESCE(l.actual_end_sim,   l.planned_end_sim)   AS t_end,
       CASE WHEN sf.id IS NOT NULL THEN jsonb_build_object(
              'x', sf.relative_x, 'y', sf.relative_y, 'heading_deg', sf.heading_degrees,
              'stall_code', sf.stall_code) END           AS from_pose,
       CASE WHEN st.id IS NOT NULL THEN jsonb_build_object(
              'x', st.relative_x, 'y', st.relative_y, 'heading_deg', st.heading_degrees,
              'stall_code', st.stall_code) END           AS to_pose,
       l.leg_id, l.status AS leg_status, l.seq
  FROM public.ottoq_itinerary_legs l
  LEFT JOIN public.ottoq_operation_catalog oc
         ON oc.leg_type = l.leg_type AND oc.pack_id = 'robotaxi'
  LEFT JOIN public.stalls sf ON sf.id = l.from_stall_id
  LEFT JOIN public.stalls st ON st.id = l.to_stall_id;
COMMENT ON VIEW public.ottoq_twin_playback_timeline IS
  'C7.4 playback seam (CLAUDE.md 2.8): (entity_id, event_type, t_start, t_end, '
  'from_pose, to_pose) per itinerary leg, poses from stall geometry, versioned '
  'via playback_schema_version. The 3D layer renders from this and through this '
  'Track B can return. No Isaac imports exist in this path.';

-- ============================================================================
-- §6  A/B RETENTION DECISION (surfaced for merge review; merging = deciding)
--     ottoq_ab_runs was registry class ''engine'', so every purge deleted the
--     CRN A/B scores with their runs — which is why the "statistical spine"
--     table was found EMPTY in C4 (SOLVER_STATE.md §4). A/B scores are claim
--     evidence keyed by (seed, policy); they must outlive their runs exactly
--     like ottoq_run_archives does. Reclass to ''evidence'' (never purged, no
--     FK per the registry contract).
-- ============================================================================
ALTER TABLE public.ottoq_ab_runs DROP CONSTRAINT IF EXISTS fk_ottoq_ab_runs_sim_run;
UPDATE public.ottoq_run_scope_registry
   SET class = 'evidence',
       note  = '0045: A/B scores are claim evidence; they outlive their runs (was engine — purge silently emptied the table; found in run2/C4).'
 WHERE table_schema='public' AND table_name='ottoq_ab_runs' AND column_name='sim_run_id';
