-- A STUB EXTENSION for exercising db/migrations/0572 on a throwaway PostgreSQL. NOT the engine. Loaded after
-- tests/fixtures/throughput_sweep_stub.sql, before 0565.
--
-- It gives the stub what 0572's P1 and its apply read on the live database: the twin depot's 116 autonomous cars in the
-- twin's class mix (36 / 46 / 34), the Benchmark depot's 100 (29 / 42 / 29) in the states they are frozen in (two
-- in_service_bay, some on a stall of their own depot, one holding a reservation there), the columns that say a car has
-- live rows, and the three probes 0572 calls. The fleet reset seeds every autonomous car homed at the depot, as the real
-- one does, and the teardown leaves the worst case behind: a borrowed car tethered to one of the twin's fast chargers.

CREATE TYPE public.vehicle_state AS ENUM ('offline', 'deployed', 'en_route_to_depot', 'arrived_at_gate',
  'staged_awaiting_service', 'in_service_bay', 'emergency_staged', 'tow_requested', 'charging_dcfc', 'charging_l2');
CREATE TYPE public.vehicle_category AS ENUM ('autonomous', 'retail', 'delivery_bot', 'humanoid', 'shuttle');

CREATE TABLE public.vehicles (
  id                        uuid PRIMARY KEY,
  vin                       text UNIQUE,
  home_depot_id             uuid NOT NULL,
  current_depot_id          uuid,
  current_stall_id          uuid,
  category                  public.vehicle_category NOT NULL DEFAULT 'autonomous',
  vehicle_class_code        text,
  fleet_operator_id         uuid,
  current_state             public.vehicle_state NOT NULL DEFAULT 'offline',
  current_soc               numeric,
  battery_capacity_kwh      numeric,
  inlet_max_kw              numeric,
  target_soc                numeric,
  config                    jsonb,
  last_state_change         timestamptz,
  robotic_tether_phase      text,
  robotic_tether_until      timestamptz,
  robotic_tether_stall_id   uuid,
  robotic_tether_direction  text,
  updated_at                timestamptz DEFAULT now()
);
-- as the live trg_vehicles_updated stamps it, so a restore can never set it back
CREATE FUNCTION public.stub_touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := clock_timestamp(); RETURN NEW; END $$;
CREATE TRIGGER trg_vehicles_updated BEFORE UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.stub_touch_updated_at();

-- the twin's 116, then the Benchmark depot's 100, each class numbered so ids are stable and ordered
INSERT INTO public.vehicles (id, vin, home_depot_id, current_depot_id, vehicle_class_code, fleet_operator_id, current_state,
                             current_soc, battery_capacity_kwh, inlet_max_kw, target_soc, config, last_state_change, updated_at)
SELECT md5('twin|' || c.cls || '|' || g)::uuid, 'TWIN-' || c.k || '-' || g, '11111111-1111-1111-1111-111111111111',
       '11111111-1111-1111-1111-111111111111', c.cls, c.op, 'offline', 90, c.batt, c.inlet, 100,
       jsonb_build_object('oem', c.k), '2026-09-01 11:00:00+00', '2026-09-19 17:09:00+00'
  FROM (VALUES ('tesla_model_y_robotaxi_2024', 'T', 36, 'a0000000-0000-0000-0000-00000000000a'::uuid, 76, 250),
               ('waymo_jaguar_ipace_2024', 'W', 46, 'a0000000-0000-0000-0000-00000000000b'::uuid, 90, 100),
               ('zoox_robotaxi_2024', 'Z', 34, 'a0000000-0000-0000-0000-00000000000c'::uuid, 135, 200)) AS c(cls, k, n, op, batt, inlet),
       generate_series(1, c.n) g;
INSERT INTO public.vehicles (id, vin, home_depot_id, current_depot_id, vehicle_class_code, fleet_operator_id, current_state,
                             current_soc, battery_capacity_kwh, inlet_max_kw, target_soc, config, last_state_change, updated_at)
