-- migration-version: 20260820210000
-- migration-name:    booking_pick_total_order
-- 0063 — THE RESERVATION-CHURN SEAM, found by the re-certification #16 follow-up.
--
-- WHAT #16 SHOWED. At the first divergent tick exactly one vehicle differed:
-- 1520dd3c was seated on DCFC stall fc5d1dab in arm B and held at the gate in
-- arm A. The stall.state_changed ledger shows the stall was first reserved for
-- 1520dd3c in BOTH arms; in B the vehicle was seated, charged 32->90 and
-- released, while in A the reservation churned onward to five other vehicles
-- (14b02ad9, 03812c6f, ad5abf3e, 55a6bddc, 983002e6) before it could be seated.
-- So the question was never "who seats" but "who overwrites a live reservation,
-- and in what order".
--
-- WHAT WAS RULED OUT FIRST (all measured, none of it the cause):
--   * public.ottoq_reserve_stall is correctly guarded — it overwrites only when
--     the stall is physically free AND (unreserved | same vehicle | expired) —
--     and EVERY one of its ~20 call sites passes the SIM clock (p_clock/v_clock),
--     never now(), so its `reservation_expires_at <= p_now` test never crosses
--     clock domains.
--   * The ~20 `ORDER BY vn.created_at DESC LIMIT 1` picks over ottoq_visit_needs
--     look like the same tie-prone class, but the data says otherwise: across
--     both #16 arms there are **ZERO** (vehicle_id, created_at) tie groups in
--     ottoq_visit_needs. Those sites are effectively total and are deliberately
--     NOT touched here — changing 20 call sites on a hypothesis the data refutes
--     would be churn, not a fix.
--
-- THE ACTUAL DEFECT. `ottoq_stall_bookings.booked_at` defaults to `now()` — one
-- REAL-clock value per statement — and the same two arms contain **261 tie
-- groups of (vehicle_id, booked_at), the largest holding 15 bookings**. Two
-- functions pick a single row out of exactly that tie with
-- `ORDER BY b.booked_at DESC LIMIT 1`, and `booking_id` is gen_random_uuid() so
-- there is no run-stable discriminator left:
--   1. ottoq.ottoq_enact_space_assignment — picks the PREFERRED STALL and then
--      immediately calls ottoq_reserve_stall(v_pref, …). This is the churn seam
--      itself: among up to 15 tied bookings, WHICH stall gets reserved was
--      decided by physical row order.
--   2. ottoq.ottoq_record_enacted_booking — picks which existing forward
--      reservation to ADOPT rather than duplicate. Narrower (it also filters on
--      stall_id and purpose) but the same non-total pick.
--
-- THE FIX is the 0062 principle applied here: keep `booked_at DESC` as the
-- dominant key (it is meaningful ACROSS statements — later statements really do
-- book later), then break ties on run-stable content — the booking window, the
-- stall, the purpose — and finally on booking_id so the order is TOTAL. Nothing
-- about which bookings are eligible changes; only the choice among rows that
-- were previously indistinguishable.
--
-- Same self-verifying in-place mechanism as 0054-0062. Pre-image pins:
--   ottoq.ottoq_enact_space_assignment  2cc4a76b31ab0948b30306f19dea2d75
--   ottoq.ottoq_record_enacted_booking  2787a382ce8d2ac15fd9d5c6835aae21

DO $do$
DECLARE
  p RECORD; v_oid oid; v_src text; v_cnt int;
BEGIN
  FOR p IN
    SELECT * FROM (VALUES
    ('ottoq','ottoq_enact_space_assignment','2cc4a76b31ab0948b30306f19dea2d75',1,
     $anchor$ORDER BY b.booked_at DESC$anchor$,
     $anchor$ORDER BY b.booked_at DESC,
              /* 0063: booked_at defaults to now() — ONE real-clock value per statement —
                 and up to 15 bookings for a single vehicle share it (measured across the
                 re-cert #16 arms: 261 tie groups). Alone it is heap order, and this pick
                 chooses WHICH stall is reserved on the very next line, so it is the
                 reservation-churn seam. Content keys first, booking_id last so the order
                 is TOTAL (the 0062 principle: never trade a random-but-total order for a
                 content order that ties). */
              lower(b.during) DESC, upper(b.during) DESC, s.id, b.purpose, b.booking_id DESC$anchor$),
    ('ottoq','ottoq_record_enacted_booking','2787a382ce8d2ac15fd9d5c6835aae21',1,
     $anchor$ORDER BY b.booked_at DESC$anchor$,
     $anchor$ORDER BY b.booked_at DESC,
            /* 0063: same non-total pick as ottoq_enact_space_assignment — this one decides
               which existing forward reservation is ADOPTED instead of duplicated. */
            lower(b.during) DESC, upper(b.during) DESC, b.booking_id DESC$anchor$)
    ) AS t(sch, fn, pre_md5, n_expected, old, new)
  LOOP
    SELECT pr.oid INTO STRICT v_oid
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = p.sch AND pr.proname = p.fn AND pr.prokind = 'f';
    v_src := pg_get_functiondef(v_oid);
    IF md5(v_src) <> p.pre_md5 THEN
      RAISE EXCEPTION '0063: %.% pre-image md5 % != pinned %', p.sch, p.fn, md5(v_src), p.pre_md5;
    END IF;
    v_cnt := (length(v_src) - length(replace(v_src, p.old, ''))) / length(p.old);
    IF v_cnt <> p.n_expected THEN
      RAISE EXCEPTION '0063: %.% anchor occurs % times (need %)', p.sch, p.fn, v_cnt, p.n_expected;
    END IF;
    EXECUTE replace(v_src, p.old, p.new);
    RAISE NOTICE '0063 patched %.% -> md5 %', p.sch, p.fn,
      (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
        JOIN pg_namespace n ON n.oid = pr.pronamespace
       WHERE n.nspname = p.sch AND pr.proname = p.fn AND pr.prokind = 'f');
  END LOOP;
END
$do$;
