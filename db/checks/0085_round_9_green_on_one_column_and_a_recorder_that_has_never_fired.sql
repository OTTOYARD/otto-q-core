-- =====================================================================
-- 0085  Round 9: green on one column, and a recorder that has never fired
-- =====================================================================
-- Closes the 0169 round opened in db/checks/0084. Two independently
-- fired flagship pairs, busy_day / 171717 / 12t.
--
-- §1  THE RESULT
-- ---------------------------------------------------------------------
--   pass 1  10:21 PM CT  runs 3085f1a3, 9c96d5df  passed, equal=true
--   pass 2  10:36 PM CT  runs 50edcbac, 6c78b78e  passed, equal=true
--
-- All four hashes byte-identical across BOTH passes AND round 8:
--   h_cmd 04177a2a5d686032aa1c54fcac43f958
--   h_dec 5328154a5f72e9e1bb6b10d177def459
--   h_bkg 0bf42b3cc1b2db78de9e91274d28b3df
--   h_nrg 8dcf8918702a18b9f20022b80dd24513
--
-- pairs_seen 2, consecutive_passes 2 -> green. Canons in
-- db/canons/round9.md. This is the first round in which round 8's table
-- was diffable, which is why it was committed.
--
-- §2  THE PREDICTION TOOK ITS SECOND BRANCH
-- ---------------------------------------------------------------------
-- db/checks/0084 §8, published BEFORE the pairs landed, said h_dec moves
-- if and only if the recorder fired, and that if deferred rows were 0
-- all four canons must reproduce round 8 exactly - and that this would
-- mean decide_seat_batch has never bound anywhere, and to say so plainly.
--
-- recorder_rows = 0 on all four runs. So, plainly:
--
--   DECIDE_SEAT_BATCH HAS NEVER BOUND ANYWHERE.
--
-- At 116 assets the flagship's seating loop never has more than 20
-- qualifying candidates in a tick. Two consequences, both stated:
--   1. 0169 is certified a no-op on the engine - four canons unmoved
--      across two independently fired pairs.
--   2. 0169's new branch has still NEVER EXECUTED, anywhere. It is
--      instrumentation for a condition that has not yet occurred. Not a
--      defect - but not a tested code path either, and it must not be
--      described as one.
SELECT r.sim_run_id,
       r.validation_notes::jsonb->>'outcome'        AS outcome,
       r.validation_notes::jsonb->'arm_b'->>'h_cmd' AS h_cmd,
       r.validation_notes::jsonb->'arm_b'->>'h_dec' AS h_dec,
       r.validation_notes::jsonb->'arm_b'->>'h_bkg' AS h_bkg,
       r.validation_notes::jsonb->'arm_b'->>'h_nrg' AS h_nrg,
       (SELECT count(*) FROM ottoq_decisions d
         WHERE d.sim_run_id = r.sim_run_id
           AND d.outcome_status = 'deferred_tick_budget') AS recorder_rows
  FROM ottoq_sim_runs r
 WHERE r.run_by = 'cert_harness' AND r.started_at >= '2026-09-03 03:20:00+00'
 ORDER BY r.started_at;

