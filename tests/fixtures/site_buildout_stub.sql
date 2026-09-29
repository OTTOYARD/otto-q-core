-- A STUB EXTENSION for exercising db/migrations/0567 on a throwaway PostgreSQL. NOT the engine. Loaded AFTER
-- tests/fixtures/throughput_stub_engine.sql and BEFORE 0565, 0566 and 0567.
--
-- It grows the stub's twin depot to what 0567's P1 reads on the live one: 10 fast chargers, the ten CANOPY-02 L2 chargers
-- the build-outs name (each with a charger and capabilities), one more L2 space that stays L2, the depot's power limits
-- 1,800 kW and 2,500 kW, the stall_type enum, and the charge-session start's markers. A second depot exists only to be
-- named wrongly. tests/test_site_buildout_sql.py says what each piece must do.

CREATE TYPE public.stall_type AS ENUM ('dcfc', 'l2', 'wash_bay', 'detail_bay', 'service_bay', 'staging', 'parking', 'safety');
ALTER TABLE public.stalls ALTER COLUMN stall_type TYPE public.stall_type USING stall_type::public.stall_type;
ALTER TABLE public.stalls
  ADD COLUMN stall_code         text,
  ADD COLUMN connector_max_kw   numeric,
  ADD COLUMN fiducial_marker_id text,
  ADD COLUMN uwb_beacon_id      text,
  ADD COLUMN equipment_config   jsonb,
  ADD COLUMN zone               text,
  ADD COLUMN ocpp_charger_id    uuid,
  ADD COLUMN canopy_code        text;
ALTER TABLE public.ottoq_sim_runs ADD COLUMN payload jsonb;

CREATE TABLE public.depots (id uuid PRIMARY KEY, dcfc_max_concurrent_kw numeric, service_max_kw numeric);
INSERT INTO public.depots VALUES ('11111111-1111-1111-1111-111111111111', 1800, 2500),
                                 ('22222222-2222-2222-2222-222222222222', 1800, 2500);

CREATE TABLE public.ottoq_ocpp_chargers (
  charger_id uuid PRIMARY KEY, depot_id uuid, max_kw numeric, vendor text, model text);
CREATE TABLE public.ottoq_operation_catalog (pack_id text, operation_code text, PRIMARY KEY (pack_id, operation_code));
INSERT INTO public.ottoq_operation_catalog VALUES ('robotaxi', 'charge_dcfc'), ('robotaxi', 'charge_l2'), ('robotaxi', 'interior_tidy');
CREATE TABLE public.ottoq_service_point_capabilities (
  stall_id         uuid REFERENCES public.stalls(id),
  asset_class_code text,
  pack_id          text,
  operation_code   text,
  PRIMARY KEY (stall_id, asset_class_code, operation_code),
  FOREIGN KEY (pack_id, operation_code) REFERENCES public.ottoq_operation_catalog(pack_id, operation_code));

-- The charge-session start, reduced to the three things 0567's P1 reads: it starts the arm on a 'dcfc' stall and reads
-- the charge kind off the charger's rating.
CREATE FUNCTION twin.ottoq_sim_start_charge_session(p_stall_type text, p_max_kw numeric) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_kind text;
BEGIN
  v_kind := CASE WHEN p_max_kw > 50 THEN 'dcfc' ELSE 'l2' END;
  IF p_stall_type = 'dcfc' THEN PERFORM 'twin.ottoq_arm_begin_cycle'; END IF;
  RETURN v_kind;
END $$;

-- The three stalls the throughput stub already has get their names and ratings.
UPDATE public.stalls SET stall_code = 'NASH-DCFC-STALL-01', connector_max_kw = 350, fiducial_marker_id = 'FID-D1-01-A',
       uwb_beacon_id = 'UWB-D1-01', zone = 'dcfc_zone', canopy_code = 'CANOPY-01',
       equipment_config = '{"charger_kw":350,"canopy_code":"CANOPY-01","canopy_side":"W"}'
 WHERE id = 'd0000000-0000-0000-0000-00000000dc01';
UPDATE public.stalls SET stall_code = 'NASH-DCFC-STALL-02', connector_max_kw = 350, fiducial_marker_id = 'FID-D1-02-A',
       uwb_beacon_id = 'UWB-D1-02', zone = 'dcfc_zone', canopy_code = 'CANOPY-01',
       equipment_config = '{"charger_kw":350,"canopy_code":"CANOPY-01","canopy_side":"W"}'
 WHERE id = 'd0000000-0000-0000-0000-00000000dc02';
UPDATE public.stalls SET stall_code = 'NASH-L2-STALL-30', connector_max_kw = 19.2, zone = 'l2_zone', canopy_code = 'CANOPY-03',
       equipment_config = '{"charger_kw":19.2,"canopy_code":"CANOPY-03","canopy_side":"E"}'
 WHERE id = 'd0000000-0000-0000-0000-00000000c0c2';

-- Eight more fast chargers: the twin's ten.
INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, connector_max_kw, fiducial_marker_id, uwb_beacon_id,
                           equipment_config, zone, canopy_code)
