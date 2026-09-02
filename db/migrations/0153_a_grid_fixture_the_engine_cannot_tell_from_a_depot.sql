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
  p_scenario_seed  bigint  DEFAULT 424242,
  p_service_max_kw numeric DEFAULT 600
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
                                 'service_max_kw', p_service_max_kw,
                                 'dcfc_max_concurrent_kw', p_service_max_kw,
                                 'config', COALESCE(v_src.config,'{}'::jsonb) || jsonb_build_object('demand_limit_kw', p_service_max_kw),
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

-- ---------------------------------------------------------------------
-- Point-to-point assertions. Each row is a rule the engine's own code
-- states, checked against what the run actually wrote. A vacuous check
-- (nothing to check) FAILS, so a short run cannot pass by doing nothing.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION twin.ottoq_grid_assert(p_run uuid)
RETURNS TABLE(check_code text, passed boolean, detail text)
LANGUAGE plpgsql STABLE
AS $fn$
DECLARE
  v_depot uuid; v_status text; v_ticks int; v_cap numeric; v_max numeric;
  n bigint; n2 bigint; n3 bigint; v_out text; v_eq text;
BEGIN
  SELECT r.depot_id, r.status, r.tick_count INTO v_depot, v_status, v_ticks
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run;
  IF v_depot IS NULL THEN RAISE EXCEPTION 'grid_assert: run % not found', p_run; END IF;
  SELECT d.service_max_kw INTO v_cap FROM public.depots d WHERE d.id = v_depot;

  -- 1. the run finished
  check_code := 'run_completed'; passed := (v_status = 'completed');
  detail := 'status='||COALESCE(v_status,'-')||', ticks='||COALESCE(v_ticks::text,'-'); RETURN NEXT;

  -- 2. enactment and calendar are one act (decide_tick's own rule): every
  --    enacted stall assignment names a booking that exists for that vehicle on that point
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                         WHERE b.booking_id = (d.enacted_action->>'booking_id')::uuid
                                           AND b.sim_run_id = p_run AND b.vehicle_id = d.entity_id
                                           AND b.stall_id = (d.enacted_action->>'stall_id')::uuid))
    INTO n, n2
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted';
  check_code := 'every_enacted_assignment_is_booked'; passed := (n > 0 AND n = n2);
  detail := n2||' of '||n||' enacted assignments have their booking'||CASE WHEN n = 0 THEN ' (vacuous: none enacted)' ELSE '' END; RETURN NEXT;

  -- 3. no point double-booked, checked independently of the EXCLUDE constraint
  SELECT count(*) INTO n
    FROM public.ottoq_stall_bookings a
    JOIN public.ottoq_stall_bookings b ON b.sim_run_id = a.sim_run_id AND b.stall_id = a.stall_id
                                       AND b.booking_id > a.booking_id AND a.during && b.during
   WHERE a.sim_run_id = p_run
     AND a.state IN ('held','active','done','interrupted') AND b.state IN ('held','active','done','interrupted');
  SELECT count(*) INTO n2 FROM public.ottoq_stall_bookings WHERE sim_run_id = p_run;
  check_code := 'no_point_double_booked'; passed := (n = 0 AND n2 > 0);
  detail := n||' overlapping live bookings among '||n2||CASE WHEN n2 = 0 THEN ' (vacuous: no bookings)' ELSE '' END; RETURN NEXT;

  -- 4. every operation lands on a point capable of it
  SELECT count(*),
         count(*) FILTER (WHERE NOT (
              (b.purpose = 'charge_dcfc' AND s.stall_type::text = 'dcfc' AND s.ocpp_charger_id IS NOT NULL)
           OR (b.purpose = 'charge_l2'   AND s.stall_type::text = 'l2'   AND s.ocpp_charger_id IS NOT NULL)
           OR (b.purpose IN ('wash','detail') AND s.stall_type::text = 'wash_bay')
           OR (b.purpose = 'service' AND s.stall_type::text = 'service_bay')
           OR (b.purpose IN ('inspect','temp_hold','perimeter_hold','staging') AND s.stall_type::text = 'staging')))
    INTO n, n2
    FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
   WHERE b.sim_run_id = p_run;
  check_code := 'every_booking_on_a_capable_point'; passed := (n > 0 AND n2 = 0);
  detail := n2||' of '||n||' bookings on an incapable point'||CASE WHEN n = 0 THEN ' (vacuous)' ELSE '' END; RETURN NEXT;

  -- 5. DCFC first, L2 only as overflow (ottoq_l2_optimize_assignments' scoring rule),
  --    read off the calendar: an L2 charge booked by the local path while a DCFC point
  --    had no live booking at that instant is a violation. Legitimate exceptions to
  --    investigate before blaming the engine: a faulted charger, a live reservation.
  SELECT count(*) INTO n3 FROM public.ottoq_stall_bookings b WHERE b.sim_run_id = p_run AND b.purpose IN ('charge_dcfc','charge_l2');
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM public.stalls s
             WHERE s.depot_id = v_depot AND s.stall_type::text = 'dcfc' AND s.ocpp_charger_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings o
                                WHERE o.sim_run_id = p_run AND o.stall_id = s.id AND o.booking_id <> b.booking_id
                                  AND o.state IN ('held','active','done','interrupted')
                                  AND o.during @> lower(b.during))))
    INTO n, n2
    FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = p_run AND b.purpose = 'charge_l2' AND b.source IN ('greedy_constrained','deterministic');
  check_code := 'dcfc_first_l2_only_as_overflow'; passed := (n3 > 0 AND n2 = 0);
  detail := n2||' of '||n||' local-path L2 assignments made while a DCFC point was unbooked ('||n3||' charge bookings in all)'
            ||CASE WHEN n3 = 0 THEN ' (vacuous: no charging)' ELSE '' END; RETURN NEXT;

  -- 6. most depleted first (the cursor's ORDER BY current_soc ASC): within one tick, a
  --    fuller vehicle never takes DCFC while an emptier one is sent to L2
  SELECT count(*) INTO n
    FROM (SELECT d.tick_seq, (d.context_frame->>'current_soc')::numeric AS soc, s.stall_type::text AS st
            FROM public.ottoq_decisions d JOIN public.stalls s ON s.id = (d.enacted_action->>'stall_id')::uuid
           WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
             AND s.stall_type::text IN ('dcfc','l2')) x
   WHERE x.st = 'l2'
     AND EXISTS (SELECT 1 FROM public.ottoq_decisions d2 JOIN public.stalls s2 ON s2.id = (d2.enacted_action->>'stall_id')::uuid
                  WHERE d2.sim_run_id = p_run AND d2.tick_seq = x.tick_seq
                    AND d2.action_context = 'stall_assignment' AND d2.outcome_status = 'enacted'
                    AND s2.stall_type::text = 'dcfc' AND (d2.context_frame->>'current_soc')::numeric > x.soc);
  SELECT count(*) INTO n2
    FROM public.ottoq_decisions d JOIN public.stalls s ON s.id = (d.enacted_action->>'stall_id')::uuid
   WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
     AND s.stall_type::text IN ('dcfc','l2');
  check_code := 'most_depleted_gets_the_fast_point'; passed := (n = 0 AND n2 > 0);
  detail := n||' same-tick inversions among '||n2||' charging assignments'||CASE WHEN n2 = 0 THEN ' (vacuous)' ELSE '' END; RETURN NEXT;

  -- 7. the declared site power cap held (the 0132 gate), measured on the energy snapshots
  SELECT max(e.total_ev_charging_kw) INTO v_max FROM public.site_energy_snapshots e WHERE e.sim_run_id = p_run;
  check_code := 'site_power_cap_held'; passed := (v_cap IS NOT NULL AND v_max IS NOT NULL AND v_max <= v_cap);
  detail := 'max ev charging '||COALESCE(v_max::text,'(no snapshots)')||' kW vs service_max_kw '||COALESCE(v_cap::text,'(none declared)'); RETURN NEXT;

  -- 8. every completed service operation terminates in an SDR (the C3 rule)
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_service_detail_records r
                                         WHERE r.leg_id = l.leg_id AND r.sim_run_id = p_run))
    INTO n, n2
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = p_run AND l.status = 'done' AND l.leg_type NOT IN ('taxi','stage','depart');
  check_code := 'every_completed_operation_has_an_sdr'; passed := (n > 0 AND n = n2);
  detail := n2||' of '||n||' completed service legs have an SDR'||CASE WHEN n = 0 THEN ' (vacuous: none completed)' ELSE '' END; RETURN NEXT;

  -- 9. every refusal carries a reason code
  SELECT count(*), count(*) FILTER (WHERE reason_code IS NULL) INTO n, n2
    FROM public.ottoq_vehicle_commands WHERE sim_run_id = p_run AND status = 'refused';
  check_code := 'every_refusal_carries_a_reason'; passed := (n2 = 0);
  detail := n2||' of '||n||' refusals without a reason code'||CASE WHEN n = 0 THEN ' (no refusals)' ELSE '' END; RETURN NEXT;

  -- 10. the proposer stayed out (0152)
  SELECT count(*), count(*) FILTER (WHERE abstained_reason IS DISTINCT FROM 'policy_disabled') INTO n, n2
    FROM public.cuopt_invocation_log WHERE sim_run_id = p_run;
  check_code := 'proposer_quiesced'; passed := (n > 0 AND n2 = 0);
  detail := n||' proposer invocations, '||n2||' other than policy_disabled'; RETURN NEXT;

  -- 11. the same seed produced the same run (the pair verdict on this arm)
  SELECT r.validation_notes::jsonb->>'outcome', r.validation_notes::jsonb->>'equal' INTO v_out, v_eq
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run;
  check_code := 'pair_verdict_passed'; passed := (v_out = 'passed');
  detail := COALESCE('outcome='||v_out||', equal='||v_eq, 'no verdict on this run (not a certification arm)'); RETURN NEXT;
  RETURN;
