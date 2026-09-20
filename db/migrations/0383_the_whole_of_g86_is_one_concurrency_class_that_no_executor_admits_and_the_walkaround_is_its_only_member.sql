-- migration-version: 20260920161631
-- migration-name:    the_whole_of_g86_is_one_concurrency_class_that_no_executor_admits_and_the_walkaround_is_its_only_member
--
-- 0383  G86: `perimeter_walkaround` IS NOT MISSING AN EXECUTOR. IT IS DERIVED INTO A
--       SEVENTH CONCURRENCY CLASS, `hold`, THAT NO STARTER ANYWHERE ADMITS, AND IT IS
--       THAT CLASS'S ONLY MEMBER.
--
-- `forces_recert` **TRUE**. This changes what `ottoq.ottoq_derive_visit_needs` writes into
-- every new visit's atom set, so a canon computed before it cannot reproduce after it.
--
-- ══ 1. WHAT G86 SAYS, AND WHICH HALF OF IT IS WRONG ═════════════════════════
--
-- `db/checks/0261` traced G86 as *"a producer, two observers that say yes for 90% of
-- arrivals, and no executor anywhere in the engine"*, and CLAUDE.md Part 3 carries the
-- consequence as *"its `perimeter_hold` bookings held 98 of the twin depot's 113 staging
-- stalls at an average 248-minute window."*
--
-- **The producer/never-completes half is true. The attribution of the staging pressure is
-- not, and it is a prefix match.** Measured on the twin depot:
--
--   purpose          need_code              need_atom              n    avg_min  stalls
--   perimeter_hold   perimeter_hold         **NULL**              82      230.1      82
--   temp_hold        temp_hold              NULL                  86       23.4      47
--   service          perimeter_walkaround   perimeter_walkaround  14       ~40        2
--
-- `perimeter_hold` is named for the depot's perimeter **RING**, not for a walk around a
-- vehicle's perimeter. `ottoq.ottoq_book_hold_stall` decides it on duration alone --
-- `v_purpose := CASE WHEN v_is_long THEN 'perimeter_hold' ELSE 'temp_hold' END`, where
-- `v_is_long := v_minutes >= p_long_threshold_min` -- and it carries `need_atom IS NULL`
-- because it serves no service atom at all. It is the long-dwell PARKING purpose. The
-- walkaround's own bookings are `purpose='service'` on two service-bay stalls, fourteen of
-- them. **No function in the database mentions both strings**, which is the cheap check
-- that would have caught this: the two sets of functions are disjoint.
--
-- So the 82 staging stalls under a 230-minute hold are long-dwell parking, which is what
-- staging stalls are FOR. They are not a walkaround pathology and freeing the walkaround
-- will not return them.
--
-- ══ 2. THE ACTUAL CAUSE, AND AN EXECUTOR THAT WAS ALREADY THERE ═════════════
--
-- There IS a general in-place executor: `twin.ottoq_sim_advance_visit_atoms`. It completes
-- **any** atom whose `status='in_progress'` and `ends_at <= p_clock` -- it names no service
-- -- then closes the atom's flow-contract leg and credits `ottoq_wear_mark_serviced`. It
-- needs no bay. What gates it is the **start** side, `ottoq_start_concurrent_atoms`:
--
--   AND v_a->>'concurrency' IN ('cabin','exterior','digital')
--
-- and the walkaround is derived with `'concurrency','hold'`. Completion by concurrency
-- class on the twin depot, which is the whole finding in one table:
--
--   concurrency  atoms  services                                     done  in_prog  pending
--   cabin          127  interior_inspection/tidy, item_retrieval,      75        5       46
--                       triage_check
--   gate            98  readiness_check                                33        0       65
--   anchor          67  charge                                         28        0       39
--   bay             64  wash/detail/service-bay six                    23        0       41
--   **hold**      **63**  **perimeter_walkaround**                    **0**    **0**   **63**
--   digital          5  remote_diagnostics                              2        0        3
--   exterior         2  sensor_clean                                    1        0        1
--
-- **Every class completes except `hold`, `hold` has exactly one member, and not one of its
-- 63 atoms has ever reached `in_progress`.** It is an orphan class, not a missing feature.
--
-- ══ 3. AND THE ENGINE ALREADY KNEW, IN TWO PLACES ══════════════════════════
--
--   * `ottoq.ottoq_atom_retirable_set()` -- the engine's own list of services it can
--     complete -- holds 14 entries and not this one, so `ottoq.ottoq_atoms_guard` demotes
--     the atom to `must_do:false` with `guard_reason='svc_not_retirable'`. Measured: 39 of
--     63 carry that demotion. The other 24... 25 are from a 2026-08-30 run and predate the
--     guard; every atom written by today's run is guarded, so there is no second writer.
--   * `public.ottoq_assert_service_vocabulary()` returns
--     `undeclared => {perimeter_walkaround}` today. It is the ONLY undeclared service.
--
-- The guard is why this was survivable rather than fatal: 39 atoms that cannot be done are
-- also not required. But 25 legacy atoms are `must_do:true` AND unperformable, and
-- `ottoq_kpi_service_completion` counts those in its denominator -- so the defect was
-- already dragging the published completion percentage down, not hidden from it.
--
-- ══ 4. THE FIX, AND WHY `exterior` IS THE RIGHT CLASS ══════════════════════
--
-- `sensor_clean` is the exact precedent and needs no new machinery: event-raised,
-- `cadence_kind='event'`, `must_do_at='always'`, `lane='exterior'`, `lane_stalls=NULL`,
-- performed at the vehicle where it stands. A perimeter walkaround is the same shape, and
-- the atom already declares `at_perimeter: true`.
--
-- **AND IT DOES NOT FABRICATE LABOUR, WHICH IS THE ONLY WAY THIS COULD HAVE BEEN
-- DISHONEST.** `ottoq_start_concurrent_atoms` already meters the tech pool:
--
--   v_free := GREATEST(0, ottoq_depot_staffing_count(depot,'general_tech')
--                       - count(in_progress atoms WHERE concurrency IN ('cabin','exterior')))
--
-- `general_tech` is **10** at the twin depot, each tech takes one vehicle at a time, and
-- `exterior` is already inside that subtraction. So admitting the walkaround costs a tech
-- exactly like a sensor clean does, and 63 pending atoms cannot all start at once. Had the
-- class been `digital` -- the one branch exempt from the pool -- it would have completed
-- 63 walkarounds with nobody walking. That is the reason this migration does not take the
-- cheaper route.
--
-- Three coordinated changes, and the ORDER MATTERS between two of them: declaring the
-- service retirable while nothing retires it would stop the guard demoting and convert 63
-- harmless atoms into permanent `must_do` blockers. They land in one transaction.
--
--   (a) derive with `'concurrency','exterior'`, keeping `at_perimeter:true`
--   (b) add it to `ottoq_atom_retirable_set()`, which is now TRUE rather than aspirational
--   (c) declare it in `service_cadence_policy`, mirroring `sensor_clean`, which closes
--       `ottoq_assert_service_vocabulary()`. Verified NOT to route it to a bay:
--       `ottoq_svc_to_stall_type` maps lane `exterior` to NULL by name in its own CASE.
--
-- **NO BACKFILL OF STORED ATOMS, deliberately.** The 39 pending `hold` atoms on live run
-- `562bf027` keep their class and will never start. Rewriting a live run's working set to
-- make a fix look bigger is the opposite of measuring it; the effect is measured on a
-- fresh run instead.
--
-- ══ 5. AND THE DETECTOR, WHICH IS THE PART THAT GENERALISES ════════════════
--
-- A service silently unperformable for the life of an engine is worth one function.
-- `public.ottoq_atom_class_coverage` reports every concurrency class observed in
-- `ottoq_visit_needs.atoms` with its services, its counts, and whether any atom of that
-- class has **ever** reached `in_progress` or `done`. It is deliberately EVIDENCE-based
-- rather than a probe of any starter's source: a source probe is the kind of pattern match
-- that produced §1's retracted attribution, and `bay`/`anchor`/`gate` are executed by
-- three other executors that no single starter's text would name. An orphan class is
-- exactly `atoms > 0 AND ever_started = 0`, which cannot drift and cannot be misread.

