-- 0302  G108 — THE SOLVER HOP WORKS, AND IT ANSWERS IN **17 MILLISECONDS**. Every one of the
--       twelve 20-second timeouts was the wrong address, not a slow solver. `0301`'s retraction is
--       upheld from the other side: the agent path had never reached CP-SAT, and now it does.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- Measured 2026-09-21 07:41–07:43 UTC on live run f13fc580 (seed 100021, busy_day, otto_q).
--
-- ══ 1. THE BEFORE AND AFTER, IN ONE TABLE, FROM ONE LEDGER ══════════════════
--
-- `public.ottoq_model_call_ledger`, rows where `provider='cpsat_service' AND endpoint IS NOT NULL`
-- — the predicate `0301` established as the only thing that distinguishes the agent path from a
-- `forward_lex` label:
--
--   at (UTC)     outcome                      http  latency   endpoint_source
--   07:10:37     errored                      NULL   20006 ms  (v9: env only)
--   ...          errored  x12, all of them    NULL   20005–20011 ms
--   07:41:07     errored                      NULL   20011 ms  (last one)
--   07:41:43     solved_but_zero_proposals     200      63 ms   db:ottoq_service_endpoints
--   07:42:21     solved_but_zero_proposals     200      17 ms   db:ottoq_service_endpoints
--
-- **Twenty thousand milliseconds to seventeen.** The twelve failures were not a solver that needed
-- longer; they were a request that never arrived. Raising the bound from 5 s to 20 s (`0301` §3a)
-- changed nothing except how long each failure took, which is worth saying plainly: that change
-- was correct reasoning from the evidence available and it fixed nothing, because the evidence
-- available was the caller's own view and the caller could not tell "no answer" from "slow answer".
-- **The instrumentation is what fixed it** — `endpoint IS NOT NULL`, a real `latency_ms`, and an
-- `http_status` — because it made the box's silence legible, which sent me to the box's own access
-- log, which held **zero `POST /assign` lines**.

SELECT to_char(called_at, 'HH24:MI:SS')        AS at_utc,
       outcome, http_status, latency_ms, proposals_out,
       detail->>'endpoint_source'              AS endpoint_source,
       detail->>'fire_status'                  AS fire_status,
       detail->>'transport_error'              AS transport_error
  FROM public.ottoq_model_call_ledger
 WHERE provider = 'cpsat_service' AND endpoint IS NOT NULL
 ORDER BY called_at;

-- ══ 2. THE CAUSE, AND THE THING THAT WAS ARCHITECTURALLY WRONG ══════════════
--
-- The box carried **no Elastic IP** — `describe-addresses` in us-east-1 returned nothing at all —
-- so its public IPv4 was auto-assigned and changed when it was stopped at 02:52 and started again
-- at **03:29:21**. `ottoq-cpsat-propose` read its address from `OTTOQ_INTEL_URL`, a Supabase
-- function secret set once by hand. From 03:29:21 that secret named an address nothing answers on,
-- and nothing in the system could say so.
--
-- Two fixes, and the second is the one that matters:
--
--   (a) **An Elastic IP**, allocated and associated by `aws-activate-ssm action=assign_eip`, so the
--       address stops moving across a stop/start. Verified reachable **from the GitHub runner** —
--       genuinely off the box — answering `/health` with `cp_sat_forward_lex` in its optimizer
--       list, which also clears the security group, the published port and the subnet route in one
--       measurement. AWS charges the same $0.005/hour for a public IPv4 whether Elastic or
--       auto-assigned, so this replaced a charge rather than adding one (sourced in the workflow
--       header). It also confirms releasing `54.166.168.193` earlier the same day was right: that
--       one billed while attached to an instance stopped since 2026-08-15.
--
--   (b) **`public.ottoq_service_endpoints`** (`db/migrations/0398`), because an Elastic IP alone
--       leaves the real defect in place: **the location of a service that moves was only ever
--       recorded in a deploy-time secret.** Nothing could assert it pointed anywhere real, nothing
--       recorded when it last changed, and correcting it needed a human with console access. It is
--       now data — one row, one `UPDATE`, with `updated_at`, `updated_by` and a note — and
--       `ottoq-cpsat-propose` v10 prefers it, falling back to the env var so an unmigrated
--       database behaves exactly as before. Every ledger row carries
--       `detail.endpoint_source`, so which source was used is never inferred.
--
-- **The split is deliberate: THE URL IS DATA, THE TOKEN IS A SECRET.** `OTTOQ_INTEL_TOKEN` stays in
-- the function environment. The intelligence repo is public, and nothing about a credential being
-- awkward to rotate makes a table the right place for it.

SELECT * FROM public.ottoq_assert_service_endpoints();
SELECT service_key, base_url, updated_by, updated_at FROM public.ottoq_service_endpoints ORDER BY 1;

