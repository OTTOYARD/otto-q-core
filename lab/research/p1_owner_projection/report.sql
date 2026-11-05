-- lab/research/p1_owner_projection/report.sql -- run in the lab copy that projection.py wrote (LAB ONLY).
-- The agent's orders with every owner keeping its places, against the same orders as the agent gave them
-- (research.referee_owner_futures and research.referee_per_owner, lab/research/p0_ and p1_).
\set ON_ERROR_STOP on
\pset footer off

\echo '== (1) the projection: how many places it moved, per order'
SELECT count(*) AS orders, round(avg(n_line), 1) AS line_cars, round(avg(n_ranked), 1) AS agent_ranked,
       count(*) FILTER (WHERE moved = 0) AS projection_is_kernels_own,
       round(avg(moved), 1) AS places_moved
  FROM research.owner_projection2_orders;

\echo '== (2) per decision, in hindsight (s = -1): the projected order owner by owner against the kernel''s own'
WITH h AS (
  SELECT order_id, count(*) FILTER (WHERE cmp > 0) AS better, count(*) FILTER (WHERE cmp < 0) AS worse
    FROM research.owner_projection2 WHERE s = -1 GROUP BY 1),
c AS (
  SELECT h.*, CASE WHEN better > 0 AND worse = 0 THEN 'good_for_every_owner'
                   WHEN worse > 0 AND better = 0 THEN 'bad_for_every_owner'
                   WHEN better > 0 AND worse > 0 THEN 'trades_one_owner_for_another'
                   ELSE 'no_owner_changes' END AS cls FROM h)
SELECT cls AS projected_in_hindsight, count(*) FROM c GROUP BY 1 ORDER BY 2 DESC;

\echo '== (3) the same decisions, the agent''s order as given (0478''s hindsight classes)'
SELECT hindsight_class AS as_given_in_hindsight, count(*) FROM research.referee_owner_verdicts GROUP BY 1 ORDER BY 2 DESC;

\echo '== (4) side by side, per decision: as given -> projected (hindsight)'
WITH h AS (
  SELECT order_id, count(*) FILTER (WHERE cmp > 0) AS better, count(*) FILTER (WHERE cmp < 0) AS worse
    FROM research.owner_projection2 WHERE s = -1 GROUP BY 1),
p AS (SELECT order_id, CASE WHEN better > 0 AND worse = 0 THEN 'good' WHEN worse > 0 AND better = 0 THEN 'bad'
                            WHEN better > 0 AND worse > 0 THEN 'trades' ELSE 'none' END AS projected FROM h)
SELECT CASE v.hindsight_class WHEN 'good_for_every_owner' THEN 'good' WHEN 'bad_for_every_owner' THEN 'bad'
                              WHEN 'trades_one_owner_for_another' THEN 'trades' ELSE 'none' END AS as_given,
       p.projected, count(*)
  FROM research.referee_owner_verdicts v JOIN p USING (order_id) GROUP BY 1, 2 ORDER BY 1, 2;

\echo '== (5) the futures the check would roll (s = 0..11): futures in which the projected order is good for every owner'
WITH f AS (
  SELECT order_id, s, count(*) FILTER (WHERE cmp > 0) AS better, count(*) FILTER (WHERE cmp < 0) AS worse
    FROM research.owner_projection2 WHERE s >= 0 GROUP BY 1, 2),
d AS (SELECT order_id, count(*) FILTER (WHERE better > 0 AND worse = 0) AS good_futures,
             count(*) FILTER (WHERE worse > 0) AS futures_some_owner_worse, count(*) AS futures FROM f GROUP BY 1)
SELECT count(*) AS decisions,
       count(*) FILTER (WHERE good_futures >= 10) AS good_in_10_of_12,
       count(*) FILTER (WHERE futures_some_owner_worse = 0) AS no_owner_worse_in_any_future,
       max(good_futures) AS most_good_futures,
       round(avg(good_futures), 2) AS mean_good_futures,
       round(avg(futures_some_owner_worse), 2) AS mean_futures_some_owner_worse
  FROM d;

\echo '== (6) a fair referee on projected orders: take when no owner is worse in the expected future and in 10 of 12, some better in the expected one; judged in hindsight'
WITH f AS (
  SELECT order_id, s, count(*) FILTER (WHERE cmp > 0) AS better, count(*) FILTER (WHERE cmp < 0) AS worse
    FROM research.owner_projection2 WHERE s >= 0 GROUP BY 1, 2),
t AS (
  SELECT order_id,
         bool_or(s = 0 AND worse = 0 AND better > 0) AS expected_fair_win,
         count(*) FILTER (WHERE worse = 0) AS futures_no_owner_worse
    FROM f GROUP BY 1),
h AS (
  SELECT order_id, count(*) FILTER (WHERE cmp > 0) AS better, count(*) FILTER (WHERE cmp < 0) AS worse
    FROM research.owner_projection2 WHERE s = -1 GROUP BY 1)
SELECT bar, count(*) FILTER (WHERE take) AS takes,
       count(*) FILTER (WHERE take AND h.better > 0 AND h.worse = 0) AS good_for_every_owner,
       count(*) FILTER (WHERE take AND h.worse > 0) AS some_owner_worse,
       count(*) FILTER (WHERE take AND h.worse = 0 AND h.better = 0) AS no_change
  FROM t JOIN h USING (order_id)
  CROSS JOIN LATERAL (VALUES (6), (8), (10), (12)) b(bar)
  CROSS JOIN LATERAL (SELECT t.expected_fair_win AND t.futures_no_owner_worse >= b.bar AS take) k
 GROUP BY bar ORDER BY bar;

\echo '== (7) owner by owner in hindsight: better / worse / no different for that owner''s cars'
SELECT COALESCE(fo.name, p.owner) AS owner, count(*) FILTER (WHERE cmp > 0) AS better,
       count(*) FILTER (WHERE cmp < 0) AS worse, count(*) FILTER (WHERE cmp = 0) AS no_different
  FROM research.owner_projection2 p LEFT JOIN public.fleet_operators fo ON fo.id::text = p.owner
 WHERE s = -1 GROUP BY 1 ORDER BY 1;
