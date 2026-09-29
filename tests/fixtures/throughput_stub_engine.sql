-- A STUB ENGINE for exercising db/migrations/0565 on a throwaway PostgreSQL. NOT the engine.
--
-- It carries the columns 0565's P1 reads, the triage writer's two markers, stub KPI functions, and one finished run on
-- the twin depot whose seven visits each exercise one definition in 0565 section 3. tests/test_throughput_scorecard_sql.py
-- states what each visit must score. Times are UTC; the run's step is 30 minutes (30 s x time_scale 60).

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')          THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role')  THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;

CREATE SCHEMA twin;
CREATE SCHEMA ottoq;
CREATE SCHEMA extensions;
GRANT USAGE ON SCHEMA public, twin, ottoq TO anon, authenticated, service_role;

CREATE TABLE public.ottoq_sim_runs (
  sim_run_id            uuid PRIMARY KEY,
  depot_id              uuid NOT NULL,
  status                text NOT NULL,
  scenario_code         text,
  random_seed           bigint,
  tick_count            integer,
  policy                text,
  tick_interval_seconds integer,
  time_scale            numeric,
  sim_clock_start       timestamptz,
  sim_clock_current     timestamptz,
  started_at            timestamptz,
  run_by                text,
  validation_status     text
);

CREATE TABLE public.ottoq_visit_needs (
  visit_id        uuid PRIMARY KEY,
  vehicle_id      uuid NOT NULL,
  sim_run_id      uuid,
  depot_id        uuid,
  archetype       text,
  arrived_at      timestamptz,
  dispatch_due_at timestamptz,
  target_soc      numeric,
  atoms           jsonb
);

CREATE TABLE public.ottoq_vehicle_dispatches (
  dispatch_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id          uuid NOT NULL,
  sim_run_id          uuid,
  dispatched_at       timestamptz,
  soc_at_dispatch_pct numeric
);

CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid, stall_type text);

CREATE TABLE public.ocpp_sessions (
  sim_run_id           uuid,
  stall_id             uuid,
  started_at           timestamptz,
  ended_at             timestamptz,
  energy_delivered_kwh numeric,
  avg_power_kw         numeric
);

CREATE TABLE public.ottoq_run_archives (sim_run_id uuid PRIMARY KEY, engine_hash text, config_hash text);

CREATE TABLE public.ottoq_run_scope_registry (
  table_schema  text,
  table_name    text,
  column_name   text,
  class         text,
  note          text,
  registered_at timestamptz DEFAULT now()
);

CREATE TABLE public.ottoq_cert_lineage (
  name                text PRIMARY KEY,
  forces_recert       boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false,
  note                text,
  classified_at       timestamptz NOT NULL DEFAULT now()
);

-- The run-scope check 0565's V1 consults. The stub blocks nothing, so V1 exercises only its own registry row.
CREATE FUNCTION public.ottoq_check_run_scope_registry()
RETURNS TABLE (table_schema text, table_name text, column_name text, problem text, severity text)
LANGUAGE sql AS $$ SELECT NULL::text, NULL::text, NULL::text, NULL::text, NULL::text WHERE false $$;

-- Stub KPIs: deterministic, and each names its run as the live ones do.
CREATE FUNCTION public.ottoq_kpi_charge_wait(p_run uuid) RETURNS jsonb LANGUAGE sql STABLE
AS $$ SELECT jsonb_build_object('sim_run_id', p_run, 'p50_wait_min', 30.0, 'p95_wait_min', 60.0) $$;
-- The live ottoq_kpi_five raises on one old run (e8a0ba01); the stub raises on run ...03 the same way.
CREATE FUNCTION public.ottoq_kpi_five(p_run uuid) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF p_run = 'a0000000-0000-0000-0000-000000000003' THEN
    RAISE EXCEPTION 'field name must not be null';
  END IF;
  RETURN jsonb_build_object('sim_run_id', p_run, 'peak_site_kw', 400.0, 'peak_site_kw_demand', 380.0,
                            'touch_events_per_turn', 1.0, 'p95_time_to_service_min', 90.0);
END $$;
CREATE FUNCTION public.ottoq_kpi_service_completion(p_run uuid) RETURNS jsonb LANGUAGE sql STABLE
AS $$ SELECT jsonb_build_object('sim_run_id', p_run, 'must_do', 9, 'must_do_done', 7, 'service_completion_pct', 77.8) $$;

-- The triage writer, reduced to the two markers 0565's P1 reads.
CREATE FUNCTION twin.ottoq_sim_advance_visit_atoms() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM jsonb_build_object('status','cancelled','confirm_required',false,'triage_verdict','clear','cleared_by_triage',true);
END $$;

