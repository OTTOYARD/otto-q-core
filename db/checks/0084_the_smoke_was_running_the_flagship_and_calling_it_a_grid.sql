-- =====================================================================
-- 0084  The smoke was running the flagship and calling it a grid
-- =====================================================================
-- 2026-09-02 evening / 2026-09-03 early. Opening the 0169 round.
--
-- 0169 (deferred_tick_budget recorder) was applied and the cheap grid
-- smoke fired before spending flagship pairs, per its own apply
-- procedure. The smoke failed after 170.1 s:
--
--   ERROR: grid_assert: run <NULL> not found
--
-- and produced zero fixture runs. 170.1 s against a ~20 s fixture
-- baseline. Two hypotheses were live overnight; BOTH ARE WRONG, and
-- they are recorded here because the wrong ones cost the most time:
--
--   H1 (rejected earlier): the per-candidate ottoq_policy_get call in
--      the seating loop is the slowdown. MEASURED at ~26 us/call
--      (257 ms per 10,000, EXPLAIN ANALYZE). Dead before it cost a
--      risky declare-block edit.
--   H2 (rejected here): 0169 removed `LIMIT 20` in favour of
--      row_number() OVER + count(*) OVER, forcing full materialisation
--      of the ranked set. Also dead - see below.
--
-- §1  WHAT IT ACTUALLY WAS
-- ---------------------------------------------------------------------
-- The cron command was:
--   SELECT * FROM twin.ottoq_grid_smoke(424242, 6, 'grid-0169-smoke',
--                                       'busy_day');
--
-- twin.ottoq_grid_smoke takes a fixture slug AND a scenario code as
-- INDEPENDENT arguments:
--   * the slug decides the depot it checks exists, resets, fingerprints
--   * the SCENARIO decides the depot stamped on the run row, because
--     twin.ottoq_sim_start_run writes v_scenario.depot_id and never
--     sees the pair's p_depot
--
-- 'grid-0169-smoke' is a 6-point fixture (aacd0bb0-...). 'busy_day' is
-- bound to the FLAGSHIP (11111111-...). So the smoke spent 170 seconds
-- ticking two arms of the flagship under a headline that said grid
-- fixture. The 170.1 s was never 0169: it was the flagship. H2 dies.
--
-- It failed only because it then went looking for its own arm by the
-- FIXTURE's depot id and found nothing there:
--   SELECT r.sim_run_id INTO v_arm FROM ottoq_sim_runs r
--    WHERE r.depot_id = v_depot AND r.run_by = 'cert_harness' ...
--
-- §2  THE FAILURE WAS THE LUCKY OUTCOME
-- ---------------------------------------------------------------------
-- The obvious repair - look the arm up by run id instead of by depot -
-- would have made it PASS. A green wall of grid-fixture assertions
-- would then have been reporting on the flagship. The lookup that broke
-- the run is the only thing that stopped it lying. That is the defect
-- class this codebase convicts: a check that reports about a world it
-- did not run.
--
-- Nothing persisted: the exception rolled the whole transaction back.
-- Verified - 0 cert_harness runs after 02:59 UTC, last cert run still
-- 2026-09-02 23:55 UTC from before the smoke.
--
-- §3  THE CAUSE WAS ALREADY ON THE RECORD
-- ---------------------------------------------------------------------
-- 0153's own header names the symptom without closing the cause:
--   "The Benchmark depot failed as a pair target because three of those
--    were missing (scenario bound to the flagship, ...)"
-- and opens by quoting Chase: "If we see scenario A go to grid B ...
-- that would be a success." Scenario A going to grid B is exactly what
-- the harness permitted. The fixture was built to dodge the hazard;
-- nothing forbade it.
--
-- Scope check - has this bitten a real lane? No. All 487 cert_harness
-- runs to date used busy_day (415) or normal_day (72), both bound to
-- the flagship, so no canon was ever built from a mismatched pair. The
-- second lane simply never ran. The MECHANISM was live and unguarded;
-- the DAMAGE is zero. Both halves stated, neither inflated.
--
-- §4  0175 - THE FIX, AND PROOF IT REFUSES
-- ---------------------------------------------------------------------
-- ottoq_determinism_pair and twin.ottoq_grid_smoke now refuse a
-- scenario whose bound depot is not the depot they were told to run,
-- BEFORE either arm is created. The smoke also reads the arm id from
-- the pair's own return value (arm_b.run), so the depot lookup that hid
-- the mismatch is gone and the tempting repair is no longer available.
--
-- A check that cannot fail is not a check. Both guards were fired at
-- the exact command that burned 170.1 s:
--
--   SELECT * FROM twin.ottoq_grid_smoke(424242,6,'grid-0169-smoke','busy_day');
--   ERROR: grid smoke: fixture grid-0169-smoke is depot aacd0bb0-...,
--          but scenario busy_day is bound to depot 11111111-....
--          This would run that world and report it as this one.
--
--   SELECT ottoq_determinism_pair(424242,1,'busy_day',aacd0bb0-...);
--   ERROR: determinism_pair: scenario busy_day is bound to depot
--          11111111-..., but the pair was told to run depot aacd0bb0-....
--          The arms would tick one world and be fingerprinted against
--          another.
--
-- Both immediate. 170.1 s -> refused before anything starts.
SELECT * FROM twin.ottoq_grid_smoke(424242, 6, 'grid-0169-smoke', 'busy_day');  -- must ERROR
SELECT public.ottoq_determinism_pair(424242, 1, 'busy_day',
         md5('ottoq_grid_fixture:grid-0169-smoke')::uuid,
         '2026-09-01 02:00:00+00', 30);                                        -- must ERROR

