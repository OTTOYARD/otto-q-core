-- 0301  THE AGENT CHAIN REACHED CP-SAT EXACTLY ONCE ON RUN 71942fbf, AND IT PRODUCED NOTHING.
--       All 255 CP-SAT proposals on that run came from the OTHER CP-SAT path — the `*/5 * * * *`
--       cron in `proposer-loop.yml` — and the evidence ledger cannot tell the two apart, which is
--       why `ottoq_intelligence_ledger` reports **"cpsat_service: 3,124 calls, 0 proposals"** for a
--       provider that had never been called over HTTP at all.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- Measured 2026-09-21 07:0x UTC on the COMPLETED run 71942fbf, and written BEFORE the next demo
-- run, because `ottoq_decisions` and `ottoq_external_proposals` are both `class='engine'` and the
-- purge takes them. Every count below is from that run unless it says otherwise.
--
-- ══ 1. TWO PATHS, ONE SOURCE NAME, AND ONLY ONE COLUMN THAT SEPARATES THEM ══
--
-- Both CP-SAT paths end at `ottoq_proposer_submit_batch(p_source := 'forward_lex')`, so the
-- proposals are indistinguishable by `source`. What separates them is who authenticated:
--
--   PATH A  otto-q-core `.github/workflows/proposer-loop.yml`, `cron: "*/5 * * * *"`, runs
--           `python3 -m bridge.proposer_bridge` on the GitHub runner, connecting straight to
--           Postgres.                                    ->  submitted_by_role  system:db:postgres
--   PATH B  the agent chain. `ottoq_cuopt_refresh` posts to `ottoq-orchestrator-agent`
--           (Nemotron), which posts the handoff to `ottoq-cpsat-propose`, which calls the
--           EC2 intelligence service's `/assign`.        ->  submitted_by_role  system:service_role
--
-- Measured on 71942fbf:
--
--   source                  submitted_by_role      rows   window (UTC)
--   forward_lex             system:db:postgres      255   05:03:51 -> 05:11:49
--   cuopt                   system:service_role      98   04:05:02 -> 05:10:00
--   ottoq_service_priority  system:db:postgres        4   05:05:35 -> 05:10:12
--   greedy_constrained      (null)                    1   05:11:45
--
-- **Every CP-SAT proposal on this run is PATH A.** forward_lex dispositions: 198 superseded,
-- 48 refused, 5 expired, **4 enacted**. PATH B contributed zero rows.

SELECT source, declared_source, submitted_by_role, count(*) AS rows,
       min(created_at) AS first_seen, max(created_at) AS last_seen
  FROM public.ottoq_external_proposals
 WHERE sim_run_id = '71942fbf-76ee-4b99-9065-c9164a714993'
 GROUP BY 1,2,3 ORDER BY rows DESC;

