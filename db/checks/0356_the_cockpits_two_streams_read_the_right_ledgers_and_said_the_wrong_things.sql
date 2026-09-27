-- 0356  **The cockpit's Intelligence and Decisions streams read the right ledgers and said the wrong things.**
--
--       Chase, 2026-09-23: "make sure that the data streams are first consistent and legible, and actually accurate."
--       This file holds the queries behind migrations 0451–0457 and the numbers they returned. FINDINGS G189 (the
--       streams) and G190 (the evidence ledger).
--
--       Measured on run `736406cf-05ee-448d-b529-0e04b074eddd` (busy_day, twin depot `11111111-…`, agent v21,
--       governor 900 sim-minutes) between 05:30 and 06:45 UTC on 2026-09-23 (12:30–1:45 AM CT), while it ran.
--
--       THAT RUN NO LONGER EXISTS. It ended at 07:08 UTC on the governor ceiling (1,910 ticks, check 0355 §1), and
--       run `689095e2` purged its engine-class rows when it started at 19:12 UTC on 2026-09-25. So §1, §3 and §4
--       cannot be re-run against it. §2 and §5 still can: they read `class='evidence'` ledgers, which the purge
--       does not touch. Every query below takes the run as a psql variable, so the whole file re-runs on any live
--       run:
--
--           \set run '<sim_run_id>'
--
--       What each section answers:
--         §1  the Intelligence panel's layers (0451)       §2  agent calls the evidence ledger never saw (0452)
--         §3  the Decisions stream's restatement (0452–0454, 0457)
--         §4  the stream printed an engine where the verdict belonged (0455)
--         §5  abstentions counted as refused proposals (0456)
--         §6  how to read the streams now

\set run '736406cf-05ee-448d-b529-0e04b074eddd'

-- ══ §1 THE INTELLIGENCE PANEL (0451) ═════════════════════════════════════════════════════════════════════════════

\echo '=== 0356 §1a — L1: a failed verdict is not a refusal ==='
SELECT effect, enforcement, count(*) AS n
  FROM public.ottoq_rule_evaluation_effect
 WHERE sim_run_id = :'run'
 GROUP BY 1, 2 ORDER BY n DESC;
-- The panel's `blocked` was count(*) FILTER (WHERE passed IS FALSE): every failed evaluation, whatever the rule's
-- enforcement and whatever its caller did with the verdict. A shadow rule failing thousands of times a run
-- (SM.001) headlined a shield that refused nothing. Since 0451 the panel's `blocked` is `effect = 'refused'`, and
-- `failed`, `recorded_only` and `advisory_failed` stand beside it.

\echo '=== 0356 §1b — L3: one run, not every run ==='
SELECT provider, role, count(*) AS calls,
       count(*) FILTER (WHERE http_status BETWEEN 200 AND 299) AS reached_2xx,
       sum(COALESCE(proposals_out, 0)) AS proposals
  FROM public.ottoq_model_call_ledger
 WHERE sim_run_id = :'run' AND role = 'proposer'
 GROUP BY 1, 2 ORDER BY 1;
-- At tick ~20 the card showed cuOpt 1,162 calls / 5,068 proposals and CP-SAT 2,052 / 537 — the LIFETIME view
-- `ottoq_intelligence_ledger`, across every run and depot — while this run had made no model call of any kind.
-- It also printed "Nemotron 0 calls": the view counts agent passes as `captured_decisions`, not `calls`.

\echo '=== 0356 §1c — L2: the cost of a late agent is staleness, not a held tick ==='
SELECT count(*) AS applied, round(avg(staleness_ticks), 2) AS mean_ticks_late,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY staleness_ticks) AS p95,
       count(*) FILTER (WHERE staleness_changed_the_answer) AS changed_the_answer
  FROM public.ottoq_agent_advice_provenance
 WHERE sim_run_id = :'run' AND applied_tick IS NOT NULL;
-- `over_one_tick` and the `degraded_latency` status rested on the claim that a slow agent holds the tick, which
-- 0332 retracted (pg_net fire-and-forget). What the panel now shows is how late applied advice is, and
-- `model_unavailable` when the latest pass ran without its model (G188).

-- ══ §2 THE EVIDENCE LEDGER NEVER SAW A FAILED AGENT CALL (0452, G190) ════════════════════════════════════════════

\echo '=== 0356 §2 — agent passes by outcome, source kind and cause ==='
SELECT outcome, source_kind, left(COALESCE(detail->>'model_error', '-'), 40) AS cause, count(*) AS n
  FROM public.ottoq_model_call_ledger
 WHERE sim_run_id = :'run' AND provider = 'nvidia_nemotron'
 GROUP BY 1, 2, 3 ORDER BY 1, n DESC;
