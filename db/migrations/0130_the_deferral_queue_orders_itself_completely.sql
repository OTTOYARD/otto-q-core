-- migration-version: 20260831013000
-- migration-name:    the_deferral_queue_orders_itself_completely
-- 0130 -- the 424242/24t carrier, CONVICTED FROM ITS OWN LEDGER (db/checks/0046 pairs 71-74).
--
-- THE EVIDENCE. Post-0129 the 424242/24t column forked in the mildest possible way: fps
-- equal, boot images equal, commands/decisions/events byte-equal -- h_bkg alone unequal, and
-- pair 73 reproduced pair 72's fork HASH-FOR-HASH (bkg_a 338994b0 / bkg_b 11c0c14f in both).
-- A reproducible fork is a dissectable one. The multiset difference is exactly 8 booking rows:
-- two vehicle PAIRS trading slots, one detail pair and one wash pair --
--     arm A: 9e05d00e -> WSH c9466ca6 @15:55 | 9f5d69bb -> ec443362 @16:05
--     arm B: 9f5d69bb -> WSH c9466ca6 @15:55 | 9e05d00e -> ec443362 @16:05
-- Their `why` strings name a window ten hours earlier than their own `during`, which dates the
-- rows: ottoq_booking_why prints p_from/p_to and the stall's own code, so a row whose why
-- disagrees with its window was WRITTEN at the earlier time and MOVED later. The mover keeps
-- its own audit trail, and that trail closes the case -- public.bay_reservation_reconcile_2026_08_02,
-- both arms, sim 13:00, defer_seq 3:
--     arm A  9e05d00e detail  old_from 12:45 -> new_from 15:55  (keeps c9466ca6)
--     arm A  9f5d69bb detail  old_from 12:45 -> new_from 16:05
--     arm B  9f5d69bb detail  old_from 12:45 -> new_from 15:55  (relocated to c9466ca6)
--     arm B  9e05d00e detail  old_from 12:45 -> new_from 16:05  (relocated)
-- Both bookings entered that tick with the IDENTICAL lower(during) = 12:45 -- and
-- ottoq_reconcile_bay_reservations drives its deferral loop on
--     ORDER BY lower(b.during)
-- and nothing else. The loop body walks each booking forward from its ETA and takes the first
-- window that does not collide, so THE ROW THE HEAP HANDS OVER FIRST WINS THE EARLIER BAY and
-- the loser is walked to the next 10-minute slot (or relocated to another bay). Two rows tied
-- on the sort key; the physical order broke the tie; the tie-break was the coin. The earlier
-- defers in the same lineage (06:00, 10:00) landed identically in both arms -- ties there
-- involved one vehicle's own two bookings, whose outcomes coincide. 13:00 was the first
-- CROSS-VEHICLE tie, and it is the whole fork.
--
-- WHY 0129 COULD NOT SEE IT. The ordering census behind 0129 extracted `ORDER BY ... LIMIT n`
-- picks, DISTINCT ON heads and window frames -- the shapes that choose ONE row. This site
-- chooses no row: it is a FOR ... IN SELECT ... ORDER BY ... LOOP with no LIMIT at all. A
-- cursor loop looks total because it visits every row, and it is total in its SET; but when the
-- body mutates a resource the rows compete for, the VISIT ORDER is as decisive as any LIMIT 1,
-- and a tie in it is the same coin. That is the class this migration closes. Re-run of the
-- census over the cursor-loop shape (49 clauses across public/ottoq/twin, backups excluded)
-- found the overwhelming majority already carrying their 0050/0054/0059-era run-stable tails
-- -- including this site's own sibling one function away, ottoq_activate_due_bay_reservations,
-- which orders `(lower(during) <= p_clock) DESC, lower(during), b.booking_id`. Four sites did
-- not, and are patched here:
--
--   * ottoq_reconcile_bay_reservations -- THE CARRIER. `ORDER BY lower(b.during)` gains the
--     content keys upper(during), vehicle_id, stall_id, purpose, then booking_id as the
--     0062/0063 last resort. Deliberately NOT re-keyed: the primary sort stays lower(during),
--     so the sweep's policy (earliest window reconciles first) is untouched. This is a
--     totality fix, not a scheduling change.
--   * ottoq_book_workflow_legs -- `ORDER BY l.seq` over ALL of one vehicle's planned unbooked
--     legs. seq is unique per itinerary and TIES across two itineraries of the same vehicle
--     (the second visit) -- verbatim the leg-seq family 0129 totalized in seven decide_tick
--     sites plus four others. This site was invisible to that census for the reason above,
--     and it is the depot's principal forward booker. Same tail as 0129 used:
--     planned_start_sim, planned_end_sim, leg_id.
--   * ottoq_plan_overnight_wave -- `ORDER BY due_at ASC, v.current_soc ASC` decides wave order
--     among vehicles; two vehicles sharing a due time and a SoC tie. Gains v.id.
--   * ottoq_sim_energy_controller -- `ORDER BY issued_at, created_at` over pending energy
--     commands. created_at defaults to now(), which is FROZEN inside a pair transaction, so
--     every same-tick command ties on it and the residual order is issued_at then heap.
--     Gains command_id.
--
-- Censused and deliberately NOT touched (their orders are already content-keyed by design,
-- each with the comment from the campaign that installed it): twin.ottoq_opportunistic_scan
-- (requested_at, vehicle_id, approval_type) and twin.ottoq_sim_confirm_commands (issued_at,
-- vehicle_id, command_type, payload stall_id) -- both 0059-era fixes whose remaining tie needs
-- two byte-identical rows; adding their uuid last resort is tier C, pending PK confirmation.
-- twin.ottoq_sim_prime_deployment's `ORDER BY q.rn` was chased to its generator and is clean:
-- row_number() OVER (ORDER BY ottoq_sim_seeded_random(v_seed, 'prime:' || v.id)) -- hash-pure
-- over vehicle identity. ottoq_purge_prior_runs / ottoq_run_blackbox order by table_name
-- (unique, and maintenance-only).
--
-- Pre-image pins, read live 2026-08-31 (each anchor asserted at exactly 1 occurrence):
--   ottoq.ottoq_reconcile_bay_reservations   21577320f4281b1d91027d7bcf712866
--   ottoq.ottoq_book_workflow_legs           f3188c7b844542d7fa6fe5223c7a36a7
--   public.ottoq_plan_overnight_wave         40a7388e8c2311434098b5a406844bed
--   twin.ottoq_sim_energy_controller         e63f1336e72061182b6795e2d22b952e

