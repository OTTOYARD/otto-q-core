-- ---------------------------------------------------------------------------
-- 0123 — the settlement record was outside the certification, and the scan
--        that wrote it grew with history.
--
-- Traced 2026-09-08 against gxdrcyphqjzjsuhxuqtg, starting from a performance
-- question that turned out to have a false premise (see the CORRECTION on
-- 0215) and ending somewhere more important.
--
-- Every reading below was taken live. Q1–Q5 record the BEFORE state and now
-- read differently — that is what keeping them is for.
-- ---------------------------------------------------------------------------

-- Q0. THE PREMISE THAT WAS FALSE.
--     0214 attributed a slowdown to 0211. This is the series that refutes it:
--     one column, fixed seed / ticks / scenario / depot, drifting monotonically
--     for a week with no step where the migrations landed.
--
--     09-01 389 · 09-02 308-500 · 09-03 431-614 · 09-04 512-652
--     09-05 545-744 · 09-06 688-804 · 09-07 643-822 · 09-08 797, 801
SELECT to_char(start_time,'MM-DD') AS day,
       count(*) AS pairs,
       min(EXTRACT(epoch FROM (end_time-start_time))::int) AS fastest_s,
       max(EXTRACT(epoch FROM (end_time-start_time))::int) AS slowest_s
FROM cron.job_run_details
WHERE command ILIKE '%determinism_pair(314159, 12%'
  AND command ILIKE '%11111111-1111-1111-1111%'
  AND status='succeeded' AND EXTRACT(epoch FROM (end_time-start_time)) > 60
GROUP BY 1 ORDER BY 1;

-- Q1. THE MISSING INDEX. ottoq_stall_bookings had nine indexes and not one of
--     them was on leg_id, which two hot paths filter.
--     BEFORE 0216: no index matching '(leg_id)'.  AFTER: ottoq_stall_bookings_leg_idx.
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname='public' AND tablename='ottoq_stall_bookings'
ORDER BY indexname;

-- Q2. WHAT IT COST. The trigger's own lookup, on the live table.
--     BEFORE 0216:  Parallel Seq Scan, 387,241 rows removed by filter,
--                   50,769 blocks read, Execution Time 965.175 ms.
--     AFTER  0216:  Index Scan using ottoq_stall_bookings_leg_idx,
--                   25 buffers, Execution Time 0.295 ms.
--
--     AND THE 3,270x DOES NOT REACH THE PAIR. Recorded here because this file
--     was written before the measurement existed and the number above would
--     otherwise read as a fix for Q0's drift. It is not. Round 25's first pair
--     on the same column took 812 s, against 797 s and 801 s before the index,
--     inside the 688-822 s band of the two preceding days. The reading above is
--     COLD-CACHE — read=50769 blocks — and in a real arm those pages are warm,
--     so ~2,236 scans do not add up to anything near an 800 s pair.
--
--     The index is still correct: it removes a cost whose size is set by total
--     history rather than by the run, which is unbounded by construction. It is
--     simply not the carrier of Q0. That is open as task G19, where the
--     hypotheses already refuted by measurement are listed so nobody re-runs
--     them.
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT b.booking_id, b.visit_id FROM public.ottoq_stall_bookings b
 WHERE b.leg_id = '00000000-0000-0000-0000-000000000001'::uuid
 ORDER BY (b.state IN ('superseded','released','cancelled')),
          lower(b.during), upper(b.during), b.stall_id, b.booked_at_sim, b.state
 LIMIT 1;

-- Q3. HOW OFTEN. 433 done-legs per 12-tick arm fire the SDR trigger; 685 legs
--     per arm open. Two arms per pair: ~2,236 scans of a 774k-row table, and
--     the table grows with every run ever archived.
SELECT count(*) FILTER (WHERE status='done') AS legs_done_per_arm,
       count(*)                              AS legs_total_per_arm,
       (SELECT count(*) FROM public.ottoq_stall_bookings) AS bookings_in_table
