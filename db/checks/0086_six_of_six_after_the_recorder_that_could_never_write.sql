-- =====================================================================
-- 0086  Six of six, after a recorder that could never write
-- =====================================================================
-- Closes round 10. Twelve pairs across six columns, 10:21 PM - 4:20 AM CT.
--
-- §1  THE RESULT: SIX OF SIX GREEN
-- ---------------------------------------------------------------------
-- Every column has 2 pairs, every pair passed with arms equal, and every
-- pass-2 canon reproduced its pass-1 canon exactly. Full table in
-- db/canons/round10.md. Only TWO values in it moved from round 8, both
-- h_dec, both on seed 424242:
--
--   busy_day 424242 12t  h_dec bb7105f3 -> f1224a98   (rec 3)
--   busy_day 424242 24t  h_dec b7cbd48c -> 3adcc2dc   (rec 14)
--
-- On those columns h_cmd, h_bkg and h_nrg ALL HELD. h_bkg holding is the
-- load-bearing result: the CONTINUE 0169 introduced did not change a
-- single assignment. Same seating, richer record - predicted in 0179's
-- header before either pair fired.
SELECT r.random_seed AS seed, r.tick_count AS ticks, r.scenario_code,
       r.validation_notes::jsonb->>'outcome' AS outcome,
       r.validation_notes::jsonb->'arm_b'->>'h_cmd' AS h_cmd,
       r.validation_notes::jsonb->'arm_b'->>'h_dec' AS h_dec,
       r.validation_notes::jsonb->'arm_b'->>'h_bkg' AS h_bkg,
       r.validation_notes::jsonb->'arm_b'->>'h_nrg' AS h_nrg,
       (SELECT count(*) FROM ottoq_decisions d
         WHERE d.sim_run_id=r.sim_run_id AND d.outcome_status='deferred_tick_budget') AS rec
  FROM ottoq_sim_runs r
 WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 03:20:00+00'
 ORDER BY r.scenario_code, r.random_seed, r.tick_count, r.started_at;

-- §2  THE DEFECT THIS ROUND EXISTS TO RECORD
-- ---------------------------------------------------------------------
-- Round 9 certified 0169 a no-op on ONE column and published, in
-- capitals, that decide_seat_batch had never bound anywhere. FALSE.
--
-- 0169 shipped an INSERT writing outcome_status='deferred_tick_budget'
-- without adding that value to ottoq_decisions_outcome_status_check. The
-- INSERT could never succeed - a LATENT CRASH, aborting any run in which
-- the batch binds. Seed 424242 hit it four times overnight, identically,
-- at 12 and at 24 ticks. 0179 added the value.
--
-- db/checks/0085 §2 had named the gap exactly:
--   "0169's new branch has still NEVER EXECUTED, anywhere ... not a
--    tested code path either, and it must not be described as one."
-- The defect lived precisely there.
--
-- A GREEN COLUMN IS EVIDENCE ABOUT WHAT IT EXERCISED, AND NOTHING ELSE.
-- Four green columns did not make the fifth safe, and the summary
-- sentence should never have reached past the seeds that produced it.
-- The correction is appended beneath the original text in
-- db/canons/round9.md - never substituted for it.
SELECT pg_get_constraintdef(c.oid) LIKE '%deferred_tick_budget%' AS value_allowed_now
  FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
 WHERE t.relname='ottoq_decisions' AND c.conname='ottoq_decisions_outcome_status_check';

-- §3  THE RECORDER, FINALLY DOING ITS JOB
-- ---------------------------------------------------------------------
-- The payload lives in context_frame (not proposed_action). At 12 ticks,
-- tick_seq 12, 2026-09-01 08:00:00+00:
--   {"lane":"wash_bay","seat_rank":21,"seat_batch":20,
--    "stall_type":"wash_bay","seat_qualified":23}
-- 23 assets qualified for the wash-bay lane, the batch is 20, ranks
-- 21/22/23 deferred with a reason instead of vanishing. Exactly 3 rows.
-- The engine may say it found nothing, but not that it never looked.
SELECT d.tick_seq, d.context_frame->>'lane' AS lane,
       d.context_frame->>'seat_rank'      AS seat_rank,
       d.context_frame->>'seat_batch'     AS seat_batch,
       d.context_frame->>'seat_qualified' AS seat_qualified
  FROM ottoq_decisions d
  JOIN ottoq_sim_runs r USING (sim_run_id)
 WHERE r.run_by='cert_harness' AND r.random_seed=424242 AND r.tick_count=12
   AND r.started_at >= '2026-09-03 07:56:00+00'
   AND d.outcome_status='deferred_tick_budget'
 ORDER BY d.tick_seq, (d.context_frame->>'seat_rank')::int;

-- §4  WHAT SIX-OF-SIX DOES NOT MEAN
-- ---------------------------------------------------------------------
--   * TWO PAIRS PER COLUMN. normal_day 171717/12t is task #47's column
--     and its proposed bar is EIGHT passes. Two do not meet it. Not
--     closed.
--   * ONE DEPOT. The two-lane cadence is still blocked on 0177 - the
--     cold-start guard counts deployed vehicles across every depot -
--     written and committed, NOT applied.
--   * STABILITY IS ONE ROUND BOUNDARY (8 -> 10) for the four unchanged
--     columns, and the two 424242 canons are BRAND NEW: a first
--     observation, not a stable one. Round 11 is the first that can test
--     whether they reproduce.
--   * The overnight harness is worth keeping: every job unscheduled
--     itself on success and SURVIVED on failure, which is what left the
--     four crashes visible instead of swept up.
SELECT count(*) AS leftover_overnight_jobs
  FROM cron.job WHERE jobname LIKE 'c_p_' OR jobname LIKE 'f_p_' OR jobname LIKE 'r9%';

-- §5  STILL OPEN, EACH ITS OWN forces_recert ROUND
-- ---------------------------------------------------------------------
--   0177  cold-start guard reads every depot (written, NOT applied)
--   twin clock: ottoq_sim_seed_fleet's COALESCE(actual_return_at, NOW())
--   rules: 9 of 29 active rules never evaluate (6 block-severity) - the
--          engine never announces vehicle_state_change,
--          stall_state_change, bess_state_change. The rules layer is
--          wired to DECISIONS, not STATE TRANSITIONS.
SELECT name, forces_recert, left(note, 80) AS note
  FROM public.ottoq_cert_lineage
 WHERE name IN ('the_recorder_wrote_a_status_the_table_refused',
                'the_cold_start_guard_looked_at_every_depot',
                'a_deadline_past_the_end_of_the_run_was_never_missed',
                'an_asset_that_arrived_on_the_last_tick_never_had_a_turn',
                'the_pair_and_the_scenario_must_name_the_same_world')
 ORDER BY classified_at;
