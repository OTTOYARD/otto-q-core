-- 0475  **The check (the referee of the agent's charge orders) ranks orders better than chance when counted by
--        independent (scenario, seed) keys, not only by decisions; its win probability has no proven skill over the
--        base rate.**
--        -> G507 (new). Frontier plan Phase 0, item 0 (docs/FRONTIER_PLAN_2026-11-03.md §5): "re-read the promotion
--        gate honestly ... until then, the gate's condition 2 is 'reads true on an optimistic interval', not 'passed'."
--        Chase, 2026-11-03: "Okay BEGIN".
--        Read against gxdrcyphqjzjsuhxuqtg, read-only, at 15:40:54 and 15:41:06 UTC (9:40 and 9:41 AM CT). Twin depot only
--        (rule 8). Graded decisions since 2026-10-01: the nightly grader (cron 787) graded run 8c0b2e04's orders this
--        morning, so the set is 370 decisions where the plan's reading of 2026-11-02 had 364.
--
-- ══ §1 THE INSTRUMENT, AS IT READS TODAY (reproduce: (1)) ════════════════════════════════════════════════════════════
--
--   public.ottoq_disposer_discrimination (0708) over 2026-10-01 .. 2026-11-04:
--     370 decisions (164 won in hindsight, 206 lost, 5 ties left out), 25 runs, 18 distinct (scenario, seed) keys
--     AUC 0.6535, interval [0.5971, 0.7100], discriminates = true
--     Brier 0.2395 against 0.2468 at the base rate: skill 0.0294
--   Its interval treats the 370 decisions as independent. They are not: decisions within a run share its world and its
--   futures, and a key repeated across runs is the same world again by construction (0339, G153). 18 keys are the
--   independent observations.
--
-- ══ §2 THE SAME NUMBERS, RESAMPLED BY KEY (reproduce: (2)) ═══════════════════════════════════════════════════════════
--
--   A cluster bootstrap: 4,000 resamples of the 18 keys with replacement, each key bringing all its decisions. Draws
--   come from hashtext, so the result is the same on every run of (2). The AUC of a resample is computed exactly from a
--   key-by-key matrix of won/lost pairs (a pair counts 1 when the won order's p_win is higher, 0.5 on a tie), so the
--   point estimate is 0708's to the fourth decimal.
--
--     AUC         0.6535   key-clustered 95% interval [0.5803, 0.7070]   resamples at or below 0.5: 0.03%
--     Brier skill 0.0294   key-clustered 95% interval [-0.0608, 0.0998]  resamples at or below 0:   26.1%
--
--   Per key, decisions (won): 58 (20), 34 (17), 32 (12), 30 (19), 29 (11), 29 (13), 28 (11), 26 (11), 24 (9), 23 (10),
--   18 (10), 8 (7), 8 (3), 7 (4), 7 (3), 6 (3), 2 (0), 1 (1). Every key is busy_day.
--
-- ══ §3 WHAT IT MEANS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) THE RANKING IS REAL. The lower end moves from 0.597 to 0.580 when counted by keys, and stays above 0.5. The
--       promotion gate's condition 2 (docs/AGENT_ARCHITECTURE.md: "the AUC interval of the check's win probability
--       excludes 0.5 on graded decisions") holds on the honest count as well as on the optimistic one.
--   (b) THE PROBABILITY IS NOT. A Brier skill whose interval spans zero means the check's p_win is not yet better than
--       always saying the base rate (0.44). So the check's number may be used to ORDER orders, and must not be read as
--       "this order wins with probability p". The take bar (10 of 12 futures) treats it as a probability; that is the
--       part E2 replaces (calibration, then a sequential test).
--   (c) THE LIMITS OF THIS READING. 18 clusters is few for a bootstrap, and seven keys hold 8 or fewer decisions; the
--       interval is an approximation, not a guarantee. Every key is busy_day: nothing here speaks for another scenario.
--       won/lost is the grader's simulated hindsight (0708's own caveat), not the world's.
--
-- ══ REPRODUCE ═════════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) The instrument, over the same window.
SELECT now() AS read_at, d->'won' AS won, d->'lost' AS lost, d->'auc' AS auc, d->'auc_ci95' AS auc_ci95_independent,
       d->'discriminates' AS discriminates, d->'brier' AS brier, d->'brier_base' AS brier_base,
       d->'brier_skill' AS brier_skill, d->'runs' AS runs, d->'distinct_keys' AS keys, d->'ties_left_out' AS ties
  FROM (SELECT public.ottoq_disposer_discrimination('11111111-1111-1111-1111-111111111111'::uuid,
                                                    '2026-10-01'::timestamptz, '2026-11-04'::timestamptz) AS d) x;

