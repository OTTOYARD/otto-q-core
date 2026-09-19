-- migration-version: 20260919173442
-- migration-name:    a_run_reads_armed_while_its_rank_zero_proposer_is_unreachable
--
-- 0349  THE ATTESTATION SAYS "ARMED, 7 OF 7". THE RANK-0 PROPOSER HAS NOT RUN
--       ONCE. BOTH SENTENCES ARE TRUE, AND THAT IS THE DEFECT.
--
-- 0339 added the seventh required key for exactly this reason, and its own note
-- says so: "so a run cannot read 'armed' while its primary proposer is starved."
-- It closed starvation. It did not close UNREACHABILITY, and that is what run
-- dde654cc-b734-4c75-a401-0358f4e02d2d demonstrates:
--
--   ottoq_agentic_arming(run) -> verdict "armed", satisfied 7, required 7, missing []
--   ottoq_proposer_fire_log   -> ZERO rows for this run
--
-- The dials are all set. The proposer they arm never ran. An operator, a
-- reviewer, or an auditor reading that attestation is told the agentic layer is
-- fully live, and 0248 §5 shows what is actually happening: cuOpt does 100% of
-- the assignment work while `forward_lex`, declared rank 0 and `holds_tick` in
-- `ottoq_proposer_precedence`, contributes nothing.
--
-- ── WHY IT NEVER RAN, ESTABLISHED RATHER THAN ASSUMED ──────────────────────
--
-- This was traced through the deployed edge sources, not the repo's copies --
-- which matters, because the repo is stale on both of them (G67). The live chain:
--
--   1. ottoq-orchestrator-agent (deployed v26) reads
--      ottoq_policy_get(run,'agent_solver_chain_enabled',0) >= 1 -- satisfied --
--      and POSTs the handoff to ottoq-cpsat-propose. Working.
--   2. ottoq-cpsat-propose (deployed v5) requires OTTOQ_INTEL_URL and
--      OTTOQ_INTEL_TOKEN. Both are unset, so it throws
--      "CP-SAT service is not configured" before building a request.
--   3. Its catch calls queueCuOptFallback -> ottoq_agent_solver_refresh and
--      returns HTTP 200 with { ok: true, engine: "cuopt", fallback: true,
--      fallback_reason: "CP-SAT service is not configured" }.
--   4. So ottoq_proposer_submit_batch(p_source := 'forward_lex') -- the ONLY
--      writer of ottoq_proposer_fire_log -- is never reached. No fire row. No
--      forward_lex proposal. cuOpt absorbs the work and the run looks healthy.
--
-- Measured on this run, every agent chain from tick 1 to tick 221:
--
--   solver_handoff.status  engine  fallback_reason                      n
--   fallback               cuopt   "CP-SAT service is not configured"  36
--
-- 36 of 36. Not intermittent, not a timeout, not a solver failure. **CP-SAT is
-- absent, not broken**, and the fallback is so well built that nothing upstream
-- noticed. That is a compliment to the fallback and an indictment of the
-- attestation: the one instrument whose job is to say whether the agentic layer
-- is live reported "armed" through all 36.
--
-- ── WHAT THIS MIGRATION DOES, AND THE LINE IT DOES NOT CROSS ──────────────
--
-- It does NOT fix CP-SAT. It cannot: `OTTOQ_INTEL_URL` and `OTTOQ_INTEL_TOKEN`
-- are edge-function secrets and the `ottoq-intelligence` host they point at must
-- be running. Both are founder actions. The bridge's own comment is explicit
-- that the host is expected to come and go -- "The solver host may be
-- intentionally stopped between development sessions" -- with a 5-second
-- AbortSignal.timeout so the chain fails over promptly. That design is right and
-- is left alone.
--
-- What it fixes is the REPORTING, which is this repo's standing rule: a number
-- that flatters us is a defect regardless of which layer produced it. After this
-- migration `ottoq_agentic_arming` answers two questions instead of one -- are
-- the dials set, AND did the proposer they arm actually run -- and it refuses to
-- say plain "armed" when the answer to the second is no.
--
-- ── THE VERDICT VOCABULARY, AND WHY CHANGING IT IS SAFE ───────────────────
--
-- New value: **`armed_primary_unreachable`**. Reached only when all 7 dials are
-- satisfied AND the evidence says the declared rank-0 proposer did not run.
-- `armed`, `partial`, `unarmed`, `cert_excluded` keep their exact meanings.
--
-- Checked before changing it, because a gate that tests `verdict = 'armed'`
-- would be inverted by this. Over every routine in the database: the only caller
-- of `ottoq_agentic_arming` is `ottoq_agentic_arm`, which returns the state after
-- arming and does not branch on it. Three other routines do contain the literal
-- `'armed'` -- `ottoq_cuopt_defer_arm`, `ottoq_cuopt_defer_roll`,
-- `ottoq_cuopt_first_refusal_arm` -- and none of them calls this function: that
-- is the cuOpt DEFERRAL state machine's own unrelated `'armed'` status. A5
-- asserts this census, so if a future gate starts branching on the verdict, this
-- migration's own assertion is what notices.
--
-- ── THE EVIDENCE RULE, AND ITS DELIBERATE BLIND SPOT ──────────────────────
--
-- `reachable` is three-valued, and the third value is the point:
--
--   true   the fire log has >= 1 row for this run from the declared primary
--   false  zero fire rows AND every agent chain recorded fallback or failure
--   null   fewer than 3 agent chains -- NOT ENOUGH EVIDENCE, and the verdict
--          stays `armed`
--
-- The null case exists so a run that has simply not had an agent pass yet is
-- never accused. A fresh run at tick 0 has 0 fires and 0 chains, which is
-- indistinguishable from unreachable if you only count fires. Requiring 3
-- chains that ALL fell back is what makes `false` mean something. On run
-- dde654cc it is 36 chains, so the finding is not near the threshold.
--
-- And the blind spot, named rather than hidden: a run whose agent chains fall
-- back for a DIFFERENT reason -- a real solver crash, a 502 from a configured
-- host -- also reads `reachable: false`. That is correct for the attestation's
-- purpose (the primary did not run) but it is not a diagnosis, which is why
-- `last_reason` is carried verbatim beside it. The reason string is the
-- diagnosis; `reachable` is only the verdict.

