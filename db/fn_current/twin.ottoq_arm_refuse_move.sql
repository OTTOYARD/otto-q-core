-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3 follow-up, re-cert #3)
-- md5 at capture: e41bd0bdb025c8f46676046790666583
CREATE OR REPLACE FUNCTION twin.ottoq_arm_refuse_move(p_vehicle_id uuid, p_mover text, p_intended_stall uuid DEFAULT NULL::uuid, p_sim_run_id uuid DEFAULT NULL::uuid, p_clock timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_clock timestamptz;
  v_veh   RECORD;
BEGIN
  IF p_vehicle_id IS NULL THEN RETURN false; END IF;

  v_clock := COALESCE(p_clock,
                      (SELECT sim_clock_current FROM public.ottoq_sim_runs
                        WHERE sim_run_id = p_sim_run_id),
                      now());

  IF NOT public.ottoq_vehicle_is_tethered(p_vehicle_id, v_clock) THEN
    RETURN false;
  END IF;

  SELECT current_depot_id, robotic_tether_until, robotic_tether_stall_id,
         robotic_tether_direction, robotic_tether_phase, current_state
    INTO v_veh FROM public.vehicles WHERE id = p_vehicle_id;

  -- Moving a car to the stall the arm is already holding it in is not a move.
  IF p_intended_stall IS NOT NULL
     AND p_intended_stall = v_veh.robotic_tether_stall_id THEN
    RETURN false;
  END IF;

  PERFORM public.ottoq_record_event(
    p_actor_type    := 'system',
    p_actor_id      := COALESCE(p_mover, 'unknown_mover'),
    p_event_type    := 'arm.move_refused',
    p_entity_type   := 'vehicle',
    p_entity_id     := p_vehicle_id,
    p_depot_id      := v_veh.current_depot_id,
    p_payload       := jsonb_build_object(
                         'mover',            p_mover,
                         'intended_stall',   p_intended_stall,
                         'held_at_stall',    v_veh.robotic_tether_stall_id,
                         'tether_direction', v_veh.robotic_tether_direction,
                         'tether_phase',     v_veh.robotic_tether_phase,
                         'tether_until',     v_veh.robotic_tether_until,
                         'vehicle_state',    v_veh.current_state,
                         'sim_clock',        v_clock),
    p_severity      := 'info',
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id);

  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_arm_refuse_move(%,%): % -- failing open, the trigger backstop still refuses',
    p_vehicle_id, p_mover, SQLERRM;
  RETURN false;
END;
$function$
