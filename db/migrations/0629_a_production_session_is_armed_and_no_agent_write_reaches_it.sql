-- migration-version: 20261009033733
-- migration-name:    a_production_session_is_armed_and_no_agent_write_reaches_it
--
-- 0629  **A production session is armed, and no write under an agent's name reaches it.**
--       Chase, the evening of 2026-10-08 CT: "Agent should always be on when runs are activated, and definitely
--       when actual vehicle data is integrated." Every twin run an operator starts is armed (0323, 0615). A production
--       session was not: ottoq_production_start wrote orchestrator_agent_enabled = 0 and cuopt_propose_enabled = 0 and
--       said "agents quiesced and VERIFIED". 0629 arms it with the same arm an operator's run gets, the agent's charge
--       order included, and holds rule 10 at the one door every setting passes through: in production the agent
--       proposes and the kernel disposes, and a write under an agent's name to a setting the session reads is refused.
--
-- ══ §1 WHY (measured 2026-10-09 02:55-03:30 UTC, 9:55-10:30 PM CT on the 8th) ════════════════════════════════════════════
--
--   (a) Why the session was quiesced, and what is left of the reason. 0113: on the first production session (e8a0ba01,
--       2026-08-30) the agent wrote deploy_peak_fraction 0.85 and energy_demand_factor_peak 0.65 onto the session's run
--       policies within two beats, because 0111's quiesce writes were silently refused. Since then: 0432 made
--       agent_writable a guard (3 dials are agent-writable: energy_demand_factor_expensive, energy_demand_factor_peak,
--       energy_reserve_shave), 0414 clamps an agent to its envelope, 0540 turned automatic promotion off, and 0618/0620
--       check every charge order the agent sends against the kernel's own before the seat takes it. What an agent could
--       still do in a production session is write those three dials: set_policy and ops_action from the agent
--       (ottoq-orchestrator-agent, p_by 'ottoq_prime'), and an outside agent's ops request a person approved (0559,
--       p_by 'ottoq_prime:agent_gateway:<principal>'). Rule 10: production OTTO-Q never changes its own settings.
--   (b) The writers, read from the catalog: ottoq_policy_params is written by ottoq_policy_set and, directly, by
--       harness functions (ab_pair, cert_arm_start, determinism_pair, dial_pair, throughput_sweep_arm,
--       grid_fixture_create) and the twin lookahead (mpc_lookahead, mpc_energy_lookahead as 'mpc', refused for a
--       production run by 0308). No table trigger exists. Every agent-named row (1,397 at run scope over 344 runs, one at
--       depot scope) came through ottoq_policy_set. So the refusal goes in ottoq_policy_set, after the shield's
--       policy_write probe (AI.001 judges and logs the attempt) and before the write, as a predicate of its own
--       (0308's argument: a guard that can be called can be tested).
--   (c) Three of the arm's dials count ticks, and a production tick is 120 seconds (the twin's live run here: about
--       12 sim-seconds, 76 ticks in 15.2 sim-minutes on b2efcc07).
--       - cuopt_first_refusal_max_defers and proposer_hold_enabled. A hold keeps a car that needs a charger out of the
--         cursor for one decide tick so a proposer can answer, unless an answer for it is already pending. Last 7 days
--         on the twin depot, 17 operator runs: 894 cars armed, 894 of 897 arms reached their hold tick, 1,049 arms in
--         all, every one by the first-refusal path (0 by cuOpt's own path). In production that is a car waiting two
--         minutes at the gate for a proposer while a charger may be free. Rule 9 and Chase on 2026-10-08: "if there's
--         nothing to optimize, it should just flow normally and go to the best fit." So both are 0 in production: the
--         first-refusal arm returns before arming any car, and the proposers still answer and the seat still takes an
--         answer that is there.
--       - agent_charge_order_ttl_ticks. An order stands until 15 ticks after the tick it was recorded at
--         (ottoq_agent_charge_order_live). On the twin's live run a pass lands about every 9 ticks, so 15 bridges one
--         or two refused passes, as 0614 meant. In production the agent can pass once a tick (ottoq_agent_chain_claim,
--         one claim per tick) and its mean latency is 19.7 s (CLAUDE.md 2.5), so 15 would hold an order 30 minutes.
--         3, the catalog's floor, holds it 6.
--   (d) The arm's other keys are unchanged in production. The review, the grounding and the asset depth are what the
--       agent reads; the chain, cuOpt and CP-SAT propose; the kernel disposes every proposal and checks every order.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_production_write_refusal(scope_type, scope_id, by), new: NULL when the write may proceed, else why
--       a write under an agent's name (ottoq_is_agent_actor: ottoq_prime and every ottoq_prime:<suffix>) would reach a
--       production session: 'production_run' (run scope, a production_live run, live or over),
--       'depot_hosts_a_live_production_session' (depot scope while one runs there), 'a_production_session_is_live'
--       (global scope while one runs anywhere). A person's write is never refused.
--   (b) ottoq_policy_set: after the policy_write probe, a refusal from (a) returns {"ok":false,
--       "error":"production_never_self_tunes", "reason":...}. Nothing is written. Every other write is unchanged.
--   (c) ottoq_agentic_arm: the charge order is armed on run_by 'production_live' as well as 'operator_demo'; on
--       'production_live', cuopt_first_refusal_max_defers 0, proposer_hold_enabled 0 and agent_charge_order_ttl_ticks
--       3, each receipt read like the others (refused or clamped raises). Every other run gets the values it got.
--   (d) ottoq_agentic_arming: a required 0 is met only by 0, and on a production run the two hold keys require 0. A
--       twin run's report is unchanged (every required value there is 1).
--   (e) ottoq_production_start: the quiesce is replaced by ottoq_agentic_arm(run, 'production_start'), which raises on
--       any refused or clamped write, so a session never starts half-armed (0113's rule, kept). Its receipt and its
--       event say 'armed', carry the arming report, and list any setting at the depot's or the global scope last
--       written under an agent's name, for a person. Today one: energy_reserve_shave = 1 at the twin depot, by
--       'ottoq_prime:promoter' on 2026-09-26 (the promotion 0540 turned off afterwards; it is still in force).
--       ottoq_agentic_arm is not granted to anon, so a session can no longer be started with the anon key (it could
--       be: production_start is granted to anon and wrote through ottoq_policy_set, which is). authenticated and
--       service_role start it as before. No code calls production_start today.
--   (f) ottoq_agent_board: on a production run the board carries {"production": {"live": true, "dials": "read_only"}}
--       with a note, so the agent does not spend its moves on dials. Absent on every other run.
--   (g) Catalog descriptions of the six keys that said production is quiesced or did not say production.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the five bodies are the ones measured (md5 of their source), the predicate is new, the
--   catalog admits 0 for both hold keys and 3 for the ttl, and 0629 is not applied. Each anchor matches once, and after
--   each EXECUTE the stored definition is the pre-image with exactly the replacements (V1). V2 the predicate on live
--   rows (reads only): an agent on the newest twin-depot production run is refused, on the newest operator run is not,
--   a person is never refused, and the depot and global answers follow whether a production session is live. V3 the
--   setter and the ops door refuse an agent on that production run and take a person's write, each in a subtransaction
--   rolled back. V4 the arming report of the newest operator run is unchanged. V5 the production arm executed on that
--   production run, rolled back: 12 receipts, the three production values, the charge order, and the report 'armed'.
--   V6 every role that can call ottoq_policy_set can call the predicate. Executed against the live bodies by
--   tests/test_agent_production_arm_sql.py: production_start arms the session and reports the inherited setting, the
--   agent's dial write and ops action are refused there and taken on a twin run, a person's are taken, an operator's
--   arm is unchanged, a cert arm is still refused, and depot and global scope are refused only while a session is live.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. The setter's new branch refuses only an agent-named write that
--   reaches a production_live run or a live production session; no certification arm, sweep, dial pair or canon runs
--   as production_live, and they write their dials directly or as a person. The arm, the arming report and the board
--   change only for run_by 'production_live'; an operator's, a sweep's and a certification arm's values are the ones
--   before 0629 (V4 and the tests).
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0629_pre' AND object_kind = 'function';
--   set each description back from the rows WHERE label = '0629_pre' AND object_kind = 'catalog_description';
--   DROP FUNCTION public.ottoq_production_write_refusal(text, uuid, text);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0629_a_production_session_is_armed_and_no_agent_write_reaches_it'.
--   A session already armed keeps its run-scoped dials until it ends.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0629 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones measured; the predicate is new; the catalog admits the production values ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_policy_set(text,uuid,text,numeric,text)', '70238f3381c885e47b7a6f8128f65121'),
    ('public.ottoq_production_start(uuid)',                  'c0554484f74511c58145c561076434d3'),
    ('public.ottoq_agentic_arm(uuid,text)',                  '9509e976b925e380a4ebd68115a75f1e'),
    ('public.ottoq_agentic_arming(uuid)',                    'fe54eb23d05d9b626b44e28743712c14'),
    ('public.ottoq_agent_board(uuid)',                       '144242b72a24b58bf792af1527a238ce')) AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0629 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_production_write_refusal(text,uuid,text)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                 WHERE name = '0629_a_production_session_is_armed_and_no_agent_write_reaches_it') THEN
    RAISE EXCEPTION '0629 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'cuopt_first_refusal_max_defers' AND COALESCE(min_value, 0) <= 0)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                     WHERE param_key = 'proposer_hold_enabled' AND COALESCE(min_value, 0) <= 0)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                     WHERE param_key = 'agent_charge_order_ttl_ticks' AND COALESCE(min_value, 0) <= 3
                       AND COALESCE(max_value, 3) >= 3)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                     WHERE param_key = 'agent_charge_order' AND default_value = 0 AND max_value = 1) THEN
    RAISE EXCEPTION '0629 P1: the catalog does not admit the production values (0, 0, 3) or the charge order dial';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0629_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure,
                 'public.ottoq_production_start(uuid)'::regprocedure,
                 'public.ottoq_agentic_arm(uuid,text)'::regprocedure,
                 'public.ottoq_agentic_arming(uuid)'::regprocedure,
                 'public.ottoq_agent_board(uuid)'::regprocedure);

