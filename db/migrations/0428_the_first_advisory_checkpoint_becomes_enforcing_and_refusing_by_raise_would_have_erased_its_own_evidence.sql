-- migration-version: PENDING
-- migration-name:    the_first_advisory_checkpoint_becomes_enforcing_and_refusing_by_raise_would_have_erased_its_own_evidence
--
-- 0428  **`charge_session_start` is the first of the six advisory checkpoints to become ENFORCING.** Four
--       blocking energy rules — `EN.001.grid_capacity_ceiling` and `EN.005.grid_event_hardstop`, both
--       `safety_critical`, plus `EN.002.stall_power_ceiling` and `EN.004.demand_response_compliance` — have
--       been consulted **8,587 times each with zero failures**, and `twin.ottoq_sim_start_charge_session`
--       discarded every verdict with `PERFORM`. Diagnosed in `db/checks/0345` §3 (G156, G149).
--
--       **The occasion is Chase's, in his words:** *"most of the rules don't actually stop anything. They
--       write a note saying 'I object' and the system proceeds anyway. Six of the ten checkpoints work that
--       way. Adding more rules adds more unread notes."* This is the first note that gets read.
--
--       `forces_recert` **TRUE**: `events` and `rules` are both atoms, and this adds an event type and can
--       change what the engine does.
--
-- ══ §1 WHY THIS CHECKPOINT, AND WHY IT COULD NOT BE DONE UNTIL TODAY ═════════
--
-- `0337` G150 said, correctly, *"the discard is load-bearing, so do NOT fix it by turning enforcement on."*
-- At that time `HW.002.charger_state_precondition` — `critical`/`block`, also at this checkpoint —
-- **could not pass**: it read the charger heartbeat one tick before the tick wrote it, failing 4,632 of
-- 4,632 with a gap of exactly 1800 s and **zero variance**. Enforcing then would have stopped the twin
-- charging outright.
--
-- `0424` (applied `20260922150552`) fixed the input. Measured since: **3,702 evaluations, 0 failures**, all
-- through the evaluator's terminal success branch across 40 chargers (`0342`). So the one rule that made the
-- discard load-bearing no longer objects, and the four energy rules never did.
--
-- **Both callers already tolerate a refusal — measured from source, not assumed:**
--
--     twin.ottoq_sim_auto_charge_assign_tick    v_session_id := ottoq_sim_start_charge_session(...)
--                                               EXCEPTION WHEN OTHERS THEN CONTINUE;
--     twin.ottoq_sim_reconcile_charge_sessions  PERFORM ottoq_sim_start_charge_session(...) in a LOOP
--     public.ottoq_tick_invariance_reset_fleet  mentions the name in a COMMENT only
--
-- ══ §2 THE TRAP THAT CHANGED THE DESIGN: A RAISE ERASES ITS OWN EVIDENCE ═════
--
-- **The obvious implementation — `RAISE EXCEPTION` on a block — is wrong, and wrong in a way that would have
-- been almost impossible to notice afterwards.** The first caller catches with `EXCEPTION WHEN OTHERS THEN
-- CONTINUE`, and a PL/pgSQL exception block is a **subtransaction**. So raising would roll back:
--
--   * the refusal event this migration emits, and
--   * **every `ottoq_rule_evaluations` row the probe just wrote** — the shield's own record of *why* it
--     refused.
--
-- The engine would refuse charges and leave **no trace of any refusal anywhere**, which is strictly worse
-- than the discard it replaces: today the verdict is written and unread; there it would be neither.
--
-- **So the refusal RETURNS NULL instead of raising.** Nothing rolls back, the evaluation rows persist, the
-- event persists, and the caller skips. This is the same family as `0332` (*a duration is not a wait*) and
-- `0337` (*a value is not an outcome*), one level further in: **a refusal is not a record of a refusal.**
--
-- The cost is one extra line in the caller: `ottoq_sim_auto_charge_assign_tick` uses the returned id only in
-- a subsequent `twin.auto_charge_assign` payload, so without a NULL guard it would count a session that
-- never started and emit `session_id: null`. Change (B) adds the guard. `reconcile_charge_sessions`
-- `PERFORM`s the result, so NULL is already harmless there and it is left untouched.
--
-- ══ §3 THE OFF-SWITCH IS A CATALOGUED DIAL, NOT A MIGRATION ══════════════════
--
-- `shield_enforce_charge_session_start`, default **1**, read through `ottoq_policy_get`. Turning enforcement
-- off is one `ottoq_policy_set` call, takes effect on the next tick, and needs no schema change. The dial is
-- registered in `ottoq_policy_param_catalog` so `ottoq_policy_catalog_gap` does not report it as an unknown
-- reader, and it is **not** `agent_writable` — the agent may not switch the safety shield off.
--
-- **Default 1 rather than 0 is a deliberate choice and P4 is what earns it:** the migration refuses to apply
-- unless the ledger shows **zero** `would_block` rows at this checkpoint since `0424`. If anything would be
-- refused right now, this file aborts and the answer is to go measure, not to enforce.
--
-- The failure mode if that is still wrong: a charge does not start, the caller skips the vehicle, and the
-- next tick retries 30 seconds later. Every refusal is a registered event, so a wrong refusal is visible
-- within one tick and the dial is the instant remedy. **What is NOT done is promoting the other five
-- checkpoints** — `0345` §3 is explicit that they go one at a time, each behind its own evidence.
--
-- ══ §4 WHAT IS DELIBERATELY NOT DONE ═════════════════════════════════════════
--
--   1. **`task_completion` stays advisory**, and on today's evidence it must: `db/checks/0346` measured
--      HW.006 failing **7.7% of untethered L2 charge completions** (G157, cause not yet attributed).
--      Enforcing there would refuse real work. G150's lesson applied before the damage.
--   2. **No rule is edited.** Not a threshold, not a severity, not an enforcement column. This changes only
--      whether a caller reads an answer.
--   3. **The three state-change triggers and `policy_write` stay advisory** — their rules are `shadow` or
--      `log_only`, so honouring them would change nothing (`0345` §2). Promoting them means promoting the
--      RULE first, which is a separate decision with separate evidence.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ═══════════════════════════════════════