SELECT md5('lender|' || c.cls || '|' || g)::uuid, 'LENDER-' || c.k || '-' || g, '22222222-2222-2222-2222-222222222222',
       '22222222-2222-2222-2222-222222222222', c.cls, c.op,
       (ARRAY['deployed', 'en_route_to_depot', 'staged_awaiting_service', 'emergency_staged', 'tow_requested']::public.vehicle_state[])[1 + g % 5],
       40 + g % 50, c.batt, c.inlet, 90, jsonb_build_object('oem', c.k, 'bench_note', 'frozen'),
       '2026-09-19 17:09:00+00', '2026-09-19 17:09:00+00'
  FROM (VALUES ('tesla_model_y_robotaxi_2024', 'T', 29, 'a0000000-0000-0000-0000-00000000000a'::uuid, 75, 250),
               ('waymo_jaguar_ipace_2024', 'W', 42, 'a0000000-0000-0000-0000-00000000000b'::uuid, 90, 100),
               ('zoox_robotaxi_2024', 'Z', 29, 'a0000000-0000-0000-0000-00000000000c'::uuid, 135, 200)) AS c(cls, k, n, op, batt, inlet),
       generate_series(1, c.n) g;
-- the four retail cars at the twin, which the engine never counts
INSERT INTO public.vehicles (id, vin, home_depot_id, current_depot_id, category, current_state, current_soc, config)
SELECT md5('retail|' || g)::uuid, 'RETAIL-' || g, '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111',
       'retail', 'offline', 92, '{}'::jsonb FROM generate_series(1, 4) g;

-- the stall pointers a lender car can hold, and the columns that say a car has live rows
ALTER TABLE public.stalls
  ADD COLUMN current_vehicle_id uuid, ADD COLUMN reserved_by uuid, ADD COLUMN reserved_at timestamptz,
  ADD COLUMN reservation_expires_at timestamptz, ADD COLUMN status text DEFAULT 'available';
ALTER TABLE public.ottoq_visit_needs ADD COLUMN status text;
ALTER TABLE public.ottoq_vehicle_dispatches ADD COLUMN status text;
ALTER TABLE public.ocpp_sessions ADD COLUMN vehicle_id uuid;
CREATE TABLE public.ottoq_stall_bookings (booking_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, vehicle_id uuid,
                                          stall_id uuid, state text);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, label text,
  object_kind text, schema_name text, object_name text, definition text, def_md5 text);

-- the first Waymo and the first Tesla at the lender (in id order, so both are borrowed) are frozen mid-work in a bay of
-- their own depot; a third lender car holds a reservation there
UPDATE public.vehicles SET current_state = 'in_service_bay'
 WHERE id IN (SELECT DISTINCT ON (vehicle_class_code) id FROM public.vehicles
               WHERE home_depot_id = '22222222-2222-2222-2222-222222222222'
                 AND vehicle_class_code IN ('tesla_model_y_robotaxi_2024', 'waymo_jaguar_ipace_2024')
               ORDER BY vehicle_class_code, id);
INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, status, current_vehicle_id, reserved_by, reserved_at)
SELECT md5('bench-bay|' || v.id)::uuid, '22222222-2222-2222-2222-222222222222', 'service_bay', 'BENCH-BAY-' || left(v.id::text, 4),
       'occupied', v.id, NULL, NULL
  FROM public.vehicles v WHERE v.current_state = 'in_service_bay';
UPDATE public.vehicles v SET current_stall_id = s.id FROM public.stalls s WHERE s.current_vehicle_id = v.id;
INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, status, reserved_by, reserved_at, reservation_expires_at)
SELECT 'e0000000-0000-0000-0000-0000000000b1', '22222222-2222-2222-2222-222222222222', 'staging', 'BENCH-STAGE-1', 'reserved',
       (SELECT id FROM public.vehicles WHERE home_depot_id = '22222222-2222-2222-2222-222222222222'
          AND vehicle_class_code = 'zoox_robotaxi_2024' ORDER BY id LIMIT 1),
       '2026-09-19 17:00:00+00', '2026-09-19 18:00:00+00';

-- as the live sync_stall_occupancy (vehicles, after update): a car's stall pointer moves the stall's
CREATE FUNCTION public.stub_sync_stall_occupancy() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.current_stall_id IS NOT NULL AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id THEN
    UPDATE public.stalls SET status = 'available', current_vehicle_id = NULL WHERE id = OLD.current_stall_id;
  END IF;
  IF NEW.current_stall_id IS NOT NULL AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id THEN
    UPDATE public.stalls SET status = 'occupied', current_vehicle_id = NEW.id WHERE id = NEW.current_stall_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_sync_stall_occupancy AFTER UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.stub_sync_stall_occupancy();
