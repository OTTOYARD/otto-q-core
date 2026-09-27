-- 0332  **CLAUDE.md says "the tick blocks a mean of 19.7 seconds of its 30-second beat on advice."
--       IT DOES NOT BLOCK AT ALL.** `ottoq_sim_decide_and_dispatch` fires the agent with
--       `net.http_post(..., timeout_milliseconds := 20000)` — pg_net is fire-and-forget — and the
--       function contains **no `pg_sleep`, no read of `net._http_response`, and no loop**. The tick
--       enqueues the call and returns.
--
--       So G62 step 4, "decouple the agent from the tick beat", is **already done and was never
--       undone**. What the measurement actually shows is a different and larger defect: **2,735 of
--       3,680 live agent calls (74.3%) end in `handoff_status='fallback'`** — the kernel computed the
--       advice and then used its own answer instead — **and it is not because the agent was slow.**
--
--       Found while opening G62 step 4 to build it. Measured 2026-09-22 ~13:4x UTC (08:4x CT).
--
-- ══ §1 THE SENTENCE THAT IS WRONG, AND WHY IT WAS EASY TO BELIEVE ═════════════
--
-- CLAUDE.md 2.5 and `db/migrations/0417` both carry: *"the tick blocks a mean of 19.7 seconds of its
-- 30-second beat on advice a mean of 4.7 ticks stale, which differs from fresh advice 0.16% of the time
-- against a 33.07% floor — so the cost is the wait, not the answer."*
--
-- **The second half is sound and stands.** Staleness is measured, it is small, and the conclusion that
-- lateness destroys almost no signal is unchanged (§3 re-derives it on more data).
--
-- **The first half was never measured — it was inferred from a latency column.** `ottoq_model_call_ledger`
-- records how long the AGENT took. That is the agent's wall time inside its own edge function, and it
-- says nothing about whether anything waited for it. I had the agent's duration and the tick's period and
-- read a dependency into the pair.
--
-- The call site, from source, comment-stripped:
--
--     IF ... ottoq_policy_get(p_sim_run_id,'orchestrator_agent_enabled',1) > 0
--         AND ottoq_policy_get(p_sim_run_id,'agent_solver_chain_enabled',0) < 1
--         AND ( (COALESCE(v_run.tick_count,0) % 3) = 0 OR ottoq_orchestrator_trigger(v_run.depot_id) ) THEN
--       BEGIN
--         SELECT decrypted_secret INTO v_k FROM vault.decrypted_secrets WHERE name='ottoq_anon_key' LIMIT 1;
--         IF v_k IS NOT NULL THEN
--           PERFORM net.http_post(url := '.../functions/v1/ottoq-orchestrator-agent',
--                                 ..., timeout_milliseconds := 20000);
--         END IF;
--       EXCEPTION WHEN OTHERS THEN NULL;
--       END;
--     END IF;
--
-- `net.http_post` enqueues a request for pg_net's background worker and returns a request id. The
-- `timeout_milliseconds` bounds **the worker's** request, not the caller. `ottoq_sim_decide_and_dispatch`
-- is 6,506 characters and contains **no `pg_sleep`, no `_http_response`, no `LOOP`** — §5 asserts all
-- three. There is no wait to remove.
--
-- **Two things follow that are worth more than the retraction.** The agent is fired on **every third
-- tick** (`tick_count % 3 = 0`) or on `ottoq_orchestrator_trigger`, which is most of the mean 4.20-tick
-- staleness on its own. And the whole fire sits inside `EXCEPTION WHEN OTHERS THEN NULL` — correct, since
-- an advisory call must never unwind a tick, but it also means a permanently broken agent fires, fails,
-- and reports nothing, forever.
--
-- ══ §2 THE REAL DEFECT: THREE OF FOUR CALLS ARE COMPUTED AND DISCARDED ════════
--
-- `public.ottoq_agent_advice_staleness`, live era only (never pool the backfill era — `0417` §2):
--
--     agent_calls              3,680
--     applied                    936   (25.4%)
--     fell_back                2,735   **(74.3%)**
--     skipped                      5
--     classes_sum_to_calls      true
--
-- **And it is NOT a latency problem, which is the measurement that matters here.** Grouped on the
-- handoff status in `ottoq_model_call_ledger`:
--
--     handoff_status   n       mean latency
--     --------------  -----   ------------
--     fallback        2,735     19,308 ms
--     completed         936     22,805 ms
--     skipped             5     49,916 ms
--
-- **The discarded calls are on average 3.5 seconds FASTER than the applied ones.** If the kernel were
-- falling back because the agent missed a deadline, that ordering would be reversed. Whatever decides
-- `fallback` is not the clock.
--
-- Every `completed` row carries a `solver_handoff.receipt.tick_seq`; **no `fallback` row carries one**
-- (2,735 of 2,735 without). So the fallback is decided before any receipt exists — upstream of the apply,
-- not at it.
--
-- **THIS IS THE OPEN QUESTION AND IT IS NOT ANSWERED HERE.** The candidate the call site points at is
-- `agent_solver_chain_enabled`: `ottoq_sim_decide_and_dispatch` fires the agent **only when that dial is
-- BELOW 1**, and `ottoq_agent_solver_refresh` refuses the solver chain **when it is below 1** — so the
-- configuration that lets the agent run is the same one that declines to chain its advice into a solver.
-- That reads like two halves of a switch that were never reconciled, but it is a reading of two source
-- fragments and not a measurement, so it is written here as the next thing to check, not as the cause.
--
-- ══ §3 THE HALF OF THE OLD SENTENCE THAT SURVIVES, RE-DERIVED ═════════════════
--
--     mean staleness            4.20 ticks   (was 4.70; more live data)
--     p50 / p95 / max            2 / 15 / 59
--     stale over one tick          581 of 936 applied
--     staleness changed answer      20 of 934 comparable = **2.14%**
--     modal-constant floor                              **25.48%**
--
-- So stale advice differs from fresh advice **2.14%** of the time against a **25.48%** floor. The earlier
-- figures (0.16% against 33.07%) were a smaller sample; the conclusion is the same and stronger for
-- having moved: **lateness destroys almost none of the signal.** `0323` §5's proposed validity window,
-- which would refuse stale advice, would still discard correct advice in roughly 46 of 47 cases.
--
-- **THE CORRECTED SENTENCE, which is the only one to quote:** *"the agent is fired asynchronously every
-- third tick and never blocks it; its advice arrives a mean of 4.2 ticks late and differs from fresh
-- advice 2.14% of the time against a 25.48% floor — and 74.3% of what it computes is discarded before
-- it is ever applied, for reasons that are not latency."*
--
-- ══ §4 WHAT THIS MEANS FOR G62 STEP 4 ════════════════════════════════════════
--
-- **Step 4 as written — "decouple the beat" — is a no-op and must be struck**, not scheduled. The thing
-- it would have built already exists.
--
-- The work that is actually there, in order of measured size:
--   1. **The 74.3%.** Three of four Nemotron calls are paid for and thrown away. That dwarfs anything
--      staleness or latency could recover, and §2 names the one-query check that starts it.
--   2. **The every-third-tick fire.** If the 74.3% is fixed, cadence becomes the next term in staleness,
--      and it is one modulus.
--   3. **`EXCEPTION WHEN OTHERS THEN NULL` around the fire.** Correct as protection, silent as
--      telemetry. A counter on that handler would make "the agent is down" visible.
--   4. **Not a validity window.** §3 measured it would cost more than it saves.
--
-- ══ §5 AND THE GENERAL LESSON, WHICH IS THE SIXTH INSTANCE OF ITS SHAPE ══════
--
-- `0329` (a hash over a minted id), `0413` (a rate over scheduler ticks), `0326` §1 (a calendar gate
-- against the wrong clock), `0331` (an actor inferred from whether a run is live) — and now a *wait*
-- inferred from a *duration*. Each time, a real measurement was read as answering a question it was not
-- about. **`latency_ms` answers "how long did the agent take", never "what waited for it."** The second
-- question is answered by reading the caller, and the caller is one `SELECT prosrc` away.

