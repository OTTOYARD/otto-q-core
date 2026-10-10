-- ============================================================================================================
-- tests/fixtures/v2_door_stub_engine.sql
--
-- A STUB ENGINE for executing db/migrations/0649 onward (the v2 operator door) on a throwaway PostgreSQL. NOT the
-- engine, NOT a migration, NEVER applied anywhere real: the guard below refuses a database that has ottoq_events or a
-- supabase_migrations schema. Loaded by tests/test_v2_door_sql.py into a database it creates and drops.
--
-- WHAT IS REAL IN HERE AND WHAT IS NOT:
--   * COPIED VERBATIM from the live catalog (gxdrcyphqjzjsuhxuqtg, read-only, 2026-10-10 ~00:35 UTC), and the test
--     asserts its md5(pg_get_functiondef()) against the md5 read from the live catalog then:
--       public.ottoq_check_run_scope_registry   4d0011f6bfd5d7448273ccd7c6bcc5dc   (what the purge refuses on)
--   * STUBBED with the live signature: ottoq_record_event (writes stub_events), ottoq_ingest_vehicle_signal (writes
--     stub_signals), ottoq_certification_in_flight (reads stub_in_flight).
--   * POSTGIS IS A STAND-IN. Neither this sandbox nor CI's postgres:16 image has PostGIS, so geography is a domain
--     over text and the five ST_ functions the door uses keep a lng/lat BOUNDING BOX, not a hull: a point well
--     outside the stalls is outside, as it is live, and the exact edge is not modelled. The live geofence is checked
--     where it is real, in 0650's own V3 against the live stalls.
--   * Tables carry only the columns something here reads or writes, with the live constraints a migration checks
--     by name (ottow_api_keys_source_check, ottoq_vehicle_commands_reason_code_check) copied exactly.
--   * The roles anon / authenticated / service_role and Supabase's default privileges on schema public are
--     reproduced, so a REVOKE that removes nothing is caught here as it would be in production.
-- ============================================================================================================

DO $guard$
BEGIN
  IF to_regclass('public.ottoq_events') IS NOT NULL OR EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'supabase_migrations') THEN
    RAISE EXCEPTION 'v2_door_stub_engine.sql is a TEST STUB and this looks like a real engine. Refusing.';
  END IF;
END $guard$;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $roles$;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS twin;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA public, extensions, ottoq, twin TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, REFERENCES, TRIGGER ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- ── the PostGIS stand-in: a value is 'minlng minlat maxlng maxlat' (a point has min = max) ──
CREATE DOMAIN public.geography AS text;
CREATE DOMAIN public.geometry AS text;
CREATE FUNCTION public.ST_MakePoint(lng float8, lat float8) RETURNS public.geometry LANGUAGE sql IMMUTABLE AS
  $f$ SELECT format('%s %s %s %s', lng, lat, lng, lat)::public.geometry $f$;
CREATE FUNCTION public.ST_SetSRID(g public.geometry, srid integer) RETURNS public.geometry LANGUAGE sql IMMUTABLE AS
  $f$ SELECT g $f$;
CREATE FUNCTION public.stub_bbox_union(a text, b text) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT CASE WHEN a IS NULL THEN b WHEN b IS NULL THEN a ELSE format('%s %s %s %s',
    least(split_part(a,' ',1)::float8, split_part(b,' ',1)::float8), least(split_part(a,' ',2)::float8, split_part(b,' ',2)::float8),
    greatest(split_part(a,' ',3)::float8, split_part(b,' ',3)::float8), greatest(split_part(a,' ',4)::float8, split_part(b,' ',4)::float8)) END
$f$;
CREATE AGGREGATE public.ST_Collect(public.geometry) (SFUNC = public.stub_bbox_union, STYPE = text);
CREATE FUNCTION public.ST_ConvexHull(g text) RETURNS public.geometry LANGUAGE sql IMMUTABLE AS $f$ SELECT g::public.geometry $f$;
CREATE FUNCTION public.ST_Buffer(g public.geography, metres float8) RETURNS public.geography LANGUAGE sql IMMUTABLE AS $f$
  SELECT format('%s %s %s %s', split_part(g,' ',1)::float8 - metres / 90000.0, split_part(g,' ',2)::float8 - metres / 111000.0,
                               split_part(g,' ',3)::float8 + metres / 90000.0, split_part(g,' ',4)::float8 + metres / 111000.0)::public.geography
