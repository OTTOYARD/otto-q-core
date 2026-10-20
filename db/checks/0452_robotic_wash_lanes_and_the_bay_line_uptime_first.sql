-- 0452  **Robotic wash lanes and the bay line uptime first: what the twin's bays did, and how the line was ordered.**
--        Chase, 2026-10-17 evening CT: the wash bays can be assumed robotic (a pull-through exterior wash; for the
--        interior, an attendant who opens the doors and a robot arm). An urgent issue brings a car home at once and is
--        fitted in around the cars that can rejoin service right away. Measured for 0746 and 0747.
--        -> G460, G461 (and §5, its open question about the charge line). §6 and §7 read the arms of the night of
--        2026-10-18/19 (robowash_normal, uptimefirst_busy), on 2026-10-19 between 6:11 and 6:44 AM CT.
--        Read-only, against gxdrcyphqjzjsuhxuqtg, 2026-10-17 between 7:10 and 7:37 PM CT (00:10 and 00:37 UTC Oct 18,
--        bounded by clock reads). The runs: the 11 completed runs at the twin depot since 2026-10-16 with 144 or more ticks
--        (6 normal days, 5 busy days); every number below names the query that reproduces it.
--
-- ══ §1 THE TWIN'S BAYS WORK FOR AS LONG AS THE BOOKING HAS LEFT (G460; reproduce: (1), (2)) ═══════════════════════════
--
--   Each seat's timer, from its own state-change event (the timer written as the car entered the bay, less the minute
--   it entered):
--                          seats   timer: mean / p10 / p50 / p90   end = booking end   seated after booking start
--     normal, wash bay      164         4.0 /  4.0 /  4.0 /  4.0         154                 4.9 min
--     normal, detail        220        19.1 / 16.8 / 20.0 / 20.0         197                 5.5
--     normal, service bay    85        40.8 / 35.0 / 39.0 / 50.0          81                 6.0
--     busy,   wash bay      276         4.1 /  4.0 /  4.0 /  5.0         260                 4.8
--     busy,   detail        266        19.8 / 20.0 / 20.0 / 20.0         248                 4.9
--     busy,   service bay   260        35.9 / 26.0 / 35.0 / 46.7         178                 4.3
--   The decide books a walk-in for 9 minutes (a wash) or 25 (a detail) at one tick; the twin seats the car on the next
--   tick, five sim-minutes later, and pins its timer to the booking's end (ottoq.ottoq_activate_due_bay_reservations,
--   twin.ottoq_sim_confirm_commands). The crews' own times, 9 and 25 minutes drawn 0.7-1.3x, apply to none of these seats.
--   One car read in full (run 7fe98840, car 1b9b6ea1): wash booked [11:55, 12:04) sim time at 11:55, seated 12:00, out at
--   12:04, 4 minutes.
--
-- ══ §2 THE BAY LINE IS URGENCY FIRST, AND ITS LAST TWO KEYS CARRY LITTLE (G461; reproduce: (3), (4)) ══════════════════
--
--   Decide section (4b)'s bay decisions (task_start resolved to stall_assignment, source needs_card):
--                  decisions   urgency critical   past the car's deploy time (median)   no deploy time   open_must_do_min = 0
--     busy days      3,875          2,090                2,638 (-431 min)                    901                3,554
--     normal days    1,149            264                  363 (+149 min)                    104                1,146
--   Passed over (noop_no_candidate) at the service bays: busy days mechanical_pm 1,411, fault_repair 826,
--   sensor_calibration 378; normal days 30, 67 and 18 (query (3), by need, urgency and outcome).
--
-- ══ §3 THE RECALL ALREADY BRINGS AN URGENT CAR HOME AT ONCE (reproduce: (5)) ═══════════════════════════════════════════
--
--   Both recall implementations return true, not deferrable, for a safety-critical fault (rung 1, lead 0 ticks), a major
--   fault (rung 2, lead 1), a low battery near reserve (rung 3, lead 1), a rider-flagged cleaning (rung 4, lead 0) and
--   stale comms (rung 8, lead 0). Chase's "focus on just getting the vehicle back to depot" is the recall as it stands.
--
-- ══ §4 THE DRY RUNS (rolled back by their own final RAISE; reproduce: the files) ════════════════════════════════════════
--
--   0746 alone, 2026-10-17 between 7:20 and 7:37 PM CT: every premise and check passed; the executable part read back by
--   md5(current_query()) equal to the file's (62450e75, priority 15 before the edit to 14); the gate 2 at the default and
--   NULL at 2; a wash for car 00cc3d0a on run 7fe98840 at 1 hour 1 minute in: 11.007 minutes at 1, 5.557 at 2 (the same
--   draw, 1.223); post-images: the service flow d7f2ee27, the decide b90378b7, the charge-off wash admission 7b56721a.
--   0746 and 0747 together, the same window: both executable parts read back equal to the files (0746 2627e8ba, 0747
--   796c5dfb); (4b)'s patched cursor planned (EXPLAIN) and run on run 7fe98840 with both dials on (0 candidates: no car
--   is staged at that run's end); the key over the depot's 120 cars at the run's end: 0 emergencies, 4 past the floor;
--   post-images: the decide fc843b9e, the key ec6a2dc9.
--   0747's key was then extended to the twin's two hazard classes (an HV battery thermal event or a charge-system fault
--   is an emergency; its other in-depot faults are fitted in). The new key, created as a temporary function and run with
--   the dial on busy run 96616822 at its end (rolled back), keyed the depot's 120 cars in 67 ms. The executable part is
--   now md5 298b9337 and the key's body 8d395ffe; the decide's patch, and so its post-image fc843b9e, are unchanged.
--   APPLIED 2026-10-18: 0746 at 6:14 AM CT (ledger 20261018111429) and 0747 at 6:15 (20261018111537), with the
--   post-images above, then checked end to end on live and rolled back (their APPLIED notes). 0746, a wash and a detail
--   seated 3 minutes before the clock: at wash_lane_physics 0 neither timer moved (9.000 and 25.000 minutes, as booked);
--   at 1 they were retimed from the seat to 10.000 and 22.093 minutes (9 and 25 times the deal), their bay needs moved
--   with them and the plan's ends kept, the lane's gate reading two supervisors; at 2, 5.278 and 15.221 minutes and the
--   gate NULL. 0747, three staged cars with open visits: at bay_order_uptime_first 0 the order was today's (the PM car,
--   the severity-2 repair, the thermal car, every key NULL); at 1 the thermal car came first, then the PM car (24 minutes
--   of must-do work), then the repair (101). One finding on the way, not a defect of either: the service flow,
--   twin.ottoq_sim_advance_service_flow, has no search_path of its own, so called outside the world tick (which sets
--   twin, ottoq, public, extensions) it cannot find twin.ottoq_sim_lane_capacity; the check set the tick's path.
--   Their arms are robowash_normal (four cells) and uptimefirst_busy (two), in tick, first in the window that opens at
--   11:00 PM CT on 2026-10-18 (db/checks/0451 §15).
--
-- ══ §5 THE CHARGE LINE SEATS A CAR HELD BY A REPAIR AHEAD OF CARS THAT COULD EARN (G461's open question; reproduce: (6)) ══
--
--   Read 2026-10-17 between 8:24 and 8:32 PM CT, on the same 11 runs. Each charge seat the decide enacted
--   (stall_assignment, assign_stall, a fast charger or an L2), with the seated car's visit open at that clock carrying a
--   must-do fault repair not yet done, and, at the same clock, any other car waiting for a charger (arrived_at_gate or
--   staged_awaiting_service, its state read from its own state-change events) whose visit needs a charge for that kind
--   of charger and holds no open repair:
--                     charge seats   to a car held by a repair   ...while a clean car for that kind waited
--     busy,   fast        1,120                23                              18
--     busy,   L2            682                29                              19
--     normal, fast        1,370                 5                               4
--     normal, L2            215                 3                               1
--   So on the busy days 37 of 1,802 seats (2.1%) went to a car whose repair would hold it after its charge while a car
--   that could have gone back to earning waited, and on the normal days 5 of 1,585 (0.3%). It is an upper bound: whether
--   the waiting car's inlet, cabinet or own plan allowed that charger is not read. These repairs are the arrival-known
--   faults of the need profile, which carry no fault class. A car with an in-depot fault is a different case and is
--   already handled: since 0557 the emission gate refuses its charge until its repair is done, and 0558 releases a charger
--   held for it, so an HV battery thermal event or a charge-system fault is not put on a charger.
--   Not built. 0743-0747 change who reaches a charger and when (the bay calendar, the holds, the plan, the bay times and
--   the bay order), and their arms have not run; a third change to the order before they are read would confound all
--   three. The candidate, for after those arms: the charge line orders a car by whether its charge is on its own critical
--   path. A car whose repair or bay work will hold it after the charge anyway can wait for a charger without being
--   ready any later; a car that leaves when its charge ends cannot.
--   RE-READ 2026-10-18 at 7:02 AM CT (query (6) on the ten full-day arms landed since: 89, 90 and 93-100; the two
--   72-tick mornings 91 and 92 are outside its filter). On the nine normal days 2 of 2,191 charge seats (0.09%) went to a
--   car held by a repair while a clean car for that kind waited (one each on arms 89 and 100), 8 to a repair-held car at
--   all; on the busy day (arm 97) 6 of 268 (2.2%), 7 to a repair-held car, the same share as §5's busy days. Neither 0746
--   nor 0747 could have moved it: no arm so far carries their dials (they were applied at 6:14 and 6:15 AM CT, after
--   the window), and their arms run in the window that opens at 11:00 PM CT on 2026-10-18. Re-run (6) on them.
--   RE-READ 2026-10-19 at 6:30 AM CT (query (6) on the eleven arms landed overnight, 101-111). Normal days: none of the
--   1,400 charge seats on robowash's four arms and the held site in tick (101-104, 107) went to a car held by a repair
--   while a clean car for that kind waited, and 4 of 972 on seeds23's seed-2 arms (one each on 108-111). Busy days: 4
--   of 315 on arm 105 (1.3%, 7 seats to a repair-held car) and 3 of 293 on arm 106 (1.0%, 6), against arm 97's 6 of 268
--   (2.2%) and the earlier busy days' 37 of 1,802 (2.1%). Robotic lanes (0746) and uptime first (0747) about halved it on
--   the busy day, on one seed, and it was already near zero on the normal day. The critical-path charge order stays a
--   candidate and is not built: it would move about one seat in a hundred on the day it matters.
--
-- ══ §6 ROBOTIC LANES AT FORTY POSTS, READ (G460; reproduce: db/checks/0451 (21), (22), (26), (29), (51), (55), (56)) ══
--
--   Read 2026-10-19 between 6:11 and 6:38 AM CT, from robowash_normal's four arms (101-104) and uptimefirst_busy's two
--   (105, 106), all on seed 1, forty robotic posts, in tick, with 0757's bay_release_reads_the_work. Arm 95 is the
--   control's cell without 0757's dial, read the night before. The normal day:
--                                          95          101         102           103          104
--                                          control     control     crews timed   robotic      robotic, uptime
--                                          (no 0757)               (physics 1)   (physics 2)  first (0747)
--     cars served (visits)                 205 (250)   217 (257)   211 (257)     210 (251)    210 (253)
--     deployed car-hours                   940.5       944.3       928.3         966.3        970.2
--     unmet ride demand                    15.6%       15.2%       16.7%         13.3%        12.9%
--     door p50 / p95 (min)                 90 / 274    85 / 271    85 / 278      85 / 268     85 / 268
--     must-do work done                    89.5%       90.6%       88.9%         90.2%        89.1%
--     wash seat, mean (min, from events)   10.00       10.00       10.89         6.72         6.85
--     detail seat, mean (min)              -           23.66       29.41         18.00        17.93
--     wash, detail bay-hours used          -           4.7, 16.2   5.1, 16.7     3.3, 13.5    3.1, 12.3
--     wash line p50 / p90 / longest (21)   15/160/335  15/158/310  25/208/305    10/138/210   5/77.5/190
--     idle bay-ticks, cars waiting (22)    157 (130)   156 (133)   180 (156)     191 (159)    147 (118)
--     walk-in refusals for a bay (26)      102         101         76            259          189
--     staff cap binding (29)               -           89 / 53     81 / 47       28 / 1       18 / 1
--   (22): five-minute bay-ticks with the bay empty while a car whose charge had ended waited for a wash seat; in
--   brackets, those with nothing booked on the bay at all. (29): ticks with two cars washing and a staged car waiting,
--   then those in which no walk-in was even tried. A dash is not read. The busy day, robotic lanes, arms 105 and 106:
--   127 (243) and 116 (231) cars served, 144.9 and 142.8 car-hours, 87.0% and 87.2% of ride demand unmet, door p50/p95
--   115/509 and 128/460, must-do work 78.5% and 78.6%; robotic wash seats 6.72 and 6.97 minutes, details 18.40 and 18.06.
--   Every car left at 100% with nothing open on all seven arms (rule 9). The seat timers of query (38) read the
--   timer written as the car entered the bay, which 0746 rewrites a tick later, so on the robotic arms seat lengths come
--   from the cars' state-change events (0451 (51)).
--
--   What robotic lanes buy at forty posts (103 against 101, the same cell otherwise; one seed): 22.0 more deployed
--   car-hours (944.3 to 966.3), unmet ride demand 15.2% to 13.3%, and the wash line's 90th percentile from 158 to 138
--   minutes and its longest wait from 310 to 210. Cars served fell from 217 to 210, on 251 visits against 257. That is
--   about what seven (at seed 2's 3.2 car-hours a post) to fourteen (at seed 1's 1.6) more fast chargers past twenty buy
--   (0451 §21). With uptime first on top (104): 970.2 car-hours, and the wash line's 90th percentile 77.5. The crews
--   timed by their own times (102) are the depot as staffed today honestly timed: 16.0 car-hours under the control.
--
--   Whether the wash is still the wall past twenty posts. Its bays, no: with robotic lanes the three bays held cars for
--   3.3 hours of washing and 13.5 of detailing in the 12-hour day (16.8 of 36 bay-hours), and the staff cap stopped
--   binding (28 ticks with two cars washing and one waiting, against 89; in 1 of them no walk-in was tried, against 53).
--   But the line did not shrink as the bays freed: walk-in refusals rose from 101 to 259 (for 26 cars) and idle
--   bay-ticks with a car waiting from 156 to 191. What holds it now is the calendar. 161 of the 259 refusals met a bay
--   held only by a reservation whose car never came (0451 (26)); of the 9 wash-bay no-shows on arm 103 (and the 9 on arm
--   104), 5 were cars parked in staging at their slot, which the calendar cannot seat (G471; 0755, held at the
--   connector), and 4 were cars still on their charger (0744's bay_hold_follows_charge, not on these cells) (0451 (55)).
--   A shorter window would not have helped (0451 §22). So past twenty posts the wash is still the line, but its wall is
--   the calendar's, not the bays'. 0451 §10 point 2 keeps its staged build: robofix (0451 §23) measures robotic lanes
--   with the calendar's four fixes on Tuesday night, and 0755 needs Chase.
--
-- ══ §7 UPTIME FIRST, READ (G461; reproduce: (3), (6), (7), (8)) ═════════════════════════════════════════════════════════
--
--   The same arms: robowash's wash_robotic.uptime_first (104) against its wash_robotic (103) on the normal day, and
--   uptimefirst_busy's two (106 against 105) on the busy day. Both pairs carry robotic lanes, so the bay order is judged
--   where the bays are fastest. One seed.
--                                          normal: 103 -> 104          busy: 105 -> 106
--     cars served (visits)                 210 (251) -> 210 (253)      127 (243) -> 116 (231)
--     deployed car-hours                   966.3 -> 970.2              144.9 -> 142.8
--     arrival to done, p50 / p90 (min), each need's atoms done of all (query (7)):
--       exterior wash                      84/151 -> 84/163            112/190 -> 111/271
--       interior deep clean                101/248 -> 106/235          257/548 -> 309/444
--       fault repair                       84/107 -> 104/143 (2 of 4)  282/466 (4 of 6) -> 212/266 (3 of 5)
--       mechanical PM                      49 -> 49 (1 of 2)           165/424 (21 of 112) -> 403/494 (19 of 110)
--       sensor calibration                 110 -> 115 (1 of 2)         125/301 (4 of 34) -> 95/310 (3 of 35)
--   On all four, every car that left did so at 100% with nothing open (rule 9): an atom not done never left with its
--   car.
--
--   Whether emergencies went first (query (8), from the key each decision recorded): on arm 104, 4 cars with an emergency
--   (14 decisions) and 3 seated; on arm 106, 4 cars (21 decisions), all 4 seated. On neither arm was a car without an
--   emergency seated in a service bay in a tick in which an emergency was refused. So the key's first term holds.
--
--   How often the 90-minute floor bound. On the normal day, 58 of arm 104's 386 decisions were past the floor and 5 of
--   its 69 seats went to a car past it. On the busy day, 937 of 1,434 decisions were past the floor and 66 of 93 seats
--   went to one: the floor is the order there, and the line is longest wait first. Twelve wash-bay seats on arm 104 and
--   13 on arm 106 went to a car under the floor in a tick in which a car past it was refused. In 17 of the 25 the seat
--   was a wash and the refused car needed a deep clean, a different job. The other 8, on arm 104, were deep cleans
--   seated past the Zoox 229f655b, which the shield refuses every time (G313). It never happened at a service bay.
--
--   What it bought (query (3), (4b)'s decisions by need). On the normal day, little: 3.9 car-hours, the same cars
--   served, the wash line's 90th percentile 138 to 77.5 minutes (§6), and a deep clean's 90th percentile 13 minutes
--   sooner, against a repair 20 minutes later at the median (2 of 4 done on both). On the busy day it cost: 11 fewer
--   cars served and 2.1 car-hours, a PM's median from arrival to done 165 to 403 minutes and a deep clean's 257 to 309,
--   for a repair's 282 to 212. The busy day's service bays are the wall (2 bays against 112 PMs and 34 calibrations),
--   and longest-wait-first spends them on the cars that have waited longest rather than on the cars that would leave
--   soonest, which is what the key's last terms were for. One seed, and the busy day's demand is G453's open question.
--   bay_order_uptime_first stays off. The 90-minute floor is the term to look at before another arm: on the busy day
--   nearly every car is past it.

-- (1) G460: each bay seat's timer, from the seat's own state-change event.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144),
seats AS (
  SELECT r.scenario_code, e.payload->'diff'->'current_state'->>'to' AS bay,
         extract(epoch from ((e.payload->'diff'->'config'->'to'->>'service_ends_at')::timestamptz
                             - (e.payload->'diff'->'last_state_change'->>'to')::timestamptz))/60.0 AS timer_min
    FROM ottoq_events e JOIN runs r ON r.sim_run_id = e.sim_run_id
   WHERE e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay','in_detail_bay','in_service_bay')
     AND e.payload->'diff'->'config'->'to' ? 'service_ends_at')
SELECT scenario_code, bay, count(*) n,
  round(avg(timer_min)::numeric,1) mean, round(percentile_cont(0.1) within group (order by timer_min)::numeric,1) p10,
  round(percentile_cont(0.5) within group (order by timer_min)::numeric,1) p50,
  round(percentile_cont(0.9) within group (order by timer_min)::numeric,1) p90,
  count(*) FILTER (WHERE timer_min < CASE bay WHEN 'in_wash_bay' THEN 6.3 WHEN 'in_detail_bay' THEN 17.5 ELSE 28 END) below_crew_floor
FROM seats GROUP BY 1,2 ORDER BY 1,2;

-- (2) G460: each seat against the booking that covers it: does the timer end where the booking ends, and how long
--     after the booking began was the car seated.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144),
seats AS (
  SELECT r.scenario_code, e.sim_run_id, e.entity_id AS vehicle_id, e.payload->'diff'->'current_state'->>'to' AS bay,
         (e.payload->'diff'->'last_state_change'->>'to')::timestamptz AS seat_at,
         (e.payload->'diff'->'config'->'to'->>'service_ends_at')::timestamptz AS ends_at
    FROM ottoq_events e JOIN runs r ON r.sim_run_id = e.sim_run_id
   WHERE e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay','in_detail_bay','in_service_bay')
     AND e.payload->'diff'->'config'->'to' ? 'service_ends_at'),
j AS (SELECT s.*, extract(epoch from s.seat_at - lower(b.during))/60.0 AS seat_after_book_lo,
             (upper(b.during) = s.ends_at) AS ends_at_booking_end
        FROM seats s LEFT JOIN LATERAL (
          SELECT b.* FROM ottoq_stall_bookings b
           WHERE b.sim_run_id = s.sim_run_id AND b.vehicle_id = s.vehicle_id AND b.purpose IN ('wash','detail','service')
             AND b.during @> s.seat_at ORDER BY lower(b.during) DESC LIMIT 1) b ON true)
SELECT scenario_code, bay, count(*) n, count(*) FILTER (WHERE ends_at_booking_end) ends_at_booking_end,
  round(avg(seat_after_book_lo)::numeric,1) mean_seat_after_booking_start
FROM j GROUP BY 1,2 ORDER BY 1,2;

-- (3) G461: decide section (4b)'s bay decisions by need, urgency and outcome.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144)
SELECT r.scenario_code, d.context_frame->>'need' need, d.context_frame->>'overall_urgency' urg, d.outcome_status, count(*) n
FROM ottoq_decisions d JOIN runs r USING (sim_run_id)
WHERE d.action_context = 'task_start' AND d.resolved_action_context = 'stall_assignment'
  AND d.proposed_action->>'source' = 'needs_card'
GROUP BY 1,2,3,4 ORDER BY 1,2,3,4;

-- (4) G461: how much the order's last two keys carry.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144)
SELECT r.scenario_code, count(*) n,
  count(*) FILTER (WHERE (d.context_frame->>'minutes_to_deploy')::numeric < 0) past_deploy,
  count(*) FILTER (WHERE d.context_frame->>'minutes_to_deploy' IS NULL) no_deploy,
  count(*) FILTER (WHERE COALESCE((d.context_frame->>'open_must_do_min')::numeric, 0) = 0) omd_zero,
  count(*) FILTER (WHERE d.context_frame->>'overall_urgency' = 'critical') critical,
  round(percentile_cont(0.5) within group (order by (d.context_frame->>'minutes_to_deploy')::numeric)::numeric, 0) med_mtd
FROM ottoq_decisions d JOIN runs r USING (sim_run_id)
WHERE d.action_context = 'task_start' AND d.resolved_action_context = 'stall_assignment'
  AND d.proposed_action->>'source' = 'needs_card'
GROUP BY 1 ORDER BY 1;

-- (5) The recall's rungs, read from the two implementations' source.
WITH src AS (SELECT p.proname, p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname IN ('ottoq_recall_naive_threshold_v1', 'ottoq_recall_interval_scheduled_v1')),
l AS (SELECT proname, t.ord AS ln, t.line FROM src, LATERAL unnest(string_to_array(src.prosrc, E'\n')) WITH ORDINALITY AS t(line, ord))
SELECT proname, ln, trim(line) FROM l WHERE line ~ 'RETURN QUERY SELECT true' ORDER BY proname, ln;

-- (6) G461's open question: charge seats given to a car held by an open repair while a clean car waited.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144),
seats AS (
  SELECT d.sim_run_id, r.scenario_code, (d.proposed_action->>'vehicle_id')::uuid AS vid, d.proposed_action->>'stall_type' AS kind,
         (d.context_frame->>'now_ts')::timestamptz AS t
    FROM ottoq_decisions d JOIN runs r USING (sim_run_id)
   WHERE d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
     AND d.proposed_action->>'verb' = 'assign_stall' AND d.proposed_action->>'stall_type' IN ('dcfc', 'l2')),
flagged AS (   -- each seat, and whether the seated car's visit open at that clock holds a must-do repair not yet done
  SELECT s.*, EXISTS (SELECT 1 FROM jsonb_array_elements(v.atoms) a
                       WHERE a->>'svc' = 'fault_repair' AND COALESCE((a->>'must_do')::boolean, false)
                         AND (a->>'done_at' IS NULL OR (a->>'done_at')::timestamptz > s.t)) AS repair_held
    FROM seats s
    LEFT JOIN LATERAL (SELECT n.atoms FROM ottoq_visit_needs n
                        WHERE n.sim_run_id = s.sim_run_id AND n.vehicle_id = s.vid AND n.arrived_at <= s.t
                        ORDER BY n.arrived_at DESC LIMIT 1) v ON true),
states AS (    -- each car's state from each change to the next, from its own state-change events
  SELECT e.sim_run_id, e.entity_id AS vid, e.sim_clock_at AS from_t,
         lead(e.sim_clock_at) OVER (PARTITION BY e.sim_run_id, e.entity_id ORDER BY e.sim_clock_at, e.event_seq) AS to_t,
         e.payload->'diff'->'current_state'->>'to' AS st
    FROM ottoq_events e JOIN runs r USING (sim_run_id)
   WHERE e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'),
waiting AS (   -- at a repair-held seat's clock, the clean cars waiting that need a charge of that kind
  SELECT h.sim_run_id, h.vid, h.t, w.vid AS wvid
    FROM flagged h
    JOIN states w ON w.sim_run_id = h.sim_run_id AND w.vid <> h.vid AND w.from_t <= h.t AND (w.to_t > h.t OR w.to_t IS NULL)
                 AND w.st IN ('arrived_at_gate', 'staged_awaiting_service')
    CROSS JOIN LATERAL (SELECT n.atoms FROM ottoq_visit_needs n
                         WHERE n.sim_run_id = h.sim_run_id AND n.vehicle_id = w.vid AND n.arrived_at <= h.t
                         ORDER BY n.arrived_at DESC LIMIT 1) wv
   WHERE h.repair_held
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(wv.atoms) a WHERE a->>'svc' = 'charge'
                   AND (a->>'closed_at' IS NULL OR (a->>'closed_at')::timestamptz > h.t)
                   AND (a->>'charger_class' IS NULL OR a->>'charger_class' = h.kind))
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(wv.atoms) a WHERE a->>'svc' = 'fault_repair'
                   AND COALESCE((a->>'must_do')::boolean, false)
                   AND (a->>'done_at' IS NULL OR (a->>'done_at')::timestamptz > h.t)))
