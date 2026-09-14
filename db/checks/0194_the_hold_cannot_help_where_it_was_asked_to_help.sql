-- ---------------------------------------------------------------------------
-- 0194 — THE RESOURCE-HOLD REVIEW: UNSOUND, AND THE DECISIVE BLOCKER IS THAT THE
-- HOLD CANNOT ACT IN THE ONLY SITUATION IT WAS COMMISSIONED FOR.
--
-- Founder's instruction, 2026-09-13: "the proposer comes in most handy or useful
-- when there is 'tightness' or contention within the depot. So it should be in the
-- loop always." Two designs, a judge, and adversarial reviewers produced a ledger-
-- based one-tick resource hold (would have been migration 0266). Two review lenses
-- returned **unsound**. NOTHING WAS APPLIED. This file records why, and why the
-- conclusion is a redirect rather than a patch list.
-- ---------------------------------------------------------------------------

-- 1. THE DECISIVE BLOCKER. The ARM step only arms a hold on a stall that is free
--    AND carries `reserved_by IS NULL`. Under contention, no such stall exists.
--    Measured during the live D3 run ccf48af1 at tick 3 (db/checks/0186, L-61):
--      31 charge stalls occupied
--       7 free but reserved for another vehicle
--       2 behind a Faulted charger
--       0 offerable
--    So the hold would have armed ZERO times in the run it was designed for -- and
--    the design says so itself, in its own committed prediction. A mechanism whose
--    honest prediction is "no effect on the measured case" is not a fix for that
--    case; it is a fix for some other case nobody has measured yet.
--
--    AND THE IDLE DEPOT IS A TRAP FOR ANYONE TESTING IT. Right now, with the depot
--    reset and no run live, the same query says the opposite:
SELECT count(*) FILTER (WHERE s.stall_type IN ('dcfc','l2'))                        AS charge_stalls,
       count(*) FILTER (WHERE s.stall_type IN ('dcfc','l2')
                          AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL) AS free_and_unreserved,
       count(*) FILTER (WHERE s.stall_type IN ('dcfc','l2') AND s.reserved_by IS NOT NULL) AS reserved
  FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111';
-- MEASURED 2026-09-13 05:58 UTC, depot idle: 40 charge stalls, 40 free AND
-- unreserved, 0 reserved. A hold tested on a fresh depot arms happily and proves
-- nothing. Any acceptance test for this mechanism must run mid-run, under the
-- reservation load busy_day actually produces.

-- 2. THE ONE-TICK TTL IS NOT A STARVATION BOUND. The hold expires at the end of
--    the tick it was armed in -- and is RE-ARMED the next tick from the same
--    still-pending proposal. So the withholding of a resource from other vehicles
--    lasts as long as the proposal lasts, not one tick. The design's central safety
--    claim ("a hold can never strand a vehicle, it lives one tick") is an artefact
--    of describing one iteration of a loop. An arm-count bound per (proposal,
--    resource) is mandatory and was absent.

-- 3. THE TTL COUNTS A CLOCK ONE PRODUCTION PATH NEVER ADVANCES.
SELECT count(*) AS prod_decide_paths
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname = 'ottoq_api_otto_q_decide';
-- MEASURED: 1. public.ottoq_api_otto_q_decide calls ottoq_sim_decide_and_dispatch
-- with no world phase, so ottoq_sim_runs.tick_count does not advance and
-- `expires_after_tick` is never reached. On that path a hold is permanent.

-- 4. AND THE MECHANISM'S OWN INERTNESS EVIDENCE WOULD HAVE TRIPPED THE TRAP I
--    FOUND SIX HOURS EARLIER. The design's only empirical proof of inertness runs
--    ottoq_determinism_pair "on the grid fixture" -- which is a canon column key
--    (grid_smoke/239001/6t), and ottoq_cert_matrix takes the most recent pair as
--    the canon. That is exactly G48 (db/checks/0190): the proof would have
--    rebased one of the only two green columns left. The reviewer caught it from
--    0190 being in the tree.

-- ---------------------------------------------------------------------------
-- THE REDIRECT, WHICH IS THE POINT OF THIS FILE
--
-- Findings 1 and 2 are not patchable in the usual sense. They say the hold is
-- aimed at the wrong joint. The root cause measured in db/checks/0188 is ORDERING:
-- the proposer is asked AFTER the sections of the tick that have already taken the
-- resources (section (4b) books both service bays before section (5) asks the
-- service proposer; the reservation optimizer and greedy claim charge stalls before
-- the stall cursor consults the door). A hold tries to defend a resource that, in
-- the contended case, nothing has left free to defend.
--
-- 0188 listed three fixes. On tonight's evidence the ranking inverts:
--
--   (b) SHOW THE PROPOSER WHAT THE TICK ALREADY DID -- pass the resources claimed
--       earlier this tick into the proposer's context, so it proposes something
--       that can still be had, or abstains honestly. This attacks the ordering
--       directly, needs no new veto over other vehicles' access, and composes with
--       the frame fix (0265) which is already designed and independent: a proposer
--       that can see reservations and charger state stops planning into walls, and
--       a proposer that can also see this tick's claims stops planning into the
--       disposer's own earlier decisions. HALF OF THIS IS ALREADY DRAFTED.
--
--   (c) ASK THE PROPOSER EARLIER -- reorder the tick so the proposer precedes the
--       sections that claim. Correct in principle, highest risk: it changes the
--       disposer's order for every run, moves h_dec/h_bkg, and forces a recert.
--
--   (a) THE HOLD -- keep the design on file with this blocker list. It becomes
--       attractive only if (b) lands and measurement then shows proposals that are
--       heard, feasible, and still lose a race within the tick. That is a measured
--       condition, not a hypothesis.
--
-- WHAT IS UNBLOCKED TONIGHT: 0265, the frame carrying what the selector filters on
-- (`reserved_by`, `reservation_expires_at`, `station_state`, `ocpp_charger_id`, and
-- a per-vehicle reservation). It is independent of the hold, it is the first half
-- of (b), and its own review is still outstanding. Nothing is applied until that
-- review is read and pg_stat_activity is clear.
--
-- WHAT NEEDS A HUMAN: whether "in the loop always, and most useful under
-- contention" is pursued via (b) -- visibility -- or (c) -- reordering. (b) is
-- cheaper, reversible, and does not touch the certified order. (c) is the only one
-- that makes the proposer first in line. The recommendation is (b) now and (c) only
-- if (b) measurably leaves proposals losing races they should win.
-- ---------------------------------------------------------------------------
