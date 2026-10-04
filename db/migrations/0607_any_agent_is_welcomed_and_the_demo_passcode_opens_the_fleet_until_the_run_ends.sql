-- migration-version: PENDING
-- migration-name:    any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends
--
-- 0607  **Any agent is welcomed, and the demo passcode opens the fleet until the run ends.** An agent that reaches
--       OTTOYARD without a key (Hermes, Grok, ChatGPT, Claude, a script) is greeted, asked for OTTOYARD's demo
--       passcode, and with it gets a session on Tesla Robotaxi TN's cars at the twin depot: the same reads and owner
--       commands an issued owner key has (0605), inside the same contract and rules, answered with the same receipts.
--       Every accepted change now carries a confirmation code that OrchestrAV, OTTO-PULSE and the twin show beside it
--       (0608). And a stop or reset of the twin ends every passcode session along with everything set in it, so the
--       next demo starts at the welcome again.
--
--       Chase, 2026-10-03, 10:50 PM CT: "I want to be able to setup and activate a new agent from theoretically Hermes
--       or [Grok] or any other agent and be able to call OTTOYARD ... and allow me to access my fleet ... a general
--       password or passcode that I can enter after the welcome agent triggered ... if it's something that doesn't
--       fit, [OTTO-Q] should send back a failure state that is still within plain English and explaining why.
--       Otherwise it should send back a confirmation and validation code with link to the orchestra app and updated
--       information ... any adjustments that are made from this respective should only apply for a single simulation
--       run."
--
-- ══ §1 WHAT WAS MISSING (read from the files and the live catalog, 2026-10-04 03:30-04:30 UTC, read-only) ═══════════
--
--   (a) An agent reached the owner tools only with a key issued by SQL (0559 ottoq_agent_issue_token) and pasted into
--       its own configuration: fine for one person's agent, not for "if I gave somebody the password they could test
--       from their [Grok] bot ... or technically any other interface". Without a key the gateway answered 401 before
--       the database: no greeting, and nothing an agent could act on.
--   (b) A receipt carried a command_id (a uuid) and a link, and nothing short a person could read aloud and match on
--       a screen.
--   (c) 0605 lifts every owner SETTING at a demo run's end; nothing ended an agent's ACCESS with it.
--   (d) A demo run ends in ottoq_sim_mark_stopped: UPDATE status 'running' | 'paused' -> 'completed', and the twin's
--       Stop and Reset both go through it (ottoq_sim_stop_and_reset). Pause writes 'paused', which is not an end: a
--       paused run keeps its settings and its sessions. Every terminal twin-depot run in the census has ended_at set.
--   (e) A run's row does not last: ottoq_purge_prior_runs deletes prior runs when the next demo starts. So "a run ended
--       after this session opened" cannot be READ later from ottoq_sim_runs. It is RECORDED when it happens, by a
--       trigger on the transition, as 0605's lift is.
--
-- ══ §2 WHAT THIS BUILDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   THE PASSCODE: public.ottoq_agent_demo_passcode, one row for the twin depot: the fleet it opens (Tesla Robotaxi TN),
--   a bcrypt hash of the passcode (pgcrypto crypt / gen_salt('bf'); the passcode is never stored or returned), how long
--   a session lasts (240 minutes) and whether the door is on. Seeded OFF, with no passcode. Set or change it with
--       SELECT public.ottoq_agent_set_passcode('the passcode');          -- 6 to 64 characters
--   (service_role, or the SQL editor). NULL turns the door off. A new passcode leaves open sessions open: they end with
--   the run, as every session does.
--
--   A SESSION IS A PRINCIPAL. The right passcode creates an ottoq_agent_principals row exactly like an issued owner key
--   (kind personal, the passcode's fleet, the twin depot, read + note + owner_settings, 30 calls a minute) plus three
--   new columns: origin 'passcode' (issued keys are 'issued'), display_name (the name the agent gave, e.g. "Grok") and
--   expires_at. Its key is 'oqs_' + 64 hex (an issued key is 'oqa_'), returned once and stored as SHA-256. So all that
--   0559 and 0605 built (scope, rate limit, ledger, owner tools, receipts, refusals, undo, OrchestrAV) serves a
--   passcode session unchanged, and a session can do nothing an issued owner key cannot.
--
--   TWO PUBLIC TOOLS, inside 0559's one dispatcher (ottoq_agent_call stays the gateway's only door into the database):
--     welcome          Anyone. Not connected: what OTTOYARD is, what the passcode opens (the fleet and its cars by
--                      model), whether a demo run is live, and the exact next call. Connected: who you are, until when,
--                      and what to try.
--     enter_passcode   {passcode, agent?}: a session, or a plain-English no. Wrong passcodes are counted from the call
--                      ledger, per caller (5 in 15 minutes, then a wait) and across all callers (200 in 15 minutes).
--   A missing, expired or ended session is answered in plain English (session_ended, session_expired, or "connect
--   first"), not with a bare "unknown token".
--
--   THE RUN'S END CLOSES THE DOOR. AFTER UPDATE OF status ON ottoq_sim_runs, on 0605's terminal transition and only for
--   run_by = 'operator_demo' (in the trigger's WHEN), every active passcode session at that depot is revoked with
--   revoked_reason 'run_ended: ...'. A session opened before a run started ends when that run ends, too.
--
--   THE CONFIRMATION CODE. public.ottoq_owner_confirmation_code(command_id) = 'OQ-' and the first 8 hex digits of the
--   SHA-256 of the command's 16 uuid bytes, as XXXX-XXXX ("OQ-7F3A-91C2"). Derived, never stored: the agent's receipt,
--   my_commands, OrchestrAV, OTTO-PULSE and the twin (0608) all show the same code for the same command, and a replayed
--   receipt carries it again. ottoq_owner_command_reply adds `confirmation_code` to every applied command, and the line
--   "Confirmation code: OQ-XXXX-XXXX." above the OrchestrAV link.
--
-- ══ §3 THE SAFETY ENVELOPE ══════════════════════════════════════════════════════════════════════════════════════════
--
--   * A passcode session is an owner key with an expiry and nothing more. 0605's envelope holds unchanged: the fleet's
--     own cars only, a live demo run only, the contract's range, add work and never remove it, holds only delay, and
--     nothing moves a car. A CHECK pins a session's capabilities to read + note + owner_settings; it never asks for
--     recalls, ops actions or adjustments.
--   * One passcode opens one fleet at one depot, the twin (rule 8, a CHECK).
--   * The passcode is a bcrypt hash, wrong tries are throttled, and the session key is shown once and kept as SHA-256.
--   * A session ends at 240 minutes or at the demo run's end, whichever is first. A revocation is final (0559's guard).
--   * Demo-grade by Chase's decision ("this doesn't have to be extremely secure"): everyone with the passcode shares
--     the same demo fleet, and a run's end resets all of it.
--
-- ══ §4 WHAT IT DELIBERATELY DOES NOT DO ═════════════════════════════════════════════════════════════════════════════
--
--   * No OAuth. A "Connect OTTOYARD" sign-in page (MCP authorization) keeps the key out of the chat entirely and is the
--     right step for real owners; this is the in-chat passcode the demos need now.
--   * No sandbox per visitor: one demo fleet, shared, reset by the run's end.
--   * No change to how an issued key behaves (V4 issues one and uses it).
--   * Nothing on the tick path, and no engine function. The one trigger fires only for an operator_demo run.
--
-- ══ §5 forces_recert FALSE, forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   Every function this file creates or replaces belongs to the agent door (ottoq_agent_*, the owner reply), which no
--   certification, dial or sweep arm calls. The one engine-table change is a trigger on ottoq_sim_runs whose WHEN
--   requires run_by = 'operator_demo'. No arm's run carries that run_by (the twin depot's census: ab_harness,
--   cert_harness, production_live, operator_demo), so the function never executes inside an arm, and it writes only
--   ottoq_agent_principals, which no atom reads. V1 asserts the WHEN and the one table it writes.
--
-- ══ §6 VALIDATED ON A SCRATCH CLUSTER ═══════════════════════════════════════════════════════════════════════════════
--
--   tests/test_passcode_door_sql.py applies 0559, 0560, 0605, 0606, 0607 and 0608 over the stub engine and drives the
--   welcome, the passcode (off, wrong, throttled, right), a session's owner commands and their confirmation codes, the
--   run's end, expiry, an issued key alongside, and the grants. tests/owner_agent.test.mjs drives the same through the
--   gateway over MCP and REST.

BEGIN;

