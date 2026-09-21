-- migration-version: 20260919210336
-- migration-name:    the_shield_gains_a_fifth_probe_point_and_the_ai_write_path_finally_lands_in_its_ledger
--
-- 0353  NO AI-ORIGINATED STATE CHANGE HAS EVER APPEARED IN THE SHIELD'S LEDGER.
--
-- Part two of two; 0352 put the agent's envelope into ottoq_policy_param_catalog
-- and published it as ottoq_agent_dial_envelope(). This file gives the shield a
-- rule that reads it, at a new probe point.
--
-- ── THE FINDING ────────────────────────────────────────────────────────────
--
-- Run dde654cc holds 177,179 ottoq_rule_evaluations rows at FOUR probe points --
-- task_start (167,518), redeployment (7,140), stall_assignment (2,120),
-- bess_dispatch (401) -- and not one at a policy write. The four guards 0352
-- enumerates are real and they are INVISIBLE: no rule code, no severity, no
-- version, no row. "Show me, in one ledger, every deterministic check that
-- admitted an AI action" has no answer, and that is the question an OEM or AV
-- autonomy team asks first about an agentic layer.
--
-- ── WHAT IT DOES ───────────────────────────────────────────────────────────
--
-- (C) public.ottoq_rule_eval_agent_dial_envelope -- judges a dial write against
--     0352's envelope. Judges the REQUESTED value as it reaches the database,
--     not the clamped one: a rule that only ever sees a post-clamp value cannot
--     fail, which is the G25/G28 vacuous class (0347's A3 tested
--     severity='blocking' against a function that returns 'block', and asserted
--     nothing at all).
-- (D) AI.001.agent_dial_within_envelope, registered at action_context
--     `policy_write` -- the fifth probe point that is actually CALLED. Note the
--     distinction, because it is the kind an auditor checks: ottoq_rules already
--     declares THIRTY distinct action_contexts, of which exactly four have ever
--     produced a logged evaluation. The other twenty-six are G44 -- declared
--     rules whose evaluators exist and whose callers do not. "Fifth probe point"
--     in this file always means the fifth with a caller, never the fifth
--     declared, and A5 counts callers for exactly that reason.
-- (E) ottoq_policy_set probes it on every dial write, by any actor, through
--     ottoq_shield_probe. That entry point was chosen by census rather than
--     taste: all four existing probe points (ottoq_decide_tick,
--     ottoq_shield_and_log, ottoq.ottoq_enact_inspection_seam) call it, while
--     ottoq_evaluate_rules_for_action serves ottoq_emit_recommendation and one
--     evaluator. Both work; only one is the convention, and only
--     ottoq_shield_probe returns `would_block`, which is exactly what promoting
--     this rule out of log_only will need to read.
--
-- ── THE LINE THIS FILE DOES NOT CROSS, STATED SO IT CANNOT BE OVERCLAIMED ──
--
-- The rule is registered `enforcement = 'log_only'`. IT CANNOT REFUSE A WRITE.
-- This migration makes the AI write path VISIBLE to the shield; it does not yet
-- let the shield stop it. That is deliberate, and it is this repo's own doctrine
-- (CLAUDE.md 2.9a): added MEASURED first, ENFORCED only after a flagship round
-- shows it behaves -- 0139 / 0206 / 0217 / 0225 all did exactly this. The honest
-- sentence until promotion is "every dial write is now evaluated and logged;
-- refusal is not yet wired."
--
-- `log_only` rather than `shadow` for one measured reason:
-- ottoq_evaluate_rule_core emits a signed ottoq_events row for EVERY shadow
-- evaluation and only for FAILURES under log_only. Same ledger row either way,
-- far fewer events, identical safety.
--
-- And note what this rule is NOT. It does not become a second engine-wide
-- clamp: a non-agent actor passes unjudged, because ottoq_policy_set's catalog
-- bounds already govern everyone and duplicating them here would mean two
-- places to change one limit.
--
-- ── ONE TRAP WALKED INTO AND BACKED OUT OF, RECORDED BECAUSE IT WOULD HAVE
--    BROKEN CERTIFICATION SILENTLY ─────────────────────────────────────────
--
-- The obvious wiring is p_entity_id := p_scope_id. For scope_type='run' that IS
-- THE SIM RUN ID, which differs between the two arms of a determinism pair by
-- construction -- and ottoq_hash_rule_evaluations digests entity_id. Every
-- certification pair would have disagreed on h_rule, and the cause would have
-- looked like anything except this file. It is 0139's lesson (a run-scoped id
-- inside a fingerprint) arriving through a new door, and it is the fourth
-- instance of that class in this repo.
--
-- So: entity_id carries the scope id ONLY for non-run scopes, the run id rides
-- in p_context, and the payload carries no id and no timestamp. The `context`
-- column is stored and is NOT one of the eleven terms
-- ottoq_hash_rule_evaluations digests (it hashes parameters_used and
-- result_payload, never context) -- verified against the live body, and A6
-- re-asserts BOTH halves so a future change to that hash cannot silently
-- re-arm the trap.
--
-- forces_recert TRUE, for a measured reason rather than caution: a run after
-- this migration carries ottoq_rule_evaluations rows at a probe point no
-- earlier run had, so h_rule moves and every canon predating it is correctly
-- invalidated. That is the canon machinery working, not a cost.

