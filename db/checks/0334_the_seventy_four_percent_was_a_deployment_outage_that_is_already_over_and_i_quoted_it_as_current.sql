-- 0334  **`0332` said, two hours ago and now in CLAUDE.md: "74.3% of what it computes is discarded before
--       it is ever applied, for reasons that are not latency." The percentage is arithmetically right and
--       the sentence is wrong. It is a LIFETIME average over a three-day deployment outage that is
--       already over. TODAY the chain completes 577 of 579 calls and there has not been a single
--       fallback.**
--
--       And the cause was never a mystery: the engine wrote its own diagnosis, in English, into the
--       `fallback_reason` field, 835 times — *"THE RUNNING IMAGE PREDATES CP-SAT. Redeploy the service
--       (ottoq-intelligence deploy workflow)."*
--
--       Measured 2026-09-22 ~13:5x UTC (08:5x CT).
--
-- ══ §1 THE SAME NUMBER, PARTITIONED BY DAY ═══════════════════════════════════
--
--     day        calls  completed  "not configured"  "image predates CP-SAT"  "Signal timed out"
--     ---------  -----  ---------  ----------------  -----------------------  ------------------
--     2026-09-19   577       **0**             577                        0                   0
--     2026-09-20 1,480          3              925                      360                   1
--     2026-09-21 1,044        360                0                      475                 205
--     2026-09-22   579    **577**                0                        0                   0
--
--     lifetime live      3,680 calls / 940 completed  = 25.5%
--     2026-09-22 only      579 calls / 577 completed  = **99.7%**
--
-- The two non-completed calls today are `status='skipped'`, not `fallback`. **The last `fallback` of any
-- kind is 2026-09-21.** A defect that reads as 74.3% of the engine's life is 0% of its last 579 calls.
--
-- ══ §2 WHAT ACTUALLY BROKE, IN THE LEDGER'S OWN WORDS ════════════════════════
--
--     fallback_reason                                                          n      mean latency
--     ----------------------------------------------------------------------  -----  ------------
--     "CP-SAT service is not configured"                                       1,502     17,339 ms
--     "intelligence /assign returned an invalid proposer envelope; /health
--      does not list cp_sat_forward_lex -- THE RUNNING IMAGE PREDATES CP-SAT.
--      Redeploy the service (ottoq-intelligence deploy workflow). /health
--      said: {"ok":true,"service":"ottoq-intelligence",
--             "optimizers":["energy_mpc"]}"                                      835     18,241 ms
--     "Signal timed out."                                                        206     31,160 ms
--     "intelligence /assign returned an invalid proposer envelope"                191     26,534 ms
--     "intelligence /assign returned 500: Internal Server Error"                    1     47,579 ms
--
-- **86% of every fallback is one thing: the CP-SAT service was absent, then deployed from an image that
-- did not contain it.** The agent was never the problem. It computed an objective, handed off, and the
-- solver leg was not there — so the chain fell back to the deterministic path, with `engine: cuopt` on
-- every fallback row.
--
-- **That also explains the latency ordering `0332` §2 called decisive and could not explain.** Fallbacks
-- average 19,308 ms against 22,805 ms for completions — *faster* — because failing on a missing service
-- is quicker than solving. `0332` was right that the clock does not decide the fallback, and wrong to
-- leave the cause open when one more column held it in plain English.
--
-- ══ §3 THE ERROR IS MINE AND IT IS THE SEVENTH OF ITS SHAPE ══════════════════
--
-- `0417` §2 established the rule and I wrote it: **"Never quote an agent latency without its source
-- kind"** — because pooling the dead `backfill` era with the `live` one moved the mean by 2.6 seconds.
-- `0332` obeyed that rule exactly, partitioned on `source_kind`, quoted the live era only… **and then
-- failed to partition the live era on TIME, while a fix landed inside it.** The same defect, one level
-- down, in a check written to correct an instance of it.
--
-- **The general form, which is what to carry forward:** a partition that was sufficient yesterday is not
-- a partition that is sufficient today. `source_kind` separated two eras because someone had already
-- named them. Nobody had named "before and after the CP-SAT deploy", so the pooled figure looked like a
-- property of the engine instead of a property of three days.
--
-- **The test that would have caught it in one query, and costs nothing:** before quoting any rate over a
-- ledger, `GROUP BY date_trunc('day', ...)` and look at the last row. If the last row disagrees with the
-- total, the total is describing history, not the system.
--
-- ══ §4 WHAT REPLACES THE SENTENCE ════════════════════════════════════════════
--
-- **SAY:** *"The agent-to-solver chain completed 577 of its last 579 calls, with no fallback since
-- 2026-09-21. Over its whole live history it completed 940 of 3,680, because the CP-SAT service was
-- unconfigured or running a pre-CP-SAT image from 09-19 to 09-21 — 86% of all fallbacks name exactly
-- that, in the ledger's own words."*
--
-- **DO NOT SAY:** "74.3% of agent calls are discarded", in any tense. As a present-tense claim it is
-- false; as a lifetime figure it describes a fixed outage and invites the reader to think otherwise.
--
-- **And one thing genuinely worth keeping from `0332`:** the tick does not block on the agent, which is
-- independent of all of this and was verified from source (`net.http_post`, no `pg_sleep`, no
-- `_http_response` read, no loop). G62 step 4 stays struck.
--
-- ══ §5 WHAT IS STILL OPEN, NOW THAT THE BIG NUMBER IS GONE ═══════════════════
--
--   1. **206 "Signal timed out" on 09-21** — the only fallback class not explained by the missing image,
--      and the only one whose mean latency (31,160 ms) exceeds a 30-second beat. Small, real, and the
--      one place where latency genuinely does decide a fallback. Worth watching if it returns.
--   2. **Staleness stands unchanged**: advice arrives a mean of 4.20 ticks late and differs from fresh
--      advice 2.14% against a 25.48% floor (`0332` §3). That half of `0417` was never about deployment.
--   3. **Nothing here re-opens G62 step 4.** Async is async.
--
-- **And the ledger earned its keep.** `0340` built `ottoq_model_call_ledger` as `class='evidence'` so a
-- purge could not erase it. Three days of a deployment fault, its exact remedy, and the date it stopped
-- were all recoverable this morning from rows a demo run would otherwise have deleted.

