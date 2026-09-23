-- 0321  **What the L1 shield actually PROTECTS, measured per evaluation rather than counted per
--       wire — and it is four codes of twenty-four. The one critical rule that detects the most is
--       in `shadow`, catching 379 violations per run and blocking none of them.**
--
--       Also: `0273`'s "twenty-one of thirty declared rules, at six decision points" is stale in
--       our favour again. Measured on run `d68d05bb`: **24 codes at NINE probe points.**
--
--       Pure measurement. No schema change, `forces_recert` FALSE.
--
-- ══ §1 THREE MORE PROBE POINTS, AND THREE "UNEVALUATED" CODES ARE NOW WIRED ══
--
-- `0192` counted four probe points, `0273` corrected it to six. Measured on one run today, the
-- shield fires at **nine**: `task_start`, `stall_assignment`, `charge_session_start`,
-- `redeployment`, `policy_write`, `bess_dispatch`, and — new to this census —
-- **`vehicle_state_change`, `stall_state_change`, `bess_state_change`.**
--
-- Those three carry the state-machine rules `0192` and `0273` both listed among the NINE
-- UNEVALUATED CRITICAL CODES. They are evaluated now:
--
--     SM.001.vehicle_transition_validity   vehicle_state_change    2,303 evaluations
--     SM.003.stall_transition_validity     stall_state_change      2,534 evaluations
--     SM.006.bess_transition_validity      bess_state_change          56 evaluations
--
-- So G44's population shrank from nine to six while nobody was counting. **Do not quote "nine
-- unevaluated" again; re-derive.** The remaining unevaluated set needs its own census.
--
-- ══ §2 EVALUATED IS NOT PROTECTED, AND HERE IS THE DIFFERENCE, MEASURED ══════
--
-- 34 (code, probe) pairs fired on `d68d05bb`. **Thirty of them never failed once.** A rule that
-- never fails is either a correctly-satisfied invariant or a rule that cannot bind, and a count
-- cannot tell you which — but the four that DID fail are, by construction, the only ones this run
-- proves are load-bearing:
--
--   code                                 probe                  evals   fails  enforcement  effect
--   ----------------------------------   --------------------  ------  ------  -----------  ----------
--   SLA.004.required_services_complete   redeployment           1,227   1,144  block        BLOCKED
--   SM.001.vehicle_transition_validity   vehicle_state_change   2,303     379  shadow       none
--   HW.002.charger_state_precondition    charge_session_start     437      16  block        BLOCKED
--   HW.005.vehicle_one_active_task       task_start            13,257       1  block        BLOCKED
--
-- **So the honest protection sentence is: of 24 codes evaluated across nine probe points, FOUR
-- demonstrably bound something on this run, and THREE of those four actually blocked.** Every
-- `safety_critical` code — EN.001 grid capacity, EN.005 grid hardstop, HW.001 connector
-- compatibility, HW.003 sensor liveness — evaluated 13,257 times each and failed zero times. That
-- is consistent with a depot that never approached those limits, and it is NOT evidence that the
-- guard works. **A rule with no failures has never been tested by the world.**
--
-- **And SLA.004 is the capacity wall wearing a rule's clothes.** It blocks redeployment when
-- required services are incomplete, and it fired 1,144 blocks in 1,227 evaluations — **93%**. The
-- shield is what holds vehicles in the depot, working exactly as designed, because two service bays
-- cannot retire the work. `db/checks/0320` explains where most of that work came from.
--
-- ══ §3 SM.001: A CRITICAL RULE IN SHADOW, AND 95% OF WHAT IT CATCHES IS ITS OWN FAULT ══
--
-- `SM.001` is `severity='critical'`, `enforcement='shadow'`, version 2. Shadow means detect and
-- allow: 379 failures, `enforcement_taken` of `shadow_fail`, zero blocked. Splitting the failures
-- by kind is what makes it actionable:
--
--     374   the transition is MISSING FROM THE TABLE      -> the rule is wrong
--       5   the actor is NOT AUTHORIZED for it            -> the ENGINE is wrong
--
-- **The table is DATA, not code.** `ottoq_eval_sm_transition_validity` looks up
-- `public.ottoq_state_transitions (entity_kind, from_state, to_state, status)` and then role-gates
-- on `allowed_actor_types`. The mechanism is well built — no-op transitions pass, the lookup is
-- clean, the role gate is separate and reports separately. **Only the table is incomplete**, which
-- means completing it is a data migration and not a rewrite.
--
-- Measured: **41 active `vehicle` rows declared, 52 distinct transitions observed, 26 missing.**
--
-- ══ §3a THE ONE DETAIL THAT EXPLAINS THE WHOLE GAP ═════════════════════════
--
-- `deployed -> tow_requested` **IS** in the table. `charging_l2 -> tow_requested` is **not**. Nor
-- is `staged_awaiting_service -> tow_requested`, nor `charge_complete_holding -> tow_requested`,
-- nor `charging_dcfc -> tow_requested`, nor `arrived_at_gate -> tow_requested`.
--
-- **The transition table was written when a vehicle could only fault while driving.** The in-depot
-- fault path — `twin.ottoq_sim_vehicle_exception_handler`, the mechanism `0320` shows condemns 74%
-- of the fleet — was added later, and nobody extended the state machine to admit it. Two artifacts
-- of one feature, built at different times, and **the rule caught the drift immediately and has
-- been reporting it into a shadow log ever since.**
--
-- ══ §3b THE 26 MISSING TRANSITIONS, CLASSIFIED — AND THEY ARE NOT ALL THE SAME ══
--
-- **(A) LEGITIMATE OPERATIONAL. The rule must learn these.** The engine does them as normal
-- business and the depot could not function otherwise:
--
--     staged_awaiting_service -> in_wash_bay          35   service dispatch
--     staged_awaiting_service -> in_detail_bay        16   service dispatch
--     charge_complete_holding -> staged_for_departure 24   the departure path
--     tow_requested -> emergency_staged              54   triage, by design
--     tow_requested -> staged_awaiting_service       25   recovery after triage
--     emergency_staged -> en_route_to_depot           3   recovery
--     staged_for_departure -> en_route_to_depot       1
--     staged_awaiting_service -> deployed             1
--     + the six in-depot fault entries of §3a       117
--
-- **(B) THE END-OF-RUN RESET, which is administrative and must NOT be legalised as operational.**
-- Nine transitions all ending in `offline`, totalling **116 — exactly the fleet size**, because
-- `ottoq_sim_stop_and_reset` takes every vehicle offline at once:
--
--     emergency_staged/charging_l2/staged_awaiting_service/charging_dcfc/deployed/
--     staged_for_departure/tow_requested/in_service_bay/en_route_to_depot -> offline
--
-- A vehicle must not be able to go from `charging_l2` straight to `offline` during operations. The
-- right treatment is **not a new row per pair** but a reset-scoped grant: the `allowed_actor_types`
-- mechanism already exists, so these belong to a dedicated reset actor and nothing else. Legalising
-- them for `ottoq_engine` would blind the rule to a real class of mid-operation disappearance.
--
-- **(C) GENUINELY SUSPICIOUS. Leave failing; these are open questions.**
--
--     offline -> charge_complete_holding             15   boots straight into "charge complete"
--     tow_requested -> charge_complete_holding        1   towed, then charge-complete, unrepaired
--     tow_requested -> en_route_to_depot              2   towed, then driving, unrepaired
--
-- Note `offline -> arrived_at_gate` (57) and `offline -> staged_awaiting_service` (38) ARE in the
-- table, so booting from offline is anticipated — booting into `charge_complete_holding` is not,
-- and a vehicle that arrives already charge-complete without charging is a boot-state synthesis
-- worth reading.
--
-- ══ §4 THE FIVE ROLE-GATE REFUSALS ARE THE ENGINE'S FAULT, NOT THE TABLE'S ══
--
--     actor ottoq_engine not authorized for vehicle transition
--       emergency_staged -> staged_awaiting_service
--
-- That transition IS declared, and its `allowed_actor_types` are the human ones —
-- `{command_center_operator, depot_supervisor}`. **The engine self-cleared five vehicles out of
-- emergency staging back into the service queue with no human sign-off.** In production that is a
-- vehicle returning to service after an emergency because a scheduler decided so.
--
-- This is the single finding in this file that is a **defect in the engine rather than in a rule**,
-- and it is exactly what a role gate is for. It should not be fixed by widening
-- `allowed_actor_types`; the engine should either request an approval (the `ottoq_ops_approvals`
-- path exists) or leave the vehicle staged.
--
-- ══ §5 HOW TO PROMOTE SM.001 WITHOUT BREAKING THE DEPOT ════════════════════
--
-- **Flipping `enforcement` from `shadow` to `block` today would block the wash bay, the detail bay,
-- the departure path and the entire triage flow.** The order is forced:
--
--   1. Add group (A) to `ottoq_state_transitions` with correct `allowed_actor_types`.
--   2. Add group (B) under a reset-only actor, never `ottoq_engine`.
--   3. Fix §4 in the engine — approval or no transition. Do not widen the gate.
--   4. Run a full day. Assert group (C) is the ONLY residue and it is small.
--   5. **Only then** promote to `block`.
--
-- That is CLAUDE.md 2.9a's blind-spot promotion doctrine — MEASURED first, ENFORCED after a clean
-- round — applied to a rule instead of an atom. The doctrine already exists in this repo for
-- determinism atoms; **this file is the argument that rule enforcement deserves the same
-- discipline, and that `shadow` is the rule-layer equivalent of a measured-but-unenforced atom.**
-- A `critical` rule parked in `shadow` with no promotion plan is a rule nobody has decided to trust.
--
-- ══ §6 WHAT IS NOT CLAIMED ═════════════════════════════════════════════════
--
-- **The thirty zero-failure pairs are not asserted to be useless.** They may be guarding limits the
-- depot never approached. The claim is narrower and harder to argue with: **this run provides no
-- evidence that they bind**, and a safety argument built on "we evaluate 24 rules" is weaker than it
-- sounds. Establishing which of the thirty CAN fail needs adversarial scenarios that push each
-- limit — which is what the C7 failure library is for.
--
-- **The 374 are one run's worth.** A transition absent here may still be declared and simply not
-- exercised; the 26 are missing relative to what this run did, not relative to all legal behaviour.
-- §3's query is the standing form and should be re-run after any change to the state machine.

