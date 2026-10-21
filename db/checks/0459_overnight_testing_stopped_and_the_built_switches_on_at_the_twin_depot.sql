-- 0459  **Overnight testing is stopped, and seven of the switches built since 2026-10-17 are on at the twin depot, so its
--        demo now runs them: the fast chargers' cleaning arm cleaned its first live car at sim 8:47 AM CT.** -> G478.
--        Chase, 2026-10-20, after seeing no cleaning arm and no doors in his 3:09 PM CT demo: "Stop overnight testing. We
--        are still building. No need to certify and test until everything is finished and we are not there. Go and build
--        and implement!" Writes and reads against gxdrcyphqjzjsuhxuqtg on 2026-10-20 between 3:46 and 4:16 PM CT (20:46:57
--        UTC, the first query's clock, to 21:16:42 UTC, the last's), and the live check's reads to 5:53 PM CT (22:53:07
--        UTC). §7's write and reads ran from 9:10 to 10:24 PM CT (02:10:59 to 03:24:39 UTC on 2026-10-21). This check
--        applies no migration; every write is named below with the statement that undoes it. The migrations the live
--        checks led to, 0760, 0761 and 0762, carry their own.
--
-- ══ §1 WHY THE DEMO SHOWED NONE OF IT (reproduce: (1), (2)) ════════════════════════════════════════════════════════════
--
--   The published app had the code: its live build (otto-twin.lovable.app, main-DihDiuro.js and its chunks, fetched
--   2026-10-20 3:47 PM CT) carries the Q card's interior-clean words, the error boundary and the cleaning arm's keys from
--   ottoyarddepot-sim PR #146. What it draws comes from the engine, and the engine had every new switch off at the twin
--   depot. (1): Chase's run 0cdbfc72 (busy_day, 3:09-3:14 PM CT, 49 ticks) read all 17 switches added by 0726-0758 as
--   off; no row set any of them at depot or global scope. (2): its 16 interior tidies went to no arm (0 with
--   performed_by stall_cabin_robot), so the renderer, which moves an arm and opens a car's doors only while the snapshot
--   names an arm at work on that stall, had nothing to play. Every switch had been turned on only inside the research
--   wing's sweep cells (fixed_params), never for the demo.
--
-- ══ §2 OVERNIGHT TESTING STOPPED (3:59 PM CT; reproduce: (3)) ════════════════════════════════════════════════════════
--
--   SELECT cron.alter_job(784, active := false)   -- ottoq_sweep_window_open: opened the sweep window at 11 PM CT nightly
--   SELECT cron.alter_job(746, active := false)   -- ottoq-recert-runner: ran determinism pairs whenever no run was live
--   SELECT cron.alter_job(763, active := false)   -- the dial window's 2026-09-28 opener, which would fire every 28 Sep
--   Undo each with active := true. The runners (783 sweeps, 755 dial experiments) stay scheduled and idle: their windows'
--   dials are 0 (785 closed the sweep window at 6:00 AM CT, 762 the dial window at 5:41 AM CT) and nothing now opens them.
--   The 32 sweeps and 8 dial experiments keep status 'active' in their tables: pausing them is an UPDATE, held by the
--   Supabase connector for Chase's confirmation, and 0759's P0 reads those rows.
--
-- ══ §3 SEVEN SWITCHES ON (4:02 PM CT; reproduce: (4)) ══════════════════════════════════════════════════════════════
--
--   public.ottoq_policy_set('depot', '11111111-1111-1111-1111-111111111111', <key>, 1, 'Chase'), every result ok, each a
--   person's change made on Chase's instruction above. The evidence is the research wing's arms on seed
--   686364201590009433 (normal day, the twin answering in the tick), read 2026-10-20 between 4:00 and 4:01 PM CT; every
--   arm named here left 0 cars below target and 0 with needed work open.
--     twin_answer_in_tick           0735, G450: the twin carries out a command in the tick it is given; every research
--                                    cell had moved onto it (removing the lag bought 10 and 20 posts 10.7 and 29.2
--                                    car-hours, 0451 §12).
--     bay_activation_per_seat       0743, G457: each bay seat is its own; arm 118 served 210 visits against arm 95's 205.
--     bay_hold_follows_charge       0744, G458: a bay hold follows a charge that runs past its plan; arm 119 204 against 205.
--     bay_exit_closes_its_leg       0750, G464: every bay seat ends in its leg and service record; arm 122 matched arm 95
--                                    on every throughput figure, as bookkeeping should.
--     repair_needs_its_green_light  0753, G467: a repaired car waits for its technician's green-light at every door (in
--                                    the twin its technician answers 15-60 minutes after the repair, 92% approve); rule 9.
--     bay_release_reads_the_work    0757, G474: a bay seat that finished early is done (VERIFIED on six arms).
--     stall_cabin_robot             0758, G476: the fast charger's cleaning arm cleans the cabin during the charge.
--   Undo any one with ottoq_policy_set(..., 0, '<a person>').
--
-- ══ §4 HELD OFF, AND WHY ════════════════════════════════════════════════════════════════════════════════════════════
--
--     itinerary_charge_on_clock     0745, G459: at the depot as built (10 posts) arm 121 served 142 visits against arm
--                                    93's 159 and left 55 cars in the depot against 49. One arm, but too large to switch on
--                                    unread.
--     bay_order_uptime_first        0747, G461: on the busy day 11 fewer cars served and a PM's arrival-to-done median
--                                    165 -> 403 minutes (0452 §7).
--     ready_promise_record, ready_promise_refresh_min   0736/0742: research instrumentation; nothing an owner sees reads it.
--     dc_power_sharing, dc_power_managed, dc_power_first_reading, dc_power_by_need, site_cap_gate_metered
--                                    0726-0737: tested only at 40 posts on a 2,400 kW cabinet, where the held site served as
--                                    many visits as its control or more (arms 107, 112, 116, 117 against 95 and 115) at lower
--                                    peaks. As built the cap never binds (arm 93's peak 915 kW against 1,800), so they would
--                                    change nothing today; they belong with 0759's 20 posts, as one change.
--     wash_lane_physics             0746, G460/G475: whether the depot's wash lanes are robotic is Chase's equipment call.
--                                    Robotic lanes (2) met 22.0 more car-hours at 40 posts and served 7 fewer cars; crews
--                                    timed by their own work (1) met 16.0 fewer, because the catalog prices a deep clean at
--                                    20 minutes and the crews take 25 (G475, open).
--
-- ══ §5 WAITING ON CHASE'S CONFIRMATION AT THE CONNECTOR ═════════════════════════════════════════════════════════════
--
--   0603 (UPDATE of four schedule_tasks rows), 0749 (its checks DROP probe tables), 0755 (its third anchor reads as an
--   UPDATE of every car; preconditions passed read-only at 4:03 PM CT), the research pause (UPDATEs; needed by 0759's P0),
--   and 0759. The connector holds each for a person's confirmation; none is reworded or sent another way.
--
-- ══ §6 THE LIVE CHECK (run c6ec017d; reproduce: (5)-(8)) ═══════════════════════════════════════════════════════════
--
--   Started at 4:05 PM CT the way the app's Start does (otto-twin-control's startScenario): ottoq_operator_start_run
--   ('busy_day') then ottoq_set_playback(run, 'live', 3); the edge's fire-and-forget call to ottoq-feed-agents, which needs
--   the service key, was not made. (5): the run reads the seven as 1 and the held switches as 0. (6): car 7a138260 plugged
--   into NASH-DCFC-STALL-06 at sim 8:46 AM CT at 21%; its must-do tidy started at sim 8:47:25 by the stall's arm
--   (performed_by stall_cabin_robot, robot_stall_id the stall, ends_at started_at + 5.8 minutes), no technician. (7): by
--   4:16 PM CT, tick 127, sim 9:06 AM CT: 2 arm cleans done, 44 service records issued. The live view (the app's own code
--   on a dev server, pinned to the run) filmed DCFC-08's cycle: doors open at sim 8:55, the arm cleaning side A at 8:58,
--   home after (ottoyarddepot-sim docs/pr-shots/clean-arm-live, scripts/liveCleanShots.mjs).
--   (8)-(11), read between 5:51 and 5:53 PM CT (22:51:19-22:53:07 UTC; tick 1,125, sim 2:33 PM CT), mid-run. (The run
--   was said here to end at 240 real minutes; its governor ended it at its 540 sim-minute ceiling instead, below.)
--     - Rule 9 at departure: 37 departures, 0 below target, 0 with needed work open.
--     - Work: 322 of 665 must-do atoms done; 144 visits, 37 served, 394 service records.
--     - The bay seats: no seat was filed interrupted. Wash bays: 29 done, 26 of them on their own bay exit
--       (bay_exit_closes_its_leg, bay_release_reads_the_work); service bays: 12 done, 10 on their bay exit.
--     - Repairs: no fault repair is done yet (4 pending), so no green-light has been asked.
--     - The cleaning arm: 8 cleans done, on DCFC-05 to -09; 1 thrown away, ca2624fc's, below.
--     - Service records issued at bay exit: 19 wash, 13 detail and 19 service, of 417 records in all.
--     - The bay calendar's seats (12), read 5:59-6:01 PM CT: 140 refused attempts, every one a 23505 on
--       idx_stalls_one_vehicle_per_stall, between sim 11:50 AM and 2:58 PM CT. 78 were for 8 cars' service-bay
--       bookings and 62 for 6 cars' wash-bay bookings. Each is G471: the car still holds its staging stall when the
--       calendar stamps it into its bay. 0755 fixes it and waits on Chase at the connector (§5). Meanwhile a
--       reserved bay can sit empty while its car waits in staging: NASH-SVC-02 was free at sim 2:53 PM, and its
--       next car, 4b179b26, was refused there at 2:58.
--     - The server log, 4:05-6:01 PM CT: no errors. The only warnings are those seat refusals and the 12
--       interlock refusals below.
--   The full day, (8)-(12), read 6:51-6:52 PM CT (23:51:37-23:52:24 UTC). The run governor ended the run at 6:36 PM CT
--   (23:36:00 UTC, tick 1,557), on reaching its 540 sim-minute ceiling: sim 8:00 AM to 5:01 PM CT.
--     - Rule 9 at departure: 54 departures, 0 below target, 0 with needed work open.
--     - Work: 446 of 756 must-do atoms done; 163 visits, 54 served (50 cars), 109 still in the depot at the end;
--       533 service records.
--     - The cleaning arm: 10 cleans done, on 7 fast chargers. 1 was thrown away, ca2624fc's, before 0760 and 0761.
--       Every one of the 10 finished before its car's charge did, so neither fix met its case on this run.
--     - The bay seats: none filed interrupted. Wash bays: 47 done on their own bay exit. Service bays: 15 done on
--       their own bay exit. At the stop, 10 wash and 25 service bookings were released (run_stopped).
--     - Refused moves filed as an exception: the 12 before 0761's dial, none after it (ticks 1,101-1,557).
--     - G471: 210 refused seat attempts over 20 bookings and 17 cars (136 at the service bays, 74 at the wash bays).
--     - Charging, busy day at 10 fast chargers: from arrival to first charge, a median 144.1 minutes, p95 246.7 and
--       the longest 250.3; 10 cars still waiting at the end. That queue is what 0759's twenty posts are for (§5).
--   One defect surfaced on the run's fourth arm clean, at 4:28 PM CT (G479). Car ca2624fc's charge ended while the arm
--   was still in its cabin, and the tether sweep freed its stall 15 seconds early. Decide section (4b), the walk-in
--   door, then took the car. This section first said the bay calendar took it; the decision rows and the booking,
--   read at 5:36-5:39 PM CT, say (4b).
--     - db/migrations/0760, applied at 4:37 PM CT, keeps the stall.
--     - db/migrations/0761, applied at 5:50 PM CT, has (4b) and (5) read the arm's hold. 0760 alone did not make them.
--     - 0761 also stops filing the charge arm's interlock as an engine exception (G472). Its dial
--       bay_walkin_waits_for_the_arm was switched on at the twin depot under Chase's name at 5:50 PM CT, by
--       public.ottoq_policy_set('depot', '11111111-1111-1111-1111-111111111111', 'bay_walkin_waits_for_the_arm', 1, 'Chase')
--       (undo with 0 and a person's name). Before it, all 12 of the run's refused moves were that interlock, the last
--       at tick 558; in its first 14 ticks, none.
--
-- ══ §7 ROBOTIC WASH LANES ON, AND THE WASH BAYS' MACHINE (run 96371023; reproduce: (13), (14)) ═════════════════════
--
--   Chase, 2026-10-20 9:05 PM CT: "Wash bays are robotic too. Car pulls in and the machine moves back and forth over it
--   several times to wash and rinse and blow dry before vehicle leave."
--     - wash_lane_physics 2 (0746, robotic lanes) on at the twin depot under Chase's name at 9:10 PM CT (02:10:59 UTC on
--       2026-10-21), by public.ottoq_policy_set('depot', '11111111-1111-1111-1111-111111111111', 'wash_lane_physics', 2,
--       'Chase') (undo with 0 and a person's name). §4 had held it as Chase's equipment call; this is the call.
--     - 0762, applied at 9:25 PM CT (G480): the snapshot publishes each bay car's seat, bay_seat {since, ends_at}, so the
--       renderer plays the bay's machine inside the twin's seat. Read only.
--     - The renderer (ottoyarddepot-sim PR #148): one rollover gantry per wash bay, six passes over the car (pre-soak, two
--       brush passes, rinse, two air-dry passes), and on a detail seat two vacuum wands through the open doors first. It
--       holds the car until it is home. From above, the canopies' solar modules and the halls' roofs now fade: from the
--       Bird Eye view they hid every arm and machine (seen on this run's live view, 10:09-10:13 PM CT: 03:09:19 to
--       03:13:24 UTC, the screenshots' own file times).
--   Run 96371023: busy_day, started at 10:06 PM CT (03:06:30 UTC) as the app's Start does, live at 3x.
--   (13), read at 10:24 PM CT (03:24:39 UTC; tick 215, sim 9:00 AM CT): every seat timed by the robotic cycle.
--     - Wash bays: 5 seats, 5 closed, 4.56-5.82 minutes (p50 4.81). The dial draws 5.0 within 15%; the tick rounds up.
--     - Detail seats: 5, 4 closed, 16.11-19.00 minutes (p50 17.71); the dial draws 16.5 within 20%.
--     - The two read in their bays at 10:20 PM CT each ended minutes before the engine's booked end (5.587 minutes against
--       a booking 3 minutes longer; 18.688 against one 6 minutes longer), so the release frees the bay early.
--   (14), the cleaning arm on the same run, read at 10:21 PM CT (03:21:08-03:21:49 UTC): 2 must-do tidies done by a fast
--   charger's arm and 8 by technicians. None of the 8 was the arm's to take. The arm takes a must-do tidy only while the
--   car charges on its stall with a whole cycle of charge left (0758: 5.8 minutes). Car b97789b5's charge lasted 5.6
--   minutes. Cars 380f0f38, ab7adca4 and aff36072 had their tidy raised after their charge ended (a triage confirm, or a
--   new visit). The other 4 never charged on a fast charger.
--
-- ══ QUERIES ═════════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) the switches Chase's run read
SELECT k, public.ottoq_policy_get('0cdbfc72-0c0b-4dc0-b3b8-c6fa00616122'::uuid, k, 0) AS read
  FROM unnest(ARRAY['dc_power_sharing','site_cap_gate_metered','dc_power_managed','dc_power_first_reading',
                    'twin_answer_in_tick','ready_promise_record','dc_power_by_need','ready_promise_refresh_min',
                    'bay_activation_per_seat','bay_hold_follows_charge','itinerary_charge_on_clock','wash_lane_physics',
                    'bay_order_uptime_first','bay_exit_closes_its_leg','repair_needs_its_green_light',
                    'bay_release_reads_the_work','stall_cabin_robot']) k;

-- (2) who did its interior work
SELECT a->>'svc' AS svc, count(*) AS atoms, string_agg(DISTINCT COALESCE(a->>'performed_by', '-'), ', ') AS performed_by
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = '0cdbfc72-0c0b-4dc0-b3b8-c6fa00616122' AND a->>'svc' ILIKE 'interior%'
 GROUP BY 1 ORDER BY 1;

-- (3) the test openers
SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobid IN (746, 755, 761, 762, 763, 783, 784, 785) ORDER BY jobid;

-- (4) the twin depot's switches
SELECT param_key, param_value, updated_by, updated_at FROM public.ottoq_policy_params
 WHERE scope_type = 'depot' AND scope_id = '11111111-1111-1111-1111-111111111111' AND updated_at > '2026-10-20 20:00+00'
 ORDER BY param_key;

-- (5) what the live check read
SELECT k, public.ottoq_policy_get('c6ec017d-ec07-4762-8774-4129de1f4ad6'::uuid, k, 0) AS read
  FROM unnest(ARRAY['twin_answer_in_tick','bay_activation_per_seat','bay_hold_follows_charge','bay_exit_closes_its_leg',
                    'repair_needs_its_green_light','bay_release_reads_the_work','stall_cabin_robot',
                    'itinerary_charge_on_clock','bay_order_uptime_first','dc_power_sharing','wash_lane_physics']) k;

-- (6), (7) the arm's work on the live check
SELECT left(vn.vehicle_id::text, 8) AS car, a->>'status' AS status, s.stall_code, a->>'started_at' AS started_at,
       a->>'ends_at' AS ends_at, a->>'done_at' AS done_at
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
  LEFT JOIN public.stalls s ON s.id::text = a->>'robot_stall_id'
 WHERE vn.sim_run_id = 'c6ec017d-ec07-4762-8774-4129de1f4ad6' AND a->>'performed_by' = 'stall_cabin_robot'
 ORDER BY a->>'started_at';

-- (8) rule 9 at departure, the work done and the service records
SELECT sc.j -> 'rule9' AS rule9, sc.j -> 'service_completion' AS service_completion, sc.j -> 'throughput' AS throughput,
       (SELECT count(*) FROM public.ottoq_service_detail_records s
         WHERE s.sim_run_id = 'c6ec017d-ec07-4762-8774-4129de1f4ad6') AS sdrs
  FROM (SELECT public.ottoq_throughput_scorecard('c6ec017d-ec07-4762-8774-4129de1f4ad6'::uuid) AS j) sc;

-- (9) how the bay seats closed
SELECT s.stall_type::text AS bay, b.state, COALESCE(b.release_reason, '-') AS why, count(*) AS bookings
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.sim_run_id = 'c6ec017d-ec07-4762-8774-4129de1f4ad6' AND s.stall_type::text IN ('wash_bay', 'service_bay')
   AND b.booked_by LIKE 'otto_q%'
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

-- (10) the cleaning arm's cleans: done, at work, and thrown away (an interruption 'left_the_cabin_robot')
SELECT count(*) FILTER (WHERE a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' = 'done') AS done,
       count(*) FILTER (WHERE a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' = 'in_progress') AS at_work,
       count(*) FILTER (WHERE a::text LIKE '%left_the_cabin_robot%') AS thrown_away
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = 'c6ec017d-ec07-4762-8774-4129de1f4ad6';

-- (11) refused moves filed as an exception, before and after 0761's dial (on from tick 1,101)
SELECT count(*) FILTER (WHERE d.tick_seq <= 1100) AS before_the_dial, count(*) FILTER (WHERE d.tick_seq > 1100) AS after,
       count(*) FILTER (WHERE d.tick_seq > 1100 AND d.enacted_action ? 'message') AS after_with_their_message
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = 'c6ec017d-ec07-4762-8774-4129de1f4ad6' AND d.enacted_action ->> 'reason' = 'exception';

-- (12) the bay calendar's refused seats (G471), per bay type: attempts, bookings, cars
WITH ref AS (
  SELECT e.sim_clock_at, x->>'booking_id' AS booking_id, x->>'vehicle_id' AS vehicle_id, x->>'stall_id' AS stall_id,
         x->>'sqlstate' AS sqlstate
    FROM public.ottoq_events e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'refused') x
   WHERE e.sim_run_id = 'c6ec017d-ec07-4762-8774-4129de1f4ad6' AND e.event_type = 'ottoq.bay_reservation_seat_refused')
SELECT s.stall_type::text AS bay, ref.sqlstate, count(*) AS attempts, count(DISTINCT ref.booking_id) AS bookings,
       count(DISTINCT ref.vehicle_id) AS cars, min(ref.sim_clock_at) AS first_at, max(ref.sim_clock_at) AS last_at
  FROM ref JOIN public.stalls s ON s.id::text = ref.stall_id
 GROUP BY 1, 2 ORDER BY 1;

-- (13) the wash and detail seats on run 96371023: each from its car's state change into the bay to the one out of it
WITH seats AS (
  SELECT e.entity_id AS car, e.sim_clock_at AS at, e.payload->'diff'->'current_state'->>'to' AS new_state,
         e.payload->'diff'->'current_state'->>'from' AS old_state
    FROM public.ottoq_events e
   WHERE e.sim_run_id = '96371023-affc-40f1-9df0-650dc7746389' AND e.event_type = 'vehicle.state_changed'
     AND (e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay', 'in_detail_bay')
          OR e.payload->'diff'->'current_state'->>'from' IN ('in_wash_bay', 'in_detail_bay'))),
pairs AS (
  SELECT s.car, s.new_state AS bay, s.at AS seated,
         (SELECT min(x.at) FROM seats x WHERE x.car = s.car AND x.old_state = s.new_state AND x.at > s.at) AS out_at
    FROM seats s WHERE s.new_state IN ('in_wash_bay', 'in_detail_bay'))
SELECT p.bay, count(*) AS seats, count(p.out_at) AS closed,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM p.out_at - p.seated) / 60.0)::numeric, 2) AS p50_min,
       round(min(extract(epoch FROM p.out_at - p.seated) / 60.0)::numeric, 2) AS min_min,
       round(max(extract(epoch FROM p.out_at - p.seated) / 60.0)::numeric, 2) AS max_min
  FROM pairs p GROUP BY p.bay ORDER BY 1;

-- (14) the must-do tidies on run 96371023: who did them, and the car's fast-charger bookings
SELECT left(n.vehicle_id::text, 8) AS car, COALESCE(a->>'performed_by', 'technician') AS by,
       (a->>'started_at')::timestamptz AS started, (a->>'ends_at')::timestamptz AS ends,
       (SELECT jsonb_agg(jsonb_build_object('from', lower(b.during), 'to', upper(b.during)) ORDER BY lower(b.during))
          FROM public.ottoq_stall_bookings b JOIN public.stalls st ON st.id = b.stall_id
         WHERE b.vehicle_id = n.vehicle_id AND b.sim_run_id = n.sim_run_id AND st.stall_type::text = 'dcfc') AS dcfc
  FROM public.ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
 WHERE n.sim_run_id = '96371023-affc-40f1-9df0-650dc7746389' AND a->>'svc' = 'interior_tidy' AND a->>'status' = 'done'
 ORDER BY 3;