-- V4's before: the arming report of the newest operator run on the twin depot, without its live counts
CREATE TEMP TABLE _0629_arming_before ON COMMIT DROP AS
SELECT r.sim_run_id, public.ottoq_agentic_arming(r.sim_run_id) - 'primary_proposer' AS report
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.run_by = 'operator_demo'
 ORDER BY r.started_at DESC LIMIT 1;

-- ══ (a) the predicate ═════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_production_write_refusal(p_scope_type text, p_scope_id uuid, p_by text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  --: 0629 (CLAUDE.md rule 10). NULL when the write may proceed; otherwise why a write under an agent's name would reach
  --: a production session. ottoq_is_agent_actor names ottoq_prime and every ottoq_prime:<suffix>: the agent, the
  --: promoter, and an outside agent's request a person approved (0559 keeps the agent's name on it on purpose). A
  --: person's write is never refused here.
  SELECT CASE
    WHEN NOT public.ottoq_is_agent_actor(p_by) THEN NULL
    --: run scope: a production run's own settings, live or over
    WHEN p_scope_type IN ('run', 'sim_run')
     AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                  WHERE r.sim_run_id = p_scope_id AND r.run_by = 'production_live')
      THEN 'production_run'
    --: depot scope: every run at the depot reads it, so while a production session is live there
    WHEN p_scope_type = 'depot'
     AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                  WHERE r.depot_id = p_scope_id AND r.run_by = 'production_live'
                    AND r.status IN ('running', 'paused'))
      THEN 'depot_hosts_a_live_production_session'
    --: global scope: every run reads it, so while any production session is live
    WHEN p_scope_type = 'global'
     AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                  WHERE r.run_by = 'production_live' AND r.status IN ('running', 'paused'))
      THEN 'a_production_session_is_live'
    ELSE NULL
  END
