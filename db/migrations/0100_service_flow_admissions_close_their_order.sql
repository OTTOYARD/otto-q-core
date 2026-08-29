-- migration-version: 20260830010000
-- migration-name:    service_flow_admissions_close_their_order
-- 0100 -- the V5 sweep, part 2: the same-tick admission cursors inside the service-flow
-- driver (twin.ottoq_sim_advance_service_flow), found by walking determinism pair 6's front
-- one hold upstream (db/checks/0046).
--
-- THREE SITES, same two diseases as 0098/0099:
--   A. WASH ADMISSION: ORDER BY (booking-holder first), q.ord -- and ord's default branch is
--      EXTRACT(EPOCH FROM last_state_change), which TIES for every vehicle that transitioned
--      in the same tick (shared sim clock; the soc_optimized branch can tie on equal SoC
--      too). Below the tie: heap order decides who gets the wash lane. + q.id closes it.
--   B. SERVICE-BAY ADMISSION: ORDER BY (booking-holder first), q.lsc LIMIT <staff cap> --
--      the exact 0098 drain-admission coin flip on the service lane. + q.id closes it.
--   C. LATEST-NEED SUBQUERY: ORDER BY n2.created_at DESC LIMIT 1 -- a 0099-family site the
--      sweep missed because it aliases the needs table as n2. + n2.visit_key DESC closes it
--      (run-stable: vehicle uuid + sim timestamp).
--
-- Behavior is unchanged except exactly at ties (admission POLICY, capacity gates, and
-- booking-holder priority are untouched); ties now close on run-stable fleet identity.
--
-- Pre-image pin, read live 2026-08-29 (each anchor verified at exactly 1 occurrence):
--   twin.ottoq_sim_advance_service_flow   87ae3c50f91a9c60216921742fb40b1c

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := E'     ORDER BY (q.booked_stall IS NULL), q.ord\n';
  v_a_new text := E'     -- 0100: run-stable tiebreak; ord ties on same-tick last_state_change (heap below).\n'
               || E'     ORDER BY (q.booked_stall IS NULL), q.ord, q.id\n';
  v_b_old text := E'     ORDER BY (q.booked_stall IS NULL), q.lsc LIMIT';
  v_b_new text := E'     -- 0100: run-stable tiebreak; lsc ties on same-tick transitions (heap below).\n'
               || E'     ORDER BY (q.booked_stall IS NULL), q.lsc, q.id LIMIT';
  v_c_old text := E'                          ORDER BY n2.created_at DESC LIMIT 1)';
  v_c_new text := E'                          ORDER BY n2.created_at DESC, n2.visit_key DESC LIMIT 1)';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_service_flow';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '87ae3c50f91a9c60216921742fb40b1c' THEN
    RAISE EXCEPTION '0100 abort: advance_service_flow drifted (md5 %)', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0100 abort: wash anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_b_old, ''))) / length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0100 abort: service anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_c_old, ''))) / length(v_c_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0100 abort: n2 anchor found % times', v_cnt; END IF;

  EXECUTE replace(replace(replace(v_src, v_a_old, v_a_new), v_b_old, v_b_new), v_c_old, v_c_new);

  v_src := pg_get_functiondef(v_oid);
  IF position('q.ord, q.id' in v_src) = 0 OR position('q.lsc, q.id' in v_src) = 0
     OR position('n2.visit_key DESC' in v_src) = 0 THEN
    RAISE EXCEPTION '0100 abort: not all three patches survived';
  END IF;

  RAISE NOTICE '0100 applied: service-flow admissions close their order.';
END
$do$;
