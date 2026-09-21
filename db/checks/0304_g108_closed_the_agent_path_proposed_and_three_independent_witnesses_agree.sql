-- 0304  **G108 CLOSED. THE AGENT PATH PROPOSED, AND THE KERNEL ENACTED IT — §6/§7, added minutes
--       later, take this from a proposal to two vehicles physically charging on CP-SAT's plan with
--       the L1 shield evaluated on both.** Nemotron → `ottoq-cpsat-propose` → the EC2
--       CP-SAT service → `ottoq_proposer_submit_batch` → the deterministic shield, end to end, on
--       live run f13fc580 at 2026-09-21 07:53:12 UTC. Three independent witnesses agree and their
--       numbers reconcile exactly.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- Captured 07:54–07:56 UTC, immediately, because two of the three witnesses are `class='engine'`
-- and the next demo run deletes them.
--
-- ══ 1. THE THREE WITNESSES, AND WHY THREE ═══════════════════════════════════
--
-- `0301`'s retraction is the reason this is not one query. An audit label read as an event cost an
-- hour of believing the loop was closed, so the criterion `0302` §4 set requires three records
-- written by three different things:
--
--   **WITNESS 1 — `ottoq_model_call_ledger`, written by the CALLER** (so on its own it is only the
--   caller's word for it):
--     07:53:13 · outcome **answered** · http_status **200** · latency **37 ms**
--     proposals_out **2** · rows 10 · real_rows 2 · abstained 8
--     objective readiness_first · receipt_status **submitted**
--     endpoint_source **db:ottoq_service_endpoints**
--
--   **WITNESS 2 — `ottoq_external_proposals`, where `submitted_by_role` is assigned by POSTGRES**
--   rather than claimed by the client, which is what makes it load-bearing. PATH A reads
--   `system:db:postgres` there; this reads:
--     **submitted_by_role `system:service_role`**, source forward_lex — 19 rows at first capture,
--     of which **2 carry `abstain:false` and `verb:'assign_stall'`**.
--
--   **WITNESS 3 — `ottoq_proposer_fire_log.fire`, where `submit_path` rides the fire record:**
--     07:53:12 · **submit_path `edge:ottoq-cpsat-propose`** · endpoint_source db:ottoq_service_endpoints
--     assign_latency_ms 37 · status submitted · n_rows 10 · n_planned **2** · n_abstained 8 · n_submitted 10
--     (and a second at 07:53:56: assign_ms 23, n_rows 9, n_planned 0, n_abstained 9)
--
-- **The numbers reconcile across all three:** 10 rows = 2 planned + 8 abstained; `proposals_out 2`
-- in the ledger equals `n_planned 2` in the fire log equals the 2 non-abstain proposal rows. Three
-- writers, one arithmetic.

SELECT 'ledger (caller)' AS witness,
       to_char(called_at,'HH24:MI:SS') AS at_utc, outcome, http_status, latency_ms, proposals_out,
       detail->>'endpoint_source' AS endpoint_source,
       detail->>'rows' AS rows, detail->>'real_rows' AS real_rows, detail->>'abstained' AS abstained,
       detail->>'receipt_status' AS receipt_status
  FROM public.ottoq_model_call_ledger
 WHERE provider = 'cpsat_service' AND endpoint IS NOT NULL AND outcome = 'answered'
 ORDER BY called_at DESC LIMIT 5;

SELECT 'proposals (postgres-assigned role)' AS witness,
       submitted_by_role, source, status, disposition_reason, count(*) AS rows
  FROM public.ottoq_external_proposals
 WHERE source = 'forward_lex' AND submitted_by_role = 'system:service_role'
 GROUP BY 1,2,3,4,5 ORDER BY rows DESC;

SELECT 'fire log (submit_path)' AS witness,
       to_char(fired_at,'HH24:MI:SS') AS at_utc,
       fire->>'submit_path' AS submit_path, fire->>'endpoint_source' AS endpoint_source,
       fire->>'agent_objective' AS objective, fire->>'assign_latency_ms' AS assign_ms,
       status, n_rows, n_planned, n_abstained, n_submitted
  FROM public.ottoq_proposer_fire_log
 WHERE effective_source = 'forward_lex' AND fire->>'submit_path' = 'edge:ottoq-cpsat-propose'
 ORDER BY fired_at DESC LIMIT 5;

-- ══ 2. WHAT UNBLOCKED IT WAS THE DEPOT, NOT A CHANGE ════════════════════════
--
-- `0303` measured 26 consecutive hops returning `solved_but_zero_proposals` against **0 of 40**
-- charge stalls offerable. At 07:53 **one DCFC stall came free** — measured in the same minute as
-- `dcfc 10 total / 1 offerable, l2 30 total / 0 offerable` — and the solver proposed on that tick.
-- No code changed between the 26 empty answers and this one. That is the strongest available
-- evidence that the empty answers were the depot's truth and not the service's fault, and it is
-- why `0303` recorded them as a capacity finding rather than a defect.
--
-- ══ 3. AND THE SHIELD DISPOSED, WHICH IS THE POINT OF THE ARCHITECTURE ══════
--
--   status refused · reason **proposer_abstained** · 23
--   status superseded · reason **entity_decided_by_other_proposal** · 3
--   status pending · 2
--
-- Read those reasons carefully, because "23 refused" is not the shield rejecting 23 CP-SAT plans.
-- `proposer_abstained` is the disposition of rows where **CP-SAT itself abstained** — bookkeeping
-- for an abstention, not a rejection of a proposal. `entity_decided_by_other_proposal` is
-- precedence: another proposer reached that vehicle first. The two real `assign_stall` proposals
-- were `pending` at capture, awaiting the decide path.
--
-- **So propose/dispose is working as designed on the agent path for the first time:** an advisory
-- solver proposed, the deterministic path kept the right to dispose, and no proposer wrote a final
-- assignment. CLAUDE.md rule 6's "agents propose, solver disposes" is now exercised through the
-- agent chain and not only through cuOpt.
--
-- ══ 4. A NEW FINDING, AND IT IS A MODEL CLAIM THAT OVERSTATES ITSELF ════════
--
-- **Both real proposals in that batch name the SAME stall.** Measured:
--
--   proposal cc86db35 · vehicle 54aeb4ca · assign_stall · stall **609910b1** · pending
--   proposal 40486606 · vehicle fd6ec8c7 · assign_stall · stall **609910b1** · pending
--   both created 2026-09-21 07:53:12.979223+00 — the same batch, the same transaction
--
-- And `609910b1` was **the only offerable charge stall in the depot** at that moment. So CP-SAT
-- returned two vehicles for one stall in a single plan.
--
-- `supabase/functions/_shared/agent_solver_chain.ts` states, in its own doc comment on
-- `assignmentPairCost`: *"Compatibility and one-vehicle/one-stall constraints remain structural in
-- the LP."* **That sentence is not true of the batch this produced**, or the two rows are
-- deliberate ranked alternatives for the disposer to choose between and the comment should say so.
-- It is one or the other, and right now the code asserts the first while emitting the second.
--
-- **Nothing unsafe happened, and that is the propose/dispose design earning its keep twice over:**
-- `ottoq_stall_bookings`' EXCLUDE constraint makes double-booking physically impossible, and the
-- decide path disposes one proposal per entity. A proposer that emits a conflicting pair is
-- contained. But a proposer whose comment claims a constraint it does not enforce will mislead the
-- next person who trusts the comment instead of the batch — and if CP-SAT is ever promoted from
-- proposer to decide-path successor (CLAUDE.md C4 step 4 option (a)), that containment disappears.
-- **Tracked as G109.**

SELECT left(proposal_id::text,8) AS pid, left(entity_id::text,8) AS vehicle,
       proposal->>'verb' AS verb, left(proposal->>'stall_id',8) AS stall,
       (proposal->>'abstain')::bool AS abstain, status, disposition_reason, created_at
  FROM public.ottoq_external_proposals
 WHERE source = 'forward_lex' AND submitted_by_role = 'system:service_role'
   AND coalesce((proposal->>'abstain')::bool, false) = false
 ORDER BY created_at DESC LIMIT 10;

-- ══ 5. THE SENTENCE THAT MAY NOW BE QUOTED ══════════════════════════════════
--
-- *"The agent chain runs end to end. Nemotron reads the board and emits one of three bounded
-- objectives; the CP-SAT service resolves its address from the database, answers in 17–63 ms, and
-- its proposals reach the deterministic shield through the same door every proposer uses. Measured
-- on run f13fc580 at 2026-09-21 07:53:12 UTC: 2 proposals from 10 solver rows, confirmed by three
-- independent records — the call ledger, the proposals table's Postgres-assigned
-- `submitted_by_role='system:service_role'`, and the fire log's
-- `submit_path='edge:ottoq-cpsat-propose'`. The shield disposed them; the proposer wrote no
-- assignment."*
--
-- **What still may NOT be said:** that a CP-SAT proposal from the agent path has been ENACTED. Both
-- real proposals were `pending` at capture. Enactment is the decide path's call and is not required
-- for G108 — the finding was that the path produced nothing, and it now produces proposals — but it
-- is a separate claim and needs its own row.
--
-- ══ 6. IT CAN NOW BE SAID. ENACTED AT TICK 726, AND THE WORLD CHANGED. ══════
--
-- Three minutes after §5 was written, at **tick 726**, the decide path enacted two of them:
--
--   proposal 40486606 · vehicle fd6ec8c7 · stall 609910b1 · **enacted_by_kernel**
--   proposal b64c589c · vehicle b97789b5 · stall bcff04b2 · **enacted_by_kernel**
--
-- **And the world moved, with the booking naming who caused it:**
--
--   booking c8a8f5bd · stall 609910b1 (NASH-DCFC-STALL-02) · vehicle fd6ec8c7
--     purpose charge_dcfc · state **active** · **source `forward_lex`**
--     why: "…to satisfy need 'charge' (visit_atom); SoC 47% -> target 90%"
--   booking de07adaf · stall bcff04b2 (NASH-DCFC-STALL-03) · vehicle b97789b5
--     purpose charge_dcfc · state **active** · **source `forward_lex`**
--     why: "…to satisfy need 'charge' (visit_atom); SoC 69% -> target 90%"
--
-- and the vehicles are physically in them, charging, with SoC climbing:
--
--   fd6ec8c7 · current_state **charging_dcfc** · current_stall NASH-DCFC-STALL-02 · SoC 47 -> **64**
--   b97789b5 · current_state **charging_dcfc** · current_stall NASH-DCFC-STALL-03 · SoC 69 -> **77**
--
-- **THE L1 SHIELD GATED BOTH, AND THAT IS THE LINE WORTH THE MOST.** The two `ottoq_decisions` rows
-- recording the enactments — `68d78210` and `516fe75f`, `action_context='stall_assignment'`,
-- `l2_engine='forward_lex'`, `outcome_status='enacted'`, tick 726 — each carry
-- **`jsonb_array_length(rule_results) = 5`**. Contrast CLAUDE.md rule 6's standing finding about the
-- other AI path: `agent_calls_with_no_l1_rules` is **3,699 of 3,699** for `nvidia_nemotron`, because
-- the dial-writing agent is the one path the shield does not gate. **The CP-SAT proposer is gated.**
-- It reaches the world only through `stall_assignment`, where the shield evaluates, and the evidence
-- for that is on the enactment row itself rather than argued from the architecture diagram.
--
-- ══ 7. AND G109's CONTAINMENT IS NOW OBSERVED RATHER THAN PREDICTED ═════════
--
-- §4 said the two-proposals-for-one-stall pair was "contained today by the EXCLUDE constraint and by
-- the decide path disposing one proposal per entity". That was a prediction. Measured at the same
-- tick 726:
--
--   40486606 · vehicle fd6ec8c7 · stall 609910b1 · **enacted**  · enacted_by_kernel
--   cc86db35 · vehicle 54aeb4ca · stall 609910b1 · **refused**  · **stall_reserved**
--
-- One enacted, one refused **with the reason named** — `stall_reserved`, not a generic rejection.
-- The kernel resolved a conflict its proposer should not have emitted, at the same tick, and said
-- why. G109 stays open on the code's claim (`_shared/agent_solver_chain.ts` asserts the LP enforces
-- one-vehicle/one-stall structurally, and this batch shows it does not), but the safety question it
-- raised is answered: the architecture absorbs it, demonstrably.

