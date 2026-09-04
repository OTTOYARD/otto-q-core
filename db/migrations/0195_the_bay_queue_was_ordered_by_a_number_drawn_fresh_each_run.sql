-- =====================================================================
-- 0195  The bay queue was ordered by a number drawn fresh each run
-- =====================================================================
-- forces_recert = TRUE. This changes the order in which held bay
-- reservations are seated within a tick, and stops a car that this
-- tick already seated from being seated a second time. Both change
-- what the engine does; the second only on ticks that today end in a
-- swallowed error and no seats at all.
--
-- THE FAILURE (round 14, pair 2, 19:26 UTC, busy_day/314159/12t)
-- ---------------------------------------------------------------------
-- equal = false. Identical boot fingerprint (fp 803698f3), identical
-- decisions for 504 rows -- ticks 1 through 4 and the first 4 decisions
-- of tick 5 -- then the arms fork at decision 505: the first arm
-- assigns L2 stall NASH-L2-STALL-30 to vehicle a8cb8731-...-feb8 at
-- 04:30; the second arm has no such decision, because in the second
-- arm that car is standing in detail bay NASH-WSH-01 and in the first
-- it is not.
--
-- Both arms held the same reservation for it: NASH-WSH-01, detail,
-- 04:20-04:43, booked at sim 02:30. At the 04:30 tick
-- ottoq.ottoq_activate_due_bay_reservations seats every due hold in one
-- loop. In the second arm it seated feb8 (booking source
-- 'bay_reservation_activated', bay 'done' at 04:43, atoms
-- interior_deep_clean and exterior_wash done). In the first arm the
-- loop THREW and the outer handler swallowed it -- the Postgres log at
-- 19:28:09 UTC, run ae0d8488:
--
--   ottoq_activate_due_bay_reservations: FAILED sqlstate=23505
--   msg=duplicate key value violates unique constraint
--   "idx_stalls_one_vehicle_per_stall"
--
-- The function's EXCEPTION WHEN OTHERS wraps the whole loop, so one bad
-- seat rolls back every seat of the tick and returns 0. feb8's hold
-- lapsed into 'no_show_grace_elapsed' at 05:00, the car stayed
-- arrived_at_gate at its staging stall, the decide path re-planned it,
-- and 1,562 versus 1,535 decisions later the arms had nothing in common.
-- The first arm logged that error at ticks 3, 4, 5 and 6; the second at
-- 3, 4, 6, 8 and 9 (plus one P0001 arm-interlock refusal at tick 10).
-- Same code, same world, different ticks.
--
-- WHY THE SAME BATCH THROWS IN ONE ARM AND NOT THE OTHER
-- ---------------------------------------------------------------------
-- The loop's cursor:
--
--   ORDER BY (lower(b.during) <= p_clock) DESC, lower(b.during), b.booking_id
--   -- "then the PK, so the order is total and stable across ticks"
--
-- Stable across ticks. Not across runs: booking_id is gen_random_uuid()
-- at insert, so two arms of one pair carry two unrelated draws for the
-- same reservation, and every tie on lower(during) is broken
-- differently. Ties are the normal case, not the edge: the 04:30 batch
-- had three holds due at 04:30, two at 04:40 and three at 04:50.
-- Sorted exactly as the cursor sorts, from the two arms' own rows:
--
--   first arm : ... 0002@WSH-03 > 52a4@SVC-01 > 2178@SVC-02 > 0006@WSH-03
--               > 1906@WSH-02 > 1906@WSH-03 > 0002@WSH-01 > 0001@WSH-02 ...
--   second arm: ... 0002@WSH-03 > 52a4@SVC-01 > 1906@WSH-02 > 2178@SVC-02
--               > 0006@WSH-03 > 0002@WSH-01 > 0001@WSH-02 > 1906@WSH-03 ...
--
-- Sorted by (in-window, lower(during), vehicle_id, stall_id) the two
-- arms produce the same sequence. This is the 0054 class -- an order
-- keyed on a per-run UUID -- in the one cursor 0054's sweep did not
-- reach, because its comment claimed totality.
--
-- Order matters here because the loop is not idempotent: each seat
-- changes stall occupancy, stall reservations, booking windows and the
-- car's state, and the cursor was a snapshot taken before any of it.
-- In particular vehicle 1906 holds TWO reservations in this batch
-- (wash NASH-WSH-02 04:40, detail NASH-WSH-03 04:50). Seat the first
-- and the car is in_wash_bay; the cursor still yields the second; the
-- second seat moves it to another bay; trg_reassignment_guard refuses
-- to vacate a bay whose car is mid-work (that is its job), so the old
-- stall keeps current_vehicle_id, the new stall takes it too, and
-- idx_stalls_one_vehicle_per_stall -- one stall per car -- throws.
-- Whether that pair of seats is reached before a competing seat takes
-- the bay (a CAS miss skips it cleanly) depends on the order. Hence
-- one arm throws at 04:30 and the other does not.
--
-- WHAT THIS MIGRATION DOES
-- ---------------------------------------------------------------------
-- 1. The contention order becomes (in-window DESC, lower(during),
--    vehicle_id, stall_id): identities the harness fixes across runs.
--    It is total: the EXCLUDE constraint forbids two live holds by one
--    car on one stall over one instant.
-- 2. Inside the loop, before touching the stall, the car's state is
--    re-read. A car this batch already seated (or anything else no
--    longer holding) is skipped, exactly as the cursor would have
--    skipped it had it been opened a moment later. Today that path is
--    the 23505 above and the loss of the whole tick's seating; after
--    this it is one CONTINUE.
-- Nothing else moves. The outer handler stays: an error that is not
-- this one still must not cost the release logic that follows.
--
-- WHAT IT DOES NOT DO
-- ---------------------------------------------------------------------
-- It does not touch ottoq_enact_space_assignment, which logs the same
-- 23505 at the same ticks in BOTH arms (vehicles ...9fc5, c333...0001,
-- ca2624fc, source bay_reconcile_twin_admit): deterministic today,
-- wrong, and the next instance of "a car in two stalls". Recorded.
-- It does not make a failed seat survive the other seats of its tick.
-- That is the right shape (one subtransaction per seat) and a larger
-- behaviour change; it is written up in db/checks/0110, not here.
-- =====================================================================