-- ── P0: nothing in flight (this file adds a trigger to ottoq_sim_runs) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0607 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0605 and 0606 applied as written; the five bodies this file replaces are the ones it was written against ──
DO $premises$
DECLARE v_bad text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends') THEN
    RAISE EXCEPTION '0607 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0605_an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0606_the_fleet_owner_cockpit_reads_what_its_agent_set') THEN
    RAISE EXCEPTION '0607 P1: 0605 and 0606 (owner settings and their cockpit read) are not applied; apply them first';
  END IF;
  -- md5(prosrc), measured on a scratch cluster with 0559, 0560, 0605 and 0606 applied from their files as merged
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)',                           '684791f21a850530fecf276f35bd82a4'),
      ('public.ottoq_agent_resolve(text)',                                              '6692a8e5ec6a2dcc2220d6ffa165cba3'),
      ('public.ottoq_agent_principals_guard()',                                         'd35f98eb3d5ad0e4ed6d1e11e5d4445f'),
      ('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)',                 'b11f634f55ee36e789252ab0c27cfca5'),
      ('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)',         'e0934475c3fd87a65dbc0d7d1b12d4a7')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(f)) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0607 P1: not the body this file was written against (re-measure before applying): %', v_bad;
  END IF;
  -- the run's end, as 0605's lift reads it: this file's trigger fires on the same transition
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.ottoq_sim_runs'::regclass AND t.tgname = 'ottoq_sim_runs_lift_owner_settings') THEN
    RAISE EXCEPTION '0607 P1: 0605''s run-end trigger ottoq_sim_runs_lift_owner_settings is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'ottoq_sim_runs' AND column_name = 'run_by') THEN
    RAISE EXCEPTION '0607 P1: ottoq_sim_runs.run_by is missing';
  END IF;
  -- the fleet the passcode opens, and the two pgcrypto functions it hashes with
  IF NOT EXISTS (SELECT 1 FROM public.fleet_operators f WHERE f.id = '33333333-3333-3333-3333-333333333333' AND f.is_active) THEN
    RAISE EXCEPTION '0607 P1: Tesla Robotaxi TN (33333333-...) is not an active fleet operator';
  END IF;
  IF to_regprocedure('extensions.crypt(text,text)') IS NULL OR to_regprocedure('extensions.gen_salt(text,integer)') IS NULL
     OR to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL THEN
    RAISE EXCEPTION '0607 P1: pgcrypto (crypt, gen_salt, gen_random_bytes) is not in schema extensions';
  END IF;
END $premises$;

-- ── P2: nothing this file creates exists yet ──
DO $fresh$
DECLARE v_fn text;
BEGIN
  IF to_regclass('public.ottoq_agent_demo_passcode') IS NOT NULL THEN
    RAISE EXCEPTION '0607 P2: public.ottoq_agent_demo_passcode already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_agent_principals'
                AND column_name IN ('origin', 'display_name', 'expires_at')) THEN
    RAISE EXCEPTION '0607 P2: ottoq_agent_principals already has a column this file adds';
  END IF;
  SELECT string_agg(p.proname, ', ') INTO v_fn
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('ottoq_agent_set_passcode', 'ottoq_agent_public_call', 'ottoq_agent_welcome_public',
                       'ottoq_agent_welcome_connected', 'ottoq_agent_unauthenticated', 'ottoq_agent_fleet_line',
                       'ottoq_owner_confirmation_code', 'ottoq_tg_end_passcode_sessions_on_terminal');
  IF v_fn IS NOT NULL THEN
    RAISE EXCEPTION '0607 P2: function(s) this file creates already exist: %', v_fn;
  END IF;
END $fresh$;

-- ── the rollback snapshot of the five bodies this file replaces ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0607_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure,
                 'public.ottoq_agent_resolve(text)'::regprocedure,
                 'public.ottoq_agent_principals_guard()'::regprocedure,
                 'public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure,
                 'public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure);

-- ══ 1. a principal can be a passcode session ════════════════════════════════════════════════════════════════════════

ALTER TABLE public.ottoq_agent_principals
  ADD COLUMN origin       text NOT NULL DEFAULT 'issued',
  ADD COLUMN display_name text,
  ADD COLUMN expires_at   timestamptz;

ALTER TABLE public.ottoq_agent_principals DROP CONSTRAINT ottoq_agent_principals_token_prefix_check;
ALTER TABLE public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_token_prefix_check
  CHECK (token_prefix ~ '^oq[as]_[0-9a-f]{8}$');
ALTER TABLE public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_origin_check
  CHECK (origin IN ('issued', 'passcode'));
--: an issued key starts oqa_ and never lapses on its own; a passcode session starts oqs_, carries the agent's name and
--: an expiry, and holds exactly what an owner key holds -- never a request_* capability
ALTER TABLE public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_origin_shape_check CHECK (
  CASE origin
    WHEN 'issued' THEN token_prefix LIKE 'oqa\_%' AND expires_at IS NULL
    ELSE token_prefix LIKE 'oqs\_%' AND expires_at IS NOT NULL AND display_name IS NOT NULL
         AND fleet_operator_id IS NOT NULL AND kind = 'personal'
         AND capabilities = ARRAY['note', 'owner_settings', 'read']::text[]
  END);
ALTER TABLE public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_display_name_check
  CHECK (display_name IS NULL OR (length(display_name) BETWEEN 1 AND 60 AND display_name !~ '[[:cntrl:]]'));

CREATE INDEX ottoq_agent_principals_open_sessions_idx ON public.ottoq_agent_principals (depot_id)
  WHERE origin = 'passcode' AND status = 'active';

COMMENT ON COLUMN public.ottoq_agent_principals.origin IS
'0607. issued = a key minted by ottoq_agent_issue_token (oqa_, no expiry); passcode = a session opened with OTTOYARD''s demo passcode through enter_passcode (oqs_, expires_at set, revoked when a demo run at its depot ends).';
COMMENT ON COLUMN public.ottoq_agent_principals.display_name IS
'0607. The name a passcode session''s agent gave itself ("Grok", "Chase''s Hermes"), as shown on receipts and in the cockpits. NULL for issued keys (their name is the principal name).';
COMMENT ON COLUMN public.ottoq_agent_principals.expires_at IS
'0607. When a passcode session lapses on its own (ottoq_agent_resolve refuses it after). NULL for issued keys.';

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
  --: a token's scope is fixed at issue (0607: and so are a passcode session's origin, name and expiry)
  IF (NEW.principal_id, NEW.name, NEW.kind, NEW.depot_id, NEW.fleet_operator_id, NEW.capabilities, NEW.token_hash,
      NEW.token_prefix, NEW.rate_limit_per_min, NEW.max_pending, NEW.note, NEW.created_at, NEW.created_by,
      NEW.origin, NEW.display_name, NEW.expires_at)
     IS DISTINCT FROM
     (OLD.principal_id, OLD.name, OLD.kind, OLD.depot_id, OLD.fleet_operator_id, OLD.capabilities, OLD.token_hash,
      OLD.token_prefix, OLD.rate_limit_per_min, OLD.max_pending, OLD.note, OLD.created_at, OLD.created_by,
      OLD.origin, OLD.display_name, OLD.expires_at) THEN
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

-- ══ 2. the passcode ═════════════════════════════════════════════════════════════════════════════════════════════════

CREATE TABLE public.ottoq_agent_demo_passcode (
  depot_id          uuid PRIMARY KEY REFERENCES public.depots(id),
  fleet_operator_id uuid NOT NULL REFERENCES public.fleet_operators(id),
  --: bcrypt (pgcrypto crypt with gen_salt('bf')). NULL = no passcode: the door is shut.
  passcode_hash     text,
  enabled           boolean NOT NULL DEFAULT false,
  session_minutes   integer NOT NULL DEFAULT 240,
  set_at            timestamptz NOT NULL DEFAULT now(),
  set_by            text NOT NULL DEFAULT session_user,
  CONSTRAINT ottoq_agent_demo_passcode_twin_check CHECK (depot_id = '11111111-1111-1111-1111-111111111111'::uuid),
  CONSTRAINT ottoq_agent_demo_passcode_minutes_check CHECK (session_minutes BETWEEN 15 AND 1440),
  CONSTRAINT ottoq_agent_demo_passcode_hash_check CHECK (passcode_hash IS NULL OR passcode_hash ~ '^\$2[abxy]?\$[0-9]{2}\$'),
  CONSTRAINT ottoq_agent_demo_passcode_on_check CHECK (NOT enabled OR passcode_hash IS NOT NULL)
);

COMMENT ON TABLE public.ottoq_agent_demo_passcode IS
'0607. OTTOYARD''s demo passcode for the twin depot (one row): the fleet it opens, a bcrypt hash (never the passcode), how long a session lasts, whether the door is on. Set it with SELECT public.ottoq_agent_set_passcode(''...''); NULL turns it off. Read only by ottoq_agent_public_call; no role reads it directly.';

INSERT INTO public.ottoq_agent_demo_passcode (depot_id, fleet_operator_id, passcode_hash, enabled)
VALUES ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', NULL, false);

