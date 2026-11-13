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
-- AFTER 0828: read the next full run with the query below and write the result here.

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
