-- ============================================================================================
-- 0045 — RUN RECONCILIATION: does the loop's paper trail add up, end to end?
--
-- Chase's validation directive (2026-08-29): "Every connection and logic point needs to be
-- tested and validated and audited... make sure our orchestration engine works from A to B to
-- C." This check is that directive made executable for ONE completed run: it walks the ledgers a
-- run leaves behind and verifies they agree with each other, stage by stage.
--
-- Born red on purpose. First run against 9291ec6d (busy_day, seed 777011, 2026-08-29): R3, R4,
-- R5, R6 and R7 all FAIL, and each failure is a real defect confirmed by hand before this file
-- existed. A reconciliation that passes on its first try has not been shown able to fail (the
-- K3 lesson, db/checks/0044). Expected verdicts as of writing are noted per check.
--
-- Targets the MOST RECENT COMPLETED run. Re-run after every engine change.
-- ============================================================================================

WITH target AS (
  SELECT sim_run_id AS id, ended_at
    FROM public.ottoq_sim_runs
   WHERE status = 'completed'
   ORDER BY started_at DESC NULLS LAST
   LIMIT 1
)

-- R0. There is a run to reconcile. EMPTY is its own verdict, never a pass.
SELECT 'R0 target' AS check,
       COALESCE((SELECT id::text FROM target), 'EMPTY(no completed runs — nothing certified)') AS detail,
       CASE WHEN EXISTS (SELECT 1 FROM target) THEN 'PASS' ELSE 'EMPTY' END AS verdict
UNION ALL

-- R1. Calendar and session ledgers in lockstep: every booking state matches its session count.
--     (2026-08-29: PASS — 128/4/381/20 identical on both sides.)
SELECT 'R1 bookings=sessions lockstep',
       COALESCE(string_agg(state||' '||b||'/'||s, ', ' ORDER BY state), 'no rows'),
       CASE WHEN count(*) FILTER (WHERE b IS DISTINCT FROM s) = 0
             AND count(*) > 0 THEN 'PASS'
            WHEN count(*) = 0 THEN 'EMPTY(no bookings)'
            ELSE 'FAIL' END
  FROM (
    SELECT COALESCE(bk.state, ss.session_state) AS state, bk.n AS b, ss.n AS s
      FROM (SELECT state, count(*) n FROM public.ottoq_stall_bookings, target WHERE sim_run_id=target.id GROUP BY 1) bk
      FULL JOIN (SELECT session_state, count(*) n FROM public.service_sessions, target WHERE sim_run_id=target.id GROUP BY 1) ss
        ON bk.state = ss.session_state
  ) x
UNION ALL

-- R2. THE SETTLEMENT CONTRACT: every done SERVICE leg has an SDR; transit (taxi) legs have none.
--     The strategic rule of CLAUDE.md 2.6 — verified against the leg ledger the 0043 trigger
--     actually fires on, not against a proxy. (2026-08-29: PASS — 65/65 service, 51 taxi unsettled.)
SELECT 'R2 done service legs -> SDR',
       'service done '||count(*) FILTER (WHERE leg_type <> 'taxi')
       ||', settled '||count(*) FILTER (WHERE leg_type <> 'taxi' AND has_sdr)
       ||'; taxi done '||count(*) FILTER (WHERE leg_type = 'taxi')
       ||', wrongly settled '||count(*) FILTER (WHERE leg_type = 'taxi' AND has_sdr),
       CASE WHEN count(*) = 0 THEN 'EMPTY(no done legs)'
            WHEN count(*) FILTER (WHERE leg_type <> 'taxi' AND NOT has_sdr) = 0
             AND count(*) FILTER (WHERE leg_type = 'taxi' AND has_sdr) = 0
             AND count(*) FILTER (WHERE leg_type <> 'taxi') > 0 THEN 'PASS'
            ELSE 'FAIL' END
  FROM (
    SELECT l.leg_type,
           EXISTS (SELECT 1 FROM public.ottoq_service_detail_records d WHERE d.leg_id = l.leg_id) AS has_sdr
      FROM public.ottoq_itinerary_legs l, target WHERE l.sim_run_id = target.id AND l.status = 'done'
  ) x