\set ON_ERROR_STOP on
BEGIN;

-- ── P1: the checkpoint is still advisory, i.e. the PERFORM is still there ──
DO $$
DECLARE v_def text; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session';
  IF v_def IS NULL THEN RAISE EXCEPTION '0428 P1: twin.ottoq_sim_start_charge_session not found'; END IF;
  v_hits := (length(v_def) - length(replace(v_def, 'PERFORM 1 FROM public.ottoq_shield_probe', '')))
            / length('PERFORM 1 FROM public.ottoq_shield_probe');
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0428 P1: expected exactly 1 discarding PERFORM of the shield probe, found % -- '
                    'somebody changed this checkpoint. STOP and re-read db/checks/0345.', v_hits;
  END IF;
END $$;

-- ── P2: the probe still exposes would_block, which is the whole mechanism ──
DO $$
BEGIN
  IF pg_get_function_result('public.ottoq_shield_probe(text,text,uuid,jsonb,uuid,uuid,uuid,uuid)'::regprocedure)
       NOT LIKE '%would_block boolean%' THEN
    RAISE EXCEPTION '0428 P2: ottoq_shield_probe no longer returns would_block -- re-read 0337 §3';
  END IF;
END $$;

-- ── P3: nothing in flight (G141 -- a pair is invisible to ottoq_sim_runs) ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN RAISE EXCEPTION '0428 P3: % run(s) running/paused -- apply between runs', v_n; END IF;
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid() AND query LIKE '%ottoq\_recert\_runner%';
  IF v_n <> 0 THEN RAISE EXCEPTION '0428 P3b: a determinism pair is in flight (G141)'; END IF;
END $$;

