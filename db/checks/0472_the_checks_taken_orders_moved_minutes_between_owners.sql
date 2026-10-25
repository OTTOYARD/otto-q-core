-- 0472  **The check takes an agent's charge order on the depot's totals, so most of the orders it took made one fleet's
--        cars wait longer or finish later so another fleet's did better: 23 of the 29 taken at the twin depot in ten
--        days left an owner worse off in the check's own expected future.** -> G504; 0784.
--        Chase, 2026-10-24: "As long as you're not assuming others will be okay with their vehicle services/charges
--        waiting for others in a curteous way ... we don't own our own vehicles, we manage for others" (CLAUDE.md rule 14).
--        Read-only against gxdrcyphqjzjsuhxuqtg, the twin depot (rule 8): query (1) at 23:53:28 UTC on 2026-10-24
--        (6:53 PM CT), query (2) at 23:56:18 UTC (6:56 PM CT), query (3) at 00:00:37 UTC on 2026-10-25 (7:00 PM CT on
--        the 24th), each clock read by the query itself.
--
-- ══ §1 WHAT DECIDED THE ORDERS THE CHECK TOOK (reproduce: (1), (3)) ══════════════════════════════════════════════════
--
--   In the ten days to 2026-10-25 00:00 UTC the check judged 976 agent charge orders at the twin depot on 10 runs: 723
--   were the kernel's own order ('same_as_kernel') and 29 were taken (accepted or partial, 'wins_most_futures'), on six
--   runs (3389e651, 67290d0a, 78c0624c, b5e80522, c6ec017d, ecf3a3bc), between 2026-10-20 21:08 and 2026-10-24 04:07
--   UTC. Every taken order was decided by lateness or by minutes past the contract's queue wait; none by minutes in the
--   depot alone. Both are the depot's totals, summed over every owner's cars (ottoq_charge_line_compare).
--
-- ══ §2 EACH OWNER, IN THE CHECK'S OWN EXPECTED FUTURE (reproduce: (2)) ════════════════════════════════════════════════
--
--   Each taken order replayed from its snapshot (ottoq_charge_order_snapshots: the state, the order and the seed the
--   check read) on the live simulator at scenario 0, under the kernel's order and the agent's, each owner's cars
--   (vehicles.fleet_operator_id) summed as the check sums the line, and each owner compared as the check compares the
--   line: cars ready by their due time, then minutes late (half a minute), then minutes past contract wait over both
--   visits (a minute), then minutes in the depot over both visits (a minute). The replay is the check's: summed over
--   owners it gives the check's own recorded totals (minutes past contract wait to 0.1 minute on the six orders
--   compared, 921, 1376, 1412, 1472, 1540 and 1658; minutes in the depot on five of the six, all but 921, where the
--   replay leaves out returns not seated inside the horizon, whose minutes the trace does not carry).
--
--     owners worse off      orders   which
--     none                       6   1375, 1424, 1472, 1539, 1651, 1653
--     one or more, on lateness
--       or contract wait        18   921, 948, 1372, 1376, 1412, 1430, 1434, 1446, 1467, 1541, 1548, 1549, 1649,
--                                    1654, 1658, 1659, 1660, 1712
--     one or more, on minutes
--       in the depot alone       5   1368, 1540, 1620, 1635, 1722 (approximate, as above)
--
--   The largest, in minutes (agent's order less the kernel's; negative is better for that owner):
--     948   past contract wait: Tesla Robotaxi TN +328.0, Waymo Nashville -83.7, Zoox Southeast -549.0
--     1376  past contract wait: Waymo +89.1, Tesla -50.3, Zoox -73.5
--     921   late: Tesla +82.0, Zoox -148.0, Waymo -1.6
--     1412  past contract wait: Zoox +55.3, Tesla -51.9, Waymo -41.6
--     1660  past contract wait: Tesla +30.7, Waymo -38.6, Zoox -23.5
--
--   An order that moves minutes inside one owner's own cars is the owner's own trade (1472: Waymo's cars 1.4 minutes
--   less late for 47.2 more minutes past contract wait, its own); the guard compares each owner's sides as the line is
--   compared, so such an order is taken when no other owner pays.
--
-- ══ §3 WHAT THIS IS NOT ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   The expected future only, on the code that judged these orders: all 29 snapshots carry code md5 f5e7e90a (the
--   simulator, comparison, rollout and verdict together), and so does the live code, read at 00:08:41 UTC on
--   2026-10-25 (7:08 PM CT on the 24th). The sampled futures each order also had to win are not replayed. A projection, not what
--   happened: the hindsight grader (0621) judges outcomes and still does so on the depot's totals. Six runs of one
--   depot: single readings, not ranges.

