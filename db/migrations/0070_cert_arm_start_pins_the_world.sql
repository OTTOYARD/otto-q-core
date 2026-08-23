-- migration-version: 20260823160000
-- migration-name:    cert_arm_start_pins_the_world
-- 0070 -- HARNESS ONLY. public.ottoq_cert_arm_start now derives the world from the run seed
-- alone, and from a fixed reference day, so the same seed reproduces the same world across
-- sessions and across calendar days.
--
-- THE PROBLEM, in the founder's words: holding every input constant between two runs should
-- hold every variable constant, so that moving one input -- drop five chargers -- is a
-- controlled experiment. It was not: the same seed produced a different world on every
-- re-certification. Two independent causes, both single lines in this function, both
-- measured. Full evidence in docs/SEED_REPRODUCIBILITY_DIAGNOSIS.md.
--
-- (a) THE A/B GROUP UUID WAS MIXED INTO THE WORLD SEED. A fresh group is allocated per
--     re-cert, so each re-cert drew a different fleet. Both arms of one pair share the
--     group, which is precisely why determinism passed within a pair and failed across
--     sessions -- the certification was real but narrower than its name.
--
-- (b) THE SIM START DATE WAS THE ARMING DAY. 0065 pinned the hour and left the date
--     floating; day- and block-lifespan variability is salted by a day number taken from
--     that date, so weather, wind, solar, grid, climate stress and per-dispatch ETA cards
--     all moved every calendar day.
--
-- WHAT THIS DOES NOT TOUCH: production orchestration. ottoq_cert_arm_start is the
-- determinism harness's entry point and has no caller outside it. The A/B group is still
-- written to ottoq_sim_runs.ab_group_id and still drives pairing and scoring; it simply no
-- longer decides which world the run happens in. A post-condition asserts that write
-- survives.
--
-- CONSEQUENCE, recorded because it is a real trade and not a free win: after this, every
-- re-cert at a given seed is the SAME test. That is what makes regression detection
-- trustworthy, and it also means a single passing run stops being evidence of robustness.
-- Robustness comes from sweeping the seed deliberately -- same configuration across N
-- seeds, compared as a distribution. This migration makes that sweep meaningful; it does
-- not perform it.
--
-- Same self-verifying in-place mechanism as 0054-0069. Pre-image pin:
--   public.ottoq_cert_arm_start 00314bb96f99e5beaa6fb2b4cd8b9143
-- Both anchors pre-verified read-only: exactly one occurrence each.

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old_seed text := E'  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || ''wave'', 17));';
  v_new_seed text := E'  /* ══════════ 0070 (a): THE WORLD SEED IS THE RUN SEED, AND NOTHING ELSE ══════════\n     This line mixed the A/B group UUID into the world seed. Every fact about the starting\n     fleet is drawn from v_wseed -- each vehicle''s SoC, which 85 of 100 deploy, and when each\n     returns -- and a fresh group is allocated per re-certification, so the SAME seed produced\n     a DIFFERENT world every time. Both arms of one pair share the group, which is exactly why\n     determinism passed within a pair and failed across sessions.\n     Measured before the change: re-cert #20 drew 7681532243817775720, re-cert #22 drew\n     6347474725636378542, and their deployed sets overlapped 70 of 85 -- 30 vehicles in a\n     different state, the exact discrepancy seen in the tick-1 frames. Proven by prediction\n     rather than correlation: twin.ottoq_sim_seeded_random is IMMUTABLE, so the formula was\n     evaluated independently and matched the arm-time record 85/85 with ZERO error on initial\n     SoC and 85/85 on the deployed set.\n     The group is still recorded on the run and still drives A/B pairing and scoring; it just\n     no longer decides what world the run happens in. This makes common-random-numbers pairing\n     stronger, not weaker. See docs/SEED_REPRODUCIBILITY_DIAGNOSIS.md. */\n  v_wseed := abs(hashtextextended(p_seed::text || ''wave'', 17));';
  v_old_sim0 text := E'  v_sim0 := date_trunc(''day'', v_now) + interval ''22 hours'';';
  v_new_sim0 text := E'  /* ══════════ 0070 (b): PIN THE DAY, NOT JUST THE HOUR ══════════\n     0065 pinned the sim clock to 22:00 so a pair no longer sampled whichever slice the arming\n     minute happened to land on. It pinned the hour and left the calendar day floating. Day-\n     and block-lifespan variability is salted by a day number taken from that day:\n     ottoq_twin_deal builds bucket ''day:''||p_sim_day, which becomes the salt handed to\n     ottoq_sample_calibrated. Weather, wind, solar, the grid, climate stress and per-dispatch\n     ETA cards all read it, so a re-cert one day later drew a different world from an identical\n     seed. Measured at seed 424242 with only the day number varying: wind 5.544 / 9.252 / 7.416\n     km/h across three consecutive days.\n     The reference day is fixed here as a constant, and is deliberately the day the\n     certification baseline was established. AT TIME ZONE ''UTC'' is explicit rather than\n     incidental: the previous expression resolved its day boundary in the session time zone,\n     so a non-UTC session would have shifted the pinned instant.\n     The REAL-domain stamps below still use v_now and still schedule ticks in wall clock; only\n     the SIM domain is pinned, exactly as 0065 established. A controls interface that wants to\n     move the reference day should promote this to a parameter -- that is a signature change,\n     and therefore its own migration, not a body edit. */\n  v_sim0 := (DATE ''2026-08-22'' + interval ''22 hours'') AT TIME ZONE ''UTC'';';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_start';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '00314bb96f99e5beaa6fb2b4cd8b9143' THEN
    RAISE EXCEPTION '0070: pre-image md5 % != pinned 00314bb96f99e5beaa6fb2b4cd8b9143', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_old_seed, ''))) / length(v_old_seed);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0070: seed anchor occurs % times (need 1)', v_cnt; END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_old_sim0, ''))) / length(v_old_sim0);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0070: sim0 anchor occurs % times (need 1)', v_cnt; END IF;

  v_src := replace(v_src, v_old_seed, v_new_seed);
  v_src := replace(v_src, v_old_sim0, v_new_sim0);

  /* Post-conditions. Asserted on the patched source, and deliberately phrased so that no
     comment text in this migration can satisfy them by accident -- the trap 0067 and 0068
     each fell into once. */
  IF position('p_ab_group::text' in v_src) <> 0 THEN
    RAISE EXCEPTION '0070: the A/B group is still being cast into the world seed';
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, 'p_ab_group', ''))) / length('p_ab_group');
  IF v_cnt <> 2 THEN
    RAISE EXCEPTION '0070: expected the group to survive exactly twice (signature + run insert), found %', v_cnt;
  END IF;
  IF position('ab_group_id' in v_src) = 0 THEN
    RAISE EXCEPTION '0070: the run no longer records its A/B group -- pairing would break';
  END IF;
  IF position('hashtextextended(p_seed::text || ''wave''' in v_src) = 0 THEN
    RAISE EXCEPTION '0070: the seed-only world seed is not present';
  END IF;
  IF position('date_trunc(''day''' in v_src) <> 0 THEN
    RAISE EXCEPTION '0070: the sim start is still derived from the arming day';
  END IF;
  IF position('DATE ''2026-08-22''' in v_src) = 0 THEN
    RAISE EXCEPTION '0070: the pinned reference day is not present';
  END IF;

  EXECUTE v_src;
  RAISE NOTICE '0070 patched public.ottoq_cert_arm_start -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_start');
END
$do$;