END;
$fn$;

COMMENT ON FUNCTION twin.ottoq_grid_assert(uuid) IS
  '0153: point-to-point conformance of one run against the engine''s own stated rules. Vacuous checks fail.';

-- One command: run a certification pair on the fixture and assert it.
CREATE OR REPLACE FUNCTION twin.ottoq_grid_smoke(
  p_seed      bigint      DEFAULT 424242,
  p_ticks     int         DEFAULT 12,
  p_slug      text        DEFAULT 'grid-fixture',
  p_scenario  text        DEFAULT 'grid_smoke',
  p_sim_start timestamptz DEFAULT '2026-09-01 02:00:00+00'
) RETURNS TABLE(check_code text, passed boolean, detail text)
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_depot uuid := md5('ottoq_grid_fixture:'||p_slug)::uuid;
  t0 timestamptz := clock_timestamp();
  v_arm uuid; v_secs numeric;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = v_depot) THEN
    RAISE EXCEPTION 'grid fixture % does not exist - run twin.ottoq_grid_fixture_create(%)', p_slug, quote_literal(p_slug);
  END IF;
  PERFORM public.ottoq_determinism_pair(p_seed, p_ticks, p_scenario, v_depot, p_sim_start, 120);
  v_secs := round(EXTRACT(epoch FROM clock_timestamp() - t0)::numeric, 1);
  SELECT r.sim_run_id INTO v_arm FROM public.ottoq_sim_runs r
   WHERE r.depot_id = v_depot AND r.run_by = 'cert_harness'
   ORDER BY r.started_at DESC, r.sim_run_id DESC LIMIT 1;
  check_code := 'pair_wall_seconds'; passed := true;
  detail := v_secs||' s for two '||p_ticks||'-tick arms on '||p_slug||', seed '||p_seed||', arm '||v_arm::text; RETURN NEXT;
  RETURN QUERY SELECT a.check_code, a.passed, a.detail FROM twin.ottoq_grid_assert(v_arm) a;
  RETURN;
END;
$fn$;

COMMENT ON FUNCTION twin.ottoq_grid_smoke(bigint, int, text, text, timestamptz) IS
  '0153: one command - a two-arm certification pair on the grid fixture, then the point-to-point assertions. Seconds, not hours.';


COMMENT ON FUNCTION twin.ottoq_grid_fixture_create IS
  '0153: clone the flagship''s depot SHAPE into a tiny grid (N points, M assets, one plant, a bound scenario) so a certification pair runs in seconds. Ids are md5(slug,kind,ordinal), so the fixture is a function of its arguments.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_grid_fixture_the_engine_cannot_tell_from_a_depot', false,
        'Adds twin.ottoq_grid_fixture_create. Touches no flagship row; every tick-path read is depot-scoped; the matrix is depot-partitioned, so grid pairs form their own canon.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
