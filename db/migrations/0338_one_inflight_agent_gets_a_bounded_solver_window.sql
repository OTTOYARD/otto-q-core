-- migration-version: 20260917040000
-- migration-name:    one_inflight_agent_gets_a_bounded_solver_window
--
-- Live run 911a5d0d measured Nemotron at about 29 seconds. A one-beat refusal
-- window released candidates before the agent could hand them to a solver, and
-- every FIRE beat launched another agent request while the first was active.
-- This migration gives the single agent harness a six-beat bounded window and
-- prevents overlapping model calls. A crashed call expires after 45 seconds.

INSERT INTO public.ottoq_policy_param_catalog
  (param_key,description,default_value,min_value,max_value,affects)
VALUES
  ('agent_chain_inflight_timeout_s',
   'Real-second lease for one in-flight agent request per run. A later FIRE beat retries only after the prior agent decision is recorded or this lease expires.',
   45,10,120,'ottoq_agent_chain_claim')
ON CONFLICT (param_key) DO UPDATE SET
  description=EXCLUDED.description,
  default_value=EXCLUDED.default_value,
  min_value=EXCLUDED.min_value,
  max_value=EXCLUDED.max_value,
  affects=EXCLUDED.affects;

UPDATE public.ottoq_policy_param_catalog
   SET description='Maximum bounded deterministic beats that may yield to the active agent-selected solver before greedy fallback. 0 disables holds; agentic full mode sets 6.',
       affects='ottoq_agentic_arm; ottoq_cuopt_first_refusal_arm; ottoq_cuopt_defer_hold via ottoq_decide_tick'
 WHERE param_key='cuopt_first_refusal_max_defers';

CREATE OR REPLACE FUNCTION public.ottoq_agent_chain_claim(
  p_sim_run_id uuid,
  p_source text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE v_tick bigint; v_claimed bigint; v_enabled boolean;
        v_prev_tick bigint; v_prev_at timestamptz; v_done boolean := false;
        v_timeout_s integer;
BEGIN
  IF p_sim_run_id IS NULL OR NULLIF(p_source,'') IS NULL THEN
    RAISE EXCEPTION 'ottoq_agent_chain_claim: run and source are required'
      USING ERRCODE='22023';
  END IF;

  SELECT COALESCE(r.tick_count,0),
         public.ottoq_policy_get(r.sim_run_id,'agent_solver_chain_enabled',0) >= 1,
         CASE WHEN COALESCE(r.payload->'agent_chain_claim'->>'tick_seq','') ~ '^[0-9]+$'
              THEN (r.payload->'agent_chain_claim'->>'tick_seq')::bigint END,
         CASE WHEN COALESCE(r.payload->'agent_chain_claim'->>'claimed_at','') <> ''
              THEN (r.payload->'agent_chain_claim'->>'claimed_at')::timestamptz END
    INTO v_tick, v_enabled, v_prev_tick, v_prev_at
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id=p_sim_run_id AND r.status='running';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('claimed',false,'reason','run_not_running');
  END IF;
  IF NOT v_enabled THEN
    RETURN jsonb_build_object('claimed',true,'chain_enabled',false,'tick_seq',v_tick);
  END IF;

  v_timeout_s := GREATEST(10,
    public.ottoq_policy_get(p_sim_run_id,'agent_chain_inflight_timeout_s',45)::integer);
  IF v_prev_tick IS NOT NULL
     AND v_prev_at >= clock_timestamp() - make_interval(secs => v_timeout_s) THEN
    SELECT EXISTS (
      SELECT 1 FROM public.ottoq_decisions d
       WHERE d.sim_run_id=p_sim_run_id
         AND d.resolved_action_context='orchestrator_agent'
         AND COALESCE(CASE WHEN COALESCE(d.context_frame->>'agent_chain_trigger_tick','') ~ '^[0-9]+$'
                           THEN (d.context_frame->>'agent_chain_trigger_tick')::bigint END,
                      d.tick_seq) = v_prev_tick
    ) INTO v_done;
    IF NOT v_done THEN
      RETURN jsonb_build_object('claimed',false,'reason','agent_run_in_flight',
        'tick_seq',v_tick,'inflight_tick',v_prev_tick,'retry_after_s',v_timeout_s);
    END IF;
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

REVOKE ALL ON FUNCTION public.ottoq_agent_chain_claim(uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_chain_claim(uuid,text) TO service_role;

DO $arm$
DECLARE d text; old text; n integer;
BEGIN
  d := pg_get_functiondef('public.ottoq_agentic_arm(uuid,text)'::regprocedure);
  old := E'(''cuopt_first_refusal_max_defers'', 1::numeric)';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    EXECUTE replace(d,old,E'(''cuopt_first_refusal_max_defers'', 6::numeric)');
  ELSIF d NOT LIKE '%(''cuopt_first_refusal_max_defers'', 6::numeric)%' THEN
    RAISE EXCEPTION '0338 P1: arm cap anchor occurs % times', n;
  END IF;
END $arm$;

DO $assertions$
DECLARE d text;
BEGIN
  SELECT p.prosrc INTO d FROM pg_proc p
   WHERE p.oid='public.ottoq_agent_chain_claim(uuid,text)'::regprocedure;
  IF d NOT LIKE '%agent_run_in_flight%' OR d NOT LIKE '%agent_chain_inflight_timeout_s%' THEN
    RAISE EXCEPTION '0338 A1: in-flight lease is absent';
  END IF;
  SELECT p.prosrc INTO d FROM pg_proc p
   WHERE p.oid='public.ottoq_agentic_arm(uuid,text)'::regprocedure;
  IF d NOT LIKE '%(''cuopt_first_refusal_max_defers'', 6::numeric)%' THEN
    RAISE EXCEPTION '0338 A2: full agent arm does not grant the solver window';
  END IF;
  IF has_function_privilege('anon','public.ottoq_agent_chain_claim(uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.ottoq_agent_chain_claim(uuid,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.ottoq_agent_chain_claim(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION '0338 A3: claim privileges are not service-role-only';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name,forces_recert,note,classified_at)
VALUES ('0338_one_inflight_agent_gets_a_bounded_solver_window',true,
  'Serializes agent calls per run and extends full-agent first refusal from one to six bounded beats. Live assignment timing changes, so recertification is required.',now())
ON CONFLICT(name) DO NOTHING;
