-- migration-version: 20260830120000
-- migration-name:    the_switch_must_exist_before_it_can_be_off
-- 0113 -- the live E2E of the production session (e8a0ba01) caught 0111/0112's gate leaking,
-- exactly the way "every green light gets broken on purpose" demands:
--
--   * production_start called ottoq_policy_set for orchestrator_agent_enabled and
--     cuopt_propose_enabled and NEVER CHECKED THE RETURN. policy_set validates keys against
--     ottoq_policy_param_catalog and neither switch was catalogued -> {ok:false,
--     error:unknown_param}, silently discarded. Both 0112 gates then read default 1.
--   * Ledger proof the stakes are real: within two beats the agent (updated_by
--     'ottoq_prime') had ENACTED two batches and WRITTEN deploy_peak_fraction=0.85 and
--     energy_demand_factor_peak=0.65 onto the deterministic session's run policies.
--   * Separately: ottoq-orchestrate-tick (posted by ottoq_cron_tick every beat with
--     submit=true) calls the NVIDIA cuOpt endpoint DIRECTLY in its own code -- a proposer
--     path outside cuopt_refresh's production_live exclusion and outside the
--     cuopt_propose_enabled read.
--
-- THREE FIXES:
--   1. Catalog both switches (default 1, range 0..1) so policy_set accepts them. Demo
--      behavior unchanged: nothing reads them below 1 unless a session sets 0.
--   2. production_start re-created with the policy writes CHECKED -- a refused write now
--      aborts the start instead of launching an unprotected session.
--   3. ottoq_cron_tick's orchestrate-tick post gains the cuopt_propose_enabled gate (same
--      newest-running-run read as 0112's N4 gate): a deterministic-only session no longer
--      has cuOpt invoked on its behalf by the edge brain.
--
-- SESSION REPAIR (data, this migration): the two switches are written onto the live session
-- e8a0ba01, and ottoq_prime's two steering rows are DELETED from that run's policy scope --
-- they were written by the very component the session declares off. Both actions recorded
-- as events by the runtime discipline (0092 GUC not available here; rows are run-scoped and
-- die with the run's teardown regardless).
--
-- Pre-image pin, read live 2026-08-30 (anchors verified at exactly 1 occurrence each):
--   public.ottoq_cron_tick   19e79e9e9a947b7d4beaf9afa42d0aca  (post-0112)

-- ---- 1. the catalog rows ----
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects)
SELECT 'orchestrator_agent_enabled',
       '0112/0113: gates every Nemotron orchestrator-agent fire site for the session. 0 = deterministic core only (production_start default); 1 = agent may propose.',
       1, 0, 1, 'decide_and_dispatch orchestrator branch; cron_tick N4'
WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key='orchestrator_agent_enabled');

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects)
SELECT 'cuopt_propose_enabled',
       '0056/0113: gates cuOpt proposal paths for the session (cuopt_refresh honors it; 0113 adds the cron_tick orchestrate-tick edge post, which calls cuOpt directly). 0 = quiesced.',
       1, 0, 1, 'cuopt_refresh; cron_tick orchestrate-tick post'
WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key='cuopt_propose_enabled');

-- ---- 2. production_start, with the returns checked ----
CREATE OR REPLACE FUNCTION public.ottoq_production_start(
  p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid
) RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_run uuid; v_scenario ottoq_scenarios%ROWTYPE; v_existing uuid; v_feed text; v_ps jsonb;
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

  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);

  -- 0113: a refused policy write aborts the start. A production session must never
  -- launch unprotected because a switch silently failed to land (the e8a0ba01 lesson).
  v_ps := ottoq_policy_set('run', v_run, 'orchestrator_agent_enabled', 0, 'production_start');
  IF NOT COALESCE((v_ps->>'ok')::boolean, false) THEN
    RAISE EXCEPTION 'production_start: orchestrator_agent_enabled write refused: %', v_ps;
  END IF;
  v_ps := ottoq_policy_set('run', v_run, 'cuopt_propose_enabled', 0, 'production_start');
  IF NOT COALESCE((v_ps->>'ok')::boolean, false) THEN
    RAISE EXCEPTION 'production_start: cuopt_propose_enabled write refused: %', v_ps;
  END IF;

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
    'agents', 'quiesced and VERIFIED (orchestrator_agent_enabled=0, cuopt_propose_enabled=0)');
