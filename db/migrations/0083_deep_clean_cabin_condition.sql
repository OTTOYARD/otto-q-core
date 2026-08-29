-- migration-version: 20260828090000
-- migration-name:    deep_clean_cabin_condition
-- 0083 -- Reconcile the deep-clean divergence, the third instance of "the needs card identifies
-- work the manifest never materializes." The card grades cabin_condition soiled->overdue,
-- biohazard->critical and flags interior_deep_clean as MUST-DO; the manifest generated
-- interior_deep_clean only as a ~10% random draw (deferrable), ignoring cabin_condition entirely.
-- A soiled/biohazard vehicle therefore deployed dirty while the card said it must be cleaned.
--
-- EVIDENCE (run 6f85e7ab, normal_day, seed 777007):
--   cabin_condition in vehicle_need_profile: clean 67 / light_litter 33 / soiled 13 / biohazard 3
--   in-depot vehicles with cabin_condition IN (soiled,biohazard) and no deep_clean atom: real gap
--   the card flagged must_do but the manifest did not materialize (atom exists only via the 10% draw).
--
-- FIX: the manifest's interior_deep_clean gate now ALSO fires when cabin_condition is soiled or
-- biohazard (must_do=true), in addition to the existing cadence draw (deferrable). It reads the
-- SAME cabin_condition column from vehicle_need_profile that the card grades by. NULL-safe: no
-- profile row => the flag is false and the random-draw gate still applies. 0082 wash backstop is
-- preserved byte-for-byte.

