-- tests/fixtures/signing_rotation_stub.sql — what db/migrations/0722 (the signing-key rotation) meets, in miniature.
-- Loaded ON TOP OF tests/fixtures/signing_grants_stub.sql and BEFORE 0701, so a test can apply 0701 and then 0722, or
-- 0722 alone and see it refuse.
--
-- What it adds, measured on the live engine 2026-10-14 (db/migrations/0722 §1):
--   * the key registry in its live shape (scope, scope_id, algorithm, activated_at, rotated_at, rotation_reason,
--     created_by, created_at; the scope CHECK; UNIQUE (scope, scope_id, is_active) DEFERRABLE INITIALLY DEFERRED), with
--     the one live row: system:v1, active, vault:ottoq_signing_key_system_v1, never rotated;
--   * a stand-in Vault in its live shape: vault.secrets (id, name unique, description, secret), vault.create_secret with
--     the live signature, and vault.decrypted_secrets, whose decrypted_secret column RAISEs a NOTICE for every read,
--     naming the secret and whether the read came through ottoq_resolve_signing_secret. A NOTICE reaches the client even
--     from a block that rolls back, so a read a migration makes inside a probe is still seen;
--   * the five functions whose default key 0722 changes, the two verifiers, the payload hash, its canonicaliser and the
--     event log's append-only guard, each with its LIVE definition byte for byte (tests/test_signing_rotation_sql.py
--     asserts every md5(pg_get_functiondef) against the live catalog's) and its live grants;
--   * the tables and columns those bodies read and write, and the append-only trigger on ottoq_events, so a migration
--     that updated or deleted an event would fail here as it would live.
-- Loads on a plain PostgreSQL 16 or 17 as a superuser named postgres.

-- ── the key registry, as live (read 2026-10-14) ──
ALTER TABLE public.ottoq_signing_keys
  ADD COLUMN scope text,
  ADD COLUMN scope_id uuid,
  ADD COLUMN algorithm text NOT NULL DEFAULT 'HMAC-SHA-256'::text,
  ADD COLUMN activated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN rotated_at timestamptz,
  ADD COLUMN rotation_reason text,
  ADD COLUMN created_by text,
  ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
UPDATE public.ottoq_signing_keys
   SET scope = 'system', secret_ref = 'vault:ottoq_signing_key_system_v1',
       activated_at = '2026-05-14 18:08:35.639607+00', created_at = '2026-05-14 18:08:35.639607+00',
       created_by = 'migration:20260514_layer1_event_journal'
 WHERE key_id = 'system:v1';
ALTER TABLE public.ottoq_signing_keys
  ALTER COLUMN scope SET NOT NULL,
  ALTER COLUMN secret_ref SET NOT NULL,
  ADD CONSTRAINT ottoq_signing_keys_scope_check CHECK (scope = ANY (ARRAY['system'::text, 'fleet_operator'::text, 'depot'::text])),
  ADD CONSTRAINT ottoq_signing_keys_scope_scope_id_is_active_key UNIQUE (scope, scope_id, is_active) DEFERRABLE INITIALLY DEFERRED;

-- ── Vault, as live in shape: the secret under its live name, create_secret, and a decrypted view that reports reads ──
UPDATE vault.secrets SET name = 'ottoq_signing_key_system_v1' WHERE name = 'ottoq_signing_system_v1';
ALTER TABLE vault.secrets
  ADD COLUMN id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ADD COLUMN description text NOT NULL DEFAULT ''::text,
  ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
DROP VIEW vault.decrypted_secrets;
CREATE FUNCTION vault.stub_decrypt(p_name text, p_secret text) RETURNS text LANGUAGE plpgsql VOLATILE AS $f$
DECLARE v_ctx text;
BEGIN
  GET DIAGNOSTICS v_ctx = PG_CONTEXT;
  RAISE NOTICE 'stub vault read: % (through the resolver: %)', p_name,
    (v_ctx ~ 'ottoq_resolve_signing_secret\(text\)')::text;
  RETURN p_secret;
END $f$;
CREATE VIEW vault.decrypted_secrets AS
  SELECT s.id, s.name, s.description, s.secret, vault.stub_decrypt(s.name, s.secret) AS decrypted_secret, s.created_at
    FROM vault.secrets s;
