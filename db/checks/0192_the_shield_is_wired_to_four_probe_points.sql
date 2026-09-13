-- ---------------------------------------------------------------------------
-- 0192 — G44 ROOT-CAUSED: NINE EVALUATORS EXIST, NINE RULES ARE ACTIVE, AND NO
-- CODE PATH EVER PROBES THE SHIELD AT THE CONTEXTS THEY LISTEN FOR.
--
-- BUILD_QUEUE #10 has said "9 of 29 rules can never fire" since it was written,
-- with the note "the engine announces four action contexts; every unreached rule
-- listens outside that set". This file measures that claim end to end, because the
-- number we publish about the shield depends on it: "29 deterministic rules" is a
-- count of DECLARED rules, and the count of rules the shield actually EVALUATES is
-- twenty.
-- ---------------------------------------------------------------------------

-- 1. THE FOUR PROBE POINTS. Every rule evaluation ever logged, by context.
SELECT action_context, count(*) AS evaluations, count(DISTINCT rule_code) AS rules,
       max(evaluated_at)::date AS last_seen
  FROM public.ottoq_rule_evaluations GROUP BY 1 ORDER BY 2 DESC;
-- MEASURED 2026-09-13 05:35 UTC:
--   task_start        2,701,143 | 13 rules | 2026-09-13
--   stall_assignment    544,413 |  5 rules | 2026-09-13
--   redeployment         90,244 |  6 rules | 2026-09-13
--   bess_dispatch         2,222 |  1 rule  | 2026-09-13
-- FOUR contexts, ever. Three of them are starts (a task starting, a stall being
-- assigned, a vehicle being redeployed) and the fourth is an energy dispatch.
-- Nothing probes at COMPLETION, at ARRIVAL, at a STATE TRANSITION, or at an
-- OVERRIDE / AUTHORIZATION event.

-- 2. THE NINE THAT NEVER RAN -- and their evaluators all EXIST.
WITH nine AS (
  SELECT r.rule_code, r.severity, r.evaluator_function, r.applies_to_actions::text AS acts
    FROM public.ottoq_rules r
   WHERE r.status = 'active'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_rule_evaluations e
                      WHERE e.rule_code = r.rule_code)
)
SELECT n.rule_code, n.severity, n.evaluator_function,
       EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = n.evaluator_function) AS evaluator_exists,
       n.acts
  FROM nine n ORDER BY n.severity, n.rule_code;
-- MEASURED: nine rows, evaluator_exists TRUE for every one of them.
--   critical | HW.006.physical_presence_verification  | {task_completion}
--   critical | SM.001.vehicle_transition_validity     | {vehicle_state_change}
--   critical | SM.003.stall_transition_validity       | {stall_state_change}
--   critical | SM.004.role_gated_actions              | {tech_override, flag_abnormality,
--                                                        resolve_abnormality, oem_accept,
--                                                        oem_flag_midflow, emergency_stop,
--                                                        brain_pause}
--   critical | SM.005.audit_note_required_on_overrides | {progression_decision_insert}
--   critical | SM.006.bess_transition_validity        | {bess_state_change}
--   warning  | SLA.002.max_queue_depth                | {arrival, queue_admission}
--   info     | TW.002.overnight_staging               | {post_redeployment_staging, task_completion}
--   info     | TW.004.tariff_window                   | {cost_advisory, schedule_optimization}
--
-- SIX OF THE NINE ARE 'critical'. Among them: whether a vehicle's state transition
-- is legal, whether a stall's is, whether a BESS's is, whether a privileged action
-- (including emergency_stop and brain_pause) was taken by a role allowed to take
-- it, and whether an override carries its audit note. The code to decide each of
-- those is written, loaded and callable. Nothing calls it.

-- 3. THE CLAIM, CORRECTED. What the shield evaluates versus what it declares.
SELECT (SELECT count(*) FROM public.ottoq_rules WHERE status='active')          AS rules_active,
       (SELECT count(DISTINCT rule_code) FROM public.ottoq_rule_evaluations)    AS rules_ever_evaluated,
       (SELECT count(DISTINCT action_context) FROM public.ottoq_rule_evaluations) AS probe_points,
       (SELECT count(*) FROM public.ottoq_rules r WHERE r.status='active'
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_rule_evaluations e
                          WHERE e.rule_code=r.rule_code))                       AS never_evaluated;
-- MEASURED: rules_active 29 | rules_ever_evaluated 20 | probe_points 4 | never_evaluated 9.
-- So the honest sentence is: "twenty of twenty-nine declared rules, evaluated at
-- four decision points, every evaluation logged." Anything that says 29 (or 52,
-- the ROW count including archived versions) is describing the catalogue, not the
-- shield.

-- ---------------------------------------------------------------------------
-- WHY THIS IS A WIRING DEFECT AND NOT A MISSING FEATURE
--
-- The shield is asked one question: "may this action proceed?" -- and it is asked
-- only where the engine is about to START something. That is a coherent design for
-- a gate, and it is why the reachable twenty are the ones they are: connector
-- compatibility, charger state, grid ceilings, power ceilings, one-task-per-vehicle,
-- single-vehicle-per-stall, SLA readiness. Every one of those is a precondition.
--
-- The nine unreachable rules are not preconditions. They are INVARIANTS over
-- transitions and outcomes: a state machine's legality, an authorization, an audit
-- note, a completion's physical verification, a queue's depth at arrival. A gate at
-- the start cannot check any of them, so they were written, declared active, and
-- left without a caller -- and the rule ledger says so in the only way it can, by
-- containing nothing.
--
-- WHAT EACH ONE NEEDS (scoped, not designed here):
--   * SM.001 / SM.003 / SM.006 -- a probe at the write that changes the state, or a
--     constraint trigger on the state column. The twin changes vehicle state in
--     several places; a single chokepoint has to exist before the rule can sit on it.
--     (SM.001 is the one BUILD_QUEUE says has had 1.19M vehicle state-change events
--     go past it.)
--   * SM.004 / SM.005 -- a probe in the override / privileged-action path. The
--     identity is already server-derived (0198) and ottoq_ops_approvals already
--     queues out-of-whitelist requests, so the data exists; the rule is simply not
--     consulted.
--   * HW.006 -- a probe at task completion, which is exactly where SDR emission
--     already happens (G10's terminus work). The natural home is that same trigger.
--   * SLA.002 -- a probe at arrival / gate admission.
--   * TW.002 / TW.004 -- 'info' severity advisories; they need a probe at staging
--     and at schedule optimisation, and TW.004 is the same "tariff never reaches a
--     scheduling decision" gap BUILD_QUEUE #6 already records.
--
-- SEQUENCING NOTE. Adding a probe point changes the rule-evaluation stream, which
-- is h_rule -- one of the fourteen certification atoms. So every one of these is a
-- forces_recert=TRUE change unless it is gated off by default, and none of them
-- should be attempted in the same window as 0263/0264. They are also the honest
-- answer to "is the shield complete?", which is a question a safety reviewer will
-- ask before they ask anything about throughput.
-- ---------------------------------------------------------------------------