$fn$;

COMMENT ON FUNCTION public.ottoq_production_write_refusal(text, uuid, text) IS
'0629 (CLAUDE.md rule 10). NULL if a write by p_by at (p_scope_type, p_scope_id) may proceed, else why a write under an '
'agent''s name would reach a production session: production_run, depot_hosts_a_live_production_session or '
'a_production_session_is_live. ottoq_policy_set refuses on it with error production_never_self_tunes. A person''s '
'write is never refused.';

-- ══ the anchored patches: one DO per body, each anchor once, the stored definition checked after (V1) ═════════════════════
CREATE TEMP TABLE _0629_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

-- (b) ottoq_policy_set
INSERT INTO _0629_patch VALUES
('public.ottoq_policy_set(text,uuid,text,numeric,text)', 1,
$old$DECLARE v_min numeric; v_max numeric; v_final numeric; v_minx numeric; v_maxx numeric;$old$,
$new$DECLARE v_min numeric; v_max numeric; v_final numeric; v_minx numeric; v_maxx numeric; v_prod text;$new$),
('public.ottoq_policy_set(text,uuid,text,numeric,text)', 2,
$old$-- 0432: agent_writable IS A GUARD, NOT A LABEL.$old$,
$new$-- 0629 (CLAUDE.md rule 10): A PRODUCTION SESSION'S SETTINGS ARE NEVER WRITTEN UNDER AN AGENT'S NAME.
  -- A production session is armed (0629): the agent proposes there and the kernel disposes. What an agent may not do
  -- there is change a setting the session reads. ottoq_production_write_refusal names why a write would reach a
  -- production session, or returns NULL. Here, after the probe above has judged and logged the attempt, and before
  -- the write. A person's write, and an agent's write to a twin run, pass as before.
  v_prod := public.ottoq_production_write_refusal(p_scope_type, p_scope_id, p_by);
  IF v_prod IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'error','production_never_self_tunes','param',p_param_key,'by',p_by,
                              'scope_type',p_scope_type,'scope_id',p_scope_id,'reason',v_prod,
                              'detail','rule 10: in production an agent proposes and the kernel disposes; a setting '
                                       'changes only under a person''s name, as a certified change');
  END IF;

