-- 0492  **The agent's fallback model answers again; a stored pass can be replayed; and eleven cars were held in the
--        charge line for a wash-bay line they were not in.**
--        Production database, 2026-11-13 13:25 UTC to 2026-11-14 00:51 UTC (7:25 AM to 6:51 PM CT on 11-13).
--        Rule 8: the twin depot. Rule 12: demo runs to see finished changes working; no pair, no sweep. Each run is one
--        seed: readings, not ranges. (Numbers 0489-0491 are another branch's checks, written the same day.)
--
-- ══ (1) G543: THE FALLBACK MODEL ══════════════════════════════════════════════════════════════════════════════════════
--
--   https://integrate.api.nvidia.com/v1/models, read 2026-11-13 13:25 UTC: 83 models, among them
--   nvidia/nemotron-3-super-120b-a12b, the model that has answered the agent HTTP 404 since 2026-10-14. A listing is
--   not proof that a key may call a model.
--   The function's own probe (POST {"probe_models": true}; agent v33, deployed as v46), 16:31:52 UTC, on both keys:
--     nvidia/nemotron-3-ultra-550b-a55b (primary)   answered, 1,219 ms
--     nvidia/nemotron-3.5-lightning-30b-a3b         answered, 187 ms
--     nvidia/nemotron-4-340b-instruct               404 on both keys, "Function … Not found for account …", 37 and 48 ms
--     nvidia/nemotron-3-super-120b-a12b             404 on both keys, the same message, 32 and 34 ms
--   The chain is the primary, then those three in that order. The two that answer 404 cost about 80 ms each when the
--   chain reaches them, and answer if the account is given them.
--
-- ══ (2) A STORED PASS, REPLAYED THROUGH THE FALLBACK (v48, 19:57:30 UTC, run 7a08f52a live) ═══════════════════════════
--
--   POST {"replay_pass_id": N, "fallback_only": true} sends a stored pass's own board and brief to the fallbacks. It
--   claims no tick, calls no door and writes nothing. All three replays report the stored board's hash matching and
--   the prompt hash the pass itself recorded (85f8d441…).
--     pass   woken by        the fallback answered in   directives   brief subjects named   the primary, live
--     9078   charger_fault   11.5 s                     4            4 of 4                 3 directives, 4 of 4
--     9289   charger_fault   14.1 s                     5            (7 subjects)           4 directives, 7 of 7
--     9011   charger_fault    5.0 s                     0            0 of 4                 2 directives, 4 of 4
--   The same pass 9078 replayed through the whole chain: the primary, 21.2 s, 3 directives.
--   WHAT THE FALLBACK IS: an answer in place of none, and a worse one. On 9011 it wrote no directive. On 9078 it named
--   every car and post and paired them wrongly: it wrote that NASH-DCFC-STALL-28's fault cut Waymo-AV-004 at 99% and
--   that the car was charging again; the primary's replay of the same board says that fault cut Tesla-AV-055 at 74%,
--   waiting first in line, and that Waymo-AV-004, cut 103 minutes earlier, was still waiting. So the coverage count
--   (did the directives name the subject) reads 4 of 4 on a directive that is wrong: it does not measure whether a
--   directive is right, as db/checks/0488 §8 (f) says.
--   Two changes follow, in v49: a directive a fallback model wrote carries by_fallback_model, and the primary's attempt
--   is bounded at 65 s where it was 75. Over the 14 days to this read the primary answered 438 of 458 attempts at the
--   twin depot (p50 18.8 s, p95 40.1 s, p99 59.3 s, the slowest 67.9 s; 15 timed out, 5 failed otherwise). At 75 s a
--   timeout left the fallback 15 s of the 90 s budget, and it needed 5 to 14. At 65 s it has 25. The cost is the
--   primary's answers slower than 65 s: 5 of the 438 took over 60.
--   NOT SEEN: a primary failure on a live pass since the chain went in. Runs 9085ca36 (32 consults) and 7a08f52a (28)
--   were answered by the primary on every pass. The chain's live path rests on the probe, the replays and the module's
--   tests (tests/agent_model_call.test.mjs, five for this).
--
-- ══ (3) A DIRECTIVE WAS CUT AT 400 CHARACTERS ════════════════════════════════════════════════════════════════════════
--
--   0488's second prompt asks for the scout findings of one kind in one directive naming every car. On run 9085ca36
--   (16:39-17:56 UTC, v46-v47) the model's answers named 135 of the 136 subjects the briefs marked new, and the applied
--   directives, cut at 400 characters, kept 101. v48 keeps 1,200. Run 7a08f52a (19:57-21:06 UTC, v48, then v49
--   during the run): 28 consults, 107 of 107 subjects in the applied directives, 27 directives longer than 400 characters,
--   the longest 903.
--
-- ══ (4) G541, ANSWERED: THE WASH BAY "IDLE WITH A CAR READY" WAS THE BOARD'S COUNT ═══════════════════════════════════
--
--   Run a95e51a3 (the night before), from the cars' own state changes: 44 entries into a wash bay, from staging, after
--   a median 1.9 minutes there. The five that had stood over 100 minutes (104 to 279) each owed service-bay work and
--   no wash at the time: they were waiting for the service bays.
--   Run 7a08f52a at tick 25: the board said busy 2, idle 1, queued 31 cars and 522 minutes (2.93 hours to clear), one
--   bay idle with a car ready. Read beside it: all three wash stalls were occupied, each with a car; and of the 31
--   cars in the line, 24 owed only an interior deep clean (requires_bay 'detail') and 7 an exterior wash.
--   Two causes. (a) public.ottoq_bay_line put the deep clean in the wash bays' line, though 0817 moved it to the
--   charging posts: fixed by 0829, below. (b) public.ottoq_depot_constraint counts a bay busy by cars in the state
--   in_wash_bay or in_detail_bay, so a bay a car holds on its way in reads idle. NOT CHANGED: (b) is OPEN.
--
-- ══ (5) G544: ELEVEN CARS HELD IN THE CHARGE LINE FOR THAT LINE, AND 0829 ════════════════════════════════════════════
--
--   0781 (charge_order_exit_first, on at the twin depot) has a car whose turn in the bays is far off yield its place
--   in the charge line to its own owner's cars, and reads that turn from the same bay line.
--                                                        run 7a08f52a, tick 35     run 14d6eda7, tick 36
--                                                        (before 0829)             (after 0829)
--     the charge line                                    31 cars                   30 cars
--     yielding (exit_key 1)                              15                        4
--       of them owing service-bay work                   3                         4
--       of them owing only a post's deep clean           11                        0
--       of them owing only an exterior wash              1                         0
--     cars in the line owing only a deep clean           (not read)                4, none yielding
--     the wash bays' line                                31 cars, 2.93 h (tick 25) 8 cars, 0.44 h
--   Before 0829 those 11 stood at a mean place of 18.1 in the kernel's line, against 6.5 for the cars not yielding,
--   with a mean "turn in the bays" of 120 minutes, for a clean their charging post does while it charges them.
--   Two different seeds, one moment each. What the comparison shows is the rule, which is exact: after 0829 a car that
--   owes only a post's clean has no turn in any bay's line (public.ottoq_charge_order_keys.bay_eta_min is null), so
--   it cannot yield. It does NOT show what those cars' waits were worth over a day: no run was read for that.
--   0829 applied 2026-11-14 00:47:43 UTC (ledger 20261114004743), between runs, P0-P2 and V1-V3 passing inside the
--   file: at the apply every run the database held was row for row unchanged where the wash bay is not exterior only,
--   and the body's md5 is the one the tests ran. tests/test_bay_line_cabin_work_sql.py: 8 on 0781's own harness, whose
--   bay line is the live definition (md5 e894dd4d…); 4 of 4 hand mutations caught.
--   A NUMBER TAKEN TWICE. This file was first written and tested as 0824. Another branch had applied its own 0824 to
--   the engine the night before, so a check for "0824 in the lineage" read 1 with this one never applied; the names
--   differed and the function's md5 was still the old one, which is what showed it. Renumbered before the apply. A
--   migration's number is free only if the ledger says so on the day.
--
-- ══ (6) WHAT IS OPEN ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) G541 (b): the board's busy count for a bay. (b) Nothing grades whether a directive is right; the fallback's
--   wrong pairing in §2 is the first case on record. (c) The fallback on a live primary failure: not yet seen.
--   (d) The cost of the yielding to the 11 cars over a day, and whether 0781's margin should change now that the wash
--   line is short: not measured. (e) The function answers its probe and a replay to any caller holding the public key
--   while a run is live, as it already answers a consult; a replay costs one model call.
--
-- ══ THE QUERIES ═══════════════════════════════════════════════════════════════════════════════════════════════════════

