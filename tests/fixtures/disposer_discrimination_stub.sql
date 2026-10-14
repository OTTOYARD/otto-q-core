-- tests/fixtures/disposer_discrimination_stub.sql -- what 0708 reads, in miniature: ottoq_charge_order_grades (a view on
-- live, reading the newest regrade; a table here with the columns 0708 reads) and ottoq_sim_runs. No live definition is
-- carried, so there is no md5 to match. Used by tests/test_disposer_discrimination_sql.py.
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
-- stand-in: nothing is in flight in a scratch database
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, scenario_code text, random_seed bigint, started_at timestamptz);
CREATE TABLE public.ottoq_charge_order_grades (order_id bigserial PRIMARY KEY, sim_run_id uuid, depot_id uuid,
  decision boolean, taken boolean, p_win numeric, outcome text, graded_at timestamptz DEFAULT now());
