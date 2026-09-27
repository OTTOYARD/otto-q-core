-- migration-version: 20260923053740
-- migration-name:    the_intelligence_panel_counted_failures_as_refusals_and_showed_every_runs_solver_calls_as_this_ones
--
-- 0451  **The cockpit's Intelligence and Decisions streams read the right tables and said the wrong things.**
--       Chase, 2026-09-23: "make sure that the data streams are first consistent and legible, and actually
--       accurate." Measured on run 736406cf (busy_day, twin depot) against the ledgers each stream claims to
--       summarise. `db/checks/0356` holds the queries and the numbers. FINDINGS G189.
--
-- ══ §1 WHAT WAS WRONG ════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_intelligence_stack` (0351) is the Intelligence tab's LAYERS view. Three of its five layers misreport:
--
--   L1 SHIELD. `blocked` was `count(*) FILTER (WHERE passed IS FALSE)`: every FAILED evaluation, whatever the
--      rule's enforcement and whatever the caller did with the verdict. CLAUDE.md 2.5 (0337, 0430) is explicit
--      that a failed shadow/log_only verdict cannot be a refusal, and that `ottoq_rule_evaluation_effect` is the
--      instrument that separates `refused` from `recorded_only`. The panel labelled failures "blocked", and
--      labelled the rules that failed most "top blocking rules". A failing shadow rule (SM.001 fails thousands of
--      times a run) would headline a shield that refused nothing.
--   L3 PROPOSERS. `providers` was read from `ottoq_intelligence_ledger` -- the LIFETIME view across every run and
--      depot -- under a card for one run. On run 736406cf at tick ~20 it showed cuOpt 1,162 calls / 5,068 proposals
--      and CP-SAT 2,052 calls / 537 proposals while THIS run had made zero model calls of any kind. It also keyed
--      the aggregate on provider alone while the view is per (provider, role), and printed the agent row there:
--      "Nemotron 0 calls" -- the ledger counts the agent's passes as `captured_decisions` (5,701), not `calls`,
--      so the one layer that was running read as never called. And its description still said "cuOpt between
--      sites", which rule 8 retired: on one depot there is no inter-site routing.
--   L2 AGENT. `over_one_tick` and the `degraded_latency` status rest on the claim that a slow agent holds the
--      tick. `db/checks/0332` retracted that: the tick fires the agent with pg_net and never waits for it. What
--      does cost something is advice STALENESS, which `ottoq_agent_advice_provenance` measures and the panel never
--      showed. And the status had no word for the failure that actually happened tonight (G188): every pass fell
--      back because the model endpoint hung, and the layer read "inactive" -- indistinguishable from "not armed".
--
--   `ottoq_activity_feed` (0346) is the Decisions stream. Its agent rows carried `agent_over_one_tick` (the same
--      retracted claim, rendered as an amber chip whose tooltip said the deterministic path "fell back" because of
--      it). Nothing on the row said how late the advice was applied, which is the measured cost.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_intelligence_stack`, same signature, same JSON shape, every change additive or a correction:
--       - L1: `blocked` now counts `effect = 'refused'` -- verdicts the engine acted on. `failed`,
--         `recorded_only` (would-block verdicts a discarding caller ignored) and `advisory_failed` (failures of
--         shadow / warn / log_only rules) are published beside it, so the four can never be confused again.
--         `top_blocking_rules` ranks refusals; `top_failing_rules` ranks failures and names each rule's
--         enforcement. `by_probe_point` lists every probe point (there are ten), not the top six. The status is
--         `ok` whenever the shield evaluated anything: a shield that had nothing to refuse is not a warning.
--       - L2: `over_one_tick` is gone. `model_fallbacks`, `latest_source` and `last_model_error` say when the
--         agent is running without its model and why; `advice_*` publish staleness from the provenance view. New
--         status `model_unavailable` when the latest pass fell back.
--       - L3: `providers` is this run's proposer calls from `ottoq_model_call_ledger` (role = 'proposer'), with
--         calls, calls that reached the provider, answered calls, proposals and the last call. The agent is not a
--         proposer and is no longer listed there. The description matches rule 8.
--   (2) `ottoq_activity_feed`: `agent_over_one_tick` is replaced by `advice_ticks_late` (the receipt's tick minus
--       the tick the advice was computed on, exactly as the provenance view computes it) and `model_error` (the
--       fallback reason when the pass ran without its model). Nothing else moves.
--   (3) `public.ottoq_twin_inject_charger_fault(run, charger?, repair_minutes?)`: the cockpit's Charger Fault button
--       wrote a `twin.solar_inverter_blip` event and changed nothing. This is the real door: it calls
--       `twin.ottoq_report_charger_fault` (station Faulted, stall to maintenance, affected vehicles replanned) for
--       a charger at the RUN'S depot, then stamps the fault on the SIM clock with a repair time so
--       `twin.ottoq_sim_recover_chargers` returns it to service. `report_charger_fault` stamps `now()`, a REAL
--       timestamp, which the recovery predicate compares against the SIM clock -- the 0326 §1 clock-domain class
--       -- so without the re-stamp an injected fault would clear on the next tick, or never.
--
-- ══ §3 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--
--   (1) and (2) are read-only reporting functions; no tick path calls either. (3) is a new operator door that no
--   tick path calls. No certification atom reads any of them. The P0 guard therefore refuses only while a pair is
--   in flight, not while a demo run is live.

