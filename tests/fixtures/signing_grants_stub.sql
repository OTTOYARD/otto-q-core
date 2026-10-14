-- tests/fixtures/signing_grants_stub.sql — the signing key, its signers and the doors 0701 closes, in miniature.
--
-- What it reproduces from the live engine (measured 2026-10-13, db/migrations/0701 §1):
--   * postgres's per-schema default privileges in public grant EXECUTE on every new function to anon, authenticated and
--     service_role, and PostgreSQL's built-in default grants it to PUBLIC; no global default is set, and none for twin,
--     ottoq or extensions;
--   * public.ottoq_resolve_signing_secret, ottoq_sign_event, ottoq_sign_sdr and ottoq_sign_bundle with their LIVE bodies
--     (the resolver's pg_get_functiondef md5 is b92997a8bcbc41b3c825ad11407c1f66, as live) and live grants;
--   * the other fourteen signatures 0701 closes, with their live signatures and grants and stand-in bodies (three of
--     them were created after 0198 and still hold PUBLIC and anon, as live);
--   * one Vault-backed signing key, 'system:v1', behind a stand-in vault.decrypted_secrets;
--   * a SECURITY DEFINER engine caller that signs on behalf of a browser role (as ottoq_verify_event_signature does),
--     a cockpit read the public key keeps (ottoq_twin_appointments), and ottoq_assert_anon_rpc_surface with its live body.
-- Loads on a plain PostgreSQL 16 or 17 as a superuser named postgres.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $roles$;

CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA twin;
CREATE SCHEMA ottoq;
CREATE SCHEMA vault;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA twin, ottoq TO service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Supabase's default privileges for functions postgres creates in public (live: {postgres=X,anon=X,authenticated=X,
-- service_role=X}); PostgreSQL's own default adds PUBLIC
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- the engine's bookkeeping, as the migrations use it
CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY, taken_at timestamptz NOT NULL DEFAULT now(), label text NOT NULL,
  object_kind text NOT NULL, schema_name text NOT NULL, object_name text NOT NULL, definition text NOT NULL,
  def_md5 text NOT NULL);
CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean NOT NULL, forces_dial_restart boolean, note text NOT NULL,
  classified_at timestamptz NOT NULL);
CREATE TABLE public.stub_in_flight (n integer NOT NULL DEFAULT 0);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT true)
RETURNS integer LANGUAGE sql STABLE AS $f$ SELECT n FROM public.stub_in_flight LIMIT 1 $f$;
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0700_an_owner_signs_in_and_connects_their_own_agent', false, false, 'stub: 0701''s premise', now());
CREATE TABLE public.stub_writes (id bigserial PRIMARY KEY, note text);

-- the key registry and a stand-in Vault (live: one key, system:v1, vault-backed, active)
CREATE TABLE public.ottoq_signing_keys (key_id text PRIMARY KEY, secret_ref text, is_active boolean NOT NULL DEFAULT true);
INSERT INTO public.ottoq_signing_keys VALUES ('system:v1', 'vault:ottoq_signing_system_v1', true);
CREATE TABLE vault.secrets (name text PRIMARY KEY, secret text NOT NULL);
INSERT INTO vault.secrets VALUES ('ottoq_signing_system_v1', 'stub-signing-secret-0701'),
                                 ('nvidia_api_key', 'stub-other-secret');
CREATE VIEW vault.decrypted_secrets AS SELECT s.name, s.secret AS decrypted_secret FROM vault.secrets s;