BEGIN;

-- ── P1  the defect is present on a real run, exactly as described ──────────
DO $$
DECLARE v_run uuid; v_verdict text; v_fires int; v_chains int; v_fb int;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE status = 'running' AND COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0349 P1: no running non-cert run; applying on catalog evidence alone';
    RETURN;
  END IF;

  v_verdict := public.ottoq_agentic_arming(v_run) ->> 'verdict';

  SELECT count(*) INTO v_fires FROM public.ottoq_proposer_fire_log f
   WHERE f.sim_run_id = v_run;

  SELECT count(*),
         count(*) FILTER (WHERE d.enacted_action->'solver_handoff'->>'status'
                               IN ('fallback','failed'))
    INTO v_chains, v_fb
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = v_run AND d.resolved_action_context = 'orchestrator_agent';

  RAISE NOTICE '0349 P1: run % verdict=% fires=% chains=% fell_back_or_failed=%',
    v_run, v_verdict, v_fires, v_chains, v_fb;

  IF v_verdict = 'armed' AND v_fires = 0 AND v_chains >= 3 AND v_fb = v_chains THEN
    RAISE NOTICE '0349 P1: ok -- the defect is live: armed with zero fires across % chains', v_chains;
  ELSE
    RAISE NOTICE '0349 P1: the live run does not currently exhibit the defect; the fix is still correct and A2/A3 prove it synthetically';
  END IF;
END $$;

-- ── P2  the declared primary is discoverable, and is not cuOpt ─────────────
DO $$
DECLARE v_primary text;
BEGIN
  SELECT source INTO v_primary FROM public.ottoq_proposer_precedence
   ORDER BY rank, source LIMIT 1;
  IF v_primary IS NULL THEN
    RAISE EXCEPTION '0349 P2: ottoq_proposer_precedence is empty; there is no declared primary to judge';
  END IF;
  IF v_primary = 'cuopt' THEN
    RAISE EXCEPTION '0349 P2: the declared rank-0 proposer is cuopt, which is the FALLBACK -- re-read 0335 before applying this file';
  END IF;
  RAISE NOTICE '0349 P2: declared rank-0 proposer is %', v_primary;
