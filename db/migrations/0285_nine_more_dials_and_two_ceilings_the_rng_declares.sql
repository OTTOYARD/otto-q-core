-- migration-version: 20260914065559
-- migration-name:    0285_nine_more_dials_and_two_ceilings_the_rng_declares
--
-- 0285  NINE MORE DIALS, AND THE TWO CEILINGS THE RNG DECLARES
--
-- ---------------------------------------------------------------------------
-- SAME RULE AS 0282 AND 0283: READ THE RANGE OFF THE CONSUMER, NEVER CHOOSE IT
--
-- Nine keys, 21 live rows between them, every one of them read by exactly one
-- live function -- which is why they are together: a single-reader dial's range
-- is either written down in that one consumer or it is not derivable at all,
-- and this batch is where both cases show up side by side.
--
--   demo_max_ticks              10 ..            240   (GREATEST(10, ...))
--   demo_max_ticks_live         10 ..          5,000   (GREATEST(10, ...))
--   rider_flag_daily_pct         0 ..            3.0
--   rider_flag_interior_share    0 .. 1          0.70  (the RNG's own range)
--   rider_flag_window_h          0 ..             14
--   calib_interval_h             1 ..            250   (GREATEST(1, ...))
--   comms_stale_ticks            0 ..              3
--   dtc_debt_threshold           0 ..              3
--   litter_p_per_active_min      0 ..          0.004
--
-- ---------------------------------------------------------------------------
-- 1-2. THE TWO TICK CAPS -- min 10, written twice in one function
--
-- public.ottoq_demo_metronome picks one of them by branch:
--   v_max_ticks := GREATEST(10, ottoq_policy_get(run,'demo_max_ticks_live', 5000)::int);
--   v_max_ticks := GREATEST(10, ottoq_policy_get(run,'demo_max_ticks',       240)::int);
-- Below 10 both already behave as 10. Catalogued together for the reason the
-- night window was: two dials selected by one branch are one switch, and half a
-- switch is worse than none. Nothing caps a run length above, so max is NULL.
--
-- ---------------------------------------------------------------------------
-- 3-5. THE RIDER-FLAG TRIPLE, and the one honest refusal in this file
--
-- public.ottoq_run_boot_draw:
--   v_rf_p := LEAST(1.0, GREATEST(0.0, (v_rf_rate / 100.0) * v_rf_days));
--   CASE WHEN ottoq_sim_seeded_random(v_seed, 'rflagkind:'||f.id::text) < v_rf_int_share
--   ... + make_interval(mins => floor(v_rf_window_h * 60 ...))
--
-- rider_flag_daily_pct: min 0, because the consumer's own GREATEST(0.0, ...)
--   already makes every negative rate behave as zero. MAX IS NULL AND THAT IS
--   THE POINT: the rate saturates where (rate/100)*days = 1, i.e. at
--   100/v_rf_days -- and v_rf_days is the RUN'S OWN LENGTH, resolved at
--   runtime. On a half-day run a rate of 150 is not equivalent to 100. There is
--   no constant ceiling to declare, so none is declared. A "100" here would
--   look obvious, read as derived, and be wrong for every run shorter than a day.
--
-- rider_flag_interior_share: [0, 1], AND THE CEILING IS DECLARED BY THE RNG.
--   twin.ottoq_sim_seeded_random ends "normalize to [0,1)" and returns
--   (hash % 1000000)::numeric / 1000000.0. Against a draw in [0,1), a share of
--   0 is never true and a share of 1 is always true; outside that the branch is
--   constant. Not a preference -- the generator's own normalization.
--
-- rider_flag_window_h: min 0. The value becomes make_interval(mins => floor(h*60)),
--   so a negative hour is a negative interval -- a flag scheduled BEFORE the
--   window it defines, which is not a setting but an inversion. Nothing bounds
--   it above, so max is NULL.
--
-- ---------------------------------------------------------------------------
-- 6. calib_interval_h -- min 1, floored once and guarded once
--
--   public.ottoq_scenario_apply_fleet_overrides:
--     'calib_interval_h', GREATEST(1, round(t.cal_raw * v_cal, 1))
--   public.ottoq_twin_wear_window:
--     CASE WHEN calib_interval_h IS NULL OR calib_interval_h = 0 THEN NULL
--          ELSE round((drive_hours_total - ...) / calib_interval_h, 3) END
--
-- The override path floors the written value at 1, and the reporting path
-- guards zero because it DIVIDES by this. Two independent statements that the
-- floor is 1. Nothing caps a calibration interval above.
--
-- ---------------------------------------------------------------------------
-- 7-8. THE TWO >= THRESHOLDS -- min 0 by saturation, not by taste
--
--   public.ottoq_recall_naive_threshold_v1:
--     IF COALESCE(v_w.worst_open_dtc_rank,99) = 1
--        OR COALESCE(v_w.open_dtc_count,0) >= v_dtc_debt THEN
--     ... EXTRACT(EPOCH FROM (now - dispatched_at))/60.0 >= v_comms_stale * p_horizon_min
--
-- Both compare a non-negative quantity with >=. At 0 the test is already
-- unconditionally true, and every negative value is behaviourally identical to
-- 0 -- the same saturation argument 0282 used for reserve_margin_pct's max 100,
-- pointed the other way. Neither quantity is bounded above (a DTC count and an
-- age in minutes both grow), so both ceilings stay NULL.
--
-- ---------------------------------------------------------------------------
-- 9. litter_p_per_active_min -- min 0, and the 0.95 is NOT this dial's ceiling
--
--   twin.ottoq_sim_advance_wear_counters:
--     ... < LEAST(0.95, v_litter_p * p_tick_minutes * (1 + v_precip * v_precip_coup))
--
-- min 0: against a draw in [0,1) a negative probability is never true, exactly
-- as 0 is. THE 0.95 CAP IS ON THE PRODUCT, NOT ON THE DIAL, and writing 0.95
-- into max_value would be the subtlest mistake available in this file -- the
-- saturation point is 0.95 / (tick_minutes * precip factor), both runtime. So
-- max stays NULL for the same reason rider_flag_daily_pct's does.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0285 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0285 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0285 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0285 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. PREMISE + THE forces_recert=false ARGUMENT -----------------------------
DO $p0$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('demo_max_ticks','demo_max_ticks_live','rider_flag_daily_pct',
                       'rider_flag_interior_share','rider_flag_window_h','calib_interval_h',
                       'comms_stale_ticks','dtc_debt_threshold','litter_p_per_active_min');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0285 P0: % of the nine keys are already catalogued', v_n;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get';
  IF v_src IS NULL OR position('ottoq_policy_param_catalog' in v_src) > 0 THEN
    RAISE EXCEPTION '0285 P0: ottoq_policy_get is missing or now reads the catalog';
  END IF;
  RAISE NOTICE '0285 P0: nine keys uncatalogued; the read path still ignores the catalog';
END $p0$;

-- P1. BOTH TICK CAPS ARE STILL FLOORED AT TEN --------------------------------
DO $p1$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_demo_metronome';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0285 P1: ottoq_demo_metronome does not exist';
  END IF;
  IF position('GREATEST(10, ottoq_policy_get(v_run.sim_run_id, ''demo_max_ticks_live'', 5000)' in v_src) = 0
     OR position('GREATEST(10, ottoq_policy_get(v_run.sim_run_id, ''demo_max_ticks'', 240)' in v_src) = 0 THEN
    RAISE EXCEPTION '0285 P1: the metronome no longer floors both tick caps at 10; '
                    'min_value is derived from those two floors';
  END IF;
  RAISE NOTICE '0285 P1: both tick caps still floor at 10';
END $p1$;

-- P2. THE GENERATOR STILL NORMALIZES TO [0,1) --------------------------------
-- Two dials are compared against a draw from it, and their ceilings are its
-- range, not a preference. If the generator is ever rescaled, both are wrong.
DO $p2$
DECLARE v_rng text; v_boot text; v_wear text;
BEGIN
  SELECT p.prosrc INTO v_rng FROM pg_proc p WHERE p.proname = 'ottoq_sim_seeded_random' LIMIT 1;
  IF v_rng IS NULL THEN
    RAISE EXCEPTION '0285 P2: ottoq_sim_seeded_random does not exist';
  END IF;
  IF position('normalize to [0,1)' in v_rng) = 0
     OR position('% 1000000)::NUMERIC / 1000000.0' in v_rng) = 0 THEN
    RAISE EXCEPTION '0285 P2: the seeded generator no longer normalizes to [0,1); '
                    'rider_flag_interior_share''s ceiling and litter_p''s floor '
                    'are both derived from that range';
  END IF;
  SELECT p.prosrc INTO v_boot FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_run_boot_draw';
  SELECT p.prosrc INTO v_wear FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_wear_counters';
  IF v_boot IS NULL OR v_wear IS NULL THEN
    RAISE EXCEPTION '0285 P2: a consumer of the seeded draw is missing';
  END IF;
  IF position('< v_rf_int_share' in v_boot) = 0 THEN
    RAISE EXCEPTION '0285 P2: interior_share is no longer compared against a seeded draw';
  END IF;
  IF position('LEAST(0.95, v_litter_p * p_tick_minutes' in v_wear) = 0 THEN
    RAISE EXCEPTION '0285 P2: the litter probability is no longer the capped product '
                    'this file reasons about; re-read before cataloguing';
  END IF;
  RAISE NOTICE '0285 P2: the generator is [0,1) and both draw consumers are unchanged';
END $p2$;

-- P3. THE RIDER-FLAG RATE STILL CLAMPS ITS DERIVED PROBABILITY ---------------
-- This is the pin behind BOTH of that dial's decisions: min 0 (the GREATEST)
-- and max NULL (the saturation point depends on v_rf_days, not a constant).
DO $p3$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_run_boot_draw';
  IF position('LEAST(1.0, GREATEST(0.0, (v_rf_rate / 100.0) * v_rf_days))' in v_src) = 0 THEN
    RAISE EXCEPTION '0285 P3: the rider-flag rate no longer derives its probability as '
                    'LEAST(1.0, GREATEST(0.0, rate/100 * days)); both of that dial''s '
                    'bounds come from that expression';
  END IF;
  IF position('make_interval(mins => floor(v_rf_window_h * 60' in v_src) = 0 THEN
    RAISE EXCEPTION '0285 P3: the flag window is no longer an interval built from hours; '
                    'min 0 is derived from that construction';
  END IF;
  RAISE NOTICE '0285 P3: the rate clamps its probability and the window is still an interval';
END $p3$;

-- P4. calib_interval_h IS STILL FLOORED AT 1 AND GUARDED AS A DIVISOR --------
DO $p4$
DECLARE v_ovr text; v_win text;
BEGIN
  SELECT p.prosrc INTO v_ovr FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_scenario_apply_fleet_overrides';
  SELECT p.prosrc INTO v_win FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_twin_wear_window';
  IF v_ovr IS NULL OR v_win IS NULL THEN
    RAISE EXCEPTION '0285 P4: a calib_interval_h consumer is missing';
  END IF;
  IF position('''calib_interval_h'', GREATEST(1, round(t.cal_raw * v_cal, 1))' in v_ovr) = 0 THEN
    RAISE EXCEPTION '0285 P4: the override path no longer floors calib_interval_h at 1';
  END IF;
  IF position('calib_interval_h = 0 THEN NULL' in v_win) = 0 THEN
    RAISE EXCEPTION '0285 P4: the wear window no longer guards calib_interval_h = 0 as a '
                    'divisor; the second half of the min-1 argument is gone';
  END IF;
  RAISE NOTICE '0285 P4: calib_interval_h floored at 1 and still guarded against 0';
END $p4$;

-- P5. BOTH >= THRESHOLDS STILL COMPARE A NON-NEGATIVE QUANTITY ---------------
DO $p5$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_recall_naive_threshold_v1';
  IF position('COALESCE(v_w.open_dtc_count,0) >= v_dtc_debt' in v_src) = 0 THEN
    RAISE EXCEPTION '0285 P5: the DTC debt test changed shape; min 0 is derived from '
                    'a count >= threshold comparison';
  END IF;
  IF position('>= v_comms_stale * p_horizon_min' in v_src) = 0 THEN
    RAISE EXCEPTION '0285 P5: the comms staleness test changed shape; min 0 is derived '
                    'from an age >= multiplier * horizon comparison';
  END IF;
  RAISE NOTICE '0285 P5: both >= thresholds unchanged; 0 already saturates each';
END $p5$;

-- P6. EVERY LIVE ROW IS INSIDE THE RANGES THIS FILE DECLARES -----------------
DO $p6$
DECLARE v_n int; v_bad int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('demo_max_ticks','demo_max_ticks_live','rider_flag_daily_pct',
                       'rider_flag_interior_share','rider_flag_window_h','calib_interval_h',
                       'comms_stale_ticks','dtc_debt_threshold','litter_p_per_active_min');
  IF v_n <> 21 THEN
    RAISE EXCEPTION '0285 P6: expected the 21 measured live rows across the nine keys, '
                    'found % -- somebody wrote these dials since the measurement', v_n;
  END IF;
  SELECT count(*) INTO v_bad FROM public.ottoq_policy_params
   WHERE (param_key IN ('demo_max_ticks','demo_max_ticks_live') AND param_value < 10)
      OR (param_key = 'calib_interval_h'          AND param_value < 1)
      OR (param_key = 'rider_flag_interior_share' AND (param_value < 0 OR param_value > 1))
      OR (param_key IN ('rider_flag_daily_pct','rider_flag_window_h','comms_stale_ticks',
                        'dtc_debt_threshold','litter_p_per_active_min') AND param_value < 0);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0285 P6: % live row(s) fall outside the ranges this file declares; '
                    'correct them before cataloguing', v_bad;
  END IF;
  RAISE NOTICE '0285 P6: 21 live rows, all inside the declared ranges';
END $p6$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES
('demo_max_ticks',
 '0285: how many ticks public.ottoq_demo_metronome will drive a NON-production run before it stops advancing it. min_value 10 is the consumer''s own word -- the metronome reads it as GREATEST(10, ottoq_policy_get(run, ''demo_max_ticks'', 240)::int), so anything below 10 already behaves as 10. MAX NULL: nothing in the engine caps a run length from above. Catalogued together with demo_max_ticks_live because one branch of one function chooses between them and half a switch is worse than none. 0285 P1 pins both floors.',
 240, 10, NULL, 'public.ottoq_demo_metronome'),
('demo_max_ticks_live',
 '0285: the same cap as demo_max_ticks, for the branch public.ottoq_demo_metronome takes on a production-live run (default 5000 rather than 240). Identical derivation -- GREATEST(10, ...) in the same function -- so min 10, max NULL. It has no live rows today; catalogued anyway, because the reason a dial is unset is usually that the setter refuses it. 0285 P1 pins both floors.',
 5000, 10, NULL, 'public.ottoq_demo_metronome'),
('rider_flag_daily_pct',
 '0285: percent of the fleet per SIM-DAY that boots carrying a rider-reported flag. public.ottoq_run_boot_draw turns it into a per-vehicle probability as LEAST(1.0, GREATEST(0.0, (rate / 100.0) * v_rf_days)). min_value 0 is that GREATEST -- every negative rate already behaves as zero. MAX_VALUE IS NULL DELIBERATELY, and 100 would be the obvious wrong answer: the rate saturates where (rate/100)*days = 1, i.e. at 100/v_rf_days, and v_rf_days is the run''s own length resolved at runtime -- so on a half-day run 150 is NOT equivalent to 100. There is no constant ceiling to declare. 0285 P3 pins the expression.',
 3.0, 0, NULL, 'public.ottoq_run_boot_draw'),
('rider_flag_interior_share',
 '0285: of the rider flags drawn, the share that are interior rather than exterior. public.ottoq_run_boot_draw decides each with ottoq_sim_seeded_random(...) < this dial. THE CEILING IS THE GENERATOR''S, NOT A PREFERENCE: ottoq_sim_seeded_random returns (hash % 1000000)::numeric / 1000000.0 and its own comment says "normalize to [0,1)", so against that draw 0 is never true, 1 is always true, and outside [0,1] the branch is constant. 0285 P2 pins the normalization and the comparison.',
 0.70, 0, 1, 'public.ottoq_run_boot_draw'),
('rider_flag_window_h',
 '0285: how many hours into the run the drawn rider flags are spread over -- the daytime deployment window. public.ottoq_run_boot_draw places each at make_interval(mins => floor(this * 60 * ...)). min_value 0 because a negative hour becomes a negative interval, scheduling a flag BEFORE the window that defines it, which is an inversion rather than a setting. MAX NULL: nothing bounds the window above. 0285 P3 pins the construction.',
 14, 0, NULL, 'public.ottoq_run_boot_draw'),
('calib_interval_h',
 '0285: drive-hours between ADAS calibrations, used as the fallback when a vehicle''s own config carries none (public.ottoq_recall_naive_threshold_v1 reads config first, this dial second). min_value 1 is stated twice by the engine: public.ottoq_scenario_apply_fleet_overrides writes it as GREATEST(1, round(cal_raw * scale, 1)), and public.ottoq_twin_wear_window DIVIDES by it and guards calib_interval_h = 0 explicitly. MAX NULL: nothing caps a calibration interval above. 0285 P4 pins the floor and the divisor guard.',
 250, 1, NULL, 'public.ottoq_recall_naive_threshold_v1, public.ottoq_scenario_apply_fleet_overrides, public.ottoq_twin_wear_window'),
('comms_stale_ticks',
 '0285: how many horizons of silence make a deployed vehicle''s telemetry stale enough to recall on. public.ottoq_recall_naive_threshold_v1 tests age_minutes >= this * p_horizon_min. min_value 0 by saturation, not by taste: the left side is a non-negative age, so at 0 the test is already unconditionally true and every negative value is behaviourally identical to 0 -- the same argument 0282 used for reserve_margin_pct''s max 100, pointed downward. MAX NULL: an age in minutes is not bounded above. 0285 P5 pins the comparison.',
 3, 0, NULL, 'public.ottoq_recall_naive_threshold_v1'),
('dtc_debt_threshold',
 '0285: how many open diagnostic trouble codes count as enough debt to pull a vehicle in (a rank-1 worst code triggers regardless). public.ottoq_recall_naive_threshold_v1 tests COALESCE(open_dtc_count,0) >= this. min_value 0 by the same saturation argument as comms_stale_ticks -- a count is non-negative, so 0 is already always true. MAX NULL: a DTC count is not bounded above. 0285 P5 pins the comparison.',
 3, 0, NULL, 'public.ottoq_recall_naive_threshold_v1'),
('litter_p_per_active_min',
 '0285: probability per active minute that a vehicle picks up interior litter. twin.ottoq_sim_advance_wear_counters draws against LEAST(0.95, this * p_tick_minutes * (1 + precip * coupling)). min_value 0: against a draw normalized to [0,1) a negative probability is never true, exactly as 0 is. THE 0.95 IS NOT THIS DIAL''S CEILING and writing it into max_value would be the subtlest mistake available here -- the cap is on the PRODUCT, so the dial saturates at 0.95 / (tick_minutes * precip factor), both of which are runtime. MAX stays NULL for the same reason rider_flag_daily_pct''s does. 0285 P2 pins the product.',
 0.004, 0, NULL, 'twin.ottoq_sim_advance_wear_counters');

-- ---------------------------------------------------------------------------
-- A1. THE SETTER ACCEPTS ALL NINE KEYS IT HAS ALWAYS REFUSED.
DO $a1$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000028500aa'::uuid;
  v_r jsonb; k text; v numeric;
  v_probe CONSTANT jsonb := jsonb_build_object(
    'demo_max_ticks', 300, 'demo_max_ticks_live', 4000,
    'rider_flag_daily_pct', 5, 'rider_flag_interior_share', 0.5,
    'rider_flag_window_h', 12, 'calib_interval_h', 200,
    'comms_stale_ticks', 4, 'dtc_debt_threshold', 2,
    'litter_p_per_active_min', 0.01);
BEGIN
  FOR k, v IN SELECT key, value::text::numeric FROM jsonb_each(v_probe) LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, v, '0285_proof');
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
  RAISE NOTICE 'A1 OK: all nine keys write through the setter, unclamped, and read back';
END $a1$;

-- A2. THE BOUNDED DIALS CLAMP ON EVERY SIDE THEY DECLARE.
DO $a2$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028500aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'demo_max_ticks', 5, '0285_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 10
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: 5 ticks should clamp to 10 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'demo_max_ticks_live', 0, '0285_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 10 THEN
    RAISE EXCEPTION 'A2 FAILED: 0 live ticks should clamp to 10: %', v_r;
  END IF;
  -- the one dial in this file with a real ceiling, clamped both ways
  v_r := public.ottoq_policy_set('run', v_scratch, 'rider_flag_interior_share', 5, '0285_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 1
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: share 5 should clamp to 1 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'rider_flag_interior_share', -1, '0285_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 0
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: share -1 should clamp to 0 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'calib_interval_h', 0, '0285_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 1 THEN
    RAISE EXCEPTION 'A2 FAILED: calib 0 should clamp to 1 -- the wear window divides '
                    'by this: %', v_r;
  END IF;
  RAISE NOTICE 'A2 OK: every declared bound in this file fires';
END $a2$;

-- A3. THE SEVEN NULL CEILINGS IMPOSE NOTHING.
-- 0283 A3 proved the contract; this re-proves it on the dial where getting it
-- wrong would be worst -- a litter probability silently pinned to zero would
-- turn a modelled wear process off and look like a quiet twin.
DO $a3$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028500aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'litter_p_per_active_min', 12.5, '0285_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 12.5
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A3 FAILED: a NULL max_value must impose no ceiling: %', v_r;
  END IF;
  IF (v_r->'safe_range'->>1) IS NOT NULL THEN
    RAISE EXCEPTION 'A3 FAILED: the receipt should report an open upper bound: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'litter_p_per_active_min', -0.5, '0285_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 0
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A3 FAILED: the floor of 0 did not fire on -0.5: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'rider_flag_daily_pct', 1000, '0285_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 1000
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A3 FAILED: rider_flag_daily_pct has no constant ceiling and must '
                    'not be clamped at 100: %', v_r;
  END IF;
  RAISE NOTICE 'A3 OK: NULL ceilings impose nothing and every declared floor still fires';
END $a3$;

-- A4. EVERY VALUE THE DEPOTS ACTUALLY RUN PASSES THROUGH UNCHANGED.
DO $a4$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028500aa'::uuid; v_r jsonb;
        k text; v numeric; v_n int := 0;
BEGIN
  FOR k, v IN
    SELECT DISTINCT param_key, param_value FROM public.ottoq_policy_params
     WHERE param_key IN ('demo_max_ticks','demo_max_ticks_live','rider_flag_daily_pct',
                         'rider_flag_interior_share','rider_flag_window_h','calib_interval_h',
                         'comms_stale_ticks','dtc_debt_threshold','litter_p_per_active_min')
       AND updated_by <> '0285_proof'
  LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, v, '0285_proof');
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

-- A5. THE SCRATCH IS GONE AND THE 21 LIVE ROWS SURVIVE.
DO $a5$
DECLARE v_n int;
BEGIN
  DELETE FROM public.ottoq_policy_params WHERE updated_by = '0285_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 9 THEN
    RAISE EXCEPTION 'A5 FAILED: expected to remove exactly 9 scratch rows, removed %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('demo_max_ticks','demo_max_ticks_live','rider_flag_daily_pct',
                       'rider_flag_interior_share','rider_flag_window_h','calib_interval_h',
                       'comms_stale_ticks','dtc_debt_threshold','litter_p_per_active_min');
  IF v_n <> 21 THEN
    RAISE EXCEPTION 'A5 FAILED: % rows remain across the nine keys, expected the original 21', v_n;
  END IF;
  RAISE NOTICE 'A5 OK: scratch removed, the original 21 rows survive';
END $a5$;

-- A6. THE 0281 INSTRUMENT AGREES THE GAP SHRANK BY NINE.
DO $a6$
DECLARE v_ok int; v_still int;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'ok'), count(*) FILTER (WHERE status <> 'ok')
    INTO v_ok, v_still
    FROM public.ottoq_policy_catalog_gap
   WHERE param_key IN ('demo_max_ticks','demo_max_ticks_live','rider_flag_daily_pct',
                       'rider_flag_interior_share','rider_flag_window_h','calib_interval_h',
                       'comms_stale_ticks','dtc_debt_threshold','litter_p_per_active_min');
  IF v_still > 0 THEN
    RAISE EXCEPTION 'A6 FAILED: % of the nine still report a gap', v_still;
  END IF;
  IF v_ok <> 9 THEN
    RAISE EXCEPTION 'A6 FAILED: expected all nine to report ok, found %', v_ok;
  END IF;
  RAISE NOTICE 'A6 OK: all nine now report ok in ottoq_policy_catalog_gap';
END $a6$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0285_nine_more_dials_and_two_ceilings_the_rng_declares', false,
 'Nine rows in ottoq_policy_param_catalog, every range read off the single consumer that reads each key. Floors the engine writes down: demo_max_ticks and demo_max_ticks_live min 10 (GREATEST(10, ...) twice in ottoq_demo_metronome), calib_interval_h min 1 (GREATEST(1, ...) in the scenario override path, and guarded as a divisor in ottoq_twin_wear_window). Floors by saturation: comms_stale_ticks and dtc_debt_threshold min 0 (both compare a non-negative quantity with >=, so 0 is already unconditionally true), rider_flag_daily_pct and litter_p_per_active_min min 0, rider_flag_window_h min 0 (a negative hour becomes a negative interval). ONE REAL CEILING, and it is the generator''s: rider_flag_interior_share [0,1], because ottoq_sim_seeded_random normalizes to [0,1) in its own comment and the share is compared against a draw from it. SEVEN NULL CEILINGS ON PURPOSE -- most notably rider_flag_daily_pct, where 100 is the obvious wrong answer (saturation is at 100/v_rf_days, and the run length is runtime), and litter_p_per_active_min, where the 0.95 in the consumer caps the PRODUCT rather than the dial. A3 proves a NULL ceiling imposes nothing and that every declared floor still fires; A4 re-offers every distinct live value and requires it through unclamped. forces_recert=false, asserted in P0: ottoq_policy_get never reads the catalog, so these rows are consumed only by ottoq_policy_set, which no certification arm calls. 21 live rows untouched.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 2026-09-14 06:55:59 UTC (1:55 AM CT) as
-- supabase_migrations.schema_migrations version 20260914065559.
--
-- Dry run: the WHOLE file byte for byte inside BEGIN ... ROLLBACK, with no
-- abbreviation anywhere (0284 had to abbreviate one literal and say so; this
-- one did not), clean on the first attempt. P-, P0-P6 and A1-A6 all passed and
-- a post-rollback re-count confirmed 0 catalog rows, 0 rows tagged 0285, and no
-- lineage row.
--
-- ONE DEFECT CAUGHT BEFORE THE DRY RUN, worth naming because it is the second
-- time in four files: a %% inside a plain SQL string literal. %% is an escape
-- only in a RAISE format string; in an ordinary literal it stores two percent
-- signs, and this one sat in the rider_flag_interior_share description -- the
-- row whose whole argument is what the generator returns. Same class as 0283's.
--
-- VERIFIED AFTER APPLY, read-only:
--
--   ottoq_policy_catalog_gap, read_uncatalogued   81 -> 72
--   ottoq_policy_catalog_gap, ok                  69 -> 78
--   ottoq_policy_param_catalog rows               77 -> 86
--   rows left behind by the proof                        0
--
-- Eighteen dials catalogued across 0282, 0283 and 0285, and not one range was
-- chosen. The gap instrument 0281 built has gone 90 -> 72 without a single
-- guessed bound being written into it.
-- ===========================================================================