-- (1) the orders the check judged, by day, status, reason and what decided the expected future
SELECT now() AS read_at, date_trunc('day', o.recorded_at)::date AS day, o.status,
       COALESCE(o.projection ->> 'reason', '-') AS reason,
       COALESCE(o.projection ->> 'expected_by', '-') AS expected_by,
       count(*) AS orders, count(DISTINCT o.sim_run_id) AS runs
  FROM public.ottoq_agent_charge_orders o
 WHERE o.depot_id = '11111111-1111-1111-1111-111111111111'
   AND o.recorded_at >= now() - interval '10 days'
 GROUP BY 2, 3, 4, 5 ORDER BY 2 DESC, 6 DESC;

-- (2) each owner, in each taken order's expected future, under the kernel's order and the agent's
WITH t AS (
  SELECT o.order_id, o.recorded_at, o.status, o.projection ->> 'expected_by' AS by, s.state, s.agent_order, s.seed,
         COALESCE((s.state ->> 'horizon_min')::numeric, 480) AS hor
    FROM public.ottoq_agent_charge_orders o JOIN public.ottoq_charge_order_snapshots s ON s.order_id = o.order_id
   WHERE o.depot_id = '11111111-1111-1111-1111-111111111111' AND o.recorded_at >= now() - interval '10 days'
     AND o.status IN ('accepted', 'partial') AND o.projection ->> 'reason' = 'wins_most_futures'
), sim AS (
  SELECT t.*, public.ottoq_charge_line_schedule(t.state, NULL, 0, t.seed, true) AS k,
              public.ottoq_charge_line_schedule(t.state, t.agent_order, 0, t.seed, true) AS a
    FROM t
), facts AS (
  SELECT DISTINCT ON (sim.order_id, c.value ->> 'id') sim.order_id, c.value ->> 'id' AS id,
         COALESCE((c.value ->> 'w')::numeric, 0) AS w0, (c.value ->> 'mw')::numeric AS mw,
         (c.value ->> 'due')::numeric AS due, LEAST((c.value ->> 'md')::numeric, (c.value ->> 'ml')::numeric) AS mm
    FROM sim CROSS JOIN LATERAL jsonb_array_elements(COALESCE(sim.state -> 'cars', '[]') || COALESCE(sim.state -> 'inbound', '[]'))
         WITH ORDINALITY c(value, o)
   ORDER BY sim.order_id, c.value ->> 'id', c.o
), rows_ AS (
  SELECT sim.order_id, z.side, y.value ->> 'id' AS id, false AS ret,
         (y.value ->> 's0')::numeric AS s0, (y.value ->> 'r')::numeric AS r, (y.value ->> 'a')::numeric AS av, false AS past, sim.hor
    FROM sim CROSS JOIN LATERAL (SELECT 'k' AS side, sim.k AS j UNION ALL SELECT 'a', sim.a) z
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(z.j -> 'seats', '[]')) y
  UNION ALL
  SELECT sim.order_id, z.side, y.value ->> 'id', true, (y.value ->> 's0')::numeric, (y.value ->> 'r')::numeric,
         (y.value ->> 'a')::numeric, COALESCE((y.value ->> 'past')::boolean, false), sim.hor
    FROM sim CROSS JOIN LATERAL (SELECT 'k' AS side, sim.k AS j UNION ALL SELECT 'a', sim.a) z
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(z.j -> 'return_seats', '[]')) y
), per AS (
  SELECT r.order_id, COALESCE(fo.name, 'none') AS owner, r.side,
         count(*) FILTER (WHERE NOT r.ret AND f.due IS NOT NULL AND r.r IS NOT NULL AND r.r <= f.due) AS on_time,
         COALESCE(sum(GREATEST(COALESCE(r.r, r.hor + f.mm) - f.due, 0)) FILTER (WHERE NOT r.ret AND f.due IS NOT NULL), 0) AS late,
         COALESCE(sum(GREATEST(CASE WHEN r.ret THEN 0 ELSE f.w0 END + COALESCE(r.s0, r.hor) - r.av - f.mw, 0))
                  FILTER (WHERE f.mw IS NOT NULL AND NOT r.past), 0) AS breach2,
         COALESCE(sum(COALESCE(r.r, r.hor + f.mm) - r.av) FILTER (WHERE NOT r.ret), 0)
           + COALESCE(sum(r.r - r.av) FILTER (WHERE r.ret AND NOT r.past AND r.r IS NOT NULL), 0) AS flow
    FROM rows_ r LEFT JOIN facts f ON f.order_id = r.order_id AND f.id = r.id
    LEFT JOIN public.vehicles v ON v.id::text = r.id LEFT JOIN public.fleet_operators fo ON fo.id = v.fleet_operator_id
   GROUP BY 1, 2, 3
), cmp AS (
  SELECT k.order_id, k.owner,
         CASE WHEN a.on_time > k.on_time THEN 1 WHEN a.on_time < k.on_time THEN -1
              WHEN a.late < k.late - 0.5 THEN 1 WHEN a.late > k.late + 0.5 THEN -1
              WHEN a.breach2 < k.breach2 - 1.0 THEN 1 WHEN a.breach2 > k.breach2 + 1.0 THEN -1
              WHEN a.flow < k.flow - 1.0 THEN 1 WHEN a.flow > k.flow + 1.0 THEN -1 ELSE 0 END AS c,
         CASE WHEN a.on_time <> k.on_time THEN 'on_time' WHEN abs(a.late - k.late) > 0.5 THEN 'lateness'
              WHEN abs(a.breach2 - k.breach2) > 1.0 THEN 'contract_wait' WHEN abs(a.flow - k.flow) > 1.0 THEN 'flow'
              ELSE 'tie' END AS by,
         round(a.late - k.late, 1) AS d_late, round(a.breach2 - k.breach2, 1) AS d_breach2, round(a.flow - k.flow, 1) AS d_flow
    FROM per k JOIN per a ON a.order_id = k.order_id AND a.owner = k.owner AND a.side = 'a'
   WHERE k.side = 'k'
)
SELECT now() AS read_at, t.order_id, t.status, t.by AS check_by,
       count(*) FILTER (WHERE cmp.c = -1) AS owners_worse, count(*) FILTER (WHERE cmp.c = 1) AS owners_better,
       string_agg(cmp.owner || ':' || cmp.c || '/' || cmp.by || ' late ' || cmp.d_late || ' breach2 ' || cmp.d_breach2
                  || ' flow ' || cmp.d_flow, ' | ' ORDER BY cmp.owner) AS per_owner
  FROM t JOIN cmp ON cmp.order_id = t.order_id
 GROUP BY t.order_id, t.status, t.by ORDER BY t.order_id;

-- (3) the window: orders judged, taken, the kernel's own, runs, and the first and last taken
SELECT now() AS read_at,
       count(*) AS orders_judged,
       count(*) FILTER (WHERE o.status IN ('accepted', 'partial') AND o.projection ->> 'reason' = 'wins_most_futures') AS taken,
       count(*) FILTER (WHERE o.projection ->> 'reason' = 'same_as_kernel') AS same_as_kernel,
       count(DISTINCT o.sim_run_id) AS runs,
       min(o.recorded_at) FILTER (WHERE o.status IN ('accepted', 'partial') AND o.projection ->> 'reason' = 'wins_most_futures') AS first_taken,
       max(o.recorded_at) FILTER (WHERE o.status IN ('accepted', 'partial') AND o.projection ->> 'reason' = 'wins_most_futures') AS last_taken,
       string_agg(DISTINCT left(o.sim_run_id::text, 8), ', ')
         FILTER (WHERE o.status IN ('accepted', 'partial') AND o.projection ->> 'reason' = 'wins_most_futures') AS taken_runs
  FROM public.ottoq_agent_charge_orders o
 WHERE o.depot_id = '11111111-1111-1111-1111-111111111111' AND o.recorded_at >= now() - interval '10 days';
