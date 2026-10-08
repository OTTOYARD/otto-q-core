-- tests/fixtures/agent_arbiter_stub.sql -- the tables 0619-0621 read beyond tests/fixtures/agent_charge_order_stub.sql.
-- GENERATED from the live catalog on 2026-10-08 (column lists by format_type; defaults, and the one generated column,
-- by pg_get_expr). pg_cron is absent on a scratch PostgreSQL, so cron.job and cron.schedule/unschedule are minimal
-- stand-ins that record a job the way pg_cron's catalog does. Loaded after agent_charge_order_stub.sql by
-- tests/test_agent_arbiter_sql.py.
SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS cron;
CREATE TABLE IF NOT EXISTS cron.job (jobid bigserial PRIMARY KEY, schedule text NOT NULL, command text NOT NULL,
                                     nodename text DEFAULT 'localhost', nodeport integer DEFAULT 5432,
                                     database text DEFAULT current_database(), username text DEFAULT current_user,
                                     active boolean DEFAULT true, jobname text);
-- stand-in: pg_cron's cron.schedule(job_name, schedule, command) upserts by name and returns the job id
CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text) RETURNS bigint
LANGUAGE plpgsql AS $fn$
DECLARE v bigint;
BEGIN
  UPDATE cron.job SET schedule = $2, command = $3 WHERE jobname = $1 RETURNING jobid INTO v;
  IF v IS NULL THEN INSERT INTO cron.job (jobname, schedule, command) VALUES ($1, $2, $3) RETURNING jobid INTO v; END IF;
  RETURN v;
END $fn$;
CREATE OR REPLACE FUNCTION cron.unschedule(job_name text) RETURNS boolean
LANGUAGE sql AS $fn$ WITH d AS (DELETE FROM cron.job WHERE jobname = $1 RETURNING 1) SELECT count(*) > 0 FROM d $fn$;

CREATE TABLE public.ottoq_charge_duration_ledger (session_id uuid NOT NULL, recorded_at timestamp with time zone NOT NULL DEFAULT now(), source_kind text NOT NULL, sim_run_id uuid, run_by text, tick_interval_seconds integer, depot_id uuid, stall_id uuid, charger_type text, charger_kw numeric, vehicle_id uuid, vehicle_kw numeric, battery_kwh numeric, soc_start integer, soc_end integer, ambient_temp_c numeric, depot_air_c numeric, started_at timestamp with time zone, ended_at timestamp with time zone, duration_min numeric, energy_delivered_kwh numeric, stopped_reason text, nominal_min numeric, detail jsonb NOT NULL DEFAULT '{}'::jsonb, capture_version smallint NOT NULL DEFAULT 2, charge_target_soc numeric, visit_target_soc numeric, visit_id uuid, soc_at_stop numeric, booking_id uuid, booked_from timestamp with time zone, booked_to timestamp with time zone, booking_state text, booking_source text, tick_minutes numeric);

CREATE TABLE public.ottoq_vehicle_dispatches (dispatch_id uuid NOT NULL DEFAULT gen_random_uuid(), vehicle_id uuid NOT NULL, sim_run_id uuid, fleet_operator_id uuid, dispatched_at timestamp with time zone NOT NULL, scheduled_return_at timestamp with time zone NOT NULL, actual_return_at timestamp with time zone, planned_duration_min numeric NOT NULL, actual_duration_min numeric, arrival_jitter_min numeric, soc_at_dispatch_pct numeric, soc_at_return_pct numeric, energy_consumed_kwh numeric, miles_driven numeric, return_trigger text, return_state text, status text NOT NULL DEFAULT 'active'::text, data_source text DEFAULT 'twin'::text, created_at timestamp with time zone NOT NULL DEFAULT now(), returning_started_at timestamp with time zone, return_eta_minutes numeric, return_evidence jsonb, heartbeat_count integer NOT NULL DEFAULT 0, planned_return_at timestamp with time zone GENERATED ALWAYS AS (((dispatched_at AT TIME ZONE 'UTC'::text) + ((planned_duration_min)::double precision * '00:01:00'::interval)) AT TIME ZONE 'UTC'::text) STORED, eta_refreshed_at timestamp with time zone, eta_source text);

-- 0621 reads what happened after a checked order: the run's charge sessions and its fault events (live catalog,
-- 2026-10-08; ottoq_events' sequence default becomes a plain bigserial here, and its signature columns keep their types).
CREATE TYPE public.ocpp_session_status AS ENUM ('active', 'completed', 'faulted', 'cancelled');
CREATE TABLE public.ocpp_sessions (id uuid NOT NULL DEFAULT gen_random_uuid(), depot_id uuid NOT NULL, stall_id uuid NOT NULL, vehicle_id uuid, schedule_task_id uuid, charge_point_id text NOT NULL, transaction_id text NOT NULL, evse_id integer NOT NULL, connector_id integer NOT NULL, status ocpp_session_status NOT NULL DEFAULT 'active'::ocpp_session_status, started_at timestamp with time zone NOT NULL, ended_at timestamp with time zone, soc_start integer, soc_end integer, energy_delivered_kwh numeric(10,3) NOT NULL DEFAULT 0, peak_power_kw numeric(8,2) NOT NULL DEFAULT 0, avg_power_kw numeric(8,2) NOT NULL DEFAULT 0, connector_temp_c_max numeric(5,1), connector_temp_c_final numeric(5,1), ambient_temp_c numeric(5,1), stopped_reason text, id_token text, meter_values_count integer NOT NULL DEFAULT 0, last_meter_value jsonb, charging_profile_applied boolean DEFAULT false, max_rate_limit_kw numeric(8,2), fault_count integer DEFAULT 0, last_fault_message text, created_at timestamp with time zone NOT NULL DEFAULT now(), updated_at timestamp with time zone NOT NULL DEFAULT now(), sim_run_id uuid);
CREATE TABLE public.ottoq_events (event_id uuid NOT NULL DEFAULT gen_random_uuid(), event_seq bigserial NOT NULL, occurred_at timestamp with time zone NOT NULL DEFAULT now(), recorded_at timestamp with time zone NOT NULL DEFAULT now(), actor_type text NOT NULL, actor_id text, actor_metadata jsonb NOT NULL DEFAULT '{}'::jsonb, event_type text NOT NULL, event_category text NOT NULL, severity text NOT NULL DEFAULT 'info'::text, entity_type text NOT NULL, entity_id uuid, fleet_operator_id uuid, depot_id uuid, payload jsonb NOT NULL DEFAULT '{}'::jsonb, previous_state jsonb, new_state jsonb, correlation_id uuid NOT NULL DEFAULT gen_random_uuid(), parent_event_id uuid, causation_chain uuid[] NOT NULL DEFAULT '{}'::uuid[], related_task_id uuid, related_schedule_id uuid, related_decision_id uuid, payload_hash text NOT NULL, signature text, signature_key_id text, signature_algorithm text NOT NULL DEFAULT 'HMAC-SHA-256'::text, outcome text, outcome_recorded_at timestamp with time zone, latency_ms integer, ingest_source text DEFAULT 'app'::text, schema_version text NOT NULL DEFAULT '1.0.0'::text, data_source text NOT NULL DEFAULT 'production'::text, sim_run_id uuid, sim_clock_at timestamp with time zone);
