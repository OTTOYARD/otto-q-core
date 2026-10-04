-- migration-version: PENDING
-- migration-name:    an_outside_agent_asks_through_one_door_and_a_person_decides
--
-- 0559  **An outside agent asks through one door, and a person decides.** Hermes, a fleet manager's own agent, or a
--       depot-operations agent can now hold a credential for this engine, read the twin depot within a scope the
--       database enforces, and ASK for a change. Nothing it asks for happens until a person approves it, and nothing
--       a person approves happens except through a door the engine already has. Where no door exists, the approval
--       is recorded as exactly that -- `approved_no_engine_door` -- instead of pretending to an effect.
--
--       The law this file is written under: OTTO-Q decides, OTTO-TWIN executes and owns world state, the renderer
--       only draws. An agent PROPOSES, a person APPROVES, the engine's own doors (and behind them its L1 shield)
--       DISPOSE. Nothing in this file writes a vehicle, a stall, a booking, a session or a command directly.
--
-- ══ §1 WHAT WAS MISSING (measured 2026-09-28 04:30-05:10 UTC, 11:30 PM-12:10 AM CT, read-only) ══════════════════
--
--   AGENT_HARNESS.md ranks "no agent-facing door" second among the gaps: there is a database door for proposals
--   (ottoq_submit_external_proposal) but nothing an outside agent can hold a credential for, no record of what an
--   outside agent asked, and no place a person answers it.
--
--   (a) THE ONLY CREDENTIAL TABLE IS THE WRONG ONE. `ottow_api_keys` is the webhook-ingestion key: otto-q-api
--       accepts any row in it on `X-OTTO-Q-API-Key` as an ingestion SOURCE (oem_webhook / fleet_api /
--       vehicle_telemetry). An agent token stored there would be able to post ingestion traffic. So this file does
--       not reuse it; it builds a principal table whose rows can do nothing but reach the dispatcher below.
--   (b) OrchestrAV reaches this database only with the anon key; its user -> fleet-operator binding is client-side
--       and spoofable. The one server-side binding that exists is `fleet_operators.auth_user_id`, and it is NULL for
--       all four operators. So "an operator decides only their own fleet's requests" can be enforced here, but it
--       cannot be USED from OrchestrAV until that cockpit signs its users in to this project. Stated in §4.
--   (c) The doors an approval can route to are live, SECURITY DEFINER, and closed to anon:
--         ottoq_hw_recall_vehicle(uuid,text,text)             queues a `begin_charge` command for the twin
--         ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)   whitelist: raise_deploy_surge, extend_forecast_horizon,
--                                                             enable_energy_reserve (0491 refuses anything else)
--       Of the three dials behind that whitelist only `energy_reserve_shave` is `agent_writable`;
--       `deploy_surge_catchup` and `forecast_horizon_min` are not (0438, G175: nothing reads them). An agent asking
--       for either is refused HERE, at submission, with the catalog's reason -- never queued for a person, because
--       a person approving a change the setter will refuse, or one nothing reads, is worse than no request
--       (the same doctrine `_shared/agent_dial_discipline.ts` applies to the orchestrator agent).
--   (d) THE RECALL DOOR IS REAL AND ITS EFFECT PATH IS UNPROVEN. `issued_by='cockpit_recall'` appears on exactly ONE
--       command in the engine's life (2026-08-16 03:50 UTC), and it ended `expired` without executing. `begin_charge`
--       commands from other issuers do execute (145 executed / 54 issued / 28 refused / 3 expired, all issuers). So an
--       approved recall request records the door's reply faithfully ("queued"), and whether the twin then brings the
--       vehicle home is NOT yet observed. §4 and AGENT_GATEWAY.md say so in the same breath as the feature.
--
-- ══ §2 WHAT THIS BUILDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   THREE TABLES
--     ottoq_agent_principals   who an agent is: kind (personal | fleet_operator | depot_ops), depot scope (the twin
--                              depot only -- CLAUDE.md rule 8), optional fleet-operator scope, capabilities, the
--                              SHA-256 of its token (the token itself is never stored), active/revoked. A token's
--                              scope is FIXED at issue: to change it, issue a new principal and revoke the old one.
--     ottoq_agent_requests     what an agent asked and what became of it. A lifecycle, guarded by a trigger: only a
--                              pending row may change, only its decision columns, and what was asked is immutable.
--                              Registered class='evidence' with NO foreign key to ottoq_sim_runs -- the 0340 pattern
--                              and its reasoning, unchanged: check (b) of ottoq_check_run_scope_registry demands an
--                              FK for engine/stamp only, and an enforcing FK on evidence could only block
--                              ottoq_purge_prior_runs or, as CASCADE, erase what check (c) forbids erasing. So a
--                              request survives the demo-run purge of the run it was made against.
--     ottoq_agent_call_ledger  every gateway call, reads included: principal, tool, ok/error, status, latency.
--                              Append-only. Not run-scoped (no run column), so it needs no registry row.
--
--   ONE DISPATCHER, service_role only: ottoq_agent_call(token_hash, tool, args, transport, meta). The edge function
--   hashes the Bearer token and calls this; the database resolves the principal, refuses a revoked or unknown token,
--   applies the per-principal rate limit, checks the capability, runs the tool, and writes the call ledger -- in one
--   transaction. The scoping lives HERE and not in the edge function, for the reason AGENT_HARNESS.md gives: a
--   guardrail inside the wrapper is bypassed by anything that does not go through the wrapper. Arguments the edge
--   function refuses against a tool's published schema still come here first (meta.gateway_refusal), so even a
--   malformed call is authenticated, rate-limited and ledgered: an unknown token learns nothing from one.
--
--   NINE TOOLS behind it: whoami, depot_status (the live run through ottoq_twin_run_context), fleet_summary
--   (ottoq_depot_cards with the principal's operator filter), vehicle_card (ottoq_vehicle_card after an ownership
--   check), recent_decisions (ottoq_activity_feed, operator-filtered), stall_availability (the THREE-GATE rule:
--   pointer n calendar-in-SIM-time n charger-not-Faulted, the calendar and charger gates read through
--   ottoq.ottoq_stall_free_between -- the engine's own shared candidate source -- and never against now()),
--   list_requests, send_note, submit_request. The two write tools insert into ottoq_agent_requests and nothing else.
--
--   THE PEOPLE'S DOORS, authenticated only:
--     ottoq_agent_inbox(depot)            PULSE: the depot crew's inbox (staff of that depot, any role, may read)
--     ottoq_agent_request_decide(id, ..)  approve / decline. Crew = a yard_supervisor or ops_manager of the request's
--                                         depot (the level PULSE already asks for `ai.approve_action`). Operator = the
--                                         auth user bound in fleet_operators.auth_user_id, deciding only requests of
--                                         its own fleet, never a depot-wide ops action. Identity is read from the
--                                         session (auth.uid()), never from an argument.
--     ottoq_agent_requests_for_operator   OrchestrAV: one operator's requests. anon is NOT granted here; 0560 is the
--                                         separate, optional file that grants it, because it is an exposure decision.
--
--   ROUTING ON APPROVAL (total: every kind lands in a defined status)
--     note            -> acknowledged                (notes are delivered; there is nothing to apply)
--     recall_vehicle  -> ottoq_hw_recall_vehicle     -> applied | refused_by_engine | apply_failed
--     ops_action      -> ottoq_apply_ops_action      -> applied | refused_by_engine | apply_failed
--                        (on the run the request was made against, and only while that run is live; otherwise
--                        approved_not_applied, and the door is not called)
--     adjustment      -> approved_no_engine_door     (recorded; nothing in the engine changes)
--   The ops door is called with p_by = 'ottoq_prime:agent_gateway:<principal>'. ottoq_is_agent_actor treats that as
--   an agent (the ':' suffix form, the precedent is 'ottoq_prime:promoter'), so ottoq_policy_set still applies the
--   AGENT envelope and the agent_writable guard, and AI.001 still judges it at `policy_write`. A person's approval
--   does not launder an agent's request into a person-privileged write. P1 asserts this before anything is built.
--
-- ══ §3 THE SECURITY MODEL ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   * Tokens: 'oqa_' + 64 hex characters (32 bytes of pgcrypto gen_random_bytes). Returned ONCE by
--     ottoq_agent_issue_token; only sha256(token) is stored. The edge function hashes before it calls, so the raw
--     token never reaches the database at all after issue.
--   * Every table here has RLS enabled with no policy, and no privilege for anon or authenticated; service_role keeps
--     no write privilege either (TRUNCATE included -- a row trigger cannot see a TRUNCATE, so it is also refused by a
--     statement trigger). Every function is revoked from PUBLIC, anon, authenticated and service_role, then granted
--     to exactly the roles named in §2. The Supabase default ACL grants a new function to anon, and PUBLIC keeps its
--     built-in EXECUTE unless revoked -- the "REVOKE that removed nothing" class 0405 records -- so V3 asserts every
--     grant with has_function_privilege rather than trusting the statements.
--   * The internal tool functions take a principal ROW. Nobody may execute them but the owner: a caller that could
--     pass its own principal row would not need a token. V3 asserts that for service_role too.
--   * A scope miss reads exactly like a missing vehicle ("not found in your scope"), so a fleet-scoped agent cannot
--     probe for another operator's vehicle ids.
--   * The rate limit counts the call ledger, not memory: 60 calls a minute per principal by default. Failed-auth calls
--     are ledgered too, bounded at 60 a minute so an attacker without a token cannot grow the ledger without limit.
--
-- ══ §4 WHAT IT DELIBERATELY DOES NOT DO ═════════════════════════════════════════════════════════════════════════════
--
--   * It writes no world state and calls no door on an agent's say-so. Only ottoq_agent_request_decide calls a door,
--     and only for a signed-in person with the authority above. V5 asserts, on comment-stripped source, that no
--     function an agent's token can reach names a door or writes outside the ottoq_agent_* tables.
--   * It does not bypass the shield and it does not claim the shield judges a recall at issue: the recall door queues
--     a command (as it does for the cockpit) and the kernel disposes downstream when the vehicle arrives.
--   * It does not submit physical proposals (stall assignments). ottoq_submit_external_proposal remains THE door for
--     that seat, and wiring an outside agent to it is a separate, later decision.
--   * It schedules nothing: no pg_cron job. Lapsed requests are expired lazily (on the next submit by that principal,
--     on a decision attempt, and computed on every read); ottoq_agent_expire_lapsed() exists for a future job.
--   * It gives OrchestrAV no way to DECIDE yet. The operator path is enforced here, but OrchestrAV has no session on
--     this project and fleet_operators.auth_user_id is empty. Until both change, the depot crew decides in PULSE.
--   * It emits no ottoq_events row. Whether a person answering an agent counts as a KPI-4 touch is a doctrine
--     question for Chase, not something to decide inside a gateway.
--   * It sets no retention on the call ledger. At the default rate limit a busy principal writes at most 86,400 rows
--     a day; a retention rule is a follow-up, named rather than guessed.
--
-- ══ §5 forces_recert FALSE, forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   Purely additive: three new tables, new functions, one registry row. No existing function body changes, nothing on
--   the tick path reads the new tables (V8 asserts no pre-existing routine names them), and a certification pair runs
--   both arms in one transaction with no outside input, so it cannot carry an agent request. The doors this file CALLS
--   are called only from ottoq_agent_request_decide, which requires a signed-in person. The same holds for a dial pair,
--   so forces_dial_restart is written FALSE -- explicitly, because 0523 reads a NULL there as "restart every dial
--   experiment's pair count".
--
-- ══ §6 VALIDATED ON A SCRATCH CLUSTER, BECAUSE compile-check CANNOT SEE THIS ═══════════════════════════════════════════
--
--   scripts/compile-check.py stops at P1 in an empty database (by design) and compiles only DO blocks and
--   CREATE OR REPLACE ... plpgsql bodies whose types exist. So, like 0364, this file was executed for real against a
--   local PostgreSQL 16 cluster loaded with tests/fixtures/agent_gateway_stub_engine.sql -- a stub engine whose two
--   doors (ottoq_hw_recall_vehicle, ottoq_apply_ops_action) and whose ottoq_policy_set, ottoq_dial_clamp,
--   ottoq_is_agent_actor, ottoq_policy_get, ottoq.ottoq_stall_free_between and ottoq_check_run_scope_registry are the
--   LIVE bodies copied from the catalog on 2026-09-28 -- and driven end to end by tests/test_agent_gateway_sql.py
--   (issue, read, scope, submit, decide as crew and as operator, route, refuse, expire, revoke, rate-limit). That test
--   skips where no scratch server exists; its counts are in the PR, not claimed here.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: pg_stat_activity keeps 1 kB of query text and the recert runner (cron 746) names
          -- ottoq_determinism_pair only at character 1,303, so the clause above never sees it. Its
          -- advisory-lock key is in its first 100 characters.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0559 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: every object this file READS or CALLS is the one it was written against ──
DO $premises$
DECLARE
  v_recall regprocedure := to_regprocedure('public.ottoq_hw_recall_vehicle(uuid,text,text)');
  v_ops    regprocedure := to_regprocedure('public.ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)');
  v_src    text;
  v_need   text;
BEGIN
  -- the two doors an approval routes to: present, jsonb, SECURITY DEFINER, closed to anon
  IF v_recall IS NULL OR v_ops IS NULL THEN
    RAISE EXCEPTION '0559 P1: a door this file routes to is missing (recall %, ops %)', v_recall, v_ops;
  END IF;
  IF (SELECT prorettype FROM pg_proc WHERE oid = v_recall) <> 'jsonb'::regtype
     OR (SELECT prorettype FROM pg_proc WHERE oid = v_ops) <> 'jsonb'::regtype
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_recall)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_ops)
     OR has_function_privilege('anon', v_recall, 'EXECUTE')
     OR has_function_privilege('anon', v_ops, 'EXECUTE') THEN
    RAISE EXCEPTION '0559 P1: a door is not the jsonb SECURITY DEFINER anon-closed function this file was written against';
  END IF;
  -- the replies the router maps: recall answers ok true/false; the ops door applied / no_change / refused
  v_src := (SELECT prosrc FROM pg_proc WHERE oid = v_recall);
  IF position('''ok'', true' IN v_src) = 0 OR position('''ok'', false' IN v_src) = 0 THEN
    RAISE EXCEPTION '0559 P1: ottoq_hw_recall_vehicle no longer answers {ok: true|false}';
  END IF;
  v_src := (SELECT prosrc FROM pg_proc WHERE oid = v_ops);
  FOREACH v_need IN ARRAY ARRAY[
      $a$p_action = 'raise_deploy_surge'$a$,      $a$v_param := 'deploy_surge_catchup'$a$,
      $a$p_action = 'extend_forecast_horizon'$a$, $a$v_param := 'forecast_horizon_min'$a$,
      $a$p_action = 'enable_energy_reserve'$a$,   $a$v_param := 'energy_reserve_shave'$a$,
      $a$'status','applied'$a$, $a$'status','no_change'$a$, $a$'status','refused'$a$] LOOP
    IF position(v_need IN v_src) = 0 THEN
      RAISE EXCEPTION '0559 P1: ottoq_apply_ops_action no longer contains %; re-read its whitelist before routing to it', v_need;
    END IF;
  END LOOP;
  -- an approval must not launder the agent's request into a person-privileged write
  IF NOT public.ottoq_is_agent_actor('ottoq_prime:agent_gateway:probe') THEN
    RAISE EXCEPTION '0559 P1: ottoq_is_agent_actor no longer treats ottoq_prime:<suffix> as an agent';
  END IF;
  -- the reads this file composes
  IF to_regprocedure('public.ottoq_depot_cards(uuid,uuid)') IS NULL
     OR to_regprocedure('public.ottoq_vehicle_card(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_twin_run_context(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)') IS NULL
     OR to_regprocedure('ottoq.ottoq_stall_free_between(uuid,uuid,timestamp with time zone,timestamp with time zone,text,text,integer,text[])') IS NULL THEN
    RAISE EXCEPTION '0559 P1: a read this file composes is missing';
  END IF;
  -- the columns the people's doors and the catalog check read
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='fleet_operators' AND column_name='auth_user_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staff_users' AND column_name='auth_user_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='ottoq_policy_param_catalog' AND column_name='agent_writable') THEN
    RAISE EXCEPTION '0559 P1: fleet_operators.auth_user_id, staff_users.auth_user_id or ottoq_policy_param_catalog.agent_writable is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'staff_role' AND e.enumlabel = 'yard_supervisor')
     OR NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'staff_role' AND e.enumlabel = 'ops_manager') THEN
    RAISE EXCEPTION '0559 P1: staff_role no longer has yard_supervisor and ops_manager';
  END IF;
  IF to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL THEN
    RAISE EXCEPTION '0559 P1: pgcrypto gen_random_bytes is not in the extensions schema';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION '0559 P1: the twin depot does not exist';
  END IF;
