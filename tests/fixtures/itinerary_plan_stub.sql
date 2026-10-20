-- tests/fixtures/itinerary_plan_stub.sql: the itinerary planner as live, for tests/test_itinerary_charge_on_clock_sql.py
-- (db/migrations/0745). Loaded on the miniature depot of tests/test_agent_charge_order_sql.py taken through 0642 (whose
-- charge clock, plug test and charge line are the live bodies) and tests/fixtures/ready_promise_stub.sql. Read from the
-- live catalog on 2026-10-17 (the tests assert each md5 of prosrc): public.ottoq_plan_visit_itinerary 990e9481, the
-- physics it times a charge with, public.ottoq_estimate_charge_minutes 24de68cf over public.ottoq_sim_compute_charge_rate
-- b0a5b152 and twin.ottoq_sim_seeded_random 237b754a, and twin.ottoq_sim_lane_capacity ef28379b and
-- public.ottoq_svc_to_leg_type fb647f62. The itinerary tables are the live columns; service_cadence_policy carries only the
-- three the planner reads. Arm 84's and arm 83's sweeps and cells are the live rows 0745's P1 reads.
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS public.ottoq_vehicle_itineraries (
  itinerary_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid NOT NULL, depot_id uuid NOT NULL,
  vehicle_id uuid NOT NULL, created_by text NOT NULL DEFAULT 'decide_tick', status text NOT NULL DEFAULT 'active',
  sim_created_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), visit_id uuid);
CREATE TABLE IF NOT EXISTS public.ottoq_itinerary_legs (
  leg_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), itinerary_id uuid NOT NULL, sim_run_id uuid NOT NULL,
  vehicle_id uuid NOT NULL, seq integer NOT NULL, leg_type text NOT NULL, from_stall_id uuid, to_stall_id uuid,
  planned_start_sim timestamptz, planned_end_sim timestamptz, planned_duration_s integer,
  duration_basis jsonb NOT NULL DEFAULT '{}'::jsonb, actual_start_sim timestamptz, actual_end_sim timestamptz,
  status text NOT NULL DEFAULT 'planned', deviation_s integer, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.service_cadence_policy (svc text PRIMARY KEY, is_active boolean, est_min_default numeric);
INSERT INTO public.service_cadence_policy (svc, is_active, est_min_default)
VALUES ('exterior_wash', true, 9), ('interior_deep_clean', true, 25), ('fault_repair', true, 40)
ON CONFLICT (svc) DO NOTHING;

-- live: the two cells 0745 pairs with (arm 84's and arm 83's), as read on 2026-10-17
INSERT INTO public.ottoq_throughput_sweeps (sweep_id, sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, created_at)
VALUES ('5a1b0e8c-7c3a-4d6e-9f1a-0745000000a4', 'dcfc40_power_normal_2026_10_17', 'stub of the live row (2026-10-17): arm 84''s sweep',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 16, 5400, 'active', '2026-10-17 07:31:42.87498+00'),
       ('5a1b0e8c-7c3a-4d6e-9f1a-0745000000a3', 'dcfc40_normal_2026_10_17', 'stub of the live row (2026-10-17): arm 83''s sweep',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 19, 5400, 'active', '2026-10-17 06:33:28.053415+00');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
VALUES ('5a1b0e8c-7c3a-4d6e-9f1a-0745000000a4', 'dcfc40.otto_q', 1, 'otto_q', 'dcfc40', '{"deploy_peak_fraction": 0.90}'),
       ('5a1b0e8c-7c3a-4d6e-9f1a-0745000000a3', 'dcfc10.otto_q', 1, 'otto_q', 'dcfc10', '{"deploy_peak_fraction": 0.90}');

