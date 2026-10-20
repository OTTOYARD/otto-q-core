-- tests/fixtures/evidence_truncate_stub.sql: what db/migrations/0748 reads, as live, for tests/test_evidence_truncate_guard_sql.py.
--
-- The live shape db/migrations/0748 reads (gxdrcyphqjzjsuhxuqtg, read 2026-10-17 between 7:54 and 8:07 PM CT):
--   - the 100 evidence tables that exist, by schema and name (md5 of the sorted names 5819248f, as 0748's P1 reads it),
--     each with its registry rows' columns and classes, and its grants as the live ACLs give them;
--   - three registry rows of tables that no longer exist, and two engine rows (one table that exists, one that does not);
--   - the default privileges postgres holds in public (service_role ALL; authenticated SELECT, REFERENCES, TRIGGER on
--     tables; EXECUTE for the API roles on functions), so a table or function created here takes what it takes live;
--   - the two refusers already guarding three of the tables, by their live bodies (md5 asserted by the test), on the
--     triggers the live tables carry;
--   - stubs: ottoq_sim_runs (its status check), ottoq_cert_lineage and ottoq_schema_snapshots (their live columns), and
--     ottoq_certification_in_flight (the live function's simulation hook only; the live one also counts the rigs in
--     pg_stat_activity).
-- PostgreSQL 16 has no MAINTAIN privilege; nothing here reads it.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, REFERENCES, TRIGGER ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

CREATE SCHEMA IF NOT EXISTS proof_0015;

CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY,
  status text NOT NULL DEFAULT 'initializing',
  CONSTRAINT ottoq_sim_runs_status_check CHECK (status = ANY (ARRAY['initializing', 'running', 'paused', 'completed',
                                                                    'failed', 'aborted']))
);
CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY,
  forces_recert boolean NOT NULL DEFAULT true,
  note text NOT NULL,
  classified_at timestamptz NOT NULL DEFAULT now(),
  forces_dial_restart boolean
);
CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY,
  taken_at timestamptz NOT NULL DEFAULT now(),
  label text NOT NULL,
  object_kind text NOT NULL,
  schema_name text NOT NULL,
  object_name text NOT NULL,
  definition text NOT NULL,
  def_md5 text NOT NULL
);
CREATE TABLE public.ottoq_run_scope_registry (
  table_schema text NOT NULL,
  table_name text NOT NULL,
  column_name text NOT NULL,
  class text NOT NULL,
  note text,
  registered_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_run_scope_registry_class_check CHECK (class = ANY (ARRAY['engine', 'stamp', 'evidence', 'run_ledger'])),
  CONSTRAINT ottoq_run_scope_registry_pkey PRIMARY KEY (table_schema, table_name, column_name)
);

CREATE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean DEFAULT true)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN current_setting('ottoq.simulate_certification_in_flight', true) = 'on' THEN 1 ELSE 0 END;
$function$;

-- the two refusers, as the live catalog prints them
CREATE OR REPLACE FUNCTION public.ottoq_agent_no_truncate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  --: a row trigger cannot see TRUNCATE, so the ledgers refuse it here as well
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN NULL;
  END IF;
  RAISE EXCEPTION '% keeps every row: TRUNCATE refused. Set ottoq.agent_ledger_unlock=on in the session to override, and say why in a migration.', TG_TABLE_NAME
    USING ERRCODE = '42501';