BEGIN;

DO $mig$
DECLARE
  v_src text; v_n int;
  v_o1 text := 'ORDER BY (lower(b.during) <= p_clock) DESC, lower(b.during), b.booking_id';
  v_c1 text := 'CONTINUE WHEN NOT public.ottoq_reserve_stall(v_res.stall_id, v_res.vehicle_id, p_clock, 900);';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_activate_due_bay_reservations';
  IF v_src IS NULL THEN RAISE EXCEPTION '0195: ottoq.ottoq_activate_due_bay_reservations not found'; END IF;
  IF position('/* 0195 */' in v_src) > 0 THEN RAISE EXCEPTION '0195: already applied - refusing to double-apply'; END IF;
  IF position('0015' in v_src) = 0 OR position('0016' in v_src) = 0 THEN
    RAISE EXCEPTION '0195: the function is missing its 0015/0016 blocks - refusing to edit a body that is not the one certified';
  END IF;
  v_n := (length(v_src) - length(replace(v_src, v_o1, ''))) / length(v_o1);
  IF v_n <> 1 THEN RAISE EXCEPTION '0195: ORDER BY anchor occurs % times, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_c1, ''))) / length(v_c1);
  IF v_n <> 1 THEN RAISE EXCEPTION '0195: reserve_stall CAS anchor occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_o1,
    'ORDER BY (lower(b.during) <= p_clock) DESC, lower(b.during), b.vehicle_id, b.stall_id /* 0195 */'
    || E'\n     -- 0195: never the row''s own uuid. It is drawn fresh every run, and two arms of'
    || E'\n     -- one pair broke every tie on lower(during) differently (db/checks/0110).');
  v_src := replace(v_src, v_c1,
       E'-- 0195: the cursor is a snapshot. A car this same batch already seated is no\n'
    || E'    -- longer holding; seating it again puts one car in two stalls, the unique index\n'
    || E'    -- refuses, and the handler below throws the WHOLE tick''s seats away.\n'
    || E'    CONTINUE WHEN NOT EXISTS (\n'
    || E'      SELECT 1 FROM public.vehicles vv\n'
    || E'       WHERE vv.id = v_res.vehicle_id AND vv.home_depot_id = p_depot_id\n'
    || E'         AND vv.current_state IN (''arrived_at_gate''::vehicle_state, ''staged_awaiting_service''::vehicle_state,\n'
    || E'                                  ''charge_complete_holding''::vehicle_state, ''service_complete_holding''::vehicle_state)); /* 0195 */\n'
    || E'    ' || v_c1);
  EXECUTE v_src;
