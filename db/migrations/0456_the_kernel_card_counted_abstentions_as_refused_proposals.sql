-- migration-version: 20260923062252
-- migration-name:    the_kernel_card_counted_abstentions_as_refused_proposals
--
-- 0456  **The Intelligence panel's L4 card counted the proposer's abstentions as proposals the kernel refused.**
--       `db/checks/0356` §5. FINDINGS G189.
--
--   The forward_lex bridge writes an `ottoq_external_proposals` row with `proposal->>'abstain' = true` for every
--   entity it declines to place on a tick -- "outside this tick's batch of 8 most urgent", "planned to start at
--   +455 min ... beyond this tick's 30-min window". The kernel files those as `refused` (`proposer_abstained`) or
--   `superseded`. `ottoq_intelligence_stack` counted every row as a proposal, so run 736406cf's L4 card read
--   **377 proposals · 0 enacted · 182 refused · 48% refusal · status refusing_all**. Measured from the same rows:
--   **367 abstentions and 10 offers; of the 10, 3 refused (stall occupied 2, stall reserved 1) and 7 superseded
--   by the decide path.** A refusal rate of 48% described a proposer declining to speak, not a kernel saying no.
--
--   FIX: L4 counts offers only in proposals / enacted / refused / superseded / expired / refusal_rate_pct, adds
--   `abstentions`, `pending`, `rows` and `top_abstain_reasons`, and keeps abstentions out of `top_refusal_reasons`.
--   Status gains `abstaining` (rows but no offers) and `none_enacted` (offers, none enacted); `refusing_all` keeps
--   its literal meaning. Every other layer is byte-for-byte the 0451 body. Same signature; `forces_recert` FALSE:
--   a read-only reporting function no tick path calls and no atom reads.

BEGIN;

-- ── P0: no pair in flight (a live demo run is fine: nothing here is on a tick path) ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0456 P0: a pair is running right now'; END IF;
END $inflight$;

-- ── P2: the 0451 body this corrects ──
DO $premises$
BEGIN
  PERFORM 1 FROM pg_proc p WHERE p.oid = 'public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure
     AND p.prosrc LIKE '%ottoq_rule_evaluation_effect%' AND p.prosrc NOT LIKE '%abstentions%';
  IF NOT FOUND THEN RAISE EXCEPTION '0456 P2: ottoq_intelligence_stack is not the 0451 body this file corrects'; END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0456_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure;

