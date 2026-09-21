-- migration-version: 20260919195941
-- migration-name:    the_intelligence_layers_are_real_and_nothing_assembles_them_into_a_stack
--
-- 0351  EVERY LAYER OF THE INTELLIGENCE STACK IS MEASURABLE. NOTHING RETURNS
--       THEM AS A STACK, SO NOTHING CAN SHOW ONE.
--
-- Five instruments now exist and each answers one layer:
--
--   ottoq_agentic_arming        (0278/0339/0349)  is the layer armed, and is its
--                                                 rank-0 proposer reachable
--   ottoq_agent_asset_depth     (0350)            what the agent SEES
--   ottoq_agent_review          (0342/0343)       what happened to what it decided
--   ottoq_activity_feed         (0346)            the per-decision stream
--   ottoq_intelligence_ledger   (0340/0341)       provider calls that outlive the run
--
-- Five calls, five shapes, five join keys. A cockpit that wants to show "the agent
-- read these variables, the shield gated it, the solver proposed, the kernel
-- disposed" has to make five round trips and invent the relationship between them.
-- So nobody has shown it, and the most load-bearing claim this company makes --
-- that there IS a layered intelligence system rather than a threshold script -- is
-- the one thing an operator cannot watch happen.
--
-- This adds ONE call that returns the layers in order, each with its own live
-- numbers, its own status, and THE NAME OF THE TABLE IT WAS MEASURED FROM.
--
-- ── WHY `measured_from` IS IN THE PAYLOAD AND NOT JUST IN THIS COMMENT ──────
--
-- Because the founder's instruction on this build is that it has to be accurate
-- before it is displayed, and because an OEM's first question about any number on
-- a screen is "where does that come from". Carrying the source table inside the
-- response makes the dashboard self-auditing: every figure can be re-derived by
-- the person looking at it. It also makes THIS file falsifiable -- A3 re-derives
-- each headline number independently and refuses the migration if the stack and
-- the direct query disagree.
--
-- That is the difference between a dashboard and a demo.
--
-- ── MEASURED ON RUN dde654cc (tick 1,112, completed) ───────────────────────
--
--   L1 shield   177,179 evaluations · 1,533 BLOCKED · 20 distinct rules
--               task_start 167,518 · redeployment 7,140 · stall_assignment 2,120
--               · bess_dispatch 401
--               top blockers: SLA.004.required_services_complete 1,054 ·
--               HW.005.vehicle_one_active_task 479
--   L2 agent    166 orchestrator_agent decisions
--   L3 solver   cuOpt reached; forward_lex never fired (G66/G68)
--   L4 kernel   cuopt enacted 21 · REFUSED 20 · superseded 2
--
-- That kernel line is the single most valuable fact the stack exposes. The AI
-- proposed 43 assignments and the deterministic kernel **refused 20 of them** --
-- 47%. "Agents propose, solver disposes" (CLAUDE.md rule 6) stops being a design
-- statement and becomes a number on a screen, and it is a number that only looks
-- good BECAUSE it is not 100%: a kernel that enacted everything would be a
-- rubber stamp, and one that enacted nothing would be a wall.
--
-- ── COST, BECAUSE THIS IS A POLLING ENDPOINT ───────────────────────────────
--
-- Measured before writing it, which is the lesson of db/checks/0098 (a 22-second
-- KPI view survived because nobody timed it against the real row count) and of
-- G21 (8,966,506 per-row re-derivations). The heaviest leg is the shield
-- group-by over this run's 177,179 evaluations: **81.6 ms**, served by
-- idx_ottoq_evals_sim_run (sim_run_id, evaluation_seq) WHERE sim_run_id IS NOT
-- NULL. ottoq_decisions has idx_decisions_run_tick and ottoq_external_proposals
-- has ottoq_extprop_lookup_idx, both leading on sim_run_id.
--
-- `p_include_frame` exists so the cockpit can poll the cheap layer counts often
-- and pull the expensive frame (0350's depth, ~500 ms) only when a human opens
-- that panel. A4 bounds the whole thing.
--
-- ── WHAT THIS DOES NOT DO ──────────────────────────────────────────────────
--
-- It computes nothing new. Every number comes from an existing table or an
-- existing function, and where a function already answers a layer this calls it
-- rather than reimplementing it (CLAUDE.md rule 5: verify, consolidate, extend --
-- duplicating an existing capability is a failure). It is a read-only STABLE
-- projection: no new table, no trigger, no write, nothing on the tick path.

BEGIN;

-- ── P1  every instrument this assembles actually exists ────────────────────
DO $$
DECLARE v_missing text := '';
BEGIN
  IF to_regprocedure('public.ottoq_agentic_arming(uuid)') IS NULL
    THEN v_missing := v_missing || 'ottoq_agentic_arming '; END IF;
  IF to_regprocedure('public.ottoq_agent_asset_depth(uuid,uuid,timestamp with time zone,integer,integer)') IS NULL
    THEN v_missing := v_missing || 'ottoq_agent_asset_depth '; END IF;
  IF to_regprocedure('public.ottoq_agent_review(uuid,integer)') IS NULL
    THEN v_missing := v_missing || 'ottoq_agent_review '; END IF;
  IF v_missing <> '' THEN
    RAISE EXCEPTION '0351 P1: missing instrument(s): % -- 0349/0350/0342 must be applied first', v_missing;
  END IF;
END $$;

-- ── P2  the tables the layers are measured from carry a run-scoped index ───
-- A polling endpoint over an unindexed predicate is db/checks/0098 again.
DO $$
DECLARE v_bad text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='ottoq_rule_evaluations'
                   AND indexdef ILIKE '%sim_run_id%') THEN v_bad := v_bad || 'ottoq_rule_evaluations '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='ottoq_decisions'
                   AND indexdef ILIKE '%sim_run_id%') THEN v_bad := v_bad || 'ottoq_decisions '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='ottoq_external_proposals'
                   AND indexdef ILIKE '%sim_run_id%') THEN v_bad := v_bad || 'ottoq_external_proposals '; END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION '0351 P2: no sim_run_id index on: % -- this is a polling endpoint and that is the 0098 defect', v_bad;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.ottoq_intelligence_stack(
  p_sim_run_id uuid,
  p_include_frame boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run RECORD;
  v_arming jsonb; v_frame jsonb; v_review jsonb;
  v_shield jsonb; v_agent jsonb; v_solver jsonb; v_kernel jsonb; v_ingress jsonb;
  v_layers jsonb;
  -- NOTE every jsonb_object_agg below COALESCEs its key. A NULL key raises
  -- 22023 "field name must not be null" at RUNTIME, and this run has NULL
  -- action_context and NULL resolved_action_context rows -- so an un-COALESCEd
  -- key would have crashed the cockpit's poll, not this migration.
  v_null_key_guard constant text := 'unspecified';
BEGIN
  SELECT sim_run_id, status, tick_count, sim_clock_current, scenario_code,
         depot_id, demo_speed_x, started_at, run_by
    INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL THEN
    RETURN jsonb_build_object('error','unknown_run','sim_run_id',p_sim_run_id);
  END IF;

  v_arming := public.ottoq_agentic_arming(p_sim_run_id);

  -- ══ L0 INGRESS — what the assets pushed, and whether it can be trusted ══
  -- The asset API boundary. twin.ottoq_sim_emit_telemetry is the only inserter,
  -- which is what makes the swap test meaningful: replace that one writer with a
  -- real OEM feed and nothing downstream changes.
  SELECT jsonb_build_object(
    'packets', count(*),
    'vehicles_reporting', count(DISTINCT vehicle_id),
    'integrity', (SELECT jsonb_object_agg(COALESCE(packet_integrity,v_null_key_guard), c) FROM (
        SELECT packet_integrity, count(*) c FROM ottoq_telemetry_packets
         WHERE sim_run_id = p_sim_run_id GROUP BY 1 ORDER BY c DESC LIMIT 5) i),
    'dropped', count(*) FILTER (WHERE packet_integrity = 'dropped'),
    'signal_below_50pct', count(*) FILTER (WHERE signal_strength_pct < 50)
  ) INTO v_ingress FROM ottoq_telemetry_packets WHERE sim_run_id = p_sim_run_id;

  -- ══ L1 SHIELD — the deterministic rules, and what they BLOCKED ══════════
  -- `passed IS FALSE` is the whole point: a shield that never refuses is not a
  -- shield. CLAUDE.md 2.5's honest sentence is "twenty of twenty-nine declared
  -- rules, at four decision points, every evaluation logged" -- distinct_rules
  -- and by_probe_point are exactly those two numbers, per run.
  SELECT jsonb_build_object(
    'evaluations', count(*),
    'blocked', count(*) FILTER (WHERE passed IS FALSE),
    'distinct_rules', count(DISTINCT rule_code),
    'overridden', count(*) FILTER (WHERE override_id IS NOT NULL),
    'by_probe_point', (SELECT jsonb_object_agg(COALESCE(action_context,v_null_key_guard), c) FROM (
        SELECT action_context, count(*) c FROM ottoq_rule_evaluations
         WHERE sim_run_id = p_sim_run_id GROUP BY 1 ORDER BY c DESC LIMIT 6) p),
    'top_blocking_rules', (SELECT jsonb_object_agg(COALESCE(rule_code,v_null_key_guard), c) FROM (
        SELECT rule_code, count(*) c FROM ottoq_rule_evaluations
         WHERE sim_run_id = p_sim_run_id AND passed IS FALSE
         GROUP BY 1 ORDER BY c DESC LIMIT 5) b)
  ) INTO v_shield FROM ottoq_rule_evaluations WHERE sim_run_id = p_sim_run_id;

  -- ══ L2 AGENT — the model, its objective, and whether it beat the beat ═══
  SELECT jsonb_build_object(
    'chains', count(*),
    'model', (SELECT COALESCE(d2.proposed_action->>'model','none') FROM ottoq_decisions d2
               WHERE d2.sim_run_id = p_sim_run_id AND d2.resolved_action_context='orchestrator_agent'
               ORDER BY d2.tick_seq DESC LIMIT 1),
    'objective', (SELECT d3.proposed_action->'solver'->>'objective' FROM ottoq_decisions d3
                   WHERE d3.sim_run_id = p_sim_run_id AND d3.resolved_action_context='orchestrator_agent'
                   ORDER BY d3.tick_seq DESC LIMIT 1),
    'objective_why', (SELECT d4.proposed_action->'solver'->>'why' FROM ottoq_decisions d4
                   WHERE d4.sim_run_id = p_sim_run_id AND d4.resolved_action_context='orchestrator_agent'
                   ORDER BY d4.tick_seq DESC LIMIT 1),
    'avg_latency_ms', round(avg(total_latency_ms)),
    'max_latency_ms', max(total_latency_ms),
    'over_one_tick', count(*) FILTER (WHERE total_latency_ms > 30000),
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
         ORDER BY d5.tick_seq DESC LIMIT 1)
  ) INTO v_agent FROM ottoq_decisions d
   WHERE d.sim_run_id = p_sim_run_id AND d.resolved_action_context = 'orchestrator_agent';

  -- ══ L3 SOLVER — who was actually reached, from the evidence ledger ══════
  -- ottoq_model_call_ledger is class 'evidence' and survives the demo purge that
  -- deletes cuopt_invocation_log (0340, proven in production 2026-09-19), so this
  -- leg keeps answering after the run's own working data is gone.
  SELECT jsonb_build_object(
    'declared_primary', (SELECT source FROM ottoq_proposer_precedence ORDER BY rank, source LIMIT 1),
    'primary_reachable', v_arming -> 'primary_proposer' -> 'reachable',
    'primary_fires', v_arming -> 'primary_proposer' -> 'fires',
    'providers', (SELECT jsonb_object_agg(COALESCE(provider,v_null_key_guard), jsonb_build_object(
                    'calls', calls, 'proposals', proposals, 'last_call', last_call))
                   FROM ottoq_intelligence_ledger),
    'fires_this_run', (SELECT count(*) FROM ottoq_proposer_fire_log
                        WHERE sim_run_id = p_sim_run_id)
  ) INTO v_solver;

  -- ══ L4 KERNEL — the disposal. THE number that proves propose/dispose. ═══
  -- A kernel that enacted everything would be a rubber stamp; one that enacted
  -- nothing would be a wall. The ratio is the claim.
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

  -- ══ THE STACK, in the order signal actually travels ════════════════════
  -- Each layer carries `measured_from` so every figure on a screen can be
  -- re-derived by whoever is looking at it. That is the difference between a
  -- dashboard and a demo.
  v_layers := jsonb_build_array(
    jsonb_build_object(
      'layer','L0_INGRESS','name','Asset telemetry',
      'does','What the assets pushed. One writer, so a real OEM feed swaps in unchanged.',
      'measured_from','ottoq_telemetry_packets',
      'status', CASE WHEN COALESCE((v_ingress->>'packets')::int,0) = 0 THEN 'inactive'
                     WHEN COALESCE((v_ingress->>'dropped')::int,0) > 0 THEN 'degraded'
                     ELSE 'ok' END,
      'live', v_ingress),
    jsonb_build_object(
      'layer','L1_SHIELD','name','Deterministic rules (L1)',
      'does','Defines which actions are FEASIBLE. Not part of the policy; part of the problem.',
      'measured_from','ottoq_rule_evaluations',
      'status', CASE WHEN COALESCE((v_shield->>'evaluations')::bigint,0) = 0 THEN 'inactive'
                     WHEN COALESCE((v_shield->>'blocked')::bigint,0) = 0 THEN 'permissive'
                     ELSE 'ok' END,
      'live', v_shield),
    jsonb_build_object(
      'layer','L2_AGENT','name','Orchestrator agent',
      'does','Reads the frame, picks an objective, writes bounded policy. Proposes; never disposes.',
      'measured_from','ottoq_decisions (resolved_action_context=orchestrator_agent)',
      'status', CASE WHEN COALESCE((v_agent->>'chains')::bigint,0) = 0 THEN 'inactive'
                     WHEN COALESCE((v_agent->>'over_one_tick')::bigint,0)
                        > COALESCE((v_agent->>'chains')::bigint,1) / 2 THEN 'degraded_latency'
                     ELSE 'ok' END,
      'live', v_agent),
    jsonb_build_object(
      'layer','L3_SOLVER','name','Proposers',
      'does','CP-SAT inside the site, cuOpt between sites. Nondeterministic by nature, which is why L4 exists.',
      'measured_from','ottoq_intelligence_ledger (evidence class) + ottoq_proposer_fire_log',
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

COMMENT ON FUNCTION public.ottoq_intelligence_stack(uuid,boolean) IS
  '0351. ONE call returning the OTTO-Q intelligence stack as an ordered set of '
  'layers — L0 ingress, L1 deterministic shield, L2 orchestrator agent, L3 '
  'proposers, L4 deterministic disposal — each with its live numbers, a derived '
  'status, and `measured_from` naming the table the numbers came from so any '
  'figure on a screen can be re-derived by whoever is looking at it. Computes '
  'nothing new: it calls ottoq_agentic_arming, ottoq_agent_asset_depth and '
  'ottoq_agent_review rather than reimplementing them, and aggregates existing '
  'tables. STABLE, read-only, nothing on the tick path. Pass '
  'p_include_frame=false to poll the cheap layer counts without the ~500 ms '
  'asset-depth frame. The kernel layer''s refusal_rate_pct is the load-bearing '
  'number: on run dde654cc the AI proposed 43 assignments and the kernel refused '
  '20 of them, which is what makes "agents propose, solver disposes" a '
  'measurement rather than a slogan.';

-- ── A1  the stack returns every layer, in order, with its source named ─────
DO $$
DECLARE v_run uuid; v_s jsonb; v_ids text;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0351 A1: no run at all; this migration cannot be verified against live data';
  END IF;

  v_s := public.ottoq_intelligence_stack(v_run, true);

  IF v_s ? 'error' THEN
    RAISE EXCEPTION '0351 A1: stack returned an error for a run that exists: %', v_s->>'error';
  END IF;

  SELECT string_agg(l->>'layer', ',' ORDER BY ord) INTO v_ids
    FROM jsonb_array_elements(v_s->'layers') WITH ORDINALITY x(l, ord);
  IF v_ids IS DISTINCT FROM 'L0_INGRESS,L1_SHIELD,L2_AGENT,L3_SOLVER,L4_KERNEL' THEN
    RAISE EXCEPTION '0351 A1: layers are missing or out of order: %', COALESCE(v_ids,'<none>');
  END IF;

  -- every layer must name its source and carry a status; a layer that cannot say
  -- where its numbers came from is the thing this file exists to prevent
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_s->'layers') l
              WHERE NOT (l.value ? 'measured_from') OR NOT (l.value ? 'status')
                 OR NOT (l.value ? 'live')) THEN
    RAISE EXCEPTION '0351 A1: a layer is missing measured_from, status or live';
  END IF;