END
$mig$;

-- ─────────────────────────────────────────────────────────────────────
-- ASSERTIONS -- A CHECK THAT CANNOT FAIL IS NOT A CHECK
-- ─────────────────────────────────────────────────────────────────────
DO $assert$
DECLARE
  v_src text; v_n int; v_bad text[];
  v_a text; v_b text;
BEGIN
  -- A1. Post-edit shape: two markers, no ORDER BY in this function names
  --     booking_id, the CAS still follows the state re-read.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_activate_due_bay_reservations';
  v_n := (length(v_src) - length(replace(v_src, '/* 0195 */', ''))) / length('/* 0195 */');
  IF v_n <> 2 THEN RAISE EXCEPTION '0195 A1 FAILED: markers = %, expected 2', v_n; END IF;
  -- comments stripped first: the first apply attempt (20:56 UTC) tripped this
  -- check on its own explanatory comment, which named the column.
  IF regexp_replace(v_src, '--[^\n]*', '', 'g') ~ 'ORDER BY[^;]*booking_id' THEN
    RAISE EXCEPTION '0195 A1 FAILED: an ORDER BY still names booking_id';
  END IF;
  IF v_src !~ 'service_complete_holding''::vehicle_state\)\); /\* 0195 \*/\s*CONTINUE WHEN NOT public\.ottoq_reserve_stall' THEN
    RAISE EXCEPTION '0195 A1 FAILED: the state re-read does not immediately precede the CAS';
  END IF;

  -- A2. THE ORDER IS NOW THE SAME IN BOTH ARMS OF THE PAIR THAT FAILED.
  --     Live data: the 04:30 batch of run ae0d8488 (first arm) and
  --     9b506190 (second arm), sorted by the new key, must yield the same
  --     vehicle/stall sequence; sorted by the old key they must NOT
  --     (that is the defect, and it must still be visible in the rows).
  WITH pool AS (
    SELECT b.sim_run_id, b.booking_id, b.vehicle_id, b.stall_id, s.stall_code,
           (lower(b.during) <= '2026-09-01 04:30+00'::timestamptz) AS in_window, lower(b.during) AS lo
      FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.sim_run_id IN ('ae0d8488-f245-4b6b-8f1a-de77a0362ba2','9b506190-f61d-49f0-97ae-390d7d09bdb6')
       AND s.stall_type::text IN ('wash_bay','detail_bay','service_bay')
       AND b.booked_at_sim <= '2026-09-01 04:30+00' AND upper(b.during) > '2026-09-01 04:30+00'
       AND lower(b.during) <= '2026-09-01 05:00+00'
       -- the one row the second arm rebased on an early seat is excluded: its
       -- lower(during) is a RESULT of the order, not an input to it
       AND NOT (b.vehicle_id::text LIKE '%1906' AND s.stall_code = 'NASH-WSH-02')
  ), o AS (
    SELECT sim_run_id,
           string_agg(right(vehicle_id::text,4)||'@'||stall_code, '>' ORDER BY in_window DESC, lo, booking_id) AS old_key,
           string_agg(right(vehicle_id::text,4)||'@'||stall_code, '>' ORDER BY in_window DESC, lo, vehicle_id, stall_id) AS new_key
      FROM pool GROUP BY sim_run_id
  )
  SELECT (SELECT new_key FROM o WHERE sim_run_id='ae0d8488-f245-4b6b-8f1a-de77a0362ba2'),
         (SELECT new_key FROM o WHERE sim_run_id='9b506190-f61d-49f0-97ae-390d7d09bdb6')
    INTO v_a, v_b;
  IF v_a IS NULL OR v_b IS NULL THEN RAISE EXCEPTION '0195 A2 FAILED: the round-14 pair-2 rows are not there to test against'; END IF;
  IF v_a <> v_b THEN RAISE EXCEPTION '0195 A2 FAILED: new key still orders the two arms differently: % vs %', v_a, v_b; END IF;
  WITH pool AS (
    SELECT b.sim_run_id, b.booking_id, b.vehicle_id, b.stall_id, s.stall_code,
           (lower(b.during) <= '2026-09-01 04:30+00'::timestamptz) AS in_window, lower(b.during) AS lo
      FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.sim_run_id IN ('ae0d8488-f245-4b6b-8f1a-de77a0362ba2','9b506190-f61d-49f0-97ae-390d7d09bdb6')
       AND s.stall_type::text IN ('wash_bay','detail_bay','service_bay')
       AND b.booked_at_sim <= '2026-09-01 04:30+00' AND upper(b.during) > '2026-09-01 04:30+00'
       AND lower(b.during) <= '2026-09-01 05:00+00'
       AND NOT (b.vehicle_id::text LIKE '%1906' AND s.stall_code = 'NASH-WSH-02')
  ), o AS (
    SELECT sim_run_id, string_agg(right(vehicle_id::text,4)||'@'||stall_code, '>' ORDER BY in_window DESC, lo, booking_id) AS old_key
      FROM pool GROUP BY sim_run_id
  )
  SELECT (SELECT old_key FROM o WHERE sim_run_id='ae0d8488-f245-4b6b-8f1a-de77a0362ba2'),
         (SELECT old_key FROM o WHERE sim_run_id='9b506190-f61d-49f0-97ae-390d7d09bdb6')
    INTO v_a, v_b;
  IF v_a = v_b THEN RAISE EXCEPTION '0195 A2 FAILED: the old key orders both arms the same -- the conviction above is not supported by the rows'; END IF;
  RAISE NOTICE '0195 A2: old key orders the two arms differently; the new key orders them identically';

  -- A3. THE CLASS. Every tick-path ORDER BY that names a per-run UUID
  --     must either put a run-stable identity (vehicle_id, stall_id,
  --     charger_id, stall_code) ahead of it, or be one of the SEVEN 0129
  --     per-car leg cursors in ottoq_decide_tick, where leg_id decides
  --     only between two legs of one car with identical seq and window.
  --     Those seven are recorded in db/checks/0110 as the next instance
  --     (the first apply attempt at 20:57 UTC surfaced them); they are
  --     not this migration's to change. Anything else -- a new site, or
  --     an eighth 0129 cursor -- refuses the migration.
  SELECT array_agg(fn || ' :: ' || clause ORDER BY fn, clause) INTO v_bad
    FROM (
      SELECT n.nspname||'.'||p.proname AS fn, regexp_replace(m[1], '\s+', ' ', 'g') AS clause
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        -- greedy on purpose: in Postgres ARE a non-greedy FIRST quantifier makes the
        -- whole match shortest, which cut every clause at the column name and hid
        -- the 0129 marker from the exemption below (second apply attempt, 21:00 UTC).
        CROSS JOIN LATERAL regexp_matches(pg_get_functiondef(p.oid), '(ORDER BY[^;]*)', 'g') m
       WHERE n.nspname IN ('public','twin','ottoq') AND p.prokind IN ('f','p')
         AND p.proname IN ('ottoq_activate_due_bay_reservations','ottoq_release_vacated_spaces','ottoq_sim_advance_service_flow',
                           'ottoq_sim_advance_tick_world','ottoq_sim_decide_and_dispatch','ottoq_sim_advance_visit_atoms',
                           'ottoq_sim_prearrival_contracts','ottoq_book_appointment','ottoq_plan_opportunistic_charges',
                           'ottoq_reconcile_bay_reservations','ottoq_sim_advance_flow_contract','ottoq_auto_dispatch_tick','ottoq_decide_tick')
    ) q
   WHERE clause ~ '\m(booking_id|decision_id|leg_id|visit_id|command_id|dispatch_id|itinerary_id|proposal_id|event_id)\M'
     AND clause !~ '(vehicle_id|stall_id|charger_id|stall_code)[^;]*(booking_id|decision_id|leg_id|visit_id|command_id|dispatch_id|itinerary_id|proposal_id|event_id)'
     AND NOT (fn = 'public.ottoq_decide_tick' AND clause ~ 'l\.seq, l\.planned_start_sim, l\.planned_end_sim, l\.leg_id /\* 0129 \*/');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0195 A3 FAILED: tick-path ORDER BY keyed on a per-run UUID before any stable identity: %', v_bad;
  END IF;
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL regexp_matches(pg_get_functiondef(p.oid), 'l\.seq, l\.planned_start_sim, l\.planned_end_sim, l\.leg_id /\* 0129 \*/', 'g') m
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  IF v_n <> 7 THEN
    RAISE EXCEPTION '0195 A3 FAILED: ottoq_decide_tick carries % 0129 leg cursors keyed on leg_id, the recorded set is 7', v_n;
  END IF;
  RAISE NOTICE '0195 A3: the 7 known 0129 leg cursors in ottoq_decide_tick are recorded (db/checks/0110), not changed';

  RAISE NOTICE '0195: all assertions passed.';
