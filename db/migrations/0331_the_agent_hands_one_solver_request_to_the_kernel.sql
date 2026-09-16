-- migration-version: 20260916000638
-- migration-name:    the_agent_hands_one_solver_request_to_the_kernel
--
-- 0331  THE AGENT AND THE SOLVER WERE BOTH LIVE, BUT THEY WERE TWO PARALLEL
--       CALLERS. ONE CHAIN ID NOW CARRIES ANALYSIS -> SOLVE -> DISPOSE.
--
-- Live proof before this file, run 7ec82afc-d6d9-40f8-bb42-6a03d1c1745b:
--   * Nemotron wrote reasoned, bounded policy actions.
--   * cuOpt returned Optimal and its proposals reached decisions, bookings and
--     executed begin_charge commands.
--   * no row connected either fact. cuOpt fired on its own beat and Nemotron
--     fired on another. That is two working features, not one product process.
--
-- This file makes the handoff explicit and single-entry:
--   1. Twin start arming enables Nemotron, cuOpt and this chain at RUN scope.
--   2. Existing solver fire beats delegate to the agent while the chain is on.
--   3. ottoq_agent_solver_refresh sets a transaction-local handoff and calls the
--      existing cuOpt gate, preserving candidate selection and first refusal.
--   4. The edge request carries the handoff. edge:v26 stamps the chain id and
--      bounded solver objective onto every proposal; the kernel still disposes.
--
-- Production sessions remain quiesced: ottoq_production_start is not one of the
-- Twin start doors changed by 0323 and still writes both agent gates to zero.
-- Certification arms remain excluded by ottoq_agentic_arm's 42501 guard.
-- forces_recert: TRUE. Normal Twin runs now turn on live intelligence and the
-- cuOpt call ordering changes from independent to agent-owned.

DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0331 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0331 P-: a pair is active'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status='running';
  IF v_runs > 0 THEN RAISE EXCEPTION '0331 P-: % sim run(s) are active', v_runs; END IF;
END $inflight$;

DO $pre$
BEGIN
  IF to_regprocedure('public.ottoq_agentic_arm(uuid,text)') IS NULL
     OR to_regprocedure('public.ottoq_agentic_arming(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_cuopt_refresh(uuid)') IS NULL THEN
    RAISE EXCEPTION '0331 P1: one or more required functions are missing';
  END IF;
  IF to_regprocedure('public.ottoq_agent_solver_refresh(uuid,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION '0331 P2: ottoq_agent_solver_refresh already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key='agent_solver_chain_enabled') THEN
    RAISE EXCEPTION '0331 P3: agent_solver_chain_enabled is already catalogued';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0331_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public'
   AND p.proname IN ('ottoq_agentic_arm','ottoq_agentic_arming','ottoq_cuopt_refresh','ottoq_cron_tick');

INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES ('agent_solver_chain_enabled',
        '0331: one audited process owns agent analysis -> cuOpt solve -> deterministic disposal. Independent cuOpt refresh callers stand down while enabled.',
        0, 0, 1,
        'ottoq_agentic_arm; ottoq_agent_solver_refresh; ottoq_cuopt_refresh; ottoq-orchestrator-agent');

