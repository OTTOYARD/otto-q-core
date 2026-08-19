-- migration-version: 20260819230000
-- migration-name:    twin_arm_refuse_move_clock_domain
-- 0049 — C7 FOLLOW-UP #3, found by re-certification #3 (post-0048 arm 5822181f):
-- a cert tick died on the vehicle-side arm interlock DESPITE the admit path
-- asking twin.ottoq_arm_refuse_move first. The mirror and the backstop were
-- evaluating the tether in two different clock domains, exactly one tick
-- apart. See the inline comment at the patched site. Body otherwise
-- byte-identical to the 2026-08-19 capture in db/fn_current/.

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

  -- ══════════ 0049: THE MIRROR MUST USE THE BACKSTOP'S CLOCK ══════════
  -- This function is the ASK-FIRST mirror of the trigger backstop
  -- public.ottoq_arm_interlock_guard (its own exception handler says so). The
  -- guard evaluates the tether against the RUN'S PERSISTED CLOCK
  -- (ottoq_sim_runs.sim_clock_current, advanced only at END of tick), while
  -- callers here passed the tick's IN-FLIGHT clock (p_sim_clock_now = clock
  -- + tick_minutes). A tether expiring exactly on the tick boundary was
  -- therefore movable to the mirror and held by the backstop, and the tick
  -- died on the interlock (measured: re-cert #3 arm 5822181f, vehicle
  -- 02f1a60b, demate expiring at the new tick's own timestamp). Sourcing the
  -- clock from the guard's EXACT expression makes mirror and backstop
  -- provably consistent for every caller; the boundary case defers one tick
  -- and proceeds cleanly once the demate has been reaped. p_clock is kept in
  -- the signature (and the event payload keeps reporting the evaluated
  -- clock), but it no longer selects the tether-check domain.
  v_clock := COALESCE(
    (SELECT sim_clock_current FROM public.ottoq_sim_runs
      WHERE status = 'running' ORDER BY started_at DESC NULLS LAST LIMIT 1),
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
;
