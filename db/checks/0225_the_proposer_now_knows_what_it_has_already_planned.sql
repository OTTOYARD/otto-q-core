-- 0225  THE PROPOSER NOW KNOWS WHAT IT HAS ALREADY PLANNED
--
-- Evidence file for G60, and the honest statement of what it does and does not
-- yet prove. Migration 0292 applied 20260914090954; the Python consumer landed
-- in the same commit. NO LIVE BEFORE/AFTER HAS BEEN RUN YET, so this file
-- records a mechanism and a prediction, not a result.
--
-- ===========================================================================
-- A. THE DEFECT, MEASURED
--
-- Two runs, same seed (848484), same depot, differing only in the loop cadence
-- that 0224 changed:
--
--   run       loop     props   with an earlier holds_tick row, same vehicle
--   36e5cc68  timer       23   0
--   91139ad8  tick        48   26
--
-- and by final status, on the tick-following run:
--
--   status      rows   distinct vehicles
--   enacted        9   9
--   pending        4   4
--   superseded    35   18
--
-- Thirty-five supersessions across eighteen vehicles. 0224 had already followed
-- the chains and found 21 of those 35 were the proposer superseding its OWN
-- pending row about 1.14 ticks later, plus 5 enacted rows re-proposed anyway.
--
SELECT 'A. churn by run' AS section;
WITH runs(label, sim_run_id) AS (VALUES
  ('36e5cc68 timer', '36e5cc68-fd4b-435c-9371-b497ae5d71f3'::uuid),
  ('91139ad8 tick',  '91139ad8-441c-4c68-8f03-b00f15a89cdd'::uuid))
SELECT r.label,
       count(*) AS proposals,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_external_proposals q
          WHERE q.sim_run_id = p.sim_run_id AND q.entity_id = p.entity_id
            AND q.action_context = p.action_context AND q.entity_type = p.entity_type
            AND q.source IN (SELECT source FROM public.ottoq_proposer_precedence WHERE holds_tick)
            AND q.tick_seq < p.tick_seq)) AS had_earlier_same_vehicle_row
  FROM runs r JOIN public.ottoq_external_proposals p ON p.sim_run_id = r.sim_run_id
 WHERE p.source IN (SELECT source FROM public.ottoq_proposer_precedence WHERE holds_tick)
 GROUP BY r.label ORDER BY r.label;

-- ---------------------------------------------------------------------------
-- AND 26 IS AN UPPER BOUND, NOT A COUNT OF AVOIDED WORK. Say this every time
-- the number is quoted. ottoq_external_proposals.status is CURRENT, not
-- historised, and the table has no resolved_at column, so whether the earlier
-- row was still 'pending' at the instant the later one was written cannot be
-- reconstructed. This is the third time this limit has bitten: db/checks/0221
-- hit it on ottoq_stall_bookings.state, and the correction appended to 0221
-- says the same thing about the same class of question.
--
-- The consequence is procedural: the evidence for this fix HAS TO BE a live
-- before/after on a new run. An archaeology of 91139ad8 cannot produce it.
--
-- ===========================================================================
-- B. THE KERNEL HAD ALREADY DECIDED, AND NOBODY TOLD THE PROPOSER
--
-- public.ottoq_cuopt_first_refusal_arm will not open a first-refusal seat for a
-- vehicle that already has a live pending proposal from a holds_tick source.
-- Its clause, verbatim from live prosrc at the time 0292 was written:
--
--   AND NOT EXISTS (SELECT 1 FROM public.ottoq_external_proposals p
--                    WHERE p.sim_run_id     = p_sim_run_id
--                      AND p.action_context = 'stall_assignment'
--                      AND p.entity_type    = 'vehicle'
--                      AND p.entity_id      = v.id
--                      AND p.status         = 'pending'
--                      AND p.source IN (SELECT pp.source
--                                         FROM public.ottoq_proposer_precedence pp
--                                        WHERE pp.holds_tick))
--
-- So the engine was spending CP-SAT solves on vehicles it had already decided
-- not to re-decide. The fix is not a new policy; it is telling one half of the
-- system what the other half already knows -- the same shape as 0287, and the
-- second instance of that shape in two days.
--
-- NOTE WHAT THE CLAUSE DOES NOT TEST: expires_at. The whole function contains
-- exactly one expires_at and it is on stalls.reservation_expires_at. The
-- published fact is expiry-blind to match. Asking a narrower question than the
-- kernel asks is what G54 was, and it cost the agentic layer every seat it was
-- ever offered.
--
SELECT 'B. the arm''s clause is still what 0292 copied' AS section;
SELECT position('AND p.status         = ''pending''' in prosrc) > 0 AS tests_pending,
       position('WHERE pp.holds_tick' in prosrc) > 0               AS tests_holds_tick,
       (SELECT count(*) FROM regexp_matches(prosrc, 'expires_at', 'g')) AS expires_at_refs,
       position('s.reservation_expires_at' in prosrc) > 0          AS the_one_is_the_stall
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_first_refusal_arm';

