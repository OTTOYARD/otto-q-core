-- =====================================================================
-- 0116  Round 20: eight passed, and the ninth was a coin in the
--       refusal walk
-- =====================================================================
-- Round 20 ran 15:56-18:10 UTC on 2026-09-06 (10:56 AM-1:10 PM CT), nine
-- pairs on the flagship, the first round after 0201 (15:40 UTC, harness)
-- and 0200 (15:51 UTC, the recertification floor). Read 18:16 UTC (1:16 PM
-- CT), on the check-in scheduled for it.
--
-- 1. THE MATRIX (ottoq_cert_matrix at the 0200 floor)
--
--   #  fired  column                 equal  h_cmd     h_bkg     h_nrg     h_prop    h_cal     vs r19
--   1  15:56  busy_day/314159/12t    yes    9fa71d19  c568aa7c  fec46a84  4469caa1  11a24626  MOVED (first post-refit pass)
--   2  16:09  busy_day/171717/12t    yes    93e895e6  5510a9d0  2c2bef25  2574c54f  11a24626  MOVED (first post-refit pass)
--   3  16:22  busy_day/314159/12t    yes    9fa71d19  c568aa7c  fec46a84  4469caa1  11a24626  = pair 1, every field
--   4  16:35  busy_day/171717/12t    yes    93e895e6  5510a9d0  2c2bef25  2574c54f  11a24626  = pair 2, every field
--   5  16:48  normal_day/171717/12t  yes    634a8781  97056af3  b3a22762  940d3890  11a24626  identical
--   6  17:01  normal_day/171717/12t  yes    634a8781  97056af3  b3a22762  940d3890  11a24626  identical
--   7  17:14  busy_day/424242/12t    yes    adf745a2  c4df69ab  481f8320  029cad7d  11a24626  identical
--   8  17:27  busy_day/171717/24t    NO     5dd1816d  38ffdbe8  5b96f9b9  2574c54f  11a24626  arm A identical to r19; arm B e6cbbdeb / 3c29dd21
--   9  17:52  busy_day/424242/24t    yes    997e2c37  1e5f1875  fd6cfd0a  bea94486  11a24626  identical
--
--   Every arm complete. h_defr d41d8cd9 on all eighteen arms. h_cal
--   11a246262ff7a2c929483b1ee0a7cd2d on all eighteen: the priors did not
--   move during the round (0201's guard is in place; the next ingest is
--   Sunday 09-13). Wall time: 12-tick 9.0-12.6 min; 24-tick 19.6 and 18.0.
--   Matrix: 314159/12t, 171717/12t, normal_day green (2 consecutive passes
--   at the floor); 424242/12t and 424242/24t one pass; 171717/24t history
--   PPf, consecutive 0.
--
-- 2. THE PREDICTIONS IN 0200'S FOOTER, AS CORRECTED THERE AT 16:45 UTC
--
--   1  MET.      The four columns with a post-refit pass in round 19
--                (normal_day 634a8781, 424242/12t adf745a2, 171717/24t
--                5dd1816d, 424242/24t 997e2c37) reproduced it; 314159/12t
--                and 171717/12t moved once and repeated. Nothing moved
--                that 0200 could be blamed for; the pair that failed
--                reproduced round 19 in arm A.
--   2  MET.      h_cal identical on all eighteen arms; canon_cal populated
--                on all six columns.
--   3  MET,      h_prop unchanged on the four post-refit columns and on
--      with a     171717/12t; 314159/12t's h_prop moved 2b86847e ->
--      note.      4469caa1 with its first post-refit pass, alongside its
--                h_cmd -- the same carrier, the refit, not a proposer coin
--                (h_cmd and h_prop moved together, and repeated together).
--                h_defr unchanged.
--   4  NOT MET.  8 of 9. Pair 8's arms disagree on h_cmd, h_dec, h_evt,
--                h_bkg and endst, and agree on fp, boot, h_nrg, h_prop,
--                h_defr, h_cal and ticks.
--
-- 3. THE COIN, CONVICTED (pair 8, arms b8f98769 / ab7c7139)
--
--   First divergence, from the command and decision streams: sim 12:00
--   (tick 20). Its cause one tick earlier: at sim 11:30 vehicle 0d43459d
--   (Waymo, seed_idx 38) arrived at the gate and the decide path issued
--   TWO proceed_to_stall commands for it to the same staging stall
--   bc469f6a -- one with reason gate_intake, one carrying new_state
--   staged_awaiting_service. Both were refused target_occupied. The
--   reactor, ottoq.ottoq_react_to_refusals, walks refused commands
--
--       ORDER BY issued_at, vehicle_id, command_type, payload->>'stall_id'
--
--   and the two rows are equal on all four keys. The walk gives the first
--   row the first free stall (91ebbf41) and the second the next (765adddb);
--   the confirm pass then keeps the 91ebbf41 command and supersedes the
--   other. In arm A the survivor was the staging command, so the vehicle
--   became staged_awaiting_service (event 13195245) and was promoted ready
--   at 12:00; in arm B the survivor was the intake command, so the vehicle
--   kept arrived_at_gate with a stall pointer (event 13201695). At 12:00
--   the stall choice for vehicle 2bc9a4a0 differed (6b043f2d vs f99a8657),
--   and from there the streams diverge. The order the sort delivered is
--   physical row order; refused rows have been UPDATEd twice, so their
--   physical order is whatever free space each arm found.
--
--   Prevalence. Same (run, issued_at, vehicle, command_type, refused stall)
--   with count > 1 among refused target_occupied/resource_faulted commands:
--   12 groups in round 20 (314159/12t: vehicles 5cee8fb3@06:00 and
--   0ea2ccfe@07:30 in all four arms; 171717/24t: 0d43459d@11:30 both arms;
--   424242/24t: c8ae20e3@13:30 both arms); 15,089 groups in the ledger
--   since 08-28. Eleven of the twelve resolved alike by chance.
--
--   twin.ottoq_sim_confirm_commands has the same shape one layer earlier
--   (0060): its duplicate ranking and current-intent window end in
--   c.payload::text and c.command_id (gen_random_uuid()); the confirm walk
--   ends in the stall id. 0207 adds ottoq_vehicle_commands.command_seq
--   (identity: issuance order, which the deterministic decide path makes
--   a function of the run) as the last key of all four walks.
--
-- 4. A LEDGER-HYGIENE FINDING ON THE WAY (G16, filed, not fixed here)
--
--   ottoq_sim_stop_and_reset pins ottoq.sim_run_id to the run it tears
--   down (0092: "the teardown's own trigger events must carry the run they
--   tear down") and nothing re-points it before the next arm boots, so
--   arm B's boot writes (94-100 vehicle.state_changed rows per pair, and
--   the condition draws with condition_drawn_run = arm A) are stamped with
--   arm A's run id. Measured on pairs 7, 8, 9: arm A carries 94, 94, 100
--   boot-shaped events; arm B carries 0. Invisible to the verdict, whose
--   hashes are taken before teardown; wrong in the ledger.
--
-- 5. STANDING
--
--   Part A's sentence after round 20: the engine reproduces itself to the
--   byte when its priors hold, EXCEPT where two commands for one vehicle
--   tie on every key of a walk; there physical row order decides, and it
--   decided differently once in 20 rounds. 0207 removes the tie. 0202,
--   0203 and 0207 apply next and move the floor; round 21 recertifies.
-- =====================================================================

