-- =====================================================================
-- 0117  Round 21: all nine passed, and every canon moved once
-- =====================================================================
-- Round 21 ran 20:48-23:13 UTC on 2026-09-06 (3:48-6:13 PM CT), nine pairs
-- on the flagship, the first round after 0202 (20:37 UTC), 0203 (20:39)
-- and 0207 (20:42, the recertification floor). Read 23:16 UTC (6:16 PM CT)
-- on the check-in scheduled for it; written up 2026-09-07 1:00 PM CT.
--
-- 1. THE MATRIX (ottoq_cert_matrix at the 0207 floor, 20:42:00)
--
--   #  fired  column                 equal  h_cmd     h_rule    h_prop    h_cal     vs r20
--   1  20:48  busy_day/171717/24t    yes    050c4606  62ed1a1e  0046879e  11a24626  MOVED (r20 5dd1816d/arm A)
--   2  21:13  busy_day/314159/12t    yes    109e340b  333cf172  a79c1095  11a24626  MOVED (r20 9fa71d19)
--   3  21:27  busy_day/171717/12t    yes    1ae7ba68  5a6ee595  0046879e  11a24626  MOVED (r20 93e895e6)
--   4  21:41  normal_day/171717/12t  yes    5921ef70  43cfd0a4  779e5a74  11a24626  MOVED (r20 634a8781)
--   5  21:55  busy_day/424242/12t    yes    76134009  c3cca844  029cad7d  11a24626  MOVED (r20 adf745a2)
--   6  22:09  busy_day/314159/12t    yes    109e340b  333cf172  a79c1095  11a24626  = pair 2, every field
--   7  22:23  busy_day/171717/12t    yes    1ae7ba68  5a6ee595  0046879e  11a24626  = pair 3, every field
--   8  22:37  normal_day/171717/12t  yes    5921ef70  43cfd0a4  779e5a74  11a24626  = pair 4, every field
--   9  22:51  busy_day/424242/24t    yes    8f232001  eb2fce86  aabef458  11a24626  MOVED (r20 997e2c37)
--
--   NINE OF NINE EQUAL AND COMPLETE. Every arm carries h_rule (0203's new
--   instrument) and the two arms of every pair agree on it: 18 of 18.
--   h_defr d41d8cd9 and h_cal 11a246262ff7a2c929483b1ee0a7cd2d on all
--   eighteen arms; the boot fingerprints are unchanged from round 20
--   (803698f3 / 92b02f8b / e418e4f0), so the worlds booted identical and
--   only the decide path moved. Wall time: 12-tick 9.9-13.4 min; 24-tick
--   21.1 and 22.0. Matrix after the round: 314159/12t, 171717/12t and
--   normal_day green (2 consecutive passes at the floor); 424242/12t,
--   424242/24t and 171717/24t one pass each (history PPPPPP, PPPPPP,
--   PPPPfP -- the f is round 20's failure, now repaired).
--
-- 2. THE PREDICTIONS, JUDGED
--
--   0202 (an evaluator INSERT gains a column; cannot move a decision)
--     MET. Nothing is attributable to it. Every arm's h_rule is populated
--     and every pair's arms agree, which is what a column-only change
--     should produce.
--
--   0203 (h_rule measured, not yet judged)
--     MET, and the promotion gate is satisfied. Nine post-0203 flagship
--     pairs; arms agree on h_rule in all nine; none disagree. 0205 may
--     move h_rule into v_equal.
--
--   0207 (the refusal-walk tie)
--     Its operative half MET: 171717/24t, which failed round 20 on that
--     tie, passed, and passed with both arms identical on every hash.
--     Its SCOPE prediction NOT MET, and the miss is this check's finding.
--     The header predicted that only the three columns carrying a refusal
--     tie in round 20 (314159/12t, 171717/24t, 424242/24t) could move and
--     that the other three MUST NOT. All six moved. See section 3.
--
-- 3. THE CORRECTION: 0207 CHANGED THE CONFIRM PASS FOR EVERY DUPLICATE,
--    NOT ONLY FOR THE REFUSAL TIE
--
--   0207 was written from round 20's failure, which was a tie among
--   REFUSED commands in ottoq.ottoq_react_to_refusals. That walk is rare:
--   12 tied groups in round 20, 8 in round 21. But the same migration also
--   replaced the sort keys of the three walks in twin.ottoq_sim_confirm_
--   commands -- the supersession window, the duplicate ranking, and the
--   confirm walk -- swapping c.payload::text and the random c.command_id
--   for c.command_seq. Those walks run over EVERY same-tick same-stall
--   duplicate command, refused or not, and that population is two orders
--   of magnitude larger:
--
--     round 20   244 duplicate groups, 18 arms, 32 vehicles
--     round 21   230 duplicate groups, 18 arms, 33 vehicles
--     of which the refusal tie 0207 was written for: 12 and 8
--
--   All of them are proceed_to_stall, and they are the ordinary product of
--   the decide path issuing a gate_intake command and a staging command
--   for one vehicle to one stall in one tick.
--
--   The measurement that convicts the scope error (section 4 below, run on
--   round 21's own rows): of the 230 duplicate groups, the OLD keys
--   (payload::text, then command_id) and the NEW key (command_seq) select
--   a DIFFERENT survivor in 214, spread across all 18 arms. The old order
--   was text order over the payload; the new order is issuance order.
--   Two-thirds of a percent of those groups were refusal ties. The rest
--   were always going to move, and the header should have said so.
--
--   The engine is not worse for it: the new survivor is the first command
--   the decide path issued, which is the intent it formed first, and the
--   choice is now a function of the run rather than of the heap. But the
--   prediction was wrong in scope, and the honest reading of round 21 is
--   "0207 moved every canon, once, deterministically" -- not "three
--   columns may move."
--
--   WHAT ROUND 22 MUST SHOW. Every column's h_cmd must equal round 21's.
--   A column that moves again has a second carrier and 0207 did not close
--   it. Three columns (424242/12t, 424242/24t, 171717/24t) are on one pass
--   and need their repeat before the floor can be called green.
--
-- 4. THE FIRST DIVERGENCE FROM ROUND 20, TRACED
--
--   424242/12t moved 484900ed(r20 arm A) -> af614e10(r21 arm A); the
--   command streams first differ at sim 02:30-03:30 (ticks 2-3), where
--   round 21 enacts a promote_ready that round 20 held as hold_no_space,
--   and the reroute stall assignments differ from there on. That is the
--   signature of a changed confirm-pass survivor one tick earlier: when
--   the surviving command is the one carrying new_state, the vehicle
--   reaches staged_awaiting_service and is promotable; when it is the
--   intake command, the vehicle keeps arrived_at_gate. Round 20's check
--   0116 section 3 describes the same mechanism as the failure mode; 0207
--   made it a decision instead of a coin, and the decision differs from
--   the coin's most common outcome.
--
-- 5. STANDING
--
--   Part A's sentence after round 21: the engine reproduces itself to the
--   byte on all six certification columns, and every tie that decided a
--   command is now decided by the run rather than by physical row order.
--   Three columns need one more pass. 0204 (sim clock in the event stream
--   and in the shield), 0205 (h_rule promoted into the verdict) and 0206
--   (the recall ledger) apply next and move the floor again; round 22
--   recertifies and must reproduce every canon in section 1.
-- =====================================================================

-- 1. The matrix at the floor (expect nine pairs seen, all six columns
--    carrying canon_rule, three green).
SELECT scenario, seed, ticks, pairs_seen, consecutive_passes, green, history,
       left(canon_cmd,8) AS cmd, left(canon_bkg,8) AS bkg, left(canon_nrg,8) AS nrg,
       left(canon_prop,8) AS prop, left(canon_defr,8) AS defr, left(canon_cal,8) AS cal,
       left(canon_rule,8) AS rule, recert_floor
  FROM public.ottoq_cert_matrix(now() - interval '3 days')
 WHERE depot = '11111111-1111-1111-1111-111111111111'
 ORDER BY ticks DESC, scenario, seed;

-- 2. The nine verdicts (expect nine equal, and arm_a = arm_b on h_rule
--    in all nine -- the 0205 promotion gate).
SELECT r.started_at, j->>'scenario' AS scen, j->>'seed' AS seed, j->>'ticks' AS ticks,
       j->>'equal' AS equal,
       left(j->'arm_a'->>'h_cmd',8) AS cmd,
       left(j->'arm_a'->>'h_rule',8) AS rule_a, left(j->'arm_b'->>'h_rule',8) AS rule_b,
       (j->'arm_a'->>'h_rule') = (j->'arm_b'->>'h_rule') AS rule_agrees,
       left(j->'arm_a'->>'h_cal',8) AS cal, left(j->'arm_a'->>'fp',8) AS fp
  FROM public.ottoq_sim_runs r, LATERAL (SELECT r.validation_notes::jsonb AS j) x
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.run_by = 'cert_harness'
   AND r.started_at BETWEEN '2026-09-06 20:45+00' AND '2026-09-06 23:20+00'
   AND r.sim_run_id = (j->'arm_a'->>'run')::uuid
 ORDER BY r.started_at;

-- 3. THE CORRECTION, MEASURED. Of round 21's same-tick same-stall
--    duplicate command groups, how many would the OLD confirm-pass keys
--    (payload::text, command_id) have resolved differently from the NEW
--    key (command_seq)? Expect 230 groups, 214 disagreements, 18 arms.
--    This is why every canon moved, and why 0207's header was wrong to
--    name only the three columns that carried a refusal tie.
WITH r21 AS (
  SELECT c.sim_run_id, c.issued_at, c.vehicle_id, c.command_type,
         c.payload->>'stall_id' AS stall, c.command_id, c.command_seq,
         c.payload::text AS ptext
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.run_by = 'cert_harness'
     AND r.started_at BETWEEN '2026-09-06 20:45+00' AND '2026-09-06 23:20+00'),
g AS (
  SELECT sim_run_id, issued_at, vehicle_id, command_type, stall,
         (array_agg(command_id ORDER BY ptext ASC, command_id ASC))[1] AS old_keeps,
         (array_agg(command_id ORDER BY command_seq ASC))[1]           AS new_keeps
    FROM r21 GROUP BY 1,2,3,4,5 HAVING count(*) > 1)
SELECT count(*) AS dup_groups,
       count(*) FILTER (WHERE old_keeps IS DISTINCT FROM new_keeps) AS keys_disagree,
       count(DISTINCT sim_run_id) FILTER (WHERE old_keeps IS DISTINCT FROM new_keeps) AS arms_affected
  FROM g;

-- 4. Prevalence across both rounds: the duplicate population the confirm
--    pass walks, versus the refusal tie 0207 was written for.
--    Expect r20 244/12 and r21 230/8, 18 arms each.
WITH census AS (
  SELECT CASE WHEN r.started_at < '2026-09-06 18:15+00' THEN 20 ELSE 21 END AS round,
         c.sim_run_id, c.issued_at, c.vehicle_id, c.command_type,
         c.payload->>'stall_id' AS stall,
         count(*) FILTER (WHERE c.status = 'refused'
                            AND c.reason_code IN ('target_occupied','resource_faulted')) AS refused_n
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.run_by = 'cert_harness'
     AND (r.started_at BETWEEN '2026-09-06 15:50+00' AND '2026-09-06 18:15+00'
       OR r.started_at BETWEEN '2026-09-06 20:45+00' AND '2026-09-06 23:20+00')
   GROUP BY 1,2,3,4,5,6 HAVING count(*) > 1)
SELECT round, count(*) AS dup_groups,
       count(*) FILTER (WHERE refused_n > 1) AS refusal_tie_groups,
       count(DISTINCT sim_run_id) AS arms, count(DISTINCT vehicle_id) AS vehicles
  FROM census GROUP BY 1 ORDER BY 1;

-- 5. The pin: the two functions 0207 rewrote still carry its bodies.
--    Expect 4d46d5e5... and 68286608....
SELECT n.nspname || '.' || p.proname AS fn, md5(pg_get_functiondef(p.oid)) AS body_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'ottoq' AND p.proname = 'ottoq_react_to_refusals')
    OR (n.nspname = 'twin'  AND p.proname = 'ottoq_sim_confirm_commands')
 ORDER BY 1;
