-- =====================================================================
-- 0110  The bay queue was ordered by a number drawn fresh each run
-- =====================================================================
-- Round 14, pair 2: busy_day / 314159 / 12t / flagship, fired 19:26 UTC
-- (2:26 PM CT). Arms ae0d8488 (A, first) and 9b506190 (B, second).
-- equal = false. Fixed by db/migrations/0195; this file is the
-- conviction and the queries that reproduce it.
--
--   canon   arm A      arm B      equal
--   fp      803698f3   803698f3   YES  (boot world identical, chargers.world aside -- 0194)
--   h_cmd   cf74d080   f2bd5208   no
--   h_dec   1788ee1c   eece0688   no
--   h_evt   25cf62c5   19a32c41   no
--   h_bkg   eaff0912   71fc7eaf   no
--   h_nrg   4afd1004   001e0870   no
--   decisions 1,562 vs 1,535; per tick identical through tick 4
--   (73/111/141/175) and 178 vs 176 at tick 5.
--
-- 1. THE FORK, BY DECISION ORDER (Q1)
--    Aligned by decision_seq, the arms are identical for 504 decisions
--    and fork at 505 (tick 5, sim 04:30): arm A enacts
--    stall_assignment/assign_stall for vehicle a8cb8731-...-feb8 onto
--    NASH-L2-STALL-30; arm B's 505th decision is arm A's 506th. Every
--    later difference cascades from feb8 being a stall candidate in A
--    and not in B.
--
-- 2. WHY feb8 WAS A CANDIDATE IN ONE ARM (Q2)
--    Both arms hold the same reservation for it: detail bay NASH-WSH-01,
--    04:20-04:43, booked at sim 02:30. In B it was seated at 04:30
--    (source bay_reservation_activated, state done at 04:43, atoms
--    interior_deep_clean and exterior_wash done 04:43). In A it was never
--    seated (released, no_show_grace_elapsed at 05:00; both atoms still
--    pending) -- so A's decide path re-planned the car, and B's did not.
--    Arm B emitted the per-tick summary event
--    ottoq.bay_reservation_activated_early at 04:30 (seated_total 2,
--    seated_early 1, declined 4). Arm A emitted none for that tick.
--
-- 3. WHAT THE POSTGRES LOG SAYS (not in any table; recorded here)
--    ottoq_activate_due_bay_reservations: FAILED sqlstate=23505
--      msg=duplicate key value violates unique constraint
--      "idx_stalls_one_vehicle_per_stall"
--    run ae0d8488 at 19:27:34, 19:27:50, 19:28:09, 19:28:28 UTC
--    run 9b506190 at 19:32:47, 19:33:08, 19:33:55, 19:34:57, 19:35:16,
--      and one sqlstate=P0001 (arm interlock) at 19:35:49.
--    At ~27 s per tick from each arm's start those are ticks 3,4,5,6
--    in A and 3,4,6,8,9(+10) in B. The function wraps its whole loop in
--    EXCEPTION WHEN OTHERS -> RAISE WARNING, RETURN 0: one bad seat
--    rolls back every seat of the tick, silently. Tick 5 (04:30) failed
--    in A and not in B. That is the fork.
--
-- 4. WHY THE SAME TICK THROWS IN ONE ARM ONLY (Q3, Q4)
--    The loop's cursor order was
--      ORDER BY (lower(b.during) <= p_clock) DESC, lower(b.during), b.booking_id
--    booking_id is gen_random_uuid() per insert: the two arms carry two
--    unrelated draws for the same reservation. The 04:30 batch had ties
--    on lower(during) at 04:30 (3), 04:40 (2) and 04:50 (3). Sorted as
--    the cursor sorts, from the arms' own rows (Q3):
--      A: ... 0002@WSH-03 > 52a4@SVC-01 > 2178@SVC-02 > 0006@WSH-03 > 1906@WSH-02 > 1906@WSH-03 ...
--      B: ... 0002@WSH-03 > 52a4@SVC-01 > 1906@WSH-02 > 2178@SVC-02 > 0006@WSH-03 > 0002@WSH-01 ...
--    Sorted by (in_window, lower(during), vehicle_id, stall_id): identical.
--    The loop is not idempotent (each seat moves a car, occupies a stall,
--    rebases a window) and its cursor is a snapshot. Vehicle 1906 holds
--    two reservations in the batch (wash WSH-02 04:40, detail WSH-03
--    04:50): seat the first and it is in_wash_bay; the second seat moves
--    it again; trg_reassignment_guard refuses to vacate a mid-work bay
--    (Q4: the guard writes NEW.current_vehicle_id := OLD.current_vehicle_id
--    for in_wash_bay/in_detail_bay/in_service_bay/charging_*), the old
--    stall keeps the car, the new one takes it, and the partial unique
--    index on stalls(current_vehicle_id) throws. Whether that pair is
--    reached before a competing seat takes the bay -- a CAS miss that
--    skips cleanly -- is a function of the order. 0054 class.
--
-- 5. RECORDED, NOT FIXED IN 0195
--    a. ottoq_enact_space_assignment logs the same 23505 in BOTH arms at
--       the same relative times (vehicles ...9fc5, c333...0001, ca2624fc;
--       type service_bay, source bay_reconcile_twin_admit). Deterministic
--       today, wrong: a car in two stalls, seat thrown away, silently.
--    b. The all-or-nothing handler in ottoq_activate_due_bay_reservations:
--       the right shape is one subtransaction per seat, so a bad seat
--       costs one seat, not the tick. Larger behaviour change; after
--       round 15 establishes the 0195 canon.
--    c. Every round-14 arm logs this failure, and the COUNT tracks the
--       verdict (Q5, read 20:05 UTC):
--         c1 busy/171717/12t  9a82a2ff 7   bd9b611a 7   equal
--         c2 busy/314159/12t  ae0d8488 4   9b506190 6   RED
--         c3 normal/171717    df469ac7 9   4f3235cf 9   equal
--         c4 busy/424242/12t  ce6790bb 10  (second arm still running)
--       Same count in both arms of every green pair; different counts in
--       the red one. The failure is deterministic whenever the order
--       happens to coincide, and the order is a coin.
-- =====================================================================