END $function$;
REVOKE ALL ON FUNCTION public.ottoq_agent_no_truncate() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ottoq_feed_plan_promotions_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF COALESCE(current_setting('ottoq.feed_plan_promotions_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'ottoq_feed_plan_promotions is append-only evidence (0716)' USING ERRCODE = '42501';
END $function$;

-- the 100 evidence tables, their registry rows and their grants
CREATE TABLE proof_0015.hold_forecast_capture (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('proof_0015', 'hold_forecast_capture', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE proof_0015.tick_samples (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('proof_0015', 'tick_samples', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.bay_reservation_reconcile_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'bay_reservation_reconcile_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.booking_ledger_proof_2026_08_01 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'booking_ledger_proof_2026_08_01', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.booking_ledger_proof_bk_2026_08_01 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'booking_ledger_proof_bk_2026_08_01', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.build2_bookings_raw_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'build2_bookings_raw_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.build2_cert_424242 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'build2_cert_424242', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.build2_interrupted_recount_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'build2_interrupted_recount_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.build2_visit_needs_raw_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'build2_visit_needs_raw_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.build3_pre_bookings_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'build3_pre_bookings_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.build3_pre_legs_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'build3_pre_legs_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.build3_smoke_bookings_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'build3_smoke_bookings_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.build3_smoke_legs_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'build3_smoke_legs_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.busy_day_tick_probe_2026_08_01 (id bigserial PRIMARY KEY, run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'busy_day_tick_probe_2026_08_01', 'run_id', 'evidence', 'as read');
CREATE TABLE public.cert0020_runa_snapshot (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0020_runa_snapshot', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_a_after_b (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_a_after_b', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_a_bookings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_a_bookings', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_a_dispatches (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_a_dispatches', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_a_flags (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_a_flags', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_a_runrow (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_a_runrow', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_a_visitneeds (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_a_visitneeds', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_b_bookings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_b_bookings', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_b_dispatches (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_b_dispatches', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_b_flags (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_b_flags', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_b_runrow (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_b_runrow', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0022_b_visitneeds (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0022_b_visitneeds', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_a_bookings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_a_bookings', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_a_dispatches (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_a_dispatches', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_a_energy (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_a_energy', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_a_flags (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_a_flags', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_a_running (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_a_running', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_a_runrow (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_a_runrow', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_a_visitneeds (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_a_visitneeds', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_b_bookings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_b_bookings', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_b_dispatches (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_b_dispatches', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_b_energy (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_b_energy', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_b_flags (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_b_flags', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_b_runrow (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_b_runrow', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_b_visitneeds (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_b_visitneeds', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_c_needs_before (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_c_needs_before', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_c_needs_terminal (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_c_needs_terminal', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cert0023_stop_pre (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cert0023_stop_pre', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cuopt_supply_before_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cuopt_supply_before_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cuopt_supply_ledger_2026_08_03 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cuopt_supply_ledger_2026_08_03', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.cuopt_supply_proof_2026_08_02 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'cuopt_supply_proof_2026_08_02', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.fwd2_pre909_card (id bigserial PRIMARY KEY, run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'fwd2_pre909_card', 'run_id', 'evidence', 'as read');
CREATE TABLE public.fwd2_pre909_runrow (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'fwd2_pre909_runrow', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.fwd2_urgency_samples (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'fwd2_urgency_samples', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.fwd3_postboot_wear (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'fwd3_postboot_wear', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.fwd3_postrun_bookings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'fwd3_postrun_bookings', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.fwd3_postrun_legs (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'fwd3_postrun_legs', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.fwd3_postrun_wear (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'fwd3_postrun_wear', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.fwd3_prerun_wear (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'fwd3_prerun_wear', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.mig0003_smoke_receipt_bookings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'mig0003_smoke_receipt_bookings', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.mig0003_smoke_receipt_decisions (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'mig0003_smoke_receipt_decisions', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.mig0006_runrows (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'mig0006_runrows', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.mig0006_smoke (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'mig0006_smoke', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.mig0009_pre_dispatches (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'mig0009_pre_dispatches', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.mig0009_pre_visit_needs (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'mig0009_pre_visit_needs', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.mig0009_run920_dispatches (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'mig0009_run920_dispatches', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_ab_runs (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_ab_runs', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_agent_charge_orders (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_agent_charge_orders', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_agent_charge_orders FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_agent_charge_orders TO service_role;
GRANT SELECT ON TABLE public.ottoq_agent_charge_orders TO authenticated;
CREATE TABLE public.ottoq_agent_pass_evidence (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_agent_pass_evidence', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_agent_pass_evidence FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_agent_pass_evidence TO service_role;
CREATE TABLE public.ottoq_agent_requests (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_agent_requests', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_agent_requests FROM PUBLIC, anon, authenticated, service_role;
CREATE TABLE public.ottoq_challenger_findings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_challenger_findings', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_challenger_findings FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_challenger_findings TO service_role;
GRANT SELECT ON TABLE public.ottoq_challenger_findings TO authenticated;
CREATE TABLE public.ottoq_channel_health (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_channel_health', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_channel_health FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_channel_health TO service_role;
CREATE TABLE public.ottoq_charge_duration_ledger (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_charge_duration_ledger', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_charge_duration_ledger FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_charge_duration_ledger TO service_role;
CREATE TABLE public.ottoq_charge_order_attribution (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_charge_order_attribution', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_charge_order_attribution FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_charge_order_attribution TO service_role;
GRANT SELECT ON TABLE public.ottoq_charge_order_attribution TO authenticated;
CREATE TABLE public.ottoq_charge_order_hindsight (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_charge_order_hindsight', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_charge_order_hindsight FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_charge_order_hindsight TO service_role;
GRANT SELECT ON TABLE public.ottoq_charge_order_hindsight TO authenticated;
CREATE TABLE public.ottoq_charge_order_reattributions (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_charge_order_reattributions', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_charge_order_reattributions FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_charge_order_reattributions TO service_role;
GRANT SELECT ON TABLE public.ottoq_charge_order_reattributions TO authenticated;
CREATE TABLE public.ottoq_charge_order_regrades (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_charge_order_regrades', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_charge_order_regrades FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_charge_order_regrades TO service_role;
GRANT SELECT ON TABLE public.ottoq_charge_order_regrades TO authenticated;
CREATE TABLE public.ottoq_charge_order_snapshots (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_charge_order_snapshots', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_charge_order_snapshots FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_charge_order_snapshots TO service_role;
GRANT SELECT ON TABLE public.ottoq_charge_order_snapshots TO authenticated;
CREATE TABLE public.ottoq_determinism_verdict_ledger (id bigserial PRIMARY KEY, arm_a_run uuid, arm_b_run uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_determinism_verdict_ledger', 'arm_a_run', 'evidence', 'as read');
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_determinism_verdict_ledger', 'arm_b_run', 'evidence', 'as read');
CREATE TABLE public.ottoq_dial_pair_ledger (id bigserial PRIMARY KEY, run_a uuid, run_b uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_dial_pair_ledger', 'run_a', 'evidence', 'as read');
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_dial_pair_ledger', 'run_b', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_dial_pair_ledger FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_dial_pair_ledger TO service_role;
GRANT SELECT ON TABLE public.ottoq_dial_pair_ledger TO authenticated;
CREATE TABLE public.ottoq_dial_promotion_ledger (id bigserial PRIMARY KEY, promotion_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_dial_promotion_ledger', 'promotion_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_feed_plan_promotions (id bigserial PRIMARY KEY, plan_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_feed_plan_promotions', 'plan_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_feed_plan_promotions FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_feed_plan_promotions TO service_role;
CREATE TABLE public.ottoq_layout_backup_0011_stall_bookings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_layout_backup_0011_stall_bookings', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_layout_backup_0011_stall_bookings FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_layout_backup_0011_stall_bookings TO service_role;
CREATE TABLE public.ottoq_model_artifacts (id bigserial PRIMARY KEY, source_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_model_artifacts', 'source_run_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_model_call_ledger (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_model_call_ledger', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_owner_commands (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_owner_commands', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_owner_commands FROM PUBLIC, anon, authenticated, service_role;
CREATE TABLE public.ottoq_proposal_disposition_ledger (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_proposal_disposition_ledger', 'sim_run_id', 'evidence', 'as read');
GRANT SELECT ON TABLE public.ottoq_proposal_disposition_ledger TO anon;
CREATE TABLE public.ottoq_proposer_fire_log (id bigserial PRIMARY KEY, sim_run_id uuid, tick_seq integer);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_proposer_fire_log', 'sim_run_id', 'evidence', 'as read');
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_proposer_fire_log', 'tick_seq', 'stamp', 'as read');
CREATE TABLE public.ottoq_ready_promise_updates (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_ready_promise_updates', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_ready_promise_updates FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT ON TABLE public.ottoq_ready_promise_updates TO service_role;
CREATE TABLE public.ottoq_ready_promises (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_ready_promises', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_ready_promises FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_ready_promises TO service_role;
CREATE TABLE public.ottoq_run_dial_ledger (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_run_dial_ledger', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_site_power_excursion_ledger (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_site_power_excursion_ledger', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_site_power_plan_ledger (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_site_power_plan_ledger', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_space_integrity_ledger (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_space_integrity_ledger', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.ottoq_throughput_scores (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_throughput_scores', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_throughput_scores FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.ottoq_throughput_scores TO service_role;
GRANT SELECT ON TABLE public.ottoq_throughput_scores TO authenticated;
CREATE TABLE public.ottoq_throughput_sweep_arms (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_throughput_sweep_arms', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_throughput_sweep_arms FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.ottoq_throughput_sweep_arms TO service_role;
GRANT SELECT ON TABLE public.ottoq_throughput_sweep_arms TO authenticated;
CREATE TABLE public.ottoq_vehicle_scout_findings (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'ottoq_vehicle_scout_findings', 'sim_run_id', 'evidence', 'as read');
REVOKE ALL ON TABLE public.ottoq_vehicle_scout_findings FROM PUBLIC, anon, authenticated, service_role;
GRANT ALL ON TABLE public.ottoq_vehicle_scout_findings TO service_role;
CREATE TABLE public.p7_band_probe_2026_08_03 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'p7_band_probe_2026_08_03', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.pre0002_approvals_evidence (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'pre0002_approvals_evidence', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.preimport_stall_bookings_20260806 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'preimport_stall_bookings_20260806', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.prof0012_tick (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'prof0012_tick', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.proof0008_wear_prestate (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'proof0008_wear_prestate', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.proof0012_binding_blocker (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'proof0012_binding_blocker', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.proof0012_prearrival_census (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'proof0012_prearrival_census', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.smoke890_bookings_2026_08_03 (id bigserial PRIMARY KEY, sim_run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'smoke890_bookings_2026_08_03', 'sim_run_id', 'evidence', 'as read');
CREATE TABLE public.workload_determinism_proof_2026_08_02 (id bigserial PRIMARY KEY, run_id uuid);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES ('public', 'workload_determinism_proof_2026_08_02', 'run_id', 'evidence', 'as read');

-- the three tables already guarded, by the triggers they carry live
CREATE TRIGGER ottoq_agent_requests_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_agent_requests
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_owner_commands_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_owner_commands
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
CREATE TRIGGER ottoq_feed_plan_promotions_append_only BEFORE UPDATE OR DELETE OR TRUNCATE ON public.ottoq_feed_plan_promotions
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_feed_plan_promotions_append_only();

-- registry rows whose table is gone, and engine rows (one table that exists)
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES
  ('public', 'band_ab_compare_2026_08_01', 'sim_run_id', 'evidence', 'as read; the table no longer exists'),
  ('public', 'p0019_prestop_a_bookings', 'sim_run_id', 'evidence', 'as read; the table no longer exists'),
  ('public', 'phase11_cert_424242', 'sim_run_id', 'evidence', 'as read; the table no longer exists'),
  ('public', 'cuopt_invocation_log', 'sim_run_id', 'engine', 'as read'),
  ('public', 'ottoq_decisions', 'sim_run_id', 'engine', 'as read; not created here');
CREATE TABLE public.cuopt_invocation_log (id bigserial PRIMARY KEY, sim_run_id uuid);

-- a row in the table 0748's V3 probes, and in two others the tests truncate
INSERT INTO public.p7_band_probe_2026_08_03 (sim_run_id) VALUES ('a0000000-0000-0000-0000-000000000748');
INSERT INTO public.ottoq_model_call_ledger (sim_run_id) VALUES ('a0000000-0000-0000-0000-000000000748');
INSERT INTO proof_0015.tick_samples (sim_run_id) VALUES ('a0000000-0000-0000-0000-000000000748');