-- Before 0452 the capture trigger fired only for `l2_engine IN ('nemotron','forward_lex','llm_advisor')`, and a
-- pass whose model call failed carries `source = 'deterministic_fallback'`, so it was never captured. At 05:55 UTC
-- the ledger's last `nvidia_nemotron` row was 04:12:10 UTC, while the agent had made 33 passes since 05:30, each
-- timing out at 75 s.
--
-- RE-RUN 2026-09-26 on the whole of 736406cf (the ledger survived the purge):
--     enacted   live       -               120
--     fallback  live       HTTP 429          ┐
--     fallback  live       model timeout     │  91 live
--     fallback  live       HTTP 503 / 500    ┘
--     fallback  backfill   (the passes before 0452 was applied)   73
--   So 164 of 284 passes (57.7%) ran without their model. By cause across both kinds: HTTP 429 rate limiting 89,
--   the 75-second deadline 40, HTTP 404 23 (all inside 06:03–06:07 UTC), HTTP 503 10, HTTP 500 2.
--
-- CAVEAT ON THE 73 BACKFILLED ROWS, found 2026-09-26: 0452's backfill stamped `called_at` with the migration's own
-- now(), so all 73 read 2026-09-23 06:03:45.635228 UTC. Their `sim_clock` and `tick_seq` are the calls' own. The
-- 0340 backfill did not do this (514 distinct `called_at` over 515 cuOpt rows). The ledger is append-only, so the
-- rows stay as written: time-partition backfill rows on `sim_clock`, never on `called_at`.

-- ══ §3 THE DECISIONS STREAM WAS 97% RESTATEMENT (0452, 0453, 0454, 0457; G189) ═══════════════════════════════════

\echo '=== 0356 §3a — rows against verdict changes, per action ==='
WITH d AS (
  SELECT COALESCE(resolved_action_context, action_context) AS act, entity_id, tick_seq, decision_seq,
         concat_ws('|', outcome_status,
                   COALESCE(enacted_action->>'verb',     proposed_action->>'verb'),
                   COALESCE(enacted_action->>'reason',   proposed_action->>'reason'),
                   COALESCE(enacted_action->>'stall_id', proposed_action->>'stall_id')) AS sig
    FROM public.ottoq_decisions WHERE sim_run_id = :'run')
SELECT act, count(*) AS rows,
       count(*) FILTER (WHERE sig IS DISTINCT FROM prev) AS changes,
       round(100.0 * count(*) FILTER (WHERE sig IS NOT DISTINCT FROM prev) / count(*), 1) AS pct_restated
  FROM (SELECT d.*, lag(sig) OVER (PARTITION BY act, entity_id ORDER BY tick_seq, decision_seq) AS prev FROM d) x
 GROUP BY 1 ORDER BY rows DESC;
-- Over the run's first 311 decided ticks:
--     task_start          12,197 rows    131 changes   98.9% restated   39.2 rows / tick
--     stall_assignment     4,557 rows    363 changes   92.0%            14.7 rows / tick
--     bay_reconcile          441 rows     16 changes   96.4%
--     bess_dispatch          311 rows     13 changes   95.8%
--     orchestrator_agent      28 rows    every one its own decision
-- The cockpit read the newest 200 rows every 4 s. At ~58 rows a tick that page was ~3.4 ticks deep and the agent
-- fires at most every third tick, so the newest 500 rows held ZERO agent decisions.
-- REPRODUCED 2026-09-26 on `689095e2` (busy_day, 506 ticks, 2026-09-25, the one busy_day run that survives):
-- task_start 10,102 rows / 94 changes (99.1% restated), stall_assignment 1,766 / 252 (85.7%), bay_reconcile
-- 97.3%, bess_dispatch 98.0%. The defect is the decide path's shape, not one run's.

\echo '=== 0356 §3b — how far apart identical verdicts recur, in each action''s own decide ticks ==='
WITH d AS (
  SELECT COALESCE(resolved_action_context, action_context) AS act, entity_id, tick_seq,
         dense_rank() OVER (PARTITION BY COALESCE(resolved_action_context, action_context) ORDER BY tick_seq) AS n,
         concat_ws('|', outcome_status, COALESCE(enacted_action->>'verb', proposed_action->>'verb'),
                   COALESCE(enacted_action->>'reason', proposed_action->>'reason')) AS sig
    FROM public.ottoq_decisions WHERE sim_run_id = :'run'),
g AS (SELECT act, n - lag(n) OVER (PARTITION BY act, entity_id, sig ORDER BY n) AS gap FROM d)
SELECT act, percentile_cont(0.5) WITHIN GROUP (ORDER BY gap) AS median_gap,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY gap) AS p95_gap
  FROM g WHERE gap IS NOT NULL GROUP BY 1 ORDER BY 1;
