-- 0290  `0288`/G98's "**12 OF 610 PROPOSALS ENACTED, 2.0%**" IS THE WRONG DENOMINATOR, AND
--       SO WAS THE "96.2% SUPERSEDED BY THE LOCAL DECIDE PATH" GLOSS. THE INFLUENCE FIGURE
--       IS **5.0% OF ENACTED ASSIGNMENTS**; THE REAL DEFECT IS A **51:1 PROPOSAL-TO-
--       ENACTMENT RATIO**. THE SUBSTANCE OF G98 SURVIVES; TWO OF ITS NUMBERS DO NOT.
--
-- Read-only. Same scope as `0288`: twin depot 11111111-1111-1111-1111-111111111111 (rule 8),
-- completed run `c8f678fb-a04a-4c18-a937-9b93673f3fe9` (busy_day, seed 100020, 1,224 ticks).
-- This file exists because `0288`'s numbers are the kind Chase quotes, and two of them are
-- wrong in the direction that **understates our own solver** — which rule 6 forbids exactly as
-- firmly as the flattering direction.
--
-- ══ 1. WHAT THE RUN ACTUALLY ENACTED ═══════════════════════════════════════
--
--   enacted `stall_assignment` decisions           **240**  across **98** vehicles
--
--     deterministic_v1        130   54.2%    77 vehicles   <- the local decide path
--     reservation_honoured     47   19.6%    37
--     greedy_constrained       22    9.2%    21
--     cuopt                    15    6.3%    13
--     **forward_lex            12    5.0%    12**
--     reservation_reopt        12    5.0%    12
--     reservation_reassigned    2    0.8%     2
--
-- **CORRECTION 1 — the denominator.** `0288` §2 reported "12 of 610 proposals enacted, 2.0%"
-- and let that stand as CP-SAT's influence. 610 is the count of PROPOSALS SUBMITTED, and a
-- vehicle can receive at most one enacted assignment however many times it is proposed for.
-- CP-SAT submitted 610 proposals covering 56 vehicles — 10.89 each — into a run that made 240
-- assignments total. **The influence figure is share of ENACTED ASSIGNMENTS: 12 of 240 =
-- 5.0%, covering 12 of 98 vehicles (12%).** 2.0% is a statement about proposal churn, and
-- `0288` presented it as a statement about standing.
--
-- **CORRECTION 2 — "96.2% superseded by the local decide path".** `0288` §2 measured that 538
-- of 559 superseded rows had a decision for the same vehicle at the same or the next tick, and
-- glossed that as the LOCAL PATH beating CP-SAT. The query looked at `ottoq_decisions` with
-- `action_context='stall_assignment'` **without filtering on source**, and that table records
-- every enacted assignment whatever proposed it — including `forward_lex`'s own 12 and
-- `cuopt`'s 15. So 96.2% means *"the vehicle got decided by someone"*, which is nearly
-- tautological for a superseded proposal. **The defensible version of the same claim is the
-- table above: `deterministic_v1` is the single largest winner at 54.2%.** G98's direction was
-- right; its evidence was a tautology wearing a percentage.
--
-- **WHAT SURVIVES UNCHANGED.** CP-SAT is a minority influence on this depot — 5.0% of
-- assignments against the local path's 54.2%, and the reservation-honouring paths take another
-- 25.4% between them. `0288` §1's starvation result is untouched: planning fires went 3.1% ->
-- 64.2% and vehicles planned 14 -> 383 when the wave arrived. And `0288` §3's capacity wall
-- (p95 39.6 min, 11 returns unserved) is a KPI reading that never depended on these ratios.

WITH enacted AS (
  SELECT COALESCE(enacted_action->>'source', l2_engine, '(null)') AS src, entity_id
    FROM public.ottoq_decisions
   WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
     AND action_context = 'stall_assignment' AND outcome_status = 'enacted')
SELECT src,
       count(*) AS enacted,
       round(100.0 * count(*) / (SELECT count(*) FROM enacted), 1) AS pct_of_enacted,
       count(DISTINCT entity_id) AS distinct_vehicles
  FROM enacted GROUP BY 1
UNION ALL
SELECT 'TOTAL', count(*), 100.0, count(DISTINCT entity_id) FROM enacted
 ORDER BY enacted DESC;

