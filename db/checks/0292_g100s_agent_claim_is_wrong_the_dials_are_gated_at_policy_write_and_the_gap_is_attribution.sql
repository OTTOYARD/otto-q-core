-- 0292  G100's CENTRAL CLAIM ABOUT THE AGENT IS **WRONG**, AND I PUBLISHED IT NINETY MINUTES AGO.
--       THE AGENT'S ONLY REACH INTO ENGINE STATE IS POLICY DIALS, AND THOSE **ARE** L1-GATED —
--       `AI.001.agent_dial_within_envelope` AT `policy_write`, **254 EVALUATIONS ON THIS RUN**.
--       WHAT IS REAL IS AN **ATTRIBUTION** GAP, NOT A GATING GAP, AND IT IS MUCH SMALLER.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), live run
-- `e8b8eb3e-da9d-41ff-ab67-84b6998ba441` (busy_day, seed 100020), measured 2026-09-20 19:42 CT
-- (2026-09-21 00:42 UTC), tick 665, run still in flight.
--
-- `0392`/G100 seeded `ottoq_enactment_branches` with the note that `orchestrator_agent` is *"the
-- one path on which an AI changes engine state and the one path the L1 shield does not gate"*, and
-- FINDINGS.md G100 says the same. **Both are wrong.** The direction of the error is the one rule 6
-- names as the more dangerous: it makes the product look **worse** than it is, in a safety claim,
-- which is exactly the sentence a hostile reader would quote.
--
-- ══ 1. THE CHAIN, FOLLOWED END TO END, IN FOUR HOPS ════════════════════════
--
-- I traced this because the edge function's insert reads `entity_type: "depot"` — and the shield
-- is vehicle-scoped, which should have made me ask what the agent actually touches before calling
-- it ungated.
--
--   (1) `edge-functions/ottoq-orchestrator-agent/index.ts` — the agent writes ONE
--       `ottoq_decisions` row per tick, `entity_type='depot'`,
--       `resolved_action_context='orchestrator_agent'`, with **no `rule_results`**. Its whole
--       effect set is `applied` / `queued` / `rejected`: dial writes and ops actions.
--   (2) `public.ottoq_apply_ops_action(run, depot, action, args, by)` — **every whitelisted
--       branch is a `ottoq_policy_set` call and nothing else.** `raise_deploy_surge`,
--       `extend_forecast_horizon`, `enable_energy_reserve`, each clamped in its own branch
--       (`LEAST`/`GREATEST`, and a ≤+40%/move limiter on the first). **Anything off-whitelist
--       INSERTs into `ottoq_ops_approvals` as `pending`** — the human queue, not a silent drop.
--       So the agent's entire physical reach is policy dials. No stall, no vehicle, no booking.
--   (3) `public.ottoq_policy_set` — **calls `ottoq_shield_probe` with `policy_write`.** One query
--       settles it: `prosrc LIKE '%ottoq_shield_probe%'` is **true**.
--   (4) `ottoq_rule_evaluations` on this run — `action_context='policy_write'`,
--       `entity_type='policy_param'`, **254 evaluations of the single code
--       `AI.001.agent_dial_within_envelope`**, a rule whose name states its job.
--
-- **So the edge function's own header comment — *"L1 shield still gates every physical effect;
-- vehicle-first inviolable"* — is ACCURATE, and I contradicted it from the data without reading
-- the path it describes.**
--
-- ══ 2. WHAT IS ACTUALLY TRUE, STATED NARROWLY ══════════════════════════════
--
-- The agent's decision row carries no `rule_results` because **the evaluation happens somewhere
-- else**: a different `action_context` (`policy_write`, not `task_start`), a different
-- `entity_type` (`policy_param`, not `depot`), and **nothing joins the two.** There is no
-- `correlation_id` on the agent's row and no decision reference on the evaluation.
--
-- So `agent_calls_with_no_l1_rules = 1,120 of 1,120` — carried in CLAUDE.md rule 6 from `0340`'s
-- ledger — is a **correctly computed metric with a misleading name**. It measures *"the agent's
-- decision row does not carry its own rule results"*, which is true, and it reads as *"the agent
-- is ungated"*, which is false. Same shape as `0289`'s `offerable` and `0392`'s own `l2_engine`
-- finding: **a field or metric named for a conclusion rather than for what it counts.** Third
-- instance in two days, and this time the misreader was me, twice in one night.
--
-- The remedy therefore is NOT to route the agent through `ottoq_shield_and_log` — that function
-- hardcodes `entity_type='vehicle'` and `CONTINUE`s on any action with no `vehicle_id`, so it
-- would skip every agent row it was given. **The remedy is a correlation id**: stamp one on the
-- agent's decision and pass it into `ottoq_policy_set`'s probe call (the column already exists on
-- `ottoq_rule_evaluations`), so the 254 evaluations join back to the decision that caused them.
-- That is an attribution fix, additive, and it does not change what the shield decides.

SELECT action_context, entity_type, count(*) AS evaluations,
       count(DISTINCT rule_code) AS codes, string_agg(DISTINCT rule_code, ', ') AS which
  FROM public.ottoq_rule_evaluations
 WHERE sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441'
 GROUP BY 1, 2 ORDER BY 3 DESC;

