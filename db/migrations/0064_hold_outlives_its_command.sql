-- migration-version: 20260821010000
-- migration-name:    hold_outlives_its_command
-- 0064 — THE RESERVATION-EXPIRY RACE. Founder-approved (Option 1) on 2026-08-21.
-- This is the first migration in the determinism series that deliberately
-- CHANGES ENGINE BEHAVIOUR, so it is called out rather than buried: it extends
-- how long a stall stays held for the vehicle it was held for.
--
-- THE DEFECT. A stall hold could expire in the gap between the tick that ISSUES
-- a stall-bearing command and the tick that CONFIRMS it. Measured on re-cert #17
-- (arms ead7911f / 35a907e7), vehicle 02734f04 and DCFC stall 906cbfff:
--     sim-min 210  stall reserved for 02734f04, reservation_expires_at = 280
--     sim-min 270  engine ISSUES begin_charge for that vehicle + that stall
--     sim-min 280  the hold EXPIRES — the command has not been confirmed yet
--     sim-min 300  two things race in one tick: the reservation path reassigns
--                  the now-expired hold to another vehicle, or the confirm walk
--                  seats the original vehicle. Whichever runs first wins.
-- Arm B seated first (02734f04 charged 32->90 and released). Arm A reassigned
-- first (stall stolen; both begin_charge rows refused 'target_occupied'). That
-- is the whole determinism divergence — but it is NOT primarily a determinism
-- bug.
--
-- THE REAL COST, measured on the same pair (fleet of 100):
--     arm A: begin_charge refused 'target_occupied' 819x vs 22 executed;
--            34 vehicles parked in staging; 80 of 100 vehicles hit a stolen-
--            stall refusal; only 2 of 22 sessions were DCFC (the rest fell back
--            to slow L2).
--     arm B: 909 refused vs 14 executed; 23 parked; 86 of 100 refused.
-- In production this is a charger being given away to another vehicle while the
-- first is already under instruction to take it. The depot parks and trickle-
-- charges instead of fast-charging. The founder independently observed exactly
-- this in the 3D view (cars parking on arrival, staging filling, services not
-- happening) before the ledger confirmed it.
--
-- THE FIX (Option 1 of three offered; founder chose it). One choke point:
-- ottoq.ottoq_emit_vehicle_command is where every accepted vehicle command is
-- written (the only other writer, public.ottoq_hw_recall_vehicle, is the
-- hardware recall path and carries no stall_id). When an ACCEPTED command names
-- a stall, the hold on that stall is pushed out to cover confirmation, making
-- "a hold outlives the command it was created for" an invariant.
--
-- DELIBERATELY NARROW — the three guards that keep this from becoming a
-- land-grab:
--   1. It only ever EXTENDS (GREATEST), never shortens an existing hold.
--   2. It only touches a stall ALREADY reserved for THIS vehicle
--      (s.reserved_by = p_vehicle). It never steals a hold from another
--      vehicle and never creates a hold where none existed.
--   3. It fires only on the accepted branch. A command OTTO-Q refuses
--      pre-flight extends nothing.
-- The window is exactly TWO TICKS, derived per run from
-- tick_interval_seconds * time_scale rather than hardcoded, so a scenario with
-- a different tick length gets the correct window (fallback 3600s = 2 ticks at
-- the standard 30-sim-minute tick). Two ticks, not one, because issue and
-- confirm are adjacent ticks and the boundary case must not land on the edge:
-- 66 of 271 holds in arm A expired EXACTLY on a tick boundary, so the tie is
-- systemic, not rare.
--
-- WHAT THIS DOES NOT DO. It does not change which stall is chosen, who is
-- eligible, or any scheduling priority. It changes one number: how long a stall
-- stays promised to the vehicle that was just told to go to it.
--
-- Same self-verifying in-place mechanism as 0054-0063. Pre-image pin:
--   ottoq.ottoq_emit_vehicle_command 901ab89c7ccdcf05f20c7fa653160ea0

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := E'    RETURNING command_id INTO v_id;\n  ELSE';
  v_new text := E'    RETURNING command_id INTO v_id;\n'
    || E'\n'
    || E'    /* ═════════ 0064: A HOLD MUST OUTLIVE THE COMMAND IT SERVES ═════════\n'
    || E'       Measured (re-cert #17, vehicle 02734f04 / stall 906cbfff): the hold\n'
    || E'       expired at sim-min 280 while the begin_charge issued at 270 was not\n'
    || E'       confirmed until 300, so at 300 the reservation path and the confirm\n'
    || E'       walk raced for the stall. Cost across that pair: 819 vs 22 and 909 vs\n'
    || E'       14 begin_charge refused-vs-executed, 80 and 86 of 100 vehicles hitting\n'
    || E'       a stolen-stall refusal, and fast-charge demand collapsing onto L2.\n'
    || E'       Extending here makes the hold outlive the command that needs it.\n'
    || E'       Narrow by construction: only EXTENDS (GREATEST), only a stall already\n'
    || E'       reserved for THIS vehicle (never steals, never creates), and only on\n'
    || E'       the accepted branch. Window is exactly two ticks, derived per run so a\n'
    || E'       scenario with a different tick length still gets issue+confirm cover. */\n'
    || E'    IF NULLIF(p_payload->>''stall_id'','''') IS NOT NULL THEN\n'
    || E'      UPDATE public.stalls s\n'
    || E'         SET reservation_expires_at = GREATEST(\n'
    || E'               COALESCE(s.reservation_expires_at, p_clock),\n'
    || E'               p_clock + make_interval(secs => COALESCE(\n'
    || E'                 (SELECT (2 * r.tick_interval_seconds * r.time_scale)::double precision\n'
    || E'                    FROM public.ottoq_sim_runs r\n'
    || E'                   WHERE r.sim_run_id = p_run), 3600::double precision)))\n'
    || E'       WHERE s.id = (p_payload->>''stall_id'')::uuid\n'
    || E'         AND s.reserved_by = p_vehicle;\n'
    || E'    END IF;\n'
    || E'  ELSE';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'ottoq' AND pr.proname = 'ottoq_emit_vehicle_command' AND pr.prokind = 'f';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '901ab89c7ccdcf05f20c7fa653160ea0' THEN
    RAISE EXCEPTION '0064: pre-image md5 % != pinned 901ab89c7ccdcf05f20c7fa653160ea0', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0064: accepted-branch anchor occurs % times (need 1)', v_cnt;
  END IF;
  EXECUTE replace(v_src, v_old, v_new);
  RAISE NOTICE '0064 patched ottoq.ottoq_emit_vehicle_command -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'ottoq' AND pr.proname = 'ottoq_emit_vehicle_command' AND pr.prokind = 'f');
END
$do$;
