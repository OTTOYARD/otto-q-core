-- 0280  G44 PARTIALLY CLOSED (`0387`/`0388`), AND THE FIRST MEASUREMENT IT MAKES POSSIBLE:
--       THE ENGINE PERFORMS VEHICLE TRANSITIONS ITS OWN DECLARED STATE MACHINE DOES NOT
--       CONTAIN. SIX OF THEM ARE OPERATIONAL AND SIXTEEN ARE HARNESS RESET.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8). Evaluations
-- are `class='engine'` and purge with their run, so every count below carries its window.
--
-- ══ 1. WHAT WAS WIRED, AND WHY IT COULD NOT SIMPLY BE WIRED ════════════════
--
-- SM.001 and SM.003 (both `critical`) had callable evaluators and no caller. `0192` and
-- `0273` diagnosed it — a state-machine invariant is a property of a TRANSITION and all six
-- live probe points sit where something STARTS — and stopped at the diagnosis.
--
-- The hook already existed. `trg_ottoq_vehicles_state_change` and
-- `trg_ottoq_stalls_state_change` are attached, enabled, fire `AFTER INSERT OR UPDATE FOR
-- EACH ROW`, and record an EVENT without ever asking the shield. `ottoq_shield_probe` was
-- already the right entry point. So the fix was one call, not a mechanism.
--
-- **But a naive wiring would have measured a missing input instead of the rule.** Before
-- writing a line:
--
--   ottoq_state_transitions, status='active'    vehicle 41 · stall 10 · bess 17 · task 14
--   rows with EMPTY allowed_actor_types         **0 of 82**
--   rows admitting 'unknown'                    **0 of 82**
--   vehicle/stall state_changed events whose
--     actor_type is 'unknown'                   **129,060 of 129,060**
--
-- `ottoq_eval_sm_transition_validity` fails a transition on legality OR on a role gate, and
-- defaults `actor_type` to `'unknown'` when nothing supplies it — which nothing did. So the
-- probe would have failed **every** transition on the role gate. `0387` therefore attributes
-- the engine first (inside a sim run; production keeps `'unknown'` because there the actor
-- genuinely is unidentified), after verifying `ottoq_kpi_touch_actor_types` marks both
-- `'unknown'` and `'ottoq_engine'` `human_actor=false` so `touch_events_per_turn` cannot move.
--
-- **The attribution worked, and the measurement below is the proof: zero of the failures are
-- role-gate failures.** Every one is the legality half.

SELECT rule_code, action_context, enforcement_taken, passed, count(*) AS n,
       min(evaluated_at)::timestamp(0) AS first_at,
       max(evaluated_at)::timestamp(0) AS last_at
  FROM public.ottoq_rule_evaluations
 WHERE rule_code IN ('SM.001.vehicle_transition_validity','SM.003.stall_transition_validity')
 GROUP BY 1,2,3,4 ORDER BY 1, 3;

-- ══ 2. AND MY OWN LABEL WAS WRONG, FOUND BY THE PATH TEST ══════════════════
--
-- `0387`'s probes are measure-only — the trigger is AFTER the row changed and discards the
-- verdict, because a raising AFTER trigger would abort the tick. With the rules still
-- `enforcement='block'` the core logged `enforcement_taken='blocked'` for transitions that
-- **happened**. In this table that word records an action the shield PREVENTED: 3,009 such
-- rows across the six pre-existing probe points, including SLA.004's 418 at `redeployment`,
-- which are vehicles that genuinely did not deploy.
--
-- `0388` moved both rules to `enforcement='shadow'`, which the core already maps to
-- `shadow_pass`/`shadow_fail`. **The split is visible exactly at the migration boundary** —
-- `allowed`/`blocked` up to 18:59, `shadow_pass`/`shadow_fail` from 19:08, with 0388
-- classified at 19:01:10 — which is also the cleanest available proof that the
-- reclassification took effect rather than being asserted.
--
-- **And my `forces_recert` classification was wrong, caught by my own preflight.** I argued
-- FALSE because `0387` had already moved the floor. The preflight asserted that condition
-- instead of assuming it and refused: the widened recert runner had certified both
-- `grid_smoke` columns at 18:58 and 18:59, after 0387's 18:56:17 floor, while the file was
-- being written. A `forces_recert` judgement is a claim about a window of time, and the
-- window can close during the writing.
--
-- ══ 3. THE FINDING: 22 OF 54, ALL LEGALITY, AND THE SPLIT IS THE POINT ═════
--
-- In the post-`0388` window SM.001 read **32 shadow_pass / 22 shadow_fail**; SM.003 read
-- **32 pass / 0 fail**. The pre-0388 window agrees on the rate (88 / 60). So roughly
-- **40% of the vehicle transitions the engine performs are absent from its own declared
-- state machine** — and the naive headline is the wrong way to say it, because the 22 are
-- two unlike things:
--
--   offline → deployed                              8   HARNESS  fleet prime
--   en_route_to_depot → offline                     4   HARNESS  run teardown
--   charging_dcfc → offline                         2   HARNESS  run teardown
--   staged_for_departure → offline                  2   HARNESS  run teardown
--   ---------------------------------------------- 16   not operational transitions at all
--   charging_l2 → staged_for_departure              2   **OPERATIONAL**
--   charge_complete_holding → staged_for_departure  2   **OPERATIONAL**
--   staged_awaiting_service → charge_complete_holding 2 **OPERATIONAL**
--   ----------------------------------------------  6   real depot behaviour, undeclared
--
-- **Sixteen are `ottoq_tick_invariance_reset_fleet` and `ottoq_sim_stop_and_reset` moving
-- vehicles in and out of `offline`.** Those are not depot operations and the operational
-- state machine has no reason to declare them. Reporting them as illegal transitions would
-- be the same error as quoting an unscoped count.
--
-- **Six are the engine shortcutting its own declared flow**, and that is a real finding.
-- `staged_for_departure` is declared reachable from exactly three states — `offline`,
-- `service_complete_holding`, `staged_awaiting_service` — so the designed path out of a
-- charge is `charging_l2 → charge_complete_holding → staged_awaiting_service →
-- staged_for_departure`. The engine goes straight from the charging states, and also takes
-- `staged_awaiting_service → charge_complete_holding`, which is likewise undeclared.