END $$;

-- ── THE FIX ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_agentic_arming(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_run_by text; v_found boolean;
  v_keys   jsonb := '[]'::jsonb;
  v_k      record;
  v_have   numeric; v_ok int := 0; v_tot int := 0;
  v_missing text[] := ARRAY[]::text[];
  -- 0349: the evidence half.
  v_primary   text;
  v_fires     int := 0;
  v_chains    int := 0;
  v_fellback  int := 0;
  v_failed    int := 0;
  v_reason    text;
  v_reachable boolean;          -- three-valued on purpose; NULL = not enough evidence
  v_min_chains constant int := 3;
  v_verdict   text;
BEGIN
  SELECT r.run_by, true INTO v_run_by, v_found
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT COALESCE(v_found, false) THEN
    RETURN jsonb_build_object('verdict','unknown_run','sim_run_id',p_sim_run_id);
  END IF;

  FOR v_k IN
    SELECT * FROM (VALUES
      ('agent_solver_chain_enabled',     1::numeric,
       '0331: one chain owns analysis -> solve -> deterministic disposal'),
      ('cuopt_propose_enabled',          1::numeric,
       '0056/0113: the solver seat and first-refusal machinery are live'),
      ('orchestrator_agent_enabled',     1::numeric,
       '0112/0113: Nemotron is allowed to analyze and hand off'),
      ('proposer_frame_facts',           1::numeric,
       '0265: the frame carries the facts the door pre-filters on'),
      ('proposer_hold_enabled',          1::numeric,
       '0259/0262: one-tick right of first refusal for a non-cuOpt proposer'),
      ('cuopt_first_refusal_max_defers', 1::numeric,
       '0152 set the global tier to 0; without a run row nothing is ever armed'),
      ('prearrival_charge_yields_to_solver', 1::numeric,
       '0339: the charge stall is not reserved before the primary proposer can see it')
    ) AS t(param_key, required, why)
    ORDER BY 1
  LOOP
    v_tot := v_tot + 1;
    --: The DEFAULT passed here is deliberately 0, not the caller default the
    --: engine's own readers use. This function asks "what is SET", and a key
    --: that resolves only through a caller's fallback is not set.
    v_have := COALESCE(public.ottoq_policy_get(p_sim_run_id, v_k.param_key, 0), 0);
    IF v_have >= v_k.required THEN
      v_ok := v_ok + 1;
    ELSE
      v_missing := v_missing || v_k.param_key;
    END IF;
    v_keys := v_keys || jsonb_build_array(jsonb_build_object(
      'param_key', v_k.param_key, 'required', v_k.required,
      'in_force', v_have, 'satisfied', v_have >= v_k.required, 'why', v_k.why));
  END LOOP;

  -- ── 0349: SEVEN SET DIALS ARE NOT A RUNNING PROPOSER ────────────────────
  -- Every dial above is a statement of INTENT read out of ottoq_policy_params.
  -- None of them observes whether the proposer they arm actually ran. Run
  -- dde654cc read "armed, 7 of 7" while ottoq_proposer_fire_log held zero rows
  -- for it and all 36 agent chains recorded
  -- fallback_reason "CP-SAT service is not configured". The dials cannot see
  -- that, because the thing that failed is an edge-function secret.
  SELECT source INTO v_primary FROM public.ottoq_proposer_precedence
   ORDER BY rank, source LIMIT 1;

  SELECT count(*) INTO v_fires
    FROM public.ottoq_proposer_fire_log f
   WHERE f.sim_run_id = p_sim_run_id
     AND (v_primary IS NULL OR f.declared_source = v_primary);

  SELECT count(*),
         count(*) FILTER (WHERE d.enacted_action->'solver_handoff'->>'status' = 'fallback'),
         count(*) FILTER (WHERE d.enacted_action->'solver_handoff'->>'status' = 'failed')
    INTO v_chains, v_fellback, v_failed
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = p_sim_run_id
     AND d.resolved_action_context = 'orchestrator_agent';

  -- The reason is the diagnosis; reachable is only the verdict. Carried verbatim
  -- so a real solver crash is never mistaken for a missing configuration.
  SELECT COALESCE(d.enacted_action->'solver_handoff'->>'fallback_reason',
                  d.enacted_action->'solver_handoff'->>'error')
    INTO v_reason
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = p_sim_run_id
     AND d.resolved_action_context = 'orchestrator_agent'
     AND COALESCE(d.enacted_action->'solver_handoff'->>'fallback_reason',
                  d.enacted_action->'solver_handoff'->>'error') IS NOT NULL
   ORDER BY d.tick_seq DESC
   LIMIT 1;

  -- Three-valued. NULL protects a run that has simply not had an agent pass yet:
  -- 0 fires / 0 chains is indistinguishable from unreachable if you count only
  -- fires, so `false` requires at least v_min_chains chains that ALL fell back.
  v_reachable := CASE
    WHEN v_fires > 0                                        THEN true
    WHEN v_chains >= v_min_chains
     AND (v_fellback + v_failed) >= v_chains                THEN false
    ELSE NULL
  END;

  v_verdict := CASE
    WHEN v_run_by = 'cert_harness'                THEN 'cert_excluded'
    WHEN v_ok = v_tot AND v_reachable IS FALSE    THEN 'armed_primary_unreachable'
    WHEN v_ok = v_tot                             THEN 'armed'
    WHEN v_ok = 0                                 THEN 'unarmed'
    ELSE 'partial' END;

  RETURN jsonb_build_object(
    'sim_run_id', p_sim_run_id,
    'run_by', v_run_by,
    'verdict', v_verdict,
    'satisfied', v_ok, 'required', v_tot,
    'missing', to_jsonb(v_missing), 'keys', v_keys,
    'primary_proposer', jsonb_build_object(
      'declared',    v_primary,
      'reachable',   v_reachable,
      'fires',       v_fires,
      'agent_chains', v_chains,
      'fell_back',   v_fellback,
      'failed',      v_failed,
      'last_reason', v_reason,
      'min_chains_to_judge', v_min_chains,
      'judged_on', 'ottoq_proposer_fire_log rows for this run from the rank-0 '
                || 'source in ottoq_proposer_precedence, against '
                || 'ottoq_decisions.enacted_action->solver_handoff->>status '
                || 'over this run''s orchestrator_agent chains'));
END $function$;

COMMENT ON FUNCTION public.ottoq_agentic_arming(uuid) IS
  'Agentic-layer attestation, two questions since 0349. (1) INTENT: are the seven '
  'required policy dials set (satisfied/required/missing/keys). (2) EVIDENCE: did '
  'the declared rank-0 proposer actually run on this run (primary_proposer). '
  'verdict is armed_primary_unreachable when all dials are set but the fire log '
  'is empty and >= min_chains_to_judge agent chains all fell back or failed -- '
  'the state run dde654cc was in while reporting plain "armed", with cuOpt doing '
  '100% of assignment work and forward_lex contributing nothing because '
  'OTTOQ_INTEL_URL/OTTOQ_INTEL_TOKEN are unset. primary_proposer.reachable is '
  'three-valued: NULL means too few chains to judge, never an accusation. '
  'last_reason is the diagnosis; reachable is only the verdict.';

-- ── A1  the live run now reports the truth ────────────────────────────────
DO $$
DECLARE v_run uuid; v_a jsonb; v_pp jsonb;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE status = 'running' AND COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0349 A1: no running run to read; A2/A3 carry the proof';
    RETURN;
  END IF;

  v_a  := public.ottoq_agentic_arming(v_run);
  v_pp := v_a -> 'primary_proposer';

  IF v_pp IS NULL THEN
    RAISE EXCEPTION '0349 A1: primary_proposer block is absent from the attestation';
  END IF;
  IF NOT (v_pp ? 'reachable' AND v_pp ? 'fires' AND v_pp ? 'agent_chains'
          AND v_pp ? 'last_reason' AND v_pp ? 'declared') THEN
    RAISE EXCEPTION '0349 A1: primary_proposer is missing a required field: %', v_pp;
  END IF;
  -- The dial half must be byte-identical to before: this migration adds a
  -- question, it does not change the answer to the old one.
  IF (v_a->>'required')::int <> 7 THEN
    RAISE EXCEPTION '0349 A1: required went to %, expected 7 -- the dial list changed', v_a->>'required';
  END IF;

  RAISE NOTICE '0349 A1: run % verdict=% reachable=% fires=% chains=% reason=%',
    v_run, v_a->>'verdict', v_pp->>'reachable', v_pp->>'fires',
    v_pp->>'agent_chains', left(COALESCE(v_pp->>'last_reason','<none>'), 60);
END $$;

-- ── A2  THE CORE ASSERTION: the new verdict fires on real evidence ─────────
-- If the live run is in the defect state, the attestation must now SAY so. A
-- reporting fix that does not change what the report says is not a fix.
DO $$
DECLARE v_run uuid; v_a jsonb; v_fires int; v_chains int; v_fb int;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE status = 'running' AND COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;

  SELECT count(*) INTO v_fires FROM public.ottoq_proposer_fire_log f
   WHERE f.sim_run_id = v_run;
  SELECT count(*),
         count(*) FILTER (WHERE d.enacted_action->'solver_handoff'->>'status'
                               IN ('fallback','failed'))
    INTO v_chains, v_fb
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = v_run AND d.resolved_action_context = 'orchestrator_agent';

  IF v_fires = 0 AND v_chains >= 3 AND v_fb = v_chains THEN
    v_a := public.ottoq_agentic_arming(v_run);
    IF (v_a->'primary_proposer'->>'reachable') IS DISTINCT FROM 'false' THEN
      RAISE EXCEPTION '0349 A2: the run has 0 fires over % all-fallback chains but reachable reads % -- the evidence rule does not fire',
        v_chains, COALESCE(v_a->'primary_proposer'->>'reachable','<null>');
    END IF;
    IF (v_a->>'satisfied')::int = (v_a->>'required')::int
       AND v_a->>'verdict' <> 'armed_primary_unreachable' THEN
      RAISE EXCEPTION '0349 A2: all dials satisfied and the primary is unreachable, but verdict reads % -- the attestation still flatters the run',
        v_a->>'verdict';
    END IF;
    IF (v_a->'primary_proposer'->>'last_reason') IS NULL THEN
      RAISE EXCEPTION '0349 A2: reachable is false but no reason was carried -- the verdict arrived without its diagnosis';
    END IF;
    RAISE NOTICE '0349 A2: ok -- verdict %, reason %',
      v_a->>'verdict', left(v_a->'primary_proposer'->>'last_reason', 70);
  ELSE
    RAISE NOTICE '0349 A2: live run is not in the defect state (fires=%, chains=%, fell_back=%); A3 carries the proof',
      v_fires, v_chains, v_fb;
  END IF;
END $$;

-- ── A3  IT DOES NOT CRY WOLF: a fire makes the run reachable again ─────────
-- Planted inside a subtransaction that is rolled back. Without this, "reachable
-- false" could be a constant, which is the same defect in the other direction.
DO $$
DECLARE v_run uuid; v_depot uuid; v_primary text; v_before text; v_after text;
BEGIN
  SELECT sim_run_id, depot_id INTO v_run, v_depot FROM public.ottoq_sim_runs
   WHERE status = 'running' AND COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0349 A3: no running run; cannot plant a fire';
    RETURN;
  END IF;
  SELECT source INTO v_primary FROM public.ottoq_proposer_precedence ORDER BY rank, source LIMIT 1;

  v_before := COALESCE(public.ottoq_agentic_arming(v_run)->'primary_proposer'->>'reachable', 'null');

  BEGIN
    -- `fire` is NOT NULL with no default, so it must be supplied; it is tagged so
    -- that if this row ever DID leak (A4 forbids it) its origin is unambiguous.
    INSERT INTO public.ottoq_proposer_fire_log
      (sim_run_id, depot_id, declared_source, status, fired_at, fire)
    VALUES (v_run, v_depot, v_primary, 'submitted', now(),
            jsonb_build_object('planted_by','0349 A3','rolled_back',true));

    v_after := COALESCE(public.ottoq_agentic_arming(v_run)->'primary_proposer'->>'reachable', 'null');
    RAISE EXCEPTION 'OTTOQ_0349_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'OTTOQ_0349_ROLLBACK' THEN
      RAISE EXCEPTION '0349 A3: planting a fire row failed: %', SQLERRM;
    END IF;
  END;

  IF v_after IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0349 A3: one planted fire from the declared primary left reachable at % -- the signal is a constant, not a measurement', COALESCE(v_after,'<null>');
  END IF;
  RAISE NOTICE '0349 A3: ok -- reachable moved % -> true on one planted fire, rolled back', v_before;
END $$;

-- ── A4  the planted fire did not survive ──────────────────────────────────
DO $$
DECLARE v_run uuid; v_n int;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE status = 'running' AND COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_proposer_fire_log
   WHERE sim_run_id = v_run;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0349 A4: the run has % fire row(s); A3''s planted row leaked into the engine', v_n;
  END IF;
END $$;

-- ── A5  the verdict-literal census this migration relied on still holds ───
-- The safety argument for adding a verdict value was that nothing branches on
-- it. If that stops being true, this assertion is what notices.
DO $$
DECLARE v_callers text; v_n int;
BEGIN
  SELECT string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname), count(*)
    INTO v_callers, v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog','information_schema')
     AND p.prosrc ILIKE '%agentic_arming%'
     AND p.proname <> 'ottoq_agentic_arming';
  -- Schema-qualified, because that is what the string_agg above produces.
  IF COALESCE(v_callers,'') <> 'public.ottoq_agentic_arm' THEN
    RAISE EXCEPTION '0349 A5: callers of ottoq_agentic_arming are now [%] -- the file argued only ottoq_agentic_arm calls it and does not branch on the verdict. Re-audit before trusting armed_primary_unreachable.', COALESCE(v_callers,'<none>');
  END IF;
