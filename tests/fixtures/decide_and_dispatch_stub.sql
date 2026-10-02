-- tests/fixtures/decide_and_dispatch_stub.sql: what db/migrations/0582 reads and patches, as the catalog held it on
-- 2026-10-02 (public.ottoq_sim_decide_and_dispatch, source md5 700e3e44b85a853d7d551a45d0d2d52b; 0582's P1 pins it).
--
-- Only the run row the function reads first is real here. Everything it calls after that is absent on purpose: a run
-- the guard lets through fails on the very next statement (`relation "depots" does not exist`), and a run it stops
-- returns without touching anything. That is the whole of what 0582 changes, so it is all this needs.
CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY, status text NOT NULL,
  payload jsonb, tick_interval_seconds integer DEFAULT 30, time_scale numeric DEFAULT 10, depot_id uuid,
  policy text DEFAULT 'otto_q', sim_clock_current timestamptz, tick_count integer DEFAULT 0, run_by text,
  started_at timestamptz DEFAULT now(), ended_at timestamptz,
  CONSTRAINT ottoq_sim_runs_status_check CHECK (status = ANY (ARRAY['initializing', 'running', 'paused', 'completed', 'failed', 'aborted'])));
CREATE TYPE public.ottoq_decide_tick_result AS (requests_built integer, enacted integer);
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false, note text, classified_at timestamptz);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigint GENERATED ALWAYS AS IDENTITY, label text, object_kind text,
  schema_name text, object_name text, definition text, def_md5 text, taken_at timestamptz DEFAULT now());
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false) RETURNS integer
LANGUAGE sql STABLE AS $$ SELECT CASE WHEN current_setting('ottoq.simulate_certification_in_flight', true) = 'on' THEN 1 ELSE 0 END $$;

-- ── as the catalog held it ──
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

  -- ════════════════════════════════════════════════════════════════════════
  -- 0374 (G89): RECORD THE INSTANTS THE SITE'S *TOTAL* LOAD CROSSED ITS
  -- DECLARED CAP. MEASURED ONLY -- this detector changes no assignment.
  -- EN.001.grid_capacity_ceiling is the one rule naming service_max_kw, and its
  -- load term is twin.ottoq_sim_compute_charger_load_kw = SUM(ocpp_sessions
  -- power) and nothing else. So on run 5b37ee46 the site metered 2,738.8 kW
  -- against a 2,500 kW contract -- EV 1,691.8 (under its own 1,800 nameplate)
  -- + BESS CHARGING at 968 + 79 base -- and every rule that judged a piece of it
  -- passed, correctly, because no rule takes the sum as its subject.
  -- It runs HERE, above the policy branch, for 0367's reason: what the world IS
  -- belongs to the problem definition, so every A/B arm reads it identically.
  -- Widening EN.001's meter would change the feasible set and is deliberately
  -- NOT in this file -- and the remedy is probably to defer the battery rather
  -- than refuse a vehicle, which is Chase's call to make on this evidence.
  -- ════════════════════════════════════════════════════════════════════════
  BEGIN
    PERFORM ottoq.ottoq_detect_site_power_excursion(
              p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0374 detect_site_power_excursion: % %', SQLSTATE, SQLERRM;
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
    -- 0486 (G219): AN UNMET NEED IS AN OPEN NEED, AND IT IS READ AGAIN EVERY TICK.
    -- A visit is derived once, at the recall, from the SoC the car had then, and the car keeps driving. A car
    -- still coming in or waiting whose SoC is now below its visit target, with no charge planned, gets the charge
    -- the deriver would give it now. Never allowed to abort the tick.
    BEGIN
      PERFORM ottoq.ottoq_reassess_charge_needs(p_sim_run_id, v_run.sim_clock_current);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'reassess charge needs: %', SQLERRM;
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
$function$;

-- ── the trigger that closes a run's needs, as the catalog declares it (its WHEN clause is what 0582's P1 reads) ──
CREATE TABLE public.stub_closed_runs (sim_run_id uuid, status text);
CREATE FUNCTION public.ottoq_tg_close_run_needs_on_terminal() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.stub_closed_runs VALUES (NEW.sim_run_id, NEW.status);
  RETURN NULL;
END $$;
CREATE TRIGGER ottoq_sim_runs_close_needs AFTER UPDATE OF status ON public.ottoq_sim_runs FOR EACH ROW
  WHEN (((old.status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text]))
         AND (new.status = ANY (ARRAY['completed'::text, 'failed'::text, 'aborted'::text]))))
  EXECUTE FUNCTION public.ottoq_tg_close_run_needs_on_terminal();
