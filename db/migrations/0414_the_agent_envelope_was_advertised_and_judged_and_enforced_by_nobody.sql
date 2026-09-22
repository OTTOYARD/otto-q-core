-- migration-version: 20260922050100
-- migration-name:    the_agent_envelope_was_advertised_and_judged_and_enforced_by_nobody
--
-- 0414  **The agent dial envelope had three of the four parts it needs. It is ADVERTISED to the agent
--       (`ottoq_agent_dial_envelope`), JUDGED by `AI.001.agent_dial_within_envelope`, AUDITED into
--       `ottoq_rule_evaluations` — and ENFORCED by nothing. `ottoq_policy_set` clamps to the ENGINE
--       bounds, so an agent asking for a value outside its own envelope but inside the engine's gets
--       exactly what it asked for, while AI.001 records a `critical` failure that blocks nothing.**
--
--       This migration adds the fourth part, and fixes an actor-matching defect that would have let
--       the dial promoter past AI.001 entirely.
--
--       `forces_recert` **FALSE**, and §4 is the assertion that earns it rather than the claim.
--
-- ══ §1 THE GAP, MEASURED ══════════════════════════════════════════════════════
--
-- `ottoq_policy_set` computes `v_final := GREATEST(v_min, LEAST(v_max, p_param_value))` — `min_value`
-- and `max_value`, the ENGINE bounds. The agent columns (`agent_min_value`, `agent_max_value`) are
-- never read on the write path. Measured on the six dials the agent actually writes:
--
--     dial                             agent envelope   engine bounds   UNENFORCED ROOM
--     ------------------------------   --------------   -------------   ------------------
--     deploy_peak_fraction             [0.5,  1.0 ]     [0.30, 1.00]    0.30..0.50
--     energy_demand_factor_expensive   [0.2,  0.8 ]     [0.20, 0.90]    0.80..0.90
--     energy_demand_factor_peak        [0.3,  0.9 ]     [0.25, 0.95]    0.25..0.30, 0.90..0.95
--     deploy_surge_catchup             [0.1,  1.0 ]     [0.10, 1.00]    none
--     energy_reserve_shave             [0.0,  1.0 ]     [0,    1   ]    none
--     forecast_horizon_min             [10.0, 90.0]     [10,   90  ]    none
--
-- **Three of the six have room outside the agent envelope that nothing prevents the agent using.**
-- The other three are enforced only by coincidence — their agent envelope equals the engine's, so the
-- engine clamp happens to do the agent clamp's job. A control that works because two numbers happen
-- to match is not a control.
--
-- **AND THE PROBE CANNOT CLOSE IT, WHICH IS WHY THIS IS NOT A ONE-LINE ENFORCEMENT FLIP.**
-- `ottoq_policy_set` wraps its shield probe in `EXCEPTION WHEN OTHERS THEN NULL` and says why in its
-- own comment — *"a reporting probe must never be able to refuse a write ottoq_policy_set would
-- otherwise have accepted. The rule is registered log_only so it cannot block; this is the second
-- belt."* That is deliberate and correct, and it means **promoting AI.001 from `log_only` to `block`
-- would still enforce nothing**: the swallow would eat the refusal. Enforcement has to live in the
-- write path, which is what this migration does. AI.001 stays `log_only` and stays the auditor.
--
-- ══ §2 THE ACTOR-MATCHING DEFECT, AND A COMMENT THAT ASSERTS ITS OPPOSITE ══════
--
-- `ottoq_rule_eval_agent_dial_envelope` tests `v_by = ANY(v_actors)` against
-- `agent_actors = ['ottoq_prime']` — **exact equality.** `ottoq_promote_dials` writes through the
-- setter as **`'ottoq_prime:promoter'`**, and its own comment claims:
--
--     -- The actor is deliberately inside the agent family so AI.001 JUDGES this write rather
--     -- than passing it unjudged.
--
-- **`'ottoq_prime:promoter'` is not equal to `'ottoq_prime'`, so AI.001 returns "actor is not an
-- agent" and passes it UNJUDGED — the exact outcome the comment says was designed against.** The
-- promoter is the one writer whose whole job is to move dials on evidence, and it was the writer the
-- envelope rule could not see.
--
-- **This has never fired in anger, and that is not reassurance.** `ottoq_dial_promotion_ledger` holds
-- **zero rows** — `ottoq_promote_dials` has never enacted or even dry-run a promotion that landed.
-- So the defect is latent, the promoter is an unexercised path, and the first time it runs would have
-- been the first time an unjudged agent write reached the dials.
--
-- Fixed by making the family test prefix-aware in ONE place both consumers call:
-- `'ottoq_prime'` matches `'ottoq_prime'` and `'ottoq_prime:anything'`, and nothing else.
--
-- ══ §3 WHAT IS DELIBERATELY NOT DONE: THE DRIFT CAP ═══════════════════════════
--
-- `agent_max_drift_pct` is **0.30 on five of the six dials** and is read by exactly two functions,
-- neither of which is a rule: `ottoq_agent_dial_envelope` (which only advertises it) and
-- `ottoq_promote_dials`, which implements it as
--
--     v_drift := abs(v_incumbent) * (r.agent_max_drift_pct / 100.0);
--
-- **That divisor makes 0.30 mean 0.3%, not 30%.** On `deploy_peak_fraction` at an incumbent of 0.9
-- it caps a promotion at ±0.0027 — a dial that can essentially never move. Either the column is a
-- percent and five dials are frozen by design, or it is a fraction and the promoter is off by 100x.
--
-- **I am not resolving that here, and the reason is the rule this repo keeps relearning: bounds are
-- COPIED from the consumer, never invented.** There is only one consumer, its interpretation is
-- ambiguous on its face, and the ledger is empty so no observed promotion can arbitrate it. Copying
-- an ambiguous semantic into a second enforcement point is precisely what `ottoq_promote_dials`'s own
-- comment warns about (*"0310 §5 is what a second copy costs"*). So this migration enforces the
-- unambiguous half — the min/max envelope — and leaves drift to the promoter until the unit is
-- decided. **Flagged for Chase as an open question, not silently picked.**
--
-- ══ §4 WHY `forces_recert` IS FALSE, ASSERTED RATHER THAN ASSUMED ═════════════
--
-- A clamp that never binds changes nothing. Two facts make that checkable, and V3/V4 assert both:
--
--   (a) **All 555 AI.001 evaluations to date passed.** Every agent dial write in the system's history
--       was already inside its envelope, so the new clamp would have altered none of them.
--   (b) **No stored policy row for an agent-writable dial sits outside its agent envelope** — so no
--       current value changes either, and no run reading a dial today reads a different number
--       tomorrow.
--
-- The clamp is therefore a no-op on all observed and all stored state, and only constrains writes
-- that have never yet been attempted. Nothing a canon column digested moves. **If either assertion
-- fails the migration aborts**, because then the premise for FALSE is gone and the classification
-- would be a lie the recert floor believes (`ottoq_cert_recert_floor` reads
-- `COALESCE(forces_recert, true)`, so a wrong FALSE is the one direction that silently keeps a canon
-- alive it should have killed).