-- 0432: agent_writable IS A GUARD, NOT A LABEL.$new$);

-- (c) ottoq_agentic_arm
INSERT INTO _0629_patch VALUES
('public.ottoq_agentic_arm(uuid,text)', 1,
$old$      ('proposer_hold_enabled',          1::numeric),$old$,
$new$      ('proposer_hold_enabled',          CASE WHEN v_run_by = 'production_live' THEN 0 ELSE 1 END::numeric),  --: 0629$new$),
('public.ottoq_agentic_arm(uuid,text)', 2,
$old$      ('cuopt_first_refusal_max_defers', 6::numeric),$old$,
$new$      ('cuopt_first_refusal_max_defers', CASE WHEN v_run_by = 'production_live' THEN 0 ELSE 6 END::numeric),  --: 0629$new$),
('public.ottoq_agentic_arm(uuid,text)', 3,
$old$  IF v_run_by = 'operator_demo' THEN$old$,
$new$  IF v_run_by IN ('operator_demo', 'production_live') THEN  --: 0629: a production session takes the order too$new$),
('public.ottoq_agentic_arm(uuid,text)', 4,
$old$  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'armed_by', p_by,$old$,
$new$  --: 0629. A PRODUCTION TICK IS 120 SECONDS, so the three dials of this arm that count ticks are set for it.
  --: cuopt_first_refusal_max_defers 0 and proposer_hold_enabled 0 (in the loop above): a hold keeps a car that needs a
  --: charger out of the cursor for one tick so a proposer can answer. A tick is about 12 sim-seconds on the twin's live
  --: run and 120 real seconds in production, so in production no car waits at the gate for a proposer; the proposers
  --: still answer, and the seat still takes an answer that is there. agent_charge_order_ttl_ticks 3: an order stands
  --: until 3 ticks after the tick it was recorded at, 6 minutes rather than 15 ticks' 30, since the agent can pass once
  --: a tick there.
  IF v_run_by = 'production_live' THEN
    v_r := public.ottoq_policy_set('run', p_sim_run_id, 'agent_charge_order_ttl_ticks', 3::numeric, p_by);
    IF NOT COALESCE((v_r->>'ok')::boolean, false) OR COALESCE((v_r->>'clamped')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: agent_charge_order_ttl_ticks was not set as asked -> %', v_r
        USING ERRCODE = '22023';
    END IF;
    v_receipts := v_receipts || jsonb_build_array(v_r);
  END IF;

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'armed_by', p_by,$new$);

-- (d) ottoq_agentic_arming
INSERT INTO _0629_patch VALUES
('public.ottoq_agentic_arming(uuid)', 1,
$old$      ('proposer_hold_enabled',          1::numeric,
       '0259/0262: one-tick right of first refusal for a non-cuOpt proposer'),
      ('cuopt_first_refusal_max_defers', 1::numeric,
       '0152 set the global tier to 0; without a run row nothing is ever armed'),$old$,
$new$      ('proposer_hold_enabled',          CASE WHEN v_run_by = 'production_live' THEN 0 ELSE 1 END::numeric,
       CASE WHEN v_run_by = 'production_live'
            THEN '0629: 0 in production: a hold is one 120-second tick, and no car waits at the gate for a proposer'
            ELSE '0259/0262: one-tick right of first refusal for a non-cuOpt proposer' END),
      ('cuopt_first_refusal_max_defers', CASE WHEN v_run_by = 'production_live' THEN 0 ELSE 1 END::numeric,
       CASE WHEN v_run_by = 'production_live'
            THEN '0629: 0 in production, so the first-refusal arm returns before it arms a car'
            ELSE '0152 set the global tier to 0; without a run row nothing is ever armed' END),$new$),
('public.ottoq_agentic_arming(uuid)', 2,
$old$    IF v_have >= v_k.required THEN$old$,
$new$    IF (CASE WHEN v_k.required = 0 THEN v_have = 0 ELSE v_have >= v_k.required END) THEN  --: 0629: a required 0 is exact$new$),
('public.ottoq_agentic_arming(uuid)', 3,
$old$      'in_force', v_have, 'satisfied', v_have >= v_k.required, 'why', v_k.why));$old$,
$new$      'in_force', v_have,
      'satisfied', (CASE WHEN v_k.required = 0 THEN v_have = 0 ELSE v_have >= v_k.required END),
      'why', v_k.why));$new$);