\echo '=== 0334 §1 — the same rate, partitioned by day. The last row is the system; the total is history ==='
SELECT date_trunc('day', called_at) AS day,
       count(*) AS calls,
       count(*) FILTER (WHERE detail->'solver_handoff'->>'status'='completed') AS completed,
       round(100.0*count(*) FILTER (WHERE detail->'solver_handoff'->>'status'='completed')/count(*),1) AS pct_completed,
       count(*) FILTER (WHERE detail->'solver_handoff'->>'fallback_reason' LIKE 'CP-SAT service is not configured%') AS not_configured,
       count(*) FILTER (WHERE detail->'solver_handoff'->>'fallback_reason' LIKE '%RUNNING IMAGE PREDATES CP-SAT%') AS stale_image,
       count(*) FILTER (WHERE detail->'solver_handoff'->>'fallback_reason' LIKE 'Signal timed out%') AS timed_out
  FROM public.ottoq_model_call_ledger
 WHERE provider='nvidia_nemotron' AND source_kind='live' AND detail ? 'solver_handoff'
 GROUP BY 1 ORDER BY 1 DESC;
-- 09-19: 0 of 577 completed. 09-22: 577 of 579. The lifetime 25.5% is the average of those two worlds.

\echo '=== 0334 §2 — the engine wrote its own diagnosis and its own remedy ==='
SELECT detail->'solver_handoff'->>'status' AS status,
       left(detail->'solver_handoff'->>'fallback_reason', 110) AS fallback_reason,
       detail->'solver_handoff'->>'engine' AS engine,
       count(*) AS n, round(avg(latency_ms)) AS mean_latency_ms,
       max(called_at) AS last_seen
  FROM public.ottoq_model_call_ledger
 WHERE provider='nvidia_nemotron' AND source_kind='live' AND detail ? 'solver_handoff'
 GROUP BY 1,2,3 ORDER BY n DESC;
-- 86% of fallbacks are the CP-SAT service being absent or pre-CP-SAT. Note `last_seen` on each: every
-- deployment-caused class stops on 09-21. The fallbacks are also FASTER than the completions, because
-- failing on a missing service is quicker than solving -- which is why 0332 could not read the clock as
-- the cause, and correctly said so.

\echo '=== 0334 §3 — the one-query test that would have caught my own error ==='
WITH d AS (
  SELECT called_at, (detail->'solver_handoff'->>'status'='completed') AS ok
    FROM public.ottoq_model_call_ledger
   WHERE provider='nvidia_nemotron' AND source_kind='live' AND detail ? 'solver_handoff'
)
SELECT round(100.0*count(*) FILTER (WHERE ok)/NULLIF(count(*),0),1) AS pct_completed_LIFETIME,
       round(100.0*count(*) FILTER (WHERE ok AND called_at >= date_trunc('day', (SELECT max(called_at) FROM d)))
             /NULLIF(count(*) FILTER (WHERE called_at >= date_trunc('day', (SELECT max(called_at) FROM d))),0),1)
         AS pct_completed_LAST_DAY,
       (SELECT max(called_at) FROM d WHERE NOT ok) AS last_non_completion,
       (SELECT max(called_at) FROM d)              AS last_call
  FROM d;
-- 25.5% lifetime against 99.7% on the last day. When those two disagree, the lifetime figure is
-- describing history and must not be spoken in the present tense.