-- ══ 3. WHAT THE SOLVER SAID, AND WHY "ZERO PROPOSALS" IS NOT A FAILURE HERE ══
--
-- Both successful hops returned `outcome='solved_but_zero_proposals'` with this detail:
--
--   rows 0 · real_rows 0 · abstained 0 · attempts 1 · fire_status "empty"
--   receipt_present true · receipt_status "empty" · objective readiness_first
--   site_source ottoq_build_site_descriptor
--
-- **`rows: 0` with `abstained: 0` is an EMPTY answer, not an abstaining one** — the bridge found no
-- candidate vehicles to consider at that tick, so there was nothing to propose or refuse. 17 ms is
-- consistent with that and nothing else: the same solver on this depot's live frame with real
-- candidates took **24–511 ms** per objective (`0301` §2). `receipt_status='empty'` shows
-- `ottoq_proposer_submit_batch` received the empty batch and said so rather than inventing a row.
--
-- This is exactly the distinction v10's outcome classes were added to make. Before them, an empty
-- answer, an all-abstain answer and a failed call were one undifferentiated `receipt: null`, and
-- `0301` mistook one of them for a completed solve.
--
-- ══ 4. WHAT IS STILL OWED, AND THE QUERY THAT CLOSES IT ═════════════════════
--
-- **SAY TODAY:** *"the agent chain reaches CP-SAT. Nemotron reads the board and emits a bounded
-- objective; `ottoq-cpsat-propose` resolves the service address from the database, calls `/assign`,
-- and gets a 200 in 17–63 ms; `ottoq_proposer_submit_batch` accepts the result. Two hops have
-- completed and both were empty frames, so no proposal has yet come from the agent path."*
--
-- **DO NOT SAY** the agent path is proposing. It has answered, not proposed. G108 closes only on a
-- hop where the frame has candidates:
--
--     outcome='answered' AND proposals_out > 0 in ottoq_model_call_ledger,
--     AND ottoq_external_proposals rows with submitted_by_role = 'system:service_role',
--     AND the matching ottoq_proposer_fire_log row carrying
--         fire->>'submit_path' = 'edge:ottoq-cpsat-propose'
--
-- All three are required and none is redundant. The ledger row is written by the caller, so on its
-- own it is the caller's word for it. `submitted_by_role` is assigned by **Postgres**, not claimed
-- by the client, which is why it is the load-bearing witness — PATH A reads `system:db:postgres`
-- there and PATH B reads `system:service_role`. The fire-log row is where `submit_path` and
-- `endpoint_source` actually live (the proposals table has no `fire` column; a criterion written as
-- though it did would be a criterion nobody could run, which is how the first draft of this
-- section was wrong). `0301`'s retraction is why this is spelled out at all: a label read as an
-- event cost an hour of believing the loop was closed.
--
-- **AND ONE DEFECT `0301` FOUND IS ONLY HALF FIXED.** v10 makes the skip unmistakable in its own
-- reply — `{ok:true, skipped:..., engine:null, solver_ran:false}` — but the lie was in the CALLER:
-- `ottoq-orchestrator-agent` reads `engine: receipt.engine ?? "cp_sat_forward_lex"`, and `??`
-- falls through on null, so an absent engine is still reported as the primary engine. Until that
-- default is deleted, a reply that names no engine can still be recorded as a CP-SAT solve.

SELECT count(*) FILTER (WHERE endpoint IS NOT NULL)                            AS agent_path_hops,
       count(*) FILTER (WHERE endpoint IS NOT NULL AND http_status = 200)       AS reached_the_service,
       count(*) FILTER (WHERE endpoint IS NOT NULL AND outcome = 'answered')    AS answered_with_rows,
       coalesce(sum(proposals_out) FILTER (WHERE endpoint IS NOT NULL), 0)      AS proposals_from_agent_path,
       count(*) FILTER (WHERE endpoint IS NULL)                                 AS forward_lex_labels_not_calls
  FROM public.ottoq_model_call_ledger
 WHERE provider = 'cpsat_service';

-- The independent half. `submitted_by_role` is assigned by Postgres on
-- `ottoq_external_proposals`; `submit_path` and `endpoint_source` ride the fire record, which
-- lands in `ottoq_proposer_fire_log.fire` (NOT on the proposals row — the proposals table has no
-- `fire` column, and a query written as though it did is a query nobody ran).
SELECT p.submitted_by_role, p.status, count(*) AS proposal_rows
  FROM public.ottoq_external_proposals p
 WHERE p.source = 'forward_lex'
 GROUP BY 1,2 ORDER BY proposal_rows DESC;

SELECT f.effective_source,
       f.fire->>'submit_path'      AS submit_path,
       f.fire->>'endpoint_source'  AS endpoint_source,
       f.status, f.n_rows, f.n_planned, f.n_abstained, f.n_submitted,
       f.fired_at
  FROM public.ottoq_proposer_fire_log f
 WHERE f.effective_source = 'forward_lex'
 ORDER BY f.fired_at DESC
 LIMIT 10;

-- OPEN-ITEM: the agent path now REACHES CP-SAT (http 200 in 17-63 ms, address from the database) but has not yet PROPOSED -- both completed hops found an empty frame. G108 closes only on outcome='answered' with proposals_out > 0 AND a matching ottoq_external_proposals row carrying submitted_by_role='system:service_role' and fire->>'submit_path'='edge:ottoq-cpsat-propose'. Separately, ottoq-orchestrator-agent still reads `receipt.engine ?? "cp_sat_forward_lex"`, so an absent engine is still reported as the primary engine -- that default must be deleted. Tracked as G108.