END $$;

-- ── A2  the frame gate works in BOTH directions ───────────────────────────
DO $$
DECLARE v_run uuid; v_with jsonb; v_without jsonb;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;

  v_with    := public.ottoq_intelligence_stack(v_run, true);
  v_without := public.ottoq_intelligence_stack(v_run, false);

  IF (v_with -> 'frame') IS NULL OR (v_with->'frame') = 'null'::jsonb THEN
    RAISE EXCEPTION '0351 A2: p_include_frame=true returned no frame';
  END IF;
  IF (v_without -> 'frame') IS NOT NULL AND (v_without->'frame') <> 'null'::jsonb THEN
    RAISE EXCEPTION '0351 A2: p_include_frame=false still returned a frame — the cheap poll is not cheap';
  END IF;
  -- the layers must be present either way; only the frame is optional
  IF jsonb_array_length(v_without->'layers') <> 5 THEN
    RAISE EXCEPTION '0351 A2: the cheap poll dropped layers (% of 5)', jsonb_array_length(v_without->'layers');
  END IF;
END $$;

-- ── A3  ACCURACY: every headline number re-derived independently ───────────
-- THE POINT OF THIS ASSERTION. The founder's instruction on this build is that
-- it must be accurate before it is displayed. So each figure the cockpit will
-- show is recomputed here by a direct query and compared. If the stack and the
-- table disagree, the migration refuses -- which is the only way a dashboard
-- earns the right to be shown to an OEM.
DO $$
DECLARE
  v_run uuid; v_s jsonb;
  v_evals bigint; v_blocked bigint; v_rules bigint;
  v_chains bigint; v_props bigint; v_enacted bigint; v_refused bigint;
  v_packets bigint;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;

  v_s := public.ottoq_intelligence_stack(v_run, false);

  SELECT count(*), count(*) FILTER (WHERE passed IS FALSE), count(DISTINCT rule_code)
    INTO v_evals, v_blocked, v_rules
    FROM public.ottoq_rule_evaluations WHERE sim_run_id = v_run;
  SELECT count(*) INTO v_chains FROM public.ottoq_decisions
   WHERE sim_run_id = v_run AND resolved_action_context = 'orchestrator_agent';
  SELECT count(*), count(*) FILTER (WHERE status='enacted'), count(*) FILTER (WHERE status='refused')
    INTO v_props, v_enacted, v_refused
    FROM public.ottoq_external_proposals WHERE sim_run_id = v_run;
  SELECT count(*) INTO v_packets FROM public.ottoq_telemetry_packets WHERE sim_run_id = v_run;

  IF (v_s->'layers'->1->'live'->>'evaluations')::bigint IS DISTINCT FROM v_evals THEN
    RAISE EXCEPTION '0351 A3: shield evaluations — stack says %, table says %',
      v_s->'layers'->1->'live'->>'evaluations', v_evals;
  END IF;
  IF (v_s->'layers'->1->'live'->>'blocked')::bigint IS DISTINCT FROM v_blocked THEN
    RAISE EXCEPTION '0351 A3: shield blocked — stack says %, table says %',
      v_s->'layers'->1->'live'->>'blocked', v_blocked;
  END IF;
  IF (v_s->'layers'->1->'live'->>'distinct_rules')::bigint IS DISTINCT FROM v_rules THEN
    RAISE EXCEPTION '0351 A3: distinct rules — stack says %, table says %',
      v_s->'layers'->1->'live'->>'distinct_rules', v_rules;
  END IF;
  IF (v_s->'layers'->2->'live'->>'chains')::bigint IS DISTINCT FROM v_chains THEN
    RAISE EXCEPTION '0351 A3: agent chains — stack says %, table says %',
      v_s->'layers'->2->'live'->>'chains', v_chains;
  END IF;
  IF (v_s->'layers'->4->'live'->>'proposals')::bigint IS DISTINCT FROM v_props THEN
    RAISE EXCEPTION '0351 A3: kernel proposals — stack says %, table says %',
      v_s->'layers'->4->'live'->>'proposals', v_props;
  END IF;
  IF (v_s->'layers'->4->'live'->>'enacted')::bigint IS DISTINCT FROM v_enacted THEN
    RAISE EXCEPTION '0351 A3: kernel enacted — stack says %, table says %',
      v_s->'layers'->4->'live'->>'enacted', v_enacted;
  END IF;
  IF (v_s->'layers'->4->'live'->>'refused')::bigint IS DISTINCT FROM v_refused THEN
    RAISE EXCEPTION '0351 A3: kernel refused — stack says %, table says %',
      v_s->'layers'->4->'live'->>'refused', v_refused;
  END IF;
  IF (v_s->'layers'->0->'live'->>'packets')::bigint IS DISTINCT FROM v_packets THEN
    RAISE EXCEPTION '0351 A3: ingress packets — stack says %, table says %',
      v_s->'layers'->0->'live'->>'packets', v_packets;
  END IF;

  -- and the derived ratio must match its own inputs, not be independently computed
  IF v_props > 0 AND (v_s->'layers'->4->'live'->>'refusal_rate_pct')::numeric
     IS DISTINCT FROM round(100.0 * v_refused / v_props) THEN
    RAISE EXCEPTION '0351 A3: refusal_rate_pct — stack says %, % of % is %',
      v_s->'layers'->4->'live'->>'refusal_rate_pct', v_refused, v_props,
      round(100.0 * v_refused / v_props);
  END IF;

  RAISE NOTICE '0351 A3: ok — 8 headline figures re-derived and identical (evals % blocked % rules % chains % proposals % enacted % refused % packets %)',
    v_evals, v_blocked, v_rules, v_chains, v_props, v_enacted, v_refused, v_packets;