END
$assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0195_the_bay_queue_was_ordered_by_a_number_drawn_fresh_each_run', TRUE,
  'Round 14 pair 2 (19:26 UTC, busy_day/314159/12t) forked at decision 505 of tick 5: the first arm re-planned vehicle ...feb8 '
  'because its held detail-bay reservation was never seated, the second arm seated it. ottoq.ottoq_activate_due_bay_reservations '
  'seats every due hold in one loop ordered by (in_window, lower(during), booking_id); booking_id is a per-run UUID, the 04:30 '
  'batch had eight ties on lower(during), and the two arms walked it in different sequences (proved from their own rows, A2). '
  'The loop is not idempotent -- vehicle 1906 held two reservations in that batch; seating the first then the second put one car '
  'in two stalls, trg_reassignment_guard refused to vacate the mid-work bay, idx_stalls_one_vehicle_per_stall threw 23505, and the '
  'outer EXCEPTION handler rolled back every seat of the tick (Postgres log 19:28:09 UTC, run ae0d8488). Which order reaches that '
  'pair of seats before a CAS miss skips it is what differed. Fix: order by (in_window, lower(during), vehicle_id, stall_id), and '
  're-read the car''s state at seat time so a car already seated this batch is skipped instead of seated twice. 0054 class: the '
  'one cursor whose comment claimed totality. Not touched: ottoq_enact_space_assignment logs the same 23505 identically in both arms '
  '(deterministic, wrong, next); per-seat subtransactions are the right shape and a larger change; and the seven 0129 per-car leg '
  'cursors in ottoq_decide_tick that end in leg_id, surfaced by this migration''s own census and pinned at exactly seven. '
  'forces_recert=TRUE: busy_day/314159/12t must go green; any column whose batches had order-sensitive ties may move its canon.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-04 21:00:23 UTC (4:00 PM CT), third attempt, after