FROM public.ottoq_itinerary_legs
WHERE sim_run_id = '53317e05-19c4-4bd0-9315-12089f51cc6b';

-- Q4. THE DEFECT UNDERNEATH. The SDR terminus chose its booking with LIMIT 1
--     and no ORDER BY. A leg can carry several bookings — the superseded plans
--     churn leaves behind.
--     MEASURED on one arm's 202 done-legs that carry a booking:
--        exactly one booking in a settled state ......... 188
--        more than one settled .......................... 0
--        none settled (every one churned) ............... 14
--        most bookings on a single leg .................. 7
--     So "the one that was not superseded" is never ambiguous when it exists,
--     which is what 0216's ORDER BY puts first.
WITH dl AS (
  SELECT leg_id FROM public.ottoq_itinerary_legs
   WHERE sim_run_id='53317e05-19c4-4bd0-9315-12089f51cc6b' AND status='done'
), per_leg AS (
  SELECT b.leg_id, count(*) AS n_all,
         count(*) FILTER (WHERE b.state NOT IN ('superseded','released','cancelled')) AS n_settled
    FROM public.ottoq_stall_bookings b JOIN dl ON dl.leg_id=b.leg_id
   GROUP BY b.leg_id
)
SELECT count(*) AS done_legs_with_a_booking,
       count(*) FILTER (WHERE n_settled=1) AS exactly_one_settled,
       count(*) FILTER (WHERE n_settled=0) AS none_settled,
       count(*) FILTER (WHERE n_settled>1) AS more_than_one_settled,
       max(n_all)                          AS most_bookings_on_one_leg
FROM per_leg;

-- Q5. AND IT DIVERGED. The two arms of the 07:49 pair — which PASSED all
--     thirteen atoms — bound 23 of 284 SDRs to a different booking.
--       core content     16d2dce1  both arms   (identical)
--       booking pick     9f074e65 / ecf6e4d2   (different)
--     After 0217 the same divergence reads as h_sdr 833f61c9 / 49714ab9.
SELECT left(public.ottoq_hash_sdrs('53317e05-19c4-4bd0-9315-12089f51cc6b'),8) AS h_sdr_arm_a,
       left(public.ottoq_hash_sdrs('ea855128-30e9-45df-91ac-4ebd880419db'),8) AS h_sdr_arm_b;

-- Q6. WHY NOTHING CAUGHT IT. No fingerprint and no hash function reads the SDR
--     table. BEFORE 0217 this returned zero rows.
SELECT n.nspname||'.'||p.proname AS reads_the_sdr_table
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prokind='f' AND n.nspname IN ('public','twin')
  AND p.prosrc ILIKE '%ottoq_service_detail_records%'
  AND (p.proname LIKE '%fingerprint%' OR p.proname LIKE 'ottoq_hash%'
       OR p.proname='ottoq_determinism_pair')
ORDER BY 1;

-- Q7. AND THE SIGNATURE STILL DOES NOT COVER IT. ottoq_emit_sdr signs a payload
--     built from operation, pack, vehicle, class, operator, stall, times,
--     energy, source_kind, leg_id and schedule_task_id — and NOT from
--     booking_id or visit_id. So the SDR is signed, but the field naming the
--     calendar claim it settles sits outside the signature.
--     NOT FIXED HERE. Adding them moves payload_hash on every future SDR and
--     therefore h_evt on every column: a full six-column recert, and it belongs
--     with G10 (task #71). Recorded so it is not mistaken for covered ground.
SELECT position('booking_id' in p.prosrc) AS booking_id_anywhere_in_emit_sdr,
       position($$'leg_id', p_leg_id$$ in p.prosrc) AS leg_id_in_the_signed_payload,
       (position($$'booking_id', p_booking_id$$ in p.prosrc) = 0) AS booking_id_absent_from_payload
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='ottoq_emit_sdr';
