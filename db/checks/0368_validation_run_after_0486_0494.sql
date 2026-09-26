-- 0368  **Validation run after 0486-0494: each fix's prediction, read live.**
--
--       One busy_day run on the twin depot (`11111111-…`), started from the twin cockpit's Control tab at 8x, with
--       0486-0494 in force. The canon had re-certified 9 of 9 under 0494 first. Every query takes the run as a psql
--       variable:
--
--           \set run '<sim_run_id>'
--
--       The predictions were written before the run was started. Results are recorded under each query.
--
--       THE RUN: `394e1e83-f835-44a1-9c9f-7921c44af8c5`, busy_day at the twin depot, seed 2336095663689336323, started
--       from the twin cockpit's Control tab at 19:45:47 UTC (2:45 PM CT) at 8x and stopped from it at 20:14:54 UTC
--       (3:14 PM CT): 450 ticks, sim 8:00-11:52 AM. 0486-0494 in force; 0496 (display only) was applied mid-run at
--       3:02 PM CT and 0495 after the stop. The predictions and the baseline were committed (c415b5f) before the start.
--
--       BEFORE, for comparison: every query below was also run on `461c79fa` (busy_day, twin depot, 0472-0484 in force,
--       324 ticks, sim 8:00-10:55 AM, the last operator run before 0486-0494) at 19:45 UTC, before the new run's start
--       purged it. Each result is recorded as `BEFORE 461c79fa` under its query.

-- ══ §1 G223 (0488): ONE GATE WRITER ON AN OPERATOR RUN ═══════════════════════════════════════════════════════════
--
--   0365 §1(c)'s live proof. 0488 fires the wave-admission edge function only while a production_live run is running,
--   so an operator demo run's gate has the kernel as its only writer, as every certified arm always had.
--   PREDICTED: no sim_tick_failed, and no gate-to-staged move outside the tick.

\echo '=== 0368 §1(a) — world ticks lost on the run ==='
SELECT count(*) AS failed_ticks, count(*) FILTER (WHERE e.payload->>'sqlstate' = '40P01') AS deadlocks
  FROM public.ottoq_events e
 WHERE e.sim_run_id = :'run' AND e.event_type = 'sim_tick_failed';
-- BEFORE 461c79fa: 3 failed ticks, all 3 deadlocks (0365 §1(a)).
-- READ: 0 failed ticks, 0 deadlocks in 450. HELD: 0365 §1(c)'s live proof of 0488.

\echo '=== 0368 §1(b) — gate-to-staged moves that share no transaction with the tick ==='
WITH moves AS (
  SELECT e.sim_run_id, e.recorded_at, e.entity_id
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'from' = 'arrived_at_gate'
     AND e.payload->'diff'->'current_state'->>'to'   = 'staged_awaiting_service'),
tx AS (
  SELECT m.*, EXISTS (SELECT 1 FROM public.ottoq_events o
                       WHERE o.sim_run_id = m.sim_run_id AND o.recorded_at = m.recorded_at
                         AND o.event_type NOT IN ('vehicle.state_changed','rule.evaluated_pass','rule.evaluated_fail','rule.evaluated')) AS with_tick
    FROM moves m)
SELECT count(*) AS gate_to_staged, count(*) FILTER (WHERE NOT with_tick) AS out_of_band FROM tx;
-- BEFORE 461c79fa: 33 of 51 out of band (0365 §1(b)).
-- READ: 8 gate-to-staged moves, 0 out of band. HELD: the kernel is the gate's only writer on an operator run.

-- ══ §2 G220 (0492): A SWEPT SESSION ENDS ON ITS RUN'S CLOCK ══════════════════════════════════════════════════════
--
--   0366 §2's live proof. PREDICTED: every session the orphan sweep ends on this run ends on the run's clock.

\echo '=== 0368 §2 — twin sessions the sweep ended on the run, and how many ended off its clock ==='
SELECT count(*) AS swept,
       count(*) FILTER (WHERE o.ended_at > r.sim_clock_current + interval '1 minute'
                           OR o.ended_at < o.started_at) AS ended_off_the_run_clock
  FROM public.ocpp_sessions o
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = o.sim_run_id
 WHERE o.sim_run_id = :'run' AND o.stopped_reason = 'vehicle_departed_orphan_sweep';
-- BEFORE 461c79fa: 2 swept, 0 off the run's clock. Not evidence either way: on that run the sim clock (sim 8:00-10:55
--   AM CDT) ran within two hours of the wall clock, so a wall-clock end fell inside the window this query accepts.
--   On a run started this afternoon the sim clock is hours behind the wall clock, so a wall-clock end shows.
-- READ: 0 swept. The orphan sweep did not fire on this run, so 0492 was not exercised live; carried to the next run.

-- ══ §3 G226 (0493, 0494): A REFUSED CHARGE BOOKS NOTHING, AND THE PROPOSER OFFERS ONLY A CHARGER THE GATE ACCEPTS ═══
--
--   PREDICTED: no begin_charge the gate refused is logged enacted (0493); every refusal of (3)'s own begin_charge is
--   logged `charger_refused`; and refusals are few, because the proposer no longer offers a charger promised to another
--   car (0494). On the canon under 0494 the 12-tick busy_day arms refused 3 and 6 (70 and 131 under 0493). What is left
--   is a charger that changed between the proposal and the gate in the same tick.