BEGIN;

-- ══════════════════════════════════════════════════════════════════════════
-- P0  PRE-IMAGE PINS. The substitution in (E) is only the substitution this
--     file describes if the body has not moved and the anchor is unique.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_def       text;
  v_anchor    constant text :=
    'INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)';
  v_n         int;
  v_overloads int;
BEGIN
  SELECT count(*) INTO v_overloads
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';
  IF v_overloads <> 1 THEN
    RAISE EXCEPTION '0353 P0: expected exactly 1 ottoq_policy_set, found %', v_overloads;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';

  IF md5(v_def) <> '3b497067448c07936badbe9e372f537e' THEN
    RAISE EXCEPTION '0353 P0: ottoq_policy_set body moved. expected md5 3b497067..., got % (len %)',
      md5(v_def), length(v_def);
  END IF;

  v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0353 P0: anchor occurs % times, expected exactly 1', v_n;
  END IF;

  RAISE NOTICE '0353 P0: ok -- one overload, body md5 3b497067, anchor unique (def len %)', length(v_def);
END $$;

-- ── P1  0352 must be in place, or the rule judges against nothing ─────────
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog WHERE agent_writable;
  IF v_n <> 6 THEN
    RAISE EXCEPTION '0353 P1: expected 0352''s six agent_writable dials, found % -- apply 0352 first', v_n;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_rules WHERE rule_code = 'AI.001.agent_dial_within_envelope') THEN
    RAISE EXCEPTION '0353 P1: AI.001.agent_dial_within_envelope is already registered';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_rule_evaluations WHERE action_context = 'policy_write') THEN
    RAISE EXCEPTION '0353 P1: policy_write evaluations already exist -- this probe point is not new';
  END IF;
  RAISE NOTICE '0353 P1: ok -- 0352 present, rule unregistered, policy_write is a new probe point';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- (C)  THE EVALUATOR
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_rule_eval_agent_dial_envelope(
  p_entity_type text,
  p_entity_id   uuid,
  p_context     jsonb,
  p_parameters  jsonb
) RETURNS public.ottoq_rule_result
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_key      text;
  v_by       text;
  v_req      numeric;
  v_actors   text[];
  v_writable boolean;
  v_lo       numeric;
  v_hi       numeric;
  v_found    boolean := false;
  v_payload  jsonb;
