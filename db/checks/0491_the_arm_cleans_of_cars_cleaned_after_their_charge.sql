-- 0491  The arm cleans of cars cleaned after their charge (0827), read on the first run under it, and what 0828 fixes.
--
-- Twin depot 11111111-1111-1111-1111-111111111111. Run 7a08f52a (busy_day, started by an operator 2026-11-13 19:57:22
-- UTC, 3 minutes after the run started to check 0827, which it superseded). 0827 was on from the run's start; its lead
-- was 2 until tick 432 (sim 19:13:48) and 3.5 after; it was turned off at tick 712 (21:01:55 UTC).
--
-- READ 1, at tick 423 (20:35 UTC), visits with a charge done, by whether the car's profile says clean_after_charge:
--     other kinds (Model Y, Cybercab):   38 charged · 37 arm done, 1 arm at work · 0 without the arm
--     the three kinds (I-PACE, Ojai, Zoox): 106 charged · 50 arm done, 5 at work, 1 cancelled · 50 without the arm,
--       of which 13 an owner's immediate turnaround (recorded) and 16 tidied by another performer
--     arm_routine.charge_left_min at the start: 1.8 in 38 visits, 0.0 in 12
-- READ 2, at tick 706 (21:01 UTC), the three kinds, by when the charge ended (fewer visits than read 1: superseded
--   visits of cars that had come back were no longer in the table):
--     lead 2   (charge done before sim 19:14):  51 charged · 29 arm · 2 immediate · 20 missed (7 tidied by another)
--     lead 3.5 (after):                         18 charged · 10 arm · 1 immediate ·  7 missed (2 tidied by another)
--
-- WHAT IT SAYS. 0827 as applied missed about 4 in 10 of the arm cleans it moved, and a wider lead did not change that
-- (7 of 18 against 20 of 51). The other kinds of car were untouched. The two causes are in 0828's header, read from
-- the source: the starter is offered a car for the arm's routine only while it charges, and the estimate of the
-- minutes left does not reach the lead on every charge.
-- WHAT IT DOES NOT SAY. Nothing about the same cars before 0827 on a like run: that run's rows were purged. One run.
--
-- AFTER 0828. Run c86b46e1 (started 21:11:17 UTC to check it; 0827 and 0828 on, lead 3.5), read at tick 491, 21:58 UTC:
--     other kinds:       45 charged · 44 arm · 1 missed (tidied by another)
--     the three kinds:  123 charged · 68 arm (34 started near the end of the charge, 9 after it, 25 by the needed-tidy
--                       branch) · 14 immediate turnarounds · 41 missed (19 tidied by another)
--     cars held on a post more than 10 sim minutes past their tether: 0
--   0828 did not fix it: 41 of 123 against 27 of 69 before. cabin_robot_after_charge was set to 0 at 21:58:23 UTC.
--   WHAT IS STILL NOT MEASURED, and must be before another attempt: the same three kinds with the setting OFF. The
--   "missed" count has no baseline; if these cars also go without the arm with the setting off (a charge closed by a
--   path the starter never sees, a tidy done by a technician first), part of the 41 is not 0827's. The rest of run
--   c86b46e1 (from tick 493, sim 20:16:44) runs with the setting off: read the visits whose charge ends after that.
--
-- THE BASELINE, read at 22:26 UTC after run c86b46e1 ended (741 ticks), the three kinds, by when the charge ended:
--     setting ON  (charge done by sim 20:16:44):  72 charged · 40 arm · 3 immediate · 29 missed (12 tidied by another;
--                                                 none of the 29 carries an arm decision; 12 are immediate-dispatch visits)
--     setting OFF (charge done after sim 20:22):  10 charged · 10 arm ·  0 missed
--   So the misses are 0827's own: with the setting off these cars are cleaned by the arm as the others are. Ten visits
--   is a small sample, and it is the same run and the same day.
--   (The ON count here, 72, is lower than the 123 of the read at tick 491: superseded visits leave the table.)
--
-- WHERE THIS LEAVES IT. cabin_robot_after_charge is OFF at the twin depot. 0827 and 0828 stay applied and change
-- nothing with it off. Before another attempt: write on the visit, each tick, why the starter did not start the arm
-- for a car of these kinds (its state, the estimate, which door it took), so that a miss explains itself; and prefer a
-- design that does not depend on catching a tick, such as starting the arm's atom at the moment the charge session
-- is stopped, in the function that stops it.
--
-- THE CAUSE, read 2026-11-14 00:3x UTC on run c86b46e1 (its rows were still in the tables), and 0830.
--   Of the 124 completed fast-charger sessions of the three kinds while the setting was on, the car's state left
--   `charge_complete_holding` at the SAME sim clock as the session's end in 121, later in 3. (The count is of
--   vehicle.state_changed events whose diff reads current_state from charge_complete_holding, within 30 minutes of the
--   session's ended_at.) One car event by event, 091fa637, session ended sim 16:02:53: charging_dcfc ->
--   charge_complete_holding -> staged_awaiting_service at 16:02:53, tether cleared and stall left at 16:03:22. 0827's
--   second door and 0828's test both need `charge_complete_holding` when the starter is asked, later in the tick, so
--   they almost never applied. And of the 29 misses, 12 were tidied by a technician during the charge: the starter's
--   technician branch took a needed tidy the arm was waiting to do.
--   0830 (applied 2026-11-14 00:52:09 UTC, setting still off) asks the starter inside the function that stops the
--   charge, records the outcome under meta.arm_after_charge, and keeps a needed tidy for the arm.
--   TRIED ON LIVE CARS INSIDE A TRANSACTION THAT WAS ROLLED BACK (run 14d6eda7, sim 14:44:47; setting on inside the
--   transaction only; four charging cars of the three kinds, their visits first stripped of arm work and decision):
--     3 immediate-dispatch visits: why asked, result decided:immediate_turnaround, released by the sweep 2 minutes on
--     1 standard visit:            why asked, result arm_started (interior_tidy to sim 14:50:35), still on its post
--                                  under its tether 2 minutes on
--   Four cars, one moment; not a run. The first run with the setting on is read below when it exists.
--   NOTE FOR A PERSON: under clean-after-charge an owner's immediate turnaround of these three kinds gets no routine
--   arm clean at all (0765's rule: it is not held past its charge for a clean it did not need). With the setting off
--   it is cleaned during its charge, right side only in the twin. A needed tidy is still done.
--
-- THE FIRST RUN UNDER 0830, c8913ea2 (busy_day, started 2026-11-14 01:56:5x UTC; cabin_robot_after_charge set to 1 at
--   the twin depot at 01:56:50 UTC, before the run; lead 3.5). Visits with a charge done:
--     at tick 296 (02:24 UTC):   the three kinds  81 charged ·  63 arm · 18 immediate turnarounds · 0 missed
--                                other kinds       30 charged ·  30 arm
--     at its end, 682 ticks (read 03:10 UTC; run ended 03:02:00 UTC):
--                                the three kinds 135 charged · 107 arm · 28 immediate turnarounds · 0 missed
--                                other kinds       59 charged ·  59 arm
--   meta.arm_after_charge at the end, 141 stops: arm_at_work 81 (the arm had started in the last minutes of the
--   charge), asked -> arm_started 32, asked -> decided:immediate_turnaround 12, decided:immediate_turnaround 16 (decided
--   before the stop). No error recorded. No visit of the three kinds was tidied by another performer.
--   At tick 296 no car stood under a demate tether more than 12 sim minutes past its end.
--   Against 29 missed of 72 with the setting on before 0830 (run c86b46e1). One run; superseded visits had left the
--   table at each read, so the counts are of the visits still in it.
--   The 28 immediate turnarounds had no routine arm clean (0765's rule; see the note above). Put to Chase 2026-11-13
--   evening CT; not changed.
--
-- TO READ THE STOP DOOR ON A RUN:
--   SELECT n.meta->'arm_after_charge'->>'why' why, n.meta->'arm_after_charge'->>'result' result, count(*)
--     FROM ottoq_visit_needs n WHERE n.sim_run_id = :'run' AND n.meta ? 'arm_after_charge' GROUP BY 1, 2;

WITH prof AS MATERIALIZED (
  SELECT v.id, COALESCE(pf.clean_after_charge, false) AS after_charge
    FROM vehicles v LEFT JOIN LATERAL public.ottoq_vehicle_port_profile(v.id) pf ON true
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'),
x AS (
  SELECT p.after_charge,
         EXISTS (SELECT 1 FROM jsonb_array_elements(n.atoms) a WHERE a->>'svc' = 'charge' AND a->>'status' = 'done') AS charged,
         EXISTS (SELECT 1 FROM jsonb_array_elements(n.atoms) a WHERE a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' IN ('done','in_progress')) AS arm,
         EXISTS (SELECT 1 FROM jsonb_array_elements(n.atoms) a WHERE a->>'svc' = 'interior_tidy' AND a->>'status' = 'done' AND COALESCE(a->>'performed_by','') <> 'stall_cabin_robot') AS tidy_other,
         n.meta->'arm_routine'->>'outcome' AS outcome
    FROM ottoq_visit_needs n JOIN prof p ON p.id = n.vehicle_id
   WHERE n.sim_run_id = :'run' AND jsonb_typeof(n.atoms) = 'array')
SELECT after_charge, count(*) FILTER (WHERE charged) AS charged,
       count(*) FILTER (WHERE charged AND arm) AS arm,
       count(*) FILTER (WHERE charged AND NOT arm AND outcome = 'immediate_turnaround') AS immediate,
       count(*) FILTER (WHERE charged AND NOT arm AND outcome IS DISTINCT FROM 'immediate_turnaround') AS missed,
       count(*) FILTER (WHERE charged AND NOT arm AND outcome IS DISTINCT FROM 'immediate_turnaround' AND tidy_other) AS missed_tidied_by_another
  FROM x GROUP BY 1 ORDER BY 1;
