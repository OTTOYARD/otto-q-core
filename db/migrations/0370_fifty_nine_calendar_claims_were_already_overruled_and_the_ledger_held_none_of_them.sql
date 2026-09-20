-- migration-version: 20260920042835
-- ════════════════════════════════════════════════════════════════════════════
-- 0370  FIFTY-NINE CALENDAR CLAIMS WERE ALREADY OVERRULED BY A VEHICLE SITTING
--       IN THE STALL, AND THE LEDGER THAT PROMISES TO RECORD EVERY SUCH CLAIM
--       HELD NONE OF THEM.
--
--       forces_recert TRUE -- it adds a per-tick write to every arm. The write
--       is evidence only; no assignment changes.
-- ════════════════════════════════════════════════════════════════════════════
--
-- G85, and it is the calendar half of the reservation wall. 0367 and 0369 cleaned
-- up the POINTER side (`stalls.reserved_by`): expired holds, holds by a vehicle
-- that can no longer use them, and holds by a vehicle physically parked elsewhere
-- with nothing in the calendar behind them. 0369 deliberately exempts a hold the
-- calendar backs, because a booking is a real forward plan. This is what some of
-- those calendar-backed plans turn out to be.
--
-- Measured on run `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10` (busy_day, seed 777777,
-- twin depot per rule 8), at the sim clock, over bookings whose window CONTAINS
-- that clock -- i.e. live claims, not future ones:
--
--   live perimeter_hold bookings on staging stalls                     97
--     state 'held'                                                     83
--       holder physically in the stall                                  0
--       stall empty                                                    26
--       **a DIFFERENT vehicle physically in the stall**                57
--     state 'active'                                                   14
--       holder physically in the stall                                  5
--       stall empty                                                     8
--       a different vehicle in it                                       1
--
--   all live perimeter_hold claims contradicted by an occupant         59
--     present in space_conflict_ledger by displaced_booking_id          0
--     whose STALL appears in the ledger at all                          4
--
--   and what the ledger does hold for this run                         26
--     assignment_refused_occupied / command_refused_preflight  l2 10, staging 8, dcfc 7
--     stale_claim_displaced / reality_outranks_plan            service_bay 1
--
-- **98 of the depot's 113 staging stalls were held by `perimeter_hold` at that
-- moment, average window 248 minutes on a run whose whole life is 540 sim-minutes.**
-- And the service those holds exist for is performed never: `perimeter_walkaround`
-- shows **36 atoms, 0 done** on this run, and it is declared in NEITHER
-- `service_cadence_policy` NOR `service_definitions` -- the standing note in
-- CLAUDE.md 2.3, now with today's numbers behind it.
--
-- THE MECHANISM, AND WHY IT MATTERS MORE THAN THE COUNT. The ledger records the
-- conflict at the moment an assignment is refused -- which is when the holder
-- finally travels to the stall and preflight discovers the occupant. The
-- contradiction was knowable for up to 248 minutes before that. So the engine
-- learns about each conflict at the worst possible time, and the 25
-- `assignment_refused_occupied` rows are the LATE symptom of the 59 standing
-- contradictions nothing was counting.
--
-- SCOPE, DELIBERATELY NARROW. This migration only counts. Per 2.9a's blind-spot
-- promotion doctrine an instrument lands MEASURED and is acted on only after a
-- round shows what it sees. Rebooking a holder whose stall is already taken,
-- before it travels, is an assignment change and belongs to Chase, not to a
-- migration written at four in the morning.
--
-- NOTED, NOT FIXED: `space_conflict_ledger` is registered `class='engine'` and
-- carries an FK to `ottoq_sim_runs`, so every demo run deletes the prior run's
-- conflicts -- 364 rows went in the purge that started this run. Rule 6 names this
-- table as load-bearing and "never to be removed"; nothing says it has to survive
-- its run, and the FK is exactly what 0340 had to avoid to make an evidence table.
-- Reclassifying it is its own migration.

-- ══ P0. THE LEDGER IS SHAPED AS THIS DETECTOR EXPECTS ═══════════════════════
DO $p0$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='space_conflict_ledger'
                    AND column_name='displaced_booking_id') THEN
    RAISE EXCEPTION 'P0: space_conflict_ledger has no displaced_booking_id';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='space_conflict_ledger'
                    AND column_name='present_vehicle_id') THEN
    RAISE EXCEPTION 'P0: space_conflict_ledger has no present_vehicle_id';
  END IF;
  --: free text by design -- no CHECK to extend, so a new conflict_kind is additive
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conrelid='public.space_conflict_ledger'::regclass AND contype='c') THEN
    RAISE EXCEPTION 'P0: a CHECK constraint appeared on the ledger; the new conflict_kind must be added to it first';
  END IF;
  RAISE NOTICE 'P0 ok';