SELECT left(reason, 95) AS reason, count(*) AS n
  FROM public.ottoq_rule_evaluations
 WHERE rule_code = 'SM.001.vehicle_transition_validity'
   AND passed IS FALSE AND enforcement_taken = 'shadow_fail'
 GROUP BY 1 ORDER BY 2 DESC;

SELECT from_state, string_agg(to_state, ', ' ORDER BY to_state) AS declared_to
  FROM public.ottoq_state_transitions
 WHERE entity_kind = 'vehicle' AND status = 'active'
   AND from_state IN ('charging_l2','charge_complete_holding','staged_awaiting_service')
 GROUP BY 1 ORDER BY 1;

SELECT string_agg(DISTINCT from_state, ', ' ORDER BY from_state) AS can_reach_staged_for_departure
  FROM public.ottoq_state_transitions
 WHERE entity_kind = 'vehicle' AND status = 'active' AND to_state = 'staged_for_departure';

-- ══ 4. WHICH SIDE IS WRONG IS A PRODUCT DECISION, NOT A BUG REPORT ═════════
--
-- Two readings, and they are not equivalent:
--
--   **(a) The declared machine is incomplete.** The shortcuts are legitimate — a vehicle
--   that finishes charging with nothing outstanding is ready to leave, and forcing it
--   through `staged_awaiting_service` would model a wait that does not happen. Fix: declare
--   the three transitions.
--
--   **(b) The engine is skipping states downstream consumers rely on.** Note that
--   `service_complete_holding` exists in the declared machine specifically as a route to
--   `staged_for_departure`, and the engine appears not to use it. Anything reading for a
--   "service complete" state would never see one. Fix: route through the intermediates.
--
-- **Not decided here.** It changes what "ready for work" means and which intermediate states
-- a consumer may depend on observing, which is Chase's call. Recorded as **G94**.
--
-- What is settled: the rules are `shadow`, so neither reading is being enforced, and
-- **promoting SM.001 to `block` today would refuse 40% of the engine's transitions** — which
-- is exactly why 2.9a's doctrine measures before enforcing, and exactly what could not be
-- known before `0387`.
--
-- ══ 5. WHAT THIS DOES AND DOES NOT CLOSE ══════════════════════════════════
--
-- SAY: *"twenty-three of thirty declared rules are evaluated, at seven probe points"* — and
-- say in the same breath that the two added are **measured, not enforced**, because G44 has
-- always been a wiring count and `0273` already warned that "evaluated" is weaker than
-- "binds".
--
-- DO NOT SAY the state machine is validated. SM.003 passing 32 of 32 is 32 stall transitions
-- on one depot in one window, not a proof; and SM.001 is failing 40% by design of the
-- measurement, not by defect.
--
-- **Seven rules remain unevaluated**, each for a reason rather than for lack of effort:
-- SM.006 (`bess_state_change`, the same shape and the next to do); SM.005
-- (`progression_decision_insert`, wants a trigger on the decision ledger and the override
-- path it judges may not occur in the twin at all); HW.006 (`task_completion`) and SLA.002
-- (`arrival`), which need probe POINTS that do not exist rather than callers; SM.004, which
-- gates `tech_override`/`emergency_stop`/`brain_pause` — actions nobody may ever perform
-- here, and probing for a population of zero would be another "exists and never called";
-- and TW.002/TW.004, info-severity advisories.

SELECT r.rule_code, r.severity, r.enforcement, r.applies_to_actions,
       (r.rule_code IN (SELECT DISTINCT rule_code FROM public.ottoq_rule_evaluations)) AS evaluated
  FROM public.ottoq_rules r
 WHERE r.status = 'active'
 ORDER BY evaluated, (r.severity = 'critical') DESC, r.rule_code;