-- ══ 2. WHY PATH B PRODUCED NOTHING: A FIVE-SECOND ABORT ON A SOLVER THAT ANSWERS IN ONE ══
--
-- `ottoq-cpsat-propose` wrapped its `/assign` fetch in `AbortSignal.timeout(5_000)`. Of the
-- **176** agent handoffs on this run, **175 fell back to cuOpt with `fallback_reason` exactly
-- "Signal timed out."** and **1 completed**. The reason string is uniform across all 175 and
-- across the whole window, including after the CP-SAT image went live at 04:31 UTC — so this is
-- not the stale-image failure of the previous day wearing a new face, it is the abort.
--
-- Five seconds does not cover what the service does per request: a cold uvicorn, an OR-Tools
-- import, and up to THREE CP-SAT solves (`max_retries: 2` in `assignmentRequest`, so the bounded
-- rejection-feedback loop may fire three times), on a 2-vCPU burstable t3.medium. For scale, the
-- same solver against this run's own live frame, run locally on the pinned core ref
-- (158 stalls, 116 vehicles, 39 sessions, derived `power_cap_kw_hard` 574 kW), took
-- **511 / 351 / 24 ms** for readiness_first / throughput_first / energy_balanced — which is
-- comfortably inside 5 s and says the bound was not absurd, only too tight once a cold start and
-- three solves are stacked behind an edge-to-EC2 hop.
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ RETRACTED 2026-09-21 07:16 UTC, WITHIN THE HOUR, AND THE FILE'S OWN     │
-- │ TITLE IS NOW WRONG: THE AGENT NEVER REACHED CP-SAT. NOT ONCE.          │
-- └─────────────────────────────────────────────────────────────────────────┘
--
-- The paragraph below said the 05:12:10 handoff was "the first time the whole chain ran end to
-- end" and that "CP-SAT answered". **Both are false, and I had no evidence for either** — I read
-- `status: completed` plus `engine: cp_sat_forward_lex` off an audit row and treated the label as
-- the event. Two independent measurements refute it:
--
--   (1) **`POST /assign` lines in the service's own uvicorn access log: ZERO.** Measured over SSM
--       at 07:15 UTC on the container created 2026-09-21 04:30:55 — which covers 05:12:10. For
--       contrast the same log holds 4 `GET /health` lines, all of them my probes. The box has
--       never been asked to solve anything. It answered `/health` on loopback in **14 ms** listing
--       `["energy_mpc","cp_sat_forward_lex"]`, at **0.14% CPU** with **loadavg 0.00** on 2 vCPU, so
--       "healthy but slow" is refuted too.
--   (2) **The surviving evidence row at that exact timestamp is `nvidia_nemotron`, not
--       `cpsat_service`.** `ottoq_model_call_ledger` is `class='evidence'` and outlived the purge
--       that deleted run 71942fbf; at `05:12:10.158057+00`, chain `c37a27a3`, there is one
--       Nemotron row and **no `cpsat_service` row carrying an endpoint anywhere near it**.
--
-- **AND THE CODE EXPLAINS IT EXACTLY, which is the strongest form of this proof because it needs
-- no surviving data.** `ottoq-cpsat-propose` v8 opened with an early return for a run that is no
-- longer live:
--
--     if (run.status !== "running")
--       return json({ ok: true, skipped: "run is not active", chain_id: chainId });
--
-- No `fallback`, no `engine`, no `receipt`. And `ottoq-orchestrator-agent` reads that reply as:
--
--     status:  receipt.fallback === true ? "fallback" : "completed"   ->  "completed"
--     engine:  receipt.engine ?? "cp_sat_forward_lex"                 ->  "cp_sat_forward_lex"
--     receipt: receipt.receipt ?? null                                ->  null
--     fallback_reason: receipt.fallback_reason ?? null                ->  null
--
-- That reproduces the observed row **field for field**, including the `receipt: null` I flagged as
-- undiagnosable — and it requires no HTTP call at all. Run 71942fbf ended around its 540-minute
-- horizon; the agent chain fired once more afterwards, `ottoq-cpsat-propose` correctly declined a
-- finished run, and the caller recorded the decline as a completed CP-SAT solve.
--
-- **THE DEFECT IS THE `??` DEFAULT.** `receipt.engine ?? "cp_sat_forward_lex"` names an engine
-- when the reply named none. An absent engine means nothing ran, and defaulting it to the primary
-- engine manufactures a success — the same class of defect as the deploy workflow's success line
-- that printed "/health lists cp_sat_forward_lex" after a rollback, and as `cpsat_service`'s 3,124
-- ledger rows that were never calls. Third instance in two days of a label being read as an event.
--
-- **What is true, and all that is true:** the agent layer works — Nemotron reads the board,
-- reasons in the depot's own vocabulary, and emits a bounded objective, and that part is quoted
-- below unchanged because it is real and it is logged. **The solver hop has never happened.**
--
-- The original paragraph follows, wrong, for the record:
--
-- **THE ONE THAT COMPLETED IS WORTH READING IN FULL**, because it is the first time the whole
-- chain ran end to end. At 2026-09-21 05:12:10 UTC, tick 1137:
--
--   engine            cp_sat_forward_lex            (NOT the cuopt fallback)
--   status            completed
--   objective         readiness_first
--   why               "239 pending service atoms (93 readiness_check, 64 charge, 17
--                      exterior_wash, 21 interior_inspection, 15 perimeter_walkaround, 13
--                      interior_deep_clean, 13 interior_tidy, 8 triage_check) vs only 11
--                      staged_for_departure; BESS at 13.4% SoC cannot sustain peak shaving; 53
--                      shield overrides (SLA.004) confirm service completion violations"
--   verb              analyze_and_solve
--   outcome_status    enacted
--   receipt           **null**
--
-- So Nemotron read the board, reasoned about it in the depot's own vocabulary, chose a bounded
-- objective, handed off, and CP-SAT answered. **And `receipt` is null, so nothing was proposed** —
-- and nothing in the record says whether CP-SAT abstained on every row, whether the batch was
-- empty, or whether the RPC simply returned nothing. That ambiguity is a defect in its own right.
--
-- ^^ END OF THE RETRACTED PARAGRAPH. The first two clauses are true and logged. "and CP-SAT
-- answered" is false — see the retraction above. The `receipt: null` I called "a defect in its own
-- right" was in fact the ONLY honest field in the row: nothing was proposed because nothing ran.