-- ══ §5 HOW THIS WAS ACTUALLY APPLIED, AND THE ONE ROW IT LEAVES BEHIND ════════
--
-- **`apply_migration` timed out at 60 s TWICE, each time with a verified clean rollback** (no
-- function created, no lineage row, no `schema_migrations` entry). Re-run statement-wise through
-- `execute_sql` the whole thing completed in under a second. **I first wrote that the timeout was
-- "the transport and not the work". That was a guess and it is now contradicted by direct
-- evidence:** minutes later a `SET statement_timeout = 0; DO $runner$ ... pg_try_advisory_xact_lock`
-- transaction — the recert harness — was observed running for 275 s while a
-- `SELECT ottoq_start_demo_run(...)` sat behind it in `wait_event_type='Lock'`,
-- `wait_event='transactionid'`, for 113 s. **A `CREATE OR REPLACE FUNCTION` on `ottoq_policy_set`
-- needs a lock that same harness transaction can hold, so LOCK CONTENTION WITH THE RECERT HARNESS is
-- the likely cause of all three of this branch's `apply_migration` timeouts, and the statement-wise
-- retry succeeded because it happened to land in a gap.** Not proven for those specific attempts —
-- I did not look at `pg_stat_activity` at the time, which is the lesson — but it is a mechanism with
-- observed evidence, where "transport" had none. Every preflight, every patch assertion and every
-- verify below was executed and
-- passed; the `schema_migrations` row was then written by hand as version `20260922050100` with a
-- statement recording that provenance. **The lesson is the one this repo already has for MCP
-- timeouts: a timeout is not a rollback, so go and look — here it happened to be a rollback both
-- times, and assuming either way without checking is how a half-applied migration gets built on.**
--
-- **PROVEN END TO END AT THE REAL CALL SITE**, which is the standard 0413 set for itself:
--
--     ottoq_policy_set(depot, …, 'deploy_peak_fraction', 0.35, 'ottoq_prime')
--       -> {"ok":true, "requested":0.35, "applied":0.5, "clamped":true}    <- would have been 0.35
--     ottoq_policy_set(depot, …, 'energy_demand_factor_expensive', 0.88, 'scenario_loader')
--       -> {"ok":true, "requested":0.88, "applied":0.88, "clamped":false}  <- non-agent untouched
--
-- and AI.001 logged the first as `passed=false` while the clamp applied 0.5 — **both belts, judged
-- AND enforced**, which is the "assignment plus verification" rule of CLAUDE.md 6 in miniature.
--
-- **The residue, stated because it changes a future assertion.** `ottoq_rule_evaluations` is
-- append-only (`ottoq_block_mutation` rejects DELETE, correctly, and I did not work around it), so
-- that deliberate out-of-envelope probe leaves **one permanent `passed=false` AI.001 row**, scoped to
-- the throwaway depot `dddddddd-…` whose policy rows were removed. So P3/V3 above, which assert
-- ZERO failed AI.001 evaluations, were true when this migration ran and are **false from now on by
-- exactly one row**. A later migration reusing that assertion must exclude
-- `context->>'scope_id' = 'dddddddd-dddd-dddd-dddd-dddddddddddd'` rather than conclude an agent has
-- misbehaved.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n   int;
  v_enf text;
