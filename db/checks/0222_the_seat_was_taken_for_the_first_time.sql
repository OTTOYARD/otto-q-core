-- 0222  THE SEAT WAS TAKEN FOR THE FIRST TIME
--
-- Read-only. 2026-09-14, ~03:00 AM CT (08:00 UTC). Run 1bd41105 (seed 171717,
-- scenario busy_day, flagship depot, 26 ticks, run_by=proposer_live), with the
-- proposer loop dispatched from branch head 63f0aa1 -- migration 0287 applied
-- and vehicle_is_held reading holds_charge_place.
--
-- ---------------------------------------------------------------------------
-- THE RESULT
--
--   run       seed    ticks  holds  answered  answered_pct  enacted
--   97769e7e  848484     18     25         0           0.0        0
--   c288555a  171717     20     19         0           0.0        0
--   1bd41105  171717     26     11         3          27.3        2
--
-- The first two are the pre-fix runs 0219 and 0284 measured. The third is the
-- same seed and scenario as the second, after the fix. `answered_pct` has never
-- been anything but 0.0 in this engine's life; it is 27.3 now, and two of the
-- three answers were ENACTED by the deterministic path.
--
-- THE CHAIN, OBSERVED END TO END ON ONE VEHICLE. At tick 15 the live frame
-- carried 77ecd026 at the gate with no reservation, no booking, and
-- holds_charge_place = false -- so vehicle_is_held returned False and CP-SAT
-- planned for it. At tick 16 the kernel armed a first-refusal seat for that
-- same vehicle, found the pending forward_lex proposal, and released the hold
-- to it. ottoq_first_refusal_outcomes records the row as answered_enacted,
-- answer_source forward_lex, answer_tick 15. The other two answers (0cb1b8c6,
-- 1e6aa7f6) were armed and answered at tick 18 -- the seat used exactly as
-- designed, within its own tick.
--
-- THE SIZE OF THE CHANGE, MEASURED ON THE LIVE FRAME AT TICK 23:
--
--   fleet                                116
--   held under the version-1 predicate     33
--   held under holds_charge_place          17
--   freed by 0287                          16
--   NEWLY held by 0287                      0
--
-- Sixteen of the thirty-three vehicles version 1 called placed were holding
-- something that is not a charge place. The change is one-directional: it never
-- hides a vehicle version 1 would have shown.
--
-- ---------------------------------------------------------------------------
-- CORRECTION TO 0221, AND IT IS A CORRECTION TO THE MECHANISM, NOT THE OUTCOME
--
-- 0221 said the eighteen held vehicles in c288555a were hidden BY THEIR STAGING
-- BOOKING. That was an inference presented as a measurement, and it does not
-- hold up. Two things are wrong with it:
--
--   1. WRONG PREDICATE. 0221 joined bookings with `during @> armed_at_sim` --
--      the booking whose WINDOW covered the arm instant. `has_live_booking`
--      does not test the window at all. It tests only
--      `state IN ('held','active')`. A vehicle whose staging booking covered
--      the instant may equally have held a charge booking for a LATER window,
--      and that would have hidden it just as well.
--
--   2. UNRECONSTRUCTABLE. `ottoq_stall_bookings.state` is current, not
--      historised, so for a finished run there is no way to ask what
--      has_live_booking returned at tick 6. c288555a's mechanism cannot now be
--      established either way.
--
-- What survives 0221 unchanged: the two predicates DID mean different things,
-- the kernel DID arm seats the proposer skipped, and the answer rate WAS zero.
-- What does not survive: the claim that the staging booking specifically is
-- what did it. The tick-23 measurement above is the honest replacement -- it
-- shows the predicates differ for 16 of 116 vehicles right now, measured, with
-- no inference in it.
--
-- ---------------------------------------------------------------------------
-- AND A NEW DEFECT THE RE-MEASUREMENT TURNED UP: THE BOOKING PREDICATE HAS NO
-- TIME BOUND AT ALL (filed G57)
--
-- Sampled mid-run, between ticks 12 and 20 (the run has since completed, so
-- these cannot be re-taken):
--
--   vehicles with >= 1 booking in state held/active        28
--   ...of which some booking's window has not yet ended    13
--   booking rows in state held/active                      36
--   ...whose window ALREADY ENDED, still held/active       21
--   ...of those 21, on a dcfc or l2 stall                   1
--   oldest already-ended window still in a live state   21 min of sim time
--
-- Twenty-one of thirty-six live-state booking rows describe a window that is
-- over. `has_live_booking` -- and therefore `holds_charge_booking`, which 0287
-- inherited the shape from -- counts every one of them. A booking whose slot
-- has finished is not a place; it is a row whose state was never advanced.
--
-- Why it is not urgent and is still a defect: twenty of the twenty-one stale
-- rows sit on non-charge stalls, so 0287's stall-type narrowing already stops
-- them counting. Exactly one stale row was on a charge stall. So the blast
-- radius today is one vehicle -- but the predicate is wrong in a way that will
-- grow silently the moment a charge booking is left unadvanced, and it is the
-- same class of defect as the one this whole pair of files is about: a
-- predicate that answers a question nobody meant to ask.
--
-- THE FIX, SHAPED AND DELIBERATELY NOT BUILT HERE: holds_charge_booking should
-- require `upper(b.during) > g.clk` -- not yet ended, which correctly keeps a
-- FUTURE booking counting as a place, since the decide path has already given
-- that slot away. has_live_booking stays as it is: it is the version-1 key and
-- 0287's whole fallback argument rests on it being byte-identical.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS RUN DOES NOT PROVE, STATED BEFORE ANYONE QUOTES THE 27.3
--
--   - It is ONE run, not a pair. The tick counts differ (26 vs 20), the loop
--     fired at different ticks, and depot congestion varied within the run
--     (charge stalls busy ranged from 1 to 40 of 40 across the 14 fires). Seed
--     and scenario are held constant; nothing else is.
--   - Hold COUNT also moved, 19 -> 11, and this file does not claim to know
--     why. Fewer seats armed is consistent with vehicles being served rather
--     than re-armed, and equally consistent with a different tick alignment.
--   - Three answers is three. The honest sentence is "the right of first
--     refusal has been exercised, and enacted, for the first time" -- not
--     "the hold now works", which wants a pair and a second seed.
--   - SATURATION IS A SECOND, INDEPENDENT BLOCKER and it is untouched. At
--     several fires all 40 charge stalls were busy, so there was no point to
--     offer whatever the frame said. A seat held at a saturated depot cannot
--     be answered by anyone. That is the liveness check 0219 reached for,
--     correctly, with the wrong predicate: not "is a proposer alive" but "is
--     there anything to propose".

