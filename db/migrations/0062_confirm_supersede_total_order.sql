-- migration-version: 20260820190000
-- migration-name:    confirm_supersede_total_order
-- 0062 — SELF-INFLICTED REGRESSION REPAIR, found by re-certification #16
-- (post-0061 arms 2010f408 / c507bce2: 11/20, first divergence sim-min 360).
--
-- WHAT 0060 GOT WRONG. 0060 replaced the supersede window's tiebreak
--   ORDER BY c.issued_at DESC, c.command_id DESC
-- with
--   ORDER BY c.issued_at DESC, c.command_type DESC, (c.payload->>'stall_id') DESC
-- on the reasoning that command_id is gen_random_uuid() and therefore a
-- per-run-random discriminator. That reasoning was right; the replacement was
-- not. Content keys alone do NOT uniquely identify a row, and the live data
-- contains genuinely duplicated commands: re-cert #16 shows vehicle 1520dd3c
-- with TWO begin_charge rows sharing one vehicle, one issued_at, one
-- command_type and one stall_id (arm A refused both 'target_occupied'; arm B
-- retired one 'superseded' and executed the other). For such a pair the 0060
-- ordering is FULLY TIED, so dup_rn — which decides which command counts as
-- current intent and which is retired — falls back to physical row order.
-- 0060 therefore converted "random but TOTAL" into "no total order at all",
-- which is strictly worse: an unordered window is nondeterministic even in
-- principle, whereas the old form at least always produced one definite
-- answer per row set.
--
-- THE FIX restores totality without giving the random UUID any authority it
-- does not need: the content keys 0060 introduced still dominate (so identical
-- content still orders by content), payload::text is added so commands that
-- differ anywhere in their payload separate on content, and command_id
-- survives only as the last-resort tiebreak between rows that are byte-
-- identical in every content field — rows for which the choice is, by
-- construction, behaviourally interchangeable.
--
-- HONEST SCOPE. This repairs a defect 0060 introduced; it is NOT yet shown to
-- be the cause of re-cert #16's divergence. The measured seating difference for
-- 1520dd3c is upstream of the confirm walk: in BOTH arms stall fc5d1dab was
-- first reserved for 1520dd3c, but in arm A that reservation churned away to
-- five other vehicles (14b02ad9, 03812c6f, ad5abf3e, 55a6bddc, 983002e6)
-- before the vehicle could be seated, while in arm B the vehicle was seated,
-- charged 32->90, and released. The reservation-churn path is the next
-- investigation and is NOT touched here.
--
-- Same self-verifying in-place mechanism as 0054-0061. Pre-image pin:
--   twin.ottoq_sim_confirm_commands d1297df4dfd78792c2f3d182e9ec6cb6

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := 'ORDER BY c.issued_at DESC, c.command_type DESC, (c.payload->>''stall_id'') DESC';
  v_new text := 'ORDER BY c.issued_at DESC, c.command_type DESC, (c.payload->>''stall_id'') DESC, c.payload::text DESC, c.command_id DESC';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'twin' AND pr.proname = 'ottoq_sim_confirm_commands' AND pr.prokind = 'f';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'd1297df4dfd78792c2f3d182e9ec6cb6' THEN
    RAISE EXCEPTION '0062: pre-image md5 % != pinned d1297df4dfd78792c2f3d182e9ec6cb6', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0062: anchor occurs % times (need 1)', v_cnt;
  END IF;
  EXECUTE replace(v_src, v_old, v_new);
  RAISE NOTICE '0062 patched twin.ottoq_sim_confirm_commands -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'twin' AND pr.proname = 'ottoq_sim_confirm_commands' AND pr.prokind = 'f');
END
$do$;
