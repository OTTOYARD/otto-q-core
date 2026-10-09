-- migration-version: 20261009233223
-- migration-name:    source_keys_are_issued_by_the_platform_and_bind_a_depot_and_a_data_source
--
-- 0649  **A source key is issued only by the platform, and it binds the depot, the data source and the streams its
--        holder may send.** (G393; security items 3 and 4 of the twin data contract review, 2026-10-08. Chase,
--        2026-10-09 CT: "Start building.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (3) otto-q-api is deployed with verify_jwt off and answers POST /api/v1/ottow/api-keys with a fresh key for any
--       depot_id in the body, with no login (edge-functions/otto-q-api/index.ts, the route at line 8396). A key is what
--       makes a webhook source trusted: it sets the source and the depot the notifications door believes. GET lists any
--       depot's keys and DELETE /api-keys/:id revokes any key, also with no login. Measured: 1 key exists (2026-04-07,
--       oem_webhook, twin depot, never used); no app calls any of the three routes.
--   (4) ottoq-ingest takes the depot and the data source from the request body and stores any unknown source as
--       production. It needs a credential that carries both, and there is none to give it.
--
--   otto-q-api is one 399,237-byte file. Redeploying it means sending the whole file through the deploy tool, and a
--   transcription slip in 9,424 lines would break routes the OTTOYARD app uses (fleet/summary, ai/fleet-summary,
--   energy/history, visit-reports). So item 3 is closed where every one of those routes must write: the table.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottow_api_keys gains data_source (production | twin | replay | shadow, default production), streams (the
--       ottoq-ingest streams the key may send; NULL = none), revoked_at and revoke_reason. The one existing key reads
--       production / no streams, so it still works on otto-q-api's notifications door and nowhere else.
--   (b) public.ottoq_issue_source_key(depot, source, source_name, data_source, streams, allowed_platforms) mints
--       'ottow_' + 64 hex (the format otto-q-api already accepts), stores only its SHA-256, returns it once.
--       public.ottoq_revoke_source_key(key_id, reason) revokes. public.ottoq_source_key_check(key_hash, stream) is
--       what a door asks: the depot, data source and source name the key binds, or why not; it stamps last_used_at.
--       All three are SECURITY DEFINER and executable by service_role alone.
--   (c) Trigger ottow_api_keys_guard refuses every INSERT and UPDATE that does not come through the issuer or the
--       revoker, except an UPDATE that changes last_used_at alone (the doors stamp it). otto-q-api's mint route now
--       fails (its store ignores the error, so it answers 500); its revoke route changes nothing and still answers
--       {revoked: true}, a false answer to a route nobody calls, to be corrected when otto-q-api is next deployed.
--   (d) REVOKE SELECT, TRIGGER, REFERENCES ON ottow_api_keys FROM anon, authenticated (no policy let them read a row;
--       the grants were unused).
--
--   Issuance is not limited to the twin depot: a key is a credential, not a test, and the hardware lab depot already
--   takes real telemetry. Rule 8 governs where we test, and a key for another depot is still issued by a person.
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   No tick path reads or writes ottow_api_keys (no function, view or cron job names it). Every run, pair and dial
--   arm behaves byte for byte as before.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Needs a person at the connector's prompt, because it drops: the trigger ottow_api_keys_guard and its function,
--   the three functions in (b), the two constraints and four columns in (a); then
--   GRANT SELECT, TRIGGER, REFERENCES ON public.ottow_api_keys TO anon, authenticated.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0649 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: the table this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0648_the_command_dock_answers_only_the_platform') THEN
    RAISE EXCEPTION '0649 P1: 0648 is not classified; apply in order';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottow_api_keys'
                AND column_name IN ('data_source', 'streams', 'revoked_at', 'revoke_reason')) THEN
    RAISE EXCEPTION '0649 P1: ottow_api_keys already has a column this file adds';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.ottow_api_keys'::regclass AND NOT tgisinternal) THEN
    RAISE EXCEPTION '0649 P1: ottow_api_keys already has a trigger';
  END IF;
  IF to_regprocedure('public.ottoq_issue_source_key(uuid,text,text,text,text[],text[])') IS NOT NULL
     OR to_regprocedure('public.ottoq_revoke_source_key(uuid,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_source_key_check(text,text)') IS NOT NULL
     OR to_regprocedure('public.ottow_api_keys_guard()') IS NOT NULL THEN
    RAISE EXCEPTION '0649 P1: a function this file creates exists already';
  END IF;
  IF to_regprocedure('extensions.digest(text,text)') IS NULL OR to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL THEN
    RAISE EXCEPTION '0649 P1: pgcrypto (extensions.digest, extensions.gen_random_bytes) is missing';
  END IF;
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
       WHERE conname = 'ottow_api_keys_source_check' AND conrelid = 'public.ottow_api_keys'::regclass)
     IS DISTINCT FROM 'CHECK ((source = ANY (ARRAY[''oem_webhook''::text, ''fleet_api''::text, ''vehicle_telemetry''::text])))' THEN
    RAISE EXCEPTION '0649 P1: ottow_api_keys_source_check is not the constraint this file was written against';
  END IF;