-- task_start 1 / 1 · stall_assignment 2 / 13 · redeployment 37 / 60 · itinerary_amended 19 / 20.
-- (689095e2, a shorter run: stall_assignment 3 / 18, itinerary_amended 4 / 8.25 — the same shape.)
-- No single gap threshold separates "the same wait" from "a second deployment" for every action, which is why
-- 0454 splits EVENTS (own row every time) from STATES (one row until the verdict changes, a new row after 40 of
-- the action's decide ticks of silence), and 0457 decides event-ness per decision: an enacted deploy is an event,
-- a held deploy ("Deploy held · SLA.004", printed three times for the same two vehicles) is a state.

\echo '=== 0356 §3c — the changes-only stream as the cockpit calls it ==='
SELECT action, count(*) AS rows, count(*) FILTER (WHERE standing) AS standing,
       max(held_ticks) AS longest_held_ticks
  FROM public.ottoq_activity_feed(:'run'::uuid, 500, NULL, true, 240)
 GROUP BY 1 ORDER BY rows DESC;
-- On 736406cf after 0457: agent passes 49 in the window, against 0 in the newest 500 raw rows before 0452.
-- On 689095e2 (2026-09-26): stall_assignment 113 rows (52 standing), agent 40, redeployment 19, itinerary 16,
-- triage 10, gate intake 10, task_start 7, bay_reconcile 5 — 220 rows for 240 ticks against ~12,900 raw decisions.

-- ══ §4 THE ENGINE'S NAME WHERE THE VERDICT BELONGED (0455) ═══════════════════════════════════════════════════════

\echo '=== 0356 §4 — decide-path verdicts the stream could not show ==='
SELECT COALESCE(resolved_action_context, action_context) AS act,
       COALESCE(enacted_action->>'reason', proposed_action->>'reason') AS verdict_reason, count(*) AS n
  FROM public.ottoq_decisions
 WHERE sim_run_id = :'run' AND COALESCE(resolved_action_context, action_context) IN ('stall_assignment','bess_dispatch')
 GROUP BY 1, 2 ORDER BY n DESC LIMIT 10;
-- 4,358 `stall_assignment` rows whose verdict was `no_compatible_available_stall` reached the cockpit as reason
-- "deterministic_v1", and 284 battery rows whose verdict was `no_active_energy_plan_or_standby` likewise: the feed
-- returned the rationale object but not the verb and reason that sit beside it.

-- ══ §5 ABSTENTIONS COUNTED AS REFUSED PROPOSALS (0456) ════════════════════════════════════════════════════════════

\echo '=== 0356 §5 — proposer rows: offers against abstentions, from the evidence ledger ==='
SELECT source, abstained, status, count(*) AS n
  FROM public.ottoq_proposal_disposition_ledger
 WHERE sim_run_id = :'run'
 GROUP BY 1, 2, 3 ORDER BY 1, 2, n DESC;
-- Mid-run the L4 card read "377 proposals · 0 enacted · 182 refused · 48% refusal · refusing_all". From the same
-- rows: 367 abstentions ("outside this tick's batch of 8 most urgent", "beyond this tick's 30-min window") and 10
-- offers — 3 refused (stall occupied 2, reserved 1) and 7 superseded by the decide path.
--
-- RE-RUN 2026-09-26 on the whole run (evidence ledger, survives the purge):
--     forward_lex         abstained  superseded 365 · refused 305           = 670 abstentions
--     forward_lex         offered    refused 16 · superseded 14 · enacted 1 =  31 offers
--     greedy_constrained  offered    enacted 44 · refused 90 · superseded 27 = 161 offers
-- CP-SAT (`forward_lex`, rank 0) spoke 31 times in 1,910 ticks and was enacted once. G167's batch-of-8 and 30-minute
-- window explain the abstentions; `cpsat_service` itself answered 11 calls with 17 proposals and returned
-- `solved_but_zero_proposals` 270 times (check 0355 §3).

-- ══ §6 HOW TO READ THE STREAMS NOW ═══════════════════════════════════════════════════════════════════════════════
--
--   Decisions: `ottoq_activity_feed(run, 300, NULL, true, 240)` — one row per change of verdict, `held_ticks` and
--     `standing` for how long it stood. Never count its rows as decisions: count `ottoq_decisions`.
--   Intelligence: `ottoq_intelligence_stack(run, …)` — L1 `blocked` means refused; L3 is this run's proposer calls;
--     L4 counts offers and reports abstentions separately.
--   Agent reliability: `ottoq_model_call_ledger` WHERE provider = 'nvidia_nemotron', by outcome and
--     `detail->>'model_error'`, partitioned by day per CLAUDE.md's standing test — and on `sim_clock` for backfill rows.
