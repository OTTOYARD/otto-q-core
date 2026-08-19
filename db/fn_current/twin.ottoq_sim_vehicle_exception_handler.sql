-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: 9cc341164274174bad52476463b3ff09
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