-- ══ P0 PREFLIGHT ═══════════════════════════════════════════════════════════

DO $p0$
DECLARE v_n int; v_retirable boolean; v_undeclared text[];
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_derive_visit_needs'
     AND p.prosrc LIKE '%''concurrency'',''hold''%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0383 P0: expected exactly 1 derive function carrying ''concurrency'',''hold'', found %', v_n;
  END IF;

  v_retirable := ottoq.ottoq_atom_retirable('perimeter_walkaround');
  IF v_retirable THEN
    RAISE EXCEPTION '0383 P0: perimeter_walkaround is already retirable -- this migration assumes it is not';
  END IF;

  SELECT undeclared INTO v_undeclared FROM public.ottoq_assert_service_vocabulary();
  IF NOT ('perimeter_walkaround' = ANY(v_undeclared)) THEN
    RAISE EXCEPTION '0383 P0: perimeter_walkaround is already declared in service_cadence_policy';
  END IF;

  RAISE NOTICE '0383 P0: preconditions hold -- class=hold, not retirable, not declared';
END $p0$;

-- ══ (a) DERIVE: 'hold' -> 'exterior' ═══════════════════════════════════════
-- Body reproduced verbatim from pg_get_functiondef at 2026-09-20 16:16 UTC with exactly
-- one substitution, asserted byte-exact before this file was written (19,080 -> 19,084
-- bytes, the four characters of 'exterior' minus 'hold'). Nothing else in this 340-line
-- function is touched.

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
      'concurrency','exterior','at_perimeter',true);
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

