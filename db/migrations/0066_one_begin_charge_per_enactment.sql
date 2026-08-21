-- migration-version: 20260821050000
-- migration-name:    one_begin_charge_per_enactment
-- 0066 -- THE DUPLICATE EMIT. public.ottoq_decide_tick issues TWO begin_charge commands
-- for every single stall enactment.
--
-- THE DEFECT: both emits sit inside the SAME `IF ottoq_reserve_stall(...) THEN` branch,
-- with no conditional between them -- the first near the top of the branch carrying
-- ('stall_id','stall_type','new_state'), the second at the bottom carrying
-- ('stall_id','stall_type','requested_kw'). They are strictly sequential, so both fire
-- on every enactment, for the same vehicle, the same stall and the same tick. The
-- ledger shows the lockstep exactly: in re-cert #18 arm A (run da724f40),
-- 589 target_occupied refusals on the new_state variant and 584 on the requested_kw
-- variant.
--
-- WHY IT MATTERS MORE THAN IT LOOKS:
--   1. It halves the refusal reactor. ottoq.ottoq_react_to_refusals drains its queue
--      with LIMIT 20 per tick against an unbounded backlog -- in #18 arm A it never
--      examined 926 of 1,286 refusals. Roughly half of that 20-per-tick budget is spent
--      re-reading a duplicate row of a decision it has already handled. Removing the
--      duplicate doubles the reactor's effective throughput at zero cost, and it is the
--      cheapest of the livelock fixes by a wide margin.
--   2. It is the source of the byte-tied duplicate rows that broke the supersede
--      ordering in re-cert #16 and forced 0062. Two commands sharing vehicle,
--      issued_at, command_type AND stall_id are indistinguishable to any content key;
--      0062 had to fall back to command_id to restore a total order. With one emit per
--      enactment that tie class stops being manufactured in the first place.
--   3. It doubles every begin_charge count in the audit trail, so every refusal figure
--      quoted from these runs is inflated ~2x.
--
-- WHICH EMIT SURVIVES, AND WHY THAT DIRECTION: the first one. twin.ottoq_sim_confirm_commands
-- reads `payload->>'new_state'` to transition the vehicle (falling back to a CASE when an
-- older emitter omits it), so the new_state payload is load-bearing. `requested_kw` is
-- NOT read off a command by anything -- a catalog sweep for functions referencing both
-- requested_kw and ottoq_vehicle_commands returns zero rows; the kW figure that actually
-- matters is claimed separately via ottoq_claim_tick_kw(...) from v_action on the line
-- after the surviving emit. It is nonetheless folded into the surviving payload so the
-- command record keeps the same information it carried before.
--
-- Nothing about stall choice, eligibility, ordering or priority changes. This removes a
-- redundant message; it does not change which stall any vehicle is sent to.
--
-- Same self-verifying in-place mechanism as 0054-0065. Pre-image pin:
--   public.ottoq_decide_tick 94d435ce3391e473e5cd453f7b77a831
-- Both anchors pre-verified read-only: exactly one occurrence each.

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int; v_before int; v_after int;
  v_keep_old text := E'                  \'new_state\', CASE WHEN v_action->>\'stall_type\'=\'dcfc\' THEN \'charging_dcfc\' ELSE \'charging_l2\' END\n                ), v_clock);';
  v_keep_new text := E'                  \'new_state\', CASE WHEN v_action->>\'stall_type\'=\'dcfc\' THEN \'charging_dcfc\' ELSE \'charging_l2\' END,\n                  /* 0066: folded in from the duplicate emit removed below, so this one\n                     command carries everything both used to. Nothing reads requested_kw\n                     off a command -- ottoq_claim_tick_kw takes the real figure from\n                     v_action on the next line -- but the record keeps it. */\n                  \'requested_kw\', v_action->>\'requested_kw\'\n                ), v_clock);';
  v_dup_old text := E'        v_ev_committed_kw := v_ev_committed_kw + COALESCE((v_action->>\'requested_kw\')::numeric,0);\n        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, \'begin_charge\', jsonb_build_object(\'stall_id\', v_action->>\'stall_id\', \'stall_type\', v_action->>\'stall_type\', \'requested_kw\', v_action->>\'requested_kw\'), v_clock);';
  v_dup_new text := E'        v_ev_committed_kw := v_ev_committed_kw + COALESCE((v_action->>\'requested_kw\')::numeric,0);\n        /* ══════════ 0066: THE DUPLICATE begin_charge EMIT IS REMOVED HERE ══════════\n           This line used to emit a SECOND begin_charge for the same vehicle, stall and\n           tick as the one already emitted at the top of this branch -- same branch, no\n           conditional between them, so both always fired. Measured in re-cert #18 arm A:\n           589 refusals on the surviving variant, 584 on this one. It halved the refusal\n           reactor (LIMIT 20 per tick against an unbounded backlog) by making it re-read\n           decisions it had already handled, and it manufactured the byte-tied duplicate\n           command rows that broke the supersede ordering in #16 and forced 0062.\n           The surviving emit above now carries requested_kw as well. */';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'ottoq_decide_tick';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '94d435ce3391e473e5cd453f7b77a831' THEN
    RAISE EXCEPTION '0066: pre-image md5 % != pinned 94d435ce3391e473e5cd453f7b77a831', md5(v_src);
  END IF;

  v_before := (length(v_src) - length(replace(v_src, 'begin_charge', ''))) / length('begin_charge');

  v_cnt := (length(v_src) - length(replace(v_src, v_keep_old, ''))) / length(v_keep_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0066: surviving-emit anchor occurs % times (need 1)', v_cnt; END IF;
  v_src := replace(v_src, v_keep_old, v_keep_new);

  v_cnt := (length(v_src) - length(replace(v_src, v_dup_old, ''))) / length(v_dup_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0066: duplicate-emit anchor occurs % times (need 1)', v_cnt; END IF;
  v_src := replace(v_src, v_dup_old, v_dup_new);

  /* Post-conditions. The removed emit is the ONLY begin_charge occurrence that may
     disappear, and exactly one PERFORM of it may remain in the branch. */
  v_after := (length(v_src) - length(replace(v_src, 'PERFORM ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, ''begin_charge''', ''))) 
              / length('PERFORM ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, ''begin_charge''');
  IF v_after <> 1 THEN
    RAISE EXCEPTION '0066: expected exactly 1 surviving begin_charge emit, found %', v_after;
  END IF;
  IF position('PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, ''begin_charge''' in v_src) <> 0 THEN
    RAISE EXCEPTION '0066: the duplicate begin_charge emit is still present';
  END IF;

  EXECUTE v_src;
  RAISE NOTICE '0066 patched public.ottoq_decide_tick -> md5 % (begin_charge mentions % -> %)',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'ottoq_decide_tick'),
    v_before,
    (SELECT (length(pg_get_functiondef(pr.oid)) - length(replace(pg_get_functiondef(pr.oid), 'begin_charge', ''))) / length('begin_charge')
       FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
      WHERE n.nspname = 'public' AND pr.proname = 'ottoq_decide_tick');
END
$do$;
