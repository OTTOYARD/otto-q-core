-- migration-version: 20260916194021
-- migration-name:    cp_sat_becomes_the_primary_agent_solver
--
-- The agent now sends one bounded objective to the deterministic CP-SAT
-- proposer. forward_lex owns the primary proposer seat; cuOpt remains a lower
-- priority fallback when the CP-SAT service or submission door fails. The
-- activity feed also joins the asynchronous fire receipt back to the agent's
-- chain id so the Twin can show the complete operational rationale without
-- exposing model chain-of-thought.
-- forces_recert: TRUE. Proposer precedence changes live tick behavior.

DO $preflight$
DECLARE v_jobs text; v_pairs integer; v_runs integer;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0335 P1: certification jobs are scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0335 P2: % certification pair(s) are active', v_pairs; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_runs > 0 THEN RAISE EXCEPTION '0335 P3: % Twin run(s) are active', v_runs; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence
                  WHERE source='forward_lex' AND rank=10 AND holds_tick AND greedy_yields)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence
                     WHERE source='cuopt' AND rank=0 AND holds_tick AND greedy_yields)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence
                     WHERE source='cuopt_fallback' AND rank=1 AND holds_tick) THEN
    RAISE EXCEPTION '0335 P4: proposer precedence moved from the 0259 baseline';
  END IF;
END $preflight$;

UPDATE public.ottoq_proposer_precedence
   SET rank = CASE source WHEN 'forward_lex' THEN 0 WHEN 'cuopt' THEN 10 ELSE 11 END,
       note = CASE source
         WHEN 'forward_lex' THEN '0335. Primary deterministic CP-SAT assignment proposer selected by the agent objective.'
         WHEN 'cuopt' THEN '0335. NVIDIA cuOpt specialist and service-failure fallback. Lower priority than CP-SAT.'
         ELSE '0335. Local cuOpt fallback. Lower priority than CP-SAT and hosted cuOpt.'
       END
 WHERE source IN ('forward_lex','cuopt','cuopt_fallback');