BEGIN
  -- P1. The clamp line is present exactly once, and there is exactly one overload to patch.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_policy_set';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0414 P1: expected exactly 1 ottoq_policy_set overload, found %', v_n;
  END IF;

  -- P2. AI.001 is present and log_only. This migration does NOT change that -- enforcement moves to
  --     the write path precisely because the probe is error-swallowed.
  SELECT enforcement INTO v_enf FROM public.ottoq_rules
   WHERE rule_code='AI.001.agent_dial_within_envelope' AND status='active';
  IF v_enf IS DISTINCT FROM 'log_only' THEN
    RAISE EXCEPTION '0414 P2: AI.001 enforcement is %, expected log_only. If it now blocks, re-read '
                    'ottoq_policy_set''s exception-swallow comment before proceeding', v_enf;
  END IF;

  -- P3. THE PREMISE FOR forces_recert=FALSE. Every agent dial write so far was in-envelope.
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations
   WHERE rule_code='AI.001.agent_dial_within_envelope' AND passed = false;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0414 P3: % AI.001 evaluations FAILED. An agent has already written outside its '
                    'envelope, so this clamp would change stored behaviour and forces_recert must be '
                    'TRUE -- reclassify before applying', v_n;
  END IF;

  RAISE NOTICE '0414 preflight: one setter, AI.001 log_only, zero out-of-envelope agent writes';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) THE AGENT FAMILY TEST, IN ONE PLACE. Prefix-aware: 'ottoq_prime' admits
