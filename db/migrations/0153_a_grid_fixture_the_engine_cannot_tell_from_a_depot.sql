-- =====================================================================
-- 0153  A grid fixture the engine cannot tell from a depot
-- =====================================================================
-- Chase, Sep 2: "Do we need an entire depot? ... It's all just data
-- points and grid points. If we see scenario A go to grid B, which is
-- according to its instructions ... that would be a success."
--
-- The pair harness on the 158-stall / 116-asset flagship costs 7-16 s
-- per tick and 5-13 min per pair (0072 §1); a six-column round is two
-- hours, and every engine fix reruns it. The engine does not need the
-- flagship. Every function on the tick path scopes by the run's depot
-- (verified: prime_deployment, seed_vehicle_need_profiles,
-- world_fingerprint, boot_state_fingerprint, reset_fleet, energy,
-- weather/solar). What it needs is the SHAPE of a depot: one row that
-- groups the points, the points, the assets, an energy plant, and the
-- per-depot configuration the tick path reads. The Benchmark depot
-- failed as a pair target because three of those were missing
-- (scenario bound to the flagship, no canopy rows, no depot-scoped
-- policy params). This fixture supplies all of them, tiny.
--
-- twin.ottoq_grid_fixture_create(slug, n_vehicles, dcfc, l2, wash,
-- service, staging) clones the flagship's shape into a new depot:
--   depot row (incl. geofence/origin), service_definitions,
--   tariff windows, depot tariffs, staffing, engine_config, tariff
--   schedules, action guardrails, waves, site structures, depot-scoped
--   policy params, one BESS (scaled), one canopy (scaled), the first N
--   stalls of each type WITH their geometry and (for chargers) a cloned
--   OCPP charger, the first N autonomous vehicles, and a scenario
--   `grid_smoke` bound to the new depot with the normal_day shape.
-- Every id is md5(slug, kind, ordinal)::uuid, so the fixture is a
-- function of its arguments, not of a random draw: the same call on
-- any database yields the same ids, so seeded draws keyed on ids
-- (reset_fleet's SoC, the bess band) reproduce too.
--
-- Classified forces_recert = FALSE: the flagship's rows are untouched,
-- every tick-path read is depot-scoped, and the matrix is
-- depot-partitioned (0149) so grid pairs form their own canon.
-- Teardown is deliberately not provided yet: the fixture is standing
-- test infrastructure, like the Benchmark depot.
--
-- DRY RUN (7:38 AM CT Sep 2, inside a transaction that was rolled back,
-- so nothing persisted and the concurrent flagship round could not see
-- it): fixture built in 298 ms - 10 points (2 DCFC, 2 L2, 1 wash, 1
-- service, 4 staging), 4 chargers, 4 assets, 9 service definitions, 6
-- tariff windows, 3 depot tariffs, 3 staffing rows, engine_config, 2
-- tariff schedules, 8 guardrails, 3 waves, 28 structures, 18 depot
-- policy params, 1 BESS, 1 canopy, scenario grid_smoke bound. Then a
-- two-arm 3-tick certification pair on it: 5.0 s wall, ticks 0.27 s
-- and 0.36 s apart, verdict passed with h_cmd/h_dec/h_nrg/endst equal,
-- proposer policy_disabled x3 (0152 holds), 1 stall assignment enacted,
-- 6 energy commands, 54 events per arm. Flagship: 7-16 s per tick.
-- =====================================================================

CREATE OR REPLACE FUNCTION twin.ottoq_grid_fixture_create(
  p_slug           text    DEFAULT 'grid-fixture',
  p_n_vehicles     int     DEFAULT 4,
  p_dcfc           int     DEFAULT 2,
  p_l2             int     DEFAULT 2,
  p_wash           int     DEFAULT 1,
  p_service        int     DEFAULT 1,
  p_staging        int     DEFAULT 4,
  p_source_depot   uuid    DEFAULT '11111111-1111-1111-1111-111111111111',
  p_scenario_code  text    DEFAULT 'grid_smoke',
  p_scenario_seed  bigint  DEFAULT 424242
) RETURNS uuid
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_depot      uuid := md5('ottoq_grid_fixture:'||p_slug)::uuid;
  v_src        public.depots%ROWTYPE;
  r            record;
  i            int := 0;
  v_code       text;
  v_stall_id   uuid;
  v_charger_id uuid;
  v_canopy     text := p_slug||'_canopy_1';
  v_n_stalls   int; v_n_veh int; v_n_chg int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.depots WHERE id = v_depot) THEN
    RAISE NOTICE 'grid fixture % already exists as %', p_slug, v_depot;
    RETURN v_depot;
  END IF;
  SELECT * INTO v_src FROM public.depots WHERE id = p_source_depot;
  IF NOT FOUND THEN RAISE EXCEPTION 'grid fixture: source depot % not found', p_source_depot; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_scenarios WHERE scenario_code = p_scenario_code) THEN
    RAISE EXCEPTION 'grid fixture: scenario_code % already exists', p_scenario_code;
  END IF;

  -- 1. The depot row: the source's shape, a new identity. Geometry columns
  --    are carried by UPDATE (jsonb round-trips do not preserve them).
  INSERT INTO public.depots
  SELECT (jsonb_populate_record(NULL::public.depots,
           (to_jsonb(v_src) - 'geofence' - 'origin_point')
           || jsonb_build_object('id', v_depot,
                                 'name', 'OTTOYARD Grid Fixture ('||p_slug||')',
                                 'slug', p_slug,
                                 'address', 'grid fixture - not a place',
                                 'created_at', now(), 'updated_at', now()))).*;
  UPDATE public.depots SET geofence = v_src.geofence, origin_point = v_src.origin_point WHERE id = v_depot;

  -- 2. Per-depot configuration the tick path reads, cloned row for row.
  INSERT INTO public.service_definitions
  SELECT (jsonb_populate_record(NULL::public.service_definitions,
           to_jsonb(s) || jsonb_build_object('id', md5('grid:'||p_slug||':svc:'||s.code)::uuid, 'depot_id', v_depot))).*
    FROM public.service_definitions s WHERE s.depot_id = p_source_depot;

  INSERT INTO public.ottoq_tariff_windows
  SELECT (jsonb_populate_record(NULL::public.ottoq_tariff_windows,
           to_jsonb(t) || jsonb_build_object('tariff_id', md5('grid:'||p_slug||':tw:'||t.tariff_id)::uuid, 'depot_id', v_depot))).*
    FROM public.ottoq_tariff_windows t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.ottoq_depot_tariffs
  SELECT (jsonb_populate_record(NULL::public.ottoq_depot_tariffs,
           to_jsonb(t) || jsonb_build_object('tariff_row_id', md5('grid:'||p_slug||':dt:'||t.tariff_row_id)::uuid, 'depot_id', v_depot))).*
    FROM public.ottoq_depot_tariffs t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.ottoq_depot_staffing
  SELECT (jsonb_populate_record(NULL::public.ottoq_depot_staffing,
           to_jsonb(t) || jsonb_build_object('depot_id', v_depot))).*
    FROM public.ottoq_depot_staffing t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.engine_config
  SELECT (jsonb_populate_record(NULL::public.engine_config,
           to_jsonb(t) || jsonb_build_object('id', md5('grid:'||p_slug||':engine_config')::uuid, 'depot_id', v_depot))).*
    FROM public.engine_config t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.tariff_schedules
  SELECT (jsonb_populate_record(NULL::public.tariff_schedules,
           to_jsonb(t) || jsonb_build_object('id', md5('grid:'||p_slug||':ts:'||t.id)::uuid, 'depot_id', v_depot))).*
    FROM public.tariff_schedules t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.action_guardrails
  SELECT (jsonb_populate_record(NULL::public.action_guardrails,
           to_jsonb(t) || jsonb_build_object('id', md5('grid:'||p_slug||':ag:'||t.id)::uuid, 'depot_id', v_depot))).*
    FROM public.action_guardrails t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.waves
  SELECT (jsonb_populate_record(NULL::public.waves,
           to_jsonb(t) || jsonb_build_object('id', md5('grid:'||p_slug||':wave:'||t.id)::uuid, 'depot_id', v_depot))).*
    FROM public.waves t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.ottoq_site_structures
  SELECT (jsonb_populate_record(NULL::public.ottoq_site_structures,
           to_jsonb(t) || jsonb_build_object('structure_id', md5('grid:'||p_slug||':struct:'||t.structure_code)::uuid, 'depot_id', v_depot))).*
    FROM public.ottoq_site_structures t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
  SELECT 'depot', v_depot, p.param_key, p.param_value, 'grid_fixture:'||p_slug
    FROM public.ottoq_policy_params p WHERE p.scope_type = 'depot' AND p.scope_id = p_source_depot;

  -- 3. Energy plant, scaled to a grid: one battery at a tenth, one canopy.
  INSERT INTO public.ottoq_bess_units
  SELECT (jsonb_populate_record(NULL::public.ottoq_bess_units,
           to_jsonb(b) || jsonb_build_object('bess_id', md5('grid:'||p_slug||':bess:1')::uuid, 'depot_id', v_depot,
             'bess_identifier', upper(p_slug)||'-BESS-01',
             'capacity_kwh', round(b.capacity_kwh/10.0, 0), 'max_charge_kw', round(b.max_charge_kw/10.0, 0),
             'max_discharge_kw', round(b.max_discharge_kw/10.0, 0),
             'current_power_kw', 0, 'current_state', 'idle', 'current_soc_pct', 50,
             'current_soc_kwh', round(b.capacity_kwh/20.0, 3), 'current_cycle_count', 0,
             'lifetime_kwh_charged', 0, 'lifetime_kwh_discharged', 0,
             'last_fault_code', NULL, 'last_fault_at', NULL, 'last_fault_payload', NULL,
             'created_at', now(), 'updated_at', now()))).*
    FROM public.ottoq_bess_units b WHERE b.depot_id = p_source_depot ORDER BY b.bess_identifier LIMIT 1;

  INSERT INTO public.ottoq_canopy_state (canopy_code, depot_id, structure_id, nameplate_dc_kw, nameplate_ac_kw,
                                         tilt_deg, azimuth_deg, current_soiling, last_rain_clean_at, last_updated_at)
  SELECT v_canopy, v_depot, NULL, 36, 30, c.tilt_deg, c.azimuth_deg, 0.85, c.last_rain_clean_at, now()
    FROM public.ottoq_canopy_state c WHERE c.depot_id = p_source_depot ORDER BY c.canopy_code LIMIT 1;

  -- 4. Points: the first N source stalls of each type, geometry kept, a
  --    cloned OCPP charger behind every charging stall.
  FOR r IN
    SELECT s.*, row_number() OVER (PARTITION BY s.stall_type ORDER BY s.stall_code) AS rn
      FROM public.stalls s WHERE s.depot_id = p_source_depot
     ORDER BY s.stall_type, s.stall_code
  LOOP
    IF NOT ((r.stall_type::text = 'dcfc'        AND r.rn <= p_dcfc)
         OR (r.stall_type::text = 'l2'          AND r.rn <= p_l2)
         OR (r.stall_type::text = 'wash_bay'    AND r.rn <= p_wash)
         OR (r.stall_type::text = 'service_bay' AND r.rn <= p_service)
         OR (r.stall_type::text = 'staging'     AND r.rn <= p_staging)) THEN
      CONTINUE;
    END IF;
    v_code := upper(p_slug)||'-'||upper(r.stall_type::text)||'-'||lpad(r.rn::text, 2, '0');
    v_charger_id := NULL;
    IF r.ocpp_charger_id IS NOT NULL THEN
      v_charger_id := md5('grid:'||p_slug||':chg:'||v_code)::uuid;
      INSERT INTO public.ottoq_ocpp_chargers
      SELECT (jsonb_populate_record(NULL::public.ottoq_ocpp_chargers,
               to_jsonb(c) || jsonb_build_object('charger_id', v_charger_id, 'depot_id', v_depot,
                 'ocpp_identifier', v_code, 'serial_number', NULL,
                 'station_state', 'Available', 'station_state_changed_at', 'epoch',
                 'last_heartbeat_at', now(), 'last_fault_code', NULL, 'last_fault_at', NULL, 'last_fault_payload', NULL,
                 'created_at', now(), 'updated_at', now()))).*
        FROM public.ottoq_ocpp_chargers c WHERE c.charger_id = r.ocpp_charger_id;
    END IF;
    v_stall_id := md5('grid:'||p_slug||':stall:'||v_code)::uuid;
    INSERT INTO public.stalls
    SELECT (jsonb_populate_record(NULL::public.stalls,
             (to_jsonb(r) - 'rn' - 'absolute_point')
             || jsonb_build_object('id', v_stall_id, 'depot_id', v_depot, 'stall_code', v_code, 'display_name', v_code,
                  'ocpp_charger_id', v_charger_id, 'current_vehicle_id', NULL,
                  'reserved_by', NULL, 'reserved_at', NULL, 'reservation_expires_at', NULL, 'reserved_for_mission_id', NULL,
                  'status', 'available',
                  'canopy_code', CASE WHEN r.canopy_code IS NULL THEN NULL ELSE v_canopy END,
                  'created_at', now(), 'updated_at', now()))).*;
    UPDATE public.stalls SET absolute_point = r.absolute_point WHERE id = v_stall_id;
  END LOOP;

  -- 5. Assets: the first N autonomous vehicles of the source, new identity,
  --    parked offline; reset_fleet deals their SoC from the seed.
  FOR r IN
    SELECT v.* FROM public.vehicles v
     WHERE v.home_depot_id = p_source_depot AND v.category = 'autonomous'
     ORDER BY v.display_name LIMIT p_n_vehicles
  LOOP
    i := i + 1;
    INSERT INTO public.vehicles
    SELECT (jsonb_populate_record(NULL::public.vehicles,
             to_jsonb(r) || jsonb_build_object(
               'id', md5('grid:'||p_slug||':veh:'||i)::uuid,
               'vin', 'GRID'||upper(left(md5(p_slug),4))||lpad(i::text, 9, '0'),
               'display_name', upper(p_slug)||'-AV-'||lpad(i::text, 2, '0'),
               'license_plate', 'GRID-'||lpad(i::text, 3, '0'),
               'av_api_vehicle_id', 'grid-sim-'||left(md5(p_slug),4)||'-'||lpad(i::text, 2, '0'),
               'home_depot_id', v_depot, 'current_depot_id', v_depot, 'current_stall_id', NULL,
               'current_state', 'offline', 'owning_sim_run_id', NULL, 'retail_member_id', NULL,
               'robotic_tether_until', NULL, 'robotic_tether_stall_id', NULL,
               'robotic_tether_direction', NULL, 'robotic_tether_phase', NULL,
               'last_state_change', now(), 'created_at', now(), 'updated_at', now()))).*;
  END LOOP;

  -- 6. A scenario bound to the grid: the normal_day shape.
  INSERT INTO public.ottoq_scenarios
  SELECT (jsonb_populate_record(NULL::public.ottoq_scenarios,
           to_jsonb(sc) || jsonb_build_object(
             'scenario_id', md5('grid:'||p_slug||':scenario:'||p_scenario_code)::uuid,
             'scenario_code', p_scenario_code, 'category', 'regression',
             'title', 'Grid fixture smoke ('||p_slug||')',
             'description', 'Point-to-point conformance on the '||p_slug||' fixture: the normal_day shape on a tiny grid (0153).',
             'depot_id', v_depot, 'random_seed', p_scenario_seed,
             'introduced_in', '0153', 'created_at', now(), 'updated_at', now()))).*
    FROM public.ottoq_scenarios sc WHERE sc.scenario_code = 'normal_day';

  SELECT count(*) INTO v_n_stalls FROM public.stalls WHERE depot_id = v_depot;
  SELECT count(*) INTO v_n_veh    FROM public.vehicles WHERE home_depot_id = v_depot;
  SELECT count(*) INTO v_n_chg    FROM public.ottoq_ocpp_chargers WHERE depot_id = v_depot;
  IF v_n_stalls <> p_dcfc + p_l2 + p_wash + p_service + p_staging THEN
    RAISE EXCEPTION 'grid fixture: expected % stalls, made %', p_dcfc + p_l2 + p_wash + p_service + p_staging, v_n_stalls;
  END IF;
  IF v_n_veh <> p_n_vehicles THEN
    RAISE EXCEPTION 'grid fixture: expected % vehicles, made % (source has fewer autonomous vehicles?)', p_n_vehicles, v_n_veh;
  END IF;
  IF v_n_chg <> p_dcfc + p_l2 THEN
    RAISE EXCEPTION 'grid fixture: expected % chargers, made %', p_dcfc + p_l2, v_n_chg;
  END IF;
  RAISE NOTICE 'grid fixture % = % : % stalls (% chargers), % vehicles, scenario %',
               p_slug, v_depot, v_n_stalls, v_n_chg, v_n_veh, p_scenario_code;
  RETURN v_depot;
END;
$fn$;

COMMENT ON FUNCTION twin.ottoq_grid_fixture_create IS
  '0153: clone the flagship''s depot SHAPE into a tiny grid (N points, M assets, one plant, a bound scenario) so a certification pair runs in seconds. Ids are md5(slug,kind,ordinal), so the fixture is a function of its arguments.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_grid_fixture_the_engine_cannot_tell_from_a_depot', false,
        'Adds twin.ottoq_grid_fixture_create. Touches no flagship row; every tick-path read is depot-scoped; the matrix is depot-partitioned, so grid pairs form their own canon.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