-- Q1 -- the fork by decision order.
WITH da AS (
  SELECT row_number() OVER (ORDER BY decision_seq) AS rn, tick_seq, sim_clock, action_context, entity_id, outcome_status,
         COALESCE(enacted_action->>'verb', proposed_action->>'verb','-') AS verb, COALESCE(proposed_action->>'stall_id','-') AS stall
    FROM ottoq_decisions WHERE sim_run_id = 'ae0d8488-f245-4b6b-8f1a-de77a0362ba2'),
db AS (
  SELECT row_number() OVER (ORDER BY decision_seq) AS rn, tick_seq, sim_clock, action_context, entity_id, outcome_status,
         COALESCE(enacted_action->>'verb', proposed_action->>'verb','-') AS verb, COALESCE(proposed_action->>'stall_id','-') AS stall
    FROM ottoq_decisions WHERE sim_run_id = '9b506190-f61d-49f0-97ae-390d7d09bdb6'),
fork AS (
  SELECT min(da.rn) AS rn FROM da JOIN db ON db.rn = da.rn
   WHERE (da.sim_clock, da.action_context, da.entity_id, da.outcome_status, da.verb, da.stall)
      IS DISTINCT FROM (db.sim_clock, db.action_context, db.entity_id, db.outcome_status, db.verb, db.stall))
SELECT 'A' AS arm, rn, tick_seq, to_char(sim_clock,'HH24:MI') AS clk, action_context, right(entity_id::text,4) AS ent, verb, right(stall,4) AS stall
  FROM da WHERE rn BETWEEN (SELECT rn FROM fork)-2 AND (SELECT rn FROM fork)+2
UNION ALL
SELECT 'B', rn, tick_seq, to_char(sim_clock,'HH24:MI'), action_context, right(entity_id::text,4), verb, right(stall,4)
  FROM db WHERE rn BETWEEN (SELECT rn FROM fork)-2 AND (SELECT rn FROM fork)+2