--     'ottoq_prime' and 'ottoq_prime:promoter', and nothing else. A bare LIKE
--     would also admit 'ottoq_primext', which is why the boundary is ':'.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_is_agent_actor(p_by text, p_actors text[] DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT EXISTS (
    SELECT 1
      FROM unnest(COALESCE(p_actors, ARRAY['ottoq_prime'])) AS a(actor)
     WHERE COALESCE(p_by,'') = a.actor
        OR COALESCE(p_by,'') LIKE a.actor || ':%'
  );
$fn$;

COMMENT ON FUNCTION public.ottoq_is_agent_actor(text, text[]) IS
  '0414: is this actor a member of an agent family? Prefix-aware on a '':'' boundary, because '
  'ottoq_promote_dials writes as ''ottoq_prime:promoter'' and AI.001''s exact-equality test passed '
  'it UNJUDGED -- the opposite of what that function''s own comment claimed. Used by both '
  'ottoq_rule_eval_agent_dial_envelope (to judge) and ottoq_dial_clamp (to enforce), so the two '
  'can never disagree about who an agent is.';

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) THE CLAMP. Engine bounds always; the agent envelope additionally when the
--     writer is an agent. Deliberately does NOT implement the drift cap -- §3.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_dial_clamp(p_param_key text, p_requested numeric, p_by text)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_min numeric; v_max numeric;
  v_alo numeric; v_ahi numeric; v_writable boolean;
  v_out numeric;
BEGIN
  SELECT c.min_value, c.max_value, c.agent_min_value, c.agent_max_value, c.agent_writable
    INTO v_min, v_max, v_alo, v_ahi, v_writable
    FROM public.ottoq_policy_param_catalog c WHERE c.param_key = p_param_key;

  -- The engine clamp, byte-for-byte the expression this replaces. GREATEST/LEAST IGNORE NULLS, and
  -- that is load-bearing: an unbounded catalog row must mean "admit, clamp nothing" (0306).
  v_out := GREATEST(v_min, LEAST(v_max, p_requested));

  -- The agent clamp. Applied ONLY for an agent actor, so every other writer -- scenario_loader,
  -- 0152_cert_quiesce, the operator demo -- is byte-identical to before this migration.
  IF public.ottoq_is_agent_actor(p_by) THEN
    v_out := GREATEST(v_alo, LEAST(v_ahi, v_out));
  END IF;

  RETURN v_out;
END
$fn$;

COMMENT ON FUNCTION public.ottoq_dial_clamp(text, numeric, text) IS
  '0414: clamps a dial write to the engine bounds, and additionally to the agent envelope when the '
  'writer is an agent actor. Before this existed the agent envelope was advertised by '
  'ottoq_agent_dial_envelope and judged by AI.001 and enforced by nobody: ottoq_policy_set clamped '
  'to min_value/max_value only, so three of the six agent-writable dials had live room outside the '
  'agent envelope. Does NOT implement agent_max_drift_pct -- that column''s unit is ambiguous '
  '(ottoq_promote_dials divides it by 100, making 0.30 mean 0.3%) and copying an ambiguous bound '
  'into a second enforcement point is the defect this repo calls 0310 §5. See db/migrations/0414 §3.';

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) THE SURGICAL SUBSTITUTION. One line of ottoq_policy_set, match count and
--     total byte delta both asserted -- the 0413 technique.
-- ─────────────────────────────────────────────────────────────────────────────
DO $patch$
DECLARE
  v_def    text;
  v_old    text := '  v_final := GREATEST(v_min, LEAST(v_max, p_param_value));';
  v_new    text := '  v_final := public.ottoq_dial_clamp(p_param_key, p_param_value, p_by);  -- 0414: engine bounds, plus the agent envelope when p_by is an agent';
  v_hits   int;
  v_newdef text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_policy_set';

  v_hits := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0414 patch: the clamp line matched % times, expected exactly 1', v_hits;
  END IF;

  v_newdef := replace(v_def, v_old, v_new);
  IF length(v_newdef) - length(v_def) <> length(v_new) - length(v_old) THEN
    RAISE EXCEPTION '0414 patch: rewritten definition differs by % bytes, expected % -- the '
                    'replacement touched more than the clamp line',
                    length(v_newdef) - length(v_def), length(v_new) - length(v_old);
  END IF;

  EXECUTE v_newdef;
  RAISE NOTICE '0414 patch: ottoq_policy_set clamp line substituted, one match, no other byte changed';