\echo '=== 0321 §1 — every probe point the shield actually fires at, and the codes per probe ==='
SELECT action_context AS probe_point,
       count(DISTINCT rule_code) AS codes,
       count(*)                  AS evaluations
  FROM public.ottoq_rule_evaluations
 GROUP BY 1 ORDER BY evaluations DESC;
-- Nine probe points at 0321, not the six 0273 recorded. ottoq_rule_evaluations is class='engine',
-- so cite the run: these figures are from d68d05bb unless the table has since been purged.

\echo '=== 0321 §2 — evaluated vs actually binding: only failures prove a rule is load-bearing ==='
SELECT rule_code, action_context, severity, enforcement,
       count(*)                            AS evals,
       count(*) FILTER (WHERE NOT passed)  AS failures,
       CASE WHEN count(*) FILTER (WHERE NOT passed) = 0 THEN 'never tested by the world'
            WHEN enforcement = 'shadow'                THEN 'detects, does not block'
            ELSE 'BINDING' END             AS verdict
  FROM public.ottoq_rule_evaluations
 GROUP BY 1,2,3,4 ORDER BY failures DESC, evals DESC;
-- EXPECT ~30 of 34 pairs at zero failures. Quote the BINDING count, not the evaluated count.

\echo '=== 0321 §3 — the SM.001 table gap: observed transitions the state machine does not declare ==='
WITH observed AS (
  SELECT payload->'diff'->'current_state'->>'from' AS from_state,
         payload->'diff'->'current_state'->>'to'   AS to_state,
         count(*) AS occurrences, count(DISTINCT entity_id) AS vehicles
    FROM public.ottoq_events
   WHERE event_type = 'vehicle.state_changed'
     AND payload->'diff' ? 'current_state'
     AND payload->'diff'->'current_state'->>'from'
         IS DISTINCT FROM payload->'diff'->'current_state'->>'to'
   GROUP BY 1,2
)
SELECT o.from_state, o.to_state, o.occurrences, o.vehicles,
       CASE WHEN o.to_state = 'offline' THEN 'B: reset, needs a reset-only actor'
            WHEN o.to_state = 'tow_requested' THEN 'A: in-depot fault, add'
            WHEN o.from_state = 'offline' THEN 'C: boot-state, investigate'
            WHEN o.from_state = 'tow_requested' AND o.to_state IN
                 ('charge_complete_holding','en_route_to_depot') THEN 'C: unrepaired, investigate'
            ELSE 'A: operational, add' END AS classification
  FROM observed o
  LEFT JOIN public.ottoq_state_transitions t
         ON t.entity_kind = 'vehicle' AND t.from_state = o.from_state
        AND t.to_state = o.to_state AND t.status = 'active'
 WHERE t.transition_id IS NULL
 ORDER BY o.occurrences DESC;
-- THE STANDING FORM. Re-run after any state-machine change, and before promoting SM.001 to block.

\echo '=== 0321 §4 — the engine performing transitions reserved for humans ==='
SELECT reason, count(*) AS violations, count(DISTINCT entity_id) AS vehicles
  FROM public.ottoq_rule_evaluations
 WHERE rule_code = 'SM.001.vehicle_transition_validity'
   AND NOT passed AND reason LIKE 'actor %not authorized%'
 GROUP BY 1 ORDER BY violations DESC;
-- A defect in the ENGINE, not the table. Do not fix by widening allowed_actor_types.

\echo '=== 0321 §5 — every critical or safety_critical rule parked in a non-blocking mode ==='
SELECT rule_code, severity, enforcement, status
  FROM public.ottoq_rules
 WHERE status = 'active'
   AND severity IN ('critical','safety_critical')
   AND enforcement NOT IN ('block')
 ORDER BY severity, rule_code;
-- A critical rule in shadow or log_only is a rule nobody has decided to trust. Each needs a
-- promotion plan or a demotion in severity -- the two must not disagree silently.