-- === THE QUERIES, AS RUN ====================================================

-- Q1. The three-run table above.
SELECT left(r.sim_run_id::text,8) AS run, r.random_seed, r.tick_count,
       count(o.*) AS holds,
       count(*) FILTER (WHERE o.answered) AS answered,
       round(100.0*count(*) FILTER (WHERE o.answered)/NULLIF(count(o.*),0),1) AS answered_pct,
       count(*) FILTER (WHERE o.outcome = 'answered_enacted') AS enacted
  FROM public.ottoq_sim_runs r
  JOIN public.ottoq_first_refusal_outcomes o ON o.sim_run_id = r.sim_run_id
 WHERE r.run_by = 'proposer_live'
 GROUP BY 1,2,3
 ORDER BY min(r.started_at);

-- Q2. Every seat in the post-fix run, and who took it.
SELECT left(vehicle_id::text,8) AS veh, armed_at_tick, spent_at_tick,
       answered, answer_source, answer_status, answer_tick, outcome
  FROM public.ottoq_first_refusal_outcomes
 WHERE sim_run_id = '1bd41105-a538-41f9-a0af-6af3f3ec50aa'
 ORDER BY armed_at_tick, veh;

-- Q3. THE SIZE OF THE CHANGE, on a live frame. Run this against a RUNNING
--     armed run; it answers "how many vehicles would the two predicates
--     disagree about right now", which is the only version of the question
--     that needs no inference.
WITH f AS (SELECT public.ottoq_build_decision_frame(
             '11111111-1111-1111-1111-111111111111'::uuid,
             '1bd41105-a538-41f9-a0af-6af3f3ec50aa'::uuid) AS j),