BEGIN
  v_key := NULLIF(p_context ->> 'param_key', '');
  v_by  := COALESCE(p_context ->> 'by', '');
  BEGIN
    v_req := (p_context ->> 'requested')::numeric;
  EXCEPTION WHEN OTHERS THEN
    v_req := NULL;
  END;

  -- Parameterizable like every other rule's thresholds, so a second agent
  -- identity is a data change rather than a migration.
  v_actors := COALESCE(
    NULLIF(ARRAY(SELECT jsonb_array_elements_text(p_parameters -> 'agent_actors')), '{}'),
    ARRAY['ottoq_prime']);

  -- A malformed probe is not a violation. ottoq_policy_set refuses a NULL value
  -- and an unknown param on its own, with its own error codes; this rule must
  -- not double-report those as an envelope breach.
  IF v_key IS NULL OR v_req IS NULL THEN
    RETURN ROW(TRUE, 'no dial write to judge', NULL,
      jsonb_build_object('source','policy_write','judged',false,
                         'why','param_key or requested absent'),
      NULL)::public.ottoq_rule_result;
  END IF;

  IF NOT (v_by = ANY(v_actors)) THEN
    RETURN ROW(TRUE, format('actor %s is not an agent', v_by), NULL,
      jsonb_build_object('source','policy_write','judged',false,
                         'param_key',v_key,'by',v_by,'requested',v_req),
      NULL)::public.ottoq_rule_result;
  END IF;

  -- From here the actor IS an agent, and every branch below is a verdict.
  SELECT c.agent_writable, c.agent_min_value, c.agent_max_value, true
    INTO v_writable, v_lo, v_hi, v_found
    FROM public.ottoq_policy_param_catalog c
   WHERE c.param_key = v_key;

  v_payload := jsonb_build_object(
    'source','policy_write','judged',true,
    'param_key',v_key,'by',v_by,'requested',v_req,
    'agent_lo',v_lo,'agent_hi',v_hi,
    'agent_writable',COALESCE(v_writable,false));

  IF NOT v_found THEN
    RETURN ROW(FALSE, format('agent wrote an uncatalogued dial: %s', v_key), 'critical',
      v_payload, 'catalog_the_dial_or_remove_it_from_the_agent')::public.ottoq_rule_result;
  END IF;

  IF NOT v_writable THEN
    RETURN ROW(FALSE, format('dial %s is not agent-writable', v_key), 'critical',
      v_payload, 'set_agent_writable_or_block_the_actor')::public.ottoq_rule_result;
  END IF;

  IF v_lo IS NOT NULL AND v_req < v_lo THEN
    RETURN ROW(FALSE, format('%s = %s is below the agent floor %s', v_key, v_req, v_lo),
      'critical', v_payload, 'clamp_to_agent_envelope')::public.ottoq_rule_result;
  END IF;

  IF v_hi IS NOT NULL AND v_req > v_hi THEN
    RETURN ROW(FALSE, format('%s = %s is above the agent ceiling %s', v_key, v_req, v_hi),
      'critical', v_payload, 'clamp_to_agent_envelope')::public.ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, format('%s = %s within agent envelope [%s, %s]', v_key, v_req, v_lo, v_hi),
    NULL, v_payload, NULL)::public.ottoq_rule_result;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_rule_eval_agent_dial_envelope(text, uuid, jsonb, jsonb) IS
  '0353. Evaluator for AI.001.agent_dial_within_envelope, judging against 0352''s '
  'agent envelope. It judges the REQUESTED value as it reaches the database, not '
  'the clamped one -- a rule that only ever sees a post-clamp value cannot fail '
  'and would be the G25/G28 vacuous class. Its payload carries no id and no '
  'timestamp, because ottoq_hash_rule_evaluations digests result_payload and a '
  'run-scoped value there would break every determinism pair (0139''s lesson).';

-- ══════════════════════════════════════════════════════════════════════════
-- (D)  REGISTER THE RULE
-- ══════════════════════════════════════════════════════════════════════════
SELECT public.ottoq_register_rule(
  p_rule_code          := 'AI.001.agent_dial_within_envelope',
  p_category           := 'role_authorization',
  p_title              := 'An AI actor may only move a dial it is declared to own, inside its declared envelope',
  p_description        := 'On every write to ottoq_policy_params, if the actor is one of the declared '
                          'agent actors, the requested value must name an agent_writable dial in '
                          'ottoq_policy_param_catalog and fall within agent_min_value..agent_max_value. '
                          'A non-agent actor passes unjudged; the engine-wide catalog bounds still apply '
                          'to everyone through ottoq_policy_set.',
  p_rationale          := 'The agent''s limits lived only in edge-function TypeScript, and the catalog '
                          'was wider than the agent envelope on three of six dials, so nothing in this '
                          'engine could state what the model was permitted to do. And no AI-originated '
                          'state change appeared in ottoq_rule_evaluations at all -- 177,179 rows on run '
                          'dde654cc, at four probe points, none of them a policy write.',
  p_severity           := 'critical',
  p_enforcement        := 'log_only',
  p_scope              := 'system',
  p_evaluator_function := 'ottoq_rule_eval_agent_dial_envelope',
  p_default_parameters := jsonb_build_object('agent_actors', jsonb_build_array('ottoq_prime')),
  p_applies_to_actions := ARRAY['policy_write'],
  p_applies_to_entities:= ARRAY['policy_param'],
  p_introduced_in      := '0353',
  p_external_references:= jsonb_build_object(
                            'finding', 'G64',
                            'note', 'log_only on purpose: measured first, enforced after a flagship '
                                    'round, per CLAUDE.md 2.9a. Promotion to block is a later migration '
                                    'and must read ottoq_shield_probe.would_block.'),
  p_override_allowed   := false,
  p_status             := 'active'
);