END $premises$;

-- ── P2: nothing this file creates exists yet, and the registry guard is clean before it is touched ──
DO $fresh$
DECLARE v_block int; v_fn text;
BEGIN
  IF to_regclass('public.ottoq_agent_principals') IS NOT NULL
     OR to_regclass('public.ottoq_agent_requests') IS NOT NULL
     OR to_regclass('public.ottoq_agent_call_ledger') IS NOT NULL THEN
    RAISE EXCEPTION '0559 P2: an ottoq_agent_* table already exists; this file has already been applied';
  END IF;
  SELECT string_agg(p.proname, ', ') INTO v_fn
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('ottoq_agent_ledger_append_only','ottoq_agent_requests_guard','ottoq_agent_principals_guard',
                       'ottoq_agent_no_truncate','ottoq_agent_arg_int','ottoq_agent_arg_uuid','ottoq_agent_resolve',
                       'ottoq_agent_live_run','ottoq_agent_vehicle_in_scope','ottoq_agent_compact_card',
                       'ottoq_agent_request_json','ottoq_agent_read_whoami','ottoq_agent_read_depot',
                       'ottoq_agent_read_fleet','ottoq_agent_read_vehicle','ottoq_agent_read_decisions',
                       'ottoq_agent_read_stalls','ottoq_agent_read_requests','ottoq_agent_submit_request',
                       'ottoq_agent_call','ottoq_agent_issue_token','ottoq_agent_revoke','ottoq_agent_expire_lapsed',
                       'ottoq_agent_inbox','ottoq_agent_request_decide','ottoq_agent_requests_for_operator');
  IF v_fn IS NOT NULL THEN
    RAISE EXCEPTION '0559 P2: function(s) this file creates already exist: %', v_fn;
  END IF;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0559 P2: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $fresh$;

-- ══ 1. the tables ═══════════════════════════════════════════════════════════════════════════════════════════════════