-- ── P4: THE PRECONDITION THAT EARNS A DEFAULT-ON DIAL.
-- Zero would-block rows at this checkpoint since 0424 fixed HW.002's input. If anything would be refused
-- right now, enforcing is not the next step -- measuring is.
DO $$
DECLARE v_blocks int; v_evals int; v_en int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE enforcement_taken='blocked')
    INTO v_evals, v_blocks
    FROM public.ottoq_rule_evaluations
   WHERE action_context='charge_session_start' AND evaluated_at >= '2026-09-22 15:05:52+00';
  IF v_evals < 500 THEN
    RAISE EXCEPTION '0428 P4: only % evaluations at charge_session_start since 0424 -- too thin to promote '
                    'on. Let a run accumulate.', v_evals;
  END IF;
  IF v_blocks <> 0 THEN
    RAISE EXCEPTION '0428 P4: % of % evaluations at charge_session_start WOULD BLOCK since 0424. Enforcing '
                    'now would refuse real charges. Measure first -- this is exactly G150.', v_blocks, v_evals;
  END IF;

  SELECT count(*) INTO v_en FROM public.ottoq_rules
   WHERE status='active' AND enforcement='block' AND 'charge_session_start' = ANY(applies_to_actions);
  IF v_en < 4 THEN
    RAISE EXCEPTION '0428 P4b: only % blocking rules declare charge_session_start -- this migration exists '
                    'to make those rules effective; if they are gone there is nothing to promote.', v_en;
  END IF;
  RAISE NOTICE '0428 P4: % evaluations since 0424, 0 would-block, % blocking rules at this checkpoint',
               v_evals, v_en;
END $$;

-- ── SNAPSHOT BEFORE REPLACING (APPLYING.md step 2) ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0428_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname='twin' AND p.proname IN ('ottoq_sim_start_charge_session',
                                           'ottoq_sim_auto_charge_assign_tick'));

-- ── (C) THE VOCABULARY AND THE DIAL, BEFORE THE CODE THAT USES THEM ──
-- Order matters: ottoq_record_event falls back to category 'system_event'/'warning' for an unregistered
-- type, so registering after the emitter would silently mis-category the first refusals.
INSERT INTO public.ottoq_event_types_catalog
       (event_type, category, default_severity, emitter, introduced_in, description)
VALUES ('ottoq.charge_start_refused', 'safety_event', 'critical',
        'twin.ottoq_sim_start_charge_session', '0428_shield_enforce_charge_session_start',
        'The L1 shield refused a charge session start at charge_session_start. Payload names every rule '
        'code whose would_block was true. Emitted BEFORE the refusal returns, and the refusal RETURNS '
        'NULL rather than raising, precisely so this row and the ottoq_rule_evaluations rows behind it '
        'survive -- a RAISE would roll back into the caller''s EXCEPTION subtransaction and erase the '
        'evidence of its own refusal (0428 section 2).')
ON CONFLICT (event_type) DO UPDATE
  SET category = EXCLUDED.category, default_severity = EXCLUDED.default_severity,
      emitter = EXCLUDED.emitter, introduced_in = EXCLUDED.introduced_in,
      description = EXCLUDED.description;

INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('shield_enforce_charge_session_start',
        'When >= 1, twin.ottoq_sim_start_charge_session REFUSES (returns NULL) if any L1 rule at '
        'charge_session_start reports would_block. When 0 the refusal is recorded as '
        'ottoq.charge_start_refused and the charge proceeds -- i.e. 0 restores the pre-0428 advisory '
        'behaviour but keeps the instrumentation. This is the off-switch for the first enforcing '
        'checkpoint; flipping it needs no migration and takes effect on the next tick.',
        1, 0, 1, 'safety', false)
ON CONFLICT (param_key) DO UPDATE
  SET description = EXCLUDED.description, default_value = EXCLUDED.default_value,
      min_value = EXCLUDED.min_value, max_value = EXCLUDED.max_value,
      affects = EXCLUDED.affects, agent_writable = EXCLUDED.agent_writable;

