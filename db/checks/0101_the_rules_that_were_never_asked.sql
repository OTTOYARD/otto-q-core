-- =====================================================================
-- 0101  The rules that were never asked
-- =====================================================================
-- A FINDING, not a fix. The fix is engine-path work with a real failure
-- mode, and it should not be started at the end of a long session.
--
-- SECTION 1 — THE GAP, EXACTLY
-- ---------------------------------------------------------------------
-- The engine has emitted FOUR action contexts, ever, across 4.6M rule
-- evaluations:
--
--   task_start         3,473,522   13 rules
--   stall_assignment   1,127,065    5 rules
--   redeployment           3,768    6 rules
--   bess_dispatch          2,710    1 rule
--
-- Nine active rules have NEVER been evaluated. Every context they listen
-- for is in a DISJOINT set from the four above:
--
--   rule                                     listens for            enforce
--   HW.006.physical_presence_verification    task_completion        BLOCK
--   SM.001.vehicle_transition_validity       vehicle_state_change   BLOCK
--   SM.003.stall_transition_validity         stall_state_change     BLOCK
--   SM.004.role_gated_actions                tech_override, +6      BLOCK
--   SM.005.audit_note_required_on_overrides  progression_decision   BLOCK
--   SM.006.bess_transition_validity          bess_state_change      BLOCK
--   SLA.002.max_queue_depth                  arrival, queue_admit   warn
--   TW.002.overnight_staging                 post_redeploy_staging  log
--   TW.004.tariff_window                     cost_advisory, sched   log
--
-- All nine have an evaluator_function. None has ever been called.
--
-- The pattern is not random. Every context the engine DOES emit is a
-- decision to START something. Every context it does not is a STATE
-- TRANSITION, a COMPLETION, or a HUMAN ACTION.
--
--   THE RULES LAYER IS WIRED TO DECISIONS, NOT TO OUTCOMES.
--
-- The asymmetry is visible inside single subsystems: bess_dispatch is
-- emitted 2,710 times, bess_state_change never; stall_assignment 1.1M
-- times, stall_state_change never. Each has a hook for asking permission
-- and none for reporting what happened.
--
-- CLAUDE.md 2.5 describes this layer as "inviolable constraints including
-- per-OEM SLAs". Six constraints marked critical/block, including the
-- three state-machine validity rules, have never once been consulted.
--
-- SECTION 2 — THE TRANSITIONS ARE ALREADY RECORDED
-- ---------------------------------------------------------------------
-- This is the part that decides how expensive the fix is. The engine is
-- not failing to observe transitions. It observes and signs them:
--
--   vehicle.state_changed          1,188,444
--   stall.state_changed              767,357
--   twin.service_completed            22,044
--   charge.session_completed          21,081
--   twin.deploy_gate_override          1,904
--   twin.vehicle_arrived                 524
--
-- and the payload carries precisely what the evaluator needs:
--
--   "current_state": { "from": "staged_awaiting_service", "to": "offline" }
--
-- So SM.001 had 1,188,444 opportunities and took none. SM.003 had
-- 767,357. HW.006 watched 22,044 service completions go by.
--
-- IT IS A ROUTING PROBLEM, NOT A DETECTION PROBLEM. The transitions, the
-- rules, and the evaluators all exist; nothing connects them.
--
-- SECTION 3 — WHY NAIVE ROUTING WOULD BE WRONG
-- ---------------------------------------------------------------------
-- Of vehicle.state_changed in the last two days, 222,516 events carry
-- NULL for both from and to - roughly 29%. The event type is emitted for
-- diffs that are not state changes at all (config-only changes ride the
-- same type). Routing on event_type alone would hand a transition-
-- validity rule 222k non-transitions to rule on.
--
-- That is the same shape as every defect this campaign has closed: a
-- population that looks like one thing and contains another. Whatever
-- wires these rules must gate on the from/to pair being present, not on
-- the event type.
--
-- SECTION 4 — WHAT THE ENGINE ACTUALLY DOES (the input any shadow run needs)
-- ---------------------------------------------------------------------
-- Observed vehicle transitions, last two days, top of the distribution:
--
--   en_route_to_depot      -> arrived_at_gate           16,582
--   deployed               -> en_route_to_depot         11,784
--   offline                -> deployed                  11,700
--   staged_for_departure   -> offline                    8,214
--   charge_complete_holding-> staged_for_departure       8,166
--   charging_l2            -> charge_complete_holding    6,928
--   arrived_at_gate        -> charging_l2                6,668
--   arrived_at_gate        -> charge_complete_holding    5,364   <-- ?
--   offline                -> en_route_to_depot          4,828
--   staged_awaiting_service-> offline                    4,390
--   ...
--   charging_l2            -> offline                    2,008   <-- ?
--   charging_dcfc          -> offline                      452   <-- ?
--   staged_awaiting_service-> tow_requested                442
--   tow_requested          -> emergency_staged             438
--
-- Three are marked because they look like they may not be legal: arriving
-- at the gate and going straight to charge-complete without charging, and
-- going offline directly out of an active charge. They may be legitimate
-- teardown or fault paths. NOT A FINDING - a question the shadow run
-- answers, listed here so it is asked.
--
-- SECTION 5 — WHY THIS IS NOT FIXED TONIGHT
-- ---------------------------------------------------------------------
-- Turning on six BLOCK rules that have never run, against a state machine
-- that has made 1.19M transitions unchallenged, can refuse transitions
-- the engine currently makes freely. That is not a migration to apply at
-- the end of a session.
--
-- The sequence that would be honest:
--
--   1. Route the transitions to the rules layer in SHADOW - evaluations
--      recorded, enforcement suppressed regardless of the rule's declared
--      enforcement. Gate on the from/to pair, not the event type (§3).
--   2. MEASURE the would-block rate per rule over a full cert round. A
--      rule that would block 5% of a working engine's transitions is
--      either wrong or is telling us something large.
--   3. Decide per rule: promote to enforcing, correct the rule, or
--      correct the engine. Three different answers, and the measurement
--      picks.
--   4. Only then enforce - and expect forces_recert = TRUE, because a
--      block that fires changes what the engine does, which is exactly
--      what the canons hash.
--
-- Volume is worth pricing before step 1: at ~2M transitions across the
-- run history, this roughly doubles ottoq_rule_evaluations. Determinism
-- also needs care - evaluation ORDER within a tick must be deterministic
-- or it becomes a new nondeterminism channel of the kind rounds 2-13
-- spent themselves closing.
--
-- WHY IT MATTERS NOW, in one sentence: the vehicle and asset feeds Chase
-- described will deliver state transitions, and a state transition is
-- precisely the event this layer cannot currently see.
-- =====================================================================

