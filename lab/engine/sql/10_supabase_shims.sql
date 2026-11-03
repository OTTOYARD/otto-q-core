-- lab/engine/sql/10_supabase_shims.sql
-- Supabase-compatibility shims for the OTTO-Q research lab (PostgreSQL 17).
-- Run once, as the lab superuser, in a fresh `ottoq_lab` database, BEFORE the
-- baseline. Every object here stands in for something Supabase provides and
-- this repository never creates. None of it reaches the network.
--
-- Shapes copied from production's catalog (read-only, Supabase MCP,
-- 2026-11-03 15:58-16:05 UTC = 9:58-10:05 AM CT):
--   extensions  btree_gist@extensions 1.7, http@extensions 1.6,
--               pg_cron@pg_catalog 1.6.4, pg_net@extensions 0.20.0,
--               pg_stat_statements@extensions 1.11, pgcrypto@extensions 1.3,
--               postgis@public 3.3.7, supabase_vault@vault 0.3.1,
--               uuid-ossp@extensions 1.1
--   search_path "$user", public, extensions      TimeZone UTC
--   database locale ICU 'en-US' (collation version 153.121, the same version
--   this lab's ICU 74 reports), LC_COLLATE/LC_CTYPE en_US.UTF-8,
--   extra_float_digits 0, jit off, lc_monetary/lc_numeric/lc_time en_US.UTF-8,
--   default_text_search_config pg_catalog.english (server configuration file)
--   net.http_get/http_post/http_delete signatures, net._http_response and
--   net.http_request_queue columns, vault.secrets / vault.decrypted_secrets
--   columns, auth.users columns, supabase_migrations.schema_migrations columns,
--   schema ACLs and postgres' default privileges in public.
--
-- What is real here and what is a stand-in:
--   REAL      uuid-ossp, pgcrypto, btree_gist, pg_stat_statements (schema
--             extensions), postgis (schema public), pg_cron (schema cron; the
--             server runs with cron.launch_active_jobs = off, so no job ever
--             launches -- see README).
--   STAND-IN  auth.*   Supabase's own definitions of uid()/role()/jwt()/email():
--                      they read the request.jwt.* settings, which nothing sets
--                      here, so each returns NULL. auth.users is empty.
--             net.*    pg_net's call surface. Each http_* function returns a
--                      fresh request id from a lab sequence and does NOTHING
--                      else: no queue row, no response row, no request.
--                      Readers of net._http_response see no response, which is
--                      what pg_net shows for a request still in flight.
--             vault.*  a plain table and view with vault's columns. It starts
--                      EMPTY and nothing is ever copied into it from
--                      production; a secret the lab itself creates through
--                      vault.create_secret is stored and read back in the
--                      clear (this is a local research copy, not a vault).
--   ABSENT    the http extension and pg_net itself (the lab has no HTTP client
--             at all), supabase_vault's encryption, GoTrue/Storage/Realtime/
--             GraphQL services and their schemas' contents.

-- ---------------------------------------------------------------- settings
DO $settings$
BEGIN
  -- the database this runs in (the build creates ottoq_lab; pg_cron below requires that
  -- it is also the server's cron.database_name)
  EXECUTE format('ALTER DATABASE %I SET search_path TO "$user", public, extensions', current_database());
  EXECUTE format('ALTER DATABASE %I SET timezone TO %L', current_database(), 'UTC');
  -- Session defaults production sets in its configuration file. extra_float_digits
  -- changes how a double precision prints as text, which several fingerprints hash.
  EXECUTE format('ALTER DATABASE %I SET extra_float_digits TO 0', current_database());
  EXECUTE format('ALTER DATABASE %I SET jit TO off', current_database());
  EXECUTE format('ALTER DATABASE %I SET lc_monetary TO %L', current_database(), 'en_US.UTF-8');
  EXECUTE format('ALTER DATABASE %I SET lc_numeric TO %L', current_database(), 'en_US.UTF-8');
  EXECUTE format('ALTER DATABASE %I SET lc_time TO %L', current_database(), 'en_US.UTF-8');
  EXECUTE format('ALTER DATABASE %I SET default_text_search_config TO %L', current_database(), 'pg_catalog.english');
  -- NOT copied: production's statement_timeout = 120000 (2 minutes, configuration
  -- file). The lab runs unpaced work in long transactions, so it keeps 0.
  EXECUTE format('ALTER ROLE postgres IN DATABASE %I SET search_path TO "$user", public, extensions', current_database());
END
$settings$;
SET search_path TO "$user", public, extensions;

-- ---------------------------------------------------------------- schemas
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS net;
CREATE SCHEMA IF NOT EXISTS vault;
CREATE SCHEMA IF NOT EXISTS supabase_migrations;

-- ---------------------------------------------------------------- extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"         WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto            WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS btree_gist          WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements  WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS postgis             WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_cron;            -- objects in schema cron

-- ---------------------------------------------------------------- schema ACLs
-- As production reads today (pg_namespace.nspacl).
GRANT USAGE ON SCHEMA public     TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL   ON SCHEMA extensions TO dashboard_user;
GRANT USAGE ON SCHEMA auth       TO anon, authenticated, service_role, dashboard_user;
GRANT USAGE ON SCHEMA storage    TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA net        TO PUBLIC, anon, authenticated, service_role, supabase_functions_admin;
GRANT USAGE ON SCHEMA vault      TO service_role;

-- ---------------------------------------------------------------- default privileges
-- Supabase's stock defaults for objects postgres creates in public (the
-- platform's init scripts). Production has since narrowed them -- 0658 revokes
-- anon's table and sequence defaults, 0701 (PENDING) would revoke more -- and
-- those revocations are left to the migrations that make them, so the lab
-- replays the history rather than starting at its end.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES    TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- auth
-- Supabase's definitions (supabase/postgres auth schema). With no
-- request.jwt.* setting in the session they all return NULL.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $f$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$f$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $f$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$f$;
CREATE OR REPLACE FUNCTION auth.email() RETURNS text LANGUAGE sql STABLE AS $f$
  select coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$f$;
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $f$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$f$;
GRANT EXECUTE ON FUNCTION auth.uid(), auth.role(), auth.email(), auth.jwt()
  TO anon, authenticated, service_role, dashboard_user;

-- auth.users: production's columns, no rows. (0700 reads it dynamically.)
CREATE TABLE IF NOT EXISTS auth.users (
  instance_id uuid,
  id uuid NOT NULL PRIMARY KEY,
  aud character varying(255),
  role character varying(255),
  email character varying(255),
  encrypted_password character varying(255),
  email_confirmed_at timestamp with time zone,
  invited_at timestamp with time zone,
  confirmation_token character varying(255),
  confirmation_sent_at timestamp with time zone,
  recovery_token character varying(255),
  recovery_sent_at timestamp with time zone,
  email_change_token_new character varying(255),
  email_change character varying(255),
  email_change_sent_at timestamp with time zone,
  last_sign_in_at timestamp with time zone,
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb,
  is_super_admin boolean,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  phone text DEFAULT NULL::character varying,
  phone_confirmed_at timestamp with time zone,
  phone_change text DEFAULT ''::character varying,
  phone_change_token character varying(255) DEFAULT ''::character varying,
  phone_change_sent_at timestamp with time zone,
  confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
  email_change_token_current character varying(255) DEFAULT ''::character varying,
  email_change_confirm_status smallint DEFAULT 0,
  banned_until timestamp with time zone,
  reauthentication_token character varying(255) DEFAULT ''::character varying,
  reauthentication_sent_at timestamp with time zone,
  is_sso_user boolean NOT NULL DEFAULT false,
  deleted_at timestamp with time zone,
  is_anonymous boolean NOT NULL DEFAULT false
);

-- ---------------------------------------------------------------- net (pg_net's surface, inert)
DO $t$ BEGIN
  IF to_regtype('net.http_method') IS NULL THEN
    CREATE TYPE net.http_method AS ENUM ('GET', 'POST', 'DELETE');
  END IF;
  IF to_regtype('net.request_status') IS NULL THEN
    CREATE TYPE net.request_status AS ENUM ('PENDING', 'SUCCESS', 'ERROR');
  END IF;
  IF to_regtype('net.http_response') IS NULL THEN
    CREATE TYPE net.http_response AS (status_code integer, headers jsonb, body text);
  END IF;
  IF to_regtype('net.http_response_result') IS NULL THEN
    CREATE TYPE net.http_response_result AS (status net.request_status, message text, response net.http_response);
  END IF;
END $t$;

CREATE SEQUENCE IF NOT EXISTS net.lab_request_id_seq;

-- The queue and response tables exist so that readers resolve; nothing writes them.
CREATE TABLE IF NOT EXISTS net.http_request_queue (
  id bigint NOT NULL DEFAULT nextval('net.lab_request_id_seq'::regclass),
  method net.http_method NOT NULL,
  url text NOT NULL,
  headers jsonb,
  body bytea,
  timeout_milliseconds integer NOT NULL
);
CREATE UNLOGGED TABLE IF NOT EXISTS net._http_response (
  id bigint,
  status_code integer,
  content_type text,
  headers jsonb,
  content text,
  timed_out boolean,
  error_msg text,
  created timestamp with time zone NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION net.http_get(url text, params jsonb DEFAULT '{}'::jsonb,
    headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000)
  RETURNS bigint LANGUAGE sql VOLATILE AS $f$
  -- LAB STUB: no request is made. A fresh id, and nothing else.
  SELECT nextval('net.lab_request_id_seq')
$f$;
CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}'::jsonb,
    params jsonb DEFAULT '{}'::jsonb, headers jsonb DEFAULT '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds integer DEFAULT 5000)
  RETURNS bigint LANGUAGE sql VOLATILE AS $f$
  -- LAB STUB: no request is made. A fresh id, and nothing else.
  SELECT nextval('net.lab_request_id_seq')
$f$;
CREATE OR REPLACE FUNCTION net.http_delete(url text, params jsonb DEFAULT '{}'::jsonb,
    headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000,
    body jsonb DEFAULT NULL::jsonb)
  RETURNS bigint LANGUAGE sql VOLATILE AS $f$
  -- LAB STUB: no request is made. A fresh id, and nothing else.
  SELECT nextval('net.lab_request_id_seq')
$f$;
CREATE OR REPLACE FUNCTION net.http_collect_response(request_id bigint, async boolean DEFAULT true)
  RETURNS net.http_response_result LANGUAGE sql VOLATILE AS $f$
  -- LAB STUB: there is never a response.
  SELECT ROW('ERROR'::net.request_status, 'lab: outbound HTTP is disabled', NULL::net.http_response)::net.http_response_result
$f$;
GRANT EXECUTE ON FUNCTION net.http_get(text, jsonb, jsonb, integer),
                          net.http_post(text, jsonb, jsonb, jsonb, integer),
                          net.http_delete(text, jsonb, jsonb, integer, jsonb),
                          net.http_collect_response(bigint, boolean)
  TO PUBLIC;
GRANT USAGE ON SEQUENCE net.lab_request_id_seq TO PUBLIC;

-- ---------------------------------------------------------------- vault (columns as production; no crypto)
CREATE TABLE IF NOT EXISTS vault.secrets (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name text,
  description text NOT NULL DEFAULT ''::text,
  secret text NOT NULL,
  key_id uuid,
  nonce bytea,
  created_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS secrets_name_idx ON vault.secrets (name) WHERE name IS NOT NULL;

CREATE OR REPLACE VIEW vault.decrypted_secrets AS
  SELECT s.id, s.name, s.description, s.secret,
         s.secret AS decrypted_secret,   -- lab: stored in the clear
         s.key_id, s.nonce, s.created_at, s.updated_at
    FROM vault.secrets s;

CREATE OR REPLACE FUNCTION vault.create_secret(new_secret text, new_name text DEFAULT NULL::text,
    new_description text DEFAULT ''::text, new_key_id uuid DEFAULT NULL::uuid)
  RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $f$
  INSERT INTO vault.secrets (secret, name, description, key_id)
  VALUES (new_secret, new_name, COALESCE(new_description, ''), new_key_id)
  RETURNING id
$f$;
CREATE OR REPLACE FUNCTION vault.update_secret(secret_id uuid, new_secret text DEFAULT NULL::text,
    new_name text DEFAULT NULL::text, new_description text DEFAULT NULL::text,
    new_key_id uuid DEFAULT NULL::uuid)
  RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $f$
  UPDATE vault.secrets
     SET secret = COALESCE(new_secret, secret),
         name = COALESCE(new_name, name),
         description = COALESCE(new_description, description),
         key_id = COALESCE(new_key_id, key_id),
         updated_at = CURRENT_TIMESTAMP
   WHERE id = secret_id
$f$;
REVOKE ALL ON vault.secrets, vault.decrypted_secrets FROM PUBLIC;
GRANT SELECT ON vault.decrypted_secrets TO service_role;
REVOKE ALL ON FUNCTION vault.create_secret(text, text, text, uuid),
                       vault.update_secret(uuid, text, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION vault.create_secret(text, text, text, uuid),
                          vault.update_secret(uuid, text, text, text, uuid) TO service_role;

-- ---------------------------------------------------------------- the migration ledger
-- Production's columns. The build writes one row per repo migration it applies
-- that carries a real ledger version (statements = the file's text), so
-- functions that read the ledger (the recert floor, 0625's regime scan) see the
-- lab's own lineage. The 621 pre-baseline rows and the 84 post-baseline rows
-- with no repo file are NOT here: the repo does not hold them.
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (
  version text NOT NULL PRIMARY KEY,
  statements text[],
  name text,
  created_by text,
  idempotency_key text,
  rollback text[]
);
