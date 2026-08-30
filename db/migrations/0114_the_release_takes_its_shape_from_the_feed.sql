-- migration-version: 20260830130000
-- migration-name:    the_release_takes_its_shape_from_the_feed
-- 0114 -- closes the first known limitation named in db/checks/0047: ottoq_sim_release_depot
-- was written for sim-feed teardown and also RESETS THE PHYSICAL WORLD -- cancels the depot's
-- active charge sessions, clears stall occupancy, releases robotic tethers, and stands every
-- autonomous vehicle down to offline. Correct when the world is a fixture; a lie when the
-- world is real. A production session on an external-feed depot must be able to stop without
-- the ledger claiming 116 physical vehicles teleported offline.
--
-- THE SPLIT, read off the live function (md5 dc2043ad33e510bdc96d7e4706cff002):
--   RUN-SCOPED LEDGER CLOSURE (both modes -- the run is over in every world):
--     tallies -> archive -> bookings released -> legs amended/skipped -> commands expired
--     -> approvals expired -> dispatches completed -> run-scoped arm cycles abandoned
--     -> charger reconcile (already real-hardware-safe: its orphan sweep is guarded
--        id_token LIKE 'TWIN-%', and its other steps only reconcile ledger to reality).
--   PHYSICAL WORLD RESET (sim feed only -- the fixture resets to empty):
--     active ocpp_sessions cancelled ('sim_reset') -> stall occupancy cleared -> robotic
--     tethers released -> vehicles stood down to offline/unstalled -> depot-wide arm sweep.
--   IN BETWEEN, two claims the run owns even over a real world:
--     stall RESERVATIONS (reserved_by/reservation_expires_at) are the run's calendar
--     claims and die with it; physical occupancy (current_vehicle_id) is not ours.
--     PLAN RESIDUE on vehicle config (the 0093 five-plus keys) is engine-written plan
--     state and is stripped in both modes; current_state/current_stall_id are not.
--
-- The gate is depots.feed_mode = 'sim' (CHECK-constrained to {sim, external}) -- the same
-- gate twin.ottoq_world_advance uses for every synthetic phase. Signature unchanged
-- (two args), so every caller -- sim stops, the governor, the 0103 natural-completion
-- finalizer, production_stop -- takes the right shape automatically, and no overload is
-- created. Sim-feed behavior is byte-identical in effect (every gated branch takes the
-- v_world_reset=true path verbatim); the post-0114 determinism pair and the fork it caught
-- — pre-existing, unrelated to this change, fixed in 0115 — are db/checks/0046 pairs 17-18.
-- External-feed behavior is proven live on a throwaway rig depot in db/checks/0048.

-- ---- 0. pin: abort if the live function is not the one this file was written against ----
DO $pin$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO STRICT v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  IF v_md5 <> 'dc2043ad33e510bdc96d7e4706cff002' THEN
    RAISE EXCEPTION '0114 abort: ottoq_sim_release_depot drifted (md5 %)', v_md5;
  END IF;
END
$pin$;

