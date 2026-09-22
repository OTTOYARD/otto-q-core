-- 0352  **The orchestrator agent's first action on run `0682752c` was to double the busy day's peak
--       deployment target — from the scenario's 0.45 to 0.95 — because its board told it the dial read 0.90
--       when the engine was using 0.45. It then spent the run trying to get back and could not: its envelope
--       floor is 0.50. And that dial is not the depot's to set at all: it is the work side's demand.**
--
--       Four findings about the agentic layer, all from the agent's own audit rows on one busy_day run, each
--       with the query that produced it. Run `0682752c-7082-4ece-97df-152a67f463f0` (busy_day, seed
--       1838167747826776069, 1,099 ticks, twin depot `11111111-…`), measured 2026-09-22 22:10–23:00 UTC
--       (5:10–6:00 PM CT) before any later run purged it. Addressed by `0432` and edge function v19.
--
--         1. **A misreported current value.** `ottoq_agent_board.policy.deploy_peak_fraction` defaults to
--            **0.90**; the dispatcher (`twin.ottoq_sim_auto_dispatch_tick`) and `ottoq_decide_tick` default to
--            the scenario's `target_deployed_fraction` — **0.45** on busy_day. The agent was told 0.90, made
--            "the smallest effective change" to **0.95** at tick 1, and so doubled the peak target.
--         2. **A floor above the scenario.** It then walked the dial down (0.85, 0.75, 0.65, 0.55) and asked for
--            0.35–0.45 on **96 of its 106** writes to it; every one was clamped to the agent floor, **0.50**. The
--            scenario's own value was never reachable again, and the agent was never told it had been clamped.
--         3. **Dither.** On the two energy dials **71% and 68% of changes reverse the previous change** (87 of
--            122, 50 of 74), a mean step of 15% of range every ~8–13 ticks. The only writer on this run was the
--            agent (`policy_write` evaluations by writer, §4) — it is not two controllers fighting; it is one
--            controller with no memory of its own last move.
--         4. **The dial is the work side's demand.** `deploy_peak_fraction` sets how much of the fleet the
--            dispatcher deploys at each hour. CLAUDE.md rule 6: *"No work-side features … The Recall Decision is
--            the only touchpoint with the work side."* An agent that can move the demand curve can make any KPI
--            of the run it is being judged on look however it likes — and on this run it did, at 08:02.

\echo '=== 0352 §1 — the first five agent writes to deploy_peak_fraction ==='
SELECT d.tick_seq, to_char(d.sim_clock AT TIME ZONE 'America/Chicago', 'HH24:MI') AS sim_ct,
       a->>'requested' AS requested, a->>'value' AS applied, a->>'limited_by' AS limiter
  FROM public.ottoq_decisions d, jsonb_array_elements(coalesce(d.enacted_action->'applied','[]')) a
 WHERE d.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0' AND d.resolved_action_context = 'orchestrator_agent'
   AND a->>'key' = 'deploy_peak_fraction'
 ORDER BY d.tick_seq LIMIT 5;
--  1  08:02  0.95  0.95  none      <-- from a board value of 0.90; the engine was using 0.45
-- 35  08:17  0.85  0.85  none
-- 47  08:23  0.75  0.75  none
-- 52  08:25  0.65  0.65  none
-- 67  08:32  0.55  0.55  none
--
-- The two defaults, from the source:
--   public.ottoq_agent_board                'deploy_peak_fraction', ottoq_policy_get(run,'deploy_peak_fraction',0.90)
--   twin.ottoq_sim_auto_dispatch_tick       v_target_deployed_pct := COALESCE(fleet_overrides->>'target_deployed_fraction', 0.90)
--                                           ... ottoq_policy_get(run,'deploy_peak_fraction', v_target_deployed_pct)
--   ottoq_sim_scenarios.busy_day            fleet_overrides.target_deployed_fraction = 0.45

\echo '=== 0352 §2 — every requested/applied pair on deploy_peak_fraction ==='
SELECT a->>'requested' AS requested, a->>'value' AS applied, a->>'limited_by' AS limiter, count(*) AS n
  FROM public.ottoq_decisions d, jsonb_array_elements(coalesce(d.enacted_action->'applied','[]')) a
 WHERE d.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0' AND d.resolved_action_context = 'orchestrator_agent'
   AND a->>'key' = 'deploy_peak_fraction'
 GROUP BY 1,2,3 ORDER BY 4 DESC;
-- 0.35 -> 0.5 range 49 · 0.45 -> 0.5 range 32 · 0.4 -> 0.5 range 15 · then eight single writes 0.55–0.95
-- => 96 of 106 clamped to the agent floor. The prompt names the dials but never their ranges, and nothing
--    tells the agent its last request was clamped, so it asked again every ~10 ticks.

\echo '=== 0352 §3 — dither: consecutive agent writes to the same dial that reverse direction ==='
WITH w AS (
  SELECT d.tick_seq, a->>'key' AS dial, (a->>'value')::numeric AS v
    FROM public.ottoq_decisions d, jsonb_array_elements(coalesce(d.enacted_action->'applied','[]')) a
   WHERE d.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0' AND d.resolved_action_context = 'orchestrator_agent'
     AND a->>'type' = 'set_policy'),
s AS (
  SELECT dial, tick_seq, v, lag(v) OVER (PARTITION BY dial ORDER BY tick_seq) AS prev,
         lag(v, 2) OVER (PARTITION BY dial ORDER BY tick_seq) AS prev2,
         tick_seq - lag(tick_seq) OVER (PARTITION BY dial ORDER BY tick_seq) AS gap
    FROM w)
