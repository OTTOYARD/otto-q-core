-- migration-version: 20260831150000
-- migration-name:    the_energy_path_joins_the_certification
-- 0133 -- the defect db/checks/0051 documented: two byte-identical arms produced different
-- peak_site_kw, so the demand-charge number was not reproducible even though the scheduler was.
--
-- THE EVIDENCE (0051, unchanged). Of 24 site_energy_snapshots rows per arm -- identical
-- timestamps, identical count -- exactly ONE differed, at sim 08:00, and the entire delta was
-- one column: d_grid -474.30 == d_bess -474.30, with d_ev, d_bldg and d_solar all 0.00.
-- twin.ottoq_sim_advance_site_energy computes
--     v_grid_kw := v_chargers_kw + v_building_kw - v_solar_ac_kw + v_bess_kw
-- and reads v_bess_kw straight off ottoq_bess_units, which is WORLD state: no reset, no boot
-- draw, no teardown and no fingerprint touched it, so arm B inherited arm A's battery.
--
-- WHAT CARRIES, PRECISELY. current_power_kw rests at 0 between runs, so the carrier is the
-- STATE OF CHARGE: the flagship unit currently sits at 93.04% (2791.22 of 3000 kWh) and the
-- benchmark unit at 97.58% -- the latter ABOVE its own configured 95% ceiling, a pre-existing
-- anomaly this reset also corrects. A different starting SoC gives a different discharge
-- trajectory, and by sim 08:00 that is 474 kW of grid import.
--
-- PART A -- ottoq_tick_invariance_reset_fleet canonicalizes the BESS.
-- Seed-derived within the unit's OWN configured band (soc_min_floor_pct .. soc_max_ceiling_pct),
-- mirroring the vehicle SoC line directly above it rather than inventing a magic number; power
-- and state to their rest values. Deterministic per seed, identical for every arm.
--
-- PART B -- ottoq_world_fingerprint gains a BESS section, per that function's own standing rule
-- ("extend the column set only alongside the 0046 probe that justifies it"). db/checks/0051 IS
-- that probe. Without this the pair cannot see a BESS divergence, which is exactly how this
-- class stayed invisible through three certification rounds.
--
-- PART C -- two unscoped reads in the same function, found in the same pass. Neither caused the
-- 474 kW delta; both are the identical disease and one is worse in kind:
--   * THE SOLAR SUM IS NOT RUN-SCOPED. Measured at the flagship depot, sim 2026-09-01 08:00:
--     860 rows from 215 DISTINCT sim runs share that timestamp and SUM(ac_power_kw) adds all of
--     them. Dark hours made it 0.0 in the 0051 evidence; at midday it inflates solar and so
--     DEFLATES grid import -- the direction that flatters the product, which is the direction
--     nobody catches from the inside.
--   * THE AMBIENT-TEMPERATURE PICK is neither run-scoped nor tiebroken (ORDER BY sim_clock_at
--     DESC LIMIT 1 over rows several runs share). Scoped here and ordered on the value actually
--     selected, so the result is total whichever row wins.
-- Both use the 0020/0124 zero-uuid idiom so production (sim_run_id NULL) keeps working.
--
-- DETERMINISM: behaviour-changing on all three counts. The six-column matrix must be re-run,
-- and Part B changes what the fingerprint hashes, so every fp canon re-mints regardless.
--
-- Pre-image pins, read live 2026-08-31:
--   public.ottoq_tick_invariance_reset_fleet   7682db4039bd4f835c1f4ea67775fc7b
--   ottoq.ottoq_world_fingerprint              d85ff49e940ad4d4abfffd590f31e6e1
--   twin.ottoq_sim_advance_site_energy         4b7e19f97d232109290fabf4b4f5ffac

CREATE FUNCTION pg_temp.ottoq_0133_patch(p_ns text, p_fn text, p_md5 text,
                                         p_old text, p_new text)
RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_oid oid; v_src text; v_cnt int;
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = p_ns AND p.proname = p_fn AND p.prokind = 'f';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> p_md5 THEN
    RAISE EXCEPTION '0133 abort: %.% drifted (md5 %)', p_ns, p_fn, md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, p_old, ''))) / length(p_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0133 abort: %.% anchor found % times, expected 1', p_ns, p_fn, v_cnt;
  END IF;
  EXECUTE replace(v_src, p_old, p_new);
  IF position('/* 0133' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0133 abort: %.% patch did not survive', p_ns, p_fn;
  END IF;
  RAISE NOTICE '0133: %.% patched.', p_ns, p_fn;
END
$helper$;

DO $apply$
BEGIN
  -- PART A: the BESS is canonicalized at reset, seed-derived inside its own configured band.
  PERFORM pg_temp.ottoq_0133_patch(
    'public', 'ottoq_tick_invariance_reset_fleet', '7682db4039bd4f835c1f4ea67775fc7b',
    '  RETURN v_n;',
    '  -- 0133: THE BESS IS START-RELEVANT WORLD. Probe: db/checks/0051 -- two byte-identical'
 || E'\n  -- arms produced peak_site_kw 524.9 vs 416.3 because the battery carried across runs.'
 || E'\n  -- Seed-derived inside the unit''s OWN configured band, mirroring the vehicle SoC line'
 || E'\n  -- above rather than inventing a constant. Also brings any unit sitting above its own'
 || E'\n  -- ceiling back into band (the benchmark unit was at 97.58% against a 95% ceiling).'
 || E'\n  UPDATE public.ottoq_bess_units b'
 || E'\n     SET current_power_kw = 0,'
 || E'\n         current_state    = ''idle'','
 || E'\n         current_soc_pct  = ROUND((COALESCE(b.soc_min_floor_pct,10)'
 || E'\n              + twin.ottoq_sim_seeded_random(p_seed, ''inv:bess:'' || b.bess_id::text)'
 || E'\n                * (COALESCE(b.soc_max_ceiling_pct,95) - COALESCE(b.soc_min_floor_pct,10)))::numeric, 2),'
 || E'\n         current_soc_kwh  = ROUND((COALESCE(b.capacity_kwh,0) *'
 || E'\n              (COALESCE(b.soc_min_floor_pct,10)'
 || E'\n               + twin.ottoq_sim_seeded_random(p_seed, ''inv:bess:'' || b.bess_id::text)'
 || E'\n                 * (COALESCE(b.soc_max_ceiling_pct,95) - COALESCE(b.soc_min_floor_pct,10))) / 100.0)::numeric, 3)'
 || E'\n   WHERE b.depot_id = p_depot_id;  /* 0133 */'
 || E'\n'
 || E'\n  RETURN v_n;');

  -- PART C1: the solar SUM stops adding every run's rows at that timestamp.
  PERFORM pg_temp.ottoq_0133_patch(
    'twin', 'ottoq_sim_advance_site_energy', '4b7e19f97d232109290fabf4b4f5ffac',
    '  WITH latest AS ('
 || E'\n    SELECT MAX(sim_clock_at) AS t FROM ottoq_solar_output'
 || E'\n     WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now'
 || E'\n  )'
 || E'\n  SELECT COALESCE(SUM(ac_power_kw), 0) INTO v_solar_ac_kw'
 || E'\n    FROM ottoq_solar_output, latest'
 || E'\n   WHERE depot_id = p_depot_id AND sim_clock_at = latest.t;',
    '  /* 0133: 860 solar rows from 215 DISTINCT runs shared sim 2026-09-01 08:00 on the'
 || E'\n     flagship depot, and this SUM added all of them -- inflating solar, deflating grid'
 || E'\n     import. Zero-uuid idiom (0020/0124) so production (sim_run_id NULL) is unchanged. */'
 || E'\n  WITH latest AS ('
 || E'\n    SELECT MAX(sim_clock_at) AS t FROM ottoq_solar_output'
 || E'\n     WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now'
 || E'\n       AND COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)'
 || E'\n         = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)'
 || E'\n  )'
 || E'\n  SELECT COALESCE(SUM(ac_power_kw), 0) INTO v_solar_ac_kw'
 || E'\n    FROM ottoq_solar_output, latest'
 || E'\n   WHERE depot_id = p_depot_id AND sim_clock_at = latest.t'
 || E'\n     AND COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)'
 || E'\n       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid);');
END
$apply$;

-- PART C2 and PART B are separate DO blocks: C2 re-pins advance_site_energy after C1 changed it.
DO $apply2$
DECLARE v_oid oid; v_src text; v_cnt int;
  a_old text := '  SELECT ambient_temp_c INTO v_ambient'
             || E'\n    FROM ottoq_weather_snapshots'
             || E'\n   WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now'
             || E'\n   ORDER BY sim_clock_at DESC LIMIT 1;';
  a_new text := '  /* 0133: neither run-scoped nor tiebroken; several runs share one sim_clock_at.'
             || E'\n     Ordered on the value actually selected, so the result is total either way. */'
             || E'\n  SELECT ambient_temp_c INTO v_ambient'
             || E'\n    FROM ottoq_weather_snapshots'
             || E'\n   WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now'
             || E'\n     AND COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)'
             || E'\n       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)'
             || E'\n   ORDER BY sim_clock_at DESC, ambient_temp_c DESC LIMIT 1;';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_site_energy' AND p.prokind='f';
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, a_old, ''))) / length(a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0133 abort: weather anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, a_old, a_new);
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, '/* 0133', ''))) / length('/* 0133');
  IF v_cnt <> 2 THEN RAISE EXCEPTION '0133 abort: advance_site_energy carries % markers, expected 2', v_cnt; END IF;
  RAISE NOTICE '0133: twin.ottoq_sim_advance_site_energy -- both reads scoped.';
