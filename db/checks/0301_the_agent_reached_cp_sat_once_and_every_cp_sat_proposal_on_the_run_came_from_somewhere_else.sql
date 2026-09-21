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

-- ══ 4. WHAT MAY BE SAID TODAY, AND WHAT MAY NOT ════════════════════════════
--
-- SAY: *"the agent chain runs end to end — Nemotron reads the board, chooses one of three bounded
-- objectives, and the CP-SAT service answers — and it has done so once, on run 71942fbf at
-- 05:12:10 UTC. The 175 handoffs before it timed out at a five-second abort, now raised to twenty
-- and instrumented. The CP-SAT proposals that reached the shield on that run — 255, of which 4
-- were enacted — came from the CI-runner path, not from the agent."*
--
-- DO NOT SAY that CP-SAT is in the agent loop in production. One completed handoff that produced
-- no proposals is a wiring proof, not a working loop. The claim to earn next, and the query that
-- earns it, is a run on which `ottoq_model_call_ledger` holds `cpsat_service` rows with
-- `endpoint IS NOT NULL`, `outcome = 'answered'`, `proposals_out > 0`, AND matching
-- `ottoq_external_proposals` rows with `submitted_by_role = 'system:service_role'` and
-- `fire->>'submit_path' = 'edge:ottoq-cpsat-propose'`.
--
-- DO NOT quote "cpsat_service: N calls" from `ottoq_intelligence_ledger` without the
-- `endpoint IS NOT NULL` predicate. Before v9 that count was 3,124 and the true number of calls
-- was 0; after v9 the two diverge again the moment a forward_lex decision is labelled, because
-- the capture trigger still maps the label to the provider. Both numbers are in the table; only
-- one of them is a call count.

-- OPEN-ITEM: PATH B has never produced a proposal. The v9 fix (20 s bound + per-attempt evidence rows) is deployed but unexercised -- it needs a live run where the agent chain fires and cpsat_service rows appear with endpoint IS NOT NULL and proposals_out > 0. Until that run exists, "CP-SAT is in the agent loop" is a wiring claim only. Tracked as G108.
