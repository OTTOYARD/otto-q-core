-- 0493  **An agent's directive is graded against the brief it answered; the fallback model has now answered live
--        passes, and four of its ten graded directives contradict their brief; and the wash bay the board called idle
--        held a car on its way out, not in.**
--        Production database, 2026-11-14 06:12 to 06:29 UTC (12:12 to 12:29 AM CT), from now() on the reads. Rule 8:
--        the twin depot. Rule 12: nothing was run for this; the reads are of stored passes and of run 7435e685, which
--        another session had live. Closes db/checks/0492 (6)(a) and (6)(b); (6)(c) is now seen.
--
-- ══ (1) 0492 (6)(a), G541 (b), ANSWERED: THE BAY THE BOARD CALLS IDLE HOLDS A CAR THAT IS LEAVING ════════════════════
--
--   0492 §4 (b) read public.ottoq_depot_constraint's busy count (cars in the state in_wash_bay / in_detail_bay /
--   in_service_bay) as missing "a bay a car holds on its way in". Measured instead of assumed. Every stored board
--   carries both counts for the same moment: constraint.resources[].busy_now and the grounding block's occupied
--   (stalls.current_vehicle_id IS NOT NULL). Over the consulted boards of the last three days (482 boards, 21 runs):
--                                    before 0829 (387 boards, 16 runs)     after 0829 (95 boards, 5 runs)
--     wash: busy_now < occupied      34                                    7
--     wash: idle_with_car_ready > 0  189                                   21
--     ... and above the pointer-free count   7                             0
--     service: busy_now < occupied   12                                    2
--     service: idle_with_car_ready > 0   32                                6
--     ... and above the pointer-free count   12                            3
--   busy_now is never above occupied. On run 7435e685 the three boards where it is below (pass 10974: one wash bay
--   and one service bay; pass 10991: one wash bay) were rebuilt from the signed events (the stall's last
--   current_vehicle_id diff and that car's current_state diffs, by sim clock):
--     NASH-WSH-01  Tesla-AV-059  in_wash_bay 16:02:43, staged_awaiting_service 16:09:10 (the board's clock), deployed 16:11:16
--     NASH-SVC-02  Tesla-AV-052  in_service_bay 15:29:25, staged_for_departure 16:09:10 (the board's clock), deployed 16:09:39
--     NASH-WSH-03  Waymo-AV-014  in_wash_bay 16:33:59, staged_for_departure 16:41:47 (the board's clock), deployed 16:42:14
--   Three of three: the car finished its bay work in the tick the board was read and had not driven out. It is a car
--   on its way OUT. For one tick the pointer says occupied and the state says free; the bay is free a tick later.
--   And the one "idle with a car ready" read on that run (pass 10991, 16:41:47): the ready car was Zoox-AV-075, whose
--   charge ended at 16:41:47 exactly, whose post's arm finished its cabin tidy at 16:44:47, and which was in
--   NASH-WSH-03 at 16:45:28. The bay waited 3.7 minutes for a car still under its post's arm.
--   NOT CHANGED: public.ottoq_depot_constraint. Counting the pointer would report a finished car's bay as busy for its
--   last tick, which is no nearer the truth. 0829 took the count that mattered (189 of 387 boards to 21 of 95).
--   Three boards on one run; the other 52 boards where the counts differ are on purged runs and were not rebuilt.
--
-- ══ (2) 0492 (6)(b): THE GRADER, 0834 AND 0835 ═══════════════════════════════════════════════════════════════════════
--
--   public.ottoq_agent_directive_grade(brief, directive): four kinds of claim about a charge a fault cut (the post,
--   the percentage at the cut, charging again or not, the place in the line), graded against the wake brief of the
--   same pass, only where the sentence's subject is certain. public.ottoq_agent_directive_grades: every stored
--   directive that answered such a brief. Pure, read-only; no engine function reads either.
--   BEFORE THE APPLY the body ran as a session-local copy over the stored passes. Its first draft read "Check charging
--   again on available DCFC." as a claim that the car is charging again, 16 times: an order, not a claim. The pattern
--   was narrowed; the second read flagged 4 directives, each read against its brief and each a real contradiction.
--   0834 applied 06:27:10 UTC (ledger 20261114062710), P0-P2 and V1-V4 passing inside the file, the body's md5 the one
--   the tests ran (9998f2ee…). Read back at 06:28:49 UTC, the twin depot:
--     model that answered                      directives  passes  runs  claims  consistent  contradicted
--     nvidia/nemotron-3-ultra-550b-a55b (primary)   494     137     11    551     201         0
--     nvidia/nemotron-3.5-lightning-30b-a3b          56      17      3     23       6         4
--   0835 (06:28:42 UTC, ledger 20261114062842) is my correction of 0834: its view carried by_fallback_model, read from
--   the stored answer, and the edge function writes that mark on the directive it applies, never into the answer it
--   stores (0 of the fallback's 56 rows carried it). A column that is always NULL reads as "no fallback wrote this".
--   Found reading the view back, before anything read the column. model_answered is the truth.
--   Tests: tests/test_agent_directive_grade_sql.py, 14 on the scratch PostgreSQL; 12 of 12 hand mutations of the
--   function and the view caught (4 survived the first draft of the tests, and a case was added for each).
--   WHAT A GRADE IS NOT. "consistent" is not "right". 339 of the 550 directives make no claim it can read. Its truth
--   is the brief, the engine's read at the pass's clock.
--
-- ══ (3) 0492 (6)(c), NOW SEEN: THE FALLBACK HAS ANSWERED LIVE PASSES, AND ITS DIRECTIVES ARE WORSE (G546) ════════════
--
--   0492 §2: "NOT SEEN: a primary failure on a live pass since the chain went in." Since then the fallback
--   (nvidia/nemotron-3.5-lightning-30b-a3b, agent v33) answered 24 consulted passes at the twin depot. 17 of them
--   answered a brief with a cut charge: recorded 2026-11-13 21:33 to 2026-11-14 02:20 UTC, on runs c86b46e1 (12),
--   14d6eda7 (3) and c8913ea2 (2), with 15 timeouts and 6 HTTP 503 among the primary's attempts on them.
--   Of its 10 directives with a claim the grader could read, 4 are contradicted; of the primary's 201, none.
--     passes 9796, 9809, 9823 (run c86b46e1): "Waymo-AV-026 ... charge cut ... at SoC 48%". The brief: cut at 99% on
--       NASH-DCFC-STALL-09, 48% now (the car left and came home). It took the car's charge now for the charge at the
--       cut. 9823 also gives the place 37 where the brief has 22; 37 is the place its directive of pass 9809 gave.
--     pass 10317 (run 14d6eda7): "Waymo-AV-024 ... waiting in line pos 21"; the brief has 18.
--   Three runs and ten graded directives: a reading, and the direction 0492 §2 found on its replays.
--   NOT CHANGED: the agent. A directive changes no engine state (0823), so a wrong one misinforms a reader and moves
--   no car. What to do with a contradicted directive (drop it, mark it, or ask the primary again) is the edge
--   function's, and waits for a decision: the grade can now be read at the pass.
--
-- ══ (4) SEEN ON THE WAY, RECORDED AND NOT CHANGED ════════════════════════════════════════════════════════════════════
--
--   Run 7435e685 at sim 16:43 (busy_day, 2 hours 43 minutes in): the service bays' line held 75 cars and 4,347
--   minutes of work for 2 bays; three minutes later the open visits' pending service-bay atoms were 67 mechanical_pm
--   (a mean 42.8 minutes), 18 sensor_calibration, 6 fault_repair and 1 cosmetic_repair. The agent's own answer of
--   16:41 puts it at 36.1 hours to clear. Zoox-AV-075's mechanical_pm was booked for 02:38 the next sim day. This is
--   the wall of G500-G503, on a scenario that scales the PM interval to 0.01 (vehicles.config.scenario_interval_scale).
--   Rule 9 holds every one of those cars until its service is done; rule 13 sets the ceiling after the build. It is a
--   capacity reading for a person, not a lever.
--   The primary's directives of passes 10391 and 10394 name two cars cut at 97% and 98% and still waiting for a post
--   209 and 222 minutes later (Waymo-AV-024, Waymo-AV-039). NOT READ: whether they owed bay work and yielded their place (0781), which would
--   make the wait the rule's and not a defect. G542 is where a cut car's wait is tracked.
--   The same question on the live run 7435e685, read at sim 21:05 (after 06:44 UTC): 15 charges cut by a charger
--   fault, all 15 cars charging again, after a mean 22.9 minutes. Two took over two hours. Zoox-AV-085 (cut at 99%,
--   141 minutes) deployed in between, so that is not a wait. Lucid-AV-003 (cut at 91% at sim 15:24) stood 129 minutes
--   at the depot before its next charge; it owes a mechanical_pm in the service bays, the kind of car 0781 has yield
--   its place to its owner's other cars. NOT READ: its exit_key during those 129 minutes. The next longest is 23.
--
-- ══ (5) WHAT IS OPEN ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) What the edge function does with a contradicted directive (§3). (b) The grader reads cut charges only; the
--   brief's other subjects (a faulted post's fault, a contract wait's minutes, an emergency) have no grade.
--   (c) 0492 (6)(d) and (6)(e) are as 0492 left them. (d) The two long waits of §4.
--
-- ══ THE QUERIES ═══════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) the board's two counts of the same bays, before and after 0829
WITH b AS (
  SELECT pass_id, sim_run_id, recorded_at >= '2026-11-14 00:47:43+00' AS after_0829, board_text::jsonb AS j
    FROM public.ottoq_agent_pass_evidence
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND consulted AND board_text IS NOT NULL
     AND recorded_at > now() - interval '3 days'),
x AS (
  SELECT b.pass_id, b.sim_run_id, b.after_0829, l.lane,
         jsonb_path_query_first(b.j, ('$.**.' || l.lane || ' ? (exists(@.free_by_pointer))')::jsonpath) AS p,
         (SELECT r FROM jsonb_array_elements(b.j -> 'constraint' -> 'resources') r WHERE r ->> 'resource' = l.lane) AS c
    FROM b, (VALUES ('wash_bay'), ('service_bay')) AS l(lane))
SELECT after_0829, lane, count(*) AS boards, count(DISTINCT sim_run_id) AS runs,
       count(*) FILTER (WHERE (c ->> 'busy_now')::int < (p ->> 'occupied')::int) AS busy_below_occupied,
       count(*) FILTER (WHERE (c ->> 'busy_now')::int > (p ->> 'occupied')::int) AS busy_above_occupied,
       count(*) FILTER (WHERE (c ->> 'idle_with_car_ready')::int > 0) AS idle_with_car_ready,
       count(*) FILTER (WHERE (c ->> 'idle_with_car_ready')::int
                              > LEAST((p ->> 'free_by_pointer')::int,
                                      GREATEST((c ->> 'units_up')::int - (p ->> 'occupied')::int, 0))) AS above_pointer_free
  FROM x GROUP BY 1, 2 ORDER BY 1, 2;

-- (4) charges a fault cut on a run, and how long each car took to charge again
WITH cut AS (
  SELECT os.vehicle_id, os.soc_end, os.ended_at,
         (SELECT min(n.started_at) FROM ocpp_sessions n
           WHERE n.sim_run_id = os.sim_run_id AND n.vehicle_id = os.vehicle_id AND n.started_at >= os.ended_at) AS again_at
    FROM ocpp_sessions os
   WHERE os.sim_run_id = '7435e685-0140-47f7-a15e-3d441fd2bbc6' AND os.status = 'faulted')
SELECT count(*) AS cuts, count(again_at) AS charged_again,
       round(avg(extract(epoch FROM (again_at - ended_at)) / 60.0), 1) AS mean_min,
       round(max(extract(epoch FROM (again_at - ended_at)) / 60.0), 1) AS longest_min
  FROM cut;

-- (2), (3) the grades by the model that answered; count the runs behind a rate (0339)
SELECT model_answered, count(*) AS directives, count(DISTINCT pass_id) AS passes, count(DISTINCT sim_run_id) AS runs,
       sum(claims) AS claims, count(*) FILTER (WHERE verdict = 'consistent') AS consistent,
       count(*) FILTER (WHERE verdict = 'contradicted') AS contradicted,
       count(*) FILTER (WHERE verdict = 'no_claim') AS no_claim
  FROM public.ottoq_agent_directive_grades
 WHERE depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 2 DESC;

-- (3) each contradicted directive beside what its brief said
SELECT g.pass_id, g.sim_run_id, g.model_answered, g.contradictions, g.directive
  FROM public.ottoq_agent_directive_grades g
 WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.verdict = 'contradicted'
 ORDER BY g.pass_id, g.directive_no;
