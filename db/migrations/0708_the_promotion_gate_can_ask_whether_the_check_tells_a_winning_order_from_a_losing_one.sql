-- migration-version: 20261013195202
-- migration-name:    the_promotion_gate_can_ask_whether_the_check_tells_a_winning_order_from_a_losing_one
--
-- 0708  **The promotion gate can ask, in one call, whether the check tells a winning agent order from a losing one.**
--       public.ottoq_disposer_discrimination(depot, since, until) reads the graded agent charge orders and returns how
--       well the check's win probability separates the orders that won in hindsight from those that lost:
--       - the area under the ROC curve, with a 95% interval (Hanley and McNeil);
--       - the Brier score against the base rate's;
--       - how many runs and distinct (scenario, seed) keys the decisions came from, because 0339's rule counts
--         independent observations, not rows.
--       docs/AGENT_ARCHITECTURE.md makes "the interval excludes 0.5" the second condition for any additional agent to
--       reach production. Until now that condition had no instrument. Read-only. (G427, the study's AV-1 and AG-2;
--       db/checks/0445.)
--
-- ══ §1 WHY (measured 2026-10-13, read-only; the dry run of the function's own query read now() = 19:50:18 UTC) ══════
--
--   (a) THE CORPUS. ottoq_charge_order_grades (a view that reads the newest regrade where one exists, 0630) holds
--       92 decided orders since 2026-10-08:
--         missed_win 42      right_refusal 42      right_take 3      wrong_take 3      neutral_take 2
--       Won in hindsight (missed_win, right_take): 45. Lost (right_refusal, wrong_take): 45. The two ties are left out.
--       The mean p_win is 0.508 for the missed wins against 0.490 for the right refusals: no visible separation.
--       The function's own query, run read-only before this file (now() = 19:50:18 UTC, 2:50 PM CT, one more order
--       graded by then): 46 won, 45 lost; AUC 0.5336, standard error 0.0607, 95% interval [0.4146, 0.6525], so it does
--       NOT discriminate; Brier 0.2756 against 0.2500 for the base rate (worse than guessing the base rate); mean p_win
--       0.533 for orders that won, 0.515 for orders that lost; from 10 runs and 6 distinct (scenario, seed) keys.
--   (b) NOTHING COMPUTES IT. The check's self-review (ottoq_arbiter_self_assessment_v3) and its track record
--       (ottoq_charge_order_track_record) compute a Brier score. No function in the database computes an AUC, or
--       an interval, or the number of independent keys behind a figure. G389 (18 decisions), the study's AV-1 (70)
--       and db/checks/0440 §2 (12) each computed one by hand. Three different denominators, and none was reproducible
--       from a call.
--   (c) WHAT THE INTERVAL CANNOT SAY. Decisions within one run are not independent (they share the run's world and
--       each other's futures), so the Hanley-McNeil interval, which assumes they are, is optimistic. The function
--       returns the run and key counts beside it, so a reader sees how few independent observations stand behind the
--       interval. And "won in hindsight" is the grader's simulated verdict, with overlapping windows (the study's
--       AV-8): the AUC measures agreement with the grader, not with the world.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_disposer_discrimination(p_depot uuid DEFAULT the twin depot, p_since timestamptz DEFAULT now() - 30
--   days, p_until timestamptz DEFAULT now()) RETURNS jsonb. It reads ottoq_charge_order_grades (decision = true, p_win
--   not null, graded inside the window) at the depot, and ottoq_sim_runs for each run's scenario and seed.
--     won   = outcome IN ('missed_win', 'right_take')      lost = outcome IN ('right_refusal', 'wrong_take')
--     auc   = the Mann-Whitney statistic over average ranks of p_win (a tie between a won and a lost order counts 1/2)
--     se    = Hanley & McNeil (1982), Radiology 143:29-36: Q1 = A/(2-A), Q2 = 2A^2/(1+A),
--             se = sqrt((A(1-A) + (n_won-1)(Q1-A^2) + (n_lost-1)(Q2-A^2)) / (n_won n_lost))
--     ci95  = A +/- 1.96 se, clipped to [0, 1];  discriminates = the interval's lower end > 0.5
--     brier = mean (p_win - y)^2;  brier_base = mean (ybar - y)^2, ybar the share that won;  skill = 1 - brier/base
--   It also returns the mean p_win for each side, a per-run breakdown, and the caveats of §1(c) as text. With fewer
--   than 2 orders on either side, it returns the counts and a null AUC.
--   LANGUAGE sql, STABLE, SECURITY INVOKER, search_path public. EXECUTE for service_role only.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   A new read-only function that nothing calls. No tick, check, grader or atom reads it.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   DELETE FROM ottoq_cert_lineage WHERE name = '0708_the_promotion_gate_can_ask_whether_the_check_tells_a_winning_order_from_a_losing_one'.
--   The function stays (never DROP); nothing calls it.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0708 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF to_regprocedure('public.ottoq_disposer_discrimination(uuid,timestamp with time zone,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0708 P1: the function already exists';
  END IF;
  IF to_regclass('public.ottoq_charge_order_grades') IS NULL OR to_regclass('public.ottoq_sim_runs') IS NULL THEN
    RAISE EXCEPTION '0708 P1: a relation the function reads is missing';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'ottoq_charge_order_grades'
         AND column_name IN ('order_id','sim_run_id','depot_id','decision','p_win','outcome','graded_at')) <> 7 THEN
    RAISE EXCEPTION '0708 P1: ottoq_charge_order_grades does not carry the seven columns this file reads';
  END IF;
  --: the outcome vocabulary the won/lost split is written against
  IF EXISTS (SELECT 1 FROM public.ottoq_charge_order_grades g
              WHERE g.decision AND g.outcome NOT IN ('missed_win','right_take','right_refusal','wrong_take','neutral_take')) THEN
    RAISE EXCEPTION '0708 P1: a decided grade carries an outcome this file does not classify';
  END IF;