-- as the live ottoq_trg_reassignment_guard (stalls, before update): a stall let go by a car at work is refused. This is
-- what makes 0572 park a car (offline, no stall) in the same statement that moves it.
CREATE FUNCTION public.stub_reassignment_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
  IF NEW.current_vehicle_id IS NULL AND OLD.current_vehicle_id IS NOT NULL THEN
    SELECT current_state::text INTO v_state FROM public.vehicles WHERE id = OLD.current_vehicle_id;
    IF v_state IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay', 'charging_dcfc', 'charging_l2') THEN
      RAISE EXCEPTION 'stub reassignment guard: stall % let go by car % at work (%)', NEW.id, OLD.current_vehicle_id, v_state;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_reassignment_guard BEFORE UPDATE ON public.stalls FOR EACH ROW EXECUTE FUNCTION public.stub_reassignment_guard();

-- the in-flight probe (0513), driven by a table
CREATE TABLE public.stub_in_flight (n int NOT NULL);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean) RETURNS integer LANGUAGE sql STABLE AS
  $$ SELECT n FROM public.stub_in_flight $$;

-- the fleet reset now seeds every autonomous car homed at the depot, as the real one does, and says how many it saw
CREATE OR REPLACE FUNCTION public.ottoq_tick_invariance_reset_fleet(p_depot uuid, p_seed bigint, p_as_of timestamptz) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE v_n int;
BEGIN
  UPDATE public.vehicles v
     SET current_soc = 85 + (abs(hashtext(p_seed::text || v.id::text)) % 14), current_state = 'offline',
         current_stall_id = NULL, current_depot_id = p_depot, last_state_change = p_as_of, target_soc = 100,
         config = COALESCE((SELECT jsonb_object_agg(e.key, e.value) FROM jsonb_each(COALESCE(v.config, '{}'::jsonb)) e
                             WHERE e.key IN ('oem')), '{}'::jsonb),
         robotic_tether_phase = NULL, robotic_tether_until = NULL, robotic_tether_stall_id = NULL, robotic_tether_direction = NULL
   WHERE v.home_depot_id = p_depot AND v.category = 'autonomous';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO public.stub_calls (fn, args) VALUES ('reset', jsonb_build_object(
    'seed', p_seed, 'guc', current_setting('ottoq.sim_run_id', true), 'census', public.stub_census(p_depot), 'fleet', v_n));
  RETURN v_n;
END $$;

-- the teardown now leaves what a day can leave: every car at the depot written to, and one lent car tethered to a fast
-- charger of the twin: the Tesla that is frozen in_service_bay at its own depot, so its restore moves it off a twin
-- charger and back into a bay
CREATE OR REPLACE FUNCTION public.ottoq_sim_stop_and_reset(p_run uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.ottoq_sim_runs SET status = 'stopped' WHERE sim_run_id = p_run;
  PERFORM set_config('ottoq.sim_run_id', p_run::text, true);   -- as the real one pins the run it tore down
  UPDATE public.vehicles SET current_soc = current_soc - 7, config = COALESCE(config, '{}'::jsonb) || '{"run_key": 1}'
   WHERE home_depot_id = '11111111-1111-1111-1111-111111111111' AND category = 'autonomous';
  UPDATE public.vehicles
     SET current_state = 'charging_dcfc', current_stall_id = 'd0000000-0000-0000-0000-00000000dc01',
         robotic_tether_phase = 'mated', robotic_tether_until = now() + interval '1 hour',
         robotic_tether_stall_id = 'd0000000-0000-0000-0000-00000000dc01', robotic_tether_direction = 'mate'
   WHERE id = (SELECT id FROM public.vehicles WHERE home_depot_id = '11111111-1111-1111-1111-111111111111'
                 AND vin LIKE 'LENDER-T-%' ORDER BY id LIMIT 1);   -- the lent Tesla frozen in_service_bay at home
  INSERT INTO public.stub_calls (fn, args) VALUES ('stop', jsonb_build_object('reason', p_reason,
    'census', public.stub_census('11111111-1111-1111-1111-111111111111')));
  RETURN jsonb_build_object('ok', true);
END $$;
