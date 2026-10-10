-- tests/fixtures/v2_door_seed.sql: the twin depot, three fleets, 158 stalls with positions, five cars at the twin depot
-- and one elsewhere. Loaded by tests/test_v2_door_sql.py after the stub engine and before 0649.
INSERT INTO public.depots (id, name) VALUES
  ('11111111-1111-1111-1111-111111111111', 'OTTOYARD Nashville Flagship'),
  ('22222222-2222-2222-2222-222222222222', 'OTTOYARD Benchmark (CRN A/B)');
INSERT INTO public.fleet_operators (id, name) VALUES
  ('22222222-2222-2222-2222-222222222222', 'Waymo Nashville'),
  ('33333333-3333-3333-3333-333333333333', 'Tesla Robotaxi TN'),
  ('44444444-4444-4444-4444-444444444444', 'Zoox Southeast');
INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, absolute_point)
SELECT md5('stall' || g)::uuid, '11111111-1111-1111-1111-111111111111', format('NASH-STALL-%s', lpad(g::text, 3, '0')),
       (CASE WHEN g <= 10 THEN 'dcfc' WHEN g <= 40 THEN 'l2' ELSE 'staging' END)::public.stall_type,
       public.ST_SetSRID(public.ST_MakePoint(-86.7735 + (g % 15) * 0.0001, 36.1390 + (g / 15) * 0.0001), 4326)::public.geography
  FROM generate_series(1, 158) g;
INSERT INTO public.vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, display_name, current_state, current_soc)
SELECT md5('veh' || n)::uuid, f, '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', name, 'deployed', 50
  FROM (VALUES (1, '22222222-2222-2222-2222-222222222222'::uuid, 'Waymo-001'), (2, '22222222-2222-2222-2222-222222222222'::uuid, 'Waymo-002'),
               (3, '33333333-3333-3333-3333-333333333333'::uuid, 'Tesla-AV-041'), (4, '44444444-4444-4444-4444-444444444444'::uuid, 'Zoox-001'),
               (5, '22222222-2222-2222-2222-222222222222'::uuid, 'Waymo-003')) v(n, f, name);
-- a car at the other depot with a twin-depot car's name, to prove resolution never leaves the key's depot
INSERT INTO public.vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, display_name, current_state, current_soc)
VALUES (md5('veh-elsewhere')::uuid, '22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222',
        '22222222-2222-2222-2222-222222222222', 'Waymo-900', 'deployed', 50);