-- ── the depot: two fast chargers, one L2 ──
INSERT INTO public.stalls VALUES
  ('d0000000-0000-0000-0000-00000000dc01', '11111111-1111-1111-1111-111111111111', 'dcfc'),
  ('d0000000-0000-0000-0000-00000000dc02', '11111111-1111-1111-1111-111111111111', 'dcfc'),
  ('d0000000-0000-0000-0000-00000000c0c2', '11111111-1111-1111-1111-111111111111', 'l2');

-- ── one finished run, 24 hours, 30-minute step ──
INSERT INTO public.ottoq_sim_runs VALUES
  ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'completed', 'busy_day', 7, 48,
   'otto_q', 30, 60, '2026-09-01 08:00+00', '2026-09-02 08:00+00', '2026-09-29 10:00+00', 'operator_demo', NULL);
INSERT INTO public.ottoq_run_archives VALUES ('a0000000-0000-0000-0000-000000000001', 'engine-e1', 'config-c1');

-- A  pass-through, due 10:45, left 10:30 at 100%, its charge closed at 10:30         -> on time, nothing open
-- B  full service, no due time, left 12:00, tidy cleared by triage                   -> triage 1, nothing open
-- C  pass-through, due 11:30, left 12:30 (60 late), wash ends 13:00 after it left     -> needed work open
-- D  full service, arrived 20:00, never left                                          -> in the depot at the horizon
-- E  fault, left 15:00 at 90% of a 100% target, repair cancelled WITHOUT triage       -> below target and work open
-- F1 full service (vehicle F), 08:00 -> 09:00
-- F2 full service (vehicle F), 13:00 -> 14:00: its departure must not be credited to F1
INSERT INTO public.ottoq_visit_needs VALUES
  ('b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'D_charge_and_go', '2026-09-01 10:00+00', '2026-09-01 10:45+00', 100,
   '[{"svc":"charge","status":"done","must_do":true,"closed_at":"2026-09-01T10:30:00+00:00"}]'),
  ('b0000000-0000-0000-0000-00000000000b', 'c0000000-0000-0000-0000-00000000000b', 'a0000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'std_mixed', '2026-09-01 10:00+00', NULL, 100,
   '[{"svc":"charge","status":"done","must_do":true,"closed_at":"2026-09-01T11:30:00+00:00"},
     {"svc":"interior_tidy","status":"cancelled","must_do":true,"triage_verdict":"clear","cleared_by_triage":true}]'),
  ('b0000000-0000-0000-0000-00000000000c', 'c0000000-0000-0000-0000-00000000000c', 'a0000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'A_charge_clean_go', '2026-09-01 11:00+00', '2026-09-01 11:30+00', 100,
   '[{"svc":"charge","status":"done","must_do":true,"closed_at":"2026-09-01T12:30:00+00:00"},
     {"svc":"exterior_wash","status":"done","must_do":true,"started_at":"2026-09-01T12:40:00+00:00","ends_at":"2026-09-01T13:00:00+00:00"}]'),
  ('b0000000-0000-0000-0000-00000000000d', 'c0000000-0000-0000-0000-00000000000d', 'a0000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'C_overnight', '2026-09-01 20:00+00', NULL, 100,
   '[{"svc":"charge","status":"pending","must_do":true}]'),
  ('b0000000-0000-0000-0000-00000000000e', 'c0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'E_tech_hold_fault', '2026-09-01 09:00+00', NULL, 100,
   '[{"svc":"fault_repair","status":"cancelled","must_do":true},
     {"svc":"readiness_check","status":"done","must_do":true,"done_at":"2026-09-01T14:30:00+00:00"}]'),
  ('b0000000-0000-0000-0000-0000000000f1', 'c0000000-0000-0000-0000-00000000000f', 'a0000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'std_mixed', '2026-09-01 08:00+00', NULL, 100,
   '[{"svc":"charge","status":"done","must_do":true,"closed_at":"2026-09-01T08:30:00+00:00"}]'),
  ('b0000000-0000-0000-0000-0000000000f2', 'c0000000-0000-0000-0000-00000000000f', 'a0000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'std_mixed', '2026-09-01 13:00+00', NULL, 100,
   '[{"svc":"charge","status":"done","must_do":true,"closed_at":"2026-09-01T13:30:00+00:00"}]');

INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, soc_at_dispatch_pct) VALUES
  ('c0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-000000000001', '2026-09-01 10:30+00', 100),
  ('c0000000-0000-0000-0000-00000000000b', 'a0000000-0000-0000-0000-000000000001', '2026-09-01 12:00+00', 100),
  ('c0000000-0000-0000-0000-00000000000c', 'a0000000-0000-0000-0000-000000000001', '2026-09-01 12:30+00', 100),
  ('c0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-000000000001', '2026-09-01 15:00+00', 90),
  ('c0000000-0000-0000-0000-00000000000f', 'a0000000-0000-0000-0000-000000000001', '2026-09-01 09:00+00', 100),
  ('c0000000-0000-0000-0000-00000000000f', 'a0000000-0000-0000-0000-000000000001', '2026-09-01 14:00+00', 100);

