-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: 1fdcb54cfbeea71bbb15ddce6273857c
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

