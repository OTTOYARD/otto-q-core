-- lab/research/p1_referee_owner_futures/rules.sql -- run in the LAB after futures.sql (all workers) and
-- lab/research/p0_referee_per_owner/analysis.sql. Candidate referee rules, each decided from the referee's own 12
-- futures, each judged by what happened (hindsight, owner by owner: research.referee_owner_verdicts).
--   v2           the referee before 0784: better in the expected future, and better in at least 10 of 12 futures
--   v2_guard     v2, and no owner worse in the expected future (0784's owner guard; on at the twin depot since 10-25)
--   fair_10      better in the expected future with no owner worse there, and in at least 10 of 12 futures the depot
--                better AND no owner worse
--   pareto_10    in the expected future and in at least 10 of 12: no owner worse and some owner better
--   pareto_12    the same, in all 12
\set ON_ERROR_STOP on
\pset footer off
DROP TABLE IF EXISTS research.referee_rules;
CREATE TABLE research.referee_rules AS
WITH f AS (
  SELECT order_id, s, max(depot_cmp) AS depot_cmp, min(depot_cmp) AS depot_cmp_min,
         count(*) FILTER (WHERE owner_cmp < 0) AS worse, count(*) FILTER (WHERE owner_cmp > 0) AS better
    FROM research.referee_owner_futures GROUP BY 1, 2
), d AS (
  SELECT order_id, count(*) AS n,
         bool_and(depot_cmp = depot_cmp_min) AS depot_consistent,
         max(depot_cmp) FILTER (WHERE s = 0) AS pcmp0,
         max(worse) FILTER (WHERE s = 0) AS worse0, max(better) FILTER (WHERE s = 0) AS better0,
         count(*) FILTER (WHERE depot_cmp = 1) AS wins,
         count(*) FILTER (WHERE depot_cmp = 1 AND worse = 0) AS fair_wins,
         count(*) FILTER (WHERE worse = 0 AND better > 0) AS pareto
    FROM f GROUP BY 1
)
SELECT d.*, g.wins AS wins_recorded, r.taken AS taken_recorded, r.recorded_with_owners,
       v.hindsight_class,
       (d.pcmp0 = 1 AND d.wins >= 10)                                        AS v2,
       (d.pcmp0 = 1 AND d.wins >= 10 AND d.worse0 = 0)                       AS v2_guard,
       (d.pcmp0 = 1 AND d.worse0 = 0 AND d.fair_wins >= 10)                  AS fair_10,
       (d.worse0 = 0 AND d.better0 > 0 AND d.pareto >= 10)                   AS pareto_10,
       (d.worse0 = 0 AND d.better0 > 0 AND d.pareto >= 12)                   AS pareto_12
  FROM d
  JOIN research.ottoq_charge_order_grades g USING (order_id)
  JOIN research.referee_replay r USING (order_id)
  JOIN research.referee_owner_verdicts v USING (order_id);

\echo '== (1) the futures reproduce what the referee recorded'
SELECT count(*) AS decisions, count(*) FILTER (WHERE n = 12) AS twelve_futures,
       count(*) FILTER (WHERE depot_consistent) AS depot_verdict_one_per_future,
       count(*) FILTER (WHERE wins = wins_recorded) AS wins_as_recorded,
       count(*) FILTER (WHERE (v2_guard AND recorded_with_owners) OR (v2 AND NOT recorded_with_owners)) AS would_take,
       count(*) FILTER (WHERE taken_recorded) AS took,
       count(*) FILTER (WHERE (CASE WHEN recorded_with_owners THEN v2_guard ELSE v2 END) = taken_recorded) AS same_verdict_as_recorded
  FROM research.referee_rules;

\echo '== (2) each rule: what it takes, judged owner by owner in hindsight'
SELECT rule, count(*) FILTER (WHERE takes) AS takes,
       count(*) FILTER (WHERE takes AND hindsight_class = 'good_for_every_owner')         AS good_for_every_owner,
       count(*) FILTER (WHERE takes AND hindsight_class = 'no_owner_changes')             AS no_owner_changes,
       count(*) FILTER (WHERE takes AND hindsight_class = 'trades_one_owner_for_another') AS trades_owners,
       count(*) FILTER (WHERE takes AND hindsight_class = 'bad_for_every_owner')          AS bad_for_every_owner,
       count(*) FILTER (WHERE NOT takes AND hindsight_class = 'good_for_every_owner')     AS good_ones_refused
  FROM research.referee_rules
 CROSS JOIN LATERAL (VALUES ('1 v2', v2), ('2 v2_guard', v2_guard), ('3 fair_10', fair_10),
                            ('4 pareto_10', pareto_10), ('5 pareto_12', pareto_12)) x(rule, takes)
 GROUP BY rule ORDER BY rule;

\echo '== (3) how often the futures agree that no owner is worse, and how often hindsight then agrees'
SELECT pareto AS futures_good_for_every_owner, count(*) AS decisions,
       count(*) FILTER (WHERE hindsight_class = 'good_for_every_owner') AS good_for_every_owner_in_hindsight,
       count(*) FILTER (WHERE hindsight_class IN ('trades_one_owner_for_another', 'bad_for_every_owner')) AS some_owner_worse_in_hindsight
  FROM research.referee_rules GROUP BY 1 ORDER BY 1;

\echo '== (4) a looser bar: no owner worse and some owner better in the expected future, and in at least t of 12 futures'
SELECT t AS at_least_futures, count(*) FILTER (WHERE takes) AS takes,
       count(*) FILTER (WHERE takes AND hindsight_class = 'good_for_every_owner') AS good_for_every_owner,
       count(*) FILTER (WHERE takes AND hindsight_class = 'no_owner_changes') AS no_owner_changes,
       count(*) FILTER (WHERE takes AND hindsight_class = 'trades_one_owner_for_another') AS trades_owners,
       count(*) FILTER (WHERE takes AND hindsight_class = 'bad_for_every_owner') AS bad_for_every_owner
  FROM generate_series(1, 9) t
 CROSS JOIN research.referee_rules r
 CROSS JOIN LATERAL (SELECT (r.worse0 = 0 AND r.better0 > 0 AND r.pareto >= t) AS takes) x
 GROUP BY t ORDER BY t;

\echo '== (5) how rare a fair improvement is: decisions good for every owner in hindsight, and the most futures any decision was'
SELECT count(*) FILTER (WHERE hindsight_class = 'good_for_every_owner') AS good_for_every_owner_in_hindsight,
       count(*) AS decisions, max(pareto) AS most_futures_good_for_every_owner,
       count(*) FILTER (WHERE pareto = 0) AS no_future_good_for_every_owner
  FROM research.referee_rules;
