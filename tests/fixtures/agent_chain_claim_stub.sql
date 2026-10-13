-- A stub engine for ottoq_agent_chain_claim (0332/0338; 0713). The claim below is the live definition byte for byte
-- (md5(pg_get_functiondef) aad09c12e9c8cd61d9ae4b527219439d on 2026-10-13); the tables carry only the columns it reads.
-- ottoq_policy_get keeps the live tier order (run, depot, global, the caller's literal) and NEVER reads the catalog's
-- default_value, which is the point 0713 turns on.
CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid, status text, tick_count integer,
  payload jsonb);
CREATE TABLE public.ottoq_decisions (sim_run_id uuid, tick_seq bigint, resolved_action_context text, context_frame jsonb);
CREATE TABLE public.ottoq_policy_params (scope_type text, scope_id uuid, param_key text, param_value numeric,
  updated_by text, updated_at timestamptz, PRIMARY KEY (scope_type, scope_id, param_key));
CREATE TABLE public.ottoq_policy_param_catalog (param_key text PRIMARY KEY, description text, default_value numeric,
  min_value numeric, max_value numeric, affects text, agent_writable boolean);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial, label text, object_kind text, schema_name text,
  object_name text, definition text, def_md5 text);
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean, note text, classified_at timestamptz);
CREATE FUNCTION public.ottoq_certification_in_flight(p boolean) RETURNS integer LANGUAGE sql AS $f$ SELECT 0 $f$;
CREATE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric) RETURNS numeric
LANGUAGE plpgsql AS $f$
DECLARE v numeric; v_depot uuid;
BEGIN
  SELECT param_value INTO v FROM ottoq_policy_params WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NOT NULL THEN
    SELECT param_value INTO v FROM ottoq_policy_params WHERE scope_type='depot' AND scope_id=v_depot AND param_key=p_param_key;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='global' AND scope_id='00000000-0000-0000-0000-000000000000'::uuid AND param_key=p_param_key;
  RETURN COALESCE(v, p_default);
END $f$;
INSERT INTO public.ottoq_policy_param_catalog VALUES ('agent_chain_inflight_timeout_s',
  'Real-second lease for one in-flight agent request per run. A later FIRE beat retries only after the prior agent decision is recorded or this lease expires.',
  45, 10, 120, 'ottoq_agent_chain_claim', false);
CREATE OR REPLACE FUNCTION public.ottoq_agent_chain_claim(p_sim_run_id uuid, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
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
END $function$;