END $patch$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (4) AI.001's EVALUATOR LEARNS THE SAME FAMILY TEST, so the judge and the
--     enforcer can never disagree about who counts as an agent.
--     Only the actor test changes; every verdict branch is untouched.
-- ─────────────────────────────────────────────────────────────────────────────
DO $rule$
DECLARE
  v_def    text;
  v_old    text := '  IF NOT (v_by = ANY(v_actors)) THEN';
  v_new    text := '  IF NOT public.ottoq_is_agent_actor(v_by, v_actors) THEN  -- 0414: prefix-aware, so ottoq_prime:promoter is judged';
  v_hits   int;
  v_newdef text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_rule_eval_agent_dial_envelope';

  v_hits := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0414 rule patch: the actor test matched % times, expected exactly 1', v_hits;
  END IF;

  v_newdef := replace(v_def, v_old, v_new);
  IF length(v_newdef) - length(v_def) <> length(v_new) - length(v_old) THEN
    RAISE EXCEPTION '0414 rule patch: rewritten definition differs by % bytes, expected %',
                    length(v_newdef) - length(v_def), length(v_new) - length(v_old);
  END IF;

  EXECUTE v_newdef;
  RAISE NOTICE '0414 rule patch: AI.001 evaluator now uses the prefix-aware family test';
END $rule$;

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE. FALSE, on the premise V3/V4 assert.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0414_the_agent_envelope_was_advertised_and_judged_and_enforced_by_nobody', false,
  'Makes the agent dial envelope enforcing in ottoq_policy_set, and makes AI.001''s agent-family '
  'test prefix-aware so ottoq_prime:promoter is judged rather than passed over. FALSE because the '
  'clamp provably never binds on any observed or stored state: all 555 AI.001 evaluations passed, so '
  'every agent write in history was already in-envelope, and no stored policy row for an '
  'agent-writable dial sits outside its agent envelope. Both are asserted in-transaction and abort '
  'the migration if false. Non-agent writers are byte-identical: the agent clamp is inside an '
  'ottoq_is_agent_actor branch. No decision, event, booking or dial value changes, so no canon '
  'column digested anything different.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_n     int;
  v_bad   text;
  v_got   numeric;
