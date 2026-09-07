-- ---------------------------------------------------------------------------
-- 0118 — ROUND 22: every h_cmd reproduced, and the instrument 0205 promoted
--        turns out not to see what the shield read.
--
-- Fired 2026-09-07 18:35–21:03 UTC (1:35–4:03 PM CT), nine pairs, flagship
-- depot, recertification floor 2026-09-07 18:27:44+00 (0206's apply).
--
-- TWO RESULTS.
--
-- 1. THE STANDING QUESTION FROM ROUND 21 IS ANSWERED. 0207 moved every canon
--    once. Round 21 could not tell whether that was one carrier closed or a
--    carrier still moving. Round 22 reproduced all six h_cmd values exactly:
--
--      314159/12t   109e340b…   171717/12t   1ae7ba68…
--      normal_day   5921ef70…   424242/12t   76134009…
--      171717/24t   050c4606…   424242/24t   8f232001…
--
--    Nine of nine pairs equal, zero inconclusive. h_dec, h_bkg, h_nrg, h_prop,
--    h_defr, h_cal and h_rule held on every column. h_evt moved on all six BY
--    DESIGN — 0204 put sim_clock_at in the event stream — and moved once.
--
-- 2. h_rule IS NARROWER THAN THE CLAIM 0205 PROMOTED IT TO CARRY.
--
--    0204 (G15) stopped the L1 shield reading the wall clock inside the twin.
--    On 171717/24t, TW.001.operational_hours went from ONE distinct local_time
--    across its 1,036 evaluations to TWENTY-FOUR spanning 00:00–23:30. The
--    evaluator now judges each task against the run's own clock instead of one
--    frozen instant. That is a large, correct change in what the shield read.
--
--    h_rule did not move. ottoq_hash_rule_evaluations hashes rule_code,
--    rule_version, action_context, entity_type, entity_id, passed, severity,
--    enforcement, enforcement_taken and parameters_used. parameters_used is
--    {} on these rows; the local time lives in result_payload, unhashed.
--
--    So the verdict can see WHICH rules fired on WHICH entities with WHAT
--    outcome, and cannot see WHAT THEY READ. Both arms of a pair are equally
--    blind, so round 22's passes stand — this is a round-to-round detection
--    gap, the same class 0139 closed for endst and 0199 for the proposal
--    stream. 0208 closes it.
--
-- CORRECTION to a mid-session reading: I recorded G15's proof as "1,162
-- evaluations at one local_time -> 518 across 24". The COUNT did not change —
-- 1,036 per pair, 518 per arm, in BOTH rounds. Only the local_time moved.
-- ---------------------------------------------------------------------------

-- 1. The nine verdicts. Expect nine rows, every one equal=true / passed.
WITH v AS (
  SELECT r.sim_run_id, r.started_at, r.random_seed, r.tick_count, r.scenario_code,
         r.validation_notes::jsonb AS vn
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND r.started_at >= '2026-09-07 18:27:44+00'
     AND r.validation_notes IS NOT NULL)
SELECT started_at, random_seed AS seed, tick_count AS ticks, scenario_code AS scen,
       vn->>'equal' AS equal, vn->>'outcome' AS outcome,
       left(vn->'arm_a'->>'h_cmd', 8) AS h_cmd,
       left(vn->'arm_a'->>'h_evt', 8) AS h_evt,
       left(vn->'arm_a'->>'h_rule', 8) AS h_rule,
       left(vn->'arm_a'->>'h_rcl', 8) AS h_rcl
  FROM v WHERE vn ? 'equal'
 ORDER BY started_at;

-- 2. The matrix at the 0206 floor. Expect six flagship columns plus the grid
--    fixture; three green (PP), three at one pass (P); stale=false everywhere.
SELECT depot, seed, ticks, scenario, pairs_seen, consecutive_passes, green,
       history, inconclusive_pairs,
       left(canon_cmd, 8) AS canon_cmd, left(canon_evt, 8) AS canon_evt,
       left(canon_rule, 8) AS canon_rule, left(canon_rcl, 8) AS canon_rcl
  FROM public.ottoq_cert_matrix('2026-09-07 18:27:44+00'::timestamptz)
 ORDER BY depot, scenario, seed, ticks;

-- 3. THE DECISIVE QUERY: the shield's read moved and h_rule did not.
--    Expect two rows on 171717/24t — one per round — with identical
--    tw001_evals and identical h_rule, and distinct_local_times 1 then 24.
WITH arms AS (
  SELECT r.sim_run_id,
         CASE WHEN r.started_at < '2026-09-07 18:27:44+00' THEN 'round21 (pre-0204)'
              ELSE 'round22 (post-0204)' END AS rnd
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND r.random_seed = 171717 AND r.tick_count = 24
     AND r.scenario_code = 'busy_day' AND r.status = 'completed'
     AND r.started_at > '2026-09-06 20:00:00+00')
SELECT a.rnd,
       count(*)                                             AS tw001_evals,
       count(DISTINCT e.result_payload->>'local_time')      AS distinct_local_times,
       count(DISTINCT e.parameters_used::text)              AS distinct_parameters_used,
       min(public.ottoq_hash_rule_evaluations(a.sim_run_id)) AS h_rule
  FROM arms a
  JOIN public.ottoq_rule_evaluations e ON e.sim_run_id = a.sim_run_id
 WHERE e.rule_code LIKE 'TW.001%'
 GROUP BY 1 ORDER BY 1;

-- 4. What h_rule actually hashes, next to what it does not. result_payload is
--    absent from the function body; that absence is the finding.
SELECT (pg_get_functiondef(p.oid) LIKE '%result_payload%') AS hashes_result_payload,
       (pg_get_functiondef(p.oid) LIKE '%parameters_used%') AS hashes_parameters_used
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_hash_rule_evaluations';

-- 5. The blast radius: every active rule whose read lands in result_payload and
--    is therefore outside the verdict today. These are the rows 0208 brings in.
SELECT e.rule_code,
       count(*)                                        AS evals,
       count(DISTINCT e.result_payload::text)           AS distinct_payloads,
       count(DISTINCT e.parameters_used::text)          AS distinct_parameters
  FROM public.ottoq_rule_evaluations e
 WHERE e.sim_run_id = '657714b0-2798-4085-87d5-0d08b032eb85'
 GROUP BY 1
HAVING count(DISTINCT e.result_payload::text) > 1
 ORDER BY 3 DESC, 1;
