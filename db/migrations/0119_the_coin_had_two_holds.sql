-- migration-version: 20260830180000
-- migration-name:    the_coin_had_two_holds
-- 0119 -- the Y/Z bistability of pairs 18/23/24 (db/checks/0046), run to ground. Vehicle
-- 87098f16's exception flow left it holding TWO live perimeter_hold bookings with the SAME
-- upper bound (03:30->12:00 and 04:07:06->12:00; identical rows in both arms). At the
-- deferred-eviction resume, twin.ottoq_sim_vehicle_exception_handler selects "the vehicle's
-- live booking" with
--
--     ORDER BY upper(b.during) DESC LIMIT 1;
--
-- -- upper() TIES, heap order picks, and each arm interrupts a DIFFERENT hold (ledger
-- proof: the two arms' booking_interrupted payloads differ by exactly the 37m06s gap
-- between the holds' lower bounds -- planned_min 510.00 vs 472.90). The cascade re-stages
-- the horizon arrival on whichever stall the interrupt freed, which is the single
-- differing command the pairs measured. The 0054 disease, verbatim, at one more site --
-- and the same cursor appears TWICE (deferred resume + the immobilizing path).
--
-- FIX: stable tail on both occurrences -- latest-ending, then latest-STARTING (the most
-- recent claim is the one the vehicle actually occupies), then stall_id as the absolute
-- closer. Never booking_id (a per-run uuid is never a determinism key -- 0054).
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 2 occurrences):
--   twin.ottoq_sim_vehicle_exception_handler   462ac04d684288bf04a507b796ed188d

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := 'ORDER BY upper(b.during) DESC LIMIT 1;';
  v_new text := 'ORDER BY upper(b.during) DESC, lower(b.during) DESC, b.stall_id LIMIT 1;  -- 0119: upper() ties between sibling holds; run-stable tail';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_vehicle_exception_handler';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '462ac04d684288bf04a507b796ed188d' THEN
    RAISE EXCEPTION '0119 abort: exception handler drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_old,'')))/length(v_old);
  IF v_cnt <> 2 THEN RAISE EXCEPTION '0119 abort: anchor found % times, expected 2', v_cnt; END IF;
  EXECUTE replace(v_src, v_old, v_new);
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src)-length(replace(v_src, 'run-stable tail','')))/length('run-stable tail');
  IF v_cnt <> 2 THEN RAISE EXCEPTION '0119 abort: patch survived % of 2 sites', v_cnt; END IF;
  RAISE NOTICE '0119 applied: both eviction cursors close their ties deterministically.';
END
$patch$;