-- ══════════════════════════════════════════════════════════════════════════
-- (E)  WIRE THE PROBE INTO ottoq_policy_set
--      Catalog-derived anchored substitution: not one character of the
--      existing 4,372 is retyped.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_def    text;
  v_anchor constant text :=
    'INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)';
  v_probe  constant text :=
$probe$  -- 0353: THE SHIELD LEARNS THAT DIAL WRITES EXIST.
  -- Probed HERE -- after every argument validation, after the catalog lookup,
  -- and BEFORE the clamped value is written -- so the rule judges what the
  -- caller ASKED for. A rule that only ever sees a post-clamp value can never
  -- fail, which is the vacuous-assertion class this repo has shipped twice.
  --
  -- entity_id is the scope id ONLY for non-run scopes. For scope_type='run' it
  -- would be the sim_run_id, which differs between the two arms of a
  -- determinism pair and IS digested by ottoq_hash_rule_evaluations; the run
  -- rides in the context column instead, which that hash does not read.
  --
  -- Error-swallowed on purpose: a reporting probe must never be able to refuse
  -- a write ottoq_policy_set would otherwise have accepted. The rule is
  -- registered log_only so it cannot block; this is the second belt.
  BEGIN
    PERFORM 1 FROM public.ottoq_shield_probe(
      p_action_context := 'policy_write',
      p_entity_type    := 'policy_param',
      p_entity_id      := CASE WHEN p_scope_type = 'run' THEN NULL ELSE p_scope_id END,
      p_context        := jsonb_build_object(
                            'param_key',  p_param_key,
                            'requested',  p_param_value,
                            'by',         p_by,
                            'scope_type', p_scope_type,
                            'scope_id',   p_scope_id));
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

$probe$;
  v_new    text;
  v_before int;
  v_after  int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';

  v_before := length(v_def);
  v_new    := replace(v_def, v_anchor, v_probe || v_anchor);
  v_after  := length(v_new);

  IF v_after - v_before <> length(v_probe) THEN
    RAISE EXCEPTION '0353 E: substitution moved the body by % characters, expected %',
      v_after - v_before, length(v_probe);
  END IF;
  IF position(v_anchor IN v_new) = 0 THEN
    RAISE EXCEPTION '0353 E: the anchor did not survive the substitution';
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0353 E: ok -- ottoq_policy_set % -> % chars (+%)', v_before, v_after, length(v_probe);
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A1  THE NON-VACUITY GATE. Five cases, both polarities.
--     A rule that passes everything is the G25/G28 defect wearing a rule code.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_params constant jsonb := jsonb_build_object('agent_actors', jsonb_build_array('ottoq_prime'));
  r        public.ottoq_rule_result;
