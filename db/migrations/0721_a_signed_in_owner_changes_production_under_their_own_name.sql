-- migration-version: PENDING
-- migration-name:    a_signed_in_owner_changes_production_under_their_own_name
--
-- 0721  **A signed-in owner changes production under their own name, and every owner command says which door it came
--        through.** OTTO-Command becomes the one filter and executor between an owner's personal agent and OTTO-Q
--        (Chase, 2026-10-14: "It should just act as both a query LLM bot to provide answers and search results, and also
--        execute for OTTO-Q when preferences are changed via personal agents like Hermes, Grok, etc. So request comes in
--        from personal agents, OTTOCommand processes and acts and returns info back. So it will act as the filter and
--        executor there."). The agent gateway's half (the MCP tool ask_ottocommand, the wider reads, the 50-second cap)
--        is in edge-functions/_shared/; this file is the database's half. CLAUDE.md rules 9 and 10; db/checks/0449.
--
-- ══ §1 WHY (read-only on the live catalog, 2026-10-14: stamped reads 14:54:24-14:54:35 and 15:18:23-15:18:52 UTC,
--    9:54 and 10:18 AM CT; reproduce: db/checks/0449) ════════════════════════════════════════════════════════════════
--
--   (a) PRODUCTION IS REFUSED TO EVERY OWNER. public.ottoq_owner_command (md5 533b275b976b5287f1f48b245132139f) sets
--       v_demo := run_by = 'operator_demo' and refuses anything else as no_live_demo. Since 0718 (applied
--       20261013210801) production's world step, twin.ottoq_world_advance, applies owner settings at every tick
--       (ottoq.ottoq_owner_orders_tick before the visit atoms), so the engine side is ready and the door is the only
--       thing between an owner and their own cars in production. The one owner command ever recorded is the 2026-10-04
--       smoke test's preview, refused no_live_demo.
--   (b) NO PERSON IS RECORDED. ottoq_owner_commands carries principal_id and principal_name, the AGENT
--       ("oauth.hermes-agent.08e94d9e"), and nothing names the person behind it, so rule 10's "in production no setting
--       changes except under a person's name" cannot be read off the record. An agent signed in through 0700 has one:
--       ottoq_oauth_grants ties its principal to an ottoq_owner_accounts row (chase@ottoyard.com, linked to Tesla Robotaxi
--       TN, the one account). A passcode session (0607) and an issued key (0559) name no one.
--   (c) NO RECORD OF WHICH DOOR. ottoq_agent_call knows the transport ('rest', 'mcp', 'ask') and does not pass it on, so
--       a command OTTO-Command made reads exactly like one the agent's own model made.
--   (d) LOWERING A CHARGE LIMIT IS ONE CALL. Rule 9: a lower limit is the owner's, "set verified and confirmed". 0605
--       counts an explicit apply as the confirmation, which holds on a demo run. In production it should take the
--       preview's plan first, so what the person confirms is the plan OTTO-Q will apply.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   TWO COLUMNS on ottoq_owner_commands (class evidence in the run-scope registry: neither is a run key, so check (a) has
--   nothing to register; V6 asserts the registry stays clean):
--     acting_person  the email of the OTTOYARD account behind an agent signed in through 0700, when that account is still
--                    linked and active and owns the agent's fleet; NULL for a passcode session or an issued key.
--     via            'ottocommand' when the command came through OTTO-Command (transport 'ask': POST /v1/ask or the MCP
--                    tool ask_ottocommand), 'direct' otherwise. NULL on rows written before this file (never backfilled).
--   Both join the immutability guard (ottoq_owner_commands_guard, md5 758eff5a6a274b176573c6674840dc55), and a BEFORE
--   INSERT trigger refuses an APPLIED command on a production_live run with no acting_person: a backstop under the door,
--   so rule 10 holds for any writer.
--
--   TWO FUNCTIONS
--     ottoq_owner_acting_person(principal)  the person, as above (one primary-key probe per table).
--     ottoq_owner_write_gate(principal, run) may this agent change settings on this run, and under whose name:
--         operator_demo run                       allowed, as before (person stamped when there is one)
--         production_live run, a person           allowed, recorded under that person
--         production_live run, no person          refused production_needs_a_person, with why for each kind of
--                                                 credential and what to do (sign in; reading works as it is)
--         no run, or any other run                refused no_live_demo, the 0605 words unchanged
--
--   ottoq_owner_command GAINS ITS DOOR. The body moves, by anchored substitution of the live definition (each anchor
--   asserted to occur exactly once), to a four-argument form ottoq_owner_command(principal, tool, args, p_via):
--     a. the 0605 demo-only refusal is replaced by the gate's answer;
--     b. set_charge_limit marks a car whose limit goes DOWN (v_pct < its limit before);
--     c. ON PRODUCTION, an apply that lowers a limit without expect_plan_hash is refused confirm_required: preview it,
--        show the person, apply with the preview's plan_hash. Raising or clearing a limit needs no preview. An undo that
--        restores a lower limit is not gated: on a production run that limit was itself confirmed by its plan hash;
--     d. every command row records acting_person and via;
--     e. the receipt says "until the production run ends" on a production run.
--   The three-argument form is kept as a one-line delegate (via 'direct') for any direct caller. ottoq_agent_call
--   (md5 ae935f897ee25b6db3eacfbb9215797d) passes its transport. The receipt (ottoq_owner_command_reply, md5
--   bd0c86d127a2a84903fa2fb812ee1ac5) shows acting_person and via, and the run's own end. whoami
--   (ottoq_agent_read_whoami, md5 53aa8a6690ecc6274e4cd1dc73972006) adds live_production_run and the gate's answer as
--   `changes`, so OTTO-Command knows before it acts.
--
--   Writes stay in the owner tables. Nothing here calls ottoq_policy_set or writes a setting: an owner's requirement is
--   the owner's (rule 9), applied at OTTO-Q's tick. Production still never self-tunes (rule 10): no agent writes a
--   setting there, and every owner change in production is recorded under the person who made it.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   Every body this file replaces is the agent door (ottoq_agent_call, ottoq_owner_command, its receipt, whoami) or a
--   trigger on ottoq_owner_commands. No certification, dial or sweep arm calls any of them, and the engine's readers of
--   owner settings (ottoq_effective_target_soc_at, ottoq_departure_clear, ottoq_owner_departure_blocked,
--   ottoq.ottoq_owner_orders_tick, both world steps) are untouched. Does changing WHO may write owner settings change a
--   certified run? No: a certification run has no owner commands. Its arms are cert_harness / ab_harness runs that the
--   gate refuses; they run in one uncommitted transaction no agent's session can see; and every test-day runner refuses
--   to start while ANY run is running or paused, with no run_by predicate (read live today: cron 746, the recert runner,
--   "IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN RETURN"; the same guard in
--   ottoq_dial_experiment_runner, ottoq_dial_pair, ottoq_throughput_sweep_arm and ottoq_throughput_sweep_runner). So a
--   setting on a production_live run is never in force while an arm runs, exactly 0605 §1(g)'s argument for demo runs.
--
-- ══ §4 WHAT IT DELIBERATELY DOES NOT DO ═════════════════════════════════════════════════════════════════════════════
--
--   * No persistence across runs: a production setting lifts when its run ends, as 0605 §4 decided for demo runs.
--   * No new credential, and passcode sessions and issued keys keep working on demo runs exactly as before.
--   * No shield probe on owner writes (the inventory's item 7): the contract checks and the gate are the owner door's.
--   * The cockpit chat seat (ottoq-ottocommand, finding S-03) is not touched.
--
-- ══ §5 VALIDATED ON A SCRATCH CLUSTER ═══════════════════════════════════════════════════════════════════════════════
--
--   tests/test_ottocommand_executor_sql.py builds the stub engine with 0559, 0560, 0605-0608 and 0700 applied from their
--   files, asserts every body this file reads is byte for byte the live one (md5), reproduces (a)-(d) before this file,
--   applies it, and drives the gate, the plan-hash rule, the stamps, the guard, the backstop and the grants.
--
-- ══ §6 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE every definition in ottoq_schema_snapshots WHERE label = '0721_pre' (the three-argument
--   ottoq_owner_command, ottoq_agent_call, ottoq_owner_command_reply, ottoq_agent_read_whoami,
--   ottoq_owner_commands_guard). The four-argument form, the two functions and the backstop trigger are then unread and
--   may stay; the two columns may stay (NULL is their old meaning). DELETE this file's ottoq_cert_lineage row.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0721 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies this file was written against, and the premises it relies on ──
DO $premises$
DECLARE v_bad text; v_src text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0721_a_signed_in_owner_changes_production_under_their_own_name') THEN
    RAISE EXCEPTION '0721 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0700_an_owner_signs_in_and_connects_their_own_agent') THEN
    RAISE EXCEPTION '0721 P1: 0700 (an owner signs in) is not applied; a person exists only through it';
  END IF;
  -- md5(pg_get_functiondef), read on the live catalog 2026-10-14 and on a scratch cluster with 0559-0608 and 0700
  -- applied from their files over the stub engine: identical, every one
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)',                                  'ae935f897ee25b6db3eacfbb9215797d'),
      ('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)',                 '533b275b976b5287f1f48b245132139f'),
      ('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)',                'bd0c86d127a2a84903fa2fb812ee1ac5'),
      ('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)',                        '53aa8a6690ecc6274e4cd1dc73972006'),
      ('public.ottoq_owner_commands_guard()',                                                  '758eff5a6a274b176573c6674840dc55')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR md5(pg_get_functiondef(to_regprocedure(f))) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 P1: not the body this file was written against (re-measure before applying): %', v_bad;
  END IF;
  -- the four reads OTTO-Command now offers an owner's agent (edge-functions/_shared/ottocommand_owner.ts), whose scope
  -- was read in these bodies: depot_status counts only the token's fleet, vehicle_card and recent_decisions keep to it
  -- through ottoq_agent_vehicle_in_scope and a fleet filter, stall_availability carries no vehicle id, name or owner.
  -- A change to any of them is a reason to read its scope again before OTTO-Command reads it for an owner.
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_agent_read_depot(public.ottoq_agent_principals)',                         '9c3ef3ebfdfc1452d430e922aedd6370'),
      ('public.ottoq_agent_read_vehicle(public.ottoq_agent_principals,jsonb)',                 'a19d1d66275fd3e459fb3ec4263634e5'),
      ('public.ottoq_agent_read_decisions(public.ottoq_agent_principals,jsonb)',               '7d1f7e652d8c840b95b52286d78cbae4'),
      ('public.ottoq_agent_read_stalls(public.ottoq_agent_principals,jsonb)',                  '17156c4b0f42b11af1ec3d0e9d511b03'),
      ('public.ottoq_agent_vehicle_in_scope(public.ottoq_agent_principals,uuid)',              '339598e6cad0c62d1d62aabdde5ded52')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR md5(pg_get_functiondef(to_regprocedure(f))) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 P1: a read OTTO-Command offers is not the body whose scope was read: %', v_bad;
  END IF;
  -- production applies what an owner sets (0718): otherwise a production command accepted here would be a placebo
  v_src := (SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
              FROM pg_proc p WHERE p.oid = to_regprocedure('twin.ottoq_world_advance()'));
  IF v_src IS NULL OR strpos(v_src, 'ottoq.ottoq_owner_orders_tick(v_run.sim_run_id') = 0
     OR v_src !~ 'run_by\s*=\s*''production_live''' THEN
    RAISE EXCEPTION '0721 P1: production''s world step does not apply owner settings on a production_live run (0718)';
  END IF;
  IF to_regclass('public.ottoq_oauth_grants') IS NULL OR to_regclass('public.ottoq_owner_accounts') IS NULL THEN
    RAISE EXCEPTION '0721 P1: 0700''s grants or accounts table is missing';
  END IF;
