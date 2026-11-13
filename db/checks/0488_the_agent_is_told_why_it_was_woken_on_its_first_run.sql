-- 0488  **The agent is told why it was woken: what the pass found, 0823 and edge v32 at the apply, and their first run.**
--        Production database, 2026-11-13 02:10 UTC onward (the evening of 2026-11-12 CT). Rule 8: the twin depot only.
--        Rule 12: one demo run to show a finished change working; no pair, no sweep. One run: readings, not ranges.
--
-- ══ (1) WHAT THE PASS FOUND (G540) ════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_agent_pass_evidence, depot 11111111-…, consulted, answered, recorded_at >= 2026-11-05 22:00 UTC (after
--   0795 took the agent off the charge line), read 02:10-02:50 UTC:
--     answered consults                                   286 on 16 runs
--     model tokens                                        7,161,273 (mean 23,969 prompt tokens a consult)
--     outcome_class = changed_state                       0
--     solver objective readiness_first                    286 of 286
--     stored boards that carry a wake reason              0 of 286
--     woken by an emergency / answers that mention one    5 / 0
--     woken by a fault, a repair or an emergency / answers that mention a fault, a repair or an emergency   59 / 31
--     directives issued                                   1,005
--   The wake gate's reasons never reached the model: edge v31 sent "BOARD DIGEST: <board>" and nothing else, and the
--   gate's fingerprint is counts, so it named no car and no charger.
--   Wake reasons of the consults of the last 12 days (same table): heartbeat 68, contract_wait 61, scout_finding 60,
--   charger_fault 31, first_consult 27, charger_restored 24, contention_relief 13, no reason 12, due_in_line 10,
--   contention_onset 6, charger_free 5, emergency 5, and 14 with two or three reasons.
--
-- ══ (2) 0823 AT THE APPLY ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   Applied 2026-11-13 03:02 UTC, ledger 20261113030227. P0-P2 and V1-V5 passed inside the file: the brief is STABLE and
--   executable by service_role only, the board and the wake gate are byte for byte what they were, the brief is NULL at
--   the dial's default on every run, a probe on the newest run with agent passes returned a well-formed brief and left
--   no setting, and the body's md5 is the one the tests ran (7cb3ec83…). agent_wake_brief = 1 at depot scope for the
--   twin depot.
--   Read back on three runs' real rows with the dial on (03:03 UTC): 138 ms and 152 ms on runs 21011d03 and cce21ff2
--   (1,377 and 2,602 bytes), under 1 ms on 02ca304f. On 21011d03 it named Tesla-RT-003, cut at 96% on NASH-DCFC-STALL-27
--   by fault.session_aborted_other and charging again on NASH-DCFC-STALL-10 after 5 minutes.
--   Tests before the apply: 14 on the scratch PostgreSQL (tests/test_agent_wake_brief_sql.py), with 10 of 10 hand
--   mutations of the file caught; 322 of 322 node tests; the edge function's type errors are the 8 it had before.
--
-- ══ (3) EDGE v32 (ottoq-orchestrator-agent v44), VERIFIED TWO WAYS ════════════════════════════════════════════════════
--
--   Deployed between the apply (03:02 UTC) and the run's start (03:10 UTC); edge-functions/_MANIFEST.md footnote 17.
--   (a) The helper session that deployed it fetched v44 back and compared each of the eight files' bytes with the
--       repo's: eight of eight equal. The repo's sha256 of index.ts, agent_wake_brief.ts and agent_rule_nine.ts, taken
--       here, equal the ones it reported.
--   (b) The function records the sha256 of the system prompt it sends. Computed from the repo's source BEFORE any run:
--       a pass with no brief sends 0f8d980d…, which is the hash on all 336 consults v43 recorded in its last ten days
--       (so with no brief v32's prompt is v31's); a pass with a brief sends 0a36353c…, which is the hash on every
--       consult of the run below.
--
-- ══ (4) RUN b848a046 (busy_day, operator_demo, live at 8x; started 03:10:27 UTC through ottoq_operator_start_run) ═════
--
--   FIRST READ, 03:26:42 UTC, tick 192, sim 16:09. 7 consults, 69 solver-only passes. All 7 are agent v32 with a brief
--   and prompt 0a36353c….
--     wake reasons                 new subjects the brief named    named by the directives    actions
--     first_consult                0                               0                          0
--     heartbeat, charger_fault     4                               4                          2
--     contract_wait                2                               2                          3
--     heartbeat                    2                               0                          0
--     contract_wait                0                               0                          3
--     contract_wait                0                               0                          0
--     heartbeat, charger_fault     6                               6                          6
--   12 of 14 named. The seventh consult's directives, verbatim in the pass's record: one per cut car, from the brief
--   ("Zoox-AV-093 charge cut by fault at 52% on NASH-DCFC-STALL-03 (thermal_emergency, 6 min ago). Resumed charging on
--   NASH-DCFC-STALL-04 after 1 min. Full target 100% still required."), one for the three faulted posts, and two on the
--   contract wait. None was refused by the rule-9 test.
--   THE MISS: the fourth consult was woken by the heartbeat alone, its brief named a newly cut charge (Tesla-AV-065)
--   and a newly faulted post (NASH-DCFC-STALL-13), and the model answered with no action at all. The prompt's rule 4
--   speaks of a heartbeat with no subjects; a heartbeat WITH new subjects fell between its rules. Not changed tonight:
--   one consult is one reading, and the run's end is read first.
--   THE RUN'S END is §6, written after the run stops.
--
-- ══ (5) FOUND ON THE WAY, RECORDED AND NOT FIXED ══════════════════════════════════════════════════════════════════════
--
--   G541. The agent's board showed a wash bay idle with a car ready on 29 of 31 consulted boards of run cce21ff2 (27
--   of 32 on 893a0313, 28 of 34 on 56d8465f), and the agent said so in a directive each time. On cce21ff2 the three
--   wash bays held 38 washes (ottoq_stall_bookings, purpose wash, state done), 300 booked minutes. NOT ESTABLISHED
--   whether any waiting car could have been seated: the board's count does not test that the car is free to move.
--   G542. Run cce21ff2: 19 charges cut by a charger fault (ocpp_sessions.status = 'faulted'). The car's next charge
--   began within 9 minutes for 16 of them; Tesla-AV-055 (cut at 75%) waited 39 minutes and Zoox-AV-097 (cut at 57%)
--   15. Two cut at 99% show 181 and 217 minutes to their next charge; one of them had left and come back at 49%.
--   A LEAD, NOT A GATE PASSED. public.ottoq_disposer_discrimination() read at 03:04 UTC over its 30 days: AUC 0.6808,
--   interval 0.6209-0.7406, 138 won and 181 lost on 27 runs and 25 distinct keys, Brier 0.2302 against 0.2455 at the
--   base rate. On 2026-10-13 it read 0.534 [0.415, 0.653]. By day: 207 of the 319 decisions are from 10-20, 10-23 and
--   10-24; since 0795 there are 44, and the newest day with both outcomes (11-12: 12 won, 13 lost) leans the same way
--   (mean win probability 0.708 for the orders that won, 0.500 for those that lost). The interval assumes independent
--   decisions, and "won" is a site total: G511 and G512 found the taken orders traded one owner for another, which
--   this number does not see (rule 14).
--
-- ══ (6) THE RUN'S END ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   PENDING: the run was still live when this file was first committed.
--
-- ══ THE QUERIES ═══════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) the baseline
SELECT count(*) AS consults, count(DISTINCT sim_run_id) AS runs,
       count(*) FILTER (WHERE outcome_class = 'changed_state') AS changed_state,
       count(*) FILTER (WHERE answer -> 'solver' ->> 'objective' = 'readiness_first') AS readiness_first,
       count(*) FILTER (WHERE board_text ~ '"wake"|wake_reason|woken') AS boards_with_a_wake_reason,
       count(*) FILTER (WHERE wake -> 'reasons' ? 'emergency') AS emergency_woken,
       count(*) FILTER (WHERE wake -> 'reasons' ? 'emergency' AND (answer -> 'actions')::text ~* 'emergenc') AS emergency_named,
       sum(jsonb_array_length(answer -> 'actions')) AS actions, sum((usage ->> 'total_tokens')::numeric) AS tokens
  FROM public.ottoq_agent_pass_evidence
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND consulted AND answer IS NOT NULL
   AND recorded_at >= '2026-11-05 22:00+00' AND agent_version = 'v31';

-- (4), (6) one run's consults: the brief, the prompt, and what the directives named
SELECT e.pass_id, e.agent_version, e.outcome_class, e.wake -> 'reasons' AS reasons, left(e.prompt_sha256, 8) AS prompt,
       (e.wake -> 'brief') IS NOT NULL AS has_brief, e.wake -> 'brief' ->> 'error' AS brief_error,
       e.levers -> 'wake_brief' AS coverage_of_applied, jsonb_array_length(COALESCE(e.answer -> 'actions', '[]')) AS actions,
       e.levers ->> 'rejected' AS rejected, e.usage ->> 'prompt_tokens' AS prompt_tokens, e.total_ms
  FROM public.ottoq_agent_pass_evidence e
 WHERE e.sim_run_id = 'b848a046-8f6b-4b75-9040-7382eb3dfdd0' AND e.consulted
 ORDER BY e.pass_id;

-- (6) the coverage view, by kind (count subjects, and the distinct runs behind them)
SELECT kind, count(*) AS subjects, count(*) FILTER (WHERE addressed) AS named, count(DISTINCT sim_run_id) AS runs
  FROM public.ottoq_agent_wake_brief_coverage
 WHERE depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY kind ORDER BY kind;
