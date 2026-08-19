-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 89c6f1fc756a6995a88e12720d4c3886
CREATE OR REPLACE FUNCTION twin.ottoq_sim_confirm_commands(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD;
  v_executed int := 0;
  v_refused  int := 0;
  v_skipped  int := 0;
  v_now      timestamptz := COALESCE(p_clock, now());
  v_due       timestamptz;
  v_stall_ok  boolean;
  v_vehicle_ok boolean;
  v_new_state text;      -- 0039 completion: the state this command puts the vehicle in
BEGIN
  -- ═══════ ONE STALL-BEARING COMMAND PER VEHICLE PER PASS ═══════
  -- A vehicle can accumulate several conflicting stall commands before any of them is
  -- confirmed. MEASURED on run ba4470f9, vehicle d5dd0338: FOUR issued at once — two
  -- begin_charge to one stall and two proceed_to_stall to a different stall. Executing
  -- them in sequence made the car occupy a charger (which flipped it to charging_l2,
  -- i.e. mid-service) and then immediately try to leave for another stall, which the
  -- in-depot gate correctly refuses — and the refusal surfaced as a 23505 on
  -- idx_stalls_one_vehicle_per_stall that aborted the entire world tick.
  -- Only the NEWEST stall-bearing command expresses current intent; the older ones are
  -- retired as 'superseded' (a reason_code the schema already defines) rather than
  -- executed one after another.
  -- A REPEAT IS NOT A CONFLICT. See a_reissued_command_does_not_supersede_itself.
  -- cur_type/cur_stall are the NEWEST stall command's intent for this vehicle.
  -- dup_rn ranks identical (type, stall) commands OLDEST FIRST, so the one the
  -- vehicle is already acting on survives and its later echoes are retired.
  WITH stall_cmds AS (
    SELECT c.command_id,
           c.command_type,
           c.payload->>'stall_id' AS stall_id,
           first_value(c.command_type) OVER w          AS cur_type,
           first_value(c.payload->>'stall_id') OVER w  AS cur_stall,
           row_number() OVER (PARTITION BY c.vehicle_id, c.command_type, c.payload->>'stall_id'
                              ORDER BY c.issued_at ASC, c.command_id ASC) AS dup_rn
      FROM ottoq_vehicle_commands c
     WHERE c.sim_run_id = p_sim_run_id AND c.status = 'issued' AND c.payload ? 'stall_id'
    WINDOW w AS (PARTITION BY c.vehicle_id ORDER BY c.issued_at DESC, c.command_id DESC
                 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
  )
  UPDATE ottoq_vehicle_commands c
     SET status = 'refused', reason_code = 'superseded',
         confirmed_at = v_now, confirmed_by = 'otto_q_preflight_supersede',
         payload = c.payload || jsonb_build_object(
                     'refusal_reason',
                       CASE WHEN (sc.command_type, sc.stall_id)
                                 IS DISTINCT FROM (sc.cur_type, sc.cur_stall)
                            THEN 'superseded_by_newer_stall_command'
                            ELSE 'duplicate_reissue_of_in_flight_command' END,
                     'refused_at_clock', v_now)
    FROM stall_cmds sc
   WHERE c.command_id = sc.command_id
     AND ( (sc.command_type, sc.stall_id) IS DISTINCT FROM (sc.cur_type, sc.cur_stall)
           OR sc.dup_rn > 1 );

  FOR v_rec IN
    SELECT c.command_id AS command_id, c.vehicle_id, c.command_type, c.payload, c.sim_run_id, c.issued_at,
           v.current_state, v.current_stall_id, v.current_soc
      FROM ottoq_vehicle_commands c
      JOIN vehicles v ON v.id = c.vehicle_id
     WHERE c.sim_run_id = p_sim_run_id
       AND c.status = 'issued'
     ORDER BY c.issued_at
  LOOP
   -- ═══════ ONE BAD COMMAND MUST NEVER TAKE DOWN THE WORLD ═══════
   -- This seam has aborted ottoq_sim_advance_tick_world three times now (42703 on a
   -- column that does not exist, 22P02 on a non-enum label, 23505 on seat exclusivity),
   -- and every time the metronome swallowed it as a RAISE WARNING while cron reported
   -- success, so the depot sat frozen and looked healthy. Each command is now its own
   -- subtransaction: a command that cannot be executed is REFUSED and the tick carries
   -- on. Refusal is already a first-class outcome here, so this adds no new vocabulary.
   BEGIN
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
          -- 0039 completion: a stall already holding THIS vehicle is not unavailable
          -- to it. Without this the engine re-issued begin_charge every tick for a car
          -- it had already seated and refused itself: 303 self-refusals in one run.
          AND (s.current_vehicle_id IS NULL OR s.current_vehicle_id = v_rec.vehicle_id)
          AND (s.reserved_by IS NULL OR s.reserved_by = v_rec.vehicle_id
               OR s.reservation_expires_at <= v_now)
      ) INTO v_stall_ok;
    END IF;
    
    -- Check vehicle state compatibility
    CASE v_rec.command_type
      WHEN 'proceed_to_stall', 'begin_charge', 'enter_wash', 'enter_service' THEN
        -- Vehicle must not already be in a terminal state
        -- PRE-EXISTING DEFECT, FIXED HERE: current_state is the 17-label vehicle_state
        -- ENUM, and 'completed'/'dead' are not among its labels. Postgres therefore tried
        -- to cast the literal and raised 22P02, aborting the whole world tick -- the same
        -- failure shape as the leg_type abort: one unmapped word taking down every tick
        -- while cron reported success. Comparing as ::text makes this seam TOTAL: an
        -- unknown word can now only fail to match, never raise. Intent is unchanged.
        v_vehicle_ok := v_rec.current_state::text NOT IN ('deployed','en_route_to_depot','completed','dead');
      WHEN 'deploy', 'proceed_to_gate' THEN
        -- Vehicle must be ready to deploy
        v_vehicle_ok := v_rec.current_state::text IN ('staged_for_departure','staged_awaiting_service');
      ELSE
        v_vehicle_ok := true; -- fallback: allow unknown verbs
    END CASE;
    
    IF v_stall_ok AND v_vehicle_ok THEN
      -- Execute: null out old stall, occupy new one
      IF v_rec.payload ? 'stall_id' THEN
        UPDATE stalls SET current_vehicle_id = NULL, status = 'available'
         WHERE current_vehicle_id = v_rec.vehicle_id
           AND id <> (v_rec.payload->>'stall_id')::uuid;
        
        -- PRE-EXISTING DEFECT, FIXED HERE: this read `WHERE command_id = ...`, copied from
        -- the two `UPDATE ottoq_vehicle_commands ... WHERE command_id = v_rec.command_id`
        -- statements below. public.stalls has no command_id column, so EVERY execution of
        -- this branch raised 42703 -- which aborted ottoq_sim_advance_tick_world, which the
        -- metronome swallows as a RAISE WARNING while cron still reports success. Observed
        -- live: run 1a1b43d9 sat at tick_count = 1 for 45 minutes with next_tick_due_at
        -- still advancing. The sibling UPDATE directly above keys the same value on `id`.
        UPDATE stalls SET current_vehicle_id = v_rec.vehicle_id, status = 'occupied'
         WHERE id = (v_rec.payload->>'stall_id')::uuid;
      END IF;

      -- ═══════════ 0039 COMPLETION: A CONFIRMED COMMAND CHANGES THE VEHICLE ═══════════
      -- Migration 0039 moved the state write out of ottoq_decide_tick and into "the twin
      -- on command confirmation" -- and this function never implemented that half. It had
      -- no UPDATE vehicles at all. So a confirmed begin_charge seated the car in the stall
      -- but never made it charging_dcfc, and twin.ottoq_sim_reconcile_charge_sessions only
      -- opens a session for a vehicle ALREADY in charging_dcfc/charging_l2. The chain was
      -- cut in the middle: measured 135 begin_charge executed, 0 ocpp_sessions.
      -- It stayed invisible because this function raised 42703 on every stall-bearing
      -- command, so the tick died before anyone could observe the omission.
      --
      -- The contract is not inferred -- ottoq_decide_tick writes the target state INTO the
      -- payload as 'new_state' (charging_dcfc / charging_l2). Where an older emitter omits
      -- it, it is derived with that same expression rather than invented.
      v_new_state := NULLIF(v_rec.payload->>'new_state','');
      IF v_new_state IS NULL THEN
        v_new_state := CASE v_rec.command_type
          WHEN 'begin_charge'  THEN CASE WHEN COALESCE(v_rec.payload->>'stall_type','') = 'dcfc'
                                         THEN 'charging_dcfc' ELSE 'charging_l2' END
          WHEN 'enter_wash'    THEN CASE WHEN COALESCE(v_rec.payload->>'purpose','wash') = 'detail'
                                         THEN 'in_detail_bay' ELSE 'in_wash_bay' END
          WHEN 'enter_service' THEN 'in_service_bay'
          ELSE NULL          -- stage / hold / dispatch / proceed_to_stall carry no transition
        END;
      END IF;

      -- TOTAL FUNCTION. vehicle_state is a closed 17-label enum; an unlisted word must be
      -- unable to reach a cast. This is the same failure that took the tick down once
      -- already ('completed'/'dead' raising 22P02), so an unknown state is checked against
      -- pg_enum and simply skipped rather than risked.
      IF v_new_state IS NOT NULL
         AND EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                      WHERE t.typname = 'vehicle_state' AND e.enumlabel = v_new_state) THEN
        -- Deliberately AFTER the two stalls updates above: those release the old stall
        -- while the vehicle is still in a holding state, so trg_reassignment_guard sees
        -- nothing in progress and lets it go. Flipping the state first would make the
        -- guard treat the departure from the OLD stall as interrupting work.
        UPDATE vehicles
           SET current_state     = v_new_state::vehicle_state,
               last_state_change = v_now,
               current_stall_id  = CASE WHEN v_rec.payload ? 'stall_id'
                                        THEN (v_rec.payload->>'stall_id')::uuid
                                        ELSE current_stall_id END
         WHERE id = v_rec.vehicle_id;
      ELSIF v_rec.payload ? 'stall_id'
            AND v_rec.command_type IN ('proceed_to_stall','enter_wash','enter_service','begin_charge') THEN
        -- No mapped transition, but the car was told to stand somewhere. Keep the pointer
        -- truthful so the stall and the vehicle cannot disagree about where it is.
        UPDATE vehicles SET current_stall_id = (v_rec.payload->>'stall_id')::uuid
         WHERE id = v_rec.vehicle_id;
      END IF;
      
      UPDATE ottoq_vehicle_commands
         SET status = 'executed',
             confirmed_at = v_due,
             confirmed_by = CASE WHEN COALESCE((v_rec.payload->>'apply_required')::boolean, false)
                                 THEN 'twin_auto_tech' ELSE 'otto_q_preflight' END,
             executed_at = v_due
       WHERE command_id = v_rec.command_id;
      
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
       WHERE command_id = v_rec.command_id;
      
      v_refused := v_refused + 1;
    END IF;
   EXCEPTION WHEN OTHERS THEN
     -- Refuse THIS command, keep the world turning, and record what actually happened so
     -- the failure is visible instead of silent.
     BEGIN
       UPDATE ottoq_vehicle_commands
          SET status = 'refused',
              confirmed_at = v_now,
              confirmed_by = 'otto_q_preflight_error',
              reason_code = 'command_malformed',
              payload = payload || jsonb_build_object(
                          'refusal_reason', 'execution_error',
                          'sqlstate', SQLSTATE, 'sqlerrm', SQLERRM,
                          'refused_at_clock', v_now)
        WHERE command_id = v_rec.command_id;
     EXCEPTION WHEN OTHERS THEN NULL;
     END;
     v_refused := v_refused + 1;
     RAISE WARNING 'confirm_commands: refused % for vehicle % — % %',
       v_rec.command_type, v_rec.vehicle_id, SQLSTATE, SQLERRM;
   END;
  END LOOP;
  
  RETURN v_executed + v_refused;
END;
$function$

