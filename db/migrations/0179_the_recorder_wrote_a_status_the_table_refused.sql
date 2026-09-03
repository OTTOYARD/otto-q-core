-- =====================================================================
-- 0179  The recorder wrote a status the table refused
-- =====================================================================
-- CONVICTED by the overnight five-column run, 2026-09-03. Four pairs
-- failed identically, all on seed 424242:
--
--   ERROR: new row for relation "ottoq_decisions" violates check
--          constraint "ottoq_decisions_outcome_status_check"
--   Failing row contains (..., stall_assignment, null, vehicle, ...)
--
-- 0169 added an INSERT writing outcome_status = 'deferred_tick_budget'
-- and never added that value to the column's check constraint. The
-- allowed list is nine values and does not include it:
--
--   enacted, overridden_to_default, deferred_noop, errored,
--   noop_no_candidate, shield_disarmed, deferred_stale_entity,
--   context_insufficient, deferred_site_power_cap
--
-- So the recorder's INSERT COULD NEVER SUCCEED. Not dormant
-- instrumentation - a LATENT CRASH. Every run in which the seat batch
-- binds aborts, taking the whole pair (or, outside a cert, the whole
-- tick transaction) with it.
--
-- AND IT CORRECTS A PUBLISHED CLAIM
-- ---------------------------------------------------------------------
-- db/checks/0085, db/canons/round9.md and PR #154 all state:
--
--   "DECIDE_SEAT_BATCH HAS NEVER BOUND ANYWHERE."
--
-- That is FALSE and is corrected here. It was drawn from seeds 171717
-- and 314159, where recorder_rows = 0 honestly. On SEED 424242 the batch
-- DOES bind - at 12 ticks and at 24 ticks - and the moment it bound, the
-- run died. The claim generalised from two seeds to "anywhere"; the
-- third seed refuted it within hours.
--
-- The failing rows name the moment precisely: tick_seq 12,
-- sim_clock 2026-09-01 08:00:00+00, action_context stall_assignment.
--
-- WHY THE CERTIFICATION MISSED IT, EXACTLY
-- ---------------------------------------------------------------------
-- Round 9 certified 0169 a no-op on busy_day/171717/12t with all four
-- canons unmoved, and db/checks/0085 §2 recorded the caveat verbatim:
--
--   "0169's new branch has still NEVER EXECUTED, anywhere. It is
--    instrumentation for a condition that has not yet occurred. Not a
--    defect - but not a tested code path either, and it must not be
--    described as one."
--
-- The defect lived exactly in the gap that caveat named. Writing the
-- caveat down is what made this diagnosable in one query instead of
-- being a mystery; it is not a substitute for having tested the branch.
-- The lesson is the one this codebase keeps paying for: A GREEN COLUMN
-- IS EVIDENCE ABOUT WHAT IT EXERCISED, AND NOTHING ELSE.
--
-- THE FIX. Add the value the engine already writes. Deliberately NOT a
-- revert of 0169: the recorder is the intended behaviour, its INSERT is
-- otherwise well-formed, and the deferral it records is real. What was
-- missing is the one line that lets the table accept it.
--
-- forces_recert = TRUE. This ENABLES an engine code path that was
-- previously aborting, so the 424242 columns will legitimately change:
-- before 0169 the `LIMIT 20` dropped candidates 21+ SILENTLY; after
-- 0169 + this fix they are skipped with a logged deferral row. The
-- seating is identical - only the record is richer. So the prediction
-- for the re-run, published before it fires:
--
--   * h_cmd, h_bkg, h_nrg MUST NOT MOVE on the 424242 columns. A moved
--     h_bkg means the CONTINUE changed which assets were seated, which
--     is a defect to revert, not a canon to re-baseline.
--   * h_dec MUST MOVE on the 424242 columns - this is the first branch
--     of 0169's original prediction finally being exercised.
--   * The 171717 and 314159 columns must not move at all; the batch does
--     not bind there and their canons are already reproduced.
-- =====================================================================

ALTER TABLE public.ottoq_decisions
  DROP CONSTRAINT ottoq_decisions_outcome_status_check;

ALTER TABLE public.ottoq_decisions
  ADD CONSTRAINT ottoq_decisions_outcome_status_check
  CHECK (outcome_status = ANY (ARRAY[
    'enacted'::text,
    'overridden_to_default'::text,
    'deferred_noop'::text,
    'errored'::text,
    'noop_no_candidate'::text,
    'shield_disarmed'::text,
    'deferred_stale_entity'::text,
    'context_insufficient'::text,
    'deferred_site_power_cap'::text,
    /* 0169, admitted by 0179: the seating loop looked at this asset and
       ran out of batch before reaching it. The engine may say it found
       nothing, but not that it never looked. */
    'deferred_tick_budget'::text
  ]));

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_recorder_wrote_a_status_the_table_refused', true,
        '0169 added an INSERT writing outcome_status = deferred_tick_budget without adding that value to ottoq_decisions_outcome_status_check, so the recorder INSERT could never succeed - a latent crash, not dormant instrumentation: every run in which the seat batch binds aborts. Convicted by four identical overnight failures, all on seed 424242, at 12 and 24 ticks. This also CORRECTS the claim published in db/checks/0085, db/canons/round9.md and PR #154 that decide_seat_batch has never bound anywhere: it does bind on seed 424242, and the claim generalised from two seeds. Round 9 certified 0169 a no-op on 171717/12t and recorded the caveat that its branch had never executed; the defect lived exactly in that gap. forces_recert because it enables an engine path that was previously aborting - the 424242 columns will legitimately move h_dec while h_cmd/h_bkg/h_nrg must hold.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
