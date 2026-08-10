-- MIGRATION: 0036_refusal_path.sql
-- P1-11: The refusal path has never fired. ottoq_sim_confirm_commands
-- stamps ALL issued commands as executed unconditionally. 31,157 executed, 0 refused.
-- This migration adds a pre-execution validation step: before executing a command,
-- verify the target stall is still available and the vehicle is in a compatible state.
-- If validation fails, stamp the command as 'refused' instead of 'executed'.

CREATE OR REPLACE FUNCTION twin.ottoq_sim_confirm_commands(p_sim_run_id uuid, p_clock timestamp with time zone)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_rec RECORD;
  v_executed int := 0;
  v_refused  int := 0;
  v_skipped  int := 0;
  v_now      timestamptz := COALESCE(p_clock, now());
  v_due       timestamptz;
  v_stall_ok  boolean;
  v_vehicle_ok boolean;
BEGIN
  FOR v_rec IN
    SELECT c.id AS command_id, c.vehicle_id, c.verb, c.payload, c.sim_run_id, c.issued_at,
           v.current_state, v.current_stall_id, v.current_soc
      FROM ottoq_vehicle_commands c
      JOIN vehicles v ON v.id = c.vehicle_id
     WHERE c.sim_run_id = p_sim_run_id
       AND c.status = 'issued'
     ORDER BY c.issued_at
  LOOP
    -- Determine due time: 30 sim-minutes after issue, or configurable
    v_due := COALESCE(v_rec.issued_at, v_now) + interval '30 minutes';
    
    -- Pre-execution validation
    v_stall_ok := true;
    v_vehicle_ok := true;
    
    -- Check stall availability for stall-specific commands
    IF v_rec.payload ? 'stall_id' THEN
      SELECT EXISTS (
        SELECT 1 FROM stalls s
        WHERE s.id = (v_rec.payload->>'stall_id')::uuid
          AND s.current_vehicle_id IS NULL
          AND (s.reserved_by IS NULL OR s.reserved_by = v_rec.vehicle_id
               OR s.reservation_expires_at <= v_now)
      ) INTO v_stall_ok;
    END IF;
    
    -- Check vehicle state compatibility
    CASE v_rec.verb
      WHEN 'proceed_to_stall', 'begin_charge', 'enter_wash', 'enter_service' THEN
        -- Vehicle must not already be in a terminal state
        v_vehicle_ok := v_rec.current_state NOT IN ('deployed','en_route_to_depot','completed','dead');
      WHEN 'deploy', 'proceed_to_gate' THEN
        -- Vehicle must be ready to deploy
        v_vehicle_ok := v_rec.current_state IN ('staged_for_departure','staged_awaiting_service');
      ELSE
        v_vehicle_ok := true; -- fallback: allow unknown verbs
    END CASE;
    
    IF v_stall_ok AND v_vehicle_ok THEN
      -- Execute: null out old stall, occupy new one
      IF v_rec.payload ? 'stall_id' THEN
        UPDATE stalls SET current_vehicle_id = NULL, status = 'available'
         WHERE current_vehicle_id = v_rec.vehicle_id
           AND id <> (v_rec.payload->>'stall_id')::uuid;
        
        UPDATE stalls SET current_vehicle_id = v_rec.vehicle_id, status = 'occupied'
         WHERE id = (v_rec.payload->>'stall_id')::uuid;
      END IF;
      
      UPDATE ottoq_vehicle_commands
         SET status = 'executed',
             confirmed_at = v_due,
             confirmed_by = CASE WHEN COALESCE((v_rec.payload->>'apply_required')::boolean, false)
                                 THEN 'twin_auto_tech' ELSE 'otto_q_preflight' END,
             executed_at = v_due
       WHERE id = v_rec.command_id;
      
      v_executed := v_executed + 1;
    ELSE
      -- Refuse: command cannot be executed
      UPDATE ottoq_vehicle_commands
         SET status = 'refused',
             confirmed_at = v_now,
             confirmed_by = 'otto_q_preflight_refusal',
             payload = v_rec.payload || jsonb_build_object(
               'refusal_reason', CASE
                 WHEN NOT v_stall_ok THEN 'stall_unavailable'
                 WHEN NOT v_vehicle_ok THEN format('vehicle_state_incompatible: %s', v_rec.current_state)
                 ELSE 'validation_failed'
               END,
               'refused_at_clock', v_now
             )
       WHERE id = v_rec.command_id;
      
      v_refused := v_refused + 1;
    END IF;
  END LOOP;
  
  RETURN v_executed + v_refused;
END;
$fn$;
