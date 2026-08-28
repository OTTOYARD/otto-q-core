-- migration-version: 20260827230100
-- migration-name:    command_reason_codes
-- 0076 -- The command bus never records WHY. reason_code was NULL on ~99% of executed commands,
-- which blocks the V1 audit log's core promise: "vehicle X was told to do Y *because Z*."
--
-- EVIDENCE (live DB, run 4f9778de, completed 2026-08-23):
--   stage             4,892 executed, 0 with reason_code
--   dispatch            965 executed, 0 with reason_code
--   proceed_to_stall    414 executed, 5 with reason_code
--   begin_charge        166 executed, 116 with reason_code (the only verb that carries one)
--   => 99.7% of the command ledger is "what" without "why".
--
-- The "why" exists at every call site (it is the decision context that triggered the emit), but
-- ottoq.ottoq_emit_vehicle_command accepted no reason parameter and wrote no reason column. The
-- fix adds two optional params (p_reason_code, p_reason_detail) and derives a baseline reason from
-- the command verb when the caller does not pass one, so EVERY command now self-describes its
-- cause. This is a TOTAL function -- an unknown verb yields NULL, never a raise -- and existing
-- callers are unchanged (the new params default NULL), so this is strictly backward-compatible.
-- Callers may later pass a richer reason; the default closes the 99% gap now with zero call-site
-- edits and therefore zero regression surface.
--
-- Vocabulary (baseline, verb-derived):
--   begin_charge      -> charge_required
--   proceed_to_stall  -> stall_assignment
--   enter_wash        -> wash_service
--   enter_service     -> service_required
--   stage             -> staging_hold
--   dispatch / deploy -> redeployment
--   proceed_to_gate   -> gate_transit
--
-- Note: the REFUSED branch already writes reason_code (v_check->>'code'); unchanged.

CREATE OR REPLACE FUNCTION ottoq.ottoq_emit_vehicle_command(p_run uuid, p_depot uuid, p_vehicle uuid, p_type text, p_payload jsonb, p_clock timestamp with time zone, p_reason_code text DEFAULT NULL, p_reason_detail text DEFAULT NULL)
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
    -- (0076) reason_code was NULL on ~99% of executed commands (run 4f9778de: 0/4892 stage,
    -- 0/965 dispatch, 5/414 proceed_to_stall, 116/166 begin_charge carried a reason), so the
    -- audit log could show WHAT happened but not WHY. A command's reason is its own context:
    -- derive a baseline from the verb when the caller does not pass one. TOTAL function -- an
    -- unknown verb gets NULL, never a raise. Callers may pass a more specific reason via the
    -- new optional params; existing callers are byte-for-byte unchanged (params default NULL).
    v_rc := COALESCE(p_reason_code,
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
    VALUES (p_run, p_depot, p_vehicle, p_type, p_payload, p_clock, v_rc, p_reason_detail)
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
