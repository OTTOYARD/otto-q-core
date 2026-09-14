-- 0215  PRE-REGISTERED: WHAT TURNING THE FACTS GATE ON MUST DO, AND WHAT
--       WOULD FALSIFY IT
--
-- Written 2026-09-14 BEFORE the run it describes. Nothing in this file has
-- been measured yet; every number below is a prediction with a stated way to
-- be wrong. That ordering is the point -- deciding what counts after seeing
-- the result is not a test.
--
-- ---------------------------------------------------------------------------
-- THE CLAIM UNDER TEST  (db/checks/0214, db/migrations/0278)
--
-- Every CP-SAT fire in this system's history read a frame built with
-- proposer_frame_facts = 0, so the frame carried none of 0265's selector facts
-- and the bridge's candidate filter fell back to status-and-occupancy -- which a
-- RESERVED BUT EMPTY stall passes. The claim is that CP-SAT was therefore
-- offered service points the door would refuse, and named them.
--
-- ---------------------------------------------------------------------------
-- THE BASELINE, MEASURED 2026-09-14 04:1x UTC, ALL OF IT UNDER facts = 0
--
--   fires                                    4   (2 runs, ticks 1,3 and 10,16)
--   proposals submitted                    329
--     enacted                                6    1.8%
--     superseded                           278   76.6%   (the door's destructive
--                                                          supersede on
--                                                          (run, context, entity))
--     expired                               45   13.7%
--   decisions quoting forward_lex            6   all stall_assignment / enacted
--                                                / assign_stall
--   fires whose fire record carries a
--     frame_facts_version                    0   NULL on all four
--
-- ---------------------------------------------------------------------------
-- WHY THE OBVIOUS COMPARISON IS THE WRONG ONE
--
-- The tempting test is "run it again with the gate on and see if 6-of-329 gets
-- better." That comparison is worthless and must not be published: a new run is
-- a different world -- different arrivals, different SoCs, different charger
-- states, a different hour -- so any movement in an enactment RATE is
-- confounded beyond rescue. A number with a run ID is still meaningless if it
-- answers a question the design cannot answer (db/checks/0146).
--
-- THE SOUND TEST IS WITHIN A SINGLE FIRE, and the instrument already exists.
-- proposer/forward_proposer.py:stall_block_reason returns exactly one reason
-- per non-offered stall, and the vocabulary splits cleanly in two:
--
--   REASONS A BLIND FRAME CAN ALSO SEE -- pre-0265, needs no facts
--     occupied            stalls.current_vehicle_id is set
--     status_<x>          stalls.status is not the free status
--     not_free            (declared unreachable; kept so the vocabulary is total)
--
--   REASONS ONLY THE FACTS FRAME CAN SEE -- a blind frame OFFERS these stalls
--     reserved            a live reservation for another vehicle
--     charger_<state>     station_state is not Available
--     charger_stale       no heartbeat inside the 90 s window
--     no_charger          no ocpp_charger_id at all
--     not_offerable       the residual
--
-- So, in one fire, under the gate ON:
--
--   sum(counts under the facts-only reasons)
--     = the number of charge-capable service points that THIS SAME FIRE, under
--       the old contract, would have handed the solver as free.
--
-- One run, one world, one frame, no cross-run confound. The blindness stops
-- being an argument and becomes a count.
--
-- ---------------------------------------------------------------------------
-- PREDICTIONS. Each is falsifiable and each says what falsifies it.
--
-- P1  CONTRACT STAMP. Every fire record carries fire->>'frame_facts_version'
--     = 1. It has been NULL on all four historical fires.
--     FALSIFIED IF: any fire in the armed run stamps NULL or absent. That would
--     mean the run was not actually armed, or the bridge cannot see the
--     selector block -- either way the rest of this file proves nothing and
--     must not be read as though it did.
--
-- P2  THE BLINDNESS IS NON-ZERO. Summed across the run's fires, the facts-only
--     reasons account for AT LEAST ONE blocked charge-capable stall.
--     FALSIFIED IF: zero. That would mean the flagship depot has no reserved,
--     faulted or silent charge points at all while the run is live, so the gate
--     changes nothing in this world and 0214's finding, while still true about
--     the contract, has no measured consequence HERE. That is a real possible
--     outcome and it gets written down as one, not explained away.
--
-- P3  THE CANDIDATE SET ONLY SHRINKS. For every fire, the set of stalls offered
--     to the solver under facts = 1 is a SUBSET of the set the same frame would
--     have offered under facts = 0. Operationally: no stall may be blocked
--     under the old contract and offered under the new one.
--     FALSIFIED IF: any stall is offered under facts = 1 that a blind frame
--     would have blocked. stall_is_free tests status FIRST and only then
--     consults `offerable`, so this should be impossible by construction --
--     which is exactly why it is worth asserting. A violation means the
--     predicate is not what this file and 0278 both claim it is, and 0278's
--     argument collapses with it.
--
-- P4  ABSTENTION REPLACES A DISCARDED PROPOSAL. Where the facts-only reasons
--     bite hard enough that no point remains, the bridge records status
--     'empty' with a stalls_blocked breakdown naming the scarcity -- rather
--     than submitting proposals that the door then refuses.
--     FALSIFIED IF: a fire submits proposals naming stalls its own
--     stalls_blocked tally counted as blocked. That is self-contradiction and
--     would mean the count and the candidate set are computed from different
--     things.
--
-- NOT PREDICTED, deliberately: that enactments go up. The gate stops CP-SAT
-- PROPOSING points it cannot win; it does not win it any. An abstention naming
-- a real scarcity and a proposal discarded at the door are different ledger
-- facts and only the first is honest, but neither is a booking. Anyone reading
-- an enactment improvement out of this experiment is reading something it was
-- not built to show.
--
-- ---------------------------------------------------------------------------
-- THE PROTOCOL, so the run is reproducible rather than remembered
--
--   1. Confirm nothing in flight: no cert job scheduled, no determinism pair
--      active in pg_stat_activity, no sim run running.
--   2. ottoq_sim_start_run(<scenario>, <sim_clock_start>, <time_scale>,
--                          <seed>, 'proposer_facts_probe')
--   3. public.ottoq_agentic_arm(<run>, '0215_probe')   -- ONE call (0278).
--      Assert the receipt reads verdict 'armed', 3 of 3, missing [].
--      This is the first use of 0278 for its purpose; if arming still takes
--      more than this one call, 0278 failed and that is the finding.
--   4. Dispatch .github/workflows/proposer-loop.yml against the run. The
--      bridge refuses by itself if a pair or a cert arm appears, so the guard
--      does not depend on the operator.
--   5. Let the metronome tick it. Ceiling is 139 sim-minutes
--      (run_governor_max_sim_minutes) and the stall watchdog stops any run
--      that goes 10 real minutes without a tick.
--   6. Run SECTIONS 1-4 below and record the answers verbatim, including the
--      ones that falsify a prediction.
--
-- ---------------------------------------------------------------------------
-- SECTION 1 -- P1. Did every fire read a facts frame?
SELECT f.sim_run_id, f.tick_seq, f.status,
       f.fire->>'frame_facts_version' AS contract,
       f.n_rows, f.n_submitted, f.n_charge_stalls, f.n_stalls_busy
  FROM public.ottoq_proposer_fire_log f
 WHERE f.declared_source IN ('cpsat','forward_lex')
   AND f.sim_run_id = :'run'
 ORDER BY f.fired_at;