-- (e) ottoq_production_start
INSERT INTO _0629_patch VALUES
('public.ottoq_production_start(uuid)', 1,
$old$  v_run uuid; v_scenario ottoq_scenarios%ROWTYPE; v_existing uuid; v_feed text; v_ps jsonb;$old$,
$new$  v_run uuid; v_scenario ottoq_scenarios%ROWTYPE; v_existing uuid; v_feed text; v_ps jsonb; v_inherited jsonb;$new$),
('public.ottoq_production_start(uuid)', 2,
$old$  v_ps := ottoq_policy_set('run', v_run, 'orchestrator_agent_enabled', 0, 'production_start');
  IF NOT COALESCE((v_ps->>'ok')::boolean, false) THEN
    RAISE EXCEPTION 'production_start: orchestrator_agent_enabled write refused: %', v_ps;
  END IF;
  v_ps := ottoq_policy_set('run', v_run, 'cuopt_propose_enabled', 0, 'production_start');
  IF NOT COALESCE((v_ps->>'ok')::boolean, false) THEN
    RAISE EXCEPTION 'production_start: cuopt_propose_enabled write refused: %', v_ps;
  END IF;$old$,
$new$  -- 0629. THE SESSION IS ARMED, as an operator's run is. Chase, 2026-10-08 CT: "Agent should always be on when runs are
  -- activated, and definitely when actual vehicle data is integrated." The agent proposes; the kernel disposes.
  -- ottoq_agentic_arm raises on any write the setter refuses or clamps, so a session never starts half-armed (0113's
  -- rule, kept), and it sets the arm's three tick-counted dials for a 120-second tick. No write under an agent's name
  -- reaches this session's settings: ottoq_policy_set refuses it (production_never_self_tunes, CLAUDE.md rule 10).
  v_ps := public.ottoq_agentic_arm(v_run, 'production_start');

  -- 0629. What this session inherits that was last written under an agent's name, at this depot's scope or the global
  -- one. Reported for a person (rule 10); never changed here.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('scope_type', pp.scope_type, 'param_key', pp.param_key,
                                               'value', pp.param_value, 'updated_by', pp.updated_by,
                                               'updated_at', pp.updated_at)
                            ORDER BY pp.scope_type, pp.param_key), '[]'::jsonb)
    INTO v_inherited
    FROM public.ottoq_policy_params pp
   WHERE ((pp.scope_type = 'depot' AND pp.scope_id = p_depot) OR pp.scope_type = 'global')
     AND public.ottoq_is_agent_actor(pp.updated_by);$new$),
('public.ottoq_production_start(uuid)', 3,
$old$    p_payload := jsonb_build_object('depot_id', p_depot, 'feed_mode', v_feed,$old$,
$new$    p_payload := jsonb_build_object('depot_id', p_depot, 'feed_mode', v_feed, 'agents', 'armed (0629)',
                                    'agent_written_settings_in_force', v_inherited,$new$),
('public.ottoq_production_start(uuid)', 4,
$old$    'agents', 'quiesced and VERIFIED (orchestrator_agent_enabled=0, cuopt_propose_enabled=0)');$old$,
$new$    'agents', 'armed (0629): the agent proposes and the kernel disposes; no write under an agent''s name reaches this '
              'session''s settings',
    'arming', v_ps -> 'arming',
    'agent_written_settings_in_force', v_inherited);$new$);

-- (f) ottoq_agent_board
INSERT INTO _0629_patch VALUES
('public.ottoq_agent_board(uuid)', 1,
$old$  RETURN v_board;
END;$old$,
$new$  --: 0629. A PRODUCTION SESSION SAYS SO. The agent is armed there and proposes; every write under its name to a setting
  --: the session reads is refused (ottoq_policy_set, production_never_self_tunes, CLAUDE.md rule 10). The board says it
  --: first, so the agent does not spend its moves on dials. Absent on every other run, so a twin board is unchanged.
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id AND r.run_by = 'production_live') THEN
    v_board := v_board || jsonb_build_object('production', jsonb_build_object(
      'live', true,
      'dials', 'read_only',
      'note', 'A production session with real vehicles. You propose; the kernel disposes. No set_policy or ops_action '
              'reaches this session: every write under your name is refused (production_never_self_tunes). Your charge '
              'order and your solver objective are proposals the kernel checks before it takes them.'));
  END IF;

  RETURN v_board;
END;$new$);

