-- migration-version: 20260828010000
-- migration-name:    command_reason_codes_no_overload
-- 0077 -- CORRECTS 0076. 0076 added defaulted parameters (p_reason_code, p_reason_detail) to
-- ottoq.ottoq_emit_vehicle_command. CREATE OR REPLACE FUNCTION does NOT replace across a signature
-- change: Postgres created a NEW 8-arg overload alongside the original 6-arg function, and every
-- existing 6-arg caller still resolved to the OLD function (fewer default arguments wins). The
-- reason-derivation therefore never fired for any real caller -- a silent no-op that "looked"
-- applied because the new function existed.
--
-- This migration DROPS the erroneous 8-arg overload and replaces the 6-arg function IN PLACE
-- (identical signature, body-only change), so every existing caller now carries a reason. The
-- reason is derived from a caller-supplied payload 'reason' when present, else a baseline from the
-- command verb. TOTAL function: unknown verb -> NULL, never a raise. The 0064 hold-outlives-command
-- logic is preserved byte-for-byte.

DROP FUNCTION IF EXISTS ottoq.ottoq_emit_vehicle_command(uuid, uuid, uuid, text, jsonb, timestamp with time zone, text, text);

CREATE OR REPLACE FUNCTION ottoq.ottoq_emit_vehicle_command(p_run uuid, p_depot uuid, p_vehicle uuid, p_type text, p_payload jsonb, p_clock timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_check jsonb; v_id uuid; v_rc text;
BEGIN
  v_check := ottoq.ottoq_validate_assignment(
               p_vehicle, NULLIF(p_payload->>'stall_id','')::uuid, p_type, p_clock);

  IF COALESCE((v_check->>'ok')::boolean, false) THEN
    -- (0077) reason_code was NULL on ~99% of executed commands. A command's reason is its own
    -- context: prefer a caller-supplied payload 'reason', else derive a baseline from the verb.
    -- TOTAL function -- unknown verb yields NULL, never a raise. Same signature as the pre-image,
    -- so this REPLACES the old function (no overload); every existing 6-arg caller now gets a reason.
    v_rc := COALESCE(NULLIF(p_payload->>'reason',''),
             CASE p_type
               WHEN 'begin_charge'     THEN 'charge_required'
               WHEN 'proceed_to_stall' THEN 'stall_assignment'
               WHEN 'enter_wash'       THEN 'wash_service'
               WHEN 'enter_service'    THEN 'service_required'
               WHEN 'stage'            THEN 'staging_hold'
               WHEN 'dispatch'         THEN 'redeployment'
               WHEN 'deploy'           THEN 'redeployment'
               WHEN 'proceed_to_gate'  THEN 'gate_transit'
               ELSE NULL
             END);
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, reason_code, reason_detail)
    VALUES (p_run, p_depot, p_vehicle, p_type, p_payload, p_clock, v_rc, NULLIF(p_payload->>'reason_detail',''))
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