BEGIN
  -- (a) agent, in envelope -> PASS
  SELECT * INTO r FROM public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
    jsonb_build_object('param_key','energy_demand_factor_peak','requested',0.5,'by','ottoq_prime'),
    v_params);
  IF NOT r.passed THEN RAISE EXCEPTION '0353 A1a: in-envelope agent write failed: %', r.reason; END IF;

  -- (b) THE CASE THIS MIGRATION EXISTS FOR. 0.93 is LEGAL to ottoq_policy_set
  --     (catalog max 0.95) and ILLEGAL to the agent (ceiling 0.9). If it passes,
  --     the envelope is decorative and 0352 bought nothing.
  SELECT * INTO r FROM public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
    jsonb_build_object('param_key','energy_demand_factor_peak','requested',0.93,'by','ottoq_prime'),
    v_params);
  IF r.passed THEN
    RAISE EXCEPTION '0353 A1b: 0.93 passed the agent ceiling 0.9 -- the rule cannot fail';
  END IF;
  RAISE NOTICE '0353 A1b: ok -- %', r.reason;

  -- (c) agent, a dial it does not own -> FAIL
  SELECT * INTO r FROM public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
    jsonb_build_object('param_key','agent_asset_depth_enabled','requested',1,'by','ottoq_prime'),
    v_params);
  IF r.passed THEN
    RAISE EXCEPTION '0353 A1c: the agent was allowed a dial that is not agent_writable';
  END IF;

  -- (d) a non-agent actor writing the SAME out-of-envelope value -> PASS. The
  --     rule judges AI actors; it must not become a second engine-wide clamp.
  SELECT * INTO r FROM public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
    jsonb_build_object('param_key','energy_demand_factor_peak','requested',0.93,'by','scenario_loader'),
    v_params);
  IF NOT r.passed THEN
    RAISE EXCEPTION '0353 A1d: a non-agent actor was judged against the agent envelope: %', r.reason;
  END IF;

  -- (e) a malformed probe is not a violation
  SELECT * INTO r FROM public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
    jsonb_build_object('by','ottoq_prime'), v_params);
  IF NOT r.passed THEN RAISE EXCEPTION '0353 A1e: a malformed probe was reported as a breach'; END IF;

  RAISE NOTICE '0353 A1: ok -- passes in-envelope, FAILS over the agent ceiling and off the '
               'allowlist, ignores non-agent actors, tolerates a malformed probe';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A2  END TO END through ottoq_policy_set, in a rolled-back subtransaction.
