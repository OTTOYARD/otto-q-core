-- 0343  **`0425` and `0426` both VERIFIED on fresh evidence, each matching its stated prediction. And the
--       verification exposed something larger: `task_completion` is wired at a path that completes only
--       NON-STALL services, so `HW.006.physical_presence_verification` — the rule that asks whether the
--       vehicle is physically in the stall — can never receive a stall.**
--
--       Measured 2026-09-22 ~16:0x UTC (11:0x CT), windowed on `0426`'s apply (`20260922155423`) and
--       scoped to runs started after it, per rule 8 and `0250`.
--
-- ══ §1 `0425` VERIFIED — THE WALKAROUND NO LONGER CLAIMS A BAY ═══════════════
--
--     leg_type               legs   with_stall
--     --------------------   ----   ----------
--     service                6,939      3,943
--     sensor_clean             510        **0**
--     perimeter_walkaround     244        **0**    <- the new leg type, behaving as its twin does
--
-- And on runs started AFTER the apply, by `need_atom`:
--
--     need_atom              bookings   stall kinds
--     --------------------   --------   -----------
--     charge                      312   charging
--     exterior_wash                98   wash
--     perimeter_walkaround     **absent — 0**
--     sensor_clean             **absent — 0**
--
-- **The walkaround has joined its siblings at zero.** Stall-occupying services still book their own kind,
-- so the fix removed a phantom claim without disarming real ones. (Scoped to the new `sim_run_id`: the
-- ~3,785 historical rows are not deleted and an unscoped count still shows them, which would read as a
-- failed fix — the `0250` / rule-8 shape.)
--
-- ══ §2 `0426` VERIFIED — EXACTLY THE PREDICTED EFFECT ════════════════════════
--
-- `0426` §3 predicted, before applying: *"HW.003 will abstain on every non-charging completion… expect
-- `failed = 0` and `abstained_on_scope_guard = evals`."*
--
--     HW.003.sensor_liveness   evals 224   failed **0**   abstained on scope guard **224**
--
-- Was 1,288 failures of 3,550, every one `safety_critical`. **The prediction was exact.**
--
-- ══ §3 AND THE PART I PREDICTED WRONG, IN THE UNFLATTERING DIRECTION ═════════
--
-- `0426` §3 said the result would be *"FOUR of five codes vacuous instead of three."* **It is FIVE of
-- five.** `HW.006` also went to zero failures — from 234 — and `0425` had explicitly declined to claim
-- that and said to measure it. Measured, the mechanism is not a fix:
--
--     HW.006  evals 224  failed 0  reason: "insufficient context for presence verification"  stall_id: 0
--
-- **HW.006 is abstaining, not passing.** Removing the phantom booking removed the probe's only source of a
-- resolvable stall — and every stall it ever resolved was the phantom one, which is why all 234 of its
-- "real verdicts" were false. **So HW.006 at this probe point has never once had a legitimate input.**
--
-- ══ §4 THE STRUCTURAL CAUSE, AND IT IS BIGGER THAN EITHER MIGRATION ══════════
--
-- Every service that reaches `task_completion` is a service that occupies NO stall:
--
--     probed at task_completion          concurrency
--     -------------------------------    -----------
--     interior_inspection (178)          cabin
--     perimeter_walkaround (174)         exterior
--     triage_check (32)                  cabin
--     interior_tidy (28)                 cabin
--     remote_diagnostics (18)            digital
--     item_retrieval (12)                cabin
--     sensor_clean (8)                   exterior
--
-- while on the very same runs these COMPLETED and were never probed:
--
--     completed, NOT probed              concurrency   completions
--     -------------------------------    -----------   -----------
--     charge                             anchor            **242**
--     readiness_check                    gate              **182**
--     exterior_wash                      bay                **88**
--     interior_deep_clean                bay                **28**
--
-- **358 stall-occupying completions, plus 182 gate completions, with no `task_completion` evaluation at
-- all.** The cause is where `0422` spliced the probe: `twin.ottoq_sim_advance_visit_atoms`, which completes
-- the **concurrent** classes admitted by `ottoq_start_concurrent_atoms` (`cabin`/`exterior`/`digital`).
-- `anchor`, `bay` and `gate` atoms complete through other paths — the charge-session and service-flow
-- machinery — and none of those carries a probe.
--
-- **So the tenth probe point is structurally blind to every service HW.006 exists to judge.** `0418` chose
-- to resolve the stall via `ottoq_stall_bookings.need_atom = svc` and `0418` §2 declined to scope the probe
-- to stall-occupying atoms because that would *"throw away four working checks"*; `0333` established there
-- were no four working checks; and this file establishes the complement — **the probe is at the one
-- location that can never supply HW.006's input.** The rule is not unwired, it is wired somewhere it
-- cannot be answered.
--
-- ══ §5 WHAT TO SAY, AND WHAT THIS DOES TO EARLIER CLAIMS ═════════════════════
--
-- **SAY:** *"`task_completion` is probed, and all five of its declared codes are now vacuous there — three
-- abstained from the start, HW.003 since `0426` corrected a context key, and HW.006 because the probe sits
-- on the only completion path that never involves a stall. 1,288 + 234 safety-critical false alarms are
-- gone; no protection was gained."*
--
-- **DO NOT SAY** "five of five vacuous" as though the codes are useless — four of them are perfectly good
-- rules asked the wrong question in the wrong place.
--
-- **G122 must be RE-OPENED, not left closed.** I recorded it closed because `0422` wired the probe. The
-- probe exists and HW.006 still cannot evaluate anything, which is what G122 was actually about.
--
-- **The remedy is a probe at the stall-occupying completion paths** — the charge-session close and the
-- service-flow bay exit — where `stall_id` is in hand by construction and HW.006's question is meaningful.
-- That is a `forces_recert` tick-path change and is NOT attempted here; `0418`'s probe function already
-- takes `p_stall_id`, so it is a wiring job rather than a new instrument.
--
-- **And note the shape, because it is the counterpart of `0340`'s.** `0340` was a rule that fired where it
-- had no jurisdiction. This is a rule with jurisdiction that never sees a case. Both look identical in a
-- coverage census — "the code is evaluated" — and neither protects anything. **A probe point is not
-- coverage until the population it sees can contain the thing the rule tests for.**