-- §1 — the four contexts the engine emits
SELECT action_context, count(*) AS evaluations, count(DISTINCT rule_code) AS rules,
       max(evaluated_at) AS last_seen
  FROM public.ottoq_rule_evaluations GROUP BY action_context ORDER BY 2 DESC;

-- §1 — the active rules that have never been evaluated
WITH ev AS (SELECT rule_code, count(*) AS n FROM public.ottoq_rule_evaluations GROUP BY rule_code)
SELECT r.rule_code, r.severity, r.enforcement, r.applies_to_actions,
       r.evaluator_function IS NOT NULL AS has_evaluator
  FROM public.ottoq_rules r LEFT JOIN ev ON ev.rule_code = r.rule_code
 WHERE r.status='active' AND COALESCE(ev.n,0)=0
 ORDER BY (r.enforcement='block') DESC, r.rule_code;

-- §2 — the transitions the engine already records and signs
SELECT event_type, count(*) AS n, max(occurred_at) AS last_seen
  FROM public.ottoq_events
 WHERE event_type IN ('vehicle.state_changed','stall.state_changed','twin.service_completed',
                      'charge.session_completed','twin.deploy_gate_override','twin.vehicle_arrived')
 GROUP BY event_type ORDER BY n DESC;

-- §3 — the trap. A transition-validity rule must gate on the from/to
-- pair, not the event type: ~29% of these events carry neither.
SELECT count(*) AS vehicle_state_changed_2d,
       count(*) FILTER (WHERE payload#>>'{diff,current_state,to}' IS NULL) AS without_a_transition,
       round(100.0*count(*) FILTER (WHERE payload#>>'{diff,current_state,to}' IS NULL)/count(*),1) AS pct
  FROM public.ottoq_events
 WHERE event_type='vehicle.state_changed' AND occurred_at > now() - interval '2 days';

-- §4 — the observed transition graph, the input a shadow run needs
SELECT (payload#>>'{diff,current_state,from}') AS from_state,
       (payload#>>'{diff,current_state,to}')   AS to_state,
       count(*) AS transitions
  FROM public.ottoq_events
 WHERE event_type='vehicle.state_changed' AND occurred_at > now() - interval '2 days'
   AND payload#>>'{diff,current_state,to}' IS NOT NULL
 GROUP BY 1,2 ORDER BY count(*) DESC;
