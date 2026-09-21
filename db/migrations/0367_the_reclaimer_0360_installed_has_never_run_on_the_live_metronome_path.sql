-- migration-version: 20260920041500
-- migration-name:    the_reclaimer_0360_installed_has_never_run_on_the_live_metronome_path
-- ════════════════════════════════════════════════════════════════════════════
-- 0367  THE RECLAIMER 0360 INSTALLED HAS NEVER RUN: THE LIVE METRONOME DOES NOT
--       CALL THE FUNCTION IT WAS WIRED INTO.
--
--       forces_recert TRUE -- it changes what ottoq_sim_decide_and_dispatch does
--       on every tick of every arm.
-- ════════════════════════════════════════════════════════════════════════════
--
-- G82. 0360 (applied 20260920022145) added `ottoq_release_unusable_reservations`
-- and wired it into `public.ottoq_sim_advance_tick`, one line above
-- `ottoq_sim_decide_and_dispatch`. **`ottoq_demo_metronome` -- cron job 12, the
-- live simulation engine -- calls `ottoq_sim_advance_tick_world` and
-- `ottoq_sim_decide_and_dispatch` DIRECTLY** (its own source, lines 100 and 108)
-- and never calls `ottoq_sim_advance_tick` at all. So the reclaimer has never run
-- on a metronome-driven run. G77's pattern -- the right routine with no live
-- caller -- reproduced inside the migration that was fixing G77.
--
-- AND NOTE HOW THE WIRING CHECK WAS FOOLED, because it is the third instance of
-- one mistake class in this repo. `position('ottoq_sim_advance_tick' in prosrc)`
-- returned 4179 for `ottoq_demo_metronome` and was read as "the metronome calls
-- advance_tick". It does not: 4179 is the offset of
-- `ottoq_sim_advance_tick_world`, of which the searched name is a PREFIX. Same
-- family as the `_`-is-a-LIKE-wildcard trap. A caller check must match the call
-- syntax -- `ottoq_sim_advance_tick(` -- not the bare name.
--
-- WHAT THIS COST, MEASURED ON LIVE RUN 3fb415d8-3e06-4084-9436-7248f6c40449
-- (cuOpt-only arm, seed 777777, busy_day, twin depot per rule 8):
--
--   ottoq.refusal_escalated events                              346
--     of which reason_code='no_capacity' after target_occupied   296  (86%)
--   release-eligible reservations standing right now              38
--     stable across a tick boundary (tick 1123 -> 1124)          38 -> 38
--   DCFC stalls the reroute walk found calendar-free              4
--     of those 4, unclaimed by reservation or vehicle             0
--
-- The causal chain, and the reason this is the whole "rejection -> re-solve"
-- question rather than a hygiene item: the loop ALREADY EXISTS and already runs.
-- `ottoq.ottoq_react_to_refusals` is called from decide_and_dispatch line 121;
-- on a refused `proceed_to_stall`/`begin_charge`/`stage` it walks up to 25
-- calendar-free stalls, reserves, books, and re-emits the command with
-- `reroute_after`. It escalates to `no_capacity` only when every candidate fails
-- `ottoq_reserve_stall`. With the reclaimer dark, all four calendar-free DCFC
-- stalls carried a reservation 36-45 sim-minutes past its own expiry -- two of
-- them holding NO vehicle at all. So the reroute had four legal moves and was
-- refused all four by expired pointers. **Nothing needs to be built here. The
-- loop needed a world that tells it the truth.**
--
-- A SECOND DEFECT, FOUND WHILE PROVING THE FIRST, AND IT WOULD HAVE HIDDEN THIS
-- ONE AGAIN. Invoked directly, the reclaimer returns
-- `{"ok": false, "msg": "deadlock detected", "sqlstate": "40P01", "released": 0}`.
-- 0360 made it swallow its own errors -- correct, because a failure on the tick
-- path must never abort the tick (APPLYING.md) -- but the call site is a bare
-- `PERFORM`, so the JSON is discarded and a reclaimer that releases NOTHING is
-- indistinguishable from one that had nothing to release. Part A fixes both
-- halves: `FOR UPDATE ... SKIP LOCKED` so the reclaimer can never be a deadlock
-- participant (it declines contended rows and takes them on a later tick), and an
-- `eligible` count plus a `ottoq.reservation_reclaim_blocked` event so "ran and
-- found nothing" is never again the same observation as "ran and could take
-- nothing".
--
-- Read `db/checks/0258` for the after-measurement. Scope: twin depot
-- 11111111-1111-1111-1111-111111111111 only, per CLAUDE.md rule 8.