-- Set, change or turn off the demo passcode. Never returns or stores the passcode itself.
CREATE OR REPLACE FUNCTION public.ottoq_agent_set_passcode(
    p_passcode          text,
    p_session_minutes   integer DEFAULT NULL,
    p_fleet_operator_id uuid    DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $fn$
DECLARE v_row public.ottoq_agent_demo_passcode; v_fleet text;
BEGIN
  IF p_passcode IS NOT NULL AND (length(p_passcode) NOT BETWEEN 6 AND 64 OR p_passcode ~ '[[:cntrl:]]') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_passcode',
      'message', 'A passcode is 6 to 64 characters, with no control characters.');
  END IF;
  IF p_session_minutes IS NOT NULL AND p_session_minutes NOT BETWEEN 15 AND 1440 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_minutes', 'message', 'A session lasts 15 to 1440 minutes.');
  END IF;
  IF p_fleet_operator_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.fleet_operators f WHERE f.id = p_fleet_operator_id AND f.is_active) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_fleet_operator', 'message', 'No active fleet operator with that id.');
  END IF;
  UPDATE public.ottoq_agent_demo_passcode d
     SET passcode_hash     = CASE WHEN p_passcode IS NULL THEN NULL ELSE extensions.crypt(p_passcode, extensions.gen_salt('bf', 10)) END,
         enabled           = p_passcode IS NOT NULL,
         session_minutes   = COALESCE(p_session_minutes, d.session_minutes),
         fleet_operator_id = COALESCE(p_fleet_operator_id, d.fleet_operator_id),
         set_at            = now(),
         set_by            = session_user
   WHERE d.depot_id = '11111111-1111-1111-1111-111111111111'
  RETURNING * INTO v_row;
  SELECT f.name INTO v_fleet FROM public.fleet_operators f WHERE f.id = v_row.fleet_operator_id;
  RETURN jsonb_build_object(
    'ok', true,
    'enabled', v_row.enabled,
    'fleet_operator', jsonb_build_object('id', v_row.fleet_operator_id, 'name', v_fleet),
    'session_minutes', v_row.session_minutes,
    'message', CASE WHEN v_row.enabled
      THEN format('The demo passcode is set. It opens %s''s cars at the twin depot for %s minutes a session, or until the demo run ends. Sessions already open stay open until then.', v_fleet, v_row.session_minutes)
      ELSE 'The demo passcode is off: no new session can be opened. Sessions already open end at their expiry or when the demo run ends.' END);
END $fn$;

-- ══ 3. the confirmation code, the welcome, and the plain-English refusals ═════════════════════════════════════════

-- "OQ-7F3A-91C2": derived from the command's uuid, so every surface shows the same code and nothing stores it.
CREATE OR REPLACE FUNCTION public.ottoq_owner_confirmation_code(p_command_id uuid)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT 'OQ-' || upper(substr(h, 1, 4)) || '-' || upper(substr(h, 5, 4))
    FROM (SELECT encode(sha256(uuid_send(p_command_id)), 'hex') AS h) x
$fn$;

-- One fleet in one line: its name, its cars at the depot, and those cars by model ("36 cars: 32 Model Y and 4 Cybercab").
CREATE OR REPLACE FUNCTION public.ottoq_agent_fleet_line(p_fleet_operator_id uuid, p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT jsonb_build_object(
    'id', p_fleet_operator_id,
    'name', (SELECT f.name FROM public.fleet_operators f WHERE f.id = p_fleet_operator_id),
    'cars', COALESCE(sum(m.n), 0),
    'cars_phrase', COALESCE(sum(m.n), 0) || CASE WHEN COALESCE(sum(m.n), 0) = 1 THEN ' car' ELSE ' cars' END,
    'models', regexp_replace(string_agg(m.n || ' ' || m.model, ', ' ORDER BY m.n DESC, m.model), ', ([^,]*)$', ' and \1'))
    FROM (SELECT COALESCE(NULLIF(btrim(v.model), ''), 'car') AS model, count(*) AS n
            FROM public.vehicles v
           WHERE v.fleet_operator_id = p_fleet_operator_id AND v.is_active
             AND (v.home_depot_id = p_depot_id OR v.current_depot_id = p_depot_id)
           GROUP BY 1) m
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_welcome_public(p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0607. What an agent without a key is told: what OTTOYARD is, what the demo passcode opens, whether a demo run is
   live, and the exact next call. Names no key, no principal and no passcode. */
DECLARE
  v_cfg   public.ottoq_agent_demo_passcode;
  v_depot text;
  v_fleet jsonb;
  v_run   jsonb;
  v_on    boolean;
  v_runl  text;
BEGIN
  SELECT * INTO v_cfg FROM public.ottoq_agent_demo_passcode d WHERE d.depot_id = p_depot_id;
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_depot_id;
  v_on := COALESCE(v_cfg.enabled, false) AND v_cfg.passcode_hash IS NOT NULL;
  IF v_cfg.fleet_operator_id IS NOT NULL THEN
    v_fleet := public.ottoq_agent_fleet_line(v_cfg.fleet_operator_id, p_depot_id);
  END IF;
  v_run := public.ottoq_agent_live_run(p_depot_id);
  v_runl := CASE
    WHEN v_run IS NULL THEN ' No demo run is live right now: you can connect and look, and changes take effect once a demo starts in OTTO-TWIN.'
    WHEN v_run ->> 'run_by' IS DISTINCT FROM 'operator_demo' THEN ' The run live now is not a demo, so changes wait for the next demo in OTTO-TWIN.'
    WHEN v_run ->> 'status' = 'paused' THEN format(' A demo run is live and paused (%s).', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true))
    ELSE format(' A demo run is live now (%s).', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)) END;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'connected', false,
    'summary', 'Welcome to OTTOYARD. You have reached OTTO-Q, the engine that orchestrates the '
      || COALESCE(v_depot, 'OTTOYARD') || ' depot (a live digital twin).'
      || CASE WHEN v_on AND v_fleet IS NOT NULL THEN
           format(' With OTTOYARD''s demo passcode you can see and adjust %s''s %s here (%s): how full they charge, which services they get, and when they may leave. Ask your person for the passcode, then call enter_passcode with it and your name.',
                  v_fleet ->> 'name', v_fleet ->> 'cars_phrase', v_fleet ->> 'models')
         ELSE ' The demo passcode is not switched on right now, so no fleet can be opened. Ask the person who gave you this address.' END
      || v_runl,
    'depot', jsonb_build_object('id', p_depot_id, 'name', v_depot),
    'fleet', CASE WHEN v_on THEN v_fleet END,
    'passcode', CASE WHEN v_on THEN 'required' ELSE 'off' END,
    'run', jsonb_build_object('live', v_run IS NOT NULL, 'demo', v_run ->> 'run_by' = 'operator_demo',
                              'status', v_run ->> 'status',
                              'sim_clock_local', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)),
    'next', CASE WHEN v_on THEN jsonb_build_object(
              'tool', 'enter_passcode',
              'arguments', jsonb_build_object('passcode', '<the passcode your person gives you>',
                                              'agent', '<your name, for example Hermes>'),
              'rest', 'POST /v1/passcode {"passcode": "...", "agent": "..."}') END,
    'you_can', jsonb_build_array(
      'See how each car is doing: its charge, where it is, and what it needs (my_fleet, my_vehicle)',
      'Set how full the cars charge, inside the owner''s contract (set_charge_limit, clear_charge_limit)',
      'Order services: exterior wash, interior clean, sensor clean, software update, a service-bay visit and more (request_service, cancel_service)',
      'Keep a car at the depot until a time (hold_vehicle, release_hold)',
      'Undo anything you set (undo_command)'),
    'rules', 'OTTO-Q checks every change against the owner''s contract and its own rules. A change that does not fit is refused in plain English, with the reason. One that fits is applied at OTTO-Q''s next tick and comes back with a confirmation code and an OrchestrAV link. Nothing you send moves a car: OTTO-Q decides when and where, and the car''s own driving system moves it. Everything set in a session lasts until the demo run ends.'));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_welcome_connected(p_agent public.ottoq_agent_principals)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0607. What a connected agent is told when it calls welcome (and, with its key added, what enter_passcode returns). */
DECLARE
  v_depot text;
  v_fleet jsonb;
  v_run   jsonb;
  v_who   text := COALESCE(p_agent.display_name, p_agent.name);
  v_until text := public.ottoq_owner_clock(p_agent.expires_at, false);
  v_runl  text;
  v_try   text;
BEGIN
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_agent.depot_id;
  IF p_agent.fleet_operator_id IS NOT NULL THEN
    v_fleet := public.ottoq_agent_fleet_line(p_agent.fleet_operator_id, p_agent.depot_id);
  END IF;
  v_run := public.ottoq_agent_live_run(p_agent.depot_id);
  v_runl := CASE
    WHEN v_run IS NULL THEN ' No demo run is live right now: changes take effect once a demo starts in OTTO-TWIN.'
    WHEN v_run ->> 'run_by' IS DISTINCT FROM 'operator_demo' THEN ' The run live now is not a demo, so changes wait for the next demo.'
    WHEN v_run ->> 'status' = 'paused' THEN format(' The demo run is paused (%s).', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true))
    ELSE format(' The demo run is live (%s).', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)) END;
  IF v_fleet IS NOT NULL AND 'owner_settings' = ANY (p_agent.capabilities) THEN
    v_try := 'Try: "how are my cars doing?", "charge every car to 90% instead of 100%", "wash every car each time it returns", or "keep one car here until 6 AM".';
  END IF;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'connected', true,
    'summary', format('You are connected to OTTOYARD as %s%s', v_who,
                      CASE WHEN p_agent.origin = 'passcode' THEN '' ELSE ' (an agent key)' END)
      || CASE WHEN v_fleet IS NOT NULL THEN format(', for %s''s %s at %s', v_fleet ->> 'name', v_fleet ->> 'cars_phrase', COALESCE(v_depot, 'the depot'))
              ELSE format(', at %s', COALESCE(v_depot, 'the depot')) END
      || CASE WHEN p_agent.origin = 'passcode' THEN format(', until %s or until the demo run ends, whichever comes first', v_until) ELSE '' END
      || '.' || v_runl || COALESCE(' ' || v_try, ''),
    'run_line', btrim(v_runl),
    'try_line', v_try,
    'agent', jsonb_build_object('name', v_who, 'via', CASE WHEN p_agent.origin = 'passcode' THEN 'passcode' ELSE 'key' END),
    'depot', jsonb_build_object('id', p_agent.depot_id, 'name', v_depot),
    'fleet', v_fleet,
    'session_expires_at', p_agent.expires_at,
    'session_expires_local', v_until,
    'run', jsonb_build_object('live', v_run IS NOT NULL, 'demo', v_run ->> 'run_by' = 'operator_demo',
                              'status', v_run ->> 'status',
                              'sim_clock_local', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)),
    'orchestrav', CASE WHEN p_agent.fleet_operator_id IS NOT NULL
                       THEN public.ottoq_owner_app_link((v_run ->> 'sim_run_id')::uuid, p_agent.fleet_operator_id, NULL) END,
    'rules', 'OTTO-Q checks every change against the owner''s contract and its own rules. A change that does not fit is refused in plain English, with the reason. One that fits is applied at OTTO-Q''s next tick and comes back with a confirmation code and an OrchestrAV link to relay to your person. Nothing you send moves a car. Everything set in a session lasts until the demo run ends.'));