SELECT h.scenario_code, h.kind, count(*) AS seats, count(*) FILTER (WHERE h.repair_held) AS repair_held,
       count(*) FILTER (WHERE h.repair_held AND EXISTS (SELECT 1 FROM waiting w
                                                         WHERE (w.sim_run_id, w.vid, w.t) = (h.sim_run_id, h.vid, h.t))) AS while_clean_waited
  FROM flagged h GROUP BY 1, 2 ORDER BY 1, 2;

-- (7) G461, §7: each bay need's atoms from the visit's arrival to the atom's done, per arm.
WITH runs(sim_run_id, arm) AS (VALUES ('d4af72ed-7021-42d2-ac93-dd8ce967b109'::uuid, 103), ('24de96a8-279c-4f9b-baf4-d5ff0e55367f'::uuid, 104),
                                      ('5a14f274-ef58-45ab-9625-b34edff6b92f'::uuid, 105), ('ab79a5c6-6aef-4196-ae4e-c9c4015254c0'::uuid, 106)),
a AS (
  SELECT r.arm, x ->> 'svc' AS svc, x ->> 'status' AS st,
         extract(epoch FROM ((x ->> 'done_at')::timestamptz - n.arrived_at)) / 60.0 AS m
    FROM runs r JOIN public.ottoq_visit_needs n ON n.sim_run_id = r.sim_run_id
    CROSS JOIN LATERAL jsonb_array_elements(n.atoms) x
   WHERE x ->> 'svc' IN ('exterior_wash', 'interior_deep_clean', 'mechanical_pm', 'fault_repair', 'sensor_calibration'))
