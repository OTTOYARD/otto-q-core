-- 0224  THE LOOP NOW WAKES ON THE TICK, AND THE OUTCOME BARELY MOVED
--
-- Read-only. 2026-09-14, ~03:35 AM CT (08:35 UTC). Run 91139ad8 (seed 848484,
-- busy_day, flagship), the first run with the tick-following loop, against
-- 36e5cc68 (same seed, same scenario, same depot, timer-driven loop) and
-- 97769e7e (same seed, before any of tonight's fixes).
--
-- ---------------------------------------------------------------------------
-- THE MECHANISM WORKS, EXACTLY AS SPECIFIED
--
--   fires                                          26
--   distinct fire_trigger values         first, tick_change
--   fires woken by the timeout bound                0
--   max ticks_since_last_fire                       1
--
-- Every wake after the first was a real tick change, the bound never fired, and
-- the loop never skipped a tick. Against 9 fires over 20 ticks on the
-- timer-driven run, that is the alignment G58 asked for, delivered.
--
-- ---------------------------------------------------------------------------
-- AND THE OUTCOME BARELY MOVED. THIS IS THE HONEST PART.
--
--   seed 848484           before 0287   +0287 (timer)   +0287 +tick
--   ------------------------------------------------------------------
--   ticks                          18            20            27
--   fires                           6             9            26
--   fires that submitted            1             6            11
--   seats armed                    25            27            27
--   seats answered                  0            15            17
--   answered_pct                  0.0          55.6          63.0
--   CP-SAT proposals               12            23            48
--   CP-SAT proposals ENACTED        0             8             9
--
-- Read the last row, not the percentage. Tick-following roughly DOUBLED the
-- fire count and the proposal count and enacted ONE more proposal. The jump
-- that mattered on this seed was 0287's -- 0 enacted to 8.
--
-- WORSE, ONE COLUMN WENT BACKWARDS, and it is a metric defect rather than a
-- regression:
--
--   outcome                        +0287 (timer)   +0287 +tick
--   ---------------------------------------------------------
--   answered_enacted                           7             2
--   answered_not_enacted (superseded)          8            16
--   unanswered                                12            10
--
-- Unanswered seats went DOWN, 12 to 10. But the seats whose answering proposal
-- survived to enactment went 7 to 2, because the proposer now RE-PLANS EVERY
-- TICK AND SUPERSEDES ITS OWN PREVIOUS PROPOSAL. The row that released the seat
-- at tick T is superseded at T+1 by the same proposer's fresh plan for the same
-- vehicle. The vehicle is not worse off -- 9 CP-SAT proposals were enacted
-- against 8 -- but the row carrying the credit is not the row that opened the
-- door.
--
-- SO `answered_enacted` MEASURES SOMETHING NOBODY MEANT TO ASK: "did the
-- specific proposal that released this seat survive to enactment", which
-- degrades automatically as the proposer re-plans more often. It cannot tell
-- "superseded by a competitor" from "superseded by its own author one tick
-- later". Filed as G59. `answered` and the CP-SAT enactment count are the two
-- honest columns until that is fixed; quote those.
--
-- ---------------------------------------------------------------------------
-- SO IS TICK-FOLLOWING KEPT? YES, AND ON NARROW GROUNDS.
--
--   FOR: the seat is one tick wide by construction, so waking on the tick is
--        the correct alignment rather than a tuning choice; unanswered seats
--        fell 12 to 10; enacted proposals did not fall.
--   AGAINST: it costs 2.9x the fires and 2.1x the proposals for one extra
--        enacted proposal, on this seed. That is a real cost with no measured
--        benefit beyond correctness of alignment.
--
-- It stays the default because the alignment is right and nothing got worse.
-- It is NOT claimed as an improvement to throughput, because on the one seed
-- measured it was not one. If a later round shows the fire cost mattering, the
-- opt-out (--no-follow-ticks) is already there and this file is the reason to
-- reach for it.
--
-- WHAT WOULD MAKE THIS A REAL COMPARISON, and is not done here: matched tick
-- counts (18 / 20 / 27 are not the same run length), and the A/B pair rig
-- holding the world constant across arms. Everything above is three separate
-- runs on one seed with the world free to diverge.
--
-- ---------------------------------------------------------------------------
-- THE THIRD BLOCKER, NOW THE ONLY ONE LEFT AND UNTOUCHED
--
-- 0223 split the unanswered seats 7 saturation / 13 cadence. Cadence is closed.
-- Of the 10 seats still unanswered here, the pattern at the big arm tick is
-- plain: 10 seats armed at tick 4, and the fire at tick 4 planned exactly ONE
-- vehicle. The loop fired; it simply could not plan for the other nine. That is
-- neither cadence nor a definitional mismatch -- it is how many vehicles the
-- proposer can serve at a tick, which is bounded by free charge points and by
-- its own abstentions. Migration 0288 (HELD) guards the zero-capacity case; the
-- partial-capacity case is new and unsized.

-- === THE QUERIES, AS RUN ====================================================

-- Q1. The mechanism: what woke each fire, and whether a tick was ever skipped.
SELECT f.fire->>'fire_trigger' AS trigger,
       count(*) AS fires,
       max((f.fire->>'ticks_since_last_fire')::int) AS max_tick_gap
  FROM public.ottoq_proposer_fire_log f
 WHERE f.sim_run_id = '91139ad8-441c-4c68-8f03-b00f15a89cdd'
 GROUP BY 1 ORDER BY 2 DESC;
-- measured: first 1, tick_change 25. max_tick_gap 1. No 'timeout', no
-- 'poll_failed', no 'interval'.

-- Q2. The three runs on seed 848484, side by side.
SELECT left(r.sim_run_id::text,8) AS run, r.tick_count AS ticks,
       (SELECT count(*) FROM public.ottoq_proposer_fire_log f
         WHERE f.sim_run_id = r.sim_run_id) AS fires,
       (SELECT count(*) FROM public.ottoq_proposer_fire_log f
         WHERE f.sim_run_id = r.sim_run_id AND f.status = 'submitted') AS fires_submitted,
       count(o.*) AS seats,
       count(*) FILTER (WHERE o.answered) AS answered,
       round(100.0*count(*) FILTER (WHERE o.answered)/NULLIF(count(o.*),0),1) AS answered_pct,
       (SELECT count(*) FROM public.ottoq_external_proposals p
         WHERE p.sim_run_id = r.sim_run_id AND p.source = 'forward_lex') AS cpsat,
       (SELECT count(*) FROM public.ottoq_external_proposals p
         WHERE p.sim_run_id = r.sim_run_id AND p.source = 'forward_lex'
           AND p.status = 'enacted') AS cpsat_enacted
  FROM public.ottoq_sim_runs r
  JOIN public.ottoq_first_refusal_outcomes o ON o.sim_run_id = r.sim_run_id
 WHERE r.run_by = 'proposer_live' AND r.random_seed = 848484
 GROUP BY 1,2,r.sim_run_id ORDER BY min(r.started_at);

-- Q3. G59, the metric that degrades as the proposer works harder.
SELECT left(sim_run_id::text,8) AS run, outcome, answer_status, count(*) AS n
  FROM public.ottoq_first_refusal_outcomes
 WHERE sim_run_id IN ('36e5cc68-fd4b-435c-9371-b497ae5d71f3',
                      '91139ad8-441c-4c68-8f03-b00f15a89cdd')
 GROUP BY 1,2,3 ORDER BY 1,2;
-- measured:
--   36e5cc68  answered_enacted 7   answered_not_enacted 8 (all superseded)   unanswered 12
--   91139ad8  answered_enacted 2   answered_not_enacted 16 (all superseded)  unanswered 10
-- Every not-enacted answer in both runs is 'superseded', never 'expired' or
-- 'rejected' -- which is what points at self-supersession rather than a
-- competitor winning the stall.

-- Q4. The remaining blocker: seats armed against rows the fire could plan.
SELECT o.armed_at_tick, count(*) AS seats,
       count(*) FILTER (WHERE o.answered) AS answered,
       (SELECT f.n_rows FROM public.ottoq_proposer_fire_log f
         WHERE f.sim_run_id = o.sim_run_id AND f.tick_seq = o.armed_at_tick LIMIT 1) AS planned_that_tick
  FROM public.ottoq_first_refusal_outcomes o
 WHERE o.sim_run_id = '91139ad8-441c-4c68-8f03-b00f15a89cdd'
 GROUP BY o.sim_run_id, o.armed_at_tick ORDER BY o.armed_at_tick;
-- measured at tick 4: 10 seats, 1 answered, 1 planned. The loop fired at that
-- tick -- it just could not plan for the other nine.

-- ===========================================================================
-- CORRECTION, SAME SESSION. "A METRIC DEFECT, NOT A REGRESSION" WAS HALF WRONG.
--
-- The section above attributes the answered_enacted collapse to the proposer
-- superseding its own rows, and calls it a bookkeeping artefact because "the
-- vehicle is not worse off -- 9 CP-SAT proposals were enacted against 8". Then
-- the proposal chains were actually followed, and the second half of that
-- sentence does not survive.
--
-- EVERY forward_lex PROPOSAL IN BOTH RUNS, BY STATUS, AND WHETHER THE SAME
-- VEHICLE GOT ANOTHER PROPOSAL AFTERWARDS:
--
--   run       status      n   has successor   successor same source   avg ticks
--   36e5cc68  enacted     8               0                       0           -
--   36e5cc68  expired     2               0                       0           -
--   36e5cc68  superseded 13               0                       0           -
--   91139ad8  enacted     9               5                       5        1.20
--   91139ad8  pending     4               0                       0           -
--   91139ad8  superseded 35              21                      21        1.14
--
-- TWO DIFFERENT WORLDS, and the timer run is the clean one. In 36e5cc68 NOT ONE
-- proposal was followed by another proposal for the same vehicle: its thirteen
-- supersessions were all by something that is not a proposal -- the kernel
-- assigning the vehicle itself. Nothing churned.
--
-- In 91139ad8, 26 of 48 proposals were followed by another proposal for the
-- SAME vehicle from the SAME source, about ONE TICK later. Twenty-one of the
-- thirty-five supersessions are the proposer invalidating its own pending row
-- before the decide path ever acted on it -- and five ENACTED rows were
-- re-proposed too. Four rows are still 'pending', resolved by nothing.
--
-- SO: proposals 23 -> 48, enactments 8 -> 9, and roughly half the extra volume
-- is the proposer overwriting itself. That is not bookkeeping. It is CHURN, and
-- it is a real cost of firing every tick: a pending proposal's window to be
-- enacted is shorter than the interval to the next re-plan, so most plans never
-- get the chance.
--
-- WHAT THIS CHANGES:
--
--   - G59 as filed ("a metric defect, not a regression") is corrected. There IS
--     a metric problem -- answered_enacted moves for reasons unrelated to
--     outcomes -- but underneath it is a behaviour problem, and the behaviour
--     one is the bigger of the two.
--   - 0224's "kept, on narrow grounds" stands, but the grounds are narrower
--     again: unanswered seats still fell 12 to 10 and enactments did not fall,
--     so nothing got worse for a vehicle. What got worse is work done for
--     nothing, which is exactly the cost this file already declined to claim as
--     a benefit.
--   - The fix is NOT to slow the loop back down. It is to stop re-planning a
--     vehicle that already has a live pending proposal from a holds_tick
--     source -- and the proposer cannot currently see that, because the frame
--     does not carry it. Same shape as 0287: a decision the proposer must make
--     about a fact it was never given. Filed G60.
--
-- The measurement below is the one to re-run after any change to the loop's
-- cadence; it is the difference between "the proposer is working harder" and
-- "the proposer is working against itself".

-- Q5. THE CHURN MEASUREMENT. Successor = the next proposal for the same vehicle
--     in the same run. A same-source successor one tick later is the proposer
--     overwriting its own pending plan.
WITH p AS (
  SELECT sim_run_id, entity_id, tick_seq, created_at, source, status,
         lead(tick_seq) OVER w AS next_tick,
         lead(source)   OVER w AS next_source
    FROM public.ottoq_external_proposals
   WHERE action_context = 'stall_assignment' AND entity_type = 'vehicle'
     AND source = 'forward_lex'
  WINDOW w AS (PARTITION BY sim_run_id, entity_id ORDER BY tick_seq NULLS FIRST, created_at)
)
SELECT left(sim_run_id::text,8) AS run, status, count(*) AS n,
       count(*) FILTER (WHERE next_tick IS NOT NULL) AS has_successor,
       count(*) FILTER (WHERE next_source = source) AS successor_same_source,
       round(avg(next_tick - tick_seq), 2) AS avg_ticks_to_successor
  FROM p
 WHERE sim_run_id IN ('36e5cc68-fd4b-435c-9371-b497ae5d71f3',
                      '91139ad8-441c-4c68-8f03-b00f15a89cdd')
 GROUP BY 1, 2 ORDER BY 1, 2;
