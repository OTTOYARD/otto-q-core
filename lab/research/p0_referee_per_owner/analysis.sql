-- lab/research/p0_referee_per_owner/analysis.sql -- run in the LAB after replay.sql. Read-only over research.referee_replay.
-- Each owner judged on its own cars with the engine's own yardstick, ottoq_charge_line_compare (on-time cars, then
-- lateness, then minutes past the contract wait, then minutes in the depot), as 0784's owner guard judges them.
-- "better" = the agent's order is better for that owner's cars than the kernel's own order.
\set ON_ERROR_STOP on
\pset footer off
DROP TABLE IF EXISTS research.referee_per_owner;
CREATE TABLE research.referee_per_owner AS
SELECT r.order_id, r.sim_run_id, r.outcome, r.taken, r.h_cmp_now AS depot_hindsight, r.e_cmp_now AS depot_expected,
       o.owner,
       COALESCE(fo.name, o.owner) AS owner_name,
       ((public.ottoq_charge_line_compare(r.h_kernel_by_owner -> o.owner, r.h_agent_by_owner -> o.owner)) ->> 'cmp')::int AS h_cmp,
       ((public.ottoq_charge_line_compare(r.h_kernel_by_owner -> o.owner, r.h_agent_by_owner -> o.owner)) ->> 'by')        AS h_by,
       ((public.ottoq_charge_line_compare(r.e_kernel_by_owner -> o.owner, r.e_agent_by_owner -> o.owner)) ->> 'cmp')::int AS e_cmp
  FROM research.referee_replay r
  CROSS JOIN LATERAL (SELECT k FROM jsonb_object_keys(r.h_kernel_by_owner) k
                      UNION SELECT k FROM jsonb_object_keys(r.h_agent_by_owner) k) o(owner)
  LEFT JOIN public.fleet_operators fo ON fo.id::text = o.owner;

DROP TABLE IF EXISTS research.referee_owner_verdicts;
CREATE TABLE research.referee_owner_verdicts AS
SELECT order_id, sim_run_id, outcome, taken, depot_hindsight, depot_expected,
       count(*) AS owners,
       count(*) FILTER (WHERE h_cmp > 0) AS h_better, count(*) FILTER (WHERE h_cmp < 0) AS h_worse,
       count(*) FILTER (WHERE e_cmp > 0) AS e_better, count(*) FILTER (WHERE e_cmp < 0) AS e_worse,
       CASE WHEN count(*) FILTER (WHERE h_cmp > 0) > 0 AND count(*) FILTER (WHERE h_cmp < 0) = 0 THEN 'good_for_every_owner'
            WHEN count(*) FILTER (WHERE h_cmp < 0) > 0 AND count(*) FILTER (WHERE h_cmp > 0) = 0 THEN 'bad_for_every_owner'
            WHEN count(*) FILTER (WHERE h_cmp > 0) > 0 AND count(*) FILTER (WHERE h_cmp < 0) > 0 THEN 'trades_one_owner_for_another'
            ELSE 'no_owner_changes' END AS hindsight_class,
       count(*) FILTER (WHERE e_cmp < 0) > 0 AS guard_would_refuse
  FROM research.referee_per_owner GROUP BY 1,2,3,4,5,6;

\echo '== (1) owners per decision'
SELECT owners, count(*) FROM research.referee_owner_verdicts GROUP BY 1 ORDER BY 1;

\echo '== (2) in hindsight, by the grader''s label (the depot''s lexicographic verdict)'
SELECT outcome, count(*) AS decisions,
       count(*) FILTER (WHERE hindsight_class = 'good_for_every_owner')         AS good_for_every_owner,
       count(*) FILTER (WHERE hindsight_class = 'trades_one_owner_for_another') AS trades_owners,
       count(*) FILTER (WHERE hindsight_class = 'bad_for_every_owner')          AS bad_for_every_owner,
       count(*) FILTER (WHERE hindsight_class = 'no_owner_changes')             AS no_owner_changes
  FROM research.referee_owner_verdicts GROUP BY ROLLUP (outcome) ORDER BY outcome NULLS LAST;

\echo '== (3) the orders the referee TOOK: which owners did each one make worse off, in hindsight'
SELECT v.outcome, v.hindsight_class, count(DISTINCT v.order_id) AS orders,
       string_agg(DISTINCT p.owner_name, ', ') FILTER (WHERE p.h_cmp < 0) AS owners_made_worse
  FROM research.referee_owner_verdicts v JOIN research.referee_per_owner p USING (order_id)
 WHERE v.taken GROUP BY 1, 2 ORDER BY 1, 2;

\echo '== (4) each owner: in how many decisions the agent''s order was better / worse / no different for its cars (hindsight)'
SELECT owner_name, count(*) AS decisions,
       count(*) FILTER (WHERE h_cmp > 0) AS agent_better, count(*) FILTER (WHERE h_cmp < 0) AS agent_worse,
       count(*) FILTER (WHERE h_cmp = 0) AS no_different,
       count(*) FILTER (WHERE h_cmp > 0 AND taken) AS taken_better, count(*) FILTER (WHERE h_cmp < 0 AND taken) AS taken_worse
  FROM research.referee_per_owner GROUP BY 1 ORDER BY 1;

\echo '== (5) where an owner loses, at what level (hindsight)'
SELECT owner_name, h_by AS decided_at, count(*) FILTER (WHERE h_cmp < 0) AS agent_worse, count(*) FILTER (WHERE h_cmp > 0) AS agent_better
  FROM research.referee_per_owner WHERE h_cmp <> 0 GROUP BY 1, 2 ORDER BY 1, 2;

\echo '== (6) the owner guard (0784) applied to every decision: refuse when the check EXPECTS any owner worse off'
SELECT taken, guard_would_refuse, hindsight_class, count(*)
  FROM research.referee_owner_verdicts GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

\echo '== (7) the check''s expected per-owner verdict against hindsight, owner by owner'
SELECT e_cmp AS expected, h_cmp AS hindsight, count(*) FROM research.referee_per_owner GROUP BY 1, 2 ORDER BY 1, 2;

\echo '== (8) independence: decisions and (scenario, seed) keys behind them'
SELECT count(DISTINCT v.order_id) AS decisions, count(DISTINCT v.sim_run_id) AS runs FROM research.referee_owner_verdicts v;

\echo '== (9) how much an owner loses when a TAKEN order makes its cars worse off (hindsight, minutes for that owner''s cars)'
WITH t AS (
  SELECT p.order_id, p.owner_name, p.h_by,
         (public.ottoq_charge_line_compare(r.h_kernel_by_owner -> p.owner, r.h_agent_by_owner -> p.owner)) AS c
    FROM research.referee_per_owner p JOIN research.referee_replay r USING (order_id)
   WHERE p.taken AND p.h_cmp < 0)
SELECT h_by AS decided_at, count(*) AS owner_losses,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY abs((c ->> 'd_late')::numeric))   AS median_lateness_min,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(COALESCE((c ->> 'd_breach')::numeric, 0))) AS median_contract_wait_min,
       sum((c ->> 'd_on_time')::int) AS on_time_cars_lost
  FROM t GROUP BY ROLLUP (h_by) ORDER BY h_by NULLS LAST;

\echo '== (10) when the check expected NO owner worse off, how often hindsight found one (the guard''s passes)'
SELECT count(*) AS guard_passes, count(*) FILTER (WHERE h_worse > 0) AS some_owner_worse_in_hindsight
  FROM research.referee_owner_verdicts WHERE NOT guard_would_refuse;
