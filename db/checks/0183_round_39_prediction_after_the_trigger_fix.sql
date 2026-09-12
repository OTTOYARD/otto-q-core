-- ===========================================================================
-- 0183  ROUND 39 PREDICTION, COMMITTED BEFORE THE FIRST PAIR FIRES
-- ===========================================================================
-- Written 2026-09-12 ~16:58 UTC (11:58 AM CT). The apply window closed at 16:52:43 UTC:
-- 0256 (20260912165023, forces_recert=TRUE, floor 13:06:22 -> 16:50:23.319089),
-- 0257 (20260912165137, FALSE), 0258 (20260912165243, FALSE). Round 39's first pair
-- fires at 17:40 UTC. This file is committed before that, so it cannot be edited to
-- suit the answer. Fourth time for this discipline (0166, 0170, 0174/0176).
--
-- Round 38 (db/canons/round38.md) confirmed all three of 0176's predictions and settled
-- 0255 as necessary and not sufficient: 96 vehicles took its sim-domain value and the
-- BEFORE trigger re-stamped 20 with the wall clock. 0256 gives that trigger's
-- equal-value fallback a second branch that reads the ottoq.sim_run_id GUC both teardown
-- routes already set, status-independent, and its A7 proved read-only that the branch
-- resolves for a run whose status has already moved.
--
-- ---------------------------------------------------------------------------
-- PREDICTION 1 -- THE TWO 48t PAIRS AGREE WITH EACH OTHER
-- ---------------------------------------------------------------------------
-- 19:23 and 19:55 UTC, both busy_day/171717/48t. Each passes internally (they always
-- have; now() is transaction-stable). NEW: they agree WITH EACH OTHER on all fourteen
-- atoms, and wsec.vehicles is identical between them. This is the whole test of 0256.
--
-- FALSIFIED IF: endst differs in `world` and wsec names `vehicles`, as in rounds 37 and
-- 38. That would mean the GUC branch did not resolve at the natural-completion
-- teardown -- most likely because ottoq.sim_run_id was not set on that route at the
-- moment the trigger fired, or was set to a run whose depot predicate did not match.
-- 0176 §6.1 would then show a wall-clock subset again, and the write must name which.
--
-- ---------------------------------------------------------------------------
-- PREDICTION 2 -- ONE VALUE ON ALL 116 VEHICLES
-- ---------------------------------------------------------------------------
-- After the 19:55 pair, every flagship vehicle holds last_state_change =
-- 2026-09-02 02:00:00+00 (02:00 + 48 x 30 sim-minutes). No wall-clock subset. The
-- 96/20 split of rounds 37-38 collapses to 116/0. Query: db/checks/0176 §6.1.
--
-- FALSIFIED IF: any row carries a 2026-09-12 timestamp. A 96/20 split with the wall
-- value at 19:55:00.xxx means 0256 changed nothing at that route; a different split
-- means it changed something else, and both must be written up before any migration.
--
-- ---------------------------------------------------------------------------
-- PREDICTION 3 -- THE EIGHT OTHER COLUMNS DO NOT MOVE
-- ---------------------------------------------------------------------------
-- Two grid and six flagship 12t/24t columns: 0 of 14 atoms moved from round 38. 0256
-- changes only what a teardown stamps, and their teardown (route A) runs after their
-- atoms are captured. 0257 adds two functions nobody on the tick path calls. 0258 adds a
-- refusal on a branch no cert run takes. None of the three can reach a 6/12/24-tick
-- verdict.
--
-- FALSIFIED IF: any of the eight moves. That would be a regression from one of the
-- three migrations and would need convicting to a specific one before round 40.
--
-- ---------------------------------------------------------------------------
-- WHAT A CLEAN SWEEP MEANS, AND WHAT IT DOES NOT
-- ---------------------------------------------------------------------------
-- All three holding puts every column at STREAK 1 above the 16:50:23 floor -- 0256
-- voided every prior canon by design. It does NOT certify anything. V1_DEMO_PLAN's
-- stopping rule is 7/7 agreeing across two consecutive rounds, so round 40 is the
-- first that can freeze the core. Nothing green is claimed off this round.
-- ===========================================================================

-- The measurement that decides P2, verbatim from 0176 §6.1.
SELECT v.last_state_change, v.current_state, count(*) AS n,
       CASE WHEN v.last_state_change > now() - interval '24 hours'
                 AND v.last_state_change <= now() THEN 'WALL' ELSE 'SIM' END AS clock_domain
  FROM public.vehicles v
 WHERE v.current_depot_id = '11111111-1111-1111-1111-111111111111'::uuid
   AND v.category = 'autonomous'
 GROUP BY 1,2,4
 ORDER BY 1 DESC;
