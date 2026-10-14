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
--       counts an explicit apply as the confirmation, which holds on a demo run. In production a lower limit should be
--       applied only as the confirm of a preview OTTO-Q itself recorded, by the same agent and recently, so the plan
--       confirmed is the plan applied. A plan hash alone does not do that: it is md5 of data the token can already
--       read, so an agent could compute it and skip the preview.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   THREE COLUMNS on ottoq_owner_commands (class evidence in the run-scope registry: none is a run key, so check (a) has
--   nothing to register; V4 asserts the registry stays clean):
--     acting_person        the email of the OTTOYARD account behind an agent signed in through 0700, when that account is
--                          still linked and active and owns the agent's fleet; NULL for a passcode session or an issued key.
--     via                  who formed the command, set by the database from the gateway's transport and the binding (c
--                          below), never taken from an argument. NULL on rows written before this file (never backfilled).
--                            ottocommand  an OTTO-Command model read the owner's words and called the tool (transport
--                                         'ask': POST /v1/ask or the MCP tool ask_ottocommand, sent with text);
--                            confirm      the agent confirmed a recorded preview: the apply bound to it, and the row
--                                         names it in confirms_command_id. No model is involved, whether the confirm went
--                                         through the confirm door of POST /v1/ask or ask_ottocommand (transport
--                                         'confirm', which applyConfirms in ottocommand_owner.ts always uses) or as a
--                                         typed tool naming the preview;
--                            direct       the agent itself made the call (a typed tool over MCP or REST, or a confirm
--                                         object that bound to no preview and is recorded as a new one), or any other
--                                         caller.
--     confirms_command_id  the preview an apply confirmed (c below). A unique index: one preview confirms one apply.
--   All three join the immutability guard (ottoq_owner_commands_guard, md5 758eff5a6a274b176573c6674840dc55). Two CHECKs
--   make via 'confirm' and confirms_command_id one fact: a row that names a preview is an apply that applied (or changed
--   nothing) recorded as 'confirm', and a 'confirm' row always names one. A BEFORE INSERT backstop
--   (ottoq_owner_commands_backstop_trg) refuses, whoever writes the row, an APPLIED command on a production_live run
--   with no acting_person (rule 10), and a confirms_command_id that is not a preview by the same principal, on the same
--   run, of the same tool and plan hash, made at most 15 minutes before the apply.
--
--   THREE FUNCTIONS (and the backstop's trigger function)
--     ottoq_owner_acting_person(principal)  the person, as above (one primary-key probe per table).
--     ottoq_owner_confirm_binding(...)      is this apply the confirm of a recorded preview (c below), and if not, why.
--     ottoq_owner_write_gate(principal, run) may this agent change settings on this run, and under whose name:
--         operator_demo run                       allowed, as before (person stamped when there is one)
--         production_live run, a person           allowed, recorded under that person
--         production_live run, no person          refused production_needs_a_person, with why for each kind of
--                                                 credential and what to do (sign in; reading works as it is)
--         no run, or any other run                refused no_live_demo, the 0605 words unchanged
--
--   ottoq_owner_command GAINS ITS DOOR AND THE BINDING. The body moves, by anchored substitution of the live definition
--   (each anchor asserted to occur exactly once), to a four-argument form ottoq_owner_command(principal, tool, args, p_via):
--     a. the 0605 demo-only refusal is replaced by the gate's answer;
--     b. a command that LOWERS how full a car charges is marked: set_charge_limit below the limit in force, or an
--        undo_command that puts back a lower limit than the one in force;
--     c. THE BINDING. An apply must be the confirm of a recorded preview when (i) it lowers a limit on a production run,
--        (ii) it came through the confirm door (transport 'confirm'), or (iii) it names a preview (the new argument
--        confirms_command_id). It names its preview by expect_plan_hash and/or confirms_command_id, and binds only to an
--        ottoq_owner_commands row with outcome 'previewed', made by the SAME principal, on the same sim_run_id, of the
--        same tool and arguments (mode, note and the words of a hold's time aside), with the same plan_hash, created at
--        most 15 minutes ago, and not already confirmed. The apply records that row as confirms_command_id, and via
--        'confirm'. An apply that must bind and does not is NOT applied: it is recorded as a preview (mode 'preview',
--        outcome 'previewed', its own plan_hash and command id) and answered 422 confirm_required, with the reason
--        (not_named, no_recorded_preview, not_a_preview, preview_already_confirmed, preview_expired,
--        preview_does_not_match) and that preview's confirm object, so the next confirm can bind to it. A stale hash is
--        still plan_changed (0605). Raising or clearing a limit, holds, service orders, cancelling the owner's own
--        unstarted orders and an undo that does not lower a limit stay one call, as does any change on a demo run sent
--        as a typed tool that names no preview (0605 unchanged). A call through transport 'ask' that carries
--        expect_plan_hash or confirms_command_id is refused confirm_not_through_ottocommand: an OTTO-Command model never
--        confirms (the gateway strips both from what the model may send);
--     d. every command row records acting_person and via, and an applied confirm its confirms_command_id;
--     e. the receipt says "until the production run ends" on a production run.
--   The three-argument form is kept as a one-line delegate (via 'direct') for any direct caller. ottoq_agent_call
--   (md5 ae935f897ee25b6db3eacfbb9215797d) admits 'confirm' as a transport, passes its transport on, and answers a
--   confirm_required preview 422. The receipt (ottoq_owner_command_reply, md5 bd0c86d127a2a84903fa2fb812ee1ac5) shows
--   acting_person, via and confirms_command_id and the run's own end, and a preview's confirm object names the preview
--   (confirms_command_id). whoami (ottoq_agent_read_whoami, md5 53aa8a6690ecc6274e4cd1dc73972006) adds
--   live_production_run and the gate's answer as `changes`, so OTTO-Command knows before it acts.
--
--   WHAT OTTO-Q ENFORCES, AND WHAT IT CANNOT. It enforces preview-then-confirm by the same signed-in principal within 15
--   minutes, one apply per preview, recorded under the person that principal is signed in as. It cannot see a person's
--   yes: the confirm is relayed by the person's own agent, which holds the same token that made the preview, so an agent
--   that previews and confirms on its own reads here exactly like one that asked its person in between. A person-only
--   surface would close that: the confirm taken in the owner's own OTTOYARD account session (auth.uid()), as 0700
--   already does for approving a device sign-in. It is NOT built here, and is an open option for Chase.
--
--   Writes stay in the owner tables. Nothing here calls ottoq_policy_set or writes a setting: an owner's requirement is
--   the owner's (rule 9), applied at OTTO-Q's tick. No command can skip, defer or shorten a service OTTO-Q found needed:
--   cancel_service is 0605's, unchanged, and takes off only the owner's own orders (an engine-found need stays, a
--   started service finishes). Production still never self-tunes (rule 10): no agent writes a setting there, and every
--   owner change in production is recorded under the person whose agent made it.
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
--   applies it, and drives the gate, the binding (unbound, bound once, twice, expired, another principal, a hash with no
--   preview, an undo that lowers), the one-call changes, the doors, the stamps, the guard, the backstop and the grants.
--
-- ══ §6 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE every definition in ottoq_schema_snapshots WHERE label = '0721_pre' (the three-argument
--   ottoq_owner_command, ottoq_agent_call, ottoq_owner_command_reply, ottoq_agent_read_whoami,
--   ottoq_owner_commands_guard). The four-argument form, ottoq_owner_write_gate, ottoq_owner_acting_person and
--   ottoq_owner_confirm_binding are then unread and may stay. The backstop trigger keeps firing on every INSERT; it is
--   harmless after a rollback, because the restored three-argument body applies nothing on a production run (it refuses
--   every run but a demo run) and writes no confirms_command_id, so neither of the trigger's checks can fire on a row it
--   writes. To remove it: DROP TRIGGER ottoq_owner_commands_backstop_trg ON
--   public.ottoq_owner_commands. The three columns, their CHECKs and the unique index may stay (NULL is their old
--   meaning), but the restored guard no longer holds the columns immutable. DELETE this file's ottoq_cert_lineage row.
--
-- ══ §7 ORDER: THE GATEWAY FIRST ═════════════════════════════════════════════════════════════════════════════════
--
--   After this file a preview's confirm object carries confirms_command_id. The gateway in this branch accepts that
--   argument and sends a confirm with transport 'confirm'; a gateway built before it refuses an unknown argument
--   (additionalProperties false) and would answer a confirm 400. So deploy ottoq-agent-gateway from this branch first,
--   then apply this file. Against the database before this file the new gateway works as it did: confirms_command_id is
--   an argument the 0605 body never reads, and the 0559 dispatcher ledgers transport 'confirm' as 'other'. Which
--   gateway version is deployed now was not read here.

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
              WHERE table_schema = 'public' AND table_name = 'ottoq_owner_commands'
                AND column_name IN ('acting_person', 'via', 'confirms_command_id')) THEN
    RAISE EXCEPTION '0721 P2: ottoq_owner_commands already has acting_person, via or confirms_command_id';
  END IF;
  IF to_regclass('public.ottoq_owner_commands_confirms_idx') IS NOT NULL THEN
    RAISE EXCEPTION '0721 P2: the index ottoq_owner_commands_confirms_idx already exists';
  END IF;
  IF to_regprocedure('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_write_gate(public.ottoq_agent_principals,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_acting_person(public.ottoq_agent_principals)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_confirm_binding(public.ottoq_agent_principals,uuid,text,jsonb,text,text,uuid,boolean)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_commands_backstop()') IS NOT NULL THEN
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

-- ══ 1. the three columns ════════════════════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.ottoq_owner_commands
  ADD COLUMN acting_person text,
  ADD COLUMN via text,
  ADD COLUMN confirms_command_id uuid,
  ADD CONSTRAINT ottoq_owner_commands_confirms_command_id_fkey FOREIGN KEY (confirms_command_id)
    REFERENCES public.ottoq_owner_commands (command_id),
  ADD CONSTRAINT ottoq_owner_commands_acting_person_check CHECK (
    acting_person IS NULL OR (acting_person = lower(btrim(acting_person)) AND acting_person ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  ADD CONSTRAINT ottoq_owner_commands_via_check CHECK (via IS NULL OR via IN ('ottocommand', 'confirm', 'direct')),
  --: a row that names a preview is an apply that went through (or changed nothing), recorded as a confirm
  ADD CONSTRAINT ottoq_owner_commands_confirms_check CHECK (
    confirms_command_id IS NULL OR (mode = 'apply' AND outcome IN ('applied', 'no_change') AND via = 'confirm')),
  --: and a row recorded as a confirm always names the preview it confirmed: via 'confirm' iff confirms_command_id
  ADD CONSTRAINT ottoq_owner_commands_confirm_is_bound_check CHECK (
    via IS DISTINCT FROM 'confirm' OR confirms_command_id IS NOT NULL);

--: one preview confirms one apply
CREATE UNIQUE INDEX ottoq_owner_commands_confirms_idx ON public.ottoq_owner_commands (confirms_command_id)
  WHERE confirms_command_id IS NOT NULL;

COMMENT ON COLUMN public.ottoq_owner_commands.acting_person IS
'0721. The person the command is recorded under: the email of the OTTOYARD account (ottoq_owner_accounts, through ottoq_oauth_grants) behind an agent signed in through 0700, while that account is active and owns the agent''s fleet. NULL for a passcode session or an issued key, which name no one. On a production_live run an applied command always has one (ottoq_owner_commands_backstop_trg). It records whose agent sent the command; OTTO-Q cannot see whether that person said yes.';
COMMENT ON COLUMN public.ottoq_owner_commands.via IS
'0721. Who formed the command, set by the database from the gateway''s transport and the binding, never taken from an argument. ottocommand: an OTTO-Command model read the owner''s words and called the tool with the owner''s own token (transport ask: POST /v1/ask or the MCP tool ask_ottocommand, sent with text). confirm: the agent confirmed a recorded preview: the apply bound to an outcome previewed row the same principal made on the same run in the last 15 minutes, named in confirms_command_id (always set on a confirm row, by CHECK); no model was involved, whether it was sent through the confirm door of /v1/ask and ask_ottocommand (transport confirm) or as a typed tool naming the preview. direct: the agent itself made the call (a typed tool over MCP or REST, or a confirm object that bound to no preview and was recorded as a new preview), or any other caller. OTTO-Q enforces preview-then-confirm by the same signed-in principal within 15 minutes; it cannot see a person''s yes, which the person''s own agent relays. NULL on rows written before 0721; never backfilled.';
COMMENT ON COLUMN public.ottoq_owner_commands.confirms_command_id IS
'0721. The preview this apply confirmed: an outcome previewed row by the same principal, on the same run, of the same tool, arguments and plan_hash, made at most 15 minutes before it and confirmed by no other apply (unique). On a production run every applied lowering of a charge limit has one. OTTO-Q enforces preview-then-confirm by the same principal; the confirm itself is relayed by the person''s agent, and OTTO-Q cannot see the person''s yes.';

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
   so that every production change is recorded under a person (CLAUDE.md rule 10); on one, a lower charge limit is
   applied only as the confirm of a preview the same agent recorded in the last 15 minutes (rule 9). Every refusal says
   why and what to do instead. Read by ottoq_owner_command and by whoami, so OTTO-Command knows before it acts. */
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
      'confirm_window_minutes', 15,
      'message', format('A production run is live. Changes are recorded under %s and lift when the run ends. Lowering how full a car charges (a lower limit, or an undo that puts one back) applies only as the confirm of a preview this agent recorded in the last 15 minutes; an apply that names no such preview is recorded as a preview and answered confirm_required. Everything else is one call.', v_person));
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

CREATE OR REPLACE FUNCTION public.ottoq_owner_confirm_binding(p_agent public.ottoq_agent_principals, p_run uuid, p_tool text,
                                                              p_args jsonb, p_hash text, p_expect text, p_confirms uuid,
                                                              p_lowering boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 (CLAUDE.md rule 9). Is this apply the confirm of a preview OTTO-Q recorded? It binds only to a row with outcome
   'previewed' made by the SAME principal, on the same run, of the same tool and arguments (mode, note and the words of a
   hold's time aside: its resolved until_sim stays in), with the same plan hash, created at most 15 minutes ago and
   confirmed by no apply yet. The apply names it by p_expect (the plan hash) and/or p_confirms (its command_id); naming
   neither binds nothing. Answers {"bound": <command_id>} (the preview row is locked until the apply commits; the unique
   index ottoq_owner_commands_confirms_idx refuses a second apply that raced it), or confirm_required with the reason and
   what to do. Called by ottoq_owner_command only; no client role reaches it.
   What it cannot know is whether a person said yes: the confirm comes from the person's agent, with the token that made
   the preview. A person-only surface (the OTTOYARD account session) is not built. */
DECLARE
  v_bound uuid;
  v_named public.ottoq_owner_commands;
  v_why   text;
BEGIN
  IF p_expect IS NULL AND p_confirms IS NULL THEN
    v_why := 'not_named';
  ELSE
    SELECT p.command_id INTO v_bound
      FROM public.ottoq_owner_commands p
     WHERE p.principal_id = p_agent.principal_id
       AND p.outcome = 'previewed'
       AND p.sim_run_id = p_run
       AND p.tool = p_tool
       AND p.plan_hash = p_hash
       AND (p_expect IS NULL OR p.plan_hash = p_expect)
       AND (p_confirms IS NULL OR p.command_id = p_confirms)
       AND (p.args - 'mode' - 'note' - 'until' - 'for_minutes') = (p_args - 'mode' - 'note' - 'until' - 'for_minutes')
       AND p.created_at >= now() - interval '15 minutes'
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_commands a WHERE a.confirms_command_id = p.command_id)
     ORDER BY p.created_at DESC, p.command_id
     LIMIT 1
       FOR UPDATE OF p;
    IF v_bound IS NOT NULL THEN
      RETURN jsonb_build_object('bound', v_bound);
    END IF;
    --: why not, in words that name nothing outside this principal's own commands
    IF p_confirms IS NOT NULL THEN
      SELECT * INTO v_named FROM public.ottoq_owner_commands p
       WHERE p.command_id = p_confirms AND p.principal_id = p_agent.principal_id;
    ELSE
      SELECT * INTO v_named FROM public.ottoq_owner_commands p
       WHERE p.principal_id = p_agent.principal_id AND p.outcome = 'previewed' AND p.sim_run_id = p_run
         AND p.tool = p_tool AND p.plan_hash = p_expect
       ORDER BY p.created_at DESC, p.command_id LIMIT 1;
    END IF;
    v_why := CASE
      WHEN v_named.command_id IS NULL THEN 'no_recorded_preview'
      WHEN v_named.outcome <> 'previewed' THEN 'not_a_preview'
      WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_commands a WHERE a.confirms_command_id = v_named.command_id)
        THEN 'preview_already_confirmed'
      WHEN v_named.created_at < now() - interval '15 minutes' THEN 'preview_expired'
      ELSE 'preview_does_not_match' END;
  END IF;
  RETURN jsonb_build_object('code', 'confirm_required', 'reason', v_why,
    'message', CASE WHEN p_lowering
                    THEN 'This is a production run, so lowering how full a car charges applies only as the confirm of a preview this agent recorded in the last 15 minutes. '
                    ELSE 'A confirm applies only a preview this agent recorded in the last 15 minutes. ' END
            || CASE v_why
                 WHEN 'not_named'                 THEN 'This apply named no preview (expect_plan_hash or confirms_command_id). '
                 WHEN 'no_recorded_preview'       THEN 'This agent recorded no such preview on this run. '
                 WHEN 'not_a_preview'             THEN 'The command it names is not a preview. '
                 WHEN 'preview_already_confirmed' THEN 'That preview was already confirmed once, and a preview confirms one apply. '
                 WHEN 'preview_expired'           THEN 'That preview is more than 15 minutes old. '
                 ELSE 'That preview does not match this command (its tool, cars, arguments or plan differ). ' END
            || 'Nothing was applied. It is recorded as a new preview, and confirming that applies it.',
    'hint', 'Show your person the plan. Once they say yes, send the confirm object this answer carries (it names this preview) within 15 minutes, from this same agent. Raising or clearing a limit, holds, service orders and cancelling your own orders need no preview.');
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_owner_acting_person(public.ottoq_agent_principals) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_owner_write_gate(public.ottoq_agent_principals, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_owner_confirm_binding(public.ottoq_agent_principals, uuid, text, jsonb, text, text, uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;

-- ══ 3. the owner command learns its door, its person, production and the binding ═══════════════════════════════════
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
       || E'  --: 0721: who may change settings on this run and under whose name, which door (from the transport and the binding,\n'
       || E'  --: never from an argument), whether the command lowers a limit, and the preview an apply confirms\n'
       || E'  v_gate        jsonb;\n'
       || E'  v_production  boolean := false;\n'
       || E'  v_person      text;\n'
       || E'  v_door        text := CASE p_via WHEN ''ask'' THEN ''ottocommand'' ELSE ''direct'' END;   --: a model, or the agent itself\n'
       || E'  v_via         text := v_door;                                    --: ''confirm'' once the apply binds to a preview\n'
       || E'  v_lowers      boolean := false;\n'
       || E'  v_confirms    uuid;\n'
       || E'  v_bind        jsonb;\n'
       || E'  v_bound       uuid;\n'
       || E'  v_confirm_req jsonb;\n'
       || E'BEGIN\n'],
    -- b2. the preview an apply names (the confirm object a preview returns carries it)
    ARRAY[E'      DETAIL = ''expect_plan_hash is the 32-character plan_hash a preview returned.'';\n  END IF;\n',
          E'      DETAIL = ''expect_plan_hash is the 32-character plan_hash a preview returned.'';\n  END IF;\n'
       || E'  --: 0721: the preview this apply confirms, by its command_id\n'
       || E'  v_confirms := public.ottoq_agent_arg_uuid(v_args, ''confirms_command_id'');\n'
       || E'  IF v_confirms IS NOT NULL AND v_mode <> ''apply'' THEN\n'
       || E'    RAISE EXCEPTION USING ERRCODE = ''OQA01'', MESSAGE = ''invalid_arguments'',\n'
       || E'      DETAIL = ''confirms_command_id is for mode apply: it names the preview this apply confirms.'';\n'
       || E'  END IF;\n'],
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
    -- e. a new limit below the one in force lowers how full the car charges
    ARRAY[E'      v_before := LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling));\n',
          E'      v_before := LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling));\n'
       || E'      IF v_pct < v_before THEN v_lowers := true; END IF;   --: 0721: this command lowers how full the car charges\n'],
    -- e2. so does an undo that puts back a lower limit than the one in force
    ARRAY[E'          v_grp := ''limit_back'';\n',
          E'          v_grp := ''limit_back'';\n'
       || E'          --: 0721: putting back a lower limit than the one in force lowers how full the car charges\n'
       || E'          IF LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling)) < LEAST(v_ceiling, v_set.charge_limit_pct) THEN\n'
       || E'            v_lowers := true;\n'
       || E'          END IF;\n'],
    -- f. the binding (rule 9), after 0605's stale-hash refusal
    ARRAY[E'      ''message'', ''The plan changed since it was previewed (a car''''s settings moved). Nothing was applied. Read the new plan and confirm it with its hash.'');\n'
       || E'  END IF;\n',
          E'      ''message'', ''The plan changed since it was previewed (a car''''s settings moved). Nothing was applied. Read the new plan and confirm it with its hash.'');\n'
       || E'  END IF;\n'
       || E'  --: 0721 (CLAUDE.md rule 9: a lower limit is the owner''s, "set verified and confirmed"). An OTTO-Command model never\n'
       || E'  --: confirms a plan: the gateway strips both binding arguments from what it may send, and a call that carries one is refused.\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''apply'' AND v_door = ''ottocommand'' AND (v_expect IS NOT NULL OR v_confirms IS NOT NULL) THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''confirm_not_through_ottocommand'',\n'
       || E'      ''message'', ''OTTO-Command does not confirm a plan. Nothing was applied. A preview is confirmed by sending its confirm object back: to ask_ottocommand or POST /v1/ask as confirm, or as the typed tool call it describes.'');\n'
       || E'  END IF;\n'
       || E'  --: An apply must be the confirm of a recorded preview (ottoq_owner_confirm_binding: same principal, run, tool, arguments\n'
       || E'  --: and plan hash, at most 15 minutes old, not confirmed before) when it lowers a limit on a production run, when it came\n'
       || E'  --: through the confirm door, or when it names a preview. One that does not bind applies nothing: it is recorded as a\n'
       || E'  --: preview, with its own plan hash and id, and answered confirm_required, so the next confirm can name it. One that\n'
       || E'  --: binds is recorded as via ''confirm'', whichever way it was sent: the agent confirmed a recorded preview.\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''apply''\n'
       || E'     AND (p_via IS NOT DISTINCT FROM ''confirm'' OR v_confirms IS NOT NULL OR (v_production AND v_lowers)) THEN\n'
       || E'    v_bind := public.ottoq_owner_confirm_binding(p_agent, v_run_id, v_tool, v_norm, v_hash, v_expect, v_confirms,\n'
       || E'                                                 v_production AND v_lowers);\n'
       || E'    v_bound := (v_bind ->> ''bound'')::uuid;\n'
       || E'    IF v_bound IS NULL THEN\n'
       || E'      v_confirm_req := v_bind;\n'
       || E'      v_mode := ''preview'';\n'
       || E'      v_norm := v_norm || jsonb_build_object(''mode'', ''preview'');\n'
       || E'    ELSE\n'
       || E'      v_via := ''confirm'';\n'
       || E'    END IF;\n'
       || E'  END IF;\n'],
    -- g. the receipt names the run that ends it
    ARRAY[E'E''\\nThis lasts until the demo run ends or you undo it.''',
          E'CASE WHEN v_production THEN E''\\nThis lasts until the production run ends or you undo it.'' ELSE E''\\nThis lasts until the demo run ends or you undo it.'' END'],
    -- g2. an apply recorded as a preview says so, and how to confirm it
    ARRAY[E'    WHEN v_mode = ''preview'' THEN ''Preview only, nothing has changed. If you confirm: ''\n',
          E'    WHEN v_confirm_req IS NOT NULL THEN ''Not applied yet: '' || (v_confirm_req ->> ''message'') || E''\\nIf you confirm: ''\n'
       || E'         || public.ottoq_owner_summarize(v_head, v_effects, v_tail)\n'
       || E'         || format(E''\\nTo confirm, send the same command with mode "apply", expect_plan_hash "%s" and confirms_command_id "%s".'', v_hash, v_cmd.command_id)\n'
       || E'    WHEN v_mode = ''preview'' THEN ''Preview only, nothing has changed. If you confirm: ''\n'],
    -- h. the record: the person, the door and the preview confirmed, on every row
    ARRAY[E'       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id)\n',
          E'       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id, acting_person, via,\n'
       || E'       confirms_command_id)\n'],
    ARRAY[E'       CASE WHEN v_tool = ''undo_command'' AND v_target.command_id IS NOT NULL THEN v_target.command_id END)\n',
          E'       CASE WHEN v_tool = ''undo_command'' AND v_target.command_id IS NOT NULL THEN v_target.command_id END,\n'
       || E'       v_person, v_via, v_bound)\n'],
    ARRAY[E'       vehicles, effects, refusal, summary, plan_hash)\n',
          E'       vehicles, effects, refusal, summary, plan_hash, acting_person, via)\n'],
    ARRAY[E'Nothing was applied; send it again.'', v_hash)\n',
          E'Nothing was applied; send it again.'', v_hash, v_person, v_door)\n'],
    -- j. an apply recorded as a preview answers confirm_required (ottoq_agent_call: 422), naming that preview
    ARRAY[E'  RETURN public.ottoq_owner_command_reply(v_cmd, false);\n',
          E'  RETURN public.ottoq_owner_command_reply(v_cmd, false)\n'
       || E'         || CASE WHEN v_confirm_req IS NOT NULL AND v_cmd.outcome = ''previewed''\n'
       || E'                 THEN jsonb_build_object(''refusal'', v_confirm_req || jsonb_build_object(''preview_command_id'', v_cmd.command_id))\n'
       || E'                 ELSE ''{}''::jsonb END;\n']];
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

-- ══ 4. the dispatcher admits the confirm door, passes its transport, and answers confirm_required 422 ════════════════
DO $call$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure);
  v_new text;
  v_pair text[];
  v_pairs text[][] := ARRAY[
    ARRAY[E'  v_transport text := CASE WHEN p_transport IN (''rest'', ''mcp'', ''ask'') THEN p_transport ELSE ''other'' END;\n',
          E'  --: 0721: ''confirm'' is the gateway''s confirm door (a preview''s confirm object sent back, no model involved)\n'
       || E'  v_transport text := CASE WHEN p_transport IN (''rest'', ''mcp'', ''ask'', ''confirm'') THEN p_transport ELSE ''other'' END;\n'],
    ARRAY[E'      ELSE public.ottoq_owner_command(v_agent, v_tool, v_args)\n',
          E'      ELSE public.ottoq_owner_command(v_agent, v_tool, v_args, v_transport)   --: 0721: the door it came through\n'],
    ARRAY[E'      v_status := CASE WHEN v_data ->> ''outcome'' = ''refused'' THEN 422\n',
          E'      --: 0721: an apply that had to confirm a preview and did not is recorded as one, and answered as not done\n'
       || E'      v_status := CASE WHEN v_data ->> ''outcome'' = ''refused'' OR v_data #>> ''{refusal,code}'' = ''confirm_required'' THEN 422\n']];
  v_n int;
BEGIN
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721: an anchor of ottoq_agent_call occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 120);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
END $call$;