--     Two things must BOTH hold: the ledger gains a row, and the write still
--     succeeds. A probe that changes the outcome is not a probe.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_res    jsonb;
  v_rows   int;
  v_taken  text;
  v_passed boolean;
  v_ctx    jsonb;
  v_run    uuid;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   ORDER BY (status = 'running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0353 A2: no run to scope a write to; A1 carries the proof';
    RETURN;
  END IF;

  BEGIN
    -- an out-of-envelope agent write: catalog-legal (max 0.95), agent-illegal (0.9)
    v_res := public.ottoq_policy_set('run', v_run, 'energy_demand_factor_peak', 0.93, 'ottoq_prime');

    IF COALESCE(v_res ->> 'ok', '') <> 'true' THEN
      RAISE EXCEPTION '0353 A2: the probe changed the outcome -- ottoq_policy_set returned %', v_res;
    END IF;

    SELECT count(*), max(enforcement_taken), bool_and(passed)
      INTO v_rows, v_taken, v_passed
      FROM public.ottoq_rule_evaluations
     WHERE action_context = 'policy_write'
       AND rule_code = 'AI.001.agent_dial_within_envelope';

    -- NOT max(context): there is no max() aggregate for jsonb in this Postgres,
    -- and CREATE FUNCTION would not have told me -- plpgsql plans lazily, so the
    -- first draft of this assertion compiled clean and would have raised 42883
    -- at apply time. Read the one row directly instead.
    SELECT e.context INTO v_ctx
      FROM public.ottoq_rule_evaluations e
     WHERE e.action_context = 'policy_write'
       AND e.rule_code = 'AI.001.agent_dial_within_envelope'
     ORDER BY e.evaluated_at DESC LIMIT 1;

    IF v_rows < 1 THEN RAISE EXCEPTION '0353 A2: the dial write produced no rule evaluation'; END IF;
    IF v_passed THEN RAISE EXCEPTION '0353 A2: the out-of-envelope write was recorded as passing'; END IF;
    IF v_taken <> 'logged' THEN
      RAISE EXCEPTION '0353 A2: enforcement_taken = %, expected logged (log_only must not block)', v_taken;
    END IF;

    -- the run must be recoverable from the row, or the ledger is anonymous
    IF COALESCE(v_ctx ->> 'scope_id', '') <> v_run::text THEN
      RAISE EXCEPTION '0353 A2: the evaluation does not name its run (context %)', v_ctx;
    END IF;
    -- and it must NOT be in entity_id, which is the hashed column
    IF EXISTS (SELECT 1 FROM public.ottoq_rule_evaluations
                WHERE rule_code = 'AI.001.agent_dial_within_envelope' AND entity_id = v_run) THEN
      RAISE EXCEPTION '0353 A2: the run id reached entity_id -- the certification trap is armed';
    END IF;

    RAISE NOTICE '0353 A2: ok -- write accepted (applied %), ledger row written, taken=%, run in context',
      v_res ->> 'applied', v_taken;

    RAISE EXCEPTION 'ottoq_0353_a2_rollback';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'ottoq_0353_a2_rollback' THEN RAISE; END IF;
  END;
END $$;

-- ── A3  the probe left no trace ───────────────────────────────────────────
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations
   WHERE rule_code = 'AI.001.agent_dial_within_envelope';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0353 A3: % evaluation rows leaked out of A2''s subtransaction', v_n;
  END IF;
  RAISE NOTICE '0353 A3: ok -- A2 left nothing behind';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A4  ottoq_policy_set's OWN refusals still work. The probe was inserted into
--     a function whose entire value is that it says no correctly.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v jsonb;
BEGIN
  v := public.ottoq_policy_set('global', NULL, 'energy_demand_factor_peak', NULL, '0353_assert');
  IF v ->> 'error' <> 'null_value' THEN RAISE EXCEPTION '0353 A4a: NULL refusal lost: %', v; END IF;

  v := public.ottoq_policy_set('global', NULL, 'no_such_dial_0353', 1, '0353_assert');
  IF v ->> 'error' <> 'unknown_param' THEN RAISE EXCEPTION '0353 A4b: unknown_param refusal lost: %', v; END IF;

  v := public.ottoq_policy_set('nonsense', NULL, 'energy_demand_factor_peak', 0.5, '0353_assert');
  IF v ->> 'error' <> 'invalid_scope_type' THEN RAISE EXCEPTION '0353 A4c: scope refusal lost: %', v; END IF;

  v := public.ottoq_policy_set('depot', NULL, 'energy_demand_factor_peak', 0.5, '0353_assert');
  IF v ->> 'error' <> 'scope_id_required' THEN RAISE EXCEPTION '0353 A4d: scope_id refusal lost: %', v; END IF;

  RAISE NOTICE '0353 A4: ok -- all four refusal paths intact';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A5  policy_write is declared by exactly this rule, and the four contexts
--     that actually LOG evaluations are still declared by a live rule.
--
--     An earlier draft of this assertion read "the shield declares at least 5
--     probe points" and was VACUOUS: ottoq_rules already declares THIRTY
--     distinct action_contexts, of which only four have ever produced a logged
--     evaluation (task_start 167,518 · redeployment 7,140 · stall_assignment
--     2,120 · bess_dispatch 401). That gap IS G44 -- nine declared rules have
--     an evaluator and no caller -- and it is why "the fifth probe point" in
--     this file means the fifth that is CALLED, never the fifth declared. An
--     assertion that counts declarations cannot tell the difference, so it
--     counts callers instead.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_declared int; v_n int; v_missing text; v_logged int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_rules r
   WHERE r.status IN ('active','shadow') AND 'policy_write' = ANY(r.applies_to_actions);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0353 A5: % live rules declare policy_write, expected exactly 1', v_n;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_rules r
                  WHERE r.status = 'active' AND r.rule_code = 'AI.001.agent_dial_within_envelope'
                    AND 'policy_write' = ANY(r.applies_to_actions)
                    AND r.enforcement = 'log_only' AND r.severity = 'critical') THEN
    RAISE EXCEPTION '0353 A5: the rule is not registered as active/log_only/critical on policy_write';
  END IF;

  SELECT string_agg(want, ', ') INTO v_missing
    FROM unnest(ARRAY['task_start','stall_assignment','redeployment','bess_dispatch']) want
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_rules r
                      WHERE r.status IN ('active','shadow') AND want = ANY(r.applies_to_actions));
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0353 A5: a probe point that logs evaluations lost its rule: %', v_missing;
  END IF;

  -- measured, and reported rather than asserted: the caller count does not move
  -- until a run writes a dial, because A2 rolled its own row back.
  SELECT count(DISTINCT a) INTO v_declared
    FROM public.ottoq_rules r, unnest(r.applies_to_actions) a WHERE r.status IN ('active','shadow');
  SELECT count(DISTINCT action_context) INTO v_logged FROM public.ottoq_rule_evaluations;
  RAISE NOTICE '0353 A5: ok -- policy_write declared by exactly this rule; % contexts declared, '
               '% have logged evaluations (policy_write becomes the fifth on the next dial write)',
               v_declared, v_logged;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A6  THE CERTIFICATION TRAP STAYS CLOSED, both halves.
