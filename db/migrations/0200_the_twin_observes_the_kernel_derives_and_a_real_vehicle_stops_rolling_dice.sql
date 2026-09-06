-- =====================================================================
-- 0200  The twin observes, the kernel derives, and a real vehicle
--       stops rolling dice
-- =====================================================================
-- forces_recert = TRUE. One decide-path function body changes
-- (twin.ottoq_sim_generate_service_manifest) and four are new. The
-- prediction, written before round 20 exists: NO canon moves. The
-- migration proves it in advance on 160 live, rolled-back probes (A1):
-- old and new produce the same manifest, the same visit row, the same
-- variability cards and the same flag transitions, byte for byte.
--
-- THE FINDING (G3; trace segments INTAKE and NEED DERIVATION)
-- ---------------------------------------------------------------------
-- Every path that gives a vehicle a service manifest calls one function:
-- twin.ottoq_sim_generate_service_manifest, 30,331 chars, SECURITY
-- DEFINER, with a seed. Callers: twin.ottoq_sim_generate_arrival_manifests
-- (arrival), ottoq.ottoq_sim_prearrival_contracts (backstop),
-- ottoq.ottoq_book_appointment (any booking without an open need --
-- including the REAL-FEED return path, ottoq_ingest_vehicle_signal ->
-- ottoq.ottoq_decide_return_on_signal -> ottoq_book_appointment), and
-- twin.ottoq_sim_wash_triage (only when depots.feed_mode = 'sim').
--
-- Inside, "does this car need an interior tidy" is
--   ottoq_sim_seeded_random(seed, salt||':tidy') < 0.35 * (1+wet) * (0.6+1.6*soil)
-- and likewise for inspection, sensor clean, item retrieval, remote
-- diagnostics, the OTA wave, deep clean, walkaround, calibration, PM,
-- cosmetic repair, a fault, and the urgency intent
-- (immediate_dispatch / overnight_hold). Only the charge atom, the wash
-- gate, the cabin-condition deep clean and the rider flag are read from
-- state. A real vehicle arriving at a real depot would have its needs
-- DRAWN from the run seed. That is not a need-derivation path; it is a
-- demand generator wearing one's clothes.
--
-- THE SPLIT
-- ---------------------------------------------------------------------
--   observer   decides what is OBSERVED about the asset.
--              twin.ottoq_sim_observe_asset draws it (same seed, same
--              salts, same three ottoq_twin_deal cards in the same
--              order) -- the v4_condition model, unchanged in value.
--              ottoq.ottoq_observe_asset senses it from vehicle_need_
--              profile and ottoq_vehicle_wear: fault codes, cabin
--              condition, item pending, software target vs installed,
--              soil, PM and calibration due. No randomness, no seed.
--   kernel     ottoq.ottoq_derive_visit_needs decides what is NEEDED
--              given observations + asset state + policy, and writes
--              the visit row, consumes the rider flag, refreshes the
--              vehicle's manifest cache -- exactly the old body with
--              every draw replaced by an observation read. It never
--              references the twin schema; its search_path excludes it.
--   entry      ottoq.ottoq_generate_visit_needs(vehicle, run) is the
--              real-feed entry (no seed exists to pass).
--              twin.ottoq_sim_generate_service_manifest keeps its
--              signature so the four call sites are untouched, resolves
--              run/clock/seed as before, and switches on
--              depots.feed_mode: 'sim' -> twin observer, anything else
--              -> the kernel's real observer.
--
-- ottoq_sim_seeded_random is IMMUTABLE and salt-keyed, so moving the
-- draws out of line cannot change a value. ottoq_twin_deal WRITES a
-- card per (run, var_key, scope, bucket); the observer deals the same
-- three cards in the same order, so the card ledger is identical too
-- (A1 hashes it). Observations cross the boundary as jsonb; every value
-- is numeric/int/bool, and numeric -> jsonb -> numeric is exact.
--
-- WHAT THE REAL OBSERVER ASSUMES (labelled; each is a policy the
-- Recall Decision or a pack will own later):
--   ASSUMPTION G3-1  urgency intent for a real arrival is 'standard'
--                    (tech_hold on a fault). immediate_dispatch /
--                    overnight_hold are work-side signals and arrive via
--                    the Recall Decision (G6/G7), not here.
--   ASSUMPTION G3-2  worst_fault_severity in vehicle_need_profile uses
--                    the wear table's rank scale (0 critical, 1 major).
--   ASSUMPTION G3-3  interior inspection on every arrival; perimeter
--                    walkaround on every night arrival (the twin models
--                    these at 93-95% and 90%). Durations from the twin's
--                    nominal midpoints: inspection 3, tidy 4, walkaround
--                    12, fault repair 60, software update
--                    15 + size_mb/100 clipped to [15,45].
--   ASSUMPTION G3-4  sensor clean when soil >= sensor_soil_threshold
--                    (existing policy param) or sensor_health_pct < 90.
--
-- RECORDED, NOT FIXED (G13): the generator supersedes every open visit
-- for the vehicle regardless of run; the carryover lookup scopes on the
-- CALLER's run id (0193) while the visit row is written with the
-- RESOLVED run id, so a NULL-run caller (wash triage) can never consume
-- a carryover. Both are preserved verbatim here so the twin path stays
-- byte-identical; both are named so they can be closed on purpose.
-- =====================================================================

BEGIN;

CREATE TEMP TABLE pin_0200 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

-- ---------------------------------------------------------------------
-- 1. The old body, copied from the live catalog under a probe name.
--    SECURITY INVOKER (the only caller is this migration, as postgres) so
--    no new SECURITY DEFINER function exists even for a moment; dropped
--    after A1.
-- ---------------------------------------------------------------------
DO $copy$
DECLARE v_def text;
BEGIN
  -- The probe copy is taken from the LIVE catalog, not retyped: it is the
  -- body the engine ran round 19 on, to the byte. Its md5 is pinned to the
  -- value measured when this file was written (0cd6b895...), so a generator
  -- that changed since is refused rather than silently compared against.
  v_def := pg_get_functiondef('twin.ottoq_sim_generate_service_manifest(uuid,uuid,bigint)'::regprocedure);
  IF md5(v_def) <> '0cd6b895241d4f7898daaa44ae72fed4' THEN
    RAISE EXCEPTION '0200: the live generator body (md5 %) is not the one this migration was written against (0cd6b895...)', md5(v_def);
  END IF;
  IF v_def !~ 'SECURITY DEFINER' OR v_def !~ 'ottoq_sim_seeded_random' THEN
    RAISE EXCEPTION '0200: the live generator is not the seeded SECURITY DEFINER body this migration expects';
  END IF;
  v_def := replace(v_def, 'FUNCTION twin.ottoq_sim_generate_service_manifest(', 'FUNCTION twin.ottoq_sim_generate_service_manifest_pre0200(');
  v_def := replace(v_def, E'\n SECURITY DEFINER', '');
  IF v_def ~ 'SECURITY DEFINER' THEN
    RAISE EXCEPTION '0200: could not strip SECURITY DEFINER from the probe copy';
  END IF;
  EXECUTE v_def;
END $copy$;
COMMENT ON FUNCTION twin.ottoq_sim_generate_service_manifest_pre0200(uuid, uuid, bigint) IS
  '0200 probe copy of the pre-0200 generator body, taken from the live catalog (SECURITY INVOKER). Exists only for assertion A1 and is dropped at the end of 0200.';

