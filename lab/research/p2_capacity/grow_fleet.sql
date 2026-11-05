-- lab/research/p2_capacity/grow_fleet.sql -- LAB ONLY. A larger fleet at the twin depot for one lab day.
--
-- The engine reads a depot's fleet as the autonomous cars homed there (0572 §0), so a larger fleet is only a question of
-- which cars are homed at the depot. 0572's build-out borrows the Benchmark depot's 100 cars; the lab holds the twin's
-- cars only (rule 8's export), and a capacity curve needs more than 216 anyway. So the lab CLONES the twin's own cars:
-- each new car is a copy of one of the twin's autonomous cars, taken round-robin in (class, id) order so the class and
-- owner mix stays the twin's own (Waymo 46, Tesla 36, Zoox 34 of 116), with
--   - an id that is a pure function of the source car and the copy's number, so every arm at the same fleet size draws
--     the same world (the twin's RNG keys on the car's id, 0052);
--   - a VIN and display name derived the same way (the VIN is unique);
--   - no stall, no tether, no run (the fleet reset seeds its state, SoC and config exactly as it seeds the depot's own);
--   - a copy of its source's vehicle_need_profile row (ottoq_run_boot_draw redraws it at the run's start).
-- The only other per-vehicle reference rows the lab holds are schedule_tasks and vehicle_schedules, the legacy calendar
-- the twin's engine does not read; they are not copied.
-- Never run against production. It refuses unless the database's name starts with 'ottoq_cap_' or 'ottoq_lab_'.
CREATE SCHEMA IF NOT EXISTS lab;

CREATE OR REPLACE FUNCTION lab.grow_fleet(p_depot uuid, p_total int)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  v_have int; v_src uuid[]; v_n int; k int; s record; v_id uuid; v_added int := 0;
BEGIN
  IF current_database() !~ '^ottoq_(cap|lab)_' THEN
    RAISE EXCEPTION 'lab.grow_fleet runs only in a lab replica (ottoq_cap_* or ottoq_lab_*), not in %', current_database();
  END IF;
  SELECT count(*) INTO v_have FROM vehicles WHERE home_depot_id = p_depot AND category = 'autonomous';
  IF p_total <= v_have THEN
    RETURN jsonb_build_object('had', v_have, 'added', 0, 'total', v_have);
  END IF;
  SELECT array_agg(id ORDER BY vehicle_class_code, id) INTO v_src
    FROM vehicles WHERE home_depot_id = p_depot AND category = 'autonomous' AND id::text !~ '^1abf';
  v_n := cardinality(v_src);
  FOR k IN 0 .. (p_total - v_have - 1) LOOP
    SELECT * INTO s FROM vehicles WHERE id = v_src[(k % v_n) + 1];
    -- '1abf' marks a lab copy in the id's first four hex digits, so a copy is never itself a source
    v_id := ('1abf' || substr(md5('lab-fleet:' || s.id::text || ':' || k), 5, 28))::uuid;
    INSERT INTO vehicles (id, fleet_operator_id, retail_member_id, home_depot_id, category, vin, make, model, year,
                          license_plate, color, display_name, battery_capacity_kwh, max_charge_rate_kw, connector_type,
                          target_soc, current_soc, min_soc_threshold, platform, av_api_vehicle_id, av_dispatch_capable,
                          current_state, current_stall_id, current_depot_id, last_state_change, default_service_sequence,
                          config, is_active, inlet_type, inlet_max_kw, current_soc_updated_at, current_soc_source,
                          owning_sim_run_id, robotic_tether_until, robotic_tether_stall_id, robotic_tether_direction,
                          robotic_tether_phase, vehicle_class_code)
    VALUES (v_id, s.fleet_operator_id, s.retail_member_id, s.home_depot_id, s.category,
            'LAB' || upper(substr(md5('lab-vin:' || v_id::text), 1, 14)), s.make, s.model, s.year,
            NULL, s.color, COALESCE(s.display_name, 'car') || ' L' || (k + 1), s.battery_capacity_kwh,
            s.max_charge_rate_kw, s.connector_type, s.target_soc, s.current_soc, s.min_soc_threshold, s.platform, NULL,
            s.av_dispatch_capable, s.current_state, NULL, s.current_depot_id, s.last_state_change,
            s.default_service_sequence, s.config, s.is_active, s.inlet_type, s.inlet_max_kw, s.current_soc_updated_at,
            s.current_soc_source, NULL, NULL, NULL, NULL, NULL, s.vehicle_class_code);
    INSERT INTO vehicle_need_profile
    SELECT (jsonb_populate_record(NULL::vehicle_need_profile,
                                  to_jsonb(p) || jsonb_build_object('vehicle_id', v_id))).*
      FROM vehicle_need_profile p WHERE p.vehicle_id = s.id;
    v_added := v_added + 1;
  END LOOP;
  RETURN jsonb_build_object('had', v_have, 'added', v_added,
                            'total', (SELECT count(*) FROM vehicles WHERE home_depot_id = p_depot AND category = 'autonomous'),
                            'by_owner', (SELECT jsonb_object_agg(fo.name, x.n) FROM (
                                           SELECT fleet_operator_id, count(*) AS n FROM vehicles
                                            WHERE home_depot_id = p_depot AND category = 'autonomous' GROUP BY 1) x
                                           JOIN fleet_operators fo ON fo.id = x.fleet_operator_id));
END $f$;
