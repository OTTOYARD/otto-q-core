-- migration-version: PENDING
-- migration-name:    an_owner_signs_in_and_connects_their_own_agent
--
-- 0660  **An owner signs in, and connects their own agent.** An OTTOYARD account (a Supabase Auth user of this
--       project) is linked to the fleet it owns. An agent that wants that fleet is sent to OTTOYARD's sign-in page; the
--       owner signs in there, sees which agent is asking and what it could do, and approves or denies. Approved, the
--       agent gets its own short-lived access token and a refresh token, through the standard (OAuth 2.1: the device
--       code grant for an agent with no screen, the authorization code with PKCE for one that opens a browser), and
--       reaches exactly what an owner key reaches: that fleet's cars, read + note + owner_settings. No password, passcode
--       or key ever passes through the agent's chat. The connection outlasts runs and ends when the owner disconnects it.
--
--       Chase, 2026-10-10, 12:00-12:45 AM CT: "I just want one unified login no matter what. Even if for now it asks
--       for login or account information and we just use basic placeholders that can be replaced by actual account
--       logins later in production." Then: "let's just set it up for only me and my [Hermes] agent currently. And then
--       down the road we can open access to all users ... it has to function super well and very close to how actual
--       production will eventually work." His Hermes runs in the cloud and he talks to it through Telegram; only his
--       Teslas and Cybercabs for now; no Google sign-in; a placeholder password for his account until real logins.
--
-- ══ §1 WHAT WAS MISSING (read from the files and the live catalog, 2026-10-10 05:00-06:40 UTC, read-only) ═══════════
--
--   (a) An agent reached an owner's fleet two ways, and neither is a login. An issued key (0559) is pasted into the
--       agent's configuration by whoever runs the SQL; the demo passcode (0607) is typed into the agent's chat and opens
--       a shared session that ends with the run. Neither names a person, and the passcode travels through the model's
--       context. PERSONAL_AGENT.md §6 and §8 already named the next step: OAuth 2.1 with a "Connect OTTOYARD" page.
--   (b) OTTOYARD has two account systems already and the agent door uses neither: OrchestrAV signs owners in to the
--       MVP project (ycsis..., switched off for the open demo since 2026-10-02), OTTO-PULSE signs its crew in to this
--       project. 6 auth.users rows here, none for chase@ottoyard.com, none @ottoyard.com (measured). This file makes
--       this project's Auth the account an agent signs in through; OrchestrAV's own login moving here is a later step.
--   (c) The standard was read, not assumed (sources at §7). MCP's authorization (2026-07-28) is OAuth 2.1 with
--       protected-resource metadata; Hermes Agent's MCP client (NousResearch/hermes-agent at dce1e9b3, read
--       2026-10-10, tools/mcp_oauth_device.py) runs RFC 8628's device code grant with `hermes mcp login <server>
--       --flow device`: it GETs the MCP address and reads resource_metadata from a 401, reads the authorization server's
--       metadata, registers itself (RFC 7591), polls the token endpoint, and stores the tokens. Its discovery treats any
--       answer but 404 as fatal, and every path-scoped well-known address on supabase.co answers 401 ("No API key found",
--       measured), so the authorization server's metadata is published at www.ottoyard.com (Vercel, the OTTOYARD-SITE
--       repository) and its endpoints stay in the gateway. The sign-in page lives there too: Supabase Edge Functions
--       answer a GET's text/html as text/plain.
--   (d) 0607's three CHECKs on ottoq_agent_principals admit two origins. A third needs them dropped and re-added; no
--       function is dropped. Six bodies are extended (each the measured live body plus the 0660 lines, md5 pinned in
--       P1): the resolver learns access tokens; the plain-English 401 learns why a token stopped; the welcome, whoami
--       and the two owner boards say "signed in" and whose account.
--
-- ══ §2 WHAT THIS BUILDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   SIX TABLES, reachable only through the functions below (RLS on, no policy, no client privilege):
--     ottoq_owner_accounts       an auth.users id and email linked to ONE fleet at the twin depot (who may connect agents)
--     ottoq_oauth_clients        agents that registered (public clients only: no secret exists)
--     ottoq_oauth_device_codes   device authorizations: the code (SHA-256), the user code, pending/approved/denied/consumed
--     ottoq_oauth_auth_requests  browser authorizations: redirect URI, PKCE challenge, state, the one-time code (SHA-256)
--     ottoq_oauth_grants         one row per connection: account, email, client, scope, resource, how it was made
--     ottoq_oauth_tokens         access (oqt_, 1 hour) and refresh (oqr_, 30 days, single-use, rotated) tokens, SHA-256
--   A CONNECTION IS A PRINCIPAL. Approved and exchanged, a code makes one ottoq_agent_principals row, origin 'oauth',
--   exactly like an owner key (kind personal, the account's fleet, the twin depot, read + note + owner_settings, 60
--   calls a minute), whose own token_hash is the SHA-256 of a secret nobody was given. ottoq_agent_resolve maps a live
--   access token to it. So all that 0559, 0605 and 0607 built (scope, rate limit, ledger, owner tools, receipts,
--   refusals, undo, OrchestrAV's link and confirmation codes) serves a signed-in agent unchanged.
--   ONE DOOR FOR THE GATEWAY'S SIGN-IN ENDPOINTS: ottoq_agent_oauth(op, args, meta), service_role only: register,
--   device_authorize, authorize, token, revoke. Every call is a row in 0559's call ledger (transport 'oauth'), except
--   that a refusal no connection owns is ledgered at most 120 times a minute (0559 bounds an unknown token the same way).
--   THE PERSON'S DOORS, authenticated only, identity from auth.uid(): ottoq_account_me, ottoq_oauth_device_lookup /
--   _decide, ottoq_oauth_request_lookup / _decide, ottoq_account_disconnect. The sign-in page calls them with the
--   person's own Supabase session.
--   LINKING: ottoq_owner_account_link(email, fleet) / _unlink (service_role, or the SQL editor). Nothing here creates an
--   auth user or sets a password: that is Supabase Auth's.
--
-- ══ §3 THE SAFETY ENVELOPE ══════════════════════════════════════════════════════════════════════════════════════════
--
--   * A connection is an owner key and nothing more: 0605's envelope holds unchanged (the fleet's own cars, a live demo
--     run for settings, the contract's range, add work never remove it, nothing moves a car). A CHECK pins it.
--   * Nothing reaches a fleet until a signed-in, linked owner approves the agent by name. A registration is not a
--     credential. Codes are single-use; a device code lives 10 minutes, an authorization code 5, an access token 60.
--   * Secrets are SHA-256 at rest. The gateway hashes what it is handed before it calls; what this file mints is
--     returned once. The ledger records outcomes, never a token, code or password.
--   * A refresh token presented twice closes its connection (OAuth 2.1 / the security BCP), except a retry within a
--     minute whose successor was never used. An authorization code presented twice closes what it opened.
--   * Throttled from the ledger: registrations 20/hour per caller (200 overall), device requests 30/hour (300),
--     browser requests 60/hour (600), wrong user codes 10 per 15 minutes per account.
--   * The owner can disconnect any of their agents at once (ottoq_account_disconnect); unlinking an account closes
--     every agent it connected.
--
-- ══ §4 WHAT IT DELIBERATELY DOES NOT DO ═════════════════════════════════════════════════════════════════════════════
--
--   * No sign-up. Accounts are created in Supabase Auth and linked by hand; for now one is (Chase's, to Tesla
--     Robotaxi TN). Opening this to every owner is sign-up plus linking, with no change to the agent side.
--   * No Client ID Metadata Documents yet (the 2026-07-28 revision's SHOULD; dynamic registration is retained there for
--     compatibility, and Hermes's device login uses it). No confidential clients. One fleet per account.
--   * The passcode door (0607) and issued keys (0559) are untouched and keep working beside this.
--   * Nothing on the tick path; no engine table changes.
--
-- ══ §5 forces_recert FALSE, forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   Every function this file creates or replaces belongs to the agent door or the owner boards, which no certification,
--   dial or sweep arm calls; the tables are new; the one existing table altered (ottoq_agent_principals) is read by no
--   atom. No engine function is touched.
--
-- ══ §6 VALIDATED ON A SCRATCH CLUSTER ═══════════════════════════════════════════════════════════════════════════════
--
--   tests/test_agent_signin_sql.py applies 0559, 0560 and 0605-0608 and this file over the stub engine and drives every
--   grant, refusal and throttle; tests/agent_signin.test.mjs drives the gateway's endpoints over HTTP against the same
--   SQL, and runs Hermes Agent's own device-login code against them end to end.
--
-- ══ §7 SOURCES (read 2026-10-10) ════════════════════════════════════════════════════════════════════════════════════
--
--   MCP authorization (2026-07-28 revision): https://modelcontextprotocol.io/specification/latest/basic/authorization
--   RFC 8628 (device grant): https://www.rfc-editor.org/rfc/rfc8628 . RFC 7591 (registration): https://www.rfc-editor.org/rfc/rfc7591
--   RFC 7009 (revocation): https://www.rfc-editor.org/rfc/rfc7009 . RFC 9207 (iss): https://www.rfc-editor.org/rfc/rfc9207
--   Hermes Agent MCP OAuth and device login: https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp
--   Supabase Edge Functions serve no HTML on the default domain: https://supabase.com/docs/guides/functions/http-methods

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0660 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0607 and 0608 applied as written; the six bodies this file extends are the ones it was written against ──
DO $premises$
DECLARE v_bad text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0660_an_owner_signs_in_and_connects_their_own_agent') THEN
    RAISE EXCEPTION '0660 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0608_the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code') THEN
    RAISE EXCEPTION '0660 P1: 0607 and 0608 (the passcode door and the owner boards) are not applied; apply them first';
  END IF;
  -- md5(prosrc), measured on the live catalog 2026-10-10 05:52 UTC and on a scratch cluster with 0559-0608 applied from
  -- their files: identical, all six
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_agent_resolve(text)',                                   '49a6e850bb511948f323e09dc18c3346'),
      ('public.ottoq_agent_unauthenticated(text)',                           '76ef1ed62fb6cb5c00b387a320a8c09b'),
      ('public.ottoq_agent_welcome_connected(public.ottoq_agent_principals)', '13ecf7f176ec91fdfa18cf811b4eb003'),
      ('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)',      '79138ff0ecc9b10370c5af6c4802e6dc'),
      ('public.ottoq_owner_board(uuid,uuid,uuid)',                           '84d0bae6cd45cb3999d84865b15cda89'),
      ('public.ottoq_depot_owner_board(uuid,integer)',                       '59fb402160a831ad698bb0012d9c1786')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(f)) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0660 P1: not the body this file was written against (re-measure before applying): %', v_bad;
  END IF;
  -- the three CHECKs this file widens are 0559's and 0607's, as merged
  IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_agent_principals'::regclass
        AND c.conname = 'ottoq_agent_principals_origin_check') NOT LIKE '%''issued''%''passcode''%'
     OR (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_agent_principals'::regclass
        AND c.conname = 'ottoq_agent_principals_token_prefix_check') NOT LIKE '%^oq[as]_%'
     OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_agent_principals'::regclass
        AND c.conname = 'ottoq_agent_principals_origin_shape_check') THEN
    RAISE EXCEPTION '0660 P1: ottoq_agent_principals'' origin, token_prefix or origin_shape CHECK is not the one this file widens';
  END IF;
  IF to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL OR to_regprocedure('auth.uid()') IS NULL THEN
    RAISE EXCEPTION '0660 P1: pgcrypto''s gen_random_bytes (schema extensions) or auth.uid() is missing';
  END IF;
  IF to_regprocedure('public.ottoq_agent_no_truncate()') IS NULL OR to_regprocedure('public.ottoq_agent_fleet_line(uuid,uuid)') IS NULL
     OR to_regprocedure('public.ottoq_owner_clock(timestamp with time zone,boolean,boolean)') IS NULL THEN
    RAISE EXCEPTION '0660 P1: a 0559/0605/0607 helper this file calls is missing';
  END IF;
END $premises$;

-- ── P2: nothing this file creates exists yet ──
DO $fresh$
DECLARE v_fn text; v_tb text;
BEGIN
  SELECT string_agg(t, ', ') INTO v_tb FROM unnest(ARRAY['public.ottoq_owner_accounts', 'public.ottoq_oauth_clients',
      'public.ottoq_oauth_device_codes', 'public.ottoq_oauth_auth_requests', 'public.ottoq_oauth_grants',
      'public.ottoq_oauth_tokens']) t WHERE to_regclass(t) IS NOT NULL;
  IF v_tb IS NOT NULL THEN
    RAISE EXCEPTION '0660 P2: table(s) this file creates already exist: %', v_tb;
  END IF;
  SELECT string_agg(p.proname, ', ') INTO v_fn
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND (p.proname LIKE 'ottoq\_oauth\_%' OR p.proname IN ('ottoq_agent_oauth', 'ottoq_account_me',
          'ottoq_account_disconnect', 'ottoq_owner_account_link', 'ottoq_owner_account_unlink'));
  IF v_fn IS NOT NULL THEN
    RAISE EXCEPTION '0660 P2: function(s) this file creates already exist: %', v_fn;
  END IF;
END $fresh$;

-- ── the rollback snapshot of the six bodies this file extends ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0660_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_resolve(text)'::regprocedure,
                 'public.ottoq_agent_unauthenticated(text)'::regprocedure,
                 'public.ottoq_agent_welcome_connected(public.ottoq_agent_principals)'::regprocedure,
                 'public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure,
                 'public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure,
                 'public.ottoq_depot_owner_board(uuid,integer)'::regprocedure);

-- ══ 1. a principal can be an agent signed in to an owner's account ══════════════════════════════════════════════════
--
-- 0607's CHECKs admit two origins. A third is admitted by dropping and re-adding three CHECKs (no function is dropped,
-- and every existing row is re-validated by the ADD). An 'oauth' principal is one CONNECTION: an owner signed in and
-- approved one agent. Its own token_hash is the SHA-256 of 32 random bytes that are never returned, so nothing can
-- present it; the connection is reached only through the short-lived access tokens in ottoq_oauth_tokens.

ALTER TABLE public.ottoq_agent_principals DROP CONSTRAINT ottoq_agent_principals_origin_check;
ALTER TABLE public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_origin_check
  CHECK (origin IN ('issued', 'passcode', 'oauth'));

ALTER TABLE public.ottoq_agent_principals DROP CONSTRAINT ottoq_agent_principals_token_prefix_check;
ALTER TABLE public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_token_prefix_check
  CHECK (token_prefix ~ '^oq[ast]_[0-9a-f]{8}$');

--: issued: oqa_, no expiry. passcode: oqs_, an expiry, an owner key's capabilities. oauth: oqt_, no expiry of its own (it
--: ends when its owner disconnects it), the agent's name, one fleet, an owner key's capabilities. ELSE false: a fourth
--: origin cannot slip through a CASE that returns NULL.
ALTER TABLE public.ottoq_agent_principals DROP CONSTRAINT ottoq_agent_principals_origin_shape_check;
ALTER TABLE public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_origin_shape_check CHECK (
  CASE origin
    WHEN 'issued' THEN token_prefix LIKE 'oqa\_%' AND expires_at IS NULL
    WHEN 'passcode' THEN token_prefix LIKE 'oqs\_%' AND expires_at IS NOT NULL AND display_name IS NOT NULL
         AND fleet_operator_id IS NOT NULL AND kind = 'personal'
         AND capabilities = ARRAY['note', 'owner_settings', 'read']::text[]
    WHEN 'oauth' THEN token_prefix LIKE 'oqt\_%' AND expires_at IS NULL AND display_name IS NOT NULL
         AND fleet_operator_id IS NOT NULL AND kind = 'personal'
         AND capabilities = ARRAY['note', 'owner_settings', 'read']::text[]
    ELSE false
  END);

COMMENT ON COLUMN public.ottoq_agent_principals.origin IS
'0607. issued = a key minted by ottoq_agent_issue_token (oqa_, no expiry); passcode = a session opened with OTTOYARD''s demo passcode through enter_passcode (oqs_, expires_at set, revoked when a demo run at its depot ends). 0660: oauth = one agent an owner signed in and approved (oqt_ access tokens in ottoq_oauth_tokens, no expiry of its own; it ends when the owner disconnects it, never with a run).';

-- ══ 2. the tables ═══════════════════════════════════════════════════════════════════════════════════════════════════

--: Who may connect agents, and to which fleet. One OTTOYARD account (an auth.users row) to one fleet at the twin depot.
--: Deliberately no FK to auth.users: ottoq_owner_account_link checks the account exists when it links it, and an FK
--: from public into auth would make a user's deletion fail or, as CASCADE, erase who connected what.
CREATE TABLE public.ottoq_owner_accounts (
  account_id        uuid PRIMARY KEY,
  email             text NOT NULL,
  fleet_operator_id uuid NOT NULL REFERENCES public.fleet_operators(id),
  depot_id          uuid NOT NULL DEFAULT '11111111-1111-1111-1111-111111111111'::uuid REFERENCES public.depots(id),
  status            text NOT NULL DEFAULT 'active',
  note              text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text NOT NULL DEFAULT session_user,
  disabled_at       timestamptz,
  CONSTRAINT ottoq_owner_accounts_depot_check CHECK (depot_id = '11111111-1111-1111-1111-111111111111'::uuid),
  CONSTRAINT ottoq_owner_accounts_status_check CHECK (status IN ('active', 'disabled')),
  CONSTRAINT ottoq_owner_accounts_disabled_check CHECK ((status = 'disabled') = (disabled_at IS NOT NULL)),
  CONSTRAINT ottoq_owner_accounts_email_check CHECK (email = lower(btrim(email)) AND email ~ '^[^@[:space:]]+@[^@[:space:]]+$')
);
COMMENT ON TABLE public.ottoq_owner_accounts IS
'0660. Which OTTOYARD accounts (Supabase Auth users of this project) may sign in and connect their own agents, and the one fleet each owns at the twin depot. Linked and unlinked by ottoq_owner_account_link / ottoq_owner_account_unlink (service_role). An agent connected through an account gets exactly an owner key''s scope: that fleet''s cars, read + note + owner_settings. No FK to auth.users, deliberately (the link function checks the account exists).';

--: The agents that registered (RFC 7591). Public clients only: no client secret exists.
CREATE TABLE public.ottoq_oauth_clients (
  client_id     text PRIMARY KEY,
  client_name   text NOT NULL,
  redirect_uris text[] NOT NULL DEFAULT '{}'::text[],
  grant_types   text[] NOT NULL,
  metadata      jsonb NOT NULL DEFAULT '{}'::jsonb,
  registered_ip text,
  status        text NOT NULL DEFAULT 'active',
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_oauth_clients_id_check CHECK (client_id ~ '^oqc_[0-9a-f]{32}$'),
  CONSTRAINT ottoq_oauth_clients_name_check CHECK (length(client_name) BETWEEN 1 AND 60 AND client_name !~ '[[:cntrl:]]'),
  CONSTRAINT ottoq_oauth_clients_grants_check CHECK (
    cardinality(grant_types) > 0
    AND grant_types <@ ARRAY['authorization_code', 'refresh_token', 'urn:ietf:params:oauth:grant-type:device_code']::text[]),
  CONSTRAINT ottoq_oauth_clients_uris_check CHECK (cardinality(redirect_uris) <= 10),
  CONSTRAINT ottoq_oauth_clients_status_check CHECK (status IN ('active', 'disabled'))
);
COMMENT ON TABLE public.ottoq_oauth_clients IS
'0660. Agents registered with OTTOYARD''s sign-in (RFC 7591 dynamic client registration through the agent gateway): a name to show the account''s owner, redirect URIs, grant types. Public clients only (token_endpoint_auth_method none): a registration is not a credential, and nothing is reachable until a signed-in owner approves the agent.';

--: One device authorization (RFC 8628): what an agent with no screen asked for, and what the owner answered.
CREATE TABLE public.ottoq_oauth_device_codes (
  device_code_hash text PRIMARY KEY,
  user_code        text NOT NULL,
  client_id        text NOT NULL REFERENCES public.ottoq_oauth_clients(client_id),
  scope            text NOT NULL,
  resource         text NOT NULL,
  status           text NOT NULL DEFAULT 'pending',
  account_id       uuid,
  principal_id     uuid REFERENCES public.ottoq_agent_principals(principal_id),
  interval_s       integer NOT NULL DEFAULT 5,
  requested_ip     text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL,
  decided_at       timestamptz,
  last_polled_at   timestamptz,
  polls            integer NOT NULL DEFAULT 0,
  CONSTRAINT ottoq_oauth_device_codes_hash_check CHECK (device_code_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT ottoq_oauth_device_codes_user_code_key UNIQUE (user_code),
  CONSTRAINT ottoq_oauth_device_codes_user_code_check CHECK (user_code ~ '^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$'),
  CONSTRAINT ottoq_oauth_device_codes_status_check CHECK (status IN ('pending', 'approved', 'denied', 'consumed')),
  CONSTRAINT ottoq_oauth_device_codes_decided_check CHECK ((status = 'pending') = (decided_at IS NULL)),
  CONSTRAINT ottoq_oauth_device_codes_account_check CHECK (status = 'pending' OR account_id IS NOT NULL),
  CONSTRAINT ottoq_oauth_device_codes_interval_check CHECK (interval_s BETWEEN 1 AND 60)
);
COMMENT ON TABLE public.ottoq_oauth_device_codes IS
'0660. RFC 8628 device authorizations: an agent with no screen of its own (Hermes on a server, reached through Telegram) asks to connect; the owner opens OTTOYARD''s sign-in page, enters the short user code, signs in and approves or denies; the agent''s polling then gets its tokens once. The device code is stored only as SHA-256 (the gateway hashes before it calls).';

--: One authorization request (OAuth 2.1 authorization code + PKCE S256), for agents that open a browser.
CREATE TABLE public.ottoq_oauth_auth_requests (
  request_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       text NOT NULL REFERENCES public.ottoq_oauth_clients(client_id),
  redirect_uri    text NOT NULL,
  code_challenge  text NOT NULL,
  state           text,
  scope           text NOT NULL,
  resource        text NOT NULL,
  issuer          text NOT NULL,
  status          text NOT NULL DEFAULT 'pending',
  account_id      uuid,
  code_hash       text,
  code_expires_at timestamptz,
  principal_id    uuid REFERENCES public.ottoq_agent_principals(principal_id),
  requested_ip    text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  decided_at      timestamptz,
  CONSTRAINT ottoq_oauth_auth_requests_challenge_check CHECK (code_challenge ~ '^[A-Za-z0-9_-]{43,128}$'),
  CONSTRAINT ottoq_oauth_auth_requests_state_check CHECK (state IS NULL OR (length(state) <= 512 AND state !~ '[[:cntrl:]]')),
  CONSTRAINT ottoq_oauth_auth_requests_status_check CHECK (status IN ('pending', 'approved', 'denied', 'consumed')),
  CONSTRAINT ottoq_oauth_auth_requests_code_hash_key UNIQUE (code_hash),
  CONSTRAINT ottoq_oauth_auth_requests_code_check CHECK ((status IN ('approved', 'consumed')) = (code_hash IS NOT NULL))
);
COMMENT ON TABLE public.ottoq_oauth_auth_requests IS
'0660. OAuth 2.1 authorization requests (code + PKCE S256): an agent that can open a browser sends its person to OTTOYARD''s sign-in page with one of these; approved, it is answered with a one-time code (stored as SHA-256) exchanged at the token endpoint with the PKCE verifier.';

--: One connection: the account that approved it, the agent, and how. The principal row is the connection's identity.
CREATE TABLE public.ottoq_oauth_grants (
  principal_id uuid PRIMARY KEY REFERENCES public.ottoq_agent_principals(principal_id),
  account_id   uuid NOT NULL,
  email        text NOT NULL,
  client_id    text NOT NULL REFERENCES public.ottoq_oauth_clients(client_id),
  scope        text NOT NULL,
  resource     text NOT NULL,
  created_via  text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_oauth_grants_via_check CHECK (created_via IN ('device_code', 'authorization_code'))
);
CREATE INDEX ottoq_oauth_grants_account_idx ON public.ottoq_oauth_grants (account_id, created_at DESC);
COMMENT ON TABLE public.ottoq_oauth_grants IS
'0660. One row per agent an owner connected to their OTTOYARD account: the account and its email, the client, the scope and resource, and whether it came through a device code or a browser authorization. Whether it is still connected is its principal''s status (ottoq_agent_principals, origin oauth).';

--: Access and refresh tokens, as SHA-256 only. An access token lasts an hour (honoured five minutes more, so a client's
--: clock drift never costs a sign-in); a refresh token 30 days and is single-use (each refresh returns a new pair, and
--: the one it replaced names its successor).
CREATE TABLE public.ottoq_oauth_tokens (
  token_hash     text PRIMARY KEY,
  kind           text NOT NULL,
  principal_id   uuid NOT NULL REFERENCES public.ottoq_agent_principals(principal_id),
  issued_at      timestamptz NOT NULL DEFAULT now(),
  expires_at     timestamptz NOT NULL,
  used_at        timestamptz,
  replaced_by    text,
  revoked_at     timestamptz,
  revoked_reason text,
  CONSTRAINT ottoq_oauth_tokens_hash_check CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT ottoq_oauth_tokens_kind_check CHECK (kind IN ('access', 'refresh')),
  CONSTRAINT ottoq_oauth_tokens_rotation_check CHECK (kind = 'refresh' OR (used_at IS NULL AND replaced_by IS NULL)),
  CONSTRAINT ottoq_oauth_tokens_revoked_check CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL))
);
CREATE INDEX ottoq_oauth_tokens_principal_idx ON public.ottoq_oauth_tokens (principal_id, kind, issued_at DESC);
COMMENT ON TABLE public.ottoq_oauth_tokens IS
'0660. The access tokens (oqt_, one hour) an agent signed in to an owner''s account presents as Authorization: Bearer, and the refresh tokens (oqr_, 30 days, single-use, rotated) it renews them with. SHA-256 only: the raw tokens are returned once, at the token endpoint, and never stored. ottoq_agent_resolve maps a live access token to its connection''s principal.';

-- ══ 3. the guards: what was connected, by whom, is evidence ═════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_oauth_keep_rows()
 RETURNS trigger
 LANGUAGE plpgsql
AS $fn$
/* 0660. The sign-in tables keep their rows: a connection, the account that approved it and its tokens are what answers
   "who let this agent in". Revoke or disable instead. The 0559 unlock (ottoq.agent_ledger_unlock = on) is the one
   override, for a migration that says why. */
BEGIN
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION '% keeps its rows as evidence: DELETE refused (revoke the connection or disable the account instead)', TG_TABLE_NAME
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_owner_accounts_keep_rows_trg BEFORE DELETE ON public.ottoq_owner_accounts
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
CREATE TRIGGER ottoq_oauth_clients_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_clients
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
CREATE TRIGGER ottoq_oauth_device_codes_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_device_codes
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
CREATE TRIGGER ottoq_oauth_auth_requests_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_auth_requests
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
CREATE TRIGGER ottoq_oauth_grants_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_grants
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
CREATE TRIGGER ottoq_oauth_tokens_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_tokens
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
CREATE TRIGGER ottoq_owner_accounts_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_owner_accounts
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_oauth_clients_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_clients
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_oauth_device_codes_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_device_codes
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_oauth_auth_requests_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_auth_requests
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_oauth_grants_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_grants
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_oauth_tokens_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_tokens
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- ══ 4. small internal helpers (executable by nobody but their owner) ═══════════════════════════════════════════════

-- SHA-256 as lowercase hex, the form every token hash in the agent door takes.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_sha256(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT encode(sha256(convert_to(p_text, 'UTF8')), 'hex')
$fn$;

-- A secret: the prefix and 64 hex digits (32 bytes of pgcrypto's gen_random_bytes, as 0559's keys are).
CREATE OR REPLACE FUNCTION public.ottoq_oauth_secret(p_prefix text)
 RETURNS text
 LANGUAGE sql
 VOLATILE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT p_prefix || encode(extensions.gen_random_bytes(32), 'hex')
$fn$;

-- A user code a person reads off a phone: XXXX-XXXX from twenty consonants (RFC 8628 6.1: no vowels, so no words, and
-- nothing to confuse with a digit). 20^8 = 2.56e10 codes, each live ten minutes, and the owner must be signed in to try one.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_new_user_code()
 RETURNS text
 LANGUAGE sql
 VOLATILE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT substr(s, 1, 4) || '-' || substr(s, 5, 4)
    FROM (SELECT string_agg(substr('BCDFGHJKLMNPQRSTVWXZ', (get_byte(b, i) % 20) + 1, 1), '' ORDER BY i) AS s
            FROM (SELECT extensions.gen_random_bytes(8) AS b) r, generate_series(0, 7) i) x
$fn$;

-- What a person typed, as a user code: case, spaces and dashes forgiven; NULL if it cannot be one.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_normalize_user_code(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT CASE WHEN c ~ '^[BCDFGHJKLMNPQRSTVWXZ]{8}$' THEN substr(c, 1, 4) || '-' || substr(c, 5, 4) END
    FROM (SELECT upper(regexp_replace(COALESCE(p_text, ''), '[^A-Za-z]', '', 'g')) AS c) x
$fn$;

-- Percent-encoding for a query value (RFC 3986 unreserved characters pass; everything else is %XX of its UTF-8 bytes).
CREATE OR REPLACE FUNCTION public.ottoq_oauth_urlencode(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT COALESCE(string_agg(CASE WHEN (b BETWEEN 48 AND 57) OR (b BETWEEN 65 AND 90) OR (b BETWEEN 97 AND 122) OR b IN (45, 46, 95, 126)
                                  THEN chr(b) ELSE '%' || upper(lpad(to_hex(b), 2, '0')) END, '' ORDER BY i), '')
    FROM (SELECT i, get_byte(v, i) AS b
            FROM (SELECT convert_to(p_text, 'UTF8') AS v) x, generate_series(0, length(convert_to(p_text, 'UTF8')) - 1) i) y
$fn$;

-- A redirect URI an agent may register: https, or a loopback address over http (RFC 8252 7.3), no fragment.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_redirect_ok(p_uri text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT p_uri IS NOT NULL AND length(p_uri) <= 300 AND p_uri !~ '[[:space:][:cntrl:]#]'
     AND (p_uri ~ '^https://[^/?]+' OR p_uri ~ '^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]{1,5})?(/|$|\?)')
$fn$;

-- Does a redirect URI an agent sent match one it registered? Exactly, or (a loopback URI) on any port (RFC 8252 7.3).
CREATE OR REPLACE FUNCTION public.ottoq_oauth_redirect_matches(p_uri text, p_registered text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT p_uri = ANY (p_registered)
      OR (p_uri ~ '^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]{1,5})?(/|$|\?)'
          AND regexp_replace(p_uri, '^(http://[^/:?]+|http://\[::1\])(:[0-9]{1,5})?', '\1')
              = ANY (SELECT regexp_replace(r, '^(http://[^/:?]+|http://\[::1\])(:[0-9]{1,5})?', '\1') FROM unnest(p_registered) r))
$fn$;

-- One row in 0559's call ledger for a sign-in call: transport 'oauth' (the gateway's sign-in endpoints) or 'web' (the
-- sign-in page, as a signed-in person). Never a raw token, code or password.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_ledger(p_tool text, p_transport text, p_ok boolean, p_status integer, p_code text,
                                                     p_principal uuid, p_meta jsonb, p_detail jsonb, p_t0 timestamptz)
 RETURNS void
 LANGUAGE sql
 VOLATILE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  INSERT INTO public.ottoq_agent_call_ledger
         (principal_id, principal_name, transport, tool, http_method, path, ok, http_status, error_code, latency_ms,
          depot_id, fleet_operator_id, detail)
  SELECT p_principal, a.name, p_transport, left(p_tool, 64), left(p_meta ->> 'http_method', 10), left(p_meta ->> 'path', 200),
         p_ok, p_status, left(p_code, 64),
         GREATEST(0, (extract(epoch FROM clock_timestamp() - p_t0) * 1000)::integer),
         COALESCE(a.depot_id, '11111111-1111-1111-1111-111111111111'::uuid), a.fleet_operator_id,
         jsonb_strip_nulls(COALESCE(p_detail, '{}'::jsonb)
           || jsonb_build_object('ip', left(p_meta ->> 'ip', 64), 'client', left(p_meta ->> 'client', 120)))
    FROM (SELECT 1) one
    LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = p_principal
$fn$;

-- Has this caller (by IP), or everyone together, made too many of one sign-in call in the window? Counted from the
-- ledger, so it holds across gateway isolates as 0559's rate limit does.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_throttled(p_tool text, p_ip text, p_per_ip integer, p_global integer, p_window interval)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT count(*) FILTER (WHERE p_ip IS NOT NULL AND l.detail ->> 'ip' = p_ip) >= p_per_ip
      OR count(*) >= p_global
    FROM public.ottoq_agent_call_ledger l
   WHERE l.called_at > now() - p_window AND l.tool = p_tool
$fn$;

-- An OAuth error body (RFC 6749 5.2 / RFC 8628 3.5 / RFC 7591 3.2.2) and the HTTP status it travels with.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_error(p_status integer, p_error text, p_description text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT jsonb_build_object('ok', false, 'http_status', p_status,
                            'body', jsonb_build_object('error', p_error, 'error_description', p_description))
$fn$;

-- The account a signed-in person is (auth.uid()), if it may connect agents.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_caller_account()
 RETURNS public.ottoq_owner_accounts
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v public.ottoq_owner_accounts;
BEGIN
  SELECT * INTO v FROM public.ottoq_owner_accounts o WHERE o.account_id = auth.uid() AND o.status = 'active';
  RETURN v;
END $fn$;

-- What a connected agent may do, in the owner's words: shown on the sign-in page before the owner approves.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_consent(p_account public.ottoq_owner_accounts)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT jsonb_build_object(
    'fleet', f,
    'depot', (SELECT d.name FROM public.depots d WHERE d.id = p_account.depot_id),
    'can', jsonb_build_array(
      format('See %s''s %s at %s: charge, where each car is, and what it still needs', f ->> 'name', f ->> 'cars_phrase',
             (SELECT d.name FROM public.depots d WHERE d.id = p_account.depot_id)),
      'Set how full your cars charge (inside your contract), order services, and hold a car until a time, during demo runs',
      'Leave notes for the depot crew'),
    'cannot', jsonb_build_array(
      'Move a car, or choose its stall, charger or place in line',
      'See or change any other owner''s cars'))
    FROM (SELECT public.ottoq_agent_fleet_line(p_account.fleet_operator_id, p_account.depot_id) AS f) x
$fn$;

-- A new connection: the principal that IS the connection, and its grant row. NULL when the account may no longer
-- connect agents (unlinked or disabled between the approval and the token request).
CREATE OR REPLACE FUNCTION public.ottoq_oauth_connect(p_account_id uuid, p_client_id text, p_scope text, p_resource text, p_via text)
 RETURNS uuid
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_acct   public.ottoq_owner_accounts;
  v_client public.ottoq_oauth_clients;
  v_slug   text;
  v_hash   text := public.ottoq_oauth_sha256(public.ottoq_oauth_secret('oqt_'));
  v_id     uuid;
BEGIN
  SELECT * INTO v_acct FROM public.ottoq_owner_accounts o WHERE o.account_id = p_account_id AND o.status = 'active';
  IF v_acct.account_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_client FROM public.ottoq_oauth_clients c WHERE c.client_id = p_client_id;
  v_slug := btrim(left(regexp_replace(lower(v_client.client_name), '[^a-z0-9]+', '-', 'g'), 24), '-');
  IF v_slug = '' THEN v_slug := 'agent'; END IF;
  INSERT INTO public.ottoq_agent_principals
         (name, kind, depot_id, fleet_operator_id, capabilities, token_hash, token_prefix, rate_limit_per_min, max_pending,
          note, origin, display_name, expires_at)
  VALUES ('oauth.' || v_slug || '.' || substr(v_hash, 9, 8), 'personal', v_acct.depot_id, v_acct.fleet_operator_id,
          ARRAY['note', 'owner_settings', 'read']::text[],
          --: the connection's own token_hash: the SHA-256 of a secret nobody was given, so it cannot be presented
          v_hash, 'oqt_' || substr(v_hash, 1, 8), 60, 20,
          format('signed in as %s (%s)', v_acct.email, replace(p_via, '_', ' ')), 'oauth', v_client.client_name, NULL)
  RETURNING principal_id INTO v_id;
  INSERT INTO public.ottoq_oauth_grants (principal_id, account_id, email, client_id, scope, resource, created_via)
  VALUES (v_id, v_acct.account_id, v_acct.email, p_client_id, p_scope, p_resource, p_via);
  RETURN v_id;
END $fn$;

-- A new token pair for a connection: an access token (an hour) and a refresh token (30 days, single-use). The raw values
-- leave here once, in the token endpoint's answer. The access token is told to last 3600 seconds and is honoured for 65
-- minutes: an MCP client renews a token ahead of time by ITS clock, and a 401 on a token it still thinks valid makes it
-- start a whole new sign-in instead (Hermes Agent cannot start a device login in the background, measured 2026-10-10 on
-- its own CLI), so five minutes of clock drift or a slow request must not cost the owner a sign-in.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_mint(p_principal_id uuid, p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_access  text := public.ottoq_oauth_secret('oqt_');
  v_refresh text := public.ottoq_oauth_secret('oqr_');
BEGIN
  INSERT INTO public.ottoq_oauth_tokens (token_hash, kind, principal_id, expires_at)
  VALUES (public.ottoq_oauth_sha256(v_access), 'access', p_principal_id, now() + interval '65 minutes'),
         (public.ottoq_oauth_sha256(v_refresh), 'refresh', p_principal_id, now() + interval '30 days');
  RETURN jsonb_build_object('access_token', v_access, 'token_type', 'Bearer', 'expires_in', 3600,
                            'refresh_token', v_refresh, 'scope', p_scope);
END $fn$;

-- Close a connection: its principal is revoked (final, 0559's guard) and every token it holds stops working.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_close(p_principal_id uuid, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_n integer;
BEGIN
  UPDATE public.ottoq_agent_principals a
     SET status = 'revoked', revoked_at = now(), revoked_reason = left(p_reason, 200)
   WHERE a.principal_id = p_principal_id AND a.origin = 'oauth' AND a.status = 'active';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE public.ottoq_oauth_tokens t
     SET revoked_at = now(), revoked_reason = left(p_reason, 200)
   WHERE t.principal_id = p_principal_id AND t.revoked_at IS NULL;
  RETURN v_n > 0;
END $fn$;
-- ══ 5. the sign-in endpoints' one door: ottoq_agent_oauth (service_role only, called by the gateway) ═══════════════
--
-- Each operation returns {ok, http_status, body} where body is exactly the OAuth answer the gateway sends (RFC 6749,
-- 7591, 7009, 8628), plus internal keys the dispatcher strips: principal_id and detail (for the ledger). The gateway
-- hashes every secret it is handed (device code, authorization code, refresh token) before it calls; the secrets this
-- door mints (device codes, access and refresh tokens) are returned once and stored as SHA-256.

CREATE OR REPLACE FUNCTION public.ottoq_oauth_register(p_args jsonb, p_meta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. RFC 7591 dynamic client registration, public clients only. Throttled per caller (20 an hour) and overall (200). */
DECLARE
  v_ip     text := left(p_meta ->> 'ip', 64);
  v_name   text;
  v_uris   text[] := '{}'::text[];
  v_grants text[];
  v_method text := COALESCE(NULLIF(p_args ->> 'token_endpoint_auth_method', ''), 'none');
  v_id     text;
  u        text;
BEGIN
  IF public.ottoq_oauth_throttled('oauth.register', v_ip, 20, 200, interval '1 hour') THEN
    RETURN public.ottoq_oauth_error(429, 'temporarily_unavailable', 'Too many agent registrations from here. Try again in an hour.');
  END IF;
  IF jsonb_typeof(p_args) IS DISTINCT FROM 'object' THEN
    RETURN public.ottoq_oauth_error(400, 'invalid_client_metadata', 'The registration must be a JSON object.');
  END IF;
  v_name := left(btrim(regexp_replace(COALESCE(p_args ->> 'client_name', ''), '[[:cntrl:]]', '', 'g')), 60);
  IF v_name = '' THEN v_name := 'An agent'; END IF;
  IF p_args ? 'redirect_uris' THEN
    IF jsonb_typeof(p_args -> 'redirect_uris') IS DISTINCT FROM 'array' OR jsonb_array_length(p_args -> 'redirect_uris') > 10 THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_redirect_uri', 'redirect_uris must be a list of at most 10 addresses.');
    END IF;
    FOR u IN SELECT jsonb_array_elements_text(p_args -> 'redirect_uris') LOOP
      IF NOT public.ottoq_oauth_redirect_ok(u) THEN
        RETURN public.ottoq_oauth_error(400, 'invalid_redirect_uri',
          'A redirect URI must be https, or http on a loopback address (127.0.0.1, localhost, [::1]), with no fragment.');
      END IF;
      v_uris := v_uris || u;
    END LOOP;
  END IF;
  IF p_args ? 'grant_types' THEN
    IF jsonb_typeof(p_args -> 'grant_types') IS DISTINCT FROM 'array' THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_client_metadata', 'grant_types must be a list.');
    END IF;
    SELECT array_agg(DISTINCT g ORDER BY g) INTO v_grants FROM jsonb_array_elements_text(p_args -> 'grant_types') g;
  ELSE
    v_grants := ARRAY['authorization_code', 'refresh_token']::text[];
  END IF;
  IF v_grants IS NULL OR NOT v_grants <@ ARRAY['authorization_code', 'refresh_token', 'urn:ietf:params:oauth:grant-type:device_code']::text[] THEN
    RETURN public.ottoq_oauth_error(400, 'invalid_client_metadata',
      'OTTOYARD signs agents in with authorization_code, the device_code grant, and refresh_token only.');
  END IF;
  IF 'authorization_code' = ANY (v_grants) AND cardinality(v_uris) = 0 THEN
    RETURN public.ottoq_oauth_error(400, 'invalid_redirect_uri', 'The authorization_code grant needs at least one redirect URI.');
  END IF;
  IF v_method <> 'none' THEN
    RETURN public.ottoq_oauth_error(400, 'invalid_client_metadata',
      'OTTOYARD registers public clients only: use token_endpoint_auth_method "none". An agent proves itself with PKCE or a device code, and its person approves it.');
  END IF;
  v_id := 'oqc_' || encode(extensions.gen_random_bytes(16), 'hex');
  INSERT INTO public.ottoq_oauth_clients (client_id, client_name, redirect_uris, grant_types, metadata, registered_ip)
  VALUES (v_id, v_name, v_uris, v_grants,
          (SELECT COALESCE(jsonb_object_agg(k, v), '{}'::jsonb) FROM jsonb_each(p_args) e(k, v)
            WHERE k IN ('client_name', 'client_uri', 'logo_uri', 'software_id', 'software_version', 'application_type', 'scope')
              AND length(v::text) <= 500),
          v_ip);
  RETURN jsonb_build_object('ok', true, 'http_status', 201,
    'body', jsonb_build_object(
      'client_id', v_id, 'client_id_issued_at', extract(epoch FROM now())::bigint, 'client_name', v_name,
      'redirect_uris', to_jsonb(v_uris), 'grant_types', to_jsonb(v_grants),
      'response_types', CASE WHEN 'authorization_code' = ANY (v_grants) THEN '["code"]'::jsonb ELSE '[]'::jsonb END,
      'token_endpoint_auth_method', 'none', 'scope', 'fleet'),
    'detail', jsonb_build_object('client_id', v_id, 'client_name', v_name));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_oauth_device_authorize(p_args jsonb, p_meta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. RFC 8628 3.1-3.2: an agent with no screen asks to connect. Ten minutes for its person to sign in and approve,
   polled no faster than every five seconds. The device code is returned once and kept as SHA-256; the gateway adds the
   sign-in page's address (verification_uri) to the answer. */
DECLARE
  v_ip     text := left(p_meta ->> 'ip', 64);
  v_client public.ottoq_oauth_clients;
  v_device text := public.ottoq_oauth_secret('oqd_');
  v_code   text;
  i        integer := 0;
BEGIN
  IF public.ottoq_oauth_throttled('oauth.device_authorize', v_ip, 30, 300, interval '1 hour') THEN
    RETURN public.ottoq_oauth_error(429, 'slow_down', 'Too many sign-in requests from here. Try again later.');
  END IF;
  SELECT * INTO v_client FROM public.ottoq_oauth_clients c WHERE c.client_id = p_args ->> 'client_id' AND c.status = 'active';
  IF v_client.client_id IS NULL THEN
    RETURN public.ottoq_oauth_error(401, 'invalid_client', 'Unknown client_id. Register first (registration_endpoint).');
  END IF;
  IF NOT ('urn:ietf:params:oauth:grant-type:device_code' = ANY (v_client.grant_types)) THEN
    RETURN public.ottoq_oauth_error(400, 'unauthorized_client', 'This client did not register the device_code grant.');
  END IF;
  LOOP
    v_code := public.ottoq_oauth_new_user_code();
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.ottoq_oauth_device_codes d WHERE d.user_code = v_code);
    i := i + 1;
    IF i > 5 THEN
      RETURN public.ottoq_oauth_error(503, 'temporarily_unavailable', 'Could not make a fresh code. Try again.');
    END IF;
  END LOOP;
  INSERT INTO public.ottoq_oauth_device_codes (device_code_hash, user_code, client_id, scope, resource, requested_ip, expires_at)
  VALUES (public.ottoq_oauth_sha256(v_device), v_code, v_client.client_id, 'fleet',
          COALESCE(NULLIF(p_args ->> 'resource', ''), 'ottoq-agent-gateway'), v_ip, now() + interval '10 minutes');
  RETURN jsonb_build_object('ok', true, 'http_status', 200,
    'body', jsonb_build_object('device_code', v_device, 'user_code', v_code, 'expires_in', 600, 'interval', 5),
    'detail', jsonb_build_object('client_id', v_client.client_id, 'client_name', v_client.client_name));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_oauth_authorize(p_args jsonb, p_meta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. OAuth 2.1 authorization endpoint (code + PKCE S256): validates the request and records it; the gateway then
   sends the browser to OTTOYARD's sign-in page with the request's id. Before the redirect URI is known to be the
   client's own, an error is shown, never redirected (RFC 6749 4.1.2.1); after, it goes back to the client. */
DECLARE
  v_ip       text := left(p_meta ->> 'ip', 64);
  v_client   public.ottoq_oauth_clients;
  v_redirect text := NULLIF(p_args ->> 'redirect_uri', '');
  v_state    text := p_args ->> 'state';
  v_back     jsonb;
  v_id       uuid;
BEGIN
  SELECT * INTO v_client FROM public.ottoq_oauth_clients c WHERE c.client_id = p_args ->> 'client_id' AND c.status = 'active';
  IF v_client.client_id IS NULL THEN
    RETURN public.ottoq_oauth_error(400, 'invalid_client', 'Unknown client_id: this agent has not registered with OTTOYARD.');
  END IF;
  IF v_redirect IS NULL AND cardinality(v_client.redirect_uris) = 1 THEN
    v_redirect := v_client.redirect_uris[1];
  END IF;
  IF v_redirect IS NULL OR NOT public.ottoq_oauth_redirect_matches(v_redirect, v_client.redirect_uris) THEN
    RETURN public.ottoq_oauth_error(400, 'invalid_request', 'redirect_uri is not one this agent registered.');
  END IF;
  -- from here an error goes back to the agent at its redirect URI
  v_back := jsonb_build_object('redirect_uri', v_redirect, 'state', v_state);
  IF COALESCE(p_args ->> 'response_type', '') <> 'code' THEN
    RETURN public.ottoq_oauth_error(400, 'unsupported_response_type', 'Only response_type=code is supported.') || v_back;
  END IF;
  IF NOT ('authorization_code' = ANY (v_client.grant_types)) THEN
    RETURN public.ottoq_oauth_error(400, 'unauthorized_client', 'This agent did not register the authorization_code grant.') || v_back;
  END IF;
  IF COALESCE(p_args ->> 'code_challenge_method', '') <> 'S256' OR COALESCE(p_args ->> 'code_challenge', '') !~ '^[A-Za-z0-9_-]{43,128}$' THEN
    RETURN public.ottoq_oauth_error(400, 'invalid_request', 'PKCE is required: code_challenge with code_challenge_method=S256.') || v_back;
  END IF;
  IF v_state IS NOT NULL AND (length(v_state) > 512 OR v_state ~ '[[:cntrl:]]') THEN
    RETURN public.ottoq_oauth_error(400, 'invalid_request', 'state is too long or not printable.') || jsonb_build_object('redirect_uri', v_redirect);
  END IF;
  IF public.ottoq_oauth_throttled('oauth.authorize', v_ip, 60, 600, interval '1 hour') THEN
    RETURN public.ottoq_oauth_error(429, 'temporarily_unavailable', 'Too many sign-in attempts from here. Try again later.') || v_back;
  END IF;
  INSERT INTO public.ottoq_oauth_auth_requests (client_id, redirect_uri, code_challenge, state, scope, resource, issuer, requested_ip, expires_at)
  VALUES (v_client.client_id, v_redirect, p_args ->> 'code_challenge', v_state, 'fleet',
          COALESCE(NULLIF(p_args ->> 'resource', ''), 'ottoq-agent-gateway'), COALESCE(NULLIF(p_args ->> 'issuer', ''), 'https://www.ottoyard.com'),
          v_ip, now() + interval '10 minutes')
  RETURNING request_id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'http_status', 200, 'body', jsonb_build_object('request_id', v_id),
                            'detail', jsonb_build_object('client_id', v_client.client_id, 'request_id', v_id));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_oauth_token(p_args jsonb, p_meta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. The token endpoint. Three grants: the device code (RFC 8628 3.4-3.5), the authorization code with its PKCE
   verifier's S256 (OAuth 2.1 4.1.3), and the refresh token (single-use, rotated: a refresh token presented twice closes
   the connection, except a retry within a minute whose successor was never used). The gateway sends hashes, never the
   raw device code, code or refresh token. */
DECLARE
  v_grant   text := COALESCE(p_args ->> 'grant_type', '');
  v_client  text := p_args ->> 'client_id';
  v_dev     public.ottoq_oauth_device_codes;
  v_req     public.ottoq_oauth_auth_requests;
  v_tok     public.ottoq_oauth_tokens;
  v_next    public.ottoq_oauth_tokens;
  v_g       public.ottoq_oauth_grants;
  v_p       public.ottoq_agent_principals;
  v_pid     uuid;
  v_out     jsonb;
BEGIN
  IF v_client IS NULL OR v_client = '' THEN
    RETURN public.ottoq_oauth_error(401, 'invalid_client', 'client_id is required.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_oauth_clients c WHERE c.client_id = v_client AND c.status = 'active') THEN
    RETURN public.ottoq_oauth_error(401, 'invalid_client', 'Unknown client_id.');
  END IF;

  IF v_grant = 'urn:ietf:params:oauth:grant-type:device_code' THEN
    SELECT * INTO v_dev FROM public.ottoq_oauth_device_codes d WHERE d.device_code_hash = p_args ->> 'device_code_hash' FOR UPDATE;
    IF v_dev.device_code_hash IS NULL OR v_dev.client_id <> v_client THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'Unknown device_code.');
    END IF;
    IF v_dev.status = 'consumed' THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'This device_code was already exchanged.');
    END IF;
    IF v_dev.status = 'denied' THEN
      RETURN public.ottoq_oauth_error(400, 'access_denied', 'The account''s owner denied this agent.') || jsonb_build_object('detail', jsonb_build_object('client_id', v_client));
    END IF;
    IF now() >= v_dev.expires_at THEN
      RETURN public.ottoq_oauth_error(400, 'expired_token', 'The sign-in code expired. Start the sign-in again.');
    END IF;
    IF v_dev.status = 'pending' THEN
      IF v_dev.last_polled_at IS NOT NULL AND now() < v_dev.last_polled_at + make_interval(secs => v_dev.interval_s - 1) THEN
        UPDATE public.ottoq_oauth_device_codes d
           SET interval_s = LEAST(d.interval_s + 5, 60), last_polled_at = now(), polls = d.polls + 1
         WHERE d.device_code_hash = v_dev.device_code_hash;
        RETURN public.ottoq_oauth_error(400, 'slow_down', 'Polling too fast: wait five more seconds between polls.');
      END IF;
      UPDATE public.ottoq_oauth_device_codes d SET last_polled_at = now(), polls = d.polls + 1
       WHERE d.device_code_hash = v_dev.device_code_hash;
      RETURN public.ottoq_oauth_error(400, 'authorization_pending', 'Waiting for the account''s owner to sign in and approve.');
    END IF;
    -- approved: the connection is made once, and the code is spent
    v_pid := public.ottoq_oauth_connect(v_dev.account_id, v_client, v_dev.scope, v_dev.resource, 'device_code');
    IF v_pid IS NULL THEN
      RETURN public.ottoq_oauth_error(400, 'access_denied', 'The account that approved this agent can no longer connect agents.');
    END IF;
    UPDATE public.ottoq_oauth_device_codes d SET status = 'consumed', principal_id = v_pid
     WHERE d.device_code_hash = v_dev.device_code_hash;
    v_out := public.ottoq_oauth_mint(v_pid, v_dev.scope);
    RETURN jsonb_build_object('ok', true, 'http_status', 200, 'body', v_out, 'principal_id', v_pid,
                              'detail', jsonb_build_object('client_id', v_client, 'grant', 'device_code', 'connected', true));

  ELSIF v_grant = 'authorization_code' THEN
    SELECT * INTO v_req FROM public.ottoq_oauth_auth_requests r WHERE r.code_hash = p_args ->> 'code_hash' FOR UPDATE;
    IF v_req.request_id IS NULL OR v_req.client_id <> v_client THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'Unknown authorization code.');
    END IF;
    IF v_req.status = 'consumed' THEN
      --: OAuth 2.1 4.1.2: a code used twice closes what it opened
      IF v_req.principal_id IS NOT NULL THEN
        PERFORM public.ottoq_oauth_close(v_req.principal_id, 'authorization_code_replayed');
      END IF;
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'This authorization code was already used; the connection it made is closed.');
    END IF;
    IF v_req.status <> 'approved' OR now() >= v_req.code_expires_at THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'The authorization code expired. Start the sign-in again.');
    END IF;
    IF NULLIF(p_args ->> 'redirect_uri', '') IS NOT NULL AND p_args ->> 'redirect_uri' <> v_req.redirect_uri THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'redirect_uri does not match the authorization request.');
    END IF;
    IF COALESCE(p_args ->> 'code_challenge_s256', '') <> v_req.code_challenge THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'PKCE verification failed: the code_verifier does not match.');
    END IF;
    v_pid := public.ottoq_oauth_connect(v_req.account_id, v_client, v_req.scope, v_req.resource, 'authorization_code');
    IF v_pid IS NULL THEN
      RETURN public.ottoq_oauth_error(400, 'access_denied', 'The account that approved this agent can no longer connect agents.');
    END IF;
    UPDATE public.ottoq_oauth_auth_requests r SET status = 'consumed', principal_id = v_pid WHERE r.request_id = v_req.request_id;
    v_out := public.ottoq_oauth_mint(v_pid, v_req.scope);
    RETURN jsonb_build_object('ok', true, 'http_status', 200, 'body', v_out, 'principal_id', v_pid,
                              'detail', jsonb_build_object('client_id', v_client, 'grant', 'authorization_code', 'connected', true));

  ELSIF v_grant = 'refresh_token' THEN
    SELECT * INTO v_tok FROM public.ottoq_oauth_tokens t WHERE t.token_hash = p_args ->> 'refresh_token_hash' AND t.kind = 'refresh' FOR UPDATE;
    IF v_tok.token_hash IS NULL THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'Unknown refresh token.');
    END IF;
    SELECT * INTO v_g FROM public.ottoq_oauth_grants g WHERE g.principal_id = v_tok.principal_id;
    SELECT * INTO v_p FROM public.ottoq_agent_principals a WHERE a.principal_id = v_tok.principal_id;
    IF v_g.client_id IS DISTINCT FROM v_client THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'This refresh token belongs to another client.');
    END IF;
    IF v_p.status <> 'active' THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'This agent was disconnected from its OTTOYARD account. Sign in again to reconnect.')
             || jsonb_build_object('principal_id', v_p.principal_id);
    END IF;
    IF v_tok.revoked_at IS NOT NULL OR now() >= v_tok.expires_at THEN
      RETURN public.ottoq_oauth_error(400, 'invalid_grant', 'This refresh token expired or was revoked. Sign in again.')
             || jsonb_build_object('principal_id', v_p.principal_id);
    END IF;
    IF v_tok.used_at IS NOT NULL THEN
      SELECT * INTO v_next FROM public.ottoq_oauth_tokens t WHERE t.token_hash = v_tok.replaced_by;
      IF v_tok.used_at > now() - interval '60 seconds' AND v_next.token_hash IS NOT NULL
         AND v_next.used_at IS NULL AND v_next.revoked_at IS NULL THEN
        --: a retry of the same refresh (a timeout, a second worker): its unused successor is retired and a new pair issued
        UPDATE public.ottoq_oauth_tokens t SET revoked_at = now(), revoked_reason = 'superseded_by_retry'
         WHERE t.token_hash = v_next.token_hash;
      ELSE
        PERFORM public.ottoq_oauth_close(v_p.principal_id, 'refresh_token_reuse');
        RETURN public.ottoq_oauth_error(400, 'invalid_grant',
          'This refresh token was already used, so the connection was closed to be safe. Sign in to OTTOYARD again.')
               || jsonb_build_object('principal_id', v_p.principal_id);
      END IF;
    END IF;
    v_out := public.ottoq_oauth_mint(v_p.principal_id, v_g.scope);
    UPDATE public.ottoq_oauth_tokens t
       SET used_at = COALESCE(t.used_at, now()), replaced_by = public.ottoq_oauth_sha256(v_out ->> 'refresh_token')
     WHERE t.token_hash = v_tok.token_hash;
    RETURN jsonb_build_object('ok', true, 'http_status', 200, 'body', v_out, 'principal_id', v_p.principal_id,
                              'detail', jsonb_build_object('client_id', v_client, 'grant', 'refresh_token'));
  END IF;
  RETURN public.ottoq_oauth_error(400, 'unsupported_grant_type',
    'Supported: urn:ietf:params:oauth:grant-type:device_code, authorization_code, refresh_token.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_oauth_revoke(p_args jsonb, p_meta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. RFC 7009: revoking a refresh token closes the connection (its access tokens stop too); revoking an access token
   ends that token only. An unknown token is answered 200 like a known one, as 7009 2.2 requires. */
DECLARE v_tok public.ottoq_oauth_tokens;
BEGIN
  SELECT * INTO v_tok FROM public.ottoq_oauth_tokens t WHERE t.token_hash = p_args ->> 'token_hash';
  IF v_tok.token_hash IS NOT NULL THEN
    IF v_tok.kind = 'refresh' THEN
      PERFORM public.ottoq_oauth_close(v_tok.principal_id, 'revoked_by_agent');
    ELSIF v_tok.revoked_at IS NULL THEN
      UPDATE public.ottoq_oauth_tokens t SET revoked_at = now(), revoked_reason = 'revoked_by_agent' WHERE t.token_hash = v_tok.token_hash;
    END IF;
  END IF;
  RETURN jsonb_build_object('ok', true, 'http_status', 200, 'body', '{}'::jsonb, 'principal_id', v_tok.principal_id,
                            'detail', jsonb_build_object('kind', v_tok.kind));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_oauth(p_op text, p_args jsonb DEFAULT '{}'::jsonb, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. The ONE function the gateway's sign-in endpoints call (service_role only), beside ottoq_agent_call: register,
   device_authorize, authorize, token, revoke. It reads no engine data and changes no engine state: it mints and closes
   connections. Every call is a row in 0559's call ledger (transport 'oauth', tool 'oauth.<op>'), refusals included, up to
   120 a minute for refusals no connection owns. An
   unexpected error rolls back what the operation started and answers 500 server_error. */
DECLARE
  t0   timestamptz := clock_timestamp();
  v_op text := left(lower(btrim(COALESCE(p_op, ''))), 32);
  v_a  jsonb := CASE WHEN jsonb_typeof(p_args) = 'object' THEN p_args ELSE '{}'::jsonb END;
  v_m  jsonb := CASE WHEN jsonb_typeof(p_meta) = 'object' THEN p_meta ELSE '{}'::jsonb END;
  v    jsonb;
BEGIN
  BEGIN
    v := CASE v_op
      WHEN 'register'         THEN public.ottoq_oauth_register(v_a, v_m)
      WHEN 'device_authorize' THEN public.ottoq_oauth_device_authorize(v_a, v_m)
      WHEN 'authorize'        THEN public.ottoq_oauth_authorize(v_a, v_m)
      WHEN 'token'            THEN public.ottoq_oauth_token(v_a, v_m)
      WHEN 'revoke'           THEN public.ottoq_oauth_revoke(v_a, v_m)
      ELSE public.ottoq_oauth_error(404, 'not_found', 'Unknown sign-in operation.') END;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_agent_oauth(%): % %', v_op, SQLSTATE, SQLERRM;
    v := public.ottoq_oauth_error(500, 'server_error', 'OTTOYARD''s sign-in hit an internal error. Try again.');
  END;
  --: a refusal no connection owns is ledgered at most 120 times a minute (0559 bounds an unknown token's the same way),
  --: so made-up codes cannot flood the ledger; every success and every refusal a connection owns is always ledgered
  IF COALESCE((v ->> 'ok')::boolean, false) OR (v ->> 'principal_id') IS NOT NULL
     OR (SELECT count(*) FROM public.ottoq_agent_call_ledger l
          WHERE l.called_at > now() - interval '1 minute' AND l.transport = 'oauth' AND NOT l.ok AND l.principal_id IS NULL) < 120 THEN
    PERFORM public.ottoq_oauth_ledger('oauth.' || CASE WHEN v_op IN ('register', 'device_authorize', 'authorize', 'token', 'revoke') THEN v_op ELSE 'unknown' END,
      'oauth', COALESCE((v ->> 'ok')::boolean, false), (v ->> 'http_status')::integer, v #>> '{body,error}',
      (v ->> 'principal_id')::uuid, v_m,
      COALESCE(v -> 'detail', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('grant_type', CASE WHEN v_op = 'token' THEN left(v_a ->> 'grant_type', 60) END)),
      t0);
  END IF;
  RETURN jsonb_build_object('ok', COALESCE((v ->> 'ok')::boolean, false), 'http_status', (v ->> 'http_status')::integer,
                            'body', v -> 'body')
         || CASE WHEN v ? 'redirect_uri' THEN jsonb_build_object('redirect_uri', v ->> 'redirect_uri', 'state', v -> 'state') ELSE '{}'::jsonb END;
END $fn$;
-- ══ 6. the signed-in person's doors (authenticated only; who is always auth.uid(), never an argument) ══════════════
--
-- The sign-in page (www.ottoyard.com/connect) signs the person in to this project's Supabase Auth, then calls these
-- through PostgREST with the person's own session. An account that is not linked to a fleet is told so and can do
-- nothing. Wrong codes are counted per account from the ledger (10 in 15 minutes, then a wait).

CREATE OR REPLACE FUNCTION public.ottoq_account_me()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. Who the signed-in person is to OTTOYARD: their account, the fleet it owns, and the agents connected to it. */
DECLARE
  v_uid  uuid := auth.uid();
  v_acct public.ottoq_owner_accounts := public.ottoq_oauth_caller_account();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_signed_in', 'message', 'Sign in first.');
  END IF;
  IF v_acct.account_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'linked', false,
      'message', 'This account is not set up to connect agents yet. Ask OTTOYARD to link it to your fleet.');
  END IF;
  RETURN jsonb_build_object('ok', true, 'linked', true, 'email', v_acct.email)
         || public.ottoq_oauth_consent(v_acct)
         || jsonb_build_object('connections', COALESCE((
              SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                       'id', a.principal_id,
                       'agent', a.display_name,
                       'via', replace(g.created_via, '_', ' '),
                       'state', CASE WHEN a.status = 'active' THEN 'connected' ELSE 'disconnected' END,
                       'connected_local', public.ottoq_owner_clock(g.created_at, false),
                       'last_used_local', public.ottoq_owner_clock(a.last_used_at, false),
                       'disconnected_local', public.ottoq_owner_clock(a.revoked_at, false)))
                     ORDER BY (a.status = 'active') DESC, g.created_at DESC)
                FROM (SELECT * FROM public.ottoq_oauth_grants g0 WHERE g0.account_id = v_acct.account_id
                       ORDER BY g0.created_at DESC LIMIT 20) g
                JOIN public.ottoq_agent_principals a ON a.principal_id = g.principal_id), '[]'::jsonb));
END $fn$;

-- The plain-English refusal for a code that cannot be acted on, and the per-account throttle on wrong codes.
CREATE OR REPLACE FUNCTION public.ottoq_oauth_code_refusal(p_acct public.ottoq_owner_accounts, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_dev public.ottoq_oauth_device_codes;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_signed_in', 'message', 'Sign in first.');
  END IF;
  IF p_acct.account_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_linked',
      'message', 'This account is not set up to connect agents yet. Ask OTTOYARD to link it to your fleet.');
  END IF;
  IF (SELECT count(*) FROM public.ottoq_agent_call_ledger l
       WHERE l.called_at > now() - interval '15 minutes' AND l.tool IN ('oauth.device_lookup', 'oauth.device_decide')
         AND NOT l.ok AND l.detail ->> 'account_id' = p_acct.account_id::text) >= 10 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'too_many_tries',
      'message', 'Too many codes that did not match. Wait 15 minutes, then try again.');
  END IF;
  IF p_code IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'invalid_code',
      'message', 'That is not an OTTOYARD sign-in code. Codes are eight letters, like BCDF-GHJK.');
  END IF;
  SELECT * INTO v_dev FROM public.ottoq_oauth_device_codes d WHERE d.user_code = p_code;
  IF v_dev.device_code_hash IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'unknown_code',
      'message', 'No agent is waiting with that code. Check it, or ask your agent to start signing in again.');
  END IF;
  IF v_dev.status = 'pending' AND now() >= v_dev.expires_at THEN
    RETURN jsonb_build_object('ok', false, 'code', 'expired_code',
      'message', format('That code expired at %s. Ask your agent to start signing in again.', public.ottoq_owner_clock(v_dev.expires_at, false)));
  END IF;
  IF v_dev.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'already_answered',
      'message', CASE WHEN v_dev.status = 'denied' THEN 'That code was already denied.'
                      ELSE 'That code was already approved. Your agent finishes connecting by itself.' END);
  END IF;
  RETURN NULL;
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_oauth_device_lookup(p_user_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. The sign-in page, signed in, with the code an agent showed its person: which agent is asking, and what it will
   be able to do if approved. Changes nothing but the ledger. */
DECLARE
  t0      timestamptz := clock_timestamp();
  v_acct  public.ottoq_owner_accounts := public.ottoq_oauth_caller_account();
  v_code  text := public.ottoq_oauth_normalize_user_code(p_user_code);
  v_no    jsonb := public.ottoq_oauth_code_refusal(v_acct, v_code);
  v_dev   public.ottoq_oauth_device_codes;
  v_name  text;
BEGIN
  IF v_no IS NULL THEN
    SELECT * INTO v_dev FROM public.ottoq_oauth_device_codes d WHERE d.user_code = v_code;
    SELECT c.client_name INTO v_name FROM public.ottoq_oauth_clients c WHERE c.client_id = v_dev.client_id;
  END IF;
  PERFORM public.ottoq_oauth_ledger('oauth.device_lookup', 'web', v_no IS NULL, CASE WHEN v_no IS NULL THEN 200 ELSE 400 END,
    v_no ->> 'code', NULL, '{}'::jsonb,
    jsonb_strip_nulls(jsonb_build_object('account_id', v_acct.account_id, 'client_id', v_dev.client_id)), t0);
  IF v_no IS NOT NULL THEN
    RETURN v_no;
  END IF;
  RETURN jsonb_build_object('ok', true, 'code', v_code, 'agent', v_name, 'email', v_acct.email,
                            'expires_local', public.ottoq_owner_clock(v_dev.expires_at, false))
         || public.ottoq_oauth_consent(v_acct);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_oauth_device_decide(p_user_code text, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. The person approves or denies the agent waiting with this code. Approved, the agent's next poll of the token
   endpoint connects it to this account (one connection, its own tokens); denied, it is told so and nothing is made. */
DECLARE
  t0       timestamptz := clock_timestamp();
  v_acct   public.ottoq_owner_accounts := public.ottoq_oauth_caller_account();
  v_code   text := public.ottoq_oauth_normalize_user_code(p_user_code);
  v_no     jsonb := public.ottoq_oauth_code_refusal(v_acct, v_code);
  v_dec    text := lower(btrim(COALESCE(p_decision, '')));
  v_dev    public.ottoq_oauth_device_codes;
  v_name   text;
BEGIN
  IF v_no IS NULL AND v_dec NOT IN ('approve', 'deny') THEN
    v_no := jsonb_build_object('ok', false, 'code', 'invalid_decision', 'message', 'Choose approve or deny.');
  END IF;
  IF v_no IS NULL THEN
    UPDATE public.ottoq_oauth_device_codes d
       SET status = CASE WHEN v_dec = 'approve' THEN 'approved' ELSE 'denied' END,
           account_id = v_acct.account_id, decided_at = now()
     WHERE d.user_code = v_code AND d.status = 'pending' AND d.expires_at > now()
    RETURNING * INTO v_dev;
    IF v_dev.device_code_hash IS NULL THEN
      v_no := jsonb_build_object('ok', false, 'code', 'already_answered', 'message', 'That code was answered a moment ago.');
    ELSE
      SELECT c.client_name INTO v_name FROM public.ottoq_oauth_clients c WHERE c.client_id = v_dev.client_id;
    END IF;
  END IF;
  PERFORM public.ottoq_oauth_ledger('oauth.device_decide', 'web', v_no IS NULL, CASE WHEN v_no IS NULL THEN 200 ELSE 400 END,
    v_no ->> 'code', NULL, '{}'::jsonb,
    jsonb_strip_nulls(jsonb_build_object('account_id', v_acct.account_id, 'client_id', v_dev.client_id,
                                         'decision', CASE WHEN v_no IS NULL THEN v_dec END)), t0);
  IF v_no IS NOT NULL THEN
    RETURN v_no;
  END IF;
  RETURN jsonb_build_object('ok', true, 'outcome', CASE WHEN v_dec = 'approve' THEN 'approved' ELSE 'denied' END, 'agent', v_name,
    'message', CASE WHEN v_dec = 'approve'
      THEN format('Done. %s is connected to your OTTOYARD account. Go back to %s: it finishes connecting by itself within a few seconds.', v_name, v_name)
      ELSE format('Denied. %s was not connected, and it has been told so.', v_name) END);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_oauth_request_lookup(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. The sign-in page, for an agent that opened a browser: which agent is asking, and what it may do if approved. */
DECLARE
  v_acct public.ottoq_owner_accounts := public.ottoq_oauth_caller_account();
  v_req  public.ottoq_oauth_auth_requests;
  v_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_signed_in', 'message', 'Sign in first.');
  END IF;
  IF v_acct.account_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_linked',
      'message', 'This account is not set up to connect agents yet. Ask OTTOYARD to link it to your fleet.');
  END IF;
  SELECT * INTO v_req FROM public.ottoq_oauth_auth_requests r WHERE r.request_id = p_request_id;
  IF v_req.request_id IS NULL OR v_req.status <> 'pending' OR now() >= v_req.expires_at THEN
    RETURN jsonb_build_object('ok', false, 'code', 'stale_request',
      'message', 'This sign-in request is no longer waiting. Start connecting again from your agent.');
  END IF;
  SELECT c.client_name INTO v_name FROM public.ottoq_oauth_clients c WHERE c.client_id = v_req.client_id;
  RETURN jsonb_build_object('ok', true, 'agent', v_name, 'email', v_acct.email,
                            'returns_to', regexp_replace(v_req.redirect_uri, '^([a-z]+://[^/?#]+).*$', '\1'),
                            'expires_local', public.ottoq_owner_clock(v_req.expires_at, false))
         || public.ottoq_oauth_consent(v_acct);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_oauth_request_decide(p_request_id uuid, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. The person approves or denies a browser sign-in. Approved: a one-time code (five minutes, stored as SHA-256) in
   the redirect back to the agent, with its state and OTTOYARD's issuer (RFC 9207). Denied: error=access_denied. */
DECLARE
  t0     timestamptz := clock_timestamp();
  v_acct public.ottoq_owner_accounts := public.ottoq_oauth_caller_account();
  v_dec  text := lower(btrim(COALESCE(p_decision, '')));
  v_req  public.ottoq_oauth_auth_requests;
  v_code text;
  v_sep  text;
  v_to   text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_signed_in', 'message', 'Sign in first.');
  END IF;
  IF v_acct.account_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_linked',
      'message', 'This account is not set up to connect agents yet. Ask OTTOYARD to link it to your fleet.');
  END IF;
  IF v_dec NOT IN ('approve', 'deny') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'invalid_decision', 'message', 'Choose approve or deny.');
  END IF;
  v_code := CASE WHEN v_dec = 'approve' THEN public.ottoq_oauth_secret('oqg_') END;
  UPDATE public.ottoq_oauth_auth_requests r
     SET status = CASE WHEN v_dec = 'approve' THEN 'approved' ELSE 'denied' END,
         account_id = v_acct.account_id, decided_at = now(),
         code_hash = CASE WHEN v_dec = 'approve' THEN public.ottoq_oauth_sha256(v_code) END,
         code_expires_at = CASE WHEN v_dec = 'approve' THEN now() + interval '5 minutes' END
   WHERE r.request_id = p_request_id AND r.status = 'pending' AND r.expires_at > now()
  RETURNING * INTO v_req;
  IF v_req.request_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'stale_request',
      'message', 'This sign-in request is no longer waiting. Start connecting again from your agent.');
  END IF;
  v_sep := CASE WHEN position('?' IN v_req.redirect_uri) > 0 THEN '&' ELSE '?' END;
  v_to := v_req.redirect_uri || v_sep
          || CASE WHEN v_dec = 'approve' THEN 'code=' || v_code
                  ELSE 'error=access_denied&error_description=' || public.ottoq_oauth_urlencode('The account''s owner denied this agent.') END
          || COALESCE('&state=' || public.ottoq_oauth_urlencode(v_req.state), '')
          || '&iss=' || public.ottoq_oauth_urlencode(v_req.issuer);
  PERFORM public.ottoq_oauth_ledger('oauth.request_decide', 'web', true, 200, NULL, NULL, '{}'::jsonb,
    jsonb_build_object('account_id', v_acct.account_id, 'client_id', v_req.client_id, 'decision', v_dec), t0);
  RETURN jsonb_build_object('ok', true, 'outcome', CASE WHEN v_dec = 'approve' THEN 'approved' ELSE 'denied' END,
                            'redirect_to', v_to);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_account_disconnect(p_connection_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. The account's owner disconnects one of their agents: it can no longer read or change anything, its tokens stop
   at once, and refreshing them is refused. Final; signing in again makes a new connection. */
DECLARE
  t0     timestamptz := clock_timestamp();
  v_acct public.ottoq_owner_accounts := public.ottoq_oauth_caller_account();
  v_g    public.ottoq_oauth_grants;
  v_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_signed_in', 'message', 'Sign in first.');
  END IF;
  SELECT * INTO v_g FROM public.ottoq_oauth_grants g WHERE g.principal_id = p_connection_id AND g.account_id = auth.uid();
  IF v_g.principal_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_found', 'message', 'No agent of yours has that connection.');
  END IF;
  SELECT a.display_name INTO v_name FROM public.ottoq_agent_principals a WHERE a.principal_id = v_g.principal_id;
  PERFORM public.ottoq_oauth_close(v_g.principal_id, 'disconnected by the account''s owner');
  PERFORM public.ottoq_oauth_ledger('oauth.disconnect', 'web', true, 200, NULL, v_g.principal_id, '{}'::jsonb,
    jsonb_build_object('account_id', auth.uid(), 'client_id', v_g.client_id), t0);
  RETURN jsonb_build_object('ok', true, 'message',
    format('%s is disconnected from your OTTOYARD account. It can no longer read or change anything for your cars.', v_name));
END $fn$;

-- ══ 7. linking an account to its fleet (service_role, or the SQL editor) ════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_owner_account_link(p_email text, p_fleet_operator_id uuid, p_note text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. Let an OTTOYARD account (an existing Supabase Auth user of this project, found by email) connect its own agents
   to one fleet at the twin depot. Re-linking an account re-activates it. */
DECLARE
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_ids   uuid[];
  v_fleet text;
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_auth', 'message', 'This database has no auth.users.');
  END IF;
  EXECUTE 'SELECT array_agg(u.id) FROM auth.users u WHERE lower(u.email) = $1' INTO v_ids USING v_email;
  IF v_ids IS NULL OR cardinality(v_ids) <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_such_account',
      'message', format('No single OTTOYARD account has the email %s. Create the user in Supabase Auth first.', v_email));
  END IF;
  SELECT f.name INTO v_fleet FROM public.fleet_operators f WHERE f.id = p_fleet_operator_id AND f.is_active;
  IF v_fleet IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_such_fleet', 'message', 'No active fleet operator has that id.');
  END IF;
  INSERT INTO public.ottoq_owner_accounts (account_id, email, fleet_operator_id, note)
  VALUES (v_ids[1], v_email, p_fleet_operator_id, p_note)
  ON CONFLICT (account_id) DO UPDATE
     SET email = EXCLUDED.email, fleet_operator_id = EXCLUDED.fleet_operator_id, note = EXCLUDED.note,
         status = 'active', disabled_at = NULL;
  RETURN jsonb_build_object('ok', true, 'account_id', v_ids[1], 'email', v_email, 'fleet', v_fleet,
    'message', format('%s can now sign in at OTTOYARD and connect their own agents to %s.', v_email, v_fleet));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_account_unlink(p_email text, p_reason text DEFAULT 'unlinked')
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0660. Stop an account connecting agents, and close every agent it connected. */
DECLARE
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_acct  public.ottoq_owner_accounts;
  v_n     integer := 0;
  r       record;
BEGIN
  UPDATE public.ottoq_owner_accounts o SET status = 'disabled', disabled_at = now()
   WHERE o.email = v_email AND o.status = 'active'
  RETURNING * INTO v_acct;
  IF v_acct.account_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_linked', 'message', format('%s is not linked.', v_email));
  END IF;
  FOR r IN SELECT g.principal_id FROM public.ottoq_oauth_grants g WHERE g.account_id = v_acct.account_id LOOP
    IF public.ottoq_oauth_close(r.principal_id, left('account unlinked: ' || COALESCE(p_reason, ''), 200)) THEN
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'email', v_email, 'connections_closed', v_n);
END $fn$;
-- ══ 8. 0559/0607's resolver and refusal, 0607's welcome and whoami, 0608's two boards, extended ══════════════════════
--
-- Each is the measured live body (P1) plus the 0660 lines, which are marked '0660'. A signed-in agent's via is 'signed
-- in' wherever a passcode session's is 'passcode' and an issued key's 'key'.

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
  --: 0660: an agent signed in to an owner's OTTOYARD account presents a short-lived access token, never its principal's
  --: own token_hash (which nobody holds). The token names the connection; a disconnected connection reaches nothing.
  IF v.principal_id IS NULL THEN
    SELECT a.* INTO v
      FROM public.ottoq_oauth_tokens t
      JOIN public.ottoq_agent_principals a ON a.principal_id = t.principal_id
     WHERE t.token_hash = p_token_hash AND t.kind = 'access' AND t.revoked_at IS NULL AND t.expires_at > now()
       AND a.origin = 'oauth' AND a.status = 'active';
  END IF;
  RETURN v;
END $fn$;

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
    --: 0660: a signed-in agent's access token: expired (its agent renews it), revoked, or its connection closed
    (SELECT CASE
       WHEN a.status = 'revoked' THEN jsonb_build_object(
         'code', 'disconnected',
         'message', 'This agent is no longer connected to its OTTOYARD account: the account''s owner disconnected it. Sign in to OTTOYARD again to reconnect.')
       WHEN t.revoked_at IS NOT NULL THEN jsonb_build_object(
         'code', 'token_revoked',
         'message', 'This sign-in token was revoked. Use the refresh token for a new one, or sign in to OTTOYARD again.')
       WHEN t.expires_at <= now() THEN jsonb_build_object(
         'code', 'token_expired',
         'message', format('This sign-in token expired at %s. Use the refresh token for a new one, or sign in to OTTOYARD again.',
                           public.ottoq_owner_clock(t.expires_at, false)))
       END
       FROM public.ottoq_oauth_tokens t
       JOIN public.ottoq_agent_principals a ON a.principal_id = t.principal_id
      WHERE p_token_hash ~ '^[0-9a-f]{64}$' AND t.token_hash = p_token_hash AND t.kind = 'access'),
    CASE WHEN COALESCE(p_token_hash, '') = '' THEN jsonb_build_object(
           'code', 'unauthenticated',
           'message', 'Connect first: call welcome, then enter_passcode with OTTOYARD''s demo passcode, and send the session key it gives you with each call (or send an agent key as Authorization: Bearer).')
         ELSE jsonb_build_object('code', 'unauthenticated', 'message', 'The token is unknown or has been revoked.') END)
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_welcome_connected(p_agent public.ottoq_agent_principals)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0607. What a connected agent is told when it calls welcome (and, with its key added, what enter_passcode returns).
   0660: an agent signed in to an owner's account is told whose account it is, and that the connection outlasts runs. */
DECLARE
  v_depot text;
  v_fleet jsonb;
  v_run   jsonb;
  v_who   text := COALESCE(p_agent.display_name, p_agent.name);
  v_until text := public.ottoq_owner_clock(p_agent.expires_at, false);
  v_runl  text;
  v_try   text;
  v_email text;
BEGIN
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_agent.depot_id;
  IF p_agent.fleet_operator_id IS NOT NULL THEN
    v_fleet := public.ottoq_agent_fleet_line(p_agent.fleet_operator_id, p_agent.depot_id);
  END IF;
  IF p_agent.origin = 'oauth' THEN
    SELECT g.email INTO v_email FROM public.ottoq_oauth_grants g WHERE g.principal_id = p_agent.principal_id;
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
                      CASE p_agent.origin WHEN 'passcode' THEN ''
                        WHEN 'oauth' THEN format(', signed in to %s''s OTTOYARD account', COALESCE(v_email, 'an owner'))
                        ELSE ' (an agent key)' END)
      || CASE WHEN v_fleet IS NOT NULL THEN format(', for %s''s %s at %s', v_fleet ->> 'name', v_fleet ->> 'cars_phrase', COALESCE(v_depot, 'the depot'))
              ELSE format(', at %s', COALESCE(v_depot, 'the depot')) END
      || CASE WHEN p_agent.origin = 'passcode' THEN format(', until %s or until the demo run ends, whichever comes first', v_until) ELSE '' END
      || '.' || v_runl || COALESCE(' ' || v_try, ''),
    'run_line', btrim(v_runl),
    'try_line', v_try,
    'agent', jsonb_strip_nulls(jsonb_build_object('name', v_who,
                                                  'via', CASE p_agent.origin WHEN 'passcode' THEN 'passcode' WHEN 'oauth' THEN 'signed in' ELSE 'key' END,
                                                  'account', v_email)),
    'depot', jsonb_build_object('id', p_agent.depot_id, 'name', v_depot),
    'fleet', v_fleet,
    'session_expires_at', p_agent.expires_at,
    'session_expires_local', v_until,
    'run', jsonb_build_object('live', v_run IS NOT NULL, 'demo', v_run ->> 'run_by' = 'operator_demo',
                              'status', v_run ->> 'status',
                              'sim_clock_local', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)),
    'orchestrav', CASE WHEN p_agent.fleet_operator_id IS NOT NULL
                       THEN public.ottoq_owner_app_link((v_run ->> 'sim_run_id')::uuid, p_agent.fleet_operator_id, NULL) END,
    'rules', 'OTTO-Q checks every change against the owner''s contract and its own rules. A change that does not fit is refused in plain English, with the reason. One that fits is applied at OTTO-Q''s next tick and comes back with a confirmation code and an OrchestrAV link to relay to your person. Nothing you send moves a car. '
      || CASE WHEN p_agent.origin = 'oauth'
              THEN 'Everything you set lasts until the demo run ends; this connection stays until the account''s owner disconnects it.'
              ELSE 'Everything set in a session lasts until the demo run ends.' END));
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
                 --: 0660: or (an agent signed in to an owner's account) whose account, until its owner disconnects it
                 || jsonb_strip_nulls(jsonb_build_object(
                      'via', CASE p_agent.origin WHEN 'passcode' THEN 'passcode' WHEN 'oauth' THEN 'signed in' ELSE 'key' END,
                      'account', CASE WHEN p_agent.origin = 'oauth'
                                      THEN (SELECT g.email FROM public.ottoq_oauth_grants g WHERE g.principal_id = p_agent.principal_id) END,
                      'display_name', p_agent.display_name,
                      'expires_at', p_agent.expires_at,
                      'expires_local', public.ottoq_owner_clock(p_agent.expires_at, false),
                      'ends', CASE WHEN p_agent.origin = 'passcode'
                                   THEN 'at expires_local, or when the demo run ends, whichever comes first'
                                   WHEN p_agent.origin = 'oauth'
                                   THEN 'when the account''s owner disconnects this agent; its access token renews itself' END)),
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

CREATE OR REPLACE FUNCTION public.ottoq_owner_board(
    p_fleet_operator_id uuid,
    p_depot_id          uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    p_command_id        uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0606. OrchestrAV's view of what ONE owner's agent set: the settings in force on the live run, per car and as lists,
   the owner's recent commands with their plain-English receipts, and the command a receipt link names. Never every
   operator at once; never previews; never a token, principal id or call. Read-only (asserted before the grant).
   0608: each command also carries its confirmation code (0607), the agent's own name and how it got in. */
DECLARE
  v_name    text;
  v_run     jsonb;
  v_run_id  uuid;
  v_force   jsonb;
  v_by_car  jsonb;
  v_cmds    jsonb;
  v_hl      jsonb;
  v_ceiling numeric;
BEGIN
  IF p_fleet_operator_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fleet_operator_required', 'message', 'Name the fleet operator whose settings to read.');
  END IF;
  SELECT f.name INTO v_name FROM public.fleet_operators f WHERE f.id = p_fleet_operator_id;
  IF v_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_fleet_operator', 'message', 'No such fleet operator.');
  END IF;
  v_run := public.ottoq_agent_live_run(p_depot_id);
  v_run_id := (v_run ->> 'sim_run_id')::uuid;
  v_ceiling := COALESCE((public.ottoq_owner_contract(p_fleet_operator_id, COALESCE((v_run ->> 'sim_clock')::timestamptz, now())) ->> 'max_charge_pct')::numeric,
                        public.ottoq_default_target_soc());

  SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'setting_id', o.setting_id, 'kind', o.kind, 'vehicle_id', o.vehicle_id, 'vehicle', v.display_name,
           'charge_limit_pct', o.charge_limit_pct,
           'hold_until_sim', o.hold_until_sim, 'hold_until_local', public.ottoq_owner_clock(o.hold_until_sim, true, true),
           'service', o.service, 'service_name', c.display_name, 'when', o.service_when,
           'set_at', o.set_at, 'set_at_local', public.ottoq_owner_clock(o.set_at, false),
           'command_id', o.command_id, 'waiting_for_tick', o.pending_reconcile))
           ORDER BY o.kind, v.display_name, o.service), '[]'::jsonb)
    INTO v_force
    FROM public.ottoq_owner_settings o
    JOIN public.vehicles v ON v.id = o.vehicle_id
    LEFT JOIN public.service_cadence_policy c ON c.svc = o.service
   WHERE o.sim_run_id = v_run_id AND o.fleet_operator_id = p_fleet_operator_id AND o.depot_id = p_depot_id
     AND o.status = 'active';

  SELECT COALESCE(jsonb_object_agg(x.vehicle_id, x.card), '{}'::jsonb) INTO v_by_car
    FROM (SELECT s ->> 'vehicle_id' AS vehicle_id,
                 jsonb_strip_nulls(jsonb_build_object(
                   'charge_limit_pct', max((s ->> 'charge_limit_pct')::numeric),
                   'full_pct', v_ceiling,
                   'hold_until_sim', max(s ->> 'hold_until_sim'),
                   'hold_until_local', max(s ->> 'hold_until_local'),
                   'orders', jsonb_agg(jsonb_build_object('service', s ->> 'service', 'name', s ->> 'service_name',
                                                          'when', s ->> 'when'))
                             FILTER (WHERE s ->> 'kind' = 'service'))) AS card
            FROM jsonb_array_elements(v_force) s GROUP BY 1) x;

  SELECT COALESCE(jsonb_agg(q.j ORDER BY q.created_at DESC), '[]'::jsonb) INTO v_cmds
    FROM (SELECT c.created_at, jsonb_strip_nulls(jsonb_build_object(
                   'command_id', c.command_id, 'tool', c.tool, 'outcome', c.outcome, 'summary', c.summary,
                   'confirmation_code', CASE WHEN c.outcome = 'applied' THEN public.ottoq_owner_confirmation_code(c.command_id) END,
                   'agent', COALESCE(a.display_name, c.principal_name),
                   'agent_via', CASE a.origin WHEN 'passcode' THEN 'passcode' WHEN 'oauth' THEN 'signed in' ELSE 'key' END,
                   'cars', jsonb_array_length(c.vehicles),
                   'vehicle_ids', (SELECT jsonb_agg(x -> 'id') FROM jsonb_array_elements(c.vehicles) x),
                   'created_at', c.created_at, 'created_at_local', public.ottoq_owner_clock(c.created_at, false),
                   'sim_clock_local', public.ottoq_owner_clock(c.sim_clock, true),
                   'sim_run_id', c.sim_run_id, 'live_run', c.sim_run_id IS NOT DISTINCT FROM v_run_id,
                   'link', c.link, 'refusal', c.refusal,
                   'undone_at', c.undone_at, 'lifted_at', c.lifted_at, 'lifted_reason', c.lifted_reason)) AS j
            FROM public.ottoq_owner_commands c
            LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = c.principal_id
           WHERE c.fleet_operator_id = p_fleet_operator_id AND c.depot_id = p_depot_id AND c.outcome <> 'previewed'
           ORDER BY c.created_at DESC
           LIMIT 20) q;

  IF p_command_id IS NOT NULL THEN
    SELECT jsonb_strip_nulls(jsonb_build_object(
             'command_id', c.command_id, 'tool', c.tool, 'outcome', c.outcome, 'summary', c.summary,
             'confirmation_code', CASE WHEN c.outcome = 'applied' THEN public.ottoq_owner_confirmation_code(c.command_id) END,
             'agent', COALESCE(a.display_name, c.principal_name),
             'agent_via', CASE a.origin WHEN 'passcode' THEN 'passcode' WHEN 'oauth' THEN 'signed in' ELSE 'key' END,
             'vehicles', c.vehicles, 'effects', c.effects, 'args', c.args - 'idempotency_key',
             'created_at', c.created_at, 'created_at_local', public.ottoq_owner_clock(c.created_at, false),
             'sim_clock_local', public.ottoq_owner_clock(c.sim_clock, true),
             'sim_run_id', c.sim_run_id, 'live_run', c.sim_run_id IS NOT DISTINCT FROM v_run_id,
             'link', c.link, 'refusal', c.refusal,
             'undone_at', c.undone_at, 'lifted_at', c.lifted_at, 'lifted_reason', c.lifted_reason))
      INTO v_hl
      FROM public.ottoq_owner_commands c
      LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = c.principal_id
     WHERE c.command_id = p_command_id AND c.fleet_operator_id = p_fleet_operator_id AND c.outcome <> 'previewed';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'fleet_operator', jsonb_build_object('id', p_fleet_operator_id, 'name', v_name),
    'depot_id', p_depot_id,
    'run', CASE WHEN v_run IS NULL THEN NULL ELSE jsonb_build_object(
             'sim_run_id', v_run_id, 'status', v_run ->> 'status', 'demo', v_run ->> 'run_by' = 'operator_demo',
             'sim_clock', v_run -> 'sim_clock', 'sim_clock_local', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)) END,
    'full_pct', v_ceiling,
    'in_force', v_force,
    'by_vehicle', v_by_car,
    'counts', jsonb_build_object(
      'charge_limits', (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'charge_limit'),
      'holds',         (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'hold'),
      'orders',        (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'service')),
    'commands', v_cmds,
    'highlight', v_hl,
    'resets', 'Everything an agent sets lasts until the demo run ends or the agent undoes it; a stop or reset of the twin puts every car back to baseline.',
    'clocks', '"sim time" is SIMULATION time in Nashville local time; CT is real time.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_depot_owner_board(
    p_depot_id uuid    DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    p_limit    integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0608. What every owner's agent set at one depot, for OTTO-PULSE (the crew) and OTTO-TWIN (the 3D depot): settings in
   force on the live run per car and as a list, the agents connected, and the last owner commands with their receipts
   and confirmation codes. Never a key, a key prefix, a principal id, a passcode or a call. Read-only (asserted before
   the grant). */
DECLARE
  v_depot  text;
  v_run    jsonb;
  v_run_id uuid;
  v_clock  timestamptz;
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_force  jsonb;
  v_by_car jsonb;
  v_cmds   jsonb;
  v_agents jsonb;
BEGIN
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_depot_id;
  IF v_depot IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_depot', 'message', 'No such depot.');
  END IF;
  v_run := public.ottoq_agent_live_run(p_depot_id);
  v_run_id := (v_run ->> 'sim_run_id')::uuid;
  v_clock := COALESCE((v_run ->> 'sim_clock')::timestamptz, now());

  SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'setting_id', o.setting_id, 'kind', o.kind, 'vehicle_id', o.vehicle_id, 'vehicle', v.display_name,
           'fleet_operator_id', o.fleet_operator_id, 'fleet_operator', f.name,
           'charge_limit_pct', o.charge_limit_pct,
           'full_pct', COALESCE((public.ottoq_owner_contract(o.fleet_operator_id, v_clock) ->> 'max_charge_pct')::numeric,
                                public.ottoq_default_target_soc()),
           'hold_until_sim', o.hold_until_sim, 'hold_until_local', public.ottoq_owner_clock(o.hold_until_sim, true, true),
           'service', o.service, 'service_name', c.display_name, 'when', o.service_when,
           'set_at', o.set_at, 'set_at_local', public.ottoq_owner_clock(o.set_at, false),
           'command_id', o.command_id,
           'confirmation_code', public.ottoq_owner_confirmation_code(o.command_id),
           'agent', COALESCE(a.display_name, cmd.principal_name),
           'agent_via', CASE a.origin WHEN 'passcode' THEN 'passcode' WHEN 'oauth' THEN 'signed in' ELSE 'key' END,
           'waiting_for_tick', o.pending_reconcile))
           ORDER BY f.name, o.kind, v.display_name, o.service), '[]'::jsonb)
    INTO v_force
    FROM public.ottoq_owner_settings o
    JOIN public.vehicles v ON v.id = o.vehicle_id
    LEFT JOIN public.fleet_operators f ON f.id = o.fleet_operator_id
    LEFT JOIN public.service_cadence_policy c ON c.svc = o.service
    LEFT JOIN public.ottoq_owner_commands cmd ON cmd.command_id = o.command_id
    LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = cmd.principal_id
   WHERE o.sim_run_id = v_run_id AND o.depot_id = p_depot_id AND o.status = 'active';

  SELECT COALESCE(jsonb_object_agg(x.vehicle_id, x.card), '{}'::jsonb) INTO v_by_car
    FROM (SELECT s ->> 'vehicle_id' AS vehicle_id,
                 jsonb_strip_nulls(jsonb_build_object(
                   'vehicle', min(s ->> 'vehicle'),
                   'fleet_operator', min(s ->> 'fleet_operator'),
                   'charge_limit_pct', max((s ->> 'charge_limit_pct')::numeric),
                   'full_pct', max((s ->> 'full_pct')::numeric),
                   'hold_until_sim', max(s ->> 'hold_until_sim'),
                   'hold_until_local', max(s ->> 'hold_until_local'),
                   'orders', jsonb_agg(jsonb_build_object('service', s ->> 'service', 'name', s ->> 'service_name',
                                                          'when', s ->> 'when'))
                             FILTER (WHERE s ->> 'kind' = 'service'),
                   'agents', jsonb_agg(DISTINCT s ->> 'agent'),
                   'confirmation_codes', jsonb_agg(DISTINCT s ->> 'confirmation_code'),
                   'waiting_for_tick', bool_or((s ->> 'waiting_for_tick')::boolean))) AS card
            FROM jsonb_array_elements(v_force) s GROUP BY 1) x;

  SELECT COALESCE(jsonb_agg(q.j ORDER BY q.created_at DESC), '[]'::jsonb) INTO v_cmds
    FROM (SELECT c.created_at, jsonb_strip_nulls(jsonb_build_object(
                   'command_id', c.command_id, 'tool', c.tool, 'outcome', c.outcome,
                   'head', split_part(c.summary, E'\n', 1), 'summary', c.summary,
                   'confirmation_code', CASE WHEN c.outcome = 'applied' THEN public.ottoq_owner_confirmation_code(c.command_id) END,
                   'agent', COALESCE(a.display_name, c.principal_name),
                   'agent_via', CASE a.origin WHEN 'passcode' THEN 'passcode' WHEN 'oauth' THEN 'signed in' ELSE 'key' END,
                   'fleet_operator_id', c.fleet_operator_id, 'fleet_operator', f.name,
                   'cars', jsonb_array_length(c.vehicles),
                   'vehicles', (SELECT jsonb_agg(x -> 'name') FROM jsonb_array_elements(c.vehicles) x),
                   'vehicle_ids', (SELECT jsonb_agg(x -> 'id') FROM jsonb_array_elements(c.vehicles) x),
                   'created_at', c.created_at, 'created_at_local', public.ottoq_owner_clock(c.created_at, false),
                   'sim_clock', c.sim_clock, 'sim_clock_local', public.ottoq_owner_clock(c.sim_clock, true),
                   'sim_run_id', c.sim_run_id, 'live_run', c.sim_run_id IS NOT DISTINCT FROM v_run_id,
                   'link', c.link, 'refusal', c.refusal ->> 'message',
                   'undone_at', c.undone_at, 'lifted_at', c.lifted_at, 'lifted_reason', c.lifted_reason)) AS j
            FROM public.ottoq_owner_commands c
            LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = c.principal_id
            LEFT JOIN public.fleet_operators f ON f.id = c.fleet_operator_id
           WHERE c.depot_id = p_depot_id AND c.outcome <> 'previewed'
           ORDER BY c.created_at DESC
           LIMIT v_limit) q;

  SELECT COALESCE(jsonb_agg(z.j ORDER BY z.ord, z.at DESC), '[]'::jsonb) INTO v_agents
    FROM (SELECT CASE WHEN st.state = 'connected' THEN 0 ELSE 1 END AS ord, COALESCE(a.last_used_at, a.created_at) AS at,
                 jsonb_strip_nulls(jsonb_build_object(
                   'agent', COALESCE(a.display_name, a.name),
                   'via', CASE a.origin WHEN 'passcode' THEN 'passcode' WHEN 'oauth' THEN 'signed in' ELSE 'key' END,
                   'fleet_operator', f.name,
                   'state', st.state,
                   'connected_at_local', public.ottoq_owner_clock(a.created_at, false),
                   'last_seen_local', public.ottoq_owner_clock(a.last_used_at, false),
                   'expires_local', public.ottoq_owner_clock(a.expires_at, false),
                   'ended_local', public.ottoq_owner_clock(COALESCE(a.revoked_at, CASE WHEN st.state = 'expired' THEN a.expires_at END), false))) AS j
            FROM public.ottoq_agent_principals a
            LEFT JOIN public.fleet_operators f ON f.id = a.fleet_operator_id
            CROSS JOIN LATERAL (SELECT CASE
                WHEN a.status = 'active' AND a.origin = 'passcode' AND a.expires_at > now() THEN 'connected'
                WHEN a.status = 'active' AND a.origin IN ('issued', 'oauth') THEN 'connected'
                WHEN a.origin = 'oauth' AND a.status = 'revoked' THEN 'closed'
                WHEN a.origin = 'passcode' AND a.status = 'revoked' AND a.revoked_reason LIKE 'run\_ended%' THEN 'ended_with_run'
                WHEN a.origin = 'passcode' AND a.status = 'revoked' THEN 'closed'
                WHEN a.origin = 'passcode' THEN 'expired' END AS state) st
           WHERE a.depot_id = p_depot_id
             AND ((a.origin = 'passcode' AND a.status = 'active' AND a.expires_at > now())
                  OR (a.origin = 'issued' AND a.status = 'active' AND a.last_used_at > now() - interval '1 hour')
                  --: 0660: an agent signed in to an owner's account, while connected and used today, or just disconnected
                  OR (a.origin = 'oauth' AND a.status = 'active' AND COALESCE(a.last_used_at, a.created_at) > now() - interval '24 hours')
                  OR (a.origin = 'oauth' AND a.revoked_at BETWEEN now() - interval '2 hours' AND now())
                  OR (a.origin = 'passcode' AND COALESCE(a.revoked_at, a.expires_at) BETWEEN now() - interval '2 hours' AND now()))
           ORDER BY 1, 2 DESC
           LIMIT 20) z;

  RETURN jsonb_build_object(
    'ok', true,
    'depot', jsonb_build_object('id', p_depot_id, 'name', v_depot),
    'run', CASE WHEN v_run IS NULL THEN NULL ELSE jsonb_build_object(
             'sim_run_id', v_run_id, 'status', v_run ->> 'status', 'demo', v_run ->> 'run_by' = 'operator_demo',
             'sim_clock', v_run -> 'sim_clock', 'sim_clock_local', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)) END,
    'in_force', v_force,
    'by_vehicle', v_by_car,
    'commands', v_cmds,
    'agents', v_agents,
    'counts', jsonb_build_object(
      'charge_limits', (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'charge_limit'),
      'holds',         (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'hold'),
      'orders',        (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'service'),
      'cars',          (SELECT count(*) FROM jsonb_object_keys(v_by_car)),
      'agents_connected', (SELECT count(*) FROM jsonb_array_elements(v_agents) g WHERE g ->> 'state' = 'connected')),
    'resets', 'Everything an owner''s agent sets lasts until the demo run ends or the agent undoes it; a stop or reset of the twin puts every car back to baseline and ends every passcode session.',
    'clocks', '"sim time" is SIMULATION time in Nashville local time; CT is real time.');
END $fn$;

-- ══ 9. privileges: revoke everything new, grant exactly ═════════════════════════════════════════════════════════════
--
-- Supabase's default privileges make a new table readable, and a new function executable, by anon and authenticated.
-- Every table here is reachable only through the functions below (RLS on, no policy, no privilege for any client role
-- or service_role); the gateway's door is service_role only; the person's doors are authenticated only; the helpers
-- are executable by nobody but their owner. V1 asserts every bit.

ALTER TABLE public.ottoq_owner_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_oauth_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_oauth_device_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_oauth_auth_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_oauth_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_oauth_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_owner_accounts, public.ottoq_oauth_clients, public.ottoq_oauth_device_codes,
                    public.ottoq_oauth_auth_requests, public.ottoq_oauth_grants, public.ottoq_oauth_tokens
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION
    public.ottoq_oauth_keep_rows(),
    public.ottoq_oauth_sha256(text),
    public.ottoq_oauth_secret(text),
    public.ottoq_oauth_new_user_code(),
    public.ottoq_oauth_normalize_user_code(text),
    public.ottoq_oauth_urlencode(text),
    public.ottoq_oauth_redirect_ok(text),
    public.ottoq_oauth_redirect_matches(text, text[]),
    public.ottoq_oauth_ledger(text, text, boolean, integer, text, uuid, jsonb, jsonb, timestamptz),
    public.ottoq_oauth_throttled(text, text, integer, integer, interval),
    public.ottoq_oauth_error(integer, text, text),
    public.ottoq_oauth_caller_account(),
    public.ottoq_oauth_consent(public.ottoq_owner_accounts),
    public.ottoq_oauth_connect(uuid, text, text, text, text),
    public.ottoq_oauth_mint(uuid, text),
    public.ottoq_oauth_close(uuid, text),
    public.ottoq_oauth_register(jsonb, jsonb),
    public.ottoq_oauth_device_authorize(jsonb, jsonb),
    public.ottoq_oauth_authorize(jsonb, jsonb),
    public.ottoq_oauth_token(jsonb, jsonb),
    public.ottoq_oauth_revoke(jsonb, jsonb),
    public.ottoq_oauth_code_refusal(public.ottoq_owner_accounts, text),
    public.ottoq_agent_oauth(text, jsonb, jsonb),
    public.ottoq_account_me(),
    public.ottoq_oauth_device_lookup(text),
    public.ottoq_oauth_device_decide(text, text),
    public.ottoq_oauth_request_lookup(uuid),
    public.ottoq_oauth_request_decide(uuid, text),
    public.ottoq_account_disconnect(uuid),
    public.ottoq_owner_account_link(text, uuid, text),
    public.ottoq_owner_account_unlink(text, text)
  FROM PUBLIC, anon, authenticated, service_role;

--: the gateway's sign-in endpoints
GRANT EXECUTE ON FUNCTION public.ottoq_agent_oauth(text, jsonb, jsonb) TO service_role;
--: the sign-in page, as the signed-in person
GRANT EXECUTE ON FUNCTION
    public.ottoq_account_me(),
    public.ottoq_oauth_device_lookup(text),
    public.ottoq_oauth_device_decide(text, text),
    public.ottoq_oauth_request_lookup(uuid),
    public.ottoq_oauth_request_decide(uuid, text),
    public.ottoq_account_disconnect(uuid)
  TO authenticated;
--: linking an account to its fleet
GRANT EXECUTE ON FUNCTION public.ottoq_owner_account_link(text, uuid, text), public.ottoq_owner_account_unlink(text, text)
  TO service_role;

COMMENT ON FUNCTION public.ottoq_agent_oauth(text, jsonb, jsonb) IS
'0660. The one function the ottoq-agent-gateway''s sign-in endpoints call (service_role only): register (RFC 7591), device_authorize (RFC 8628), authorize (OAuth 2.1 code + PKCE S256), token (device_code, authorization_code, refresh_token), revoke (RFC 7009). Returns {ok, http_status, body} with body the exact OAuth answer. Mints and closes connections; reads no engine data and changes no engine state. Every call is ledgered (transport oauth).';
COMMENT ON FUNCTION public.ottoq_oauth_device_decide(text, text) IS
'0660. The signed-in owner (auth.uid(), never an argument) approves or denies the agent waiting with this user code. Called by OTTOYARD''s sign-in page.';
COMMENT ON FUNCTION public.ottoq_owner_account_link(text, uuid, text) IS
'0660. Let an existing Supabase Auth account (by email) sign in and connect its own agents to one fleet at the twin depot. service_role / SQL editor.';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════

-- V1: no client role reaches a new table; the gateway's door is service_role's alone; the person's doors are
--     authenticated's alone; the helpers are nobody's
DO $v1$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s on %s', r, t), ', ') INTO v_bad
    FROM unnest(ARRAY['public.ottoq_owner_accounts', 'public.ottoq_oauth_clients', 'public.ottoq_oauth_device_codes',
                      'public.ottoq_oauth_auth_requests', 'public.ottoq_oauth_grants', 'public.ottoq_oauth_tokens']) t,
         unnest(ARRAY['anon', 'authenticated', 'service_role']) r
   WHERE has_table_privilege(r, t, 'SELECT') OR has_table_privilege(r, t, 'INSERT')
      OR has_table_privilege(r, t, 'UPDATE') OR has_table_privilege(r, t, 'DELETE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0660 V1 FAILED: a client role reaches a sign-in table: %', v_bad;
  END IF;
  SELECT string_agg(format('%s %s %s', r, CASE WHEN has_function_privilege(r, f, 'EXECUTE') THEN 'can' ELSE 'cannot' END, f), '; ') INTO v_bad
    FROM (VALUES
      ('public.ottoq_agent_oauth(text,jsonb,jsonb)', 'service_role', true),
      ('public.ottoq_agent_oauth(text,jsonb,jsonb)', 'authenticated', false),
      ('public.ottoq_agent_oauth(text,jsonb,jsonb)', 'anon', false),
      ('public.ottoq_oauth_device_decide(text,text)', 'authenticated', true),
      ('public.ottoq_oauth_device_decide(text,text)', 'anon', false),
      ('public.ottoq_oauth_device_lookup(text)', 'authenticated', true),
      ('public.ottoq_oauth_device_lookup(text)', 'anon', false),
      ('public.ottoq_oauth_request_decide(uuid,text)', 'authenticated', true),
      ('public.ottoq_oauth_request_decide(uuid,text)', 'anon', false),
      ('public.ottoq_account_me()', 'authenticated', true),
      ('public.ottoq_account_me()', 'anon', false),
      ('public.ottoq_account_disconnect(uuid)', 'authenticated', true),
      ('public.ottoq_account_disconnect(uuid)', 'anon', false),
      ('public.ottoq_owner_account_link(text,uuid,text)', 'service_role', true),
      ('public.ottoq_owner_account_link(text,uuid,text)', 'authenticated', false),
      ('public.ottoq_owner_account_link(text,uuid,text)', 'anon', false),
      ('public.ottoq_oauth_token(jsonb,jsonb)', 'service_role', false),
      ('public.ottoq_oauth_token(jsonb,jsonb)', 'authenticated', false),
      ('public.ottoq_oauth_connect(uuid,text,text,text,text)', 'service_role', false),
      ('public.ottoq_oauth_connect(uuid,text,text,text,text)', 'authenticated', false),
      ('public.ottoq_oauth_mint(uuid,text)', 'service_role', false),
      ('public.ottoq_oauth_mint(uuid,text)', 'anon', false),
      ('public.ottoq_oauth_close(uuid,text)', 'authenticated', false),
      ('public.ottoq_oauth_secret(text)', 'anon', false)) x(f, r, want)
   WHERE has_function_privilege(r, f, 'EXECUTE') IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0660 V1 FAILED: %', v_bad;
  END IF;
END $v1$;

-- V2: the device sign-in end to end on this catalog, as a probe account, inside a block that rolls itself back: a
--     registration; a device request; a poll before approval (pending), the owner's approval by user code, the poll
--     that connects (a principal of origin oauth, an owner key's scope); the access token reaching the owner door
--     (whoami says "signed in" and whose account); a refresh that rotates; the first refresh token presented again after
--     the grace (the connection closes, and the access token stops). Passcode sessions and issued keys are untouched.
DO $v2$
DECLARE
  v_acct   uuid := gen_random_uuid();
  v_reg    jsonb;
  v_client text;
  v_dev    jsonb;
  v_t      jsonb;
  v_look   jsonb;
  v_dec    jsonb;
  v_tok    jsonb;
  v_who    jsonb;
  v_ref    jsonb;
  v_reuse  jsonb;
  v_after  jsonb;
  v_pid    uuid;
  v_msg    text;
BEGIN
  BEGIN
    INSERT INTO public.ottoq_owner_accounts (account_id, email, fleet_operator_id, note)
    VALUES (v_acct, 'probe-0660@ottoyard.invalid', '33333333-3333-3333-3333-333333333333', '0660 V2 probe, rolled back');
    v_reg := public.ottoq_agent_oauth('register',
      '{"client_name": "Probe Agent", "redirect_uris": ["http://127.0.0.1:8420/callback"], "grant_types": ["urn:ietf:params:oauth:grant-type:device_code", "refresh_token"], "response_types": [], "token_endpoint_auth_method": "none"}'::jsonb,
      '{"ip": "192.0.2.60"}'::jsonb);
    v_client := v_reg #>> '{body,client_id}';
    IF (v_reg ->> 'http_status')::int <> 201 OR v_client !~ '^oqc_[0-9a-f]{32}$' THEN
      RAISE EXCEPTION '0660 V2 FAILED (register): %', v_reg;
    END IF;
    v_dev := public.ottoq_agent_oauth('device_authorize',
      jsonb_build_object('client_id', v_client, 'resource', 'https://probe.invalid/account/mcp'), '{"ip": "192.0.2.60"}'::jsonb);
    IF (v_dev ->> 'http_status')::int <> 200 OR v_dev #>> '{body,user_code}' !~ '^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$'
       OR v_dev #>> '{body,device_code}' !~ '^oqd_[0-9a-f]{64}$' THEN
      RAISE EXCEPTION '0660 V2 FAILED (device request): %', v_dev;
    END IF;
    v_t := public.ottoq_agent_oauth('token', jsonb_build_object('grant_type', 'urn:ietf:params:oauth:grant-type:device_code',
      'client_id', v_client, 'device_code_hash', public.ottoq_oauth_sha256(v_dev #>> '{body,device_code}')), '{}'::jsonb);
    IF v_t #>> '{body,error}' IS DISTINCT FROM 'authorization_pending' THEN
      RAISE EXCEPTION '0660 V2 FAILED (poll before approval): %', v_t;
    END IF;
    -- the owner, signed in, with the code read off the agent's message (lower case and a space, as a person types it)
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_acct, 'role', 'authenticated')::text, true);
    v_look := public.ottoq_oauth_device_lookup(lower(replace(v_dev #>> '{body,user_code}', '-', ' ')));
    v_dec := public.ottoq_oauth_device_decide(v_dev #>> '{body,user_code}', 'approve');
    PERFORM set_config('request.jwt.claims', '', true);
    IF NOT (v_look ->> 'ok')::boolean OR v_look ->> 'agent' <> 'Probe Agent' OR v_dec ->> 'outcome' <> 'approved' THEN
      RAISE EXCEPTION '0660 V2 FAILED (approval): % / %', v_look, v_dec;
    END IF;
    UPDATE public.ottoq_oauth_device_codes d SET last_polled_at = now() - interval '10 seconds'
     WHERE d.user_code = v_dev #>> '{body,user_code}';
    v_tok := public.ottoq_agent_oauth('token', jsonb_build_object('grant_type', 'urn:ietf:params:oauth:grant-type:device_code',
      'client_id', v_client, 'device_code_hash', public.ottoq_oauth_sha256(v_dev #>> '{body,device_code}')), '{}'::jsonb);
    IF (v_tok ->> 'http_status')::int <> 200 OR v_tok #>> '{body,access_token}' !~ '^oqt_[0-9a-f]{64}$'
       OR v_tok #>> '{body,refresh_token}' !~ '^oqr_[0-9a-f]{64}$' OR v_tok #>> '{body,token_type}' <> 'Bearer' THEN
      RAISE EXCEPTION '0660 V2 FAILED (connect): %', v_tok;
    END IF;
    SELECT a.principal_id INTO v_pid FROM public.ottoq_agent_principals a JOIN public.ottoq_oauth_grants g USING (principal_id)
     WHERE g.account_id = v_acct AND a.origin = 'oauth' AND a.status = 'active' AND a.kind = 'personal'
       AND a.fleet_operator_id = '33333333-3333-3333-3333-333333333333'
       AND a.capabilities = ARRAY['note', 'owner_settings', 'read']::text[] AND a.display_name = 'Probe Agent';
    IF v_pid IS NULL THEN
      RAISE EXCEPTION '0660 V2 FAILED: no oauth principal with an owner key''s scope';
    END IF;
    v_who := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_tok #>> '{body,access_token}'), 'whoami', '{}'::jsonb, 'mcp', '{}'::jsonb);
    IF NOT (v_who ->> 'ok')::boolean OR v_who #>> '{data,principal,via}' <> 'signed in'
       OR v_who #>> '{data,principal,account}' <> 'probe-0660@ottoyard.invalid' THEN
      RAISE EXCEPTION '0660 V2 FAILED (the access token at the owner door): %', v_who;
    END IF;
    v_ref := public.ottoq_agent_oauth('token', jsonb_build_object('grant_type', 'refresh_token', 'client_id', v_client,
      'refresh_token_hash', public.ottoq_oauth_sha256(v_tok #>> '{body,refresh_token}')), '{}'::jsonb);
    IF (v_ref ->> 'http_status')::int <> 200 OR v_ref #>> '{body,refresh_token}' = v_tok #>> '{body,refresh_token}' THEN
      RAISE EXCEPTION '0660 V2 FAILED (refresh): %', v_ref;
    END IF;
    -- the first refresh token, presented again after the grace: the connection closes
    UPDATE public.ottoq_oauth_tokens t SET used_at = now() - interval '2 minutes'
     WHERE t.token_hash = public.ottoq_oauth_sha256(v_tok #>> '{body,refresh_token}');
    v_reuse := public.ottoq_agent_oauth('token', jsonb_build_object('grant_type', 'refresh_token', 'client_id', v_client,
      'refresh_token_hash', public.ottoq_oauth_sha256(v_tok #>> '{body,refresh_token}')), '{}'::jsonb);
    v_after := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_ref #>> '{body,access_token}'), 'whoami', '{}'::jsonb, 'mcp', '{}'::jsonb);
    IF v_reuse #>> '{body,error}' <> 'invalid_grant'
       OR (SELECT a.status FROM public.ottoq_agent_principals a WHERE a.principal_id = v_pid) <> 'revoked'
       OR (v_after ->> 'ok')::boolean OR (v_after ->> 'http_status')::int <> 401 THEN
      RAISE EXCEPTION '0660 V2 FAILED (reuse closes the connection): % / %', v_reuse, v_after;
    END IF;
    RAISE EXCEPTION '0660 V2 PASSED: registered %, user code %, connected as % (%), whoami via %, refreshed, reuse closed it (%)',
      v_client, v_dev #>> '{body,user_code}', v_pid, v_who #>> '{data,principal,account}', v_who #>> '{data,principal,via}',
      v_after #>> '{error,code}';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0660 V2 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0660 V2: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v2$;

-- Rollback: EXECUTE the six definitions in ottoq_schema_snapshots WHERE label = '0660_pre' as they are, revoke every
-- origin 'oauth' principal (ottoq_agent_revoke), and re-add 0607's two CHECKs once no oauth principal is active; the
-- six tables are then unread and can stay. DELETE this file's ottoq_cert_lineage row.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0660_an_owner_signs_in_and_connects_their_own_agent', false, false,
  'Agent door only (Chase 2026-10-10): an OTTOYARD account (this project''s Supabase Auth) linked to one fleet; OAuth 2.1 sign-in for its own agents (device code grant, authorization code + PKCE, refresh rotation, RFC 7591 registration, RFC 7009 revocation) through ottoq_agent_oauth (service_role) and the signed-in person''s doors (authenticated); a connection is an ottoq_agent_principals row of origin oauth with an owner key''s scope, reached by hashed access tokens. Six agent-door / owner-board bodies extended (resolve, unauthenticated, welcome_connected, whoami, owner_board, depot_owner_board). No engine function, no tick path, no engine table.',
  now());

COMMIT;