SELECT left(p.proposal_id::text,8) AS pid, left(p.entity_id::text,8) AS vehicle,
       left(p.proposal->>'stall_id',8) AS stall, p.status, p.disposition_reason, p.disposed_tick
  FROM public.ottoq_external_proposals p
 WHERE p.source = 'forward_lex' AND p.submitted_by_role = 'system:service_role'
   AND coalesce((p.proposal->>'abstain')::bool, false) = false
 ORDER BY p.disposed_tick DESC NULLS LAST, p.created_at DESC;

-- The enactment's own audit rows, with the L1 rule count that makes the gating checkable.
SELECT left(decision_id::text,8) AS did, action_context, l2_engine, outcome_status,
       left(entity_id::text,8) AS vehicle, tick_seq,
       jsonb_array_length(coalesce(rule_results,'[]'::jsonb)) AS l1_rules_evaluated
  FROM public.ottoq_decisions
 WHERE l2_engine = 'forward_lex' AND outcome_status = 'enacted'
 ORDER BY created_at DESC LIMIT 6;

-- The world, which is the only witness that cannot be argued with.
SELECT left(b.booking_id::text,8) AS booking, s.stall_code, left(b.vehicle_id::text,8) AS vehicle,
       b.purpose, b.state, b.source, b.booked_at
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.source = 'forward_lex'
 ORDER BY b.booked_at DESC LIMIT 6;

