-- 0305  RUN f13fc580 CLOSED, AND IT SETTLES THREE THINGS AT ONCE: the clock fix holds on a SECOND
--       seed, the skip branch records a decline as a decline, and **CP-SAT drove five real stall
--       assignments through the agent chain, three of which ran to completion.**
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- Run f13fc580 (seed 100021, busy_day, otto_q, robotaxi) completed 2026-09-21 08:18:49 UTC at tick
-- **1136**, sim_elapsed **09:10:38** — the same governor threshold as 71942fbf's 09:10:36, which is
-- worth noting as a consistency check on `ottoq_run_governor_auto_stop` rather than a coincidence.
-- Captured within a minute of completion; the KPI inputs are `class='engine'`.
--
-- ══ 1. THE CLOCK FIX HOLDS ON A SECOND SEED, INDEPENDENTLY ══════════════════
--
-- `0300` closed G107 on seed 100020. This is seed **100021**, a different world:
--
--   audit.hours_clipped_to_window          **+12.04**   (was -227.36 / -237.29 pre-fix)
--   audit.horizon_source                   run_horizon
--   audit.dispatches_counted               138
--   ottoq_assert_dispatch_time_coherence   **"coherent: all 138 dispatches return after they
--                                           were dispatched"** — 0 inverted, 0 negative durations
--   provenance.not_reproducible            [] (all eight metrics reproducible from the run ID)
--   payload.boot_prime.start_hour_cst      19, matching sim_clock_start 19:45 CT
--
-- Two seeds, two positive clips, two coherent dispatch sets. `0396` is not a one-seed fix.
--
-- ══ 2. THE FIVE KPIs ════════════════════════════════════════════════════════
--
--   asset_hours_available_per_day           2026-09-21: **70.09**
--   service_point_turns_per_point_per_day   2026-09-21: **3.35**
--   peak_site_kw                            **1393.6**   (peak_site_kw_demand 1393.7)
--   touch_events_per_turn                   **0.163**
--   p95_time_to_service_min                 **115.4**    (p50 **1.1**)
--   returns_unserved                        **12**
--
--   run_key.config_hash  489f1649addc928b0b4ce608e2a6d5f9
--   run_key.engine_hash  34fca07dcc1670ce08555572b60e801b
--
-- **NOT a controlled comparison against `0300`'s seed-100020 figures, and the reason is now three
-- deep:** different seed, different `config_hash`, and a different `engine_hash` again (0398 applied
-- between them). Recorded as a trend log. The 98x p50-to-p95 spread `0300` §4 flagged persists here
-- — 1.1 against 115.4 — which is the staging-and-charging capacity question `0303` measured directly,
-- not a clock artefact.

SELECT jsonb_pretty(public.ottoq_kpi_five('f13fc580-ff1a-4da6-87ee-dbba7c42540e')) AS kpi_five;
SELECT public.ottoq_assert_dispatch_time_coherence('f13fc580-ff1a-4da6-87ee-dbba7c42540e') AS coherence;

-- ══ 3. THE SKIP BRANCH, VERIFIED — A DECLINE IS NOW RECORDED AS A DECLINE ═══
--
-- `0304` §8 deployed orchestrator v29 and said plainly that the skip branch itself was unverified,
-- because it fires only when the agent chain ticks against a run that is no longer `running` —
-- which is exactly the condition that produced the false "completed" at 05:12:10 and cost an hour.
-- The run ended at 08:18:49. The next agent tick:
--
--   08:18:33  status **skipped** · engine **(null)** · solver_ran **false**
--             skipped "run is not active" · verb **agent_batch:2** · outcome_status enacted
--   08:17:21  status completed · engine cp_sat_forward_lex · solver_ran true · verb analyze_and_solve
--
-- **Under the old code that 08:18:33 row would have read `completed` / `cp_sat_forward_lex` /
-- `analyze_and_solve` / `receipt:null`** — the 05:12:10 row, reproduced. It now names the decline,
-- names no engine, says the solver did not run, and takes its verb from what was ACTUALLY applied
-- (`agent_batch:2` — two policy dials the agent set). `outcome_status='enacted'` is correct on that
-- row precisely because those two dials were applied; the verb no longer borrows credit from a
-- solver that never ran.
--
-- So the whole of `0301`'s defect is now closed, and closed on the exact condition that created it.

