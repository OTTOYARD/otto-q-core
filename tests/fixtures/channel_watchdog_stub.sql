-- tests/fixtures/channel_watchdog_stub.sql -- the tables 0707's watchdog reads, in miniature, with the live column names
-- (read 2026-10-13 19:22-19:31 UTC from information_schema). pg_cron and pg_net are stood in by plain tables in their
-- own schemas; nothing here is a live definition, so there is no md5 to match. Used by tests/test_channel_watchdog_sql.py.
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS cron;
CREATE SCHEMA IF NOT EXISTS net;
-- stand-ins for pg_cron's catalog (the columns the watchdog reads, plus end_time)
CREATE TABLE cron.job (jobid bigserial PRIMARY KEY, jobname text UNIQUE, schedule text, command text,
  active boolean NOT NULL DEFAULT true);
CREATE TABLE cron.job_run_details (runid bigserial PRIMARY KEY, jobid bigint, start_time timestamptz,
  end_time timestamptz, status text, return_message text);
-- stand-in for pg_cron's cron.schedule(name, schedule, command): upsert by name
CREATE FUNCTION cron.schedule(p_name text, p_schedule text, p_command text) RETURNS bigint LANGUAGE sql AS $f$
  INSERT INTO cron.job (jobname, schedule, command) VALUES (p_name, p_schedule, p_command)
  ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command RETURNING jobid $f$;
-- stand-in for pg_net's reply table (live columns)
CREATE TABLE net._http_response (id bigserial PRIMARY KEY, status_code integer, content_type text, headers jsonb,
  content text, timed_out boolean, error_msg text, created timestamptz NOT NULL DEFAULT now());

-- stand-in: nothing is in flight in a scratch database
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
INSERT INTO public.ottoq_cert_lineage VALUES ('0703_every_agent_pass_keeps_what_it_saw_and_what_it_changed', false, 'stub',
  now(), false);
CREATE TABLE public.ottoq_run_scope_registry (table_schema text, table_name text, column_name text, class text, note text,
  registered_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_policy_params (scope_type text, scope_id uuid, param_key text, param_value numeric,
  updated_by text, updated_at timestamptz DEFAULT now(), PRIMARY KEY (scope_type, scope_id, param_key));
-- stand-in: run scope, then the default (the live function also reads depot and global tiers)
CREATE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric) RETURNS numeric
LANGUAGE sql STABLE AS $f$
  SELECT COALESCE((SELECT param_value FROM public.ottoq_policy_params
                    WHERE scope_type = 'run' AND scope_id = p_sim_run_id AND param_key = p_param_key), p_default) $f$;

CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid, status text, tick_count bigint,
  sim_clock_current timestamptz, started_at timestamptz, last_tick_at timestamptz, next_tick_due_at timestamptz,
  run_by text);
CREATE TABLE public.ottoq_agent_pass_evidence (pass_id bigserial PRIMARY KEY, chain_id text, sim_run_id uuid,
  consulted boolean, model_answered text, attempts jsonb, total_ms integer, recorded_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_model_call_ledger (call_id bigserial PRIMARY KEY, sim_run_id uuid, provider text,
  http_status integer, outcome text, latency_ms integer, called_at timestamptz DEFAULT now());