-- the live bodies (pg_get_functiondef headers, prosrc byte for byte)
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seeded_random(p_seed bigint, p_salt text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hash BIGINT;
BEGIN
  -- Combine seed + salt into a deterministic hash, normalize to [0,1)
  v_hash := abs(hashtextextended(p_seed::text || ':' || p_salt, p_seed));
  RETURN (v_hash % 1000000)::NUMERIC / 1000000.0;
END;
$function$;
CREATE OR REPLACE FUNCTION public.ottoq_sim_compute_charge_rate(p_soc_pct numeric, p_battery_temp_c numeric, p_ambient_temp_c numeric, p_charger_max_kw numeric, p_vehicle_max_kw numeric, p_battery_capacity_kwh numeric, p_battery_soh_pct numeric DEFAULT 100, p_noise_seed bigint DEFAULT 0, p_noise_salt text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_base_rate      NUMERIC;
  v_is_dcfc        BOOLEAN;
  v_curve_factor   NUMERIC := 1.0;
  v_thermal_factor NUMERIC := 1.0;
  v_soh_factor     NUMERIC;
  v_noise_factor   NUMERIC;
  v_accept         NUMERIC[];
  v_soc            NUMERIC;
  v_i              INT;
BEGIN
  v_base_rate := LEAST(p_charger_max_kw, p_vehicle_max_kw);
  IF v_base_rate <= 0 THEN RETURN 0; END IF;
  v_is_dcfc := p_charger_max_kw > 22;

  IF v_is_dcfc AND p_battery_capacity_kwh > 0 THEN
    -- 0573: what the battery accepts, in kW per usable kWh, at 0, 5, ..., 100% charge, capped by the car's and the
    -- charger's maxima. Sources and fits: docs/research/direct/2026-09-30-lane-a-service-time-calibration.md.
    v_accept := CASE
      -- Tesla Model Y Long Range (250 kW, 75 kWh usable): its own measured curve (Fastned, figshare
      -- doi:10.6084/m9.figshare.30570653.v1) to 90%, then the median tail of the 20 curves measured to 98%+
      WHEN p_vehicle_max_kw = 250 AND p_battery_capacity_kwh = 75 THEN
        ARRAY[3.062, 3.062, 2.934, 2.607, 2.428, 2.315, 2.191, 1.953, 1.758, 1.570, 1.404,
              1.244, 1.112, 1.042, 0.971, 0.878, 0.647, 0.593, 0.461, 0.375, 0.219]::numeric[]
      -- Jaguar I-PACE (104 kW, 84.7 kWh usable): its maximum to 50%, then fitted so 10-80% takes EV Database's
      -- published 45 minutes, then the median tail
      WHEN p_vehicle_max_kw = 104 AND p_battery_capacity_kwh = 84.7 THEN
        ARRAY[3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000,
              1.079, 0.929, 0.780, 0.631, 0.481, 0.332, 0.309, 0.278, 0.219, 0.103]::numeric[]
      -- every other battery: the median over the dataset's 99 measured curves
      ELSE
        ARRAY[1.906, 1.949, 1.992, 1.991, 1.945, 1.948, 1.855, 1.679, 1.653, 1.581, 1.543,
              1.367, 1.229, 1.121, 1.013, 0.950, 0.790, 0.702, 0.608, 0.484, 0.312]::numeric[]
    END;
    v_soc := LEAST(100, GREATEST(0, COALESCE(p_soc_pct, 100)));
    v_i := LEAST(19, floor(v_soc / 5)::int);
    v_curve_factor := LEAST(1.0, p_battery_capacity_kwh
                                 * (v_accept[v_i + 1] + (v_accept[v_i + 2] - v_accept[v_i + 1]) * (v_soc - 5 * v_i) / 5)
                                 / v_base_rate);
  ELSIF v_is_dcfc THEN
    -- no battery size given: the shape used before 0573
    IF p_soc_pct < 20 THEN
      v_curve_factor := 0.85 + (p_soc_pct / 20.0) * 0.15;
    ELSIF p_soc_pct <= 80 THEN
      v_curve_factor := 1.0 - ((p_soc_pct - 20.0) / 60.0) * 0.78;
    ELSE
      v_curve_factor := GREATEST(0.08, 0.22 - ((p_soc_pct - 80.0) / 20.0) * 0.14);
    END IF;
  ELSE
    -- L2/AC: onboard-charger limited, flat with ~88% AC->DC efficiency;
    -- taper only near full.
    v_curve_factor := CASE WHEN p_soc_pct > 95 THEN 0.88 * 0.5 ELSE 0.88 END;
  END IF;

  -- thermal derate: INL-calibrated cold behavior; heat derate unchanged
  IF p_battery_temp_c > 35 THEN
    v_thermal_factor := GREATEST(0.30, 1.0 - (p_battery_temp_c - 35) * 0.020);
  ELSIF p_battery_temp_c < 0 THEN
    v_thermal_factor := GREATEST(0.20, 0.35 + p_battery_temp_c * 0.010);  -- <=0C: 0.35 and falling
  ELSIF p_battery_temp_c < 10 THEN
    v_thermal_factor := 0.65;                                             -- 0-10C: x0.65 (INL)
  ELSIF p_battery_temp_c < 15 THEN
    v_thermal_factor := 0.65 + (p_battery_temp_c - 10) * 0.07;            -- blend 10->15C
  END IF;

  v_soh_factor := 0.70 + (p_battery_soh_pct / 100.0) * 0.30;
  v_noise_factor := 0.97 + ottoq_sim_seeded_random(
    p_noise_seed, COALESCE(p_noise_salt, '') || ':' || p_soc_pct::text) * 0.06;

  RETURN ROUND((v_base_rate * v_curve_factor * v_thermal_factor * v_soh_factor * v_noise_factor)::NUMERIC, 3);
END;
$function$;
CREATE OR REPLACE FUNCTION public.ottoq_estimate_charge_minutes(p_start_soc numeric, p_target_soc numeric, p_charger_max_kw numeric, p_vehicle_max_kw numeric, p_battery_capacity_kwh numeric, p_battery_temp_c numeric DEFAULT 25, p_battery_soh_pct numeric DEFAULT 95, p_rate_mult numeric DEFAULT 1.0)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc  numeric := p_start_soc;
  v_step numeric := 1.0;
  v_kw   numeric;
  v_min  numeric := 0;
BEGIN
  IF p_target_soc <= p_start_soc OR p_battery_capacity_kwh <= 0 THEN RETURN 0; END IF;
  WHILE v_soc < p_target_soc LOOP
    v_kw := public.ottoq_sim_compute_charge_rate(
      p_soc_pct := v_soc,
      p_battery_temp_c := p_battery_temp_c,
      p_ambient_temp_c := p_battery_temp_c,
      p_charger_max_kw := p_charger_max_kw,
      p_vehicle_max_kw := p_vehicle_max_kw,
      p_battery_capacity_kwh := p_battery_capacity_kwh,
      p_battery_soh_pct := p_battery_soh_pct,
      p_noise_seed := 0, p_noise_salt := 'plan');
    v_kw := v_kw / GREATEST(0.2, p_rate_mult);
    EXIT WHEN v_kw <= 0.5;
    v_min := v_min + (v_step / 100.0 * p_battery_capacity_kwh) / v_kw * 60.0;
    v_soc := v_soc + v_step;
  END LOOP;
  RETURN ROUND(v_min, 1);
END;
$function$;
CREATE OR REPLACE FUNCTION twin.ottoq_sim_lane_capacity(p_sim_run_id uuid, p_lane_staff_key text, p_physical integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_knobs   JSONB;
  v_master  NUMERIC;
  v_lane    NUMERIC;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN p_physical; END IF;
  SELECT knobs INTO v_knobs FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  IF v_knobs IS NULL THEN RETURN p_physical; END IF;
  v_master := COALESCE((v_knobs #>> ARRAY['_rates','staffing_level'])::numeric, 1);
  v_lane   := COALESCE((v_knobs #>> ARRAY['_rates', p_lane_staff_key])::numeric, 1);
  -- Any positive staffing keeps at least ONE lane open (understaffing slows the
  -- flow + grows staging; it never fully gridlocks). Zero staffing = closed.
  IF v_master * v_lane <= 0 THEN RETURN 0; END IF;
  RETURN GREATEST(1, FLOOR(p_physical * v_master * v_lane))::int;
END;
$function$;
CREATE OR REPLACE FUNCTION public.ottoq_svc_to_leg_type(p_svc text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    -- twin codes that are already valid itinerary leg types: pass through unchanged
    WHEN p_svc = ANY (ARRAY['interior_tidy','sensor_clean','item_retrieval','software_update',
                            'remote_diagnostics','triage_check','sensor_calibration','perimeter_walkaround',
                            'mechanical_pm','fault_repair','cosmetic_repair'])
      THEN p_svc
    -- twin codes with a distinct itinerary spelling (matches the bay loop's existing CASE)
    WHEN p_svc = 'exterior_wash'       THEN 'wash'
    WHEN p_svc = 'interior_deep_clean' THEN 'detail'
    WHEN p_svc = 'interior_inspection' THEN 'inspect'
    -- Anything the twin invents that OTTO-Q has no leg for lands on the generic service leg.
    -- DO NOT remove this ELSE: totality is the whole point. The true code is preserved in
    -- ottoq_itinerary_legs.payload->>'atom', so the remap is lossless.
    ELSE 'service'
  END;
$function$;
CREATE OR REPLACE FUNCTION public.ottoq_plan_visit_itinerary(p_sim_run_id uuid, p_vehicle uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_visit RECORD; v_veh RECORD; v_itin uuid; v_depot uuid;
  v_a jsonb; v_cursor timestamptz; v_charge_start timestamptz; v_charge_end timestamptz;
  v_min numeric; v_seq int := 0; v_n int := 0;
  v_wash_wait numeric; v_svc_wait numeric;
  v_charger_kw numeric; v_charge_leg_type text;
  v_itin_visit uuid;                       -- 0011
  v_fault_first boolean := false;          -- 0558 (G292)
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
  SELECT vn.visit_id, vn.atoms, vn.urgency, vn.dispatch_due_at, vn.target_soc INTO v_visit
    FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
   ORDER BY vn.created_at DESC, vn.visit_key DESC /* 0129 */ LIMIT 1;
  IF v_visit.visit_id IS NULL THEN RETURN 0; END IF;
  SELECT home_depot_id, current_soc, COALESCE(inlet_max_kw,150) AS inlet_kw,
         COALESCE(battery_capacity_kwh,75) AS pack_kwh
    INTO v_veh FROM vehicles WHERE id = p_vehicle;
  v_depot := v_veh.home_depot_id;

  SELECT itinerary_id, visit_id INTO v_itin, v_itin_visit
    FROM ottoq_vehicle_itineraries
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle AND status = 'active'
   ORDER BY sim_created_at DESC, created_at DESC, itinerary_id DESC /* 0129 */ LIMIT 1;

  -- ══════════════════ 0011: STALE-ITINERARY UNBLOCK ══════════════════
  -- An active itinerary that names a DIFFERENT visit is a leftover. Closing it is the same
  -- act ottoq_release_visit_artifacts performs at redeploy, so no new lifecycle is invented.
  IF v_itin IS NOT NULL
     AND v_itin_visit IS NOT NULL
     AND v_itin_visit <> v_visit.visit_id
     AND public.ottoq_policy_get(p_sim_run_id, 'stale_itinerary_unblocks_replan', 1) >= 1 THEN
    UPDATE ottoq_itinerary_legs SET status = 'skipped'
     WHERE itinerary_id = v_itin AND status IN ('planned');
    UPDATE ottoq_vehicle_itineraries SET status = 'completed' WHERE itinerary_id = v_itin;
    v_itin := NULL; v_itin_visit := NULL;
  END IF;

  -- Unchanged protection: never double-plan the visit this itinerary already covers.
  IF v_itin IS NOT NULL AND EXISTS (SELECT 1 FROM ottoq_itinerary_legs
        WHERE itinerary_id = v_itin AND status = 'planned') THEN
    RETURN 0;
  END IF;
  IF v_itin IS NULL THEN
    INSERT INTO ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at, visit_id)
    VALUES (p_sim_run_id, v_depot, p_vehicle, 'flow_contract_m4', p_clock, v_visit.visit_id)
    RETURNING itinerary_id INTO v_itin;
  ELSE
    -- Appending to an existing active itinerary for this same visit: stamp the visit if the
    -- row predates 0011, so the next call can tell stale from current.
    UPDATE ottoq_vehicle_itineraries SET visit_id = COALESCE(visit_id, v_visit.visit_id)
     WHERE itinerary_id = v_itin;
  END IF;
  SELECT COALESCE(MAX(seq),0) INTO v_seq FROM ottoq_itinerary_legs WHERE itinerary_id = v_itin;

  SELECT count(*) * 10.0 / GREATEST(1, ottoq_sim_lane_capacity(NULL,'cleaning_staff',3)) INTO v_wash_wait
    FROM vehicles WHERE home_depot_id = v_depot AND current_state IN ('in_wash_bay','in_detail_bay');
  SELECT count(*) * 40.0 / GREATEST(1, ottoq_sim_lane_capacity(NULL,'service_staff',2)) INTO v_svc_wait
    FROM vehicles WHERE home_depot_id = v_depot AND current_state = 'in_service_bay';

  v_cursor := p_clock;

  -- 0558 (G292, CLAUDE.md rule 9): a car with an open vehicle fault is repaired first. The emission gate refuses its
  -- charge until the repair is done (0557), so a plan with the charge first and the repair after it can never start:
  -- on 0411's run the car waited from 5:09 AM behind an 8-hour charge, its repair booked for 1:24 PM. The repair's
  -- service leg goes first, at the plan's start, and every other leg after it.
  v_fault_first := public.ottoq_vehicle_fault_open((SELECT vh.config FROM vehicles vh WHERE vh.id = p_vehicle))
                   AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_visit.atoms) a
                                WHERE a->>'svc' = 'fault_repair' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'));
  IF v_fault_first THEN
    SELECT a INTO v_a FROM jsonb_array_elements(v_visit.atoms) a
     WHERE a->>'svc' = 'fault_repair' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled') LIMIT 1;
    v_min := COALESCE((v_a->>'est_min')::numeric,
                      (SELECT scp.est_min_default FROM public.service_cadence_policy scp
                        WHERE scp.svc = 'fault_repair' AND scp.is_active LIMIT 1),
                      20);
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, 'service',
           v_cursor, v_cursor + (v_min::text || ' minutes')::interval, (v_min*60)::int,
           jsonb_build_object('kind','flow_contract','atom','fault_repair',
                              'queue_wait_min',round(COALESCE(v_svc_wait,0),1),'first_because','vehicle_fault_open'),
           'planned');
    v_cursor := v_cursor + (v_min::text || ' minutes')::interval;
  END IF;

  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_visit.atoms) a
              WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')) THEN
    SELECT a INTO v_a FROM jsonb_array_elements(v_visit.atoms) a
     WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled') LIMIT 1;
    v_charger_kw := (CASE WHEN v_veh.current_soc < 45 THEN 100 ELSE 11 END);
    v_charge_leg_type := (CASE WHEN v_veh.current_soc < 45 THEN 'charge_dcfc' ELSE 'charge_l2' END);
    BEGIN
      SELECT ottoq_estimate_charge_minutes(v_veh.current_soc,
             COALESCE((v_a->>'target_soc')::numeric, v_visit.target_soc, public.ottoq_default_target_soc()),
             v_charger_kw, v_veh.inlet_kw, v_veh.pack_kwh, 20, 100, 1.0) INTO v_min;
    EXCEPTION WHEN OTHERS THEN
      v_min := GREATEST(10, (COALESCE((v_a->>'target_soc')::numeric, public.ottoq_default_target_soc()) - v_veh.current_soc) * 1.2);
    END;
    v_min := COALESCE(v_min, 25);
    v_charge_start := v_cursor; v_charge_end := v_cursor + (v_min::text || ' minutes')::interval;
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, v_charge_leg_type, v_charge_start, v_charge_end,
           (v_min*60)::int, jsonb_build_object('kind','flow_contract','charger_kw_assumed',v_charger_kw), 'planned');
    FOR v_a IN SELECT a FROM jsonb_array_elements(v_visit.atoms) a LOOP
      IF v_a->>'concurrency' IN ('cabin','exterior','digital')
         AND v_a->>'svc' NOT IN ('readiness_check')
         AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
        v_seq := v_seq + 1; v_n := v_n + 1;
        INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
               planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
        VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, public.ottoq_svc_to_leg_type(v_a->>'svc'), v_charge_start,
               v_charge_start + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval,
               (COALESCE((v_a->>'est_min')::numeric,5)*60)::int,
               jsonb_build_object('kind','flow_contract','concurrent_with','charge','atom',v_a->>'svc'), 'planned');
      END IF;
    END LOOP;
    v_cursor := v_charge_end;
  ELSE
    FOR v_a IN SELECT a FROM jsonb_array_elements(v_visit.atoms) a LOOP
      IF v_a->>'concurrency' IN ('cabin','exterior','digital')
         AND v_a->>'svc' NOT IN ('readiness_check')
         AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
        v_seq := v_seq + 1; v_n := v_n + 1;
        INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
               planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
        VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, public.ottoq_svc_to_leg_type(v_a->>'svc'), v_cursor,
               v_cursor + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval,
               (COALESCE((v_a->>'est_min')::numeric,5)*60)::int,
               jsonb_build_object('kind','flow_contract','atom',v_a->>'svc'), 'planned');
      END IF;
    END LOOP;
    v_cursor := v_cursor + interval '10 minutes';
  END IF;

  FOR v_a IN
    SELECT a FROM jsonb_array_elements(v_visit.atoms) a
    WHERE a->>'concurrency' = 'bay' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
      AND NOT (v_fault_first AND a->>'svc' = 'fault_repair')   -- 0558 (G292): planned first, above
    ORDER BY (CASE a->>'svc' WHEN 'exterior_wash' THEN 1 WHEN 'interior_deep_clean' THEN 2
                             WHEN 'sensor_calibration' THEN 3 WHEN 'mechanical_pm' THEN 4
                             WHEN 'fault_repair' THEN 5 ELSE 6 END)
  LOOP
    -- Duration is the SERVICE time only; the forward calendar expresses contention
      -- by moving the leg, not by inflating it. (queue_wait_min is still recorded in
      -- duration_basis below for diagnostics.)
      -- 0011: the dwell is a LOOKUP. Atom est_min first (the manifest already priced it),
      -- then service_cadence_policy.est_min_default, then 20 as a last resort.
      v_min := COALESCE((v_a->>'est_min')::numeric,
                        (SELECT scp.est_min_default FROM public.service_cadence_policy scp
                          WHERE scp.svc = v_a->>'svc' AND scp.is_active LIMIT 1),
                        20);
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq,
           (CASE v_a->>'svc' WHEN 'exterior_wash' THEN 'wash' WHEN 'interior_deep_clean' THEN 'detail'
                             ELSE 'service' END),
           v_cursor, v_cursor + (v_min::text || ' minutes')::interval, (v_min*60)::int,
           jsonb_build_object('kind','flow_contract','atom',v_a->>'svc','queue_wait_min',
             round((CASE WHEN v_a->>'requires_bay' IN ('wash_bay','detail') THEN COALESCE(v_wash_wait,0) ELSE COALESCE(v_svc_wait,0) END),1)), 'planned');
    v_cursor := v_cursor + (v_min::text || ' minutes')::interval;
  END LOOP;

  IF v_visit.urgency = 'overnight_hold' AND v_visit.dispatch_due_at IS NOT NULL AND v_visit.dispatch_due_at > v_cursor THEN
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, 'stage', v_cursor, v_visit.dispatch_due_at,
           GREATEST(0, EXTRACT(EPOCH FROM (v_visit.dispatch_due_at - v_cursor)))::int,
           jsonb_build_object('kind','flow_contract','reason','overnight_hold'), 'planned');
    v_cursor := v_visit.dispatch_due_at;
  END IF;
  v_seq := v_seq + 1; v_n := v_n + 1;
  INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
         planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
  VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, 'inspect', v_cursor, v_cursor + interval '3 minutes',
         180, jsonb_build_object('kind','flow_contract','atom','readiness_check'), 'planned');
  RETURN v_n;
END; $function$;
