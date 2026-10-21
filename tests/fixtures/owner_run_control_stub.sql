-- tests/fixtures/owner_run_control_stub.sql -- the three run-control doors 0721 reasons from (§1 (k), §17 (g)), as the LIVE
-- definitions, byte for byte (pg_get_functiondef): taken from tests/fixtures/run_control_grants_stub.sql as 0791's branch
-- carries it (read from live as base64 on 2026-10-17 at 14:07:41 UTC and decoded), md5-checked here on 2026-10-17 and
-- re-read on live the same day (SELECT only):
--   public.ottoq_production_start(uuid)     ea2945cbb0435c58ce73b4f5e038c501
--   public.ottoq_pause_run(uuid, text)      1e3ec33aca6f4f3b008a0d83bff08c51
--   public.ottoq_resume_run(uuid)           b693dc33284db3914381f89bd7f21724
-- 0721's P1 pins all three (pause and resume also as 0791 leaves them: 28cba3966f9831f23705fb5c2341e691 and
-- 3950a271cc07b6374a4fb2db70680e74). Created with check_function_bodies off: they name engine functions and tables the
-- owner stub does not carry, and the suite calls none of them (it inserts and updates runs as they do). Their grants are
-- not reproduced; nothing here reads them. Loaded by tests/test_ottocommand_executor_sql.py, before 0721.
SET check_function_bodies = off;

-- ── public.ottoq_production_start(uuid), pg_get_functiondef md5 ea2945cbb0435c58ce73b4f5e038c501 ──
CREATE OR REPLACE FUNCTION public.ottoq_production_start(p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_run uuid; v_scenario ottoq_scenarios%ROWTYPE; v_existing uuid; v_feed text; v_ps jsonb; v_inherited jsonb;
  v_int jsonb;
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

  -- 0719 (G437). Production takes the world as the operator door does: every running check is cancelled, and the world
  -- lock waits for their rollback. Without it a session started inside a sweep arm got no tick until the arm ended
  -- (pg_cron runs one job at a time here, G141). A check cancelled here re-runs after the session ends.
  v_int := public.ottoq_world_yield_to_start('production_start');
  SELECT sim_run_id INTO v_existing FROM ottoq_sim_runs
   WHERE depot_id = p_depot AND status = 'running' LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_already_has_running_run',
                              'running_run', v_existing, 'interrupted', v_int);
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

  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);

  -- 0629. THE SESSION IS ARMED, as an operator's run is. Chase, 2026-10-08 CT: "Agent should always be on when runs are
  -- activated, and definitely when actual vehicle data is integrated." The agent proposes; the kernel disposes.
  -- ottoq_agentic_arm raises on any write the setter refuses or clamps, so a session never starts half-armed (0113's
  -- rule, kept), and it sets the arm's three tick-counted dials for a 120-second tick. No write under an agent's name
  -- reaches this session's settings: ottoq_policy_set refuses it (production_never_self_tunes, CLAUDE.md rule 10).
  v_ps := public.ottoq_agentic_arm(v_run, 'production_start');

  -- 0629. What this session inherits that was last written under an agent's name, at this depot's scope or the global
  -- one. Reported for a person (rule 10); never changed here.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('scope_type', pp.scope_type, 'param_key', pp.param_key,
                                               'value', pp.param_value, 'updated_by', pp.updated_by,
                                               'updated_at', pp.updated_at)
                            ORDER BY pp.scope_type, pp.param_key), '[]'::jsonb)
    INTO v_inherited
    FROM public.ottoq_policy_params pp
   WHERE ((pp.scope_type = 'depot' AND pp.scope_id = p_depot) OR pp.scope_type = 'global')
     AND public.ottoq_is_agent_actor(pp.updated_by);

  SELECT COALESCE(d.feed_mode, 'sim') INTO v_feed FROM depots d WHERE d.id = p_depot;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'production_start',
    p_event_type := 'production.session_started', p_entity_type := 'sim_run',
    p_payload := jsonb_build_object('depot_id', p_depot, 'feed_mode', v_feed, 'agents', 'armed (0629)',
                                    'agent_written_settings_in_force', v_inherited, 'interrupted', v_int,
                                    'tick', 'ottoq-depot-tick */2min -> twin.ottoq_world_advance (wall-elapsed) -> decide_and_dispatch'),
    p_severity := 'info', p_ingest_source := 'engine', p_data_source := 'production',
    p_sim_run_id := v_run);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', v_run, 'depot_id', p_depot,
    'feed_mode', v_feed, 'run_by', 'production_live', 'policy', 'otto_q',
    'driver', 'ottoq-depot-tick cron (*/2 min) -> twin.ottoq_world_advance -> ottoq_sim_decide_and_dispatch',
    'agents', 'armed (0629): the agent proposes and the kernel disposes; no write under an agent''s name reaches this '
              'session''s settings',
    'arming', v_ps -> 'arming',
    'agent_written_settings_in_force', v_inherited, 'interrupted', v_int);