--     The hash MUST digest entity_id (so a run id there would break a pair)
--     and MUST NOT digest the context column (so the run id is safe where this
--     file put it). Asserting only one half would let a future change re-arm it.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_hash_rule_evaluations';
  IF v_src IS NULL THEN RAISE EXCEPTION '0353 A6: ottoq_hash_rule_evaluations not found'; END IF;

  IF position('e.entity_id' IN v_src) = 0 THEN
    RAISE EXCEPTION '0353 A6: the hash no longer digests entity_id -- re-read this file''s trap note';
  END IF;
  IF position('e.context' IN v_src) <> 0 THEN
    RAISE EXCEPTION '0353 A6: the hash now digests the context column, where this file put the run id';
  END IF;
  RAISE NOTICE '0353 A6: ok -- entity_id hashed, context not; the run id rides safely';
END $$;

-- ── A7  the registry is still clean ───────────────────────────────────────
DO $$
DECLARE v_block int;
BEGIN
  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block <> 0 THEN
    RAISE EXCEPTION '0353 A7: % blocking run-scope registry defects', v_block;
  END IF;
  RAISE NOTICE '0353 A7: ok -- 0 blocking registry defects';
END $$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0353_the_shield_gains_a_fifth_probe_point_and_the_ai_write_path_finally_lands_in_its_ledger', true,
  'Part two of two (0352 added the envelope). Adds action_context `policy_write` -- the fifth L1 probe '
  'point that is actually CALLED, after task_start (167,518 logged evaluations), redeployment (7,140), '
  'stall_assignment (2,120) and bess_dispatch (401). Not the fifth DECLARED: ottoq_rules already declares '
  'thirty action_contexts and only those four have ever logged an evaluation, which is G44, and A5 counts '
  'callers rather than declarations because an earlier draft of it counted declarations and was therefore '
  'vacuous. Plus the '
  'rule AI.001.agent_dial_within_envelope that sits at it and the evaluator '
  'ottoq_rule_eval_agent_dial_envelope that judges against 0352''s catalog columns. Closes the measurable '
  'half of G64: run dde654cc held 177,179 rule evaluations at four probe points and not one at a policy '
  'write, so "show me every deterministic check that admitted an AI action" had no answer. Registered '
  'log_only, NOT block: this makes the AI write path visible to the shield, it does not yet let the shield '
  'refuse it -- measured first, enforced after a flagship round, per CLAUDE.md 2.9a; promotion must read '
  'ottoq_shield_probe.would_block. log_only rather than shadow because ottoq_evaluate_rule_core emits a '
  'signed event for every shadow evaluation and only for failures under log_only: same ledger row, far '
  'fewer events. A1 is the non-vacuity gate and is falsifiable both ways -- 0.93 on '
  'energy_demand_factor_peak is legal to ottoq_policy_set (catalog max 0.95) and must FAIL the agent '
  'ceiling of 0.9, while the same value from a non-agent actor must PASS, because the rule judges AI '
  'actors and must not become a second engine-wide clamp. A2 proves end to end that the ledger gains a '
  'row AND the write still succeeds, since a probe that changes the outcome is not a probe. A6 pins the '
  'certification trap this file nearly walked into, the fourth instance of 0139''s class: entity_id is '
  'hashed and for scope_type=run it would have been the sim_run_id, which differs between arms, so the run '
  'rides in the context column, which the hash does not digest -- both halves asserted so a future hash '
  'change cannot silently re-arm it. forces_recert TRUE, measured rather than cautious: a run after this '
  'migration carries evaluations at a probe point no earlier run had, so h_rule moves and every canon '
  'predating it is correctly invalidated.',
  now())
ON CONFLICT(name) DO NOTHING;

COMMIT;