END $premises$;

CREATE OR REPLACE FUNCTION public.ottoq_disposer_discrimination(
  p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111',
  p_since timestamptz DEFAULT now() - interval '30 days',
  p_until timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
  WITH d AS (
    SELECT g.sim_run_id, g.p_win AS p,
           CASE WHEN g.outcome IN ('missed_win','right_take') THEN 1 ELSE 0 END AS y
      FROM public.ottoq_charge_order_grades g
     WHERE g.depot_id = p_depot AND g.decision AND g.p_win IS NOT NULL
       AND g.graded_at >= p_since AND g.graded_at < p_until
       AND g.outcome IN ('missed_win','right_take','right_refusal','wrong_take')),
  n AS (
    SELECT count(*) FILTER (WHERE y = 1) AS nw, count(*) FILTER (WHERE y = 0) AS nl,
           avg(y::numeric) AS ybar,
           round(avg(p) FILTER (WHERE y = 1), 3) AS pw, round(avg(p) FILTER (WHERE y = 0), 3) AS pl
      FROM d),
  --: the Mann-Whitney statistic over average ranks: a tie between a won and a lost order counts one half
  rk AS (
    SELECT y, rank() OVER (ORDER BY p) + (count(*) OVER (PARTITION BY p) - 1) / 2.0 AS r FROM d),
  a AS (
    SELECT CASE WHEN n.nw >= 2 AND n.nl >= 2
                THEN ((SELECT sum(r) FROM rk WHERE y = 1) - n.nw * (n.nw + 1) / 2.0) / (n.nw::numeric * n.nl) END AS auc
      FROM n),
  --: Hanley & McNeil (1982)
  se AS (
    SELECT a.auc,
           sqrt(GREATEST(0, (a.auc * (1 - a.auc)
                             + (n.nw - 1) * (a.auc / (2 - a.auc) - a.auc * a.auc)
                             + (n.nl - 1) * (2 * a.auc * a.auc / (1 + a.auc) - a.auc * a.auc))
                            / (n.nw::numeric * n.nl))) AS se
      FROM a, n),
  b AS (
    SELECT avg((d.p - d.y) ^ 2) AS brier, avg((n.ybar - d.y) ^ 2) AS base FROM d, n),
  k AS (
    SELECT count(DISTINCT d.sim_run_id) AS runs, count(DISTINCT (s.scenario_code, s.random_seed)) AS keys
      FROM d LEFT JOIN public.ottoq_sim_runs s ON s.sim_run_id = d.sim_run_id),
  br AS (
    SELECT COALESCE(jsonb_agg(x ORDER BY x ->> 'started_at'), '[]'::jsonb) AS by_run
      FROM (SELECT jsonb_build_object('sim_run_id', d.sim_run_id, 'scenario', s.scenario_code, 'seed', s.random_seed::text,
                                      'started_at', min(s.started_at),
                                      'won', count(*) FILTER (WHERE d.y = 1), 'lost', count(*) FILTER (WHERE d.y = 0),
                                      'mean_p_win_won', round(avg(d.p) FILTER (WHERE d.y = 1), 3),
                                      'mean_p_win_lost', round(avg(d.p) FILTER (WHERE d.y = 0), 3)) AS x
              FROM d LEFT JOIN public.ottoq_sim_runs s ON s.sim_run_id = d.sim_run_id
             GROUP BY d.sim_run_id, s.scenario_code, s.random_seed) q),
  t AS (
    SELECT count(*) AS ties FROM public.ottoq_charge_order_grades g
     WHERE g.depot_id = p_depot AND g.decision AND g.graded_at >= p_since AND g.graded_at < p_until
       AND g.outcome = 'neutral_take')
  SELECT jsonb_build_object(
    'depot_id', p_depot, 'since', p_since, 'until', p_until,
    'won', n.nw, 'lost', n.nl, 'ties_left_out', t.ties,
    'auc', round(se.auc, 4), 'auc_se', round(se.se, 4),
    'auc_ci95', CASE WHEN se.auc IS NOT NULL THEN jsonb_build_array(round(GREATEST(0, se.auc - 1.96 * se.se), 4),
                                                                   round(LEAST(1, se.auc + 1.96 * se.se), 4)) END,
    'discriminates', (se.auc - 1.96 * se.se) > 0.5,
    'brier', round(b.brier, 4), 'brier_base', round(b.base, 4),
    'brier_skill', CASE WHEN b.base > 0 THEN round(1 - b.brier / b.base, 4) END,
    'mean_p_win_won', n.pw, 'mean_p_win_lost', n.pl,
    'runs', k.runs, 'distinct_keys', k.keys, 'by_run', br.by_run,
    'why_null', CASE WHEN se.auc IS NULL THEN 'fewer than 2 graded orders on one side' END,
    'caveats', jsonb_build_array(
      'decisions within a run share its world and futures, so the interval (which assumes independence) is optimistic: read it beside runs and distinct_keys',
      'won/lost is the grader''s simulated hindsight (overlapping windows, the study''s AV-8), not the world''s'))
    FROM n, se, b, k, br, t
$fn$;

COMMENT ON FUNCTION public.ottoq_disposer_discrimination(uuid, timestamptz, timestamptz) IS
'0708. How well the agent-order check''s p_win separates orders that won in hindsight (missed_win, right_take) from those that lost (right_refusal, wrong_take): AUC with a Hanley-McNeil 95% interval, Brier against the base rate, mean p_win per side, and the runs and distinct (scenario, seed) keys behind it. The promotion gate''s second condition (docs/AGENT_ARCHITECTURE.md): discriminates = the interval''s lower end above 0.5. Read-only.';

REVOKE ALL ON FUNCTION public.ottoq_disposer_discrimination(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_disposer_discrimination(uuid, timestamptz, timestamptz) TO service_role;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v$
DECLARE v_r jsonb;
BEGIN
  --: V1 it answers on the live corpus, and its counts are the corpus's
  v_r := public.ottoq_disposer_discrimination('11111111-1111-1111-1111-111111111111', '-infinity', 'infinity');
  IF (v_r ->> 'won')::integer + (v_r ->> 'lost')::integer
     <> (SELECT count(*) FROM public.ottoq_charge_order_grades g
          WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.decision AND g.p_win IS NOT NULL
            AND g.outcome IN ('missed_win','right_take','right_refusal','wrong_take')) THEN
    RAISE EXCEPTION '0708 V1 FAILED: the counts are not the corpus''s: %', v_r;
  END IF;
  --: V2 the statistic is bounded and the interval contains it
  IF v_r ->> 'auc' IS NOT NULL AND NOT ((v_r ->> 'auc')::numeric BETWEEN 0 AND 1
       AND (v_r -> 'auc_ci95' ->> 0)::numeric <= (v_r ->> 'auc')::numeric
       AND (v_r -> 'auc_ci95' ->> 1)::numeric >= (v_r ->> 'auc')::numeric) THEN
    RAISE EXCEPTION '0708 V2 FAILED: %', v_r;
  END IF;
  --: V3 no client role can call it
  IF has_function_privilege('anon', 'public.ottoq_disposer_discrimination(uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_disposer_discrimination(uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0708 V3 FAILED: a client role may execute it';
  END IF;
  RAISE NOTICE '0708 V1-V3 PASSED: won % lost % auc % ci % discriminates % brier % base % runs % keys %',
    v_r ->> 'won', v_r ->> 'lost', v_r ->> 'auc', v_r -> 'auc_ci95', v_r ->> 'discriminates', v_r ->> 'brier',
    v_r ->> 'brier_base', v_r ->> 'runs', v_r ->> 'distinct_keys';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0708_the_promotion_gate_can_ask_whether_the_check_tells_a_winning_order_from_a_losing_one', false, false,
  'G427 (the study''s AV-1/AG-2; db/checks/0445): public.ottoq_disposer_discrimination(depot, since, until), a read-only '
  'instrument for the promotion gate''s second condition. AUC of the agent-order check''s p_win over graded decisions '
  '(won = missed_win/right_take, lost = right_refusal/wrong_take) with a Hanley-McNeil 95% interval, Brier against the '
  'base rate, and the runs and distinct (scenario, seed) keys behind it. Nothing calls it: FALSE/FALSE.',
  now());

COMMIT;