SELECT ('d0000000-0000-0000-0000-00000000dc' || lpad(i::text, 2, '0'))::uuid, '11111111-1111-1111-1111-111111111111',
       'dcfc', 'NASH-DCFC-STALL-' || lpad(i::text, 2, '0'), 350, 'FID-D1-' || lpad(i::text, 2, '0') || '-A',
       'UWB-D1-' || lpad(i::text, 2, '0'), '{"charger_kw":350,"canopy_code":"CANOPY-01"}', 'dcfc_zone', 'CANOPY-01'
  FROM generate_series(3, 10) AS i;

-- The ten CANOPY-02 L2 chargers the build-outs name, each with a charger and two classes' capabilities.
INSERT INTO public.ottoq_ocpp_chargers
SELECT ('f0000000-0000-0000-0000-0000000002' || lpad(i::text, 2, '0'))::uuid, '11111111-1111-1111-1111-111111111111',
       19.2, 'ChargePoint', 'CT4000 Family'
  FROM generate_series(1, 10) AS i;
INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, connector_max_kw, equipment_config, zone, canopy_code,
                           ocpp_charger_id)
SELECT ('d0000000-0000-0000-0000-0000000002' || lpad(i::text, 2, '0'))::uuid, '11111111-1111-1111-1111-111111111111',
       'l2', 'NASH-L2-STALL-' || lpad(i::text, 2, '0'), 19.2,
       jsonb_build_object('charger_kw', 19.2, 'canopy_code', 'CANOPY-02', 'canopy_side', CASE WHEN i <= 8 THEN 'W' ELSE 'E' END),
       'l2_zone', 'CANOPY-02', ('f0000000-0000-0000-0000-0000000002' || lpad(i::text, 2, '0'))::uuid
  FROM generate_series(1, 10) AS i;
INSERT INTO public.ottoq_service_point_capabilities
SELECT s.id, c.cls, 'robotaxi', 'charge_l2'
  FROM public.stalls s CROSS JOIN (VALUES ('waymo_jaguar_ipace_2024'), ('zoox_robotaxi_2024')) AS c(cls)
 WHERE s.canopy_code = 'CANOPY-02';
INSERT INTO public.ottoq_service_point_capabilities
SELECT s.id, 'waymo_jaguar_ipace_2024', 'robotaxi', 'interior_tidy' FROM public.stalls s WHERE s.canopy_code = 'CANOPY-02';

-- A space at the other depot, for a build-out that names the wrong depot.
INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, connector_max_kw, zone)
VALUES ('d0000000-0000-0000-0000-000000000999', '22222222-2222-2222-2222-222222222222', 'l2', 'BENCH-L2-STALL-01', 19.2, 'l2_zone');

-- ── a finished day that ran on dcfc20, scored after its restore ──
-- Its record names ten converted spaces. One session on a built fast charger, one on converted space L2-STALL-01 (a
-- fast charge that day), one on L2-STALL-30 (L2 that day and today).
INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, scenario_code, random_seed, tick_count, policy,
                                   tick_interval_seconds, time_scale, sim_clock_start, sim_clock_current, started_at,
                                   run_by, validation_status, payload)
VALUES ('a0000000-0000-0000-0000-00000000000b', '11111111-1111-1111-1111-111111111111', 'completed', 'busy_day', 11, 240,
        'otto_q', 30, 12, '2026-09-01 08:00+00', '2026-09-02 08:00+00', '2026-09-29 12:00+00', 'ab_harness', 'passed',
        jsonb_build_object('site_buildout', jsonb_build_object(
          'buildout_code', 'dcfc20', 'dcfc_posts', 20, 'dcfc_max_concurrent_kw', 3600, 'service_max_kw', 4363,
          'converted_stall_ids', (SELECT jsonb_agg(('d0000000-0000-0000-0000-0000000002' || lpad(i::text, 2, '0'))::uuid ORDER BY i)
                                    FROM generate_series(1, 10) AS i))));
INSERT INTO public.ottoq_visit_needs VALUES
  ('b0000000-0000-0000-0000-0000000000bb', 'c0000000-0000-0000-0000-0000000000bb', 'a0000000-0000-0000-0000-00000000000b',
   '11111111-1111-1111-1111-111111111111', 'D_charge_and_go', '2026-09-01 10:00+00', '2026-09-01 11:00+00', 100,
   '[{"svc":"charge","status":"done","must_do":true,"closed_at":"2026-09-01T10:30:00+00:00"}]');
INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, soc_at_dispatch_pct) VALUES
  ('c0000000-0000-0000-0000-0000000000bb', 'a0000000-0000-0000-0000-00000000000b', '2026-09-01 10:35+00', 100);
INSERT INTO public.ocpp_sessions VALUES
  ('a0000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-00000000dc01', '2026-09-01 10:00+00', '2026-09-01 10:30+00', 40, 80),
  ('a0000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-000000000201', '2026-09-01 11:00+00', '2026-09-01 11:30+00', 40, 80),
  ('a0000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-00000000c0c2', '2026-09-01 12:00+00', '2026-09-01 14:00+00', 30, 15);