END $fn$;

-- Why a call carried no usable key, in words an agent can act on.
CREATE OR REPLACE FUNCTION public.ottoq_agent_unauthenticated(p_token_hash text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT COALESCE(
    (SELECT CASE
       WHEN a.origin = 'passcode' AND a.status = 'revoked' AND a.revoked_reason LIKE 'run\_ended%' THEN jsonb_build_object(
         'code', 'session_ended',
         'message', 'This OTTOYARD session ended when the demo run ended: a stop or reset of the twin ends every passcode session and lifts everything set in it. Call enter_passcode again with the passcode to start a new session.')
       WHEN a.origin = 'passcode' AND a.status = 'revoked' THEN jsonb_build_object(
         'code', 'session_revoked',
         'message', 'The depot closed this OTTOYARD session. Call enter_passcode again with the passcode to start a new one.')
       WHEN a.origin = 'passcode' AND a.expires_at <= now() THEN jsonb_build_object(
         'code', 'session_expired',
         'message', format('This OTTOYARD session expired at %s. Call enter_passcode again with the passcode to start a new one.',
                           public.ottoq_owner_clock(a.expires_at, false)))
       END
       FROM public.ottoq_agent_principals a
      WHERE p_token_hash ~ '^[0-9a-f]{64}$' AND a.token_hash = p_token_hash),
    CASE WHEN COALESCE(p_token_hash, '') = '' THEN jsonb_build_object(
           'code', 'unauthenticated',
           'message', 'Connect first: call welcome, then enter_passcode with OTTOYARD''s demo passcode, and send the session key it gives you with each call (or send an agent key as Authorization: Bearer).')
         ELSE jsonb_build_object('code', 'unauthenticated', 'message', 'The token is unknown or has been revoked.') END)
$fn$;

-- ══ 4. the two public tools: welcome and enter_passcode ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_agent_public_call(
    p_tool      text,
    p_args      jsonb,
    p_transport text,
    p_meta      jsonb,
    p_t0        timestamptz)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $fn$
/* 0607. Reached only from ottoq_agent_call, for a caller without a usable key: welcome (anyone) and enter_passcode
   (the demo passcode -> a session principal). Every call is ledgered; a wrong passcode is always ledgered, because
   the throttle counts those rows. */
DECLARE
  c_twin    constant uuid := '11111111-1111-1111-1111-111111111111';
  c_window  constant interval := interval '15 minutes';
  c_per_ip  constant integer := 5;
  c_global  constant integer := 200;
  v_args    jsonb := COALESCE(p_args, '{}'::jsonb);
  v_meta    jsonb := COALESCE(p_meta, '{}'::jsonb);
  v_ip      text := COALESCE(NULLIF(COALESCE(p_meta, '{}'::jsonb) ->> 'ip', ''), 'unknown');
  v_cfg     public.ottoq_agent_demo_passcode;
  v_pass    text;
  v_display text;
  v_slug    text;
  v_fails   integer;
  v_global  integer;
  v_oldest  timestamptz;
  v_wait    integer;
  v_token   text;
  v_row     public.ottoq_agent_principals;
  v_data    jsonb;
  v_status  integer;
  v_code    text;
  v_msg     text;
  v_retry   integer;
  v_call    bigint;
  v_recent  integer;
  v_try     integer := 0;
BEGIN
  v_meta := v_meta - 'http_method' - 'path' - 'gateway_refusal';

  IF p_tool = 'welcome' THEN
    v_data := public.ottoq_agent_welcome_public(c_twin);
    SELECT count(*) INTO v_recent FROM public.ottoq_agent_call_ledger l
     WHERE l.principal_id IS NULL AND l.called_at > now() - interval '1 minute';
    IF v_recent < 60 THEN
      INSERT INTO public.ottoq_agent_call_ledger (principal_id, transport, tool, http_method, path, ok, http_status,
                                                 latency_ms, depot_id, detail)
      VALUES (NULL, p_transport, 'welcome', p_meta ->> 'http_method', left(p_meta ->> 'path', 200), true, 200,
              (extract(epoch FROM clock_timestamp() - p_t0) * 1000)::integer, c_twin, v_meta)
      RETURNING call_id INTO v_call;
    END IF;
    RETURN jsonb_build_object('ok', true, 'http_status', 200, 'tool', 'welcome', 'call_id', v_call, 'data', v_data);
  END IF;

  IF p_tool IS DISTINCT FROM 'enter_passcode' THEN
    RAISE EXCEPTION 'ottoq_agent_public_call: % is not a public tool', p_tool;
  END IF;

  -- ── enter_passcode: shape ──
  v_pass := CASE WHEN jsonb_typeof(v_args -> 'passcode') = 'string' THEN v_args ->> 'passcode' END;
  IF jsonb_typeof(v_args) <> 'object'
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(CASE WHEN jsonb_typeof(v_args) = 'object' THEN v_args ELSE '{}'::jsonb END) k
                 WHERE k NOT IN ('passcode', 'agent'))
     OR v_pass IS NULL OR length(v_pass) NOT BETWEEN 1 AND 200
     OR (v_args ? 'agent' AND (jsonb_typeof(v_args -> 'agent') <> 'string' OR length(v_args ->> 'agent') > 80))
     OR (COALESCE(p_meta, '{}'::jsonb) ->> 'gateway_refusal') = 'invalid_arguments' THEN
    v_status := 400; v_code := 'invalid_arguments';
    v_msg := 'enter_passcode takes {"passcode": "...", "agent": "your name"}: the passcode your person gave you, and a name for yourself (optional, at most 80 characters).';
  END IF;

  -- ── the throttle, from the ledger: per caller, and across every caller ──
  IF v_status IS NULL THEN
    SELECT count(*) FILTER (WHERE l.detail ->> 'ip' = v_ip), count(*), min(l.called_at) FILTER (WHERE l.detail ->> 'ip' = v_ip)
      INTO v_fails, v_global, v_oldest
      FROM public.ottoq_agent_call_ledger l
     WHERE l.tool = 'enter_passcode' AND l.error_code = 'wrong_passcode' AND l.called_at > now() - c_window;
    IF v_fails >= c_per_ip THEN
      v_wait := GREATEST(1, ceil(extract(epoch FROM (v_oldest + c_window - now())) / 60.0)::integer);
      v_status := 429; v_code := 'too_many_attempts'; v_retry := v_wait * 60;
      v_msg := format('Too many wrong passcodes from here. Nothing was opened; try again in %s minute%s.',
                      v_wait, CASE WHEN v_wait = 1 THEN '' ELSE 's' END);
    ELSIF v_global >= c_global THEN
      v_status := 429; v_code := 'door_resting'; v_retry := 300;
      v_msg := 'OTTOYARD has had too many wrong passcodes in the last 15 minutes, so the door is resting. Try again in a few minutes.';
    END IF;
  END IF;

  -- ── the door: on, and the passcode right ──
  IF v_status IS NULL THEN
    SELECT * INTO v_cfg FROM public.ottoq_agent_demo_passcode d WHERE d.depot_id = c_twin;
    IF NOT FOUND OR NOT v_cfg.enabled OR v_cfg.passcode_hash IS NULL THEN
      v_status := 503; v_code := 'passcode_off';
      v_msg := 'OTTOYARD''s demo passcode is not switched on right now, so no session can be opened. The depot switches it on.';
    ELSIF extensions.crypt(v_pass, v_cfg.passcode_hash) IS DISTINCT FROM v_cfg.passcode_hash THEN
      v_status := 403; v_code := 'wrong_passcode';
      v_msg := 'That passcode is not right, so nothing was opened. '
        || CASE WHEN c_per_ip - v_fails - 1 > 0
                THEN format('%s more %s in the next 15 minutes. ', c_per_ip - v_fails - 1,
                            CASE WHEN c_per_ip - v_fails - 1 = 1 THEN 'try' ELSE 'tries' END)
                ELSE 'That was the last try for 15 minutes. ' END
        || 'Ask the person who gave you OTTOYARD''s address for the current passcode.';
    END IF;
  END IF;

  IF v_status IS NOT NULL THEN
    --: a wrong passcode is ALWAYS ledgered (the throttle counts it); other refusals within the unauthenticated cap
    SELECT count(*) INTO v_recent FROM public.ottoq_agent_call_ledger l
     WHERE l.principal_id IS NULL AND l.called_at > now() - interval '1 minute';
    IF v_code = 'wrong_passcode' OR v_recent < 60 THEN
      INSERT INTO public.ottoq_agent_call_ledger (principal_id, transport, tool, http_method, path, ok, http_status,
                                                 error_code, latency_ms, depot_id, detail)
      VALUES (NULL, p_transport, 'enter_passcode', p_meta ->> 'http_method', left(p_meta ->> 'path', 200), false, v_status,
              v_code, (extract(epoch FROM clock_timestamp() - p_t0) * 1000)::integer, c_twin,
              v_meta || jsonb_build_object('ip', v_ip)
                     || CASE WHEN v_args ? 'agent' AND jsonb_typeof(v_args -> 'agent') = 'string'
                             THEN jsonb_build_object('agent', left(v_args ->> 'agent', 80)) ELSE '{}'::jsonb END)
      RETURNING call_id INTO v_call;
    END IF;
    RETURN jsonb_build_object('ok', false, 'http_status', v_status, 'tool', 'enter_passcode', 'call_id', v_call,
      'error', jsonb_strip_nulls(jsonb_build_object('code', v_code, 'message', v_msg, 'retry_after_s', v_retry)));
  END IF;

  -- ── the right passcode: a session principal, shown once ──
  v_display := left(btrim(regexp_replace(COALESCE(v_args ->> 'agent', ''), '[[:cntrl:]]+', ' ', 'g')), 60);
  IF v_display = '' THEN v_display := 'Agent'; END IF;
  v_slug := left(btrim(regexp_replace(lower(v_display), '[^a-z0-9]+', '-', 'g'), '-'), 40);
  v_slug := btrim(v_slug, '-');
  IF v_slug = '' THEN v_slug := 'agent'; END IF;
  LOOP
    v_try := v_try + 1;
    v_token := 'oqs_' || encode(extensions.gen_random_bytes(32), 'hex');
    BEGIN
      INSERT INTO public.ottoq_agent_principals
        (name, kind, depot_id, fleet_operator_id, capabilities, token_hash, token_prefix, rate_limit_per_min, max_pending,
         note, origin, display_name, expires_at)
      VALUES
        (v_slug || '.' || encode(extensions.gen_random_bytes(3), 'hex'), 'personal', c_twin, v_cfg.fleet_operator_id,
         ARRAY['note', 'owner_settings', 'read']::text[], encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
         left(v_token, 12), 30, 5, 'a passcode session', 'passcode', v_display,
         now() + make_interval(mins => v_cfg.session_minutes))
      RETURNING * INTO v_row;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_try >= 3 THEN RAISE; END IF;
    END;
  END LOOP;

  INSERT INTO public.ottoq_agent_call_ledger (principal_id, principal_name, transport, tool, http_method, path, ok,
                                             http_status, latency_ms, depot_id, fleet_operator_id, detail)
  VALUES (v_row.principal_id, v_row.name, p_transport, 'enter_passcode', p_meta ->> 'http_method', left(p_meta ->> 'path', 200),
          true, 201, (extract(epoch FROM clock_timestamp() - p_t0) * 1000)::integer, c_twin, v_row.fleet_operator_id,
          v_meta || jsonb_build_object('ip', v_ip, 'agent', v_display))
  RETURNING call_id INTO v_call;

  v_data := public.ottoq_agent_welcome_connected(v_row);
  v_data := v_data || jsonb_build_object(
    'summary', format('Welcome, %s. The passcode is right: you have %s until %s, or until the demo run ends, whichever comes first.',
                      v_display,
                      CASE WHEN v_data ? 'fleet'
                           THEN format('%s''s %s at %s', v_data #>> '{fleet,name}', v_data #>> '{fleet,cars_phrase}', v_data #>> '{depot,name}')
                           ELSE 'your fleet' END,
                      public.ottoq_owner_clock(v_row.expires_at, false))
      || COALESCE(' ' || (v_data ->> 'run_line'), '') || COALESCE(' ' || (v_data ->> 'try_line'), ''),
    'session', v_token,
    'session_use', 'Send this key as the "session" argument on every other OTTOYARD tool call (on the REST API, as Authorization: Bearer). It is a key: do not show it to your person or anyone else. It stops working when the demo run ends or at session_expires_local, and enter_passcode gives a new one.');
  RETURN jsonb_build_object('ok', true, 'http_status', 201, 'tool', 'enter_passcode', 'call_id', v_call,
    'principal', jsonb_build_object('name', v_row.name, 'kind', v_row.kind, 'capabilities', to_jsonb(v_row.capabilities)),
    'data', v_data);
END $fn$;

-- ══ 5. the run's end closes every passcode session at its depot ════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_tg_end_passcode_sessions_on_terminal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0607. A demo run's end ends every passcode session at its depot (the trigger's WHEN admits only operator_demo runs).
   A failure here never fails the run's end: it is a WARNING, and the sessions still lapse at expires_at. */
BEGIN
  BEGIN
    UPDATE public.ottoq_agent_principals a
       SET status = 'revoked', revoked_at = now(),
           revoked_reason = format('run_ended: demo run %s ended (%s); a passcode session ends with the run', NEW.sim_run_id, NEW.status)
     WHERE a.origin = 'passcode' AND a.status = 'active' AND a.depot_id = NEW.depot_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ending passcode sessions at the end of run % failed: % %', NEW.sim_run_id, SQLSTATE, SQLERRM;
  END;
  RETURN NULL;
END $fn$;

CREATE TRIGGER ottoq_sim_runs_end_passcode_sessions
  AFTER UPDATE OF status ON public.ottoq_sim_runs
  FOR EACH ROW
  WHEN ((old.status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text]))
        AND (new.status = ANY (ARRAY['completed'::text, 'failed'::text, 'aborted'::text]))
        AND new.run_by = 'operator_demo'::text)
  EXECUTE FUNCTION public.ottoq_tg_end_passcode_sessions_on_terminal();