\echo '=== 0343 §1 — 0425 verified: the walkaround books no stall, its siblings unchanged ==='
SELECT leg_type, count(*) AS legs, count(*) FILTER (WHERE to_stall_id IS NOT NULL) AS with_stall
  FROM public.ottoq_itinerary_legs
 WHERE leg_type IN ('perimeter_walkaround','sensor_clean','service')
 GROUP BY 1 ORDER BY 2 DESC;
-- perimeter_walkaround 244 legs / 0 with a stall, exactly like sensor_clean's 510 / 0.

WITH new_runs AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE started_at >= '2026-09-22 15:54:23+00'
     AND depot_id='11111111-1111-1111-1111-111111111111')
SELECT sb.need_atom, count(*) AS bookings, string_agg(DISTINCT st.stall_kind, ', ') AS kinds
  FROM public.ottoq_stall_bookings sb JOIN public.stalls st ON st.id=sb.stall_id
 WHERE sb.sim_run_id IN (SELECT sim_run_id FROM new_runs)
 GROUP BY 1 ORDER BY 2 DESC;
-- perimeter_walkaround is ABSENT. charge and exterior_wash still book their own kinds. SCOPE THIS TO THE
-- NEW RUN: the historical rows are not deleted and an unscoped count reads as a failed fix.

\echo '=== 0343 §2–§3 — 0426 exact; HW.006 abstains rather than passes; FIVE of five vacuous ==='
SELECT rule_code, count(*) AS evals,
       count(*) FILTER (WHERE NOT passed) AS failed,
       count(*) FILTER (WHERE reason LIKE '%N/A%')                  AS abstained_scope_guard,
       count(*) FILTER (WHERE reason LIKE '%insufficient context%') AS abstained_no_input,
       count(*) FILTER (WHERE context ? 'stall_id')                 AS carries_stall_id
  FROM public.ottoq_rule_evaluations
 WHERE action_context='task_completion' AND evaluated_at >= '2026-09-22 15:54:23+00'
 GROUP BY 1 ORDER BY 1;
-- HW.003: 0 failed, all abstained on the scope guard -- 0426's prediction, exact.
-- HW.006: 0 failed, all "insufficient context", ZERO carrying a stall_id -- abstaining, not passing.
-- I predicted four of five vacuous. It is five of five.