END
$function$
;


-- ── public.ottoq_pause_run(uuid, text), pg_get_functiondef md5 1e3ec33aca6f4f3b008a0d83bff08c51 ──
CREATE OR REPLACE FUNCTION public.ottoq_pause_run(p_sim_run_id uuid, p_reason text DEFAULT 'operator_pause'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run ottoq_sim_runs%ROWTYPE;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  IF v_run.status <> 'running' THEN
    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,
                              'note', 'run was not running');
  END IF;

  UPDATE ottoq_sim_runs
     SET status = 'paused',
         next_tick_due_at = NULL,
         payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('paused_at', clock_timestamp(), 'pause_reason', p_reason)
   WHERE sim_run_id = p_sim_run_id;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type := 'twin.sim_run_paused', p_entity_type := 'sim_run',
    p_entity_id := p_sim_run_id, p_depot_id := v_run.depot_id,
    p_payload := jsonb_build_object('reason', p_reason, 'tick_count', v_run.tick_count),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
    p_sim_run_id := p_sim_run_id);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'status', 'paused',
    'frozen_at_sim_clock', v_run.sim_clock_current, 'tick_count', v_run.tick_count);
END;
$function$
;


-- ── public.ottoq_resume_run(uuid), pg_get_functiondef md5 b693dc33284db3914381f89bd7f21724 ──
CREATE OR REPLACE FUNCTION public.ottoq_resume_run(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run ottoq_sim_runs%ROWTYPE; v_paused_at timestamptz; v_paused_s numeric;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  IF v_run.status <> 'paused' THEN
    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,
                              'note', 'run was not paused');
  END IF;

  v_paused_at := (v_run.payload->>'paused_at')::timestamptz;
  v_paused_s  := GREATEST(0, EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_paused_at, clock_timestamp()))));

  -- ⭐ RE-ANCHOR THE LIVE CLOCK. Without this the first tick after resume advances the
  -- sim clock by the entire paused interval (see migration comment).
  UPDATE ottoq_sim_runs
     SET status = 'running',
         last_tick_at = clock_timestamp(),
         next_tick_due_at = now(),
         payload = (COALESCE(payload,'{}'::jsonb) - 'paused_at' - 'pause_reason')
                   || jsonb_build_object('last_pause_seconds', round(v_paused_s, 2))
   WHERE sim_run_id = p_sim_run_id;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type := 'twin.sim_run_resumed', p_entity_type := 'sim_run',
    p_entity_id := p_sim_run_id, p_depot_id := v_run.depot_id,
    p_payload := jsonb_build_object('paused_seconds', round(v_paused_s, 2),
                                    'sim_clock_resumed_at', v_run.sim_clock_current),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
    p_sim_run_id := p_sim_run_id);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'status', 'running',
    'resumed_at_sim_clock', v_run.sim_clock_current,
    'paused_real_seconds', round(v_paused_s, 2),
    'clock_reanchored', true);
END;
$function$
;

RESET check_function_bodies;