END $premises$;

-- ── (a) what a key binds ──
ALTER TABLE public.ottow_api_keys
  ADD COLUMN data_source   text NOT NULL DEFAULT 'production',
  ADD COLUMN streams       text[],
  ADD COLUMN revoked_at    timestamptz,
  ADD COLUMN revoke_reason text;
ALTER TABLE public.ottow_api_keys
  ADD CONSTRAINT ottow_api_keys_data_source_check CHECK (data_source IN ('production', 'twin', 'replay', 'shadow')),
  ADD CONSTRAINT ottow_api_keys_streams_check CHECK (
    streams IS NULL OR (cardinality(streams) > 0 AND streams <@ ARRAY['energy', 'telemetry', 'ocpp', 'arrival', 'incident']::text[]));

COMMENT ON COLUMN public.ottow_api_keys.data_source IS
  '0649: the data_source every row this key sends is stamped with. Taken from the key, never from the request.';
COMMENT ON COLUMN public.ottow_api_keys.streams IS
  '0649: the ottoq-ingest streams this key may send (energy, telemetry, ocpp, arrival, incident). NULL = none.';

-- ── (c) the guard: only the issuer and the revoker write a key; a door may stamp last use ──
CREATE OR REPLACE FUNCTION public.ottow_api_keys_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  /* 0649 (G393): a source key is issued and revoked only through ottoq_issue_source_key / ottoq_revoke_source_key,
     which open this door for their own statement. A door that checks a key may stamp last_used_at and nothing else. */
  IF current_setting('ottoq.source_key_door', true) = 'on' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND (to_jsonb(NEW) - 'last_used_at') = (to_jsonb(OLD) - 'last_used_at') THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'ottow_api_keys: a source key is issued and revoked only by ottoq_issue_source_key / ottoq_revoke_source_key (0649)'
    USING ERRCODE = 'insufficient_privilege';
END $fn$;

CREATE TRIGGER ottow_api_keys_guard
  BEFORE INSERT OR UPDATE ON public.ottow_api_keys
  FOR EACH ROW EXECUTE FUNCTION public.ottow_api_keys_guard();