-- 1. The matrix at the floor (expect three green, two one-pass, one PPf).
SELECT scenario, seed, ticks, pairs_seen, consecutive_passes, green, history,
       left(canon_cmd,8) AS cmd, left(canon_bkg,8) AS bkg, left(canon_nrg,8) AS nrg,
       left(canon_prop,8) AS prop, left(canon_defr,8) AS defr, left(canon_cal,8) AS cal,
       recert_floor
  FROM public.ottoq_cert_matrix(now() - interval '2 days')
 WHERE depot = '11111111-1111-1111-1111-111111111111'
 ORDER BY ticks DESC, scenario, seed;

-- 2. The nine verdicts (expect 8 equal, 1 not; h_cal identical on all).
SELECT r.started_at, j->>'scenario' AS scen, j->>'seed' AS seed, j->>'ticks' AS ticks, j->>'equal' AS equal,
       left(j->'arm_a'->>'h_cmd',8) AS cmd_a, left(j->'arm_b'->>'h_cmd',8) AS cmd_b,
       left(j->'arm_a'->>'h_cal',8) AS cal_a, left(j->'arm_b'->>'h_cal',8) AS cal_b
  FROM public.ottoq_sim_runs r, LATERAL (SELECT r.validation_notes::jsonb AS j) x
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.run_by = 'cert_harness'
   AND r.started_at BETWEEN '2026-09-06 15:50+00' AND '2026-09-06 18:15+00'
   AND r.sim_run_id = (j->'arm_a'->>'run')::uuid
 ORDER BY r.started_at;