-- Fast chargers: two one-hour sessions (40 kWh each); L2: one.
INSERT INTO public.ocpp_sessions VALUES
  ('a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-00000000dc01', '2026-09-01 10:00+00', '2026-09-01 11:00+00', 40, 40),
  ('a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-00000000dc02', '2026-09-01 11:30+00', '2026-09-01 12:30+00', 40, 40),
  ('a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-00000000c0c2', '2026-09-01 10:00+00', '2026-09-01 12:00+00', 30, 15);

-- A finished run on which ottoq_kpi_five fails: the scorecard must still be written, with the failure under kpi_errors.
INSERT INTO public.ottoq_sim_runs VALUES
  ('a0000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'completed', 'production', 9, 7,
   'otto_q', 120, 1, '2026-09-01 08:00+00', '2026-09-01 08:14+00', '2026-09-29 08:00+00', 'production_live', NULL);
INSERT INTO public.ottoq_visit_needs VALUES
  ('b0000000-0000-0000-0000-0000000000b3', 'c0000000-0000-0000-0000-0000000000b3', 'a0000000-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111', 'D_charge_and_go', '2026-09-01 08:00+00', NULL, 100,
   '[{"svc":"charge","status":"done","must_do":true,"closed_at":"2026-09-01T08:10:00+00:00"}]');
INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, soc_at_dispatch_pct) VALUES
  ('c0000000-0000-0000-0000-0000000000b3', 'a0000000-0000-0000-0000-000000000003', '2026-09-01 08:12+00', 100);

-- A live run: the backfill must skip it.
INSERT INTO public.ottoq_sim_runs VALUES
  ('a0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'running', 'busy_day', 8, 10,
   'otto_q', 30, 60, '2026-09-01 08:00+00', '2026-09-01 10:00+00', '2026-09-29 11:00+00', 'operator_demo', NULL);
INSERT INTO public.ottoq_visit_needs VALUES
  ('b0000000-0000-0000-0000-0000000000aa', 'c0000000-0000-0000-0000-0000000000aa', 'a0000000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111', 'D_charge_and_go', '2026-09-01 09:00+00', NULL, 100, '[]');

-- A passed determinism pair: two arms, one start instant, identical rows. V2 must find them and score them identically.
INSERT INTO public.ottoq_sim_runs VALUES
  ('e0000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'completed', 'busy_day', 171717, 48,
   'otto_q', 30, 60, '2026-09-01 08:00+00', '2026-09-02 08:00+00', '2026-09-29 09:00+00', 'cert_harness', 'passed'),
  ('e0000000-0000-0000-0000-00000000000b', '11111111-1111-1111-1111-111111111111', 'completed', 'busy_day', 171717, 48,
   'otto_q', 30, 60, '2026-09-01 08:00+00', '2026-09-02 08:00+00', '2026-09-29 09:00+00', 'cert_harness', 'passed');
INSERT INTO public.ottoq_visit_needs
SELECT ('b1' || substr(v.visit_id::text, 3))::uuid, v.vehicle_id, arm.id, v.depot_id, v.archetype, v.arrived_at,
       v.dispatch_due_at, v.target_soc, v.atoms
  FROM public.ottoq_visit_needs v
  CROSS JOIN (VALUES ('e0000000-0000-0000-0000-00000000000a'::uuid), ('e0000000-0000-0000-0000-00000000000b'::uuid)) arm(id)
 WHERE v.sim_run_id = 'a0000000-0000-0000-0000-000000000001' AND arm.id = 'e0000000-0000-0000-0000-00000000000a'
UNION ALL
SELECT ('b2' || substr(v.visit_id::text, 3))::uuid, v.vehicle_id, 'e0000000-0000-0000-0000-00000000000b', v.depot_id,
       v.archetype, v.arrived_at, v.dispatch_due_at, v.target_soc, v.atoms
  FROM public.ottoq_visit_needs v
 WHERE v.sim_run_id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, soc_at_dispatch_pct)
SELECT d.vehicle_id, arm.id, d.dispatched_at, d.soc_at_dispatch_pct
  FROM public.ottoq_vehicle_dispatches d
  CROSS JOIN (VALUES ('e0000000-0000-0000-0000-00000000000a'::uuid), ('e0000000-0000-0000-0000-00000000000b'::uuid)) arm(id)
 WHERE d.sim_run_id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.ocpp_sessions
SELECT arm.id, s.stall_id, s.started_at, s.ended_at, s.energy_delivered_kwh, s.avg_power_kw
  FROM public.ocpp_sessions s
  CROSS JOIN (VALUES ('e0000000-0000-0000-0000-00000000000a'::uuid), ('e0000000-0000-0000-0000-00000000000b'::uuid)) arm(id)
 WHERE s.sim_run_id = 'a0000000-0000-0000-0000-000000000001';
