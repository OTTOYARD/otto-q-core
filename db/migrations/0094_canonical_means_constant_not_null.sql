-- migration-version: 20260829223000
-- migration-name:    canonical_means_constant_not_null
-- 0094 -- corrects 0093 patch D, caught by the world-bleed probe ON ITS FIRST EXERCISE:
-- ottoq_ocpp_chargers.station_state_changed_at is NOT NULL, so the 0093 charger
-- canonicalization ("set the fault clock to NULL") raised 23502 and made the CRN reset
-- unrunnable. A green light that was never exercised would have hidden this; the probe fired
-- it immediately (a check that cannot fail is not a check).
--
-- Canonical means CONSTANT, not NULL: the reset now pins the fault clock to the epoch --
-- deterministic across resets, honest about being a reset value, and legal under the schema.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_tick_invariance_reset_fleet   b71009dea0bbcc315adaa60ecc6ad089  (post-0093)

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  v_a_old text := E'     SET station_state = ''Available'', last_fault_code = NULL,\n'
               || E'         station_state_changed_at = NULL\n';
  v_a_new text := E'     SET station_state = ''Available'', last_fault_code = NULL,\n'
               || E'         -- 0094: the column is NOT NULL; canonical means a CONSTANT, not an absence.\n'
               || E'         station_state_changed_at = ''epoch''::timestamptz\n';

  v_b_old text := E'          OR c.last_fault_code IS NOT NULL OR c.station_state_changed_at IS NOT NULL);';
  v_b_new text := E'          OR c.last_fault_code IS NOT NULL\n'
               || E'          OR c.station_state_changed_at IS DISTINCT FROM ''epoch''::timestamptz);';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'b71009dea0bbcc315adaa60ecc6ad089' THEN
    RAISE EXCEPTION '0094 abort: reset_fleet drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0094 abort: SET anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_b_old, ''))) / length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0094 abort: WHERE anchor found % times', v_cnt; END IF;

  EXECUTE replace(replace(v_src, v_a_old, v_a_new), v_b_old, v_b_new);

  IF position('canonical means a CONSTANT' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0094 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0094 applied: charger canonicalization is constant-valued and legal.';
END
$do$;
