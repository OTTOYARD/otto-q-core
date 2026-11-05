-- 0478  **Counted owner by owner, most of the referee's "wins" trade one owner's cars for another's. Of the 32 agent
--        charge orders it took before the owner guard, 27 made at least one owner's cars worse off in hindsight; of the
--        143 orders it refused that the depot-level grade calls "missed wins", 30 were good for every owner.**
--        -> G511 (new); answers G508's per-owner question. Frontier plan Phase 0, item 2 (E2, E7; CLAUDE.md rule 14).
--        Chase, 2026-11-04: "keep going".
--        Measured in the research lab (lab/engine/, built from production's export of 2026-11-04), on production's
--        evidence read through the read-only endpoint at 01:05:37 UTC 2026-11-05 (7:05 PM CT 2026-11-04):
--        lib/export_decisions.py, the decision set of 0475/0476 (370 graded decisions at the twin depot since
--        2026-10-01, from 25 runs). Scripts and full output: lab/research/p0_referee_per_owner/. Rule 8: twin depot only.
--        Nothing here writes to production.
--
-- ══ §1 THE LAB RE-GRADES THE REFEREE EXACTLY (replay.sql) ═════════════════════════════════════════════════════════
--
--   The grader (0621/0630) is a pure function of evidence production keeps for every checked order: the check's
--   state, the agent's order and the futures' seed (ottoq_charge_order_snapshots), and what happened in the window
--   (ottoq_charge_order_grades.realized). Recomputed in the lab with ottoq_charge_line_realize and
--   ottoq_charge_line_schedule (grader code md5 15da9f4c, production's current):
--
--     expected (the check's own future) reproduced byte for byte     370 of 370
--     hindsight reproduced byte for byte                             370 of 370
--       of which graded by today's grader code                        30
--
--   So every per-owner number below comes from the same arithmetic that wrote production's grades.
--
-- ══ §2 OWNERS ADDED, NOTHING ELSE CHANGED ══════════════════════════════════════════════════════════════════════════
--
--   0784's owner guard makes the check carry every car's owner and sum each owner's cars on their own (by_owner). The
--   30 decisions since the guard went on (2026-10-25 17:01 UTC, Chase) carry it; the other 340 were given it in the
--   lab exactly as ottoq_charge_line_state builds it (vehicles.fleet_operator_id of the twin depot's 116 autonomous
--   cars: Waymo Nashville 46, Tesla Robotaxi TN 36, Zoox Southeast 34). On all 370, every depot-level number on all
--   four sides (kernel and agent, expected and hindsight) is unchanged by it.
--
-- ══ §3 EACH OWNER ON ITS OWN, IN HINDSIGHT (analysis.sql (2), (3), (4)) ════════════════════════════════════════════
--
--   Each owner judged with the engine's own yardstick, ottoq_charge_line_compare (on-time cars, lateness, minutes past
--   the contract wait, minutes in the depot), on its own cars:
--
--     the grader's label     decisions  good for every owner  trades one owner for another  bad for every owner  no change
--     missed_win (refused)        143            30                    113                          0               0
--     right_refusal               195             0                    115                         40              40
--     right_take (taken)           21             5                     16                          0               0
--     wrong_take (taken)           11             0                      6                          5               0
--     all                         370            35                    250                         45              40
--
--   The 32 orders the referee took (all before the owner guard; none of the 30 decisions since was taken):
--   5 good for every owner, 22 helped one owner at another's expense, 5 hurt every owner. When a taken order hurt an
--   owner (43 owner losses), the median cost to that owner's cars was 23.1 minutes past their contract wait and 2.0
--   minutes of lateness; one car missed its due time (9).
--
--   Owner by owner, over all 370 decisions (better / worse / no different for that owner's cars):
--     Waymo Nashville     182 / 146 / 42     taken: 22 better, 10 worse
--     Tesla Robotaxi TN   145 / 180 / 45     taken: 15 better, 17 worse
--     Zoox Southeast      153 / 171 / 46     taken: 15 better, 16 worse
--   The agent's orders lean toward Waymo's cars and away from Tesla's and Zoox's. A reading, not a test: 370 decisions
--   from 25 runs and 18 (scenario, seed) keys (0475), so the decisions are not independent.
--
-- ══ §4 THE CHECK CANNOT YET SEE OWNERS (analysis.sql (6), (7), (10)) ═══════════════════════════════════════════════
--
--   - Owner by owner (1,110 owner-decisions), the check's expected verdict and hindsight's point the same way in 513
--     and opposite ways in 432: 54% when both call a direction.
--   - 0784's guard (refuse when the check EXPECTS any owner worse off), applied to every decision: it refuses 322 of
--     370. Of the 32 taken orders it would refuse 27, among them 23 of the 27 that hurt an owner, and 4 of the 5 that
--     were good for every owner.
--   - Its 48 passes are not safe either: in hindsight 39 of them made some owner's cars worse off.
--   So the guard keeps rule 14 by refusing almost everything, not by telling which orders are fair. Since it went on,
--   the agent's per-tick orders have in effect been off (0 of 128 on 763734d4, 0 of 17 on 8c0b2e04).
--
-- ══ §5 WHAT IT MEANS FOR THE PLAN ══════════════════════════════════════════════════════════════════════════════════
--
--   - G508's priced depot totals understate the problem: a price on the depot's sum still lets one owner pay for
--     another. E2's verdict has to be per owner (E7) with rule 14 as a constraint, and its per-owner estimates have to
--     be calibrated (E4) before any bar reads them; today they are close to a coin.
--   - D5 is supported: the agent's per-tick charge orders add little the kernel's own fair line does not, and when the
--     referee took them they mostly moved one owner's minutes onto another.
--   - Keep the owner guard on (it is) until E2 replaces it.
--
-- ══ §6 WHAT WAS NOT VERIFIED ═══════════════════════════════════════════════════════════════════════════════════════
--
--   - Hindsight is the grader's: the pure scheduler re-run with what happened in the window, not the world itself.
--   - Each owner judged lexicographically, the engine's own yardstick; no prices per owner (D4 sets none).
--   - Independence: 25 runs, 18 keys. Counts, not significance tests.
--   - Per-owner minutes past the contract wait exist for 329 of the 370 (the rest predate 0642); those 41 are judged
--     on on-time cars, lateness and minutes in the depot, as the engine judged them.

-- (1) LAB. The replay reproduces production's grades (run replay.sql first).
SELECT count(*) AS decisions, count(*) FILTER (WHERE expected_reproduced) AS expected_reproduced,
       count(*) FILTER (WHERE hindsight_reproduced) AS hindsight_reproduced,
       count(*) FILTER (WHERE owner_neutral) AS owner_neutral, count(*) FILTER (WHERE taken) AS taken
  FROM research.referee_replay;

-- (2) LAB. Each decision's per-owner class, by the grader's label (run analysis.sql first).
SELECT outcome, hindsight_class, count(*) FROM research.referee_owner_verdicts GROUP BY 1, 2 ORDER BY 1, 2;

-- (3) LAB. Owner by owner, better / worse / no different.
SELECT owner_name, count(*) FILTER (WHERE h_cmp > 0) AS agent_better, count(*) FILTER (WHERE h_cmp < 0) AS agent_worse,
       count(*) FILTER (WHERE h_cmp = 0) AS no_different
  FROM research.referee_per_owner GROUP BY 1 ORDER BY 1;

-- (4) PRODUCTION, read-only. The owner guard at the twin depot.
SELECT scope_type, scope_id, param_value, updated_by, updated_at
  FROM public.ottoq_policy_params WHERE param_key = 'agent_charge_order_owner_guard' AND scope_type <> 'run';
