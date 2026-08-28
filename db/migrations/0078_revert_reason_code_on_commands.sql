-- migration-version: 20260828030000
-- migration-name:    revert_reason_code_on_commands
-- 0078 -- REVERTS 0076 and 0077. Both assumed ottoq_vehicle_commands.reason_code is a free-text
-- "why was this issued" field. It is not: the column carries a CHECK constraint restricting it to
-- exactly seven REFUSAL reasons (target_occupied, resource_faulted, target_unknown,
-- vehicle_unresponsive, command_malformed, no_capacity, superseded). Writing an issued-command
-- rationale there raised 23514 (check_violation) and aborted the DECIDE half of every tick --
-- measured on run 7bfc166d: 75 sim_tick_failed events, 116 vehicles_unplaced, zero decisions
-- enacted, before the run was stopped.
--
-- The "why was this command issued" already lives in ottoq_decisions (proposed_action.rationale,
-- context_frame, shield_verdict, rule_results). The correct audit surface is a READ-side join from
-- command -> decision, not a write-side reason column. That join is the follow-up work; this
-- migration only restores the schema's original semantics.
--
-- This drops the 0076 8-arg overload (if present) and restores the original 6-arg
-- ottoq.ottoq_emit_vehicle_command byte-for-byte.

DROP FUNCTION IF EXISTS ottoq.ottoq_emit_vehicle_command(uuid, uuid, uuid, text, jsonb, timestamp with time zone, text, text);

CREATE OR REPLACE FUNCTION ottoq.ottoq_emit_vehicle_command(p_run uuid, p_depot uuid, p_vehicle uuid, p_type text, p_payload jsonb, p_clock timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_check jsonb; v_id uuid;
BEGIN
  v_check := ottoq.ottoq_validate_assignment(
               p_vehicle, NULLIF(p_payload->>'stall_id','')::uuid, p_type, p_clock);

  IF COALESCE((v_check->>'ok')::boolean, false) THEN
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at)
    VALUES (p_run, p_depot, p_vehicle, p_type, p_payload, p_clock)
    RETURNING command_id INTO v_id;

    /* ═════════ 0064: A HOLD MUST OUTLIVE THE COMMAND IT SERVES ═════════
       Measured (re-cert #17, vehicle 02734f04 / stall 906cbfff): the hold
       expired at sim-min 280 while the begin_charge issued at 270 was not
       confirmed until 300, so at 300 the reservation path and the confirm
       walk raced for the stall. Cost across that pair: 819 vs 22 and 909 vs
       14 begin_charge refused-vs-executed, 80 and 86 of 100 vehicles hitting
       a stolen-stall refusal, and fast-charge demand collapsing onto L2.
       Extending here makes the hold outlive the command that needs it.
       Narrow by construction: only EXTENDS (GREATEST), only a stall already
       reserved for THIS vehicle (never steals, never creates), and only on
       the accepted branch. Window is exactly two ticks, derived per run so a
       scenario with a different tick length still gets issue+confirm cover. */
    IF NULLIF(p_payload->>'stall_id','') IS NOT NULL THEN
      UPDATE public.stalls s
         SET reservation_expires_at = GREATEST(
               COALESCE(s.reservation_expires_at, p_clock),
               p_clock + make_interval(secs => COALESCE(
                 (SELECT (2 * r.tick_interval_seconds * r.time_scale)::double precision
                    FROM public.ottoq_sim_runs r
                   WHERE r.sim_run_id = p_run), 3600::double precision)))
       WHERE s.id = (p_payload->>'stall_id')::uuid
         AND s.reserved_by = p_vehicle;
    END IF;
  ELSE
    -- OTTO-Q refuses its OWN conflicting instruction pre-flight. It is recorded
    -- for the audit trail and the reaction loop, and never reaches the twin.
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at,
                                               status, reason_code, reason_detail, confirmed_at, confirmed_by)
    VALUES (p_run, p_depot, p_vehicle, p_type, p_payload, p_clock,
            'refused', v_check->>'code', v_check->>'detail', p_clock, 'otto_q_preflight')
    RETURNING command_id INTO v_id;
  END IF;
  RETURN v_id;
END $function$