CREATE OR REPLACE FUNCTION twin.ottoq_sim_generate_service_manifest(p_vehicle_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid, p_seed bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc numeric; v_target numeric; v_cycles int; v_seed bigint; v_m jsonb := '[]'::jsonb;
  v_depot uuid; v_clock timestamptz; v_run uuid; v_plan jsonb; v_visit text;
  v_precip_stress numeric := 0; v_boost numeric := 0;
  v_probs jsonb; v_clamp_lo numeric := 0.005; v_clamp_hi numeric := 0.90;
  v_p numeric; v_conf numeric;
  v_hour int; v_urgency text; v_due timestamptz; v_visit_target numeric;
  v_is_night boolean; v_tail_scale numeric; v_insp_p numeric; v_night_start int; v_night_end int;
  v_fault boolean := false; v_ota boolean := false;
  v_band_lo numeric; v_band_hi numeric;
  v_sla_floor numeric; v_sim_day int;
  v_carry jsonb; v_carry_visit uuid; v_atom jsonb;
  v_archetype text;
  v_wear RECORD; v_soil numeric := 0; v_cap numeric; v_inlet_kw numeric; v_soh numeric;
  v_curve numeric; v_svcspd numeric; v_pm_int numeric; v_calib_int numeric; v_washcad int;
  v_pm_prog numeric := 0; v_calib_prog numeric := 0;
  v_wash_min int; v_deep_min int; v_pm_min int; v_calib_min int; v_charge_min int := 0;
  -- 0082: the hours-clock wash signal. needs_card grades wash OVERDUE from
  -- (sim_clock - last_wash_at) / wash_interval_h; this manifest previously only
  -- washed on night-rotation + soil + cycles. Reconciled by reading the SAME clock.
  v_last_wash timestamptz; v_wash_int numeric; v_wash_ratio numeric; v_wash_overdue boolean := false;
  -- 0083: cabin-condition deep-clean signal (soiled/biohazard => must clean, same source the
  -- needs card grades cabin_urgency by). The manifest previously only drew deep-clean as a
  -- 10% random event, ignoring the actual cabin state.
  v_cabin_cond text; v_deep_clean_due boolean := false;
  -- 0018. SCALARS, not a RECORD: the flag lookup is skipped entirely when v_run is
  -- NULL (benchmark / no active run), and reading a field of a never-assigned
  -- plpgsql RECORD raises "record is not assigned yet". Scalars are NULL-safe.
  v_rf_id uuid; v_rf_kind text; v_rf_status text; v_rf_visit text;
  v_rf_svc text; v_rf_min int;
  -- 0020. The visit row this call actually wrote, and the visit the flag was
  -- previously consumed by. Both uuids. Nothing is resolved by string any more.
  v_visit_id uuid; v_rf_prev_visit_id uuid; v_this_visit_id uuid;
  v_rf_place boolean := false; v_rf_retire boolean := false;
  v_salt text;   /* 0055: run-relative draw salt; v_visit stays the ledger key */
BEGIN
  SELECT current_soc, COALESCE(target_soc, public.ottoq_default_target_soc()), COALESCE((config->>'cycles_since_wash')::int,0),
         home_depot_id, COALESCE(last_state_change, now()),
         battery_capacity_kwh, inlet_max_kw,
         (config->>'battery_soh_pct')::numeric, (config->>'charge_curve_scalar')::numeric,
         (config->>'service_speed_scalar')::numeric, (config->>'pm_interval_km')::numeric,
         (config->>'calib_interval_h')::numeric, (config->>'wash_cadence_cycles')::int
    INTO v_soc, v_target, v_cycles, v_depot, v_clock,
         v_cap, v_inlet_kw, v_soh, v_curve, v_svcspd, v_pm_int, v_calib_int, v_washcad
    FROM vehicles WHERE id = p_vehicle_id;
  IF v_soc IS NULL THEN RETURN NULL; END IF;
  SELECT w.soil_index,
         w.drive_km_total    - COALESCE(w.km_at_last_pm,0)             AS km_since_pm,
         w.drive_hours_total - COALESCE(w.hours_at_last_calibration,0) AS h_since_calib
    INTO v_wear FROM ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND (p_sim_run_id IS NULL OR w.sim_run_id = p_sim_run_id)
   ORDER BY w.updated_at DESC LIMIT 1;
  v_soil := COALESCE(v_wear.soil_index, 0);

  -- 0082: fetch the hours-clock wash cadence the needs card grades by. If the row is
  -- missing (no profile drawn yet), v_wash_ratio stays NULL and the backstop below is a
  -- no-op -- the rotation/soil/cycles gates still apply, so nothing regresses.
  SELECT p.last_wash_at, p.wash_interval_h, p.cabin_condition
    INTO v_last_wash, v_wash_int, v_cabin_cond
    FROM public.vehicle_need_profile p
   WHERE p.vehicle_id = p_vehicle_id;

  v_run := COALESCE(p_sim_run_id,
    (SELECT sim_run_id FROM ottoq_sim_runs r
      WHERE r.status = 'running' AND r.depot_id = v_depot
      ORDER BY started_at DESC LIMIT 1));

  v_plan := ottoq_feed_plan('service_manifest');

  IF p_seed IS NOT NULL THEN
    v_seed := p_seed;
  ELSIF v_run IS NOT NULL THEN
    SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = v_run;
  ELSE
    v_seed := abs(hashtextextended(p_vehicle_id::text || 'manifest', 13));
  END IF;
  -- 0020 NOTE. v_visit is UNCHANGED on purpose. It is not only the visit_key, it
  -- is the salt for every ottoq_sim_seeded_random draw below. Run scoping is done
  -- at the unique INDEX instead, so no draw moves and seed pinning survives.
  v_visit := p_vehicle_id::text || ':' || to_char(v_clock, 'YYYYMMDDHH24MISS');
  /* ══════════ 0055: THE DRAW SALT LEAVES THE ABSOLUTE-CLOCK DOMAIN ══════════
     v_visit embeds the ABSOLUTE sim clock, and (per the 0020 note above) it was
     also the salt for every seeded draw below — so two same-seed runs, anchored
     to different wall-clock starts, drew DIFFERENT manifests by construction
     (measured: re-certs #8/#9, tick-2 holding<->staged swaps with every SoC
     paired — the manifests decided the wash-triage verdicts). The fix splits
     the two roles 0020 fused: v_visit REMAINS the ledger key everywhere
     (visit_key upsert, rider-flag binding, carryover note, meta), while the
     draws move to v_salt — whole MINUTES since the run's own sim_clock_start
     (the 0045 domain; minutes not seconds, and GREATEST(0,…), so the tick-1
     arrival batch — whose v_clock is the reset's wall clock, fractionally
     BEFORE sim_clock_start — lands in bucket 0 in every run instead of
     straddling a second boundary). No-run callers keep the old absolute salt
     verbatim, so live behavior is unchanged where there is no run to key on. */
  v_salt := p_vehicle_id::text || ':' ||
            COALESCE((SELECT GREATEST(0, floor(EXTRACT(EPOCH FROM (v_clock - r.sim_clock_start)) / 60.0))::text
                        FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run),
                     to_char(v_clock, 'YYYYMMDDHH24MISS'));
  v_sim_day := (v_clock::date - DATE '2020-01-01');

  IF v_run IS NOT NULL AND v_plan IS NOT NULL THEN
    v_precip_stress := COALESCE((ottoq_twin_climate_stress(v_run, v_sim_day)->>'precip_stress')::numeric, 0);
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
  v_band_lo := COALESCE((v_plan->>'confirm_band_lo')::numeric, 0.40);
  v_band_hi := COALESCE((v_plan->>'confirm_band_hi')::numeric, 0.75);

  -- ===== URGENCY (time-of-day shaped; fault overrides to tech_hold) =====
  v_fault := ottoq_sim_seeded_random(v_seed, v_salt || ':fault') < COALESCE((v_plan->>'fault_repair_p')::numeric, 0.02);
  v_hour := EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int;
  IF v_fault THEN
    v_urgency := 'tech_hold';
  ELSIF v_hour >= 22 OR v_hour < 4 THEN
    v_urgency := CASE WHEN ottoq_sim_seeded_random(v_seed, v_salt || ':urg')
                        < COALESCE((v_plan->>'overnight_hold_p_night')::numeric, 0.75)
                 THEN 'overnight_hold' ELSE 'standard' END;
  ELSE
    v_urgency := CASE WHEN ottoq_sim_seeded_random(v_seed, v_salt || ':urg')
                        < COALESCE((v_plan->>'immediate_dispatch_p_day')::numeric, 0.30)
                 THEN 'immediate_dispatch' ELSE 'standard' END;
  END IF;
  v_due := CASE v_urgency
    WHEN 'immediate_dispatch' THEN v_clock + interval '45 minutes'
    WHEN 'overnight_hold' THEN
      (((v_clock AT TIME ZONE 'America/Chicago')::date
        + CASE WHEN v_hour >= 4 THEN 1 ELSE 0 END) + time '07:00') AT TIME ZONE 'America/Chicago'
    ELSE NULL END;
  BEGIN
    SELECT min_soc_at_deployment_pct INTO v_sla_floor
      FROM ottoq_get_active_sla((SELECT fleet_operator_id FROM vehicles WHERE id = p_vehicle_id));
  EXCEPTION WHEN OTHERS THEN v_sla_floor := NULL; END;
  v_sla_floor := COALESCE(v_sla_floor, 80);
  v_visit_target := CASE WHEN v_urgency = 'immediate_dispatch'
                         THEN GREATEST(v_sla_floor + 5, 70) ELSE v_target END;

  v_pm_prog    := CASE WHEN COALESCE(v_pm_int,0)    > 0 THEN COALESCE(v_wear.km_since_pm,0)   / v_pm_int    ELSE 0 END;
  v_calib_prog := CASE WHEN COALESCE(v_calib_int,0) > 0 THEN COALESCE(v_wear.h_since_calib,0) / v_calib_int ELSE 0 END;
  v_wash_min  := GREATEST(8, LEAST(10, round(9 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'wash_time',        v_salt, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1))))::int;
  v_deep_min  := GREATEST(12, round(20 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'detail_time',      v_salt, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_pm_min    := GREATEST(20, round(40 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'maintenance_time', v_salt, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;
  IF v_soc < v_visit_target - 1 THEN
    v_charge_min := GREATEST(8, round(COALESCE(
      ottoq_estimate_charge_minutes(v_soc, v_visit_target, 150, COALESCE(v_inlet_kw,150),
                                    COALESCE(v_cap,75), 25, COALESCE(v_soh,95),
                                    GREATEST(0.2, (CASE WHEN v_run IS NULL THEN 1.0 ELSE ottoq_profile_rate_mult(v_run,'charge_time') END)
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

  v_insp_p := CASE WHEN v_is_night
                   THEN COALESCE((v_plan->>'night_interior_inspection_p')::numeric, 0.95)
                   ELSE COALESCE((v_plan->>'day_interior_inspection_p')::numeric, 0.93) END;
  IF ottoq_sim_seeded_random(v_seed, v_salt || ':insp') < v_insp_p THEN
    v_m := v_m || jsonb_build_object('svc','interior_inspection','must_do',true,'deferrable',false,
      'est_min', (3 + round(2 * ottoq_sim_seeded_random(v_seed, v_salt || ':inspmin')))::int,
      'concurrency','cabin','at_charge_stall',true);
  END IF;

  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'interior_tidy')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  IF ottoq_sim_seeded_random(v_seed, v_salt || ':tidy') < v_p THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_salt || ':tidyconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','interior_tidy','must_do',true,'deferrable',false,
      'est_min', (3 + round(2 * ottoq_sim_seeded_random(v_seed, v_salt || ':tidymin')))::int,
      'concurrency','cabin','confidence',v_conf,
      'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_salt || ':item') < COALESCE((v_plan->>'item_retrieval_p')::numeric, 0.06) THEN
    v_m := v_m || jsonb_build_object('svc','item_retrieval','must_do',true,'deferrable',false,
      'est_min',4,'concurrency','cabin','confidence',1.0,'confirm_required',false);
  END IF;
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'sensor_clean')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  IF ottoq_sim_seeded_random(v_seed, v_salt || ':sclean') < v_p THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_salt || ':scleanconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','sensor_clean','must_do',true,'deferrable',false,
      'est_min',5,'concurrency','exterior','confidence',v_conf,
      'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_salt || ':diag') < COALESCE((v_plan->>'remote_diagnostics_p')::numeric, 0.05) THEN
    v_m := v_m || jsonb_build_object('svc','remote_diagnostics','must_do',false,'deferrable',true,
      'est_min',5,'concurrency','digital');
  END IF;
  v_ota := ottoq_sim_seeded_random(v_seed, 'ota_wave:' || v_sim_day::text) < COALESCE((v_plan->>'ota_wave_daily_p')::numeric, 0.08);
  IF v_ota THEN
    v_m := v_m || jsonb_build_object('svc','software_update','must_do',false,'deferrable',true,
      'est_min', 15 + floor(ottoq_sim_seeded_random(v_seed, v_salt || ':otamin') * 30)::int,
      'concurrency','digital','blocks_dispatch_while_running',true);
  END IF;
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'interior_deep_clean')::numeric * (1 + v_boost * 0.5)));
  -- 0083: deep-clean fires on a dirty cabin (must_do) OR the normal cadence draw (deferrable).
  -- A soiled/biohazard cabin is real work the card already flags; the manifest must materialize
  -- the atom or the vehicle deploys dirty. Promoted to must_do here, matching the card.
  IF v_deep_clean_due OR ottoq_sim_seeded_random(v_seed, v_salt || ':deep') < v_p THEN
    v_m := v_m || jsonb_build_object('svc','interior_deep_clean',
      'must_do', v_deep_clean_due, 'deferrable', NOT v_deep_clean_due,
      'est_min',v_deep_min,'concurrency','bay','requires_bay','detail','carryover_eligible',true);
  END IF;

  -- 0082: compute the hours-clock overdue flag from the profile read earlier.
  v_wash_ratio := CASE WHEN v_last_wash IS NULL OR COALESCE(v_wash_int,0) <= 0
                       THEN NULL
                       ELSE EXTRACT(EPOCH FROM (v_clock - v_last_wash)) / 3600.0 / v_wash_int END;
  v_wash_overdue := COALESCE(v_wash_ratio, 0) >= COALESCE(
                      (SELECT c.overdue_ratio FROM public.service_cadence_policy c
                        WHERE c.svc = 'exterior_wash' AND c.is_active), 1.25);

  -- 0083: a soiled/biohazard cabin is must-clean on THIS arrival. Same condition the card
  -- grades cabin_urgency by (soiled->overdue, biohazard->critical). NULL-safe: no profile row
  -- => false, and the random-draw gate below still applies for normal cadence deep-cleans.
  v_deep_clean_due := COALESCE(v_cabin_cond IN ('soiled','biohazard'), false);

  -- exterior wash (rain OR cadence, deferrable, precedes calibration)
  -- ==========================================================================
  -- PATH 1 GATE -- UNCHANGED BY 0018. Wash is EVERY 3rd NIGHT and only at night.
  -- The rotation is a calendar third of the fleet per night, so each vehicle
  -- washes every 3rd day. 0018 changed only WHERE wash_group comes from (it is
  -- now redrawn per run from the run seed in ottoq_run_boot_draw), not this gate.
  -- Exceptions preserved verbatim: a visibly dirty vehicle is washed off-rotation,
  -- and a long backstop catches anything the rotation missed.
  -- ==========================================================================
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'exterior_wash')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  IF (v_is_night
       AND COALESCE((SELECT (config->>'wash_group')::int FROM vehicles WHERE id = p_vehicle_id),
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3)) = (v_sim_day % 3))
     OR v_soil >= COALESCE((v_plan->>'wash_soil_override')::numeric, 0.75)
     OR v_cycles >= COALESCE((v_plan->>'wash_backstop_cycles')::int, 9)
     -- 0082: HOURS-CLOCK BACKSTOP. A vehicle whose wash cadence has lapsed to
     -- OVERDUE on the hours clock washes NOW, regardless of night/rotation. This is the
     -- SAME signal needs_card grades wash_urgency by, so the card and the manifest can
     -- never again disagree about whether a wash is due. Overdue = failure state, never
     -- a trigger: wash it on THIS arrival rather than leave it for a rotation that may
     -- be days away. NULL-safe: no profile row => no override.
     OR v_wash_overdue THEN
    v_m := v_m || jsonb_build_object('svc','exterior_wash','must_do',false,'deferrable',true,
      'est_min',v_wash_min,'concurrency','bay','requires_bay','wash_bay','carryover_eligible',true);
  END IF;

  -- ==========================================================================
  -- 0018 PATH 2 -- RIDER-FLAGGED CLEANING, RESHAPED BY 0020.
  --
  -- 0019 wrote the flag to 'recalled' RIGHT HERE, in the middle of assembling a
  -- manifest, ~120 lines before any visit row existed to carry it. That ordering
  -- is what made the failure silent: the ledger recorded "handled" against a
  -- visit_key that was still only a string in a variable, and nothing downstream
  -- could tell whether the row that key named was this run's or a previous run's.
  --
  -- 0020 SPLITS THE STEP: this block only READS the flag and shapes the atom.
  -- The flag transition happens after the upsert, against the visit_id the
  -- database actually returned. See section (0020 CONSUME) below.
  -- ==========================================================================
  IF v_run IS NOT NULL THEN
    SELECT f.flag_id, f.flag_kind, f.status, f.recalled_visit_key, f.recalled_visit_id
      INTO v_rf_id, v_rf_kind, v_rf_status, v_rf_visit, v_rf_prev_visit_id
      FROM public.ottoq_rider_cleaning_flags f
     WHERE f.sim_run_id = v_run AND f.vehicle_id = p_vehicle_id
       AND f.status IN ('pending','recalled')
       AND f.raised_at_sim_clock <= v_clock;

    IF v_rf_id IS NOT NULL THEN
      -- TOTAL: 'exterior' takes the wash lane; interior AND anything unrecognised
      -- takes the detail lane. An unknown word must never silently drop the work.
      IF v_rf_kind = 'exterior' THEN
        v_rf_svc := 'exterior_wash'; v_rf_min := v_wash_min;
      ELSE
        v_rf_svc := 'interior_deep_clean'; v_rf_min := v_deep_min;
      END IF;

      -- RETIRE-OR-PLACE, decided by uuid instead of by string comparison.
      -- 0019 asked "is the key I just rebuilt different from the key stored on the
      -- flag?" -- two strings from two clock domains and two runs, compared as if
      -- they named the same thing. The question it MEANT to ask is "is the visit
      -- row this call is about to write the same ROW that already consumed this
      -- flag?", so ask that: look up the row this upsert will land on, on the same
      -- run-scoped unique index the upsert infers.
      --
      -- Decided HERE, before the atom is shaped, and not after the upsert. Placing
      -- first and retiring afterwards would leave a must_do, non-deferrable
      -- cleaning stranded on the new visit that nothing will ever clear -- and
      -- ALWAYS HOLD would then keep a clean car in the depot indefinitely.
      SELECT n.visit_id INTO v_this_visit_id
        FROM ottoq_visit_needs n
       WHERE n.vehicle_id = p_vehicle_id
         AND n.visit_key  = v_visit
         AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
           = COALESCE(v_run,        '00000000-0000-0000-0000-000000000000'::uuid);

      IF v_rf_status = 'recalled'
         AND v_rf_prev_visit_id IS NOT NULL
         AND v_rf_prev_visit_id IS DISTINCT FROM v_this_visit_id THEN
        -- A different visit already took this cleaning. Retire the flag; do not
        -- re-emit the atom, or the car gets washed twice and held for the second.
        v_rf_retire := true;
        v_rf_status := 'served';
      ELSE
        v_rf_place  := true;
        v_rf_status := 'recalled';
      END IF;
    END IF;

    IF v_rf_place THEN
      -- If the routine draw already put this atom on the visit, PROMOTE it to
      -- must_do rather than adding a duplicate; otherwise append it.
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

  IF v_is_night
     AND ottoq_sim_seeded_random(v_seed, v_salt || ':walkaround')
         < COALESCE((v_plan->>'night_walkaround_p')::numeric, 0.90) THEN
    v_m := v_m || jsonb_build_object('svc','perimeter_walkaround','must_do',true,'deferrable',false,
      'est_min', (10 + round(5 * ottoq_sim_seeded_random(v_seed, v_salt || ':walkmin')))::int,
      'concurrency','hold','at_perimeter',true);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_salt || ':calib') < LEAST(0.95, (v_probs->>'sensor_calibration')::numeric
        * CASE WHEN v_calib_prog >= 1.0 THEN 12 WHEN v_calib_prog >= 0.8 THEN 4 ELSE 0.5 END) THEN
    v_m := v_m || jsonb_build_object('svc','sensor_calibration','must_do',false,'deferrable',true,
      'est_min',v_calib_min,'slot','dedicated_service','concurrency','bay','requires_bay','service_bay',
      'predecessors',jsonb_build_array('exterior_wash'),'carryover_eligible',true);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_salt || ':pm') < LEAST(0.95, (v_probs->>'mechanical_pm')::numeric
        * CASE WHEN v_pm_prog >= 1.0 THEN 12 WHEN v_pm_prog >= 0.8 THEN 4 ELSE 0.5 END) THEN
    v_m := v_m || jsonb_build_object('svc','mechanical_pm','must_do',false,'deferrable',true,
      'est_min',v_pm_min,'concurrency','bay','requires_bay','service_bay','carryover_eligible',true);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_salt || ':cosmetic') < (v_probs->>'cosmetic_repair')::numeric THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_salt || ':cosconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','cosmetic_repair','must_do',false,'deferrable',true,
      'est_min',60,'disposition','offline_candidate','concurrency','bay','requires_bay','service_bay',
      'confidence',v_conf,'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi,
      'carryover_eligible',true);
  END IF;
  IF v_fault THEN
    v_m := v_m || jsonb_build_object('svc','fault_repair','must_do',true,'deferrable',false,
      'est_min', 30 + floor(ottoq_sim_seeded_random(v_seed, v_salt || ':faultmin') * 90)::int,
      'concurrency','bay','requires_bay','service_bay','requires_tech_greenlight',true);
  END IF;

  -- ===== CARRYOVER =====
  SELECT visit_id, atoms INTO v_carry_visit, v_carry
    FROM ottoq_visit_needs
   WHERE vehicle_id = p_vehicle_id AND status = 'carried_over'
   ORDER BY created_at DESC LIMIT 1;
  IF v_carry IS NOT NULL THEN
    FOR v_atom IN SELECT * FROM jsonb_array_elements(v_carry) LOOP
      IF COALESCE((v_atom->>'carryover_eligible')::boolean, false)
         AND NOT COALESCE((v_atom->>'done')::boolean, false)
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_atom->>'svc') THEN
        v_m := v_m || (v_atom || jsonb_build_object('carried',true));
      END IF;
    END LOOP;
    UPDATE ottoq_visit_needs SET status = 'complete',
           meta = COALESCE(meta,'{}'::jsonb) || jsonb_build_object('carryover_consumed_by', v_visit)
     WHERE visit_id = v_carry_visit;
  END IF;

  v_archetype := CASE
    WHEN v_fault THEN 'E_tech_hold_fault'
    -- 0018: a rider-flagged recall is its own archetype, so the visit is legible
    -- as "this car came back because a customer complained", not as a mystery.
    WHEN v_rf_id IS NOT NULL AND v_rf_status = 'recalled' THEN 'R_rider_flag_cleaning'
    WHEN v_ota THEN 'J_ota_wave'
    WHEN v_urgency = 'overnight_hold' THEN 'C_overnight'
    WHEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'charge') THEN 'M_pass_through_or_P_triage'
    WHEN v_urgency = 'immediate_dispatch'
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'interior_tidy') THEN 'A_charge_clean_go'
    WHEN v_urgency = 'immediate_dispatch' THEN 'D_charge_and_go'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'mechanical_pm') THEN 'B_full_service'
    ELSE 'std_mixed' END;

  UPDATE ottoq_visit_needs SET status = 'superseded'
   WHERE vehicle_id = p_vehicle_id AND status IN ('open','in_progress');
  -- 0020: the conflict target is now the RUN-SCOPED index. Two runs walking the
  -- same sim clock produce two visits, not one row overwritten by the other.
  -- RETURNING gives the atomic step below a real uuid to bind the flag to.
  INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key,
                                 archetype, urgency, dispatch_due_at, target_soc, atoms, meta)
  VALUES (p_vehicle_id, v_run, v_depot, v_clock, v_visit,
          v_archetype, v_urgency, v_due, v_visit_target, v_m,
          jsonb_build_object('plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
                             'crn', v_run IS NOT NULL, 'precip_stress', round(v_precip_stress,3),
                             'wet_boost', round(v_boost,3), 'soc_at_arrival', v_soc,
                             'sla_floor', v_sla_floor, 'generator', 'v4_condition',
                             'rider_flagged', (v_rf_id IS NOT NULL AND v_rf_status = 'recalled'),
                             'rider_flag_kind', v_rf_kind))
  ON CONFLICT (vehicle_id, visit_key, (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  DO UPDATE
    SET atoms = EXCLUDED.atoms, urgency = EXCLUDED.urgency, archetype = EXCLUDED.archetype,
        dispatch_due_at = EXCLUDED.dispatch_due_at, target_soc = EXCLUDED.target_soc,
        meta = EXCLUDED.meta, status = 'open'
  RETURNING visit_id INTO v_visit_id;

  -- ══════════════════ 0020 CONSUME -- ONE ATOMIC STEP ══════════════════
  -- The visit row now EXISTS and carries the atom. Only now may the flag say it
  -- has been handled, and it says so by pointing at that row's visit_id.
  --
  -- The place-or-retire decision was already taken, by uuid, above. All that is
  -- left is to record it against the row the database just handed back. If the
  -- upsert somehow returned nothing, the flag is NOT touched: it stays 'pending'
  -- and is re-offered next tick. Failing to consume is recoverable; consuming
  -- without placing is the defect.
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

  UPDATE vehicles SET config = jsonb_set(
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
        'generator', 'v4_condition'))
   WHERE id = p_vehicle_id;
  RETURN v_m;
END;
$function$