ORDER BY arm, rn;

-- Q2 -- feb8's detail reservation and its atoms in each arm.
SELECT CASE WHEN b.sim_run_id='ae0d8488-f245-4b6b-8f1a-de77a0362ba2' THEN 'A' ELSE 'B' END AS arm,
       s.stall_code, to_char(lower(b.during),'HH24:MI') AS lo, to_char(upper(b.during),'HH24:MI') AS hi,
       b.purpose, b.state, b.release_reason, b.source, to_char(b.booked_at_sim,'HH24:MI') AS booked_sim
  FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
 WHERE b.sim_run_id IN ('ae0d8488-f245-4b6b-8f1a-de77a0362ba2','9b506190-f61d-49f0-97ae-390d7d09bdb6')
   AND b.vehicle_id = 'a8cb8731-fb8b-4b96-8f24-52064752feb8' AND s.stall_type::text IN ('wash_bay','detail_bay')
 ORDER BY 1, lower(b.during);

SELECT CASE WHEN e.sim_run_id='ae0d8488-f245-4b6b-8f1a-de77a0362ba2' THEN 'A' ELSE 'B' END AS arm,
       e.event_seq, e.payload - 'note' AS activation_summary
  FROM ottoq_events e
 WHERE e.sim_run_id IN ('ae0d8488-f245-4b6b-8f1a-de77a0362ba2','9b506190-f61d-49f0-97ae-390d7d09bdb6')
   AND e.event_type = 'ottoq.bay_reservation_activated_early'
 ORDER BY 1, e.event_seq;

-- Q3 -- the 04:30 batch in both arms under the old key and the new key.
WITH pool AS (
  SELECT b.sim_run_id, b.booking_id, b.vehicle_id, b.stall_id, s.stall_code,
         (lower(b.during) <= '2026-09-01 04:30+00'::timestamptz) AS in_window, lower(b.during) AS lo
    FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
   WHERE b.sim_run_id IN ('ae0d8488-f245-4b6b-8f1a-de77a0362ba2','9b506190-f61d-49f0-97ae-390d7d09bdb6')
     AND s.stall_type::text IN ('wash_bay','detail_bay','service_bay')
     AND b.booked_at_sim <= '2026-09-01 04:30+00' AND upper(b.during) > '2026-09-01 04:30+00'
     AND lower(b.during) <= '2026-09-01 05:00+00')
SELECT CASE WHEN sim_run_id='ae0d8488-f245-4b6b-8f1a-de77a0362ba2' THEN 'A' ELSE 'B' END AS arm,
       string_agg(right(vehicle_id::text,4)||'@'||stall_code, ' > ' ORDER BY in_window DESC, lo, booking_id)            AS order_old_key_booking_id,
       string_agg(right(vehicle_id::text,4)||'@'||stall_code, ' > ' ORDER BY in_window DESC, lo, vehicle_id, stall_id)  AS order_new_key_vehicle_stall
  FROM pool GROUP BY sim_run_id ORDER BY 1;

-- Q4 -- the guard that keeps a mid-work car's stall (why two stalls end
--       up claiming one car), and the index that refuses it.
SELECT pg_get_indexdef(i.indexrelid) FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid WHERE c.relname='idx_stalls_one_vehicle_per_stall';
SELECT regexp_replace(substr(pg_get_functiondef(p.oid), position('IF v_state IS NULL' in pg_get_functiondef(p.oid)), 260), '\s+', ' ', 'g') AS guard_protected_states
  FROM pg_proc p WHERE p.proname = 'ottoq_trg_reassignment_guard';

-- Q5 -- the log (Supabase unified logs, ClickHouse; not SQL against the
--       database). Kept verbatim so the count can be re-run:
--   select substring(event_message, 'run=([0-9a-f]{8})') as run8, count(*)
--     from logs where source = 'postgres_logs'
--      and event_message like 'ottoq_activate_due_bay_reservations: FAILED%'
--    group by run8