-- ══ P0. THE DEFECT ITSELF: THE LIVE METRONOME DOES NOT CALL advance_tick ═════
DO $p0$
DECLARE
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_demo_metronome';
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'P0: ottoq_demo_metronome not found';
  END IF;
  --: match the CALL, not the bare name -- the prefix trap this migration exists for
  IF position('ottoq_sim_advance_tick(' in v_src) > 0 THEN
    RAISE EXCEPTION 'P0: the metronome DOES call advance_tick -- 0360 was on the live path after all; re-diagnose before applying this';
  END IF;
  IF position('ottoq_sim_decide_and_dispatch(' in v_src) = 0 THEN
    RAISE EXCEPTION 'P0: the metronome does not call decide_and_dispatch either; this migration wires the wrong function';
  END IF;
  RAISE NOTICE 'P0 ok: metronome calls decide_and_dispatch and not advance_tick';
END $p0$;

-- ══ P1. THE RECLAIMER EXISTS WITH THE SIGNATURE PART A REPLACES ═════════════
DO $p1$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'ottoq_release_unusable_reservations'
       AND pg_get_function_identity_arguments(p.oid)
           = 'p_sim_run_id uuid, p_sim_clock timestamp with time zone, p_depot_id uuid')
  THEN
    RAISE EXCEPTION 'P1: ottoq_release_unusable_reservations(uuid, timestamptz, uuid) not found as 0360 left it';
  END IF;
  RAISE NOTICE 'P1 ok';
END $p1$;

-- ══ P2. THE INSERTION ANCHOR IS UNIQUE IN decide_and_dispatch ═══════════════
DO $p2$
DECLARE
  v_src text; v_n int;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_decide_and_dispatch';
  v_n := (length(v_src) - length(replace(v_src, 'IF v_run.policy IS NULL OR v_run.policy = ''otto_q'' THEN', ''))) 
         / length('IF v_run.policy IS NULL OR v_run.policy = ''otto_q'' THEN');
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'P2: policy-branch anchor occurs % times, expected 1 -- the generated Part B was built against a different body', v_n;
  END IF;
  IF position('ottoq_release_unusable_reservations' in v_src) > 0 THEN
    RAISE EXCEPTION 'P2: decide_and_dispatch already calls the reclaimer; this migration has already been applied';
  END IF;
  IF position('ottoq_react_to_refusals' in v_src) = 0 THEN
    RAISE EXCEPTION 'P2: the refusal reactor is not in decide_and_dispatch -- the causal chain this migration rests on is wrong';
  END IF;
  RAISE NOTICE 'P2 ok';
END $p2$;

-- ══ P3. THERE IS SOMETHING TO RECLAIM (the defect is live, not historical) ══
DO $p3$
DECLARE
  v_eligible bigint;
BEGIN
  SELECT count(*) INTO v_eligible
    FROM public.stalls s
    LEFT JOIN public.vehicles v ON v.id = s.reserved_by
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
     AND s.reserved_by IS NOT NULL
     AND s.current_vehicle_id IS DISTINCT FROM s.reserved_by
     AND ( v.current_state::text = ANY (ARRAY['tow_requested','staged_for_departure',
                                              'en_route_to_deployment','out_of_service'])
        OR (s.reservation_expires_at IS NOT NULL
            AND s.reservation_expires_at < (SELECT COALESCE(r.sim_clock_current, r.sim_clock_start)
                                              FROM public.ottoq_sim_runs r
                                             WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
                                               AND r.status = 'running'
                                             ORDER BY r.started_at DESC LIMIT 1)) );
  --: NOT a failure when zero: no run may be live. Recorded either way so the
  --: before-picture is in the migration that changed it.
  RAISE NOTICE 'P3: release-eligible reservations on the twin depot right now = %', v_eligible;
END $p3$;