-- (2) The key-clustered bootstrap (0708's decision set; key = scenario_code:random_seed).
WITH d AS (
  SELECT g.sim_run_id, g.p_win::numeric AS p,
         CASE WHEN g.outcome IN ('missed_win','right_take') THEN 1 ELSE 0 END AS y,
         COALESCE(s.scenario_code || ':' || s.random_seed::text, g.sim_run_id::text) AS key
    FROM public.ottoq_charge_order_grades g
    LEFT JOIN public.ottoq_sim_runs s ON s.sim_run_id = g.sim_run_id
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.decision AND g.p_win IS NOT NULL
     AND g.graded_at >= '2026-10-01' AND g.graded_at < '2026-11-04'
     AND g.outcome IN ('missed_win','right_take','right_refusal','wrong_take')
), keys AS (
  SELECT key, (row_number() OVER (ORDER BY key) - 1)::int AS ki FROM (SELECT DISTINCT key FROM d) z
), kk AS (SELECT count(*)::int AS k FROM keys
), dk AS (SELECT d.*, keys.ki FROM d JOIN keys USING (key)
), c AS (
  SELECT w.ki AS i, l.ki AS j,
         sum(CASE WHEN w.p > l.p THEN 1.0 WHEN w.p = l.p THEN 0.5 ELSE 0 END) AS conc, count(*)::numeric AS n
    FROM dk w JOIN dk l ON w.y = 1 AND l.y = 0 GROUP BY 1, 2
), ks AS (
  SELECT ki, count(*)::numeric AS n, sum(y)::numeric AS sy, sum((p - y) ^ 2) AS sse FROM dk GROUP BY ki
), draws AS (
  SELECT b, ((hashtext('p0-key-boot:' || b || ':' || r)::bigint % kk.k) + kk.k) % kk.k AS ki
    FROM generate_series(1, 4000) b, kk, generate_series(1, kk.k) r
), m AS (SELECT b, ki::int AS ki, count(*)::numeric AS m FROM draws GROUP BY b, ki
), auc_b AS (
  SELECT mi.b, sum(mi.m * mj.m * c.conc) / NULLIF(sum(mi.m * mj.m * c.n), 0) AS auc
    FROM m mi JOIN m mj ON mj.b = mi.b JOIN c ON c.i = mi.ki AND c.j = mj.ki GROUP BY mi.b
), brier_b AS (
  SELECT m.b, sum(m.m * ks.sse) / sum(m.m * ks.n) AS brier, sum(m.m * ks.sy) / sum(m.m * ks.n) AS ybar
    FROM m JOIN ks USING (ki) GROUP BY m.b
), skill_b AS (
  SELECT b, CASE WHEN ybar > 0 AND ybar < 1 THEN 1 - brier / (ybar * (1 - ybar)) END AS skill FROM brier_b
)
SELECT now() AS read_at,
  (SELECT count(*) FROM d) AS decisions, (SELECT sum(y) FROM d) AS won, (SELECT k FROM kk) AS keys,
  (SELECT count(DISTINCT sim_run_id) FROM d) AS runs,
  round((SELECT sum(conc) / sum(n) FROM c), 4) AS auc_point,
  round((SELECT percentile_cont(0.025) WITHIN GROUP (ORDER BY auc) FROM auc_b)::numeric, 4) AS auc_key_ci_lo,
  round((SELECT percentile_cont(0.975) WITHIN GROUP (ORDER BY auc) FROM auc_b)::numeric, 4) AS auc_key_ci_hi,
  round((SELECT avg((auc <= 0.5)::int) FROM auc_b), 4) AS share_resamples_auc_le_half,
  round((SELECT 1 - (sum(sse) / sum(n)) / ((sum(sy) / sum(n)) * (1 - sum(sy) / sum(n))) FROM ks), 4) AS skill_point,
  round((SELECT percentile_cont(0.025) WITHIN GROUP (ORDER BY skill) FROM skill_b)::numeric, 4) AS skill_key_ci_lo,
  round((SELECT percentile_cont(0.975) WITHIN GROUP (ORDER BY skill) FROM skill_b)::numeric, 4) AS skill_key_ci_hi,
  round((SELECT avg((skill <= 0)::int) FROM skill_b), 4) AS share_resamples_skill_le_zero,
  (SELECT json_agg(x ORDER BY x.n DESC) FROM (SELECT key, count(*) AS n, sum(y) AS won FROM d GROUP BY key) x) AS per_key;