-- §5  THE SMOKE, RUN AS IT WAS ALWAYS MEANT TO BE RUN
-- ---------------------------------------------------------------------
-- 10.8 s for two 6-tick arms. Not 170.1. The pair PASSED, arms equal.
-- 0169 costs nothing and breaks nothing.
--
--   pair_wall_seconds                        10.8 s, arm 5c2e48a5
--   run_completed                            status=completed, ticks=6
--   every_enacted_assignment_is_booked       2 of 2
--   no_point_double_booked                   0 overlapping among 15
--   every_booking_on_a_capable_point         0 of 15 incapable
--   charge_point_matches_the_asset_need      2 of 2
--   the_fast_point_goes_to_whoever_needs_it  0 inversions among 2
--   site_power_cap_held_in_plan_and_meter    212.5 kW plan / 119.5 kW
--                                            metered / 600 kW cap
--   every_completed_operation_has_an_sdr     4 of 4
--   every_refusal_carries_a_reason           0 of 3 without
--   proposer_quiesced                        6 invocations, 0 non-policy
--   pair_verdict_passed                      outcome=passed, equal=true
--   the_power_cap_was_exercised              CAP NEVER BOUND - not
--                                            evidence about the cap
--   injected_fault_was_met                   NO FAULT INJECTED - not
--                                            evidence
SELECT * FROM twin.ottoq_grid_smoke(424242, 6, 'grid-0169-smoke', 'grid_smoke');

-- §6  TWO REDS, AND WHY NEITHER IS 0169
-- ---------------------------------------------------------------------
-- The run above returned two failing checks. Both are horizon artifacts
-- IN THE CHECKS, not engine defects, and both are the same family as
-- 0170/0171/0172:
--
--   no_asset_starves_while_a_capable_point_is_free  FALSE
--     "2 of 4 assets ended below their own target SoC having never been
--      assigned a charge point while one stood free"
--     Those two assets (4384f56b, 4e59acce) ARRIVED AT 05:00:00 - the
--     final tick, the instant the run ends. There is no tick after
--     their arrival in which they could have been seated. This is the
--     final-tick-arrival component of the stranding chain already
--     characterised in 0081/0082 (32 -> 16 -> 0).
--
--   assets_made_their_due_time                      FALSE
--     "0 on time, 0 late, 3 stranded"
--     All three carry dispatch_due_at = 2026-09-01 12:00:00 UTC. The
--     run's horizon ends at 05:00:00 UTC. A deadline SEVEN HOURS past
--     the end of the run is counted as missed. This is exactly the
--     defect 0170 closed for returns_unserved and 0172 closed for
--     post-horizon returns; ottoq_kpi_dispatch_readiness still has it.
--
-- Both are queued as their own (non-forces_recert) fix, on the 0170
-- pattern: count only what is due inside sim_clock_current, and report
-- the rest as due_beyond_horizon rather than as failure. A check that
-- cannot pass on a short run is as useless as one that cannot fail -
-- it trains the reader to ignore red.
SELECT v.vehicle_id, v.archetype, v.urgency,
       v.arrived_at        AT TIME ZONE 'UTC' AS arrived_utc,
       v.dispatch_due_at   AT TIME ZONE 'UTC' AS due_utc,
       r.sim_clock_current AT TIME ZONE 'UTC' AS run_ends_utc
  FROM ottoq_visit_needs v JOIN ottoq_sim_runs r USING (sim_run_id)
 WHERE v.sim_run_id = '5c2e48a5-cf7c-4ca7-ab0e-5bc85feadbd5'
 ORDER BY v.arrived_at;

