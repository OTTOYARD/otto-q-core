-- migration-version: 20260830070000
-- migration-name:    the_run_draws_its_own_world
-- 0107 -- pair 11 (seed 171717, first seed tried after the 424242 certification) diverged at
-- TICK 1: one arm's manifest for vehicle 58f68551 carried an exterior_wash atom, the other's
-- did not, and the runs forked from there (742 vs 768 commands). World fingerprints MATCHED,
-- so the leak is state the fingerprint does not cover:
--
--   vehicle_need_profile -- the rich per-vehicle needs profile (last_wash_at,
--   last_calibration_at, last_pm_at, soil, faults, ...) -- is PERSISTENT and mutated by
--   every run. The witness row's drawn_for_run was a run from a different day, seed 777012:
--   nothing on the harness path ever redraws it. generate_service_manifest's wash backstop
--   divides hours-since-last_wash_at; arm A inherited an overdue clock (-> wash atom), then
--   arm A's own wash stamped the clock fresh, so arm B saw no overdue (-> no atom).
--
--   The 424242 pairs passed because CONSECUTIVE IDENTICAL RUNS form a fixpoint: each arm
--   inherited the identical output-profile of an identical run. Real equality, wrong
--   mechanism -- the equality lived in the sequence of runs, not in the seed. Seed 171717,
--   arriving after the 424242 orbit, broke it immediately. This is V3's lesson one table
--   further out: SAME SEED MUST MEAN SAME STARTING WORLD, ALL of it.
--
-- The redraw machinery already exists and is already deterministic:
-- public.ottoq_run_boot_draw -> ottoq_seed_vehicle_need_profiles is a full
-- ON CONFLICT DO UPDATE whose every clock is drawn as (run's sim clock - seeded offset)
-- ('vnp:*' salts keyed by vehicle id -- persistent fixtures). It simply is not on
-- twin.ottoq_sim_start_run's path; only ottoq_sim_run_scenario calls it.
--
-- TWO PATCHES:
--   A. twin.ottoq_sim_start_run: after the 0092 GUC pin and BEFORE the 0093 fingerprint
--      stamp, run public.ottoq_run_boot_draw(v_run_id) -- so every run started through this
--      entry point derives its whole starting world from its own seed, and the fingerprint
--      then covers the drawn state. Failure-isolated with a WARNING, matching
--      run_boot_draw's own internal posture ("a profile failure must NEVER abort a run
--      boot"). For callers that later boot-draw again the redraw is idempotent by
--      determinism (same seed, same values).
--   B. ottoq.ottoq_world_fingerprint gains a fourth section: the depot's
--      vehicle_need_profile rows (jsonb key-sorted row image, minus the wall-clock and
--      per-run bookkeeping columns drawn_at / updated_at / drawn_for_run /
--      wear_km_applied_run). A leak of this class now shows up as a fingerprint mismatch at
--      start, not as a 12-tick divergence hunt.
--
-- CANONICAL VALUES CHANGE, on purpose: the pre-0107 fingerprint 3c903a8f and the pair-9/10
-- stream hashes in db/checks/0046 describe the inherited-fixpoint world; post-0107 runs draw
-- a fresh world per seed, so new canonicals are recorded by the pair-12/13 runs in 0046.
--
-- Pre-image pins, read live 2026-08-30 (each anchor verified at exactly 1 occurrence):
--   twin.ottoq_sim_start_run       032bc71933431ca98334f17bd7d07db3
--   ottoq.ottoq_world_fingerprint  7cac36a77f7e908f11c53a5fae3e9236

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  -- A: insert the boot draw between the 0092 pin and the 0093 fingerprint.
  v_a_old text := E'  PERFORM set_config(''ottoq.sim_run_id'', v_run_id::text, true);\n\n  -- 0093:';
  v_a_new text := E'  PERFORM set_config(''ottoq.sim_run_id'', v_run_id::text, true);\n\n'
               || E'  -- 0107: THE RUN DRAWS ITS OWN WORLD. vehicle_need_profile is persistent state\n'
               || E'  -- every run mutates (last_wash_at et al.); without a per-run redraw each run\n'
               || E'  -- inherits the previous run''s clocks (pair 11: one arm washed a vehicle the\n'
               || E'  -- other did not). Deterministic per seed; runs BEFORE the fingerprint stamp\n'
               || E'  -- so the stamp covers the drawn state.\n'
               || E'  BEGIN\n'
               || E'    PERFORM public.ottoq_run_boot_draw(v_run_id);\n'
               || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''run boot draw failed: %'', SQLERRM;\n'
               || E'  END;\n\n  -- 0093:';

  -- B: append the profile section before the fingerprint's closing paren.
  v_b_old text := E'), '''')\n  )';
  v_b_new text := E'), '''')\n    || ''#'' ||\n'
               || E'    -- 0107: the needs profile is start-relevant world (pair-11 finding). Row image\n'
               || E'    -- minus wall-clock / per-run bookkeeping; jsonb text output is key-sorted.\n'
               || E'    COALESCE((SELECT string_agg(np.vehicle_id::text||''|''||\n'
               || E'                 (to_jsonb(np) - ''drawn_at'' - ''updated_at'' - ''drawn_for_run'' - ''wear_km_applied_run'')::text,\n'
               || E'                 E''\\n'' ORDER BY np.vehicle_id)\n'
               || E'                FROM public.vehicle_need_profile np\n'
               || E'                JOIN public.vehicles v2 ON v2.id = np.vehicle_id\n'
               || E'               WHERE v2.home_depot_id = p_depot AND v2.category=''autonomous''), '''')\n  )';
BEGIN
  -- ---------- A ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_run';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '032bc71933431ca98334f17bd7d07db3' THEN
    RAISE EXCEPTION '0107 abort: start_run drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_a_old,'')))/length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0107 abort: start_run anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_a_old, v_a_new);
  IF position('ottoq_run_boot_draw' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0107 abort: start_run patch did not survive';
  END IF;

  -- ---------- B ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '7cac36a77f7e908f11c53a5fae3e9236' THEN
    RAISE EXCEPTION '0107 abort: world_fingerprint drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_b_old,'')))/length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0107 abort: fingerprint anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_b_old, v_b_new);
  IF position('vehicle_need_profile np' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0107 abort: fingerprint patch did not survive';
  END IF;

  RAISE NOTICE '0107 applied: the run draws its own world, and the fingerprint covers it.';
END
$do$;