CREATE TABLE public.ottoq_agent_principals (
  principal_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name               text NOT NULL,
  kind               text NOT NULL,
  --: CLAUDE.md rule 8: the twin depot is the only site. ottoq_agent_issue_token refuses any other.
  depot_id           uuid NOT NULL DEFAULT '11111111-1111-1111-1111-111111111111'::uuid REFERENCES public.depots(id),
  --: NULL = sees every owner at the depot (personal / depot_ops). Set = sees only this operator's vehicles.
  fleet_operator_id  uuid REFERENCES public.fleet_operators(id),
  capabilities       text[] NOT NULL DEFAULT ARRAY['read','note']::text[],
  --: sha256(token) as lowercase hex. The token itself is never stored.
  token_hash         text NOT NULL,
  --: 'oqa_' + the first 8 hex characters: enough to tell tokens apart, 32 of 256 bits.
  token_prefix       text NOT NULL,
  status             text NOT NULL DEFAULT 'active',
  rate_limit_per_min integer NOT NULL DEFAULT 60,
  max_pending        integer NOT NULL DEFAULT 20,
  note               text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         text NOT NULL DEFAULT session_user,
  last_used_at       timestamptz,
  revoked_at         timestamptz,
  revoked_reason     text,
  CONSTRAINT ottoq_agent_principals_name_key UNIQUE (name),
  CONSTRAINT ottoq_agent_principals_token_hash_key UNIQUE (token_hash),
  CONSTRAINT ottoq_agent_principals_name_check CHECK (name ~ '^[a-z0-9][a-z0-9_.-]{1,62}$'),
  CONSTRAINT ottoq_agent_principals_kind_check CHECK (kind IN ('personal', 'fleet_operator', 'depot_ops')),
  CONSTRAINT ottoq_agent_principals_fleet_scope_check CHECK (kind <> 'fleet_operator' OR fleet_operator_id IS NOT NULL),
  CONSTRAINT ottoq_agent_principals_depot_ops_scope_check CHECK (kind <> 'depot_ops' OR fleet_operator_id IS NULL),
  --: owner_settings (0605) and an oqs_ prefix (0607's passcode session) are admitted in the table's first shape. All three
  --: files were written before any was applied, and a later file that widened a CHECK would have to DROP it first. This
  --: file issues neither: ottoq_agent_issue_token refuses owner_settings and mints only oqa_ keys.
  CONSTRAINT ottoq_agent_principals_capabilities_check CHECK (
    cardinality(capabilities) > 0
    AND capabilities <@ ARRAY['read','note','request_recall','request_ops_action','request_adjustment','owner_settings']::text[]),
  --: an ops action changes the whole depot; a fleet-scoped principal may not ask for one
  CONSTRAINT ottoq_agent_principals_ops_scope_check CHECK (
    NOT ('request_ops_action' = ANY (capabilities)) OR fleet_operator_id IS NULL),
  CONSTRAINT ottoq_agent_principals_token_hash_check CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT ottoq_agent_principals_token_prefix_check CHECK (token_prefix ~ '^oq[as]_[0-9a-f]{8}$'),
  CONSTRAINT ottoq_agent_principals_status_check CHECK (status IN ('active', 'revoked')),
  CONSTRAINT ottoq_agent_principals_revoked_check CHECK ((status = 'revoked') = (revoked_at IS NOT NULL)),
  CONSTRAINT ottoq_agent_principals_rate_check CHECK (rate_limit_per_min BETWEEN 1 AND 600),
  CONSTRAINT ottoq_agent_principals_pending_check CHECK (max_pending BETWEEN 1 AND 200)
);

COMMENT ON TABLE public.ottoq_agent_principals IS
'0559. An outside agent''s identity for the ottoq-agent-gateway: kind (personal | fleet_operator | depot_ops), the depot it is scoped to (the twin depot only, CLAUDE.md rule 8), an optional fleet-operator scope, its capabilities (read, note, request_recall, request_ops_action, request_adjustment) and the SHA-256 of its token. The token is shown once by ottoq_agent_issue_token and never stored. A principal''s scope is FIXED at issue (a trigger refuses any change but last_used_at and revocation): to change what an agent may do, issue a new principal and revoke the old one. Not ottow_api_keys, deliberately: a row there is an ingestion source for otto-q-api.';

CREATE TABLE public.ottoq_agent_requests (
  request_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id      uuid NOT NULL REFERENCES public.ottoq_agent_principals(principal_id),
  --: frozen at submission, so history reads right after a revocation
  principal_name    text NOT NULL,
  principal_kind    text NOT NULL,
  depot_id          uuid NOT NULL,
  --: whose request this is: the principal's operator, else the target vehicle's, else NULL (depot-wide)
  fleet_operator_id uuid,
  --: Durable historical key. NO FOREIGN KEY, deliberately (0340's reasoning): the run row may be purged; this row
  --: must not be.
  sim_run_id        uuid,
  --: that run's SIM clock at submission. SIM domain: never compared with now().
  sim_clock         timestamptz,
  kind              text NOT NULL,
  --: durable key, no FK: the ledger outlives any vehicle row
  vehicle_id        uuid,
  vehicle_label     text,
  title             text NOT NULL,
  body              text,
  payload           jsonb NOT NULL DEFAULT '{}'::jsonb,
  priority          text NOT NULL DEFAULT 'normal',
  idempotency_key   text,
  status            text NOT NULL DEFAULT 'pending',
  decision          text,
  decided_by_kind   text,
  decided_by_uid    uuid,
  decided_by_label  text,
  decision_note     text,
  decided_at        timestamptz,
  --: set only when a door was actually called
  engine_door       text,
  engine_reply      jsonb,
  applied_at        timestamptz,
  --: why a row closed without a decision (lapsed, principal revoked)
  closed_reason     text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  --: REAL time. Agents and people act on the wall clock; this is never compared with a sim clock.
  expires_at        timestamptz NOT NULL,
  CONSTRAINT ottoq_agent_requests_kind_check CHECK (kind IN ('note', 'recall_vehicle', 'ops_action', 'adjustment')),
  CONSTRAINT ottoq_agent_requests_priority_check CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  CONSTRAINT ottoq_agent_requests_status_check CHECK (status IN (
    'pending', 'declined', 'expired', 'acknowledged', 'applied', 'refused_by_engine',
    'approved_no_engine_door', 'approved_not_applied', 'apply_failed')),
  --: a note is delivered or dismissed; only a request can be applied
  CONSTRAINT ottoq_agent_requests_kind_status_check CHECK (
    (kind = 'note' AND status IN ('pending', 'declined', 'expired', 'acknowledged'))
    OR (kind <> 'note' AND status <> 'acknowledged')),
  CONSTRAINT ottoq_agent_requests_decision_check CHECK (
       (status = 'pending'  AND decision IS NULL AND decided_at IS NULL)
    OR (status = 'expired'  AND decision IS NULL AND decided_at IS NULL)
    OR (status = 'declined' AND decision = 'declined' AND decided_at IS NOT NULL AND decided_by_kind IS NOT NULL)
    OR (status IN ('acknowledged', 'applied', 'refused_by_engine', 'approved_no_engine_door', 'approved_not_applied',
                   'apply_failed')
        AND decision = 'approved' AND decided_at IS NOT NULL AND decided_by_kind IS NOT NULL)),
  CONSTRAINT ottoq_agent_requests_decider_check CHECK (decided_by_kind IS NULL OR decided_by_kind IN ('crew', 'operator')),
  CONSTRAINT ottoq_agent_requests_title_check CHECK (char_length(title) BETWEEN 1 AND 140),
  CONSTRAINT ottoq_agent_requests_body_check CHECK (body IS NULL OR char_length(body) <= 4000),
  CONSTRAINT ottoq_agent_requests_payload_check CHECK (jsonb_typeof(payload) = 'object' AND octet_length(payload::text) <= 4000),
  CONSTRAINT ottoq_agent_requests_recall_vehicle_check CHECK (kind <> 'recall_vehicle' OR vehicle_id IS NOT NULL),
  CONSTRAINT ottoq_agent_requests_ops_action_check CHECK (kind <> 'ops_action' OR (payload ? 'action' AND vehicle_id IS NULL)),
  CONSTRAINT ottoq_agent_requests_idempotency_check CHECK (idempotency_key IS NULL OR idempotency_key ~ '^[A-Za-z0-9._:-]{1,100}$'),
  CONSTRAINT ottoq_agent_requests_expiry_check CHECK (expires_at > created_at)
);

COMMENT ON TABLE public.ottoq_agent_requests IS
'0559. What an outside agent asked and what became of it -- the request/decision ledger behind the agent inbox in OTTO-PULSE and the agent-requests panel in OrchestrAV. Lifecycle: pending -> declined | expired | acknowledged (a note) | applied | refused_by_engine | approved_no_engine_door | approved_not_applied | apply_failed. `decision` is the person''s verdict; `status` is where the request ended up; `engine_door` / `engine_reply` are the door that was called and exactly what it said. A trigger freezes a closed row and freezes what was asked on an open one. Registered class=evidence with NO foreign key to ottoq_sim_runs (0340''s reasoning), so a request survives the purge of the run it was made against; sim_run_id is a durable historical key. expires_at is REAL time; sim_clock is SIM time.';

CREATE UNIQUE INDEX ottoq_agent_requests_idempotency_idx
  ON public.ottoq_agent_requests (principal_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX ottoq_agent_requests_inbox_idx ON public.ottoq_agent_requests (depot_id, status, created_at DESC);
CREATE INDEX ottoq_agent_requests_principal_idx ON public.ottoq_agent_requests (principal_id, created_at DESC);
CREATE INDEX ottoq_agent_requests_operator_idx
  ON public.ottoq_agent_requests (fleet_operator_id, created_at DESC) WHERE fleet_operator_id IS NOT NULL;
CREATE INDEX ottoq_agent_requests_vehicle_idx
  ON public.ottoq_agent_requests (vehicle_id, status) WHERE vehicle_id IS NOT NULL;
CREATE INDEX ottoq_agent_requests_run_idx ON public.ottoq_agent_requests (sim_run_id) WHERE sim_run_id IS NOT NULL;

CREATE TABLE public.ottoq_agent_call_ledger (
  call_id           bigserial PRIMARY KEY,
  --: NULL when the token did not resolve
  principal_id      uuid REFERENCES public.ottoq_agent_principals(principal_id),
  principal_name    text,
  transport         text NOT NULL,
  tool              text NOT NULL,
  http_method       text,
  path              text,
  ok                boolean NOT NULL,
  http_status       integer,
  error_code        text,
  latency_ms        integer,
  --: the request a write tool created or replayed
  request_id        uuid,
  depot_id          uuid,
  fleet_operator_id uuid,
  detail            jsonb NOT NULL DEFAULT '{}'::jsonb,
  called_at         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_agent_call_ledger IS
'0559. One row per call an outside agent made to the ottoq-agent-gateway, reads included: principal, transport (rest | mcp), tool, ok, HTTP status, error code, latency. Written by ottoq_agent_call in the same transaction as the tool it ran, so a write tool''s row and its request row commit together. Append-only (override: ottoq.agent_ledger_unlock=on in a migration that says why). Calls with an unknown or revoked token are ledgered with principal_id NULL, bounded at 60 a minute. Calls refused before the database (a malformed token, an oversized body) are not here; the edge function answers those itself. No retention rule yet.';

CREATE INDEX ottoq_agent_call_ledger_principal_idx ON public.ottoq_agent_call_ledger (principal_id, called_at DESC);
CREATE INDEX ottoq_agent_call_ledger_unauth_idx ON public.ottoq_agent_call_ledger (called_at) WHERE principal_id IS NULL;
CREATE INDEX ottoq_agent_call_ledger_at_idx ON public.ottoq_agent_call_ledger (called_at DESC);

-- ══ 2. the guards: a ledger that can be edited proves nothing ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_agent_ledger_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'ottoq_agent_call_ledger is append-only: % refused. Set ottoq.agent_ledger_unlock=on in the session to override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_no_truncate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $fn$
BEGIN
  --: a row trigger cannot see TRUNCATE, so the ledgers refuse it here as well
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN NULL;
  END IF;
  RAISE EXCEPTION '% keeps every row: TRUNCATE refused. Set ottoq.agent_ledger_unlock=on in the session to override, and say why in a migration.', TG_TABLE_NAME
    USING ERRCODE = '42501';
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_requests_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'ottoq_agent_requests keeps every request: DELETE refused' USING ERRCODE = '42501';
  END IF;
  IF OLD.status <> 'pending' THEN
    RAISE EXCEPTION 'agent request % is closed (%); a closed request cannot change', OLD.request_id, OLD.status
      USING ERRCODE = '42501';
  END IF;
  --: what was asked is immutable; only the decision columns of an open request move
  IF (NEW.request_id, NEW.principal_id, NEW.principal_name, NEW.principal_kind, NEW.depot_id, NEW.fleet_operator_id,
      NEW.sim_run_id, NEW.sim_clock, NEW.kind, NEW.vehicle_id, NEW.vehicle_label, NEW.title, NEW.body, NEW.payload,
      NEW.priority, NEW.idempotency_key, NEW.created_at, NEW.expires_at)
     IS DISTINCT FROM
     (OLD.request_id, OLD.principal_id, OLD.principal_name, OLD.principal_kind, OLD.depot_id, OLD.fleet_operator_id,
      OLD.sim_run_id, OLD.sim_clock, OLD.kind, OLD.vehicle_id, OLD.vehicle_label, OLD.title, OLD.body, OLD.payload,
      OLD.priority, OLD.idempotency_key, OLD.created_at, OLD.expires_at) THEN
    RAISE EXCEPTION 'agent request %: what was asked is immutable; only its decision may be recorded', OLD.request_id
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_principals_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'ottoq_agent_principals keeps every principal: DELETE refused (revoke with ottoq_agent_revoke)'
      USING ERRCODE = '42501';
  END IF;
  --: a token's scope is fixed at issue
  IF (NEW.principal_id, NEW.name, NEW.kind, NEW.depot_id, NEW.fleet_operator_id, NEW.capabilities, NEW.token_hash,
      NEW.token_prefix, NEW.rate_limit_per_min, NEW.max_pending, NEW.note, NEW.created_at, NEW.created_by)
     IS DISTINCT FROM
     (OLD.principal_id, OLD.name, OLD.kind, OLD.depot_id, OLD.fleet_operator_id, OLD.capabilities, OLD.token_hash,
      OLD.token_prefix, OLD.rate_limit_per_min, OLD.max_pending, OLD.note, OLD.created_at, OLD.created_by) THEN
    RAISE EXCEPTION 'agent principal %: its scope is fixed at issue; issue a new principal and revoke this one', OLD.name
      USING ERRCODE = '42501';
  END IF;
  --: a revocation is final
  IF OLD.status = 'revoked' AND (NEW.status <> 'revoked' OR NEW.revoked_at IS DISTINCT FROM OLD.revoked_at
                                 OR NEW.revoked_reason IS DISTINCT FROM OLD.revoked_reason) THEN
    RAISE EXCEPTION 'agent principal % is revoked; a revocation cannot be undone', OLD.name USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $fn$;

CREATE TRIGGER ottoq_agent_call_ledger_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_agent_call_ledger
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_ledger_append_only();
CREATE TRIGGER ottoq_agent_call_ledger_no_truncate_trg
  BEFORE TRUNCATE ON public.ottoq_agent_call_ledger
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_agent_requests_guard_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_agent_requests
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_requests_guard();
CREATE TRIGGER ottoq_agent_requests_no_truncate_trg
  BEFORE TRUNCATE ON public.ottoq_agent_requests
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_agent_principals_guard_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_agent_principals
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_principals_guard();
CREATE TRIGGER ottoq_agent_principals_no_truncate_trg
  BEFORE TRUNCATE ON public.ottoq_agent_principals
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();

-- ══ 3. register the one run-scoped column, as evidence ══════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_agent_requests', 'sim_run_id', 'evidence',
        '0559: the run an outside agent''s request was made against. Evidence, not engine: the request, the person''s decision and the engine''s reply must survive ottoq_purge_prior_runs. Deliberately NO foreign key to ottoq_sim_runs -- check (b) asks for one from engine/stamp only, and an enforcing FK on evidence can only block the purge or, as CASCADE, erase what check (c) forbids erasing (0340).');

-- ══ 4. small internal helpers ═══════════════════════════════════════════════════════════════════════════════════════
--
-- Business refusals are raised with house SQLSTATEs so the dispatcher can map them to an HTTP status and roll back
-- whatever the tool had started: OQA01 invalid arguments (400), OQA03 forbidden (403), OQA04 not found (404),
-- OQA09 conflict (409), OQA22 refused (422), OQA29 too many (429). MESSAGE is the machine code, DETAIL the sentence.

CREATE OR REPLACE FUNCTION public.ottoq_agent_arg_int(p_args jsonb, p_key text, p_default integer, p_min integer, p_max integer)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
DECLARE v jsonb := p_args -> p_key; v_txt text;
BEGIN
  IF v IS NULL OR jsonb_typeof(v) = 'null' THEN RETURN p_default; END IF;
  v_txt := v #>> '{}';
  --: REST query strings arrive as text, MCP arguments as numbers; both are accepted, nothing else is. The format is
  --: checked in its own IF before any cast, so no evaluation order is relied on.
  IF NOT ((jsonb_typeof(v) = 'number' AND v_txt ~ '^-?[0-9]+$') OR (jsonb_typeof(v) = 'string' AND v_txt ~ '^-?[0-9]{1,9}$')) THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
      DETAIL = format('%s must be a whole number from %s to %s.', p_key, p_min, p_max);
  END IF;
  IF v_txt::numeric < p_min OR v_txt::numeric > p_max THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
      DETAIL = format('%s must be a whole number from %s to %s.', p_key, p_min, p_max);
  END IF;
  RETURN v_txt::integer;
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_arg_uuid(p_args jsonb, p_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
DECLARE v jsonb := p_args -> p_key;
BEGIN
  IF v IS NULL OR jsonb_typeof(v) = 'null' OR (jsonb_typeof(v) = 'string' AND btrim(v #>> '{}') = '') THEN
    RETURN NULL;
  END IF;
  IF jsonb_typeof(v) <> 'string'
     OR btrim(v #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = format('%s must be a UUID.', p_key);
  END IF;
  RETURN btrim(v #>> '{}')::uuid;
END $fn$;

-- The active principal a token hash names, or a row of NULLs. Revoked and unknown read the same.
CREATE OR REPLACE FUNCTION public.ottoq_agent_resolve(p_token_hash text)
 RETURNS public.ottoq_agent_principals
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v public.ottoq_agent_principals;
BEGIN
  IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
    RETURN v;
  END IF;
  SELECT * INTO v FROM public.ottoq_agent_principals a
   WHERE a.token_hash = p_token_hash AND a.status = 'active';
  RETURN v;
END $fn$;

-- The depot's live run, chosen exactly as ottoq_depot_cards chooses it, or NULL.
CREATE OR REPLACE FUNCTION public.ottoq_agent_live_run(p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT jsonb_build_object('sim_run_id', r.sim_run_id, 'status', r.status, 'scenario', r.scenario_code,
                            'seed', r.random_seed::text, 'sim_clock', r.sim_clock_current, 'tick', r.tick_count,
                            'speed_x', r.demo_speed_x, 'started_at', r.started_at, 'run_by', r.run_by)
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = p_depot_id AND r.status IN ('running', 'paused')
   ORDER BY r.started_at DESC
   LIMIT 1
$fn$;

-- A vehicle the principal may see, or a row of NULLs. A scope miss and a missing vehicle are the same answer.
CREATE OR REPLACE FUNCTION public.ottoq_agent_vehicle_in_scope(p_agent public.ottoq_agent_principals, p_vehicle_id uuid)
 RETURNS public.vehicles
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v public.vehicles;
BEGIN
  IF p_vehicle_id IS NULL OR p_agent.principal_id IS NULL THEN
    RETURN v;
  END IF;
  SELECT * INTO v FROM public.vehicles x
   WHERE x.id = p_vehicle_id
     AND (x.current_depot_id = p_agent.depot_id OR x.home_depot_id = p_agent.depot_id)
     AND (p_agent.fleet_operator_id IS NULL OR x.fleet_operator_id = p_agent.fleet_operator_id);
  RETURN v;
END $fn$;

-- One ottoq_depot_cards vehicle, reduced to what an agent needs to reason about it (~300 bytes, not ~2.5 kB).
CREATE OR REPLACE FUNCTION public.ottoq_agent_compact_card(p_card jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'vehicle_id',      p_card -> 'vehicle_id',
    'display_name',    p_card -> 'display_name',
    'operator',        p_card #> '{operator,name}',
    'state',           p_card -> 'state',
    'soc',             p_card -> 'soc',
    'target_soc',      p_card -> 'target_soc',
    'stall',           p_card #> '{stall,code}',
    'urgency',         p_card #> '{card,urgency}',
    'dispatch_due_at', p_card #> '{card,dispatch_due_at}',
    'current_step',    CASE WHEN jsonb_typeof(p_card #> '{card,current_step}') = 'object' THEN jsonb_strip_nulls(jsonb_build_object(
                         'leg_type',     p_card #> '{card,current_step,leg_type}',
                         'atom',         p_card #> '{card,current_step,atom}',
                         'expected_end', p_card #> '{card,current_step,expected_end}',
                         'progress_pct', p_card #> '{card,current_step,progress_pct}')) END,
    'next_step',       CASE WHEN jsonb_typeof(p_card #> '{card,next_step}') = 'object' THEN jsonb_strip_nulls(jsonb_build_object(
                         'leg_type',      p_card #> '{card,next_step,leg_type}',
                         'atom',          p_card #> '{card,next_step,atom}',
                         'planned_start', p_card #> '{card,next_step,planned_start}')) END,
    'open_needs',      CASE WHEN jsonb_typeof(p_card #> '{card,needs}') = 'array' THEN (
                         SELECT count(*) FROM jsonb_array_elements(p_card #> '{card,needs}') a
                          WHERE COALESCE(a ->> 'status', 'pending') <> 'done') END,
    'reservations',    CASE WHEN jsonb_typeof(p_card -> 'reservations') = 'array'
                            THEN jsonb_array_length(p_card -> 'reservations') END,
    'last_decision',   CASE WHEN jsonb_typeof(p_card -> 'last_decision') = 'object'
                            THEN (p_card -> 'last_decision') - 'rationale' END))
$fn$;

-- A request as a reader sees it. p_audience: 'agent' (its own), 'crew' (PULSE), 'operator' (OrchestrAV).
-- Only the crew sees who decided by name; everyone else sees whether it was the crew or the operator.
CREATE OR REPLACE FUNCTION public.ottoq_agent_request_json(p_req public.ottoq_agent_requests, p_audience text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_eff   text := CASE WHEN p_req.status = 'pending' AND p_req.expires_at <= now() THEN 'expired' ELSE p_req.status END;
  v_veh   jsonb;
  v_fleet jsonb;
BEGIN
  IF p_req.vehicle_id IS NOT NULL THEN
    SELECT jsonb_build_object('id', v.id, 'label', COALESCE(v.display_name, p_req.vehicle_label),
                              'state', v.current_state::text, 'soc', v.current_soc)
      INTO v_veh FROM public.vehicles v WHERE v.id = p_req.vehicle_id;
    v_veh := COALESCE(v_veh, jsonb_build_object('id', p_req.vehicle_id, 'label', p_req.vehicle_label,
                                                'state', NULL, 'soc', NULL));
  END IF;
  IF p_req.fleet_operator_id IS NOT NULL THEN
    SELECT jsonb_build_object('id', f.id, 'name', f.name) INTO v_fleet
      FROM public.fleet_operators f WHERE f.id = p_req.fleet_operator_id;
  END IF;
  RETURN jsonb_build_object(
    'request_id',      p_req.request_id,
    'kind',            p_req.kind,
    'title',           p_req.title,
    'body',            p_req.body,
    'payload',         p_req.payload,
    'priority',        p_req.priority,
    'status',          v_eff,
    'recorded_status', p_req.status,
    'lapsed',          v_eff <> p_req.status,
    'principal',       jsonb_build_object('name', p_req.principal_name, 'kind', p_req.principal_kind),
    'vehicle',         v_veh,
    'fleet_operator',  v_fleet,
    'sim_run_id',      p_req.sim_run_id,
    'sim_clock',       p_req.sim_clock,
    'created_at',      p_req.created_at,
    'expires_at',      p_req.expires_at,
    'decision',        p_req.decision,
    'decided_by',      CASE WHEN p_req.decided_by_kind IS NULL THEN NULL
                            WHEN p_audience = 'crew' THEN jsonb_build_object('kind', p_req.decided_by_kind,
                                                                            'label', p_req.decided_by_label)
                            ELSE jsonb_build_object('kind', p_req.decided_by_kind) END,
    'decided_at',      p_req.decided_at,
    'decision_note',   p_req.decision_note,
    'engine_door',     p_req.engine_door,
    'engine_reply',    p_req.engine_reply,
    'applied_at',      p_req.applied_at,
    'closed_reason',   p_req.closed_reason);
END $fn$;

-- ══ 5. the tools (internal: reachable only through ottoq_agent_call) ════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_whoami(p_agent public.ottoq_agent_principals)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_depot text; v_fleet text;
BEGIN
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_agent.depot_id;
  IF p_agent.fleet_operator_id IS NOT NULL THEN
    SELECT f.name INTO v_fleet FROM public.fleet_operators f WHERE f.id = p_agent.fleet_operator_id;
  END IF;
  RETURN jsonb_build_object(
    'principal', jsonb_build_object('name', p_agent.name, 'kind', p_agent.kind, 'token_prefix', p_agent.token_prefix,
                                    'created_at', p_agent.created_at, 'last_used_at', p_agent.last_used_at,
                                    'note', p_agent.note),
    'scope', jsonb_build_object(
      'depot', jsonb_build_object('id', p_agent.depot_id, 'name', v_depot),
      'fleet_operator', CASE WHEN p_agent.fleet_operator_id IS NULL THEN NULL
                             ELSE jsonb_build_object('id', p_agent.fleet_operator_id, 'name', v_fleet) END,
      'sees', CASE WHEN p_agent.fleet_operator_id IS NULL THEN 'every vehicle at the depot, all owners'
                   ELSE 'only this fleet operator''s vehicles' END),
    'capabilities', to_jsonb(p_agent.capabilities),
    'limits', jsonb_build_object('calls_per_minute', p_agent.rate_limit_per_min,
                                 'max_pending_requests', p_agent.max_pending),
    'how_changes_happen',
      'Every change you ask for is a request. A person approves or declines it: the depot crew in OTTO-PULSE, or the '
      || 'fleet''s own operator once signed in. An approved request goes to one of OTTO-Q''s own doors, which may still '
      || 'refuse it; list_requests shows the decision and the engine''s exact reply. Nothing happens on your say-so alone.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_depot(p_agent public.ottoq_agent_principals)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_run    jsonb := public.ottoq_agent_live_run(p_agent.depot_id);
  v_depot  text;
  v_counts jsonb;
  v_total  integer;
BEGIN
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_agent.depot_id;
  --: the same vehicle population ottoq_depot_cards serves: current_depot_id, under the principal's operator filter
  SELECT COALESCE(jsonb_object_agg(s.state, s.n), '{}'::jsonb), COALESCE(sum(s.n), 0)::integer
    INTO v_counts, v_total
    FROM (SELECT v.current_state::text AS state, count(*) AS n
            FROM public.vehicles v
           WHERE v.current_depot_id = p_agent.depot_id
             AND (p_agent.fleet_operator_id IS NULL OR v.fleet_operator_id = p_agent.fleet_operator_id)
           GROUP BY 1) s;
  RETURN jsonb_build_object(
    'depot', jsonb_build_object('id', p_agent.depot_id, 'name', v_depot),
    'live', v_run IS NOT NULL,
    'run', v_run,
    'run_context', CASE WHEN v_run IS NULL THEN NULL
                        ELSE public.ottoq_twin_run_context((v_run ->> 'sim_run_id')::uuid) END,
    'fleet_in_scope', jsonb_build_object(
      'scope', CASE WHEN p_agent.fleet_operator_id IS NULL THEN 'every owner' ELSE 'your fleet only' END,
      'total', v_total, 'by_state', v_counts),
    'clocks', 'run.sim_clock is SIMULATION time. run.started_at is real time (UTC).',
    'message', CASE WHEN v_run IS NULL THEN 'No run is live at this depot right now.' END);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_fleet(p_agent public.ottoq_agent_principals, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_state   text    := NULLIF(lower(btrim(COALESCE(p_args ->> 'state', ''))), '');
  v_limit   integer := public.ottoq_agent_arg_int(p_args, 'limit', 200, 1, 500);
  v_cards   jsonb;
  v_all     jsonb;
  v_rows    jsonb;
  v_counts  jsonb;
  v_matched integer;
BEGIN
  IF v_state IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM unnest(enum_range(NULL::public.vehicle_state)) e WHERE e::text = v_state) THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
      DETAIL = 'state must be one of the engine''s vehicle states.',
      HINT = (SELECT string_agg(e::text, ', ') FROM unnest(enum_range(NULL::public.vehicle_state)) e);
  END IF;
  --: ONE read contract: the same card RPC both cockpits read, with the principal's operator filter
  v_cards := public.ottoq_depot_cards(p_agent.depot_id, p_agent.fleet_operator_id);
  v_all := CASE WHEN jsonb_typeof(v_cards -> 'vehicles') = 'array' THEN v_cards -> 'vehicles' ELSE '[]'::jsonb END;
  SELECT COALESCE(jsonb_object_agg(s.k, s.n), '{}'::jsonb) INTO v_counts
    FROM (SELECT x ->> 'state' AS k, count(*) AS n FROM jsonb_array_elements(v_all) x GROUP BY 1) s;
  SELECT count(*) INTO v_matched FROM jsonb_array_elements(v_all) x WHERE v_state IS NULL OR x ->> 'state' = v_state;
  SELECT COALESCE(jsonb_agg(public.ottoq_agent_compact_card(q.x) ORDER BY q.nm), '[]'::jsonb) INTO v_rows
    FROM (SELECT x, x ->> 'display_name' AS nm FROM jsonb_array_elements(v_all) x
           WHERE v_state IS NULL OR x ->> 'state' = v_state
           ORDER BY x ->> 'display_name' LIMIT v_limit) q;
  RETURN jsonb_build_object(
    'sim_run_id', v_cards -> 'sim_run_id', 'run_status', v_cards -> 'run_status', 'sim_clock', v_cards -> 'sim_clock',
    'scope', CASE WHEN p_agent.fleet_operator_id IS NULL THEN 'every owner at the depot' ELSE 'your fleet only' END,
    'total', jsonb_array_length(v_all), 'counts_by_state', v_counts,
    'matched', v_matched, 'returned', jsonb_array_length(v_rows), 'truncated', v_matched > jsonb_array_length(v_rows),
    'vehicles', v_rows,
    'contract', jsonb_build_object('endpoint', v_cards ->> 'endpoint', 'version', v_cards ->> 'contract_version'),
    'clocks', 'sim_clock, dispatch_due_at and step times are SIMULATION time.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_vehicle(p_agent public.ottoq_agent_principals, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_id   uuid := public.ottoq_agent_arg_uuid(p_args, 'vehicle_id');
  v_veh  public.vehicles;
  v_card jsonb;
BEGIN
  IF v_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'vehicle_id is required.';
  END IF;
  v_veh := public.ottoq_agent_vehicle_in_scope(p_agent, v_id);
  IF v_veh.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'vehicle_not_found',
      DETAIL = 'No vehicle with that id is in your scope.';
  END IF;
  v_card := public.ottoq_vehicle_card(v_id);
  RETURN jsonb_build_object(
    'vehicle_id', v_veh.id, 'display_name', v_veh.display_name, 'state', v_veh.current_state::text,
    'soc', v_veh.current_soc, 'target_soc', v_veh.target_soc,
    'card', v_card -> 'vehicle',
    'contract', jsonb_build_object('endpoint', v_card ->> 'endpoint', 'version', v_card ->> 'contract_version'),
    'message', CASE WHEN jsonb_typeof(v_card -> 'vehicle') IS DISTINCT FROM 'object'
                    THEN 'No work-order card: the vehicle is not on a live run at its current depot.' END,
    'clocks', 'Step and booking times on the card are SIMULATION time.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_decisions(p_agent public.ottoq_agent_principals, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_run   jsonb   := public.ottoq_agent_live_run(p_agent.depot_id);
  v_vid   uuid    := public.ottoq_agent_arg_uuid(p_args, 'vehicle_id');
  v_limit integer := public.ottoq_agent_arg_int(p_args, 'limit', 25, 1, 100);
  v_veh   public.vehicles;
  v_rows  jsonb;
BEGIN
  IF v_vid IS NOT NULL THEN
    v_veh := public.ottoq_agent_vehicle_in_scope(p_agent, v_vid);
    IF v_veh.id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'vehicle_not_found',
        DETAIL = 'No vehicle with that id is in your scope.';
    END IF;
  END IF;
  IF v_run IS NULL THEN
    RETURN jsonb_build_object('live', false, 'decisions', '[]'::jsonb,
      'message', 'No run is live at this depot; decisions are read from the live run only.');
  END IF;
  --: the cockpits' own decision stream, filtered to the principal's vehicles when it is fleet-scoped
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'at_sim', f.occurred_at, 'vehicle_id', f.vehicle_id, 'vehicle', f.display_name, 'action', f.action,
           'engine', f.engine, 'target', f.target, 'outcome', f.outcome, 'reason', f.reason, 'rationale', f.rationale,
           'decision_seq', f.decision_seq, 'tick', f.tick_seq, 'held_ticks', f.held_ticks, 'standing', f.standing)
           ORDER BY f.occurred_at DESC, f.decision_seq DESC), '[]'::jsonb)
    INTO v_rows
    FROM (SELECT a.* FROM public.ottoq_activity_feed((v_run ->> 'sim_run_id')::uuid, 200, v_vid, true, 240) a
           WHERE p_agent.fleet_operator_id IS NULL
              OR a.vehicle_id IN (SELECT v.id FROM public.vehicles v WHERE v.fleet_operator_id = p_agent.fleet_operator_id)
           ORDER BY a.occurred_at DESC, a.decision_seq DESC
           LIMIT v_limit) f;
  RETURN jsonb_build_object(
    'live', true, 'sim_run_id', v_run -> 'sim_run_id', 'sim_clock', v_run -> 'sim_clock',
    'scope', CASE WHEN p_agent.fleet_operator_id IS NULL THEN 'every owner' ELSE 'your fleet only' END,
    'decisions', v_rows,
    'clocks', 'at_sim is SIMULATION time.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_stalls(p_agent public.ottoq_agent_principals, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_run     jsonb   := public.ottoq_agent_live_run(p_agent.depot_id);
  v_type    text    := NULLIF(lower(btrim(COALESCE(p_args ->> 'stall_type', ''))), '');
  v_horizon integer := public.ottoq_agent_arg_int(p_args, 'horizon_min', 30, 5, 240);
  v_run_id  uuid;
  v_from    timestamptz;
  v_to      timestamptz;
  v_free    uuid[];
  v_stalls  jsonb;
  v_by_type jsonb;
  v_list    jsonb;
BEGIN
  IF v_type IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM unnest(enum_range(NULL::public.stall_type)) e WHERE e::text = v_type) THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
      DETAIL = 'stall_type must be one of the engine''s stall types.',
      HINT = (SELECT string_agg(e::text, ', ') FROM unnest(enum_range(NULL::public.stall_type)) e);
  END IF;
  IF v_run IS NULL THEN
    RETURN jsonb_build_object('live', false,
      'message', 'No run is live, so there is no sim clock to evaluate the stall calendar against. Availability is the '
                 || 'intersection of three gates and the calendar gate is evaluated on the run''s SIM clock, never on '
                 || 'the wall clock; without a run it is not computed.');
  END IF;
  v_run_id := (v_run ->> 'sim_run_id')::uuid;
  --: THE CALENDAR GATE RUNS ON THE SIM CLOCK. ottoq_stall_bookings.during is SIM time; against now() the calendar
  --: reads every stall free on a full depot (db/checks/0326 section 1, G125). now() appears nowhere below.
  v_from := (v_run ->> 'sim_clock')::timestamptz;
  v_to   := v_from + make_interval(mins => v_horizon);
  --: gates two and three -- the calendar and the charger -- as the engine's shared candidate source computes them
  v_free := ARRAY(SELECT f.stall_id
                    FROM ottoq.ottoq_stall_free_between(v_run_id, p_agent.depot_id, v_from, v_to, v_type, NULL, 10000, NULL) f);
  --: gate one, the pointer, which that function does not fully check (it never reads reserved_by)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'stall_code', s.stall_code, 'stall_type', s.stall_type, 'zone', s.zone,
           'pointer_free', s.pointer_free, 'calendar_and_charger_free', s.id = ANY (v_free),
           'charger_faulted', s.charger_faulted) ORDER BY s.stall_code), '[]'::jsonb)
    INTO v_stalls
    FROM (SELECT st.id, st.stall_code, st.stall_type::text AS stall_type, st.zone,
                 (st.status = 'available' AND st.current_vehicle_id IS NULL AND st.reserved_by IS NULL) AS pointer_free,
                 (st.stall_type::text IN ('dcfc', 'l2')
                  AND EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers ch
                               WHERE ch.charger_id = st.ocpp_charger_id AND ch.station_state = 'Faulted')) AS charger_faulted
            FROM public.stalls st
           WHERE st.depot_id = p_agent.depot_id AND (v_type IS NULL OR st.stall_type::text = v_type)) s;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'stall_type', t.stall_type, 'total', t.total, 'pointer_free', t.pointer_free,
           'calendar_and_charger_free', t.engine_free, 'charger_faulted', t.faulted, 'offerable', t.offerable)
           ORDER BY t.stall_type), '[]'::jsonb)
    INTO v_by_type
    FROM (SELECT x ->> 'stall_type' AS stall_type, count(*) AS total,
                 count(*) FILTER (WHERE (x ->> 'pointer_free')::boolean) AS pointer_free,
                 count(*) FILTER (WHERE (x ->> 'calendar_and_charger_free')::boolean) AS engine_free,
                 count(*) FILTER (WHERE (x ->> 'charger_faulted')::boolean) AS faulted,
                 count(*) FILTER (WHERE (x ->> 'pointer_free')::boolean
                                    AND (x ->> 'calendar_and_charger_free')::boolean) AS offerable
            FROM jsonb_array_elements(v_stalls) x GROUP BY 1) t;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('stall_code', q.x -> 'stall_code', 'stall_type', q.x -> 'stall_type',
                                               'zone', q.x -> 'zone') ORDER BY q.code), '[]'::jsonb)
    INTO v_list
    FROM (SELECT x, x ->> 'stall_code' AS code FROM jsonb_array_elements(v_stalls) x
           WHERE (x ->> 'pointer_free')::boolean AND (x ->> 'calendar_and_charger_free')::boolean
           ORDER BY x ->> 'stall_code' LIMIT 50) q;
  RETURN jsonb_build_object(
    'live', true, 'sim_run_id', v_run_id,
    'window_sim', jsonb_build_object('from', v_from, 'to', v_to, 'horizon_min', v_horizon),
    'by_type', v_by_type,
    'offerable_stalls', v_list,
    'gates', 'A stall is offerable only when all three gates agree: its pointer is clear (status available, no '
             || 'vehicle, no reservation), its calendar is clear for the window on the run''s SIM clock, and, for dcfc '
             || 'and l2, its charger is not Faulted. Gates two and three are read from ottoq.ottoq_stall_free_between, '
             || 'the engine''s own candidate source. Neither single gate is availability; quote the intersection.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_requests(p_agent public.ottoq_agent_principals, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_status text    := NULLIF(lower(btrim(COALESCE(p_args ->> 'status', ''))), '');
  v_id     uuid    := public.ottoq_agent_arg_uuid(p_args, 'request_id');
  v_limit  integer := public.ottoq_agent_arg_int(p_args, 'limit', 20, 1, 100);
  v_rows   jsonb;
BEGIN
  IF v_status IS NOT NULL AND v_status NOT IN ('pending', 'declined', 'expired', 'acknowledged', 'applied',
                                               'refused_by_engine', 'approved_no_engine_door', 'approved_not_applied',
                                               'apply_failed') THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'status is not a request status.';
  END IF;
  SELECT COALESCE(jsonb_agg(public.ottoq_agent_request_json(q.r, 'agent') ORDER BY q.created_at DESC), '[]'::jsonb)
    INTO v_rows
    FROM (SELECT r, r.created_at
            FROM public.ottoq_agent_requests r
           WHERE r.principal_id = p_agent.principal_id
             AND (v_id IS NULL OR r.request_id = v_id)
             AND (v_status IS NULL
                  OR (CASE WHEN r.status = 'pending' AND r.expires_at <= now() THEN 'expired' ELSE r.status END) = v_status)
           ORDER BY r.created_at DESC
           LIMIT v_limit) q;
  IF v_id IS NOT NULL AND jsonb_array_length(v_rows) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'request_not_found', DETAIL = 'You made no request with that id.';
  END IF;
  RETURN jsonb_build_object(
    'requests', v_rows, 'returned', jsonb_array_length(v_rows),
    'statuses', 'pending: waiting for a person. declined / expired: nothing happened. acknowledged: a note was read. '
                || 'applied: approved, and the engine door accepted it -- engine_reply is exactly what it said. '
                || 'refused_by_engine: approved, and the door refused. approved_no_engine_door: approved, but OTTO-Q has '
                || 'no door for this; nothing in the engine changed. approved_not_applied: approved, but the door was not '
                || 'called (engine_reply says why). apply_failed: the door raised an error.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_submit_request(p_agent public.ottoq_agent_principals, p_kind text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_kind     text := lower(btrim(COALESCE(p_kind, '')));
  v_title    text := btrim(COALESCE(p_args ->> 'title', ''));
  v_body     text := NULLIF(btrim(COALESCE(p_args ->> 'body', '')), '');
  v_priority text := lower(COALESCE(NULLIF(btrim(p_args ->> 'priority'), ''), 'normal'));
  v_idem     text := NULLIF(btrim(COALESCE(p_args ->> 'idempotency_key', '')), '');
  v_cap      text;
  v_ttl      integer;
  v_vid      uuid;
  v_veh      public.vehicles;
  v_existing public.ottoq_agent_requests;
  v_row      public.ottoq_agent_requests;
  v_action   text;
  v_param    text;
  v_args     jsonb;
  v_adj      text;
  v_value    jsonb;
  v_run      jsonb;
  v_pending  integer;
BEGIN
  v_cap := CASE v_kind WHEN 'note' THEN 'note' WHEN 'recall_vehicle' THEN 'request_recall'
                       WHEN 'ops_action' THEN 'request_ops_action' WHEN 'adjustment' THEN 'request_adjustment' END;
  IF v_cap IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_kind',
      DETAIL = 'kind must be recall_vehicle, ops_action or adjustment (a note goes through send_note).';
  END IF;
  IF NOT (v_cap = ANY (p_agent.capabilities)) THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA03', MESSAGE = 'capability_missing',
      DETAIL = format('This token does not carry the %s capability.', v_cap);
  END IF;
  IF char_length(v_title) NOT BETWEEN 1 AND 140 THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'title is required, 1 to 140 characters.';
  END IF;
  IF v_body IS NOT NULL AND char_length(v_body) > 4000 THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'body is at most 4000 characters.';
  END IF;
  IF v_priority NOT IN ('low', 'normal', 'high', 'urgent') THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'priority is low, normal, high or urgent.';
  END IF;
  IF v_idem IS NOT NULL AND v_idem !~ '^[A-Za-z0-9._:-]{1,100}$' THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
      DETAIL = 'idempotency_key is 1 to 100 of A-Z a-z 0-9 . _ : -';
  END IF;
  v_ttl := public.ottoq_agent_arg_int(p_args, 'ttl_minutes', CASE WHEN v_kind = 'note' THEN 1440 ELSE 120 END, 5, 10080);
  v_vid := public.ottoq_agent_arg_uuid(p_args, 'vehicle_id');

  --: the same key is the same request: a retry replays it instead of asking twice
  IF v_idem IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.ottoq_agent_requests r
     WHERE r.principal_id = p_agent.principal_id AND r.idempotency_key = v_idem;
    IF FOUND THEN
      RETURN jsonb_build_object('duplicate', true, 'request', public.ottoq_agent_request_json(v_existing, 'agent'));
    END IF;
  END IF;

  --: close this principal's lapsed requests before counting what is still open
  UPDATE public.ottoq_agent_requests r
     SET status = 'expired', closed_reason = 'lapsed: nobody decided before it expired'
   WHERE r.principal_id = p_agent.principal_id AND r.status = 'pending' AND r.expires_at <= now();
  SELECT count(*) INTO v_pending FROM public.ottoq_agent_requests r
   WHERE r.principal_id = p_agent.principal_id AND r.status = 'pending';
  IF v_pending >= p_agent.max_pending THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA29', MESSAGE = 'too_many_pending',
      DETAIL = format('%s of your requests are already waiting for a person; wait for decisions before sending more.', v_pending);
  END IF;

  IF v_vid IS NOT NULL THEN
    v_veh := public.ottoq_agent_vehicle_in_scope(p_agent, v_vid);
    IF v_veh.id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'vehicle_not_found', DETAIL = 'No vehicle with that id is in your scope.';
    END IF;
  END IF;

  IF v_kind = 'recall_vehicle' THEN
    IF v_veh.id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'A recall names the vehicle_id to recall.';
    END IF;
    IF NOT COALESCE(v_veh.is_active, false) THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA22', MESSAGE = 'vehicle_inactive', DETAIL = 'That vehicle is not active.';
    END IF;
    --: one open recall per vehicle, whoever asked: the inbox must not fill with the same question
    SELECT * INTO v_existing FROM public.ottoq_agent_requests r
     WHERE r.kind = 'recall_vehicle' AND r.vehicle_id = v_veh.id AND r.status = 'pending' AND r.expires_at > now()
     ORDER BY r.created_at LIMIT 1;
    IF FOUND THEN
      IF v_existing.principal_id = p_agent.principal_id THEN
        RETURN jsonb_build_object('duplicate', true, 'request', public.ottoq_agent_request_json(v_existing, 'agent'));
      END IF;
      RAISE EXCEPTION USING ERRCODE = 'OQA09', MESSAGE = 'recall_already_pending',
        DETAIL = 'A recall for this vehicle is already waiting for a decision.';
    END IF;
  ELSIF v_kind = 'ops_action' THEN
    v_action := lower(btrim(COALESCE(p_args ->> 'action', '')));
    --: ottoq_apply_ops_action's whitelist, action -> the dial it sets (P1 asserts the engine still pairs them so)
    v_param := CASE v_action WHEN 'raise_deploy_surge'      THEN 'deploy_surge_catchup'
                             WHEN 'extend_forecast_horizon' THEN 'forecast_horizon_min'
                             WHEN 'enable_energy_reserve'   THEN 'energy_reserve_shave' END;
    IF v_param IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'unknown_ops_action',
        DETAIL = 'action must be one of raise_deploy_surge, extend_forecast_horizon, enable_energy_reserve (the engine''s ops-action whitelist).';
    END IF;
    --: refused HERE with the catalog's reason, never queued for a person: approving a change the setter refuses, or one
    --: nothing reads, is worse than no request (0438, G175; _shared/agent_dial_discipline.ts)
    IF NOT COALESCE((SELECT c.agent_writable FROM public.ottoq_policy_param_catalog c WHERE c.param_key = v_param), false) THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA22', MESSAGE = 'not_agent_writable',
        DETAIL = format('%s sets %s, which is not an agent actuator (ottoq_policy_param_catalog.agent_writable is false).', v_action, v_param),
        HINT = 'A person can still change it from the cockpit; an agent cannot ask for it.';
    END IF;
    IF v_vid IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'An ops action is depot-wide; it names no vehicle.';
    END IF;
    v_args := p_args -> 'args';
    IF v_args IS NOT NULL AND jsonb_typeof(v_args) = 'null' THEN v_args := NULL; END IF;
    IF v_args IS NOT NULL AND (jsonb_typeof(v_args) <> 'object'
                               OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_args) k WHERE k <> 'value')
                               OR (v_args ? 'value' AND jsonb_typeof(v_args -> 'value') <> 'number')) THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'args may carry only a numeric value.';
    END IF;
  ELSIF v_kind = 'adjustment' THEN
    v_adj := lower(btrim(COALESCE(p_args ->> 'adjustment', '')));
    IF v_adj !~ '^[a-z][a-z0-9_]{1,48}$' THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'adjustment is a short snake_case name for what you want changed, e.g. charge_target or hold_until.';
    END IF;
    v_value := p_args -> 'value';
    IF v_value IS NOT NULL AND (jsonb_typeof(v_value) NOT IN ('number', 'string', 'boolean', 'null')
                                OR (jsonb_typeof(v_value) = 'string' AND char_length(v_value #>> '{}') > 200)) THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'value is a number, true/false, or text of at most 200 characters.';
    END IF;
  END IF;

  v_run := public.ottoq_agent_live_run(p_agent.depot_id);
  IF v_kind = 'ops_action' AND v_run IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA22', MESSAGE = 'no_live_run',
      DETAIL = 'An ops action changes a run-scoped dial, and no run is live at this depot.';
  END IF;

  BEGIN
    INSERT INTO public.ottoq_agent_requests
      (principal_id, principal_name, principal_kind, depot_id, fleet_operator_id, sim_run_id, sim_clock, kind,
       vehicle_id, vehicle_label, title, body, payload, priority, idempotency_key, expires_at)
    VALUES
      (p_agent.principal_id, p_agent.name, p_agent.kind, p_agent.depot_id,
       COALESCE(p_agent.fleet_operator_id, v_veh.fleet_operator_id),
       (v_run ->> 'sim_run_id')::uuid, (v_run ->> 'sim_clock')::timestamptz, v_kind,
       v_veh.id, v_veh.display_name, v_title, v_body,
       jsonb_strip_nulls(jsonb_build_object('action', v_action, 'param', v_param, 'args', v_args,
                                            'adjustment', v_adj, 'value', v_value)),
       v_priority, v_idem, now() + make_interval(mins => v_ttl))
    RETURNING * INTO v_row;
  EXCEPTION WHEN unique_violation THEN
    --: two concurrent submits with one key: the second replays the first
    SELECT * INTO v_existing FROM public.ottoq_agent_requests r
     WHERE r.principal_id = p_agent.principal_id AND r.idempotency_key = v_idem;
    IF FOUND THEN
      RETURN jsonb_build_object('duplicate', true, 'request', public.ottoq_agent_request_json(v_existing, 'agent'));
    END IF;
    RAISE;
  END;

  RETURN jsonb_build_object(
    'duplicate', false,
    'request', public.ottoq_agent_request_json(v_row, 'agent'),
    'next', CASE WHEN v_kind = 'note' THEN 'Delivered to the depot crew''s agent inbox in OTTO-PULSE.'
                 ELSE 'Waiting for a person to approve or decline it. list_requests shows the decision and the engine''s reply.' END);
END $fn$;

-- ══ 6. the one door the gateway calls ═══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_agent_call(
    p_token_hash text,
    p_tool       text,
    p_args       jsonb DEFAULT '{}'::jsonb,
    p_transport  text  DEFAULT 'rest',
    p_meta       jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0559. The ONLY function the ottoq-agent-gateway edge function calls. It resolves the token hash to an active
   principal, applies the per-principal rate limit, checks the tool's capability, runs the tool and writes the call
   ledger, in one transaction. Business refusals from a tool (SQLSTATE OQAxx) roll back whatever the tool started and
   come back as an HTTP status the edge function forwards. This function names no engine door: an agent can read and
   can ASK, and a person decides through ottoq_agent_request_decide. */
DECLARE
  t0          timestamptz := clock_timestamp();
  v_agent     public.ottoq_agent_principals;
  v_tool      text := left(lower(btrim(COALESCE(p_tool, ''))), 64);
  v_transport text := CASE WHEN p_transport IN ('rest', 'mcp') THEN p_transport ELSE 'other' END;
  v_args      jsonb := COALESCE(p_args, '{}'::jsonb);
  v_meta      jsonb;
  v_need      text;
  v_data      jsonb;
  v_status    integer := 200;
  v_code      text;
  v_msg       text;
  v_detail    text;
  v_hint      text;
  v_state     text;
  v_recent    integer;
  v_request   uuid;
  v_call      bigint;
BEGIN
  --: only small, known keys from the caller reach the ledger
  v_meta := jsonb_strip_nulls(jsonb_build_object(
    'http_method',  left(COALESCE(p_meta, '{}'::jsonb) ->> 'http_method', 8),
    'path',         left(COALESCE(p_meta, '{}'::jsonb) ->> 'path', 200),
    'mcp_method',   left(COALESCE(p_meta, '{}'::jsonb) ->> 'mcp_method', 64),
    'mcp_version',  left(COALESCE(p_meta, '{}'::jsonb) ->> 'mcp_version', 16),
    'client',       left(COALESCE(p_meta, '{}'::jsonb) ->> 'client', 120),
    'ip',           left(COALESCE(p_meta, '{}'::jsonb) ->> 'ip', 64)));

  v_agent := public.ottoq_agent_resolve(p_token_hash);
  IF v_agent.principal_id IS NULL THEN
    --: an unknown or revoked token reaches no tool. Ledgered, but at most 60 a minute, so a caller without a token
    --: cannot grow the ledger without bound.
    SELECT count(*) INTO v_recent FROM public.ottoq_agent_call_ledger l
     WHERE l.principal_id IS NULL AND l.called_at > now() - interval '1 minute';
    IF v_recent < 60 THEN
      INSERT INTO public.ottoq_agent_call_ledger (principal_id, transport, tool, http_method, path, ok, http_status,
                                                 error_code, latency_ms, detail)
      VALUES (NULL, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path', false, 401, 'unauthenticated',
              (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer, v_meta - 'http_method' - 'path')
      RETURNING call_id INTO v_call;
    END IF;
    RETURN jsonb_build_object('ok', false, 'http_status', 401, 'tool', v_tool, 'call_id', v_call,
      'error', jsonb_build_object('code', 'unauthenticated', 'message', 'The token is unknown or has been revoked.'));
  END IF;

  --: the rate limit reads the ledger, so it holds across edge isolates and cold starts
  SELECT count(*) INTO v_recent FROM public.ottoq_agent_call_ledger l
   WHERE l.principal_id = v_agent.principal_id AND l.called_at > now() - interval '1 minute';
  IF v_recent >= v_agent.rate_limit_per_min THEN
    IF v_recent < 2 * v_agent.rate_limit_per_min THEN
      INSERT INTO public.ottoq_agent_call_ledger (principal_id, principal_name, transport, tool, http_method, path, ok,
                                                 http_status, error_code, latency_ms, depot_id, fleet_operator_id, detail)
      VALUES (v_agent.principal_id, v_agent.name, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path',
              false, 429, 'rate_limited', (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer,
              v_agent.depot_id, v_agent.fleet_operator_id, v_meta - 'http_method' - 'path')
      RETURNING call_id INTO v_call;
    END IF;
    RETURN jsonb_build_object('ok', false, 'http_status', 429, 'tool', v_tool, 'call_id', v_call,
      'error', jsonb_build_object('code', 'rate_limited', 'retry_after_s', 60,
        'message', format('At most %s calls a minute for this token.', v_agent.rate_limit_per_min)));
  END IF;

  UPDATE public.ottoq_agent_principals a SET last_used_at = now()
   WHERE a.principal_id = v_agent.principal_id
     AND (a.last_used_at IS NULL OR a.last_used_at < now() - interval '1 minute');

  --: TOTAL over the tool vocabulary: an unknown name is a 404, never a fall-through
  v_need := CASE v_tool
    WHEN 'handshake'          THEN ''
    WHEN 'whoami'             THEN ''
    WHEN 'list_requests'      THEN ''
    WHEN 'depot_status'       THEN 'read'
    WHEN 'fleet_summary'      THEN 'read'
    WHEN 'vehicle_card'       THEN 'read'
    WHEN 'recent_decisions'   THEN 'read'
    WHEN 'stall_availability' THEN 'read'
    WHEN 'send_note'          THEN 'note'
    WHEN 'submit_request'     THEN 'per_kind'
    ELSE NULL END;

  BEGIN
    IF v_need IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'unknown_tool', DETAIL = format('No tool named %s.', v_tool);
    END IF;
    IF jsonb_typeof(v_args) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'arguments must be a JSON object.';
    END IF;
    IF v_need NOT IN ('', 'per_kind') AND NOT (v_need = ANY (v_agent.capabilities)) THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA03', MESSAGE = 'capability_missing',
        DETAIL = format('This token does not carry the %s capability.', v_need);
    END IF;
    --: the gateway refused the arguments against the tool's published schema. It still asks here first, so the
    --: refusal is authenticated, rate-limited and ledgered like any call: an unknown token learns nothing from a
    --: malformed request, and a known one leaves a trace of it.
    IF (COALESCE(p_meta, '{}'::jsonb) ->> 'gateway_refusal') = 'invalid_arguments' THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'The arguments do not match the tool''s schema; the gateway''s reply lists each problem.';
    END IF;
    v_data := CASE v_tool
      WHEN 'handshake'          THEN public.ottoq_agent_read_whoami(v_agent)
      WHEN 'whoami'             THEN public.ottoq_agent_read_whoami(v_agent)
      WHEN 'depot_status'       THEN public.ottoq_agent_read_depot(v_agent)
      WHEN 'fleet_summary'      THEN public.ottoq_agent_read_fleet(v_agent, v_args)
      WHEN 'vehicle_card'       THEN public.ottoq_agent_read_vehicle(v_agent, v_args)
      WHEN 'recent_decisions'   THEN public.ottoq_agent_read_decisions(v_agent, v_args)
      WHEN 'stall_availability' THEN public.ottoq_agent_read_stalls(v_agent, v_args)
      WHEN 'list_requests'      THEN public.ottoq_agent_read_requests(v_agent, v_args)
      WHEN 'send_note'          THEN public.ottoq_agent_submit_request(v_agent, 'note', v_args)
      WHEN 'submit_request'     THEN public.ottoq_agent_submit_request(v_agent, COALESCE(v_args ->> 'kind', ''), v_args)
    END;
    IF v_tool IN ('send_note', 'submit_request') THEN
      v_status := CASE WHEN COALESCE((v_data ->> 'duplicate')::boolean, false) THEN 200 ELSE 201 END;
      v_request := (v_data #>> '{request,request_id}')::uuid;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT,
                            v_detail = PG_EXCEPTION_DETAIL, v_hint = PG_EXCEPTION_HINT;
    v_status := CASE v_state WHEN 'OQA01' THEN 400 WHEN 'OQA03' THEN 403 WHEN 'OQA04' THEN 404
                             WHEN 'OQA09' THEN 409 WHEN 'OQA22' THEN 422 WHEN 'OQA29' THEN 429 ELSE 500 END;
    v_code := CASE WHEN v_status = 500 THEN 'internal_error' ELSE v_msg END;
    INSERT INTO public.ottoq_agent_call_ledger (principal_id, principal_name, transport, tool, http_method, path, ok,
                                               http_status, error_code, latency_ms, depot_id, fleet_operator_id, detail)
    VALUES (v_agent.principal_id, v_agent.name, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path', false,
            v_status, v_code, (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer,
            v_agent.depot_id, v_agent.fleet_operator_id,
            (v_meta - 'http_method' - 'path')
            || CASE WHEN v_status = 500 THEN jsonb_build_object('sqlstate', v_state, 'error', left(v_msg, 300))
                    ELSE '{}'::jsonb END)
    RETURNING call_id INTO v_call;
    RETURN jsonb_build_object('ok', false, 'http_status', v_status, 'tool', v_tool, 'call_id', v_call,
      'error', jsonb_strip_nulls(jsonb_build_object(
        'code', v_code,
        'message', CASE WHEN v_status = 500 THEN 'The gateway hit an internal error. It is recorded under this call_id.'
                        ELSE COALESCE(NULLIF(v_detail, ''), v_msg) END,
        'hint', CASE WHEN v_status = 500 THEN NULL ELSE NULLIF(v_hint, '') END)));
  END;

  INSERT INTO public.ottoq_agent_call_ledger (principal_id, principal_name, transport, tool, http_method, path, ok,
                                             http_status, latency_ms, request_id, depot_id, fleet_operator_id, detail)
  VALUES (v_agent.principal_id, v_agent.name, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path', true,
          v_status, (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer, v_request,
          v_agent.depot_id, v_agent.fleet_operator_id, v_meta - 'http_method' - 'path')
  RETURNING call_id INTO v_call;
  RETURN jsonb_build_object('ok', true, 'http_status', v_status, 'tool', v_tool, 'call_id', v_call,
    'principal', jsonb_build_object('name', v_agent.name, 'kind', v_agent.kind,
                                    'capabilities', to_jsonb(v_agent.capabilities)),
    'data', v_data);
END $fn$;

-- ══ 7. the people's doors ═══════════════════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_agent_request_decide(p_request_id uuid, p_decision text, p_note text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0559. A person approves or declines an outside agent's request. Who is deciding is read from the session
   (auth.uid()), never from an argument. Crew: a yard_supervisor or ops_manager of the request's depot. Operator: the
   auth user bound in fleet_operators.auth_user_id, deciding only its own fleet's requests, never a depot-wide ops
   action. On approval the request goes to the engine's own door, if one exists, and the reply is recorded exactly. */
DECLARE
  v_uid      uuid := auth.uid();
  v_decision text := lower(btrim(COALESCE(p_decision, '')));
  v_note     text := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_req      public.ottoq_agent_requests;
  v_role     text;
  v_label    text;
  v_op_id    uuid;
  v_op_name  text;
  v_by       text;
  v_status   text;
  v_door     text;
  v_reply    jsonb;
  v_applied  timestamptz;
  v_run      jsonb;
  v_veh      public.vehicles;
  v_msg      text;
  v_state    text;
BEGIN
  IF v_decision NOT IN ('approved', 'declined') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_decision', 'message', 'The decision is approved or declined.');
  END IF;
  IF v_note IS NOT NULL AND char_length(v_note) > 1000 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'note_too_long', 'message', 'The note is at most 1000 characters.');
  END IF;
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sign_in_required',
      'message', 'A person decides an agent''s request. Sign in first.');
  END IF;
  SELECT * INTO v_req FROM public.ottoq_agent_requests r WHERE r.request_id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found', 'message', 'No such request.');
  END IF;

  --: who is deciding: crew of this depot first, then the fleet's bound operator
  SELECT s.role::text, COALESCE(NULLIF(btrim(s.display_name), ''), s.first_name || ' ' || left(s.last_name, 1) || '.')
    INTO v_role, v_label
    FROM public.staff_users s
   WHERE s.auth_user_id = v_uid AND s.is_active AND s.depot_id = v_req.depot_id
   ORDER BY (s.role::text IN ('ops_manager', 'yard_supervisor')) DESC
   LIMIT 1;
  IF v_role IS NOT NULL THEN
    IF v_role NOT IN ('yard_supervisor', 'ops_manager') THEN
      RETURN jsonb_build_object('ok', false, 'error', 'role_insufficient', 'role', v_role,
        'message', 'A yard supervisor or an ops manager decides agent requests (the level PULSE asks for ai.approve_action).');
    END IF;
    v_by := 'crew';
  ELSE
    SELECT f.id, f.name INTO v_op_id, v_op_name
      FROM public.fleet_operators f WHERE f.auth_user_id = v_uid AND f.is_active
     ORDER BY f.name LIMIT 1;
    IF v_op_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_authorized',
        'message', 'Only this depot''s supervisors and ops managers, or the fleet''s own operator, decide agent requests.');
    END IF;
    IF v_req.fleet_operator_id IS DISTINCT FROM v_op_id THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_your_fleet',
        'message', 'An operator decides only its own fleet''s requests.');
    END IF;
    IF v_req.kind = 'ops_action' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'depot_wide_action_needs_crew',
        'message', 'An ops action changes the whole depot, so the depot crew decides it.');
    END IF;
    v_by := 'operator';
    v_label := v_op_name;
  END IF;

  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_' || v_req.status, 'status', v_req.status,
      'message', 'This request has already been closed.');
  END IF;
  IF v_req.expires_at <= now() THEN
    UPDATE public.ottoq_agent_requests r
       SET status = 'expired', closed_reason = 'lapsed: nobody decided before it expired'
     WHERE r.request_id = v_req.request_id;
    RETURN jsonb_build_object('ok', false, 'error', 'expired', 'status', 'expired',
      'message', 'This request expired before anyone decided it.');
  END IF;

  IF v_decision = 'declined' THEN
    UPDATE public.ottoq_agent_requests r
       SET status = 'declined', decision = 'declined', decided_by_kind = v_by, decided_by_uid = v_uid,
           decided_by_label = v_label, decision_note = v_note, decided_at = now()
     WHERE r.request_id = v_req.request_id;
    RETURN jsonb_build_object('ok', true, 'request_id', v_req.request_id, 'decision', 'declined', 'status', 'declined');
  END IF;

  --: APPROVED: to the engine's own door, if one exists. TOTAL over kind: every kind lands in a defined status.
  IF v_req.kind = 'note' THEN
    v_status := 'acknowledged';
  ELSIF v_req.kind = 'adjustment' THEN
    v_status := 'approved_no_engine_door';
    v_reply := jsonb_build_object('door', NULL,
      'reason', 'OTTO-Q has no door for this adjustment yet. The approval is recorded so a person can act on it; nothing in the engine changed.');
  ELSIF v_req.kind = 'recall_vehicle' THEN
    SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = v_req.vehicle_id;
    IF v_veh.id IS NULL
       OR (v_req.fleet_operator_id IS NOT NULL AND v_veh.fleet_operator_id IS DISTINCT FROM v_req.fleet_operator_id)
       OR (v_veh.current_depot_id IS DISTINCT FROM v_req.depot_id AND v_veh.home_depot_id IS DISTINCT FROM v_req.depot_id) THEN
      v_status := 'approved_not_applied';
      v_reply := jsonb_build_object('door', 'ottoq_hw_recall_vehicle', 'called', false,
        'reason', 'The vehicle is no longer in this request''s scope, so the recall door was not called.');
    ELSE
      v_door := 'ottoq_hw_recall_vehicle';
      BEGIN
        v_reply := public.ottoq_hw_recall_vehicle(
          v_req.vehicle_id,
          left(format('agent request %s from %s: %s', v_req.request_id, v_req.principal_name, v_req.title), 500),
          left(format('agent:%s approved_by:%s:%s', v_req.principal_name, v_by, v_label), 200));
        v_status := CASE WHEN COALESCE((v_reply ->> 'ok')::boolean, false) THEN 'applied' ELSE 'refused_by_engine' END;
        v_applied := now();
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        v_status := 'apply_failed';
        v_reply := jsonb_build_object('door', v_door, 'sqlstate', v_state, 'error', left(v_msg, 300));
      END;
    END IF;
  ELSIF v_req.kind = 'ops_action' THEN
    v_run := public.ottoq_agent_live_run(v_req.depot_id);
    IF v_run IS NULL THEN
      v_status := 'approved_not_applied';
      v_reply := jsonb_build_object('door', 'ottoq_apply_ops_action', 'called', false,
        'reason', 'No run is live at the depot, and an ops action changes a run-scoped dial.');
    ELSIF (v_run ->> 'sim_run_id')::uuid IS DISTINCT FROM v_req.sim_run_id THEN
      v_status := 'approved_not_applied';
      v_reply := jsonb_build_object('door', 'ottoq_apply_ops_action', 'called', false,
        'reason', 'The run this request was made against is no longer the live run.',
        'requested_on_run', v_req.sim_run_id, 'live_run', v_run -> 'sim_run_id');
    ELSE
      v_door := 'ottoq_apply_ops_action';
      BEGIN
        --: 'ottoq_prime:<suffix>' keeps the AGENT envelope and agent_writable guard in force (0559 P1): a person's
        --: approval does not turn an agent's request into a person-privileged write
        v_reply := public.ottoq_apply_ops_action(v_req.sim_run_id, v_req.depot_id, v_req.payload ->> 'action',
                                                 COALESCE(v_req.payload -> 'args', '{}'::jsonb),
                                                 left('ottoq_prime:agent_gateway:' || v_req.principal_name, 120));
        v_status := CASE v_reply ->> 'status'
                      WHEN 'applied'   THEN 'applied'
                      WHEN 'no_change' THEN 'applied'
                      WHEN 'refused'   THEN 'refused_by_engine'
                      ELSE 'apply_failed' END;
        v_applied := now();
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        v_status := 'apply_failed';
        v_reply := jsonb_build_object('door', v_door, 'sqlstate', v_state, 'error', left(v_msg, 300));
      END;
    END IF;
  ELSE
    v_status := 'approved_no_engine_door';
    v_reply := jsonb_build_object('door', NULL, 'reason', format('No route for kind %s.', v_req.kind));
  END IF;

  UPDATE public.ottoq_agent_requests r
     SET status = v_status, decision = 'approved', decided_by_kind = v_by, decided_by_uid = v_uid,
         decided_by_label = v_label, decision_note = v_note, decided_at = now(),
         engine_door = v_door, engine_reply = v_reply, applied_at = v_applied
   WHERE r.request_id = v_req.request_id;
  RETURN jsonb_build_object('ok', true, 'request_id', v_req.request_id, 'decision', 'approved', 'status', v_status,
                            'engine_door', v_door, 'engine_reply', v_reply);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_inbox(
    p_depot_id       uuid    DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    p_include_closed boolean DEFAULT true,
    p_limit          integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0559. PULSE's agent inbox: every outside agent's request at one depot, open ones first. For the depot's own crew
   (any role may read; only a supervisor or ops manager may decide, and `viewer.can_decide` says which). */
DECLARE
  v_uid   uuid    := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_role  text;
  v_label text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sign_in_required', 'message', 'Sign in to read the agent inbox.');
  END IF;
  SELECT s.role::text, COALESCE(NULLIF(btrim(s.display_name), ''), s.first_name || ' ' || left(s.last_name, 1) || '.')
    INTO v_role, v_label
    FROM public.staff_users s
   WHERE s.auth_user_id = v_uid AND s.is_active AND s.depot_id = p_depot_id
   ORDER BY (s.role::text IN ('ops_manager', 'yard_supervisor')) DESC
   LIMIT 1;
  IF v_role IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_depot_staff',
      'message', 'The agent inbox is for the crew of this depot.');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'depot_id', p_depot_id,
    'viewer', jsonb_build_object('role', v_role, 'label', v_label,
                                 'can_decide', v_role IN ('yard_supervisor', 'ops_manager')),
    'counts', (SELECT jsonb_build_object(
                 'open', count(*) FILTER (WHERE r.status = 'pending' AND r.expires_at > now()),
                 'total', count(*))
                 FROM public.ottoq_agent_requests r WHERE r.depot_id = p_depot_id),
    'items', (SELECT COALESCE(jsonb_agg(public.ottoq_agent_request_json(q.r, 'crew')
                                        ORDER BY q.open_first DESC, q.prio DESC, q.ts DESC), '[]'::jsonb)
                FROM (SELECT r,
                             (r.status = 'pending' AND r.expires_at > now()) AS open_first,
                             CASE WHEN r.status = 'pending' AND r.expires_at > now() THEN
                               CASE r.priority WHEN 'urgent' THEN 3 WHEN 'high' THEN 2 WHEN 'normal' THEN 1 ELSE 0 END
                             ELSE 0 END AS prio,
                             COALESCE(r.decided_at, r.created_at) AS ts
                        FROM public.ottoq_agent_requests r
                       WHERE r.depot_id = p_depot_id
                         AND (COALESCE(p_include_closed, true) OR (r.status = 'pending' AND r.expires_at > now()))
                       ORDER BY (r.status = 'pending' AND r.expires_at > now()) DESC, COALESCE(r.decided_at, r.created_at) DESC
                       LIMIT v_limit) q));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_requests_for_operator(
    p_fleet_operator_id uuid,
    p_depot_id          uuid    DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    p_limit             integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0559. OrchestrAV's view: one fleet operator's agent requests at one depot -- requests its own agents made, and
   requests any agent made about its vehicles. Never all operators at once. Who decided is shown as crew/operator,
   never by name. `can_decide` is true only for the auth user bound to this operator in fleet_operators.auth_user_id. */
DECLARE
  v_uid   uuid    := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_name  text;
  v_can   boolean;
BEGIN
  IF p_fleet_operator_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fleet_operator_required',
      'message', 'Name the fleet operator whose requests to read.');
  END IF;
  SELECT f.name INTO v_name FROM public.fleet_operators f WHERE f.id = p_fleet_operator_id;
  IF v_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_fleet_operator', 'message', 'No such fleet operator.');
  END IF;
  v_can := v_uid IS NOT NULL AND EXISTS (SELECT 1 FROM public.fleet_operators f
                                          WHERE f.id = p_fleet_operator_id AND f.auth_user_id = v_uid AND f.is_active);
  RETURN jsonb_build_object(
    'ok', true,
    'fleet_operator', jsonb_build_object('id', p_fleet_operator_id, 'name', v_name),
    'depot_id', p_depot_id,
    'can_decide', v_can,
    'decide_note', CASE WHEN v_can THEN NULL ELSE
      'Deciding from OrchestrAV needs a sign-in on the engine bound to this fleet (fleet_operators.auth_user_id). '
      || 'Until then the depot crew decides these in OTTO-PULSE.' END,
    'counts', (SELECT jsonb_build_object(
                 'open', count(*) FILTER (WHERE r.status = 'pending' AND r.expires_at > now()),
                 'total', count(*))
                 FROM public.ottoq_agent_requests r
                WHERE r.fleet_operator_id = p_fleet_operator_id AND r.depot_id = p_depot_id),
    'items', (SELECT COALESCE(jsonb_agg(public.ottoq_agent_request_json(q.r, 'operator')
                                        ORDER BY q.open_first DESC, q.ts DESC), '[]'::jsonb)
                FROM (SELECT r,
                             (r.status = 'pending' AND r.expires_at > now()) AS open_first,
                             COALESCE(r.decided_at, r.created_at) AS ts
                        FROM public.ottoq_agent_requests r
                       WHERE r.fleet_operator_id = p_fleet_operator_id AND r.depot_id = p_depot_id
                       ORDER BY (r.status = 'pending' AND r.expires_at > now()) DESC, COALESCE(r.decided_at, r.created_at) DESC
                       LIMIT v_limit) q));
END $fn$;

-- ══ 8. issuing and revoking (service_role; Chase runs these in the SQL editor) ══════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_agent_issue_token(
    p_name               text,
    p_kind               text,
    p_capabilities       text[]  DEFAULT ARRAY['read','note']::text[],
    p_fleet_operator_id  uuid    DEFAULT NULL,
    p_depot_id           uuid    DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    p_note               text    DEFAULT NULL,
    p_rate_limit_per_min integer DEFAULT 60,
    p_max_pending        integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $fn$
/* 0559. Creates an agent principal and returns its token ONCE. Only sha256(token) is stored; a lost token cannot be
   recovered -- revoke the principal and issue a new one. */
DECLARE
  v_name  text   := lower(btrim(COALESCE(p_name, '')));
  v_kind  text   := lower(btrim(COALESCE(p_kind, '')));
  v_caps  text[];
  v_token text;
  v_row   public.ottoq_agent_principals;
BEGIN
  IF v_name !~ '^[a-z0-9][a-z0-9_.-]{1,62}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_name',
      'message', '2 to 63 characters of a-z 0-9 . _ -, starting with a letter or digit.');
  END IF;
  IF v_kind NOT IN ('personal', 'fleet_operator', 'depot_ops') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_kind', 'message', 'kind is personal, fleet_operator or depot_ops.');
  END IF;
  IF p_depot_id IS DISTINCT FROM '11111111-1111-1111-1111-111111111111'::uuid THEN
    RETURN jsonb_build_object('ok', false, 'error', 'twin_depot_only',
      'message', 'CLAUDE.md rule 8: the twin depot (11111111-1111-1111-1111-111111111111) is the only site an agent is scoped to.');
  END IF;
  IF v_kind = 'fleet_operator' AND p_fleet_operator_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fleet_operator_required', 'message', 'A fleet_operator agent names its fleet operator.');
  END IF;
  IF v_kind = 'depot_ops' AND p_fleet_operator_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_ops_sees_every_owner', 'message', 'A depot_ops agent is not fleet-scoped.');
  END IF;
  IF p_fleet_operator_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.fleet_operators f WHERE f.id = p_fleet_operator_id AND f.is_active) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_fleet_operator', 'message', 'No active fleet operator with that id.');
  END IF;
  v_caps := ARRAY(SELECT DISTINCT lower(btrim(c)) FROM unnest(COALESCE(p_capabilities, ARRAY[]::text[])) c ORDER BY 1);
  IF cardinality(v_caps) = 0
     OR NOT (v_caps <@ ARRAY['read','note','request_recall','request_ops_action','request_adjustment']::text[]) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_capabilities',
      'allowed', jsonb_build_array('read','note','request_recall','request_ops_action','request_adjustment'));
  END IF;
  IF 'request_ops_action' = ANY (v_caps) AND p_fleet_operator_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ops_action_needs_depot_scope',
      'message', 'An ops action changes the whole depot, so a fleet-scoped agent cannot ask for one.');
  END IF;
  IF p_rate_limit_per_min NOT BETWEEN 1 AND 600 OR p_max_pending NOT BETWEEN 1 AND 200 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_limits', 'message', 'rate 1..600 per minute, pending 1..200.');
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_agent_principals a WHERE a.name = v_name) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'name_taken',
      'message', 'A principal already has that name. A token''s scope is fixed at issue: revoke the old one and issue under a new name.');
  END IF;

  v_token := 'oqa_' || encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO public.ottoq_agent_principals
    (name, kind, depot_id, fleet_operator_id, capabilities, token_hash, token_prefix, rate_limit_per_min, max_pending, note)
  VALUES
    (v_name, v_kind, p_depot_id, p_fleet_operator_id, v_caps, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
     left(v_token, 12), p_rate_limit_per_min, p_max_pending, NULLIF(btrim(COALESCE(p_note, '')), ''))
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'ok', true,
    'token', v_token,
    'warning', 'This is the only time the token is shown. Only its SHA-256 is stored. If it is lost, revoke this principal and issue a new one.',
    'principal', jsonb_build_object('principal_id', v_row.principal_id, 'name', v_row.name, 'kind', v_row.kind,
                                    'depot_id', v_row.depot_id, 'fleet_operator_id', v_row.fleet_operator_id,
                                    'capabilities', to_jsonb(v_row.capabilities), 'token_prefix', v_row.token_prefix,
                                    'rate_limit_per_min', v_row.rate_limit_per_min, 'max_pending', v_row.max_pending));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_revoke(p_principal text, p_reason text, p_expire_pending boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0559. Revokes a principal by name or id. Final: a revoked principal cannot be re-activated. By default its open
   requests expire with it -- a revoked token may have been stolen, and its questions should not reach a person. */
DECLARE
  v_key text := btrim(COALESCE(p_principal, ''));
  v_id  uuid;
  v_row public.ottoq_agent_principals;
  v_n   integer := 0;
BEGIN
  IF btrim(COALESCE(p_reason, '')) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reason_required', 'message', 'Say why the token is revoked.');
  END IF;
  --: cast in its own statement: a CASE inside the query does not stop the planner folding 'name'::uuid
  IF v_key ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    v_id := v_key::uuid;
  END IF;
  SELECT * INTO v_row FROM public.ottoq_agent_principals a
   WHERE a.name = lower(v_key) OR a.principal_id = v_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found', 'message', 'No principal with that name or id.');
  END IF;
  IF v_row.status = 'revoked' THEN
    RETURN jsonb_build_object('ok', true, 'already_revoked', true, 'name', v_row.name, 'revoked_at', v_row.revoked_at);
  END IF;
  UPDATE public.ottoq_agent_principals a
     SET status = 'revoked', revoked_at = now(), revoked_reason = left(btrim(p_reason), 500)
   WHERE a.principal_id = v_row.principal_id;
  IF COALESCE(p_expire_pending, true) THEN
    UPDATE public.ottoq_agent_requests r
       SET status = 'expired', closed_reason = left('principal revoked: ' || btrim(p_reason), 500)
     WHERE r.principal_id = v_row.principal_id AND r.status = 'pending';
    GET DIAGNOSTICS v_n = ROW_COUNT;
  END IF;
  RETURN jsonb_build_object('ok', true, 'principal_id', v_row.principal_id, 'name', v_row.name,
                            'revoked_at', now(), 'open_requests_expired', v_n);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_expire_lapsed()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0559. Records every lapsed pending request as expired. Reads already show a lapsed request as expired, so nothing
   depends on this running; it exists for a future scheduled job, and none is scheduled by 0559. */
DECLARE v_n integer;
BEGIN
  UPDATE public.ottoq_agent_requests r
     SET status = 'expired', closed_reason = 'lapsed: nobody decided before it expired'
   WHERE r.status = 'pending' AND r.expires_at <= now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'expired', v_n);