END
$apply2$;

DO $applyb$
BEGIN
  -- PART B: the fingerprint learns to see the battery. chr(10) as the delimiter keeps this
  -- patch free of nested newline-escape ambiguity.
  PERFORM pg_temp.ottoq_0133_patch(
    'ottoq', 'ottoq_world_fingerprint', 'd85ff49e940ad4d4abfffd590f31e6e1',
    '               WHERE v2.home_depot_id = p_depot AND v2.category=''autonomous''), '''')'
 || E'\n  )',
    '               WHERE v2.home_depot_id = p_depot AND v2.category=''autonomous''), '''')'
 || E'\n    || ''#'' ||'
 || E'\n    -- 0133: the BESS is start-relevant world. Probe: db/checks/0051 -- peak_site_kw'
 || E'\n    -- differed between two byte-identical arms because the battery carried across runs,'
 || E'\n    -- and no fingerprint section could see it. /* 0133 */'
 || E'\n    COALESCE((SELECT string_agg(b.bess_id::text||''|''||COALESCE(b.current_power_kw::text,''-'')||''|'''
 || E'\n                     ||COALESCE(b.current_soc_pct::text,''-'')||''|''||COALESCE(b.current_soc_kwh::text,''-'')||''|'''
 || E'\n                     ||COALESCE(b.current_state,''-''), chr(10) ORDER BY b.bess_id)'
 || E'\n                FROM public.ottoq_bess_units b WHERE b.depot_id = p_depot), '''')'
 || E'\n  )');
END
$applyb$;

DO $verify$
DECLARE v_n int; v_fp1 text; v_fp2 text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind='f'
     AND pg_get_functiondef(p.oid) LIKE '%/* 0133%';
  IF v_n <> 3 THEN RAISE EXCEPTION '0133 abort: % functions carry the marker, expected 3', v_n; END IF;

  -- The fingerprint must still be a pure function of world state: two calls, no writes between.
  v_fp1 := ottoq.ottoq_world_fingerprint('11111111-1111-1111-1111-111111111111'::uuid);
  v_fp2 := ottoq.ottoq_world_fingerprint('11111111-1111-1111-1111-111111111111'::uuid);
  IF v_fp1 IS DISTINCT FROM v_fp2 THEN
    RAISE EXCEPTION '0133 abort: fingerprint is not stable across two calls (% vs %)', v_fp1, v_fp2;
  END IF;
  RAISE NOTICE '0133 verified: 3 markers, fingerprint stable at %.', left(v_fp1, 8);
END
$verify$;