\echo '=== 0332 §1 — the tick does not wait: no sleep, no response poll, no loop ==='
WITH s AS (
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_decide_and_dispatch'
)
SELECT length(src)                              AS chars,
       (src ILIKE '%net.http_post%')            AS fires_the_agent_async,
       (src ILIKE '%pg_sleep%')                 AS waits_with_pg_sleep,
       (src ILIKE '%\_http\_response%')         AS polls_the_response_table,
       (src ~* '\mLOOP\M')                      AS has_any_loop,
       (src ILIKE '%tick_count,0) %% 3%')       AS fires_every_third_tick,
       (src ILIKE '%EXCEPTION WHEN OTHERS THEN NULL%') AS fire_is_silently_swallowed
  FROM s;
-- 6,506 / true / FALSE / FALSE / FALSE / true / true. Comment-stripped, because prosrc carries comments
-- and this function's own header would otherwise match several of these probes.

\echo '=== 0332 §2 — 74.3% of live agent calls are discarded, and the discarded ones are FASTER ==='
SELECT detail->'solver_handoff'->>'status'                  AS handoff_status,
       (detail->'solver_handoff'->'receipt' ? 'tick_seq')   AS carries_a_receipt_tick,
       count(*)                                             AS n,
       round(100.0*count(*) / sum(count(*)) OVER (), 1)     AS pct,
       round(avg(latency_ms))                               AS mean_latency_ms
  FROM public.ottoq_model_call_ledger
 WHERE provider='nvidia_nemotron' AND source_kind='live'
 GROUP BY 1,2 ORDER BY n DESC;
