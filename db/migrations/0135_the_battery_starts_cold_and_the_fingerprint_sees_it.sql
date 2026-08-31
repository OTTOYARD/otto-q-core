-- migration-version: 20260831190500
-- migration-name:    the_battery_starts_cold_and_the_fingerprint_sees_it
-- 0135 -- the residual the 0133 fingerprint could not see, and therefore could not fail on.
--
-- WHAT 0134 PROVED, AND WHAT IT DID NOT. 0134 run-scoped four world-table readers and closed a
-- real defect: the post-0134 pair (run_a 8b04b5c3, run_b bc82a908) shows BESS soc_pct IDENTICAL
-- between arms at every tick where it previously diverged -- 69.71/69.71 at tick 3, 69.59/69.59
-- at tick 4, against 91.34 vs 91.46 before. The solar SUM no longer integrates seventy runs and
-- the ambient pick is no longer a coin. That carrier is dead.
--
-- The pair still failed. Same tick, same shape: ticks 1-3 identical, tick 4 first divergence
-- (bess_setpoint -459.5 vs -459.1, charge_cap 811.1 vs 811.5). The new evidence is sharper than
-- the old, in two ways.
--
-- FIRST: divergence occurs ONLY on ticks where the BESS actually moves. Ticks 1,2,3,5,7,10,11,12
-- carry bess_setpoint 0.0 and byte-identical caps; ticks 4,6,8,9 carry a non-zero setpoint and
-- every one of them diverges. And cap + |setpoint| is constant across arms, so exactly ONE
-- quantity forks and the cap is derived from it.
--
-- SECOND: public.bess_snapshots dates the fork to before the first tick. At matching SoC the two
-- arms report different battery temperatures from the very first sample:
--       SoC 69.84 -> 30.10 vs 22.10   SoC 69.71 -> 27.80 vs 21.30   SoC 69.59 -> 26.10 vs 20.80
-- Identical state of charge, five to eight degrees apart, before either arm has diverged in SoC
-- (which first differs at tick 4: 76.94 vs 76.95). The battery did not get hot during the run --
-- it STARTED at a different temperature. public.ottoq_bess_units.current_temperature_c reads
-- 20.54 right now, which is the last value the previous run wrote.
--
-- THE MECHANISM, from twin.ottoq_sim_bess_step:
--     v_new_temp := v.current_temperature_c
--                 + (v_target_temp - v.current_temperature_c) * v_thermal_lag
--                 + v_thermal_noise;
-- Temperature is a FIRST-ORDER LAG STATE: each step's value is a function of the previous one.
-- A different starting temperature is not damped out inside a twelve-tick run, it is carried
-- through all of it -- and twin.ottoq_sim_bess_compute_max_power_kw is handed
-- v.current_temperature_c on every charge and discharge step. The noise term is NOT the carrier:
-- it is ottoq_sim_seeded_random(v_seed,'noise'), deterministic per seed.
--
-- Ruled out by measurement, not by argument: current_soh_pct is a flat 97.54 across all
-- twenty-four snapshots of BOTH arms, and max_charge_kw a flat 1500, so the direct power
-- multiplier did not move in this pair. SoH is fixed here anyway, because it is the same class
-- of residue and is one degradation event away from becoming the next carrier.
--
-- WHY THE HARNESS CALLED THIS WORLD IDENTICAL. 0133 taught ottoq.ottoq_world_fingerprint to see
-- the battery, and the section it added hashes exactly:
--       bess_id | current_power_kw | current_soc_pct | current_soc_kwh | current_state
-- current_temperature_c is not in it. So the fingerprint compared two worlds that differed by
-- eight degrees and reported them equal -- and every pair in this lineage has been certifying a
-- boot image that was never actually canonical. This is the repo's own standing rule turned on
-- its instrument: A CHECK THAT CANNOT FAIL IS NOT A CHECK. Part B is therefore not optional
-- tidying; without it the next residual column repeats this round exactly.
--
-- PART A -- ottoq_tick_invariance_reset_fleet canonicalizes the columns the run mutates and the
-- reset previously left standing. Five columns join current_power_kw / current_state /
-- current_soc_pct / current_soc_kwh:
--   * current_temperature_c   -> 25.0   THE PROVEN CARRIER.
--   * current_soh_pct         -> 100.0  written by twin.ottoq_sim_bess_apply_degradation, read by
--                                       compute_max_power_kw as a direct multiplier.
--   * current_cycle_count     -> 0      \  monotonic accumulators, written every run, never
--   * lifetime_kwh_charged    -> 0       > restored; they feed the degradation calculation that
--   * lifetime_kwh_discharged -> 0      /  writes current_soh_pct.
--
-- WHY A CONSTANT HERE WHEN 0133 USED A SEEDED DRAW. 0133 seeded SoC "inside the unit's own
-- configured band rather than at an invented constant" -- and SoC HAS an operating band, in
-- soc_min_floor_pct..soc_max_ceiling_pct. Temperature has no operating band: its only configured
-- pair is temperature_min_c..temperature_max_c = -10..50 on every unit, which is a SAFETY
-- envelope whose endpoints sit inside thermal-derate territory (compute_max_power_kw derates
-- above 45 and below 5). Seeding a start temperature across it would put arms into derate at
-- random, which is not realism, it is noise. 25.0 is not invented either: public.ottoq_cert_arm_start
-- already canonicalizes this exact column to 25.0, and Part A adopts the value the repo has
-- already chosen for the same purpose. current_soh_pct -> 100.0 is the certification baseline:
-- every arm starts from a nameplate-healthy pack, within-run degradation still models normally,
-- and the cross-run accumulation is the leak being closed. It also ends a live pathology --
-- current_soh_pct and current_cycle_count are carrying roughly a thousand digits of accumulated
-- numeric precision, because unbounded numeric arithmetic has been compounding them across
-- hundreds of runs with nothing ever rounding or restoring them. If a real per-unit nameplate
-- SoH is wanted later it belongs in a column of its own, not in residue.
--
-- PART B -- the fingerprint's BESS section gains all five, so the boot image can fail on them.
--
-- Both parts re-mint every canon, so the six-column ladder is re-run from scratch after this.
--
-- Pre-image pins, read live 2026-08-31 (each anchor asserted at exactly 1 occurrence):
--   public.ottoq_tick_invariance_reset_fleet  45c111fa658eec4e9abd241a7f861dc8
--   ottoq.ottoq_world_fingerprint             29efa3fc48b438105671cc89ee1900ed