-- §3  A TIMING ALARM THAT WAS MINE, AND WAS WRONG
-- ---------------------------------------------------------------------
-- Pass 1's first arm ran 480 s against round 8's 296-400 s band for this
-- column, and I published that as a possible cost of 0169 removing
-- `LIMIT 20`. It is not.
--
--   pass 1 arms: 480 s / 200 s
--   pass 2 arms: 448 s / 179 s
--
-- A ~2.5x spread between two arms doing IDENTICAL work inside ONE
-- transaction, repeated across both pairs. That is load and warm-up. The
-- second arm of each pair is FASTER than the round-8 band, and the
-- canons are byte-identical, so nothing behavioural changed. Recorded
-- because the alarm was published before it was checked.
--
-- §4  WHAT ROUND 9 DOES NOT COVER
-- ---------------------------------------------------------------------
-- ONE column of six. busy_day/171717/24t, busy_day/314159/12t,
-- busy_day/424242/12t, busy_day/424242/24t and normal_day/171717/12t
-- were NOT re-run against 0169. They still carry round-8 canons and are
-- not diffed against the current engine. Round 9 is green on one column,
-- not six. Task #47 (normal_day 171717/12t) remains open on its own
-- stated evidence bar.
--
-- §5  0176 AND 0178 APPLIED AFTER THE ROUND CLOSED
-- ---------------------------------------------------------------------
-- Nothing went into the database mid-round. Both close the two reds
-- db/checks/0084 §6 recorded, and both are the same shape:
--
--   0170  returns_unserved counted work due beyond the horizon
--   0172  a return stamped after the run ended never happened
--   0176  a dispatch deadline beyond the horizon was never missed
--   0178  an asset that arrived on the last tick never had a turn
--
-- The rule, four times now: A RUN MAY ONLY BE JUDGED ON WHAT IT HAD TIME
-- TO DO. And the corollary this codebase keeps re-learning: a check that
-- cannot pass on a short run is as useless as one that cannot fail -
-- both train the reader to ignore red. What is excluded is REPORTED,
-- never silently dropped.
--
-- Verification - the same smoke that produced the two reds:
--   before  no_asset_starves...      FALSE  "2 of 4 assets ended below
--                                            their own target SoC..."
--           assets_made_their_due_time FALSE "0 on time, 0 late, 3 stranded"
--   after   no_asset_starves...      TRUE   "0 of 2 assets ... (2 set
--                                            aside: arrived at or after
--                                            the last decision clock, so
--                                            never had a turn)"
--           assets_made_their_due_time TRUE  "NO DUE TIMES in this run -
--                                            not evidence about readiness"
--
-- and the readiness object now carries due_beyond_horizon = 3 with
-- horizon 2026-09-01T05:00:00+00 - the three deadlines seven hours past
-- the end of the run, reported instead of counted. All 16 checks green;
-- every other assertion unchanged (2 of 2 assignments, 15 bookings,
-- 212.5 kW plan, 4 of 4 SDRs, proposer quiesced, pair equal).
SELECT * FROM twin.ottoq_grid_smoke(424242, 6, 'grid-0169-smoke', 'grid_smoke');

-- §6  STILL OPEN, EACH NEEDING ITS OWN forces_recert ROUND
-- ---------------------------------------------------------------------
--   0177  the cold-start guard looked at every depot. WRITTEN AND
--         COMMITTED, NOT APPLIED. twin.ottoq_sim_start_run counts
--         deployed vehicles with no depot filter, so one depot's traffic
--         decides whether another depot's run cold-starts. The
--         certification path does not depend on that branch (the pair
--         primes every arm explicitly at 0.70), so no recorded canon is
--         in question - but it blocks the two-lane cadence, and it is
--         why a grid smoke must not run beside a flagship pair.
--   twin clock: ottoq_sim_seed_fleet's
--         actual_return_at = COALESCE(actual_return_at, NOW())
--   rules:  9 of 29 active rules never evaluate (6 block-severity)
--         because the engine never announces the actions they are scoped
--         to - vehicle_state_change, stall_state_change,
--         bess_state_change. The rules layer is wired to DECISIONS, not
--         STATE TRANSITIONS. See docs/DECISION_BOUNDARY.md.
--   0169:  prove the recorder can fire at all. Needs a contention
--         fixture (more assets than points); the 4-asset grid never has
--         two candidates in a tick. decide_seat_batch = 1 there changed
--         nothing, self-consistently - the override WAS resolving
--         (verified: run -> 1, global -> 20, then removed). Do NOT run
--         it concurrently with a flagship pair, per 0177.
SELECT name, forces_recert, left(note, 90) AS note
  FROM public.ottoq_cert_lineage
 WHERE name IN ('the_pair_and_the_scenario_must_name_the_same_world',
                'a_deadline_past_the_end_of_the_run_was_never_missed',
                'an_asset_that_arrived_on_the_last_tick_never_had_a_turn',
                'the_cold_start_guard_looked_at_every_depot')
 ORDER BY classified_at;