\echo '=== 0343 §4 — the probe is blind to every stall-occupying service, on the same runs ==='
WITH a AS (
  SELECT jsonb_array_elements(n.atoms) AS atom
    FROM public.ottoq_visit_needs n
   WHERE n.sim_run_id IN (SELECT sim_run_id FROM public.ottoq_sim_runs
                           WHERE started_at >= '2026-09-22 15:54:23+00'
                             AND depot_id='11111111-1111-1111-1111-111111111111'))
SELECT atom->>'concurrency' AS concurrency,
       string_agg(DISTINCT atom->>'svc', ', ') AS services,
       count(*) FILTER (WHERE atom->>'status'='done') AS completed,
       (atom->>'concurrency' IN ('cabin','exterior','digital')) AS probed_at_task_completion
  FROM a GROUP BY 1,4 HAVING count(*) FILTER (WHERE atom->>'status'='done') > 0
 ORDER BY completed DESC;
-- anchor (charge, 242 completed), gate (readiness_check, 182), bay (exterior_wash 88 +
-- interior_deep_clean 28) all COMPLETE and are NEVER probed -- 0422 spliced the probe into
-- twin.ottoq_sim_advance_visit_atoms, which only completes the concurrent classes. HW.006 asks whether the
-- vehicle is in the stall; the only completions it sees are the ones with no stall.

-- ══ §6 THE REMEDY, DESIGNED FROM SOURCE — AND ITS ONE LOAD-BEARING CONSTRAINT ═
--
-- §5 said the remedy is "a probe at the stall-occupying completion paths". Having read them, the design is
-- specific, and it has a constraint that would have produced a fresh false-alarm class if discovered after
-- applying rather than before.
--
-- **SITE: `twin.ottoq_sim_stop_charge_session`.** It holds `v_session.stall_id` and `v_session.vehicle_id`
-- from `ocpp_sessions` by construction, which is exactly the pair HW.006 needs. (`advance_visit_atoms`,
-- where `0422` put the probe, mentions `stall_id` **nowhere** — measured — which is the mechanical reason
-- the existing probe can never resolve one.)
--
-- **THE CONSTRAINT: the probe MUST sit BEFORE this statement**, which the function performs on the close
-- path:
--
--     UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_session.stall_id;
--
-- `ottoq_eval_hw_006_presence_verification` compares `stalls.current_vehicle_id` against the context's
-- `vehicle_id` and fails on `IS DISTINCT FROM`. **Probe after the clear and it fails 100% of charge closes**
-- — a brand-new `critical` false-alarm stream, the exact class `0426` and `0425` just removed 1,522 of.
-- Placing it before the clear asks the meaningful question: *was the vehicle still recorded at the stall at
-- the moment its charge completed?*
--
-- **AND THE SAME PROBE GIVES HW.003 ITS FIRST LEGITIMATE CASE.** HW.003 is charge-only by its scope guard
-- (`0340`), so passing `'service' := 'charge'` here makes it evaluate **for real** rather than abstain —
-- the one population it has jurisdiction over and has never been shown. So one probe moves two of the five
-- codes from vacuous to meaningful, which is why this site is worth more than a generic bay-exit probe.
--
-- Context to pass, by the conventions each consumer actually reads:
--     'stall_id'   := v_session.stall_id     -- HW.006's comparand
--     'vehicle_id' := v_session.vehicle_id   -- HW.006's comparand
--     'svc'        := 'charge'               -- the stall resolution and every analysis query (0418)
--     'service'    := 'charge'               -- HW.003's scope guard (0340/0426)
--     'now_ts'     := v_clock                -- the SIM clock the function already computed (0326 §1)
--
-- **NOT designed yet, and deliberately separate:** the `bay` exit (`exterior_wash`,
-- `interior_deep_clean`) in `twin.ottoq_sim_advance_service_flow` — 30,510 characters with several exit
-- paths, so it needs its own read rather than an assumption that one anchor covers them. And
-- `readiness_check` (`gate`, 182 completions) is a third path again. **One site per migration**, per
-- APPLYING.md's one-concern rule.
--
-- **Predicted effect, so it is falsifiable before it is built:** HW.006 produces its first real verdicts at
-- `task_completion` — expected to PASS, because a vehicle should still be at its stall when charging ends —
-- and HW.003 produces its first real charge verdicts. **A failure from either would be a genuine finding,
-- not a wiring artefact**, which is the difference between this probe and the one `0422` installed.
