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
--       THE RUN: pending. This file was committed with its predictions before the run was started.
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
-- READ: pending the run.

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
-- READ: pending the run.

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
-- READ: pending the run.

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
-- READ: pending the run.

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
-- READ: pending the run.

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
-- READ: pending the run.

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
-- READ: pending the run.

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
-- READ: pending the run.

-- ══ §7 G219 (0486): THE BATTERY DRAINS WHILE THE CAR IS OUT, AND OTTO-Q RE-READS THE NEED ═══════════════════════
--
--   0486 drains a deployed car each tick at the scenario's rate and removes the one-step drop at the gate, so the
--   dispatch ledger and the car agree when it arrives (on 461c79fa the gate read 33.4 points below the ledger), and the
--   re-assessment re-derives a visit whose charge need the drain has changed.
--   PREDICTED: (a) ledger against gate within about a point on every return; (b) no single SoC step while out larger
--   than one tick's drain; (c) need_reassessed events on the run.

\echo '=== 0368 §7(a) — the dispatch ledger''s SoC at return against the SoC the car reached the gate with ==='
SELECT count(*) AS completed_dispatches, round(avg(d.soc_at_return_pct)) AS avg_ledger_soc_at_return,
       round(avg(g.gate_soc)) AS avg_gate_soc, round(avg(d.soc_at_return_pct - g.gate_soc), 1) AS avg_gap,
       round(min(d.soc_at_return_pct - g.gate_soc), 1) AS min_gap, round(max(d.soc_at_return_pct - g.gate_soc), 1) AS max_gap
  FROM public.ottoq_vehicle_dispatches d
  CROSS JOIN LATERAL (SELECT (e.payload#>>'{diff,current_soc,to}')::numeric AS gate_soc FROM public.ottoq_events e
                        WHERE e.sim_run_id = d.sim_run_id AND e.entity_id = d.vehicle_id AND e.event_type = 'vehicle.state_changed'
                          AND e.payload#>>'{diff,current_state,to}' = 'arrived_at_gate' AND e.sim_clock_at = d.actual_return_at
                        LIMIT 1) g
 WHERE d.sim_run_id = :'run' AND d.status = 'completed';
-- BEFORE 461c79fa: 88 completed dispatches, ledger 79% against gate 46%, gap 33.4 (32.9-33.8) (0363 §4a).
-- READ: pending the run.

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
-- READ: pending the run.

\echo '=== 0368 §7(c) — needs re-derived on the run ==='
SELECT count(*) AS need_reassessed, count(DISTINCT e.entity_id) AS cars
  FROM public.ottoq_events e WHERE e.sim_run_id = :'run' AND e.event_type = 'ottoq.need_reassessed';
-- BEFORE 461c79fa: 0 (0486 not yet applied).
-- READ: pending the run.

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
-- READ: pending the run.

-- ══ §9 THE FIVE KPIs ═══════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0368 §9 — the five canonical KPIs for the run ==='
SELECT public.ottoq_kpi_five(:'run'::uuid);
-- READ: pending the run.

-- ══ §10 THE COCKPITS ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   READ: pending the run.