-- ══ PART A. THE RECLAIMER, DEADLOCK-PROOF AND NO LONGER SILENT ══════════════
--
-- Three changes from 0360, and nothing else:
--   1. `FOR UPDATE OF s SKIP LOCKED` in a deterministic id order. A best-effort
--      reclaimer must never wait and never be a deadlock participant; a stall
--      another transaction holds is simply left for the next tick. This is what
--      makes the 40P01 above impossible rather than handled.
--   2. `eligible` is counted WITHOUT locking, so `eligible > 0 AND released = 0`
--      is a reportable state rather than an invisible one.
--   3. That state emits `ottoq.reservation_reclaim_blocked` (registered in
--      Part C), inside its own handler so the alarm can never break the tick.
--
-- The safety invariant is unchanged and load-bearing: a stall whose reservation
-- holder is physically in it is NEVER released (CLAUDE.md rule 6 -- assignment
-- plus verification, always).
CREATE OR REPLACE FUNCTION public.ottoq_release_unusable_reservations(
  p_sim_run_id uuid,
  p_sim_clock  timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_depot_id   uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clock     timestamptz;
  v_depot     uuid;
  v_eligible  bigint := 0;
  v_by_state  bigint := 0;
  v_by_expiry bigint := 0;
  v_rec       RECORD;
BEGIN
  --: NEVER now(). reservation_expires_at is a SIM-clock column (G77), and the
  --: fallback chain ends at the run's own start rather than a wall clock -- the
  --: pattern 0357 installed in ottoq_sim_release_depot.
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, r.sim_clock_start),
         COALESCE(p_depot_id, r.depot_id)
    INTO v_clock, v_depot
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;

  v_clock := COALESCE(v_clock, p_sim_clock);
  v_depot := COALESCE(v_depot, p_depot_id);

  --: Refuse rather than guess. A reclaimer that cannot establish its own clock
  --: or scope must do nothing: releasing on a guessed clock is G77 again.
  IF v_clock IS NULL OR v_depot IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false, 'released', 0, 'eligible', 0,
      'reason', 'no sim clock or depot resolvable; refusing to guess');
  END IF;

  --: 0367: counted WITHOUT a lock, so "nothing to do" and "could take nothing"
  --: are different numbers. 0360 could not tell them apart and therefore
  --: reported a deadlock as silence.
  SELECT count(*) INTO v_eligible
    FROM public.stalls s
    LEFT JOIN public.vehicles v ON v.id = s.reserved_by
   WHERE s.depot_id = v_depot
     AND s.reserved_by IS NOT NULL
     AND s.current_vehicle_id IS DISTINCT FROM s.reserved_by
     AND ( v.current_state::text = ANY (ARRAY['tow_requested','staged_for_departure',
                                              'en_route_to_deployment','out_of_service'])
        OR (s.reservation_expires_at IS NOT NULL AND s.reservation_expires_at < v_clock) );

  --: SKIP LOCKED is the whole deadlock fix. Ordered by id so the lock order is
  --: at least stable for anything else that adopts the same order.
  FOR v_rec IN
    SELECT s.id AS stall_id,
           (v.current_state::text = ANY (ARRAY['tow_requested','staged_for_departure',
                                               'en_route_to_deployment','out_of_service'])) AS unusable_holder
      FROM public.stalls s
      LEFT JOIN public.vehicles v ON v.id = s.reserved_by
     WHERE s.depot_id = v_depot
       AND s.reserved_by IS NOT NULL
       --: THE SAFETY INVARIANT. A stall whose holder is physically in it is never
       --: released -- that would desync the calendar from physical reality, and
       --: both sides of that pair are load-bearing (CLAUDE.md rule 6).
       AND s.current_vehicle_id IS DISTINCT FROM s.reserved_by
       AND ( v.current_state::text = ANY (ARRAY['tow_requested','staged_for_departure',
                                                'en_route_to_deployment','out_of_service'])
          OR (s.reservation_expires_at IS NOT NULL AND s.reservation_expires_at < v_clock) )
     ORDER BY s.id
     FOR UPDATE OF s SKIP LOCKED
  LOOP
    UPDATE public.stalls s
       SET reserved_by            = NULL,
           reserved_at            = NULL,
           reservation_expires_at = NULL
     WHERE s.id = v_rec.stall_id;

    IF v_rec.unusable_holder THEN
      v_by_state := v_by_state + 1;
    ELSE
      --: expiry-only, so the two buckets sum to `released` without double count
      v_by_expiry := v_by_expiry + 1;
    END IF;
  END LOOP;

  --: THE ALARM. Eligible rows that none of which could be taken is the state
  --: 0360 could not report, and the state it was actually in for its whole life.
  IF v_eligible > 0 AND (v_by_state + v_by_expiry) = 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type   := 'ottoq_engine',
        p_actor_id     := 'reservation_reclaimer',
        p_event_type   := 'ottoq.reservation_reclaim_blocked',
        p_entity_type  := 'depot',
        p_entity_id    := v_depot,
        p_depot_id     := v_depot,
        p_payload      := jsonb_build_object('eligible', v_eligible, 'released', 0,
                                            'sim_clock', v_clock),
        p_severity     := 'warning',
        p_ingest_source := 'production',
        p_data_source  := CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END,
        p_sim_run_id   := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN jsonb_build_object(
    'ok',                 true,
    'eligible',           v_eligible,
    'released',           v_by_state + v_by_expiry,
    'skipped_locked',     GREATEST(v_eligible - (v_by_state + v_by_expiry), 0),
    'by_unusable_holder', v_by_state,
    'by_sim_expiry',      v_by_expiry,
    'sim_clock',          v_clock,
    'depot_id',           v_depot);

