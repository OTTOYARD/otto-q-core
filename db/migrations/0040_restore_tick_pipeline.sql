-- MIGRATION: 0040_restore_tick_pipeline.sql
-- Restore functions damaged by cascade DROP of twin.ottoq_sim_confirm_commands.
-- Apply via psql: psql -f db/migrations/0040_restore_tick_pipeline.sql

CREATE OR REPLACE FUNCTION public.ottoq_sim_advance_tick_world(p_sim_run_id uuid)
 RETURNS TABLE(out_sim_clock_after timestamp with time zone, out_tick_minutes numeric, out_telemetry_emitted integer, out_charge_advanced integer, out_completed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wear_ids uuid[];
  v_wear_written int;
  v_run ottoq_sim_runs%ROWTYPE;
  v_tick_minutes numeric; v_new_sim_clock timestamptz; v_completed boolean := FALSE;
  v_telemetry_count int; v_tick_t0 timestamptz; v_charge_adv int; v_feed_sim boolean := true;
BEGIN
  v_tick_t0 := clock_timestamp();   -- T0 instrument: whole-tick wall clock
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR UPDATE;
  IF NOT FOUND OR v_run.status NOT IN ('running') THEN out_completed:=TRUE; RETURN NEXT; RETURN; END IF;

  SELECT COALESCE(d.feed_mode, 'sim') = 'sim' INTO v_feed_sim FROM depots d WHERE d.id = v_run.depot_id;
  v_feed_sim := COALESCE(v_feed_sim, true);
  -- PLAYBACK CLOCK. 'live' = TRUE 1:1 (sim advances by REAL elapsed x speed_x, so
  -- one real second is one sim second at 1x). 'fixed' (default) keeps the historical
  -- tick_interval_seconds * time_scale behaviour so certs/benchmarks stay deterministic.
  -- The 0.05..10 clamp keeps a stalled metronome or a long GC pause from teleporting
  -- the world; it never applies in fixed mode.
  IF COALESCE(v_run.payload->>'playback_mode','fixed') = 'live' THEN
    -- TRUE 1:1. clock_timestamp() (NOT now(), which is transaction time and does
    -- not advance inside a transaction). Floor 0 -- a zero advance is correct when
    -- no real time has elapsed. The 10-minute ceiling stays as the anti-teleport guard.
    v_tick_minutes := LEAST(10.0, GREATEST(0.0,
      (EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.last_tick_at, clock_timestamp())))
       * COALESCE((v_run.payload->>'speed_x')::numeric, 1.0)) / 60.0));
  ELSE
    v_tick_minutes := (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0;
  END IF;
  v_new_sim_clock := v_run.sim_clock_current + (v_tick_minutes || ' minutes')::interval;
  IF v_new_sim_clock >= v_run.sim_clock_end THEN v_new_sim_clock := v_run.sim_clock_end; v_completed := TRUE; END IF;

  PERFORM ottoq_sim_advance_visit_atoms(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_opportunistic_scan(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_sim_advance_flow_contract(p_sim_run_id, v_new_sim_clock);
  IF v_feed_sim THEN
    PERFORM ottoq_sim_prearrival_contracts(p_sim_run_id, v_new_sim_clock);
    PERFORM ottoq_sim_confirm_commands(p_sim_run_id, v_new_sim_clock);
  END IF;
  IF (v_run.policy IS NULL OR v_run.policy = 'otto_q') AND ottoq_policy_get(p_sim_run_id,'energy_orchestration_enabled',1) > 0 THEN
    PERFORM ottoq_energy_orchestrate(p_sim_run_id, v_run.depot_id, v_new_sim_clock, v_run.tick_count + 1);
  END IF;
  IF v_feed_sim THEN
    PERFORM ottoq_sim_energy_controller(p_sim_run_id, v_run.depot_id, v_new_sim_clock);
  END IF;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_reconcile_charge_sessions(p_sim_run_id, v_new_sim_clock);
    SELECT COUNT(*) INTO v_charge_adv FROM ottoq_sim_advance_charge_sessions(p_sim_run_id, v_new_sim_clock);
    PERFORM ottoq_sim_advance_all_energy(v_run.depot_id, p_sim_run_id, v_new_sim_clock, v_tick_minutes);
  ELSE
    v_charge_adv := 0;
  END IF;
  IF v_feed_sim THEN
  -- AP-2 R1: snapshot the in-flight dispatch set BEFORE telemetry mutates it
  SELECT array_agg(d.dispatch_id) INTO v_wear_ids
    FROM ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning');
  SELECT COUNT(*) INTO v_telemetry_count FROM ottoq_sim_advance_deployed_telemetry(p_sim_run_id, v_new_sim_clock, v_tick_minutes);
  v_wear_written := -1;
  BEGIN
    v_wear_written := ottoq_sim_advance_wear_counters(
      p_sim_run_id, v_new_sim_clock, v_tick_minutes, v_run.tick_count + 1, COALESCE(v_wear_ids, ARRAY[]::uuid[]));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'wear_counters: %', SQLERRM; END;
  BEGIN
    INSERT INTO ottoq_wear_tick_status (sim_run_id, tick_seq, sim_clock, attempted, written, note)
    VALUES (p_sim_run_id, v_run.tick_count + 1, v_new_sim_clock,
            COALESCE(array_length(v_wear_ids,1),0), GREATEST(v_wear_written,0),
            CASE WHEN v_wear_written < 0 THEN 'advancer raised' ELSE NULL END)
    ON CONFLICT (sim_run_id, tick_seq) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  ELSE
    v_telemetry_count := 0;
  END IF;
  BEGIN PERFORM ottoq_comms_advance(p_sim_run_id, v_new_sim_clock); EXCEPTION WHEN OTHERS THEN RAISE WARNING 'comms_advance: %', SQLERRM; END;
  PERFORM ottoq_sim_advance_service_flow(p_sim_run_id, v_new_sim_clock, v_tick_minutes, v_run.depot_id);
  IF v_feed_sim THEN PERFORM ottoq_sim_overnight_service_drain(v_run.depot_id, v_new_sim_clock, p_sim_run_id); END IF;

  UPDATE ottoq_sim_runs SET sim_clock_current=v_new_sim_clock, last_tick_at=v_tick_t0,
         -- LIVE-CLOCK COUPLING FIX 2026-08-01: publish the ACTUAL elapsed sim-minutes
         -- so every per-tick RATE cap downstream scales with the real tick size.
         -- Fixed mode writes exactly 30 = the historical fallback (no behaviour change).
         payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('tick_minutes_actual', v_tick_minutes),  -- anchor at tick START so the tick's own compute is inside the next elapsed
         next_tick_due_at=clock_timestamp()+(v_run.tick_interval_seconds||' seconds')::interval,
         tick_count=tick_count+1, status=CASE WHEN v_completed THEN 'completed' ELSE status END,
         ended_at=CASE WHEN v_completed THEN NOW() ELSE ended_at END
   WHERE sim_run_id=p_sim_run_id;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_emit_depot_heartbeats(v_run.depot_id, v_new_sim_clock);
    UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_new_sim_clock WHERE depot_id = v_run.depot_id AND station_state <> 'Faulted';
    PERFORM ottoq_sim_recover_chargers(v_run.depot_id, v_new_sim_clock, 50);
  END IF;
  BEGIN PERFORM ottoq_reconcile_charger_states(v_run.depot_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'charger reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_oem_webhook_collect_responses();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'webhook reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_admit_stranded_vehicles(v_run.depot_id, p_sim_run_id, v_new_sim_clock, 80, 12);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'admit stranded: %', SQLERRM; END;

  UPDATE vehicles SET current_state='charge_complete_holding'::vehicle_state, last_state_change=v_new_sim_clock
   WHERE home_depot_id=v_run.depot_id AND category='autonomous'
     AND current_state='arrived_at_gate' AND current_soc>=85;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_generate_arrival_manifests(v_run.depot_id, p_sim_run_id);
  END IF;
  PERFORM ottoq_sim_wash_triage(v_run.depot_id, v_new_sim_clock);
  IF v_feed_sim THEN
    PERFORM ottoq_sim_vehicle_exception_handler(v_run.depot_id, v_new_sim_clock, p_sim_run_id);
    PERFORM ottoq_sim_bay_fault_handler(v_run.depot_id, v_new_sim_clock, p_sim_run_id);
  END IF;

  -- T0 instrument: authoritative wall-clock + compute cost, one row per tick.
  -- clock_timestamp() (not now()) so batch-stepped ticks are individually timed.
  BEGIN
    INSERT INTO ottoq_tick_clock_log (
      sim_run_id, tick_seq, real_started_at, real_ended_at,
      sim_clock_before, sim_clock_after, tick_compute_ms, sim_advance_s,
      playback_mode, speed_x)
    VALUES (
      p_sim_run_id, COALESCE(v_run.tick_count,0) + 1, v_tick_t0, clock_timestamp(),
      v_run.sim_clock_current, v_new_sim_clock,
      round(EXTRACT(EPOCH FROM (clock_timestamp() - v_tick_t0))::numeric * 1000, 1),
      round(EXTRACT(EPOCH FROM (v_new_sim_clock - v_run.sim_clock_current))::numeric, 1),
      COALESCE(v_run.payload->>'playback_mode','fixed'),
      COALESCE((v_run.payload->>'speed_x')::numeric, 1.0))
    ON CONFLICT (sim_run_id, tick_seq) DO UPDATE
      SET real_ended_at   = EXCLUDED.real_ended_at,
          tick_compute_ms = EXCLUDED.tick_compute_ms;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'tick clock log: %', SQLERRM;
  END;

  out_sim_clock_after:=v_new_sim_clock; out_tick_minutes:=v_tick_minutes;
  out_telemetry_emitted:=v_telemetry_count; out_charge_advanced:=v_charge_adv; out_completed:=v_completed;
  RETURN NEXT;
END;
$function$;

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
  v_fire_hb timestamptz; v_hb_window int;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF NOT FOUND THEN out_dispatched:=0; out_charge_assigned:=0; RETURN NEXT; RETURN; END IF;
  v_tick_minutes := COALESCE((v_run.payload->>'tick_minutes_actual')::numeric,
                             (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0);

  SELECT EXISTS (SELECT 1 FROM depots d WHERE d.id = v_run.depot_id AND d.slug LIKE 'benchmark%') INTO v_is_benchmark;

  IF v_run.policy IS NULL OR v_run.policy = 'otto_q' THEN
    BEGIN
      UPDATE ottoq_sim_runs
         SET payload = COALESCE(payload,'{}'::jsonb)
                     || jsonb_build_object('inbound_forecast', ottoq_inbound_forecast(v_run.depot_id, 60))
       WHERE sim_run_id = p_sim_run_id;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'inbound_forecast attach: %', SQLERRM;
    END;
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

  IF COALESCE(v_run.run_by,'') <> 'benchmark'
     AND NOT v_is_benchmark
     AND v_run.policy IS NOT DISTINCT FROM 'otto_q'
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

CREATE OR REPLACE FUNCTION twin.ottoq_sim_confirm_commands(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed bigint; v_n int := 0; v_rec RECORD; v_delay numeric; v_due timestamptz;
  v_stall_id uuid; v_stype text;
BEGIN
  SELECT COALESCE(random_seed,42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  FOR v_rec IN
    SELECT command_id, vehicle_id, command_type, payload, issued_at FROM ottoq_vehicle_commands
     WHERE sim_run_id = p_sim_run_id AND status = 'issued'
  LOOP
    v_delay := 1 + ottoq_sim_seeded_random(v_seed, v_rec.command_id::text || ':conf') * 2;  -- 1-3 min
    v_due := v_rec.issued_at + (v_delay::text || ' minutes')::interval;
    IF v_due > p_clock THEN CONTINUE; END IF;

    -- apply when the instruction asks the twin to perform the move (the world
    -- obeying an order, not the world deciding)
    v_stall_id := NULLIF(v_rec.payload->>'stall_id','')::uuid;
    IF COALESCE((v_rec.payload->>'apply_required')::boolean, false) AND v_stall_id IS NOT NULL THEN
      SELECT s.stall_type::text INTO v_stype FROM stalls s WHERE s.id = v_stall_id;
      UPDATE stalls SET current_vehicle_id = NULL, status = 'available'
       WHERE current_vehicle_id = v_rec.vehicle_id AND id <> v_stall_id;
      UPDATE vehicles
         SET current_stall_id = v_stall_id,
             current_state = CASE
               WHEN v_rec.command_type = 'begin_charge' AND v_stype = 'dcfc' THEN 'charging_dcfc'::vehicle_state
               WHEN v_rec.command_type = 'begin_charge'                      THEN 'charging_l2'::vehicle_state
               ELSE 'staged_awaiting_service'::vehicle_state END,
             last_state_change = v_due
       WHERE id = v_rec.vehicle_id;
      UPDATE stalls SET current_vehicle_id = v_rec.vehicle_id, status = 'occupied'
       WHERE id = v_stall_id;
    END IF;

    UPDATE ottoq_vehicle_commands
       SET status = 'executed',
           confirmed_at = v_due,
           confirmed_by = CASE WHEN COALESCE((v_rec.payload->>'apply_required')::boolean,false)
                               THEN 'twin_executor' ELSE 'twin_auto_tech' END,
           executed_at  = v_due
     WHERE command_id = v_rec.command_id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END; $function$

-- ===== ottoq_sim_current_tariff =====
CREATE OR REPLACE FUNCTION twin.ottoq_sim_current_tariff(p_depot_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS TABLE(out_label text, out_rate_usd_kwh numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hour    INTEGER;
  v_dow     INTEGER;
  v_month   INTEGER;
  v_season  TEXT;
BEGIN
  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_dow  := EXTRACT(DOW  FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_month := EXTRACT(MONTH FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  v_season := CASE
    WHEN v_month BETWEEN 6 AND 9  THEN 'summer'
    WHEN v_month BETWEEN 12 AND 12 OR v_month BETWEEN 1 AND 2 THEN 'winter'
    ELSE 'shoulder' END;

  SELECT label, rate_usd_per_kwh
    INTO out_label, out_rate_usd_kwh
    FROM ottoq_tariff_windows
   WHERE depot_id = p_depot_id
     AND active
     AND v_hour >= hour_start AND v_hour < hour_end
     AND (season = v_season OR season = 'all')
   ORDER BY rate_usd_per_kwh DESC                       -- super-peak wins over peak
   LIMIT 1;
  IF NOT FOUND THEN
    out_label := 'unknown';
    out_rate_usd_kwh := 0.10;
  END IF;
  RETURN NEXT;
END;
$function$;