\echo '=== 0368 §3 — (3)''s own begin_charge: issued, refused at the gate, logged enacted anyway, logged charger_refused ==='
SELECT count(*) AS decide_begin_charge,
       count(*) FILTER (WHERE c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused') AS refused_at_gate,
       count(*) FILTER (WHERE c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused'
                          AND EXISTS (SELECT 1 FROM public.ottoq_decisions d
                                       WHERE d.sim_run_id = c.sim_run_id AND d.entity_id = c.vehicle_id AND d.sim_clock = c.issued_at
                                         AND d.resolved_action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
                                         AND d.enacted_action->>'stall_id' = c.payload->>'stall_id')) AS refused_logged_enacted,
       (SELECT count(*) FROM public.ottoq_decisions d WHERE d.sim_run_id = :'run' AND d.resolved_action_context = 'stall_assignment'
           AND d.enacted_action->>'verb' = 'charger_refused') AS logged_charger_refused,
       count(DISTINCT c.vehicle_id) FILTER (WHERE c.status = 'executed') AS cars_charged,
       string_agg(DISTINCT c.reason_code, ', ') FILTER (WHERE c.status = 'refused') AS refusal_codes
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.command_type = 'begin_charge' AND NOT (c.payload ? 'reroute_reason');
-- BEFORE 461c79fa: 75 issued, 5 refused at the gate (target_occupied, superseded), 5 logged enacted (0367 §1(a)),
--   65 cars charged.
-- READ: 119 issued, 24 refused at the gate, 0 logged enacted, 24 logged `charger_refused`, 79 cars charged, every
--   refusal `target_occupied`. 0493 HELD (5 of 5 refusals were logged enacted before). The prediction that refusals
--   are few did NOT hold as stated: 24 of 119, 20%, against 3-8 of 90-174 per canon arm. §10 is why, and 0495 is the fix.

-- ══ §4 G210 (0493): (3) AND (3b) SPLIT THE CARS AT THE GATE BY ONE RULE ═══════════════════════════════════════════
--
--   PREDICTED: no tick in which the charge step and the gate intake both command one car. Pairs of other kinds may
--   remain: a refusal and the reactor's reroute in one tick is the reactor working, and the appointment planner's own
--   pairs are open (§8).

\echo '=== 0368 §4 — ticks in which one car got two stall commands, by the two commands'' reasons ==='
WITH c AS (
  SELECT vc.vehicle_id, vc.issued_at, vc.status,
         vc.command_type || ':' || COALESCE(vc.payload->>'reason', CASE WHEN vc.payload ? 'reroute_reason' THEN 'reroute'
                                                                       WHEN vc.payload ? 'appointment' THEN 'planner' END,
                                            '(none)') AS reason
    FROM public.ottoq_vehicle_commands vc
   WHERE vc.sim_run_id = :'run' AND vc.payload ? 'stall_id'),
multi AS (SELECT vehicle_id, issued_at, array_agg(reason || ':' || status ORDER BY reason, status) AS pair
            FROM c GROUP BY 1, 2 HAVING count(*) > 1)
SELECT pair, count(*) AS ticks FROM multi GROUP BY 1 ORDER BY 2 DESC;
-- BEFORE 461c79fa: 4 ticks. {begin_charge:(none):refused, proceed_to_stall:gate_intake:executed} 1 (G210),
--   {begin_charge:(none):refused, begin_charge:reroute:executed} 1, {stage:planner:refused, stage:reroute:executed} 1,
--   {enter_wash:needs_card_detail:refused, proceed_to_stall:(none):executed} 1.
-- READ: 8 ticks, none of them a charge and a gate intake (G210 HELD):
--   {stage:planner:refused, stage:reroute:executed}                       4   the planner's stage, then the reactor
--   {begin_charge:(none):refused, begin_charge:reroute:executed}          3   a refusal and its reroute in one pass
--   {proceed_to_stall:planner:refused, proceed_to_stall:reroute:refused}  1   the planner, and a reroute that failed too

-- ══ §5 G195, THE PART 0493 REMOVES: A CHARGING CAR HOLDS NO OTHER CHARGER ═══════════════════════════════════════
--
--   PREDICTED: at every reading, no car with an active charging session holds a held or active charge booking on a
--   different charger. The staging half of G195 is open and is read as a census (0362 §8's query).

\echo '=== 0368 §5(a) — cars charging on one charger that hold a charge booking on another ==='
SELECT count(*) AS cars, string_agg(left(o.vehicle_id::text, 8) || ' on ' || so.stall_type || ', holds ' || sb.stall_type
                                    || ' ' || b.state, ' | ') AS detail
  FROM public.ocpp_sessions o
  JOIN public.stalls so ON so.id = o.stall_id
  JOIN public.ottoq_stall_bookings b ON b.sim_run_id = o.sim_run_id AND b.vehicle_id = o.vehicle_id
                                    AND b.state IN ('held','active') AND b.stall_id <> o.stall_id
  JOIN public.stalls sb ON sb.id = b.stall_id AND sb.stall_type IN ('dcfc','l2')
 WHERE o.sim_run_id = :'run' AND o.status = 'active';
-- BEFORE 461c79fa: 0 at the stop (a stopped run has no active session, so this is read live).
-- READ, live: 0 at sim 8:07, 8:29, 9:11 and 11:50 AM (18 to 35 active sessions each time). HELD.

\echo '=== 0368 §5(b) — active bookings whose car is elsewhere, by stall type and purpose, with stall-minutes left ==='
WITH clk AS (SELECT sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run')
SELECT s.stall_type, b.purpose, count(*) AS leaked,
       round(sum(GREATEST(0, EXTRACT(EPOCH FROM (upper(b.during) - clk.t)) / 60.0))) AS stall_minutes_left
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
  JOIN public.vehicles v ON v.id = b.vehicle_id
  CROSS JOIN clk
 WHERE b.sim_run_id = :'run' AND b.state = 'active' AND v.current_stall_id IS DISTINCT FROM b.stall_id
 GROUP BY 1, 2 ORDER BY 3 DESC;
-- READ: not read on this run. The stop relabels live bookings, so this census has to be taken live, and it was not.

-- ══ §6 HW.006 AT THE CHARGE CLOSE (0427, 0489) ═════════════════════════════════════════════════════════════════
--
--   0489 made the completion probe judge the stall its caller names. PREDICTED: HW.006 at a charge close fails only
--   where the stall's pointer really does not record the car (G157's untethered L2 closes), never on a stall the car did
--   not charge on.

\echo '=== 0368 §6 — HW.006 at task_completion on charge closes, by stall type ==='
SELECT s.stall_type, count(*) FILTER (WHERE e.passed) AS passed, count(*) FILTER (WHERE NOT e.passed) AS failed,
       count(*) FILTER (WHERE NOT e.passed AND EXISTS (
         SELECT 1 FROM public.ocpp_sessions o WHERE o.sim_run_id = e.sim_run_id AND o.vehicle_id = e.entity_id
            AND o.stall_id = (e.context->>'stall_id')::uuid)) AS failed_on_its_own_charger
  FROM public.ottoq_rule_evaluations e
  LEFT JOIN public.stalls s ON s.id = (e.context->>'stall_id')::uuid
 WHERE e.sim_run_id = :'run' AND e.rule_code = 'HW.006.physical_presence_verification'
   AND e.action_context = 'task_completion' AND e.context->>'svc' = 'charge'
 GROUP BY 1 ORDER BY 1;
-- BEFORE 461c79fa (before 0489): dcfc 8 passed / 0 failed, l2 5 / 8, no stall resolved 14 / 0.
-- READ: dcfc 28 passed / 0 failed, l2 34 / 0, every close resolved to a stall. HELD. G157's untethered L2 case (the
--   pointer emptied before the close) did not occur on this run; 0 is an observation, not a proof that it cannot.

-- ══ §7 G219 (0486): THE BATTERY DRAINS WHILE THE CAR IS OUT, AND OTTO-Q RE-READS THE NEED ═══════════════════════
--
--   0486 drains a deployed car each tick at the scenario's rate and removes the one-step drop at the gate, so the
--   dispatch ledger and the car agree when it arrives (on 461c79fa the gate read 33.4 points below the ledger), and the
--   re-assessment re-derives a visit whose charge need the drain has changed.
--   PREDICTED: (a) ledger against gate within about a point on every return; (b) no single SoC step while out larger
--   than one tick's drain; (c) need_reassessed events on the run.

\echo '=== 0368 §7(a) — the dispatch ledger''s SoC at return against the car''s last recorded SoC at or before the gate ==='
-- The first version of this query (0363 §4a's) read the gate SoC from the arrival event's `current_soc` diff. That
-- premise is exactly what 0486 removed: with the drain drawn en route, the SoC does not change at the gate, the diff
-- carries no `current_soc`, and the query saw 2 of 121 returns. This one reads the car's last recorded SoC at or
-- before the gate, whichever event wrote it.
WITH x AS (
  SELECT dd.soc_at_return_pct,
         (SELECT e.payload FROM public.ottoq_events e
           WHERE e.sim_run_id = dd.sim_run_id AND e.entity_id = dd.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload#>>'{diff,current_state,to}' = 'arrived_at_gate' AND e.sim_clock_at = dd.actual_return_at LIMIT 1) AS gate_ev,
         (SELECT (e.payload#>>'{diff,current_soc,to}')::numeric FROM public.ottoq_events e
           WHERE e.sim_run_id = dd.sim_run_id AND e.entity_id = dd.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload#>'{diff,current_soc}' IS NOT NULL AND e.sim_clock_at <= dd.actual_return_at
           ORDER BY e.sim_clock_at DESC LIMIT 1) AS car_soc
    FROM public.ottoq_vehicle_dispatches dd WHERE dd.sim_run_id = :'run' AND dd.status = 'completed')
SELECT count(*) AS completed, count(*) FILTER (WHERE gate_ev IS NOT NULL) AS with_gate_event,
       count(*) FILTER (WHERE gate_ev->'diff' ? 'current_soc') AS soc_moved_at_the_gate,
       round(avg(soc_at_return_pct - car_soc), 2) AS avg_gap, round(min(soc_at_return_pct - car_soc), 2) AS min_gap,
       round(max(soc_at_return_pct - car_soc), 2) AS max_gap, count(*) FILTER (WHERE abs(soc_at_return_pct - car_soc) > 1) AS gaps_over_1pt
  FROM x;
-- BEFORE 461c79fa: 88 completed dispatches, ledger 79% against gate 46%, gap 33.4 (32.9-33.8) (0363 §4a).
-- READ: 121 completed, 121 with a gate event, the SoC moved at the gate on 2. Ledger against the car: mean -0.10,
--   -0.5 to +0.5, none over 1 point. HELD: the ledger, the car and the gate agree.

\echo '=== 0368 §7(b) — each SoC step while a car was out, and the step at the gate ==='
WITH d AS (
  SELECT d.vehicle_id, d.dispatched_at, COALESCE(d.actual_return_at, r.sim_clock_current) AS until_at
    FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
   WHERE d.sim_run_id = :'run'),
steps AS (
  SELECT (e.payload#>>'{diff,current_soc,from}')::numeric - (e.payload#>>'{diff,current_soc,to}')::numeric AS drop_pts,
         e.payload#>>'{diff,current_state,to}' AS to_state
    FROM d JOIN public.ottoq_events e ON e.sim_run_id = :'run' AND e.entity_id = d.vehicle_id
                                    AND e.event_type = 'vehicle.state_changed'
                                    AND e.sim_clock_at > d.dispatched_at AND e.sim_clock_at <= d.until_at
                                    AND e.payload#>'{diff,current_soc}' IS NOT NULL)
SELECT count(*) AS soc_steps, round(avg(drop_pts), 2) AS avg_drop, max(drop_pts) AS max_drop,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY drop_pts) AS p95_drop,
       count(*) FILTER (WHERE to_state = 'arrived_at_gate') AS gate_steps,
       max(drop_pts) FILTER (WHERE to_state = 'arrived_at_gate') AS max_drop_at_gate
  FROM steps;
-- BEFORE 461c79fa: 2,025 SoC steps while out, mean 2.22 points, p95 3.8, max 34. 88 of them at the gate, max 34:
--   the arrival drain landing in one step (G219).
-- READ: 4,145 steps while out, mean 0.96 points, p95 1.0; 2 at the gate, max 1. The 13 steps over 2 points are all the
--   8:00 AM boot (offline -> staged_for_departure, 100 -> 86-97, the seed drawing each car's starting SoC), not drain.
--   HELD: the battery drains a point or so a tick while the car is out, and nothing lands at the gate.

\echo '=== 0368 §7(c) — needs re-derived on the run ==='
SELECT count(*) AS need_reassessed, count(DISTINCT e.entity_id) AS cars
  FROM public.ottoq_events e WHERE e.sim_run_id = :'run' AND e.event_type = 'ottoq.need_reassessed';
-- BEFORE 461c79fa: 0 (0486 not yet applied).
-- READ: 10 events on 10 cars. HELD: the re-read fires, once per car that needed it.

-- ══ §8 OPEN: THE APPOINTMENT PLANNER COMMANDS CARS STILL ON THE ROAD (0367 §4) ═════════════════════════════════════
--
--   Not fixed. Read so the next change has a live baseline.

\echo '=== 0368 §8 — the appointment planner''s commands by outcome ==='
SELECT c.command_type, c.status, COALESCE(c.reason_code, '-') AS reason_code, count(*) AS commands
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.payload ? 'appointment'
 GROUP BY 1, 2, 3 ORDER BY 4 DESC;
-- BEFORE 461c79fa: stage executed 59, proceed_to_stall refused vehicle_state_incompatible 13, proceed_to_stall
--   refused target_occupied 5, stage refused target_occupied 3, proceed_to_stall expired run_ended 1.
-- READ: stage executed 78, proceed_to_stall refused vehicle_state_incompatible 20, proceed_to_stall refused
--   target_occupied 14, stage refused target_occupied 7. Still open: 20 commands to cars not yet at the depot.

-- ══ §9 THE FIVE KPIs ═══════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0368 §9 — the five canonical KPIs for the run ==='
SELECT public.ottoq_kpi_five(:'run'::uuid);
-- READ (run key: busy_day, seed 2336095663689336323, policy otto_q, engine_hash 1b29a4e5..., config_hash 333ec7f8...):
--   asset_hours_available_per_day 93.81 · service_point_turns_per_point_per_day 2.65 · peak_site_kw 1,194.0
--   (demand 1,077.1) · touch_events_per_turn 0.000 · p95_time_to_service 0.7 min (p50 0.4) · returns_unserved 1.
--   KPI 5 is right by its definition (recall complete to FIRST operation active) and blind to what this run was about:
--   the first operation is usually a digital or cabin task that starts at once, while the charge the car came in for
--   waited up to 162 minutes (§11, p95). A busy day's queue needs a companion number, time to the first charge.

-- ══ §10 FOUND ON THE RUN: WHERE THE REMAINING REFUSALS COME FROM (0495) ═════════════════════════════════════════
--
--   Not predicted. Every refusal of (3)'s own begin_charge, by the proposer whose stall it carried (matched on stall).

\echo '=== 0368 §10 — refused begin_charge by the proposal it came from ==='
SELECT COALESCE(src.engine, '(no matching decision)') AS engine, count(*) AS refused,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands x WHERE x.sim_run_id = c.sim_run_id
                                         AND x.vehicle_id = c.vehicle_id AND x.command_type = 'begin_charge'
                                         AND x.payload ? 'reroute_reason' AND x.status = 'executed'
                                         AND x.issued_at BETWEEN c.issued_at AND c.issued_at + interval '1 minute')) AS rerouted_same_pass
  FROM public.ottoq_vehicle_commands c
  LEFT JOIN LATERAL (
    SELECT COALESCE(d.proposed_action->>'l2_engine', d.proposed_action->'rationale'->>'optimizer', 'per_car_proposer') AS engine
      FROM public.ottoq_decisions d
     WHERE d.sim_run_id = c.sim_run_id AND d.entity_id = c.vehicle_id AND d.sim_clock = c.issued_at
       AND d.resolved_action_context = 'stall_assignment' AND d.proposed_action->>'stall_id' = c.payload->>'stall_id'
     LIMIT 1) src ON true
 WHERE c.sim_run_id = :'run' AND c.command_type = 'begin_charge' AND c.status = 'refused'
   AND c.confirmed_by = 'otto_q_preflight' AND NOT (c.payload ? 'reroute_reason')
 GROUP BY 1 ORDER BY 2 DESC;
-- READ: greedy_constrained 21 (3 rerouted and charged in the same pass), forward_lex 3 (0), the per-car proposer 0.
--   So 0494 held where it applies, and 21 of 24 refusals came from the kernel's own greedy optimizer
--   (`ottoq_l2_optimize_assignments`), which picks by pointer and which the charge step honours before the per-car
--   proposer. The same is true of every refusal on the canon under 0494 (3, 3, 3, 6, 7 and 8 per arm, all greedy).
--   0495 gives it the gate's check. Probe (rolled back, on this run after the stop, at sim 11:52:11 AM; the tail and
--   the migration body as filed, verbatim below):
--     car A=00cc3d0a, promised to B: 0c916ac0 (dcfc)
--     OLD  pick after the promise: 0c916ac0 (gate ok=false), tick: refused target_occupied on 0c916ac0
--     NEW  pick after the promise: 3a7310ac (gate ok=true),  tick: issued on 3a7310ac
--   0495 = 20260926201658 (3:16 PM CT), stored statement md5 357e8310..., equal to the file's body; forces_recert TRUE.
--   The 3 `forward_lex` refusals are CP-SAT's, an external proposer the gate is right to refuse. That CP-SAT proposed
--   a promised charger at all suggests the frame it solves over does not carry the calendar's forward holds; not
--   measured here.
--
--   The probe as run:
--   DO $probe_old$
--   DECLARE
--     v_run   uuid := '394e1e83-f835-44a1-9c9f-7921c44af8c5';
--     v_depot uuid := '11111111-1111-1111-1111-111111111111';
--     v_clock timestamptz;
--     v_cars  uuid[]; a uuid; b uuid;
--     v_s1 uuid; v_s2 uuid; v_t1 text; v_ok2 text; r_old_tick text;
--   BEGIN
--     SELECT sim_clock_current INTO v_clock FROM ottoq_sim_runs WHERE sim_run_id = v_run;
--     -- the optimizer and the decide tick find their run by status, so the stopped run is the depot's running run here
--     UPDATE ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
--     -- a clean depot at the run's last clock: every charger Available and answering, no car on or reserving one, nobody
--     -- else at the gate, no booking of the run's on a charger and no pending proposal, so only the probe's booking promises one
--     UPDATE ottoq_ocpp_chargers c SET station_state = 'Available', last_heartbeat_at = v_clock
--       FROM stalls s WHERE s.ocpp_charger_id = c.charger_id AND s.depot_id = v_depot;
--     UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL, status = 'available'
--      WHERE depot_id = v_depot AND stall_type IN ('l2','dcfc');
--     UPDATE vehicles SET current_state = 'staged_for_departure', current_stall_id = NULL
--      WHERE home_depot_id = v_depot AND current_state = 'arrived_at_gate';
--     DELETE FROM ottoq_stall_bookings b USING stalls s
--      WHERE b.sim_run_id = v_run AND s.id = b.stall_id AND s.stall_type IN ('l2','dcfc');
--     DELETE FROM ottoq_external_proposals WHERE sim_run_id = v_run AND status = 'pending';
--
--     SELECT array_agg(id ORDER BY id) INTO v_cars
--       FROM (SELECT id FROM vehicles WHERE home_depot_id = v_depot AND category = 'autonomous' ORDER BY id LIMIT 2) x;
--     a := v_cars[1]; b := v_cars[2];
--     UPDATE vehicles SET current_state = 'arrived_at_gate', current_stall_id = NULL, current_soc = 20 WHERE id = a;
--
--     -- the live body: the optimizer's pick for A, then its pick once B is promised that charger, and the tick that follows
--     PERFORM public.ottoq_l2_optimize_assignments(v_run, v_depot, v_clock);
--     SELECT (p.proposal->>'stall_id')::uuid, p.proposal->>'stall_type' INTO v_s1, v_t1
--       FROM ottoq_external_proposals p WHERE p.sim_run_id = v_run AND p.source = 'greedy_constrained' AND p.entity_id = a;
--     PERFORM ottoq.ottoq_book_stall(v_run, v_s1, b, 'charge_' || v_t1, v_clock - interval '25 minutes',
--                                    v_clock + interval '30 minutes', NULL, NULL, 'otto_q');
--     BEGIN
--       PERFORM public.ottoq_l2_optimize_assignments(v_run, v_depot, v_clock);
--       SELECT (p.proposal->>'stall_id')::uuid INTO v_s2
--         FROM ottoq_external_proposals p WHERE p.sim_run_id = v_run AND p.source = 'greedy_constrained' AND p.entity_id = a;
--       v_ok2 := COALESCE(ottoq.ottoq_validate_assignment(a, v_s2, 'begin_charge', v_clock, v_run)->>'ok', 'n/a');
--       PERFORM public.ottoq_decide_tick(v_run);
--       SELECT string_agg(c.status || COALESCE(' ' || c.reason_code, '') || ' on ' || left(c.payload->>'stall_id', 8)
--                         || CASE WHEN c.payload ? 'reroute_reason' THEN ' (reroute)' ELSE '' END, ', ' ORDER BY c.created_at)
--         INTO r_old_tick FROM ottoq_vehicle_commands c
--        WHERE c.sim_run_id = v_run AND c.vehicle_id = a AND c.command_type = 'begin_charge' AND c.issued_at = v_clock;
--       RAISE EXCEPTION 'probe0495_old_rolled_back';
--     EXCEPTION WHEN OTHERS THEN
--       IF SQLERRM <> 'probe0495_old_rolled_back' THEN RAISE; END IF;
--     END;
--     PERFORM set_config('probe0495.a', a::text, true);
--     PERFORM set_config('probe0495.old', format('car A=%s, promised to B: %s (%s) | OLD pick after the promise: %s (gate ok=%s), tick: %s',
--         left(a::text, 8), left(v_s1::text, 8), v_t1, left(v_s2::text, 8), v_ok2, COALESCE(r_old_tick, 'no begin_charge')), true);
--   END $probe_old$;
--
--   -- (here, in the same transaction: 0495's body as filed, without its P0 guard)
--
--   DO $probe_new$
--   DECLARE
--     v_run   uuid := '394e1e83-f835-44a1-9c9f-7921c44af8c5';
--     v_depot uuid := '11111111-1111-1111-1111-111111111111';
--     v_clock timestamptz;
--     a uuid := current_setting('probe0495.a')::uuid;
--     v_s3 uuid; v_ok3 text; r_new_tick text;
--   BEGIN
--     SELECT sim_clock_current INTO v_clock FROM ottoq_sim_runs WHERE sim_run_id = v_run;
--     PERFORM public.ottoq_l2_optimize_assignments(v_run, v_depot, v_clock);
--     SELECT (p.proposal->>'stall_id')::uuid INTO v_s3
--       FROM ottoq_external_proposals p WHERE p.sim_run_id = v_run AND p.source = 'greedy_constrained' AND p.entity_id = a;
--     v_ok3 := COALESCE(ottoq.ottoq_validate_assignment(a, v_s3, 'begin_charge', v_clock, v_run)->>'ok', 'n/a');
--     PERFORM public.ottoq_decide_tick(v_run);
--     SELECT string_agg(c.status || COALESCE(' ' || c.reason_code, '') || ' on ' || left(c.payload->>'stall_id', 8)
--                       || CASE WHEN c.payload ? 'reroute_reason' THEN ' (reroute)' ELSE '' END, ', ' ORDER BY c.created_at)
--       INTO r_new_tick FROM ottoq_vehicle_commands c
--      WHERE c.sim_run_id = v_run AND c.vehicle_id = a AND c.command_type = 'begin_charge' AND c.issued_at = v_clock;
--     RAISE EXCEPTION E'PROBE0495 clock=%\n %\n NEW pick after the promise: % (gate ok=%), tick: %',
--       v_clock, current_setting('probe0495.old'), left(v_s3::text, 8), v_ok3, COALESCE(r_new_tick, 'no begin_charge');
--   END $probe_new$;

-- ══ §11 FOUND ON THE RUN: CARS WAITING FOR A CHARGER, AND THE HOLDS UNDER THEM ═══════════════════════════════════
--
--   Not predicted. A charge-waiting arrival keeps state `arrived_at_gate` so the charge step retries it every tick, and
--   the congestion fallback parks it in a staging stall. The question is whether the calendar knows it is there.

\echo '=== 0368 §11(a) — cars at the gate by sim time (every 15 sim-minutes), and how long each of them waited there ==='
WITH r AS (SELECT sim_run_id, sim_clock_start, sim_clock_current FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
ev AS (
  SELECT e.entity_id, e.sim_clock_at, e.payload#>>'{diff,current_state,from}' AS s_from, e.payload#>>'{diff,current_state,to}' AS s_to
    FROM public.ottoq_events e, r
   WHERE e.sim_run_id = r.sim_run_id AND e.event_type = 'vehicle.state_changed' AND e.payload#>'{diff,current_state}' IS NOT NULL),
stay AS (
  SELECT a.entity_id, a.sim_clock_at AS at_gate,
         (SELECT min(x.sim_clock_at) FROM ev x WHERE x.entity_id = a.entity_id AND x.s_from = 'arrived_at_gate'
             AND x.sim_clock_at >= a.sim_clock_at) AS left_at
    FROM ev a WHERE a.s_to = 'arrived_at_gate'),
grid AS (SELECT generate_series(r.sim_clock_start, r.sim_clock_current, interval '15 minutes') AS t FROM r)
SELECT to_char(g.t AT TIME ZONE 'America/Chicago', 'HH24:MI') AS sim_ct,
       count(l.*) FILTER (WHERE l.at_gate <= g.t AND (l.left_at IS NULL OR l.left_at > g.t)) AS at_gate,
       round(avg(EXTRACT(EPOCH FROM (COALESCE(l.left_at, (SELECT sim_clock_current FROM r)) - l.at_gate)) / 60)
             FILTER (WHERE l.at_gate <= g.t AND (l.left_at IS NULL OR l.left_at > g.t))) AS their_mean_gate_minutes
  FROM grid g CROSS JOIN stay l
 GROUP BY g.t ORDER BY g.t;
-- READ, after the stop (a car still waiting at the stop has its stay ended by the stop, so its minutes are a floor):
--   08:00 16 (4 min, the boot cohort) · 08:30 4 · 09:00 8 · 09:30 22 · 10:00 42 · 10:30 42 · 11:00 41 · 11:30 39,
--   the cars present at 09:30-11:30 spending a mean 127-130 minutes there. 137 gate arrivals; the median waited 4
--   minutes, the 95th percentile 162. From 10:00 the depot held about 40 cars waiting for a charger at all times.

\echo '=== 0368 §11(b) — at one moment: where the cars at the gate are, and the last booking on the stall each occupies ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
g AS (SELECT v.id, v.current_stall_id FROM public.vehicles v
       WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
         AND v.current_state = 'arrived_at_gate'),
lastb AS (
  SELECT g.id, g.current_stall_id, b.state, b.purpose, b.release_reason, lower(b.during) AS b_from, upper(b.during) AS b_to
    FROM g CROSS JOIN r
    LEFT JOIN LATERAL (SELECT * FROM public.ottoq_stall_bookings b WHERE b.sim_run_id = r.run AND b.vehicle_id = g.id
                          AND b.stall_id = g.current_stall_id ORDER BY lower(b.during) DESC LIMIT 1) b ON true)
SELECT CASE WHEN current_stall_id IS NULL THEN '(no stall)' ELSE COALESCE(state || ' / ' || purpose || ' / '
            || COALESCE(release_reason, '-'), '(no booking on its stall)') END AS last_booking_on_its_stall,
       count(*) AS cars, round(avg(EXTRACT(EPOCH FROM (b_to - b_from)) / 60)) AS avg_window_min,
       round(avg(EXTRACT(EPOCH FROM ((SELECT t FROM r) - b_to)) / 60)) AS avg_min_past_window
  FROM lastb GROUP BY 1 ORDER BY 2 DESC;
-- READ, live at sim 10:37 AM: 42 cars at the gate, every one with an open charge atom, mean SoC 50%, and all 42
--   parked in a staging stall whose pointer names the car (0 physically at the gate). The last booking on that stall:
--     done / temp_hold / window_elapsed_occupied   38 cars, a 17-minute window that ended a mean 54 minutes before
--     active / perimeter_hold                        2 cars (120-minute window)
--     active / temp_hold                             2 cars (12-minute window, 7 minutes left)
--   So for 38 of 42 waiting cars the calendar shows the stall free while the pointer holds it. The pointer gate still
--   refuses any command to those stalls, so nothing is double-parked; what the calendar gets wrong is its own
--   availability, which every calendar reader (the planner's forward bookings, the cockpits' held/free counts) takes
--   as true. `window_elapsed_occupied` is the overstay by design (G81); a car parked to wait for a charger with a
--   17-minute hold is an overstay by construction.
-- READ, live at sim 11:50 AM: 35 at the gate, all in a staging stall. done / temp_hold / window_elapsed_occupied 31
--   (a 12-minute window, a mean 107 minutes past it), done / perimeter_hold / window_elapsed_occupied 2 (120-minute
--   window, 29 past), active perimeter_hold 1, active temp_hold 1. 33 of 35 on a lapsed hold.

-- ══ §12 THE COCKPITS ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The twin cockpit (ottoyarddepot-sim#110's head on :8080), PULSE and OrchestrAV (their PR heads on :8081 and :8082,
--   each through its local live-harness page), all on this run.
--   - Start, from Control (scenario picker, Start, speed 8x): it posted `scenarios/start` and then the playback speed,
--     with no resume call and no 409, the first live use of #110's change. Stop, from Control: the run ended at 3:14 PM
--     CT and the cockpit landed on Runs, the run first (3h 52m sim, 450 ticks, 129 dispatches, 98 charges, 7 faults).
--   - 2D and 3D, sim 8:39-8:58 AM: 71-75 cars drawn over 80 two-second samples, at most 1 stationary over 10 s at once.
--   - Intelligence at sim 9:39-9:40: the Decisions stream in words (dispatch, agent pass with CP-SAT's receipt, holds
--     since a time); Layers: L1 11,694 evaluations, 2 refused (both SLA.004), 2 failed. Its run card read "running ·
--     1x" on a run at 8x: `ottoq_intelligence_stack` reported `demo_speed_x`, which the speed slider never writes
--     (1.0 on this run and on 461c79fa). 0496 (20260926200223, 3:02 PM CT, display only, forces_recert FALSE) reads
--     the playback speed the way the metronome paces the run; the stack then reported 8.0 on this run.
--   - The Runs tab prints every seed rounded: 2336095663689336323 as 2336095663689336300, 5753109525808485125 as
--     5753109525808485000. A 64-bit seed crosses the wire as a JSON number and the browser parses it as a double.
--     0497 sends it as text from the four read functions that carry it (the boot manifest's stored boot draw
--     included); the cockpits type it `number | string` (ottoyarddepot-sim#110 060b942, which also adds the exact
--     `seed_text` to the channel contract, 1.1.0; ottoyard-field-ops#16 f239330; ottoyard-OTTO-Q#22 c9cd607).
--   - The 2D map's "Q" badge read 0 all run. It counts a status of the old client engine that twin mode never sets.
--     It happens to be right today (§11: no car stood at the gate), but it is not measuring anything. Removed in
--     ottoyarddepot-sim#110 (4f61045) with the 3D view's "Live Depot Status" and "Power" panels, which read a KPI
--     store nothing has written since the client engine went (0% uptime, 0 waiting and 0 kW on a live run).
--   - PULSE, sim 9:09-9:14 AM, and OrchestrAV, sim 9:12 AM: the same run, tick and sim clock as the twin. PULSE: 116
--     vehicles; 2 with two active stall reservations at once (Tesla-AV-064, Waymo-AV-028); Tesla-AV-042's card read
--     "Next: Inspect at 8:02 AM" at 9:10 while the car charged. The plan put the 3-minute inspection at 8:02, inside a
--     69-minute L2 charge, and it ran at 10:10. On the run 30 of 109 inspections were planned inside their car's
--     charge window and 6 of 109 started 30+ minutes after their planned time (p95 33 minutes late); software updates
--     planned inside a charge (55 of 133) are concurrent by design. OrchestrAV, viewing as Waymo: 46 cars (at the gate
--     7, queued 6, charging 15, service bay 1, off site 17), and the picker labelled them "46 on site"; fixed in
--     ottoyard-OTTO-Q#22 (48c1d1f) to "46 vehicles".

-- ══ §13 THE CANON UNDER 0495 ════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0368 §13 — (3)''s begin_charge issued / refused at the gate, and cars charged, under 0494 and under 0495 ==='
WITH cols AS (
  SELECT v.scenario, v.seed, v.ticks, v.verdict_id, v.arm_a_run AS run,
         CASE WHEN v.verdict_id BETWEEN 393 AND 401 THEN '0494' ELSE '0495' END AS body
    FROM public.ottoq_determinism_verdict_ledger v
   WHERE v.verdict_id BETWEEN 393 AND 401 OR v.certified_at > '2026-09-26 20:16:58+00'
)
SELECT c.scenario || '/' || c.seed || '/' || c.ticks AS col, c.body, c.verdict_id,
       count(*) FILTER (WHERE x.command_type = 'begin_charge' AND NOT (x.payload ? 'reroute_reason')) AS issued,
       count(*) FILTER (WHERE x.command_type = 'begin_charge' AND NOT (x.payload ? 'reroute_reason')
                          AND x.confirmed_by = 'otto_q_preflight' AND x.status = 'refused') AS refused_at_gate,
       count(DISTINCT x.vehicle_id) FILTER (WHERE x.command_type = 'begin_charge' AND x.status = 'executed') AS cars_charged
  FROM cols c JOIN public.ottoq_vehicle_commands x ON x.sim_run_id = c.run
 GROUP BY 1, 2, 3 ORDER BY 1, 2;
-- READ (20:44 UTC, 3:44 PM CT): the canon re-certified 9 of 9 under 0495, each column on its first attempt: verdicts
--   402-410, pairs started 20:17-20:35 UTC (3:17-3:35 PM CT), every one `passed` with no disagreeing atom. Arm A of
--   each, (3)'s begin_charge issued / refused at the gate, cars charged and kWh delivered, under 0494 -> under 0495:
--     grid_smoke/239001/6      3/0 ->   3/0    cars   2 ->   2    kWh     4 ->     4
--     grid_smoke/424242/6      2/0 ->   2/0    cars   2 ->   2    kWh    23 ->    23
--     busy_day/171717/12      90/3 ->  88/0    cars  87 ->  87    kWh 1,556 -> 1,554
--     busy_day/314159/12     100/6 ->  94/0    cars  91 ->  91    kWh 1,739 -> 1,749
--     busy_day/424242/12     104/7 ->  95/0    cars  93 ->  94    kWh 1,513 -> 1,513
--     normal_day/171717/12    90/3 ->  88/0    cars  87 ->  87    kWh 1,591 -> 1,600
--     busy_day/171717/24     104/3 -> 101/0    cars  89 ->  89    kWh 1,783 -> 1,790
--     busy_day/424242/24     115/8 -> 106/0    cars  96 ->  96    kWh 1,777 -> 1,770
--     busy_day/171717/48     174/3 -> 173/0    cars 109 -> 109    kWh 4,398 -> 4,488
--   No begin_charge of the charge step's own was refused at the gate on any arm, for the first time since the
--   refusals were counted (19-57 an arm under 0492, 27-131 under 0493, 3-8 under 0494). The same cars charged, one
--   more on busy_day/424242/12, on 1-9 fewer commands an arm, and the seven busy_day and normal_day columns delivered
--   14,464 kWh against 14,357 (+0.7%).
--
--   0497 (20260926204519, 3:45 PM CT, stored statement md5 0a627200..., equal to the file's body) was applied after the
--   sweep: display only, forces_recert FALSE. `ottoq_twin_run_list` then sent this run's seed as the string
--   "2336095663689336323".