DO $patch$
DECLARE f record; p record; v_def text; v_pre text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0629_patch ORDER BY fn LOOP
    v_pre := pg_get_functiondef(to_regprocedure(f.fn));
    v_def := v_pre;
    FOR p IN SELECT * FROM _0629_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0629 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0629 V1: % is not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ V1, by meaning: the refusal sits after the probe and before the write; the arm's gates are in their order ═══════════
DO $v1$
DECLARE v_set text; v_arm text; v_start text;
BEGIN
  v_set := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure),
                                         '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF NOT (strpos(v_set, 'ottoq_shield_probe(') > 0
          AND strpos(v_set, 'ottoq_shield_probe(') < strpos(v_set, 'public.ottoq_production_write_refusal(p_scope_type, p_scope_id, p_by)')
          AND strpos(v_set, 'public.ottoq_production_write_refusal(p_scope_type, p_scope_id, p_by)') < strpos(v_set, 'INSERT INTO ottoq_policy_params')
          AND strpos(v_set, 'public.ottoq_production_write_refusal(p_scope_type, p_scope_id, p_by)') < strpos(v_set, '''not_agent_writable''')) THEN
    RAISE EXCEPTION '0629 V1: the setter''s refusal is not after the probe and before the 0432 guard and the write';
  END IF;

  v_arm := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_agentic_arm(uuid,text)'::regprocedure),
                                         '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF strpos(v_arm, 'IF v_run_by = ''cert_harness'' THEN') = 0
     OR strpos(v_arm, 'IF v_run_by = ''cert_harness'' THEN') > strpos(v_arm, 'FOR v_k IN')
     OR strpos(v_arm, 'IF v_run_by IN (''operator_demo'', ''production_live'') THEN') = 0
     OR strpos(v_arm, 'IF v_run_by = ''production_live'' THEN') = 0 THEN
    RAISE EXCEPTION '0629 V1: the arm''s gates are not cert refusal first, then the loop, the order and production';
  END IF;

  v_start := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_production_start(uuid)'::regprocedure),
                                           '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF strpos(v_start, 'public.ottoq_agentic_arm(v_run, ''production_start'')') = 0
     OR strpos(v_start, '''orchestrator_agent_enabled'', 0') > 0
     OR strpos(v_start, '''cuopt_propose_enabled'', 0') > 0 THEN
    RAISE EXCEPTION '0629 V1: production_start still quiesces, or does not arm';
  END IF;
END $v1$;

-- ══ V2: the predicate on live rows (reads only) ═══════════════════════════════════════════════════════════════════════════
DO $v2$
DECLARE v_prod uuid; v_demo uuid; v_live_here boolean; v_live_any boolean;
        c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  SELECT sim_run_id INTO v_prod FROM public.ottoq_sim_runs
   WHERE depot_id = c_twin AND run_by = 'production_live' ORDER BY started_at DESC LIMIT 1;
  SELECT sim_run_id INTO v_demo FROM public.ottoq_sim_runs
   WHERE depot_id = c_twin AND run_by = 'operator_demo' ORDER BY started_at DESC LIMIT 1;
  IF v_prod IS NULL OR v_demo IS NULL THEN
    RAISE EXCEPTION '0629 V2: the twin depot has no production run or no operator run to read';
  END IF;

  IF public.ottoq_production_write_refusal('run', v_prod, 'ottoq_prime') IS DISTINCT FROM 'production_run'
     OR public.ottoq_production_write_refusal('run', v_prod, 'ottoq_prime:agent_gateway:v2') IS DISTINCT FROM 'production_run'
     OR public.ottoq_production_write_refusal('sim_run', v_prod, 'ottoq_prime:promoter') IS DISTINCT FROM 'production_run' THEN
    RAISE EXCEPTION '0629 V2: an agent on production run % is not refused', v_prod;
  END IF;
  IF public.ottoq_production_write_refusal('run', v_prod, 'production_start') IS NOT NULL
     OR public.ottoq_production_write_refusal('run', v_prod, 'ottocommand') IS NOT NULL
     OR public.ottoq_production_write_refusal('run', v_prod, NULL) IS NOT NULL
     OR public.ottoq_production_write_refusal('run', v_demo, 'ottoq_prime') IS NOT NULL THEN
    RAISE EXCEPTION '0629 V2: a person, or an agent on operator run %, is refused', v_demo;
  END IF;

  v_live_here := EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = c_twin AND run_by = 'production_live'
                                                              AND status IN ('running', 'paused'));
  v_live_any := EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE run_by = 'production_live'
                                                             AND status IN ('running', 'paused'));
  IF (public.ottoq_production_write_refusal('depot', c_twin, 'ottoq_prime') IS NOT NULL) <> v_live_here
     OR (public.ottoq_production_write_refusal('global', '00000000-0000-0000-0000-000000000000', 'ottoq_prime') IS NOT NULL)
        <> v_live_any
     OR public.ottoq_production_write_refusal('depot', c_twin, 'production_start') IS NOT NULL THEN
    RAISE EXCEPTION '0629 V2: the depot or global answer does not follow whether a production session is live';
  END IF;
  RAISE NOTICE '0629 V2: production run % refused for an agent; operator run % not; a production session live here: %, anywhere: %',
    v_prod, v_demo, v_live_here, v_live_any;
