-- 0080  The engine parked them repeatedly and never promoted them.
--       Diagnostic only, no change applied. Read 6:55 PM CT, 2026-09-02.
--
-- 0079 §4 reported 32 unserved returns across 12 of 25 runs and called the cause
-- unidentified. This is that diagnosis. It corrects the number and replaces the
-- hypothesis I had been carrying since 0076 §13.
--
--
-- §1  The number is 16, not 32
-- -----------------------------
-- "Unserved" means: an asset returned to the depot and no service operation went
-- ACTIVE for it afterwards. Split by whether the asset had any time at all:
--
--   32  unserved returns across the last 25 runs
--   16  arrived on the run's FINAL TICK - the horizon ended, nothing was owed
--   16  had time remaining and were still unserved   <- the real number
--    0  had no booking of any kind
--
-- The 16 horizon cases are not a defect. A 12-tick run ends at 08:00 and an
-- asset arriving at 08:00 has no tick left to be served in. Counting them was my
-- error, not the engine's.
--
-- THIRD TIME TODAY a number of mine halved under scrutiny: readiness 32% -> 17%,
-- "58% of needy assets" -> 24 sessions, and now 32 -> 16. 0076 §12a already named
-- the pattern - "I reach for the alarming denominator first" - and naming it did
-- not stop it. The rule that would have: before reporting a count, subtract the
-- cases where the engine was never given the chance to act.
--
--
-- §2  The engine never ignored them
-- ----------------------------------
-- Every one of the 16 held a booking. Not one was overlooked:
--
--   16 of 16  had at least one booking released with reason 'window_elapsed'
--   avg 2.8   such expiries per asset, max 5
--   purposes  temp_hold, perimeter_hold
--
-- Those are HOLDING bookings - staging and the perimeter queue - not service
-- seats. Traced on one asset (54ec9dcb, run seq 1763): five temp_holds at 02:30,
-- 03:00, 03:30, 04:00, 04:30, each released 'window_elapsed', while its actual
-- work (inspect, interior_tidy) sat planned at 08:00, the run's last instant, and
-- was skipped.
--
-- So the mechanism is NOT "nothing re-enters the asset into assignment." The
-- asset is re-entered every tick, parked, and the park expires - 2.8 times on
-- average - without ever converting into a service seat.
--
--   THE ENGINE PARKS THEM AND NEVER PROMOTES THEM.
--
-- That is the opposite failure from the one I was hunting. 0076 §13's hypothesis
-- was that assets fall out of consideration; the recording work drafted in 0169
-- was aimed at proving it. The evidence says consideration is fine and PROMOTION
-- is what fails. 0169 is still worth applying - it makes a different blind spot
-- visible - but it was never going to find this, and this check corrects the
-- expectation that it would.
--
-- This also matches Chase's own framing of the fault case (2026-09-02): "park
-- temporarily in staging area until ready." The parking works. Getting back out
-- of parking is what does not.
--
--
-- §3  What is NOT yet established
-- --------------------------------
--  a. WHY the work legs are planned at the run's final instant (08:00 on a
--     12-tick run) rather than when the asset arrived. That is the next
--     question, and it decides whether this is a planner defect or correct
--     deferral of low-priority work behind higher-priority assets.
--  b. Whether these 16 assets were low-priority by design. Their needs on the
--     traced asset were inspect and interior_tidy - real work, but not charge.
--     If the ranking deliberately starves non-charge work while charge demand
--     exists, that is a POLICY worth exposing (like 0159 did for the
--     wait-vs-slower-charger choice), not a bug to patch.
--  c. Whether the hold window is simply too short to survive a busy tick. Five
--     expiries on one asset suggests the hold is re-granted faithfully; the
--     question is what it is waiting for.
--
-- Do not build a fix before (a) and (b) are answered. The last hypothesis
-- survived from 0076 §13 to 0079 §4 without evidence and was wrong.
--
--
-- §4  Queries
-- ------------

-- 4.1 the split that corrects 32 to 16
WITH runs AS (SELECT sim_run_id, sim_run_seq, sim_clock_current, tick_interval_seconds
                FROM ottoq_sim_runs ORDER BY sim_run_seq DESC LIMIT 25),
u AS (SELECT r.sim_run_seq, r.sim_clock_current, r.tick_interval_seconds,
             d.vehicle_id, d.actual_return_at, d.sim_run_id
        FROM ottoq_vehicle_dispatches d JOIN runs r USING (sim_run_id)
       WHERE d.actual_return_at IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM ottoq_itinerary_legs l
                          WHERE l.sim_run_id=d.sim_run_id AND l.vehicle_id=d.vehicle_id
                            AND l.leg_type NOT IN ('taxi','stage')
                            AND l.actual_start_sim IS NOT NULL
                            AND l.actual_start_sim >= d.actual_return_at))
SELECT count(*) AS unserved_total,
       count(*) FILTER (WHERE actual_return_at >= sim_clock_current - (tick_interval_seconds||' seconds')::interval) AS arrived_on_final_tick,
       count(*) FILTER (WHERE actual_return_at <  sim_clock_current - (tick_interval_seconds||' seconds')::interval) AS real_unserved
  FROM u;

-- 4.2 every real-unserved asset was held, and how often
--     (same CTE as 4.1 with the final-tick cases excluded, then:)
--   SELECT count(*) AS real_unserved, count(*) FILTER (WHERE h.holds>0) AS had_holds,
--          round(avg(h.holds),1) AS avg_holds, max(h.holds) AS max_holds,
--          string_agg(DISTINCT h.purposes,' | ') AS hold_purposes
--     FROM u CROSS JOIN LATERAL (
--       SELECT count(*) FILTER (WHERE b.release_reason='window_elapsed') AS holds,
--              string_agg(DISTINCT b.purpose,',') AS purposes
--         FROM ottoq_stall_bookings b
--        WHERE b.sim_run_id=u.sim_run_id AND b.vehicle_id=u.vehicle_id) h;
--   -> 16, 16, 2.8, 5, 'perimeter_hold | temp_hold'

-- 4.3 the trace: holds versus work, one asset (the shape §2 rests on)
SELECT 'booking' AS kind, b.purpose AS what, b.state, COALESCE(b.release_reason,'-') AS why,
       to_char(lower(b.during) AT TIME ZONE 'UTC','MM-DD HH24:MI') AS at_utc
  FROM ottoq_stall_bookings b
 WHERE b.sim_run_id=(SELECT sim_run_id FROM ottoq_sim_runs WHERE sim_run_seq=1763)
   AND b.vehicle_id='54ec9dcb-76c1-4a7a-84e5-43ea4b3a7c8a'
UNION ALL
SELECT 'leg', l.leg_type, l.status, '-',
       to_char(l.planned_start_sim AT TIME ZONE 'UTC','MM-DD HH24:MI')
  FROM ottoq_itinerary_legs l
 WHERE l.sim_run_id=(SELECT sim_run_id FROM ottoq_sim_runs WHERE sim_run_seq=1763)
   AND l.vehicle_id='54ec9dcb-76c1-4a7a-84e5-43ea4b3a7c8a'
 ORDER BY 5, 1;

-- 4.4 CAUTION recorded: vehicles.current_state is LIVE SHARED STATE, not
--     run-scoped. Reading it to characterise a past run reports the last run to
--     touch the fleet. It was consulted here first and showed all four assets
--     'offline', which would have ended this diagnosis with the wrong answer.
--     Same defect class as the query corrected in 0078 §5.3. Run-scoped
--     evidence only: ottoq_itinerary_legs, ottoq_stall_bookings,
--     ottoq_visit_needs, ottoq_decisions, ottoq_events.
