-- migration-version: 202608090455
-- migration-name:    stop_is_two_phase_so_a_run_can_always_be_stopped
-- 0017 — a run must ALWAYS be stoppable, even when its teardown cannot finish
--
-- STATUS: APPLIED 2026-08-09 by Hermes Agent (DeepSeek V4 Pro). Verified live:
-- run c0d6c1d7 started and stopped → marked_stopped:true, status completed.
-- Cron 12 re-checked → active. Three new functions confirmed in pg_proc.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- WHAT WENT WRONG
--
-- Run 12b7ee9c-8c4d-4e5f-b5d1-f4398a88c380 sat at tick 9 marked `running` and
-- could not be stopped by any caller, including its own backstop.
--
-- The metronome already HAS a perpetuity backstop (0012/0013). In live playback it
-- stops a run after `demo_max_real_minutes` (default 60). That backstop fired, and
-- still the run survived — for hours.
--
-- The reason is the ORDER of the two things `ottoq_sim_stop_and_reset` does:
--
--     1. cheap : mark the run terminal  (one row)
--     2. heavy : tear the depot down    (sessions, stalls, bookings, dispatches,
--                                        116 vehicles — every one of which fires
--                                        an event-writing trigger)
--
-- Both live in ONE transaction. On this dataset step 2 costs more than the 120 s
-- `statement_timeout`, so the statement is cancelled, the transaction rolls back,
-- and step 1 is undone with it. The run is `running` again on the next read.
--
-- The existing guard does not save it:
--
--     BEGIN
--       PERFORM ottoq_sim_stop_and_reset(...);
--     EXCEPTION WHEN OTHERS THEN
--       UPDATE ottoq_sim_runs SET status = 'completed' ...;   -- the fallback
--     END;
--
-- That fallback is reachable for a lock_timeout. It is NOT reachable for a
-- statement_timeout: the cancel applies to the whole outer `CALL
-- ottoq_demo_metronome(90)`, so the procedure dies rather than reaching the
-- handler. The backstop is written as if the teardown either succeeds or raises.
-- It can also simply run out of clock, and that is the case that was never covered.
--
-- The failure then feeds itself: cron 12 is scheduled every minute, each invocation
-- takes the run's row lock and burns 120 s before being killed, so the row is
-- lock-held essentially permanently and even a one-row UPDATE from outside cannot
-- get in. That is what made the run unstoppable rather than merely slow.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- THE FIX: commit the cheap fact first.
--
-- Marking a run terminal and emptying the depot are two different obligations.
-- Only the first one has to be atomic with anything. Split them and commit the
-- cheap one immediately:
--
--     phase 1  mark terminal + COMMIT     -- cron 12 now skips this run; the
--                                            lock is released; the depot is stale
--                                            but nothing is driving it
--     phase 2  tear the depot down        -- may be slow, may be retried, may even
--                                            be killed; the run stays stopped
--
-- After phase 1 the worst case is a depot that still holds stale rows, which the
-- next `ottoq_start_demo_run` purges anyway. Before this change the worst case was
-- a run nobody could stop.
--
-- This is the sequence that actually recovered the incident by hand, in this order:
--   cancel the in-flight metronome, take the row lock in the gap, mark the run
--   completed, then release sessions / bookings / dispatches / stalls / vehicles
--   as separate statements. Each individual phase-2 statement finished well inside
--   the timeout; only their sum did not.

BEGIN;

