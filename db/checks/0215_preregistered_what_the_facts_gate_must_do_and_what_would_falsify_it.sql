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

-- ===========================================================================
-- RESULTS  --  run 09a1e9d1-c7d2-441e-9fcd-a0420878e258
--              busy_day / seed 424242 / time_scale 60 / flagship depot
--              run_by 'proposer_facts_probe'
--              config_hash 1c4e9d2452e04638faa1ec9d4f0587bd
--              engine_hash 4ee94c53f3cd02a9946cfc70390a7be2
--              2026-09-14 ~04:17-04:26 UTC (11:17-11:26 PM CT, 2026-09-13)
--
-- Same scenario, same seed, same depot and same time_scale as BOTH baseline
-- CP-SAT runs. The only deliberate difference is the arming.
--
-- ---------------------------------------------------------------------------
-- ARMING. One call, and it is the first time proposer_frame_facts = 1 has ever
-- been in force on a run in this database:
--
--   SELECT ottoq_agentic_arm('09a1e9d1-...', '0215_probe');
--   -> {"ok": true, "armed_by": "0215_probe",
--       "arming": {"verdict": "armed", "satisfied": 3, "required": 3,
--                  "missing": [], "run_by": "proposer_facts_probe"},
--       "receipts": [3 x {"ok": true, "clamped": false}]}
--
-- Protocol step 3 asked whether arming still takes more than one call. It does
-- not. 0278 did what it was built for.
--
-- ---------------------------------------------------------------------------
-- A DEVIATION FROM THE PROTOCOL, STATED RATHER THAN BURIED
--
-- Steps 4-6 said: dispatch the bridge, let it fire, read its fire records. That
-- is NOT what was done. The measurement was taken by calling
-- ottoq_build_decision_frame directly and classifying its stalls array in SQL,
-- replicating proposer/forward_proposer.py's stall_is_free / stall_block_reason
-- predicates line for line.
--
-- Why: the frame builder is the thing under test, and reading it directly
-- removes the bridge, the network and the GitHub runner from the measurement
-- entirely. It also yields the BOTH-CONTRACTS comparison from ONE frame build
-- -- the blind verdict and the facts verdict computed over the identical stall
-- rows in the identical instant -- which the bridge cannot produce because it
-- only ever sees one contract per fire.
--
-- The cost is real and is the honest caveat: P4 (does the bridge ABSTAIN rather
-- than propose into a wall) is NOT TESTED by this run. It needs the bridge.
-- P1, P2 and P3 are tested, and P3 is tested more strongly than planned.
--
-- ---------------------------------------------------------------------------
-- P1 -- CONTRACT STAMP.  CONFIRMED.
--
--   frame->'selector' = {"clock": "2026-09-13T01:17:36.140363+00:00",
--                        "facts_version": 1,
--                        "heartbeat_window_s": 90,
--                        "authority": "public.ottoq_l2_external_proposal"}
--
-- Non-null for the first time. Note the clock: it is the SIM clock, not now().
-- 0265's comment predicted that reading the wall clock here would make every
-- flagship charge stall look heartbeat-dead; the stamp shows it reads the run's
-- own clock, so that trap is closed and visible rather than assumed.
--
-- ---------------------------------------------------------------------------
-- P2 -- THE BLINDNESS.  CONFIRMED, AND IT IS NOT A CONSTANT.
--
-- Two samples, 40 charge-capable stalls at the flagship depot in both:
--
--   tick  blind frame   facts frame   THE BLINDNESS   breakdown
--         would offer   offers        (offered by the blind
--                                      frame, refused by the door)
--   ----  -----------   -----------   -------------   ---------------------
--     4        25             0             25        15 occupied (both see)
--                                                     24 reserved  <- facts only
--                                                      1 charger_faulted <- facts only
--     9        20            18              2
--
-- AT TICK 4 THE BLIND FRAME OFFERS THE SOLVER 25 SERVICE POINTS AND EVERY
-- SINGLE ONE IS A POINT THE DOOR WOULD REFUSE. The correct answer at that
-- instant is "nothing is offerable, abstain" -- the facts frame offers zero --
-- and the old contract instead invites 25 proposals that cannot win. That is
-- G49's 23-of-23 reproduced from first principles, in a live world, as a count
-- rather than an argument.
--
-- AND THE SECOND SAMPLE IS THE MORE USEFUL ONE. At tick 9 the blindness is 2 of
-- 20. So the defect is NOT a fixed tax: it is a function of contention, and it
-- is worst exactly when the scheduler matters most. When the site has slack the
-- blind frame is nearly right and nobody would notice; when every point is
-- spoken for it is wrong about all of them. A single headline number here would
-- have been a lie in both directions -- quoting 25 overstates the steady state,
-- quoting 2 understates the failure mode. Quote the shape: at saturation the
-- blind frame's candidate set is entirely false.
--
-- ---------------------------------------------------------------------------
-- P3 -- THE CANDIDATE SET ONLY SHRINKS.  CONFIRMED, ZERO VIOLATIONS.
--
--   stalls offered under facts = 1 that the blind contract would have blocked:
--     tick 4: 0        tick 9: 0
--
-- The subset relation holds exactly. This was predicted to be impossible by
-- construction (stall_is_free tests status FIRST, then consults `offerable`),
-- and asserting it was worth doing precisely because a violation would have
-- collapsed 0278's argument along with this one. It did not violate.
--
-- ---------------------------------------------------------------------------
-- P4 -- NOT TESTED. See the deviation above. Needs a bridge fire.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS DOES NOT SHOW, restated because the numbers above are quotable
--
-- No enactment improved. None was predicted to. The gate stops CP-SAT proposing
-- points it cannot win; it does not win it any. At tick 4 the honest
-- consequence of the fix is that the proposer says NOTHING instead of saying 25
-- wrong things -- and an abstention naming a real scarcity is a better ledger
-- fact than a discarded proposal, but it is not a booking.
--
-- ---------------------------------------------------------------------------
-- A HAZARD FOUND WHILE DOING THIS, WHICH GATES THE OBVIOUS NEXT STEP
--
-- An adversarial review of the agentic-loop designs (2026-09-14) reported, and
-- I then confirmed directly against the catalog, that:
--
--   public.ottoq_capture_decision_snapshot BOTH calls ottoq_build_decision_frame
--   AND writes public.ottoq_decision_snapshots.
--
-- So arming a run changes that run's content_hash -- the content-hashed
-- anti-cheat substrate CLAUDE.md rule 6 names. The same review further reports
-- that content_hash is ALREADY non-deterministic (a passing cert pair, seed
-- 171717 / busy_day, whose arms differ on 44 of 48 ticks, traced to
-- ocpp_sessions.id defaulting to uuid_generate_v4() while appearing both in the
-- hashed payload and in the array's ORDER BY). That second half is REPORTED,
-- NOT YET INDEPENDENTLY CONFIRMED HERE, and is labelled as such.
--
-- CONSEQUENCE, and it is why this run was stopped deliberately rather than left
-- to the governor: proposer_frame_facts = 1 must NOT be armed on a
-- cert_harness run, and should not be left armed on anything that matters,
-- until the content_hash determinism question is settled. This probe was a
-- non-cert run (run_by 'proposer_facts_probe'), no certification was scheduled
-- and no pair was in flight, so the exposure is one archived run -- and
-- ottoq_agentic_arm refuses a cert_harness run outright by construction (0278),
-- which is the guard that made running this safe at all.
--
-- The run was stopped at tick 9 with a stated reason; ottoq_sim_stop_and_reset
-- returned world_reset, depot_reset_to_empty, 78 vehicles unplaced,
-- vehicles_residue_stripped 0, archived true.