BEGIN
  -- V1. THE FAMILY TEST IS RIGHT AT ITS BOUNDARIES, including the one a bare LIKE would get wrong.
  IF NOT public.ottoq_is_agent_actor('ottoq_prime') THEN
    RAISE EXCEPTION '0414 V1: the bare agent actor is not recognised';
  END IF;
  IF NOT public.ottoq_is_agent_actor('ottoq_prime:promoter') THEN
    RAISE EXCEPTION '0414 V1: ottoq_prime:promoter is still not recognised -- §2 is not fixed';
  END IF;
  IF public.ottoq_is_agent_actor('ottoq_primext') THEN
    RAISE EXCEPTION '0414 V1: ottoq_primext was admitted; the '':'' boundary is not holding';
  END IF;
  IF public.ottoq_is_agent_actor('scenario_loader')
     OR public.ottoq_is_agent_actor('0152_cert_quiesce')
     OR public.ottoq_is_agent_actor(NULL) THEN
    RAISE EXCEPTION '0414 V1: a non-agent writer was classified as an agent';
  END IF;

  -- V2. THE CLAMP BINDS FOR AN AGENT AND IS INERT FOR EVERYONE ELSE. deploy_peak_fraction is the
  --     clearest case: engine floor 0.30, agent floor 0.5, so 0.35 is the value that used to get
  --     through. This is the whole migration in four assertions.
  v_got := public.ottoq_dial_clamp('deploy_peak_fraction', 0.35, 'ottoq_prime');
  IF v_got <> 0.5 THEN
    RAISE EXCEPTION '0414 V2: agent request 0.35 clamped to % , expected the agent floor 0.5', v_got;
  END IF;
  v_got := public.ottoq_dial_clamp('deploy_peak_fraction', 0.35, 'scenario_loader');
  IF v_got <> 0.35 THEN
    RAISE EXCEPTION '0414 V2: a NON-agent write of 0.35 was altered to % -- this migration must not '
                    'touch non-agent writers', v_got;
  END IF;
  v_got := public.ottoq_dial_clamp('energy_demand_factor_expensive', 0.88, 'ottoq_prime:promoter');
  IF v_got <> 0.8 THEN
    RAISE EXCEPTION '0414 V2: promoter request 0.88 clamped to %, expected the agent ceiling 0.8', v_got;
  END IF;
  v_got := public.ottoq_dial_clamp('deploy_peak_fraction', 0.85, 'ottoq_prime');
  IF v_got <> 0.85 THEN
    RAISE EXCEPTION '0414 V2: an IN-envelope agent request of 0.85 was altered to % -- the clamp must '
                    'only bind outside the envelope', v_got;
  END IF;

  -- V3. THE forces_recert=FALSE PREMISE, PART (a): no agent write has ever failed AI.001.
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations
   WHERE rule_code='AI.001.agent_dial_within_envelope' AND passed = false;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0414 V3: % failed AI.001 evaluations exist; forces_recert=FALSE is not earned', v_n;
  END IF;

  -- V4. PART (b): no STORED value for an agent-writable dial is outside its agent envelope, so the
  --     clamp changes nothing any run will read. This is the assertion that makes FALSE honest.
  SELECT count(*), string_agg(DISTINCT p.param_key || '=' || p.param_value, ', ')
    INTO v_n, v_bad
    FROM public.ottoq_policy_params p
    JOIN public.ottoq_policy_param_catalog c ON c.param_key = p.param_key
   WHERE c.agent_writable
     AND (   (c.agent_min_value IS NOT NULL AND p.param_value < c.agent_min_value)
          OR (c.agent_max_value IS NOT NULL AND p.param_value > c.agent_max_value));
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0414 V4: % stored agent-writable dial value(s) sit outside the agent envelope '
                    '(%). The clamp would change what a run reads, so forces_recert must be TRUE',
                    v_n, v_bad;
  END IF;

  -- V5. The setter routes through the clamp, and AI.001 is still the auditor rather than a blocker.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_policy_set'
     AND p.prosrc LIKE '%ottoq_dial_clamp%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0414 V5: ottoq_policy_set does not call ottoq_dial_clamp';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_rules
   WHERE rule_code='AI.001.agent_dial_within_envelope' AND status='active' AND enforcement='log_only';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0414 V5: AI.001 is no longer active/log_only; enforcement belongs in the write '
                    'path because the probe is error-swallowed';
  END IF;

  RAISE NOTICE '0414 verify: family test exact at its boundaries, clamp binds for agents and is '
               'inert for everyone else, zero out-of-envelope evaluations and zero out-of-envelope '
               'stored values, AI.001 still the auditor';
END $post$;

COMMIT;