-- ---- 1. the function, re-created with the feed-mode split ----
CREATE OR REPLACE FUNCTION public.ottoq_sim_release_depot(p_sim_run_id uuid, p_reason text DEFAULT 'operator_stop'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_veh int := 0; v_sess int := 0; v_archive jsonb;
        v_feed text; v_world_reset boolean; v_residue int := 0;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'run not found');
  END IF;

  -- 0114: the release takes its shape from the depot's feed. A sim-feed world is a
  -- fixture and resets to empty; an external-feed world is reality -- the run's ledgers
  -- close, but nothing physical is touched. Same gate world_advance uses per phase.
  SELECT COALESCE(d.feed_mode, 'sim') INTO v_feed FROM depots d WHERE d.id = v_depot;
  v_feed := COALESCE(v_feed, 'sim');
  v_world_reset := (v_feed = 'sim');

  -- Truthful tallies for the flight recorder. Best-effort: a slow count must not
  -- cost us the teardown, and the run is already stopped either way.
  BEGIN
    UPDATE ottoq_sim_runs SET
        charge_sessions    = (SELECT count(*) FROM ocpp_sessions WHERE sim_run_id = p_sim_run_id),
        events_generated   = (SELECT count(*) FROM ottoq_events  WHERE sim_run_id = p_sim_run_id),
        -- 0087: settlement-grade definition -- one completed task, one SDR. The old
        -- expression counted twin.service_completed events: 9 on a run with 65 settled
        -- operations, a headline matching no ledger.
        tasks_completed    = (SELECT count(*) FROM ottoq_service_detail_records
                                WHERE sim_run_id = p_sim_run_id),
        vehicles_simulated = (SELECT count(DISTINCT vehicle_id) FROM ottoq_telemetry_packets
                                WHERE sim_run_id = p_sim_run_id)
     WHERE sim_run_id = p_sim_run_id;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot tallies: %', SQLERRM; END;

  BEGIN v_archive := ottoq_archive_run(p_sim_run_id, p_reason);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot archive: %', SQLERRM; END;

  -- 0114: sim only. An external feed's active sessions are real charging on real
  -- hardware; reality ends them, and the orchestrator's exit must not.
  IF v_world_reset THEN
    UPDATE ocpp_sessions SET status='cancelled', ended_at=now(),
           stopped_reason='sim_reset', updated_at=now()
     WHERE depot_id = v_depot AND status='active';
    GET DIAGNOSTICS v_sess = ROW_COUNT;
  END IF;

  BEGIN
    UPDATE ottoq_stall_bookings
       SET state='released', released_at=now(), release_reason='run_stopped'
     WHERE sim_run_id = p_sim_run_id AND state IN ('held','active');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot booking release: %', SQLERRM; END;

  -- 0089: a run that ends leaves no leg open. In-flight work closes 'amended' (it
  -- happened; it did not finish -- never 'done', settlement is only for completed
  -- operations, so no SDR fires) and never-started work closes 'skipped', both
  -- stamped with the run's final sim clock. 30 legs on 9291ec6d sat 'active' forever.
  BEGIN
    UPDATE ottoq_itinerary_legs l
       SET status = 'amended',
           actual_end_sim = COALESCE(l.actual_end_sim,
             (SELECT COALESCE(r.sim_clock_current, now()) FROM ottoq_sim_runs r
               WHERE r.sim_run_id = p_sim_run_id))
     WHERE l.sim_run_id = p_sim_run_id AND l.status = 'active';
    UPDATE ottoq_itinerary_legs l
       SET status = 'skipped'
     WHERE l.sim_run_id = p_sim_run_id AND l.status = 'planned';
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot leg close: %', SQLERRM; END;

  -- 0087: a run that ends leaves no command dangling. 18 final-second stage commands
  -- on 9291ec6d stayed 'issued' forever; the vehicles they addressed are stood down
  -- to offline below, so nothing could ever have reacted.
  UPDATE ottoq_vehicle_commands
     SET status='expired', reason_code='run_ended',
         confirmed_at=now(), confirmed_by='run_finalizer',
         payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('expired_reason','run_ended_before_reaction')
   WHERE sim_run_id = p_sim_run_id AND status IN ('issued','confirmed');

  -- 0097: no approval outlives its run. Readers filter on vehicle/type/status only,
  -- so a surviving 'approved' row is readable by the NEXT run's gates -- the tick-2
  -- divergence channel of the 0046 determinism pair. Prior status kept in payload.
  BEGIN
    UPDATE ottoq_ops_approvals
       SET payload = COALESCE(payload,'{}'::jsonb)
                     || jsonb_build_object('expired_from', status,
                                           'expired_reason', 'run_ended'),
           status = 'expired',
           decided_at = COALESCE(decided_at, now()),
           decided_by = COALESCE(decided_by, 'run_finalizer')
     WHERE sim_run_id = p_sim_run_id AND status IN ('pending','approved');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot approval expiry: %', SQLERRM; END;

  UPDATE ottoq_vehicle_dispatches
     SET status='completed',
         actual_return_at = COALESCE(actual_return_at, now()),
         return_trigger   = COALESCE(return_trigger, 'run_stopped')
   WHERE sim_run_id = p_sim_run_id AND status IN ('active','returning');

  -- Predicate narrowed to rows that are actually dirty. The original rewrote every
  -- stall in the depot, and each no-op UPDATE still fires the stall trigger.
  IF v_world_reset THEN
    UPDATE stalls SET current_vehicle_id=NULL, reserved_by=NULL, reservation_expires_at=NULL
     WHERE depot_id = v_depot
       AND (current_vehicle_id IS NOT NULL OR reserved_by IS NOT NULL
            OR reservation_expires_at IS NOT NULL);
  ELSE
    -- 0114 ledger-only: a reservation is the run's calendar claim and dies with it;
    -- current_vehicle_id is physical occupancy and is not ours to erase.
    UPDATE stalls SET reserved_by=NULL, reservation_expires_at=NULL
     WHERE depot_id = v_depot
       AND (reserved_by IS NOT NULL OR reservation_expires_at IS NOT NULL);
  END IF;

  -- ═══════ THE ARM LETS GO WHEN THE RUN DOES -- AND IT GOES FIRST ═══════
  -- HOISTED ABOVE THE VEHICLE RESET 2026-08-13. The reset below clears
  -- current_stall_id, and the arm interlock trigger refuses to move a car out of
  -- its stall while the tether still names one. Clearing the tether afterwards
  -- meant every teardown raised. Letting go before standing the cars down is also
  -- simply the right order.
  -- The tether is a SIM-CLOCK deadline, so a run stopped at sim 19:30 leaves
  -- deadlines in the future of any run that starts at 06:00 — and
  -- ottoq_release_expired_tethers correctly refuses to clear something that has
  -- not expired. Left alone, the next run inherits cars its own gate calls
  -- immovable. Keyed on the tether itself, NOT on vehicle state: the reset above
  -- skips rows already 'offline', and an offline car can still be holding one.
  -- 0114: sim only. On an external feed the tether mirrors a real latch on a real
  -- arm; only real events release it.
  IF v_world_reset THEN
    BEGIN
      UPDATE vehicles
         SET robotic_tether_until = NULL, robotic_tether_stall_id = NULL,
             robotic_tether_direction = NULL, robotic_tether_phase = NULL
       WHERE current_depot_id = v_depot
         AND (robotic_tether_until IS NOT NULL OR robotic_tether_stall_id IS NOT NULL);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot tether release: %', SQLERRM; END;
  END IF;

  IF v_world_reset THEN
    UPDATE vehicles
       SET current_state='offline'::vehicle_state, current_stall_id=NULL,
           last_state_change=now(),
           -- 0093: a run that ends leaves no plan residue on the fleet. These five keys
           -- are run-generated plan state (measured bleeding into the next run).
           config = (COALESCE(config,'{}'::jsonb) - 'svc_step' - 'service_ends_at'
                     - 'service_manifest' - 'service_manifest_meta' - 'charge_plan'
                     - 'deferred_services' - 'draining_item')
     WHERE current_depot_id = v_depot AND category='autonomous'
       AND current_state <> 'offline'::vehicle_state;
    GET DIAGNOSTICS v_veh = ROW_COUNT;
  ELSE
    -- 0114 ledger-only: the 0093 guarantee holds in both modes -- no plan residue
    -- outlives its run -- but current_state and current_stall_id belong to the feed.
    UPDATE vehicles
       SET config = (COALESCE(config,'{}'::jsonb) - 'svc_step' - 'service_ends_at'
                     - 'service_manifest' - 'service_manifest_meta' - 'charge_plan'
                     - 'deferred_services' - 'draining_item')
     WHERE current_depot_id = v_depot AND category='autonomous'
       AND config ?| ARRAY['svc_step','service_ends_at','service_manifest',
                           'service_manifest_meta','charge_plan','deferred_services','draining_item'];
    GET DIAGNOSTICS v_residue = ROW_COUNT;
  END IF;

  -- Open arm cycles are closed as ABANDONED rather than deleted: the run
  -- happened, and a cycle that was in flight when the world stopped is a true
  -- record of a mate that never finished. Inventing 'latched' would be a lie and
  -- deleting it would erase the evidence.
  -- 0114: the run's own cycles close as abandoned in both modes (their orchestrator
  -- is gone); the DEPOT-WIDE sweep is a fixture-teardown affordance, sim only.
  BEGIN
    UPDATE twin.arm_cycles
       SET ended_at = COALESCE(ended_at, now()), outcome = COALESCE(outcome, 'abandoned')
     WHERE ended_at IS NULL
       AND (sim_run_id = p_sim_run_id OR (v_world_reset AND depot_id = v_depot));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot arm cycle close: %', SQLERRM; END;

  -- Real-hardware-safe by construction (orphan sweep is id_token LIKE 'TWIN-%' only;
  -- the stall/charger steps reconcile ledger to physical reality): both modes.
  BEGIN PERFORM ottoq_reconcile_charger_states(v_depot);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot charger reconcile: %', SQLERRM; END;

  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='otto_twin',
      p_event_type:='twin.sim_stopped_and_reset', p_entity_type:='sim_run',
      p_entity_id:=p_sim_run_id, p_depot_id:=v_depot,
      p_payload:=jsonb_build_object('reason',p_reason,'vehicles_reset',v_veh,'sessions_ended',v_sess,
                                    'feed_mode',v_feed,
                                    'release_mode', CASE WHEN v_world_reset THEN 'world_reset' ELSE 'ledger_only' END,
                                    'vehicles_residue_stripped',v_residue),
      p_severity:='info', p_ingest_source:='twin', p_data_source:='twin',
      p_sim_run_id:=p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release_depot event: %', SQLERRM; END;

  RETURN jsonb_build_object('ok',true,'stopped',p_sim_run_id,
    'release_mode', CASE WHEN v_world_reset THEN 'world_reset' ELSE 'ledger_only' END,
    'feed_mode', v_feed, 'depot_reset_to_empty', v_world_reset,
    'vehicles_unplaced',v_veh,'vehicles_residue_stripped',v_residue,
    'sessions_ended',v_sess,'blackbox_ready',true,
    'archived', COALESCE(v_archive->>'ok','false')::boolean,
    'reproducible_from', v_archive->'reproducible_from');
END;
$function$;

-- ---- 2. post-conditions: exactly one function (no overload), and the split is in it ----
DO $post$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0114 abort: expected 1 ottoq_sim_release_depot, found % (overload created?)', v_n;
  END IF;
  SELECT pg_get_functiondef(p.oid) INTO STRICT v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  IF position('the release takes its shape from the depot''s feed' in v_src) = 0
     OR position('ledger_only' in v_src) = 0 THEN
    RAISE EXCEPTION '0114 abort: rewrite did not survive';
  END IF;
  RAISE NOTICE '0114 applied: sim feed resets the fixture; external feed closes the ledgers and leaves the world alone.';
END
$post$;