END $premises$;

-- ── P2: nothing this file creates exists yet, and the registry guard is clean before it is touched ──
DO $fresh$
DECLARE v_block int;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'ottoq_owner_commands' AND column_name IN ('acting_person', 'via')) THEN
    RAISE EXCEPTION '0721 P2: ottoq_owner_commands already has acting_person or via';
  END IF;
  IF to_regprocedure('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_write_gate(public.ottoq_agent_principals,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_acting_person(public.ottoq_agent_principals)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_commands_production_person()') IS NOT NULL THEN
    RAISE EXCEPTION '0721 P2: a function this file creates already exists';
  END IF;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0721 P2: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $fresh$;

-- ── the rollback snapshot of the five bodies this file replaces ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0721_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure,
                 'public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure,
                 'public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure,
                 'public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure,
                 'public.ottoq_owner_commands_guard()'::regprocedure);

-- ══ 1. the two columns ══════════════════════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.ottoq_owner_commands
  ADD COLUMN acting_person text,
  ADD COLUMN via text,
  ADD CONSTRAINT ottoq_owner_commands_acting_person_check CHECK (
    acting_person IS NULL OR (acting_person = lower(btrim(acting_person)) AND acting_person ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  ADD CONSTRAINT ottoq_owner_commands_via_check CHECK (via IS NULL OR via IN ('ottocommand', 'direct'));

COMMENT ON COLUMN public.ottoq_owner_commands.acting_person IS
'0721. The person the command is recorded under: the email of the OTTOYARD account (ottoq_owner_accounts, through ottoq_oauth_grants) behind an agent signed in through 0700, while that account is active and owns the agent''s fleet. NULL for a passcode session or an issued key, which name no one. On a production_live run an applied command always has one (ottoq_owner_commands_production_person_trg).';
COMMENT ON COLUMN public.ottoq_owner_commands.via IS
'0721. ottocommand: the command came through OTTO-Command (transport ask: POST /v1/ask or the MCP tool ask_ottocommand), which read the owner''s words and called the tool with the owner''s own token. direct: the agent called the tool itself (MCP or REST). NULL on rows written before 0721; never backfilled.';

-- ══ 2. who the person is, and whether this agent may change settings on this run ═══════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_owner_acting_person(p_agent public.ottoq_agent_principals)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  -- 0721. The person behind an agent: the OTTOYARD account an agent signed in through (0700), only while the account is
  -- active and owns the agent's fleet at the agent's depot. A passcode session or an issued key names no one: NULL.
  SELECT a.email
    FROM public.ottoq_oauth_grants g
    JOIN public.ottoq_owner_accounts a ON a.account_id = g.account_id
   WHERE p_agent.origin = 'oauth' AND p_agent.status = 'active'
     AND g.principal_id = p_agent.principal_id
     AND a.status = 'active'
     AND a.fleet_operator_id = p_agent.fleet_operator_id
     AND a.depot_id = p_agent.depot_id
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_write_gate(p_agent public.ottoq_agent_principals, p_run jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721. May this agent change its own cars' settings on this run (p_run: ottoq_agent_live_run's answer), and under
   whose name. A demo run, as 0605 allowed. A production run only for an agent signed in to its owner's OTTOYARD account,
   so that every production change is recorded under a person (CLAUDE.md rule 10); on one, a lower charge limit takes a
   preview and its plan hash (rule 9). Every refusal says why and what to do instead. Read by ottoq_owner_command and
   by whoami, so OTTO-Command knows before it acts. */
DECLARE
  v_person text := public.ottoq_owner_acting_person(p_agent);
  v_kind   text := CASE WHEN p_run IS NULL THEN NULL
                        WHEN p_run ->> 'run_by' = 'operator_demo' THEN 'demo'
                        WHEN p_run ->> 'run_by' = 'production_live' THEN 'production'
                        ELSE 'other' END;
BEGIN
  IF v_kind = 'demo' THEN
    RETURN jsonb_strip_nulls(jsonb_build_object('allowed', true, 'run_kind', 'demo', 'person', v_person,
      'message', 'A demo run is live: settings apply to it and lift when it ends.'));
  ELSIF v_kind = 'production' AND v_person IS NOT NULL THEN
    RETURN jsonb_build_object('allowed', true, 'run_kind', 'production', 'person', v_person, 'lower_limit_needs_preview', true,
      'message', format('A production run is live. Changes are recorded under %s and lift when the run ends. Lowering how full a car charges takes a preview first, then an apply with the preview''s plan_hash.', v_person));
  ELSIF v_kind = 'production' THEN
    RETURN jsonb_build_object('allowed', false, 'run_kind', 'production', 'code', 'production_needs_a_person',
      'message', CASE p_agent.origin
        WHEN 'passcode' THEN 'The live run at the twin depot is a production run, and a passcode session can read your cars there but not change them: in production every change is recorded under the person who made it, and a passcode names no one.'
        WHEN 'oauth'    THEN 'The live run at the twin depot is a production run, and the OTTOYARD account this agent signed in with is not linked to this fleet, so there is no person to record the change under.'
        ELSE 'The live run at the twin depot is a production run, and an issued key names no person: in production every change is recorded under the person who made it.' END,
      'hint', 'Sign your agent in to your OTTOYARD account (PERSONAL_AGENT.md section 10) and send it again. Reading your cars works as it is.');
  ELSIF v_kind IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'no_live_demo',
      'message', 'No demo run is live at the twin depot. Start one in OTTO-TWIN; what you set applies to that run and resets when it ends.');
  END IF;
  RETURN jsonb_build_object('allowed', false, 'run_kind', 'other', 'code', 'no_live_demo',
    'message', 'The live run at the twin depot is not a demo run, and owner settings apply only to demo runs.');
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_owner_acting_person(public.ottoq_agent_principals) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_owner_write_gate(public.ottoq_agent_principals, jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- ══ 3. the owner command learns its door, its person and production ═════════════════════════════════════════════════
--
-- The live body, by anchored substitution, under a four-argument signature. Every anchor is asserted to occur exactly
-- once in the definition read here; the md5 premise above pins the definition itself.
DO $command$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure);
  v_new text;
  v_pair text[];
  v_pairs text[][] := ARRAY[
    -- a. the signature: the door the command came through
    ARRAY[E'p_tool text, p_args jsonb)\n RETURNS jsonb\n',
          E'p_tool text, p_args jsonb, p_via text)\n RETURNS jsonb\n'],
    -- b. the declarations
    ARRAY[E'  v_cphrase  text;\nBEGIN\n',
          E'  v_cphrase  text;\n'
       || E'  --: 0721: who may change settings on this run and under whose name, which door, and whether a limit goes down\n'
       || E'  v_gate       jsonb;\n'
       || E'  v_production boolean := false;\n'
       || E'  v_person     text;\n'
       || E'  v_via        text := CASE WHEN p_via = ''ask'' THEN ''ottocommand'' ELSE ''direct'' END;\n'
       || E'  v_lowers     boolean := false;\n'
       || E'BEGIN\n'],
    -- c. the gate, beside 0605's demo test
    ARRAY[E'  v_demo := v_run IS NOT NULL AND v_run ->> ''run_by'' = ''operator_demo'';\n',
          E'  v_demo := v_run IS NOT NULL AND v_run ->> ''run_by'' = ''operator_demo'';\n'
       || E'  --: 0721: a demo run, or a production run for an agent signed in to its owner''s account (ottoq_owner_write_gate)\n'
       || E'  v_gate := public.ottoq_owner_write_gate(p_agent, v_run);\n'
       || E'  v_production := COALESCE(v_gate ->> ''run_kind'', '''') = ''production'';\n'
       || E'  v_person := v_gate ->> ''person'';\n'],
    -- d. the gate's answer replaces the demo-only refusal (its no-run and other-run words are 0605's, unchanged)
    ARRAY[E'  IF v_refusal IS NULL AND NOT v_demo THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''no_live_demo'',\n'
       || E'      ''message'', CASE WHEN v_run IS NULL THEN ''No demo run is live at the twin depot. Start one in OTTO-TWIN; what you set applies to that run and resets when it ends.''\n'
       || E'                      ELSE ''The live run at the twin depot is not a demo run, and owner settings apply only to demo runs.'' END);\n'
       || E'  END IF;\n',
          E'  --: 0721: the gate: a demo run, or a production run under a signed-in person; why not, and what to do, otherwise\n'
       || E'  IF v_refusal IS NULL AND NOT COALESCE((v_gate ->> ''allowed'')::boolean, false) THEN\n'
       || E'    v_refusal := jsonb_strip_nulls(jsonb_build_object(''code'', v_gate ->> ''code'', ''message'', v_gate ->> ''message'',\n'
       || E'                                                      ''hint'', v_gate ->> ''hint''));\n'
       || E'  END IF;\n'],
    -- e. a car whose limit goes down
    ARRAY[E'      v_before := LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling));\n',
          E'      v_before := LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling));\n'
       || E'      IF v_pct < v_before THEN v_lowers := true; END IF;   --: 0721: this command lowers how full the car charges\n'],
    -- f. on production, a lower limit is applied only with the plan hash its preview returned (rule 9)
    ARRAY[E'      ''message'', ''The plan changed since it was previewed (a car''''s settings moved). Nothing was applied. Read the new plan and confirm it with its hash.'');\n'
       || E'  END IF;\n',
          E'      ''message'', ''The plan changed since it was previewed (a car''''s settings moved). Nothing was applied. Read the new plan and confirm it with its hash.'');\n'
       || E'  END IF;\n'
       || E'  --: 0721 (CLAUDE.md rule 9: a lower limit is the owner''s, "set verified and confirmed"): on a production run, lowering\n'
       || E'  --: how full a car charges takes two steps. The preview shows the plan; only an apply bound to its plan_hash makes it.\n'
       || E'  IF v_refusal IS NULL AND v_production AND v_mode = ''apply'' AND v_tool = ''set_charge_limit'' AND v_lowers\n'
       || E'     AND v_expect IS NULL THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''confirm_required'',\n'
       || E'      ''message'', ''This is a production run, so lowering how full a car charges takes two steps: preview it (mode "preview"), show your person the plan, and apply it with the plan_hash the preview returns. Nothing was changed.'',\n'
       || E'      ''hint'', ''Raising a limit, or clearing it back to full, needs no preview.'');\n'
       || E'  END IF;\n'],
    -- g. the receipt names the run that ends it
    ARRAY[E'E''\\nThis lasts until the demo run ends or you undo it.''',
          E'CASE WHEN v_production THEN E''\\nThis lasts until the production run ends or you undo it.'' ELSE E''\\nThis lasts until the demo run ends or you undo it.'' END'],
    -- h. the record: the person and the door, on every row
    ARRAY[E'       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id)\n',
          E'       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id, acting_person, via)\n'],
    ARRAY[E'       CASE WHEN v_tool = ''undo_command'' AND v_target.command_id IS NOT NULL THEN v_target.command_id END)\n',
          E'       CASE WHEN v_tool = ''undo_command'' AND v_target.command_id IS NOT NULL THEN v_target.command_id END,\n'
       || E'       v_person, v_via)\n'],
    ARRAY[E'       vehicles, effects, refusal, summary, plan_hash)\n',
          E'       vehicles, effects, refusal, summary, plan_hash, acting_person, via)\n'],
    ARRAY[E'Nothing was applied; send it again.'', v_hash)\n',
          E'Nothing was applied; send it again.'', v_hash, v_person, v_via)\n']];
  v_n int;
BEGIN
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721: an anchor of ottoq_owner_command occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 120);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
END $command$;

