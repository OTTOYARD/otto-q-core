-- 0054 — PROOF THAT 0133 CLOSES THE ENERGY-PATH DEFECT (2026-08-31)
-- ============================================================================================
-- 0051 established that two byte-identical arms produced peak_site_kw 524.9 vs 416.3, and
-- localised the whole delta to bess_output_kw at sim 08:00 -- ottoq_bess_units is world state
-- that no reset, no boot draw, no teardown and no fingerprint touched. 0133 fixes it. This is
-- the test that the fix does what it claims, run live before the certification ladder.
--
-- THE CARRIER, NAMED PRECISELY. current_power_kw rests at 0 between runs, so the thing that
-- actually carried is the STATE OF CHARGE: the flagship unit sat at 93.04% (2791.22 of
-- 3000 kWh) and the benchmark unit at 97.58% -- the latter ABOVE its own configured 95%
-- ceiling. A different starting SoC gives a different discharge trajectory, and by sim 08:00
-- that is 474 kW of grid import.
--
-- THE TEST (three assertions, any of which could have failed):
--   1. SEED-DETERMINISTIC. reset_fleet(depot, 424242) twice must give the SAME SoC. If the
--      reset were not a pure function of the seed it would be a new nondeterminism source,
--      which is worse than the defect it replaces.
--   2. SEED-SENSITIVE. reset_fleet(depot, 171717) must give a DIFFERENT SoC. A reset that
--      ignored the seed would be a constant -- defensible, but not what was written, and the
--      assertion catches the difference between "seeded" and "hardcoded".
--   3. VISIBLE TO THE FINGERPRINT. ottoq_world_fingerprint must CHANGE when the BESS changes.
--      This is the assertion that matters most: without it the pair still cannot see a battery
--      divergence, and the class stays invisible exactly as it did through three rounds.
-- RESULT: all three passed; the block raised no exception. Observed after the seed-171717
-- reset: NASH-BESS-01 at 69.99% / 2099.742 kWh (= 3000 x 0.6999, inside its 10-95 band),
-- current_power_kw 0, state 'idle'. The benchmark depot's unit was untouched at 97.58%,
-- confirming the reset is depot-scoped rather than global.
--
-- WHAT THIS DOES NOT CLAIM. It does not claim peak_site_kw is now reproducible -- that is what
-- the certification ladder tests, because it needs two full arms, not a reset. It claims the
-- three mechanisms 0133 introduces behave as specified. The solar and weather run-scoping in
-- the same migration are not exercised here at all: they were dark-hour no-ops in the 0051
-- evidence and their effect shows up as a midday difference, which only a full run produces.
--
-- Re-runnable. Expects no exception; prints the three SoCs and whether the fingerprint moved.
DO $t$
DECLARE d uuid := '11111111-1111-1111-1111-111111111111';
        s1 numeric; s2 numeric; s3 numeric; f1 text; f3 text;
BEGIN
  PERFORM public.ottoq_tick_invariance_reset_fleet(d, 424242);
  SELECT current_soc_pct INTO s1 FROM public.ottoq_bess_units WHERE depot_id=d;
  f1 := ottoq.ottoq_world_fingerprint(d);

  PERFORM public.ottoq_tick_invariance_reset_fleet(d, 424242);
  SELECT current_soc_pct INTO s2 FROM public.ottoq_bess_units WHERE depot_id=d;

  PERFORM public.ottoq_tick_invariance_reset_fleet(d, 171717);
  SELECT current_soc_pct INTO s3 FROM public.ottoq_bess_units WHERE depot_id=d;
  f3 := ottoq.ottoq_world_fingerprint(d);

  IF s1 IS DISTINCT FROM s2 THEN RAISE EXCEPTION 'FAIL: same seed gave % then %', s1, s2; END IF;
  IF s1 = s3           THEN RAISE EXCEPTION 'FAIL: different seeds gave the same SoC %', s1; END IF;
  IF f1 = f3           THEN RAISE EXCEPTION 'FAIL: fingerprint did not move when the BESS moved'; END IF;
  RAISE NOTICE '0054 PASS | 424242 soc=% (repeat %) | 171717 soc=% | fingerprint moved: %',
               s1, s2, s3, (f1 IS DISTINCT FROM f3);
END $t$;