-- ---------------------------------------------------------------------
-- 2. THE KERNEL: needs from observations + asset state + policy.
--    Every draw in the old body is now a read of p_obs. Nothing else
--    moved: same reads, same gates, same writes, same order. The
--    search_path has no twin schema on purpose.
--
--    p_sim_run_id  the run id AS THE CALLER PASSED IT (may be NULL);
--                  the 0193 carryover scope and the wear read use it.
--    p_run         the run RESOLVED by the entry (caller's, else the
--                  depot's running run); the visit row, the salt and the
--                  rider flag use it. Two parameters because the old
--                  body used both and byte-identity is the contract.
-- ---------------------------------------------------------------------
CREATE FUNCTION ottoq.ottoq_derive_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_clock timestamp with time zone, p_depot_id uuid, p_obs jsonb)
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
  SELECT current_soc, COALESCE(target_soc, public.ottoq_default_target_soc()), COALESCE((config->>'cycles_since_wash')::int,0),
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
  v_visit_target := CASE WHEN v_urgency = 'immediate_dispatch'
                         THEN GREATEST(v_sla_floor + 5, 70) ELSE v_target END;

  -- ===== DURATIONS: nominal x observed variability x the vehicle's service-speed scalar =====
  v_wash_min  := GREATEST(8, LEAST(10, round(9 * COALESCE((p_obs->>'deal_wash_time')::numeric, 1.0) * COALESCE(v_svcspd,1))))::int;
  v_deep_min  := GREATEST(12, round(20 * COALESCE((p_obs->>'deal_detail_time')::numeric, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_pm_min    := GREATEST(20, round(40 * COALESCE((p_obs->>'deal_maintenance_time')::numeric, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;
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
    v_m := v_m || jsonb_build_object('svc','remote_diagnostics','must_do',false,'deferrable',true,
      'est_min',5,'concurrency','digital');
  END IF;
  v_ota := COALESCE((p_obs->>'ota_pending')::boolean, false);
  IF v_ota THEN
    v_m := v_m || jsonb_build_object('svc','software_update','must_do',false,'deferrable',true,
      'est_min', COALESCE((p_obs->>'ota_min')::int, 30),
      'concurrency','digital','blocks_dispatch_while_running',true);
  END IF;
  -- a soiled/biohazard cabin is must-clean on THIS arrival (state), else the observed cadence draw (deferrable)
  v_deep_clean_due := COALESCE(v_cabin_cond IN ('soiled','biohazard'), false);
  IF v_deep_clean_due OR COALESCE((p_obs->>'deep_clean_drawn')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','interior_deep_clean',
      'must_do', v_deep_clean_due, 'deferrable', NOT v_deep_clean_due,
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
      'must_do', v_wash_overdue, 'deferrable', NOT v_wash_overdue,
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
      'concurrency','hold','at_perimeter',true);
  END IF;
  IF COALESCE((p_obs->>'sensor_calibration')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','sensor_calibration','must_do',false,'deferrable',true,
      'est_min',v_calib_min,'slot','dedicated_service','concurrency','bay','requires_bay','service_bay',
      'predecessors',jsonb_build_array('exterior_wash'),'carryover_eligible',true);
  END IF;
  IF COALESCE((p_obs->>'mechanical_pm')::boolean, false) THEN
    v_m := v_m || jsonb_build_object('svc','mechanical_pm','must_do',false,'deferrable',true,
      'est_min',v_pm_min,'concurrency','bay','requires_bay','service_bay','carryover_eligible',true);
  END IF;
  IF COALESCE((p_obs->>'cosmetic_repair')::boolean, false) THEN
    v_conf := COALESCE((p_obs->>'cosmetic_confidence')::numeric, 1.0);
    v_m := v_m || jsonb_build_object('svc','cosmetic_repair','must_do',false,'deferrable',true,
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
COMMENT ON FUNCTION ottoq.ottoq_derive_visit_needs(uuid, uuid, uuid, timestamptz, uuid, jsonb) IS
  '0200 KERNEL. Derives a visit''s service needs from observations (p_obs) + asset state + policy and writes the visit row. No randomness, no twin reference. p_sim_run_id = caller''s run (carryover/wear scope), p_run = resolved run (visit row, flags).';

-- ---------------------------------------------------------------------
-- 3. THE TWIN OBSERVER: the v4_condition model's draws, exactly as they
--    were, delivered as observations. Same seed, same salts, same three
--    ottoq_twin_deal cards in the same order.
-- ---------------------------------------------------------------------
CREATE FUNCTION twin.ottoq_sim_observe_asset(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_seed bigint, p_clock timestamp with time zone, p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_salt text; v_sim_day int; v_hour int; v_plan jsonb; v_probs jsonb;
  v_clamp_lo numeric := 0.005; v_clamp_hi numeric := 0.90; v_tail_scale numeric;
  v_precip_stress numeric := 0; v_boost numeric := 0;
  v_wear RECORD; v_soil numeric := 0; v_pm_int numeric; v_calib_int numeric;
  v_pm_prog numeric := 0; v_calib_prog numeric := 0;
  v_urg text; v_is_night boolean; v_night_start int; v_night_end int; v_insp_p numeric;
  v_deal_wash numeric; v_deal_detail numeric; v_deal_maint numeric; v_rate numeric;
BEGIN
  -- the 0055 salt: whole minutes since the run's own sim_clock_start; absolute clock when there is no run
  v_salt := p_vehicle_id::text || ':' ||
            COALESCE((SELECT GREATEST(0, floor(EXTRACT(EPOCH FROM (p_clock - r.sim_clock_start)) / 60.0))::text
                        FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run),
                     to_char(p_clock, 'YYYYMMDDHH24MISS'));
  v_sim_day := (p_clock::date - DATE '2020-01-01');
  v_hour    := EXTRACT(HOUR FROM (p_clock AT TIME ZONE 'America/Chicago'))::int;
  v_plan    := ottoq_feed_plan('service_manifest');

  SELECT (config->>'pm_interval_km')::numeric, (config->>'calib_interval_h')::numeric
    INTO v_pm_int, v_calib_int FROM vehicles WHERE id = p_vehicle_id;
  SELECT w.soil_index,
         w.drive_km_total    - COALESCE(w.km_at_last_pm,0)             AS km_since_pm,
         w.drive_hours_total - COALESCE(w.hours_at_last_calibration,0) AS h_since_calib
    INTO v_wear FROM ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND (p_sim_run_id IS NULL OR w.sim_run_id = p_sim_run_id)   -- the caller's scope, as the old body read it
   ORDER BY w.updated_at DESC LIMIT 1;
  v_soil := COALESCE(v_wear.soil_index, 0);

  IF p_run IS NOT NULL AND v_plan IS NOT NULL THEN
    v_precip_stress := COALESCE((ottoq_twin_climate_stress(p_run, v_sim_day)->>'precip_stress')::numeric, 0);
    v_boost := v_precip_stress * COALESCE((v_plan->>'precip_soil_coupling')::numeric, 0.6);
  END IF;

  v_probs := COALESCE(v_plan->'probabilities', jsonb_build_object(
    'interior_tidy',0.35,'sensor_clean',0.20,'interior_deep_clean',0.10,
    'exterior_wash',0.20,'sensor_calibration',0.04,'mechanical_pm',0.05,'cosmetic_repair',0.02));
  v_tail_scale := GREATEST(0, COALESCE((v_plan->>'long_tail_scale')::numeric, 0.5));
  v_probs := v_probs || jsonb_build_object(
    'sensor_clean',        COALESCE((v_probs->>'sensor_clean')::numeric,0.20)        * v_tail_scale,
    'interior_deep_clean', COALESCE((v_probs->>'interior_deep_clean')::numeric,0.10) * v_tail_scale,
    'sensor_calibration',  COALESCE((v_probs->>'sensor_calibration')::numeric,0.04)  * v_tail_scale,
    'mechanical_pm',       COALESCE((v_probs->>'mechanical_pm')::numeric,0.05)       * v_tail_scale,
    'cosmetic_repair',     COALESCE((v_probs->>'cosmetic_repair')::numeric,0.02)     * v_tail_scale);
  IF v_plan IS NOT NULL THEN
    v_clamp_lo := COALESCE((v_plan->'probability_clamp'->>0)::numeric, 0.005);
    v_clamp_hi := COALESCE((v_plan->'probability_clamp'->>1)::numeric, 0.90);
  END IF;

  IF v_hour >= 22 OR v_hour < 4 THEN
    v_urg := CASE WHEN ottoq_sim_seeded_random(p_seed, v_salt || ':urg')
                    < COALESCE((v_plan->>'overnight_hold_p_night')::numeric, 0.75)
             THEN 'overnight_hold' ELSE 'standard' END;
  ELSE
    v_urg := CASE WHEN ottoq_sim_seeded_random(p_seed, v_salt || ':urg')
                    < COALESCE((v_plan->>'immediate_dispatch_p_day')::numeric, 0.30)
             THEN 'immediate_dispatch' ELSE 'standard' END;
  END IF;

  v_pm_prog    := CASE WHEN COALESCE(v_pm_int,0)    > 0 THEN COALESCE(v_wear.km_since_pm,0)   / v_pm_int    ELSE 0 END;
  v_calib_prog := CASE WHEN COALESCE(v_calib_int,0) > 0 THEN COALESCE(v_wear.h_since_calib,0) / v_calib_int ELSE 0 END;

  -- the three cards, dealt in the order the old body dealt them (each call may write a card row)
  v_deal_wash   := CASE WHEN p_run IS NOT NULL THEN ottoq_twin_deal(p_run,'wash_time',        v_salt, p_clock, v_sim_day, 0, 'global') END;
  v_deal_detail := CASE WHEN p_run IS NOT NULL THEN ottoq_twin_deal(p_run,'detail_time',      v_salt, p_clock, v_sim_day, 0, 'global') END;
  v_deal_maint  := CASE WHEN p_run IS NOT NULL THEN ottoq_twin_deal(p_run,'maintenance_time', v_salt, p_clock, v_sim_day, 0, 'global') END;
  v_rate        := CASE WHEN p_run IS NULL THEN 1.0 ELSE ottoq_profile_rate_mult(p_run,'charge_time') END;

  v_night_start := COALESCE((v_plan->>'night_start_hour')::int, 20);
  v_night_end   := COALESCE((v_plan->>'night_end_hour')::int, 6);
  v_is_night    := (v_hour >= v_night_start OR v_hour < v_night_end);
  v_insp_p := CASE WHEN v_is_night
                   THEN COALESCE((v_plan->>'night_interior_inspection_p')::numeric, 0.95)
                   ELSE COALESCE((v_plan->>'day_interior_inspection_p')::numeric, 0.93) END;

  RETURN jsonb_build_object(
    'observer', 'twin.ottoq_sim_observe_asset', 'generator', 'v4_condition',
    'precip_stress', v_precip_stress, 'wet_boost', v_boost,
    'fault', ottoq_sim_seeded_random(p_seed, v_salt || ':fault') < COALESCE((v_plan->>'fault_repair_p')::numeric, 0.02),
    'urgency_intent', v_urg,
    'interior_inspection', ottoq_sim_seeded_random(p_seed, v_salt || ':insp') < v_insp_p,
    'interior_inspection_min', (3 + round(2 * ottoq_sim_seeded_random(p_seed, v_salt || ':inspmin')))::int,
    'interior_tidy', ottoq_sim_seeded_random(p_seed, v_salt || ':tidy')
                     < LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'interior_tidy')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil))),
    'interior_tidy_confidence', round((0.30 + 0.70 * ottoq_sim_seeded_random(p_seed, v_salt || ':tidyconf'))::numeric, 2),
    'interior_tidy_min', (3 + round(2 * ottoq_sim_seeded_random(p_seed, v_salt || ':tidymin')))::int,
    'item_retrieval', ottoq_sim_seeded_random(p_seed, v_salt || ':item') < COALESCE((v_plan->>'item_retrieval_p')::numeric, 0.06),
    'sensor_clean', ottoq_sim_seeded_random(p_seed, v_salt || ':sclean')
                    < LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'sensor_clean')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil))),
    'sensor_clean_confidence', round((0.30 + 0.70 * ottoq_sim_seeded_random(p_seed, v_salt || ':scleanconf'))::numeric, 2),
    'remote_diagnostics', ottoq_sim_seeded_random(p_seed, v_salt || ':diag') < COALESCE((v_plan->>'remote_diagnostics_p')::numeric, 0.05),
    'ota_pending', ottoq_sim_seeded_random(p_seed, 'ota_wave:' || v_sim_day::text) < COALESCE((v_plan->>'ota_wave_daily_p')::numeric, 0.08),
    'ota_min', 15 + floor(ottoq_sim_seeded_random(p_seed, v_salt || ':otamin') * 30)::int,
    'deep_clean_drawn', ottoq_sim_seeded_random(p_seed, v_salt || ':deep')
                        < LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'interior_deep_clean')::numeric * (1 + v_boost * 0.5))),
    'perimeter_walkaround', ottoq_sim_seeded_random(p_seed, v_salt || ':walkaround') < COALESCE((v_plan->>'night_walkaround_p')::numeric, 0.90),
    'perimeter_walkaround_min', (10 + round(5 * ottoq_sim_seeded_random(p_seed, v_salt || ':walkmin')))::int,
    'sensor_calibration', ottoq_sim_seeded_random(p_seed, v_salt || ':calib') < LEAST(0.95, (v_probs->>'sensor_calibration')::numeric
                          * CASE WHEN v_calib_prog >= 1.0 THEN 12 WHEN v_calib_prog >= 0.8 THEN 4 ELSE 0.5 END),
    'mechanical_pm', ottoq_sim_seeded_random(p_seed, v_salt || ':pm') < LEAST(0.95, (v_probs->>'mechanical_pm')::numeric
                     * CASE WHEN v_pm_prog >= 1.0 THEN 12 WHEN v_pm_prog >= 0.8 THEN 4 ELSE 0.5 END),
    'cosmetic_repair', ottoq_sim_seeded_random(p_seed, v_salt || ':cosmetic') < (v_probs->>'cosmetic_repair')::numeric,
    'cosmetic_confidence', round((0.30 + 0.70 * ottoq_sim_seeded_random(p_seed, v_salt || ':cosconf'))::numeric, 2),
    'fault_repair_min', 30 + floor(ottoq_sim_seeded_random(p_seed, v_salt || ':faultmin') * 90)::int,
    'deal_wash_time', v_deal_wash, 'deal_detail_time', v_deal_detail, 'deal_maintenance_time', v_deal_maint,
    'charge_rate_mult', v_rate);