END $p0$;

-- ══ P1. THE BLIND SPOT IS LIVE, AND ITS SIZE IS RECORDED HERE ═══════════════
DO $p1$
DECLARE
  v_run uuid; v_clk timestamptz; v_contradicted bigint; v_in_ledger bigint;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start)
    INTO v_run, v_clk
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status='running'
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE 'P1: no running run on the twin depot; nothing to measure';
    RETURN;
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM public.space_conflict_ledger l
            WHERE l.sim_run_id = v_run AND l.displaced_booking_id = z.booking_id))
    INTO v_contradicted, v_in_ledger
    FROM (
      SELECT b.booking_id
        FROM public.ottoq_stall_bookings b
        JOIN public.stalls s ON s.id = b.stall_id
       WHERE b.sim_run_id = v_run
         AND b.state IN ('held','active')
         AND b.during @> v_clk
         AND s.depot_id = '11111111-1111-1111-1111-111111111111'
         AND s.current_vehicle_id IS NOT NULL
         AND s.current_vehicle_id <> b.vehicle_id) z;

  RAISE NOTICE 'P1: live claims contradicted by an occupant = %, of which already in the ledger = %',
               v_contradicted, v_in_ledger;
END $p1$;

-- ══ PART A. THE DETECTOR ════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION ottoq.ottoq_detect_contradicted_claims(
  p_sim_run_id uuid,
  p_depot_id   uuid,
  p_clock      timestamp with time zone,
  p_limit      integer DEFAULT 200)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_n integer := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN
    RETURN 0;
  END IF;

  WITH contradicted AS (
    SELECT b.booking_id, b.stall_id, b.vehicle_id, b.purpose, b.state, b.during,
           b.leg_id, b.booked_by,
           s.stall_type::text        AS stall_type,
           s.current_vehicle_id      AS present_vehicle_id,
           v.current_state::text     AS present_vehicle_state
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls s   ON s.id = b.stall_id
      LEFT JOIN public.vehicles v ON v.id = s.current_vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state IN ('held','active')
       --: LIVE claims only. A future window is a plan, not a contradiction.
       AND b.during @> p_clock
       AND s.depot_id = p_depot_id
       AND s.current_vehicle_id IS NOT NULL
       AND s.current_vehicle_id <> b.vehicle_id
       --: ONE ROW PER BOOKING, EVER. Without this the detector writes 59 rows a
       --: tick and floods the very ledger it is trying to make readable.
       AND NOT EXISTS (
         SELECT 1 FROM public.space_conflict_ledger l
          WHERE l.sim_run_id          = p_sim_run_id
            AND l.displaced_booking_id = b.booking_id
            AND l.conflict_kind        = 'standing_claim_contradicted')
     ORDER BY b.stall_id, b.vehicle_id, b.booking_id   /* run-stable, never heap order (0054/0207) */
     LIMIT GREATEST(COALESCE(p_limit, 200), 1)
  ), ins AS (
    INSERT INTO public.space_conflict_ledger
      (sim_run_id, depot_id, sim_clock, stall_id, stall_type, conflict_kind,
       resolution, present_vehicle_id, present_vehicle_state,
       displaced_vehicle_id, displaced_booking_id, displaced_state, displaced_during,
       displaced_leg_id, displaced_booked_by, detail)
    SELECT p_sim_run_id, p_depot_id, p_clock, c.stall_id, c.stall_type,
           'standing_claim_contradicted',
           --: MEASURED, NOT ACTED. 2.9a's blind-spot promotion doctrine: an atom
           --: is added measured first and enforced only after a round agrees.
           'recorded_not_acted',
           c.present_vehicle_id, c.present_vehicle_state,
           c.vehicle_id, c.booking_id, c.state, c.during,
           c.leg_id, c.booked_by,
           jsonb_build_object(
             'detector',        '0370',
             'purpose',         c.purpose,
             'claim_age_min',   round(EXTRACT(epoch FROM (p_clock - lower(c.during)))/60.0, 2),
             'claim_remaining_min',
                                round(EXTRACT(epoch FROM (upper(c.during) - p_clock))/60.0, 2),
             'note',            'the booking window contains the sim clock and a different vehicle is in the stall; discovered by sweep, not by a refused assignment')
      FROM contradicted c
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ins;

  RETURN COALESCE(v_n, 0);

--: Total on its own account. This runs inside decide_and_dispatch and an
--: unhandled error there rolls back the whole tick while cron still reads
--: "succeeded" (APPLYING.md). A missing evidence row is a gap; a rolled-back
--: tick is an outage.
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '0370 detect_contradicted_claims: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$;

COMMENT ON FUNCTION ottoq.ottoq_detect_contradicted_claims(uuid, uuid, timestamptz, integer) IS
'0370 (G85). Per-tick sweep recording calendar claims that physical reality has '
'ALREADY overruled: a booking in state held/active whose window contains the sim '
'clock, on a stall a DIFFERENT vehicle is physically sitting in. Writes one row per '
'booking per run into space_conflict_ledger with conflict_kind '
'"standing_claim_contradicted" and resolution "recorded_not_acted" -- MEASURED '
'ONLY, per 2.9a''s blind-spot promotion doctrine; it changes no assignment. Exists '
'because the ledger previously recorded such conflicts only at the moment an '
'assignment was refused (assignment_refused_occupied), which is when the holder '
'finally travels: on run 5b37ee46, 59 live claims were contradicted and 0 of them '
'appeared in the ledger by booking id, while 98 of 113 staging stalls were held by '
'perimeter_hold with an average 248-minute window. Never raises; a failure here '
'must never abort the tick.';

-- ══ PART B. WIRED INTO THE PATH THE LIVE METRONOME CALLS ════════════════════
-- Derived verbatim from pg_get_functiondef(ottoq_sim_decide_and_dispatch) with one
-- block inserted after 0367's reclaimer call. Not retyped.
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

  -- ════════════════════════════════════════════════════════════════════════
  -- 0370 (G85): COUNT THE CALENDAR CLAIMS PHYSICAL REALITY HAS ALREADY
  -- OVERRULED. MEASURED ONLY -- this detector changes no assignment.
  -- CLAUDE.md rule 6 says space_conflict_ledger "records every calendar claim
  -- overruled by physical reality". It records the ones discovered AT ASSIGNMENT
  -- TIME (assignment_refused_occupied, 25 rows on run 5b37ee46) and one
  -- displacement. It did not record a claim that is ALREADY contradicted while it
  -- stands: 59 live perimeter_hold bookings named a staging stall a DIFFERENT
  -- vehicle was sitting in, 0 of them present in the ledger by booking id.
  -- Per 2.9a's blind-spot promotion doctrine this lands MEASURED first. Acting on
  -- it -- rebooking the holder before it travels -- is an assignment change and
  -- is deliberately not in this migration.
  -- ════════════════════════════════════════════════════════════════════════
  BEGIN
    PERFORM ottoq.ottoq_detect_contradicted_claims(
              p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0370 detect_contradicted_claims: % %', SQLSTATE, SQLERRM;
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

-- ══ P9. POST-ASSERTIONS ═════════════════════════════════════════════════════
DO $p9$
DECLARE v_src text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='ottoq' AND p.proname='ottoq_detect_contradicted_claims') THEN
    RAISE EXCEPTION 'P9: the detector does not exist';
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_decide_and_dispatch';
  IF position('ottoq_detect_contradicted_claims' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the detector is not wired into decide_and_dispatch';
  END IF;
  --: 0367 and 0369 must both survive the re-derivation
  IF position('ottoq_release_unusable_reservations' in v_src) = 0
     OR position('ottoq_react_to_refusals' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the re-derived body lost the reclaimer or the refusal reactor';
  END IF;
  --: and the detector must be MEASURED, not acting
  IF position('recorded_not_acted' in
        (SELECT p2.prosrc FROM pg_proc p2 JOIN pg_namespace n2 ON n2.oid=p2.pronamespace
          WHERE n2.nspname='ottoq' AND p2.proname='ottoq_detect_contradicted_claims')) = 0 THEN
    RAISE EXCEPTION 'P9: the detector does not declare itself measured-only';
  END IF;
  RAISE NOTICE 'P9 ok: detector exists, is wired, and declares itself measured-only';
END $p9$;