CREATE FUNCTION pg_temp.ottoq_0130_total(p_ns text, p_fn text, p_md5 text,
                                         p_old text, p_new text, p_expect int,
                                         p_prior int DEFAULT 0)
RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_oid oid; v_src text; v_cnt int;
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = p_ns AND p.proname = p_fn AND p.prokind = 'f';
  v_src := pg_get_functiondef(v_oid);
  IF p_md5 IS NOT NULL AND md5(v_src) <> p_md5 THEN
    RAISE EXCEPTION '0130 abort: %.% drifted (md5 %)', p_ns, p_fn, md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, p_old, ''))) / length(p_old);
  IF v_cnt <> p_expect THEN
    RAISE EXCEPTION '0130 abort: %.% anchor found % times, expected %', p_ns, p_fn, v_cnt, p_expect;
  END IF;
  EXECUTE replace(v_src, p_old, p_new);
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, '/* 0130 */', ''))) / length('/* 0130 */');
  IF v_cnt <> p_prior + p_expect THEN
    RAISE EXCEPTION '0130 abort: %.% patch survived % of % sites', p_ns, p_fn, v_cnt - p_prior, p_expect;
  END IF;
  RAISE NOTICE '0130: %.% -- % site(s) totalized.', p_ns, p_fn, p_expect;
END
$helper$;

DO $apply$
BEGIN
  -- 1. THE CARRIER. The deferral queue picks its order completely.
  PERFORM pg_temp.ottoq_0130_total(
    'ottoq', 'ottoq_reconcile_bay_reservations', '21577320f4281b1d91027d7bcf712866',
    'ORDER BY lower(b.during)',
    'ORDER BY lower(b.during), upper(b.during), b.vehicle_id, b.stall_id, b.purpose, b.booking_id  /* 0130 */',
    1);

  -- 2. The forward booker's leg cursor -- the 0129 leg-seq family, missed site.
  PERFORM pg_temp.ottoq_0130_total(
    'ottoq', 'ottoq_book_workflow_legs', 'f3188c7b844542d7fa6fe5223c7a36a7',
    'ORDER BY l.seq',
    'ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id  /* 0130 */',
    1);

  -- 3. The overnight wave's vehicle order.
  PERFORM pg_temp.ottoq_0130_total(
    'public', 'ottoq_plan_overnight_wave', '40a7388e8c2311434098b5a406844bed',
    'ORDER BY due_at ASC, v.current_soc ASC',
    'ORDER BY due_at ASC, v.current_soc ASC, v.id  /* 0130 */',
    1);

  -- 4. Pending energy commands (created_at is frozen inside a pair; it cannot break a tie).
  PERFORM pg_temp.ottoq_0130_total(
    'twin', 'ottoq_sim_energy_controller', 'e63f1336e72061182b6795e2d22b952e',
    'ORDER BY issued_at, created_at',
    'ORDER BY issued_at, created_at, command_id  /* 0130 */',
    1);

  RAISE NOTICE '0130 applied: the deferral queue orders itself completely (4 cursor loops).';
END
$apply$;

-- Post-condition: all four markers live in the catalog, and the carrier's sibling still
-- carries the tail it has had since its own fix (proving we did not regress the pair).
DO $verify$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind = 'f'
     AND pg_get_functiondef(p.oid) LIKE '%/* 0130 */%';
  IF v_n <> 4 THEN RAISE EXCEPTION '0130 abort: % functions carry the marker, expected 4', v_n; END IF;

  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_activate_due_bay_reservations'
      AND pg_get_functiondef(p.oid) LIKE '%lower(b.during), b.booking_id%';
  IF NOT FOUND THEN
    RAISE EXCEPTION '0130 abort: activate_due_bay_reservations lost its own run-stable tail';
  END IF;

  RAISE NOTICE '0130 verified: 4 markers in place; the sibling sweep is intact.';
END
$verify$;