END;
$function$;
COMMENT ON FUNCTION twin.ottoq_sim_observe_asset(uuid, uuid, uuid, bigint, timestamptz, uuid) IS
  '0200 TWIN OBSERVER. The v4_condition model''s seeded draws (same seed, same salts, same twin_deal cards in the same order) delivered as observations for ottoq.ottoq_derive_visit_needs.';

-- ---------------------------------------------------------------------
-- 4. THE REAL OBSERVER: what the asset profile and wear ledger say.
--    No seed, no draw. Assumptions G3-1..4 in the header.
-- ---------------------------------------------------------------------
CREATE FUNCTION ottoq.ottoq_observe_asset(p_vehicle_id uuid, p_run uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_p RECORD; v_w RECORD; v_cfg jsonb;
  v_pm_int numeric; v_calib_int numeric;
  v_km_since_pm numeric; v_h_since_calib numeric;
  v_soil numeric; v_sensor_soil numeric; v_sensor_health_floor numeric;
  v_fault boolean; v_ota boolean; v_ota_min int;
BEGIN
  SELECT * INTO v_p FROM public.vehicle_need_profile WHERE vehicle_id = p_vehicle_id;
  SELECT w.soil_index, w.worst_open_dtc_rank, w.open_dtc_count,
         w.drive_km_total    - COALESCE(w.km_at_last_pm,0)             AS km_since_pm,
         w.drive_hours_total - COALESCE(w.hours_at_last_calibration,0) AS h_since_calib
    INTO v_w FROM public.ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND (p_run IS NULL OR w.sim_run_id = p_run)
   ORDER BY w.updated_at DESC LIMIT 1;
  SELECT config INTO v_cfg FROM public.vehicles WHERE id = p_vehicle_id;

  v_pm_int    := COALESCE((v_cfg->>'pm_interval_km')::numeric,  v_p.pm_interval_km);
  v_calib_int := COALESCE((v_cfg->>'calib_interval_h')::numeric, v_p.calib_interval_h);

  -- wear ledger first (run-scoped, twin-maintained); the asset profile when there is none
  v_soil          := COALESCE(v_w.soil_index, v_p.exterior_soil_level);
  v_km_since_pm   := COALESCE(v_w.km_since_pm,
                              CASE WHEN v_p.odometer_km IS NOT NULL THEN v_p.odometer_km - COALESCE(v_p.km_at_last_pm, 0) END);
  v_h_since_calib := COALESCE(v_w.h_since_calib,
                              CASE WHEN v_p.last_calibration_at IS NOT NULL THEN EXTRACT(EPOCH FROM (p_clock - v_p.last_calibration_at)) / 3600.0 END);

  v_sensor_soil         := public.ottoq_policy_get(p_run, 'sensor_soil_threshold', 0.35);
  v_sensor_health_floor := public.ottoq_policy_get(p_run, 'sensor_health_clean_pct', 90);

  -- ASSUMPTION G3-2: fault = a wear DTC of rank <= 1, any open fault code, or profile severity <= 1
  v_fault := COALESCE(v_w.worst_open_dtc_rank, 99) <= 1
          OR COALESCE(array_length(v_p.open_fault_codes, 1), 0) > 0
          OR COALESCE(v_p.worst_fault_severity, 99) <= 1;
  v_ota := v_p.sw_target_version IS NOT NULL AND v_p.sw_target_version IS DISTINCT FROM v_p.software_version;
  v_ota_min := LEAST(45, GREATEST(15, 15 + COALESCE(v_p.sw_update_size_mb, 0) / 100))::int;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'observer', 'ottoq.ottoq_observe_asset', 'generator', 'v5_state',
    'soil_index', v_soil, 'km_since_pm', v_km_since_pm, 'h_since_calib', v_h_since_calib,
    'fault', v_fault,
    'urgency_intent', NULL,                                  -- ASSUMPTION G3-1: standard until the Recall Decision says otherwise
    'interior_inspection', true, 'interior_inspection_min', 3, -- ASSUMPTION G3-3
    'interior_tidy', COALESCE(v_p.cabin_condition = 'light_litter', false),
    'interior_tidy_confidence', 1.0, 'interior_tidy_min', 4,
    'item_retrieval', COALESCE(v_p.item_retrieval_pending, false),
    'sensor_clean', COALESCE(v_soil, 0) >= v_sensor_soil OR COALESCE(v_p.sensor_health_pct, 100) < v_sensor_health_floor,  -- ASSUMPTION G3-4
    'sensor_clean_confidence', 1.0,
    'remote_diagnostics', false,
    'ota_pending', v_ota, 'ota_min', v_ota_min,
    'deep_clean_drawn', false,                              -- a soiled/biohazard cabin is state; the kernel reads it directly
    'perimeter_walkaround', true, 'perimeter_walkaround_min', 12,  -- ASSUMPTION G3-3 (the kernel gates it to night)
    'sensor_calibration', COALESCE(v_calib_int, 0) > 0 AND COALESCE(v_h_since_calib, 0) >= v_calib_int,
    'mechanical_pm',      COALESCE(v_pm_int, 0)    > 0 AND COALESCE(v_km_since_pm, 0)   >= v_pm_int,
    'cosmetic_repair', false,
    'fault_repair_min', 60,
    'charge_rate_mult', 1.0));