-- ══ 5. the receipt shows the person, the door, the preview confirmed and the run that ends it; a confirm names its preview
DO $reply$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure);
  v_new text;
  v_pair text[];
  v_pairs text[][] := ARRAY[
    ARRAY[E'      ''lifted_at'', p_c.lifted_at, ''lifted_reason'', p_c.lifted_reason),\n',
          E'      ''lifted_at'', p_c.lifted_at, ''lifted_reason'', p_c.lifted_reason,\n'
       || E'      --: 0721: the person the command is recorded under, the door it came through, and the preview it confirmed\n'
       || E'      ''acting_person'', p_c.acting_person, ''via'', p_c.via, ''confirms_command_id'', p_c.confirms_command_id),\n'],
    ARRAY[E'                         || jsonb_build_object(''mode'', ''apply'', ''expect_plan_hash'', p_c.plan_hash),\n'
       || E'                 ''note'', ''Send this to apply exactly the plan shown. If the cars or settings change first, OTTO-Q refuses with the new plan.'') END,\n',
          E'                         --: 0721: the confirm names this preview, which confirms one apply\n'
       || E'                         || jsonb_build_object(''mode'', ''apply'', ''expect_plan_hash'', p_c.plan_hash, ''confirms_command_id'', p_c.command_id),\n'
       || E'                 ''note'', ''Send this to apply exactly the plan shown, from the agent that previewed it, within 15 minutes; it confirms this preview once. If the cars or settings change first, OTTO-Q refuses with the new plan.'') END,\n'],
    ARRAY[E'                    THEN ''Lasts until this demo run ends or you undo it; a stop or reset of the twin puts every car back to baseline.'' END))\n',
          E'                    THEN CASE WHEN (SELECT r.run_by FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_c.sim_run_id) = ''production_live''\n'
       || E'                              THEN ''Lasts until this production run ends or you undo it; when the run ends every car goes back to its baseline.''\n'
       || E'                              ELSE ''Lasts until this demo run ends or you undo it; a stop or reset of the twin puts every car back to baseline.'' END END))\n']];
  v_n int;