-- live: vault 0.3.1, SECURITY DEFINER, SET search_path TO ''; the stand-in stores the value as given
CREATE FUNCTION vault.create_secret(new_secret text, new_name text DEFAULT NULL::text, new_description text DEFAULT ''::text,
                                    new_key_id uuid DEFAULT NULL::uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_id uuid;
BEGIN
  INSERT INTO vault.secrets (secret, name, description) VALUES (new_secret, new_name, new_description) RETURNING id INTO v_id;
  RETURN v_id;
END $f$;

-- ── the tables the five live bodies and the two verifiers read and write (the columns they name) ──
CREATE TABLE public.depots (id uuid PRIMARY KEY, slug text, feed_mode text);
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, vehicle_class_code text, fleet_operator_id uuid, current_depot_id uuid,
                              home_depot_id uuid);
CREATE TABLE public.ottoq_event_types_catalog (event_type text PRIMARY KEY, category text NOT NULL, default_severity text NOT NULL);
CREATE TABLE public.ottoq_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_seq bigserial UNIQUE,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  actor_type text NOT NULL CHECK (actor_type = ANY (ARRAY['fleet_operator_admin', 'fleet_operator_viewer', 'oem_dispatch_webhook',
    'oem_admin_console', 'depot_tech', 'depot_supervisor', 'command_center_operator', 'ottoq_engine', 'ottow_driver',
    'ottow_dispatcher', 'otto_response_agent', 'system_scheduler', 'external_sensor', 'ocpp_charger', 'av_vehicle',
    'bess_controller', 'solar_controller', 'migration_script', 'system', 'unknown'])),
  actor_id text,
  actor_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  event_type text NOT NULL,
  event_category text NOT NULL,
  severity text NOT NULL DEFAULT 'info'::text
    CHECK (severity = ANY (ARRAY['debug', 'info', 'warning', 'error', 'critical', 'safety_critical'])),
  entity_type text NOT NULL,
  entity_id uuid,
  fleet_operator_id uuid,
  depot_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  previous_state jsonb,
  new_state jsonb,
  correlation_id uuid NOT NULL DEFAULT gen_random_uuid(),
  parent_event_id uuid,
  causation_chain uuid[] NOT NULL DEFAULT '{}'::uuid[],
  related_task_id uuid,
  related_schedule_id uuid,
  related_decision_id uuid,
  payload_hash text NOT NULL,
  signature text,
  signature_key_id text,
  signature_algorithm text NOT NULL DEFAULT 'HMAC-SHA-256'::text,
  outcome text CHECK (outcome = ANY (ARRAY['pending', 'in_progress', 'succeeded', 'failed', 'rolled_back', 'partial', 'timed_out'])),
  outcome_recorded_at timestamptz,
  latency_ms integer,
  ingest_source text DEFAULT 'app'::text,
  schema_version text NOT NULL DEFAULT '1.0.0'::text,
  data_source text NOT NULL DEFAULT 'production'::text CHECK (data_source = ANY (ARRAY['production', 'twin', 'replay', 'shadow'])),
  sim_run_id uuid,
  sim_clock_at timestamptz,
  CONSTRAINT no_future_events CHECK (occurred_at <= recorded_at + interval '1 minute'));
CREATE TABLE public.ottoq_service_tariffs (tariff_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), pack_id text, operation_code text,
  active boolean NOT NULL DEFAULT true, fleet_operator_id uuid, asset_class_code text, effective_from timestamptz NOT NULL DEFAULT now(),
  effective_until timestamptz);
