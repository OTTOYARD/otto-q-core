-- A stub engine for ottoq.ottoq_derive_visit_needs (0715). The derive below is the live definition byte for byte
-- (md5(pg_get_functiondef) cd5c513bb164a14614003e308009a347 on 2026-10-13); everything around it is the least it reads,
-- with the helpers it calls reduced to constants (a target of 100, no feed plan, an SLA floor of 80, a 30-minute charge
-- estimate) and the atom guard as the identity (the live guard keeps a required PM or calibration atom as it is:
-- measured 2026-10-13, ottoq_atoms_guard md5 2ce83de7).
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, fleet_operator_id uuid, current_soc numeric, battery_capacity_kwh numeric,
  inlet_max_kw numeric, config jsonb DEFAULT '{}'::jsonb);
CREATE TABLE public.ottoq_vehicle_wear (vehicle_id uuid, sim_run_id uuid, soil_index numeric, drive_km_total numeric,
  km_at_last_pm numeric, drive_hours_total numeric, hours_at_last_calibration numeric, updated_at timestamptz DEFAULT now());
CREATE TABLE public.vehicle_need_profile (vehicle_id uuid PRIMARY KEY, last_wash_at timestamptz, wash_interval_h numeric,
  cabin_condition text);
CREATE TABLE public.service_cadence_policy (svc text, overdue_ratio numeric, is_active boolean);
CREATE TABLE public.ottoq_rider_cleaning_flags (flag_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid,
  vehicle_id uuid, flag_kind text, status text, recalled_visit_key text, recalled_visit_id uuid,
  raised_at_sim_clock timestamptz, served_at_sim_clock timestamptz, recalled_at_sim_clock timestamptz);
CREATE TABLE public.ottoq_visit_needs (visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid,
  sim_run_id uuid, depot_id uuid, arrived_at timestamptz, visit_key text, archetype text, urgency text,
  dispatch_due_at timestamptz, target_soc numeric, atoms jsonb, status text DEFAULT 'open', source text, meta jsonb,
  created_at timestamptz DEFAULT now());
CREATE UNIQUE INDEX ON public.ottoq_visit_needs (vehicle_id, visit_key,
  (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)));
CREATE TABLE public.ottoq_vehicle_dispatches (dispatch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid,
  sim_run_id uuid, dispatched_at timestamptz, return_trigger text);
CREATE TABLE public.ottoq_policy_params (scope_type text, scope_id uuid, param_key text, param_value numeric,
  updated_by text, updated_at timestamptz, PRIMARY KEY (scope_type, scope_id, param_key));
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial, label text, object_kind text, schema_name text,
  object_name text, definition text, def_md5 text);
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean, note text, classified_at timestamptz);
CREATE FUNCTION public.ottoq_certification_in_flight(p boolean) RETURNS integer LANGUAGE sql AS $f$ SELECT 0 $f$;
CREATE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric) RETURNS numeric
LANGUAGE sql STABLE AS $f$
  SELECT COALESCE((SELECT param_value FROM public.ottoq_policy_params
                    WHERE scope_type = 'run' AND scope_id = p_sim_run_id AND param_key = p_param_key), p_default) $f$;
