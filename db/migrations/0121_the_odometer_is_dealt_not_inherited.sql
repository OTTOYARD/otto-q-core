-- migration-version: 20260830200000
-- migration-name:    the_odometer_is_dealt_not_inherited
-- 0121 -- closes the last known fp-noise driver (0046 pairs 27-28; db/checks/0049 rank 1).
-- config.lifetime_miles accrues through the arrival-payload round-trip
-- (twin.ottoq_sim_build_arrival_payload emits odometer = lifetime_miles + dispatch miles;
-- the ingest path writes it back), the 0095 whitelist keeps it, and the fingerprint hashes
-- it -- so the first cert boot after a foreign lineage always carries the previous
-- lineage's mileage and boots off-fixpoint, with byte-equal streams.
--
-- FIX, the V3 idiom: ottoq_tick_invariance_reset_fleet DEALS the odometer from the seed --
-- round(500 + 79000 * power(r,2)) miles, salt 'veh_lifemiles:'||vehicle -- matching the
-- live fleet's measured scale (100 vehicles, 500..79,174, mean ~23k; the power-2 skew is
-- the boot draw's own idiom and lands the mean at ~26k). Demo/production worlds are
-- untouched (only the cert reset deals it); in-run accrual still works and simply gets
-- re-dealt at the next cert boot. The need-profile's odometer_km derives from this value,
-- so profile priors become seed-pure too.
--
-- Prediction (falsifiable, again): pairs 29-31 (171717 -> 424242 -> 171717) must show
-- BOTH arms at one fp per seed AND pair 31 booting at pair 29's exact fp -- true
-- cross-lineage fixpoints, retiring the fp caveat in 0046. If any first arm still
-- differs, another member exists and the caveat stands.
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 1 occurrence):
--   public.ottoq_tick_invariance_reset_fleet   b767c8c468c88c49d9b5bb4ea87fef78  (post-0120)

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := 'jsonb_build_object(''cycles_since_wash'', 1)';
  v_new text := 'jsonb_build_object(''cycles_since_wash'', 1,'
             || E'\n                       -- 0121: the odometer is DEALT from the seed, not inherited from the'
             || E'\n                       -- lineage (it accrues in-run via the arrival-payload round-trip).'
             || E'\n                       ''lifetime_miles'', round(500 + 79000 * power(twin.ottoq_sim_seeded_random(p_seed, ''veh_lifemiles:'' || v.id::text), 2)))';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'b767c8c468c88c49d9b5bb4ea87fef78' THEN
    RAISE EXCEPTION '0121 abort: reset_fleet drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_old,'')))/length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0121 abort: anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_old, v_new);
  IF position('DEALT from the seed' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0121 abort: patch did not survive';
  END IF;
  -- 0121b lesson: a text post-check cannot catch a call-time error (the first cut named
  -- public.ottoq_sim_seeded_random; it lives in twin, and every cert reset aborted until
  -- the cron failures surfaced it). The post-condition that bites: execute the reset.
  PERFORM public.ottoq_tick_invariance_reset_fleet('11111111-1111-1111-1111-111111111111'::uuid, 42);
  RAISE NOTICE '0121 applied: the odometer is dealt, not inherited, and the reset executes clean.';
END
$patch$;