-- ══ 2. SO THE REAL DEFECT IS CHURN, AND IT IS 51:1 ═════════════════════════
--
--   forward_lex proposals submitted            **610**
--   distinct vehicles proposed for              **56**   (10.89 proposals each)
--   enacted assignments won                     **12**
--   **proposals per enactment                   51:1**
--
-- That is the number worth acting on, and it is a proposer-side defect rather than a
-- precedence one. The mechanism is already documented in `proposer/forward_proposer.py`:
-- `vehicle_is_held` withholds a vehicle only while it carries a **live pending** `holds_tick`
-- proposal. `ottoq_dispose_external_proposals` runs every tick, so the moment a proposal is
-- superseded or expired the vehicle is admissible again and the next fire re-plans it —
-- unchanged, against a frame that has barely moved. The loop therefore spends OR-Tools time
-- and ledger rows re-deciding vehicles whose plan nothing has invalidated.
--
-- **This also makes every ratio in the run unreadable**, which is how `0288` came to quote
-- 2.0% as influence. A proposer that fires once per vehicle-decision would have submitted
-- roughly 56 rows and won the same 12, and the headline would have read 21% — same behaviour,
-- same enactments, four times the apparent standing. **A churning proposer slanders itself.**
--
-- ══ 3. AND THE HOLD ANALYSIS IN `0288` §6 NEEDS ITS CONCLUSION REVERSED ════
--
-- `0288` §6 found holds covering 2.5% of proposals, called it a wiring gap, and proposed
-- arming holds at the tick boundary for pending proposals. **Reading
-- `ottoq_cuopt_first_refusal_arm` settles it the other way.** Its selection explicitly
-- EXCLUDES any vehicle that already has a pending `holds_tick` proposal:
--
--     -- cuOpt has already answered for this vehicle => let the cursor enact it now
--     AND NOT EXISTS (SELECT 1 FROM public.ottoq_external_proposals p ...
--                      AND p.status = 'pending'
--                      AND p.source IN (SELECT source FROM ottoq_proposer_precedence
--                                        WHERE holds_tick))
--
-- The hold is a **pre-proposal seat reservation** — it buys the proposer time to answer for a
-- vehicle that has no plan yet, and stands down once a plan exists. So 2.5% coverage is the
-- DESIGNED behaviour, not a gap, and `0288` §6's recommended remedy (b) would have inverted
-- the function's stated intent. **Withdrawn.** The hold is working; G98's follow-up is not
-- about holds at all.
--
-- Note also that the arm only ever considers `current_state = 'arrived_at_gate'` with
-- `current_soc < 85`, so vehicles in `staged_awaiting_service` — half the population the CI
-- loop proposes for since `0288` widened it — are outside the hold's remit by construction.

WITH fl AS (
  SELECT entity_id, status FROM public.ottoq_external_proposals
   WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9' AND source = 'forward_lex')
SELECT count(*) AS proposals_submitted,
       count(DISTINCT entity_id) AS distinct_vehicles,
       round(count(*)::numeric / NULLIF(count(DISTINCT entity_id), 0), 2) AS proposals_per_vehicle,
       (SELECT count(*) FROM public.ottoq_decisions
         WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
           AND action_context = 'stall_assignment' AND outcome_status = 'enacted'
           AND COALESCE(enacted_action->>'source', l2_engine) = 'forward_lex') AS enactments_won,
       round(count(*)::numeric / NULLIF((SELECT count(*) FROM public.ottoq_decisions
         WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
           AND action_context = 'stall_assignment' AND outcome_status = 'enacted'
           AND COALESCE(enacted_action->>'source', l2_engine) = 'forward_lex'), 0), 1)
         AS proposals_per_enactment
  FROM fl;

-- ══ 4. WHAT TO ACT ON, IN ORDER ════════════════════════════════════════════
--
--   (1) **Cut the churn** — proposer-side, no tick-path change, no recert. Do not re-plan a
--       vehicle whose proposal was disposed this tick unless the frame moved for it. This is
--       the defect with a clear right answer and no product judgement in it.
--   (2) **THEN ask whether the local path should yield.** `ottoq_proposer_precedence` carries
--       a `greedy_yields` column that `ottoq_l2_optimize_assignments` honours — greedy already
--       stands aside for any `greedy_yields` source, which is why it put only 4 rows on this
--       run. Nothing makes `deterministic_v1` do the same. Making it yield to a pending rank-0
--       proposal is the symmetric completion of a mechanism that already exists, not a new
--       invention — but it is a tick-path change, `forces_recert TRUE`, and it must be
--       measured against a churn-free proposer or the result is uninterpretable for exactly
--       the reason §2 gives.
--
-- **Order matters and this is the whole lesson of this file:** measuring standing while the
-- proposer floods its own denominator produced two wrong numbers in one check file. Fix the
-- instrument, then read it.