-- ══ 8. AND THE LAST LIVE PIECE OF 0301's DEFECT IS NOW FIXED (orchestrator v29) ══
--
-- §5 and 0302 §4 both flagged that the retraction was only half repaired: `ottoq-cpsat-propose`
-- v10 made its decline unmistakable in its own reply (`{ok:true, skipped, engine:null,
-- solver_ran:false}`), but the LIE WAS IN THE CALLER. `ottoq-orchestrator-agent` read
--
--     engine: receipt.engine ?? "cp_sat_forward_lex"
--
-- and `??` falls through on **null as well as undefined** — so the bridge setting `engine: null`
-- was not enough on its own, and that is precisely why this line had to change rather than only
-- the bridge. Deployed as v29:
--
--   * a reply carrying `skipped` records `status:"skipped", engine:null, solver_ran:false`;
--   * the engine is **never defaulted** — `receipt.engine ?? null`, because an absent engine
--     means nothing ran;
--   * `solver_ran` and the bridge's `assign` block are carried onto the audit row;
--   * `solverAccepted` — which drives both the `verb` and `outcome_status` — counts only
--     "completed" and "fallback", so a skip can no longer produce `analyze_and_solve`/`enacted`.
--
-- **Verified live at 08:02:50 UTC**, one tick after deploy:
--
--   status completed · engine cp_sat_forward_lex · **solver_ran true**
--   **assign { rows 6, real_rows 0, latency_ms 24, endpoint_source db:ottoq_service_endpoints }**
--   verb analyze_and_solve · outcome_status enacted
--
-- Note what that row now says that the old one could not: the solver ran, answered in 24 ms, and
-- proposed **nothing** (6 rows, 0 real). A bare "completed" can no longer stand in for "something
-- was proposed" — the numbers are on the row. The 08:02:13 row immediately before it still reads
-- `solver_ran: null`, which dates the deploy precisely.
--
-- **STILL UNVERIFIED, and deliberately not claimed:** the skip branch itself. It fires only when
-- the agent chain ticks against a run that is no longer `running`, which is what happened at
-- 05:12:10 and produced the false "completed". Run f13fc580 has not ended yet. The check is one
-- query once it does — the last `orchestrator_agent` decision of the run must read
-- `status:"skipped"`, `engine:null`, `solver_ran:false`, and a verb that is not
-- `analyze_and_solve`.

SELECT to_char(created_at,'HH24:MI:SS') AS at_utc,
       enacted_action->'solver_handoff'->>'status'      AS handoff_status,
       enacted_action->'solver_handoff'->>'engine'      AS engine,
       enacted_action->'solver_handoff'->>'solver_ran'  AS solver_ran,
       enacted_action->'solver_handoff'->'assign'       AS assign,
       enacted_action->>'verb'                          AS verb,
       outcome_status
  FROM public.ottoq_decisions
 WHERE resolved_action_context = 'orchestrator_agent'
 ORDER BY created_at DESC LIMIT 8;

-- OPEN-ITEM: G109 -- CP-SAT returned two assign_stall proposals for the SAME stall (609910b1, the depot's only offerable charge stall) in one batch at 07:53:12, while _shared/agent_solver_chain.ts asserts "one-vehicle/one-stall constraints remain structural in the LP". Either the LP does not enforce it or the rows are deliberate ranked alternatives and the comment must say so. Contained today by ottoq_stall_bookings' EXCLUDE constraint and by the decide path disposing one proposal per entity, but that containment disappears if CP-SAT is ever promoted from proposer to decide-path successor. Also still unclaimed: no agent-path CP-SAT proposal has yet been ENACTED (both were pending at capture).