-- fallback 2,735 @ 19,308 ms with NO receipt tick on any row; completed 936 @ 22,805 ms with one on all
-- of them. The fallbacks are 3.5 s faster, so the clock is not what decides them.

\echo '=== 0332 §3 — staleness re-derived on the live era. Never pool the backfill era (0417 §2) ==='
SELECT source_kind, agent_calls, applied, fell_back, skipped, classes_sum_to_calls,
       mean_staleness_ticks, p50_staleness_ticks, p95_staleness_ticks, max_staleness_ticks,
       comparable, staleness_changed_answer, pct_staleness_changed_answer,
       pct_modal_constant_would_be_wrong,
       mean_latency_ms, p95_latency_ms, calls_over_thirty_seconds
  FROM public.ottoq_agent_advice_staleness ORDER BY source_kind;
-- live: 2.14% changed against a 25.48% floor. The backfill row's mean_latency_ms of 30,394 is the figure
-- CLAUDE.md quoted as current; it is a dead era and its `applied` is 0, so it can say nothing about
-- staleness at all.

\echo '=== 0332 §2b — the dial the call site points at, both halves, read together ==='
-- WHITESPACE-TOLERANT ON PURPOSE. The first draft of this query used
--   ILIKE '%agent_solver_chain_enabled%,0) < 1%'
-- and returned FALSE for ottoq_sim_decide_and_dispatch and TRUE for ottoq_agent_solver_refresh -- not
-- because they differ, but because one writes `'agent_solver_chain_enabled', 0)` with a space after the
-- comma and the other does not. A source assertion that a formatting difference can flip is not an
-- assertion. Same family as the comment-stripping trap, one level down.
WITH s AS (
  SELECT p.proname,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('ottoq_sim_decide_and_dispatch','ottoq_agent_solver_refresh')
)
SELECT proname,
       (src ~ 'agent_solver_chain_enabled''\s*,\s*0\s*\)\s*<\s*1') AS gates_on_the_dial_being_below_1
  FROM s ORDER BY proname;
-- Both true: the tick fires the agent ONLY when the dial is below 1, and the solver-chain refresh
-- REFUSES when the dial is below 1. That is a READING of two fragments, not a measurement of the
-- fallback. It is the next thing to check, and §2 says so rather than calling it the cause.