END $v2$;

-- ══ V3: the setter and the ops door refuse an agent on the production run and take a person's write (rolled back) ════════
DO $v3$
DECLARE v_prod uuid; v_depot uuid; v_r jsonb; v_detail text;
BEGIN
  SELECT sim_run_id, depot_id INTO v_prod, v_depot FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND run_by = 'production_live'
   ORDER BY started_at DESC LIMIT 1;

  BEGIN
    v_r := jsonb_build_object(
      'agent',   public.ottoq_policy_set('run', v_prod, 'energy_reserve_shave', 1, 'ottoq_prime'),
      'gateway', public.ottoq_policy_set('run', v_prod, 'energy_demand_factor_peak', 0.5, 'ottoq_prime:agent_gateway:v3'),
      'ops',     public.ottoq_apply_ops_action(v_prod, v_depot, 'extend_forecast_horizon', '{}'::jsonb, 'ottoq_prime'),
      'person',  public.ottoq_policy_set('run', v_prod, 'energy_demand_factor_peak', 0.5, '0629_v3_person'));
    RAISE EXCEPTION 'v3' USING ERRCODE = 'OQ629', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ629' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
  END;
  v_r := v_detail::jsonb;

  IF v_r #>> '{agent,error}' IS DISTINCT FROM 'production_never_self_tunes'
     OR v_r #>> '{agent,reason}' IS DISTINCT FROM 'production_run'
     OR v_r #>> '{gateway,error}' IS DISTINCT FROM 'production_never_self_tunes'
     OR v_r #>> '{ops,status}' IS DISTINCT FROM 'refused'
     OR v_r #>> '{ops,reason}' IS DISTINCT FROM 'production_never_self_tunes'
     OR v_r #>> '{person,ok}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0629 V3: the doors did not answer as built -> %', v_r;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_prod
                                                          AND updated_by = '0629_v3_person') THEN
    RAISE EXCEPTION '0629 V3: the rolled-back write is still there';
  END IF;
END $v3$;

-- ══ V4: the newest operator run's arming report is the one before 0629 ═══════════════════════════════════════════════════
DO $v4$
DECLARE b record;
BEGIN
  SELECT * INTO b FROM _0629_arming_before;
  IF b.sim_run_id IS NULL THEN
    RAISE EXCEPTION '0629 V4: no operator run to compare';
  END IF;
  IF (public.ottoq_agentic_arming(b.sim_run_id) - 'primary_proposer') IS DISTINCT FROM b.report THEN
    RAISE EXCEPTION '0629 V4: operator run %''s arming report moved: % -> %', b.sim_run_id, b.report,
      public.ottoq_agentic_arming(b.sim_run_id) - 'primary_proposer';
  END IF;
END $v4$;

-- ══ V5: the production arm, executed on the newest twin-depot production run and rolled back ═════════════════════════════
DO $v5$
DECLARE v_prod uuid; v_r jsonb; v_detail text; v_rc jsonb;
BEGIN
  SELECT sim_run_id INTO v_prod FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND run_by = 'production_live'
   ORDER BY started_at DESC LIMIT 1;

  BEGIN
    v_r := public.ottoq_agentic_arm(v_prod, '0629_v5');
    RAISE EXCEPTION 'v5' USING ERRCODE = 'OQ629', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ629' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
  END;
  v_r := v_detail::jsonb;

  SELECT jsonb_object_agg(x->>'param', (x->>'applied')::numeric) INTO v_rc
    FROM jsonb_array_elements(v_r->'receipts') x;
  IF (v_r->>'ok') IS DISTINCT FROM 'true'
     OR jsonb_array_length(v_r->'receipts') <> 12
     OR (v_rc->>'cuopt_first_refusal_max_defers')::numeric IS DISTINCT FROM 0
     OR (v_rc->>'proposer_hold_enabled')::numeric IS DISTINCT FROM 0
     OR (v_rc->>'agent_charge_order_ttl_ticks')::numeric IS DISTINCT FROM 3
     OR (v_rc->>'agent_charge_order')::numeric IS DISTINCT FROM 1
     OR (v_rc->>'orchestrator_agent_enabled')::numeric IS DISTINCT FROM 1
     OR (v_rc->>'cuopt_propose_enabled')::numeric IS DISTINCT FROM 1
     OR (v_r #>> '{arming,satisfied}')::int IS DISTINCT FROM (v_r #>> '{arming,required}')::int
     OR v_r #>> '{arming,verdict}' NOT IN ('armed', 'armed_primary_unreachable') THEN
    RAISE EXCEPTION '0629 V5: the production arm did not land as built -> receipts %, arming %', v_rc, v_r->'arming';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_prod
                                                          AND updated_by = '0629_v5') THEN
    RAISE EXCEPTION '0629 V5: the rolled-back arm left a row';
  END IF;
  RAISE NOTICE '0629 V5: production arm on %: 12 receipts, holds 0/0, ttl 3, order 1; arming %', v_prod,
    v_r #>> '{arming,verdict}';