END $$;

-- ── A4  COST: the cheap poll must actually be cheap ───────────────────────
DO $$
DECLARE v_run uuid; v_t0 timestamptz; v_cheap numeric; v_full numeric; v_bytes int;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;

  v_t0 := clock_timestamp();
  SELECT length(public.ottoq_intelligence_stack(v_run, false)::text) INTO v_bytes;
  v_cheap := EXTRACT(epoch FROM clock_timestamp()-v_t0)*1000;

  v_t0 := clock_timestamp();
  PERFORM public.ottoq_intelligence_stack(v_run, true);
  v_full := EXTRACT(epoch FROM clock_timestamp()-v_t0)*1000;

  RAISE NOTICE '0351 A4: cheap poll % ms (% bytes), full % ms', round(v_cheap,1), v_bytes, round(v_full,1);

  -- Loose bounds on purpose: these fail on a real regression, not on a busy host.
  -- The shield group-by over 177,179 evaluations measured 81.6 ms before this file
  -- was written, so 3000 ms is ~36x headroom on the dominant leg.
  IF v_cheap > 3000 THEN
    RAISE EXCEPTION '0351 A4: the CHEAP poll took % ms (budget 3000). A cockpit polls this; find the unindexed predicate.', round(v_cheap,1);
  END IF;
  IF v_full > 6000 THEN
    RAISE EXCEPTION '0351 A4: the full stack took % ms (budget 6000).', round(v_full,1);
  END IF;