END $fn$;

-- ══ 9. privileges: revoke everything, then grant exactly ════════════════════════════════════════════════════════════

ALTER TABLE public.ottoq_agent_principals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_agent_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_agent_call_ledger ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_agent_principals, public.ottoq_agent_requests, public.ottoq_agent_call_ledger
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE public.ottoq_agent_call_ledger_call_id_seq FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.ottoq_agent_ledger_append_only(),
  public.ottoq_agent_no_truncate(),
  public.ottoq_agent_requests_guard(),
  public.ottoq_agent_principals_guard(),
  public.ottoq_agent_arg_int(jsonb, text, integer, integer, integer),
  public.ottoq_agent_arg_uuid(jsonb, text),
  public.ottoq_agent_resolve(text),
  public.ottoq_agent_live_run(uuid),
  public.ottoq_agent_vehicle_in_scope(public.ottoq_agent_principals, uuid),
  public.ottoq_agent_compact_card(jsonb),
  public.ottoq_agent_request_json(public.ottoq_agent_requests, text),
  public.ottoq_agent_read_whoami(public.ottoq_agent_principals),
  public.ottoq_agent_read_depot(public.ottoq_agent_principals),
  public.ottoq_agent_read_fleet(public.ottoq_agent_principals, jsonb),
  public.ottoq_agent_read_vehicle(public.ottoq_agent_principals, jsonb),
  public.ottoq_agent_read_decisions(public.ottoq_agent_principals, jsonb),
  public.ottoq_agent_read_stalls(public.ottoq_agent_principals, jsonb),
  public.ottoq_agent_read_requests(public.ottoq_agent_principals, jsonb),
  public.ottoq_agent_submit_request(public.ottoq_agent_principals, text, jsonb),
  public.ottoq_agent_call(text, text, jsonb, text, jsonb),
  public.ottoq_agent_issue_token(text, text, text[], uuid, uuid, text, integer, integer),
  public.ottoq_agent_revoke(text, text, boolean),
  public.ottoq_agent_expire_lapsed(),
  public.ottoq_agent_inbox(uuid, boolean, integer),
  public.ottoq_agent_request_decide(uuid, text, text),
  public.ottoq_agent_requests_for_operator(uuid, uuid, integer)
  FROM PUBLIC, anon, authenticated, service_role;