-- Expand the arming report and the all-or-nothing writer without replacing any
-- later edits to either function. Each anchor is the exact 0278 three-key list.
DO $arm_patch$
DECLARE v_def text; v_new text; old_report text; new_report text; old_arm text; new_arm text;
BEGIN
  old_report := E'      (''proposer_frame_facts'',           1::numeric,\n'
             || E'       ''0265: the frame carries the facts the door pre-filters on''),\n'
             || E'      (''proposer_hold_enabled'',          1::numeric,\n'
             || E'       ''0259/0262: one-tick right of first refusal for a non-cuOpt proposer''),\n'
             || E'      (''cuopt_first_refusal_max_defers'', 1::numeric,\n'
             || E'       ''0152 set the global tier to 0; without a run row nothing is ever armed'')';
  new_report := E'      (''agent_solver_chain_enabled'',     1::numeric,\n'
             || E'       ''0331: one chain owns analysis -> solve -> deterministic disposal''),\n'
             || E'      (''cuopt_propose_enabled'',          1::numeric,\n'
             || E'       ''0056/0113: the solver seat and first-refusal machinery are live''),\n'
             || E'      (''orchestrator_agent_enabled'',     1::numeric,\n'
             || E'       ''0112/0113: Nemotron is allowed to analyze and hand off''),\n'
             || old_report;

  SELECT pg_get_functiondef('public.ottoq_agentic_arming(uuid)'::regprocedure) INTO v_def;
  IF (length(v_def)-length(replace(v_def,old_report,'')))/length(old_report) <> 1 THEN
    RAISE EXCEPTION '0331 P4: arming-report anchor is not unique';
  END IF;
  v_new := replace(v_def,old_report,new_report);
  EXECUTE v_new;

  old_arm := E'      (''proposer_frame_facts'',           1::numeric),\n'
          || E'      (''proposer_hold_enabled'',          1::numeric),\n'
          || E'      (''cuopt_first_refusal_max_defers'', 1::numeric)';
  new_arm := E'      (''agent_solver_chain_enabled'',     1::numeric),\n'
          || E'      (''cuopt_propose_enabled'',          1::numeric),\n'
          || E'      (''orchestrator_agent_enabled'',     1::numeric),\n'
          || old_arm;

  SELECT pg_get_functiondef('public.ottoq_agentic_arm(uuid,text)'::regprocedure) INTO v_def;
  IF (length(v_def)-length(replace(v_def,old_arm,'')))/length(old_arm) <> 1 THEN
    RAISE EXCEPTION '0331 P5: arm-writer anchor is not unique';
  END IF;
  v_new := replace(v_def,old_arm,new_arm);
  EXECUTE v_new;
END $arm_patch$;

COMMENT ON FUNCTION public.ottoq_agentic_arm(uuid,text) IS
'0331. Arm one non-cert Twin run for the complete process: Nemotron analysis, one agent-owned solver request, proposal facts/hold, and deterministic disposal. All six run-scoped policy writes are receipt-checked and all-or-nothing.';

COMMENT ON FUNCTION public.ottoq_agentic_arming(uuid) IS
'0331. Reports whether all six controls for the complete agent -> solver -> deterministic process are in force. Certification arms remain cert_excluded.';