END;
$function$;
COMMENT ON FUNCTION ottoq.ottoq_observe_asset(uuid, uuid, timestamptz) IS
  '0200 REAL OBSERVER. Observations from vehicle_need_profile and ottoq_vehicle_wear: fault codes, cabin condition, item pending, software target vs installed, soil, PM and calibration due. No seed, no draw. Assumptions G3-1..4 recorded in migration 0200.';

-- ---------------------------------------------------------------------
-- 5. THE KERNEL ENTRY for a real feed: no seed exists to pass.
-- ---------------------------------------------------------------------
CREATE FUNCTION ottoq.ottoq_generate_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc numeric; v_depot uuid; v_clock timestamptz; v_run uuid;
BEGIN
  SELECT current_soc, home_depot_id, COALESCE(last_state_change, now())
    INTO v_soc, v_depot, v_clock FROM public.vehicles WHERE id = p_vehicle_id;
  IF v_soc IS NULL THEN RETURN NULL; END IF;
  v_run := COALESCE(p_sim_run_id,
    (SELECT sim_run_id FROM public.ottoq_sim_runs r
      WHERE r.status = 'running' AND r.depot_id = v_depot
      ORDER BY started_at DESC LIMIT 1));
  RETURN ottoq.ottoq_derive_visit_needs(p_vehicle_id, p_sim_run_id, v_run, v_clock, v_depot,
                                        ottoq.ottoq_observe_asset(p_vehicle_id, v_run, v_clock));
END;
$function$;
COMMENT ON FUNCTION ottoq.ottoq_generate_visit_needs(uuid, uuid) IS
  '0200 KERNEL ENTRY. Real-feed need derivation: observe the asset, derive the visit. The twin reaches the same kernel through twin.ottoq_sim_generate_service_manifest.';