v AS (SELECT e FROM f, jsonb_array_elements(f.j->'vehicles') e)
SELECT count(*) AS fleet,
       count(*) FILTER (WHERE (e->>'reserved_stall_id') IS NOT NULL
                           OR (e->>'has_live_booking')::bool)            AS v1_held,
       count(*) FILTER (WHERE (e->>'holds_charge_place')::bool)          AS v2_held,
       count(*) FILTER (WHERE ((e->>'reserved_stall_id') IS NOT NULL
                            OR (e->>'has_live_booking')::bool)
                          AND NOT (e->>'holds_charge_place')::bool)      AS freed_by_0287,
       count(*) FILTER (WHERE NOT ((e->>'reserved_stall_id') IS NOT NULL
                                OR (e->>'has_live_booking')::bool)
                          AND (e->>'holds_charge_place')::bool)          AS newly_held_by_0287
  FROM v;
-- measured at tick 23: fleet 116, v1_held 33, v2_held 17, freed 16, newly 0.

-- Q4. G57, the missing time bound. Run against a RUNNING run.
WITH r AS (SELECT sim_run_id, sim_clock_current AS clk FROM public.ottoq_sim_runs
            WHERE sim_run_id = '1bd41105-a538-41f9-a0af-6af3f3ec50aa'),
b AS (SELECT b.vehicle_id, s.stall_type::text AS typ, b.during, r.clk
        FROM public.ottoq_stall_bookings b
        JOIN public.stalls s ON s.id = b.stall_id, r
       WHERE b.sim_run_id = r.sim_run_id AND b.state IN ('held','active'))
SELECT count(DISTINCT vehicle_id)                                          AS veh_live_state,
       count(DISTINCT vehicle_id) FILTER (WHERE upper(during) > clk)       AS veh_not_yet_ended,
       count(*)                                                            AS rows_live_state,
       count(*) FILTER (WHERE upper(during) <= clk)                        AS rows_already_ended,
       count(*) FILTER (WHERE upper(during) <= clk
                          AND typ IN ('dcfc','l2'))                        AS stale_charge_rows,
       max(clk - upper(during)) FILTER (WHERE upper(during) <= clk)        AS oldest_stale
  FROM b;
-- measured mid-run: 28 vehicles / 13 not-yet-ended; 36 rows / 21 already ended;
-- 1 of those 21 on a charge stall; oldest stale window ended 21 sim-minutes ago.

-- Q5. Congestion, the second blocker this file does not fix.
SELECT f.tick_seq, f.status, f.n_in_serviceable_state AS serviceable,
       (f.fire->>'n_vehicles_held')::int AS held,
       (f.fire->>'n_stalls_busy')::int AS charge_stalls_busy,
       (f.fire->>'n_charge_stalls')::int AS charge_stalls,
       f.n_rows, (f.fire->>'frame_facts_version')::int AS facts_version
  FROM public.ottoq_proposer_fire_log f
 WHERE f.sim_run_id = '1bd41105-a538-41f9-a0af-6af3f3ec50aa'
 ORDER BY f.tick_seq;
-- 14 fires, every one at facts_version 2 and armed. charge_stalls_busy spans
-- 1..40 of 40; the fires that produced nothing are the saturated ones.