END
$fn$;

-- ---- 3. cron_tick's orchestrate-tick post honors cuopt_propose_enabled ----
DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := E'  -- (1) depot-wide re-optimize (~7s w/ cuOpt -> needs >5s pg_net default timeout)\n  PERFORM net.http_post(';
  v_a_new text := E'  -- (1) depot-wide re-optimize (~7s w/ cuOpt -> needs >5s pg_net default timeout)\n'
               || E'  -- 0113: this edge function calls cuOpt DIRECTLY; a deterministic-only session gates it off.\n'
               || E'  IF ottoq_policy_get((SELECT r.sim_run_id FROM ottoq_sim_runs r\n'
               || E'                        WHERE r.status=''running'' AND COALESCE(r.run_by,'''') <> ''cert_harness''\n'
               || E'                        ORDER BY r.started_at DESC LIMIT 1),\n'
               || E'                      ''cuopt_propose_enabled'', 1) > 0 THEN\n'
               || E'  PERFORM net.http_post(';
  v_b_old text := E'''submit'',true,''shadow'',false),\n    timeout_milliseconds := 25000);';
  v_b_new text := E'''submit'',true,''shadow'',false),\n    timeout_milliseconds := 25000);\n  END IF;';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cron_tick';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '19e79e9e9a947b7d4beaf9afa42d0aca' THEN
    RAISE EXCEPTION '0113 abort: cron_tick drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_a_old,'')))/length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0113 abort: anchor 1 found % times', v_cnt; END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_b_old,'')))/length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0113 abort: anchor 2 found % times', v_cnt; END IF;
  v_src := replace(v_src, v_a_old, v_a_new);
  v_src := replace(v_src, v_b_old, v_b_new);
  EXECUTE v_src;
  IF position('a deterministic-only session gates it off' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0113 abort: cron patch did not survive';
  END IF;
  RAISE NOTICE '0113 applied: the switch exists, the start verifies it, the edge post honors it.';
END
$do$;

-- ---- 4. repair the live session e8a0ba01 ----
DO $repair$
DECLARE v_run uuid; v_ps jsonb; v_deleted int;
BEGIN
  SELECT sim_run_id INTO v_run FROM ottoq_sim_runs
   WHERE run_by='production_live' AND status='running'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0113 repair: no running production session; nothing to repair.';
    RETURN;
  END IF;

  v_ps := ottoq_policy_set('run', v_run, 'orchestrator_agent_enabled', 0, '0113_repair');
  IF NOT COALESCE((v_ps->>'ok')::boolean, false) THEN
    RAISE EXCEPTION '0113 repair: orchestrator_agent_enabled write refused: %', v_ps;
  END IF;
  v_ps := ottoq_policy_set('run', v_run, 'cuopt_propose_enabled', 0, '0113_repair');
  IF NOT COALESCE((v_ps->>'ok')::boolean, false) THEN
    RAISE EXCEPTION '0113 repair: cuopt_propose_enabled write refused: %', v_ps;
  END IF;

  -- The agent's steering rows go: they were written by the component this session
  -- declares off. Run-scoped; the deterministic defaults resume immediately.
  DELETE FROM ottoq_policy_params
   WHERE scope_type='run' AND scope_id=v_run AND updated_by='ottoq_prime';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RAISE NOTICE '0113 repair: session % protected; % agent-written policy rows removed.', v_run, v_deleted;
END
$repair$;