CREATE OR REPLACE FUNCTION public.ottoq_activity_feed(
  p_sim_run_id uuid,
  p_limit integer DEFAULT 200,
  p_vehicle_id uuid DEFAULT NULL
)
RETURNS TABLE (
  occurred_at timestamptz,
  vehicle_id uuid,
  display_name text,
  action text,
  engine text,
  target text,
  outcome text,
  rationale jsonb,
  reason text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
  SELECT
    d.sim_clock AS occurred_at,
    d.entity_id AS vehicle_id,
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN 'OTTO-Q PRIME' ELSE v.display_name END AS display_name,
    COALESCE(d.resolved_action_context,d.action_context) AS action,
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN COALESCE(d.proposed_action->>'model','deterministic_fallback') || ' -> ' ||
              COALESCE(f.effective_source,'cp_sat_forward_lex')
         ELSE COALESCE(NULLIF(d.l2_engine,''),d.proposed_action->>'source') END AS engine,
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN 'objective: ' || COALESCE(d.proposed_action->'solver'->>'objective','readiness_first')
         ELSE COALESCE(s.stall_code,d.enacted_action->>'verb',d.proposed_action->>'verb') END AS target,
    d.outcome_status AS outcome,
    CASE WHEN d.resolved_action_context='orchestrator_agent' THEN
      jsonb_strip_nulls(jsonb_build_object(
        'summary',d.enacted_action->>'rationale',
        'agent_model',d.proposed_action->>'model',
        'objective',d.proposed_action->'solver'->>'objective',
        'objective_why',d.proposed_action->'solver'->>'why',
        'solver_engine',COALESCE(f.effective_source,'cp_sat_forward_lex'),
        'handoff_status',d.enacted_action->'solver_handoff'->>'status',
        'solver_status',f.status,
        'planned',f.n_planned,
        'submitted',f.n_submitted,
        'retry_attempts',f.fire->'retry_attempts',
        'applied',d.enacted_action->'applied',
        'queued',d.enacted_action->'queued',
        'rejected',d.enacted_action->'rejected',
        'chain_id',d.proposed_action->>'agent_solver_chain_id'
      ))
      ELSE d.proposed_action->'rationale' END AS rationale,
    CASE
      WHEN d.resolved_action_context='orchestrator_agent'
        THEN COALESCE(d.enacted_action->>'rationale',d.proposed_action->'solver'->>'why')
      WHEN d.override_rule_codes IS NOT NULL AND cardinality(d.override_rule_codes)>0
        THEN 'blocked: ' || array_to_string(d.override_rule_codes,', ')
      WHEN d.proposed_action ? 'rationale'
       AND jsonb_typeof(d.proposed_action->'rationale') <> 'null'
        THEN (d.proposed_action->'rationale')::text
      WHEN jsonb_typeof(d.rule_results)='array' AND jsonb_array_length(d.rule_results)>0
        THEN COALESCE(d.rule_results->0->>'reason',d.rule_results->0->>'rule_code')
      ELSE COALESCE(NULLIF(d.l2_engine,''),d.proposed_action->>'source')
    END AS reason
  FROM public.ottoq_decisions d
  LEFT JOIN public.vehicles v ON v.id=d.entity_id AND d.entity_type='vehicle'
  LEFT JOIN public.stalls s ON s.id=CASE
    WHEN COALESCE(d.enacted_action->>'stall_id',d.proposed_action->>'stall_id','') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
    THEN COALESCE(d.enacted_action->>'stall_id',d.proposed_action->>'stall_id')::uuid
    ELSE NULL END
  LEFT JOIN LATERAL (
    SELECT l.effective_source,l.status,l.n_planned,l.n_submitted,l.fire
      FROM public.ottoq_proposer_fire_log l
     WHERE l.sim_run_id=d.sim_run_id
       AND l.fire->>'agent_chain_id'=d.proposed_action->>'agent_solver_chain_id'
     ORDER BY l.fired_at DESC,l.fire_id DESC LIMIT 1
  ) f ON d.resolved_action_context='orchestrator_agent'
  WHERE d.sim_run_id=p_sim_run_id
    AND (p_vehicle_id IS NULL OR d.entity_id=p_vehicle_id)
  ORDER BY d.sim_clock DESC,d.decision_seq DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit,200),1),500);
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_activity_feed(uuid,integer,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_activity_feed(uuid,integer,uuid) TO anon,authenticated,service_role;

COMMENT ON FUNCTION public.ottoq_activity_feed(uuid,integer,uuid) IS
'0335. Live read-only decision feed. Agent rows join their asynchronous CP-SAT fire receipt by chain id and expose operational rationale, objective, solver outcome and bounded retry summary. No private model chain-of-thought is stored or returned.';

INSERT INTO public.ottoq_cert_lineage(name,forces_recert,note,classified_at)
VALUES ('0335_cp_sat_becomes_the_primary_agent_solver',true,
  'forward_lex becomes rank 0 and cuOpt moves to fallback ranks. Activity feed change is read-only; precedence changes proposer selection.',now())
ON CONFLICT(name) DO NOTHING;

DO $assert$
DECLARE v_src text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence
                  WHERE source='forward_lex' AND rank=0 AND holds_tick AND greedy_yields)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence
                     WHERE source='cuopt' AND rank=10 AND holds_tick AND greedy_yields)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence
                     WHERE source='cuopt_fallback' AND rank=11 AND holds_tick) THEN
    RAISE EXCEPTION '0335 A1: CP-SAT primary precedence did not hold';
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_activity_feed'
     AND pg_get_function_identity_arguments(p.oid)='p_sim_run_id uuid, p_limit integer, p_vehicle_id uuid';
  IF v_src NOT LIKE '%agent_chain_id%' OR v_src NOT LIKE '%ottoq_proposer_fire_log%' THEN
    RAISE EXCEPTION '0335 A2: activity feed does not join the solver receipt';
  END IF;
  IF EXISTS (
       SELECT 1
         FROM pg_proc p
         CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) x
        WHERE p.oid='public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure
          AND x.grantee=0 AND x.privilege_type='EXECUTE')
     OR NOT has_function_privilege('anon','public.ottoq_activity_feed(uuid,integer,uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0335 A3: activity feed grants are not the narrow demo posture';
  END IF;
END $assert$;
