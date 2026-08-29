-- migration-version: 20260830000000
-- migration-name:    the_drain_admission_is_not_a_coin_flip
-- 0098 -- check 0046's in-run nondeterminism, third pair (A4/B4, arms 02ad9218/40cd6a63,
-- identical world fingerprints, approvals expired per 0097), bisected to ONE ROW:
--
--   Ticks 1 AND 2 byte-identical (0097 moved the divergence horizon from tick 2 to tick 3 --
--   the approvals mechanism was real and is dead). At tick 3, position 21 of the
--   stall_assignment stream: arm A processes vehicle bc55d859, arm B never does; every later
--   assignment shifts by one and the arms never re-converge. The vehicle differed in exactly
--   one way: at tick 2, arm A gave it the extra transition staged_for_departure ->
--   staged_awaiting_service -- an OVERNIGHT-DRAIN ADMISSION -- and arm B admitted some other
--   vehicle into that slot.
--
-- THE CURSOR (ottoq.ottoq_plan_overnight_drain_admissions):
--
--     ORDER BY jsonb_array_length(config->'deferred_services') DESC, last_state_change
--     LIMIT v_admit
--
-- Every vehicle that transitioned in the same tick carries the SAME last_state_change (the
-- sim clock), and same-sized deferred lists are common -- so the LIMIT-3 admission breaks its
-- ties in heap order. Which vehicle gets the last drain slot is a coin flip, and the admitted
-- vehicle's entire subsequent path (charge queue membership, stall pairings, session timings)
-- cascades from it. This is the 0054/0067 disease -- "the score is byte-identical for two
-- rows, so LIMIT returned heap order" -- at a site both passes missed (the function predates
-- neither; it was carved out of the fused drain later).
--
-- ONE PATCH: the standard run-stable tiebreak. `id` closes the order absolutely; the score
-- (deferred count, then oldest transition) still dominates, so admission POLICY is unchanged
-- -- this only decides among vehicles that were already indistinguishable.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   ottoq.ottoq_plan_overnight_drain_admissions   6ff4de95a332a387f3962ab8e609c2e8

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := E'         ORDER BY jsonb_array_length(config->''deferred_services'') DESC, last_state_change\n'
               || E'         LIMIT v_admit';
  v_a_new text := E'         -- 0098: run-stable tiebreak. Same-tick transitions share last_state_change\n'
               || E'         -- (the sim clock), so without this the LIMIT admits in heap order.\n'
               || E'         ORDER BY jsonb_array_length(config->''deferred_services'') DESC, last_state_change, id\n'
               || E'         LIMIT v_admit';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_plan_overnight_drain_admissions';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '6ff4de95a332a387f3962ab8e609c2e8' THEN
    RAISE EXCEPTION '0098 abort: drain admissions planner drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0098 abort: cursor anchor found % times', v_cnt; END IF;

  EXECUTE replace(v_src, v_a_old, v_a_new);

  IF position('run-stable tiebreak' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0098 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0098 applied: drain admission order is closed; no coin flips.';
END
$do$;