SELECT arm, svc, count(*) AS atoms, count(*) FILTER (WHERE st = 'done') AS done,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY m) FILTER (WHERE st = 'done')::numeric) AS p50_arrival_to_done,
       round(percentile_cont(0.9) WITHIN GROUP (ORDER BY m) FILTER (WHERE st = 'done')::numeric) AS p90_arrival_to_done
  FROM a GROUP BY 1, 2 ORDER BY 2, 1;

-- (8) G461, §7: 0747's key on each of (4b)'s decisions (context_frame.uptime_key, ascending: its first term is 0 for a
--     safety emergency, its second 0 for a car past the wait floor): emergencies seated, and seats that went past a car
--     the key put ahead, in the same tick and at the same kind of bay.
WITH runs(sim_run_id, arm) AS (VALUES ('24de96a8-279c-4f9b-baf4-d5ff0e55367f'::uuid, 104), ('ab79a5c6-6aef-4196-ae4e-c9c4015254c0'::uuid, 106)),
d AS (
  SELECT r.arm, x.sim_clock AS t, x.entity_id AS vid, x.proposed_action->>'stall_type' AS bay_type, x.context_frame->>'need' AS need,
         ((x.context_frame->'uptime_key'->>0)::numeric = 0) AS emergency, ((x.context_frame->'uptime_key'->>1)::numeric = 0) AS past_floor,
         (x.outcome_status = 'enacted' AND x.enacted_action->>'verb' = 'assign_stall') AS seated,
         x.enacted_action->>'reason' AS reason
    FROM ottoq_decisions x JOIN runs r USING (sim_run_id)
   WHERE x.action_context = 'task_start' AND x.resolved_action_context = 'stall_assignment'
     AND x.proposed_action->>'source' = 'needs_card' AND x.context_frame ? 'uptime_key')