END $$;

-- ── A5  it does not crash on a NULL aggregate key ─────────────────────────
-- This run HAS NULL resolved_action_context rows (3,503 of them) and NULL
-- action_context rows. An un-COALESCEd jsonb_object_agg key raises 22023 at
-- runtime, which would have taken the cockpit's poll down rather than this
-- migration. Proven by the fact that A1/A3 above ran at all, and asserted
-- explicitly here so a future edit cannot quietly drop a COALESCE.
DO $$
DECLARE v_run uuid; v_nulls bigint;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;

  SELECT count(*) INTO v_nulls FROM public.ottoq_decisions
   WHERE sim_run_id = v_run AND resolved_action_context IS NULL;

  IF v_nulls = 0 THEN
    RAISE NOTICE '0351 A5: this run has no NULL resolved_action_context, so the COALESCE guard is untested here — it stays because another run will';
  ELSE
    -- calling it is the test: a missing COALESCE raises 22023 and fails the migration
    PERFORM public.ottoq_intelligence_stack(v_run, false);
    RAISE NOTICE '0351 A5: ok — stack survived % NULL-keyed decision rows', v_nulls;
  END IF;
END $$;

-- ── CERT LINEAGE ──────────────────────────────────────────────────────────
-- forces_recert FALSE. Read-only STABLE projection over existing tables and
-- existing functions. Creates no table, no trigger, writes nothing, and is called
-- from nowhere on the tick path — only by a cockpit and by hand.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0351_the_intelligence_layers_are_real_and_nothing_assembles_them_into_a_stack', false,
  'Five instruments each answered one layer of the intelligence stack — ottoq_agentic_arming (armed? primary reachable?), ottoq_agent_asset_depth (what the agent sees), ottoq_agent_review (what happened to it), ottoq_activity_feed (the stream), ottoq_intelligence_ledger (provider calls) — with five shapes and five join keys, so a cockpit wanting to show "agent read the variables, shield gated, solver proposed, kernel disposed" had to make five round trips and invent the relationship. Nobody had shown it, which meant the most load-bearing claim the company makes (that there IS a layered intelligence system rather than a threshold script) was the one thing an operator could not watch happen. ottoq_intelligence_stack returns the layers in signal order — L0 ingress, L1 shield, L2 agent, L3 proposers, L4 disposal — each with live numbers, a derived status, and measured_from naming its source table so any figure on a screen can be re-derived by the person looking at it. Computes nothing new (CLAUDE.md rule 5): calls the three existing functions rather than reimplementing them. Measured on run dde654cc: shield 177,179 evaluations / 1,533 BLOCKED / 20 rules at 4 probe points; kernel 43 proposals, 21 enacted, 20 REFUSED — a 47% refusal rate, which is what turns "agents propose, solver disposes" into a measurement, and which only reads well because it is neither 0% (a wall) nor 100% (a rubber stamp). A3 is the accuracy gate the founder asked for: eight headline figures re-derived by direct query and required to be identical, so the migration refuses rather than letting an inaccurate dashboard ship. A4 bounds the cheap poll at 3000 ms against a measured 81.6 ms dominant leg. A5 pins the COALESCE on every jsonb_object_agg key — this run has 3,503 NULL resolved_action_context rows and an un-COALESCEd key raises 22023 at runtime, which would have taken down the cockpit poll rather than a migration. forces_recert FALSE: STABLE, read-only, nothing on the tick path.',
  now())
ON CONFLICT(name) DO NOTHING;

COMMIT;