$f$;
CREATE FUNCTION public.ST_Covers(area public.geography, pt public.geography) RETURNS boolean LANGUAGE sql IMMUTABLE AS $f$
  SELECT split_part(pt,' ',1)::float8 >= split_part(area,' ',1)::float8 AND split_part(pt,' ',3)::float8 <= split_part(area,' ',3)::float8
     AND split_part(pt,' ',2)::float8 >= split_part(area,' ',2)::float8 AND split_part(pt,' ',4)::float8 <= split_part(area,' ',4)::float8
$f$;

-- ── enums (live labels, 2026-10-09) ──
CREATE TYPE public.vehicle_state AS ENUM ('offline','deployed','en_route_to_depot','arrived_at_gate','staged_awaiting_service',
  'charging_dcfc','charging_l2','charge_complete_holding','in_wash_bay','in_detail_bay','in_service_bay','service_complete_holding',
  'staged_for_departure','en_route_to_deployment','emergency_staged','tow_requested','out_of_service');
CREATE TYPE public.stall_type AS ENUM ('dcfc','l2','wash_bay','detail_bay','service_bay','staging','parking','safety');
CREATE TYPE public.exception_type AS ENUM ('charger_fault','excessive_contamination','other','safety_concern','schedule_conflict',
  'sensor_anomaly','service_bay_fault','tire_issue','unauthorized_movement','vehicle_damage','vehicle_malfunction',
  'vehicle_unresponsive','wash_system_fault');
CREATE TYPE public.exception_severity AS ENUM ('low','medium','high','critical');
CREATE TYPE public.exception_status AS ENUM ('open','acknowledged','in_progress','resolved','escalated');

-- ── tables: the columns something here reads or writes ──
CREATE TABLE public.depots (id uuid PRIMARY KEY, name text NOT NULL, geofence public.geography);
CREATE TABLE public.fleet_operators (id uuid PRIMARY KEY, name text NOT NULL);
CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY, fleet_operator_id uuid REFERENCES public.fleet_operators(id), home_depot_id uuid, current_depot_id uuid,
  display_name text, current_state public.vehicle_state NOT NULL DEFAULT 'deployed', current_soc integer,
  current_soc_updated_at timestamptz, current_soc_source text, last_state_change timestamptz, current_stall_id uuid,
  CONSTRAINT vehicles_current_soc_source_check CHECK (((current_soc_source IS NULL) OR (current_soc_source = ANY (ARRAY['oem_telemetry'::text, 'ocpp_meter'::text, 'manual'::text, 'estimated'::text])))));
CREATE TABLE public.stalls (
  id uuid PRIMARY KEY, depot_id uuid NOT NULL, stall_code text NOT NULL, stall_type public.stall_type NOT NULL,
  absolute_point public.geography, ocpp_charger_id uuid, zone text, current_vehicle_id uuid, reserved_by uuid,
  reservation_expires_at timestamptz, status text DEFAULT 'available', connector_max_kw numeric);
CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY, depot_id uuid, status text NOT NULL, run_by text, started_at timestamptz NOT NULL DEFAULT now(),
  sim_clock_current timestamptz, tick_interval_seconds integer, time_scale numeric);