-- 0194 (20:55:20 UTC) and after round 14 closed. The first two attempts
-- were refused by this file's own assertions and rolled back cleanly
-- (markers 0, no lineage row, 0194 intact between attempts):
--   20:56  A1 matched the explanatory comment that named booking_id;
--          the comment now says "the row's own uuid" and A1 strips
--          comments before matching.
--   20:57  A3 surfaced seven ORDER BY ... l.leg_id /* 0129 */ per-car
--          leg cursors in ottoq_decide_tick; they are recorded
--          (db/checks/0110 section 5) and pinned at exactly seven.
--   21:00  A3's exemption still missed them: the capture regex mixed a
--          non-greedy and a greedy quantifier and Postgres ARE made the
--          whole match shortest, cutting each clause before the 0129
--          marker. Capture is now greedy on the whole clause.
-- Then: A1 shape (2 markers, no ORDER BY names booking_id, re-read
-- precedes the CAS); A2 the two round-14 arms order the 04:30 batch
-- identically under the new key and differently under the old; A3 no
-- other tick-path ORDER BY keyed on a per-run UUID; lineage
-- forces_recert = true. Round 15 scheduled 21:01 UTC, c2 first.
--
-- =====================================================================
-- THE PREDICTION (published before round 15)
-- =====================================================================
-- 1. busy_day/314159/12t passes in round 15, both arms complete, with a
--    canon that matches neither of round 14's arms (cf74d080 / f2bd5208)
--    -- because the order is now a third, stable one.
-- 2. Every other round-15 column passes. Whether its canon equals round
--    14's is NOT predicted: any batch with an order-sensitive tie moves
--    it, and there were ties in every batch inspected.
-- 3. The Postgres log for round 15 carries strictly fewer
--    'ottoq_activate_due_bay_reservations: FAILED sqlstate=23505' lines
--    per arm than round 14 pair 2 (4 and 5). Zero is not predicted: the
--    double-seat is one of the ways a car ends up claimed by two stalls,
--    not the only one.
-- =====================================================================