-- ══ (b) THE RETIRABLE SET: now true, not aspirational ══════════════════════

CREATE OR REPLACE FUNCTION ottoq.ottoq_atom_retirable_set()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'ottoq', 'public', 'extensions'
AS $function$
  SELECT ARRAY(
    SELECT DISTINCT s FROM (
      SELECT unnest(ottoq.ottoq_bay_purpose_atoms(p)) AS s
        FROM unnest(ARRAY['wash','detail','service','inspect']) p
      UNION ALL
      -- The non-bay retirables: completed in place by ottoq_start_concurrent_atoms ->
      -- twin.ottoq_sim_advance_visit_atoms, or by the charge-session and departure seams.
      -- 0383 adds perimeter_walkaround, which became completable in the same transaction
      -- when derive stopped writing it into the orphan 'hold' concurrency class. Adding it
      -- here WITHOUT that change would stop ottoq_atoms_guard demoting it and turn 63
      -- harmless atoms into permanent must_do blockers.
      SELECT unnest(ARRAY['charge','readiness_check','triage_check',
                          'interior_inspection','item_retrieval',
                          'remote_diagnostics','perimeter_walkaround'])
    ) u ORDER BY s);
$function$;

-- ══ (c) DECLARE THE SERVICE, MIRRORING sensor_clean ════════════════════════
-- lane='exterior' is what keeps it out of a bay: ottoq_svc_to_stall_type's own CASE maps
-- wash_bay/detail/service_bay to stall types and returns NULL for
-- 'anchor / cabin / exterior / digital / gate, and anything new'.

INSERT INTO public.service_cadence_policy
  (svc, display_name, category, lane, est_min_default, cadence_kind,
   due_soon_ratio, due_ratio, overdue_ratio, critical_ratio, must_do_at,
   lane_stalls, sequence_order, notes, is_active)
VALUES
  ('perimeter_walkaround', 'Perimeter walkaround', 'inspection', 'exterior', 12, 'event',
   0.00, 1.00, 1.25, 1.60, 'always',
   NULL, 27,
   '0383/G86. Night-shift walkaround raised by the asset observer, performed at the vehicle '
   'where it stands (the atom carries at_perimeter:true) and metered against the '
   'general_tech pool exactly like sensor_clean. Declared here to close '
   'ottoq_assert_service_vocabulary, which reported this as the only observed-but-undeclared '
   'service. lane=exterior deliberately: ottoq_svc_to_stall_type maps that lane to NULL, so '
   'the service consumes a technician and never a bay. est_min_default 12 matches derive''s '
   'own COALESCE((p_obs->>''perimeter_walkaround_min'')::int, 12). must_do_at=always mirrors '
   'sensor_clean and fault_repair: event-raised, and mandatory once raised.',
   true)
ON CONFLICT (svc) DO NOTHING;