REVOKE ALL ON FUNCTION public.ottoq_owner_command(public.ottoq_agent_principals, text, jsonb, text) FROM PUBLIC, anon, authenticated, service_role;

--: the three-argument form keeps its name, grants and signature for any direct caller, and is the four-argument one
CREATE OR REPLACE FUNCTION public.ottoq_owner_command(p_agent public.ottoq_agent_principals, p_tool text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721. The owner command's body is ottoq_owner_command(principal, tool, args, p_via), which also records the door a
   command came through and the person behind it. ottoq_agent_call calls that form with its transport; a caller of this
   form is recorded as via 'direct'. */
BEGIN
  RETURN public.ottoq_owner_command(p_agent, p_tool, p_args, NULL::text);
END $fn$;

-- ══ 4. the dispatcher passes its transport ══════════════════════════════════════════════════════════════════════════
DO $call$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure);
  c_old constant text := E'      ELSE public.ottoq_owner_command(v_agent, v_tool, v_args)\n';
  c_new constant text := E'      ELSE public.ottoq_owner_command(v_agent, v_tool, v_args, v_transport)   --: 0721: the door it came through\n';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0721: ottoq_agent_call''s owner-command line occurs % times, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $call$;

-- ══ 5. the receipt shows the person, the door and the run that ends it ══════════════════════════════════════════════
DO $reply$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure);
  c_old1 constant text := E'      ''lifted_at'', p_c.lifted_at, ''lifted_reason'', p_c.lifted_reason),\n';
  c_new1 constant text := E'      ''lifted_at'', p_c.lifted_at, ''lifted_reason'', p_c.lifted_reason,\n'
                       || E'      --: 0721: the person the command is recorded under, and whether OTTO-Command sent it\n'
                       || E'      ''acting_person'', p_c.acting_person, ''via'', p_c.via),\n';
  c_old2 constant text := E'                    THEN ''Lasts until this demo run ends or you undo it; a stop or reset of the twin puts every car back to baseline.'' END))\n';
  c_new2 constant text := E'                    THEN CASE WHEN (SELECT r.run_by FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_c.sim_run_id) = ''production_live''\n'
                       || E'                              THEN ''Lasts until this production run ends or you undo it; when the run ends every car goes back to its baseline.''\n'
                       || E'                              ELSE ''Lasts until this demo run ends or you undo it; a stop or reset of the twin puts every car back to baseline.'' END END))\n';
  v_n1 int; v_n2 int;
