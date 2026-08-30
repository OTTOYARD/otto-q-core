-- migration-version: 20260830110000
-- migration-name:    the_production_session_lifecycle
-- 0111 -- the founder directive (2026-08-30): make the orchestration layer work top to
-- bottom -- once initiated it analyzes and optimizes integrated vehicle/site state
-- continuously in the background, in real time, with no simulator/twin involvement and no
-- cuOpt/LLM agents (deterministic core only; intelligence layers return later).
--
-- SURVEY VERDICT (verify-consolidate-extend): the loop already exists in pieces --
--   * twin.ottoq_world_advance IS the production tick: it self-selects the running
--     run_by='production_live' session, ticks by WALL-ELAPSED minutes (0.25..10, from
--     last_tick_at), runs the orchestration mirror (visit atoms, opportunistic scan, flow
--     contract, OTTO-Q energy orchestration, comms, service flow, charger-state reconcile,
--     webhook collect, stranded admits, wash triage, gate disposition), skips EVERY
--     synthetic twin phase when depots.feed_mode <> 'sim', advances the clock to now(), and
--     ends with ottoq_sim_decide_and_dispatch. THE TICK, figured out: wall-elapsed, driven
--     by the ottoq-depot-tick cron every 2 minutes via ottoq_cron_tick.
--   * ottoq_ingest_vehicle_signal is the live-telemetry return handshake; in-depot
--     progression is decide_tick's job (its own comment).
--   * Every standing service already stands aside for production_live: the metronome never
--     twin-advances it, the governor never auto-stops it, purges never touch it, and
--     cuopt_refresh's run resolution EXCLUDES production_live -- cuOpt is structurally
--     silent for production sessions, exactly the founder's "no cuOpt now".
--
-- WHAT WAS MISSING: a lifecycle. Nothing created or finalized a production session. This
-- migration adds the two calls:
--
--     SELECT public.ottoq_production_start();          -- initiate (flagship depot default)
--     SELECT public.ottoq_production_stop('reason');   -- finalize
--
-- start: refuses if the depot already has a running run; inserts the run row under the new
-- 'production' scenario (clocks = now(), horizon open at +100 years, tick_interval 120s to
-- match the cron cadence); pins the 0092 event GUC; sets run policies
-- orchestrator_agent_enabled=0 and cuopt_propose_enabled=0 (deterministic core only -- the
-- agent gate lands in 0112); records production.session_started. Deliberately NO twin
-- baggage: no scenario prime, no seeded boot draw (a real-feed depot's profiles come from
-- telemetry, not from a seed), no world reset.
-- stop: runs the SAME finalizer as every other run (ottoq_sim_release_depot: bookings
-- released, commands expired, legs closed, approvals expired, archive written), marks the
-- run completed with the reason -- and does NOT reset the physical world (production state
-- is reality, not a fixture).

INSERT INTO public.ottoq_scenarios (scenario_code, category, title, description)
SELECT 'production', 'normal_operations', 'Production orchestration session',
       'Continuous real-time orchestration over integrated vehicle/site state. Wall-clock tick via twin.ottoq_world_advance; synthetic feeds only where depots.feed_mode=''sim''.'
WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_scenarios WHERE scenario_code='production');

CREATE OR REPLACE FUNCTION public.ottoq_production_start(
  p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid
) RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_run uuid; v_scenario ottoq_scenarios%ROWTYPE; v_existing uuid; v_feed text;
BEGIN
  SELECT sim_run_id INTO v_existing FROM ottoq_sim_runs
   WHERE depot_id = p_depot AND status = 'running' LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_already_has_running_run',
                              'running_run', v_existing);
  END IF;

  SELECT * INTO v_scenario FROM ottoq_scenarios WHERE scenario_code = 'production';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'production_scenario_missing');
  END IF;

  INSERT INTO ottoq_sim_runs (
    sim_run_id, scenario_id, scenario_code, started_at, next_tick_due_at,
    sim_clock_start, sim_clock_current, sim_clock_end,
    time_scale, tick_interval_seconds, depot_id, random_seed,
    status, run_by, policy, demo_speed_x
  ) VALUES (
    gen_random_uuid(), v_scenario.scenario_id, 'production', now(), now(),
    now(), now(), now() + interval '100 years',
    1.0, 120, p_depot, 42,
    'running', 'production_live', 'otto_q', 1.0
  ) RETURNING sim_run_id INTO v_run;

  -- 0092 discipline: this transaction's events carry the session just created.
  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);

  -- Deterministic core only (founder directive): no LLM orchestrator, no cuOpt.
  -- cuopt_refresh already skips production_live structurally; the policy is the belt.
  PERFORM ottoq_policy_set('run', v_run, 'orchestrator_agent_enabled', 0, 'production_start');
  PERFORM ottoq_policy_set('run', v_run, 'cuopt_propose_enabled', 0, 'production_start');

  SELECT COALESCE(d.feed_mode, 'sim') INTO v_feed FROM depots d WHERE d.id = p_depot;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'production_start',
    p_event_type := 'production.session_started', p_entity_type := 'sim_run',
    p_payload := jsonb_build_object('depot_id', p_depot, 'feed_mode', v_feed,
                                    'tick', 'ottoq-depot-tick */2min -> twin.ottoq_world_advance (wall-elapsed) -> decide_and_dispatch'),
    p_severity := 'info', p_ingest_source := 'engine', p_data_source := 'production',
    p_sim_run_id := v_run);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', v_run, 'depot_id', p_depot,
    'feed_mode', v_feed, 'run_by', 'production_live', 'policy', 'otto_q',
    'driver', 'ottoq-depot-tick cron (*/2 min) -> twin.ottoq_world_advance -> ottoq_sim_decide_and_dispatch',
    'agents', 'quiesced (orchestrator_agent_enabled=0, cuopt_propose_enabled=0)');
END
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_production_stop(
  p_reason text DEFAULT 'operator_stop'
) RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_run uuid; v_release jsonb;
BEGIN
  SELECT sim_run_id INTO v_run FROM ottoq_sim_runs
   WHERE run_by = 'production_live' AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_running_production_session');
  END IF;

  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);

  -- The same finalizer every run gets: bookings released, commands expired (0087),
  -- legs closed (0089), plan residue stripped (0093), approvals expired (0097),
  -- archive written. NO world reset: production state is reality, not a fixture.
  v_release := ottoq_sim_release_depot(v_run, p_reason);

  UPDATE ottoq_sim_runs
     SET status = 'completed', ended_at = now(), failure_reason = p_reason
   WHERE sim_run_id = v_run;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'production_stop',
    p_event_type := 'production.session_stopped', p_entity_type := 'sim_run',
    p_payload := jsonb_build_object('reason', p_reason, 'release', v_release),
    p_severity := 'info', p_ingest_source := 'engine', p_data_source := 'production',
    p_sim_run_id := v_run);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', v_run, 'reason', p_reason,
                            'release', v_release);
END
$fn$;
