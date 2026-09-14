-- migration-version: PENDING
-- migration-name:    0286_eleven_dials_and_the_ceiling_a_check_constraint_hands_you
--
-- 0286  ELEVEN MORE DIALS, AND THREE THAT ARE ONE SWITCH
--
-- Fourth file under the rule from 0282: READ THE RANGE OFF THE CONSUMER, NEVER
-- CHOOSE IT. Eleven keys, 17 live rows. Nothing new in method; what is new is
-- one derivation shape this batch adds and one trap it walks past twice.
--
-- ---------------------------------------------------------------------------
-- THE SHAPE THIS BATCH ADDS: A CEILING HANDED OVER BY A CHECK CONSTRAINT ON
-- THE OTHER SIDE OF A LEAST()
--
-- public.ottoq_target_soc_cap is a pure CASE over three dials, and both twin
-- consumers use it identically:
--
--   v_target_soc := LEAST(COALESCE(v_vehicle.target_soc, ottoq_default_target_soc()),
--                         public.ottoq_target_soc_cap(stall_type, at));
--
-- The left operand is vehicles.target_soc, which carries
--   CHECK ((target_soc >= 20) AND (target_soc <= 100)).
-- A cap above 100 therefore binds NOTHING -- the LEAST always picks the other
-- side -- so every value over 100 is behaviourally identical to 100. That is a
-- ceiling read off a constraint the dial never touches, reached through the
-- operator that compares them. min 0 is the weaker half and is labelled as
-- such in each row: it is the SoC scale's floor (the 0..100 that 0282 pinned in
-- ottoq_recall_naive_threshold_v1), not a bound this consumer declares.
--
-- All three are catalogued together because ONE CASE chooses between them --
-- the same reason 0283 catalogued the night window as a pair and 0285 the two
-- tick caps. A switch with one arm catalogued is worse than none.
--
-- ---------------------------------------------------------------------------
-- THE TRAP, WALKED PAST TWICE MORE
--
-- twin.ottoq_sim_advance_wear_counters clamps its RESULTS, not its dials:
--
--   soil accrual: LEAST(1.0, GREATEST(0, km_tick * v_soil_rate * scalar
--                                        * (1 + v_precip * v_precip_coup)))
--   soil decay:   soil_index = LEAST(1.0, GREATEST(0, ...
--                                - (v_soil_decay * tick_minutes / 30.0)))
--
-- Writing 1.0 into max_value for soil_rate_per_km or soil_decay_per_tick would
-- be the same mistake 0285 avoided with litter_p_per_active_min's 0.95: the
-- clamp is on the product, the saturation point divides by km_tick or
-- tick_minutes, and both are runtime. All three soil dials therefore take
-- min 0 and MAX NULL.
--
-- min 0 for each is read off what a negative would do, and each is different:
--   soil_rate_per_km      GREATEST(0, ...) already makes a negative rate zero
--   soil_decay_per_tick   a negative DECAY adds soil, inverting the name
--   precip_soil_coupling  a negative coupling makes rain clean the vehicle
--
-- AND ONE NAME, TWO SOURCES, TWO DEFAULTS -- recorded because it looks like a
-- bug and is not: twin.ottoq_sim_observe_asset reads precip_soil_coupling from
-- the PLAN (v_plan->>'precip_soil_coupling', default 0.6), not from the policy
-- layer at all. The dial catalogued here is the policy one, default 0.5. They
-- are different inputs that happen to share a name, and the catalog row says so
-- rather than implying the 0.6 is a second live value of this key.
--
-- ---------------------------------------------------------------------------
-- THE REST, BY THE DERIVATION ALREADY ESTABLISHED
--
--   pm_interval_km            min 1, max NULL   the calib_interval_h shape
--                             exactly: ottoq_scenario_apply_fleet_overrides
--                             writes GREATEST(1, round(pm_raw * scale)), and
--                             ottoq_twin_wear_window DIVIDES by it and guards
--                             pm_interval_km = 0. Two independent floors of 1.
--
--   wash_soil_threshold       [0, 1]            the sensor_soil_threshold shape
--                             exactly: compared with >= against
--                             ottoq_vehicle_wear.soil_index, which carries
--                             CHECK (soil_index >= 0 AND soil_index <= 1).
--
--   allow_concurrent_runs     [0, 1]            twin.ottoq_sim_start_run tests
--                             ottoq_policy_get(NULL,'allow_concurrent_runs',0) < 1
--   enforce_site_charge_cap   [0, 1]            ottoq_decide_tick tests
--                             ottoq_policy_get(run,'enforce_site_charge_cap',1) >= 1
--                             Both are boolean gates: one value on each side of
--                             the test is all the engine can distinguish.
--
--   p99_burn_pct_per_min      min 0, max NULL   ottoq_recall_naive_threshold_v1:
--                             v_burn_guard := rate * (v_eta_min + p_horizon_min),
--                             then IF v_soc <= v_reserve + v_burn_guard. A
--                             negative rate would pull the recall trigger BELOW
--                             the reserve it is meant to protect -- the same
--                             inversion 0282 rejected for reserve_margin_pct.
--                             No constant ceiling: saturation depends on the
--                             ETA and the horizon, both runtime.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0286 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0286 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0286 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0286 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. PREMISE + THE forces_recert=false ARGUMENT -----------------------------
DO $p0$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('pm_interval_km','wash_soil_threshold','allow_concurrent_runs',
                       'enforce_site_charge_cap','p99_burn_pct_per_min','soil_rate_per_km',
                       'soil_decay_per_tick','precip_soil_coupling','dcfc_target_soc_day',
                       'dcfc_target_soc_night','l2_target_soc');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0286 P0: % of the eleven keys are already catalogued', v_n;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get';
  IF v_src IS NULL OR position('ottoq_policy_param_catalog' in v_src) > 0 THEN
    RAISE EXCEPTION '0286 P0: ottoq_policy_get is missing or now reads the catalog';
  END IF;
  RAISE NOTICE '0286 P0: eleven keys uncatalogued; the read path still ignores the catalog';
