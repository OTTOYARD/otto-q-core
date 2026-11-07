-- 0480  **The agent's charge order is now a background challenger at the twin depot: checked, kept and graded as before,
--        never standing; and the agent is consulted when something exceptional happens, plus a check-in every 30
--        sim-minutes, instead of on every pass.** (0795, with 0705's wake gate switched on.)
--        -> G512 answered by Chase's D5 decision; G513 (new) found on the way. Frontier plan E8 ("agents at the edges")
--        and D5 ("move it, and keep the per-tick orders as a low-frequency challenger"). Chase, 2026-11-05: "Okay I agree
--        with you on all fronts. Begin building and let's make sure that AI + Agentic assistance is still a huge tool for
--        us in the OTTO-Q tech stack. Even if it isn't in every loop, maybe it is in the background or knows when to be
--        called for exceptions or input".
--        Built and tested in the research lab on a replica of production's engine (engine hash 7af6fcca, 0794 included),
--        2026-11-05 21:17-21:32 UTC (3:17-3:32 PM CT); applied to production and switched on at the twin depot at
--        21:33:48 UTC (0795, ledger 20261105213348) and 21:34:09 UTC (both dials, under Chase's name), 3:33-3:34 PM CT.
--        Rule 8: twin depot only.
--
-- ══ §1 WHY ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0478/0479 (G511, G512): of the 32 agent charge orders the kernel's check took before 0784's owner guard, 5 were good
--   for every owner in hindsight, 22 traded one owner's cars for another's and 5 hurt every owner; no rule that lets no
--   owner lose would have taken any of the 370 graded decisions. Since the guard went on (2026-10-25 17:01 UTC) the check
--   has taken none (0 of 145 on 763734d4 and 8c0b2e04). The kernel's own line (0642's floor and minutes, 0781's exit key,
--   each owner keeping its places) seats every car whenever no agent order stands.
--
-- ══ §2 WHAT 0795 DOES (lab/research/p1_agent_challenger/test_0795.py, every line an assertion) ═══════════════════════
--
--   On a replica of production's engine, busy_day seed 171717 at the twin depot, a line of 17 cars at tick 2:
--     - at the dial's default the record's receipt and row, the board, the usage and the wake gate answer exactly as
--       their pre-images (0795_pre) do;
--     - dial 0: an order the check takes is 'accepted' and stands (6 cars live); dial 1: the same order is 'shadow' and
--       ottoq_agent_charge_order_live answers {}; the next tick's events, decisions and commands are digest-equal to a
--       tick with no order at all (137 decisions, 61 commands, 1,217 events), while the same order accepted changes
--       all three;
--     - an order the real check refuses stays 'refused' with its reason (worse_in_expected_future);
--     - a shadow order is graded as the check's take (taken = true; here wrong_take), its forecast errors and fidelity
--       read the kernel's side, the side the depot followed, and the two sides differ (fidelity), so the check could
--       fail; the pre-image would have graded it as a refusal; an accepted order is graded exactly as before;
--     - the board says shadow: true and is otherwise the same board; the usage counts orders_shadow;
--     - the wake gate at dial 1 drops due_in_line and charger_free and nothing else, with the same fingerprint, at every
--       tick tried.
--
-- ══ §3 HOW OFTEN THE AGENT WILL BE CONSULTED (lab/research/p1_agent_challenger/wake_replay.py) ═════════════════════
--
--   Replayed on the twin depot's 1,691 passes since 2026-10-20 (12 runs, 59.4 sim-hours), all consulted because the gate
--   was in shadow: with 0795 and the gate on, about 143 consults: 61 woken by an exception (a charger fault or repair,
--   contention onset or relief, an emergency, a car newly past its contract wait, a demand-response call, a scout's
--   finding, a run's first pass) and 82 heartbeats. On a 9-hour busy day that is about 20 consults, where the runs had
--   157 to 419 passes. An estimate: with fewer consults the gate's onsets and jumps are judged against an older
--   fingerprint than these passes recorded. Every pass still hands the solver its work on the standing objective (edge
--   v29+, solver-only passes).
--
-- ══ §4 G513: THE GRADER FILES THE OWNER GUARD'S REFUSALS AS NO DECISION ═════════════════════════════════════════════
--
--   ottoq_charge_order_grade_compute counts a verdict as a decision for 0620's four reasons only. Since the guard: 30
--   orders refused worse_for_an_owner, graded no_decision_mattered 27 and no_decision 3, beside 33 graded decisions and
--   89 echoes of the kernel's order (query (3)). The fix belongs with E2/E7's per-owner grader, not as a patch: counting
--   them as decisions with the depot's hindsight would read a depot gain that costs an owner as a missed win, and the
--   self-review's bar sweep would count the guard's refusals as the bar's.
--
-- ══ §5 WHAT WAS NOT VERIFIED ═══════════════════════════════════════════════════════════════════════════════════════
--
--   - No demo run has run with it yet; the next one at the twin depot is its first. Edge v31 is unchanged: it counts an
--     order as taken only on accepted or partial, so a shadow order is not an enacted action (read in
--     edge-functions/_shared/agent_charge_order.ts and agent_pass_evidence.ts, not executed against the deployed edge).
--   - §3 is a replay estimate, not a measurement.
--   - The lab's arm ticks 30 sim-minutes; a demo run ticks about 12 sim-seconds.

-- (1) PRODUCTION. The dials at the twin depot.
SELECT param_key, param_value, updated_by, updated_at
  FROM public.ottoq_policy_params
 WHERE scope_type = 'depot' AND scope_id = '11111111-1111-1111-1111-111111111111'
   AND param_key IN ('agent_charge_order_shadow', 'agent_wake_enabled', 'agent_charge_order_owner_guard')
 ORDER BY 1;

-- (2) PRODUCTION. On a run since the switch: the orders by status, and the passes by class.
SELECT o.sim_run_id, o.status, o.projection ->> 'reason' AS reason, count(*)
  FROM public.ottoq_agent_charge_orders o
 WHERE o.depot_id = '11111111-1111-1111-1111-111111111111' AND o.recorded_at >= '2026-11-05 21:34:09+00'
 GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC;
SELECT e.sim_run_id, e.consulted, e.outcome_class, count(*)
  FROM public.ottoq_agent_pass_evidence e
 WHERE e.depot_id = '11111111-1111-1111-1111-111111111111' AND e.recorded_at >= '2026-11-05 21:34:09+00'
 GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC;

-- (3) PRODUCTION. G513: the guard's refusals and how they were graded.
SELECT o.projection ->> 'reason' AS reason, g.outcome, count(*)
  FROM public.ottoq_agent_charge_orders o LEFT JOIN public.ottoq_charge_order_grades g USING (order_id)
 WHERE o.depot_id = '11111111-1111-1111-1111-111111111111' AND o.recorded_at >= '2026-10-25 17:01:29+00'
 GROUP BY 1, 2 ORDER BY 3 DESC;