-- ══ 3. AND THE SAME QUERY RETIRES A SECOND STALE SENTENCE, ALSO IN OUR FAVOUR ══
--
-- CLAUDE.md 2.5 currently instructs: *"twenty-one of thirty declared rules, at six decision
-- points, every evaluation logged"* — `0273`'s re-derivation, dated 2026-09-20. Measured on this
-- run, one day later:
--
--   active rule codes                                    **30**
--   codes evaluated on this run                           **23**
--   distinct probe points                                  **8**
--
-- **The two new probe points are `vehicle_state_change` (628 evaluations, `SM.001`) and
-- `stall_state_change` (581, `SM.003`)**, and both codes were on `0273`'s list of nine
-- unevaluated — where it said *"the nine unevaluated codes are the same nine, and six are still
-- critical."* **They were wired by `db/migrations/0387`, which I applied the same day**, and 2.5
-- was never re-derived after it. A file correcting an undercount, made stale within hours by the
-- migration that fixed what it described.
--
-- **THE SENTENCE TO QUOTE NOW:** *"twenty-three of thirty declared rules, at eight decision
-- points, every evaluation logged."* And `0273`'s caveat survives intact and still governs:
-- **evaluated is a WIRING count, not a PROTECTION count** — `0263` §1 showed four of the five
-- codes at `stall_assignment` are charge-specific and cannot judge a parking hold, and
-- `HW.004.stall_single_vehicle` says in its own description that an index enforces it. 23 of 30
-- is the optimistic bound.
--
-- **The seven still unevaluated, four of them `critical`:**
--
--   HW.006.physical_presence_verification              critical
--   SM.004.role_gated_actions                         critical
--   SM.005.audit_note_required_on_overrides            critical
--   SM.006.bess_transition_validity                   critical   (G96, measured by 0285)
--   SLA.002.max_queue_depth                           warning
--   TW.002.overnight_staging                          info
--   TW.004.tariff_window                              info
--
-- Two of those seven are already characterised and waiting: **SM.005** is G97's population (the
-- unaudited `overridden_to_default` rows, whose predicate `0391` just corrected — the trigger is
-- written and deferred until this run ends), and **SM.006** is G96 (3,426 of 23,730 BESS
-- transitions direct charge<->discharge, which the rule forbids; whether that is a real
-- requirement is an external question about grid-inverter practice and is the one thing in this
-- queue that needs a web source).

WITH ev AS (SELECT DISTINCT rule_code FROM public.ottoq_rule_evaluations
             WHERE sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441'),
al AS (SELECT DISTINCT rule_code FROM public.ottoq_rules WHERE status = 'active')
SELECT (SELECT count(*) FROM al) AS active_codes,
       (SELECT count(*) FROM ev) AS evaluated_this_run,
       (SELECT count(DISTINCT action_context) FROM public.ottoq_rule_evaluations
         WHERE sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441') AS probe_points,
       (SELECT string_agg(a.rule_code||' ('||r.severity||')', ', ' ORDER BY a.rule_code)
          FROM al a JOIN public.ottoq_rules r
            ON r.rule_code = a.rule_code AND r.status = 'active'
         WHERE a.rule_code NOT IN (SELECT rule_code FROM ev)) AS still_unevaluated;

-- ══ 4. WHAT SURVIVES OF G100, AND IT IS STILL WORTH HAVING ═════════════════
--
-- **The instrument stands. The rules-side blind spot stands. One of the two gap branches stands.**
--
--   - A rules-side coverage count still cannot see an enactment that consulted no rule. That was
--     the finding and it is unaffected: §3 above is a rules-side count, and it reports 23 of 30
--     while `ottoq_assert_shield_coverage` reports 170 unshielded enacted decisions on the same
--     run. **Both are right. They answer different questions, and only one of them was being
--     asked before `0392`.**
--   - **`gate_intake_no_charge` is still a real gap and is now the only one.** Its loop books a
--     staging stall via `ottoq.ottoq_book_stall`, stamps `to_stall_id`, writes `'enacted'`, and
--     emits `proceed_to_stall`, with no probe between its `FOR` and its `END LOOP` — and unlike
--     the agent there is no second probe point downstream, because a staging booking is not a
--     policy write. It is vehicle-scoped, so `ottoq_shield_and_log` fits it exactly.
--   - `orchestrator_agent` is **reclassified**: `shield_expected` FALSE with the reason recorded,
--     because a depot-scoped advisory row is not where the vehicle shield belongs and the gating
--     it needs already happens at `policy_write`. `db/migrations/0393` makes that change to the
--     declaration table and nowhere else.
--
-- **And the lesson, which is the reason this file exists rather than a quiet edit.** `0392` was
-- built on a census of `resolved_action_context` — a field that says what a decision was ABOUT,
-- and which I read as though it said what had been CHECKED. The check that would have caught it
-- costs one query (`does the writer's effect path call the probe?`) and I skipped it for the one
-- branch where the answer was most consequential. **An audit instrument is not evidence about the
-- thing it is pointed at until the path it measures has been read end to end** — and `0392` shipped
-- with four of five branches read that way, and the fifth, the one I led with, not read at all.