END $p0$;

-- P1. pm_interval_km IS STILL FLOORED AT 1 AND GUARDED AS A DIVISOR ----------
DO $p1$
DECLARE v_ovr text; v_win text;
BEGIN
  SELECT p.prosrc INTO v_ovr FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_scenario_apply_fleet_overrides';
  SELECT p.prosrc INTO v_win FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_twin_wear_window';
  IF v_ovr IS NULL OR v_win IS NULL THEN
    RAISE EXCEPTION '0286 P1: a pm_interval_km consumer is missing';
  END IF;
  IF position('''pm_interval_km'',   GREATEST(1, round(t.pm_raw  * v_pm))' in v_ovr) = 0 THEN
    RAISE EXCEPTION '0286 P1: the override path no longer floors pm_interval_km at 1';
  END IF;
  IF position('pm_interval_km = 0 THEN NULL' in v_win) = 0 THEN
    RAISE EXCEPTION '0286 P1: the wear window no longer guards pm_interval_km = 0 as a '
                    'divisor; the second half of the min-1 argument is gone';
  END IF;
  RAISE NOTICE '0286 P1: pm_interval_km floored at 1 and still guarded against 0';
END $p1$;

-- P2. wash_soil_threshold IS STILL COMPARED AGAINST A [0,1] COLUMN -----------
DO $p2$
DECLARE v_def text; v_src text;
BEGIN
  SELECT pg_get_constraintdef(con.oid) INTO v_def
    FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
   WHERE rel.relname = 'ottoq_vehicle_wear'
     AND con.conname = 'ottoq_vehicle_wear_soil_index_check';
  IF v_def IS NULL
     OR position('soil_index >= (0)::numeric' in v_def) = 0
     OR position('soil_index <= (1)::numeric' in v_def) = 0 THEN
    RAISE EXCEPTION '0286 P2: soil_index no longer runs [0,1]; wash_soil_threshold''s '
                    'range is derived from that constraint and must be re-read';
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_recall_naive_threshold_v1';
  IF position('v_wash_soil' in v_src) = 0 THEN
    RAISE EXCEPTION '0286 P2: ottoq_recall_naive_threshold_v1 no longer reads a wash '
                    'soil threshold at all';
  END IF;
  RAISE NOTICE '0286 P2: wash_soil_threshold is compared against a CHECK-bounded [0,1] column';
END $p2$;

-- P3. BOTH BOOLEAN GATES ARE STILL GATES -------------------------------------
DO $p3$
DECLARE v_start text; v_dec text;
BEGIN
  SELECT p.prosrc INTO v_start FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_run';
  SELECT p.prosrc INTO v_dec FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  IF v_start IS NULL OR v_dec IS NULL THEN
    RAISE EXCEPTION '0286 P3: a gate consumer is missing';
  END IF;
  IF position('''allow_concurrent_runs'', 0) < 1' in v_start) = 0 THEN
    RAISE EXCEPTION '0286 P3: allow_concurrent_runs is no longer a < 1 gate';
  END IF;
  IF position('''enforce_site_charge_cap'', 1) >= 1' in v_dec) = 0 THEN
    RAISE EXCEPTION '0286 P3: enforce_site_charge_cap is no longer a >= 1 gate';
  END IF;
  RAISE NOTICE '0286 P3: both gates still test one threshold; [0,1] is all either distinguishes';
END $p3$;

-- P4. THE BURN GUARD STILL MULTIPLIES A RATE BY A HORIZON --------------------
DO $p4$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_recall_naive_threshold_v1';
  IF position('v_burn_guard := v_burn_per_min * (v_eta_min + p_horizon_min)' in v_src) = 0 THEN
    RAISE EXCEPTION '0286 P4: the burn guard is no longer rate * (eta + horizon); '
                    'both of p99_burn_pct_per_min''s bounds come from that shape';
  END IF;
  IF position('v_soc <= v_reserve + v_burn_guard' in v_src) = 0 THEN
    RAISE EXCEPTION '0286 P4: the burn guard is no longer added to the reserve SoC';
  END IF;
  RAISE NOTICE '0286 P4: burn guard = rate * (eta + horizon), added to the reserve';
END $p4$;

-- P5. THE THREE SOIL DIALS STILL FEED CLAMPED PRODUCTS -----------------------
-- The clamps are on the RESULTS. This pin is what stops a later reader
-- concluding that 1.0 belongs in max_value.
DO $p5$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_wear_counters';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0286 P5: twin.ottoq_sim_advance_wear_counters does not exist';
  END IF;
  IF position('LEAST(1.0, GREATEST(0, c.km_tick * v_soil_rate' in v_src) = 0 THEN
    RAISE EXCEPTION '0286 P5: the soil accrual product is no longer clamped as '
                    'LEAST(1.0, GREATEST(0, km_tick * rate * ...)); soil_rate_per_km''s '
                    'NULL ceiling rests on the clamp being on the PRODUCT';
  END IF;
  IF position('(v_soil_decay * COALESCE(p_tick_minutes, 30) / 30.0)' in v_src) = 0 THEN
    RAISE EXCEPTION '0286 P5: the soil decay term changed shape';
  END IF;
  IF position('(1 + v_precip * v_precip_coup)' in v_src) = 0 THEN
    RAISE EXCEPTION '0286 P5: the precipitation coupling is no longer a (1 + precip*coup) '
                    'multiplier';
  END IF;
  RAISE NOTICE '0286 P5: all three soil dials still feed products clamped at the result';
END $p5$;

-- P6. THE TARGET-SOC TRIO IS STILL A LEAST AGAINST A [20,100] COLUMN ---------
DO $p6$
DECLARE v_cap text; v_adv text; v_def text;
BEGIN
  SELECT p.prosrc INTO v_cap FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_target_soc_cap';
  IF v_cap IS NULL THEN
    RAISE EXCEPTION '0286 P6: ottoq_target_soc_cap does not exist';
  END IF;
  IF position('''dcfc_target_soc_day''' in v_cap) = 0
     OR position('''dcfc_target_soc_night''' in v_cap) = 0
     OR position('''l2_target_soc''' in v_cap) = 0 THEN
    RAISE EXCEPTION '0286 P6: ottoq_target_soc_cap no longer chooses between all three '
                    'dials; they are catalogued here as one switch';
  END IF;
  SELECT p.prosrc INTO v_adv FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_charge_sessions';
  IF v_adv IS NULL OR position('LEAST(COALESCE(v_vehicle.target_soc' in v_adv) = 0 THEN
    RAISE EXCEPTION '0286 P6: the cap is no longer applied as a LEAST against '
                    'vehicles.target_soc; max 100 is derived from that comparison';
  END IF;
  SELECT pg_get_constraintdef(con.oid) INTO v_def
    FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
   WHERE rel.relname = 'vehicles' AND con.conname = 'vehicles_target_soc_check';
  IF v_def IS NULL OR position('target_soc <= 100' in v_def) = 0 THEN
    RAISE EXCEPTION '0286 P6: vehicles.target_soc is no longer CHECK-bounded at 100; '
                    'the trio''s ceiling comes from that constraint';
  END IF;
  RAISE NOTICE '0286 P6: the cap is a LEAST against a column CHECK-bounded at 100';
END $p6$;

-- P7. EVERY LIVE ROW IS INSIDE THE RANGES THIS FILE DECLARES -----------------
DO $p7$
DECLARE v_n int; v_bad int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('pm_interval_km','wash_soil_threshold','allow_concurrent_runs',
                       'enforce_site_charge_cap','p99_burn_pct_per_min','soil_rate_per_km',
                       'soil_decay_per_tick','precip_soil_coupling','dcfc_target_soc_day',
                       'dcfc_target_soc_night','l2_target_soc');
  IF v_n <> 17 THEN
    RAISE EXCEPTION '0286 P7: expected the 17 measured live rows across the eleven keys, '
                    'found % -- somebody wrote these dials since the measurement', v_n;
  END IF;
  SELECT count(*) INTO v_bad FROM public.ottoq_policy_params
   WHERE (param_key = 'pm_interval_km' AND param_value < 1)
      OR (param_key = 'wash_soil_threshold' AND (param_value < 0 OR param_value > 1))
      OR (param_key IN ('allow_concurrent_runs','enforce_site_charge_cap')
          AND (param_value < 0 OR param_value > 1))
      OR (param_key IN ('dcfc_target_soc_day','dcfc_target_soc_night','l2_target_soc')
          AND (param_value < 0 OR param_value > 100))
      OR (param_key IN ('p99_burn_pct_per_min','soil_rate_per_km','soil_decay_per_tick',
                        'precip_soil_coupling') AND param_value < 0);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0286 P7: % live row(s) fall outside the ranges this file declares', v_bad;
  END IF;
  RAISE NOTICE '0286 P7: 17 live rows, all inside the declared ranges';
END $p7$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES
('pm_interval_km',
 '0286: kilometres between preventive-maintenance visits, used as the fallback when a vehicle''s own config carries none (public.ottoq_recall_naive_threshold_v1 reads config first, this dial second). min_value 1 is stated twice by the engine, exactly as calib_interval_h''s is: public.ottoq_scenario_apply_fleet_overrides writes it as GREATEST(1, round(pm_raw * scale)), and public.ottoq_twin_wear_window DIVIDES by it and guards pm_interval_km = 0 explicitly. MAX NULL: nothing caps a PM interval above. 0286 P1 pins both.',
 8000, 1, NULL, 'public.ottoq_recall_naive_threshold_v1, public.ottoq_scenario_apply_fleet_overrides, public.ottoq_twin_wear_window'),
('wash_soil_threshold',
 '0286: the soil level at or above which an asset is judged to need an exterior wash -- the wash-lane sibling of sensor_soil_threshold (0282), and derived identically. Compared with >= against ottoq_vehicle_wear.soil_index by public.ottoq_recall_naive_threshold_v1, and that column carries CHECK (soil_index >= 0 AND soil_index <= 1), so outside [0,1] the comparison is constant. 0286 P2 pins the constraint.',
 0.50, 0, 1, 'public.ottoq_recall_naive_threshold_v1'),
('allow_concurrent_runs',
 '0286: whether twin.ottoq_sim_start_run will start a run while another is already running. Tested as ottoq_policy_get(NULL, ''allow_concurrent_runs'', 0) < 1, so it is a boolean gate and [0,1] is the whole of what the engine can distinguish -- 0 refuses, anything at or above 1 permits. Read at GLOBAL scope (the NULL first argument), so a run-scoped row for it would never be consulted. 0286 P3 pins the test.',
 0, 0, 1, 'twin.ottoq_sim_start_run'),
('enforce_site_charge_cap',
 '0286: whether public.ottoq_decide_tick applies the site power cap when choosing a charge stall (0132''s gate). Tested as ottoq_policy_get(run, ''enforce_site_charge_cap'', 1) >= 1 -- a boolean gate, so [0,1]. NOTE the one live row is 0, at RUN scope: some run has the site cap switched OFF. That is a fact about the data, not something this file changes, and it is exactly the kind of row that could only ever have been written around the setter before now. 0286 P3 pins the test.',
 1, 0, 1, 'public.ottoq_decide_tick'),
('p99_burn_pct_per_min',
 '0286: assumed worst-case state-of-charge burn in percentage points per minute, used to size the recall guard. public.ottoq_recall_naive_threshold_v1 computes v_burn_guard := this * (v_eta_min + p_horizon_min) and then recalls when v_soc <= v_reserve + v_burn_guard. min_value 0 because a negative rate would pull the recall trigger BELOW the reserve it exists to protect -- the same inversion 0282 rejected for reserve_margin_pct. MAX NULL: the guard saturates only where the ETA and the horizon put it, both runtime. 0286 P4 pins the arithmetic.',
 0.25, 0, NULL, 'public.ottoq_recall_naive_threshold_v1'),
('soil_rate_per_km',
 '0286: soil accrued per kilometre driven, before per-vehicle and weather scaling. twin.ottoq_sim_advance_wear_counters accrues LEAST(1.0, GREATEST(0, km_tick * this * veh_soil_scalar * (1 + precip * coupling))). min_value 0 is that GREATEST -- a negative rate is already zero. MAX IS NULL AND 1.0 WOULD BE WRONG: the clamp is on the PRODUCT, so the dial saturates at 1 / (km_tick * scalars), which is runtime -- the same trap 0285 avoided with litter_p_per_active_min''s 0.95. 0286 P5 pins the product.',
 0.0016, 0, NULL, 'twin.ottoq_sim_advance_wear_counters'),
('soil_decay_per_tick',
 '0286: soil shed per 30-minute tick, scaled by the actual tick length -- twin.ottoq_sim_advance_wear_counters subtracts (this * COALESCE(p_tick_minutes,30) / 30.0) inside the same LEAST(1.0, GREATEST(0, ...)) that bounds soil_index. min_value 0 because a negative DECAY adds soil, which inverts the dial rather than setting it. MAX NULL for the same reason as soil_rate_per_km: the clamp is on the result, and the saturation point divides by the tick length. 0286 P5 pins the term.',
 0.010, 0, NULL, 'twin.ottoq_sim_advance_wear_counters'),
('precip_soil_coupling',
 '0286: how strongly precipitation multiplies soiling -- twin.ottoq_sim_advance_wear_counters applies (1 + v_precip * this) to both the soil accrual and the litter probability. min_value 0 because a negative coupling makes rain CLEAN the vehicle, inverting the mechanism the name describes. MAX NULL: the products it feeds are clamped at their results, not here. ONE NAME, TWO SOURCES, RECORDED BECAUSE IT LOOKS LIKE A BUG AND IS NOT: twin.ottoq_sim_observe_asset reads a field of the same name off the PLAN (v_plan->>''precip_soil_coupling'', default 0.6), not off the policy layer. That 0.6 is a different input, not a second live value of this key. 0286 P5 pins the multiplier.',
 0.5, 0, NULL, 'twin.ottoq_sim_advance_wear_counters'),
('dcfc_target_soc_day',
 '0286: the depot''s DAYTIME ceiling on how full a DC fast-charge plug will fill an asset -- public.ottoq_target_soc_cap returns it when the stall is dcfc and ottoq_is_depot_night is false. One of three dials chosen by ONE CASE in that function, catalogued together for the reason 0283 catalogued the night window as a pair. MAX 100 IS READ OFF A CONSTRAINT ON THE OTHER SIDE OF A LEAST: both twin consumers apply the cap as LEAST(COALESCE(vehicles.target_soc, default), cap), and vehicles.target_soc carries CHECK (target_soc >= 20 AND target_soc <= 100), so a cap above 100 binds nothing. min 0 is the weaker half and is the SoC scale''s floor (the 0..100 that 0282 pinned in ottoq_recall_naive_threshold_v1), not a bound this consumer declares. 0286 P6 pins the LEAST and the CHECK.',
 90, 0, 100, 'public.ottoq_target_soc_cap, public.ottoq_charge_plan_for_visit, twin.ottoq_sim_start_charge_session, twin.ottoq_sim_advance_charge_sessions'),
('dcfc_target_soc_night',
 '0286: the depot''s OVERNIGHT ceiling for a DC fast-charge plug -- the second arm of ottoq_target_soc_cap''s CASE, taken when the stall is dcfc and ottoq_is_depot_night is true. Identical derivation to dcfc_target_soc_day: max 100 from the CHECK on vehicles.target_soc reached through the LEAST, min 0 from the SoC scale. 0286 P6 pins both.',
 100, 0, 100, 'public.ottoq_target_soc_cap, public.ottoq_charge_plan_for_visit, twin.ottoq_sim_start_charge_session, twin.ottoq_sim_advance_charge_sessions'),
('l2_target_soc',
 '0286: the depot''s ceiling for any NON-dcfc plug -- ottoq_target_soc_cap''s ELSE arm, so it covers L2 and every other stall type the twin charges on. Third arm of the same CASE, same derivation: max 100 from the CHECK on vehicles.target_soc reached through the LEAST, min 0 from the SoC scale. 0286 P6 pins both.',
 100, 0, 100, 'public.ottoq_target_soc_cap, public.ottoq_charge_plan_for_visit, twin.ottoq_sim_start_charge_session, twin.ottoq_sim_advance_charge_sessions');

-- ---------------------------------------------------------------------------
-- A1. THE SETTER ACCEPTS ALL ELEVEN, UNCLAMPED, AT AN IN-RANGE VALUE.
DO $a1$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000028600aa'::uuid;
  v_r jsonb; k text; v numeric;
  v_probe CONSTANT jsonb := jsonb_build_object(
    'pm_interval_km', 9000, 'wash_soil_threshold', 0.6,
    'allow_concurrent_runs', 1, 'enforce_site_charge_cap', 1,
    'p99_burn_pct_per_min', 0.3, 'soil_rate_per_km', 0.002,
    'soil_decay_per_tick', 0.02, 'precip_soil_coupling', 0.7,
    'dcfc_target_soc_day', 85, 'dcfc_target_soc_night', 95,
    'l2_target_soc', 95);
BEGIN
  FOR k, v IN SELECT key, value::text::numeric FROM jsonb_each(v_probe) LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, v, '0286_proof');
    IF NOT COALESCE((v_r->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'A1 FAILED: the setter still refuses %: %', k, v_r;
    END IF;
    IF COALESCE((v_r->>'clamped')::boolean,true) THEN
      RAISE EXCEPTION 'A1 FAILED: % was clamped from an IN-RANGE probe value %: %', k, v, v_r;
    END IF;
    IF public.ottoq_policy_get(v_scratch, k, -1) <> v THEN
      RAISE EXCEPTION 'A1 FAILED: % did not read back as %', k, v;
    END IF;
  END LOOP;
  RAISE NOTICE 'A1 OK: all eleven keys write through the setter, unclamped, and read back';
END $a1$;

-- A2. EVERY DECLARED BOUND FIRES.
DO $a2$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028600aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'pm_interval_km', 0, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 1 THEN
    RAISE EXCEPTION 'A2 FAILED: pm 0 should clamp to 1 -- the wear window divides by '
                    'this: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'wash_soil_threshold', 9, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 1
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: wash soil 9 should clamp to 1 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'allow_concurrent_runs', 7, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 1 THEN
    RAISE EXCEPTION 'A2 FAILED: a gate set to 7 should clamp to 1: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'enforce_site_charge_cap', -3, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 0 THEN
    RAISE EXCEPTION 'A2 FAILED: a gate set to -3 should clamp to 0: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'dcfc_target_soc_day', 150, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 100
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: a target SoC of 150 should clamp to 100 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'l2_target_soc', -1, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 0 THEN
    RAISE EXCEPTION 'A2 FAILED: a target SoC of -1 should clamp to 0: %', v_r;
  END IF;
  RAISE NOTICE 'A2 OK: every declared bound in this file fires';
END $a2$;

-- A3. THE FOUR NULL CEILINGS IMPOSE NOTHING, AND EVERY FLOOR STILL DOES.
-- Proven on the soil dials specifically: a rate silently pinned to its floor
-- would turn a modelled wear process off and look like a quiet twin.
DO $a3$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028600aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'soil_rate_per_km', 40, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 40
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A3 FAILED: a NULL max_value must impose no ceiling -- and 1.0 in '
                    'particular must NOT be the ceiling here: %', v_r;
  END IF;
  IF (v_r->'safe_range'->>1) IS NOT NULL THEN
    RAISE EXCEPTION 'A3 FAILED: the receipt should report an open upper bound: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'soil_decay_per_tick', -1, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 0
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A3 FAILED: a negative decay must clamp to 0 -- it would add soil: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'p99_burn_pct_per_min', -0.5, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 0 THEN
    RAISE EXCEPTION 'A3 FAILED: a negative burn rate must clamp to 0: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'pm_interval_km', 500000, '0286_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 500000
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A3 FAILED: pm_interval_km has no ceiling and must not be clamped: %', v_r;
  END IF;
  RAISE NOTICE 'A3 OK: NULL ceilings impose nothing and every declared floor still fires';
END $a3$;

-- A4. EVERY DISTINCT LIVE VALUE PASSES THROUGH UNCHANGED.
DO $a4$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028600aa'::uuid; v_r jsonb;
        k text; v numeric; v_n int := 0;
BEGIN
  FOR k, v IN
    SELECT DISTINCT param_key, param_value FROM public.ottoq_policy_params
     WHERE param_key IN ('pm_interval_km','wash_soil_threshold','allow_concurrent_runs',
                         'enforce_site_charge_cap','p99_burn_pct_per_min','soil_rate_per_km',
                         'soil_decay_per_tick','precip_soil_coupling','dcfc_target_soc_day',
                         'dcfc_target_soc_night','l2_target_soc')
       AND updated_by <> '0286_proof'
  LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, v, '0286_proof');
    IF COALESCE((v_r->>'clamped')::boolean,true) THEN
      RAISE EXCEPTION 'A4 FAILED: the live value % = % was altered by the catalog: %',
                      k, v, v_r;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'A4 FAILED: no live values to re-offer; the check proved nothing';
  END IF;
  RAISE NOTICE 'A4 OK: all % distinct live values pass through unchanged', v_n;
END $a4$;

-- A5. THE SCRATCH IS GONE AND THE 17 LIVE ROWS SURVIVE.
DO $a5$
DECLARE v_n int;
BEGIN
  DELETE FROM public.ottoq_policy_params WHERE updated_by = '0286_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 11 THEN
    RAISE EXCEPTION 'A5 FAILED: expected to remove exactly 11 scratch rows, removed %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('pm_interval_km','wash_soil_threshold','allow_concurrent_runs',
                       'enforce_site_charge_cap','p99_burn_pct_per_min','soil_rate_per_km',
                       'soil_decay_per_tick','precip_soil_coupling','dcfc_target_soc_day',
                       'dcfc_target_soc_night','l2_target_soc');
  IF v_n <> 17 THEN
    RAISE EXCEPTION 'A5 FAILED: % rows remain across the eleven keys, expected the original 17', v_n;
  END IF;
  RAISE NOTICE 'A5 OK: scratch removed, the original 17 rows survive';
END $a5$;

-- A6. THE 0281 INSTRUMENT AGREES THE GAP SHRANK BY ELEVEN.
DO $a6$
DECLARE v_ok int; v_still int;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'ok'), count(*) FILTER (WHERE status <> 'ok')
    INTO v_ok, v_still
    FROM public.ottoq_policy_catalog_gap
   WHERE param_key IN ('pm_interval_km','wash_soil_threshold','allow_concurrent_runs',
                       'enforce_site_charge_cap','p99_burn_pct_per_min','soil_rate_per_km',
                       'soil_decay_per_tick','precip_soil_coupling','dcfc_target_soc_day',
                       'dcfc_target_soc_night','l2_target_soc');
  IF v_still > 0 THEN
    RAISE EXCEPTION 'A6 FAILED: % of the eleven still report a gap', v_still;
  END IF;
  IF v_ok <> 11 THEN
    RAISE EXCEPTION 'A6 FAILED: expected all eleven to report ok, found %', v_ok;
  END IF;
  RAISE NOTICE 'A6 OK: all eleven now report ok in ottoq_policy_catalog_gap';
END $a6$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0286_eleven_dials_and_the_ceiling_a_check_constraint_hands_you', false,
 'Eleven rows in ottoq_policy_param_catalog, every range read off a consumer. New derivation shape: the dcfc_target_soc_day / dcfc_target_soc_night / l2_target_soc trio takes max 100 from CHECK (target_soc <= 100) on vehicles.target_soc, reached through the LEAST that both twin charge consumers use to apply the cap -- a ceiling handed over by a constraint the dial never touches; min 0 is labelled the weaker half in each row (the SoC scale, not a declared bound). All three catalogued together because one CASE in ottoq_target_soc_cap chooses between them. Established shapes: pm_interval_km min 1 (GREATEST(1,...) in the override path plus a divisor guard in ottoq_twin_wear_window, identical to calib_interval_h); wash_soil_threshold [0,1] (compared against the CHECK-bounded soil_index, identical to sensor_soil_threshold); allow_concurrent_runs and enforce_site_charge_cap [0,1] (boolean gates); p99_burn_pct_per_min min 0 (a negative rate inverts the recall guard). The three soil dials -- soil_rate_per_km, soil_decay_per_tick, precip_soil_coupling -- take min 0 and MAX NULL because twin.ottoq_sim_advance_wear_counters clamps its PRODUCTS at LEAST(1.0, GREATEST(0, ...)), not its dials; writing 1.0 as their ceiling is the same trap 0285 avoided with litter_p_per_active_min and 0.95, and A3 proves the open ceiling on soil_rate_per_km at 40. Also recorded: precip_soil_coupling exists twice under one name -- the policy dial (0.5) and an unrelated plan field read by twin.ottoq_sim_observe_asset (0.6). Noted that the single live enforce_site_charge_cap row is 0 at run scope. forces_recert=false, asserted in P0: ottoq_policy_get never reads the catalog. 17 live rows untouched.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
