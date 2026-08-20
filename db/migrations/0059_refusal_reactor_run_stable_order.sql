-- migration-version: 20260820160000
-- migration-name:    refusal_reactor_run_stable_order
-- 0059 — C7 FOLLOW-UP #13, found by re-certification #13 (post-0058 arms
-- bb74e241 vs 0b490fb0: 12/20 identical, first divergence sim-min 390). The
-- 0058 card fix HOLDS: eta_delay card sets are behaviorally identical per
-- vehicle across the arms (the apparent diff rows were multi-dispatch join
-- artifacts) and zero charger-fault cards dealt a fault in either arm. The
-- full event-stream positional diff pins the first divergent event exactly:
-- run B reserves two stalls (67daf51e, 891e775f) IMMEDIATELY BEFORE the
-- refusal-reactor batch while run A reserves them immediately AFTER — the
-- reactor processed vehicle 0bfd4d59's refused command FIRST in B (rerouting
-- it into those stalls) and LAST in A (four other vehicles escalated
-- no_capacity first). The reactor's loop is capacity-consuming (reserve-first
-- walk), so its processing order decides WHO gets the free stalls and WHO
-- escalates; by tick 13 four gate vehicles hold different stalls/states.
--
-- ROOT CAUSE — the 0050/0054 unordered-cursor class, one level subtler:
-- ottoq.ottoq_react_to_refusals orders its cursor by issued_at ALONE, and
-- issued_at is the per-tick sim-clock stamp shared by every command in the
-- batch (measured: up to 72 commands on one stamp). Within a tick the ORDER
-- BY is therefore no order at all — heap order decides, per run. The 0054
-- sweep missed it because the cursor HAS an ORDER BY; the key is just
-- insufficient. Schema-wide re-sweep of ottoq found no other offender:
-- ottoq_stall_free_between orders by (distance_from_entrance, stall_code),
-- and release_expired_bookings' unordered loop is commutative (set-based
-- release; only event emission order varies, which the frame digest does not
-- score).
--
-- THE FIX: run-stable tiebreak on the reactor cursor —
-- (issued_at, vehicle_id, command_type, refused target stall). Any remaining
-- tie is two byte-identical commands, where order is behaviorally
-- indifferent. Engine semantics otherwise untouched; the LIMIT 20 batch now
-- also SELECTS a deterministic subset, not just processes one in order.
--
-- Same self-verifying in-place mechanism as 0054-0058. Pre-image pin:
--   ottoq.ottoq_react_to_refusals 60987f9b3c1d702b5a618a8ae73511d5

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := E'     ORDER BY issued_at\n     LIMIT 20';
  v_new text := E'     /* 0059: issued_at is the per-tick sim-clock stamp (up to 72 commands\n        share one value), so alone it is heap order. Run-stable tiebreak:\n        vehicle, command type, refused target stall. */\n     ORDER BY issued_at, vehicle_id, command_type, payload->>''stall_id''\n     LIMIT 20';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'ottoq' AND pr.proname = 'ottoq_react_to_refusals';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '60987f9b3c1d702b5a618a8ae73511d5' THEN
    RAISE EXCEPTION '0059: pre-image md5 % != pinned 60987f9b3c1d702b5a618a8ae73511d5', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0059: anchor occurs % times (need 1)', v_cnt;
  END IF;
  EXECUTE replace(v_src, v_old, v_new);
  RAISE NOTICE '0059 patched ottoq.ottoq_react_to_refusals -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'ottoq' AND pr.proname = 'ottoq_react_to_refusals');
END
$do$;