-- §7  THE RECORDER DID NOT FIRE, AND THE FIXTURE CANNOT MAKE IT
-- ---------------------------------------------------------------------
-- 0169's whole point is the deferred_tick_budget row: the engine may
-- say it found nothing, but not that it never looked. On the fixture:
--
--   deferred_tick_budget rows           0
--   decisions total                     13
--   by action_context: stall_assignment  2 enacted
--                      task_start         5 enacted
--                      bess_dispatch      1 enacted, 4 noop, 1 override
--
-- Only TWO stall_assignment decisions in the entire run - the seating
-- loop never sees more than one candidate in a tick, so seat_rank never
-- exceeds the batch. Setting decide_seat_batch = 1 on the fixture depot
-- changed nothing (identical 8/4/1 outcome distribution), which is
-- self-consistent rather than evidence the override failed.
--
-- The override WAS resolving - verified directly rather than assumed:
--   ottoq_policy_get(run,  'decide_seat_batch', 20) -> 1
--   ottoq_policy_get(NULL, 'decide_seat_batch', 20) -> 20
-- The plumbing works; the fixture is simply too small to exercise it.
-- The override was then REMOVED (0 rows remain, global back to 20).
--
-- So the fixture proves 0169 is harmless, and cannot prove it is
-- useful. The flagship, at 116 assets against a batch of 20, is where
-- the batch can actually bind - so that is where the recorder must be
-- shown to fire. Recorded plainly: as of this file, the 0169 recorder
-- has NEVER been observed to fire anywhere.
SELECT public.ottoq_policy_get(NULL, 'decide_seat_batch', 20) AS global_batch,
       (SELECT count(*) FROM public.ottoq_policy_params
         WHERE param_key='decide_seat_batch')                 AS overrides_left,
       (SELECT count(*) FROM public.ottoq_decisions
         WHERE outcome_status='deferred_tick_budget')          AS recorder_rows_anywhere;

-- §8  THE FLAGSHIP PAIRS, AND THE PREDICTION THEY MUST MEET
-- ---------------------------------------------------------------------
-- Fired 10:21 and 10:31 PM CT (03:21 / 03:31 UTC) as cron r9a/r9b:
--   ottoq_determinism_pair(171717, 12, 'busy_day', flagship,
--                          '2026-09-01 02:00:00+00', 900)
--
-- Diff target - round 8 canon, busy_day/171717/12t:
--   h_cmd 04177a2a5d686032aa1c54fcac43f958
--   h_dec 5328154a5f72e9e1bb6b10d177def459
--   h_bkg 0bf42b3cc1b2db78de9e91274d28b3df
--   h_nrg 8dcf8918702a18b9f20022b80dd24513
--
-- 0169 only ADDS a logged row and CONTINUEs past candidates beyond the
-- batch. Before 0169 the `LIMIT 20` dropped those candidates silently;
-- after 0169 they are deferred with a reason and skipped. The SEATING
-- IS UNCHANGED - only the record is richer. So:
--
--   * h_cmd, h_bkg, h_nrg MUST NOT MOVE. A moved h_bkg is a defect to
--     revert, never a canon to re-baseline.
--   * h_dec moves IF AND ONLY IF the recorder fired. If deferred rows
--     are 0, all four canons must reproduce round 8 EXACTLY - and that
--     result would itself be worth having: it would mean the flagship
--     never exceeds 20 qualifying candidates in a tick, and the batch
--     has never bound anywhere.
--
-- Stated before the pairs land, so it can be wrong.
SELECT r.sim_run_id, r.random_seed, r.tick_count,
       r.validation_notes::jsonb->>'outcome'          AS outcome,
       r.validation_notes::jsonb->'arm_b'->>'h_cmd'   AS h_cmd,
       r.validation_notes::jsonb->'arm_b'->>'h_dec'   AS h_dec,
       r.validation_notes::jsonb->'arm_b'->>'h_bkg'   AS h_bkg,
       r.validation_notes::jsonb->'arm_b'->>'h_nrg'   AS h_nrg,
       (SELECT count(*) FROM ottoq_decisions d
         WHERE d.sim_run_id = r.sim_run_id
           AND d.outcome_status = 'deferred_tick_budget') AS recorder_rows
  FROM ottoq_sim_runs r
 WHERE r.run_by = 'cert_harness'
   AND r.started_at >= '2026-09-03 03:20:00+00'
 ORDER BY r.started_at;