BEGIN;

-- ── P0: no pair in flight (a live demo run is fine: nothing here is on a tick path) ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0451 P0: a pair is running right now'; END IF;
END $inflight$;

-- ── P2: the premises this file builds on ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_rule_evaluation_effect') IS NULL THEN
    RAISE EXCEPTION '0451 P2: ottoq_rule_evaluation_effect (0430) is missing';
  END IF;
  IF to_regclass('public.ottoq_agent_advice_provenance') IS NULL THEN
    RAISE EXCEPTION '0451 P2: ottoq_agent_advice_provenance (0417) is missing';
  END IF;
  IF to_regprocedure('twin.ottoq_report_charger_fault(uuid,text,text,text)') IS NULL THEN
    RAISE EXCEPTION '0451 P2: twin.ottoq_report_charger_fault is missing';
  END IF;
  IF to_regprocedure('public.ottoq_model_call_outcome_class(text)') IS NULL THEN
    RAISE EXCEPTION '0451 P2: ottoq_model_call_outcome_class is missing';
  END IF;
  PERFORM 1 FROM pg_proc p WHERE p.oid = 'public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure
     AND p.prosrc LIKE '%count(*) FILTER (WHERE passed IS FALSE)%' AND p.prosrc LIKE '%FROM ottoq_intelligence_ledger%';
  IF NOT FOUND THEN RAISE EXCEPTION '0451 P2: ottoq_intelligence_stack is not the 0351 body this file corrects'; END IF;
  PERFORM 1 FROM pg_proc p WHERE p.oid = 'public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure
     AND p.prosrc LIKE '%''agent_over_one_tick'',(COALESCE(d.total_latency_ms,0) > 30000)%';
  IF NOT FOUND THEN RAISE EXCEPTION '0451 P2: ottoq_activity_feed is not the 0346 body this file corrects'; END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0451_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure,
                 'public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure);