-- ═══ the corrected stack ════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_intelligence_stack(p_sim_run_id uuid, p_include_frame boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run RECORD;
  v_arming jsonb; v_frame jsonb; v_review jsonb;
  v_shield jsonb; v_agent jsonb; v_solver jsonb; v_kernel jsonb; v_ingress jsonb;
  v_layers jsonb;
  -- Every jsonb_object_agg below COALESCEs its key: a NULL key raises 22023 at runtime (0351 A5).
  v_null_key_guard constant text := 'unspecified';
BEGIN
  SELECT sim_run_id, status, tick_count, sim_clock_current, scenario_code,
         depot_id, demo_speed_x, started_at, run_by
    INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL THEN
    RETURN jsonb_build_object('error','unknown_run','sim_run_id',p_sim_run_id);
  END IF;

  v_arming := public.ottoq_agentic_arming(p_sim_run_id);

  SELECT jsonb_build_object(
    'packets', count(*),
    'vehicles_reporting', count(DISTINCT vehicle_id),
    'integrity', (SELECT jsonb_object_agg(COALESCE(packet_integrity,v_null_key_guard), c) FROM (
        SELECT packet_integrity, count(*) c FROM ottoq_telemetry_packets
         WHERE sim_run_id = p_sim_run_id GROUP BY 1 ORDER BY c DESC LIMIT 5) i),
    'dropped', count(*) FILTER (WHERE packet_integrity = 'dropped'),
    'signal_below_50pct', count(*) FILTER (WHERE signal_strength_pct < 50)
  ) INTO v_ingress FROM ottoq_telemetry_packets WHERE sim_run_id = p_sim_run_id;

  -- 0451 (1): what the shield REFUSED is what the engine acted on (0430's effect view), not what failed.
  WITH e AS (
    SELECT rule_code, action_context, passed, enforcement, effect
      FROM public.ottoq_rule_evaluation_effect WHERE sim_run_id = p_sim_run_id)
  SELECT jsonb_build_object(
    'evaluations',     count(*),
    'failed',          count(*) FILTER (WHERE passed IS FALSE),
    'blocked',         count(*) FILTER (WHERE effect = 'refused'),
    'refused',         count(*) FILTER (WHERE effect = 'refused'),
    'recorded_only',   count(*) FILTER (WHERE effect = 'recorded_only'),
    'advisory_failed', count(*) FILTER (WHERE passed IS FALSE AND COALESCE(enforcement,'') <> 'block'),
    'distinct_rules',  count(DISTINCT rule_code),
    'overridden', (SELECT count(*) FROM ottoq_rule_evaluations
                    WHERE sim_run_id = p_sim_run_id AND override_id IS NOT NULL),
    'by_probe_point', (SELECT jsonb_object_agg(COALESCE(action_context,v_null_key_guard), c) FROM (
        SELECT action_context, count(*) c FROM e GROUP BY 1 ORDER BY c DESC LIMIT 12) p),
    'top_blocking_rules', (SELECT jsonb_object_agg(COALESCE(rule_code,v_null_key_guard), c) FROM (
        SELECT rule_code, count(*) c FROM e WHERE effect = 'refused'
         GROUP BY 1 ORDER BY c DESC LIMIT 5) b),
    'top_failing_rules', (SELECT jsonb_object_agg(COALESCE(k,v_null_key_guard), c) FROM (
        SELECT rule_code || ' (' || COALESCE(enforcement,'?') || ')' AS k, count(*) c FROM e
         WHERE passed IS FALSE GROUP BY 1 ORDER BY c DESC LIMIT 5) f)
  ) INTO v_shield FROM e;

  SELECT jsonb_build_object(
    'chains', count(*),
    'model', (SELECT COALESCE(d2.proposed_action->>'model','none') FROM ottoq_decisions d2
               WHERE d2.sim_run_id = p_sim_run_id AND d2.resolved_action_context='orchestrator_agent'
               ORDER BY d2.tick_seq DESC, d2.decision_seq DESC LIMIT 1),
    'latest_source', (SELECT d6.enacted_action->>'source' FROM ottoq_decisions d6
               WHERE d6.sim_run_id = p_sim_run_id AND d6.resolved_action_context='orchestrator_agent'
               ORDER BY d6.tick_seq DESC, d6.decision_seq DESC LIMIT 1),
    'objective', (SELECT d3.proposed_action->'solver'->>'objective' FROM ottoq_decisions d3
                   WHERE d3.sim_run_id = p_sim_run_id AND d3.resolved_action_context='orchestrator_agent'
                   ORDER BY d3.tick_seq DESC, d3.decision_seq DESC LIMIT 1),
    'objective_why', (SELECT d4.proposed_action->'solver'->>'why' FROM ottoq_decisions d4
                   WHERE d4.sim_run_id = p_sim_run_id AND d4.resolved_action_context='orchestrator_agent'
                   ORDER BY d4.tick_seq DESC, d4.decision_seq DESC LIMIT 1),
    -- compute time of a pass, NOT a wait: the tick never blocks on the agent (0332)
    'avg_latency_ms', round(avg(total_latency_ms)),
    'max_latency_ms', max(total_latency_ms),
    'model_fallbacks', count(*) FILTER (WHERE enacted_action->>'source' = 'deterministic_fallback'),
    'last_model_error', (SELECT substring(d7.enacted_action->>'rationale' FROM '\(([^)]*)\)')
          FROM ottoq_decisions d7
         WHERE d7.sim_run_id = p_sim_run_id AND d7.resolved_action_context='orchestrator_agent'
           AND d7.enacted_action->>'source' = 'deterministic_fallback'
         ORDER BY d7.tick_seq DESC, d7.decision_seq DESC LIMIT 1),
    'by_source', (SELECT jsonb_object_agg(COALESCE(src,v_null_key_guard), c) FROM (
        SELECT enacted_action->>'source' src, count(*) c FROM ottoq_decisions
         WHERE sim_run_id = p_sim_run_id AND resolved_action_context='orchestrator_agent'
         GROUP BY 1 ORDER BY c DESC LIMIT 4) s),
    'handoff', (SELECT jsonb_object_agg(COALESCE(k,v_null_key_guard), c) FROM (
        SELECT COALESCE(enacted_action->'solver_handoff'->>'status','none')
               ||CASE WHEN enacted_action->'solver_handoff'->>'engine' IS NOT NULL
                      THEN ' -> '||(enacted_action->'solver_handoff'->>'engine') ELSE '' END AS k,
               count(*) c
          FROM ottoq_decisions
         WHERE sim_run_id = p_sim_run_id AND resolved_action_context='orchestrator_agent'
         GROUP BY 1 ORDER BY c DESC LIMIT 4) h),
    'last_fallback_reason', (SELECT d5.enacted_action->'solver_handoff'->>'fallback_reason'
          FROM ottoq_decisions d5
         WHERE d5.sim_run_id = p_sim_run_id AND d5.resolved_action_context='orchestrator_agent'
           AND d5.enacted_action->'solver_handoff'->>'fallback_reason' IS NOT NULL
         ORDER BY d5.tick_seq DESC LIMIT 1),
    -- 0451 (1): what lateness actually costs is staleness, measured by the provenance view (0417)
    'advice_applied', (SELECT count(*) FROM public.ottoq_agent_advice_provenance v
                        WHERE v.sim_run_id = p_sim_run_id AND v.staleness_class = 'applied'),
    'advice_mean_ticks_late', (SELECT round(avg(v.staleness_ticks), 1) FROM public.ottoq_agent_advice_provenance v
                        WHERE v.sim_run_id = p_sim_run_id AND v.staleness_class = 'applied'),
    'advice_p95_ticks_late', (SELECT percentile_disc(0.95) WITHIN GROUP (ORDER BY v.staleness_ticks)
                        FROM public.ottoq_agent_advice_provenance v
                        WHERE v.sim_run_id = p_sim_run_id AND v.staleness_class = 'applied')
  ) INTO v_agent FROM ottoq_decisions d
   WHERE d.sim_run_id = p_sim_run_id AND d.resolved_action_context = 'orchestrator_agent';

  -- 0451 (1): THIS run's proposer calls. The lifetime ledger answers a different question.
  SELECT jsonb_build_object(
    'declared_primary', (SELECT source FROM ottoq_proposer_precedence ORDER BY rank, source LIMIT 1),
    'primary_reachable', v_arming -> 'primary_proposer' -> 'reachable',
    'primary_fires', v_arming -> 'primary_proposer' -> 'fires',
    'providers', (SELECT jsonb_object_agg(COALESCE(provider,v_null_key_guard), jsonb_build_object(
                    'calls', calls, 'reached', reached, 'answered', answered,
                    'proposals', proposals, 'last_call', last_call))
                   FROM (SELECT z.provider,
                                count(*) AS calls,
                                count(*) FILTER (WHERE z.http_status IS NOT NULL) AS reached,
                                count(*) FILTER (WHERE public.ottoq_model_call_outcome_class(z.outcome) = 'answered') AS answered,
                                COALESCE(sum(z.proposals_out),0) AS proposals,
                                max(z.called_at) AS last_call
                           FROM public.ottoq_model_call_ledger z
                          WHERE z.sim_run_id = p_sim_run_id AND z.role = 'proposer'
                          GROUP BY z.provider) pr),
    'fires_this_run', (SELECT count(*) FROM ottoq_proposer_fire_log WHERE sim_run_id = p_sim_run_id)
  ) INTO v_solver;

  --: 0456: AN ABSTENTION IS NOT A PROPOSAL. The proposer writes a row with proposal->>'abstain' = true for every
  --: entity it declines to place this tick ("outside this tick's batch of 8", "not due yet"), and the kernel files
  --: those as refused (proposer_abstained) or superseded. Counted as proposals they made run 736406cf read
  --: 377 proposals / 182 refused / 48% refusal, when the proposer had offered 10 assignments and the kernel
  --: refused 3. Proposals and refusals now count offers only; abstentions are their own count.
  SELECT jsonb_build_object(
    'proposals', count(*) FILTER (WHERE NOT COALESCE((proposal->>'abstain')::boolean, false)),
    'enacted', count(*) FILTER (WHERE status = 'enacted' AND NOT COALESCE((proposal->>'abstain')::boolean, false)),
    'refused', count(*) FILTER (WHERE status = 'refused' AND NOT COALESCE((proposal->>'abstain')::boolean, false)),
    'superseded', count(*) FILTER (WHERE status = 'superseded' AND NOT COALESCE((proposal->>'abstain')::boolean, false)),
    'expired', count(*) FILTER (WHERE status = 'expired' AND NOT COALESCE((proposal->>'abstain')::boolean, false)),
    'pending', count(*) FILTER (WHERE status NOT IN ('enacted','refused','superseded','expired')
                                  AND NOT COALESCE((proposal->>'abstain')::boolean, false)),
    'abstentions', count(*) FILTER (WHERE COALESCE((proposal->>'abstain')::boolean, false)),
    'rows', count(*),
    'refusal_rate_pct', CASE WHEN count(*) FILTER (WHERE NOT COALESCE((proposal->>'abstain')::boolean, false)) > 0
        THEN round(100.0 * count(*) FILTER (WHERE status='refused' AND NOT COALESCE((proposal->>'abstain')::boolean, false))
                   / count(*) FILTER (WHERE NOT COALESCE((proposal->>'abstain')::boolean, false))) END,
    'by_source_status', (SELECT jsonb_object_agg(COALESCE(k,v_null_key_guard), c) FROM (
        SELECT COALESCE(source,'?')||'/'||CASE WHEN COALESCE((proposal->>'abstain')::boolean, false)
                                               THEN 'abstained' ELSE COALESCE(status,'?') END k, count(*) c
          FROM ottoq_external_proposals WHERE sim_run_id = p_sim_run_id
         GROUP BY 1 ORDER BY c DESC LIMIT 8) bs),
    'top_refusal_reasons', (SELECT jsonb_object_agg(COALESCE(dr,v_null_key_guard), c) FROM (
        SELECT disposition_reason dr, count(*) c FROM ottoq_external_proposals
         WHERE sim_run_id = p_sim_run_id AND status IN ('refused','superseded','expired')
           AND NOT COALESCE((proposal->>'abstain')::boolean, false)
         GROUP BY 1 ORDER BY c DESC LIMIT 5) rr),
    --: why the proposer declined, from its own tag (abstained_by) or the head of its reason
    'top_abstain_reasons', (SELECT jsonb_object_agg(COALESCE(ar,v_null_key_guard), c) FROM (
        SELECT COALESCE(proposal->'rationale'->>'abstained_by',
                        substring(proposal->'rationale'->>'reason' FROM '^[^;(]{1,60}')) ar, count(*) c
          FROM ottoq_external_proposals
         WHERE sim_run_id = p_sim_run_id AND COALESCE((proposal->>'abstain')::boolean, false)
         GROUP BY 1 ORDER BY c DESC LIMIT 5) ab)
  ) INTO v_kernel FROM ottoq_external_proposals WHERE sim_run_id = p_sim_run_id;

  v_layers := jsonb_build_array(
    jsonb_build_object(
      'layer','L0_INGRESS','name','Asset telemetry',
      'does','What the assets pushed. One writer, so a real OEM feed swaps in unchanged.',
      'measured_from','ottoq_telemetry_packets',
      'status', CASE WHEN COALESCE((v_ingress->>'packets')::bigint,0) = 0 THEN 'inactive'
                     WHEN COALESCE((v_ingress->>'dropped')::bigint,0) > 0 THEN 'degraded'
                     ELSE 'ok' END,
      'live', v_ingress),
    jsonb_build_object(
      'layer','L1_SHIELD','name','Deterministic rules (L1)',
      'does','Defines which actions are FEASIBLE. Blocked counts refusals the engine acted on; a failed advisory rule is recorded, not refused.',
      'measured_from','ottoq_rule_evaluation_effect (0430)',
      'status', CASE WHEN COALESCE((v_shield->>'evaluations')::bigint,0) = 0 THEN 'inactive'
                     ELSE 'ok' END,
      'live', v_shield),
    jsonb_build_object(
      'layer','L2_AGENT','name','Orchestrator agent',
      'does','Reads the frame, picks an objective, writes bounded policy. Proposes; never disposes. Runs beside the tick and never holds it.',
      'measured_from','ottoq_decisions (resolved_action_context=orchestrator_agent) + ottoq_agent_advice_provenance',
      'status', CASE WHEN COALESCE((v_agent->>'chains')::bigint,0) = 0 THEN 'inactive'
                     WHEN v_agent->>'latest_source' = 'deterministic_fallback' THEN 'model_unavailable'
                     ELSE 'ok' END,
      'live', v_agent),
    jsonb_build_object(
      'layer','L3_SOLVER','name','Proposers',
      'does','Propose stall assignments for the kernel to dispose. CP-SAT is primary inside the site; cuOpt proposes as a fallback. Nondeterministic by nature, which is why L4 exists.',
      'measured_from','ottoq_model_call_ledger (this run, role=proposer) + ottoq_proposer_fire_log',
      'status', CASE WHEN (v_solver->'primary_reachable')::text = 'false' THEN 'primary_unreachable'
                     WHEN COALESCE((v_solver->>'fires_this_run')::bigint,0) = 0 THEN 'primary_idle'
                     ELSE 'ok' END,
      'live', v_solver),
    jsonb_build_object(
      'layer','L4_KERNEL','name','Deterministic disposal',
      'does','Disposes every proposal. Refusing some is the point: all-enacted is a rubber stamp.',
      'measured_from','ottoq_external_proposals',
      --: 0456: only abstentions -> 'abstaining' (the proposer offered nothing); offers with none enacted ->
      --: 'none_enacted' (which says nothing about WHY: refused and superseded are different outcomes);
      --: 'refusing_all' is kept for its literal meaning, every offer refused.
      'status', CASE WHEN COALESCE((v_kernel->>'rows')::bigint,0) = 0 THEN 'inactive'
                     WHEN COALESCE((v_kernel->>'proposals')::bigint,0) = 0 THEN 'abstaining'
                     WHEN COALESCE((v_kernel->>'refused')::bigint,0) = COALESCE((v_kernel->>'proposals')::bigint,0)
                       THEN 'refusing_all'
                     WHEN COALESCE((v_kernel->>'enacted')::bigint,0) = 0 THEN 'none_enacted'
                     ELSE 'ok' END,
      'live', v_kernel));

  IF p_include_frame THEN
    v_frame  := public.ottoq_agent_asset_depth(
                  p_sim_run_id, v_run.depot_id, v_run.sim_clock_current, 10, 10);
    v_review := public.ottoq_agent_review(p_sim_run_id, 3);
  END IF;

  RETURN jsonb_build_object(
    'run', jsonb_build_object(
      'sim_run_id', v_run.sim_run_id, 'status', v_run.status,
      'tick', v_run.tick_count, 'sim_clock', v_run.sim_clock_current,
      'scenario', v_run.scenario_code, 'speed_x', v_run.demo_speed_x,
      'started_at', v_run.started_at, 'run_by', v_run.run_by),
    'arming', v_arming - 'keys',
    'layers', v_layers,
    'frame',  v_frame,
    'review', v_review,
    'frame_included', p_include_frame);
END $function$;

-- ═══ verification ═════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_run uuid; v_l4 jsonb; v_offers bigint; v_abst bigint; v_ref bigint;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_external_proposals p
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = p.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY p.created_at DESC NULLS LAST LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;
  SELECT l->'live' INTO v_l4 FROM jsonb_array_elements(public.ottoq_intelligence_stack(v_run, false)->'layers') l
   WHERE l->>'layer' = 'L4_KERNEL';
  SELECT count(*) FILTER (WHERE NOT COALESCE((proposal->>'abstain')::boolean, false)),
         count(*) FILTER (WHERE COALESCE((proposal->>'abstain')::boolean, false)),
         count(*) FILTER (WHERE status = 'refused' AND NOT COALESCE((proposal->>'abstain')::boolean, false))
    INTO v_offers, v_abst, v_ref
    FROM public.ottoq_external_proposals WHERE sim_run_id = v_run;
  -- V1: offers and abstentions partition the rows, and the card reports each against the table
  IF (v_l4->>'proposals')::bigint <> v_offers OR (v_l4->>'abstentions')::bigint <> v_abst
     OR (v_l4->>'rows')::bigint <> v_offers + v_abst THEN
    RAISE EXCEPTION '0456 V1: L4 % offers / % abstentions / % rows against % / % in the table',
      v_l4->>'proposals', v_l4->>'abstentions', v_l4->>'rows', v_offers, v_abst;
  END IF;
  -- V2: refusals are refusals of offers, and the outcome counts never exceed the offers
  IF (v_l4->>'refused')::bigint <> v_ref THEN
    RAISE EXCEPTION '0456 V2: L4 refused % against % refused offers', v_l4->>'refused', v_ref;
  END IF;
  IF (v_l4->>'enacted')::bigint + (v_l4->>'refused')::bigint + (v_l4->>'superseded')::bigint
     + (v_l4->>'expired')::bigint + (v_l4->>'pending')::bigint <> v_offers THEN
    RAISE EXCEPTION '0456 V2: L4 outcomes do not sum to its offers';
  END IF;
  -- V3: an abstention reason never appears among refusal reasons
  IF (v_l4->'top_refusal_reasons') ? 'proposer_abstained' THEN
    RAISE EXCEPTION '0456 V3: proposer_abstained still listed as a refusal reason';
  END IF;
  RAISE NOTICE '0456 run %: % offers, % abstentions, % refused', v_run, v_offers, v_abst, v_ref;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0456_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0456_the_kernel_card_counted_abstentions_as_refused_proposals', false,
  'Reporting: ottoq_intelligence_stack L4 separates the proposer''s abstentions from its offers. No tick path reads it.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