-- ── (b) the issuer ──
CREATE OR REPLACE FUNCTION public.ottoq_issue_source_key(
  p_depot_id uuid, p_source text, p_source_name text,
  p_data_source text DEFAULT 'production', p_streams text[] DEFAULT NULL, p_allowed_platforms text[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $fn$
DECLARE v_key text; v_id uuid; v_name text := btrim(p_source_name); v_ds text := COALESCE(p_data_source, 'production');
BEGIN
  /* 0649 (G393): the only way a source key is born. Returns the key once; only its SHA-256 is stored. */
  IF p_depot_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.depots WHERE id = p_depot_id) THEN
    RAISE EXCEPTION 'ottoq_issue_source_key: unknown depot %', p_depot_id;
  END IF;
  IF COALESCE(v_name, '') = '' THEN
    RAISE EXCEPTION 'ottoq_issue_source_key: source_name is required';
  END IF;
  v_key := 'ottow_' || encode(extensions.gen_random_bytes(32), 'hex');
  PERFORM set_config('ottoq.source_key_door', 'on', true);
  INSERT INTO public.ottow_api_keys (depot_id, key_hash, key_prefix, source, source_name, allowed_platforms, data_source, streams)
  VALUES (p_depot_id, encode(extensions.digest(v_key, 'sha256'), 'hex'), substr(v_key, 1, 14), p_source, v_name,
          p_allowed_platforms, v_ds, p_streams)
  RETURNING id INTO v_id;
  PERFORM set_config('ottoq.source_key_door', 'off', true);
  RETURN jsonb_build_object(
    'id', v_id, 'key', v_key, 'key_prefix', substr(v_key, 1, 14), 'depot_id', p_depot_id, 'source', p_source,
    'source_name', v_name, 'data_source', v_ds, 'streams', to_jsonb(p_streams),
    'warning', 'Shown once; only its SHA-256 is stored. Send it as the X-OTTO-Q-API-Key header.');
END $fn$;

-- ── (b) the revoker ──
CREATE OR REPLACE FUNCTION public.ottoq_revoke_source_key(p_key_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_row public.ottow_api_keys%ROWTYPE;
BEGIN
  /* 0649 (G393): the only way a source key is revoked. A reason is required and kept. */
  IF COALESCE(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'ottoq_revoke_source_key: a reason is required';
  END IF;
  PERFORM set_config('ottoq.source_key_door', 'on', true);
  UPDATE public.ottow_api_keys
     SET is_active = false, revoked_at = COALESCE(revoked_at, now()), revoke_reason = COALESCE(revoke_reason, btrim(p_reason))
   WHERE id = p_key_id
  RETURNING * INTO v_row;
  PERFORM set_config('ottoq.source_key_door', 'off', true);
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'ottoq_revoke_source_key: no key %', p_key_id;
  END IF;
  RETURN jsonb_build_object('id', v_row.id, 'key_prefix', v_row.key_prefix, 'revoked_at', v_row.revoked_at,
                            'reason', v_row.revoke_reason);
END $fn$;

-- ── (b) what a door asks ──
CREATE OR REPLACE FUNCTION public.ottoq_source_key_check(p_key_hash text, p_stream text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_row public.ottow_api_keys%ROWTYPE;
BEGIN
  /* 0649 (G393): the depot, data source and source a key binds, or why not. The door hashes the key it was handed
     (SHA-256, lowercase hex) and never passes the key itself. Stamps last_used_at on success. */
  SELECT * INTO v_row FROM public.ottow_api_keys WHERE key_hash = p_key_hash AND is_active LIMIT 1;
  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_or_revoked_key');
  END IF;
  IF p_stream IS NOT NULL AND NOT (p_stream = ANY (COALESCE(v_row.streams, ARRAY[]::text[]))) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'stream_not_allowed', 'key_prefix', v_row.key_prefix,
                              'streams', to_jsonb(v_row.streams));
  END IF;
  UPDATE public.ottow_api_keys SET last_used_at = now() WHERE id = v_row.id;
  RETURN jsonb_build_object('ok', true, 'key_id', v_row.id, 'key_prefix', v_row.key_prefix, 'depot_id', v_row.depot_id,
                            'source', v_row.source, 'source_name', v_row.source_name, 'data_source', v_row.data_source,
                            'streams', to_jsonb(v_row.streams));
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_issue_source_key(uuid,text,text,text,text[],text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_revoke_source_key(uuid,text)                       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_source_key_check(text,text)                        FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_issue_source_key(uuid,text,text,text,text[],text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_revoke_source_key(uuid,text)                       TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_source_key_check(text,text)                        TO service_role;

-- ── (d) unused grants ──
REVOKE SELECT, TRIGGER, REFERENCES ON public.ottow_api_keys FROM anon, authenticated;

-- ── V1: issue, check, refuse a direct write, revoke; the probe key rolls back with the sub-block ──
DO $v1$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  k jsonb; v_hash text; c_ok jsonb; c_stream jsonb; c_revoked jsonb;
  v_stored boolean; v_stamped boolean; v_insert_refused boolean := false; v_update_refused boolean := false;
  v_keys_before bigint; v_keys_after bigint;
BEGIN
  SELECT count(*) INTO v_keys_before FROM public.ottow_api_keys;
  BEGIN
    k := public.ottoq_issue_source_key(v_twin, 'fleet_api', 'probe_0649', 'twin', ARRAY['telemetry', 'arrival']);
    v_hash := encode(extensions.digest(k->>'key', 'sha256'), 'hex');
    v_stored := EXISTS (SELECT 1 FROM public.ottow_api_keys WHERE id = (k->>'id')::uuid AND key_hash = v_hash
                          AND key_prefix = left(k->>'key', 14) AND data_source = 'twin' AND streams = ARRAY['telemetry', 'arrival']);
    c_ok := public.ottoq_source_key_check(v_hash, 'telemetry');
    v_stamped := EXISTS (SELECT 1 FROM public.ottow_api_keys WHERE id = (k->>'id')::uuid AND last_used_at IS NOT NULL);
    c_stream := public.ottoq_source_key_check(v_hash, 'energy');
    -- a direct write, as otto-q-api's mint route makes one
    BEGIN
      INSERT INTO public.ottow_api_keys (depot_id, key_hash, key_prefix, source, source_name)
      VALUES (v_twin, md5('0649 probe'), 'ottow_00000000', 'fleet_api', 'probe_0649_direct');
    EXCEPTION WHEN insufficient_privilege THEN v_insert_refused := true;
    END;
    -- a direct edit of what a key binds
    BEGIN
      UPDATE public.ottow_api_keys SET data_source = 'production' WHERE id = (k->>'id')::uuid;
    EXCEPTION WHEN insufficient_privilege THEN v_update_refused := true;
    END;
    PERFORM public.ottoq_revoke_source_key((k->>'id')::uuid, '0649 V1 probe');
    c_revoked := public.ottoq_source_key_check(v_hash, 'telemetry');
    RAISE EXCEPTION '0649 V1 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0649 V1 PROBED' THEN RAISE EXCEPTION '0649 V1: the probe itself failed: %', v_msg; END IF;
  SELECT count(*) INTO v_keys_after FROM public.ottow_api_keys;

  IF (k->>'key') !~ '^ottow_[0-9a-f]{64}$' THEN RAISE EXCEPTION '0649 V1 FAILED: the key is not ottow_ + 64 hex'; END IF;
  IF NOT v_stored THEN RAISE EXCEPTION '0649 V1 FAILED: the stored hash, prefix or binding does not match the key issued'; END IF;
  IF NOT COALESCE((c_ok->>'ok')::boolean, false) OR c_ok->>'depot_id' <> v_twin::text OR c_ok->>'data_source' <> 'twin'
     OR c_ok->>'source_name' <> 'probe_0649' THEN
    RAISE EXCEPTION '0649 V1 FAILED: the check did not return the binding: %', c_ok;
  END IF;
  IF NOT v_stamped THEN RAISE EXCEPTION '0649 V1 FAILED: the check did not stamp last_used_at (the guard refused it?)'; END IF;
  IF COALESCE((c_stream->>'ok')::boolean, true) OR c_stream->>'reason' <> 'stream_not_allowed' THEN
    RAISE EXCEPTION '0649 V1 FAILED: a stream the key does not carry was let through: %', c_stream;
  END IF;
  IF NOT v_insert_refused THEN RAISE EXCEPTION '0649 V1 FAILED: a direct INSERT was not refused'; END IF;
  IF NOT v_update_refused THEN RAISE EXCEPTION '0649 V1 FAILED: a direct UPDATE of the binding was not refused'; END IF;
  IF COALESCE((c_revoked->>'ok')::boolean, true) OR c_revoked->>'reason' <> 'unknown_or_revoked_key' THEN
    RAISE EXCEPTION '0649 V1 FAILED: a revoked key still checks: %', c_revoked;
  END IF;
  IF v_keys_after <> v_keys_before THEN RAISE EXCEPTION '0649 V1 FAILED: the probe key did not roll back'; END IF;
  RAISE NOTICE '0649 V1 PASSED: issued ottow_+64hex, stored as its SHA-256 with its binding; the check returns depot, data source and source and stamps last use; a stream it does not carry, a direct INSERT, a direct UPDATE and a revoked key are refused; % key(s) before and after', v_keys_after;
END $v1$;

-- ── V2: who may call what ──
DO $v2$
DECLARE r record;
BEGIN
  FOR r IN SELECT unnest(ARRAY['public.ottoq_issue_source_key(uuid,text,text,text,text[],text[])',
                               'public.ottoq_revoke_source_key(uuid,text)',
                               'public.ottoq_source_key_check(text,text)'])::regprocedure AS f
  LOOP
    IF has_function_privilege('anon', r.f, 'EXECUTE') OR has_function_privilege('authenticated', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0649 V2 FAILED: % is executable by anon or authenticated', r.f;
    END IF;
    IF NOT has_function_privilege('service_role', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0649 V2 FAILED: service_role cannot execute %', r.f;
    END IF;
  END LOOP;
  IF has_table_privilege('anon', 'public.ottow_api_keys', 'SELECT') OR has_table_privilege('authenticated', 'public.ottow_api_keys', 'SELECT') THEN
    RAISE EXCEPTION '0649 V2 FAILED: anon or authenticated still holds SELECT on ottow_api_keys';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottow_api_keys WHERE data_source <> 'production' OR streams IS NOT NULL) THEN
    RAISE EXCEPTION '0649 V2 FAILED: an existing key changed its binding';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0649_source_keys_are_issued_by_the_platform_and_bind_a_depot_and_a_data_source', false, false,
  'G393 (security items 3, 4): ottow_api_keys gains data_source, streams, revoked_at, revoke_reason; '
  'ottoq_issue_source_key / ottoq_revoke_source_key / ottoq_source_key_check (service_role only); a guard trigger '
  'refuses every other INSERT/UPDATE but a last_used_at stamp, which closes otto-q-api''s open mint route. No tick path '
  'names the table. FALSE/FALSE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-09 23:32:23 UTC (6:32 PM CT), version 20261009233223 ════════════════════════════════════════
--   Claude, MCP apply_migration, the file as committed in ce417d8; the ledger's stored statement is that file byte for
--   byte (md5 ea0200f0daad83860469160f5ff28535, 18,907 characters, 19,663 bytes). P0, P1, V1, V2 passed in the apply's
--   transaction. Read after: 1 key, oem_webhook / production / no streams / active, as before. Probed from outside at
--   23:32 UTC: POST /functions/v1/otto-q-api/api/v1/ottow/api-keys with no credential answered HTTP 500 ("Cannot read
--   properties of null (reading 'id')") and wrote no key (still 1, newest 2026-04-07).
