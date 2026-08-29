-- migration-version: 20260830050000
-- migration-name:    the_tech_verdict_is_not_a_coin_from_another_run
-- 0104 -- kills the determinism pair-7 front at its actual root: twin.ottoq_opportunistic_scan.
--
-- HOW IT WAS PINNED (pair 7, arms 2ebf111d/4f203026, tick 3 = sim 03:30):
--   * The first divergent DECISION content is position 66 (77ecd026's stall_assignment:
--     06acce00 in arm A, 321e4142 in arm B). Positions 1-65 byte-identical.
--   * The (3b) intake pick that made decision 66 is already total-ordered
--     ((staging_role='temp') DESC, distance, s.id) -- so a different winner means different
--     AVAILABILITY: in arm B the better stall 06acce00 (distance 131 < 161) was already
--     reserved by bc55d859's co-tick 30-minute temp_hold.
--   * That hold is written by the WORLD phase (before every decision):
--     twin.ottoq_opportunistic_scan -> ottoq_enact_opportunistic_charge -> book_hold_stall.
--   * 0046's earlier hypothesis ("the 5-minute holds pre-claim the decision's stall") was
--     INVERTED by this trace: the 5- and 15-minute hold families are written by
--     ottoq_place_unplaced_vehicles AFTER decide_tick -- they are victims of the cascade,
--     not its cause. The ledger shows them permuting one position downstream of the root.
--
-- TWO DEFECTS, ONE FUNCTION:
--   1. THE COIN IS NOT RUN-STABLE. The simulated tech verdict draws
--        ottoq_sim_seeded_random(v_seed, approval_id::text || ':decide')
--      and ottoq_ops_approvals.approval_id defaults to gen_random_uuid() -- a fresh random
--      uuid every run. Same seed, same vehicle, same tick: different coin. Ledger proof:
--      vehicle 5f8af8a5's opportunistic_charge was DECLINED in arm A and APPROVED in arm B;
--      814c9bc7 the reverse. An approved verdict books a 30-minute hold and moves the
--      vehicle; a declined one does nothing -- whole downstream families of bookings appear
--      and vanish with the flip (15-min holds: 20 vs 19; 30-min holds: 5 vs 6).
--      This is the 0054 rule verbatim: a per-run random uuid is never a determinism key.
--      A live sweep of every ottoq_sim_seeded_random call in public/twin/ottoq confirms this
--      is the ONLY salt keyed by a per-run random id.
--   2. THE CURSOR HAS NO ORDER BY. The verdict loop iterates pending approvals in heap
--      order. Each approved row consumes a stall from the shared staging pool, so even with
--      identical verdicts the vehicle->stall pairing permutes with the heap.
--
-- THE FIX, in place, anchored:
--   A. Cursor SELECT gains ap.requested_at (needed for the new salt).
--   B. Cursor gains ORDER BY ap.requested_at, ap.vehicle_id, ap.approval_type -- all three
--      run-stable (requested_at is sim-domain; vehicle ids are persistent fixtures).
--   C. The draw re-keys to 'techdecide:' || vehicle_id || ':' || approval_type || ':' ||
--      epoch(requested_at) -- run-stable identity, distinct per approval, and two arms of
--      one seed now flip the same coin. (Two same-typed approvals for one vehicle at the
--      same sim second would share a verdict -- deterministic, and no such pair exists in
--      any archived run.)
--   Approval probabilities, ownership filter (0002), expiry sweep: untouched.
--
-- Pre-image pin, read live 2026-08-29 (each anchor verified at exactly 1 occurrence):
--   twin.ottoq_opportunistic_scan   48689a1ea7601514d8eac2641ce0fc6f

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  v_sel_old text := 'SELECT ap.approval_id, ap.approval_type, ap.vehicle_id, v.current_soc';
  v_sel_new text := 'SELECT ap.approval_id, ap.approval_type, ap.vehicle_id, ap.requested_at, v.current_soc';

  v_loop_old text := E'AND ap.decide_after <= p_clock AND ap.expires_at > p_clock\n  LOOP';
  v_loop_new text := E'AND ap.decide_after <= p_clock AND ap.expires_at > p_clock\n'
                  || E'     -- 0104: run-stable total order; the heap decided who charged where.\n'
                  || E'     ORDER BY ap.requested_at, ap.vehicle_id, ap.approval_type\n  LOOP';

  v_draw_old text := 'ottoq_sim_seeded_random(v_seed, v_rec.approval_id::text || '':decide'')';
  v_draw_new text := 'ottoq_sim_seeded_random(v_seed, ''techdecide:'' || v_rec.vehicle_id::text'
                  || ' || '':'' || v_rec.approval_type || '':'' || extract(epoch from v_rec.requested_at)::bigint::text)';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_opportunistic_scan';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '48689a1ea7601514d8eac2641ce0fc6f' THEN
    RAISE EXCEPTION '0104 abort: opportunistic_scan drifted (md5 %)', md5(v_src);
  END IF;

  v_cnt := (length(v_src)-length(replace(v_src, v_sel_old,'')))/length(v_sel_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0104 abort: select anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_loop_old,'')))/length(v_loop_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0104 abort: loop anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_draw_old,'')))/length(v_draw_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0104 abort: draw anchor found % times', v_cnt; END IF;

  v_src := replace(v_src, v_sel_old,  v_sel_new);
  v_src := replace(v_src, v_loop_old, v_loop_new);
  v_src := replace(v_src, v_draw_old, v_draw_new);
  EXECUTE v_src;

  v_src := pg_get_functiondef(v_oid);
  IF position('techdecide:' in v_src) = 0
     OR position('ORDER BY ap.requested_at, ap.vehicle_id, ap.approval_type' in v_src) = 0
     OR position('approval_id::text || '':decide''' in v_src) > 0 THEN
    RAISE EXCEPTION '0104 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0104 applied: the tech verdict flips a run-stable coin, in a run-stable order.';
END
$do$;
