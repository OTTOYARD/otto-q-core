-- migration-version: 20260830190000
-- migration-name:    the_whitelist_kept_a_moving_part
-- 0120 -- the last known driver of cross-lineage fingerprint variance (0046 pairs 22/26:
-- streams canon-exact, first-arm fp differing). ottoq_tick_invariance_reset_fleet's 0095
-- whitelist rebuild keeps 'last_calibration_at' as durable identity -- but the engine
-- MUTATES it in-run (ottoq_wear_mark_serviced stamps it, sim-domain, on every completed
-- calibration), so it leaks through every reset carrying the lineage's calibration
-- history straight into the fp-hashed config. Reader sweep: NOTHING reads the config
-- copy -- the need-profile seeder only names its own column (its calibration prior is a
-- seeded draw), and the only other mentions are the writer and this whitelist. Write-only
-- residue: dropping it from the keep-list changes no behavior, only kills the noise.
-- ('lifetime_miles' stays: no in-run writer exists, so it is genuinely durable.)
--
-- Prediction this migration made (the falsifiable kind): with the key dropped, alternating
-- seeds reach TRUE fp fixpoints. OUTCOME (0046 pairs 27-28): correct but INSUFFICIENT --
-- pair 27 passes on a new same-seed fixpoint (c525a339), but the first-arm-after-foreign-
-- lineage variance survives via ONE more key: lifetime_miles, whose writer hides behind
-- the arrival-payload round-trip (emit odometer -> ingest writes it back). That close is
-- the next leg; streams are canon-exact throughout.
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 1 occurrence):
--   public.ottoq_tick_invariance_reset_fleet   f90aeb338978446d343a9bb60637f52f

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := '''lifetime_miles'',''last_calibration_at'',''battery_chemistry'',';
  v_new text := '''lifetime_miles'',''battery_chemistry'',  -- 0120: last_calibration_at is run-mutated (wear_mark_serviced) and read by nothing; a whitelist keeps only STILL parts';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'f90aeb338978446d343a9bb60637f52f' THEN
    RAISE EXCEPTION '0120 abort: reset_fleet drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_old,'')))/length(v_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0120 abort: anchor found % times (layout drift?)', v_cnt;
  END IF;
  EXECUTE replace(v_src, v_old, v_new);
  IF position('a whitelist keeps only STILL parts' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0120 abort: patch did not survive';
  END IF;
  RAISE NOTICE '0120 applied: the whitelist no longer keeps a moving part.';
END
$patch$;