-- ═══ (1) the Intelligence layers ═══════════════════════════════════════════════════════════════════════════
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

  SELECT jsonb_build_object(
    'proposals', count(*),
    'enacted', count(*) FILTER (WHERE status = 'enacted'),
    'refused', count(*) FILTER (WHERE status = 'refused'),
    'superseded', count(*) FILTER (WHERE status = 'superseded'),
    'expired', count(*) FILTER (WHERE status = 'expired'),
    'refusal_rate_pct', CASE WHEN count(*) > 0
        THEN round(100.0 * count(*) FILTER (WHERE status='refused') / count(*)) END,
    'by_source_status', (SELECT jsonb_object_agg(COALESCE(k,v_null_key_guard), c) FROM (
        SELECT COALESCE(source,'?')||'/'||COALESCE(status,'?') k, count(*) c
          FROM ottoq_external_proposals WHERE sim_run_id = p_sim_run_id
         GROUP BY 1 ORDER BY c DESC LIMIT 8) bs),
    'top_refusal_reasons', (SELECT jsonb_object_agg(COALESCE(dr,v_null_key_guard), c) FROM (
        SELECT disposition_reason dr, count(*) c FROM ottoq_external_proposals
         WHERE sim_run_id = p_sim_run_id AND status IN ('refused','superseded','expired')
         GROUP BY 1 ORDER BY c DESC LIMIT 5) rr)
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
      'status', CASE WHEN COALESCE((v_kernel->>'proposals')::bigint,0) = 0 THEN 'inactive'
                     WHEN COALESCE((v_kernel->>'enacted')::bigint,0) = 0 THEN 'refusing_all'
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

-- ═══ (2) the Decisions stream: staleness instead of a retracted latency claim ══════════════════════════════
DO $feed$
DECLARE v_def text; v_old text; v_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure);
  v_old := $o$'agent_over_one_tick',(COALESCE(d.total_latency_ms,0) > 30000),$o$;
  v_new := $n$--: 0451: how late the advice was APPLIED (receipt tick - computed tick, as the provenance view
        --: computes it). The retracted over-one-tick flag is gone: the tick never waits on the agent (0332).
        'advice_ticks_late',((d.enacted_action->'solver_handoff'->'receipt'->>'tick_seq')::bigint - d.tick_seq),
        'model_error',CASE WHEN d.enacted_action->>'source' = 'deterministic_fallback'
                           THEN substring(d.enacted_action->>'rationale' FROM '\(([^)]*)\)') END,$n$;
  IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION '0451 (2): the agent_over_one_tick anchor is not unique in ottoq_activity_feed';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $feed$;

-- ═══ (3) the Charger Fault button's real door ═════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_twin_inject_charger_fault(
  p_sim_run_id uuid,
  p_charger_id uuid DEFAULT NULL,
  p_repair_minutes numeric DEFAULT 60,
  p_actor text DEFAULT 'cockpit_operator'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_run RECORD; v_charger uuid; v_stall_code text; v_had_vehicle boolean; v_res jsonb;
  v_repair numeric := LEAST(GREATEST(COALESCE(p_repair_minutes, 60), 5), 480);
BEGIN
  SELECT sim_run_id, depot_id, status, sim_clock_current INTO v_run
    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'run_not_found'); END IF;
  IF v_run.status <> 'running' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'run_not_running', 'status', v_run.status);
  END IF;

  -- The target is always a charger at the RUN'S depot (rule 8). Given one, it must be; given none, take the
  -- DC fast charger whose loss is visible -- one with a vehicle on it first -- in a fixed order.
  SELECT c.charger_id, s.stall_code, (s.current_vehicle_id IS NOT NULL)
    INTO v_charger, v_stall_code, v_had_vehicle
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = v_run.depot_id AND c.depot_id = v_run.depot_id
     AND c.station_state <> 'Faulted'
     AND (p_charger_id IS NULL OR c.charger_id = p_charger_id)
     AND (p_charger_id IS NOT NULL OR s.stall_type::text = 'dcfc')
   ORDER BY (s.current_vehicle_id IS NOT NULL) DESC, s.stall_code
   LIMIT 1;
  IF v_charger IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'reason', CASE WHEN p_charger_id IS NULL THEN 'no_healthy_dcfc_charger_at_this_depot'
                     ELSE 'charger_not_at_this_depot_or_already_faulted' END);
  END IF;

  v_res := twin.ottoq_report_charger_fault(
             p_charger_id => v_charger, p_actor => p_actor, p_fault_code => 'operator_injected',
             p_note => 'injected from the cockpit; repairs in ' || v_repair || ' sim-min');

  -- report_charger_fault stamps now() (REAL time). twin.ottoq_sim_recover_chargers compares the stamp with the
  -- SIM clock plus last_fault_payload.repair_minutes, so the fault is re-stamped on the sim clock here.
  UPDATE public.ottoq_ocpp_chargers
     SET station_state_changed_at = v_run.sim_clock_current,
         last_fault_payload = COALESCE(last_fault_payload, '{}'::jsonb)
                              || jsonb_build_object('repair_minutes', v_repair, 'injected_via', 'cockpit',
                                                    'sim_run_id', p_sim_run_id)
   WHERE charger_id = v_charger AND station_state = 'Faulted';

  RETURN jsonb_build_object('ok', COALESCE((v_res->>'ok')::boolean, false),
    'charger_id', v_charger, 'stall_code', v_stall_code, 'had_vehicle', v_had_vehicle,
    'repair_minutes', v_repair, 'faulted_at_sim', v_run.sim_clock_current,
    'recovers_at_sim', v_run.sim_clock_current + make_interval(secs => (v_repair * 60)::double precision),
    'report', v_res);
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text) TO service_role;

