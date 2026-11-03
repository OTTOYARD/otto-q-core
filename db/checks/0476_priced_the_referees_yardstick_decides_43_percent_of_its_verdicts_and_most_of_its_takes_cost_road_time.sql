-- 0476  **Priced, the referee's yardstick changes the answer: for 140 of 329 past decisions (43%) which order was
--        better depends only on what lateness, contract wait and time out at work are worth; at equal prices 17 of
--        the 29 orders the check took cost the depot more than they gained.**
--        -> G508 (new). Frontier plan Phase 0, item 2 (docs/FRONTIER_PLAN_2026-11-03.md §5, E2, D4). Chase,
--        2026-11-03: "Okay BEGIN", with equal owner weights until he sets prices.
--        Read against gxdrcyphqjzjsuhxuqtg, read-only, at 15:46:00 and 15:46:23 UTC (9:46 AM CT). Twin depot only
--        (rule 8). Decision set: 0708's (0475): 370 graded decisions since 2026-10-01, of which 329 store all four
--        depot components (on-time cars, lateness, minutes past the contract wait, minutes out at work) for both orders,
--        in both the check's expected future and the grader's hindsight.
--
-- ══ THE YARDSTICK BEING TESTED ════════════════════════════════════════════════════════════════════════════════════════
--
--   The check ranks a future lexicographically: on-time cars, then lateness, then minutes past the contract wait, then
--   flow. Here on-time cars stay first (a hard level: rule 9 readiness), and below it one priced score per order:
--       score = - (p_late x lateness_min + p_wait x minutes_past_contract_wait) + p_out x minutes_out_at_work
--   over 63 price points: p_late and p_wait in {0, 1, 2, 5}, p_out in {0, 0.5, 1, 2}, all-zero left out. Flow is left
--   out because inside one window it is nearly the complement of minutes out at work (counting both counts one thing
--   twice). Depot totals only: the per-owner split is stored for 24 decisions (plan §4 E2), so rule 14's per-owner
--   reading waits for the lab's replay.
--
-- ══ §1 HOW MANY VERDICTS DEPEND ON THE PRICES (reproduce: (1)) ═══════════════════════════════════════════════════════
--
--     in hindsight, over all 63 prices                        decisions
--     the agent's order never worse, and better at some price     46
--     the kernel's order never worse, and better at some price   101
--     the same outcome at every price                             42
--     the winner depends on the price                            140   (85 of them the lexicographic yardstick called
--                                                                        for the agent)
--     total                                                      329
--
--   (1)'s "_incl_ties" columns count an every-price tie in both; the table above removes the 42 from each (re-read at
--   15:47:19 UTC with strict counts: 42 / 46 / 101 / 140).
--
-- ══ §2 AT EQUAL PRICES (p_late = p_wait = p_out = 1) (reproduce: (2)) ═════════════════════════════════════════════════
--
--     the grader's label        decisions   agent better   kernel better   same
--     missed_win (refused)         126            65              60           1
--     right_refusal                174            25             108          41
--     right_take (taken)            20            10              10           0
--     wrong_take (taken)             9             2               7           0
--
--   (a) Half the "missed wins" were losses once time out at work counts (60 of 126; the plan's §2.2 read the same
--       effect on 2026-11-02 as a mean 18.6 more minutes out at work under the kernel's order).
--   (b) The check's takes: the agent's order was better on 12 of the 29 it took. Its refusals: the kernel's order was
--       better on 168 of the 258 refusals with a winner. The take side is where the lexicographic yardstick hurts: the
--       check's own futures rank by it, so it takes orders that win on lateness and lose time on the road.
--   (c) The check's expected future agrees with hindsight on 175 of 329 under equal prices and on 175 under its own
--       lexicographic yardstick; weighting time out at work higher (p_out = 2, p_late = 0, p_wait = 1) raises it to
--       194. So a priced yardstick does not by itself make the check's futures better predictors; it changes which
--       orders it should take.
--
-- ══ §3 WHAT IT MEANS FOR THE BUILD ════════════════════════════════════════════════════════════════════════════════════
--
--   - D4 (owners' prices) is not a formality: it decides 43% of the verdicts. Until Chase sets prices, E2 reports both
--     the every-price answer (46 / 101 / 42) and the equal-price answer, and takes nothing that depends on prices alone.
--   - The lexicographic "missed wins" (141 on 2026-11-02, plan §2.1) overstate what the agent leaves on the table.
--   - Limits: depot totals, not per owner; the grader's simulated hindsight (overlapping windows), not the world's;
--     18 keys, all busy_day (0475); single readings, not ranges.
--
-- ══ REPRODUCE ═════════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) Every price point, and the equal-price slice.
WITH g AS (
  SELECT g.order_id, g.taken, g.outcome, g.expected AS e, g.hindsight AS h,
         CASE WHEN g.outcome IN ('missed_win','right_take') THEN 1 ELSE -1 END AS lex_h
    FROM public.ottoq_charge_order_grades g
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.decision AND g.p_win IS NOT NULL
     AND g.graded_at >= '2026-10-01' AND g.graded_at < '2026-11-04'
     AND g.outcome IN ('missed_win','right_take','right_refusal','wrong_take')
), c AS (
  SELECT order_id, taken, lex_h,
    (e->>'cmp')::int AS lex_e_cmp,
    (h->'agent'->>'on_time')::numeric AS h_ota, (h->'kernel'->>'on_time')::numeric AS h_otk,
    (h->'agent'->>'late_sum')::numeric AS h_la, (h->'kernel'->>'late_sum')::numeric AS h_lk,
    (h->'agent'->>'breach_sum')::numeric AS h_ba, (h->'kernel'->>'breach_sum')::numeric AS h_bk,
    (h->'agent'->>'out_min')::numeric AS h_oa, (h->'kernel'->>'out_min')::numeric AS h_ok,
    (e->'agent'->>'on_time')::numeric AS e_ota, (e->'kernel'->>'on_time')::numeric AS e_otk,
    (e->'agent'->>'late_sum')::numeric AS e_la, (e->'kernel'->>'late_sum')::numeric AS e_lk,
    (e->'agent'->>'breach_sum')::numeric AS e_ba, (e->'kernel'->>'breach_sum')::numeric AS e_bk,
    (e->'agent'->>'out_min')::numeric AS e_oa, (e->'kernel'->>'out_min')::numeric AS e_ok
  FROM g
), cc AS (
  SELECT * FROM c WHERE h_ba IS NOT NULL AND h_bk IS NOT NULL AND h_oa IS NOT NULL AND h_ok IS NOT NULL
                    AND e_ba IS NOT NULL AND e_bk IS NOT NULL AND e_oa IS NOT NULL AND e_ok IS NOT NULL
), grid AS (
  SELECT a::numeric AS pl, b::numeric AS pb, o::numeric AS po
    FROM (VALUES (0),(1),(2),(5)) A(a), (VALUES (0),(1),(2),(5)) B(b), (VALUES (0),(0.5),(1),(2)) O(o)
   WHERE NOT (a = 0 AND b = 0 AND o = 0)
), v AS (
  SELECT cc.order_id, cc.taken, cc.lex_h, cc.lex_e_cmp, grid.pl, grid.pb, grid.po,
    CASE WHEN h_ota <> h_otk THEN sign(h_ota - h_otk)
         ELSE sign((-(pl*h_la + pb*h_ba) + po*h_oa) - (-(pl*h_lk + pb*h_bk) + po*h_ok)) END AS hv,
    CASE WHEN e_ota <> e_otk THEN sign(e_ota - e_otk)
         ELSE sign((-(pl*e_la + pb*e_ba) + po*e_oa) - (-(pl*e_lk + pb*e_bk) + po*e_ok)) END AS ev
  FROM cc, grid
), per_dec AS (
  SELECT order_id, max(lex_h) AS lex_h,
         count(DISTINCT hv) FILTER (WHERE hv <> 0) AS hv_signs,
         bool_and(hv >= 0) AS never_kernel, bool_and(hv <= 0) AS never_agent
    FROM v GROUP BY order_id
), eq AS (SELECT * FROM v WHERE pl = 1 AND pb = 1 AND po = 1
)
SELECT now() AS read_at,
  (SELECT count(*) FROM g) AS decisions_all, (SELECT count(*) FROM cc) AS decisions_with_all_components,
  (SELECT count(*) FROM grid) AS price_points,
  (SELECT count(*) FILTER (WHERE hv_signs <= 1 AND never_kernel) FROM per_dec) AS agent_better_at_every_price_incl_ties,
  (SELECT count(*) FILTER (WHERE hv_signs <= 1 AND never_agent) FROM per_dec) AS kernel_better_at_every_price_incl_ties,
  (SELECT count(*) FILTER (WHERE hv_signs = 0) FROM per_dec) AS same_at_every_price,
  (SELECT count(*) FILTER (WHERE hv_signs = 2) FROM per_dec) AS winner_depends_on_price,
  (SELECT count(*) FILTER (WHERE hv_signs = 2 AND lex_h = 1) FROM per_dec) AS depends_and_lex_said_agent,
  (SELECT json_build_object('agent_better', count(*) FILTER (WHERE hv > 0), 'kernel_better', count(*) FILTER (WHERE hv < 0),
          'tie', count(*) FILTER (WHERE hv = 0), 'lex_agent_better', count(*) FILTER (WHERE lex_h = 1),
          'agree_with_lex', count(*) FILTER (WHERE sign(hv) = lex_h),
          'check_expected_agrees_with_hindsight_priced', count(*) FILTER (WHERE ev = hv AND hv <> 0),
          'check_expected_agrees_with_hindsight_lex', count(*) FILTER (WHERE sign(lex_e_cmp) = lex_h),
          'taken', count(*) FILTER (WHERE taken), 'taken_agent_better_priced', count(*) FILTER (WHERE taken AND hv > 0))
     FROM eq) AS at_equal_prices;

-- (2) Equal prices, by the grader's label.
WITH g AS (
  SELECT g.outcome, g.expected AS e, g.hindsight AS h
    FROM public.ottoq_charge_order_grades g
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.decision AND g.p_win IS NOT NULL
     AND g.graded_at >= '2026-10-01' AND g.graded_at < '2026-11-04'
     AND g.outcome IN ('missed_win','right_take','right_refusal','wrong_take')
), c AS (
  SELECT outcome,
    CASE WHEN (h->'agent'->>'on_time')::numeric <> (h->'kernel'->>'on_time')::numeric
         THEN sign((h->'agent'->>'on_time')::numeric - (h->'kernel'->>'on_time')::numeric)
         ELSE sign((-((h->'agent'->>'late_sum')::numeric + (h->'agent'->>'breach_sum')::numeric) + (h->'agent'->>'out_min')::numeric)
                 - (-((h->'kernel'->>'late_sum')::numeric + (h->'kernel'->>'breach_sum')::numeric) + (h->'kernel'->>'out_min')::numeric)) END AS hv
  FROM g
  WHERE h->'agent' ? 'breach_sum' AND h->'kernel' ? 'breach_sum' AND h->'agent' ? 'out_min' AND h->'kernel' ? 'out_min'
    AND e->'agent' ? 'breach_sum' AND e->'kernel' ? 'breach_sum' AND e->'agent' ? 'out_min' AND e->'kernel' ? 'out_min'
)
SELECT now() AS read_at, outcome, count(*) AS n,
       count(*) FILTER (WHERE hv > 0) AS agent_better_equal_prices,
       count(*) FILTER (WHERE hv < 0) AS kernel_better_equal_prices,
       count(*) FILTER (WHERE hv = 0) AS same
FROM c GROUP BY outcome ORDER BY outcome;