-- the gateway's one door, and the admin doors: the service key only
GRANT EXECUTE ON FUNCTION public.ottoq_agent_call(text, text, jsonb, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_issue_token(text, text, text[], uuid, uuid, text, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_revoke(text, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_expire_lapsed() TO service_role;
-- the people's doors: signed-in users (the functions themselves decide who among them may act)
GRANT EXECUTE ON FUNCTION public.ottoq_agent_inbox(uuid, boolean, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_request_decide(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_requests_for_operator(uuid, uuid, integer) TO authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_agent_call(text, text, jsonb, text, jsonb) IS
'0559. The one door the ottoq-agent-gateway edge function calls (service_role only): token hash -> active principal -> rate limit -> capability -> tool -> call ledger, in one transaction. Tools: handshake, whoami, depot_status, fleet_summary, vehicle_card, recent_decisions, stall_availability, list_requests, send_note, submit_request. Returns {ok, http_status, tool, call_id, principal?, data? | error?}. Names no engine door: an agent reads and ASKS; a person decides through ottoq_agent_request_decide.';
COMMENT ON FUNCTION public.ottoq_agent_request_decide(uuid, text, text) IS
'0559. A signed-in person approves or declines an outside agent''s request. Crew = yard_supervisor/ops_manager of the request''s depot; operator = the auth user in fleet_operators.auth_user_id, own fleet only, never an ops action. Approval routes: note -> acknowledged; recall_vehicle -> ottoq_hw_recall_vehicle; ops_action -> ottoq_apply_ops_action as ottoq_prime:agent_gateway:<principal> (agent envelope kept), on the run it was asked against; adjustment -> approved_no_engine_door. The door''s reply is stored verbatim in engine_reply.';
COMMENT ON FUNCTION public.ottoq_agent_inbox(uuid, boolean, integer) IS
'0559. OTTO-PULSE''s agent inbox for one depot: open requests first. Readable by that depot''s staff (auth.uid() in staff_users); viewer.can_decide is true for yard_supervisor and ops_manager.';
COMMENT ON FUNCTION public.ottoq_agent_requests_for_operator(uuid, uuid, integer) IS
'0559. OrchestrAV''s agent requests for ONE fleet operator (never all). anon is not granted by 0559; 0560 is the separate, optional grant. can_decide is true only for the auth user bound in fleet_operators.auth_user_id.';
COMMENT ON FUNCTION public.ottoq_agent_issue_token(text, text, text[], uuid, uuid, text, integer, integer) IS
'0559. Issue an agent token (service_role / SQL editor). Returns the token ONCE; stores only sha256. Twin depot only (rule 8). Scope is fixed at issue.';
COMMENT ON FUNCTION public.ottoq_agent_revoke(text, text, boolean) IS
'0559. Revoke an agent principal by name or id, with a reason. Final. Expires its open requests unless p_expire_pending is false.';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_tbl     text;
  v_fn      regprocedure;
  v_src     text;
  v_bad     text;
  v_block   integer;
  v_res     jsonb;
  v_target  text;
  v_internal regprocedure[] := ARRAY[
    'public.ottoq_agent_arg_int(jsonb,text,integer,integer,integer)',
    'public.ottoq_agent_arg_uuid(jsonb,text)',
    'public.ottoq_agent_resolve(text)',
    'public.ottoq_agent_live_run(uuid)',
    'public.ottoq_agent_vehicle_in_scope(public.ottoq_agent_principals,uuid)',
    'public.ottoq_agent_compact_card(jsonb)',
    'public.ottoq_agent_request_json(public.ottoq_agent_requests,text)',
    'public.ottoq_agent_read_whoami(public.ottoq_agent_principals)',
    'public.ottoq_agent_read_depot(public.ottoq_agent_principals)',
    'public.ottoq_agent_read_fleet(public.ottoq_agent_principals,jsonb)',
    'public.ottoq_agent_read_vehicle(public.ottoq_agent_principals,jsonb)',
    'public.ottoq_agent_read_decisions(public.ottoq_agent_principals,jsonb)',
    'public.ottoq_agent_read_stalls(public.ottoq_agent_principals,jsonb)',
    'public.ottoq_agent_read_requests(public.ottoq_agent_principals,jsonb)',
    'public.ottoq_agent_submit_request(public.ottoq_agent_principals,text,jsonb)']::regprocedure[];
  v_service regprocedure[] := ARRAY[
    'public.ottoq_agent_call(text,text,jsonb,text,jsonb)',
    'public.ottoq_agent_issue_token(text,text,text[],uuid,uuid,text,integer,integer)',
    'public.ottoq_agent_revoke(text,text,boolean)',
    'public.ottoq_agent_expire_lapsed()']::regprocedure[];
  v_people regprocedure[] := ARRAY[
    'public.ottoq_agent_inbox(uuid,boolean,integer)',
    'public.ottoq_agent_request_decide(uuid,text,text)',
    'public.ottoq_agent_requests_for_operator(uuid,uuid,integer)']::regprocedure[];
BEGIN
  -- V1: the tables are closed to every client role; service_role keeps no write; RLS on with no policy; no run FK
  FOREACH v_tbl IN ARRAY ARRAY['public.ottoq_agent_principals', 'public.ottoq_agent_requests', 'public.ottoq_agent_call_ledger'] LOOP
    IF has_table_privilege('anon', v_tbl, 'SELECT') OR has_table_privilege('anon', v_tbl, 'INSERT')
       OR has_table_privilege('authenticated', v_tbl, 'SELECT') OR has_table_privilege('authenticated', v_tbl, 'INSERT')
       OR has_table_privilege('authenticated', v_tbl, 'UPDATE') OR has_table_privilege('authenticated', v_tbl, 'DELETE')
       OR has_table_privilege('service_role', v_tbl, 'INSERT') OR has_table_privilege('service_role', v_tbl, 'UPDATE')
       OR has_table_privilege('service_role', v_tbl, 'DELETE') OR has_table_privilege('service_role', v_tbl, 'TRUNCATE') THEN
      RAISE EXCEPTION '0559 V1: % is reachable by a client role or writable by service_role', v_tbl;
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = v_tbl::regclass)
       OR EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = v_tbl::regclass) THEN
      RAISE EXCEPTION '0559 V1: % does not have RLS on with no policy', v_tbl;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE contype = 'f' AND conrelid = v_tbl::regclass
                  AND confrelid = 'public.ottoq_sim_runs'::regclass) THEN
      RAISE EXCEPTION '0559 V1: % acquired a foreign key to ottoq_sim_runs', v_tbl;
    END IF;
  END LOOP;

  -- V2: every SECURITY DEFINER function here pins its search_path
  SELECT string_agg(p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'ottoq\_agent\_%' AND p.prosecdef
     AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%')
     AND p.oid = ANY ((v_internal || v_service || v_people)::oid[]);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0559 V2: SECURITY DEFINER without a pinned search_path: %', v_bad;
  END IF;

  -- V3: grants, measured rather than trusted
  FOREACH v_fn IN ARRAY v_internal LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION '0559 V3: internal % is executable by a client role (a caller that passes its own principal row needs no token)', v_fn;
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_service LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION '0559 V3: % is not service_role-only', v_fn;
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_people LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION '0559 V3: % is not authenticated-only', v_fn;
    END IF;
  END LOOP;

  -- V4: registered as evidence, and the guard is clean and silent about the new tables
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name = 'ottoq_agent_requests' AND column_name = 'sim_run_id' AND class = 'evidence') THEN
    RAISE EXCEPTION '0559 V4: ottoq_agent_requests.sim_run_id is not registered as evidence';
  END IF;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0559 V4: the registry guard now reports % blocking defect(s)', v_block;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE table_name LIKE 'ottoq\_agent\_%') THEN
    RAISE EXCEPTION '0559 V4: the registry guard reports an ottoq_agent_* table';
  END IF;

  -- V5: NOTHING AN AGENT'S TOKEN CAN REACH NAMES A DOOR OR WRITES OUTSIDE THE AGENT LEDGER. Comment-stripped and
  -- whitespace-tolerant, because an assertion a formatting difference can flip is not an assertion (CLAUDE.md 2.9a).
  FOREACH v_fn IN ARRAY (v_internal || ARRAY['public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure]) LOOP
    v_src := regexp_replace(regexp_replace((SELECT prosrc FROM pg_proc WHERE oid = v_fn), '/\*.*?\*/', '', 'g'),
                            '--[^' || chr(10) || ']*', '', 'g');
    IF v_src ~* '(ottoq_hw_recall_vehicle|ottoq_apply_ops_action|ottoq_agent_request_decide|ottoq_submit_external_proposal|ottoq_policy_set|ottoq_hw_set_return_threshold)' THEN
      RAISE EXCEPTION '0559 V5: % names an engine door', v_fn;
    END IF;
    FOR v_target IN
      SELECT lower(regexp_replace(m[2], '^public\.', ''))
        FROM regexp_matches(v_src, '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+([a-z_.]+)', 'gi') AS m
    LOOP
      IF v_target NOT LIKE 'ottoq\_agent\_%' THEN
        RAISE EXCEPTION '0559 V5: % writes to % (the agent side may write only ottoq_agent_* tables)', v_fn, v_target;
      END IF;
    END LOOP;
  END LOOP;
  -- ...and the decide door is the one function here that does name the doors
  v_src := (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_agent_request_decide(uuid,text,text)'::regprocedure);
  IF position('ottoq_hw_recall_vehicle' IN v_src) = 0 OR position('ottoq_apply_ops_action' IN v_src) = 0 THEN
    RAISE EXCEPTION '0559 V5: the decide door does not route to both engine doors';
  END IF;

  -- V6: a decision needs a signed-in person, whoever holds the connection
  v_res := public.ottoq_agent_request_decide('00000000-0000-0000-0000-000000000000'::uuid, 'approved');
  IF v_res ->> 'error' IS DISTINCT FROM 'sign_in_required' THEN
    RAISE EXCEPTION '0559 V6: the decide door answered % without a signed-in person', v_res;
  END IF;
  v_res := public.ottoq_agent_request_decide('00000000-0000-0000-0000-000000000000'::uuid, 'maybe');
  IF COALESCE((v_res ->> 'ok')::boolean, true) THEN
    RAISE EXCEPTION '0559 V6: the decide door accepted a decision that is neither approved nor declined';
  END IF;

  -- V8: forces_recert FALSE, executed: no pre-existing routine reads the new tables
  SELECT string_agg(p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin')
     AND p.prosrc ~* 'ottoq_agent_(principals|requests|call_ledger)'
     AND p.proname NOT LIKE 'ottoq\_agent\_%';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0559 V8: an existing routine already reads the new tables: %', v_bad;
  END IF;
END $verify$;

-- V7: THE ROUND TRIP, EXECUTED AND ROLLED BACK. Issue a probe token, read, write a note, replay it, be refused a
-- capability, be refused with a wrong token, try to edit and delete the ledgers, revoke, be refused again -- then undo
-- all of it. The token never leaves this block. A probe that cannot fail is a comment; each step below can.
DO $probe$
DECLARE
  v        jsonb;
  v_hash   text;
  v_req    uuid;
  v_ok     boolean;
BEGIN
  BEGIN
    v := public.ottoq_agent_issue_token('probe-0559-v7', 'personal', ARRAY['read','note'], NULL,
                                        '11111111-1111-1111-1111-111111111111', '0559 V7, rolled back', 60, 5);
    IF NOT COALESCE((v ->> 'ok')::boolean, false) THEN RAISE EXCEPTION '0559 V7a: issue refused: %', v - 'token'; END IF;
    v_hash := encode(sha256(convert_to(v ->> 'token', 'UTF8')), 'hex');

    v := public.ottoq_agent_call(v_hash, 'whoami', '{}'::jsonb, 'rest', '{}'::jsonb);
    IF NOT COALESCE((v ->> 'ok')::boolean, false) OR v #>> '{data,principal,name}' IS DISTINCT FROM 'probe-0559-v7' THEN
      RAISE EXCEPTION '0559 V7b: whoami read %', v;
    END IF;

    v := public.ottoq_agent_call(v_hash, 'send_note',
           jsonb_build_object('title', '0559 V7 probe', 'body', 'rolled back', 'idempotency_key', 'v7'), 'rest', '{}'::jsonb);
    IF (v ->> 'http_status')::integer IS DISTINCT FROM 201 THEN RAISE EXCEPTION '0559 V7c: a note read %', v; END IF;
    v_req := (v #>> '{data,request,request_id}')::uuid;

    v := public.ottoq_agent_call(v_hash, 'send_note',
           jsonb_build_object('title', '0559 V7 probe', 'idempotency_key', 'v7'), 'rest', '{}'::jsonb);
    IF NOT COALESCE((v #>> '{data,duplicate}')::boolean, false) OR (v #>> '{data,request,request_id}')::uuid IS DISTINCT FROM v_req THEN
      RAISE EXCEPTION '0559 V7d: the same idempotency key did not replay: %', v;
    END IF;

    v := public.ottoq_agent_call(v_hash, 'submit_request',
           jsonb_build_object('kind', 'recall_vehicle', 'title', 'x', 'vehicle_id', gen_random_uuid()), 'rest', '{}'::jsonb);
    IF (v ->> 'http_status')::integer IS DISTINCT FROM 403 THEN
      RAISE EXCEPTION '0559 V7e: a token without request_recall was not refused: %', v;
    END IF;

    --: arguments the gateway refused still come here first: authenticated, refused, and ledgered under their tool
    v := public.ottoq_agent_call(v_hash, 'vehicle_card', '{}'::jsonb, 'rest',
           jsonb_build_object('gateway_refusal', 'invalid_arguments', 'path', '/v1/vehicles/not-a-uuid'));
    IF (v ->> 'http_status')::integer IS DISTINCT FROM 400 OR (v #>> '{error,code}') IS DISTINCT FROM 'invalid_arguments'
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_agent_call_ledger l
                       WHERE l.call_id = (v ->> 'call_id')::bigint AND l.tool = 'vehicle_card'
                         AND l.http_status = 400 AND l.error_code = 'invalid_arguments') THEN
      RAISE EXCEPTION '0559 V7e2: a call the gateway refused was not refused and ledgered here: %', v;
    END IF;

    v := public.ottoq_agent_call(repeat('0', 64), 'whoami', '{}'::jsonb, 'rest', '{}'::jsonb);
    IF (v ->> 'http_status')::integer IS DISTINCT FROM 401 THEN RAISE EXCEPTION '0559 V7f: an unknown token read %', v; END IF;

    BEGIN
      UPDATE public.ottoq_agent_requests SET title = 'edited' WHERE request_id = v_req;
      v_ok := false;
    EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION '0559 V7g: what the agent asked could be edited'; END IF;
    BEGIN
      DELETE FROM public.ottoq_agent_requests WHERE request_id = v_req;
      v_ok := false;
    EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION '0559 V7h: a request could be deleted'; END IF;
    BEGIN
      DELETE FROM public.ottoq_agent_call_ledger WHERE principal_name = 'probe-0559-v7';
      v_ok := false;
    EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION '0559 V7i: the call ledger could be deleted from'; END IF;

    v := public.ottoq_agent_revoke('probe-0559-v7', '0559 V7', true);
    IF NOT COALESCE((v ->> 'ok')::boolean, false) OR (v ->> 'open_requests_expired')::integer IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION '0559 V7j: revoke read %', v;
    END IF;
    v := public.ottoq_agent_call(v_hash, 'whoami', '{}'::jsonb, 'rest', '{}'::jsonb);
    IF (v ->> 'http_status')::integer IS DISTINCT FROM 401 THEN RAISE EXCEPTION '0559 V7k: a revoked token read %', v; END IF;

    RAISE EXCEPTION USING ERRCODE = 'OQA99', MESSAGE = '0559_v7_rollback';
  EXCEPTION WHEN SQLSTATE 'OQA99' THEN
    NULL;  -- everything above is undone; each step proved what it set out to
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_agent_principals WHERE name = 'probe-0559-v7')
     OR EXISTS (SELECT 1 FROM public.ottoq_agent_requests)
     OR EXISTS (SELECT 1 FROM public.ottoq_agent_call_ledger) THEN
    RAISE EXCEPTION '0559 V7: the probe survived its own rollback';
  END IF;
END $probe$;

-- Rollback: DROP FUNCTION each ottoq_agent_* function this file created (the list in section 9), DROP TABLE
-- public.ottoq_agent_call_ledger, public.ottoq_agent_requests, public.ottoq_agent_principals (in that order),
-- DELETE FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_agent_requests', and
-- DELETE FROM public.ottoq_cert_lineage WHERE name = '0559_an_outside_agent_asks_through_one_door_and_a_person_decides'.
-- Nothing else was touched.

--: forces_dial_restart is FALSE, stated rather than left NULL: 0523 reads COALESCE(forces_dial_restart, true), so an
--: omitted value would restart every dial experiment's pair count for a file that cannot move an arm. A dial pair runs
--: inside a certification transaction that takes no outside input, and no tick-path function reads these tables (V8).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0559_an_outside_agent_asks_through_one_door_and_a_person_decides', false, false,
  'Additive: three agent tables (principals, requests as evidence, call ledger), the gateway dispatcher, the people''s decide/inbox doors and one registry row. No existing function body changes; nothing on the tick path reads the new tables (V8); a certification pair or a dial pair takes no outside input, so it cannot carry an agent request, and no dial arm can come out differently. The two engine doors are called only from ottoq_agent_request_decide, by a signed-in person.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
