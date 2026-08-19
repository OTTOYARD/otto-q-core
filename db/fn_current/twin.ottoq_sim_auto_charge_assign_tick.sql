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
      ottoq_apply_profile(p_sim_run_id, 'target_soc', COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc()), COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc()))));

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
;