END $v5$;

-- ══ V6: every role that can call the setter can call the predicate ══════════════════════════════════════════════════════
DO $v6$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_function_privilege(r, 'public.ottoq_policy_set(text,uuid,text,numeric,text)', 'EXECUTE')
       AND NOT has_function_privilege(r, 'public.ottoq_production_write_refusal(text,uuid,text)', 'EXECUTE') THEN
      RAISE EXCEPTION '0629 V6: % can call ottoq_policy_set and not the predicate it now calls', r;
    END IF;
  END LOOP;
END $v6$;

-- ══ (g) the catalog's words ═══════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0629_pre', 'catalog_description', 'public', 'ottoq_policy_param_catalog.' || c.param_key, c.description,
       md5(c.description)
  FROM public.ottoq_policy_param_catalog c
 WHERE c.param_key IN ('orchestrator_agent_enabled', 'agent_review_enabled', 'cuopt_first_refusal_max_defers',
                       'proposer_hold_enabled', 'agent_charge_order', 'agent_charge_order_ttl_ticks');

DO $words$
DECLARE r record; n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('orchestrator_agent_enabled',
     '0 = deterministic core only (production_start default)',
     '0 = deterministic core only (production_start wrote 0 until 0629, which arms the session)'),
    ('agent_review_enabled',
     'Certification arms and production runs keep 0.',
     'Certification arms keep 0; a production session is armed with 1 (0629).'),
    ('cuopt_first_refusal_max_defers',
     'agentic full mode sets 6.',
     'agentic full mode sets 6, and 0 on a production session (0629): a hold is one tick, 120 seconds there, so no car waits at the gate for a proposer.'),
    ('proposer_hold_enabled',
     'Certification arms set neither key.',
     'Certification arms set neither key. A production session is armed with 0 (0629).'),
    ('agent_charge_order',
     'Set run-scoped by ottoq_agentic_arm (0615); never by the engine.',
     'Set run-scoped by ottoq_agentic_arm on an operator''s run (0615) and a production session (0629); never by the engine.'),
    ('agent_charge_order_ttl_ticks',
     'after it the kernel''s own order resumes.',
     'after it the kernel''s own order resumes. A production session is armed with 3 (0629): a tick is 120 seconds there and the agent can pass once a tick, so an order stands 6 minutes, not 30.')
  ) AS t(param_key, c_old, c_new) LOOP
    SELECT (length(description) - length(replace(description, r.c_old, ''))) / length(r.c_old) INTO n
      FROM public.ottoq_policy_param_catalog WHERE param_key = r.param_key;
    IF n IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION '0629 (g): the words of % match % times, not 1', r.param_key, n;
    END IF;
    UPDATE public.ottoq_policy_param_catalog
       SET description = replace(description, r.c_old, r.c_new)
     WHERE param_key = r.param_key;
  END LOOP;
END $words$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0629_a_production_session_is_armed_and_no_agent_write_reaches_it', false, false,
  'ottoq_production_start arms the session with ottoq_agentic_arm instead of quiescing it; on production_live the arm '
  'also arms the charge order and sets cuopt_first_refusal_max_defers 0, proposer_hold_enabled 0 and '
  'agent_charge_order_ttl_ticks 3; ottoq_policy_set refuses a write under an agent''s name that reaches a production '
  'session (ottoq_production_write_refusal); the arming report requires the two hold keys at 0 on production; the '
  'board says so on production. FALSE/FALSE: every change applies only to run_by production_live or to an agent-named '
  'write reaching one; no certification arm, sweep, dial pair or canon runs as production_live, and an operator''s, a '
  'sweep''s and a certification arm''s values are the ones before 0629 (V4, tests).',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
