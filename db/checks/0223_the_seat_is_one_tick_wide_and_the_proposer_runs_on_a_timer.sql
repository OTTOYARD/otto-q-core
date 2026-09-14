-- 0223  THE SEAT IS ONE TICK WIDE AND THE PROPOSER RUNS ON A TIMER
--
-- Read-only. 2026-09-14, ~03:20 AM CT (08:20 UTC). Runs 1bd41105 (seed 171717)
-- and 36e5cc68 (seed 848484), both post-0287, both measured in db/checks/0222.
--
-- 0222 reported the answer rate moving from 0.0/0.0 to 27.3/55.6 and named
-- SATURATION as the second, untouched blocker, sized from run 1bd41105: all
-- seven seats that went unanswered there were armed at ticks where 40 of 40
-- charge stalls were busy. Migration 0288 was drafted to guard against exactly
-- that.
--
-- THEN THE SECOND RUN WAS CHECKED, AND SATURATION IS THE MINORITY CAUSE.
--
-- ---------------------------------------------------------------------------
-- THE ALIGNMENT, WHICH IS THE WHOLE FINDING
--
--   run 36e5cc68 (seed 848484, 27 seats, 15 answered)
--     proposer fired at ticks   2, 5, 6, 9, 12, 14, 16, 18, 20
--     seats armed at ticks      4, 6, 8, 10, 12, 14, 16, 18
--     ANSWERED arm ticks           6,    12, 14, 16, 18      <- all fire ticks
--     UNANSWERED arm ticks      4,    8, 10                  <- NONE is a fire tick
--
--   Perfect separation. Every seat armed at a tick the proposer fired on was
--   answered -- 15 of 15, including the one at tick 6 where only ONE of the 40
--   charge stalls was free. Every seat armed at a tick it did not fire on went
--   unanswered -- 12 of 12. Saturation explains none of it.
--
--   run 1bd41105 (seed 171717, 11 seats, 3 answered)
--     proposer fired at ticks   0, 2, 4, 6, 7, 10, 12, 13, 15, 18, 19, 22, 24, 26
--     UNANSWERED arm ticks      2 (1 seat), 4 (6 seats), 16 (1 seat)
--
--   Here ticks 2 and 4 ARE fire ticks, and the fire log records 40 of 40 charge
--   stalls busy at both: the proposer looked and had nothing to offer. That is
--   real saturation. Tick 16 is not a fire tick (fires at 15 and 18).
--
-- SO THE TWENTY UNANSWERED SEATS ACROSS BOTH RUNS SPLIT:
--
--     7   the proposer fired and the depot was full        SATURATION
--    13   the proposer never fired inside the seat's tick  CADENCE
--
-- Cadence is the dominant cause, by roughly two to one.
--
-- ---------------------------------------------------------------------------
-- WHY THE TWO CLOCKS CANNOT AGREE, BY CONSTRUCTION
--
--   ottoq_cuopt_defer_roll binds a seat at exactly ONE tick: armed -> spent at
--   tick T, and STEP 1 releases anything spent before the current tick. So the
--   seat is open for the duration of one decide tick and no longer -- that is
--   the starvation bound, and it is deliberate.
--
--   The proposer loop fires on a WALL-CLOCK interval. The workflow that ran
--   these two runs used --interval-s 18, and the twin advances on its own
--   metronome. Nothing aligns the two. The loop landed on 9 of 20 ticks in one
--   run and 14 of 26 in the other, and which ticks it lands on is a property of
--   two independent timers.
--
--   A one-tick window offered to a process that arrives on an unrelated
--   schedule is answered when the two happen to coincide. On these runs they
--   coincided 15 times and missed 13.
--
-- THIS IS NOT A BUG IN EITHER HALF. The one-tick bound is what stops a vehicle
-- starving behind a proposer that never answers; 0219 and the defer_roll
-- comment are both explicit that this is the point. The timer is what makes the
-- loop a loop. The defect is that nobody ever made the seat and the fire the
-- same event.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS MEANS FOR MIGRATION 0288, AND WHY IT IS HELD
--
-- 0288 adds a guard: do not arm a seat when no charge point is free. It is
-- correct, it is fail-open, and it would have suppressed the 7 saturation
-- seats. It is NOT applied, and the reason is this file:
--
--   1. Its justification shrank. It was drafted believing saturation explained
--      every unanswered seat. It explains 7 of 20.
--   2. Fixing cadence changes WHERE seats are armed and whether they are
--      answered, so the saturation guard's value can only be sized honestly
--      AFTER cadence is fixed. Tuning against a number that is about to move is
--      how a change gets credited with someone else's improvement.
--   3. It touches the DECIDE PATH. That is the one place where "small, safe and
--      probably fine" is not a good enough reason to ship tonight.
--
-- The file is committed as PENDING with its measurements intact. It will be
-- re-argued, not re-derived, once cadence is closed.
--
-- ---------------------------------------------------------------------------
-- AND A WARNING ABOUT THE METRIC ITSELF, which applies to 0288 and to any
-- cadence fix: answered_pct has a denominator made of seats, and BOTH fixes
-- raise it partly by removing seats that could never have been answered. A
-- guard that stops arming a dead seat adds no answers at all and still moves
-- the percentage. The number that means something is the LATENCY: a seat that
-- cannot be answered costs its vehicle one decide tick of delay, and nothing
-- else. Quote the seat count and the tick cost, not the ratio alone.
--
-- FILED AS G58: make the seat and the fire the same event. Three shapes, none
-- costed here:
--   (a) drive the fire from the tick -- the twin calls out, or the loop polls
--       tick_count and fires on change, instead of sleeping a fixed interval;
--   (b) widen the seat to N ticks, with N read off the loop's interval -- but
--       that weakens the starvation bound, which is the one thing the deferral
--       machinery exists to protect;
--   (c) arm the seat only when a fire is known to be imminent, which needs the
--       loop to declare itself and is the same coupling as (a) wearing a hat.
-- (a) is the only one that does not trade the starvation bound away.

