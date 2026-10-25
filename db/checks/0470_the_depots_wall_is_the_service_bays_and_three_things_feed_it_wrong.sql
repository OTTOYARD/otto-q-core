-- 0470  **On the 30-post depot the wall is the two service bays, and three things feed it wrong: a plan's leftover charge
--        leg keeps ready cars out of their own empty bays; the posts give two thirds of their time to cars the bays will
--        hold; and the agent, reading a board that never says where the wall is, names the chargers.** -> G500, G501,
--        G502, G503; 0780 (G500).
--        Chase, 2026-10-24: "Dive deep into the agent layer now within OTTO-Q. Make sure we're not missing any edge in our
--        intelligence ... Study all layers and study what the ideal outcome is for optimal, autonomous, fleet,
--        orchestration, and logistics. Go find an edge and build."
--        Run 78c0624c-ff52-4594-8e54-9da254d4d867: busy_day at the twin depot (rule 8), 1,745 ticks, sim 13:00:00 to
--        22:00:44 (8:00 AM to 5:00 PM CT sim), started 03:18:55 UTC on 2026-10-24 by operator_demo, completed 06:08:00 UTC.
--        The depot as built since 0763: 30 robotic fast chargers, no standard charger, 3 wash bays, 2 service bays, 113
--        staging stalls, 10 general technicians, 3 service technicians. Read-only against gxdrcyphqjzjsuhxuqtg, 2026-10-24
--        16:07:41 UTC (the first query's clock, 11:07 AM CT) to 16:37:42 UTC (11:37 AM CT); 0780's apply is recorded in
--        its own file. PR #258's 0461 read the same run live, to sim 16:15; this file reads it to its end and asks a
--        different question: where is the wall, and is it fed.
--
-- ══ §1 THE WALL (reproduce: (1), (2)) ═════════════════════════════════════════════════════════════════════════════════════
--
--   247 visits, 134 served, 113 still in the depot at the horizon. The fast chargers were busy 75.5% of the day (265
--   sessions, a mean 46.2 minutes, 12,245 charge-minutes on 30 posts), and a car left its post a median 0.44 minutes
--   after its charge ended (p90 0.69, the most 4.1; 124 minutes in all, 1.0% of charge time): the posts are freed the
--   moment a car is done, as 0735 made them. The service bays faced 159 owed jobs (112 preventive maintenance at a mean
--   40.4 minutes, 41 calibrations at 60.4, 5 repairs at 81.2, 1 cosmetic repair at 60): about 124 bay-hours of work for
--   two bays open 9.0 hours, 6.9 times what they can do. They did 24 of those jobs in 22 seats. Of the 162 visits that
--   needed any bay, 53 left by the horizon; of the 85 that needed none, 81. The wash lanes were not the wall: 43 deep
--   cleans and 19 washes, about 17 bay-hours on three bays, 62 of 62 done.
--   Rule 9 names what a wall like this is: a capacity finding. Busy_day's maintenance load is about a hundred times a
--   real day's (G430, open, Chase's decision), so the size of the wall is the scenario's; how the depot feeds it is
--   the engine's, and that is what §2-§4 measure.
--
-- ══ §2 READY CARS WAIT BY THEIR OWN EMPTY BAYS (G500; reproduce: (3)-(7)) ═══════════════════════════════════════════════
--
--   (a) The service bays stood empty 151.7 of 1,081 bay-minutes (14.0%; NASH-SVC 6ff1e0a5 74.2, e8c670f7 77.5) by the
--       calendar's own seats (done, active and interrupted bookings, each to its release). In 97.3 of those minutes a
--       car was refused a service bay that tick for want of a free one (reason no_free_space), across eight gaps:
--       16.6 minutes (23 refused ticks), 24.4 (41), 7.5 (15), 1.5 (2), 13.9 (26), 6.0 (12), 2.6 (5) and 24.8 (41).
--   (b) Each gap ended at, or was cut by, a forward hold the planner had made 4-5 hours earlier, starting 3-60 minutes
--       into the gap. Six of its seven cars were read, and each was a car at 100%, its charge closed hours before,
--       parked in staging or in charge_complete_holding with a preventive maintenance owed: 05b0de6f (charged 14:31,
--       hold 18:46), 091fa637 (16:02, 17:41), 1b9b6ea1 (15:08, 19:41), 5cee8fb3 (14:40, 20:27), 5e93a514 (15:44, 20:58),
--       b97789b5 (15:30, 21:51). The seventh (616a06de, hold 22:24) was released by the run's stop and not read.
--   (c) Each of them carried a standard charge leg the itinerary had planned by its fixed rule (G459) and the depot could
--       never give (0763 left it no standard charger): charge_l2, planned to start 21:55 and run 165-445 minutes, never
--       started, re-timed forward. ottoq.ottoq_vehicle_bay_ready reads any such leg as a charge under way, so: the
--       calendar's early activation, which seats a ready car in its free bay ahead of its slot, never called them
--       ready; their own requests for the bay were refused because the window they asked for overlapped their own
--       hold (05b0de6f asked 92 times, 14:45 to 18:44); no other car could take the bay, its window overlapping the
--       same hold; and the yield (0553) moves a hold only for a car that cannot come, which these could.
--   (d) Three minutes before each hold began, the reconcile's BLOCKER 1, the same test, read the leg as charging and
--       released the hold replanned_no_window, giving ETAs of 21:23 to 05:03 the next morning. All 12 of the run's
--       reconcile actions blocked by 'charging' were on cars not on a charger whose last charge had closed at 99-100%:
--       10 service holds released, one service and one wash hold moved. Of the six gap holds released this way, five
--       cars never got a service bay in the run (5cee8fb3 was seated by the reactive path the tick its hold went).
--       05b0de6f stood in staging NASH-STG-E013 from 14:31:36 to the run's end at 22:00:44 with its maintenance owed.
--   So 97 bay-minutes at a wall 6.9 times oversubscribed, about two preventive maintenances a day, were lost to a plan
--   the depot cannot run, and the cars the bays were held for lost their place in line. 0780 has both readers ask the
--   car's battery (G244's one rule) before they believe its plan. Rule 9 is untouched: the departure test already reads
--   the battery.
--
-- ══ §3 THE POSTS SERVE CARS THE BAYS WILL HOLD (G501; reproduce: (8), (9)) ═════════════════════════════════════════════
--
--   Each visit split by whether it owed any bay work. The 85 that owed none (charge, cabin work at the post, the
--   readiness check) were ready a mean 1.4 minutes after their charge ended: the charge is their exit. They waited a
--   mean 34.5 minutes for a post (median 6.8). The 162 that owed bay work waited a mean 76.1 (median 43.4), and once
--   charged waited a mean 70.1 more for their bays (median 51.0); 107 of them were charged and still in the depot at the
--   horizon. Their charges were 7,098 of the run's 12,245 charge-minutes, and another 1,343 went to the 33 that left
--   more than 30 minutes after their charge ended: 69% of the posts' time went to cars whose exit the bays decided.
--   Hour by hour (sim, mean over 5-minute samples), the cars that owed no bay work and were waiting for a post, against
--   the posts charging a car that would then wait 30 minutes or more for its bays:
--
--       hour (CT)    8 AM   9 AM  10 AM  11 AM  12 PM   1 PM   2 PM   3 PM   4 PM
--       exit-bound   12.3    6.6    5.9    6.8    5.6    4.7    3.8    1.1    1.0   waiting for a post
--       bay-gated     4.0   11.0   15.3   14.9   20.5   22.3   20.8   17.1    3.9   charging on one
--
--   From 9 AM on, in every hour, more posts were charging cars the bays would hold than there were exit-bound cars
--   waiting. The kernel's line (0642: a car past 90 minutes first, then the response ratio in minutes of charge) has no
--   term for what a car does after its charge, so a car whose service bay is hours away and one that leaves the moment
--   it is full are ordered alike. Rule 9 names better ordering of who is served next as an answer to site pressure;
--   ordering the line by whether a charge is the car's exit is that ordering, with no charge shortened. The slack here
--   is measured in hindsight (the car's real wait for its bays); the engine's own estimate is the car's bay booking,
--   held at arrival 4-8 hours ahead on this day. Not built yet: it changes who charges first on every run and needs the
--   check's simulator to order the line the same way (the check's state carries the kernel's keys, 0642), so it is
--   its own file.
--
-- ══ §4 THE BOOT HOUR: TWO SERVICE BAYS EMPTY WHILE 46 CARS WAIT FOR A POST (G502; reproduce: (6), (10)) ════════════════
--
--   The other 53.7 idle bay-minutes had no candidate at all: 13:00-13:24:54 on one bay, 13:00-13:14:52 and
--   15:00:18-15:14:10 on the other. Section (4b) of the decide (needs-card space routing) seats a car in a bay only once
--   it owes no charge ("CHARGE FIRST ... the anchor leg"; 0003's one exception is a car owed interrupted bay work), and
--   at the boot every car needing a bay also needed a charge, with every post taken. Charge first was the right
--   doctrine when the posts were the wall (10 posts and 30 standard chargers); on 30 posts the wall is the bay, and a
--   car that will wait hours for its bay can be served there first when no post is free, then charged. Not built yet:
--   it is a change of doctrine across (4b), the bay readiness 0780 patches, the reconcile and the yield, and goes with
--   §3's ordering.
--
-- ══ §5 THE AGENT NAMES THE CHARGERS (G503; reproduce: (11)-(13)) ═══════════════════════════════════════════════════════
--
--   266 passes, every one consulted (the wake gate is in shadow at the twin depot), 6.01 million prompt tokens, a mean
--   22.7 s to answer. 8 changed state, 146 proposed the kernel's own charge order back, 109 advised only, 3 fell back.
--   Of 209 charge orders, 197 were refused by the check, 3 accepted, 5 taken in part, 4 rejected. The fifteen most
--   frequent directive shapes restate the board's counts: a car past its contract wait (237 and 28), the cars past it
--   (167), "Capacity finding: N cars wait for N free DCFC" (125 and 50), deploy overdue (116 and 100), scout findings,
--   a service backlog count (43). None of them names the service bays as the wall or says what the posts are spending
--   on cars the bays will hold. The board's own lesson is more_cars_than_chargers ("41 cars wait for 0 free chargers")
--   and its resources block gives pointer counts; nothing on it compares a resource's queued work with its capacity,
--   says which resource decides each car's exit, or counts the minutes a bay stood empty with a car ready. The agent
--   restates what it is shown. What would let it see the wall is a read model of the depot's constraint, which the
--   board would carry; PR #258's 0461 §7 lists the bay line as the agent's next lever (5) and one shift brief instead of
--   repeated directives (6), and both want that read model first.
--
-- ══ §6 WHAT IS BUILT, WHAT IS ON, WHAT IS ASKED ═════════════════════════════════════════════════════════════════════════
--
--   Built and applied: 0780 (G500), ledger 20261024163830 at 16:38:30 UTC (11:38 AM CT), dial bay_ready_reads_energy,
--   default 0. tests/test_bay_ready_reads_energy_sql.py, 12 tests on the scratch PostgreSQL over the live bodies.
--   Not yet on: switching it on at the twin depot is one ottoq_policy_set statement, and the Supabase connector held a
--   rolled-back live probe for a confirmation that a cloud session cannot answer (16:39 UTC). Rule 12 has the switch go
--   on at depot scope under the deciding person's name once that answer comes.
--   Named, not built: G501 (§3) and G502 (§4), one change of doctrine in two halves; G503 (§5), the agent's constraint
--   read model. G459's own fix, 0745's itinerary_charge_on_clock, would stop the itinerary planning the standard
--   charge at all; it is built and off at the twin depot (0459 §4 held it off on the old depot's arms, and 0461 §5
--   recommends it at 30 posts), and 0780 makes the bay calendar indifferent to whether it is on.

-- (1) the run and its depot
SELECT r.sim_run_id, r.status, r.tick_count, r.sim_clock_current, r.started_at, r.ended_at, r.run_by,
       (SELECT json_agg(s) FROM (SELECT stall_type, count(*) n FROM stalls
                                  WHERE depot_id = '11111111-1111-1111-1111-111111111111' GROUP BY 1 ORDER BY 1) s) AS stalls
  FROM ottoq_sim_runs r WHERE r.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867';
SELECT public.ottoq_throughput_scorecard('78c0624c-ff52-4594-8e54-9da254d4d867');

-- (2) the bay work owed and done, by service
SELECT a->>'svc' svc, a->>'requires_bay' bay, count(*) atoms, count(*) FILTER (WHERE a->>'status' = 'done') done,
       round(avg((a->>'est_min')::numeric), 1) est_min
  FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND a->>'concurrency' = 'bay'
 GROUP BY 1, 2 ORDER BY 3 DESC;

-- (3) each service bay's idle minutes, from the calendar's own seats
WITH b AS (
  SELECT b.stall_id, lower(b.during) s,
         least(coalesce(b.released_at, upper(b.during)), '2026-10-23 22:00:44+00'::timestamptz) e
    FROM ottoq_stall_bookings b JOIN stalls st ON st.id = b.stall_id
   WHERE b.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND st.stall_type = 'service_bay'
     AND b.state IN ('done', 'active', 'interrupted')),
used AS (SELECT stall_id, range_agg(tstzrange(s, e)) u FROM b WHERE e > s GROUP BY 1)
SELECT stall_id,
       round((SELECT sum(extract(epoch FROM (upper(r) - lower(r))) / 60) FROM unnest(u) r)::numeric, 1) used_min
  FROM used;

-- (4) the idle gaps, and the ticks in each that refused a car a service bay for want of a free one
WITH b AS (
  SELECT b.stall_id, lower(b.during) s,
         least(coalesce(b.released_at, upper(b.during)), '2026-10-23 22:00:44+00'::timestamptz) e
    FROM ottoq_stall_bookings b JOIN stalls st ON st.id = b.stall_id
   WHERE b.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND st.stall_type = 'service_bay'
     AND b.state IN ('done', 'active', 'interrupted')),
used AS (SELECT stall_id, range_agg(tstzrange(s, e)) u FROM b WHERE e > s GROUP BY 1),
idle AS (SELECT u.stall_id, r idle_r
           FROM used u, unnest(tstzmultirange(tstzrange('2026-10-23 13:00:00+00', '2026-10-23 22:00:44+00')) - u.u) r),
cand AS (SELECT sim_clock FROM ottoq_decisions
          WHERE sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND enacted_action->>'verb' = 'hold_no_space'
            AND enacted_action->>'stall_type' = 'service_bay' AND enacted_action->>'reason' = 'no_free_space'
          GROUP BY 1)
SELECT i.stall_id, lower(i.idle_r), upper(i.idle_r),
       round(extract(epoch FROM (upper(i.idle_r) - lower(i.idle_r))) / 60::numeric, 1) idle_min,
       (SELECT count(*) FROM cand c WHERE c.sim_clock <@ i.idle_r) refused_ticks
  FROM idle i WHERE upper(i.idle_r) - lower(i.idle_r) > interval '1 minute' ORDER BY 1, 2;

-- (5) the forward holds that ended each gap, and their cars' state and charge at the gap
--     (gap starts from (4); the held cars' last state change before it, their sessions and their bay atoms)
SELECT b.vehicle_id, lower(b.during) hold_from, b.state, b.release_reason, b.released_at, b.booked_at_sim
  FROM ottoq_stall_bookings b JOIN stalls st ON st.id = b.stall_id
 WHERE b.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND st.stall_type = 'service_bay' AND b.booked_by = 'otto_q'
   AND b.release_reason IN ('replanned_no_window', 'run_stopped')
 ORDER BY lower(b.during);

-- (6) the reconcile's actions blocked by a charge, against the car's charging at that moment
WITH r AS (
  SELECT r.*, st.stall_type FROM bay_reservation_reconcile_2026_08_02 r JOIN stalls st ON st.id = r.stall_id
   WHERE r.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND r.blocked_by LIKE 'charging%')
SELECT stall_type, action, reason, count(*) n,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM ocpp_sessions o
                                           WHERE o.vehicle_id = r.vehicle_id AND o.sim_run_id = r.sim_run_id
                                             AND o.started_at <= r.sim_clock AND coalesce(o.ended_at, 'infinity') > r.sim_clock)
                          AND coalesce((SELECT o.soc_end FROM ocpp_sessions o
                                         WHERE o.vehicle_id = r.vehicle_id AND o.sim_run_id = r.sim_run_id
                                           AND o.ended_at <= r.sim_clock ORDER BY o.ended_at DESC LIMIT 1), 0) >= 99)
         AS owed_no_charge
  FROM r GROUP BY 1, 2, 3;

-- (7) one car's leftover charge leg, and its requests for its own bay
SELECT l.seq, l.leg_type, l.status, l.planned_start_sim, l.planned_end_sim, l.actual_start_sim, l.actual_end_sim
  FROM ottoq_itinerary_legs l
 WHERE l.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND l.vehicle_id::text LIKE '05b0de6f%'
   AND l.leg_type LIKE 'charge%' ORDER BY l.planned_start_sim;
SELECT d.enacted_action->>'verb', d.proposed_action->>'verb', d.enacted_action->>'reason', count(*), min(d.sim_clock), max(d.sim_clock)
  FROM ottoq_decisions d
 WHERE d.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND d.entity_id::text LIKE '05b0de6f%'
   AND d.sim_clock BETWEEN '2026-10-23 14:30:00+00' AND '2026-10-23 18:50:00+00'
 GROUP BY 1, 2, 3 ORDER BY 5;

-- (8) visits by whether they owed bay work: wait for a post, charge, and charged-to-ready
WITH v AS (
  SELECT visit_id, vehicle_id, arrived_at,
         (SELECT (a->>'done_at')::timestamptz FROM jsonb_array_elements(atoms) a
           WHERE a->>'svc' = 'readiness_check' AND a->>'status' = 'done') ready_at,
         (SELECT count(*) FROM jsonb_array_elements(atoms) a WHERE a->>'concurrency' = 'bay') n_bay
    FROM ottoq_visit_needs WHERE sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867'),
s AS (
  SELECT v.*,
         (SELECT min(o.started_at) FROM ocpp_sessions o WHERE o.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867'
            AND o.vehicle_id = v.vehicle_id AND o.started_at >= v.arrived_at - interval '1 minute'
            AND (v.ready_at IS NULL OR o.started_at <= v.ready_at)) chg_start,
         (SELECT max(o.ended_at) FROM ocpp_sessions o WHERE o.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867'
            AND o.vehicle_id = v.vehicle_id AND o.started_at >= v.arrived_at - interval '1 minute'
            AND (v.ready_at IS NULL OR o.started_at <= v.ready_at)) chg_end
    FROM v)
SELECT (n_bay > 0) has_bay, count(*) visits, count(ready_at) ready,
       round(avg(extract(epoch FROM chg_start - arrived_at) / 60) FILTER (WHERE chg_start IS NOT NULL)::numeric, 1) mean_wait,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM chg_start - arrived_at) / 60)::numeric, 1) p50_wait,
       round(avg(extract(epoch FROM ready_at - chg_end) / 60) FILTER (WHERE ready_at IS NOT NULL)::numeric, 1) charged_to_ready,
       round(sum(extract(epoch FROM chg_end - chg_start) / 60)
               FILTER (WHERE ready_at IS NULL AND chg_end IS NOT NULL)::numeric, 0) charge_min_not_ready_at_horizon,
       round(sum(extract(epoch FROM chg_end - chg_start) / 60)
               FILTER (WHERE ready_at IS NOT NULL AND extract(epoch FROM ready_at - chg_end) / 60 > 30)::numeric, 0)
         charge_min_left_30_after
  FROM s GROUP BY 1;