SELECT enacted_action->'solver_handoff'->>'status'          AS handoff_status,
       enacted_action->'solver_handoff'->>'engine'          AS engine,
       enacted_action->'solver_handoff'->>'fallback_reason' AS fallback_reason,
       count(*) AS n, min(created_at) AS first_seen, max(created_at) AS last_seen
  FROM public.ottoq_decisions
 WHERE resolved_action_context = 'orchestrator_agent'
   AND sim_run_id = '71942fbf-76ee-4b99-9065-c9164a714993'
 GROUP BY 1,2,3 ORDER BY n DESC;

-- ══ 3. AND THE LEDGER NUMBER THAT WAS NEVER A CALL COUNT ════════════════════
--
-- `public.ottoq_intelligence_ledger` reports `cpsat_service`: **3,124 rows, 0 proposals**. A
-- reader takes that for a busy solver that never answers. It is neither.
--
--   rows                3,124
--   with http_status        0
--   with endpoint           0
--
-- **Not one of those rows is a call.** `ottoq_capture_decision_model_call` maps any decision
-- carrying `l2_engine='forward_lex'` to provider `cpsat_service`, so a DB-side LABEL is recorded
-- as a provider call. The 2,977 of them classed `deferred_site_power_cap` are decisions the local
-- path deferred, not solves the service refused. This is the same defect shape rule 6 was written
-- for: `cuopt_invocation_log`'s 20,533 rows against 16 actual NVIDIA calls. The honest predicate
-- was already sitting in the schema unused — `nvidia_cuopt`'s rows carry
-- `endpoint = 'optimize.api.nvidia.com/v1/nvidia/cuopt'` and an `http_status`, and cpsat's carry
-- neither.
--
-- **FIXED, 2026-09-21, by `ottoq-cpsat-propose` v9** (deployed; not a migration — the writer is an
-- edge function). Two changes:
--
--   (a) `ASSIGN_TIMEOUT_MS = 20_000`, matching the `timeout_milliseconds := 20000` this codebase
--       already uses for every other external solver hop in `ottoq_cuopt_refresh`. Chosen to be
--       generous AND instrumented rather than tuned blind: every attempt now records its real
--       wall-clock `latency_ms`, so the next person tightens this from the ledger. It is safe to be
--       generous here because the agent chain is already off-tick by design — G62 measured
--       Nemotron's mean at ~22 s against a 30-second beat, which is exactly why an advisory agent
--       must never be a synchronous dependency of a tick.
--   (b) the function writes its OWN row to `public.ottoq_model_call_ledger` for every attempt,
--       with `endpoint = 'ottoq-intelligence/assign'`, the http status, the measured latency, the
--       proposal count, and a `detail.path` of `edge:ottoq-cpsat-propose`. So
--       **`endpoint IS NOT NULL` is now the predicate that separates PATH B from a forward_lex
--       label**, five outcome classes are distinguished (`answered`,
--       `solved_but_zero_proposals`, `refused`, `errored`, with `detail.timed_out` on the last),
--       and a null receipt is diagnosable from the row alone. The write is wrapped in a
--       swallowing try/catch: an evidence write that can fail the chain it observes is worse
--       than no evidence.
--
-- **`p_source` STAYS `'forward_lex'` AND MUST.** The tempting fix — give PATH B its own source
-- name so the paths separate by `source` — would break the engine. `ottoq_proposer_precedence`
-- ranks `forward_lex` at **rank 0 with `holds_tick = true`**, ahead of `cuopt` (10),
-- `cuopt_fallback` (11) and `llm_advisor` (20); a new unregistered source has no precedence row
-- and would lose CP-SAT's right of first refusal entirely. Same trap CLAUDE.md records for the
-- five `cuopt*` functions that are not cuOpt: the name is load-bearing. The separation belongs in
-- the evidence columns, which is where it now is.