-- ── the resolver, byte for byte as live (pg_get_functiondef md5 b92997a8bcbc41b3c825ad11407c1f66) ──
CREATE OR REPLACE FUNCTION public.ottoq_resolve_signing_secret(p_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_secret   TEXT;
  v_ref      TEXT;
  v_guc_name TEXT := 'ottoq.signing_secret_' || replace(p_key_id, ':', '_');
BEGIN
  -- 1. GUC override (set by edge function on connection). Also the cache slot.
  v_secret := current_setting(v_guc_name, TRUE);
  IF v_secret IS NOT NULL AND length(v_secret) > 0 THEN
    RETURN v_secret;
  END IF;

  -- 2. Default GUC for the system key (allows bootstrap)
  IF p_key_id = 'system:v1' THEN
    v_secret := current_setting('ottoq.signing_secret_default', TRUE);
    IF v_secret IS NOT NULL AND length(v_secret) > 0 THEN
      RETURN v_secret;
    END IF;
  END IF;

  -- 3. Resolve through the key registry. Only 'vault:<name>' is resolvable from
  --    inside the database; 'env:<NAME>' is by definition not visible here.
  SELECT k.secret_ref INTO v_ref
    FROM ottoq_signing_keys k
   WHERE k.key_id = p_key_id
     AND k.is_active
   LIMIT 1;

  IF v_ref IS NOT NULL AND v_ref LIKE 'vault:%' THEN
    BEGIN
      SELECT s.decrypted_secret INTO v_secret
        FROM vault.decrypted_secrets s
       WHERE s.name = substring(v_ref FROM 7)
       LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      -- Vault unreadable for this role: fall through to NULL rather than break
      -- event recording. Recording must never fail because signing failed.
      v_secret := NULL;
    END;

    IF v_secret IS NOT NULL AND length(v_secret) > 0 THEN
      -- Cache for the rest of this session so the hot writer does not decrypt
      -- once per event. Session-scoped, so it survives per-tick COMMITs.
      PERFORM set_config(v_guc_name, v_secret, false);
      RETURN v_secret;
    END IF;
  END IF;

  -- 4. No secret available: signing is skipped, the event is still recorded.
  RETURN NULL;
END;
$function$;

-- ── the three signers, bodies as live ──
CREATE OR REPLACE FUNCTION public.ottoq_sign_event(p_event_id uuid, p_occurred_at timestamp with time zone, p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid, p_payload_hash text, p_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_secret TEXT;
  v_canonical TEXT;
BEGIN
  v_secret := ottoq_resolve_signing_secret(p_key_id);
  IF v_secret IS NULL THEN
    RETURN NULL;
  END IF;

  v_canonical := concat_ws('|',
    p_event_id::text,
    to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    p_actor_type,
    p_event_type,
    p_entity_type,
    COALESCE(p_entity_id::text, ''),
    p_payload_hash
  );

  RETURN encode(hmac(v_canonical, v_secret, 'sha256'), 'hex');
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_sign_sdr(p_sdr_id uuid, p_ended_at timestamp with time zone, p_vehicle_id uuid, p_operation_code text, p_payload_hash text, p_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_secret text;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);
  v_secret := ottoq_resolve_signing_secret(p_key_id);
  IF v_secret IS NULL THEN RETURN NULL; END IF;
  RETURN encode(hmac(
    concat_ws('|',
      p_sdr_id::text,
      to_char(p_ended_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      COALESCE(p_vehicle_id::text, ''),
      p_operation_code,
      p_payload_hash),
    v_secret, 'sha256'), 'hex');
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_sign_bundle(p_bundle_id uuid, p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_sha256 text, p_signing_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_secret      TEXT;
  v_canonical   TEXT;
BEGIN
  v_secret := ottoq_resolve_signing_secret(p_signing_key_id);
  IF v_secret IS NULL THEN
    RETURN NULL;
  END IF;
  v_canonical := concat_ws('|',
    p_bundle_id::text,
    to_char(p_window_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    to_char(p_window_end   AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    p_sha256
  );
  RETURN encode(hmac(v_canonical, v_secret, 'sha256'), 'hex');
END;
$function$;

-- ── the other fourteen signatures 0701 closes: live signatures and return types, stand-in bodies ──
CREATE FUNCTION public.ottoq_oem_deliver_live(p_webhook_id uuid, p_sim_run_id uuid, p_vehicle_id uuid, p_fleet_op uuid, p_oem text,
  p_endpoint text, p_payload jsonb, p_secret_ref text, p_sim_clock_now timestamptz)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $f$ BEGIN INSERT INTO public.stub_writes (note) VALUES ('deliver_live'); RETURN 1; END $f$;
CREATE FUNCTION public.ottoq_energy_mpc_replan(uuid, uuid, integer, numeric, numeric[], integer, text, text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $f$ SELECT '{}'::jsonb $f$;
CREATE FUNCTION public.ottoq_energy_mpc_replan(uuid, uuid, integer, numeric, numeric[], integer, text, text, timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $f$ SELECT '{}'::jsonb $f$;
CREATE FUNCTION public.ottoq_energy_mpc_replan(uuid, uuid, integer, numeric, numeric[], integer, text, text, timestamptz, uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $f$ SELECT '{}'::jsonb $f$;
CREATE FUNCTION public.ottoq_purge_prior_runs(p_keep_run uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $f$ BEGIN DELETE FROM public.stub_writes; RETURN '{}'::jsonb; END $f$;
CREATE FUNCTION public.ottoq_start_busy_run(p_speed numeric, p_days integer, p_seed bigint)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $f$ SELECT '{}'::jsonb $f$;
CREATE FUNCTION public.ottoq_start_busy_run_once(p_tag text, p_speed numeric, p_days integer, p_seed bigint)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $f$ SELECT public.ottoq_start_busy_run(p_speed, p_days, p_seed) $f$;
CREATE FUNCTION public.ottoq_release_unusable_reservations(p_depot uuid, p_clock timestamptz, p_run uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $f$ SELECT '{}'::jsonb $f$;
CREATE FUNCTION public.ottoq_fit_charge_fault_model(p_depot uuid, p_through timestamptz, p_window interval, p_note text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
AS $f$ BEGIN INSERT INTO public.stub_writes (note) VALUES ('fit'); RETURN 1; END $f$;
CREATE FUNCTION public.ottoq_record_event(text, text, text, uuid, jsonb, text, jsonb, uuid, uuid, jsonb, jsonb, text, uuid, uuid,
  uuid, uuid, uuid, text, integer, text, text, text, uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $f$ SELECT NULL::uuid $f$;
CREATE FUNCTION public.ottoq_emit_sdr(text, text, text, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, timestamptz,
  numeric, numeric, text)
RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $f$ SELECT NULL::uuid $f$;
CREATE FUNCTION public.ottoq_generate_audit_bundle(uuid, uuid[], text, timestamptz, timestamptz, text, text, bigint, text, text,
  text, text, timestamptz)
RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $f$ SELECT NULL::uuid $f$;
CREATE FUNCTION public.ottoq_complete_audit_report(uuid, jsonb, bigint, bigint, bigint, bigint, bigint, bigint, bigint, boolean,
  numeric, text)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $f$ SELECT $f$;
CREATE FUNCTION public.ottoq_probe_task_completion(uuid, uuid, uuid, text, timestamptz, timestamptz)
RETURNS TABLE(rule_code text, passed boolean) LANGUAGE sql SECURITY DEFINER AS $f$ SELECT 'HW.006'::text, true $f$;

-- live grants: fifteen closed to PUBLIC and anon by 0198 (authenticated re-granted by it), three still holding them
DO $acl$
DECLARE s text;
BEGIN
  FOREACH s IN ARRAY ARRAY[
    'public.ottoq_resolve_signing_secret(text)',
    'public.ottoq_sign_event(uuid,timestamptz,text,text,text,uuid,text,text)',
    'public.ottoq_sign_sdr(uuid,timestamptz,uuid,text,text,text)',
    'public.ottoq_sign_bundle(uuid,timestamptz,timestamptz,text,text)',
    'public.ottoq_oem_deliver_live(uuid,uuid,uuid,uuid,text,text,jsonb,text,timestamptz)',
    'public.ottoq_energy_mpc_replan(uuid,uuid,integer,numeric,numeric[],integer,text,text)',
    'public.ottoq_energy_mpc_replan(uuid,uuid,integer,numeric,numeric[],integer,text,text,timestamptz)',
    'public.ottoq_energy_mpc_replan(uuid,uuid,integer,numeric,numeric[],integer,text,text,timestamptz,uuid)',
    'public.ottoq_purge_prior_runs(uuid)',
    'public.ottoq_start_busy_run(numeric,integer,bigint)',
    'public.ottoq_start_busy_run_once(text,numeric,integer,bigint)',
    'public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,integer,text,text,text,uuid)',
    'public.ottoq_emit_sdr(text,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,numeric,text)',
    'public.ottoq_generate_audit_bundle(uuid,uuid[],text,timestamptz,timestamptz,text,text,bigint,text,text,text,text,timestamptz)',
    'public.ottoq_complete_audit_report(uuid,jsonb,bigint,bigint,bigint,bigint,bigint,bigint,bigint,boolean,numeric,text)'] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', s);
  END LOOP;
END $acl$;

-- a SECURITY DEFINER engine caller a browser role keeps (as ottoq_verify_event_signature: it signs to compare)
CREATE FUNCTION public.ottoq_verify_event_signature(p_event_id uuid)
RETURNS TABLE(event_id uuid, computed text) LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $f$ SELECT p_event_id, public.ottoq_sign_event(p_event_id, '2026-10-13 00:00:00+00', 'system', 'probe', 'probe', NULL,
                                                  md5('stub'), 'system:v1') $f$;
REVOKE EXECUTE ON FUNCTION public.ottoq_verify_event_signature(uuid) FROM PUBLIC, anon;
-- the twin app's appointment card, which the public key keeps (live: VOLATILE SECURITY DEFINER, anon and authenticated)
CREATE FUNCTION public.ottoq_twin_appointments(p_sim_run_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $f$ SELECT '[]'::jsonb $f$;
REVOKE EXECUTE ON FUNCTION public.ottoq_twin_appointments(uuid) FROM PUBLIC;

-- the standing gate, live body
CREATE OR REPLACE FUNCTION public.ottoq_assert_anon_rpc_surface()
 RETURNS TABLE(proname text, problem text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p.proname::text,
         'granted to anon but contains a write statement'
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND has_function_privilege('anon', p.oid, 'EXECUTE')
     AND p.prosecdef
     AND p.prosrc ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\()'
  UNION ALL
  SELECT p.proname::text,
         'mutating cockpit RPC must stay behind the otto-twin-control edge function'
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('ottoq_hw_recall_vehicle','ottoq_hw_set_return_threshold','ottoq_sim_jump_forward',
                       'ottoq_start_demo_run','ottoq_sim_stop_and_reset','ottoq_set_playback','ottoq_decide_tick')
     AND has_function_privilege('anon', p.oid, 'EXECUTE')
$function$;