-- (9) hour by hour: exit-bound cars waiting for a post, against posts charging a car its bays will hold 30+ minutes
--     (the visits of (8); hindsight slack: the car's real exit, or the horizon)
-- WITH ... (8)'s s, then:
-- SELECT date_trunc('hour', t) hr,
--        avg(count of n_bay = 0 visits arrived, not yet charging, not yet ready at t),
--        avg(count of n_bay > 0 visits charging at t with (coalesce(ready_at, horizon) - chg_end) > 30 minutes)
--   FROM generate_series('2026-10-23 13:00:00+00', '2026-10-23 22:00:00+00', interval '5 minutes') t GROUP BY 1;

-- (10) the decide's charge-first gate in (4b), and 0003's one exception (comment-stripped source)
SELECT position('CHARGE FIRST' IN prosrc) > 0 AS has_charge_first,
       position('rebook_owed' IN prosrc) > 0 AS has_0003_exception
  FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;

-- (11) the agent's passes by outcome class
SELECT outcome_class, count(*) passes, round(avg((usage->>'prompt_tokens')::numeric)) prompt_tok, round(avg(propose_ms)) ms
  FROM ottoq_agent_pass_evidence WHERE sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' GROUP BY 1 ORDER BY 2 DESC;

-- (12) the charge orders by status
SELECT status, count(*) FROM ottoq_agent_charge_orders
 WHERE sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' GROUP BY 1;

-- (13) the directives by shape (numbers masked)
SELECT left(regexp_replace(d->>'text', '[0-9]+(\.[0-9]+)?', 'N', 'g'), 70) shape, count(*) n
  FROM ottoq_agent_pass_evidence e, jsonb_array_elements(coalesce(e.answer->'actions', '[]'::jsonb)) d
 WHERE e.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND d->>'type' = 'directive'
 GROUP BY 1 ORDER BY 2 DESC LIMIT 15;