END $$;

-- ── CERT LINEAGE ──────────────────────────────────────────────────────────
-- forces_recert FALSE. ottoq_agentic_arming is a STABLE reporting function. It
-- is called by ottoq_agentic_arm (which returns its output) and by check files;
-- no tick path, no proposer, no shield evaluator reads it, and it writes nothing.
-- The seven dials and their required values are unchanged (A1 asserts required=7),
-- so no run's behaviour moves -- only what the attestation says about it.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0349_a_run_reads_armed_while_its_rank_zero_proposer_is_unreachable', false,
  'ottoq_agentic_arming answered one question -- are the seven dials set -- and run dde654cc read "armed, 7 of 7" while ottoq_proposer_fire_log held ZERO rows for it and all 36 orchestrator_agent chains (ticks 1-221) recorded solver_handoff {status: fallback, engine: cuopt, fallback_reason: "CP-SAT service is not configured"}. Traced through the DEPLOYED edge sources: ottoq-cpsat-propose v5 requires OTTOQ_INTEL_URL and OTTOQ_INTEL_TOKEN, both unset, so it throws before building a request and its catch queues the cuOpt fallback with HTTP 200 -- meaning ottoq_proposer_submit_batch, the only writer of the fire log, is never reached. CP-SAT is absent, not broken. This migration adds the evidence half: a primary_proposer block (declared/reachable/fires/agent_chains/fell_back/failed/last_reason) and a new verdict armed_primary_unreachable when all dials are set but the rank-0 proposer demonstrably did not run. reachable is three-valued so a run with fewer than 3 agent chains is never accused. Safe because the only caller is ottoq_agentic_arm and it does not branch on the verdict (A5 asserts that census). Proven both ways: A2 requires the new verdict on the live defect state, A3 plants one fire row in a rolled-back subtransaction and requires reachable to return to true so the signal is a measurement rather than a constant. Does NOT fix CP-SAT: the two secrets and the ottoq-intelligence host are founder actions.',
  now())
ON CONFLICT(name) DO NOTHING;

COMMIT;