-- ══ 6. 0559's resolver and 0605's three agent-door bodies, extended (each is the measured body plus the 0607 lines) ═

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
   WHERE a.token_hash = p_token_hash AND a.status = 'active'
     --: 0607: a passcode session also lapses at its expiry (and a demo run's end revokes it)
     AND (a.expires_at IS NULL OR a.expires_at > now());
  RETURN v;
END $fn$;

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
   can ASK, and a person decides through ottoq_agent_request_decide.
   0605: and an OWNER's agent can set what its own cars need (owner_settings): the owner tools write only
   ottoq_owner_commands and ottoq_owner_settings, and the engine applies the settings at its next tick. A refused owner
   command is not an exception: it is recorded as evidence and answered 422 with the recorded command. Transport 'ask'
   is the gateway's natural-language door (OTTO-Command speaking for the agent, with the agent's own token).
   0607: two PUBLIC tools need no key: welcome (anyone) and enter_passcode (OTTOYARD's demo passcode opens a session
   principal, ottoq_agent_public_call). A call with a missing, expired or ended session is told why in plain words. */
DECLARE
  t0          timestamptz := clock_timestamp();
  v_agent     public.ottoq_agent_principals;
  v_tool      text := left(lower(btrim(COALESCE(p_tool, ''))), 64);
  v_transport text := CASE WHEN p_transport IN ('rest', 'mcp', 'ask') THEN p_transport ELSE 'other' END;
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
  v_owner_cmd boolean;
  v_unauth    jsonb;