-- (2) the primary's attempts over 14 days
SELECT count(*) AS attempts, count(*) FILTER (WHERE x ->> 'status' = 'ok') AS ok,
       count(*) FILTER (WHERE x ->> 'status' = 'timeout') AS timeouts,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY (x ->> 'ms')::int) FILTER (WHERE x ->> 'status' = 'ok') AS p95_ms,
       max((x ->> 'ms')::int) FILTER (WHERE x ->> 'status' = 'ok') AS slowest_ok_ms
  FROM public.ottoq_agent_pass_evidence e, jsonb_array_elements(e.attempts) x
 WHERE e.depot_id = '11111111-1111-1111-1111-111111111111' AND e.consulted
   AND e.recorded_at > now() - interval '14 days' AND x ->> 'model' = 'nvidia/nemotron-3-ultra-550b-a55b';

-- (5) who yields in the charge line now, and for what (give it a running run)
WITH r AS (SELECT sim_run_id, depot_id, sim_clock_current AS c FROM public.ottoq_sim_runs
            WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running' LIMIT 1),
k AS (SELECT x.* FROM r, LATERAL public.ottoq_charge_order_keys(r.sim_run_id, r.depot_id, r.c) x),
a AS (SELECT k.vehicle_id, bool_or(t.value ->> 'requires_bay' = 'service_bay') AS service,
             bool_or(t.value ->> 'requires_bay' = 'wash_bay') AS wash, bool_or(t.value ->> 'requires_bay' = 'detail') AS clean
        FROM k JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = k.vehicle_id AND vn.status IN ('open', 'in_progress')
                                               AND vn.sim_run_id = (SELECT sim_run_id FROM r)
       CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) t
       WHERE COALESCE(t.value ->> 'status', 'pending') NOT IN ('done', 'cancelled', 'skipped', 'in_progress')
         AND t.value ->> 'requires_bay' IN ('service_bay', 'wash_bay', 'detail') GROUP BY 1)
SELECT count(*) AS line, count(*) FILTER (WHERE k.exit_key = 1) AS yielding,
       count(*) FILTER (WHERE k.exit_key = 1 AND a.service) AS yielding_with_service_bay_work,
       count(*) FILTER (WHERE k.exit_key = 1 AND a.clean AND NOT a.service AND NOT a.wash) AS yielding_for_a_post_clean_only
  FROM k LEFT JOIN a ON a.vehicle_id = k.vehicle_id;
