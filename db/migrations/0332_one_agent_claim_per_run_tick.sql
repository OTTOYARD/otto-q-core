-- migration-version: 20260916002025
-- migration-name:    one_agent_claim_per_run_tick
--
-- The first 0331 live run proved the chain itself, then exposed two entrances:
-- run 6700deec-dd17-4340-aa98-480338f844b6 recorded two Nemotron decisions at
-- tick 4 with conflicting energy-factor proposals. The metronome entered through
-- ottoq_cuopt_refresh, while ottoq_sim_decide_and_dispatch still posted the old
-- direct agent call. One chain per invocation is not enough if two invocations
-- can analyze the same world state.
--
-- 0332 closes both sides:
--   * the legacy decide-tick direct post stands down only in chain mode;
--   * the agent atomically claims (run,tick) in ottoq_sim_runs.payload before
--     any NVIDIA call, so cron/metronome races produce one analysis at most.
--
-- Production sessions keep agent_solver_chain_enabled=0 and retain their prior
-- behavior. Certification runs remain excluded. forces_recert: TRUE because the
-- number and ordering of live agent proposals changes.

DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0332 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0332 P-: a pair is active'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status='running';
  IF v_runs > 0 THEN RAISE EXCEPTION '0332 P-: % sim run(s) are active', v_runs; END IF;
END $inflight$;

DO $pre$
BEGIN
  IF to_regprocedure('public.ottoq_agent_solver_refresh(uuid,jsonb)') IS NULL
     OR to_regprocedure('public.ottoq_sim_decide_and_dispatch(uuid)') IS NULL THEN
    RAISE EXCEPTION '0332 P1: 0331 or the decide driver is missing';
  END IF;
  IF to_regprocedure('public.ottoq_agent_chain_claim(uuid,text)') IS NOT NULL THEN
    RAISE EXCEPTION '0332 P2: ottoq_agent_chain_claim already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key='agent_solver_chain_enabled') THEN
    RAISE EXCEPTION '0332 P3: chain policy is not catalogued';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0332_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_sim_decide_and_dispatch';

CREATE FUNCTION public.ottoq_agent_chain_claim(
  p_sim_run_id uuid,
  p_source text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE v_tick bigint; v_claimed bigint; v_enabled boolean;
BEGIN
  IF p_sim_run_id IS NULL OR NULLIF(p_source,'') IS NULL THEN
    RAISE EXCEPTION 'ottoq_agent_chain_claim: run and source are required'
      USING ERRCODE='22023';
  END IF;

  SELECT COALESCE(r.tick_count,0),
         public.ottoq_policy_get(r.sim_run_id,'agent_solver_chain_enabled',0) >= 1
    INTO v_tick, v_enabled
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id=p_sim_run_id AND r.status='running';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('claimed',false,'reason','run_not_running');
  END IF;
  IF NOT v_enabled THEN
    RETURN jsonb_build_object('claimed',true,'chain_enabled',false,'tick_seq',v_tick);
  END IF;

  UPDATE public.ottoq_sim_runs r
     SET payload = COALESCE(r.payload,'{}'::jsonb)
                 || jsonb_build_object('agent_chain_claim',jsonb_build_object(
                      'tick_seq',v_tick,
                      'claimed_at',clock_timestamp(),
                      'source',left(p_source,120)))
   WHERE r.sim_run_id=p_sim_run_id
     AND r.status='running'
     AND COALESCE((r.payload->'agent_chain_claim'->>'tick_seq')::bigint,-1) <> v_tick
  RETURNING r.tick_count INTO v_claimed;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('claimed',false,'reason','agent_tick_already_claimed','tick_seq',v_tick);
  END IF;
  RETURN jsonb_build_object('claimed',true,'chain_enabled',true,'tick_seq',v_tick);
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_agent_chain_claim(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_agent_chain_claim(uuid,text) FROM anon;
REVOKE ALL ON FUNCTION public.ottoq_agent_chain_claim(uuid,text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_chain_claim(uuid,text) TO service_role;

COMMENT ON FUNCTION public.ottoq_agent_chain_claim(uuid,text) IS
'0332. Atomic per-run, per-tick claim before an agent model call. Stored on the run payload so concurrent trigger transactions serialize on the run row. Chain-disabled sessions pass through unchanged. Service role only.';

-- The old direct agent fire remains available when chain mode is off. When the
-- chain is active, solver fire beats own the single entrance.
DO $decide_patch$
DECLARE v_def text; v_new text; a text; b text;
BEGIN
  SELECT pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure) INTO v_def;
  a := E'     AND ottoq_policy_get(p_sim_run_id, ''orchestrator_agent_enabled'', 1) > 0  -- 0112: deterministic-only sessions quiesce the agent\n'
    || E'     AND ( (COALESCE(v_run.tick_count,0) % 3) = 0';
  b := E'     AND ottoq_policy_get(p_sim_run_id, ''orchestrator_agent_enabled'', 1) > 0  -- 0112: deterministic-only sessions quiesce the agent\n'
    || E'     AND ottoq_policy_get(p_sim_run_id, ''agent_solver_chain_enabled'', 0) < 1  -- 0332: chain fire beats own the agent entrance\n'
    || E'     AND ( (COALESCE(v_run.tick_count,0) % 3) = 0';
  IF (length(v_def)-length(replace(v_def,a,'')))/length(a) <> 1 THEN
    RAISE EXCEPTION '0332 P4: decide agent-gate anchor is not unique';
  END IF;
  v_new := replace(v_def,a,b);
  EXECUTE v_new;
END $decide_patch$;

DO $assert$
DECLARE v_def text;
BEGIN
  SELECT prosrc INTO v_def FROM pg_proc
   WHERE oid='public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure;
  IF v_def !~ 'agent_solver_chain_enabled.*< 1' THEN
    RAISE EXCEPTION '0332 A1: legacy decide agent trigger did not stand down';
  END IF;
  IF has_function_privilege('anon','public.ottoq_agent_chain_claim(uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.ottoq_agent_chain_claim(uuid,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.ottoq_agent_chain_claim(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION '0332 A2: claim privileges are not service-role-only';
  END IF;
END $assert$;

INSERT INTO public.ottoq_cert_lineage(name,forces_recert,note,classified_at)
VALUES ('0332_one_agent_claim_per_run_tick',true,
  'Run 6700deec exposed two Nemotron decisions at tick 4 after 0331: the new solver-fire entrance and the legacy decide-tick direct post both ran. The legacy post now stands down in chain mode and a service-role RPC atomically claims each run tick before any model call. Production and certification behavior remain excluded; live Twin ordering changes, so recert is required.',now())
ON CONFLICT(name) DO NOTHING;
