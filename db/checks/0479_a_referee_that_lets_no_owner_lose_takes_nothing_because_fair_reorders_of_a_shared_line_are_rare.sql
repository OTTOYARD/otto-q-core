-- 0479  **A referee that lets no owner lose takes nothing: in the 370 past decisions, reordering the shared charge line
--        was good for every owner 35 times in hindsight, and the referee's own futures never showed it in more than 8
--        of 12. Moving one owner's car up the line moves another owner's car down.**
--        -> G512 (new). Frontier plan Phase 1, E2 and E7: the first replay report ("the verdict each candidate rule would
--        have given and how it fares in hindsight"). Chase, 2026-11-04: "keep going".
--        Measured in the research lab on the replay set of 0478 (370 decisions at the twin depot since 2026-10-01, 25
--        runs), 2026-11-05 01:22-01:38 UTC (7:22-7:38 PM CT 2026-11-04). Scripts and output:
--        lab/research/p1_referee_owner_futures/. Rule 8: twin depot only. Nothing here touches production.
--
-- ══ §1 THE LAB RUNS THE REFEREE'S OWN FUTURES (futures.sql; rules.sql (1)) ════════════════════════════════════════
--
--   For each decision, the 12 futures the referee rolled when it decided (the expected one and 11 sampled, the same
--   seed and the same draws for both orders: ottoq_charge_line_rollout), re-run with each car's owner in the state.
--   Against what the referee recorded:
--     wins in 12 futures as recorded                       370 of 370
--     the referee's verdict as recorded                    370 of 370   (v2 before the owner guard, v2 with it after)
--   So the candidate rules below are decided from exactly the futures the referee saw.
--
-- ══ §2 THE RULES, JUDGED OWNER BY OWNER IN HINDSIGHT (rules.sql (2)) ═════════════════════════════════════════════
--
--     rule                                                    takes  good for     trades one   bad for   good ones
--                                                                    every owner  owner for    every     refused
--                                                                                 another      owner     (of 35)
--     v2: the referee before 0784 (better in the expected       32       5           22           5         30
--         future and in 10 of 12)
--     v2 + 0784's owner guard (on since 2026-10-25)              5       1            3           1         34
--     fair_10: the depot better and no owner worse in 10 of 12   0       0            0           0         35
--     pareto_10: no owner worse, some better, in 10 of 12        0       0            0           0         35
--     pareto_12: the same in all 12                              0       0            0           0         35
--
--   A looser bar (rules.sql (4)): no owner worse and some better in the expected future and in at least t of 12:
--     t = 1: 36 takes (3 good for every owner, 1 changing nothing, 29 trades, 3 bad) ... t = 5: 9 (2, 0, 6, 1) ...
--     t = 8: 2 (0, 0, 2, 0); t = 9: 0.
--   No bar picks out mostly fair orders.
--
-- ══ §3 WHY: A SHARED LINE IS CLOSE TO ZERO-SUM BETWEEN OWNERS (rules.sql (3), (5)) ═════════════════════════════════
--
--   - In hindsight 35 of 370 orders were good for every owner (9.5%); 250 traded one owner for another (0478).
--   - In the referee's futures, 153 of 370 decisions had no future in which the agent's order was good for every owner;
--     the most any decision had was 8 of 12. More such futures go with fairer hindsight, weakly: 13 of 70 decisions
--     with 3 or more were good for every owner in hindsight, against 22 of 300 with fewer.
--   - The kernel's line (0642) already serves every car alike. An agent order that reorders it moves some cars up and
--     some down, and with three owners sharing one line those cars rarely all belong to the same owner.
--
-- ══ §4 WHAT IT MEANS FOR THE PLAN (a recommendation; D5 and E2's shape are Chase's call) ══════════════════════════
--
--   - A better referee for today's agent orders cannot fix this: the orders themselves trade owners. Keep 0784's guard
--     on (it is) while they run.
--   - Rule 14's own form points at the answer: a rule added for the depot's sake "may trade places only among one
--     owner's own cars", as 0781's exit key does (each owner's cars reordered among the places that owner's cars
--     hold). An agent order projected the same way, each owner keeping its places, is fair to the other owners by
--     construction, and E2 then only has to judge whether it helps that owner's own cars (E7).
--   - Or move the agent off per-tick charge orders altogether (D5) and give its effort to E6's search for a better
--     kernel key, where the same constraint applies.
--
-- ══ §5 WHAT WAS NOT VERIFIED ═══════════════════════════════════════════════════════════════════════════════════════
--
--   - Hindsight is the grader's simulated hindsight (0478 §6). Owners judged on the engine's yardstick, unpriced.
--   - 370 decisions from 25 runs and 18 keys: counts, not tests.
--   - The within-owner projection is not built or replayed; §4 says what it would require, not how it would fare.

-- (1) LAB. The futures reproduce the referee (run futures.sql on every worker, then rules.sql).
SELECT count(*) AS decisions, count(*) FILTER (WHERE wins = wins_recorded) AS wins_as_recorded,
       count(*) FILTER (WHERE (CASE WHEN recorded_with_owners THEN v2_guard ELSE v2 END) = taken_recorded) AS verdict_as_recorded
  FROM research.referee_rules;

-- (2) LAB. Each rule's takes, owner by owner in hindsight.
SELECT count(*) FILTER (WHERE v2) AS v2, count(*) FILTER (WHERE v2 AND hindsight_class = 'good_for_every_owner') AS v2_good,
       count(*) FILTER (WHERE v2_guard) AS v2_guard, count(*) FILTER (WHERE fair_10) AS fair_10,
       count(*) FILTER (WHERE pareto_10) AS pareto_10, count(*) FILTER (WHERE pareto_12) AS pareto_12
  FROM research.referee_rules;

-- (3) LAB. How rare a fair improvement is.
SELECT count(*) FILTER (WHERE hindsight_class = 'good_for_every_owner') AS good_for_every_owner, count(*) AS decisions,
       max(pareto) AS most_futures_good_for_every_owner, count(*) FILTER (WHERE pareto = 0) AS none
  FROM research.referee_rules;