SELECT dial, count(*) AS writes,
       count(*) FILTER (WHERE v = prev) AS unchanged_resend,
       count(*) FILTER (WHERE prev IS NOT NULL AND v <> prev) AS changes,
       count(*) FILTER (WHERE prev IS NOT NULL AND prev2 IS NOT NULL AND sign(v - prev) * sign(prev - prev2) < 0) AS reversals,
       round(avg(abs(v - prev)) FILTER (WHERE v <> prev), 3) AS mean_step,
       round(avg(gap), 1) AS mean_ticks_between_writes
  FROM s GROUP BY 1 ORDER BY 2 DESC;
-- energy_demand_factor_peak       144  21  122  87  0.093   7.7
-- deploy_peak_fraction            106  92   13   4  0.065  10.4
-- energy_demand_factor_expensive   87  12   74  50  0.089  12.7

\echo '=== 0352 §4 — who wrote dials on this run (policy_write evaluations by writer) ==='
SELECT coalesce(e.context->>'by', '?') AS writer, coalesce(e.context->>'param_key', '?') AS dial, count(*) AS writes
  FROM public.ottoq_rule_evaluations e
 WHERE e.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0' AND e.action_context = 'policy_write'
 GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 6;
-- ottoq_prime  energy_demand_factor_peak       143
-- ottoq_prime  deploy_peak_fraction            105
-- ottoq_prime  energy_demand_factor_expensive   86
-- ottoq_prime  energy_reserve_shave             19
-- ottoq_prime  forecast_horizon_min              5
-- ottoq_prime  deploy_surge_catchup              4
-- => the MPC lookahead and the CIL proposer, which also write these dials, wrote none on this run.

-- ══ §5 TWO GUARDS THAT WERE WORDS ══════════════════════════════════════════
--
-- (a) `ottoq_policy_param_catalog.agent_writable` is read by nothing that refuses. `public.ottoq_dial_clamp`
--     clamps an agent actor to `[agent_min, agent_max]`; it SELECTs the flag into `v_writable` and never uses
--     the variable (an earlier draft of this line said it "never looks at the flag" -- it looks and ignores).
--     A non-writable dial has NULL agent bounds and `GREATEST`/`LEAST` ignore NULLs, so an agent write goes
--     straight through. `AI.001.agent_dial_within_envelope` at the `policy_write` probe DOES detect it --
--     "dial %s is not agent-writable", critical, remedy `set_agent_writable_or_block_the_actor` -- but it is
--     `log_only` and the setter swallows the probe by design, so the detection has no actuator. The edge
--     function's KNOBS whitelist is the only thing that has ever kept the agent off a non-writable dial.
-- (a2) All 312 stored rows of `deploy_peak_fraction` are `scope_type='run'` and `updated_by='ottoq_prime'`
--     (values 0.50-1.00; measured 2026-09-22 23:0x UTC). No operator, scenario or promoter row exists: every
--     agentic run was judged against a demand curve the agent itself had set.
-- (b) `public.ottoq_apply_ops_action` `PERFORM`s the setter and returns `status:'applied'` whatever the
--     setter said — `0231`/G65's defect, in the ops path. An ops action the catalog refuses is reported to
--     the agent, and written to the audit row, as done.

-- ══ §6 WHAT FOLLOWS ═════════════════════════════════════════════════════════
--
--   `0432`: `deploy_peak_fraction` stops being agent-writable; the setter refuses an agent write to any dial
--   whose catalog row says `agent_writable=false`; the ops path reports a refusal as one; and the board gains
--   a `grounding` block — effective values (the dispatcher's own default), each actuator's envelope and the
--   agent's last write to it, a queue that separates vehicles waiting for service from readiness checks that
--   are simply not due yet, resources, energy limits (including an active DR call), the last 30 sim-minutes
--   of flow instead of run-cumulative counters, and the work side's demand as read-only information.
--   Edge function v19: the prompt states envelopes and the stability rule; a change that reverses the
--   agent's own change to the same dial within 30 sim-minutes is held; a write to the value already in force
--   is a no-op, not a move.
--
-- ══ §7 WHAT v19's DISPOSER DOES TO THIS RUN'S OWN REQUEST STREAM ═══════════════
--
-- The model's raw energy-dial requests on this run (`proposed_action->'actions'`, 144 + 87), replayed
-- offline through `edge-functions/_shared/agent_dial_discipline.ts` twice: once as v18 disposed them (clamp
-- only) and once as v19 does (clamp, then `no_change`, then the reversal dwell), both from the catalog
-- defaults 0.50 / 0.35. Reversals here are counted CHANGE-TO-CHANGE (a resend is not a change), which is not
-- §3's consecutive-write definition -- so compare the two columns with each other, not with §3.
--
--                                       v18        v19 dwell 30   v19 dwell 15
--   energy_demand_factor_peak  changes   123            23             36
--                              reversal  84%            45%            60%
--                              held       --     44 no_change +    50 + 58
--                                                77 reversal
--   energy_demand_factor_expensive       76 / 80%   19 / 39%       28 / 44%
--
-- COUNTERFACTUAL BY CONSTRUCTION: under v19 the agent sees `rejected` reasons and a `last_change` on its
-- next board, so it would not have sent this stream. This bounds what the disposer does to the stream that
-- was sent; the live number comes from the first armed run after 0432 (rerun §3 on it).
-- Method: pull the stream with the query below, then node against the shared module.
--   SELECT d.tick_seq, d.sim_clock, a->>'key', (a->>'value')::numeric
--     FROM ottoq_decisions d, jsonb_array_elements(d.proposed_action->'actions') a
--    WHERE d.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'
--      AND d.resolved_action_context = 'orchestrator_agent' AND a->>'type' = 'set_policy'
--      AND a->>'key' IN ('energy_demand_factor_peak','energy_demand_factor_expensive')
--    ORDER BY d.tick_seq, d.decision_seq;