SELECT provider,
       count(*)                                    AS ledger_rows,
       count(http_status)                          AS rows_with_http_status,
       count(endpoint)                             AS rows_with_endpoint,
       count(*) FILTER (WHERE endpoint IS NOT NULL) AS real_calls,
       max(called_at)                              AS last_row
  FROM public.ottoq_model_call_ledger
 GROUP BY 1 ORDER BY 1;

-- ══ 4. WHAT MAY BE SAID TODAY, AND WHAT MAY NOT (REWRITTEN AFTER THE RETRACTION) ══
--
-- SAY: *"the agent layer works and is logged — Nemotron reads the board, reasons in the depot's own
-- vocabulary, and emits one of three bounded objectives. The CP-SAT service is deployed and healthy,
-- answering /health in 14 ms with `cp_sat_forward_lex` in its optimizer list, and the solver itself
-- produces real proposals on this depot's live frame in 24–511 ms. **The hop between them has never
-- once completed:** the service's own access log holds zero `POST /assign` lines. The CP-SAT
-- proposals that reached the shield — 255 on run 71942fbf, 4 enacted — all came from the CI-runner
-- path."*
--
-- DO NOT SAY the chain has run end to end. It has not, and I said it had for about an hour on the
-- strength of an audit label. There is no completed solver hop to point at.
--
-- The claim to earn, and the query that earns it, unchanged: a run on which
-- `ottoq_model_call_ledger` holds `cpsat_service` rows with `endpoint IS NOT NULL`,
-- `outcome = 'answered'`, `proposals_out > 0`, AND matching `ottoq_external_proposals` rows with
-- `submitted_by_role = 'system:service_role'` and
-- `fire->>'submit_path' = 'edge:ottoq-cpsat-propose'`. **Note what the retraction adds: the ledger
-- predicate alone is no longer enough, because `endpoint IS NOT NULL` is written by the caller.
-- The independent witness is the box's own uvicorn access log, over SSM — `POST /assign` lines,
-- counted on the box, by something that is not the thing making the claim.**
--
-- ══ 5. AND THE MEASUREMENT THAT SAYS WHY IT NEVER ARRIVES ═══════════════════
--
-- Run f13fc580 (seed 100021), with v9's instrumentation live, twelve attempts:
--
--   outcome=errored   n=12   latency 20005–20011 ms   http_status: 0 of 12   proposals: 0
--
-- **Twelve attempts clustered inside 6 ms of the 20-second ceiling, none carrying a status.** A
-- solve of variable difficulty does not do that; a connection that never completes does. Combined
-- with §4's zero-`POST /assign` and the box being idle at 0.14% CPU, the request is not reaching
-- the box — so the cause is the address, the security group, or egress, and NOT the service.
-- `OTTOQ_INTEL_URL` is a Supabase secret, not readable from here; the instance was stopped
-- 2026-09-21 02:52 and started again, and it carries **no Elastic IP**, so a public address that
-- changed on restart is the leading candidate and is checked in the next file rather than asserted
-- here.
--
-- DO NOT quote "cpsat_service: N calls" from `ottoq_intelligence_ledger` without the
-- `endpoint IS NOT NULL` predicate. Before v9 that count was 3,124 and the true number of calls
-- was 0; after v9 the two diverge again the moment a forward_lex decision is labelled, because
-- the capture trigger still maps the label to the provider. Both numbers are in the table; only
-- one of them is a call count.

-- OPEN-ITEM: PATH B has never once reached the CP-SAT service -- zero POST /assign lines in the box's own access log -- and the "completed" handoff this file originally cited is retracted above as the skip branch mislabelled by orchestrator-agent's `receipt.engine ?? "cp_sat_forward_lex"` default. Two things are owed: (a) make /assign actually arrive, the leading candidate being a stale OTTOQ_INTEL_URL after the instance restarted without an Elastic IP; (b) delete the lying default so an absent engine can never be reported as the primary engine. Tracked as G108.