CREATE FUNCTION pg_temp.ottoq_0135_patch(p_ns text, p_fn text, p_md5 text,
                                         p_old text, p_new text, p_expect int)
RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_oid oid; v_src text; v_cnt int;
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = p_ns AND p.proname = p_fn AND p.prokind = 'f';
  v_src := pg_get_functiondef(v_oid);
  IF p_md5 IS NOT NULL AND md5(v_src) <> p_md5 THEN
    RAISE EXCEPTION '0135 abort: %.% drifted (md5 %)', p_ns, p_fn, md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, p_old, ''))) / length(p_old);
  IF v_cnt <> p_expect THEN
    RAISE EXCEPTION '0135 abort: %.% anchor found % times, expected %', p_ns, p_fn, v_cnt, p_expect;
  END IF;
  EXECUTE replace(v_src, p_old, p_new);
  v_src := pg_get_functiondef(v_oid);
  IF v_src NOT LIKE '%/* 0135%' THEN
    RAISE EXCEPTION '0135 abort: %.% patch did not survive', p_ns, p_fn;
  END IF;
  RAISE NOTICE '0135: %.% patched.', p_ns, p_fn;
END
$helper$;

DO $apply$
BEGIN
  -- PART A: the battery starts canonical, not wherever the last run left it.
  PERFORM pg_temp.ottoq_0135_patch(
    'public', 'ottoq_tick_invariance_reset_fleet', '45c111fa658eec4e9abd241a7f861dc8',
    '     SET current_power_kw = 0,' || chr(10) ||
    '         current_state    = ''idle'',',
    '     SET current_power_kw = 0,' || chr(10) ||
    '         current_state    = ''idle'',' || chr(10) ||
    '         current_temperature_c   = 25.0,   /* 0135 */' || chr(10) ||
    '         current_soh_pct         = 100.0,  /* 0135 */' || chr(10) ||
    '         current_cycle_count     = 0,      /* 0135 */' || chr(10) ||
    '         lifetime_kwh_charged    = 0,      /* 0135 */' || chr(10) ||
    '         lifetime_kwh_discharged = 0,      /* 0135 */',
    1);

  -- PART B: the fingerprint can now fail on every column Part A restores.
  PERFORM pg_temp.ottoq_0135_patch(
    'ottoq', 'ottoq_world_fingerprint', '29efa3fc48b438105671cc89ee1900ed',
    '||COALESCE(b.current_state,''-''), chr(10) ORDER BY b.bess_id)',
    '||COALESCE(b.current_state,''-'')||''|''' || chr(10) ||
    '                     ||COALESCE(b.current_temperature_c::text,''-'')||''|''   /* 0135 */' || chr(10) ||
    '                     ||COALESCE(b.current_soh_pct::text,''-'')||''|''' || chr(10) ||
    '                     ||COALESCE(b.current_cycle_count::text,''-'')||''|''' || chr(10) ||
    '                     ||COALESCE(b.lifetime_kwh_charged::text,''-'')||''|''' || chr(10) ||
    '                     ||COALESCE(b.lifetime_kwh_discharged::text,''-''), chr(10) ORDER BY b.bess_id)',
    1);

  RAISE NOTICE '0135 applied: the battery starts cold and the fingerprint sees it.';
END
$apply$;

-- Post-condition: both parts landed, 0133's own section survives, and -- the point of the
-- migration -- the fingerprint text actually names the column that carried the defect.
DO $verify$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_tick_invariance_reset_fleet';
  IF v_src NOT LIKE '%current_temperature_c   = 25.0%' THEN
    RAISE EXCEPTION '0135 abort: reset does not canonicalize temperature';
  END IF;
  IF v_src NOT LIKE '%lifetime_kwh_discharged = 0%' THEN
    RAISE EXCEPTION '0135 abort: reset does not zero the lifetime accumulators';
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_world_fingerprint';
  IF v_src NOT LIKE '%current_temperature_c::text%' THEN
    RAISE EXCEPTION '0135 abort: the fingerprint still cannot see battery temperature';
  END IF;
  IF v_src NOT LIKE '%/* 0133 */%' THEN
    RAISE EXCEPTION '0135 abort: 0133 BESS section lost';
  END IF;

  RAISE NOTICE '0135 verified: reset canonicalizes 5 more columns; the fingerprint sees all of them.';
END
$verify$;