-- 3. The coin: the two tied rows in each arm of pair 8 (expect 2 and 2).
SELECT left(c.sim_run_id::text,8) AS arm, count(*) AS tied_rows,
       string_agg(COALESCE(c.payload->>'reason','(staging)') || ' -> ' || left(c.payload->'reaction'->>'new_stall_id',8), ' | ') AS reroutes
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id IN ('b8f98769-5ae5-4ac8-9aff-f9fd38bd2e0e','ab7c7139-9330-47f8-876a-a7d1d22ed6ba')
   AND c.vehicle_id = '0d43459d-a82f-4d46-9579-43fc89feb981' AND c.issued_at = '2026-09-01 11:30:00+00'
   AND c.command_type = 'proceed_to_stall' AND c.status = 'refused' AND c.reason_code = 'target_occupied'
   AND c.payload->>'stall_id' = 'bc469f6a-edfd-46b9-b71f-be3d9e249c74'
 GROUP BY c.sim_run_id;

-- 4. Prevalence of the tie in round 20 (expect 12 groups over 8 arms).
SELECT count(*) AS tie_groups, count(DISTINCT sim_run_id) AS arms
  FROM (SELECT c.sim_run_id, c.issued_at, c.vehicle_id, c.command_type, c.payload->>'stall_id' AS stall
          FROM public.ottoq_vehicle_commands c
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id
         WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.run_by = 'cert_harness'
           AND r.started_at BETWEEN '2026-09-06 15:50+00' AND '2026-09-06 18:15+00'
           AND c.status = 'refused' AND c.reason_code IN ('target_occupied','resource_faulted')
         GROUP BY 1,2,3,4,5 HAVING count(*) > 1) g;

-- 5. G16: boot-shaped events stamped with the previous arm's run (expect A > 0, B = 0 per pair).
SELECT left(r.sim_run_id::text,8) AS run, j->>'seed' AS seed, j->>'ticks' AS ticks,
       CASE WHEN r.sim_run_id = (j->'arm_a'->>'run')::uuid THEN 'A' ELSE 'B' END AS arm,
       (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = r.sim_run_id AND e.event_type = 'vehicle.state_changed'
          AND e.payload->'diff' ? 'config' AND e.payload->'diff' ? 'current_soc'
          AND e.payload->'diff'->'last_state_change'->>'to' = '2026-09-01T02:00:00+00:00') AS boot_shaped
  FROM public.ottoq_sim_runs r, LATERAL (SELECT r.validation_notes::jsonb AS j) x
 WHERE r.sim_run_id IN ('484900ed-d1a6-47c7-8117-cf02d8234104','ad81f5cd-8603-43ba-9283-6e725e89fa36',
                        'b8f98769-5ae5-4ac8-9aff-f9fd38bd2e0e','ab7c7139-9330-47f8-876a-a7d1d22ed6ba',
                        '029b19bc-b65c-4e0c-8258-b2254c34498e','3cdb98ef-ef90-4a17-932a-7f08729f6430')
 ORDER BY r.started_at, arm;