-- ══ (5) THE DETECTOR ══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_atom_class_coverage(p_sim_run_id uuid DEFAULT NULL)
 RETURNS TABLE(concurrency text, services text[], atoms bigint, pending bigint,
               in_progress bigint, done bigint, cancelled bigint, ever_started bigint,
               first_start timestamptz, last_start timestamptz, verdict text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  WITH a AS (
    SELECT COALESCE(e->>'concurrency','(none)')        AS cls,
           e->>'svc'                                   AS svc,
           COALESCE(e->>'status','pending')             AS st,
           (e->>'started_at')::timestamptz             AS started_at
      FROM public.ottoq_visit_needs vn,
           jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
     WHERE (p_sim_run_id IS NULL OR vn.sim_run_id = p_sim_run_id)
       AND (e->>'svc') IS NOT NULL)
  SELECT cls,
         array_agg(DISTINCT svc ORDER BY svc),
         count(*),
         count(*) FILTER (WHERE st = 'pending'),
         count(*) FILTER (WHERE st = 'in_progress'),
         count(*) FILTER (WHERE st = 'done'),
         count(*) FILTER (WHERE st = 'cancelled'),
         count(*) FILTER (WHERE st IN ('in_progress','done')),
         min(started_at), max(started_at),
         CASE
           WHEN count(*) FILTER (WHERE st IN ('in_progress','done')) > 0 THEN 'executing'
           WHEN count(*) FILTER (WHERE st = 'cancelled') = count(*)      THEN 'all_cancelled'
           ELSE 'ORPHAN_CLASS: ' || count(*)
                || ' atoms, none ever reached in_progress or done'
         END
    FROM a GROUP BY cls ORDER BY count(*) DESC;
$function$;

COMMENT ON FUNCTION public.ottoq_atom_class_coverage(uuid) IS
'0383/G86. One row per concurrency class observed in ottoq_visit_needs.atoms. An ORPHAN_CLASS verdict means atoms of that class exist and not one has ever reached in_progress or done -- a service the engine derives and no executor can perform. This is how G86 hid: perimeter_walkaround was derived into class ''hold'', which no starter admits, and sat at 63 atoms / 0 started while every other class completed. DELIBERATELY EVIDENCE-BASED, NOT A SOURCE PROBE: the in-place starter (ottoq_start_concurrent_atoms) names only cabin/exterior/digital, while bay, anchor and gate are executed by the bay-exit, charge-session and departure seams respectively, so no single function''s text is the authority on what is executable -- and a text probe is the pattern-match class of error that produced 0383 section 1''s retracted attribution. Pass a sim_run_id to scope to one run (atoms are class=engine and purge with their run); NULL reads whatever survives.';

-- ══ POSTFLIGHT ════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_derive_visit_needs'
     AND p.prosrc LIKE '%''concurrency'',''exterior'',''at_perimeter'',true%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0383 P1: derive does not carry the exterior/at_perimeter atom (found %)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_derive_visit_needs'
     AND p.prosrc LIKE '%''concurrency'',''hold''%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0383 P1: derive still carries ''concurrency'',''hold'' in % definition(s)', v_n;
  END IF;
  RAISE NOTICE '0383 P1: derive writes concurrency=exterior, no hold remains';
END $p1$;

DO $p2$
DECLARE v_set text[];
BEGIN
  v_set := ottoq.ottoq_atom_retirable_set();
  IF NOT ottoq.ottoq_atom_retirable('perimeter_walkaround') THEN
    RAISE EXCEPTION '0383 P2: perimeter_walkaround is still not retirable';
  END IF;
  IF array_length(v_set,1) <> 15 THEN
    RAISE EXCEPTION '0383 P2: retirable set is % entries, expected 15 (14 + perimeter_walkaround)',
      array_length(v_set,1);
  END IF;
  -- the six pre-existing non-bay entries must all survive
  IF NOT (ARRAY['charge','readiness_check','triage_check','interior_inspection',
                'item_retrieval','remote_diagnostics'] <@ v_set) THEN
    RAISE EXCEPTION '0383 P2: the retirable set lost a pre-existing non-bay member: %', v_set;
  END IF;
  RAISE NOTICE '0383 P2: retirable set is 15 and carries perimeter_walkaround';
END $p2$;

DO $p3$
DECLARE v_undeclared text[]; v_never text[]; v_lane text; v_stall text;
BEGIN
  SELECT undeclared, never_observed INTO v_undeclared, v_never
    FROM public.ottoq_assert_service_vocabulary();
  IF 'perimeter_walkaround' = ANY(COALESCE(v_undeclared,'{}'::text[])) THEN
    RAISE EXCEPTION '0383 P3: perimeter_walkaround still reads as undeclared';
  END IF;
  IF array_length(COALESCE(v_undeclared,'{}'::text[]),1) IS NOT NULL THEN
    RAISE EXCEPTION '0383 P3: the vocabulary gap is not empty: %', v_undeclared;
  END IF;

  SELECT lane INTO v_lane FROM public.service_cadence_policy
   WHERE svc='perimeter_walkaround' AND is_active;
  IF v_lane <> 'exterior' THEN
    RAISE EXCEPTION '0383 P3: declared lane is %, expected exterior', v_lane;
  END IF;

  -- the point of lane=exterior: it must NOT resolve to a bookable bay
  v_stall := ottoq.ottoq_svc_to_stall_type('perimeter_walkaround',
               '11111111-1111-1111-1111-111111111111');
  IF v_stall IS NOT NULL THEN
    RAISE EXCEPTION '0383 P3: declaring the service routed it to stall type % -- it must stay in place', v_stall;
  END IF;
  RAISE NOTICE '0383 P3: vocabulary gap closed, lane=exterior, routes to no bay';
END $p3$;

DO $p4$
DECLARE v_rec RECORD; v_orphans int := 0; v_rows int := 0;
BEGIN
  -- Invoke the detector rather than string-match it: 0381 shipped a function body that
  -- raised 42703 while three source assertions passed, because plpgsql resolves columns
  -- at execution. The only assertion worth making about a function is that it runs.
  FOR v_rec IN SELECT * FROM public.ottoq_atom_class_coverage() LOOP
    v_rows := v_rows + 1;
    IF v_rec.verdict LIKE 'ORPHAN_CLASS%' THEN
      v_orphans := v_orphans + 1;
      RAISE NOTICE '0383 P4: orphan class % (%) -- %',
        v_rec.concurrency, v_rec.services, v_rec.verdict;
    END IF;
    IF v_rec.atoms <> v_rec.pending + v_rec.in_progress + v_rec.done + v_rec.cancelled THEN
      RAISE EXCEPTION '0383 P4: class % does not sum -- % atoms vs %+%+%+%',
        v_rec.concurrency, v_rec.atoms, v_rec.pending, v_rec.in_progress,
        v_rec.done, v_rec.cancelled;
    END IF;
  END LOOP;
  IF v_rows = 0 THEN
    RAISE EXCEPTION '0383 P4: the detector returned no classes -- it cannot report a clean answer over nothing';
  END IF;
  -- `hold` IS STILL EXPECTED HERE. The 63 stored atoms keep the class they were written
  -- with; §4 says why they are not backfilled. What must be true is that the detector
  -- SEES it, which is the capability this migration adds.
  RAISE NOTICE '0383 P4: detector returned % classes, % orphan', v_rows, v_orphans;
END $p4$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0383_the_whole_of_g86_is_one_concurrency_class_that_no_executor_admits_and_the_walkaround_is_its_only_member', true,
  'G86 closed. perimeter_walkaround was never missing an executor: twin.ottoq_sim_advance_visit_atoms '
  'completes ANY atom whose ends_at has passed and names no service, but the start gate '
  '(ottoq_start_concurrent_atoms) admits only concurrency IN (cabin,exterior,digital) and derive wrote '
  'the walkaround as concurrency=hold -- a seventh class with exactly one member and, measured on the '
  'twin depot, 63 atoms of which 0 ever reached in_progress while every other class completed (cabin '
  '75/127, gate 33/98, anchor 28/67, bay 23/64, digital 2/5, exterior 1/2). Fixed by deriving it as '
  'exterior beside sensor_clean, which is metered against the general_tech pool (10 at the twin depot) '
  'so admitting it costs a technician rather than fabricating labour -- the digital branch, exempt from '
  'that pool, would have completed 63 walkarounds with nobody walking. Also adds it to '
  'ottoq_atom_retirable_set (same transaction, never before the derive change, or ottoq_atoms_guard '
  'stops demoting and 63 harmless atoms become permanent must_do blockers) and declares it in '
  'service_cadence_policy with lane=exterior, closing the only entry in '
  'ottoq_assert_service_vocabulary.undeclared while ottoq_svc_to_stall_type keeps mapping that lane to '
  'NULL so it consumes no bay. RETRACTS the staging-stall attribution in CLAUDE.md Part 3 and '
  'db/checks/0261: perimeter_hold is named for the depot perimeter RING and is chosen on dwell '
  'duration alone by ottoq_book_hold_stall, carries need_atom IS NULL, and no function in the database '
  'mentions both strings -- the walkaround''s own bookings are 14 purpose=service rows on two stalls, '
  'not the 82 staging holds. Adds public.ottoq_atom_class_coverage, an evidence-based detector (atoms '
  'exist, none ever started) so an orphan concurrency class cannot hide again. forces_recert TRUE: '
  'derive writes a different atom set.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