--: Total on its own account, not only behind the caller's handler. On the tick
--: path an unhandled error rolls back the whole tick and cron still reads
--: "succeeded" (APPLYING.md).
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'released', 0, 'eligible', v_eligible,
    'sqlstate', SQLSTATE, 'msg', left(SQLERRM, 200));
END;
$function$;

COMMENT ON FUNCTION public.ottoq_release_unusable_reservations(uuid, timestamptz, uuid) IS
'0360/0367. Releases stall reservations whose holder can no longer consume them '
'(tow_requested / staged_for_departure / en_route_to_deployment / out_of_service) '
'or that are past reservation_expires_at ON THE SIM CLOCK. Never releases a stall '
'whose reservation holder is physically in it. Takes rows FOR UPDATE SKIP LOCKED, '
'so it can never be a deadlock participant and never waits on the decide path; '
'contended rows are left for the next tick and counted in skipped_locked. Returns '
'eligible / released / skipped_locked so "nothing to do" is distinguishable from '
'"could take nothing" -- 0360 could not tell those apart and was silently '
'deadlocking on every call. Emits ottoq.reservation_reclaim_blocked when eligible '
'> 0 and released = 0. Called from ottoq_sim_decide_and_dispatch (the path the '
'live metronome uses) and from ottoq_sim_advance_tick.';
-- ══ PART B. THE WIRING, ON THE PATH THE METRONOME ACTUALLY CALLS ═══════════
-- Derived verbatim from pg_get_functiondef(ottoq_sim_decide_and_dispatch) with
-- one block inserted above the policy branch. NOT retyped -- 0360 Part C nearly
-- broke every tick because a signature was typed from memory.
CREATE OR REPLACE FUNCTION public.ottoq_sim_decide_and_dispatch(p_sim_run_id uuid)
 RETURNS TABLE(out_dispatched integer, out_charge_assigned integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_decide ottoq_decide_tick_result;
  v_is_benchmark boolean; v_redeployed int := 0;
  v_tick_minutes numeric; v_k text;
  v_fire_hb timestamptz; v_hb_window int; v_seat int; /* 0261 */
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF NOT FOUND THEN out_dispatched:=0; out_charge_assigned:=0; RETURN NEXT; RETURN; END IF;
  v_tick_minutes := COALESCE((v_run.payload->>'tick_minutes_actual')::numeric,
                             (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0);

  SELECT EXISTS (SELECT 1 FROM depots d WHERE d.id = v_run.depot_id AND d.slug LIKE 'benchmark%') INTO v_is_benchmark;

  -- ════════════════════════════════════════════════════════════════════════
  -- 0367 (G82): THE RESERVATION RECLAIMER, ON THE PATH THAT ACTUALLY RUNS.
  -- 0360 wired this into ottoq_sim_advance_tick. ottoq_demo_metronome -- the
  -- live engine, cron job 12 -- calls ottoq_sim_advance_tick_world and
  -- ottoq_sim_decide_and_dispatch DIRECTLY and never calls advance_tick, so the
  -- reclaimer had never run on a metronome-driven run. Measured before this
  -- migration: 38 release-eligible reservations standing on the twin depot,
  -- unchanged across a tick boundary, some 45 sim-minutes past expiry.
  -- It runs HERE, above the policy branch, so every arm of an A/B gets the same
  -- world: reservation hygiene is part of the problem definition, not the policy
  -- (the C5 / 0146 argument about the L1 shield, applied to the calendar).
  -- Never allowed to abort the tick: the function returns ok:false rather than
  -- raising, and this handler is the second line of that same defence.
  -- ════════════════════════════════════════════════════════════════════════
  BEGIN
    PERFORM public.ottoq_release_unusable_reservations(
              p_sim_run_id, v_run.sim_clock_current, v_run.depot_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0367 release_unusable_reservations: % %', SQLSTATE, SQLERRM;
  END;

  IF v_run.policy IS NULL OR v_run.policy = 'otto_q' THEN
    BEGIN
      UPDATE ottoq_sim_runs
         SET payload = COALESCE(payload,'{}'::jsonb)
                     || jsonb_build_object('inbound_forecast', ottoq_inbound_forecast(v_run.depot_id, 60))
       WHERE sim_run_id = p_sim_run_id;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'inbound_forecast attach: %', SQLERRM;
    END;
    -- A SATISFIED NEED IS A DONE NEED, AND IT IS RESOLVED FIRST.
    -- Runs ahead of every planner below so nothing books a charger against a
    -- need the car no longer has. A charge atom left open on a car already at
    -- its target is what sent nine vehicles to chargers in run c99e4435 with
    -- 0.00 kWh to deliver. OTTO-Q decides satisfaction; the twin only reports
    -- state. Never allowed to abort the tick.
    BEGIN
      PERFORM ottoq.ottoq_close_satisfied_charge_needs(p_sim_run_id, v_run.sim_clock_current);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'close satisfied charge needs: %', SQLERRM;
    END;
    /* 0261: THE PROPOSER SEAT. Seat 0 -- the default, and every run that has ever
       existed -- is the block below, untouched. A non-zero seat is set run-scoped
       by ottoq_ab_pair only (CHECK ottoq_policy_params_proposer_seat_run_scoped);
       it replaces OTTO-Q's proposers with ONE baseline proposer and leaves the
       disposer -- ottoq_decide_tick, the shield, the calendar -- exactly as it is.
       The policy is what proposes; the kernel disposes. */
    v_seat := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int;
    IF v_seat = 0 THEN
    BEGIN
      PERFORM ottoq_reoptimize_reservation_book(p_sim_run_id, v_run.sim_clock_current);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'reservation reopt: %', SQLERRM;
    END;

    -- ════════════════════════════════════════════════════════════════════════
    -- P6 FIX 2 — DECIDE-BEAT cuOpt FIRE, CONDITIONAL. net.http_post only QUEUES
    -- a row; the pg_net worker cannot transmit until THIS transaction COMMITS,
    -- and ottoq_decide_tick runs a few lines below, inside it. So a fire from
    -- here lands one full tick late by construction. It is NOT deleted, because
    -- this function is also the only route to cuOpt for callers with no fire
    -- beat (twin.ottoq_world_advance, ottoq_api_otto_q_decide, probe ticks).
    -- Stand down ONLY while a healthy FIRE beat is demonstrably running.
    -- ════════════════════════════════════════════════════════════════════════
    v_hb_window := GREATEST(5, ottoq_policy_get(p_sim_run_id, 'cuopt_fire_beat_heartbeat_s', 60)::int);
    BEGIN
      v_fire_hb := (v_run.payload->>'cuopt_fire_beat_at')::timestamptz;
    EXCEPTION WHEN OTHERS THEN v_fire_hb := NULL;
    END;
    IF v_fire_hb IS NULL OR v_fire_hb < now() - make_interval(secs => v_hb_window) THEN
      BEGIN PERFORM ottoq_cuopt_refresh(p_sim_run_id); EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    -- ════════════════════════════════════════════════════════════════════════
    -- P7 2026-08-03 — RIGHT OF FIRST REFUSAL ON DECIDE-BEAT ARRIVALS.
    --
    -- The metronome alternates FIRE and DECIDE beats. A vehicle that reaches the
    -- gate during a DECIDE beat is placed by the local greedy path inside THIS
    -- transaction, so no FIRE beat ever sees it and cuOpt cannot compete for it.
    -- Measured on the phase-9 cert: 113 arrivals, 57 gate candidates -- the
    -- coin-flip you would predict from the beat split, not a solver problem.
    --
    -- This holds such a vehicle out of the greedy cursor for EXACTLY ONE decide
    -- tick so the next FIRE beat can offer it. The hold releases the instant a
    -- cuopt proposal exists (first refusal, never veto) and UNCONDITIONALLY at
    -- the next decide tick via ottoq_cuopt_defer_roll -- so if cuOpt abstains,
    -- greedy assigns next tick with no condition attached. Capped at
    -- cuopt_first_refusal_max_defers (default 1) per vehicle per run; set it to
    -- 0 to disable. Never aborts the tick.
    -- ════════════════════════════════════════════════════════════════════════
    BEGIN
      PERFORM ottoq_cuopt_first_refusal_arm(p_sim_run_id, COALESCE(v_run.tick_count,0));
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'cuopt first-refusal arm: %', SQLERRM;
    END;

    PERFORM ottoq_l2_optimize_assignments(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
    BEGIN PERFORM ottoq_service_priority_propose(p_sim_run_id); EXCEPTION WHEN OTHERS THEN NULL; END;
    ELSE
      BEGIN PERFORM public.ottoq_l2_propose_seat(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current, v_seat);
      EXCEPTION WHEN OTHERS THEN RAISE WARNING 'proposer seat % failed: %', v_seat, SQLERRM; END;
    END IF;
  END IF;
  v_decide := CASE v_run.policy
    WHEN 'greedy' THEN ottoq_greedy_tick(p_sim_run_id)
    WHEN 'fifo'   THEN ottoq_fifo_tick(p_sim_run_id)
    WHEN 'manual' THEN ottoq_manual_tick(p_sim_run_id)
    ELSE               ottoq_decide_tick(p_sim_run_id)
  END;

  IF v_run.policy IS DISTINCT FROM 'greedy' THEN
    v_redeployed := ottoq_sim_auto_dispatch_tick(p_sim_run_id, v_run.sim_clock_current, v_tick_minutes);
  END IF;

  BEGIN
    PERFORM ottoq_itin_close_travel_legs(p_sim_run_id, v_run.sim_clock_current, 20);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'close travel legs: %', SQLERRM;
  END;

  BEGIN
    PERFORM ottoq_sweep_stranded_deployments(p_sim_run_id, v_run.sim_clock_current, 45);

  BEGIN
    PERFORM ottoq_release_expired_bookings(p_sim_run_id, v_run.sim_clock_current);
    PERFORM ottoq_place_unplaced_vehicles(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
    PERFORM ottoq.ottoq_react_to_refusals(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'placement reconcile: %', SQLERRM;
  END;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'stranded deploy sweep: %', SQLERRM;
  END;

  IF COALESCE(v_run.run_by,'') NOT IN ('benchmark', 'cert_harness')  -- 0105: cert runs quiesce the LLM proposer
     AND NOT v_is_benchmark
     AND v_run.policy IS NOT DISTINCT FROM 'otto_q'
     AND ottoq_policy_get(p_sim_run_id, 'orchestrator_agent_enabled', 1) > 0  -- 0112: deterministic-only sessions quiesce the agent
     AND ottoq_policy_get(p_sim_run_id, 'agent_solver_chain_enabled', 0) < 1  -- 0332: chain fire beats own the agent entrance
     AND ( (COALESCE(v_run.tick_count,0) % 3) = 0
           OR ottoq_orchestrator_trigger(v_run.depot_id) ) THEN
    BEGIN
      SELECT decrypted_secret INTO v_k FROM vault.decrypted_secrets WHERE name='ottoq_anon_key' LIMIT 1;
      IF v_k IS NOT NULL THEN
        PERFORM net.http_post(
          url := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-orchestrator-agent',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_k,'apikey',v_k),
          body := jsonb_build_object('depot_id', v_run.depot_id, 'sim_run_id', p_sim_run_id),
          timeout_milliseconds := 20000);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type:='ottoq_engine', p_actor_id:='ottoq_orchestrator', p_event_type:='twin.sim_tick_advanced',
    p_entity_type:='system', p_payload:=jsonb_build_object('sim_run_id',p_sim_run_id,'sim_clock',v_run.sim_clock_current,
      'policy',v_run.policy,'decisions_built',v_decide.requests_built,'enacted',v_decide.enacted,
      'redeployed',v_redeployed,'completed',(v_run.status='completed')),
    p_severity:='debug', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

  out_dispatched:=v_decide.enacted; out_charge_assigned:=v_decide.requests_built;
  RETURN NEXT;
END;
$function$
;

-- ══ PART C. REGISTER THE NEW EVENT TYPE ═════════════════════════════════════
-- C7 step 2 requires additions to the event vocabulary to be registered rather
-- than merely emitted. (Noted while doing it, not fixed here: 25 of the 57 event
-- types on the live run are absent from this catalog, `ottoq.refusal_escalated`
-- among them. That is the C7 audit, and it is a separate piece of work.)
INSERT INTO public.ottoq_event_types_catalog
  (event_type, category, description, emitter, default_severity, introduced_in)
VALUES
  ('ottoq.reservation_reclaim_blocked', 'system_event',
   'The stall-reservation reclaimer found release-eligible reservations and could release none of them -- every candidate row was locked by another transaction. Countable evidence for the state that 0360 reported as silence.',
   'public.ottoq_release_unusable_reservations', 'warning', '0367')
ON CONFLICT (event_type) DO NOTHING;

-- ══ P9. POST-ASSERTIONS ═════════════════════════════════════════════════════
DO $p9$
DECLARE
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_decide_and_dispatch';
  IF position('ottoq_release_unusable_reservations' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: Part B did not take -- decide_and_dispatch does not call the reclaimer';
  END IF;
  IF position('ottoq_react_to_refusals' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: Part B lost the refusal reactor';
  END IF;
  IF position('SKIP LOCKED' in (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                 WHERE n.nspname='public'
                                   AND p.proname='ottoq_release_unusable_reservations')) = 0 THEN
    RAISE EXCEPTION 'P9: the reclaimer is not the SKIP LOCKED version';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog
                  WHERE event_type = 'ottoq.reservation_reclaim_blocked') THEN
    RAISE EXCEPTION 'P9: the new event type is not registered';
  END IF;
  RAISE NOTICE 'P9 ok: reclaimer wired into the live path, SKIP LOCKED in place, event type registered';
END $p9$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
-- Written HERE and not only through a side call, which is why CI went red five ways
-- on this branch: tests/test_migration_hygiene.py reads the FILE, and
-- ottoq_cert_recert_floor() treats a migration with no lineage row as forcing a
-- recert, so a missing INSERT restarts every certification column's streak. The row
-- is already in the database under the unprefixed name; this INSERT carries the
-- current PREFIXED convention and ON CONFLICT keeps them one row rather than two.
-- Both join correctly either way -- 0226 strips the NNNN_ prefix from both sides.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0367_the_reclaimer_0360_installed_has_never_run_on_the_live_metronome_path', true,
  'Engine: ottoq_release_unusable_reservations is now called from '
  'ottoq_sim_decide_and_dispatch, above the policy branch, which is the path '
  'ottoq_demo_metronome actually uses -- 0360 wired it only into ottoq_sim_advance_tick, '
  'which the live metronome never calls, so it had never run. The reclaimer now takes '
  'rows FOR UPDATE SKIP LOCKED (it was silently returning deadlock detected / 40P01 / '
  'released 0 on every direct call), counts eligible without locking, and emits '
  'ottoq.reservation_reclaim_blocked when eligible > 0 and released = 0. Changes what '
  'every tick of every arm does, so it invalidates canons.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
