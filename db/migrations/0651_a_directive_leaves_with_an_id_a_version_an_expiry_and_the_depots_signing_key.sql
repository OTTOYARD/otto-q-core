-- migration-version: 20261010005934
-- migration-name:    a_directive_leaves_with_an_id_a_version_an_expiry_and_the_depots_signing_key
--
-- 0651  **What OTTO-Q asks of a car leaves the depot as a contract directive: with an id, a version, the directive it
--        replaced, an expiry and an ack deadline, and a key to sign it with.** (Step 3 of the twin data contract
--        review, 2026-10-08; contract/README.md rules 3, 4, 7 and 8. Chase, 2026-10-09 CT: "Start building.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_vehicle_commands is the engine's queue of what it asks of each car. A row has no expiry, no version and no
--   signature, the old dock (0648) hands any operator's commands to whoever asks first, and 0 of 114,733 commands were
--   ever delivered outside (the review, measured 2026-10-08). The contract says what a directive is; this renders a
--   command as one and gives an operator only its own.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottoq.ottoq_v2_directive_event(command_id): the command as an unsigned CloudEvent of the contract.
--         begin_charge                               -> directive.charge.plan: the stall, its charger's OCPP identifier,
--                                                       target_soc_pct = ottoq_effective_target_soc_at (the owner's,
--                                                       100 unless the owner set less: CLAUDE.md rule 9), and a one-
--                                                       period OCPP schedule at the requested kW (or the stall's
--                                                       connector maximum). No plan is rendered at zero watts: a car
--                                                       is never told to charge at nothing.
--         proceed_to_stall, stage, enter_wash,       -> directive.stall.assignment: the stall and its type, a purpose
--         enter_service, hold                           (staging, service or hold), and the window the calendar holds
--                                                       the stall for the car where a booking says so.
--         dispatch, and a command OTTO-Q refused     -> nothing: leaving is the operator's act, and a pre-flight
--         before it left (0088)                         refusal never reached anyone.
--       Every directive: directive_id = command_id; version 1 (the engine issues a new command, not a new version,
--       when it changes its mind); supersedes = the car's newest earlier directive still open when this one was issued;
--       issued_at = valid_from = the command's issue time on its own clock; ack_deadline one tick later; expires_at two
--       ticks later, the hold window 0064 already gives a stall so the hold outlives the command it serves. A tick is
--       the run's tick_interval_seconds x time_scale, or 120 seconds (production's tick) for a command with no run.
--   (b) public.ottoq_v2_read_directives(key_hash, after, limit, mark_delivered): the outbox. A key reads the
--       directives for its own fleets' cars at its own depot, of its own data source (and, for a twin key, the depot's
--       running run), after a cursor (command_seq), oldest first, at most 500. It stamps delivered_at / delivered_to
--       on first read unless told not to. No delivery column is in the determinism pair's command atom (h_cmd digests
--       issued_at, vehicle, type, stall, status, reason_code), so a read moves no certified digest.
--   (c) public.ottoq_v2_signing_keys + ottoq_v2_signing_key_store / ottoq_v2_signing_key_current / ottoq_v2_jwks.
--       The edge function makes the depot's Ed25519 key itself on first use and stores the private half in Supabase
--       Vault through _store, so it is never handed to anyone, this file included. One key is active at a time.
--       _jwks lists the public halves (active, and retired in the last 7 days, so a rotation overlaps).
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   Nothing in a tick calls any of it. The only engine rows it writes are delivered_at / delivered_to on commands an
--   operator reads, outside every certified digest. The old dock (0648) is untouched. V1 renders existing commands
--   read-only and runs the outbox and the key store inside a sub-block that rolls back.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Nothing existing changes. Dropping the table and the six functions needs a person at the connector's prompt; a
--   Vault secret named ottoq_v2_signing_key:<kid> is deleted with vault.secrets.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0651 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0650_the_v2_door_takes_cloudevents_keeps_their_time_drops_duplicates_and_orders_them') THEN
    RAISE EXCEPTION '0651 P1: 0650 is not classified; apply in order';
  END IF;
  IF to_regclass('public.ottoq_v2_signing_keys') IS NOT NULL
     OR to_regprocedure('public.ottoq_v2_read_directives(text,bigint,integer,boolean)') IS NOT NULL
     OR to_regprocedure('ottoq.ottoq_v2_directive_event(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0651 P1: an object this file creates exists already';
  END IF;
  IF to_regprocedure('public.ottoq_effective_target_soc_at(uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0651 P1: ottoq_effective_target_soc_at(uuid,timestamptz) is missing (rule 9''s one answer)';
  END IF;
  IF to_regprocedure('vault.create_secret(text,text,text,uuid)') IS NULL OR to_regclass('vault.decrypted_secrets') IS NULL THEN
    RAISE EXCEPTION '0651 P1: Supabase Vault (vault.create_secret, vault.decrypted_secrets) is missing';
  END IF;
  -- the columns the outbox reads and stamps
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_vehicle_commands'
        AND column_name IN ('command_seq', 'delivered_at', 'delivered_to', 'data_source', 'confirmed_by', 'payload')) <> 6 THEN
    RAISE EXCEPTION '0651 P1: ottoq_vehicle_commands lacks a column the outbox reads';
  END IF;
END $premises$;

-- ── a time as the contract writes it ──
CREATE OR REPLACE FUNCTION ottoq.ottoq_v2_rfc3339(p timestamptz)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $fn$
  /* 0651: RFC 3339 in UTC with a Z, microseconds kept. */
  SELECT to_char(p AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
$fn$;

-- ── (a) a command as a directive ──
CREATE OR REPLACE FUNCTION ottoq.ottoq_v2_directive_event(p_command_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  c public.ottoq_vehicle_commands%ROWTYPE;
  v_ref text; s public.stalls%ROWTYPE; v_tick numeric; v_type text; v_purpose text;
  v_expires timestamptz; v_ack timestamptz; v_prev uuid; v_ws timestamptz; v_we timestamptz;
  v_kw numeric; v_evse text; v_header jsonb; v_data jsonb;
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
BEGIN
  /* 0651: contract/README.md, rules 3 and 7. NULL when the command is not a directive (dispatch: leaving is the
     operator's act), never left the depot (0088's pre-flight refusal), or cannot be rendered truthfully. */
  SELECT * INTO c FROM public.ottoq_vehicle_commands WHERE command_id = p_command_id;
  IF c.command_id IS NULL OR c.command_type = 'dispatch' OR c.depot_id IS NULL THEN
    RETURN NULL;
  END IF;
  IF c.status = 'refused' AND c.confirmed_by = 'otto_q_preflight' THEN
    RETURN NULL;
  END IF;
  SELECT display_name INTO v_ref FROM public.vehicles WHERE id = c.vehicle_id;
  IF v_ref IS NULL OR COALESCE(c.payload ->> 'stall_id', '') !~ c_uuid THEN
    RETURN NULL;   -- every directive names a car and a stall
  END IF;
  SELECT * INTO s FROM public.stalls WHERE id = (c.payload ->> 'stall_id')::uuid;
  IF s.id IS NULL THEN
    RETURN NULL;
  END IF;

  v_tick    := COALESCE((SELECT r.tick_interval_seconds * r.time_scale FROM public.ottoq_sim_runs r
                          WHERE r.sim_run_id = c.sim_run_id), 120);
  v_ack     := c.issued_at + make_interval(secs => v_tick::float8);
  v_expires := c.issued_at + make_interval(secs => (2 * v_tick)::float8);
  -- the directive this one replaced: the car's newest earlier one, still open when this one was issued
  SELECT p.command_id INTO v_prev FROM public.ottoq_vehicle_commands p
   WHERE p.vehicle_id = c.vehicle_id AND p.data_source = c.data_source AND p.sim_run_id IS NOT DISTINCT FROM c.sim_run_id
     AND p.command_type <> 'dispatch' AND (p.issued_at, p.command_seq) < (c.issued_at, c.command_seq)
     AND NOT (p.status = 'refused' AND p.confirmed_by = 'otto_q_preflight')
     AND (p.confirmed_at IS NULL OR p.confirmed_at > c.issued_at)
   ORDER BY p.issued_at DESC, p.command_seq DESC
   LIMIT 1;
  v_header := jsonb_build_object(
    'directive_id', c.command_id, 'version', 1,
    'supersedes', CASE WHEN v_prev IS NULL THEN NULL ELSE jsonb_build_object('directive_id', v_prev, 'version', 1) END,
    'issued_at', ottoq.ottoq_v2_rfc3339(c.issued_at), 'valid_from', ottoq.ottoq_v2_rfc3339(c.issued_at),
    'expires_at', ottoq.ottoq_v2_rfc3339(v_expires), 'ack_deadline', ottoq.ottoq_v2_rfc3339(v_ack),
    'vehicle_ref', v_ref);

  IF c.command_type = 'begin_charge' THEN
    v_type := 'com.ottoyard.directive.charge.plan';
    v_kw := COALESCE(CASE WHEN c.payload ->> 'requested_kw' ~ '^[0-9]+(\.[0-9]+)?$' THEN (c.payload ->> 'requested_kw')::numeric END,
                     s.connector_max_kw);
    IF v_kw IS NULL OR v_kw <= 0 THEN
      RETURN NULL;   -- never a zero-watt plan (rule 9): no plan rather than a wrong one
    END IF;
    SELECT ch.ocpp_identifier INTO v_evse FROM public.ottoq_ocpp_chargers ch WHERE ch.charger_id = s.ocpp_charger_id;
    v_data := v_header || jsonb_strip_nulls(jsonb_build_object(
      'stall_code', s.stall_code,
      'evse_id', CASE WHEN length(v_evse) <= 48 THEN v_evse END,
      'target_soc_pct', public.ottoq_effective_target_soc_at(c.vehicle_id, c.issued_at),
      'charging_schedule', jsonb_build_object(
        'start_schedule', ottoq.ottoq_v2_rfc3339(c.issued_at), 'charging_rate_unit', 'W',
        'periods', jsonb_build_array(jsonb_build_object('start_period_s', 0, 'limit', round(v_kw * 1000))))));
  ELSE
    v_type := 'com.ottoyard.directive.stall.assignment';
    v_purpose := CASE c.command_type WHEN 'enter_wash' THEN 'service' WHEN 'enter_service' THEN 'service'
                                     WHEN 'hold' THEN 'hold' ELSE 'staging' END;
    -- the window the calendar holds the stall for this car, where a booking says so
    IF COALESCE(c.payload ->> 'booking_id', '') ~ c_uuid THEN
      SELECT lower(b.during), upper(b.during) INTO v_ws, v_we FROM public.ottoq_stall_bookings b
       WHERE b.booking_id = (c.payload ->> 'booking_id')::uuid AND b.stall_id = s.id;
    END IF;
    IF v_ws IS NULL OR v_we IS NULL THEN
      SELECT lower(b.during), upper(b.during) INTO v_ws, v_we FROM public.ottoq_stall_bookings b
       WHERE b.stall_id = s.id AND b.vehicle_id = c.vehicle_id AND b.during @> c.issued_at
       ORDER BY b.booked_at DESC LIMIT 1;
    END IF;
    IF v_ws IS NULL OR v_we IS NULL OR v_we <= v_ws THEN
      v_ws := c.issued_at; v_we := v_expires;
    END IF;
    v_data := v_header || jsonb_build_object(
      'stall', jsonb_strip_nulls(jsonb_build_object('stall_code', s.stall_code, 'stall_type', s.stall_type::text,
                                                    'zone', CASE WHEN length(s.zone) <= 32 THEN s.zone END)),
      'purpose', v_purpose,
      'window', jsonb_build_object('start', ottoq.ottoq_v2_rfc3339(v_ws), 'end', ottoq.ottoq_v2_rfc3339(v_we)));
  END IF;

  RETURN jsonb_build_object(
    'specversion', '1.0', 'id', 'ottoq:directive:' || c.command_id || ':v1',
    'source', 'urn:ottoq:depot:' || c.depot_id, 'type', v_type, 'time', ottoq.ottoq_v2_rfc3339(c.issued_at),
    'datacontenttype', 'application/json',
    'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/' || substr(v_type, 14) || '.json',
    'subject', v_ref, 'sequence', lpad(c.command_seq::text, 20, '0'), 'data', v_data);
END $fn$;

-- ── (b) the outbox ──
CREATE OR REPLACE FUNCTION public.ottoq_v2_read_directives(
  p_key_hash text, p_after bigint DEFAULT 0, p_limit integer DEFAULT 100, p_mark_delivered boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  k public.ottow_api_keys%ROWTYPE;
  v_run uuid; v_lim integer; v_last bigint := COALESCE(p_after, 0);
  v_events jsonb := '[]'::jsonb; v_ids uuid[] := ARRAY[]::uuid[]; v_ev jsonb; r record;
BEGIN
  /* 0651: contract/README.md rules 3 and 4. A key reads the directives for its own fleets' cars at its own depot,
     of its own data source, after its cursor. The HTTP door signs each one before it leaves. */
  SELECT * INTO k FROM public.ottow_api_keys WHERE key_hash = p_key_hash AND is_active LIMIT 1;
  IF k.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_or_revoked_key');
  END IF;
  IF COALESCE(cardinality(k.fleet_operator_ids), 0) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'key_speaks_for_no_fleet');
  END IF;
  IF k.data_source NOT IN ('production', 'twin') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_directives_for_' || k.data_source);
  END IF;
  v_lim := least(greatest(COALESCE(p_limit, 100), 1), 500);
  IF k.data_source = 'twin' THEN
    SELECT r2.sim_run_id INTO v_run FROM public.ottoq_sim_runs r2
     WHERE r2.depot_id = k.depot_id AND r2.status = 'running' AND COALESCE(r2.run_by, '') <> 'production_live'
     ORDER BY r2.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN
      RETURN jsonb_build_object('ok', true, 'operator', k.source_name, 'data_source', k.data_source, 'events', '[]'::jsonb,
                                'count', 0, 'next_after', v_last, 'note', 'no_running_run');
    END IF;
  END IF;

  FOR r IN
    SELECT c.command_id, c.command_seq
      FROM public.ottoq_vehicle_commands c
      JOIN public.vehicles v ON v.id = c.vehicle_id
     WHERE c.depot_id = k.depot_id
       AND c.data_source = k.data_source
       AND v.fleet_operator_id = ANY (k.fleet_operator_ids)
       AND c.command_seq > COALESCE(p_after, 0)
       AND c.command_type <> 'dispatch'
       AND NOT (c.status = 'refused' AND c.confirmed_by = 'otto_q_preflight')
       AND (k.data_source = 'production' OR c.sim_run_id = v_run)
     ORDER BY c.command_seq
     LIMIT v_lim
  LOOP
    v_last := r.command_seq;
    v_ev := ottoq.ottoq_v2_directive_event(r.command_id);
    IF v_ev IS NOT NULL THEN
      v_events := v_events || jsonb_build_array(v_ev);
      v_ids := v_ids || r.command_id;
    END IF;
  END LOOP;

  IF p_mark_delivered AND cardinality(v_ids) > 0 THEN
    UPDATE public.ottoq_vehicle_commands
       SET delivered_at = COALESCE(delivered_at, now()), delivered_to = COALESCE(delivered_to, 'v2:' || k.source_name)
     WHERE command_id = ANY (v_ids);
  END IF;
  UPDATE public.ottow_api_keys SET last_used_at = now() WHERE id = k.id;
  RETURN jsonb_build_object('ok', true, 'operator', k.source_name, 'depot_id', k.depot_id, 'data_source', k.data_source,
                            'sim_run_id', v_run, 'events', v_events, 'count', jsonb_array_length(v_events),
                            'next_after', v_last);
END $fn$;

-- ── (c) the depot's signing key ──
CREATE TABLE public.ottoq_v2_signing_keys (
  kid             text PRIMARY KEY CHECK (kid ~ '^[A-Za-z0-9._-]{1,64}$'),
  public_jwk      jsonb NOT NULL,
  vault_secret_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  retired_at      timestamptz
);
CREATE UNIQUE INDEX ottoq_v2_signing_keys_one_active ON public.ottoq_v2_signing_keys ((true)) WHERE retired_at IS NULL;
COMMENT ON TABLE public.ottoq_v2_signing_keys IS
  '0651: the public halves of the Ed25519 keys the v2 door signs directives with (contract/README.md, Signatures). '
  'The private half is in Supabase Vault (vault_secret_id), put there by the edge function that made it. One active.';
ALTER TABLE public.ottoq_v2_signing_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_v2_signing_keys FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.ottoq_v2_signing_key_store(p_kid text, p_public_jwk jsonb, p_private_jwk jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_active public.ottoq_v2_signing_keys%ROWTYPE; v_secret uuid; c_b64 constant text := '^[A-Za-z0-9_-]{43}$';
BEGIN
  /* 0651: the edge function that made a key keeps its private half here, once. If a key is already active (another
     invocation won the race) nothing is stored and the active key is named, so the caller signs with that one. */
  SELECT * INTO v_active FROM public.ottoq_v2_signing_keys WHERE retired_at IS NULL;
  IF v_active.kid IS NOT NULL THEN
    RETURN jsonb_build_object('stored', false, 'kid', v_active.kid);
  END IF;
  IF p_kid IS NULL OR p_kid !~ '^[A-Za-z0-9._-]{1,64}$'
     OR p_public_jwk ->> 'kty' IS DISTINCT FROM 'OKP' OR p_public_jwk ->> 'crv' IS DISTINCT FROM 'Ed25519'
     OR COALESCE(p_public_jwk ->> 'x', '') !~ c_b64 OR p_public_jwk ? 'd'
     OR p_private_jwk ->> 'x' IS DISTINCT FROM p_public_jwk ->> 'x' OR COALESCE(p_private_jwk ->> 'd', '') !~ c_b64 THEN
    RAISE EXCEPTION 'ottoq_v2_signing_key_store: not an Ed25519 key pair in JWK form (RFC 8037)';
  END IF;
  v_secret := vault.create_secret(p_private_jwk::text, 'ottoq_v2_signing_key:' || p_kid,
                                  'Ed25519 private key the v2 door signs directives with (0651)', NULL);
  INSERT INTO public.ottoq_v2_signing_keys (kid, public_jwk, vault_secret_id)
  VALUES (p_kid, jsonb_build_object('kty', 'OKP', 'crv', 'Ed25519', 'x', p_public_jwk ->> 'x'), v_secret);
  RETURN jsonb_build_object('stored', true, 'kid', p_kid);
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_active FROM public.ottoq_v2_signing_keys WHERE retired_at IS NULL;
  RETURN jsonb_build_object('stored', false, 'kid', v_active.kid);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_v2_signing_key_current()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  /* 0651: the active key, private half included, for the edge function alone (service_role). NULL when none yet. */
  SELECT jsonb_build_object('kid', k.kid, 'private_jwk', ds.decrypted_secret::jsonb)
    FROM public.ottoq_v2_signing_keys k
    JOIN vault.decrypted_secrets ds ON ds.id = k.vault_secret_id
   WHERE k.retired_at IS NULL
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_v2_jwks()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  /* 0651: the public halves an operator verifies with: the active key, and any retired in the last 7 days. */
  SELECT jsonb_build_object('keys', COALESCE(jsonb_agg(
           k.public_jwk || jsonb_build_object('kid', k.kid, 'use', 'sig', 'alg', 'Ed25519') ORDER BY k.created_at), '[]'::jsonb))
    FROM public.ottoq_v2_signing_keys k
   WHERE k.retired_at IS NULL OR k.retired_at > now() - interval '7 days'
$fn$;

REVOKE ALL ON FUNCTION ottoq.ottoq_v2_rfc3339(timestamptz)                                 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ottoq.ottoq_v2_directive_event(uuid)                                FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_v2_read_directives(text,bigint,integer,boolean)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_v2_signing_key_store(text,jsonb,jsonb)                 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_v2_signing_key_current()                               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_v2_jwks()                                              FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_v2_read_directives(text,bigint,integer,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_v2_signing_key_store(text,jsonb,jsonb)          TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_v2_signing_key_current()                        TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_v2_jwks()                                       TO service_role;

-- ── V1: render the engine's own commands (read-only), and the outbox and the key store in a sub-block that rolls back ──
DO $v1$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_charge uuid; v_stage uuid; e_charge jsonb; e_stage jsonb; c record; v_tick numeric;
  v_fleet uuid; k jsonb; h text; r_read jsonb; v_foreign int; v_rendered int; v_running uuid;
  s1 jsonb; s2 jsonb; cur jsonb; jw jsonb; v_keys_after bigint; v_keys_before bigint;
  c_x text := 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; c_d text := 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
BEGIN
  -- (a) the newest charge and stall commands the twin depot sent, rendered
  SELECT command_id INTO v_charge FROM public.ottoq_vehicle_commands
   WHERE depot_id = v_twin AND command_type = 'begin_charge' AND NOT (status = 'refused' AND confirmed_by = 'otto_q_preflight')
   ORDER BY command_seq DESC LIMIT 1;
  SELECT command_id INTO v_stage FROM public.ottoq_vehicle_commands
   WHERE depot_id = v_twin AND command_type IN ('proceed_to_stall', 'stage') AND NOT (status = 'refused' AND confirmed_by = 'otto_q_preflight')
   ORDER BY command_seq DESC LIMIT 1;
  IF v_charge IS NOT NULL THEN
    e_charge := ottoq.ottoq_v2_directive_event(v_charge);
    SELECT cmd.*, COALESCE(r.tick_interval_seconds * r.time_scale, 120) AS tick INTO c
      FROM public.ottoq_vehicle_commands cmd LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = cmd.sim_run_id
     WHERE cmd.command_id = v_charge;
    IF e_charge IS NULL OR e_charge ->> 'type' <> 'com.ottoyard.directive.charge.plan'
       OR e_charge -> 'data' ->> 'directive_id' <> v_charge::text
       OR (e_charge -> 'data' ->> 'expires_at')::timestamptz <> c.issued_at + make_interval(secs => (2 * c.tick)::float8)
       OR (e_charge -> 'data' ->> 'ack_deadline')::timestamptz <> c.issued_at + make_interval(secs => c.tick::float8)
       OR (e_charge -> 'data' -> 'charging_schedule' -> 'periods' -> 0 ->> 'limit')::numeric <= 0
       OR (e_charge -> 'data' ->> 'target_soc_pct')::numeric <> public.ottoq_effective_target_soc_at(c.vehicle_id, c.issued_at)
       OR e_charge -> 'data' ->> 'stall_code' IS DISTINCT FROM (SELECT stall_code FROM public.stalls WHERE id = (c.payload ->> 'stall_id')::uuid)
       OR e_charge ->> 'subject' IS DISTINCT FROM (SELECT display_name FROM public.vehicles WHERE id = c.vehicle_id) THEN
      RAISE EXCEPTION '0651 V1 FAILED: the newest charge command renders as %', e_charge;
    END IF;
  END IF;
  IF v_stage IS NOT NULL THEN
    e_stage := ottoq.ottoq_v2_directive_event(v_stage);
    IF e_stage IS NULL OR e_stage ->> 'type' <> 'com.ottoyard.directive.stall.assignment'
       OR e_stage -> 'data' ->> 'purpose' <> 'staging' OR e_stage -> 'data' -> 'stall' ->> 'stall_code' IS NULL
       OR (e_stage -> 'data' -> 'window' ->> 'end')::timestamptz <= (e_stage -> 'data' -> 'window' ->> 'start')::timestamptz THEN
      RAISE EXCEPTION '0651 V1 FAILED: the newest staging command renders as %', e_stage;
    END IF;
  END IF;

  SELECT count(*) INTO v_keys_before FROM public.ottoq_v2_signing_keys;
  SELECT sim_run_id INTO v_running FROM public.ottoq_sim_runs
   WHERE depot_id = v_twin AND status = 'running' AND COALESCE(run_by, '') <> 'production_live' ORDER BY started_at DESC LIMIT 1;
  SELECT fleet_operator_id INTO v_fleet FROM public.vehicles
   WHERE home_depot_id = v_twin AND fleet_operator_id IS NOT NULL ORDER BY display_name LIMIT 1;
  BEGIN
    -- (b) a twin key for one fleet reads only that fleet's cars, and marks nothing
    k := public.ottoq_issue_source_key(v_twin, 'fleet_api', 'probe-0651', 'twin', ARRAY['telemetry']);
    PERFORM public.ottoq_scope_source_key((k->>'id')::uuid, ARRAY[v_fleet]);
    h := encode(extensions.digest(k->>'key', 'sha256'), 'hex');
    r_read := public.ottoq_v2_read_directives(h, 0, 500, false);
    SELECT count(*) INTO v_foreign FROM jsonb_array_elements(r_read -> 'events') e
     WHERE NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.display_name = e ->> 'subject' AND v.fleet_operator_id = v_fleet
                          AND (v.home_depot_id = v_twin OR v.current_depot_id = v_twin));
    v_rendered := jsonb_array_length(COALESCE(r_read -> 'events', '[]'::jsonb));
    -- (c) the key store: one active key, the public half without d, a second store names the first
    s1 := public.ottoq_v2_signing_key_store('probe-0651-a', jsonb_build_object('kty', 'OKP', 'crv', 'Ed25519', 'x', c_x),
                                            jsonb_build_object('kty', 'OKP', 'crv', 'Ed25519', 'x', c_x, 'd', c_d));
    s2 := public.ottoq_v2_signing_key_store('probe-0651-b', jsonb_build_object('kty', 'OKP', 'crv', 'Ed25519', 'x', c_x),
                                            jsonb_build_object('kty', 'OKP', 'crv', 'Ed25519', 'x', c_x, 'd', c_d));
    cur := public.ottoq_v2_signing_key_current();
    jw := public.ottoq_v2_jwks();
    RAISE EXCEPTION '0651 V1 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0651 V1 PROBED' THEN RAISE EXCEPTION '0651 V1: the probe itself failed: %', v_msg; END IF;
  SELECT count(*) INTO v_keys_after FROM public.ottoq_v2_signing_keys;

  IF NOT COALESCE((r_read ->> 'ok')::boolean, false) THEN RAISE EXCEPTION '0651 V1 FAILED: the outbox refused a scoped twin key: %', r_read; END IF;
  IF v_running IS NULL AND r_read ->> 'note' IS DISTINCT FROM 'no_running_run' THEN
    RAISE EXCEPTION '0651 V1 FAILED: with no running run the outbox did not say so: %', r_read;
  END IF;
  IF v_foreign > 0 THEN RAISE EXCEPTION '0651 V1 FAILED: % directive(s) for another fleet''s car reached a scoped key', v_foreign; END IF;
  IF NOT COALESCE((s1 ->> 'stored')::boolean, false) OR COALESCE((s2 ->> 'stored')::boolean, true) OR s2 ->> 'kid' <> 'probe-0651-a' THEN
    RAISE EXCEPTION '0651 V1 FAILED: the key store: % then %', s1, s2;
  END IF;
  IF cur ->> 'kid' <> 'probe-0651-a' OR cur -> 'private_jwk' ->> 'd' <> c_d THEN
    RAISE EXCEPTION '0651 V1 FAILED: the current key did not come back from Vault whole';
  END IF;
  IF jsonb_array_length(jw -> 'keys') <> 1 OR jw -> 'keys' -> 0 ? 'd' OR jw -> 'keys' -> 0 ->> 'alg' <> 'Ed25519' THEN
    RAISE EXCEPTION '0651 V1 FAILED: the JWK Set: %', jw;
  END IF;
  IF v_keys_after <> v_keys_before THEN RAISE EXCEPTION '0651 V1 FAILED: the probe key did not roll back'; END IF;
  RAISE NOTICE '0651 V1 PASSED: the newest charge command renders as a charge plan (expiry 2 ticks, ack 1 tick, the owner''s target, a positive limit, its stall and car) and the newest staging command as a stall assignment; a twin key for one fleet read % directive(s) of the running run (%), none another fleet''s; the key store keeps one active key, returns its private half from Vault and publishes only the public half; all rolled back',
    v_rendered, COALESCE(v_running::text, 'none running');
END $v1$;

-- ── V2: who may call what ──
DO $v2$
DECLARE r record;
BEGIN
  FOR r IN SELECT unnest(ARRAY['public.ottoq_v2_read_directives(text,bigint,integer,boolean)',
                               'public.ottoq_v2_signing_key_store(text,jsonb,jsonb)',
                               'public.ottoq_v2_signing_key_current()',
                               'public.ottoq_v2_jwks()'])::regprocedure AS f
  LOOP
    IF has_function_privilege('anon', r.f, 'EXECUTE') OR has_function_privilege('authenticated', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0651 V2 FAILED: % is executable by anon or authenticated', r.f;
    END IF;
    IF NOT has_function_privilege('service_role', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0651 V2 FAILED: service_role cannot execute %', r.f;
    END IF;
  END LOOP;
  IF has_function_privilege('service_role', 'ottoq.ottoq_v2_directive_event(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0651 V2 FAILED: the renderer is callable around the outbox';
  END IF;
  IF has_table_privilege('anon', 'public.ottoq_v2_signing_keys', 'SELECT') OR has_table_privilege('authenticated', 'public.ottoq_v2_signing_keys', 'SELECT') THEN
    RAISE EXCEPTION '0651 V2 FAILED: anon or authenticated can read the signing keys';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0651_a_directive_leaves_with_an_id_a_version_an_expiry_and_the_depots_signing_key', false, false,
  'Step 3 of the twin data contract review: ottoq.ottoq_v2_directive_event renders a command as a contract directive '
  '(id, version, supersedes, expiry 2 ticks, ack 1 tick, the owner''s target); ottoq_v2_read_directives is the '
  'fleet-scoped outbox (stamps delivered_at/delivered_to only, outside h_cmd); ottoq_v2_signing_keys + Vault-held '
  'private half; ottoq_v2_jwks. Nothing in a tick calls any of it. FALSE/FALSE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 00:59:34 UTC (7:59 PM CT on 2026-10-09), version 20261010005934 ═══════════════════════════════
--   Claude, MCP apply_migration, the file as committed in e2315a0; the ledger's stored statement is that file byte for
--   byte (md5 dbebfe62624f8856576d7400fa4a34cb, 29,616 characters, 30,356 bytes). P0, P1, V1, V2 passed in the apply's
--   transaction: the twin depot's newest charge command (Zoox-001 to NASH-DCFC-STALL-06, 30 kW asked, a 1,800-second
--   tick) and newest staging command rendered as stated. Read after: 0 signing keys and 0 Vault secrets (the edge
--   function makes the first on first use; V1's probe key rolled back), 0 probe source keys, 0 commands stamped
--   delivered by the outbox.
