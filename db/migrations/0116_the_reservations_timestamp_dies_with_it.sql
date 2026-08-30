-- migration-version: 20260830150000
-- migration-name:    the_reservations_timestamp_dies_with_it
-- 0116 -- the post-0115 cross-seed pair (424242 after a 171717 pair; db/checks/0046 pair 20)
-- produced the pair-14(a) signature under the new fingerprint: ALL FOUR STREAMS BYTE-EQUAL,
-- fingerprints UNEQUAL. Root: stalls.reserved_at. ottoq_reserve_stall stamps it (sim
-- domain), the fingerprint covers it (it always has), and NO teardown clears it --
-- release_depot clears reserved_by and reservation_expires_at but leaves the timestamp of
-- the dead reservation on the row. Measured on the flagship at diagnosis: 158 stalls
-- carrying an orphaned reserved_at (reserved_by NULL) across 12 distinct values -- the
-- previous runs' reservation pattern, varying with predecessor SEED, hence fp-unequal arms
-- with identical behavior (readers gate on reserved_by/reservation_expires_at).
--
-- FIX: the reservation's timestamp dies with the reservation, at both 0114 clear sites
-- (world-reset and ledger-only -- an orphaned timestamp is dead bookkeeping in any feed
-- mode). One-time repair clears the standing orphans. Canonical fingerprints re-minted
-- after this in db/checks/0046.
--
-- Pre-image pin, read live 2026-08-30 (anchors verified at exactly 1 occurrence each):
--   public.ottoq_sim_release_depot   eaaa41969b670a94f6ce29fd833ec880  (post-0114)

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := E'    UPDATE stalls SET current_vehicle_id=NULL, reserved_by=NULL, reservation_expires_at=NULL\n'
               || E'     WHERE depot_id = v_depot\n'
               || E'       AND (current_vehicle_id IS NOT NULL OR reserved_by IS NOT NULL\n'
               || E'            OR reservation_expires_at IS NOT NULL);';
  v_a_new text := E'    UPDATE stalls SET current_vehicle_id=NULL, reserved_by=NULL, reservation_expires_at=NULL,\n'
               || E'           reserved_at=NULL  -- 0116: the reservation''s timestamp dies with it\n'
               || E'     WHERE depot_id = v_depot\n'
               || E'       AND (current_vehicle_id IS NOT NULL OR reserved_by IS NOT NULL\n'
               || E'            OR reservation_expires_at IS NOT NULL OR reserved_at IS NOT NULL);';
  v_b_old text := E'    UPDATE stalls SET reserved_by=NULL, reservation_expires_at=NULL\n'
               || E'     WHERE depot_id = v_depot\n'
               || E'       AND (reserved_by IS NOT NULL OR reservation_expires_at IS NOT NULL);';
  v_b_new text := E'    UPDATE stalls SET reserved_by=NULL, reservation_expires_at=NULL,\n'
               || E'           reserved_at=NULL  -- 0116: dead bookkeeping in any feed mode\n'
               || E'     WHERE depot_id = v_depot\n'
               || E'       AND (reserved_by IS NOT NULL OR reservation_expires_at IS NOT NULL\n'
               || E'            OR reserved_at IS NOT NULL);';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_release_depot';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'eaaa41969b670a94f6ce29fd833ec880' THEN
    RAISE EXCEPTION '0116 abort: release_depot drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_a_old,'')))/length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0116 abort: world-reset anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_b_old,'')))/length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0116 abort: ledger-only anchor found % times', v_cnt; END IF;
  v_src := replace(v_src, v_a_old, v_a_new);
  v_src := replace(v_src, v_b_old, v_b_new);
  EXECUTE v_src;
  IF position('the reservation''s timestamp dies with it' in pg_get_functiondef(v_oid)) = 0
     OR position('dead bookkeeping in any feed mode' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0116 abort: patch did not survive';
  END IF;
END
$patch$;

-- one-time repair: the standing orphans (a reserved_at with no live reservation)
DO $repair$
DECLARE v_n int;
BEGIN
  UPDATE stalls SET reserved_at = NULL
   WHERE reserved_by IS NULL AND reserved_at IS NOT NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE '0116 applied: reserved_at cleared at both release sites; % standing orphans repaired.', v_n;
END
$repair$;