BEGIN
  v_n1 := (length(v_def) - length(replace(v_def, c_old1, ''))) / length(c_old1);
  v_n2 := (length(v_def) - length(replace(v_def, c_old2, ''))) / length(c_old2);
  IF v_n1 <> 1 OR v_n2 <> 1 THEN
    RAISE EXCEPTION '0721: ottoq_owner_command_reply''s anchors occur % and % times, expected exactly 1 each', v_n1, v_n2;
  END IF;
  EXECUTE replace(replace(v_def, c_old1, c_new1), c_old2, c_new2);
END $reply$;

-- ══ 6. whoami says whether this agent may change settings now, and under whose name ═════════════════════════════════
DO $whoami$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure);
  c_old1 constant text := E'      ''live_demo_run'', CASE WHEN v_run ->> ''run_by'' = ''operator_demo'' THEN v_run -> ''sim_run_id'' END,\n';
  c_new1 constant text := E'      ''live_demo_run'', CASE WHEN v_run ->> ''run_by'' = ''operator_demo'' THEN v_run -> ''sim_run_id'' END,\n'
                       || E'      --: 0721: a production run, and the gate: may this agent change settings now, under whose name, and why not\n'
                       || E'      ''live_production_run'', CASE WHEN v_run ->> ''run_by'' = ''production_live'' THEN v_run -> ''sim_run_id'' END,\n'
                       || E'      ''changes'', public.ottoq_owner_write_gate(p_agent, v_run),\n';
  c_old2 constant text := E'undoable, and lifted when the demo run ends.'',\n';
  c_new2 constant text := E'undoable, and lifted when the run ends. On a production run only an agent signed in to its owner''''s OTTOYARD account may change them, each change is recorded under that person, and a lower charge limit is previewed first and applied with the preview''''s plan_hash.'',\n';
  v_n1 int; v_n2 int;
