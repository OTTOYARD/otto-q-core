-- 0219  THE RIGHT OF FIRST REFUSAL HOLDS A SEAT FOR A PROPOSER THAT LEFT
--
-- Read-only. Found immediately after 0218's fix landed, by looking at what the
-- first armed run actually did rather than stopping at "the frame is fixed".
--
-- ===========================================================================
-- WHAT 0218 FIXED, AND WHAT IT DID NOT
--
-- 0218 gave the CP-SAT proposer a frame that tells the truth: at tick 4 the
-- armed run reported 40 of 40 charge points unavailable (28 occupied, 12
-- reserved) instead of offering the solver stalls the door had already given
-- away. That is a real fix and it is proven.
--
-- It did not make CP-SAT's proposals get enacted. On run
-- 97769e7e-cd44-4789-b272-f696c60c2a66, the first ever run to propose against
-- a facts-carrying frame:
--
--   source              status       n
--   forward_lex         superseded   8
--   forward_lex         pending      4
--   greedy_constrained  enacted      1
--   greedy_constrained  superseded   1
--
-- Twelve CP-SAT proposals, none enacted. That is NOT a regression and it is
-- not obviously wrong -- ottoq_decide_tick marks a proposal 'enacted' only when
-- the decision it finds for that entity carries enacted_action->>'source' equal
-- to the proposal's own source, and 'superseded' when the entity was decided by
-- anything else. Honest pre-emption, exactly as designed.
--
-- But looking at WHY led somewhere else.

SELECT '1. the holds this run armed, and how many were ever answered' AS section;
WITH d AS (
  SELECT vehicle_id, armed_at_tick
    FROM public.ottoq_cuopt_deferrals
   WHERE sim_run_id = '97769e7e-cd44-4789-b272-f696c60c2a66'
)
SELECT count(*) AS holds_armed,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_external_proposals p
          WHERE p.sim_run_id = '97769e7e-cd44-4789-b272-f696c60c2a66'
            AND p.entity_id  = d.vehicle_id
            AND p.tick_seq BETWEEN d.armed_at_tick AND d.armed_at_tick + 1)) AS answered,
       min(armed_at_tick) AS first_armed_tick,
       max(armed_at_tick) AS last_armed_tick
  FROM d;

-- ===========================================================================
-- THE FINDING
--
--   holds armed                        25
--   answered within the hold window     0
--   held for nothing                   25
--   armed at ticks                   4 .. 16
--   last tick CP-SAT actually proposed    2
--
-- Every hold this run placed was placed AFTER the proposer had stopped
-- producing, and not one of them was answered.
--
-- ===========================================================================
-- WHY, READ OFF ottoq_cuopt_first_refusal_arm
--
-- The arm selects every gate vehicle under 85% SoC that has no charge stall
-- already reserved and no pending proposal from a holds_tick source, and holds
-- each one out of the local decide cursor for one tick. Its guards are good and
-- carefully reasoned -- a Zone A/outside-the-walls check mirroring defer_arm's,
-- a starvation bound (never re-arm 'armed' or 'spent'; never more than
-- cuopt_first_refusal_max_defers times per run), an off switch at cap 0, and a
-- fail-OPEN exception handler so a ledger hiccup can never change assignment.
--
-- THERE IS NO LIVENESS CHECK. Nothing asks whether any proposer is running,
-- has fired recently, or exists at all. The hold is speculative by nature --
-- you cannot know in advance whether the optimizer will answer -- but
-- "speculative" and "blind" are different things, and the engine already has
-- the signal it would need: ottoq_proposer_fire_log.fired_at, one row per fire
-- since 0260.
--
-- AND NOTHING RECORDS THE OUTCOME. cuopt_log_gate writes a 'first_refusal_arm'
-- row with {armed, offered, tick, max_defers} -- what was held. No row anywhere
-- says whether the answer the hold was waiting for ever arrived. Until this
-- file, "held for an answer that never came" was not a countable event.
--
-- ===========================================================================
-- HOW BIG IS IT, HONESTLY
--
-- Bounded, and small per vehicle: cuopt_first_refusal_max_defers is 1, so each
-- vehicle can be held at most once per run, for one decide tick. On a run at
-- time_scale 60 that is one sim minute of delay for 25 vehicles.
--
-- It is also SCOPED AWAY FROM THE CERTIFIED PATH by construction: 0152 set the
-- global tier of cuopt_first_refusal_max_defers to 0, so the arm returns 0
-- before doing anything on any run without an explicit row. The 25 holds here
-- exist precisely BECAUSE 0218's arming wrote the run-scoped 1. Turning the
-- agentic layer on is what made this measurable -- and it is the first time it
-- has ever been on for a run that proposed.
--
-- So this is not an emergency. It is a cost that is paid whenever the agentic
-- layer is armed and the proposer is not actually there, and it has been
-- invisible because the layer had never been armed before today.
--
-- ===========================================================================
-- G54, THE SHAPE OF THE FIX (not built here)
--
--   1. LIVENESS. Do not arm a hold when no proposer has fired for this run
--      within a policy-set staleness window. The signal exists
--      (ottoq_proposer_fire_log.fired_at, per run); the window is a new dial
--      and must be catalogued the way 0282/0283 catalogue one -- range read
--      off its consumer, never chosen.
--   2. OUTCOME. Record, per hold, whether an answer arrived before it cleared.
--      ottoq_cuopt_deferrals already has spent_at_tick and cleared_at_tick; what
--      is missing is a column, or a gate row, distinguishing "cleared because
--      the proposer answered" from "cleared because the tick ended".
--
-- (2) is worth more than (1) and should land first. A hold whose outcome is
-- recorded can be tuned by measurement; a hold whose outcome is invisible can
-- only be argued about. That ordering is this session's recurring lesson --
-- 0281 shipped the instrument before cataloguing a single dial, and 0218's
-- whole finding was possible only because frame_facts_version had been recorded
-- faithfully for days.
