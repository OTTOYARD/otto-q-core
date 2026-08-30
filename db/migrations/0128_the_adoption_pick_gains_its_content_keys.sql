-- migration-version: 20260830240000
-- migration-name:    the_adoption_pick_gains_its_content_keys
-- 0128 -- the second 171717/24t carrier, isolated by the 0125 instrument by ELIMINATION
-- (0046 pairs 55-56): with the interrupted-booking leak closed (0127), pair 55 passed
-- with bookings.fgn = 0 in both arms; pair 56 then forked streams with the arms' BOOT
-- IMAGES IDENTICAL across all five fingerprinted tables -- so the carrier had to be
-- heap-order-fed randomness, not content. The archaeology's primal write: at sim 03:00
-- the planner adopts one of vehicle 5cee8fb3's tied forward wash-bay reservations --
-- WSH-02 in one arm, WSH-03 in the other -- and the 14:00 enter_wash follows it.
--
-- The site convicts itself in its own comment. ottoq_record_enacted_booking's
-- forward-reservation ADOPTION pick reads:
--     ORDER BY b.booked_at DESC,   /* 0063: same non-total pick as enact_space... */
--              lower(b.during) DESC, upper(b.during) DESC, b.booking_id DESC LIMIT 1;
-- booked_at defaults to now() -- FROZEN inside a pair transaction, so same-sweep
-- candidates tie -- the windows of the tied candidates are equal -- and the pick falls
-- to booking_id, a random uuid: total WITHIN an arm, RANDOM BETWEEN arms. Its sibling
-- in ottoq_enact_space_assignment was already fixed the right way (content keys s.id,
-- b.purpose before the uuid); this site never got them. The two tied candidates differ
-- exactly in stall_id -- the content key that is missing.
--
-- FIX (the 0062/0063 discipline, completed): content keys before the uuid last-resort --
--     ... lower(b.during) DESC, upper(b.during) DESC, b.stall_id, b.purpose,
--         b.booking_id DESC LIMIT 1;
-- booking_id survives only for candidates byte-identical in every content field.
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 1 occurrence):
--   ottoq.ottoq_record_enacted_booking   b6fcb932ba8e8d47d8fca1f08b892d6a

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := 'lower(b.during) DESC, upper(b.during) DESC, b.booking_id DESC LIMIT 1;';
  v_new text := 'lower(b.during) DESC, upper(b.during) DESC, b.stall_id, b.purpose, b.booking_id DESC LIMIT 1;  -- 0128: content keys before the uuid; the adoption pick was random between cert arms';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'b6fcb932ba8e8d47d8fca1f08b892d6a' THEN
    RAISE EXCEPTION '0128 abort: record_enacted_booking drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0128 abort: anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_old, v_new);
  IF position('the adoption pick was random between cert arms' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0128 abort: patch did not survive';
  END IF;
  RAISE NOTICE '0128 applied: the adoption pick gains its content keys.';
END
$patch$;