CREATE TABLE public.ottoq_telemetry_packets (
  packet_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), packet_seq bigserial, vehicle_id uuid NOT NULL,
  sim_run_id uuid REFERENCES public.ottoq_sim_runs(sim_run_id), fleet_operator_id uuid,
  packet_at timestamptz NOT NULL DEFAULT now(), sim_clock_at timestamptz, soc_pct numeric, soc_source text DEFAULT 'oem_telemetry',
  battery_temp_c numeric, ambient_temp_c numeric, tire_pressures_psi numeric[], speed_kmh numeric, current_lat numeric,
  current_lng numeric, instant_power_kw numeric, vehicle_state text, odometer_km numeric, range_remaining_km numeric,
  dtc_codes text[], data_source text NOT NULL DEFAULT 'twin', packet_integrity text, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.exceptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
  depot_id uuid NOT NULL REFERENCES public.depots(id), exception_type public.exception_type NOT NULL,
  severity public.exception_severity NOT NULL, status public.exception_status NOT NULL DEFAULT 'open', title text NOT NULL,
  description text, metadata jsonb, data_source text, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_vehicle_commands (
  command_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid REFERENCES public.ottoq_sim_runs(sim_run_id),
  depot_id uuid, vehicle_id uuid NOT NULL REFERENCES public.vehicles(id), command_type text NOT NULL, payload jsonb,
  issued_at timestamptz NOT NULL, issued_by text NOT NULL DEFAULT 'decide_tick', status text NOT NULL DEFAULT 'issued',
  confirmed_at timestamptz, confirmed_by text, executed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
  reason_code text, reason_detail text, reacted_at timestamptz, command_seq bigserial, data_source text NOT NULL DEFAULT 'twin',
  delivered_at timestamptz, delivered_to text,
  CONSTRAINT ottoq_vehicle_commands_command_type_check CHECK ((command_type = ANY (ARRAY['dispatch'::text, 'begin_charge'::text, 'proceed_to_stall'::text, 'enter_wash'::text, 'enter_service'::text, 'stage'::text, 'hold'::text]))),
  CONSTRAINT ottoq_vehicle_commands_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text]))),
  CONSTRAINT ottoq_vehicle_commands_reason_code_check CHECK (((reason_code IS NULL) OR (reason_code = ANY (ARRAY['target_occupied'::text, 'resource_faulted'::text, 'target_unknown'::text, 'vehicle_unresponsive'::text, 'command_malformed'::text, 'no_capacity'::text, 'superseded'::text, 'vehicle_state_incompatible'::text, 'run_ended'::text, 'vehicle_declined'::text])))),
  CONSTRAINT ottoq_vehicle_commands_status_check CHECK ((status = ANY (ARRAY['issued'::text, 'confirmed'::text, 'executed'::text, 'refused'::text, 'expired'::text]))));
CREATE TABLE public.ottoq_event_types_catalog (
  event_type text PRIMARY KEY, category text NOT NULL, description text, payload_schema jsonb, emitter text,
  default_severity text, introduced_in text, deprecated boolean DEFAULT false, created_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_run_scope_registry (
  table_schema text NOT NULL, table_name text NOT NULL, column_name text NOT NULL, class text NOT NULL, note text,
  registered_at timestamptz DEFAULT now(), PRIMARY KEY (table_schema, table_name, column_name));
CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY, label text NOT NULL, object_kind text NOT NULL, schema_name text, object_name text,
  definition text, def_md5 text, captured_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean NOT NULL, forces_dial_restart boolean, note text, classified_at timestamptz);
CREATE TABLE public.ottow_api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid NOT NULL REFERENCES public.depots(id), key_hash text NOT NULL,
  key_prefix text NOT NULL, source text NOT NULL, source_name text NOT NULL, allowed_platforms text[],
  is_active boolean DEFAULT true, last_used_at timestamptz, created_at timestamptz DEFAULT now(), created_by_user_id uuid,
  CONSTRAINT ottow_api_keys_source_check CHECK ((source = ANY (ARRAY['oem_webhook'::text, 'fleet_api'::text, 'vehicle_telemetry'::text]))));

CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, depot_id uuid, ocpp_identifier text, station_state text);
CREATE TABLE public.ottoq_stall_bookings (
  booking_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid, stall_id uuid, vehicle_id uuid, purpose text,
  during tstzrange, state text, booked_at timestamptz NOT NULL DEFAULT now());

-- Supabase Vault, as far as the door uses it: create_secret and the decrypted view (the stand-in stores plain text)
CREATE SCHEMA IF NOT EXISTS vault;
CREATE TABLE vault.secrets (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text UNIQUE, description text, secret text);
CREATE FUNCTION vault.create_secret(new_secret text, new_name text DEFAULT NULL, new_description text DEFAULT '', new_key_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE sql AS $f$ INSERT INTO vault.secrets (name, description, secret) VALUES (new_name, new_description, new_secret) RETURNING id $f$;
CREATE VIEW vault.decrypted_secrets AS SELECT id, name, description, secret, secret AS decrypted_secret FROM vault.secrets;

-- what the stubs record
CREATE TABLE public.stub_events (n bigserial, event_type text, actor_type text, actor_id text, entity_id uuid, payload jsonb,
  ingest_source text, data_source text, sim_run_id uuid, severity text);
CREATE TABLE public.stub_signals (n bigserial, vehicle_id uuid, soc numeric, eta_min numeric, source text);
CREATE TABLE public.stub_in_flight (n integer NOT NULL DEFAULT 0);
INSERT INTO public.stub_in_flight VALUES (0);

-- ── the functions the migrations call, with the live signatures ──
CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT true)
RETURNS integer LANGUAGE sql STABLE AS $f$ SELECT n FROM public.stub_in_flight LIMIT 1 $f$;