CREATE FUNCTION public.ottoq_effective_target_soc_at(p_vehicle_id uuid, p_clock timestamptz) RETURNS numeric
LANGUAGE sql STABLE AS $f$ SELECT 100::numeric $f$;
CREATE FUNCTION public.ottoq_feed_plan(p_kind text) RETURNS jsonb LANGUAGE sql STABLE AS $f$ SELECT NULL::jsonb $f$;
CREATE FUNCTION public.ottoq_get_active_sla(p_operator uuid) RETURNS TABLE (min_soc_at_deployment_pct numeric)
LANGUAGE sql STABLE AS $f$ SELECT 80::numeric $f$;
CREATE FUNCTION public.ottoq_estimate_charge_minutes(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $f$ SELECT 30::numeric $f$;
CREATE FUNCTION ottoq.ottoq_atoms_guard(p_atoms jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$ SELECT p_atoms $f$;
CREATE OR REPLACE FUNCTION ottoq.ottoq_derive_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_clock timestamp with time zone, p_depot_id uuid, p_obs jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc numeric; v_target numeric; v_cycles int; v_m jsonb := '[]'::jsonb;
  v_depot uuid := p_depot_id; v_clock timestamptz := p_clock; v_run uuid := p_run; v_plan jsonb; v_visit text;
  v_precip_stress numeric := 0; v_boost numeric := 0;
  v_conf numeric;
  v_hour int; v_urgency text; v_due timestamptz; v_visit_target numeric;
  v_is_night boolean; v_night_start int; v_night_end int;
  v_fault boolean := false; v_ota boolean := false;
  v_band_lo numeric; v_band_hi numeric;
  v_sla_floor numeric; v_sim_day int;
  v_carry jsonb; v_carry_visit uuid; v_atom jsonb;
  v_archetype text;
  v_wear RECORD; v_soil numeric := 0; v_cap numeric; v_inlet_kw numeric; v_soh numeric;
  v_curve numeric; v_svcspd numeric; v_pm_int numeric; v_calib_int numeric; v_washcad int;
  v_wash_min int; v_deep_min int; v_pm_min int; v_calib_min int; v_charge_min int := 0;
  v_last_wash timestamptz; v_wash_int numeric; v_wash_ratio numeric; v_wash_overdue boolean := false;
  v_cabin_cond text; v_deep_clean_due boolean := false;
  v_rf_id uuid; v_rf_kind text; v_rf_status text; v_rf_visit text;
  v_rf_svc text; v_rf_min int;
  v_visit_id uuid; v_rf_prev_visit_id uuid; v_this_visit_id uuid;
  v_rf_place boolean := false; v_rf_retire boolean := false;
  v_observer  text := COALESCE(p_obs->>'observer',  'unknown');
  v_generator text := COALESCE(p_obs->>'generator', 'v5_state');
BEGIN
  IF p_obs IS NULL OR jsonb_typeof(p_obs) <> 'object' THEN
    RAISE EXCEPTION 'ottoq_derive_visit_needs: observations are required (got %)', COALESCE(jsonb_typeof(p_obs),'NULL')
      USING ERRCODE = 'P0001';
  END IF;

  -- ===== ASSET STATE =====
  SELECT current_soc, public.ottoq_effective_target_soc_at(p_vehicle_id, v_clock) /* 0539: the owner's, not the last plan's stamp */, COALESCE((config->>'cycles_since_wash')::int,0),
         battery_capacity_kwh, inlet_max_kw,
         (config->>'battery_soh_pct')::numeric, (config->>'charge_curve_scalar')::numeric,
         (config->>'service_speed_scalar')::numeric, (config->>'pm_interval_km')::numeric,
         (config->>'calib_interval_h')::numeric, (config->>'wash_cadence_cycles')::int
    INTO v_soc, v_target, v_cycles,
         v_cap, v_inlet_kw, v_soh, v_curve, v_svcspd, v_pm_int, v_calib_int, v_washcad
    FROM public.vehicles WHERE id = p_vehicle_id;
  IF v_soc IS NULL THEN RETURN NULL; END IF;
  SELECT w.soil_index,
         w.drive_km_total    - COALESCE(w.km_at_last_pm,0)             AS km_since_pm,
         w.drive_hours_total - COALESCE(w.hours_at_last_calibration,0) AS h_since_calib
    INTO v_wear FROM public.ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND (p_sim_run_id IS NULL OR w.sim_run_id = p_sim_run_id)
   ORDER BY w.updated_at DESC LIMIT 1;
  -- an OBSERVED soil reading outranks modelled wear; the twin observer never sets it
  v_soil := COALESCE((p_obs->>'soil_index')::numeric, v_wear.soil_index, 0);

  SELECT p.last_wash_at, p.wash_interval_h, p.cabin_condition
    INTO v_last_wash, v_wash_int, v_cabin_cond
    FROM public.vehicle_need_profile p
   WHERE p.vehicle_id = p_vehicle_id;

  v_plan  := public.ottoq_feed_plan('service_manifest');
  v_visit := p_vehicle_id::text || ':' || to_char(v_clock, 'YYYYMMDDHH24MISS');
  v_sim_day := (v_clock::date - DATE '2020-01-01');

  -- ===== OBSERVATIONS (environment) =====
  v_precip_stress := COALESCE((p_obs->>'precip_stress')::numeric, 0);
  v_boost         := COALESCE((p_obs->>'wet_boost')::numeric, 0);

  -- ===== POLICY =====
  v_band_lo := COALESCE((v_plan->>'confirm_band_lo')::numeric, 0.40);
  v_band_hi := COALESCE((v_plan->>'confirm_band_hi')::numeric, 0.75);

  -- ===== URGENCY: a fault holds the car; otherwise the observed intent, else standard =====
  v_fault := COALESCE((p_obs->>'fault')::boolean, false);
  v_hour  := EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int;
  IF v_fault THEN
    v_urgency := 'tech_hold';
  ELSE
    v_urgency := COALESCE(p_obs->>'urgency_intent', 'standard');
  END IF;
  v_due := CASE v_urgency
    WHEN 'immediate_dispatch' THEN v_clock + interval '45 minutes'
    WHEN 'overnight_hold' THEN
      (((v_clock AT TIME ZONE 'America/Chicago')::date
        + CASE WHEN v_hour >= 4 THEN 1 ELSE 0 END) + time '07:00') AT TIME ZONE 'America/Chicago'
    ELSE NULL END;
  BEGIN
    SELECT min_soc_at_deployment_pct INTO v_sla_floor
      FROM public.ottoq_get_active_sla((SELECT fleet_operator_id FROM public.vehicles WHERE id = p_vehicle_id));
  EXCEPTION WHEN OTHERS THEN v_sla_floor := NULL; END;
  v_sla_floor := COALESCE(v_sla_floor, 80);
  -- 0539 (CLAUDE.md rule 9): every visit charges the car to its target, whatever the urgency. An immediate dispatch
  -- keeps its 45-minute due time. It was also charged less, to the SLA floor + 5 (85), which no owner asked for.
  v_visit_target := v_target;

  -- ===== DURATIONS: nominal x observed variability x the vehicle's service-speed scalar =====
  v_wash_min  := GREATEST(8, LEAST(10, round(9 * COALESCE((p_obs->>'deal_wash_time')::numeric, 1.0) * COALESCE(v_svcspd,1))))::int;
  v_deep_min  := GREATEST(12, round(20 * COALESCE((p_obs->>'deal_detail_time')::numeric, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_pm_min    := GREATEST(20, round(40 * COALESCE((p_obs->>'deal_maintenance_time')::numeric, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_calib_min := GREATEST(30, round(60 * COALESCE(v_svcspd,1)))::int;  -- 0573: 60 min typical (30-120), public static calibration times
  IF v_soc < v_visit_target - 1 THEN
    v_charge_min := GREATEST(8, round(COALESCE(
      public.ottoq_estimate_charge_minutes(v_soc, v_visit_target, 150, COALESCE(v_inlet_kw,150),
                                    COALESCE(v_cap,75), 25, COALESCE(v_soh,95),
                                    GREATEST(0.2, COALESCE((p_obs->>'charge_rate_mult')::numeric, 1.0)
                                                  / GREATEST(0.2, COALESCE(v_curve,1.0)))), 25)))::int;
  END IF;

  -- ===== ATOMS =====
  IF v_soc < v_visit_target - 1 THEN
    v_m := v_m || jsonb_build_object('svc','charge','must_do',true,'deferrable',false,
      'target_soc',v_visit_target,'est_min',v_charge_min,'concurrency','anchor');
  END IF;
  v_m := v_m || jsonb_build_object('svc','readiness_check','must_do',true,'deferrable',false,
      'est_min',3,'concurrency','gate','predecessors',jsonb_build_array('*'));
  v_night_start := COALESCE((v_plan->>'night_start_hour')::int, 20);
  v_night_end   := COALESCE((v_plan->>'night_end_hour')::int, 6);
  v_is_night    := (v_hour >= v_night_start OR v_hour < v_night_end);

  IF COALESCE((p_obs->>'interior_inspection')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','interior_inspection','must_do',true,'deferrable',false,
      'est_min', COALESCE((p_obs->>'interior_inspection_min')::int, 3),
      'concurrency','cabin','at_charge_stall',true);
  END IF;

  IF COALESCE((p_obs->>'interior_tidy')::boolean, false) THEN
    v_conf := COALESCE((p_obs->>'interior_tidy_confidence')::numeric, 1.0);
    v_m := v_m || jsonb_build_object('svc','interior_tidy','must_do',true,'deferrable',false,
      'est_min', COALESCE((p_obs->>'interior_tidy_min')::int, 4),
      'concurrency','cabin','confidence',v_conf,
      'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi);
  END IF;
  IF COALESCE((p_obs->>'item_retrieval')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','item_retrieval','must_do',true,'deferrable',false,
      'est_min',4,'concurrency','cabin','confidence',1.0,'confirm_required',false);
  END IF;
  IF COALESCE((p_obs->>'sensor_clean')::boolean, false) THEN
    v_conf := COALESCE((p_obs->>'sensor_clean_confidence')::numeric, 1.0);
    v_m := v_m || jsonb_build_object('svc','sensor_clean','must_do',true,'deferrable',false,
      'est_min',5,'concurrency','exterior','confidence',v_conf,
      'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi);
  END IF;
  IF COALESCE((p_obs->>'remote_diagnostics')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','remote_diagnostics','must_do',true,'deferrable',true,
      'est_min',5,'concurrency','digital');
  END IF;
  v_ota := COALESCE((p_obs->>'ota_pending')::boolean, false);
  IF v_ota THEN
    v_m := v_m || jsonb_build_object('svc','software_update','must_do',true,'deferrable',true,
      'est_min', COALESCE((p_obs->>'ota_min')::int, 30),
      'concurrency','digital','blocks_dispatch_while_running',true);
  END IF;
  -- 0695: data offload, the robotaxi catalog's (CLAUDE.md 2.4). The car's logged data comes off over a wired uplink at
  -- a charger or a service bay, sized by the hours of driving the observation says it carries (1 TB an hour kept, 10
  -- Gbps per uplink: docs/DATA_OFFLOAD.md), between 10 and 40 minutes. Raised on a visit that charges, so the car
  -- stands on a charger anyway; a visit with no charge leaves the hours for the next one.
  IF COALESCE((p_obs->>'data_offload_hours')::numeric, 0) > 0 AND v_soc < v_visit_target - 1 THEN
    v_m := v_m || jsonb_build_object('svc','data_offload','must_do',true,'deferrable',false,
      'est_min', GREATEST(10, LEAST(40, ceil((p_obs->>'data_offload_hours')::numeric * 60.0 / 4.5)))::int,
      'concurrency','digital','needs_uplink',true,
      'hours_out', round((p_obs->>'data_offload_hours')::numeric, 2));
  END IF;
  -- a soiled/biohazard cabin is must-clean on THIS arrival (state), else the observed cadence draw (deferrable)
  v_deep_clean_due := COALESCE(v_cabin_cond IN ('soiled','biohazard'), false);
  IF v_deep_clean_due OR COALESCE((p_obs->>'deep_clean_drawn')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','interior_deep_clean',
      'must_do', true, 'deferrable', NOT v_deep_clean_due,
      'est_min',v_deep_min,'concurrency','bay','requires_bay','detail','carryover_eligible',true);
  END IF;

  -- exterior wash: hours-clock overdue (0082/0085), night rotation, soil override, cycles backstop. No draw.
  v_wash_ratio := CASE WHEN v_last_wash IS NULL OR COALESCE(v_wash_int,0) <= 0
                       THEN NULL
                       ELSE EXTRACT(EPOCH FROM (v_clock - v_last_wash)) / 3600.0 / v_wash_int END;
  v_wash_overdue := COALESCE(v_wash_ratio, 0) >= COALESCE(
                      (SELECT c.overdue_ratio FROM public.service_cadence_policy c
                        WHERE c.svc = 'exterior_wash' AND c.is_active), 1.25);
  IF (v_is_night
       AND COALESCE((SELECT (config->>'wash_group')::int FROM public.vehicles WHERE id = p_vehicle_id),
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3)) = (v_sim_day % 3))
     OR v_soil >= COALESCE((v_plan->>'wash_soil_override')::numeric, 0.75)
     OR v_cycles >= COALESCE((v_plan->>'wash_backstop_cycles')::int, 9)
     OR v_wash_overdue THEN
    v_m := v_m || jsonb_build_object('svc','exterior_wash',
      'must_do', true, 'deferrable', NOT v_wash_overdue,
      'est_min',v_wash_min,'concurrency','bay','requires_bay','wash_bay','carryover_eligible',true);
  END IF;

  -- rider-flagged cleaning (0018/0019/0020): read the lifecycle, shape the atom, consume after the row exists
  IF v_run IS NOT NULL THEN
    SELECT f.flag_id, f.flag_kind, f.status, f.recalled_visit_key, f.recalled_visit_id
      INTO v_rf_id, v_rf_kind, v_rf_status, v_rf_visit, v_rf_prev_visit_id
      FROM public.ottoq_rider_cleaning_flags f
     WHERE f.sim_run_id = v_run AND f.vehicle_id = p_vehicle_id
       AND f.status IN ('pending','recalled')
       AND f.raised_at_sim_clock <= v_clock;

    IF v_rf_id IS NOT NULL THEN
      IF v_rf_kind = 'exterior' THEN
        v_rf_svc := 'exterior_wash'; v_rf_min := v_wash_min;
      ELSE
        v_rf_svc := 'interior_deep_clean'; v_rf_min := v_deep_min;
      END IF;

      SELECT n.visit_id INTO v_this_visit_id
        FROM public.ottoq_visit_needs n
       WHERE n.vehicle_id = p_vehicle_id
         AND n.visit_key  = v_visit
         AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
           = COALESCE(v_run,        '00000000-0000-0000-0000-000000000000'::uuid);

      IF v_rf_status = 'recalled'
         AND v_rf_prev_visit_id IS NOT NULL
         AND v_rf_prev_visit_id IS DISTINCT FROM v_this_visit_id THEN
        v_rf_retire := true;
        v_rf_status := 'served';
      ELSE
        v_rf_place  := true;
        v_rf_status := 'recalled';
      END IF;
    END IF;

    IF v_rf_place THEN
      IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_rf_svc) THEN
        SELECT jsonb_agg(CASE WHEN a->>'svc' = v_rf_svc
                              THEN a || jsonb_build_object('must_do', true, 'deferrable', false,
                                     'carryover_eligible', false,
                                     'rider_flagged', true,
                                     'rider_flag_kind', COALESCE(v_rf_kind,'interior'),
                                     'return_trigger', 'rider_flag_cleaning')
                              ELSE a END)
          INTO v_m FROM jsonb_array_elements(v_m) a;
      ELSE
        v_m := v_m || jsonb_build_object(
          'svc', v_rf_svc, 'must_do', true, 'deferrable', false,
          'est_min', v_rf_min, 'concurrency', 'bay',
          'requires_bay', CASE WHEN v_rf_svc = 'exterior_wash' THEN 'wash_bay' ELSE 'detail' END,
          'carryover_eligible', false,
          'rider_flagged', true,
          'rider_flag_kind', COALESCE(v_rf_kind,'interior'),
          'return_trigger', 'rider_flag_cleaning',
          'why', 'Rider-reported ' || COALESCE(v_rf_kind,'interior')
                 || ' cleanliness issue; vehicle was recalled for this.');
      END IF;
    END IF;
  END IF;

  IF v_is_night AND COALESCE((p_obs->>'perimeter_walkaround')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','perimeter_walkaround','must_do',true,'deferrable',false,
      'est_min', COALESCE((p_obs->>'perimeter_walkaround_min')::int, 12),
      'concurrency','exterior','at_perimeter',true);
  END IF;
  IF COALESCE((p_obs->>'sensor_calibration')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','sensor_calibration','must_do',true,'deferrable',true,
      'est_min',v_calib_min,'slot','dedicated_service','concurrency','bay','requires_bay','service_bay',
      'predecessors',jsonb_build_array('exterior_wash'),'carryover_eligible',true);
  END IF;
  IF COALESCE((p_obs->>'mechanical_pm')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','mechanical_pm','must_do',true,'deferrable',true,
      'est_min',v_pm_min,'concurrency','bay','requires_bay','service_bay','carryover_eligible',true);
  END IF;
  /* 0448 (G181): a vehicle recalled because its interval maintenance was hard-overdue gets that maintenance on
     this visit -- the recall's service bundle (CLAUDE.md 2.7), exactly as 0018/0019 made a rider-flag
     recall's cleaning must_do. Only interval_scheduled_v1 emits this trigger; naive_threshold_v1 never does. */
  IF (SELECT d.return_trigger FROM public.ottoq_vehicle_dispatches d
       WHERE d.vehicle_id = p_vehicle_id AND d.sim_run_id = v_run
       ORDER BY d.dispatched_at DESC, d.dispatch_id LIMIT 1) = 'service_interval_overdue'
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' IN ('mechanical_pm','sensor_calibration')) THEN
    SELECT jsonb_agg(CASE WHEN a->>'svc' IN ('mechanical_pm','sensor_calibration')
                          THEN a || jsonb_build_object('must_do', true, 'deferrable', false,
                                 'carryover_eligible', false, 'return_trigger', 'service_interval_overdue')
                          ELSE a END ORDER BY o)
      INTO v_m FROM jsonb_array_elements(v_m) WITH ORDINALITY AS t(a, o);
  END IF;
  IF COALESCE((p_obs->>'cosmetic_repair')::boolean, false) THEN
    v_conf := COALESCE((p_obs->>'cosmetic_confidence')::numeric, 1.0);
    v_m := v_m || jsonb_build_object('svc','cosmetic_repair','must_do',true,'deferrable',true,
      'est_min',60,'disposition','offline_candidate','concurrency','bay','requires_bay','service_bay',
      'confidence',v_conf,'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi,
      'carryover_eligible',true);
  END IF;
  IF v_fault THEN
    v_m := v_m || jsonb_build_object('svc','fault_repair','must_do',true,'deferrable',false,
      'est_min', COALESCE((p_obs->>'fault_repair_min')::int, 60),
      'concurrency','bay','requires_bay','service_bay','requires_tech_greenlight',true);
  END IF;

  -- ===== CARRYOVER (0193 scope: the caller's run id, verbatim; see header, RECORDED) =====
  SELECT visit_id, atoms INTO v_carry_visit, v_carry
    FROM public.ottoq_visit_needs
   WHERE vehicle_id = p_vehicle_id AND status = 'carried_over' AND COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
   ORDER BY created_at DESC LIMIT 1;
  IF v_carry IS NOT NULL THEN
    FOR v_atom IN SELECT * FROM jsonb_array_elements(v_carry) LOOP
      IF COALESCE((v_atom->>'carryover_eligible')::boolean, false)
         AND NOT COALESCE((v_atom->>'done')::boolean, false)
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_atom->>'svc') THEN
        v_m := v_m || (v_atom || jsonb_build_object('carried',true));
      END IF;
    END LOOP;
    UPDATE public.ottoq_visit_needs SET status = 'complete',
           meta = COALESCE(meta,'{}'::jsonb) || jsonb_build_object('carryover_consumed_by', v_visit)
     WHERE visit_id = v_carry_visit;
  END IF;

  -- 0698 (G413, CLAUDE.md rule 9): the supersede below closes every open visit of the car, and the new visit must not
  -- lose what they still owe. Every required atom an open or in-progress visit of the car on THIS run has not done or
  -- cancelled comes onto the new visit as it stood (carried, with the old visit's key), unless the new visit already
  -- has that service. Not the charge or the readiness check (set afresh here from the car as it is now), not an atom
  -- the guard tagged as not required (no executor: it would hold the car forever), not another run's. Ordered by the
  -- old visits' sim-clock arrival, then key, then atom order, so a pair's arms carry the same atoms the same way.
  FOR v_atom IN
    SELECT x.a || jsonb_build_object('carried', true, 'carried_from_visit', o.visit_key)
      FROM public.ottoq_visit_needs o
     CROSS JOIN LATERAL jsonb_array_elements(o.atoms) WITH ORDINALITY AS x(a, k)
     WHERE o.vehicle_id = p_vehicle_id AND o.status IN ('open','in_progress')
       AND COALESCE(o.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
       AND COALESCE((x.a->>'must_do')::boolean, false)
       AND COALESCE(x.a->>'status', 'pending') NOT IN ('done', 'cancelled')
       AND COALESCE(x.a->>'svc', '') NOT IN ('charge', 'readiness_check', '')
     ORDER BY o.arrived_at, o.visit_key, x.k
  LOOP
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_atom->>'svc') THEN
      v_m := v_m || v_atom;
    END IF;
  END LOOP;

  v_archetype := CASE
    WHEN v_fault THEN 'E_tech_hold_fault'
    WHEN v_rf_id IS NOT NULL AND v_rf_status = 'recalled' THEN 'R_rider_flag_cleaning'
    WHEN v_ota THEN 'J_ota_wave'
    WHEN v_urgency = 'overnight_hold' THEN 'C_overnight'
    WHEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'charge') THEN 'M_pass_through_or_P_triage'
    WHEN v_urgency = 'immediate_dispatch'
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'interior_tidy') THEN 'A_charge_clean_go'
    WHEN v_urgency = 'immediate_dispatch' THEN 'D_charge_and_go'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'mechanical_pm') THEN 'B_full_service'
    ELSE 'std_mixed' END;

  -- ===== THE LEDGER ROW (unscoped supersede verbatim; see header, RECORDED) =====
  UPDATE public.ottoq_visit_needs SET status = 'superseded'
   WHERE vehicle_id = p_vehicle_id AND status IN ('open','in_progress');
  INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key,
                                 archetype, urgency, dispatch_due_at, target_soc, atoms, meta)
  VALUES (p_vehicle_id, v_run, v_depot, v_clock, v_visit,
          v_archetype, v_urgency, v_due, v_visit_target, ottoq.ottoq_atoms_guard(v_m),
          jsonb_build_object('plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
                             'crn', v_run IS NOT NULL, 'precip_stress', round(v_precip_stress,3),
                             'wet_boost', round(v_boost,3), 'soc_at_arrival', v_soc,
                             'sla_floor', v_sla_floor, 'generator', v_generator,
                             'rider_flagged', (v_rf_id IS NOT NULL AND v_rf_status = 'recalled'),
                             'rider_flag_kind', v_rf_kind,
                             'observer', v_observer))
  ON CONFLICT (vehicle_id, visit_key, (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  DO UPDATE
    SET atoms = EXCLUDED.atoms, urgency = EXCLUDED.urgency, archetype = EXCLUDED.archetype,
        dispatch_due_at = EXCLUDED.dispatch_due_at, target_soc = EXCLUDED.target_soc,
        meta = EXCLUDED.meta, status = 'open'
  RETURNING visit_id INTO v_visit_id;

  IF v_rf_id IS NOT NULL AND v_visit_id IS NOT NULL THEN
    IF v_rf_retire THEN
      UPDATE public.ottoq_rider_cleaning_flags
         SET status = 'served', served_at_sim_clock = COALESCE(served_at_sim_clock, v_clock)
       WHERE flag_id = v_rf_id;
    ELSIF v_rf_place THEN
      UPDATE public.ottoq_rider_cleaning_flags
         SET status                = 'recalled',
             recalled_at_sim_clock = COALESCE(recalled_at_sim_clock, v_clock),
             recalled_visit_key    = v_visit,
             recalled_visit_id     = v_visit_id
       WHERE flag_id = v_rf_id;
    END IF;
  END IF;

  UPDATE public.vehicles SET config = jsonb_set(
      jsonb_set(COALESCE(config,'{}'::jsonb), '{service_manifest}', v_m),
      '{service_manifest_meta}', jsonb_build_object(
        'visit', v_visit,
        'visit_id', v_visit_id,
        'plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
        'crn', v_run IS NOT NULL,
        'precip_stress', round(v_precip_stress, 3),
        'wet_boost', round(v_boost, 3),
        'urgency', v_urgency,
        'rider_flagged', (v_rf_id IS NOT NULL AND v_rf_status = 'recalled'),
        'generator', v_generator,
        'observer', v_observer))
   WHERE id = p_vehicle_id;
  RETURN v_m;
END;
$function$;