UNION ALL

-- R3. Every refusal carries a reason code. "Every directive carries a reason code" is a founding
--     principle; a refusal with no code is a decision whose why is lost.
--     (2026-08-29: FAIL — 14 of 73 refusals carry none, all proceed_to_stall.)
SELECT 'R3 refusals carry reason codes',
       count(*)::text||' refused, '||count(*) FILTER (WHERE reason_code IS NULL)::text||' without a code',
       CASE WHEN count(*) = 0 THEN 'EMPTY(no refusals — path unexercised)'
            WHEN count(*) FILTER (WHERE reason_code IS NULL) = 0 THEN 'PASS'
            ELSE 'FAIL' END
  FROM public.ottoq_vehicle_commands, target
 WHERE sim_run_id = target.id AND status = 'refused'
UNION ALL

-- R4. No command is left dangling on a completed run. A command still 'issued' after the run
--     ended got no reaction and no timeout — the silent-outcome failure mode.
--     (2026-08-29: FAIL — 18 stage commands stranded for the entire simulated day.)
SELECT 'R4 no stranded commands',
       count(*) FILTER (WHERE status='issued')::text||' still issued of '||count(*)::text,
       CASE WHEN count(*) = 0 THEN 'EMPTY(no commands)'
            WHEN count(*) FILTER (WHERE status='issued') = 0 THEN 'PASS'
            ELSE 'FAIL' END
  FROM public.ottoq_vehicle_commands, target WHERE sim_run_id = target.id
UNION ALL

-- R5. Every ENACTED decision names its action. An enacted row with no verb in either
--     proposed_action or enacted_action is an audit hole: something happened, the trail cannot
--     say what. (2026-08-29: FAIL — 100 of 822, every one from 'orchestrator_agent'.)
SELECT 'R5 enacted decisions carry a verb',
       count(*)::text||' enacted, '||count(*) FILTER (WHERE enacted_action->>'verb' IS NULL AND proposed_action->>'verb' IS NULL)::text
       ||' verbless ('||COALESCE(string_agg(DISTINCT COALESCE(resolved_action_context, action_context), ',')
            FILTER (WHERE enacted_action->>'verb' IS NULL AND proposed_action->>'verb' IS NULL), 'none')||')',
       CASE WHEN count(*) = 0 THEN 'EMPTY(no enacted decisions)'
            WHEN count(*) FILTER (WHERE enacted_action->>'verb' IS NULL AND proposed_action->>'verb' IS NULL) = 0 THEN 'PASS'
            ELSE 'FAIL' END
  FROM public.ottoq_decisions, target
 WHERE sim_run_id = target.id AND outcome_status = 'enacted'
UNION ALL