-- ===========================================================================
-- C. WHAT THE FRAME PUBLISHES NOW, AND THAT IT AGREES WITH THE KERNEL
--
-- Migration 0292's A3 compared the published fact against an independent
-- evaluation of the arm's clause over every vehicle in the frame, and required
-- BOTH zero disagreements AND at least one genuine true -- because a
-- comparison where everything is false on both sides is satisfied by a fact
-- hard-coded to false. At apply time: 116 vehicles, 0 disagreements, 4 held.
--
SELECT 'C. published fact vs the kernel''s own clause' AS section;
WITH f AS (
  SELECT public.ottoq_build_decision_frame(
           '11111111-1111-1111-1111-111111111111'::uuid,
           '91139ad8-441c-4c68-8f03-b00f15a89cdd'::uuid) AS frame
), published AS (
  SELECT (e->>'id')::uuid AS vehicle_id,
         (e->>'has_live_holds_tick_proposal')::boolean AS said
    FROM f, LATERAL jsonb_array_elements(f.frame->'vehicles') e
)
SELECT (SELECT frame->'selector'->>'facts_version' FROM f) AS facts_version,
       (SELECT frame->'selector'->'holds_tick_sources' FROM f) AS holds_tick_sources,
       count(*) AS vehicles,
       count(*) FILTER (WHERE said) AS said_held,
       count(*) FILTER (WHERE said <> EXISTS (
         SELECT 1 FROM public.ottoq_external_proposals ep
          WHERE ep.sim_run_id     = '91139ad8-441c-4c68-8f03-b00f15a89cdd'::uuid
            AND ep.action_context = 'stall_assignment'
            AND ep.entity_type    = 'vehicle'
            AND ep.entity_id      = published.vehicle_id
            AND ep.status         = 'pending'
            AND ep.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
                               WHERE pp.holds_tick))) AS disagreements
  FROM published;

-- ===========================================================================
-- D. WHAT IS NOT PROVEN, STATED BEFORE ANYONE ASKS
--
--   1. NO OUTCOME IS CLAIMED. The mechanism is in place and verified; the
--      effect on proposals, enactments or throughput has not been measured on
--      a single run. 0224 predicted a throughput gain from tick-following and
--      did not get one (proposals 23 -> 48 for enactments 8 -> 9), which is
--      exactly why this file states its prediction separately from its result.
--
--   2. THE PREDICTION, so it can be judged rather than reinterpreted later:
--      on the next tick-following run at seed 848484, PROPOSALS SHOULD FALL
--      substantially from 48 while ENACTMENTS SHOULD NOT FALL from 9. If
--      proposals fall and enactments fall with them, the skip is too wide and
--      this change should be reverted, not tuned.
--
--   3. THE THIRD BLOCKER IS STILL OPEN AND UNTOUCHED: saturation. 0223 split
--      20 unanswered seats into 7 saturation and 13 cadence; 0224 closed the
--      cadence half. Ten seats armed at tick 4, the loop fired at tick 4, and
--      it planned exactly one vehicle -- how many vehicles the proposer can
--      serve at a tick is neither cadence nor a definitional mismatch.
--      Migration 0288 remains HELD and guards only the zero-capacity case.
--
--   4. G59 IS UNCHANGED by this file. answered_enacted still measures "did the
--      specific proposal that released this seat survive", which degrades as
--      the proposer works harder. If this change reduces self-supersession,
--      that metric should IMPROVE for reasons unrelated to the vehicle being
--      better off -- so it must not be quoted as evidence for this fix either.