SELECT to_char(created_at,'HH24:MI:SS')                                  AS at_utc,
       enacted_action->'solver_handoff'->>'status'                        AS handoff_status,
       coalesce(enacted_action->'solver_handoff'->>'engine','(null)')     AS engine,
       coalesce(enacted_action->'solver_handoff'->>'solver_ran','(null)') AS solver_ran,
       coalesce(enacted_action->'solver_handoff'->>'skipped','-')         AS skipped,
       enacted_action->>'verb'                                           AS verb,
       outcome_status
  FROM public.ottoq_decisions
 WHERE resolved_action_context = 'orchestrator_agent'
 ORDER BY created_at DESC LIMIT 8;

-- ══ 4. WHAT THE AGENT PATH DID OVER THE WHOLE RUN ═══════════════════════════
--
--   hops (ledger rows with endpoint IS NOT NULL)      **131**
--   reached the service (http_status 200)             **87**
--   answered with rows                                **6**
--   proposals_out                                     **8**
--   latency on successful hops                        14 ms min · **28 ms mean** · 187 ms max
--
-- The 44 hops that did not reach it are the pre-fix window, all `http_status NULL` at ~20,006 ms.
-- After the address moved into the database, every hop reached the service.
--
--   DISPOSITION of what it submitted:
--     refused    · proposer_abstained                **210**  <- CP-SAT's OWN abstentions, bookkeeping
--     superseded · entity_decided_by_other_proposal    57     <- precedence; another proposer first
--     superseded · newer_proposal_same_entity          22     <- its own later plan replaced its earlier
--     **enacted  · enacted_by_kernel                    5**
--     refused    · stall_reserved                       3     <- G109's conflicting pairs, resolved
--
-- **And five bookings in the world carry `source='forward_lex'`:**
--
--   NASH-DCFC-STALL-02 · vehicle fd6ec8c7 · charge_dcfc · **done**
--   NASH-DCFC-STALL-03 · vehicle b97789b5 · charge_dcfc · **done**
--   NASH-DCFC-STALL-04 · vehicle 54aeb4ca · charge_dcfc · **done**
--   NASH-DCFC-STALL-07 · vehicle a1111111 · charge_dcfc · released
--   NASH-L2-STALL-08   · vehicle 616a06de · charge_l2   · superseded
--
-- **Three of the five ran to `done`** — charged to completion on a plan the agent chain produced.
-- Note `54aeb4ca`: it is the vehicle whose competing proposal for stall 609910b1 was refused
-- `stall_reserved` at tick 726 (`0304` §7), and it was assigned NASH-DCFC-STALL-04 later in the run
-- and charged there. The kernel refusing a conflicting proposal did not cost that vehicle its
-- service; it cost it that stall, that tick.
--
-- ══ 5. THE SENTENCE THIS RUN EARNS ══════════════════════════════════════════
--
-- *"On run f13fc580 the agent chain ran end to end for a full 9-hour sim day: 131 handoffs, 87
-- reaching the CP-SAT service at a mean 28 ms, 6 answers, 8 proposals, 5 enacted by the
-- deterministic kernel, and 3 of those charged to completion. Every enactment was gated by the L1
-- shield. The proposer wrote no assignment; the kernel disposed every one."*
--
-- **Still not claimed, and not claimable from this run:** that any of it improved a KPI. That needs
-- a controlled pair on one `engine_hash` with the agent chain as the only variable, which is
-- `0145`/`0146`'s open A/B gap. Everything above is a capability and reliability result, not an
-- outcome result, and the two must not be conflated.

SELECT count(*)                                                        AS hops,
       count(*) FILTER (WHERE http_status = 200)                        AS reached_service,
       count(*) FILTER (WHERE outcome = 'answered')                     AS answered,
       coalesce(sum(proposals_out), 0)                                  AS proposals,
       min(latency_ms) FILTER (WHERE http_status = 200)                 AS min_ms,
       round(avg(latency_ms) FILTER (WHERE http_status = 200))          AS avg_ms,
       max(latency_ms) FILTER (WHERE http_status = 200)                 AS max_ms
  FROM public.ottoq_model_call_ledger
 WHERE provider = 'cpsat_service' AND endpoint IS NOT NULL;

SELECT s.stall_code, left(b.vehicle_id::text,8) AS vehicle, b.purpose, b.state, b.source
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.source = 'forward_lex' ORDER BY b.booked_at DESC;