-- === THE QUERIES, AS RUN ====================================================

-- Q1. THE ALIGNMENT. Fire ticks against answered and unanswered arm ticks, per
--     run. This is the whole finding in one row per run.
SELECT left(f.sim_run_id::text,8) AS run,
       array_agg(DISTINCT f.tick_seq ORDER BY f.tick_seq) AS fire_ticks,
       (SELECT array_agg(DISTINCT o.armed_at_tick ORDER BY o.armed_at_tick)
          FROM public.ottoq_first_refusal_outcomes o
         WHERE o.sim_run_id = f.sim_run_id AND o.answered) AS answered_arm_ticks,
       (SELECT array_agg(DISTINCT o.armed_at_tick ORDER BY o.armed_at_tick)
          FROM public.ottoq_first_refusal_outcomes o
         WHERE o.sim_run_id = f.sim_run_id AND NOT o.answered) AS unanswered_arm_ticks
  FROM public.ottoq_proposer_fire_log f
 GROUP BY f.sim_run_id
 ORDER BY 1;
-- measured:
--   1bd41105  fires 0,2,4,6,7,10,12,13,15,18,19,22,24,26
--             answered 16,18   unanswered 2,4,16
--   36e5cc68  fires 2,5,6,9,12,14,16,18,20
--             answered 6,12,14,16,18   unanswered 4,8,10
--   c288555a  fires 1,3,6,9,11,14,17,19   (pre-fix)
--             answered (none)  unanswered 4,6,8,12,14,16,20
--
-- NOTE the pre-fix run is the control for the OTHER cause: ticks 6 and 14 are
-- both fire ticks AND arm ticks there, so the proposer did look while seats
-- were held -- and answered none, because of the definitional mismatch 0221
-- and 0287 are about. Three causes, separable by this one query.

-- Q2. Seats per arm tick with the free-stall count the proposer saw, where a
--     fire exists at that tick to read it from.
SELECT left(o.sim_run_id::text,8) AS run, o.armed_at_tick, count(*) AS seats,
       count(*) FILTER (WHERE o.answered) AS answered,
       (f.fire->>'n_charge_stalls')::int - (f.fire->>'n_stalls_busy')::int AS free_charge
  FROM public.ottoq_first_refusal_outcomes o
  LEFT JOIN public.ottoq_proposer_fire_log f
    ON f.sim_run_id = o.sim_run_id AND f.tick_seq = o.armed_at_tick
 WHERE o.sim_run_id IN ('1bd41105-a538-41f9-a0af-6af3f3ec50aa',
                        '36e5cc68-fd4b-435c-9371-b497ae5d71f3')
 GROUP BY 1, o.armed_at_tick, f.fire
 ORDER BY 1, o.armed_at_tick;
-- free_charge NULL means no fire at that tick -- the cadence case. Where it is
-- non-NULL the seats were answered whenever it was above zero, INCLUDING at
-- free_charge = 1.

-- Q3. The one-tick bound, from the engine's own source rather than from memory.
SELECT position('spent_at_tick < p_tick' in p.prosrc) > 0 AS releases_before_this_tick,
       position('state = ''armed''' in p.prosrc) > 0      AS arms_to_spent
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_defer_roll';
-- both true: STEP 1 clears anything spent before the current tick, STEP 2 moves
-- armed -> spent at it. One tick, by construction.