-- ═══ V: verify every change, and roll the probes back ═════════════════════════════════════════════════════
DO $verify$
DECLARE d text; v_stack jsonb; v_run uuid; v_eff bigint; v_l1 jsonb; v_l3 jsonb; v_other bigint;
BEGIN
  -- V1: the stack reads the effect view, publishes the four shield counts, and no longer reads the lifetime ledger
  SELECT p.prosrc INTO d FROM pg_proc p WHERE p.oid = 'public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure;
  IF d NOT LIKE '%ottoq_rule_evaluation_effect%' OR d LIKE '%FROM ottoq_intelligence_ledger%'
     OR d NOT LIKE '%''recorded_only''%' OR d NOT LIKE '%''advisory_failed''%'
     OR d LIKE '%''over_one_tick''%' OR d NOT LIKE '%model_unavailable%' THEN
    RAISE EXCEPTION '0451 V1: the stack body is not the corrected one';
  END IF;

  -- V2: the feed carries staleness and no longer the retracted flag
  SELECT p.prosrc INTO d FROM pg_proc p WHERE p.oid = 'public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure;
  IF d LIKE '%''agent_over_one_tick''%' OR d NOT LIKE '%''advice_ticks_late''%' OR d NOT LIKE '%''model_error''%' THEN
    RAISE EXCEPTION '0451 V2: the feed body is not the corrected one';
  END IF;

  -- V3: on the most recent twin-depot run, blocked equals the effect view's refusals and providers are run-scoped
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    v_stack := public.ottoq_intelligence_stack(v_run, false);
    SELECT e->'live' INTO v_l1 FROM jsonb_array_elements(v_stack->'layers') e WHERE e->>'layer' = 'L1_SHIELD';
    SELECT e->'live' INTO v_l3 FROM jsonb_array_elements(v_stack->'layers') e WHERE e->>'layer' = 'L3_SOLVER';
    SELECT count(*) INTO v_eff FROM public.ottoq_rule_evaluation_effect WHERE sim_run_id = v_run AND effect = 'refused';
    IF (v_l1->>'blocked')::bigint IS DISTINCT FROM v_eff THEN
      RAISE EXCEPTION '0451 V3: L1 blocked % <> refused %', v_l1->>'blocked', v_eff;
    END IF;
    SELECT count(*) INTO v_other FROM public.ottoq_model_call_ledger WHERE sim_run_id = v_run AND role = 'proposer';
    IF COALESCE((SELECT sum((x.value->>'calls')::bigint) FROM jsonb_each(COALESCE(v_l3->'providers','{}'::jsonb)) x), 0)
       <> v_other THEN
      RAISE EXCEPTION '0451 V3: L3 providers do not sum to this run''s proposer calls (%)', v_other;
    END IF;
    IF (v_l3->'providers') ? 'nvidia_nemotron' THEN
      RAISE EXCEPTION '0451 V3: the agent is still listed as a proposer';
    END IF;
  END IF;

  -- V4: the charger-fault door is service-role only and refuses a run that is not running
  IF has_function_privilege('anon','public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)','EXECUTE') THEN
    RAISE EXCEPTION '0451 V4: inject_charger_fault privileges are wrong';
  END IF;
  IF (public.ottoq_twin_inject_charger_fault(gen_random_uuid())->>'reason') <> 'run_not_found' THEN
    RAISE EXCEPTION '0451 V4: an unknown run was not refused';
  END IF;
END $verify$;

-- Rollback: restore both functions from ottoq_schema_snapshots label '0451_pre' and
-- DROP FUNCTION public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0451_the_intelligence_panel_counted_failures_as_refusals_and_showed_every_runs_solver_calls_as_this_ones', false,
  'Reporting corrections to ottoq_intelligence_stack and ottoq_activity_feed, plus a new operator door (ottoq_twin_inject_charger_fault). No tick path calls any of them; no atom reads them.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