BEGIN
  v_n1 := (length(v_def) - length(replace(v_def, c_old1, ''))) / length(c_old1);
  v_n2 := (length(v_def) - length(replace(v_def, c_old2, ''))) / length(c_old2);
  IF v_n1 <> 1 OR v_n2 <> 1 THEN
    RAISE EXCEPTION '0721: whoami''s anchors occur % and % times, expected exactly 1 each', v_n1, v_n2;
  END IF;
  EXECUTE replace(replace(v_def, c_old1, c_new1), c_old2, c_new2);
END $whoami$;

-- ══ 7. the guard: who and which door are as immutable as what was commanded ═════════════════════════════════════════
DO $guard$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure);
  c_old1 constant text := E'NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at)';
  c_new1 constant text := E'NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at, NEW.acting_person, NEW.via)';
  c_old2 constant text := E'OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at)';
  c_new2 constant text := E'OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at, OLD.acting_person, OLD.via)';
  v_n1 int; v_n2 int;
BEGIN
  v_n1 := (length(v_def) - length(replace(v_def, c_old1, ''))) / length(c_old1);
  v_n2 := (length(v_def) - length(replace(v_def, c_old2, ''))) / length(c_old2);
  IF v_n1 <> 1 OR v_n2 <> 1 THEN
    RAISE EXCEPTION '0721: ottoq_owner_commands_guard''s tuples occur % and % times, expected exactly 1 each', v_n1, v_n2;
  END IF;
  EXECUTE replace(replace(v_def, c_old1, c_new1), c_old2, c_new2);
