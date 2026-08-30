-- migration-version: 20260830113000
-- migration-name:    the_agent_gate_is_a_policy
-- 0112 -- completes the founder's "deterministic core only" posture for production
-- sessions. 0111's production_start sets run policy orchestrator_agent_enabled=0; this
-- migration makes the two Nemotron fire sites honor it:
--   A. public.ottoq_sim_decide_and_dispatch's orchestrator branch (the 0105 gate) -- fires
--      from inside every decide pass, production ticks included, every 3rd tick.
--   B. public.ottoq_cron_tick's N4 block -- fires the agent edge function against the depot
--      every ~10 minutes whenever any drivable run exists; it reads the policy off the
--      depot's newest running non-cert run (the run the agent would act on).
-- Default 1 everywhere: demo runs keep the agent exactly as before; only a session that
-- explicitly sets the policy to 0 (production_start today) quiesces it. cuOpt needs no gate
-- here -- cuopt_refresh's run resolution already excludes production_live, and
-- production_start sets cuopt_propose_enabled=0 as the belt.
--
-- Pre-image pins, read live 2026-08-30 (each anchor verified at exactly 1 occurrence):
--   public.ottoq_sim_decide_and_dispatch   6670c6e10d3127ffcfedcf9e59080b60  (post-0105)
--   public.ottoq_cron_tick                 bc17cc978b61b221ed7ab17412612949  (post-0106)

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  v_a_old text := 'AND v_run.policy IS NOT DISTINCT FROM ''otto_q''';
  v_a_new text := E'AND v_run.policy IS NOT DISTINCT FROM ''otto_q''\n'
               || '     AND ottoq_policy_get(p_sim_run_id, ''orchestrator_agent_enabled'', 1) > 0  -- 0112: deterministic-only sessions quiesce the agent';

  v_b_old text := 'IF EXTRACT(MINUTE FROM now())::int % 10 < 2 THEN';
  v_b_new text := E'IF EXTRACT(MINUTE FROM now())::int % 10 < 2\n'
               || E'     -- 0112: the agent is a policy, not a reflex. Read it off the run it would act on.\n'
               || E'     AND ottoq_policy_get((SELECT r.sim_run_id FROM ottoq_sim_runs r\n'
               || E'                            WHERE r.status=''running'' AND COALESCE(r.run_by,'''') <> ''cert_harness''\n'
               || E'                            ORDER BY r.started_at DESC LIMIT 1),\n'
               || E'                          ''orchestrator_agent_enabled'', 1) > 0 THEN';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_decide_and_dispatch';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '6670c6e10d3127ffcfedcf9e59080b60' THEN
    RAISE EXCEPTION '0112 abort: decide_and_dispatch drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_a_old,'')))/length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0112 abort: dispatch anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_a_old, v_a_new);
  IF position('deterministic-only sessions quiesce the agent' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0112 abort: dispatch patch did not survive';
  END IF;

  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cron_tick';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'bc17cc978b61b221ed7ab17412612949' THEN
    RAISE EXCEPTION '0112 abort: cron_tick drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_b_old,'')))/length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0112 abort: cron anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_b_old, v_b_new);
  IF position('the agent is a policy, not a reflex' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0112 abort: cron patch did not survive';
  END IF;

  RAISE NOTICE '0112 applied: the agent gate is a policy.';
END
$do$;