CREATE OR REPLACE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text, p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid, p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer, p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
RETURNS uuid LANGUAGE plpgsql AS $f$
BEGIN
  -- the live function's actor_type CHECK, which is what makes the old ack path's 'vehicle' fail
  IF p_actor_type NOT IN ('fleet_operator_admin','fleet_operator_viewer','oem_dispatch_webhook','oem_admin_console','depot_tech',
     'depot_supervisor','command_center_operator','ottoq_engine','ottow_driver','ottow_dispatcher','otto_response_agent',
     'system_scheduler','external_sensor','ocpp_charger','av_vehicle','bess_controller','solar_controller','migration_script',
     'system','unknown') THEN
    RAISE EXCEPTION 'new row for relation "ottoq_events" violates check constraint "ottoq_events_actor_type_check"' USING ERRCODE = '23514';
  END IF;
  INSERT INTO public.stub_events (event_type, actor_type, actor_id, entity_id, payload, ingest_source, data_source, sim_run_id, severity)
  VALUES (p_event_type, p_actor_type, p_actor_id, p_entity_id, p_payload, p_ingest_source, p_data_source, p_sim_run_id, p_severity);
  RETURN gen_random_uuid();
END $f$;

CREATE OR REPLACE FUNCTION public.ottoq_ingest_vehicle_signal(p_vehicle_id uuid, p_soc_pct numeric, p_eta_min numeric, p_source text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO public.stub_signals (vehicle_id, soc, eta_min, source) VALUES (p_vehicle_id, p_soc_pct, p_eta_min, p_source);
  RETURN jsonb_build_object('evaluated', true, 'stub', true);
END $f$;

CREATE OR REPLACE FUNCTION public.ottoq_effective_target_soc_at(p_vehicle_id uuid, p_as_of timestamp with time zone)
RETURNS numeric LANGUAGE sql STABLE AS $f$ SELECT 100::numeric $f$;  -- the fleet default under every contract today (0539)

-- 0649's premise: 0648 is classified
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0648_the_command_dock_answers_only_the_platform', false, false, 'stub: 0649''s premise', now());

CREATE OR REPLACE FUNCTION public.ottoq_check_run_scope_registry()
 RETURNS TABLE(table_schema text, table_name text, column_name text, problem text, severity text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- (a) a run-scoped column that nobody has classified
  --
  --     WIDENED 0408. This read IN ('public','proof_0015') and therefore could never see the
  --     `twin` or `ottoq` schemas. It returned clean while twin.arm_cycles (54,098 rows) and
  --     twin.arm_registrations (28,841) sat unclassified, which meant the purge never touched
  --     them and they accumulated ~1,400 runs of orphans -- 97% of their rows. db/checks/0316
  --     then read that accumulation as one run's activity. The gate whose entire job is to
  --     notice an unclassified run-scoped table could not look where two of them were.
  --
  --     Severity stays 'warn': the purge raises on 'block' only, so this can report an
  --     unclassified table on every run start without ever refusing one.
  SELECT c.table_schema::text, c.table_name::text, c.column_name::text,
         'unregistered run-scoped column'::text, 'warn'::text
    FROM information_schema.columns c
    JOIN pg_class rc ON rc.relname = c.table_name
    JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
   WHERE rc.relkind = 'r'
     AND c.table_schema IN ('public','ottoq','twin','proof_0015')
     AND c.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_schema = c.table_schema
                        AND g.table_name   = c.table_name
                        AND g.column_name  = c.column_name)
  UNION ALL
  -- (b1) EXISTENCE. Unchanged, over EVERY engine/stamp row. to_regclass (not a
  --      ::regclass cast) is deliberate: the cast RAISES on a dropped table, and
  --      the purge calls this guard, so one dropped scratch table would have made
  --      every run start fail.
  SELECT g.table_schema, g.table_name, g.column_name,
         'registered engine/stamp table no longer exists',
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND to_regclass(g.table_schema||'.'||g.table_name) IS NULL
  UNION ALL
  -- (b2) THE FK REQUIREMENT, narrowed by 0344 to rows whose column is an actual
  --      run-scoping key -- the same four names (a) watches.
  --
  --      WHY. The registry is per-COLUMN; this check was per-TABLE. So
  --      ottoq_proposer_fire_log.tick_seq, class 'stamp', demanded an FK to
  --      ottoq_sim_runs -- while the same table's sim_run_id is class 'evidence'
  --      and must OUTLIVE the run. 0267 satisfied the demand by adding the FK,
  --      and that FK then made ottoq_purge_prior_runs step (5) raise 23503,
  --      which made ottoq_start_demo_run raise, which broke the Twin's start
  --      door. The table was required to block the purge it was registered to
  --      survive.
  --
  --      tick_seq is an integer tick counter. It is not a key into
  --      ottoq_sim_runs and no FK on it could exist -- the registry's own note
  --      says "Provenance, not a scoping key; sim_run_id is." Orphaning is
  --      impossible through a column that does not reference the parent, so no
  --      protection is lost. This considers strictly FEWER rows than before, so
  --      it cannot invent a block; 0344 A5 asserts ottoq_external_proposals is
  --      still required to keep its FK by its own engine-class row.
  SELECT g.table_schema, g.table_name, g.column_name,
         'engine/stamp run-key column''s table has no FK to ottoq_sim_runs',
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND g.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND to_regclass(g.table_schema||'.'||g.table_name) IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint k
        WHERE k.contype = 'f'
          AND k.conrelid = to_regclass(g.table_schema||'.'||g.table_name)
          AND k.confrelid = 'public.ottoq_sim_runs'::regclass)
  UNION ALL
  -- (c) any FK to the run table that has become CASCADE
  SELECT n.nspname::text, c.relname::text, 'sim_run_id'::text,
         'FK to ottoq_sim_runs is ON DELETE CASCADE — history can be silently erased',
         'block'
    FROM pg_constraint k
    JOIN pg_class c ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE k.contype = 'f'
     AND k.confrelid = 'public.ottoq_sim_runs'::regclass
     AND k.confdeltype = 'c'
  UNION ALL
  -- (d) ADDED 0348. An engine-class table whose append-only DELETE guard never
  --     learned the purge's arming protocol. The registry says the rows must not
  --     outlive their run; the guard says they can never be deleted. Both cannot
  --     be true, and the loser is every simulation start.
  --
  --     ottoq_recall_refusals was exactly this: class 'engine', guard raising
  --     unconditionally, six rows, and ottoq_start_demo_run could not complete.
  --     Its FK then made ottoq_recall_decisions undeletable too -- one guard,
  --     two survivors.
  --
  --     TEXTUAL, on the COMMENT-STRIPPED body, and that is stated because it
  --     matters: prosrc carries comments, and this repo has twice been fooled by
  --     matching them (0346 A1a, 0220's LIMIT 1 count). Precision measured on the
  --     live catalog rather than assumed: flags 1 of 4, the right one.
  --
  --     engine + DELETE only. The stamp/UPDATE mirror is real but unlistable
  --     this way -- `vehicles` carries six UPDATE triggers that are loggers and
  --     workers, not guards, and none honours the flag because none needs to.
  --     Flagging those would put six false blocks on the purge's own
  --     precondition. Named, not silently included.
  SELECT DISTINCT
         g.table_schema, g.table_name, g.column_name,
         'engine table''s append-only DELETE guard ('||p.proname||
           ') does not honour set_config(''ottoq.retention'') — the purge cannot clear it',
         'block'
    FROM public.ottoq_run_scope_registry g
    JOIN pg_class c   ON c.oid = to_regclass(g.table_schema||'.'||g.table_name)
    JOIN pg_trigger t ON t.tgrelid = c.oid AND NOT t.tgisinternal AND (t.tgtype & 8) > 0
    JOIN pg_proc p    ON p.oid = t.tgfoid
   WHERE g.class = 'engine'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g') ILIKE '%RAISE EXCEPTION%'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g') NOT ILIKE '%ottoq.retention%';
$function$;

-- the stand-in's coordinate readers (a point's min corner)
CREATE FUNCTION public.ST_X(g public.geometry) RETURNS float8 LANGUAGE sql IMMUTABLE AS $f$ SELECT split_part(g,' ',1)::float8 $f$;
CREATE FUNCTION public.ST_Y(g public.geometry) RETURNS float8 LANGUAGE sql IMMUTABLE AS $f$ SELECT split_part(g,' ',2)::float8 $f$;
