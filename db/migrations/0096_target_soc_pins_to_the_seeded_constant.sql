-- migration-version: 20260829233000
-- migration-name:    target_soc_pins_to_the_seeded_constant
-- 0096 -- corrects 0095, caught (again) by the probe on first exercise: vehicles.target_soc is
-- NOT NULL (default 100), so pinning it NULL raised 23502. Same lesson as 0094: canonical
-- means a CONSTANT, not an absence. The seeded fleet rests at 90 (the run had bumped 2
-- vehicles to 100, which is the drift 0095 set out to kill), so the CRN reset pins 90.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_tick_invariance_reset_fleet   425833cd84ea089002f8cd53d5b119df  (post-0095)

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := E'         target_soc = NULL,\n';
  v_a_new text := E'         -- 0096: NOT NULL column; canonical means a CONSTANT (seeded fleet rests at 90).\n'
               || E'         target_soc = 90,\n';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '425833cd84ea089002f8cd53d5b119df' THEN
    RAISE EXCEPTION '0096 abort: reset_fleet drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0096 abort: anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_a_old, v_a_new);
  IF position('target_soc = 90' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0096 abort: patch did not survive';
  END IF;
  RAISE NOTICE '0096 applied: target_soc pinned to the seeded constant.';
END
$do$;