SELECT a.arm, a.bay_type, count(*) AS decisions,
       count(*) FILTER (WHERE a.emergency) AS emergency_decisions, count(DISTINCT a.vid) FILTER (WHERE a.emergency) AS emergency_cars,
       count(*) FILTER (WHERE a.emergency AND a.seated) AS emergency_seated,
       count(*) FILTER (WHERE a.past_floor) AS past_floor_decisions, count(*) FILTER (WHERE a.past_floor AND a.seated) AS past_floor_seated,
       count(*) FILTER (WHERE a.seated AND NOT a.emergency) AS other_seats,
       count(*) FILTER (WHERE a.seated AND NOT a.emergency AND EXISTS (
          SELECT 1 FROM d b WHERE b.arm = a.arm AND b.t = a.t AND b.bay_type = a.bay_type AND b.emergency AND NOT b.seated)) AS seated_past_a_refused_emergency,
       count(*) FILTER (WHERE a.seated AND NOT a.emergency AND NOT a.past_floor AND EXISTS (
          SELECT 1 FROM d b WHERE b.arm = a.arm AND b.t = a.t AND b.bay_type = a.bay_type AND b.past_floor AND NOT b.seated)) AS under_floor_seated_past_a_refused_one
  FROM d a GROUP BY 1, 2 ORDER BY 1, 2;