-- SECTION 2 -- P2. How big is the blindness, in service points?
-- Splits each fire's stalls_blocked tally by whether a blind frame could have
-- seen the reason. The facts_only column is the headline number.
WITH r AS (
  SELECT f.fire_id, f.tick_seq,
         (jsonb_each_text(COALESCE(f.fire->'stalls_blocked','{}'::jsonb))).*
    FROM public.ottoq_proposer_fire_log f
   WHERE f.declared_source IN ('cpsat','forward_lex')
     AND f.sim_run_id = :'run'
)
SELECT tick_seq,
       sum(value::int) FILTER (
         WHERE key = 'occupied' OR key LIKE 'status\_%' OR key = 'not_free'
       ) AS blind_frame_also_sees,
       sum(value::int) FILTER (
         WHERE key IN ('reserved','charger_stale','no_charger','not_offerable')
            OR key LIKE 'charger\_%'
       ) AS facts_only_the_blindness,
       jsonb_object_agg(key, value) AS full_breakdown
  FROM r GROUP BY tick_seq ORDER BY tick_seq;

-- SECTION 3 -- P3. Nothing was offered that the old contract would have blocked.
-- The old contract blocks on occupancy or a non-free status. A submitted
-- proposal naming such a stall would be the violation. Expect zero rows.
SELECT p.proposal_id, p.entity_id AS vehicle_id,
       (p.proposal->>'stall_id')::uuid AS stall_id,
       s.status, s.current_vehicle_id
  FROM public.ottoq_external_proposals p
  JOIN public.stalls s ON s.id = (p.proposal->>'stall_id')::uuid
 WHERE p.source = 'forward_lex' AND p.sim_run_id = :'run'
   AND (s.current_vehicle_id IS NOT NULL OR s.status <> 'available');

-- SECTION 4 -- P4. Where nothing was offerable, did the bridge abstain rather
-- than propose into a wall?
SELECT f.tick_seq, f.status, f.n_submitted, f.error,
       f.fire->'stalls_blocked' AS blocked
  FROM public.ottoq_proposer_fire_log f
 WHERE f.declared_source IN ('cpsat','forward_lex')
   AND f.sim_run_id = :'run'
   AND f.status IN ('empty','error')
 ORDER BY f.tick_seq;

-- ---------------------------------------------------------------------------
-- RESULTS: (to be appended after the run, verbatim, predictions judged one by
-- one including the ones that failed)
