-- migration-version: 20260822013000
-- migration-name:    greedy_stall_pick_total_order_and_sim_domain
-- 0067 -- THE REMAINING DETERMINISM RESIDUE, ROOT-CAUSED FROM THE FIRST PINNED BASELINE
-- (re-cert #19, arms 88ed727f / 81ee350d, verdict 10/20, first divergence sim-min 330).
-- Two defects in public.ottoq_l2_optimize_assignments, the 'greedy_constrained' proposer.
--
-- ═══ DEFECT 1: THE STALL PICK IS NOT TOTALLY ORDERED ═══
-- The pick is `ORDER BY (dcfc ? 0 : l2_overflow_penalty) + COALESCE(distance_from_entrance,50)*0.1
-- ASC LIMIT 1` with NO tiebreak. Two stalls of the same type at the same distance produce a
-- byte-identical score, so `LIMIT 1` returns whichever row the heap hands over first.
--
-- Measured, and the signature is exact. At tick 10 the proposer assigned the SAME two stalls
-- to the SAME two vehicles, SWAPPED between arms:
--     arm A: b6e8b116 -> d55efb15 (NASH-L2-STALL-29),  f1776816 -> a1c28ab4 (NASH-L2-STALL-03)
--     arm B: b6e8b116 -> a1c28ab4,                     f1776816 -> d55efb15
-- Both stalls are l2, connector Multi, distance_from_entrance = 176 -- an exact tie. Tick 9
-- agreed byte-for-byte in both arms ('reservation_honoured'); the divergence is introduced
-- precisely here. The outer vehicle cursor is already total (ORDER BY current_soc ASC, v.id),
-- so vehicle order is NOT the problem: a single tie in the stall pick is sufficient, because
-- the first vehicle consumes one stall via v_used and the second is handed the other.
-- By tick 11 arm B's b6e8b116 had no compatible stall left ('no_compatible_available_stall')
-- and sat at the gate while arm A had it charging; 2 divergent vehicles at tick 11 become 11
-- at tick 12, 18 at 13, and 50 by tick 18.
--
-- The tie class is small, entirely L2, and exactly explains the observed split: this depot has
-- FOUR (stall_type, distance) groups holding more than one chargeable stall -- l2@72, l2@136,
-- l2@141, l2@176, two stalls each -- and ZERO on dcfc. That is why re-cert #19's DCFC session
-- count was identical across arms (18 / 18) while the whole residue lived in the L2 path.
--
-- THE FIX: append (s.distance_from_entrance, s.stall_code, s.id) after the score. stall_code
-- is the same idiom ottoq.ottoq_stall_free_between already uses (distance_from_entrance,
-- stall_code); s.id closes it absolutely. The SCORE still dominates -- DCFC-first and the L2
-- overflow penalty are untouched -- so this only decides among stalls that were already
-- indistinguishable. No eligibility, priority or preference changes.
--
-- ═══ DEFECT 2: A REAL-CLOCK READ INSIDE A SIM-CLOCK FUNCTION ═══
-- The same query filters `AND (s.reserved_by IS NULL OR s.reservation_expires_at <= now())`.
-- reservation_expires_at is written in the SIM domain (ottoq_reserve_stall stamps p_now, and
-- every call site passes the sim clock), but this compares it to the REAL clock. The function
-- already takes p_sim_clock and uses it correctly one line below for the charger heartbeat.
--
-- This was masked for as long as the cert's sim clock happened to equal the arming minute.
-- 0065 pinned the sim clock to 22:00 UTC, so the two domains can now sit up to ~22 hours
-- apart, and a genuinely-expired sim reservation reads as still-live against now() -- forever.
-- The error direction is conservative (the proposer declines to offer a stall it should have
-- offered; it never steals one), so this suppresses capacity rather than double-booking, which
-- is why re-cert #19 still ran healthy. It is nonetheless wrong, and it is wrong in exactly
-- the way 0065's charger-heartbeat trap was wrong.
--
-- NOT CHANGED, deliberately: the other three now() calls in this function are the cuOpt yield
-- check (`COALESCE(p.expires_at, p.created_at + '35 minutes') >= now()`) and the two proposal
-- bookkeeping stamps (created_at / expires_at on the INSERT). Those form a closed real-domain
-- pair -- proposals are written with now() and read back against now() -- so they are
-- internally consistent, and cuOpt is quiesced in cert arms regardless. Migrating proposal
-- bookkeeping to the sim domain is a larger, separate change and is not smuggled in here.
--
-- Same self-verifying in-place mechanism as 0054-0066. Pre-image pin:
--   public.ottoq_l2_optimize_assignments c99394c4cbd7436574e7a17b02dbc348
-- Both anchors pre-verified read-only: exactly one occurrence each.

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_now_old text := E'       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= now())\n       AND c.station_state = ''Available''';
  v_now_new text := E'       /* 0067: SIM domain. reservation_expires_at is stamped by ottoq_reserve_stall\n          from the sim clock at every call site; comparing it to the REAL clock only worked while\n          the cert''s sim clock equalled the arming minute. Since 0065 pinned that clock the\n          two domains sit up to ~22h apart and an expired sim reservation read as live\n          forever, suppressing capacity (conservative direction -- it never stole a stall). */\n       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_sim_clock)\n       AND c.station_state = ''Available''';
  v_ord_old text := E'       + COALESCE(s.distance_from_entrance, 50) * 0.1\n     ASC\n     LIMIT 1;';
  v_ord_new text := E'       + COALESCE(s.distance_from_entrance, 50) * 0.1\n     ASC,\n       /* 0067: RUN-STABLE TIEBREAK. The score above is byte-identical for two stalls of the\n          same type at the same distance, so LIMIT 1 returned heap order. Measured in re-cert\n          #19 at tick 10: stalls NASH-L2-STALL-03 and NASH-L2-STALL-29 (both l2, Multi,\n          distance 176) were handed to the same two vehicles in OPPOSITE order across two\n          same-seed arms, and by tick 18 fifty vehicles had diverged. This depot has four such\n          (type, distance) pairs, all l2 and none dcfc -- which is why #19''s DCFC session count\n          matched exactly (18/18) while the residue lived entirely in the L2 path. The score\n          still dominates, so DCFC-first and the L2 overflow penalty are unaffected: this only\n          decides among stalls that were already indistinguishable. stall_code is the idiom\n          ottoq.ottoq_stall_free_between already uses; s.id closes the order absolutely. */\n       s.distance_from_entrance ASC, s.stall_code ASC, s.id ASC\n     LIMIT 1;';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'ottoq_l2_optimize_assignments';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'c99394c4cbd7436574e7a17b02dbc348' THEN
    RAISE EXCEPTION '0067: pre-image md5 % != pinned c99394c4cbd7436574e7a17b02dbc348', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_now_old, ''))) / length(v_now_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0067: reservation-expiry anchor occurs % times (need 1)', v_cnt; END IF;
  v_src := replace(v_src, v_now_old, v_now_new);

  v_cnt := (length(v_src) - length(replace(v_src, v_ord_old, ''))) / length(v_ord_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0067: stall-pick ORDER BY anchor occurs % times (need 1)', v_cnt; END IF;
  v_src := replace(v_src, v_ord_old, v_ord_new);

  /* Post-conditions. The three deliberately-untouched real-clock reads must survive: the
     cuOpt yield check and the two proposal bookkeeping stamps. Before: 4 now() calls;
     after: exactly 3. If this trips, the patch reached further than intended. */
  v_cnt := (length(v_src) - length(replace(v_src, 'now()', ''))) / length('now()');
  IF v_cnt <> 3 THEN
    RAISE EXCEPTION '0067: expected exactly 3 surviving now() calls (cuOpt yield + 2 proposal stamps), found %', v_cnt;
  END IF;
  IF position('reservation_expires_at <= p_sim_clock' in v_src) = 0 THEN
    RAISE EXCEPTION '0067: the reservation-expiry test was not moved to the sim domain';
  END IF;
  IF position('s.distance_from_entrance ASC, s.stall_code ASC, s.id ASC' in v_src) = 0 THEN
    RAISE EXCEPTION '0067: the stall-pick tiebreak is not present';
  END IF;

  EXECUTE v_src;
  RAISE NOTICE '0067 patched public.ottoq_l2_optimize_assignments -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'ottoq_l2_optimize_assignments');
END
$do$;