BEGIN
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721: an anchor of ottoq_owner_command_reply occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 120);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
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
  c_new2 constant text := E'undoable, and lifted when the run ends. On a production run only an agent signed in to its owner''''s OTTOYARD account may change them, each change is recorded under that person, and a lower charge limit (or an undo that puts one back) applies only as the confirm of a preview the same agent recorded in the last 15 minutes.'',\n';
  v_n1 int; v_n2 int;
BEGIN
  v_n1 := (length(v_def) - length(replace(v_def, c_old1, ''))) / length(c_old1);
  v_n2 := (length(v_def) - length(replace(v_def, c_old2, ''))) / length(c_old2);
  IF v_n1 <> 1 OR v_n2 <> 1 THEN
    RAISE EXCEPTION '0721: whoami''s anchors occur % and % times, expected exactly 1 each', v_n1, v_n2;
  END IF;
  EXECUTE replace(replace(v_def, c_old1, c_new1), c_old2, c_new2);
END $whoami$;

-- ══ 7. the guard: who, which door and which preview are as immutable as what was commanded ══════════════════════
DO $guard$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure);
  c_old1 constant text := E'NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at)';
  c_new1 constant text := E'NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at, NEW.acting_person, NEW.via,\n'
                       || E'      NEW.confirms_command_id)';
  c_old2 constant text := E'OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at)';
  c_new2 constant text := E'OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at, OLD.acting_person, OLD.via,\n'
                       || E'      OLD.confirms_command_id)';
  v_n1 int; v_n2 int;
BEGIN
  v_n1 := (length(v_def) - length(replace(v_def, c_old1, ''))) / length(c_old1);
  v_n2 := (length(v_def) - length(replace(v_def, c_old2, ''))) / length(c_old2);
  IF v_n1 <> 1 OR v_n2 <> 1 THEN
    RAISE EXCEPTION '0721: ottoq_owner_commands_guard''s tuples occur % and % times, expected exactly 1 each', v_n1, v_n2;
  END IF;
  EXECUTE replace(replace(v_def, c_old1, c_new1), c_old2, c_new2);
END $guard$;

-- ══ 8. the backstop, whoever writes the row: no applied production command without a person (rule 10), and no confirm
--      of anything but a preview this apply may confirm (rule 9) ══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_owner_commands_backstop()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721. Under the door, for any writer. CLAUDE.md rule 10: in production no setting changes except under a person's
   name, so an applied command on a production_live run carries acting_person. Rule 9: a confirms_command_id names a
   preview (outcome 'previewed') by the same principal, on the same run, of the same tool and plan hash, made at most
   15 minutes before the apply; the unique index ottoq_owner_commands_confirms_idx lets it confirm one apply. */
DECLARE
  v_p public.ottoq_owner_commands;
BEGIN
  IF NEW.outcome = 'applied' AND NEW.acting_person IS NULL AND NEW.sim_run_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id AND r.run_by = 'production_live') THEN
    RAISE EXCEPTION 'owner command on production run %: an applied change needs the person it is recorded under (acting_person)',
      NEW.sim_run_id USING ERRCODE = '42501';
  END IF;
  IF NEW.confirms_command_id IS NOT NULL THEN
    SELECT * INTO v_p FROM public.ottoq_owner_commands p WHERE p.command_id = NEW.confirms_command_id;
    IF v_p.command_id IS NULL OR v_p.outcome IS DISTINCT FROM 'previewed' OR v_p.principal_id IS DISTINCT FROM NEW.principal_id
       OR v_p.sim_run_id IS DISTINCT FROM NEW.sim_run_id OR v_p.tool IS DISTINCT FROM NEW.tool
       OR v_p.plan_hash IS DISTINCT FROM NEW.plan_hash
       OR v_p.created_at < NEW.created_at - interval '15 minutes' OR v_p.created_at > NEW.created_at THEN
      RAISE EXCEPTION 'owner command %: confirms_command_id % is not a preview this apply may confirm (the same principal, run, tool and plan, at most 15 minutes before it)',
        NEW.command_id, NEW.confirms_command_id USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_owner_commands_backstop() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER ottoq_owner_commands_backstop_trg
  BEFORE INSERT ON public.ottoq_owner_commands
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_commands_backstop();

-- ══ V1: the bodies say what this file says they do ══════════════════════════════════════════════════════════════════
DO $v1$
DECLARE
  v_cmd   text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)'::regprocedure);
  v_three text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure);
  v_call  text := pg_get_functiondef('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure);
  v_reply text := pg_get_functiondef('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure);
  v_who   text := pg_get_functiondef('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure);
  v_guard text := pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure);
  v_bind  text := pg_get_functiondef('public.ottoq_owner_confirm_binding(public.ottoq_agent_principals,uuid,text,jsonb,text,text,uuid,boolean)'::regprocedure);
BEGIN
  IF strpos(v_cmd, 'v_gate := public.ottoq_owner_write_gate(p_agent, v_run);') = 0
     OR strpos(v_cmd, 'v_bind := public.ottoq_owner_confirm_binding(p_agent, v_run_id, v_tool, v_norm, v_hash, v_expect, v_confirms,') = 0
     OR strpos(v_cmd, 'v_door        text := CASE p_via WHEN ''ask'' THEN ''ottocommand'' ELSE ''direct'' END;') = 0
     OR strpos(v_cmd, 'ELSE' || chr(10) || '      v_via := ''confirm'';') = 0
     OR strpos(v_cmd, '''confirm_not_through_ottocommand''') = 0
     OR strpos(v_cmd, 'v_person, v_via, v_bound)') = 0
     OR strpos(v_cmd, 'IF v_refusal IS NULL AND NOT v_demo THEN') > 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the four-argument owner command is not the patched body';
  END IF;
  IF strpos(v_three, 'RETURN public.ottoq_owner_command(p_agent, p_tool, p_args, NULL::text);') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the three-argument owner command does not delegate';
  END IF;
  IF strpos(v_call, 'public.ottoq_owner_command(v_agent, v_tool, v_args, v_transport)') = 0
     OR strpos(v_call, 'p_transport IN (''rest'', ''mcp'', ''ask'', ''confirm'')') = 0
     OR strpos(v_call, 'v_data #>> ''{refusal,code}'' = ''confirm_required'' THEN 422') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: ottoq_agent_call does not admit the confirm door, pass its transport or answer confirm_required 422';
  END IF;
  IF strpos(v_reply, '''acting_person'', p_c.acting_person, ''via'', p_c.via, ''confirms_command_id'', p_c.confirms_command_id') = 0
     OR strpos(v_reply, '''expect_plan_hash'', p_c.plan_hash, ''confirms_command_id'', p_c.command_id') = 0
     OR strpos(v_who, '''changes'', public.ottoq_owner_write_gate(p_agent, v_run)') = 0
     OR strpos(v_guard, 'NEW.confirms_command_id)') = 0 OR strpos(v_guard, 'OLD.confirms_command_id)') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the receipt, whoami or the guard is not patched';
  END IF;
  IF strpos(v_bind, 'p.created_at >= now() - interval ''15 minutes''') = 0 OR strpos(v_bind, 'p.principal_id = p_agent.principal_id') = 0
     OR strpos(v_bind, 'a.confirms_command_id = p.command_id') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the binding does not hold a confirm to the same principal, 15 minutes and one apply';
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
                      'public.ottoq_owner_confirm_binding(public.ottoq_agent_principals,uuid,text,jsonb,text,text,uuid,boolean)',
                      'public.ottoq_owner_commands_backstop()']) f
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
-- account, two connections, their access tokens), a passcode session, an issued key, their commands and settings, the
-- ledger rows -- is in a block that raises at its end and is rolled back. Only the answers, held in variables, survive it.
-- It probes the binding (rule 9): a lowering sent in one call is recorded as a preview and applies nothing; its confirm,
-- sent by the OTHER connection, applies nothing; sent by the agent that made it, applies once and is recorded as via
-- 'confirm' naming the preview; sent again, applies nothing; a raise is one call; the undo of that raise (which puts the
-- lower limit back) is gated the same way and applies only as its own preview's confirm. A preview older than 15 minutes
-- cannot be made inside one transaction (now() does not move), so expiry is proved by the test suite, not here.
DO $v3$
DECLARE
  c_twin   constant uuid := '11111111-1111-1111-1111-111111111111';
  c_email  constant text := 'v0721.probe@ottoyard.invalid';
  v_run    uuid := gen_random_uuid();
  v_tpl    uuid;
  v_cols   text;
  v_fleet  uuid;
  v_ctr    jsonb;
  v_low    numeric;
  v_mid    numeric;
  v_client text := 'oqc_' || md5('0721-client' || clock_timestamp()::text);
  v_acct   uuid := gen_random_uuid();
  v_pid    uuid;
  v_oauth  text := 'oqt_' || md5('0721-oauth-a' || clock_timestamp()::text) || md5('0721-oauth-b' || clock_timestamp()::text);
  v_pid2   uuid;
  v_oauth2 text := 'oqt_' || md5('0721-oauth-c' || clock_timestamp()::text) || md5('0721-oauth-d' || clock_timestamp()::text);
  v_pass   text := 'oqs_' || md5('0721-pass-a' || clock_timestamp()::text) || md5('0721-pass-b' || clock_timestamp()::text);
  v_key    text;
  v_th     text;
  v_car    uuid;
  r_whoami jsonb; r_lower jsonb; r_confirm jsonb; r_again jsonb; r_mid jsonb; r_undo jsonb; r_clear jsonb;
  r_pass jsonb; r_key jsonb; r_demo jsonb; r_other jsonb; r_undone jsonb;
  v_t_confirm numeric;
  v_t_undo    numeric;
  v_t_other   numeric;
  v_t_undone  numeric;
  v_prev   uuid;
  v_cmd    uuid;
  v_ledger text;
  v_twice  text := 'not reached';
  v_bogus  text := 'not reached';
  v_guard  text := 'not reached';
  v_back   text := 'not reached';