-- The service-role-only entrance used by the orchestrator edge function. The
-- transaction-local GUC lets the existing refresh function distinguish this
-- handoff from all independent callers without changing its public signature.
CREATE FUNCTION public.ottoq_agent_solver_refresh(
  p_sim_run_id uuid,
  p_agent_handoff jsonb
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE v_req bigint;
BEGIN
  IF p_sim_run_id IS NULL OR p_agent_handoff IS NULL
     OR NULLIF(p_agent_handoff->>'chain_id','') IS NULL THEN
    RAISE EXCEPTION 'ottoq_agent_solver_refresh: run and handoff.chain_id are required'
      USING ERRCODE='22023';
  END IF;
  IF public.ottoq_policy_get(p_sim_run_id,'agent_solver_chain_enabled',0) < 1 THEN
    PERFORM public.cuopt_log_gate(p_sim_run_id,'agent_chain_disabled',NULL,
      jsonb_build_object('chain_id',p_agent_handoff->>'chain_id'),clock_timestamp());
    RETURN NULL;
  END IF;
  PERFORM set_config('ottoq.agent_solver_handoff',p_agent_handoff::text,true);
  v_req := public.ottoq_cuopt_refresh(p_sim_run_id);
  RETURN v_req;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_agent_solver_refresh(uuid,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_agent_solver_refresh(uuid,jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.ottoq_agent_solver_refresh(uuid,jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_solver_refresh(uuid,jsonb) TO service_role;

COMMENT ON FUNCTION public.ottoq_agent_solver_refresh(uuid,jsonb) IS
'0331. The single agent-owned solver entrance. Carries a transaction-local audited handoff into the existing cuOpt gate, preserving candidate selection and first refusal. Service role only.';

-- Patch the existing gate in place. Independent callers delegate to the agent
-- while the chain is enabled; the wrapper above sets the handoff GUC and
-- therefore proceeds through the solver gate. A handoff never gets discarded
-- by the old solver-only debounce: the agent fire itself is already paced by
-- the metronome, cron, or decide fallback that called this function.
DO $refresh_patch$
DECLARE v_def text; v_new text; a_decl text; b_decl text; a_gate text; b_gate text;
        a_debounce text; b_debounce text; a_body text; b_body text; a_log text; b_log text;
BEGIN
  SELECT pg_get_functiondef('public.ottoq_cuopt_refresh(uuid)'::regprocedure) INTO v_def;

  a_decl := E'        v_tick bigint; v_sim timestamptz; v_cand uuid[]; v_armed int := 0;\nBEGIN';
  b_decl := E'        v_tick bigint; v_sim timestamptz; v_cand uuid[]; v_armed int := 0;\n'
         || E'        v_agent_handoff jsonb;\nBEGIN';
  IF (length(v_def)-length(replace(v_def,a_decl,'')))/length(a_decl) <> 1 THEN
    RAISE EXCEPTION '0331 P6: refresh declaration anchor is not unique';
  END IF;
  v_new := replace(v_def,a_decl,b_decl);

  a_gate := E'  -- DEBOUNCE (tunable). REAL domain on purpose: it throttles NVIDIA API spend,';
  b_gate := E'  -- 0331: independent solver beats stand down while the agent owns the chain.\n'
         || E'  BEGIN\n'
         || E'    v_agent_handoff := NULLIF(current_setting(''ottoq.agent_solver_handoff'',true),'''')::jsonb;\n'
         || E'  EXCEPTION WHEN OTHERS THEN v_agent_handoff := NULL; END;\n'
         || E'  IF public.ottoq_policy_get(v_run,''agent_solver_chain_enabled'',0) >= 1\n'
         || E'     AND v_agent_handoff IS NULL THEN\n'
         || E'    IF public.ottoq_policy_get(v_run,''orchestrator_agent_enabled'',0) < 1 THEN\n'
         || E'      PERFORM public.cuopt_log_gate(v_run,''agent_policy_disabled'',NULL,NULL,v_t0);\n'
         || E'      RETURN NULL;\n'
         || E'    END IF;\n'
         || E'    SELECT r.depot_id INTO v_depot FROM public.ottoq_sim_runs r\n'
         || E'     WHERE r.sim_run_id=v_run AND r.status=''running'';\n'
         || E'    IF v_depot IS NULL THEN\n'
         || E'      PERFORM public.cuopt_log_gate(v_run,''no_depot'',NULL,NULL,v_t0);\n'
         || E'      RETURN NULL;\n'
         || E'    END IF;\n'
         || E'    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets\n'
         || E'     WHERE name=''ottoq_anon_key'' LIMIT 1;\n'
         || E'    IF v_key IS NULL THEN\n'
         || E'      PERFORM public.cuopt_log_gate(v_run,''no_anon_key_in_vault'',NULL,NULL,v_t0);\n'
         || E'      RETURN NULL;\n'
         || E'    END IF;\n'
         || E'    SELECT net.http_post(\n'
         || E'      url := ''https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-orchestrator-agent'',\n'
         || E'      headers := jsonb_build_object(''Content-Type'',''application/json'',''Authorization'',''Bearer ''||v_key,''apikey'',v_key),\n'
         || E'      body := jsonb_build_object(''sim_run_id'',v_run,''depot_id'',v_depot),\n'
         || E'      timeout_milliseconds := 20000) INTO v_req;\n'
         || E'    PERFORM public.cuopt_log_gate(v_run,''delegated_to_agent_chain'',NULL,\n'
         || E'      jsonb_build_object(''request_id'',v_req,''fn'',''ottoq-orchestrator-agent''),v_t0);\n'
         || E'    RETURN v_req;\n'
         || E'  END IF;\n\n'
         || a_gate;
  IF (length(v_new)-length(replace(v_new,a_gate,'')))/length(a_gate) <> 1 THEN
    RAISE EXCEPTION '0331 P7: refresh gate anchor is not unique';
  END IF;
  v_new := replace(v_new,a_gate,b_gate);

  a_debounce := E'  v_debounce := GREATEST(1, ottoq_policy_get(v_run, ''cuopt_debounce_s'', 2)::int);\n'
             || E'  SELECT fired_at INTO v_last FROM ottoq_cuopt_fire_log WHERE sim_run_id = v_run;\n'
             || E'  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => v_debounce) THEN\n'
             || E'    PERFORM public.cuopt_log_gate(v_run, ''debounce'', NULL,\n'
             || E'      jsonb_build_object(''debounce_s'', v_debounce, ''last_fired_at'', v_last), v_t0);\n'
             || E'    RETURN NULL;\n'
             || E'  END IF;';
  b_debounce := E'  IF v_agent_handoff IS NULL THEN\n' || a_debounce || E'\n  END IF;';
  IF (length(v_new)-length(replace(v_new,a_debounce,'')))/length(a_debounce) <> 1 THEN
    RAISE EXCEPTION '0331 P8: refresh debounce anchor is not unique';
  END IF;
  v_new := replace(v_new,a_debounce,b_debounce);

  a_body := E'                               ''gate_sim_clock'', v_sim),';
  b_body := E'                               ''gate_sim_clock'', v_sim,\n'
         || E'                               ''agent_handoff'', v_agent_handoff),';
  IF (length(v_new)-length(replace(v_new,a_body,'')))/length(a_body) <> 1 THEN
    RAISE EXCEPTION '0331 P9: refresh request-body anchor is not unique';
  END IF;
  v_new := replace(v_new,a_body,b_body);

  a_log := E'                       ''deferred_to_cuopt'', v_armed), v_t0);';
  b_log := E'                       ''deferred_to_cuopt'', v_armed,\n'
        || E'                       ''agent_chain_id'', v_agent_handoff->>''chain_id''), v_t0);';
  IF (length(v_new)-length(replace(v_new,a_log,'')))/length(a_log) <> 1 THEN
    RAISE EXCEPTION '0331 P10: refresh ledger anchor is not unique';
  END IF;
  v_new := replace(v_new,a_log,b_log);
  EXECUTE v_new;
END $refresh_patch$;

-- ottoq_cron_tick historically bypassed ottoq_cuopt_refresh and posted a second
-- solver implementation directly. In chain mode it now enters through the same
-- refresh door as the metronome. Its separate ten-minute agent post also stands
-- down, preventing two agent analyses for one cron beat.
DO $cron_patch$
DECLARE v_def text; v_new text; a_gate text; b_gate text; a_else text; b_else text;
        a_agent text; b_agent text;
BEGIN
  SELECT pg_get_functiondef('public.ottoq_cron_tick()'::regprocedure) INTO v_def;

  a_gate := E'  IF ottoq_policy_get(v_prun, ''cuopt_propose_enabled'', 1) > 0 THEN';
  b_gate := E'  IF ottoq_policy_get(v_prun, ''cuopt_propose_enabled'', 1) > 0\n'
         || E'     AND ottoq_policy_get(v_prun, ''agent_solver_chain_enabled'', 0) < 1 THEN';
  IF (length(v_def)-length(replace(v_def,a_gate,'')))/length(a_gate) <> 1 THEN
    RAISE EXCEPTION '0331 P11: cron solver gate anchor is not unique';
  END IF;
  v_new := replace(v_def,a_gate,b_gate);

  a_else := E'  ELSIF v_prun IS NOT NULL THEN\n  -- 0240: a CLOSED gate is a fact too.';
  b_else := E'  ELSIF v_prun IS NOT NULL\n'
         || E'     AND ottoq_policy_get(v_prun, ''cuopt_propose_enabled'', 1) > 0\n'
         || E'     AND ottoq_policy_get(v_prun, ''agent_solver_chain_enabled'', 0) >= 1 THEN\n'
         || E'    v_req := public.ottoq_cuopt_refresh(v_prun);\n'
         || E'  ELSIF v_prun IS NOT NULL THEN\n'
         || E'  -- 0240: a CLOSED gate is a fact too.';
  IF (length(v_new)-length(replace(v_new,a_else,'')))/length(a_else) <> 1 THEN
    RAISE EXCEPTION '0331 P12: cron chain delegation anchor is not unique';
  END IF;
  v_new := replace(v_new,a_else,b_else);

  a_agent := E'  IF EXTRACT(MINUTE FROM now())::int % 10 < 2\n'
          || E'     -- 0112: the agent is a policy, not a reflex.';
  b_agent := E'  IF EXTRACT(MINUTE FROM now())::int % 10 < 2\n'
          || E'     AND ottoq_policy_get(v_prun, ''agent_solver_chain_enabled'', 0) < 1\n'
          || E'     -- 0112: the agent is a policy, not a reflex.';
  IF (length(v_new)-length(replace(v_new,a_agent,'')))/length(a_agent) <> 1 THEN
    RAISE EXCEPTION '0331 P13: cron legacy-agent anchor is not unique';
  END IF;
  v_new := replace(v_new,a_agent,b_agent);
  EXECUTE v_new;
END $cron_patch$;

DO $assert$
DECLARE v_arm text; v_report text; v_refresh text; v_cron text; v_n int;
BEGIN
  SELECT prosrc INTO v_arm FROM pg_proc WHERE oid='public.ottoq_agentic_arm(uuid,text)'::regprocedure;
  SELECT prosrc INTO v_report FROM pg_proc WHERE oid='public.ottoq_agentic_arming(uuid)'::regprocedure;
  SELECT prosrc INTO v_refresh FROM pg_proc WHERE oid='public.ottoq_cuopt_refresh(uuid)'::regprocedure;
  SELECT prosrc INTO v_cron FROM pg_proc WHERE oid='public.ottoq_cron_tick()'::regprocedure;

  IF v_arm !~ 'agent_solver_chain_enabled' OR v_arm !~ 'orchestrator_agent_enabled'
     OR v_arm !~ 'cuopt_propose_enabled' THEN
    RAISE EXCEPTION '0331 A1: full arm does not write all three execution controls';
  END IF;
  IF v_report !~ 'agent_solver_chain_enabled' OR v_report !~ 'orchestrator_agent_enabled'
     OR v_report !~ 'cuopt_propose_enabled' THEN
    RAISE EXCEPTION '0331 A2: arming report does not measure all three execution controls';
  END IF;
  IF v_refresh !~ 'delegated_to_agent_chain' OR v_refresh !~ 'agent_handoff' THEN
    RAISE EXCEPTION '0331 A3: cuOpt refresh lacks delegation or handoff';
  END IF;
  IF v_cron !~ 'agent_solver_chain_enabled' OR v_cron !~ 'ottoq_cuopt_refresh' THEN
    RAISE EXCEPTION '0331 A4: cron still bypasses the single chain entrance';
  END IF;
  IF has_function_privilege('anon','public.ottoq_agent_solver_refresh(uuid,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','public.ottoq_agent_solver_refresh(uuid,jsonb)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.ottoq_agent_solver_refresh(uuid,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION '0331 A5: wrapper privileges are not service-role-only';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key='agent_solver_chain_enabled' AND scope_type <> 'run';
  IF v_n <> 0 THEN RAISE EXCEPTION '0331 A6: chain key leaked outside run scope'; END IF;
END $assert$;

INSERT INTO public.ottoq_cert_lineage(name,forces_recert,note,classified_at)
VALUES ('0331_the_agent_hands_one_solver_request_to_the_kernel',true,
  'Live run 7ec82afc proved Nemotron and cuOpt both worked but as parallel callers. Twin arming now enables a single agent-owned solver chain; independent solver beats delegate to the agent, the handoff carries a chain id and bounded objective, and the existing deterministic kernel still disposes every proposal. Production_start remains quiesced and cert_harness remains excluded. Normal Twin behavior changes, so recert is required.',now())
ON CONFLICT(name) DO NOTHING;