BEGIN
  --: only small, known keys from the caller reach the ledger
  v_meta := jsonb_strip_nulls(jsonb_build_object(
    'http_method',  left(COALESCE(p_meta, '{}'::jsonb) ->> 'http_method', 8),
    'path',         left(COALESCE(p_meta, '{}'::jsonb) ->> 'path', 200),
    'mcp_method',   left(COALESCE(p_meta, '{}'::jsonb) ->> 'mcp_method', 64),
    'mcp_version',  left(COALESCE(p_meta, '{}'::jsonb) ->> 'mcp_version', 16),
    'client',       left(COALESCE(p_meta, '{}'::jsonb) ->> 'client', 120),
    'ip',           left(COALESCE(p_meta, '{}'::jsonb) ->> 'ip', 64)));

  --: 0607: the two public tools. welcome answers anyone (a connected caller's welcome falls through to its own
  --: principal, rate limit and ledger); enter_passcode turns OTTOYARD's demo passcode into a session principal.
  IF v_tool IN ('welcome', 'enter_passcode') THEN
    v_agent := public.ottoq_agent_resolve(p_token_hash);
    IF v_tool = 'enter_passcode' OR v_agent.principal_id IS NULL THEN
      RETURN public.ottoq_agent_public_call(v_tool, v_args, v_transport,
        v_meta || jsonb_strip_nulls(jsonb_build_object('gateway_refusal', COALESCE(p_meta, '{}'::jsonb) ->> 'gateway_refusal')), t0);
    END IF;
  END IF;

  v_agent := public.ottoq_agent_resolve(p_token_hash);
  IF v_agent.principal_id IS NULL THEN
    v_unauth := public.ottoq_agent_unauthenticated(p_token_hash);
    --: an unknown or revoked token reaches no tool. Ledgered, but at most 60 a minute, so a caller without a token
    --: cannot grow the ledger without bound.
    SELECT count(*) INTO v_recent FROM public.ottoq_agent_call_ledger l
     WHERE l.principal_id IS NULL AND l.called_at > now() - interval '1 minute';
    IF v_recent < 60 THEN
      INSERT INTO public.ottoq_agent_call_ledger (principal_id, transport, tool, http_method, path, ok, http_status,
                                                 error_code, latency_ms, detail)
      VALUES (NULL, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path', false, 401, v_unauth ->> 'code',
              (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer, v_meta - 'http_method' - 'path')
      RETURNING call_id INTO v_call;
    END IF;
    RETURN jsonb_build_object('ok', false, 'http_status', 401, 'tool', v_tool, 'call_id', v_call, 'error', v_unauth);
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
    WHEN 'welcome'            THEN ''
    WHEN 'list_requests'      THEN ''
    WHEN 'depot_status'       THEN 'read'
    WHEN 'fleet_summary'      THEN 'read'
    WHEN 'vehicle_card'       THEN 'read'
    WHEN 'recent_decisions'   THEN 'read'
    WHEN 'stall_availability' THEN 'read'
    WHEN 'send_note'          THEN 'note'
    WHEN 'submit_request'     THEN 'per_kind'
    -- 0605: the owner's reads and commands
    WHEN 'my_fleet'           THEN 'read'
    WHEN 'my_vehicle'         THEN 'read'
    WHEN 'my_settings'        THEN 'read'
    WHEN 'my_commands'        THEN ''
    WHEN 'set_charge_limit'   THEN 'owner_settings'
    WHEN 'clear_charge_limit' THEN 'owner_settings'
    WHEN 'request_service'    THEN 'owner_settings'
    WHEN 'cancel_service'     THEN 'owner_settings'
    WHEN 'hold_vehicle'       THEN 'owner_settings'
    WHEN 'release_hold'       THEN 'owner_settings'
    WHEN 'undo_command'       THEN 'owner_settings'
    ELSE NULL END;
  v_owner_cmd := v_tool IN ('set_charge_limit', 'clear_charge_limit', 'request_service', 'cancel_service', 'hold_vehicle',
                            'release_hold', 'undo_command');

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
      WHEN 'welcome'            THEN public.ottoq_agent_welcome_connected(v_agent)
      WHEN 'depot_status'       THEN public.ottoq_agent_read_depot(v_agent)
      WHEN 'fleet_summary'      THEN public.ottoq_agent_read_fleet(v_agent, v_args)
      WHEN 'vehicle_card'       THEN public.ottoq_agent_read_vehicle(v_agent, v_args)
      WHEN 'recent_decisions'   THEN public.ottoq_agent_read_decisions(v_agent, v_args)
      WHEN 'stall_availability' THEN public.ottoq_agent_read_stalls(v_agent, v_args)
      WHEN 'list_requests'      THEN public.ottoq_agent_read_requests(v_agent, v_args)
      WHEN 'send_note'          THEN public.ottoq_agent_submit_request(v_agent, 'note', v_args)
      WHEN 'submit_request'     THEN public.ottoq_agent_submit_request(v_agent, COALESCE(v_args ->> 'kind', ''), v_args)
      WHEN 'my_fleet'           THEN public.ottoq_owner_read(v_agent, 'my_fleet', v_args)
      WHEN 'my_vehicle'         THEN public.ottoq_owner_read(v_agent, 'my_vehicle', v_args)
      WHEN 'my_settings'        THEN public.ottoq_owner_read(v_agent, 'my_settings', v_args)
      WHEN 'my_commands'        THEN public.ottoq_owner_read(v_agent, 'my_commands', v_args)
      ELSE public.ottoq_owner_command(v_agent, v_tool, v_args)
    END;
    IF v_tool IN ('send_note', 'submit_request') THEN
      v_status := CASE WHEN COALESCE((v_data ->> 'duplicate')::boolean, false) THEN 200 ELSE 201 END;
      v_request := (v_data #>> '{request,request_id}')::uuid;
    END IF;
    IF v_owner_cmd THEN
      v_status := CASE WHEN v_data ->> 'outcome' = 'refused' THEN 422
                       WHEN v_data ->> 'outcome' = 'applied' AND NOT COALESCE((v_data ->> 'duplicate')::boolean, false) THEN 201
                       ELSE 200 END;
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
                                             http_status, error_code, latency_ms, request_id, depot_id, fleet_operator_id, detail)
  VALUES (v_agent.principal_id, v_agent.name, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path',
          v_status < 400, v_status, CASE WHEN v_status >= 400 THEN v_data #>> '{refusal,code}' END,
          (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer, v_request,
          v_agent.depot_id, v_agent.fleet_operator_id,
          (v_meta - 'http_method' - 'path')
          || CASE WHEN v_owner_cmd THEN jsonb_strip_nulls(jsonb_build_object('command_id', v_data #>> '{command,command_id}',
                                                                             'outcome', v_data ->> 'outcome'))
                  ELSE '{}'::jsonb END)
  RETURNING call_id INTO v_call;
  --: 0605: a refused owner command was recorded, not raised: it answers 422 WITH the recorded command
  IF v_status >= 400 THEN
    RETURN jsonb_build_object('ok', false, 'http_status', v_status, 'tool', v_tool, 'call_id', v_call,
      'principal', jsonb_build_object('name', v_agent.name, 'kind', v_agent.kind,
                                      'capabilities', to_jsonb(v_agent.capabilities)),
      'error', jsonb_strip_nulls(jsonb_build_object('code', v_data #>> '{refusal,code}',
                                                    'message', v_data #>> '{refusal,message}',
                                                    'hint', v_data #>> '{refusal,hint}')),
      'data', v_data);
  END IF;
  RETURN jsonb_build_object('ok', true, 'http_status', v_status, 'tool', v_tool, 'call_id', v_call,
    'principal', jsonb_build_object('name', v_agent.name, 'kind', v_agent.kind,
                                    'capabilities', to_jsonb(v_agent.capabilities)),
    'data', v_data);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_whoami(p_agent public.ottoq_agent_principals)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_depot text; v_fleet text; v_owner jsonb; v_run jsonb; v_contract jsonb;
BEGIN
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_agent.depot_id;
  IF p_agent.fleet_operator_id IS NOT NULL THEN
    SELECT f.name INTO v_fleet FROM public.fleet_operators f WHERE f.id = p_agent.fleet_operator_id;
  END IF;
  --: 0605: what an owner's agent may set, and inside what range
  IF 'owner_settings' = ANY (p_agent.capabilities) AND p_agent.fleet_operator_id IS NOT NULL THEN
    v_run := public.ottoq_agent_live_run(p_agent.depot_id);
    v_contract := public.ottoq_owner_contract(p_agent.fleet_operator_id, COALESCE((v_run ->> 'sim_clock')::timestamptz, now()));
    v_owner := jsonb_build_object(
      'cars', (SELECT count(*) FROM public.ottoq_owner_fleet(p_agent)),
      'live_demo_run', CASE WHEN v_run ->> 'run_by' = 'operator_demo' THEN v_run -> 'sim_run_id' END,
      'charge_limit_pct', jsonb_build_object('min', v_contract -> 'min_charge_pct', 'max', v_contract -> 'max_charge_pct'),
      'requestable_services', (SELECT jsonb_agg(jsonb_build_object('service', c.svc, 'name', c.display_name,
                                                                    'minutes', c.est_min_default,
                                                                    'where', public.ottoq_owner_service_where(c.svc))
                                                ORDER BY c.display_name)
                                 FROM public.service_cadence_policy c
                                WHERE c.svc = ANY (public.ottoq_owner_requestable_services()) AND c.is_active
                                  AND NOT COALESCE((v_contract -> 'blocked_services') ? c.svc, false)),
      'hold_max_hours', 24,
      'commands', jsonb_build_array('set_charge_limit', 'clear_charge_limit', 'request_service', 'cancel_service',
                                    'hold_vehicle', 'release_hold', 'undo_command'),
      'rules', 'Your settings change what your cars need, never how they move: OTTO-Q decides when and where, the AV stack moves the car. Each setting is checked against your contract, applied at OTTO-Q''s next tick, undoable, and lifted when the demo run ends.',
      'orchestrav', public.ottoq_owner_app_link((v_run ->> 'sim_run_id')::uuid, p_agent.fleet_operator_id, NULL));
  END IF;
  RETURN jsonb_build_object(
    'principal', jsonb_build_object('name', p_agent.name, 'kind', p_agent.kind, 'token_prefix', p_agent.token_prefix,
                                    'created_at', p_agent.created_at, 'last_used_at', p_agent.last_used_at,
                                    'note', p_agent.note)
                 --: 0607: how this caller got in, and (a passcode session) until when
                 || jsonb_strip_nulls(jsonb_build_object(
                      'via', CASE WHEN p_agent.origin = 'passcode' THEN 'passcode' ELSE 'key' END,
                      'display_name', p_agent.display_name,
                      'expires_at', p_agent.expires_at,
                      'expires_local', public.ottoq_owner_clock(p_agent.expires_at, false),
                      'ends', CASE WHEN p_agent.origin = 'passcode'
                                   THEN 'at expires_local, or when the demo run ends, whichever comes first' END)),
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
      CASE WHEN v_owner IS NOT NULL THEN
        'Settings for your own cars (charge limit, services, holds) are yours to set: OTTO-Q checks each against your '
        || 'contract and its own rules, applies it at its next tick, and answers with a receipt and an OrchestrAV link. '
        || 'Anything else is a request a person approves or declines in OTTO-PULSE.'
      ELSE
      'Every change you ask for is a request. A person approves or declines it: the depot crew in OTTO-PULSE, or the '
      || 'fleet''s own operator once signed in. An approved request goes to one of OTTO-Q''s own doors, which may still '
      || 'refuse it; list_requests shows the decision and the engine''s exact reply. Nothing happens on your say-so alone.'
      END,
    'owner', v_owner);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_command_reply(p_c public.ottoq_owner_commands, p_duplicate boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'outcome', p_c.outcome,
    'duplicate', p_duplicate,
    --: 0607: an applied command's receipt carries its confirmation code, on the line above the OrchestrAV link
    'summary', CASE WHEN p_c.outcome = 'applied' AND p_c.link IS NOT NULL
                    THEN replace(p_c.summary, E'\nSee it in OrchestrAV: ',
                                 E'\nConfirmation code: ' || public.ottoq_owner_confirmation_code(p_c.command_id)
                                 || E'.\nSee it in OrchestrAV: ')
                    ELSE p_c.summary END,
    'confirmation_code', CASE WHEN p_c.outcome = 'applied' THEN public.ottoq_owner_confirmation_code(p_c.command_id) END,
    'link', p_c.link,
    'refusal', p_c.refusal,
    'command', jsonb_build_object(
      'command_id', p_c.command_id, 'tool', p_c.tool, 'mode', p_c.mode, 'outcome', p_c.outcome,
      'cars', jsonb_array_length(p_c.vehicles), 'vehicles', p_c.vehicles, 'effects', p_c.effects,
      'args', p_c.args, 'plan_hash', p_c.plan_hash, 'sim_run_id', p_c.sim_run_id,
      'sim_clock', p_c.sim_clock, 'sim_clock_local', public.ottoq_owner_clock(p_c.sim_clock, true),
      'created_at', p_c.created_at, 'created_at_local', public.ottoq_owner_clock(p_c.created_at, false),
      'undone_at', p_c.undone_at, 'undone_by_command_id', p_c.undone_by_command_id,
      'lifted_at', p_c.lifted_at, 'lifted_reason', p_c.lifted_reason),
    'confirm', CASE WHEN p_c.outcome = 'previewed' THEN jsonb_build_object(
                 'tool', p_c.tool,
                 -- what the preview showed, exactly: a hold goes back as the absolute time it resolved to, so a
                 -- confirm sent after the sim clock moved holds until the time shown, not "90 minutes from now"
                 'args', (p_c.args - 'mode' - 'expect_plan_hash' - 'idempotency_key' - 'until_sim'
                          - CASE WHEN p_c.args ? 'until_sim' THEN ARRAY['until', 'for_minutes'] ELSE ARRAY[]::text[] END)
                         || CASE WHEN p_c.args ? 'until_sim' THEN jsonb_build_object('until', p_c.args ->> 'until_sim')
                                 ELSE '{}'::jsonb END
                         || jsonb_build_object('mode', 'apply', 'expect_plan_hash', p_c.plan_hash),
                 'note', 'Send this to apply exactly the plan shown. If the cars or settings change first, OTTO-Q refuses with the new plan.') END,
    'undo', CASE WHEN p_c.outcome = 'applied' AND p_c.undone_at IS NULL AND p_c.lifted_at IS NULL AND p_c.tool <> 'undo_command'
                 THEN jsonb_build_object('tool', 'undo_command', 'args', jsonb_build_object('command_id', p_c.command_id)) END,
    'expires', CASE WHEN p_c.outcome = 'applied' AND p_c.tool <> 'undo_command'
                    THEN 'Lasts until this demo run ends or you undo it; a stop or reset of the twin puts every car back to baseline.' END))
$fn$;

-- ══ 7. privileges: revoke everything new, grant exactly ═══════════════════════════════════════════════════════════

ALTER TABLE public.ottoq_agent_demo_passcode ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_agent_demo_passcode FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.ottoq_agent_set_passcode(text, integer, uuid),
  public.ottoq_owner_confirmation_code(uuid),
  public.ottoq_agent_fleet_line(uuid, uuid),
  public.ottoq_agent_welcome_public(uuid),
  public.ottoq_agent_welcome_connected(public.ottoq_agent_principals),
  public.ottoq_agent_unauthenticated(text),
  public.ottoq_agent_public_call(text, jsonb, text, jsonb, timestamptz),
  public.ottoq_tg_end_passcode_sessions_on_terminal()
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.ottoq_agent_set_passcode(text, integer, uuid) TO service_role;

COMMENT ON FUNCTION public.ottoq_agent_set_passcode(text, integer, uuid) IS
'0607. Set, change or (NULL) turn off OTTOYARD''s demo passcode: bcrypt-hashed, never stored or returned. Optional: minutes a session lasts (15-1440, default 240) and the fleet it opens (default Tesla Robotaxi TN). service_role and the SQL editor only.';
COMMENT ON FUNCTION public.ottoq_agent_public_call(text, jsonb, text, jsonb, timestamptz) IS
'0607. The two tools a caller without a key may use, reached only from ottoq_agent_call: welcome, and enter_passcode (the demo passcode, throttled per caller and overall from the ledger, opens a session principal of origin passcode; its key is shown once).';
COMMENT ON FUNCTION public.ottoq_owner_confirmation_code(uuid) IS
'0607. A command''s confirmation code, "OQ-XXXX-XXXX": the first 8 hex digits of sha256(uuid_send(command_id)). Derived, never stored, the same on every surface.';
COMMENT ON FUNCTION public.ottoq_tg_end_passcode_sessions_on_terminal() IS
'0607. On a demo run''s end (the trigger admits only run_by = operator_demo), revokes every active passcode session at its depot with revoked_reason run_ended. Writes ottoq_agent_principals only.';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════

-- V1: the trigger fires only on a demo run's end, and its function writes nothing but the principals
DO $v1$
DECLARE v_def text; v_src text;
BEGIN
  SELECT pg_get_triggerdef(t.oid) INTO v_def FROM pg_trigger t
   WHERE t.tgrelid = 'public.ottoq_sim_runs'::regclass AND t.tgname = 'ottoq_sim_runs_end_passcode_sessions';
  IF v_def IS NULL OR v_def NOT LIKE '%(new.run_by = ''operator_demo''::text)%'
     OR v_def NOT LIKE '%(new.status = ANY (ARRAY[''completed''::text, ''failed''::text, ''aborted''::text]))%' THEN
    RAISE EXCEPTION '0607 V1: the session trigger does not fire only on a demo run''s end: %', v_def;
  END IF;
  v_src := regexp_replace(regexp_replace(
             (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_tg_end_passcode_sessions_on_terminal()'::regprocedure),
             '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src, '(INSERT[[:space:]]+INTO|UPDATE|DELETE[[:space:]]+FROM|TRUNCATE)[[:space:]]+([a-z_."]+)', 'gi')) <> 1
     OR v_src !~* 'UPDATE[[:space:]]+public\.ottoq_agent_principals[[:space:]]' THEN
    RAISE EXCEPTION '0607 V1: the session trigger writes something other than ottoq_agent_principals';
  END IF;
END $v1$;

-- V2: no client role reaches anything new, and the passcode table is read by no role
DO $v2$
DECLARE v_fn regprocedure; v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOR v_fn IN SELECT unnest(ARRAY[
        'public.ottoq_agent_set_passcode(text,integer,uuid)'::regprocedure,
        'public.ottoq_owner_confirmation_code(uuid)'::regprocedure,
        'public.ottoq_agent_fleet_line(uuid,uuid)'::regprocedure,
        'public.ottoq_agent_welcome_public(uuid)'::regprocedure,
        'public.ottoq_agent_welcome_connected(public.ottoq_agent_principals)'::regprocedure,
        'public.ottoq_agent_unauthenticated(text)'::regprocedure,
        'public.ottoq_agent_public_call(text,jsonb,text,jsonb,timestamptz)'::regprocedure,
        'public.ottoq_tg_end_passcode_sessions_on_terminal()'::regprocedure,
        'public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure]) LOOP
      IF has_function_privilege(v_role, v_fn, 'EXECUTE') THEN
        RAISE EXCEPTION '0607 V2: % can execute %', v_role, v_fn;
      END IF;
    END LOOP;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_table_privilege(v_role, 'public.ottoq_agent_demo_passcode', 'SELECT')
       OR has_table_privilege(v_role, 'public.ottoq_agent_demo_passcode', 'UPDATE') THEN
      RAISE EXCEPTION '0607 V2: % can touch the passcode table directly', v_role;
    END IF;
  END LOOP;
  IF NOT has_function_privilege('service_role', 'public.ottoq_agent_set_passcode(text,integer,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_agent_call(text,text,jsonb,text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '0607 V2: service_role lost a grant it needs';
  END IF;
  IF (SELECT enabled OR passcode_hash IS NOT NULL FROM public.ottoq_agent_demo_passcode) THEN
    RAISE EXCEPTION '0607 V2: the passcode must ship OFF, with no passcode';
  END IF;
END $v2$;

-- V3: the door end to end, on this catalog, inside a block that rolls itself back
DO $probe$
DECLARE
  v        jsonb;
  v_key    text;
  v_hash   text;
  v_sess   public.ottoq_agent_principals;
  v_issued jsonb;
  v_ihash  text;
  v_code   text;
BEGIN
  BEGIN
    v := public.ottoq_agent_call(NULL, 'welcome', '{}'::jsonb, 'rest', '{"ip": "probe-0607"}'::jsonb);
    IF NOT (v ->> 'ok')::boolean OR v #>> '{data,passcode}' IS DISTINCT FROM 'off'
       OR (v #>> '{data,connected}')::boolean OR v #>> '{data,summary}' NOT LIKE 'Welcome to OTTOYARD.%' THEN
      RAISE EXCEPTION '0607 V3a: an unconnected welcome is wrong: %', v;
    END IF;
    v := public.ottoq_agent_call(NULL, 'enter_passcode', '{"passcode": "probe-0607-passcode", "agent": "Probe"}'::jsonb, 'rest', '{"ip": "probe-0607"}'::jsonb);
    IF (v ->> 'http_status')::int <> 503 OR v #>> '{error,code}' IS DISTINCT FROM 'passcode_off' THEN
      RAISE EXCEPTION '0607 V3b: the door opened while off: %', v;
    END IF;
    IF NOT (public.ottoq_agent_set_passcode('probe-0607-passcode') ->> 'ok')::boolean THEN
      RAISE EXCEPTION '0607 V3c: the passcode could not be set';
    END IF;
    IF (SELECT passcode_hash LIKE '%probe-0607%' OR passcode_hash !~ '^\$2' FROM public.ottoq_agent_demo_passcode) THEN
      RAISE EXCEPTION '0607 V3c: the passcode is not stored as a bcrypt hash';
    END IF;
    v := public.ottoq_agent_call(NULL, 'enter_passcode', '{"passcode": "not-the-passcode", "agent": "Probe"}'::jsonb, 'rest', '{"ip": "probe-0607"}'::jsonb);
    IF (v ->> 'http_status')::int <> 403 OR v #>> '{error,code}' IS DISTINCT FROM 'wrong_passcode'
       OR v #>> '{error,message}' NOT LIKE 'That passcode is not right%' THEN
      RAISE EXCEPTION '0607 V3d: a wrong passcode was not refused in plain English: %', v;
    END IF;
    v := public.ottoq_agent_call(NULL, 'enter_passcode', '{"passcode": "probe-0607-passcode", "agent": "Probe Agent"}'::jsonb, 'mcp', '{"ip": "probe-0607"}'::jsonb);
    v_key := v #>> '{data,session}';
    IF (v ->> 'http_status')::int <> 201 OR v_key !~ '^oqs_[0-9a-f]{64}$' OR v #>> '{data,summary}' NOT LIKE 'Welcome, Probe Agent. The passcode is right%' THEN
      RAISE EXCEPTION '0607 V3e: the right passcode did not open a session: %', v;
    END IF;
    v_hash := encode(sha256(convert_to(v_key, 'UTF8')), 'hex');
    SELECT * INTO v_sess FROM public.ottoq_agent_principals a WHERE a.token_hash = v_hash;
    IF v_sess.origin <> 'passcode' OR v_sess.display_name <> 'Probe Agent' OR v_sess.name !~ '^probe-agent\.[0-9a-f]{6}$'
       OR v_sess.capabilities <> ARRAY['note', 'owner_settings', 'read']::text[]
       OR v_sess.fleet_operator_id <> '33333333-3333-3333-3333-333333333333'
       OR v_sess.expires_at NOT BETWEEN now() + interval '239 minutes' AND now() + interval '241 minutes' THEN
      RAISE EXCEPTION '0607 V3f: the session principal is not what the passcode promises: %', row_to_json(v_sess);
    END IF;
    v := public.ottoq_agent_call(v_hash, 'whoami', '{}'::jsonb, 'mcp', '{}'::jsonb);
    IF NOT (v ->> 'ok')::boolean OR v #>> '{data,principal,via}' IS DISTINCT FROM 'passcode' THEN
      RAISE EXCEPTION '0607 V3g: the session key does not work: %', v;
    END IF;
    v := public.ottoq_agent_call(v_hash, 'welcome', '{}'::jsonb, 'mcp', '{}'::jsonb);
    IF NOT (v ->> 'ok')::boolean OR NOT (v #>> '{data,connected}')::boolean
       OR v #>> '{data,summary}' NOT LIKE 'You are connected to OTTOYARD as Probe Agent, for %' THEN
      RAISE EXCEPTION '0607 V3h: a connected welcome is wrong: %', v;
    END IF;
    v := public.ottoq_agent_call(v_hash, 'my_fleet', '{}'::jsonb, 'mcp', '{}'::jsonb);
    IF NOT (v ->> 'ok')::boolean THEN
      RAISE EXCEPTION '0607 V3i: a session cannot read its fleet: %', v;
    END IF;
    v := public.ottoq_agent_call(NULL, 'my_fleet', '{}'::jsonb, 'rest', '{}'::jsonb);
    IF (v ->> 'http_status')::int <> 401 OR v #>> '{error,message}' NOT LIKE 'Connect first:%' THEN
      RAISE EXCEPTION '0607 V3j: a call with no key is not told how to connect: %', v;
    END IF;
    -- an issued key is unchanged beside it
    v_issued := public.ottoq_agent_issue_token('probe-0607-key', 'personal', ARRAY['read', 'note', 'owner_settings'],
                  '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', NULL, 60, 20);
    v_ihash := encode(sha256(convert_to(v_issued ->> 'token', 'UTF8')), 'hex');
    v := public.ottoq_agent_call(v_ihash, 'whoami', '{}'::jsonb, 'rest', '{}'::jsonb);
    IF NOT (v ->> 'ok')::boolean OR v #>> '{data,principal,via}' IS DISTINCT FROM 'key'
       OR (SELECT origin FROM public.ottoq_agent_principals WHERE name = 'probe-0607-key') <> 'issued' THEN
      RAISE EXCEPTION '0607 V4: an issued key changed: %', v;
    END IF;
    v_code := public.ottoq_owner_confirmation_code('00000000-0000-0000-0000-000000000000');
    IF v_code !~ '^OQ-[0-9A-F]{4}-[0-9A-F]{4}$' OR v_code <> public.ottoq_owner_confirmation_code('00000000-0000-0000-0000-000000000000') THEN
      RAISE EXCEPTION '0607 V5: the confirmation code is not a stable OQ-XXXX-XXXX: %', v_code;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OQA99', MESSAGE = '0607_v3_rollback';
  EXCEPTION WHEN SQLSTATE 'OQA99' THEN
    NULL;  -- everything above is undone; each step proved what it set out to
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_agent_principals WHERE name LIKE 'probe-0607%' OR name LIKE 'probe-agent.%')
     OR (SELECT enabled OR passcode_hash IS NOT NULL FROM public.ottoq_agent_demo_passcode) THEN
    RAISE EXCEPTION '0607 V3: the probe survived its own rollback';
  END IF;
END $probe$;

-- Rollback: DROP TRIGGER ottoq_sim_runs_end_passcode_sessions ON ottoq_sim_runs; re-create ottoq_agent_call,
-- ottoq_agent_resolve, ottoq_agent_principals_guard, ottoq_agent_read_whoami and ottoq_owner_command_reply from their
-- '0607_pre' snapshots; DROP the eight functions this file created and TABLE ottoq_agent_demo_passcode; revoke every
-- principal of origin 'passcode' (UPDATE ... SET status = 'revoked', revoked_at = now(), revoked_reason = 'rollback 0607'),
-- then, with ottoq.agent_ledger_unlock = on, DROP the three constraints and the index this file added, restore 0559's
-- token_prefix CHECK ('^oqa_[0-9a-f]{8}$', which then requires the passcode rows gone or re-keyed) and DROP COLUMN
-- origin, display_name, expires_at; DELETE this file's ottoq_cert_lineage row.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends', false, false,
  'Agent door only (Chase 2026-10-03): welcome and enter_passcode inside ottoq_agent_call; a passcode session is an ottoq_agent_principals row (origin passcode, oqs_ key, expires_at, capabilities pinned to an owner key''s); a confirmation code on every applied owner command; plain-English refusals for missing, expired and ended sessions. The one engine-table change is AFTER UPDATE OF status ON ottoq_sim_runs, WHEN run_by = operator_demo (no arm has that run_by), writing ottoq_agent_principals only (V1). No tick-path body changes.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