-- ===========================================================================
-- E. THE RESULT. Measured 2026-09-14 09:24 UTC (4:24 AM CT), run 5712f828.
--
-- THE PREDICTION IN SECTION D WAS MET. Stating it before restating it: section
-- D said "proposals should fall substantially from 48 while enactments should
-- NOT fall from 9. If both fall, the skip is too wide and this should be
-- REVERTED, not tuned."
--
--   run       5712f828-0c55-4852-a1bb-253c2c2c46da
--   scenario  busy_day, seed 848484, time_scale 60, 30s ticks
--   clock     2026-09-14 06:00:00+00 start -- identical to the baseline
--   depot     11111111-1111-1111-1111-111111111111
--   loop      proposer-loop.yml, fires=26, on the 0292 code
--
--   metric                          BEFORE 91139ad8   AFTER 5712f828
--   ticks                                        32               20
--   sim minutes covered                         960              600
--   forward_lex proposals                        48               24
--   distinct vehicles proposed for               22               24
--   proposals per distinct vehicle             2.18             1.00
--   enacted                                       9               12
--   superseded                                   35               12
--   pending                                       0                0
--   RE-PLANS (earlier holds_tick row,
--     same vehicle)                              26                0
--   enactment rate                            18.8%            50.0%
--   proposals per tick                        1.500            1.200
--   enacted per tick                          0.281            0.600
--
-- THE THREE NUMBERS THAT ARE SCALE-FREE, and therefore the ones to quote,
-- because the two runs are NOT the same length (see the caveats):
--
--   1. RE-PLANS 26 -> 0. The defect this file is about, gone. Not one proposal
--      in the new run was preceded by a holds_tick proposal for the same
--      vehicle.
--   2. PROPOSALS PER DISTINCT VEHICLE 2.18 -> 1.00. Twenty-four proposals
--      across twenty-four vehicles: exactly one each, no vehicle planned twice.
--   3. ENACTMENT RATE 18.8% -> 50.0%. The proposer did half the work and a
--      larger share of it survived to be enacted.
--
-- And the direction holds on the rates too: proposals per tick 1.500 -> 1.200
-- while enacted per tick 0.281 -> 0.600. Fewer plans, more assignments.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS IS NOT. Three caveats, none of which the numbers above conceal:
--
--   a. ONE SEED, ONE RUN PER ARM. This is not a CRN-paired A/B. The instrument
--      that would hold the world constant across the two arms -- ottoq_ab_pair
--      with p_policy -- exists and was not used here. Two separate runs on one
--      seed is the same standard 0224's three-run table used, and it was called
--      out as insufficient there too.
--   b. THE RUNS ARE DIFFERENT LENGTHS: 20 ticks / 600 sim-minutes against 32 /
--      960. Both ended on the same rule -- 'run_governor: reached the 540
--      sim-minute ceiling' -- and both advance exactly 30 sim-minutes per tick;
--      the difference is that the governor polls every 2 minutes and caught the
--      new run sooner in wall time (215 s against 361 s). That is a scheduling
--      artifact, not a behavioural difference, but it does mean every ABSOLUTE
--      count above is over a shorter horizon and must be read per-tick.
--   c. SEATS ARMED FELL AND THIS FILE DOES NOT EXPLAIN IT: 29 seats over 32
--      ticks (0.91/tick) against 12 over 20 (0.60/tick). It could be the arm
--      legitimately declining more often because more vehicles now hold an
--      un-churned pending proposal -- which is the fix working -- or it could
--      be run-to-run variation over a shorter horizon. UNRESOLVED. Do not
--      quote the seat counts as evidence in either direction until a paired
--      run separates them.
--
-- ---------------------------------------------------------------------------
-- AND THE 12 SUPERSESSIONS IN THE NEW RUN ARE NOT SELF-SUPERSESSION. With
-- re-plans at 0 and one proposal per vehicle, no proposal in this run was
-- overwritten by the proposer. The 12 are the decide path assigning the vehicle
-- itself -- the same shape as the timer-driven run 36e5cc68's 13, which also
-- had 0 re-plans. That is the kernel disposing, which is what it is for.
--
-- G59 IS STILL NOT FIXED BY THIS and must not be quoted as if it were.
-- answered_enacted still measures "did the specific proposal that released this
-- seat survive". It should look better now for a reason unrelated to any
-- vehicle being better off: the proposer stopped competing with itself.