CREATE TABLE public.ottoq_service_detail_records (
  sdr_id uuid PRIMARY KEY, sdr_seq bigserial, sim_run_id uuid, data_source text, pack_id text, operation_code text, vehicle_id uuid,
  asset_class_code text, fleet_operator_id uuid, depot_id uuid, stall_id uuid, source_kind text, leg_id uuid UNIQUE,
  schedule_task_id uuid UNIQUE, visit_id uuid, booking_id uuid, ocpp_session_id uuid, started_at timestamptz, ended_at timestamptz,
  duration_min numeric, energy_kwh numeric, peak_kw numeric, tariff_id uuid, attribution_id uuid, cost_components jsonb,
  total_cost_usd numeric, billable_amount_usd numeric, currency text DEFAULT 'USD', sdr_event_id uuid, payload_hash text,
  signature text, signature_key_id text, signature_algorithm text DEFAULT 'HMAC-SHA-256', status text DEFAULT 'issued',
  schema_version text DEFAULT '1.0', issued_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_rule_evaluations (evaluated_at timestamptz, fleet_operator_id uuid);
CREATE TABLE public.ottoq_predictions (created_at timestamptz, fleet_operator_id uuid);
CREATE TABLE public.ottoq_anomaly_observations (observed_at timestamptz, fleet_operator_id uuid, is_anomaly boolean);
CREATE TABLE public.ottoq_emergency_invocations (triggered_at timestamptz);
CREATE TABLE public.ottoq_audit_bundles (
  bundle_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bundle_seq bigserial, bundle_code text NOT NULL,
  fleet_operator_id uuid NOT NULL, report_ids uuid[] NOT NULL, event_id_range_low bigint, event_id_range_high bigint,
  window_start timestamptz NOT NULL, window_end timestamptz NOT NULL, format text NOT NULL DEFAULT 'jsonl'::text,
  storage_path text, size_bytes bigint, sha256 text NOT NULL, signature text NOT NULL, signature_key_id text NOT NULL,
  signature_algorithm text NOT NULL DEFAULT 'HMAC-SHA-256'::text, manifest jsonb NOT NULL, public_verification_url text,
  generated_at timestamptz NOT NULL DEFAULT now(), generated_by_actor_type text, generated_by_actor_id text, delivered_to text,
  delivered_at timestamptz, download_count integer NOT NULL DEFAULT 0, last_downloaded_at timestamptz, expires_at timestamptz,
  revoked_at timestamptz, revocation_reason text, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_audit_reports (
  report_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), report_seq bigserial, report_type text NOT NULL, report_subtype text,
  fleet_operator_id uuid, depot_id uuid, vehicle_id uuid, schedule_id uuid, window_start timestamptz NOT NULL,
  window_end timestamptz NOT NULL, requested_by_actor_type text, requested_by_actor_id text,
  requested_at timestamptz NOT NULL DEFAULT now(), generation_started_at timestamptz, generation_completed_at timestamptz,
  generation_status text NOT NULL DEFAULT 'pending'::text, generation_duration_ms integer, generation_error text, payload jsonb,
  payload_hash text, signature text, signature_key_id text, signature_algorithm text DEFAULT 'HMAC-SHA-256'::text,
  event_count bigint, rule_eval_count bigint, prediction_count bigint, anomaly_count bigint, override_count bigint,
  emergency_count bigint, visit_count bigint, title text, description text, format text DEFAULT 'json'::text,
  expires_at timestamptz, parent_report_id uuid, source_event_id uuid, audit_trail_complete boolean, data_quality_score numeric,
  exclusions jsonb DEFAULT '[]'::jsonb, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.schedule_tasks (id uuid PRIMARY KEY, vehicle_schedule_id uuid, schedule_id uuid);
CREATE TABLE public.ottoq_visit_cost_attribution (
  attribution_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), attribution_seq bigserial, schedule_id uuid NOT NULL,
  vehicle_id uuid, fleet_operator_id uuid, depot_id uuid, total_cost_usd numeric, billable_amount_usd numeric,
  cost_components jsonb DEFAULT '{}'::jsonb, computed_at timestamptz NOT NULL DEFAULT now());

-- ottoq.ottoq_run_now(): the run's sim clock; ottoq_record_event reads it only for an event that names a run
CREATE FUNCTION ottoq.ottoq_run_now() RETURNS timestamptz LANGUAGE sql STABLE AS $f$ SELECT now() $f$;

-- ── live definitions, byte for byte ──
-- public.ottoq_canonicalize_payload (live pg_get_functiondef md5 e06c86021e88731f019c857f1f872adb)
CREATE OR REPLACE FUNCTION public.ottoq_canonicalize_payload(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF p IS NULL THEN RETURN '{}'; END IF;
  RETURN jsonb_strip_nulls(p)::text;
END;
$function$
;

-- public.ottoq_compute_event_hash (live pg_get_functiondef md5 a870ab4db2effd0fb825eb8ba94173a0)
CREATE OR REPLACE FUNCTION public.ottoq_compute_event_hash(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  RETURN encode(digest(ottoq_canonicalize_payload(p), 'sha256'), 'hex');
END;
$function$
;

-- public.ottoq_events_block_mutation, the append-only guard (live pg_get_functiondef md5 ad4622dbfa8d1ca8414a8f914a2b0916)
CREATE OR REPLACE FUNCTION public.ottoq_events_block_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- Retention maintenance only. UPDATE is forgiven here solely because
  -- ottoq_events_parent_event_id_fkey is ON DELETE SET NULL, so purging a parent
  -- rewrites its surviving children. Without this the purge aborts on its own FK.
  IF current_setting('ottoq.retention', true) = 'on' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;   -- unchanged from the pre-image
    IF TG_OP = 'UPDATE' THEN RETURN NEW; END IF;   -- the one added line
  END IF;
  RAISE EXCEPTION 'ottoq_events is append-only. Operation % rejected on event_id=%',
    TG_OP, COALESCE(OLD.event_id, NEW.event_id);
END;
$function$
;

-- public.ottoq_record_event: every event; its default key is the one 0722 changes (live pg_get_functiondef md5 6d3eafdb8d582a05c6d0af2b90bbb8ff)
CREATE OR REPLACE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text, p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid, p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer, p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_event_id        UUID := gen_random_uuid();
  v_category        TEXT;
  v_severity        TEXT;
  v_payload_hash    TEXT;
  v_signature       TEXT;
  v_correlation_id  UUID;
  v_causation       UUID[] := '{}'::uuid[];
  v_parent          ottoq_events%ROWTYPE;
  v_occurred_at     TIMESTAMPTZ := NOW();
BEGIN
  SELECT category, default_severity INTO v_category, v_severity
    FROM ottoq_event_types_catalog WHERE event_type = p_event_type;
  IF v_category IS NULL THEN
    v_category := 'system_event';
    v_severity := 'warning';
  END IF;
  v_severity := COALESCE(p_severity, v_severity);

  v_correlation_id := COALESCE(
    p_correlation_id,
    NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID,
    gen_random_uuid()
  );

  IF p_parent_event_id IS NOT NULL THEN
    SELECT * INTO v_parent FROM ottoq_events WHERE event_id = p_parent_event_id;
    IF FOUND THEN
      v_causation := v_parent.causation_chain || p_parent_event_id;
    ELSE
      v_causation := ARRAY[p_parent_event_id];
    END IF;
  END IF;

  v_payload_hash := ottoq_compute_event_hash(p_payload);
  v_signature := ottoq_sign_event(
    v_event_id, v_occurred_at, p_actor_type, p_event_type,
    p_entity_type, p_entity_id, v_payload_hash, p_signing_key_id
  );

  INSERT INTO ottoq_events (
    event_id, occurred_at, recorded_at,
    actor_type, actor_id, actor_metadata,
    event_type, event_category, severity,
    entity_type, entity_id,
    fleet_operator_id, depot_id,
    payload, previous_state, new_state,
    correlation_id, parent_event_id, causation_chain,
    related_task_id, related_schedule_id, related_decision_id,
    payload_hash, signature, signature_key_id,
    outcome, latency_ms, ingest_source,
    data_source, sim_run_id, sim_clock_at
  ) VALUES (
    v_event_id, v_occurred_at, NOW(),
    p_actor_type, p_actor_id, p_actor_metadata,
    p_event_type, v_category, v_severity,
    p_entity_type, p_entity_id,
    p_fleet_operator_id,
    COALESCE(p_depot_id,
             CASE WHEN p_entity_type = 'depot'
                       AND EXISTS (SELECT 1 FROM public.depots d WHERE d.id = p_entity_id)
                  THEN p_entity_id END),
    p_payload, p_previous_state, p_new_state,
    v_correlation_id, p_parent_event_id, v_causation,
    p_related_task_id, p_related_schedule_id, p_related_decision_id,
    v_payload_hash, v_signature, p_signing_key_id,
    p_outcome, p_latency_ms, p_ingest_source,
    COALESCE(p_data_source, 'production'), p_sim_run_id, CASE WHEN p_sim_run_id IS NOT NULL THEN ottoq.ottoq_run_now() END
  );

  RETURN v_event_id;
END;
$function$
;

-- public.ottoq_emit_sdr: every SDR and its sdr_issued event (live pg_get_functiondef md5 8158e4bf2fdac5a8e0495d65c43b891a)
CREATE OR REPLACE FUNCTION public.ottoq_emit_sdr(p_source_kind text, p_operation_code text, p_pack_id text, p_vehicle_id uuid, p_sim_run_id uuid, p_leg_id uuid, p_schedule_task_id uuid, p_visit_id uuid, p_booking_id uuid, p_stall_id uuid, p_depot_id uuid, p_started_at timestamp with time zone, p_ended_at timestamp with time zone, p_energy_kwh numeric DEFAULT NULL::numeric, p_peak_kw numeric DEFAULT NULL::numeric, p_key_id text DEFAULT 'system:v1'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_sdr_id uuid := gen_random_uuid();
  v_class text; v_operator uuid; v_tariff uuid;
  v_payload jsonb; v_hash text; v_sig text; v_event uuid;
  v_data_source text := COALESCE((SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END FROM public.depots d WHERE d.id = COALESCE(p_depot_id, (SELECT COALESCE(v.current_depot_id, v.home_depot_id) FROM public.vehicles v WHERE v.id = p_vehicle_id))), 'twin');
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);

  IF p_leg_id IS NOT NULL AND EXISTS
     (SELECT 1 FROM ottoq_service_detail_records WHERE leg_id = p_leg_id) THEN
    RETURN NULL;
  END IF;
  IF p_schedule_task_id IS NOT NULL AND EXISTS
     (SELECT 1 FROM ottoq_service_detail_records WHERE schedule_task_id = p_schedule_task_id) THEN
    RETURN NULL;
  END IF;

  SELECT v.vehicle_class_code, v.fleet_operator_id INTO v_class, v_operator
    FROM vehicles v WHERE v.id = p_vehicle_id;

  SELECT t.tariff_id INTO v_tariff
    FROM ottoq_service_tariffs t
   WHERE t.pack_id = p_pack_id AND t.operation_code = p_operation_code
     AND t.active
     AND (t.fleet_operator_id IS NULL OR t.fleet_operator_id = v_operator)
     AND (t.asset_class_code  IS NULL OR t.asset_class_code  = v_class)
     AND (t.effective_until IS NULL OR t.effective_until > p_ended_at)
   ORDER BY (t.fleet_operator_id IS NOT NULL) DESC,
            (t.asset_class_code  IS NOT NULL) DESC,
            t.effective_from DESC
   LIMIT 1;

  v_payload := jsonb_build_object(
    'operation_code', p_operation_code, 'pack_id', p_pack_id,
    'vehicle_id', p_vehicle_id, 'asset_class_code', v_class,
    'fleet_operator_id', v_operator, 'stall_id', p_stall_id,
    'started_at', p_started_at, 'ended_at', p_ended_at,
    'energy_kwh', p_energy_kwh, 'source_kind', p_source_kind,
    'leg_id', p_leg_id, 'schedule_task_id', p_schedule_task_id);
  v_hash := ottoq_compute_event_hash(v_payload);
  v_sig  := ottoq_sign_sdr(v_sdr_id, p_ended_at, p_vehicle_id,
                           p_operation_code, v_hash, p_key_id);

  v_event := ottoq_record_event(
    p_actor_type => 'system', p_event_type => 'sdr_issued',
    p_entity_type => 'service_detail_record', p_entity_id => v_sdr_id,
    p_payload => v_payload, p_actor_id => 'ottoq_emit_sdr',
    p_actor_metadata => '{}'::jsonb,
    p_fleet_operator_id => v_operator, p_depot_id => p_depot_id,
    p_previous_state => NULL, p_new_state => NULL, p_severity => NULL,
    p_correlation_id => NULL, p_parent_event_id => NULL,
    p_related_task_id => p_schedule_task_id, p_related_schedule_id => NULL,
    p_related_decision_id => NULL, p_outcome => 'succeeded', p_latency_ms => NULL,
    p_ingest_source => 'kernel', p_signing_key_id => p_key_id,
    p_data_source => v_data_source, p_sim_run_id => p_sim_run_id);

  INSERT INTO ottoq_service_detail_records
    (sdr_id, sim_run_id, data_source, pack_id, operation_code, vehicle_id,
     asset_class_code, fleet_operator_id, depot_id, stall_id, source_kind,
     leg_id, schedule_task_id, visit_id, booking_id,
     started_at, ended_at, duration_min, energy_kwh, peak_kw,
     tariff_id, sdr_event_id, payload_hash, signature, signature_key_id)
  VALUES
    (v_sdr_id, p_sim_run_id, v_data_source, p_pack_id, p_operation_code, p_vehicle_id,
     v_class, v_operator, p_depot_id, p_stall_id, p_source_kind,
     p_leg_id, p_schedule_task_id, p_visit_id, p_booking_id,
     p_started_at, p_ended_at,
     CASE WHEN p_started_at IS NOT NULL
          THEN round(EXTRACT(EPOCH FROM (p_ended_at - p_started_at))/60.0, 2) END,
     p_energy_kwh, p_peak_kw,
     v_tariff, v_event, v_hash, v_sig, p_key_id)
  ON CONFLICT DO NOTHING;

  RETURN v_sdr_id;
END;
$function$
;

-- public.ottoq_generate_audit_bundle: every audit bundle (live pg_get_functiondef md5 23c0bda2f0c9ce64b02c9c25699cf412)
CREATE OR REPLACE FUNCTION public.ottoq_generate_audit_bundle(p_fleet_operator_id uuid, p_report_ids uuid[], p_bundle_code text, p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_format text DEFAULT 'jsonl'::text, p_storage_path text DEFAULT NULL::text, p_size_bytes bigint DEFAULT NULL::bigint, p_sha256 text DEFAULT NULL::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_generated_by_actor_type text DEFAULT 'system'::text, p_generated_by_actor_id text DEFAULT NULL::text, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_bundle_id   UUID := gen_random_uuid();
  v_sha256      TEXT;
  v_signature   TEXT;
  v_manifest    JSONB;
  v_event_low   BIGINT;
  v_event_high  BIGINT;
BEGIN
  -- Compute event_seq range from the period
  SELECT MIN(event_seq), MAX(event_seq) INTO v_event_low, v_event_high
    FROM ottoq_events
   WHERE occurred_at BETWEEN p_window_start AND p_window_end
     AND (p_fleet_operator_id IS NULL OR fleet_operator_id = p_fleet_operator_id);

  -- Build manifest summarizing what's inside
  v_manifest := jsonb_build_object(
    'report_count', cardinality(p_report_ids),
    'event_count',  COALESCE(v_event_high - v_event_low + 1, 0),
    'window_start', p_window_start,
    'window_end',   p_window_end,
    'rule_eval_count', (
      SELECT count(*) FROM ottoq_rule_evaluations
       WHERE evaluated_at BETWEEN p_window_start AND p_window_end
         AND (p_fleet_operator_id IS NULL OR fleet_operator_id = p_fleet_operator_id)
    ),
    'prediction_count', (
      SELECT count(*) FROM ottoq_predictions
       WHERE created_at BETWEEN p_window_start AND p_window_end
         AND (p_fleet_operator_id IS NULL OR fleet_operator_id = p_fleet_operator_id)
    ),
    'anomaly_count', (
      SELECT count(*) FROM ottoq_anomaly_observations
       WHERE observed_at BETWEEN p_window_start AND p_window_end
         AND (p_fleet_operator_id IS NULL OR fleet_operator_id = p_fleet_operator_id)
         AND is_anomaly = TRUE
    ),
    'emergency_count', (
      SELECT count(*) FROM ottoq_emergency_invocations
       WHERE triggered_at BETWEEN p_window_start AND p_window_end
    ),
    'audit_trail_complete', TRUE
  );

  -- sha256 placeholder until file upload provides the real hash
  v_sha256 := COALESCE(p_sha256, encode(digest(v_manifest::text, 'sha256'), 'hex'));

  -- Sign
  v_signature := ottoq_sign_bundle(v_bundle_id, p_window_start, p_window_end, v_sha256, p_signing_key_id);
  IF v_signature IS NULL THEN
    -- Fail-open: record bundle but flag missing signature
    v_signature := 'UNSIGNED:no_signing_secret_available';
  END IF;

  INSERT INTO ottoq_audit_bundles (
    bundle_id, bundle_code, fleet_operator_id,
    report_ids, event_id_range_low, event_id_range_high,
    window_start, window_end,
    format, storage_path, size_bytes, sha256,
    signature, signature_key_id, signature_algorithm,
    manifest, generated_by_actor_type, generated_by_actor_id, expires_at
  ) VALUES (
    v_bundle_id, p_bundle_code, p_fleet_operator_id,
    p_report_ids, v_event_low, v_event_high,
    p_window_start, p_window_end,
    p_format, p_storage_path, p_size_bytes, v_sha256,
    v_signature, p_signing_key_id, 'HMAC-SHA-256',
    v_manifest, p_generated_by_actor_type, p_generated_by_actor_id, p_expires_at
  );

  PERFORM ottoq_record_event(
    p_actor_type        := p_generated_by_actor_type,
    p_actor_id          := p_generated_by_actor_id,
    p_event_type        := 'audit.bundle_generated',
    p_entity_type       := 'audit_bundle',
    p_entity_id         := v_bundle_id,
    p_fleet_operator_id := p_fleet_operator_id,
    p_payload           := jsonb_build_object(
      'bundle_code', p_bundle_code,
      'report_ids', to_jsonb(p_report_ids),
      'manifest', v_manifest,
      'signature_present', (v_signature NOT LIKE 'UNSIGNED:%')
    ),
    p_severity          := 'info'
  );

  RETURN v_bundle_id;
END;
$function$
;

-- public.ottoq_complete_audit_report: every completed audit report (live pg_get_functiondef md5 b0ec150fae0619d75af4e32bafe37bc0)
CREATE OR REPLACE FUNCTION public.ottoq_complete_audit_report(p_report_id uuid, p_payload jsonb, p_event_count bigint DEFAULT NULL::bigint, p_rule_eval_count bigint DEFAULT NULL::bigint, p_prediction_count bigint DEFAULT NULL::bigint, p_anomaly_count bigint DEFAULT NULL::bigint, p_override_count bigint DEFAULT NULL::bigint, p_emergency_count bigint DEFAULT NULL::bigint, p_visit_count bigint DEFAULT NULL::bigint, p_audit_trail_complete boolean DEFAULT true, p_data_quality_score numeric DEFAULT 1.0, p_signing_key_id text DEFAULT 'system:v1'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_report     ottoq_audit_reports%ROWTYPE;
  v_hash       TEXT;
  v_signature  TEXT;
BEGIN
  v_hash := encode(digest(jsonb_strip_nulls(p_payload)::text, 'sha256'), 'hex');

  SELECT * INTO v_report FROM ottoq_audit_reports r WHERE r.report_id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'audit report % not found', p_report_id;
  END IF;

  v_signature := ottoq_sign_event(
    v_report.report_id, v_report.requested_at,
    'ottoq_engine', 'audit.report_completed',
    'audit_report', v_report.report_id,
    v_hash, p_signing_key_id
  );

  UPDATE ottoq_audit_reports
     SET generation_completed_at = NOW(),
         generation_duration_ms = EXTRACT(MILLISECOND FROM (NOW() - generation_started_at))::INTEGER,
         generation_status = 'completed',
         payload = p_payload,
         payload_hash = v_hash,
         signature = v_signature,
         signature_key_id = p_signing_key_id,
         event_count = p_event_count,
         rule_eval_count = p_rule_eval_count,
         prediction_count = p_prediction_count,
         anomaly_count = p_anomaly_count,
         override_count = p_override_count,
         emergency_count = p_emergency_count,
         visit_count = p_visit_count,
         audit_trail_complete = p_audit_trail_complete,
         data_quality_score = p_data_quality_score
   WHERE report_id = p_report_id;

  PERFORM ottoq_record_event(
    p_actor_type    := 'ottoq_engine',
    p_event_type    := 'audit.report_completed',
    p_entity_type   := 'audit_report',
    p_entity_id     := p_report_id,
    p_fleet_operator_id := v_report.fleet_operator_id,
    p_depot_id      := v_report.depot_id,
    p_payload       := jsonb_build_object(
      'report_type', v_report.report_type,
      'event_count', p_event_count,
      'audit_trail_complete', p_audit_trail_complete,
      'data_quality_score', p_data_quality_score,
      'signature_present', (v_signature IS NOT NULL)
    ),
    p_severity      := 'info',
    p_parent_event_id := v_report.source_event_id
  );
END;
$function$
;

-- public.ottoq_trg_attribution_attach: the sdr_costs_attached event, the one literal key (live pg_get_functiondef md5 9a89bcd66a2319d734828bb601b539a0)
CREATE OR REPLACE FUNCTION public.ottoq_trg_attribution_attach()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_n int;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);
  UPDATE ottoq_service_detail_records r
     SET attribution_id      = NEW.attribution_id,
         cost_components     = COALESCE(NEW.cost_components, '{}'::jsonb),
         total_cost_usd      = NEW.total_cost_usd,
         billable_amount_usd = NEW.billable_amount_usd
   WHERE r.schedule_task_id IN
         (SELECT t.id FROM schedule_tasks t
           WHERE t.vehicle_schedule_id = NEW.schedule_id OR t.schedule_id = NEW.schedule_id)
     AND r.attribution_id IS DISTINCT FROM NEW.attribution_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN
    PERFORM ottoq_record_event(
      p_actor_type => 'system', p_event_type => 'sdr_costs_attached',
      p_entity_type => 'visit_cost_attribution', p_entity_id => NEW.attribution_id,
      p_payload => jsonb_build_object('schedule_id', NEW.schedule_id,
                                      'sdrs_updated', v_n,
                                      'total_cost_usd', NEW.total_cost_usd),
      p_actor_id => 'ottoq_trg_attribution_attach', p_actor_metadata => '{}'::jsonb,
      p_fleet_operator_id => NEW.fleet_operator_id, p_depot_id => NEW.depot_id,
      p_previous_state => NULL, p_new_state => NULL, p_severity => NULL,
      p_correlation_id => NULL, p_parent_event_id => NULL,
      p_related_task_id => NULL, p_related_schedule_id => NEW.schedule_id,
      p_related_decision_id => NULL, p_outcome => 'succeeded', p_latency_ms => NULL,
      p_ingest_source => 'kernel', p_signing_key_id => 'system:v1',
      p_data_source => 'production', p_sim_run_id => NULL);
  END IF;
  RETURN NEW;
END;
$function$
;

DROP FUNCTION public.ottoq_verify_event_signature(uuid);
-- public.ottoq_verify_event_signature (its stand-in in signing_grants_stub.sql returns another row type, so it is dropped first) (live pg_get_functiondef md5 e30eeef88da501303c546c6e6ba8c121)
CREATE OR REPLACE FUNCTION public.ottoq_verify_event_signature(p_event_id uuid)
 RETURNS TABLE(event_id uuid, has_signature boolean, valid boolean, algorithm text, key_id text, computed text, stored text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_event       ottoq_events%ROWTYPE;
  v_recomputed  TEXT;
BEGIN
  SELECT * INTO v_event FROM ottoq_events e WHERE e.event_id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event % not found', p_event_id;
  END IF;
  IF v_event.signature IS NULL THEN
    RETURN QUERY SELECT v_event.event_id, FALSE, FALSE, v_event.signature_algorithm,
      v_event.signature_key_id, NULL::TEXT, NULL::TEXT;
    RETURN;
  END IF;
  v_recomputed := ottoq_sign_event(
    v_event.event_id, v_event.occurred_at,
    v_event.actor_type, v_event.event_type,
    v_event.entity_type, v_event.entity_id,
    v_event.payload_hash, v_event.signature_key_id
  );
  RETURN QUERY SELECT
    v_event.event_id, TRUE, (v_recomputed = v_event.signature),
    v_event.signature_algorithm, v_event.signature_key_id,
    v_recomputed, v_event.signature;
END;
$function$
;

-- public.ottoq_verify_audit_bundle (live pg_get_functiondef md5 40afdf347eda12d04441c65456ab039c)
CREATE OR REPLACE FUNCTION public.ottoq_verify_audit_bundle(p_bundle_id uuid)
 RETURNS TABLE(out_bundle_id uuid, out_has_signature boolean, out_valid boolean, out_algorithm text, out_signing_key_id text, out_computed text, out_stored text, out_manifest_match boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_bundle ottoq_audit_bundles%ROWTYPE;
  v_recomputed TEXT;
BEGIN
  SELECT * INTO v_bundle FROM ottoq_audit_bundles b WHERE b.bundle_id = p_bundle_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bundle % not found', p_bundle_id;
  END IF;

  v_recomputed := ottoq_sign_bundle(
    v_bundle.bundle_id, v_bundle.window_start, v_bundle.window_end,
    v_bundle.sha256, v_bundle.signature_key_id
  );

  RETURN QUERY SELECT
    v_bundle.bundle_id,
    (v_bundle.signature IS NOT NULL),
    (v_recomputed IS NOT NULL AND v_recomputed = v_bundle.signature),
    v_bundle.signature_algorithm,
    v_bundle.signature_key_id,
    v_recomputed,
    v_bundle.signature,
    TRUE;
END;
$function$
;

-- the append-only guard on the event log, as live
CREATE TRIGGER trg_ottoq_events_no_update BEFORE DELETE OR UPDATE ON public.ottoq_events
  FOR EACH ROW EXECUTE FUNCTION ottoq_events_block_mutation();
-- the attribution trigger, as live
CREATE TRIGGER trg_0043_attribution_attach AFTER INSERT ON public.ottoq_visit_cost_attribution
  FOR EACH ROW EXECUTE FUNCTION ottoq_trg_attribution_attach();

-- live grants. The five keep the grants signing_grants_stub.sql gave their stand-ins (CREATE OR REPLACE keeps an ACL):
-- {postgres, authenticated, service_role}, as live before 0701. The verifiers and the attribution trigger hold the same;
-- the payload hash, its canonicaliser and the append-only guard hold PUBLIC, anon, authenticated and service_role, which
-- is what the stub's default privileges already give them.
REVOKE EXECUTE ON FUNCTION public.ottoq_verify_event_signature(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ottoq_verify_audit_bundle(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ottoq_trg_attribution_attach() FROM PUBLIC, anon;

-- the twin depot and one of its cars (CLAUDE.md rule 8), for the rows a test signs
INSERT INTO public.depots (id, slug, feed_mode) VALUES ('11111111-1111-1111-1111-111111111111', 'ottoyard-nashville-flagship', 'sim');
INSERT INTO public.vehicles (id, vehicle_class_code, fleet_operator_id, current_depot_id, home_depot_id)
VALUES ('22222222-0000-4000-8000-000000000722', 'robotaxi', '33333333-0000-4000-8000-000000000722',
        '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111');