-- ── (A) THE CHECKPOINT READS ITS OWN VERDICT ──
DO $$
DECLARE v_def text; v_new text; v_anchor text; v_insert text; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session';

  v_anchor := E'  BEGIN\n'
           || E'    PERFORM set_config(''ottoq.sim_run_id'', p_sim_run_id::text, true);\n'
           || E'    PERFORM 1 FROM public.ottoq_shield_probe(\n'
           || E'      p_action_context    := ''charge_session_start'',\n'
           || E'      p_entity_type       := ''stall'',\n'
           || E'      p_entity_id         := p_stall_id,\n'
           || E'      p_context           := jsonb_build_object(\n'
           || E'                               ''depot_id'',     v_stall.depot_id::text,\n'
           || E'                               ''stall_id'',      p_stall_id::text,\n'
           || E'                               ''charger_id'',    v_charger.charger_id::text,\n'
           || E'                               ''requested_kw'',  LEAST(v_charger.max_kw, v_vehicle.inlet_max_kw),\n'
           || E'                               ''now_ts'',        v_clock::text),\n'
           || E'      p_fleet_operator_id := v_vehicle.fleet_operator_id,\n'
           || E'      p_depot_id          := v_stall.depot_id);\n'
           || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''charge_session_start shield probe: %'', SQLERRM;\n'
           || E'  END;';

  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0428 (A): anchor matched % times, expected 1 -- the function was reformatted; re-read '
                    'pg_get_functiondef and re-derive', v_hits;
  END IF;

  -- 0428 (G156/G149): this checkpoint now READS the verdict it has always written. Its own DECLARE block
  -- so no second substitution is needed in the function header.
  --   * the inner BEGIN/EXCEPTION still swallows a probe FAILURE (a probe must never abort a tick) and
  --     resets the count, so a broken probe cannot refuse anything;
  --   * the decision sits OUTSIDE that handler, so a refusal is a decision rather than an error;
  --   * the refusal RETURNS NULL and does NOT raise -- a raise would roll back into the caller's
  --     EXCEPTION subtransaction and erase both this event and the shield's evaluation rows (section 2);
  --   * the dial is read per call, so the off-switch takes effect on the next tick.
  v_insert := E'  DECLARE\n'
           || E'    v_shield_blocks INT := 0;\n'
           || E'    v_shield_codes  TEXT[];\n'
           || E'  BEGIN\n'
           || E'    BEGIN\n'
           || E'      PERFORM set_config(''ottoq.sim_run_id'', p_sim_run_id::text, true);\n'
           || E'      SELECT count(*) FILTER (WHERE sp.would_block),\n'
           || E'             array_agg(sp.rule_code) FILTER (WHERE sp.would_block)\n'
           || E'        INTO v_shield_blocks, v_shield_codes\n'
           || E'        FROM public.ottoq_shield_probe(\n'
           || E'          p_action_context    := ''charge_session_start'',\n'
           || E'          p_entity_type       := ''stall'',\n'
           || E'          p_entity_id         := p_stall_id,\n'
           || E'          p_context           := jsonb_build_object(\n'
           || E'                                   ''depot_id'',     v_stall.depot_id::text,\n'
           || E'                                   ''stall_id'',      p_stall_id::text,\n'
           || E'                                   ''charger_id'',    v_charger.charger_id::text,\n'
           || E'                                   ''requested_kw'',  LEAST(v_charger.max_kw, v_vehicle.inlet_max_kw),\n'
           || E'                                   ''now_ts'',        v_clock::text),\n'
           || E'          p_fleet_operator_id := v_vehicle.fleet_operator_id,\n'
           || E'          p_depot_id          := v_stall.depot_id) sp;\n'
           || E'    EXCEPTION WHEN OTHERS THEN\n'
           || E'      RAISE WARNING ''charge_session_start shield probe: %'', SQLERRM;\n'
           || E'      v_shield_blocks := 0;\n'
           || E'    END;\n'
           || E'    IF COALESCE(v_shield_blocks, 0) > 0 THEN\n'
           || E'      PERFORM ottoq_record_event(\n'
           || E'        p_actor_type := ''ottoq_engine'', p_actor_id := ''twin_charge_orchestrator'',\n'
           || E'        p_event_type := ''ottoq.charge_start_refused'',\n'
           || E'        p_entity_type := ''stall'', p_entity_id := p_stall_id,\n'
           || E'        p_fleet_operator_id := v_vehicle.fleet_operator_id, p_depot_id := v_stall.depot_id,\n'
           || E'        p_payload := jsonb_build_object(\n'
           || E'          ''vehicle_id'', p_vehicle_id, ''charger_id'', v_charger.charger_id,\n'
           || E'          ''blocking_rules'', to_jsonb(v_shield_codes), ''block_count'', v_shield_blocks,\n'
           || E'          ''requested_kw'', LEAST(v_charger.max_kw, v_vehicle.inlet_max_kw),\n'
           || E'          ''enforced'', (public.ottoq_policy_get(p_sim_run_id,\n'
           || E'                          ''shield_enforce_charge_session_start'', 1) >= 1)),\n'
           || E'        p_severity := ''critical'', p_ingest_source := ''twin'', p_data_source := ''twin'',\n'
           || E'        p_sim_run_id := p_sim_run_id);\n'
           || E'      IF public.ottoq_policy_get(p_sim_run_id,\n'
           || E'           ''shield_enforce_charge_session_start'', 1) >= 1 THEN\n'
           || E'        RETURN NULL;\n'
           || E'      END IF;\n'
           || E'    END IF;\n'
           || E'  END;';

  v_new := replace(v_def, v_anchor, v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0428 (A): byte delta % <> expected % -- refusing a substitution that did more than one '
                    'replacement', length(v_new) - length(v_def), length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0428 (A): charge_session_start now reads its verdict, +% bytes',
               length(v_new) - length(v_def);
END $$;

-- ── (B) THE CALLER SKIPS A REFUSED START INSTEAD OF COUNTING IT ──
DO $$
DECLARE v_def text; v_new text; v_anchor text; v_insert text; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_auto_charge_assign_tick';

  v_anchor := E'    END;\n\n    v_count := v_count + 1;';
  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0428 (B): anchor matched % times, expected 1 -- re-derive from pg_get_functiondef',
                    v_hits;
  END IF;

  -- 0428: the start now RETURNS NULL when the shield refuses (it must not raise -- section 2). Without
  -- this guard the tick would count a session that never started and emit twin.auto_charge_assign with
  -- session_id: null, which is the only place the returned id is used.
  v_insert := E'    END;\n\n'
           || E'    IF v_session_id IS NULL THEN CONTINUE; END IF;\n\n'
           || E'    v_count := v_count + 1;';

  v_new := replace(v_def, v_anchor, v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0428 (B): byte delta % <> expected %', length(v_new) - length(v_def),
                    length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0428 (B): auto_charge_assign_tick skips a refused start, +% bytes',
               length(v_new) - length(v_def);
END $$;

-- ── V1: the checkpoint reads would_block, and the discarding PERFORM is gone ──
DO $$
DECLARE v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session';
  IF v_src LIKE '%PERFORM 1 FROM public.ottoq_shield_probe%' THEN
    RAISE EXCEPTION '0428 V1: the discarding PERFORM survived -- the checkpoint is still advisory';
  END IF;
  IF v_src NOT LIKE '%FILTER (WHERE sp.would_block)%' THEN
    RAISE EXCEPTION '0428 V1: the verdict is not being read';
  END IF;
  IF v_src NOT LIKE '%shield_enforce_charge_session_start%' THEN
    RAISE EXCEPTION '0428 V1: the off-switch is not wired -- refusing to ship enforcement with no dial';
  END IF;
  RAISE NOTICE '0428 V1: verdict read, PERFORM gone, dial wired';
END $$;

-- ── V2: THE ASSERTION THIS FILE IS REALLY ABOUT -- the refusal must NOT raise.
-- A raise would roll back into the caller's EXCEPTION subtransaction and erase both the refusal event and
-- the shield's evaluation rows. Assert the decision branch returns instead, and that the only RAISE left in
-- the block is the probe-failure WARNING.
DO $$
DECLARE v_src text; v_decide int; v_ret int;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session';
  v_decide := position('IF COALESCE(v_shield_blocks, 0) > 0 THEN' in v_src);
  v_ret    := position('RETURN NULL;' in v_src);
  IF v_decide = 0 THEN RAISE EXCEPTION '0428 V2: the decision branch is missing'; END IF;
  IF v_ret = 0 OR v_ret < v_decide THEN
    RAISE EXCEPTION '0428 V2: no RETURN NULL after the decision branch (decide=%, return=%) -- if the '
                    'refusal raises instead, it rolls back its own evidence. See section 2.', v_decide, v_ret;
  END IF;
  IF substr(v_src, v_decide) LIKE '%RAISE EXCEPTION%' THEN
    RAISE EXCEPTION '0428 V2: a RAISE EXCEPTION appears after the decision branch -- a refusal must return, '
                    'never raise, or the caller''s subtransaction erases the evaluation rows behind it';
  END IF;
  RAISE NOTICE '0428 V2: the refusal returns (decide=%, return=%) and does not raise', v_decide, v_ret;
END $$;

-- ── V3: both functions still build a plan and run. The charge start sits inside the world advance, so a
-- body that errors on first call would take charging down; the smoke call proves syntax, and (A)'s
-- references were checked against prosrc by hand (0427's footer: a call that returns early proves syntax,
-- not resolution -- here every new reference is to p_stall_id / p_vehicle_id / v_stall / v_charger /
-- v_vehicle / p_sim_run_id, all of which exist above the splice point).
DO $$
DECLARE v_ok boolean := false; v_src text; v_guard int; v_counter int;
BEGIN
  -- (A) executed: the rewritten body must parse AND reach its own first guard. p_sim_run_id has no default,
  -- so it is passed; the guard fires before any INSERT, so this call has no side effects.
  BEGIN
    PERFORM twin.ottoq_sim_start_charge_session(
              p_vehicle_id := '00000000-0000-0000-0000-000000000000'::uuid,
              p_stall_id   := '00000000-0000-0000-0000-000000000000'::uuid,
              p_sim_run_id := '00000000-0000-0000-0000-000000000000'::uuid);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%not found%' THEN
      v_ok := true;
    ELSE
      RAISE EXCEPTION '0428 V3: the rewritten start failed for the wrong reason (%) -- it sits on the '
                      'charge path inside the world advance, so this would take charging down', SQLERRM;
    END IF;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION '0428 V3: the start did not reject an unknown vehicle -- expected its own guard to fire';
  END IF;

  -- (B) asserted from source rather than executed, deliberately: ottoq_sim_auto_charge_assign_tick takes
  -- TWO required arguments and loops over live vehicles, so calling it with a fabricated run id would test
  -- the fixture rather than the change. The change is three tokens and its correctness is purely positional
  -- -- the guard must precede the counter -- so assert exactly that.
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_auto_charge_assign_tick';
  v_guard   := position('IF v_session_id IS NULL THEN CONTINUE; END IF;' in v_src);
  v_counter := position('v_count := v_count + 1;' in v_src);
  IF v_guard = 0 THEN RAISE EXCEPTION '0428 V3b: the NULL guard is missing from the caller'; END IF;
  IF v_counter = 0 THEN RAISE EXCEPTION '0428 V3b: the counter is gone -- re-read before trusting V3b'; END IF;
  IF v_guard > v_counter THEN
    RAISE EXCEPTION '0428 V3b: the guard (%) sits AFTER the counter (%) -- a refused start would still be '
                    'counted and would emit twin.auto_charge_assign with session_id: null',
                    v_guard, v_counter;
  END IF;
  RAISE NOTICE '0428 V3: start reaches its vehicle guard; caller guard at % precedes the counter at %',
               v_guard, v_counter;
END $$;

-- ── V4: the dial reads back as 1 and is not agent-writable ──
DO $$
DECLARE v_val numeric; v_agent boolean;
BEGIN
  SELECT default_value, agent_writable INTO v_val, v_agent
    FROM public.ottoq_policy_param_catalog WHERE param_key='shield_enforce_charge_session_start';
  IF v_val IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION '0428 V4: dial default is % not 1', v_val;
  END IF;
  IF v_agent THEN
    RAISE EXCEPTION '0428 V4: the dial is agent_writable -- the agent must not be able to switch the '
                    'safety shield off';
  END IF;
  IF public.ottoq_policy_get(NULL::uuid, 'shield_enforce_charge_session_start', 1) < 1 THEN
    RAISE EXCEPTION '0428 V4: ottoq_policy_get returns < 1 for a run with no override -- enforcement '
                    'would be off by default, which is not what this file ships';
  END IF;
  RAISE NOTICE '0428 V4: dial default 1, not agent-writable, reads back enforcing';
END $$;

-- ── LINEAGE. In the file and inside the transaction. ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0428_the_first_advisory_checkpoint_becomes_enforcing_and_refusing_by_raise_would_have_erased_its_own_evidence',
  true,
  'Promotes charge_session_start from advisory to enforcing -- the first of the six checkpoints 0337/0345 '
  'measured as discarding the shield''s verdict with PERFORM. Four blocking energy rules (EN.001 and EN.005 '
  'safety_critical, EN.002, EN.004) had been consulted 8,587 times each with zero failures and every verdict '
  'thrown away. Could not be done before 0424: HW.002 at the same checkpoint was arithmetically incapable of '
  'passing (4,632 of 4,632, gap min=max=1800s), which is why 0337 G150 said not to enforce; since 0424 it '
  'reads 3,702 evaluations / 0 failures. THE DESIGN TURNS ON ONE TRAP: refusing by RAISE EXCEPTION would '
  'roll back into the caller''s EXCEPTION subtransaction and erase BOTH the refusal event and every '
  'ottoq_rule_evaluations row the probe just wrote -- the engine would refuse charges and leave no trace of '
  'any refusal, strictly worse than the discard it replaces. So the refusal RETURNS NULL; V2 asserts that '
  'permanently and fails if any RAISE EXCEPTION appears after the decision branch. Change (B) adds the '
  'caller''s NULL guard, without which the tick would count a session that never started and emit '
  'twin.auto_charge_assign with session_id: null. Off-switch is the catalogued dial '
  'shield_enforce_charge_session_start (default 1, NOT agent_writable) -- 0 restores advisory behaviour '
  'while keeping the instrumentation, takes effect next tick, no migration. P4 earns the default-on by '
  'refusing to apply unless the ledger shows zero would-block rows at this checkpoint since 0424. NOT done: '
  'task_completion stays advisory because 0346 measured HW.006 failing 7.7% of untethered L2 completions '
  '(G157); the three state-change triggers and policy_write stay advisory because their rules are shadow or '
  'log_only and honouring them would change nothing; and no rule is edited -- not a threshold, not a '
  'severity, not an enforcement column. TRUE because events and rules are both atoms and this adds an event '
  'type and can change what the engine does.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §6 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- `forces_recert` TRUE — resweep before quoting any determinism claim.
--
-- Then, on a fresh run, windowed on the apply (`0334`'s standing rule):
--
--   SELECT count(*) AS refusals,
--          jsonb_agg(DISTINCT payload->'blocking_rules') AS which_rules,
--          count(*) FILTER (WHERE (payload->>'enforced')::boolean) AS actually_refused
--     FROM public.ottoq_events
--    WHERE event_type='ottoq.charge_start_refused'
--      AND occurred_at >= '<apply timestamp>';
--
-- **EXPECT ZERO.** P4 asserted zero would-block rows over the preceding window, so a non-zero count means
-- either a rule began objecting for a real reason — read `blocking_rules`; if it is an `EN.*` code the site
-- power ceiling was genuinely reached and the shield just did its job for the first time — or the promotion
-- is wrong, in which case:
--
--   SELECT public.ottoq_policy_set('global', NULL, 'shield_enforce_charge_session_start', 0);
--
-- turns it off on the next tick without a migration. **Then ask why, do not re-enable and hope.**
--
-- Also confirm the throughput did not move: `twin.auto_charge_assign` count per run should be unchanged,
-- because change (B)'s `CONTINUE` only fires on a refusal and there should be none.
--
-- **And the next checkpoint is NOT task_completion.** `0346`/G157 must be resolved first — HW.006 is
-- failing 7.7% of untethered L2 completions and the writer clearing that pointer is unidentified.