END $guard$;

-- ══ 8. the backstop: no applied production command without a person (rule 10), whoever writes it ══════════════════
CREATE OR REPLACE FUNCTION public.ottoq_owner_commands_production_person()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721. CLAUDE.md rule 10: in production no setting changes except under a person's name. ottoq_owner_command applies a
   production command only for a signed-in person (ottoq_owner_write_gate); this refuses the row itself if any writer
   ever records an applied production command without one. */
BEGIN
  IF NEW.outcome = 'applied' AND NEW.acting_person IS NULL AND NEW.sim_run_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id AND r.run_by = 'production_live') THEN
    RAISE EXCEPTION 'owner command on production run %: an applied change needs the person it is recorded under (acting_person)',
      NEW.sim_run_id USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_owner_commands_production_person() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER ottoq_owner_commands_production_person_trg
  BEFORE INSERT ON public.ottoq_owner_commands
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_commands_production_person();

-- ══ V1: the bodies say what this file says they do ══════════════════════════════════════════════════════════════════
DO $v1$
DECLARE
  v_cmd   text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)'::regprocedure);
  v_three text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure);
  v_call  text := pg_get_functiondef('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure);
  v_reply text := pg_get_functiondef('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure);
  v_who   text := pg_get_functiondef('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure);
  v_guard text := pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure);
BEGIN
  IF strpos(v_cmd, 'v_gate := public.ottoq_owner_write_gate(p_agent, v_run);') = 0
     OR strpos(v_cmd, '''confirm_required''') = 0
     OR strpos(v_cmd, 'undoes_command_id, acting_person, via)') = 0
     OR strpos(v_cmd, 'IF v_refusal IS NULL AND NOT v_demo THEN') > 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the four-argument owner command is not the patched body';
  END IF;
  IF strpos(v_three, 'RETURN public.ottoq_owner_command(p_agent, p_tool, p_args, NULL::text);') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the three-argument owner command does not delegate';
  END IF;
  IF strpos(v_call, 'public.ottoq_owner_command(v_agent, v_tool, v_args, v_transport)') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: ottoq_agent_call does not pass its transport';
  END IF;
  IF strpos(v_reply, '''acting_person'', p_c.acting_person, ''via'', p_c.via') = 0
     OR strpos(v_who, '''changes'', public.ottoq_owner_write_gate(p_agent, v_run)') = 0
     OR strpos(v_guard, 'NEW.acting_person, NEW.via)') = 0 OR strpos(v_guard, 'OLD.acting_person, OLD.via)') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the receipt, whoami or the guard is not patched';
  END IF;
  RAISE NOTICE '0721 V1 PASSED';
END $v1$;

-- ══ V2: no client role reaches anything new; the gateway's one door is unchanged ════════════════════════════════════
DO $v2$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(f || ' ' || r, ', ') INTO v_bad
    FROM unnest(ARRAY['public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)',
                      'public.ottoq_owner_write_gate(public.ottoq_agent_principals,jsonb)',
                      'public.ottoq_owner_acting_person(public.ottoq_agent_principals)',
                      'public.ottoq_owner_commands_production_person()']) f
   CROSS JOIN unnest(ARRAY['anon', 'authenticated', 'service_role']) r
   WHERE has_function_privilege(r, f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 V2 FAILED: a client role can execute %', v_bad;
  END IF;
  IF NOT has_function_privilege('service_role', 'public.ottoq_agent_call(text,text,jsonb,text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '0721 V2 FAILED: the gateway (service_role) lost ottoq_agent_call';
  END IF;
  RAISE NOTICE '0721 V2 PASSED';
END $v2$;

-- ══ V3: a production session at the twin depot, probed end to end through the dispatcher, then rolled back ══════════
--
-- Everything it writes -- a paused production_live run copied from the newest twin-depot run (paused, so the
-- one-running-run index never meets it; the newest run, so ottoq_agent_live_run answers with it), a probe sign-in (client,
-- account, connection, access token), a passcode session, an issued key, their commands and settings, the ledger rows --
-- is in a block that raises at its end and is rolled back. Only the answers, held in variables, survive it.
DO $v3$
DECLARE
  c_twin   constant uuid := '11111111-1111-1111-1111-111111111111';
  c_email  constant text := 'v0721.probe@ottoyard.invalid';
  v_run    uuid := gen_random_uuid();
  v_tpl    uuid;
  v_cols   text;
  v_fleet  uuid;
  v_ctr    jsonb;
  v_pct    numeric;
  v_client text := 'oqc_' || md5('0721-client' || clock_timestamp()::text);
  v_acct   uuid := gen_random_uuid();
  v_pid    uuid;
  v_oauth  text := 'oqt_' || md5('0721-oauth-a' || clock_timestamp()::text) || md5('0721-oauth-b' || clock_timestamp()::text);
  v_pass   text := 'oqs_' || md5('0721-pass-a' || clock_timestamp()::text) || md5('0721-pass-b' || clock_timestamp()::text);
  v_key    text;
  v_car    uuid;
  r_whoami jsonb; r_lower jsonb; r_prev jsonb; r_apply jsonb; r_raise jsonb; r_pass jsonb; r_key jsonb; r_demo jsonb;
  v_target numeric;
  v_guard  text := 'not reached';
  v_back   text := 'not reached';
  v_cmd    uuid;
BEGIN
  SELECT r.sim_run_id INTO v_tpl FROM public.ottoq_sim_runs r WHERE r.depot_id = c_twin ORDER BY r.started_at DESC LIMIT 1;
  --: the twin depot's owner with the most cars and a contract whose range has room below its top
  SELECT v.fleet_operator_id INTO v_fleet
    FROM public.vehicles v
   WHERE (v.current_depot_id = c_twin OR v.home_depot_id = c_twin) AND v.fleet_operator_id IS NOT NULL
     AND (public.ottoq_owner_contract(v.fleet_operator_id, now()) ->> 'min_charge_pct')::numeric
         < (public.ottoq_owner_contract(v.fleet_operator_id, now()) ->> 'max_charge_pct')::numeric
   GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1;
  IF v_tpl IS NULL OR v_fleet IS NULL THEN
    RAISE EXCEPTION '0721 V3: no twin-depot run to copy, or no owner at the twin depot with a contract range to probe';
  END IF;
  v_ctr := public.ottoq_owner_contract(v_fleet, now());
  v_pct := GREATEST((v_ctr ->> 'min_charge_pct')::numeric, (v_ctr ->> 'max_charge_pct')::numeric - 5);
  SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position) INTO v_cols
    FROM information_schema.columns c
   WHERE c.table_schema = 'public' AND c.table_name = 'ottoq_sim_runs'
     AND c.column_name NOT IN ('sim_run_id', 'status', 'started_at', 'run_by')
     AND COALESCE(c.column_default, '') NOT LIKE 'nextval(%' AND c.is_identity = 'NO' AND c.is_generated = 'NEVER';

  BEGIN
    EXECUTE format('INSERT INTO public.ottoq_sim_runs (sim_run_id, status, started_at, run_by, %1$s) '
                   'SELECT $1, ''paused'', clock_timestamp(), ''production_live'', %1$s FROM public.ottoq_sim_runs WHERE sim_run_id = $2',
                   v_cols) USING v_run, v_tpl;
    INSERT INTO public.ottoq_oauth_clients (client_id, client_name, grant_types)
    VALUES (v_client, '0721 probe', ARRAY['urn:ietf:params:oauth:grant-type:device_code']);
    INSERT INTO public.ottoq_owner_accounts (account_id, email, fleet_operator_id, note)
    VALUES (v_acct, c_email, v_fleet, '0721 V3 probe, rolled back');
    v_pid := public.ottoq_oauth_connect(v_acct, v_client, 'ottoyard:owner', 'https://probe.invalid/account/mcp', 'device_code');
    INSERT INTO public.ottoq_oauth_tokens (token_hash, kind, principal_id, expires_at)
    VALUES (public.ottoq_oauth_sha256(v_oauth), 'access', v_pid, now() + interval '10 minutes');
    INSERT INTO public.ottoq_agent_principals (name, kind, depot_id, fleet_operator_id, capabilities, token_hash, token_prefix,
                                              origin, display_name, expires_at, note)
    VALUES ('v0721-probe-passcode', 'personal', c_twin, v_fleet, ARRAY['note', 'owner_settings', 'read'],
            public.ottoq_oauth_sha256(v_pass), left(v_pass, 12), 'passcode', '0721 probe', now() + interval '10 minutes',
            '0721 V3 probe, rolled back');
    v_key := public.ottoq_agent_issue_token('v0721-probe-key', 'personal', ARRAY['read', 'note', 'owner_settings'], v_fleet,
                                            c_twin, '0721 V3 probe, rolled back', 600, 20) ->> 'token';
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.fleet_operator_id = v_fleet AND (v.current_depot_id = c_twin OR v.home_depot_id = c_twin)
     ORDER BY v.display_name, v.id LIMIT 1;

    r_whoami := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_oauth), 'whoami', '{}'::jsonb, 'mcp', '{}'::jsonb);
    -- the person lowers the limit in one call: refused, and the refusal is recorded under the person
    r_lower := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_oauth), 'set_charge_limit',
                 jsonb_build_object('vehicles', 'all', 'percent', v_pct), 'mcp', '{}'::jsonb);
    -- previewed through OTTO-Command, then applied with the preview's plan hash
    r_prev := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_oauth), 'set_charge_limit',
                jsonb_build_object('vehicles', 'all', 'percent', v_pct, 'mode', 'preview'), 'ask', '{}'::jsonb);
    r_apply := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_oauth), 'set_charge_limit',
                 jsonb_build_object('vehicles', 'all', 'percent', v_pct, 'mode', 'apply',
                                    'expect_plan_hash', r_prev #>> '{data,command,plan_hash}'), 'ask', '{}'::jsonb);
    v_target := public.ottoq_effective_target_soc_at(v_car, now());
    -- the guard holds the person and the door; the backstop refuses an applied production row with no person
    v_cmd := (r_apply #>> '{data,command,command_id}')::uuid;
    BEGIN
      UPDATE public.ottoq_owner_commands SET via = 'direct' WHERE command_id = v_cmd;
      v_guard := 'updated';
    EXCEPTION WHEN insufficient_privilege THEN v_guard := 'refused';
    END;
    BEGIN
      INSERT INTO public.ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool,
                                               mode, outcome, summary)
      VALUES (v_pid, '0721 probe', v_fleet, c_twin, v_run, 'clear_charge_limit', 'apply', 'applied', '0721 backstop probe');
      v_back := 'inserted';
    EXCEPTION WHEN insufficient_privilege THEN v_back := 'refused';
    END;
    -- raising back to full needs no preview
    r_raise := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_oauth), 'clear_charge_limit',
                 jsonb_build_object('vehicles', 'all'), 'rest', '{}'::jsonb);
    -- a passcode session and an issued key name no person: refused in production
    r_pass := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_pass), 'set_charge_limit',
                jsonb_build_object('vehicles', 'all', 'percent', v_pct, 'mode', 'preview'), 'mcp', '{}'::jsonb);
    r_key := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_key), 'hold_vehicle',
               jsonb_build_object('vehicles', 'all', 'for_minutes', 30), 'rest', '{}'::jsonb);
    -- and on a demo run the passcode session works as before, with no person and its door recorded
    UPDATE public.ottoq_sim_runs SET run_by = 'operator_demo' WHERE sim_run_id = v_run;
    r_demo := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_pass), 'hold_vehicle',
                jsonb_build_object('vehicles', 'all', 'for_minutes', 30), 'ask', '{}'::jsonb);
    RAISE EXCEPTION USING ERRCODE = 'OQ721', MESSAGE = '0721 V3 probe rolled back';
  EXCEPTION WHEN SQLSTATE 'OQ721' THEN NULL;
  END;

  IF r_whoami #>> '{data,owner,changes,allowed}' IS DISTINCT FROM 'true'
     OR r_whoami #>> '{data,owner,changes,person}' IS DISTINCT FROM c_email
     OR r_whoami #>> '{data,owner,live_production_run}' IS DISTINCT FROM v_run::text THEN
    RAISE EXCEPTION '0721 V3 FAILED: whoami does not say a signed-in person may change production: %', r_whoami -> 'data' -> 'owner';
  END IF;
  IF (r_lower ->> 'http_status')::int <> 422 OR r_lower #>> '{error,code}' IS DISTINCT FROM 'confirm_required'
     OR r_lower #>> '{data,command,acting_person}' IS DISTINCT FROM c_email OR r_lower #>> '{data,command,via}' IS DISTINCT FROM 'direct' THEN
    RAISE EXCEPTION '0721 V3 FAILED: a production limit lowered in one call was not refused confirm_required under the person: %', r_lower;
  END IF;
  IF r_prev #>> '{data,outcome}' IS DISTINCT FROM 'previewed' OR r_prev #>> '{data,command,via}' IS DISTINCT FROM 'ottocommand' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the preview through OTTO-Command: %', r_prev;
  END IF;
  IF (r_apply ->> 'http_status')::int <> 201 OR r_apply #>> '{data,outcome}' IS DISTINCT FROM 'applied'
     OR r_apply #>> '{data,command,acting_person}' IS DISTINCT FROM c_email
     OR r_apply #>> '{data,command,via}' IS DISTINCT FROM 'ottocommand'
     OR strpos(r_apply #>> '{data,summary}', 'until the production run ends') = 0
     OR strpos(r_apply #>> '{data,expires}', 'production run') = 0 THEN
    RAISE EXCEPTION '0721 V3 FAILED: the confirmed production limit was not applied under the person through OTTO-Command: %', r_apply;
  END IF;
  IF v_target IS DISTINCT FROM v_pct THEN
    RAISE EXCEPTION '0721 V3 FAILED: the engine reads % as the car''s target, not the owner''s confirmed %', v_target, v_pct;
  END IF;
  IF v_guard <> 'refused' OR v_back <> 'refused' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the guard (%) or the production backstop (%) let the row through', v_guard, v_back;
  END IF;
  IF r_raise #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_raise #>> '{data,command,via}' IS DISTINCT FROM 'direct' THEN
    RAISE EXCEPTION '0721 V3 FAILED: clearing the limit in production needed more than one call: %', r_raise;
  END IF;
  IF r_pass #>> '{error,code}' IS DISTINCT FROM 'production_needs_a_person' OR r_pass #>> '{data,outcome}' IS DISTINCT FROM 'refused'
     OR r_key #>> '{error,code}' IS DISTINCT FROM 'production_needs_a_person' THEN
    RAISE EXCEPTION '0721 V3 FAILED: a passcode session or an issued key was not refused in production: % / %', r_pass, r_key;
  END IF;
  IF r_demo #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_demo #> '{data,command}' ? 'acting_person'
     OR r_demo #>> '{data,command,via}' IS DISTINCT FROM 'ottocommand' THEN
    RAISE EXCEPTION '0721 V3 FAILED: a passcode session on a demo run: %', r_demo;
  END IF;
  -- nothing the probe wrote survived it
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run)
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_accounts WHERE account_id = v_acct)
     OR EXISTS (SELECT 1 FROM public.ottoq_agent_principals WHERE name IN ('v0721-probe-passcode', 'v0721-probe-key'))
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_commands WHERE acting_person = c_email OR sim_run_id = v_run) THEN
    RAISE EXCEPTION '0721 V3 FAILED: the probe left rows behind';
  END IF;
  RAISE NOTICE '0721 V3 PASSED: production at the twin depot takes a signed-in person (% on %), refuses a passcode and a key, and lowers a limit only with its preview''s plan hash', c_email, v_run;
