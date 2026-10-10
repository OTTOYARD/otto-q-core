-- tests/fixtures/public_key_stub.sql — the grants 0658 was written against, in miniature.
--
-- What it reproduces from the live engine (measured 2026-10-10, db/migrations/0658 §1):
--   * postgres's default privileges in public give the public key (anon) SELECT, REFERENCES and TRIGGER on every new
--     table (and MAINTAIN on 17) and USAGE, SELECT and UPDATE on every new sequence;
--   * some tables and views also hold anon write grants;
--   * a twin schema the public key holds a grant in but cannot enter;
--   * PostGIS's three objects, owned by supabase_admin, which granted anon and PUBLIC on them;
--   * the cockpit RPCs: one SECURITY DEFINER over a table the public key loses, one that runs as its caller and reads
--     only the catalog.
-- Loads on a plain PostgreSQL 16 or 17 as a superuser named postgres.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN CREATE ROLE supabase_admin NOLOGIN; END IF;
END $roles$;

-- Supabase's default privileges for objects postgres creates in public
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, REFERENCES, TRIGGER ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO anon, authenticated, service_role;

-- the engine's bookkeeping, as the migrations use it
CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY, taken_at timestamptz NOT NULL DEFAULT now(), label text NOT NULL,
  object_kind text NOT NULL, schema_name text NOT NULL, object_name text NOT NULL, definition text NOT NULL,
  def_md5 text NOT NULL);
CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean NOT NULL, forces_dial_restart boolean, note text, classified_at timestamptz);
CREATE TABLE public.stub_in_flight (n integer NOT NULL DEFAULT 0);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT true)
RETURNS integer LANGUAGE sql STABLE AS $f$ SELECT n FROM public.stub_in_flight LIMIT 1 $f$;
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0657_the_readiness_check_is_the_last_thing_a_visit_does', true, true, 'stub: 0658''s premise', now());

-- the fifteen the cockpits read: thirteen tables and two views
CREATE TABLE public.ottoq_arbiter_assessments (id bigserial PRIMARY KEY, area text);
CREATE TABLE public.ottoq_calibration_datasets (id bigserial PRIMARY KEY, name text);
CREATE TABLE public.ottoq_calibration_distributions (id bigserial PRIMARY KEY, name text);
CREATE TABLE public.ottoq_charge_clock_fits (id bigserial PRIMARY KEY, fit jsonb);
CREATE TABLE public.ottoq_comms_messages (msg_id bigserial PRIMARY KEY, sim_run_id uuid, msg_type text);
CREATE TABLE public.ottoq_decisions (id bigserial PRIMARY KEY, vehicle_id uuid, decision text);
CREATE TABLE public.ottoq_depot_tariffs (id bigserial PRIMARY KEY, tariff text);
CREATE TABLE public.ottoq_external_proposals (id bigserial PRIMARY KEY, vehicle_id uuid);
CREATE TABLE public.ottoq_feed_plans (id bigserial PRIMARY KEY, plan text);
CREATE TABLE public.ottoq_proposal_disposition_ledger (id bigserial PRIMARY KEY, disposition text);
CREATE TABLE public.ottoq_rules (rule_code text PRIMARY KEY);
CREATE TABLE public.ottoq_variability_catalog (code text PRIMARY KEY);
CREATE TABLE public.ottoq_vehicle_classes (class_code text PRIMARY KEY);
INSERT INTO public.ottoq_rules VALUES ('HW.002.charger_state_precondition');
INSERT INTO public.ottoq_comms_messages (msg_type) VALUES ('telemetry');
ALTER TABLE public.ottoq_decisions ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_decisions_read ON public.ottoq_decisions FOR SELECT USING (true);

-- what the cockpits do not read
CREATE TABLE public.ottoq_events (event_id bigserial PRIMARY KEY, event_type text, entity_id uuid);
CREATE TABLE public.ottoq_stall_bookings (booking_id bigserial PRIMARY KEY, stall_id uuid);
CREATE TABLE public.ottoq_visit_needs (id bigserial PRIMARY KEY, vehicle_id uuid);
CREATE TABLE public.ottoq_sim_runs (id uuid PRIMARY KEY);
CREATE TABLE public.staff_users (id uuid PRIMARY KEY, email text);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, stall_type text);
CREATE TABLE public.depots (id uuid PRIMARY KEY, name text);
CREATE TABLE public.ottoq_model_call_ledger (id bigserial PRIMARY KEY, provider text);
INSERT INTO public.ottoq_events (event_type) VALUES ('vehicle.state_changed');
-- the ones the public key could also write
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON public.ottoq_events, public.stalls TO anon;
CREATE VIEW public.ottoq_determinism_canon AS SELECT r.rule_code AS cell FROM public.ottoq_rules r;
CREATE VIEW public.ottoq_intelligence_ledger AS SELECT count(*) AS calls FROM public.ottoq_model_call_ledger;
CREATE VIEW public.ottoq_open_stalls AS SELECT * FROM public.stalls;
GRANT INSERT, UPDATE, DELETE ON public.ottoq_open_stalls TO anon;

-- a schema the public key holds a grant in but cannot enter
CREATE SCHEMA twin;
CREATE TABLE twin.ottoq_world_clock (sim_run_id uuid PRIMARY KEY);
GRANT SELECT ON twin.ottoq_world_clock TO anon;

-- PostGIS's three, owned by supabase_admin, which granted anon and PUBLIC on them
CREATE TABLE public.spatial_ref_sys (srid integer PRIMARY KEY, auth_name text);
CREATE VIEW public.geometry_columns AS SELECT 1 AS f_table_catalog;
CREATE VIEW public.geography_columns AS SELECT 1 AS f_table_catalog;
ALTER TABLE public.spatial_ref_sys OWNER TO supabase_admin;
ALTER VIEW public.geometry_columns OWNER TO supabase_admin;
ALTER VIEW public.geography_columns OWNER TO supabase_admin;
SET ROLE supabase_admin;
GRANT ALL ON public.spatial_ref_sys, public.geometry_columns, public.geography_columns TO anon;
GRANT SELECT ON public.spatial_ref_sys, public.geometry_columns, public.geography_columns TO PUBLIC;
RESET ROLE;

-- the cockpit RPCs 0658's V1 calls as the public key
CREATE FUNCTION public.ottoq_depot_cards(p_depot_id uuid, p_fleet_operator_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $f$ SELECT jsonb_build_object('events', (SELECT count(*) FROM public.ottoq_events)) $f$;
CREATE FUNCTION public.ottoq_shield_probe_posture()
RETURNS TABLE(action_context text, posture text) LANGUAGE sql STABLE
AS $f$ SELECT p.proname::text, 'advisory'::text FROM pg_proc p WHERE p.proname = 'ottoq_shield_probe_posture' $f$;