BEGIN
  SELECT r.sim_run_id INTO v_tpl FROM public.ottoq_sim_runs r WHERE r.depot_id = c_twin ORDER BY r.started_at DESC LIMIT 1;
  --: the twin depot's owner with the most cars and a contract range at least 3 points wide (a lower limit, then a raise
  --: that stays under the top)
  SELECT v.fleet_operator_id INTO v_fleet
    FROM public.vehicles v
   WHERE (v.current_depot_id = c_twin OR v.home_depot_id = c_twin) AND v.fleet_operator_id IS NOT NULL
     AND (public.ottoq_owner_contract(v.fleet_operator_id, now()) ->> 'min_charge_pct')::numeric + 3
         <= (public.ottoq_owner_contract(v.fleet_operator_id, now()) ->> 'max_charge_pct')::numeric
   GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1;
  IF v_tpl IS NULL OR v_fleet IS NULL THEN
    RAISE EXCEPTION '0721 V3: no twin-depot run to copy, or no owner at the twin depot with a contract range to probe';
  END IF;
  v_ctr := public.ottoq_owner_contract(v_fleet, now());
  v_low := GREATEST((v_ctr ->> 'min_charge_pct')::numeric, (v_ctr ->> 'max_charge_pct')::numeric - 5);
  v_mid := v_low + 2;
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
    --: a second agent signed in to the same person's account: another principal, which confirms only its own previews
    v_pid2 := public.ottoq_oauth_connect(v_acct, v_client, 'ottoyard:owner', 'https://probe.invalid/account/mcp', 'device_code');
    INSERT INTO public.ottoq_oauth_tokens (token_hash, kind, principal_id, expires_at)
    VALUES (public.ottoq_oauth_sha256(v_oauth2), 'access', v_pid2, now() + interval '10 minutes');
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
    v_th := public.ottoq_oauth_sha256(v_oauth);

    r_whoami := public.ottoq_agent_call(v_th, 'whoami', '{}'::jsonb, 'mcp', '{}'::jsonb);
    -- 1. the person's agent lowers the limit in one call: nothing is applied; OTTO-Q records it as a preview under the
    --    person and answers confirm_required
    r_lower := public.ottoq_agent_call(v_th, 'set_charge_limit', jsonb_build_object('vehicles', 'all', 'percent', v_low),
                                       'mcp', '{}'::jsonb);
    v_prev := (r_lower #>> '{data,command,command_id}')::uuid;
    -- 1b. that preview's confirm, sent by another agent signed in to the same account: not its preview, so nothing applies
    r_other := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_oauth2), r_lower #>> '{data,confirm,tool}',
                                       r_lower #> '{data,confirm,args}', 'confirm', '{}'::jsonb);
    v_t_other := public.ottoq_effective_target_soc_at(v_car, now());
    -- 2. that preview's confirm object, sent back through the confirm door: applied once, bound to the preview
    r_confirm := public.ottoq_agent_call(v_th, r_lower #>> '{data,confirm,tool}', r_lower #> '{data,confirm,args}', 'confirm',
                                         '{}'::jsonb);
    v_t_confirm := public.ottoq_effective_target_soc_at(v_car, now());
    v_cmd := (r_confirm #>> '{data,command,command_id}')::uuid;
    SELECT l.transport INTO v_ledger FROM public.ottoq_agent_call_ledger l WHERE l.call_id = (r_confirm ->> 'call_id')::bigint;
    -- 3. the same confirm again applies nothing; a second apply naming the preview, written straight into the table, is
    --    refused by the unique index; and a confirm naming a command that is no preview is refused by the backstop
    r_again := public.ottoq_agent_call(v_th, r_lower #>> '{data,confirm,tool}', r_lower #> '{data,confirm,args}', 'confirm',
                                       '{}'::jsonb);
    BEGIN
      INSERT INTO public.ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, mode,
                                               outcome, summary, plan_hash, acting_person, via, confirms_command_id)
      VALUES (v_pid, '0721 probe', v_fleet, c_twin, v_run, 'set_charge_limit', 'apply', 'applied', '0721 double-confirm probe',
              r_lower #>> '{data,command,plan_hash}', c_email, 'confirm', v_prev);
      v_twice := 'inserted';
    EXCEPTION WHEN unique_violation THEN v_twice := 'refused';
    END;
    BEGIN
      INSERT INTO public.ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, mode,
                                               outcome, summary, plan_hash, acting_person, via, confirms_command_id)
      VALUES (v_pid, '0721 probe', v_fleet, c_twin, v_run, 'set_charge_limit', 'apply', 'applied', '0721 bogus-confirm probe',
              r_confirm #>> '{data,command,plan_hash}', c_email, 'confirm', v_cmd);
      v_bogus := 'inserted';
    EXCEPTION WHEN insufficient_privilege THEN v_bogus := 'refused';
    END;
    -- 4. raising is one call; undoing that raise puts the lower limit back, so it is gated like a new lower limit
    r_mid := public.ottoq_agent_call(v_th, 'set_charge_limit', jsonb_build_object('vehicles', 'all', 'percent', v_mid),
                                     'rest', '{}'::jsonb);
    r_undo := public.ottoq_agent_call(v_th, 'undo_command', jsonb_build_object('command_id', r_mid #>> '{data,command,command_id}'),
                                      'mcp', '{}'::jsonb);
    v_t_undo := public.ottoq_effective_target_soc_at(v_car, now());
    --    the undo's recorded preview, confirmed by the agent that made it: applied, bound to it, the lower limit back
    r_undone := public.ottoq_agent_call(v_th, r_undo #>> '{data,confirm,tool}', r_undo #> '{data,confirm,args}', 'confirm',
                                        '{}'::jsonb);
    v_t_undone := public.ottoq_effective_target_soc_at(v_car, now());
    -- 5. the guard holds the person, the door and the preview; the backstop refuses an applied production row with no person
    BEGIN
      UPDATE public.ottoq_owner_commands SET via = 'direct', confirms_command_id = NULL WHERE command_id = v_cmd;
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
    -- 6. clearing back to full is one call, and a "via" among the arguments is ignored: the door is the transport's
    r_clear := public.ottoq_agent_call(v_th, 'clear_charge_limit', jsonb_build_object('vehicles', 'all', 'via', 'ottocommand'),
                                       'rest', '{}'::jsonb);
    -- 7. a passcode session and an issued key name no person: refused in production
    r_pass := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_pass), 'set_charge_limit',
                jsonb_build_object('vehicles', 'all', 'percent', v_low, 'mode', 'preview'), 'mcp', '{}'::jsonb);
    r_key := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_key), 'hold_vehicle',
               jsonb_build_object('vehicles', 'all', 'for_minutes', 30), 'rest', '{}'::jsonb);
    -- 8. and on a demo run the passcode session works as before, with no person and its door recorded
    UPDATE public.ottoq_sim_runs SET run_by = 'operator_demo' WHERE sim_run_id = v_run;
    r_demo := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_pass), 'hold_vehicle',
                jsonb_build_object('vehicles', 'all', 'for_minutes', 30), 'ask', '{}'::jsonb);
    RAISE EXCEPTION USING ERRCODE = 'OQ721', MESSAGE = '0721 V3 probe rolled back';
  EXCEPTION WHEN SQLSTATE 'OQ721' THEN NULL;
  END;

  IF r_whoami #>> '{data,owner,changes,allowed}' IS DISTINCT FROM 'true'
     OR r_whoami #>> '{data,owner,changes,person}' IS DISTINCT FROM c_email
     OR r_whoami #>> '{data,owner,changes,confirm_window_minutes}' IS DISTINCT FROM '15'
     OR r_whoami #>> '{data,owner,live_production_run}' IS DISTINCT FROM v_run::text THEN
    RAISE EXCEPTION '0721 V3 FAILED: whoami does not say a signed-in person may change production: %', r_whoami -> 'data' -> 'owner';
  END IF;
  IF (r_lower ->> 'http_status')::int <> 422 OR r_lower #>> '{error,code}' IS DISTINCT FROM 'confirm_required'
     OR r_lower #>> '{data,refusal,reason}' IS DISTINCT FROM 'not_named'
     OR r_lower #>> '{data,outcome}' IS DISTINCT FROM 'previewed' OR r_lower #>> '{data,command,mode}' IS DISTINCT FROM 'preview'
     OR r_lower #>> '{data,command,acting_person}' IS DISTINCT FROM c_email OR r_lower #>> '{data,command,via}' IS DISTINCT FROM 'direct'
     OR r_lower #>> '{data,confirm,args,confirms_command_id}' IS DISTINCT FROM v_prev::text THEN
    RAISE EXCEPTION '0721 V3 FAILED: a production limit lowered in one call was not recorded as a preview and answered confirm_required: %', r_lower;
  END IF;
  IF (r_confirm ->> 'http_status')::int <> 201 OR r_confirm #>> '{data,outcome}' IS DISTINCT FROM 'applied'
     OR r_confirm #>> '{data,command,acting_person}' IS DISTINCT FROM c_email
     OR r_confirm #>> '{data,command,via}' IS DISTINCT FROM 'confirm'
     OR r_confirm #>> '{data,command,confirms_command_id}' IS DISTINCT FROM v_prev::text
     OR strpos(r_confirm #>> '{data,summary}', 'until the production run ends') = 0
     OR strpos(r_confirm #>> '{data,expires}', 'production run') = 0 OR v_ledger IS DISTINCT FROM 'confirm' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the confirm of the recorded preview was not applied, bound and recorded under the person: % (ledger %)', r_confirm, v_ledger;
  END IF;
  IF v_t_confirm IS DISTINCT FROM v_low THEN
    RAISE EXCEPTION '0721 V3 FAILED: the engine reads % as the car''s target, not the owner''s confirmed %', v_t_confirm, v_low;
  END IF;
  IF r_again #>> '{data,outcome}' = 'applied' OR v_twice <> 'refused' OR v_bogus <> 'refused' THEN
    RAISE EXCEPTION '0721 V3 FAILED: a preview confirmed a second apply (% / %) or a non-preview was confirmed (%)', r_again, v_twice, v_bogus;
  END IF;
  IF r_mid #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_mid #>> '{data,command,via}' IS DISTINCT FROM 'direct'
     OR (r_undo ->> 'http_status')::int <> 422 OR r_undo #>> '{error,code}' IS DISTINCT FROM 'confirm_required'
     OR r_undo #>> '{data,outcome}' IS DISTINCT FROM 'previewed' OR v_t_undo IS DISTINCT FROM v_mid THEN
    RAISE EXCEPTION '0721 V3 FAILED: a raise took more than one call, or an undo that lowers was applied unconfirmed (target %): % / %', v_t_undo, r_mid, r_undo;
  END IF;
  IF r_other #>> '{error,code}' IS DISTINCT FROM 'confirm_required' OR r_other #>> '{data,refusal,reason}' IS DISTINCT FROM 'no_recorded_preview'
     OR r_other #>> '{data,outcome}' IS DISTINCT FROM 'previewed' OR r_other #>> '{data,command,via}' IS DISTINCT FROM 'direct'
     OR v_t_other IS DISTINCT FROM (v_ctr ->> 'max_charge_pct')::numeric THEN
    RAISE EXCEPTION '0721 V3 FAILED: another principal confirmed a preview it did not make (target %): %', v_t_other, r_other;
  END IF;
  IF r_undone #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_undone #>> '{data,command,via}' IS DISTINCT FROM 'confirm'
     OR r_undone #>> '{data,command,confirms_command_id}' IS DISTINCT FROM r_undo #>> '{data,command,command_id}'
     OR v_t_undone IS DISTINCT FROM v_low THEN
    RAISE EXCEPTION '0721 V3 FAILED: the confirm of the undo''s recorded preview was not applied and bound (target %): %', v_t_undone, r_undone;
  END IF;
  IF v_guard <> 'refused' OR v_back <> 'refused' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the guard (%) or the production backstop (%) let the row through', v_guard, v_back;
  END IF;
  IF r_clear #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_clear #>> '{data,command,via}' IS DISTINCT FROM 'direct' THEN
    RAISE EXCEPTION '0721 V3 FAILED: clearing the limit in production took more than one call, or the arguments set the door: %', r_clear;
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
     OR EXISTS (SELECT 1 FROM public.ottoq_agent_principals WHERE principal_id IN (v_pid, v_pid2))
     OR EXISTS (SELECT 1 FROM public.ottoq_agent_principals WHERE name IN ('v0721-probe-passcode', 'v0721-probe-key'))
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_commands WHERE acting_person = c_email OR sim_run_id = v_run) THEN
    RAISE EXCEPTION '0721 V3 FAILED: the probe left rows behind';
  END IF;
  RAISE NOTICE '0721 V3 PASSED: production at the twin depot takes a signed-in person (% on %), refuses a passcode and a key, and lowers a limit (or undoes a raise) only as the one confirm of a preview the same principal recorded', c_email, v_run;
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
  'person (acting_person, from a 0700 sign-in), the door (via: ottocommand, confirm or direct) and the preview an apply '
  'confirmed (confirms_command_id); production_live runs take owner commands from a signed-in person only, and lower a '
  'charge limit there only as the one confirm of a preview the same principal recorded in the last 15 minutes (rule 9); '
  'a backstop refuses an applied production command with no person (rule 10) and a confirm of anything but such a '
  'preview. Agent door only: ottoq_agent_call, ottoq_owner_command, its '
  'receipt, whoami and the owner-commands guard. No arm reaches any of them, and no arm can run while a run is live '
  '(every runner''s guard), so no certified run changes: FALSE/FALSE.',
  now());

COMMIT;