-- R6. Calendar↔reality disagreements are RECORDED. A 'target_occupied' refusal means the plan
--     met a stall that physical reality says is taken — exactly what space_conflict_ledger
--     exists to hold. Refusals without ledger rows mean the disagreement happened and no
--     first-class record was kept. (2026-08-29: FAIL — 18 such refusals, 0 ledger rows; the
--     ledger's only writer is the displacement path, the refusal path never writes it.)
SELECT 'R6 target_occupied -> conflict ledger',
       (SELECT count(*) FROM public.ottoq_vehicle_commands, target
         WHERE sim_run_id=target.id AND status='refused' AND reason_code='target_occupied')::text
       ||' occupied-refusals vs '||
       (SELECT count(*) FROM public.space_conflict_ledger, target WHERE sim_run_id=target.id)::text
       ||' conflict rows',
       CASE WHEN (SELECT count(*) FROM public.ottoq_vehicle_commands, target
                   WHERE sim_run_id=target.id AND status='refused' AND reason_code='target_occupied') = 0
              THEN 'EMPTY(no occupied-refusals)'
            WHEN (SELECT count(*) FROM public.space_conflict_ledger, target WHERE sim_run_id=target.id) > 0
              THEN 'PASS'
            ELSE 'FAIL' END
UNION ALL

-- R7. The run row's own summary agrees with the ledgers it summarizes. A headline number that
--     matches no ledger is the 'field that looks like evidence' defect (0073's family).
--     (2026-08-29: FAIL — run says tasks_completed 9; legs say 116 done, 65 settled.)
SELECT 'R7 run summary = ledger truth',
       'run.tasks_completed '||(SELECT COALESCE(tasks_completed,0) FROM public.ottoq_sim_runs, target WHERE sim_run_id=target.id)::text
       ||' vs done legs '||(SELECT count(*) FROM public.ottoq_itinerary_legs, target WHERE sim_run_id=target.id AND status='done')::text
       ||' vs SDRs '||(SELECT count(*) FROM public.ottoq_service_detail_records, target WHERE sim_run_id=target.id)::text,
       CASE WHEN (SELECT COALESCE(tasks_completed,0) FROM public.ottoq_sim_runs, target WHERE sim_run_id=target.id)
              IN ((SELECT count(*) FROM public.ottoq_itinerary_legs, target WHERE sim_run_id=target.id AND status='done'),
                  (SELECT count(*) FROM public.ottoq_service_detail_records, target WHERE sim_run_id=target.id))
              THEN 'PASS'
            ELSE 'FAIL' END
UNION ALL

-- R8. Cross-ledger identity on charges: the session ledger and the settlement ledger must count
--     the same charge events with the same linkage. (2026-08-29: FAIL — totals agree at 7, but
--     only 2 of 7 charge sessions share a leg_id with their SDR, and the DCFC/L2 split disagrees
--     2/5 vs 3/4: two ledgers describing the same events with different keys and labels.)
SELECT 'R8 charge sessions = charge SDRs, by key',
       'sessions done '||(SELECT count(*) FROM public.service_sessions, target
                           WHERE sim_run_id=target.id AND session_state='done' AND operation_code LIKE 'charge%')::text
       ||', SDRs '||(SELECT count(*) FROM public.ottoq_service_detail_records, target
                      WHERE sim_run_id=target.id AND operation_code LIKE 'charge%')::text
       ||', key-linked '||(SELECT count(*) FROM public.service_sessions s, target
                            WHERE s.sim_run_id=target.id AND s.session_state='done' AND s.operation_code LIKE 'charge%'
                              AND EXISTS (SELECT 1 FROM public.ottoq_service_detail_records d
                                           WHERE d.leg_id = s.leg_id AND d.leg_id IS NOT NULL))::text,
       CASE WHEN (SELECT count(*) FROM public.service_sessions, target
                   WHERE sim_run_id=target.id AND session_state='done' AND operation_code LIKE 'charge%') = 0
              THEN 'EMPTY(no charge sessions)'
            WHEN (SELECT count(*) FROM public.service_sessions s, target
                   WHERE s.sim_run_id=target.id AND s.session_state='done' AND s.operation_code LIKE 'charge%'
                     AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_detail_records d
                                      WHERE d.leg_id = s.leg_id AND d.leg_id IS NOT NULL)) = 0
              THEN 'PASS'
            ELSE 'FAIL' END
UNION ALL

-- R9. Every SDR is hashed and signed — the settlement rail's integrity floor.
--     (2026-08-29: PASS — 65/65 carry payload_hash and signature.)
SELECT 'R9 SDRs hashed and signed',
       count(*)::text||' SDRs, '||count(*) FILTER (WHERE payload_hash IS NULL OR signature IS NULL)::text||' missing hash/signature',
       CASE WHEN count(*) = 0 THEN 'EMPTY(no SDRs)'
            WHEN count(*) FILTER (WHERE payload_hash IS NULL OR signature IS NULL) = 0 THEN 'PASS'
            ELSE 'FAIL' END
  FROM public.ottoq_service_detail_records, target WHERE sim_run_id = target.id;