-- ---------------------------------------------------------------------
-- 6. THE TWIN WRAPPER. Same signature, same resolution of run / clock /
--    seed, one switch on the depot's feed mode. The four call sites do
--    not change.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION twin.ottoq_sim_generate_service_manifest(p_vehicle_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid, p_seed bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc numeric; v_depot uuid; v_clock timestamptz; v_run uuid; v_seed bigint; v_obs jsonb;
BEGIN
  /* 0200: this function used to BE the need generator -- a seeded model of what a
     simulated car needs, called for every car including a real one. It is now the
     twin's door to the kernel: it resolves what the old body resolved, asks the
     observer that matches the depot's feed mode what it sees, and lets
     ottoq.ottoq_derive_visit_needs decide what is needed. */
  SELECT current_soc, home_depot_id, COALESCE(last_state_change, now())
    INTO v_soc, v_depot, v_clock FROM vehicles WHERE id = p_vehicle_id;
  IF v_soc IS NULL THEN RETURN NULL; END IF;

  v_run := COALESCE(p_sim_run_id,
    (SELECT sim_run_id FROM ottoq_sim_runs r
      WHERE r.status = 'running' AND r.depot_id = v_depot
      ORDER BY started_at DESC LIMIT 1));

  IF p_seed IS NOT NULL THEN
    v_seed := p_seed;
  ELSIF v_run IS NOT NULL THEN
    SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = v_run;
  ELSE
    v_seed := abs(hashtextextended(p_vehicle_id::text || 'manifest', 13));
  END IF;

  IF COALESCE((SELECT d.feed_mode FROM depots d WHERE d.id = v_depot), 'sim') = 'sim' THEN
    v_obs := twin.ottoq_sim_observe_asset(p_vehicle_id, p_sim_run_id, v_run, v_seed, v_clock, v_depot);
  ELSE
    v_obs := ottoq.ottoq_observe_asset(p_vehicle_id, v_run, v_clock);
  END IF;

  RETURN ottoq.ottoq_derive_visit_needs(p_vehicle_id, p_sim_run_id, v_run, v_clock, v_depot, v_obs);
END;
$function$;
COMMENT ON FUNCTION twin.ottoq_sim_generate_service_manifest(uuid, uuid, bigint) IS
  '0200: the twin''s door to ottoq.ottoq_derive_visit_needs. Resolves run/clock/seed as before; feed_mode ''sim'' -> twin.ottoq_sim_observe_asset (seeded v4_condition draws), else ottoq.ottoq_observe_asset (sensed state).';

-- =====================================================================
-- ASSERTIONS
-- =====================================================================
DO $assert$
DECLARE
  v_changed text[]; v_new text[]; v_n int; v_names text; v_src text;
  v_run uuid; v_veh uuid; v_seed bigint; v_clk timestamptz;
  v_old jsonb; v_new_j jsonb; v_probes int := 0; v_mism int := 0; v_first_mism text;
  v_atoms int := 0; v_flagged int := 0; v_carried int := 0; v_fault int := 0;
  v_ext uuid := 'e2000000-0000-4000-8000-0000000000d2';
  v_m1 jsonb; v_m2 jsonb; v_m3 jsonb; v_row jsonb; v_svcs text[];
BEGIN
  -- ── A0. THE PIN. One decide-path body changed; four kernel/observer bodies new; the
  --     probe copy present for now (dropped below, re-pinned in A5).
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0200 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h;
  IF v_changed IS DISTINCT FROM ARRAY['twin.ottoq_sim_generate_service_manifest(p_vehicle_id uuid, p_sim_run_id uuid, p_seed bigint)'] THEN
    RAISE EXCEPTION '0200 A0 FAILED: function bodies changed = % -- only the generator may change', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0200 a USING (sig)
   WHERE a.sig IS NULL;
  IF v_new IS DISTINCT FROM ARRAY[
       'ottoq.ottoq_derive_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_clock timestamp with time zone, p_depot_id uuid, p_obs jsonb)',
       'ottoq.ottoq_generate_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid)',
       'ottoq.ottoq_observe_asset(p_vehicle_id uuid, p_run uuid, p_clock timestamp with time zone)',
       'twin.ottoq_sim_generate_service_manifest_pre0200(p_vehicle_id uuid, p_sim_run_id uuid, p_seed bigint)',
       'twin.ottoq_sim_observe_asset(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_seed bigint, p_clock timestamp with time zone, p_depot_id uuid)'] THEN
    RAISE EXCEPTION '0200 A0 FAILED: new functions = %', v_new;
  END IF;
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('ottoq','twin') AND p.prosecdef
     AND p.proname IN ('ottoq_derive_visit_needs','ottoq_generate_visit_needs','ottoq_observe_asset','ottoq_sim_observe_asset','ottoq_sim_generate_service_manifest_pre0200');
  IF v_n <> 0 THEN RAISE EXCEPTION '0200 A0 FAILED: % new function(s) are SECURITY DEFINER; none may be (0198 posture)', v_n; END IF;
  RAISE NOTICE '0200 A0: one body changed (the generator), four new plus the probe copy, none SECURITY DEFINER';

  -- ── A1. EQUIVALENCE, LIVE AND ROLLED BACK. 40 flagship vehicles x 2 seeds x day/night
  --     = 160 probes. Old body vs new path on the same run, same vehicle, same clock:
  --     manifest, visit row, vehicle manifest cache, variability cards and rider flags
  --     must be byte-identical (visit_id / new keys excluded). Every probe rolls back.
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'completed'
   ORDER BY started_at DESC, sim_run_id DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION '0200 A1 FIXTURE: no completed flagship run'; END IF;
  IF (SELECT count(*) FROM public.ottoq_vehicle_wear WHERE sim_run_id = v_run) < 100 THEN
    RAISE EXCEPTION '0200 A1 FIXTURE: run % has too few wear rows to be a fair probe', v_run;
  END IF;

  FOR v_veh IN SELECT id FROM public.vehicles
                WHERE home_depot_id = '11111111-1111-1111-1111-111111111111' AND category = 'autonomous'
                ORDER BY id LIMIT 40 LOOP
    FOREACH v_seed IN ARRAY ARRAY[424242::bigint, 171717::bigint] LOOP
      FOREACH v_clk IN ARRAY ARRAY['2026-09-01 20:00:00+00'::timestamptz, '2026-09-02 04:30:00+00'::timestamptz] LOOP
        -- OLD
        BEGIN
          UPDATE public.vehicles SET last_state_change = v_clk WHERE id = v_veh;
          v_old := jsonb_build_object(
            'm', twin.ottoq_sim_generate_service_manifest_pre0200(v_veh, v_run, v_seed));
          v_old := v_old || jsonb_build_object(
            'row', (SELECT (to_jsonb(n) - 'visit_id' - 'created_at') #- '{meta,observer}' FROM public.ottoq_visit_needs n
                     WHERE n.vehicle_id = v_veh AND n.sim_run_id = v_run AND n.status = 'open'),
            'cfg', (SELECT config->'service_manifest' FROM public.vehicles WHERE id = v_veh),
            'cfgmeta', (SELECT (config->'service_manifest_meta') - 'observer' - 'visit_id' FROM public.vehicles WHERE id = v_veh),
            'cards', (SELECT md5(COALESCE(string_agg(var_key||'|'||scope_instance||'|'||bucket_key||'|'||value::text||'|'||active::text, E'\n'
                                  ORDER BY var_key, scope_instance, bucket_key, value::text, active::text), ''))
                        FROM public.ottoq_variability_cards WHERE sim_run_id = v_run),
            'flags', (SELECT COALESCE(jsonb_agg(to_jsonb(f) - 'recalled_visit_id' ORDER BY f.flag_id), '[]'::jsonb)
                        FROM public.ottoq_rider_cleaning_flags f WHERE f.sim_run_id = v_run AND f.vehicle_id = v_veh),
            'complete_n', (SELECT count(*) FROM public.ottoq_visit_needs WHERE vehicle_id = v_veh AND status = 'complete'));
          RAISE EXCEPTION USING ERRCODE = 'P0200', MESSAGE = v_old::text;
        EXCEPTION WHEN SQLSTATE 'P0200' THEN v_old := SQLERRM::jsonb;
        END;
        -- NEW
        BEGIN
          UPDATE public.vehicles SET last_state_change = v_clk WHERE id = v_veh;
          v_new_j := jsonb_build_object(
            'm', twin.ottoq_sim_generate_service_manifest(v_veh, v_run, v_seed));
          v_new_j := v_new_j || jsonb_build_object(
            'row', (SELECT (to_jsonb(n) - 'visit_id' - 'created_at') #- '{meta,observer}' FROM public.ottoq_visit_needs n
                     WHERE n.vehicle_id = v_veh AND n.sim_run_id = v_run AND n.status = 'open'),
            'cfg', (SELECT config->'service_manifest' FROM public.vehicles WHERE id = v_veh),
            'cfgmeta', (SELECT (config->'service_manifest_meta') - 'observer' - 'visit_id' FROM public.vehicles WHERE id = v_veh),
            'cards', (SELECT md5(COALESCE(string_agg(var_key||'|'||scope_instance||'|'||bucket_key||'|'||value::text||'|'||active::text, E'\n'
                                  ORDER BY var_key, scope_instance, bucket_key, value::text, active::text), ''))
                        FROM public.ottoq_variability_cards WHERE sim_run_id = v_run),
            'flags', (SELECT COALESCE(jsonb_agg(to_jsonb(f) - 'recalled_visit_id' ORDER BY f.flag_id), '[]'::jsonb)
                        FROM public.ottoq_rider_cleaning_flags f WHERE f.sim_run_id = v_run AND f.vehicle_id = v_veh),
            'complete_n', (SELECT count(*) FROM public.ottoq_visit_needs WHERE vehicle_id = v_veh AND status = 'complete'));
          RAISE EXCEPTION USING ERRCODE = 'P0200', MESSAGE = v_new_j::text;
        EXCEPTION WHEN SQLSTATE 'P0200' THEN v_new_j := SQLERRM::jsonb;
        END;
        v_probes := v_probes + 1;
        IF v_old IS DISTINCT FROM v_new_j THEN
          v_mism := v_mism + 1;
          IF v_first_mism IS NULL THEN
            v_first_mism := format('vehicle %s seed %s clock %s :: OLD %s :: NEW %s', v_veh, v_seed, v_clk,
                                   left(v_old::text, 1500), left(v_new_j::text, 1500));
          END IF;
        END IF;
        -- coverage: the probes must exercise more than the two trivial atoms
        v_atoms   := v_atoms   + COALESCE(jsonb_array_length(v_old->'m'), 0);
        v_flagged := v_flagged + CASE WHEN COALESCE((v_old->'row'->'meta'->>'rider_flagged')::boolean, false) THEN 1 ELSE 0 END;
        v_carried := v_carried + CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_old->'m','[]'::jsonb)) e WHERE COALESCE((e->>'carried')::boolean,false)) THEN 1 ELSE 0 END;
        v_fault   := v_fault   + CASE WHEN v_old->'row'->>'urgency' = 'tech_hold' THEN 1 ELSE 0 END;
      END LOOP;
    END LOOP;
  END LOOP;
  IF v_probes <> 160 THEN RAISE EXCEPTION '0200 A1 FAILED: expected 160 probes, ran %', v_probes; END IF;
  IF v_mism <> 0 THEN
    RAISE EXCEPTION '0200 A1 FAILED: % of % probes differ between the old body and the observer/kernel path. First: %', v_mism, v_probes, v_first_mism;
  END IF;
  IF v_atoms < 160 * 3 THEN
    RAISE EXCEPTION '0200 A1 FAILED: probes averaged under three atoms (% over %); the fixture is not exercising the generator', v_atoms, v_probes;
  END IF;
  RAISE NOTICE '0200 A1: % probes byte-identical (atoms %, rider-flagged %, carried %, tech_hold %), all rolled back', v_probes, v_atoms, v_flagged, v_carried, v_fault;

  -- ── A2. THE REAL PATH, LIVE AND ROLLED BACK. An external-depot vehicle gets needs
  --     from its profile, deterministically, with no run and no seed.
  IF NOT EXISTS (SELECT 1 FROM public.vehicles v JOIN public.depots d ON d.id = v.home_depot_id
                  WHERE v.id = v_ext AND d.feed_mode = 'external') THEN
    RAISE EXCEPTION '0200 A2 FIXTURE: external-depot vehicle % not found', v_ext;
  END IF;
  -- (a) a dirty, overdue, pending-everything profile at night: every state-derived atom, no drawn one
  BEGIN
    UPDATE public.vehicles SET current_soc = 40, target_soc = 100, last_state_change = '2026-09-02 04:30:00+00',
           config = COALESCE(config,'{}'::jsonb) || jsonb_build_object('pm_interval_km', 8000, 'calib_interval_h', 250)
     WHERE id = v_ext;
    DELETE FROM public.vehicle_need_profile WHERE vehicle_id = v_ext;
    INSERT INTO public.vehicle_need_profile (vehicle_id, profile_version, cabin_condition, exterior_soil_level, item_retrieval_pending,
            software_version, sw_target_version, sw_update_size_mb, odometer_km, km_at_last_pm, last_calibration_at, sensor_health_pct)
    VALUES (v_ext, '0200-probe', 'light_litter', 0.80, true, '1.0.0', '1.1.0', 1200, 9000, 0, '2026-08-01 00:00:00+00', 95);
    v_m1 := twin.ottoq_sim_generate_service_manifest(v_ext, NULL, NULL);
    SELECT to_jsonb(n) INTO v_row FROM public.ottoq_visit_needs n WHERE n.vehicle_id = v_ext AND n.status = 'open';
    RAISE EXCEPTION USING ERRCODE = 'P0200', MESSAGE = jsonb_build_object('m', v_m1, 'row', v_row)::text;
  EXCEPTION WHEN SQLSTATE 'P0200' THEN v_m1 := SQLERRM::jsonb;
  END;
  SELECT array_agg(e->>'svc' ORDER BY e->>'svc') INTO v_svcs FROM jsonb_array_elements(v_m1->'m') e;
  IF v_svcs IS DISTINCT FROM ARRAY['charge','exterior_wash','interior_inspection','interior_tidy','item_retrieval','mechanical_pm',
                                   'perimeter_walkaround','readiness_check','sensor_calibration','sensor_clean','software_update'] THEN
    RAISE EXCEPTION '0200 A2(a) FAILED: real-path atoms = %, expected exactly the eleven state-derived ones', v_svcs;
  END IF;
  IF v_m1->'row'->>'urgency' <> 'standard' OR v_m1->'row'->'meta'->>'generator' <> 'v5_state'
     OR v_m1->'row'->'meta'->>'observer' <> 'ottoq.ottoq_observe_asset' OR (v_m1->'row'->>'sim_run_id') IS NOT NULL THEN
    RAISE EXCEPTION '0200 A2(a) FAILED: row urgency/generator/observer/run = % / % / % / %',
      v_m1->'row'->>'urgency', v_m1->'row'->'meta'->>'generator', v_m1->'row'->'meta'->>'observer', v_m1->'row'->>'sim_run_id';
  END IF;
  -- (b) the same fixture twice is the same manifest: no dice anywhere on the real path
  BEGIN
    UPDATE public.vehicles SET current_soc = 40, target_soc = 100, last_state_change = '2026-09-02 04:30:00+00',
           config = COALESCE(config,'{}'::jsonb) || jsonb_build_object('pm_interval_km', 8000, 'calib_interval_h', 250)
     WHERE id = v_ext;
    DELETE FROM public.vehicle_need_profile WHERE vehicle_id = v_ext;
    INSERT INTO public.vehicle_need_profile (vehicle_id, profile_version, cabin_condition, exterior_soil_level, item_retrieval_pending,
            software_version, sw_target_version, sw_update_size_mb, odometer_km, km_at_last_pm, last_calibration_at, sensor_health_pct)
    VALUES (v_ext, '0200-probe', 'light_litter', 0.80, true, '1.0.0', '1.1.0', 1200, 9000, 0, '2026-08-01 00:00:00+00', 95);
    v_m2 := twin.ottoq_sim_generate_service_manifest(v_ext, NULL, NULL);
    RAISE EXCEPTION USING ERRCODE = 'P0200', MESSAGE = v_m2::text;
  EXCEPTION WHEN SQLSTATE 'P0200' THEN v_m2 := SQLERRM::jsonb;
  END;
  IF v_m1->'m' IS DISTINCT FROM v_m2 THEN
    RAISE EXCEPTION '0200 A2(b) FAILED: the real path produced two different manifests for the same state';
  END IF;
  -- (c) a clean, full, current vehicle by day: exactly readiness_check + interior_inspection
  BEGIN
    UPDATE public.vehicles SET current_soc = 100, target_soc = 100, last_state_change = '2026-09-01 20:00:00+00',
           config = (COALESCE(config,'{}'::jsonb) - 'cycles_since_wash' - 'wash_group') || jsonb_build_object('pm_interval_km', 8000, 'calib_interval_h', 250, 'wash_group', 1)
     WHERE id = v_ext;
    DELETE FROM public.vehicle_need_profile WHERE vehicle_id = v_ext;
    INSERT INTO public.vehicle_need_profile (vehicle_id, profile_version, cabin_condition, exterior_soil_level, item_retrieval_pending,
            software_version, sw_target_version, odometer_km, km_at_last_pm, last_calibration_at, sensor_health_pct, last_wash_at, wash_interval_h)
    VALUES (v_ext, '0200-probe', 'clean', 0.05, false, '1.1.0', '1.1.0', 1000, 0, '2026-09-01 00:00:00+00', 99, '2026-09-01 12:00:00+00', 72);
    v_m3 := twin.ottoq_sim_generate_service_manifest(v_ext, NULL, NULL);
    RAISE EXCEPTION USING ERRCODE = 'P0200', MESSAGE = v_m3::text;
  EXCEPTION WHEN SQLSTATE 'P0200' THEN v_m3 := SQLERRM::jsonb;
  END;
  SELECT array_agg(e->>'svc' ORDER BY e->>'svc') INTO v_svcs FROM jsonb_array_elements(v_m3) e;
  IF v_svcs IS DISTINCT FROM ARRAY['interior_inspection','readiness_check'] THEN
    RAISE EXCEPTION '0200 A2(c) FAILED: a clean, full, current vehicle by day got %, expected readiness_check + interior_inspection only', v_svcs;
  END IF;
  IF EXISTS (SELECT 1 FROM public.vehicle_need_profile WHERE profile_version = '0200-probe')
     OR EXISTS (SELECT 1 FROM public.ottoq_visit_needs WHERE vehicle_id = v_ext AND meta->>'observer' = 'ottoq.ottoq_observe_asset') THEN
    RAISE EXCEPTION '0200 A2 FAILED: a probe left rows behind';
  END IF;
  RAISE NOTICE '0200 A2: real path -> eleven state-derived atoms from a dirty profile, two from a clean one, deterministic, nothing left behind';

  -- ── A3. KERNEL PURITY, STRUCTURAL. No randomness source and no twin reference in
  --     any ottoq.* function this migration created; the kernel search_path has no twin.
  FOR v_names, v_src IN
    SELECT p.proname,
           regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')   -- code only; comments may say the word
           || ' ' || array_to_string(COALESCE(p.proconfig,'{}'), ' ')
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'ottoq' AND p.proname IN ('ottoq_derive_visit_needs','ottoq_generate_visit_needs','ottoq_observe_asset') LOOP
    IF v_src ~* 'seeded_random|ottoq_twin_deal|ottoq_twin_climate|profile_rate_mult|\mrandom\s*\(|\mtwin\M' THEN
      RAISE EXCEPTION '0200 A3 FAILED: ottoq.% references randomness or the twin schema', v_names;
    END IF;
  END LOOP;
  IF (SELECT array_to_string(proconfig, ' ') FROM pg_proc WHERE oid = 'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure) !~ 'search_path=ottoq, public, extensions' THEN
    RAISE EXCEPTION '0200 A3 FAILED: the kernel search_path must be ottoq, public, extensions';
  END IF;
  -- and the twin observer is the only place the draws survive
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_generate_service_manifest' AND p.prosrc ~* 'seeded_random|ottoq_twin_deal';
  IF v_n <> 0 THEN RAISE EXCEPTION '0200 A3 FAILED: the wrapper still draws'; END IF;
  RAISE NOTICE '0200 A3: no randomness and no twin reference in the kernel; the wrapper no longer draws';

  -- ── A4. THE CALL SITES DID NOT MOVE (they are in the pin as unchanged) and still name the wrapper.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('ottoq','twin') AND p.proname IN ('ottoq_book_appointment','ottoq_sim_prearrival_contracts','ottoq_sim_generate_arrival_manifests','ottoq_sim_wash_triage')
     AND p.prosrc ILIKE '%ottoq_sim_generate_service_manifest%';
  IF v_n <> 4 THEN RAISE EXCEPTION '0200 A4 FAILED: expected the four call sites to reference the wrapper, found %', v_n; END IF;
  RAISE NOTICE '0200 A4: four call sites unchanged and still reach the kernel through the wrapper';
END $assert$;

-- The probe copy has done its job.
DROP FUNCTION twin.ottoq_sim_generate_service_manifest_pre0200(uuid, uuid, bigint);

DO $assert5$
DECLARE v_new text[];
BEGIN
  -- ── A5. Re-pin: after the drop, exactly four new functions remain.
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0200 a USING (sig)
   WHERE a.sig IS NULL;
  IF v_new IS DISTINCT FROM ARRAY[
       'ottoq.ottoq_derive_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_clock timestamp with time zone, p_depot_id uuid, p_obs jsonb)',
       'ottoq.ottoq_generate_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid)',
       'ottoq.ottoq_observe_asset(p_vehicle_id uuid, p_run uuid, p_clock timestamp with time zone)',
       'twin.ottoq_sim_observe_asset(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_seed bigint, p_clock timestamp with time zone, p_depot_id uuid)'] THEN
    RAISE EXCEPTION '0200 A5 FAILED: after dropping the probe copy, new functions = %', v_new;
  END IF;
  RAISE NOTICE '0200 A5: probe copy dropped; four new functions remain';
  RAISE NOTICE '0200: all assertions passed';
END $assert5$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0200_the_twin_observes_the_kernel_derives_and_a_real_vehicle_stops_rolling_dice', TRUE,
  'G3. Every manifest path (twin arrival, prearrival backstop, ottoq_book_appointment incl. the real-feed return path, wash triage) called '
  'twin.ottoq_sim_generate_service_manifest, a 30KB seeded generator; a real vehicle would have had its needs drawn from the run seed. '
  'Split: ottoq.ottoq_derive_visit_needs (kernel: observations + asset state + policy -> visit row, flag consume, manifest cache; no '
  'randomness, no twin reference, search_path without twin); twin.ottoq_sim_observe_asset (the v4_condition draws, same seed/salts, same '
  'three twin_deal cards in order); ottoq.ottoq_observe_asset (sensed: fault codes, cabin condition, item pending, software target vs '
  'installed, soil, PM/calibration due; assumptions G3-1..4 recorded); ottoq.ottoq_generate_visit_needs (real-feed entry); the generator '
  'is now a wrapper switching on depots.feed_mode so its four call sites are untouched. A1: 160 live rolled-back probes (40 flagship '
  'vehicles x 2 seeds x day/night) old vs new byte-identical on manifest, visit row, manifest cache, variability cards and rider flags. '
  'A2: real path yields eleven state-derived atoms from a dirty profile, two from a clean one, deterministic. A0/A5 pin: one body '
  'changed, four new, none SECURITY DEFINER. forces_recert TRUE because a decide-path body changed; the prediction for round 20 is '
  'that no canon moves. Recorded for G13: unscoped supersede of open visits; carryover scoped on the caller''s run while the row is '
  'written with the resolved run.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-06 15:51:00 UTC (10:51 AM CT) -- one transaction as
-- postgres through a one-shot pg_cron job (jobid 394, scheduled 15:49:34
-- UTC for 15:51, per the lesson in 0201's footer). The job ran 15:51:00.10
-- to 15:51:06.23 and returned COMMIT: the 160 A1 probes, the A2 real-path
-- probe, the A3 purity scan, the A4 call-site check and the A5 re-pin all
-- passed inside those six seconds. Verified from the ledger at 15:52 UTC:
--
--   job_run_details 394               succeeded, return_message COMMIT
--   lineage row                       present, 15:51:00.10, forces_recert TRUE
--   ottoq_cert_recert_floor()         moved 15:40:59 -> 15:51:00 (the matrix
--                                     is entirely stale until round 20)
--   ottoq.ottoq_derive_visit_needs    present, not SECURITY DEFINER
--   ottoq.ottoq_generate_visit_needs  present, not SECURITY DEFINER
--   ottoq.ottoq_observe_asset         present, not SECURITY DEFINER
--   twin.ottoq_sim_observe_asset      present, not SECURITY DEFINER
--   twin.ottoq_sim_generate_service_manifest
--                                     body changed (now the feed_mode wrapper),
--                                     still SECURITY DEFINER as before
--   ..._pre0200 probe copy            absent (A5)
--   vehicle_need_profile '0200-probe' 0 rows (A2 left nothing)
--   ottoq_calibration_fingerprint()   11a246262ff7a2c929483b1ee0a7cd2d, unchanged
--   apply_0200 cron job               unscheduled by hand at 15:52 UTC (a
--                                     one-shot written as a date schedule
--                                     would otherwise fire again next year)
--
-- Pre-checks before scheduling the apply, 15:45 UTC: no r*_ or apply_ jobs,
-- no pair backend in pg_stat_activity, no running sim run, live generator
-- md5 0cd6b895241d4f7898daaa44ae72fed4 (matches the A1 pin).
--
-- ROUND 20, scheduled 15:53 UTC as nine self-unscheduling pairs, budget
-- 1800, sim_start 2026-09-01 02:00 UTC, flagship depot (jobids 395-403):
--
--   15:56  r20_c2_busy_314159_12t        16:09  r20_c1_busy_171717_12t
--   16:22  r20_c2dup_busy_314159_12t     16:35  r20_c1dup_busy_171717_12t
--   16:48  r20_c3_normal_171717_12t      17:01  r20_c3dup_normal_171717_12t
--   17:14  r20_c4_busy_424242_12t        17:27  r20_c5_busy_171717_24t
--   17:52  r20_c6_busy_424242_24t
--
-- PREDICTIONS, written before the first pair fires:
--   1. No canon moves attributable to 0200. Its A1 equivalence (160 rolled-
--      back probes, old vs new byte-identical on manifest, visit row, cache,
--      cards and flags) is the proof; the round is the check. Concretely:
--      314159/12t = 2b86847e, 171717/12t = 2574c54f, normal_day = 940d3890,
--      424242/12t = 029cad7d, 171717/24t = 2574c54f, 424242/24t = bea94486
--      (round 19's post-refit values), and the doubled columns agree with
--      themselves twice.
--   2. h_cal = 11a246262ff7a2c929483b1ee0a7cd2d on every arm of every pair,
--      and canon_cal reads that value on every column. The next ingest is
--      Sunday 2026-09-13 04:00 UTC; nothing refits under this round.
--   3. h_prop and h_defr unchanged from round 19 per column.
--   4. Nine of nine equal=true, complete=true within budget; 12t pairs in
--      9-13 min, 24t pairs in 16-20 min, no overlap between neighbours.
-- If prediction 1 fails on any column, the first divergence is 0200's to
-- explain before anything else is built; the A1 probes covered day and
-- night clocks but not every tick of a 12-tick run.
-- =====================================================================
--
-- CORRECTION 2026-09-06 16:45 UTC (11:45 AM CT), written after round 20's
-- first pair and before its fifth. Prediction 1 above is wrong twice, and
-- the ledger caught it before the round did:
--   (a) the six hashes it lists (2b86847e, 2574c54f, 940d3890, 029cad7d,
--       2574c54f, bea94486) are round 19's h_prop values, not its h_cmd
--       canons. The canons (h_cmd, arm_a, from validation_notes) are:
--         314159/12t  cf74d080   PRE-refit  (round-19 pair 1, 03:43 UTC)
--         171717/12t  80183641   PRE-refit  (round-19 pair 2, 03:56 UTC)
--         normal_day  634a8781   post-refit
--         424242/12t  adf745a2   post-refit
--         171717/24t  5dd1816d   post-refit
--         424242/24t  997e2c37   post-refit
--   (b) round 19's pairs 1 and 2 ran BEFORE the 04:05:25 UTC calibration
--       refit (db/checks/0115), so 314159/12t and 171717/12t have never
--       been run on the current priors. The honest prediction for them is
--       "a first post-refit value, and the doubled column agrees with
--       itself twice" -- which is what task #64 said and what this footer
--       failed to write. Only the four post-refit columns must equal
--       round 19.
-- Round 20 pair 1 (314159/12t, 15:56 UTC) reads h_cmd 9fa71d19, h_dec
-- 1fa3e10e, h_evt 36bb019a, h_nrg fec46a84, h_prop 4469caa1, h_cal
-- 11a24626, fp 803698f3. fp equals round 19's and h_cal is the post-refit
-- fingerprint, so the world booted identically on the current priors and
-- the streams moved -- consistent with the refit, not yet proof of it.
-- Prediction 1 stands, corrected: 314159/12t and 171717/12t move once and
-- repeat; normal_day, 424242/12t, 171717/24t and 424242/24t must read
-- 634a8781, adf745a2, 5dd1816d, 997e2c37. If any of those four moves,
-- 0200 is the suspect and the first divergence is its to explain.
--
-- ROUND 20 READ 2026-09-06 18:16 UTC (1:16 PM CT). db/checks/0116.
-- Prediction 1 (corrected)  MET. normal_day 634a8781, 424242/12t adf745a2,
--                           171717/24t 5dd1816d (arm A), 424242/24t 997e2c37
--                           reproduced round 19; 314159/12t and 171717/12t
--                           moved once (9fa71d19, 93e895e6) and repeated.
--                           Nothing that 0200 could be blamed for moved.
-- Prediction 2              MET. h_cal 11a24626 on all eighteen arms;
--                           canon_cal populated on all six columns.
-- Prediction 3              MET with a note: 314159/12t's h_prop moved with
--                           its h_cmd on its first post-refit pass (the
--                           refit, not a proposer coin); the rest unchanged.
-- Prediction 4              NOT MET. 8 of 9. Pair 8 (171717/24t) failed
--                           intra-pair: a sort tie in ottoq_react_to_refusals
--                           settled by physical row order. Convicted in 0116,
--                           fixed by 0207. Not this migration's.
