-- 0365  **0488-0490: the gate had two writers, the completion probe flipped a coin, and the refusal reactor rerouted a
--       plan the decide path had already replaced.**
--
--       Three findings from one morning (2026-09-26), each traced from a symptom to one function:
--         G223  operator runs lost 2-6 world ticks each to a deadlock, and most of their gate intake was not OTTO-Q's (0488)
--         G224  the canon's 48-tick column failed under 0487 on one HW.006 row decided by physical row order (0489)
--         G225  the booking tie behind G224 was made by the refusal reactor rerouting a stale refusal (0490)
--       Read-only queries below. Times are UTC in the data and CT (CDT, UTC-5) in the prose.

-- ══ §1 G223: THE WAVE-ADMISSION EDGE FUNCTION UNDER THE LIVE TICK (0488) ═══════════════════════════════════════════
--
--   `ottoq_cron_tick` (cron 10, every 2 minutes, only while a non-certification run is live) fired `ottoq-wave-admit`
--   with commit:true. The edge function flips cars from arrived_at_gate to staged_awaiting_service in one PostgREST
--   UPDATE: no stall, no booking, no step, no command, on the wall clock.
--
--   The deadlock, from the Postgres log (run 461c79fa, 13:56:11-12 UTC, read through the log API, not queryable here):
--   process 1455259 (postgrest, the vehicles UPDATE) waits on the run row held by 1456191, and 1456191 (pg_cron, the
--   metronome's world tick in `ottoq_sim_emit_depot_heartbeats`) waits on vehicle tuple (287,4) held by 1455259. The
--   edge function's state-change trigger probes the shield, whose rule-evaluation insert takes KEY SHARE on the run row.

\echo '=== 0365 §1(a) — world ticks lost, per operator run ==='
SELECT left(e.sim_run_id::text, 8) AS run, count(*) AS failed_ticks,
       count(*) FILTER (WHERE e.payload->>'sqlstate' = '40P01') AS deadlocks,
       count(*) FILTER (WHERE e.payload->>'half' = 'world') AS world_half,
       min(e.occurred_at) AS first_at, max(e.occurred_at) AS last_at,
       string_agg(DISTINCT to_char(e.occurred_at, 'SS'), ',') AS seconds_past_the_minute
  FROM public.ottoq_events e
 WHERE e.event_type = 'sim_tick_failed' AND e.occurred_at >= '2026-09-25'
 GROUP BY e.sim_run_id ORDER BY min(e.occurred_at) DESC;
-- READ (2026-09-26, 16:30 UTC): 461c79fa 3, 3dbe16db 3, 49c45bd4 6, 317d4331 5, 689095e2 2. Every one 40P01 in the
--   world half, every one 0-10 seconds past a minute, and cron 10 fires on the even minutes. None on a certification arm.

\echo '=== 0365 §1(b) — gate-to-staged moves that share no transaction with the tick ==='
-- A transaction's events share recorded_at (now()). A move whose transaction holds nothing but vehicle state changes
-- and rule evaluations was written outside the tick.
WITH moves AS (
  SELECT e.sim_run_id, e.recorded_at, e.entity_id
    FROM public.ottoq_events e
   WHERE e.sim_run_id IN (SELECT sim_run_id FROM public.ottoq_sim_runs
                           WHERE sim_run_id::text LIKE ANY (ARRAY['461c79fa%','3dbe16db%','49c45bd4%']))
     AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'from' = 'arrived_at_gate'
     AND e.payload->'diff'->'current_state'->>'to'   = 'staged_awaiting_service'),
tx AS (
  SELECT m.*, EXISTS (SELECT 1 FROM public.ottoq_events o
                       WHERE o.sim_run_id = m.sim_run_id AND o.recorded_at = m.recorded_at
                         AND o.event_type NOT IN ('vehicle.state_changed','rule.evaluated_pass','rule.evaluated_fail','rule.evaluated')) AS with_tick
    FROM moves m)
SELECT left(sim_run_id::text, 8) AS run, count(*) AS gate_to_staged, count(*) FILTER (WHERE NOT with_tick) AS out_of_band
  FROM tx GROUP BY sim_run_id ORDER BY 1;
-- READ (2026-09-26, 16:30 UTC): 3dbe16db 79 of 124, 461c79fa 33 of 51, 49c45bd4 59 of 86. On 461c79fa the kernel's 18
--   each came with a stall, a booking and a command; the edge function's 33 came with no stall (0 of 33). Counting the
--   same moves by SM.001's evaluations instead gives 76/121, 31/49, 54/81: the same split, a few moves the shield did
--   not judge.
--
--   Certification arms never saw either: `ottoq_cron_tick` returns early for cert_harness, so the canon's gate was the
--   kernel's alone while every operator run had a second writer.
--
--   0488 = 20260926160930 (11:09 AM CT), stored statement md5 34aef599..., equal to the file's body. The call now fires
--   only while a production_live run is running. forces_recert FALSE: the cron tick never runs for a certification arm.
--
--   §1(c) LIVE PROOF, PENDING the next operator run: re-run §1(a) and §1(b) on it. Expected: no sim_tick_failed, and
--   no out-of-band gate-to-staged move. Charge-needing arrivals then wait at the gate for a charger, as in every
--   certified arm (the edge function's moves had waited a mean 9.1 sim-minutes, max 15.4). Staging them in a real
--   stall is the open follow-up on G223.

-- ══ §2 G224: THE COMPLETION PROBE'S STALL WAS A COIN FLIP (0489) ═══════════════════════════════════════════════════

\echo '=== 0365 §2(a) — the 48-tick column, before and after the retry ==='
SELECT verdict_id, certified_at, scenario, seed, ticks, outcome, equal, disagreeing_atoms
  FROM public.ottoq_determinism_verdict_ledger
 WHERE verdict_id IN (364, 365) ORDER BY verdict_id;
-- READ (2026-09-26): 364 at 15:45:19 UTC (10:45 AM CT) failed on {events, rules}; 365 at 15:54:23 UTC, the runner's
--   retry on identical inputs, passed. Commands, decisions, bookings, energy, recalls and SDRs were equal in 364, so
--   both arms played the same world.

\echo '=== 0365 §2(b) — HW.006 at task_completion per arm, and the stall judged at car 0001''s last charge close ==='
WITH v AS (SELECT verdict_id, arm_a_run, arm_b_run FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id IN (364, 365))
SELECT v.verdict_id, CASE WHEN e.sim_run_id = v.arm_a_run THEN 'A' ELSE 'B' END AS arm,
       count(*) FILTER (WHERE NOT e.passed) AS failed, count(*) FILTER (WHERE e.passed) AS passed,
       string_agg(DISTINCT left(e.context->>'stall_id', 8), ',')
         FILTER (WHERE e.entity_id = 'a1111111-0001-0001-0001-000000000001' AND e.context->>'svc' = 'charge'
                   AND (e.context->>'ends_at')::timestamptz = '2026-09-02 00:30+00') AS car0001_last_close_stall
  FROM v JOIN public.ottoq_rule_evaluations e ON e.sim_run_id IN (v.arm_a_run, v.arm_b_run)
 WHERE e.rule_code = 'HW.006.physical_presence_verification' AND e.action_context = 'task_completion'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-26, 16:30 UTC):
--     364 A  11 failed, 497 passed, judged 3a7310ac (the DCFC it charged on: present, pass)
--     364 B  12 failed, 496 passed, judged fe18413d (an L2 it never charged on: "stall does not record this vehicle as
--            present", fail)
--     365 A  12 / 496, fe18413d        365 B  12 / 496, fe18413d
--   So 365 did not pass because the probe was right. It passed because both arms landed on the wrong stall and agreed
--   on a false failure. The flake and the false verdict are one defect.

\echo '=== 0365 §2(c) — the tie: two done charge bookings for car 0001 at the same instant ==='
WITH v AS (SELECT arm_a_run, arm_b_run FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id = 364)
SELECT CASE WHEN b.sim_run_id = v.arm_a_run THEN 'A' ELSE 'B' END AS arm, left(b.stall_id::text, 8) AS stall,
       s.stall_type, b.state, b.purpose, b.source, lower(b.during) AS starts, upper(b.during) AS ends
  FROM v JOIN public.ottoq_stall_bookings b ON b.sim_run_id IN (v.arm_a_run, v.arm_b_run)
  LEFT JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.vehicle_id = 'a1111111-0001-0001-0001-000000000001' AND b.need_atom = 'charge'
   AND b.state IN ('held','active','done','interrupted')
 ORDER BY arm, lower(b.during) DESC, b.stall_id;
-- READ (2026-09-26): in both arms, 3a7310ac dcfc done charge_dcfc otto_q_enacted 23:00-23:48 and fe18413d l2 done
--   charge_l2 otto_q_reaction 23:00-00:00 (sim, 2026-09-01). `ORDER BY (state IN ('held','active')) DESC,
--   lower(during) DESC LIMIT 1` cannot tell them apart, so the row that sits first wins, and the arms of one transaction
--   do not lay their rows down in the same physical order. The charge close, the caller, knew the stall all along:
--   `v_session.stall_id`. The L2 booking is G225's (§3).
--
--   0489 = 20260926161825 (11:18 AM CT), stored statement md5 6de05266..., equal to the file's body. forces_recert TRUE.
--
--   The probe as run (0489's body without P0 and a rolled-back tail, one transaction ending in RAISE), on 364's arm B:
--     six-argument probe (the visit-atom path, no stall)     5 rows, had_a_stall true, judged 3a7310ac (tie on stall id)
--     _at(..., 3a7310ac)                                     judged 3a7310ac:dcfc
--     _at(..., fe18413d)                                     judged fe18413d:l2
--     _at(..., NULL)                                         judged 3a7310ac
--   The tail, verbatim:
--   DO $probe$
--   DECLARE
--     v_run uuid; v_car uuid := 'a1111111-0001-0001-0001-000000000001';
--     v_depot uuid := '11111111-1111-1111-1111-111111111111';
--     v_seq bigint; v_six jsonb; v_six_stall text; v_at_dcfc text; v_at_l2 text; v_at_null text; v_n int;
--   BEGIN
--     SELECT arm_b_run INTO v_run FROM ottoq_determinism_verdict_ledger WHERE verdict_id = 364;
--     SELECT COALESCE(max(evaluation_seq), 0) INTO v_seq FROM ottoq_rule_evaluations;
--     SELECT count(*), jsonb_agg(DISTINCT had_a_stall) INTO v_n, v_six
--       FROM public.ottoq_probe_task_completion(v_run, v_depot, v_car, 'charge', '2026-09-02 00:00+00', '2026-09-02 00:30+00');
--     SELECT string_agg(DISTINCT left(e.context->>'stall_id', 8), ',') INTO v_six_stall FROM ottoq_rule_evaluations e
--      WHERE e.evaluation_seq > v_seq AND e.entity_id = v_car AND e.action_context = 'task_completion';
--     -- the same three reads after _at(..., '3a7310ac-...'), _at(..., 'fe18413d-...') and _at(..., NULL)
--     RAISE EXCEPTION 'PROBE six: rows=% had_a_stall=% judged=% | at(dcfc)=% | at(l2)=% | at(null)=%', ...;
--   END $probe$;

-- ══ §3 G225: THE REFUSAL REACTOR REROUTED A PLAN THE DECIDE PATH HAD ALREADY REPLACED (0490) ═══════════════════════

\echo '=== 0365 §3(a) — car 0001''s commands around the tie, arm A of 364 ==='
WITH v AS (SELECT arm_a_run AS run FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id = 364)
SELECT c.command_seq, c.issued_at, c.command_type, c.status, c.reason_code, left(c.payload->>'stall_id', 8) AS stall,
       c.payload->>'stall_type' AS stall_type, c.reacted_at, c.payload->'reaction'->>'action' AS reaction,
       left(c.payload->'reaction'->>'new_stall_id', 8) AS rerouted_to, c.executed_at
  FROM v JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = v.run
 WHERE c.vehicle_id = 'a1111111-0001-0001-0001-000000000001'
   AND c.issued_at BETWEEN '2026-09-01 22:00+00' AND '2026-09-02 01:30+00'
 ORDER BY c.issued_at, c.command_seq;
-- READ (2026-09-26, sim times):
--     22:30  proceed_to_stall  L2 fbb3a3df   refused target_occupied, reacted 23:00: rerouted to L2 fe18413d
--     23:00  begin_charge      DCFC 3a7310ac refused target_occupied, reacted 23:00: escalated (no DCFC free)
--     23:00  proceed_to_stall  L2 fe18413d   the reroute; executed 23:30
--     23:30  begin_charge      DCFC 3a7310ac executed 00:00, and the session ran 00:00-00:30
--   At 23:00 the decide path had already re-planned the car (DCFC, booking 23:00-23:48), and the reactor rerouted the
--   22:30 refusal anyway. One extra move, an L2 charger held an hour for a car that never charged on it, and the
--   second done booking behind §2's tie.

\echo '=== 0365 §3(b) — reroutes of a refusal whose car already held a command from a later tick ==='
WITH arms AS (
  SELECT verdict_id, scenario, seed, ticks, arm_a_run AS run FROM public.ottoq_determinism_verdict_ledger
   WHERE verdict_id BETWEEN 358 AND 364),
rx AS (
  SELECT r.sim_run_id, r.command_id, r.vehicle_id, r.issued_at, r.reacted_at
    FROM public.ottoq_vehicle_commands r
   WHERE r.payload->'reaction'->>'action' = 'rerouted' AND r.sim_run_id IN (SELECT run FROM arms))
SELECT a.verdict_id, a.scenario, a.seed, a.ticks,
       (SELECT count(*) FROM rx WHERE rx.sim_run_id = a.run) AS reroutes,
       (SELECT count(*) FROM rx WHERE rx.sim_run_id = a.run AND EXISTS (
           SELECT 1 FROM public.ottoq_vehicle_commands n
            WHERE n.sim_run_id = rx.sim_run_id AND n.vehicle_id = rx.vehicle_id
              AND n.issued_at > rx.issued_at AND n.issued_at <= rx.reacted_at
              AND COALESCE(n.payload->>'reroute_after', '') <> rx.command_id::text)) AS stale_reroutes
  FROM arms a ORDER BY a.verdict_id;
-- READ (2026-09-26, canon arms under 0487): busy_day 171717/12 1 of 3, 424242/12 3 of 5, normal_day 171717/12 1 of 4,
--   busy_day 171717/24 1 of 4, 424242/24 3 of 6, busy_day 171717/48 6 of 48; 314159/12 and grid_smoke have none.
--   The dial-experiment arms of the morning: 0-2 an arm. Today's three demo runs after G204 (49c45bd4, 3dbe16db,
--   461c79fa): 0.

\echo '=== 0365 §3(c) — one car rerouted twice in one reactor pass, by day ==='
WITH rxd AS (
  SELECT r.sim_run_id, r.vehicle_id, r.reacted_at, count(*) AS n
    FROM public.ottoq_vehicle_commands r
   WHERE r.payload->'reaction'->>'action' = 'rerouted' AND r.depot_id = '11111111-1111-1111-1111-111111111111'
   GROUP BY 1, 2, 3)
SELECT date_trunc('day', s.started_at) AS day, s.run_by, count(DISTINCT rxd.sim_run_id) AS runs,
       sum(rxd.n) AS reroutes, count(*) FILTER (WHERE rxd.n > 1) AS double_passes
  FROM rxd JOIN public.ottoq_sim_runs s ON s.sim_run_id = rxd.sim_run_id
 GROUP BY 1, 2 ORDER BY 1 DESC, 2;
-- READ (2026-09-26, 16:10 UTC): 51 double passes on 09-26's demo runs and 66 on its cert arms. Split on 0472's apply
--   (07:09:05 UTC): before it, 64 of the cert arms' and all 51 of the demo runs' (317d4331 and 689095e2 carried 74 and
--   27 duplicate proceed_to_stall commands, same car, tick and stall, which was G204). After it, 6: two on the dial arms
--   of 09:00 UTC, two on those of 09:20, two on the cert pair of 13:25, and every one is G225's own shape. The car's
--   refusal from the tick before (proceed_to_stall, L2) and its refusal from this tick (begin_charge) were both
--   rerouted in one pass, to two stalls. Under 0490 the older one is superseded by the newer command, so this shape
--   goes with the cross-tick case (b) measures.
--
--   Left open on purpose: the decide path still issues some same-tick pairs to one car from two writers, such as
--   begin_charge + proceed_to_stall (1-5 a run) and stage + proceed_to_stall (3-9 a canon arm). Which of two same-tick
--   commands is the plan is G210's question, not this one.
--
--   0490 = 20260926161853 (11:18 AM CT), stored statement md5 7b9a0ed0..., equal to the file's body. forces_recert TRUE.
--
--   The probe as run (0490's body without P0, then a tail that rewinds two refusals of 364's arm A to their reaction
--   tick in one transaction ending in RAISE):
--     stale   the 22:30 refusal, with car 0001's later commands and the reroute removed and only it unreacted, reacted
--             at 23:00: n=1, {"action": "superseded", "by_command_id": 340c9d92..., "by_command_type": "begin_charge",
--             "by_issued_at": "2026-09-01T23:00:00+00:00"}, which is the 23:00 begin_charge (seq 1665300)
--     control the first rerouted refusal whose car held no other command between refusal and reaction, rewound the
--             same way to 06:00: n=1, {"action": "rerouted", "new_stall_id": c957b07b..., "booking_id": ..., ...}
--   The tail, verbatim:
--   DO $probe$
--   DECLARE
--     v_run uuid; v_car uuid := 'a1111111-0001-0001-0001-000000000001';
--     v_depot uuid := '11111111-1111-1111-1111-111111111111';
--     v_stale uuid; v_expect uuid;
--     v_ctrl uuid; v_ctrl_car uuid; v_ctrl_at timestamptz;
--     r_stale jsonb; r_ctrl jsonb; v_n1 int; v_n2 int;
--   BEGIN
--     SELECT arm_a_run INTO v_run FROM ottoq_determinism_verdict_ledger WHERE verdict_id = 364;
--     SELECT command_id INTO v_stale  FROM ottoq_vehicle_commands WHERE sim_run_id = v_run AND command_seq = 1665276;
--     SELECT command_id INTO v_expect FROM ottoq_vehicle_commands WHERE sim_run_id = v_run AND command_seq = 1665300;
--     SELECT r.command_id, r.vehicle_id, r.reacted_at INTO v_ctrl, v_ctrl_car, v_ctrl_at
--       FROM ottoq_vehicle_commands r
--      WHERE r.sim_run_id = v_run AND r.payload->'reaction'->>'action' = 'rerouted' AND r.vehicle_id <> v_car
--        AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_commands n
--                         WHERE n.sim_run_id = v_run AND n.vehicle_id = r.vehicle_id
--                           AND n.issued_at > r.issued_at AND n.issued_at <= r.reacted_at
--                           AND COALESCE(n.payload->>'reroute_after','') <> r.command_id::text)
--      ORDER BY r.issued_at, r.command_seq LIMIT 1;
--     DELETE FROM ottoq_vehicle_commands WHERE sim_run_id = v_run AND vehicle_id = v_car
--        AND (issued_at > '2026-09-01 23:00+00' OR payload->>'reroute_after' = v_stale::text);
--     UPDATE ottoq_vehicle_commands SET reacted_at = COALESCE(reacted_at, '2026-09-01 23:00+00') WHERE sim_run_id = v_run AND status = 'refused';
--     UPDATE ottoq_vehicle_commands SET reacted_at = NULL, payload = payload - 'reaction' WHERE command_id = v_stale;
--     v_n1 := ottoq.ottoq_react_to_refusals(v_run, v_depot, '2026-09-01 23:00+00');
--     SELECT payload->'reaction' INTO r_stale FROM ottoq_vehicle_commands WHERE command_id = v_stale;
--     DELETE FROM ottoq_vehicle_commands WHERE sim_run_id = v_run AND vehicle_id = v_ctrl_car
--        AND (issued_at > v_ctrl_at OR payload->>'reroute_after' = v_ctrl::text);
--     UPDATE ottoq_vehicle_commands SET reacted_at = NULL, payload = payload - 'reaction' WHERE command_id = v_ctrl;
--     v_n2 := ottoq.ottoq_react_to_refusals(v_run, v_depot, v_ctrl_at);
--     SELECT payload->'reaction' INTO r_ctrl FROM ottoq_vehicle_commands WHERE command_id = v_ctrl;
--     RAISE EXCEPTION 'PROBE n1=% stale=% expect_by=% | n2=% ctrl_at=% ctrl=%', v_n1, r_stale, v_expect, v_n2, v_ctrl_at, r_ctrl;
--   END $probe$;

-- ══ §4 THE CANON UNDER 0489 AND 0490 ═══════════════════════════════════════════════════════════════════════════════
--
--   Both forcing migrations landed inside one runner minute (16:18:25 and 16:18:53 UTC), and the runner began one sweep
--   at 16:19:00 UTC (11:19 AM CT).

\echo '=== 0365 §4 — the canon ==='
SELECT c.scenario, c.seed, c.ticks, c.verdict_id, c.certified_at, c.outcome, c.equal, c.disagreeing_atoms,
       c.satisfies_floor, c.status
  FROM public.ottoq_determinism_canon c
 WHERE c.enabled
 ORDER BY c.certified_at;
-- READ (2026-09-26, 16:48 UTC): all nine columns current under 0489 and 0490, every one `passed` with no disagreeing
--   atom, first attempt each: verdicts 366-374, pairs started 16:19:00-16:37:32 UTC (11:19-11:37 AM CT). grid_smoke
--   239001/6 and 424242/6 (366, 367), busy_day 171717/12, 314159/12, 424242/12 (368-370), normal_day 171717/12 (371),
--   busy_day 171717/24 and 424242/24 (372, 373), busy_day 171717/48 (374).

\echo '=== 0365 §4(b) — the 48-tick column under 0487 (364) and under 0489/0490 (374): the fixes are not vacuous ==='
WITH v AS (SELECT verdict_id, arm_a_run, arm_b_run FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id IN (364, 374))
SELECT v.verdict_id, CASE WHEN e.sim_run_id = v.arm_a_run THEN 'A' ELSE 'B' END AS arm,
       count(*) FILTER (WHERE NOT e.passed) AS hw006_failed, count(*) FILTER (WHERE e.passed) AS hw006_passed
  FROM v JOIN public.ottoq_rule_evaluations e ON e.sim_run_id IN (v.arm_a_run, v.arm_b_run)
 WHERE e.rule_code = 'HW.006.physical_presence_verification' AND e.action_context = 'task_completion'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ: 364 A 11 failed / 497 passed, B 12 / 496. 374 A 0 / 502, B 0 / 502. Every HW.006 failure this column carried
--   was a wrong stall. The same arms: the reactor marked 6 refusals `superseded` and rerouted 42 (48 before), exactly
--   the six §3(b) counted, and no car holds two charge bookings starting at one instant (1 under 364).
--
--   What this does not say: HW.006 is still advisory, and the mechanism G157 names (an L2 session that outlives its
--   vehicle's stall pointer, 0350) is independent of both fixes. On an operator run a failure at the charge close now
--   means that mechanism and nothing else.