END $v3$;

-- ══ V4: the run-scope registry stays clean ════════════════════════════════════════════════════════════════════════
DO $v4$
DECLARE v_block int; v_mine int;
BEGIN
  SELECT count(*) FILTER (WHERE severity = 'block'), count(*) FILTER (WHERE table_name = 'ottoq_owner_commands')
    INTO v_block, v_mine FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 OR v_mine > 0 THEN
    RAISE EXCEPTION '0721 V4 FAILED: the registry reports % block(s) and % row(s) for ottoq_owner_commands', v_block, v_mine;
  END IF;
  RAISE NOTICE '0721 V4 PASSED';
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0721_a_signed_in_owner_changes_production_under_their_own_name', false, false,
  'OTTO-Command as the filter and executor for owners'' agents (Chase 2026-10-14): ottoq_owner_commands records the '
  'person (acting_person, from a 0700 sign-in) and the door (via); production_live runs take owner commands from a '
  'signed-in person only, and a lower charge limit there only with its preview''s plan hash (rule 9); a backstop refuses '
  'an applied production command with no person (rule 10). Agent door only: ottoq_agent_call, ottoq_owner_command, its '
  'receipt, whoami and the owner-commands guard. No arm reaches any of them, and no arm can run while a run is live '
  '(every runner''s guard), so no certified run changes: FALSE/FALSE.',
  now());

COMMIT;