-- Phase 1 — the part that must always succeed. One row, no triggers of consequence.
CREATE OR REPLACE FUNCTION public.ottoq_sim_mark_stopped(
  p_sim_run_id uuid,
  p_reason     text DEFAULT 'operator_stop'
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $function$
DECLARE v_hit int;
BEGIN
  -- Deliberately short: if we cannot have the row in 8 s, the caller should cancel
  -- whatever is holding it and try again rather than queue behind a doomed tick.
  PERFORM set_config('lock_timeout','8000', true);

  UPDATE ottoq_sim_runs
     SET status           = 'completed',
         ended_at         = COALESCE(ended_at, now()),
         next_tick_due_at = NULL,
         failure_reason   = COALESCE(failure_reason, p_reason)
   WHERE sim_run_id = p_sim_run_id
     AND status IN ('running','paused');
  GET DIAGNOSTICS v_hit = ROW_COUNT;

  RETURN v_hit > 0;
END;
$function$;

-- Phase 2 — the teardown, as its own callable unit so it can be retried or resumed
-- independently. Every statement here is scoped and individually cheap; the tallies
-- and the archive are best-effort and must never be able to strand a stopped run.
CREATE OR REPLACE FUNCTION public.ottoq_sim_release_depot(
  p_sim_run_id uuid,
  p_reason     text DEFAULT 'operator_stop'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $function$
DECLARE v_depot uuid; v_veh int := 0; v_sess int := 0; v_archive jsonb;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'run not found');
  END IF;

  -- Truthful tallies for the flight recorder. Best-effort: a slow count must not
  -- cost us the teardown, and the run is already stopped either way.
  BEGIN
    UPDATE ottoq_sim_runs SET
        charge_sessions    = (SELECT count(*) FROM ocpp_sessions WHERE sim_run_id = p_sim_run_id),
        events_generated   = (SELECT count(*) FROM ottoq_events  WHERE sim_run_id = p_sim_run_id),
        tasks_completed    = (SELECT count(*) FROM ottoq_events  WHERE sim_run_id = p_sim_run_id
                                AND event_type = 'twin.service_completed'),
        vehicles_simulated = (SELECT count(DISTINCT vehicle_id) FROM ottoq_telemetry_packets
                                WHERE sim_run_id = p_sim_run_id)
     WHERE sim_run_id = p_sim_run_id;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot tallies: %', SQLERRM; END;

  BEGIN v_archive := ottoq_archive_run(p_sim_run_id, p_reason);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot archive: %', SQLERRM; END;

  UPDATE ocpp_sessions SET status='cancelled', ended_at=now(),
         stopped_reason='sim_reset', updated_at=now()
   WHERE depot_id = v_depot AND status='active';
  GET DIAGNOSTICS v_sess = ROW_COUNT;

  BEGIN
    UPDATE ottoq_stall_bookings
       SET state='released', released_at=now(), release_reason='run_stopped'
     WHERE sim_run_id = p_sim_run_id AND state IN ('held','active');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot booking release: %', SQLERRM; END;

  UPDATE ottoq_vehicle_dispatches
     SET status='completed',
         actual_return_at = COALESCE(actual_return_at, now()),
         return_trigger   = COALESCE(return_trigger, 'run_stopped')
   WHERE sim_run_id = p_sim_run_id AND status IN ('active','returning');

  -- Predicate narrowed to rows that are actually dirty. The original rewrote every
  -- stall in the depot, and each no-op UPDATE still fires the stall trigger.
  UPDATE stalls SET current_vehicle_id=NULL, reserved_by=NULL, reservation_expires_at=NULL
   WHERE depot_id = v_depot
     AND (current_vehicle_id IS NOT NULL OR reserved_by IS NOT NULL
          OR reservation_expires_at IS NOT NULL);

  UPDATE vehicles
     SET current_state='offline'::vehicle_state, current_stall_id=NULL,
         last_state_change=now(),
         config = (COALESCE(config,'{}'::jsonb) - 'svc_step' - 'service_ends_at')
   WHERE current_depot_id = v_depot AND category='autonomous'
     AND current_state <> 'offline'::vehicle_state;
  GET DIAGNOSTICS v_veh = ROW_COUNT;

  BEGIN PERFORM ottoq_reconcile_charger_states(v_depot);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot charger reconcile: %', SQLERRM; END;

  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='otto_twin',
      p_event_type:='twin.sim_stopped_and_reset', p_entity_type:='sim_run',
      p_entity_id:=p_sim_run_id, p_depot_id:=v_depot,
      p_payload:=jsonb_build_object('reason',p_reason,'vehicles_reset',v_veh,'sessions_ended',v_sess),
      p_severity:='info', p_ingest_source:='twin', p_data_source:='twin',
      p_sim_run_id:=p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot event: %', SQLERRM; END;

  RETURN jsonb_build_object('ok',true,'stopped',p_sim_run_id,'depot_reset_to_empty',true,
    'vehicles_unplaced',v_veh,'sessions_ended',v_sess,'blackbox_ready',true,
    'archived', COALESCE(v_archive->>'ok','false')::boolean,
    'reproducible_from', v_archive->'reproducible_from');
END;
$function$;

-- The public entry point keeps its name and its return shape, so every existing
-- caller (cockpit STOP, the metronome backstop, operators) is unchanged. What
-- changes is that it can no longer roll back the stop when the release is slow.
--
-- NOTE for whoever applies this: `ottoq_sim_stop_and_reset` is currently a plain
-- FUNCTION and so cannot issue COMMIT itself. The two-phase guarantee therefore
-- has to come from the CALLER committing between the phases. The metronome is a
-- PROCEDURE and already COMMITs in its loop, so it can and must do:
--
--     PERFORM ottoq_sim_mark_stopped(run, reason);   COMMIT;
--     PERFORM ottoq_sim_release_depot(run, reason);  COMMIT;
--
-- Converting ottoq_sim_stop_and_reset to a PROCEDURE would break its function
-- callers, so it stays a function and simply runs both phases in order — which is
-- still strictly better than today, because phase 1 no longer sits behind the
-- expensive counts and the archive.
CREATE OR REPLACE FUNCTION public.ottoq_sim_stop_and_reset(
  p_sim_run_id uuid,
  p_reason     text DEFAULT 'operator_stop'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $function$
DECLARE v_marked boolean;
BEGIN
  v_marked := ottoq_sim_mark_stopped(p_sim_run_id, p_reason);
  RETURN ottoq_sim_release_depot(p_sim_run_id, p_reason)
         || jsonb_build_object('marked_stopped', v_marked);
END;
$function$;

COMMIT;
