-- 0322  **Chase asked what cuOpt's true role and edge actually are. Measured, and the answer is not
--       the one either the brief or `D001` predicts: cuOpt was formally RETIRED from the decide path
--       on 2026-09-03 and is live today as the CP-SAT chain's declared fallback engine — and on
--       every rate that can be measured it currently BEATS the CP-SAT service that was supposed to
--       replace it.**
--
--       No migration here. This is the diagnosis the decision needs, and one number in it
--       (`0250`'s "1 enacted / 7 refused / 11 superseded") is retracted as a single-run figure.
--
--       **Measured 2026-09-22 04:40:02 UTC (2026-09-21 11:40 PM CT), AND A RUN WAS LIVE WHILE
--       MEASURING** — `greedy_constrained` went from 16,034 to 16,246 proposals between two queries
--       four minutes apart. Every figure below is from ONE atomic snapshot at that moment. Cite the
--       moment, never the table.
--
-- ══ §1 THE PREDICATE THAT DECIDES EVERYTHING BELOW: `endpoint IS NOT NULL` ═════
--
-- `0301` established that `ottoq_model_call_ledger` holds two different kinds of row under one
-- provider name, because `ottoq_capture_decision_model_call` maps a decision by its engine —
--
--     WHEN 'forward_lex' THEN 'cpsat_service'
--
-- — so every local decision labelled `forward_lex` becomes a `cpsat_service` row whether or not
-- anything was called. `0301` fixed the WRITE side (the edge function now stamps `endpoint`), and
-- **the READ side was never fixed: `ottoq_intelligence_ledger.calls` still counts both.** Measured:
--
--     provider           ledger rows   endpoint NOT NULL   % that are NOT calls
--     ----------------   -----------   -----------------   --------------------
--     nvidia_nemotron          4,248                   0                 100.0%
--     cpsat_service            3,638                 487                  86.6%
--     nvidia_cuopt             1,159               1,159                   0.0%
--
-- **cuOpt is the only provider in the ledger whose call count is a call count.** And the
-- contamination is not cosmetic — it moves latency in the flattering direction:
-- `cpsat_service` reports **251 ms** average across all rows and **1,847 ms** across its real calls,
-- a 7.4x understatement, because 3,151 sub-25 ms decision rows are averaged in with the network hops.
--
-- **WHAT IS NOT CLAIMED, and the distinction matters for G62.** Zero Nemotron rows carrying an
-- endpoint does NOT mean Nemotron never called NVIDIA. It means no Nemotron row records one, so the
-- predicate that separates calls from captured decisions classifies none of them as calls, and its
-- 22,596 ms average is DECISION latency, not an instrumented round trip. For G62's purpose that is
-- still the right measurement — a decision that took 22.6 s against a 30 s tick is the finding
-- whether or not the fetch was timed — but "4,248 Nemotron CALLS" is not a sentence this ledger
-- supports.
--
-- ══ §2 THE HONEST PER-PROVIDER NUMBERS ════════════════════════════════════════
--
--     provider         real calls   answered   avg ms   last real call
--     --------------   ----------   --------   ------   --------------------
--     nvidia_cuopt          1,159      1,141    2,719   2026-09-21 07:32 UTC
--     cpsat_service           487         20    1,847   2026-09-22 02:03 UTC
--     nvidia_nemotron           0          -        -   none recorded
--
-- **cuOpt answers 1,141 of 1,159 calls — 98.4%. The CP-SAT service answers 20 of 487 — 4.1%.**
-- CP-SAT's 487 real calls decompose as: **420 `solved_but_zero_proposals`** (it solved and every row
-- came back `abstain`), **44 `errored`** (all `"Signal timed out."` at the 20,000 ms bound, avg
-- 20,007 ms), **20 `answered`** (fast when it answers — 415 ms), **3 `refused`** (HTTP 500).
--
-- ══ §3 DISPOSITIONS — WHO ACTUALLY DECIDES THE DEPOT ══════════════════════════
--
--     source                   rank   proposals   enacted   refused   superseded   enact%   share of
--                                                                                           all enacts
--     ----------------------   ----   ---------   -------   -------   ----------   ------   ----------
--     greedy_constrained       NULL      16,246     4,700     2,580        8,965    28.9%      97.7%
--     cuopt                      10       1,190        74       116          995     6.2%       1.5%
--     forward_lex (CP-SAT)        0       4,166        36       611        3,493     0.9%       0.7%
--     ottoq_service_priority   NULL         353         0         0          118     0.0%       0.0%
--
-- Total enactments 4,810. **The two external solvers together account for 110 of them — 2.3%.**
--
-- **`0250`'s "1 enacted against 7 refused and 11 superseded" is RETRACTED as a live-architecture
-- statement.** It was true of one run. Across the surviving evidence cuOpt has 74 enactments, and the
-- shape is different in a way that changes the diagnosis: cuOpt's dominant fate is **superseded
-- (83.6%), not refused (9.7%)**. A refusal means the shield judged the proposal infeasible. A
-- supersession means the proposal was fine and arrived too late to matter — 570
-- `newer_proposal_same_entity` plus 425 `entity_decided_by_other_proposal`. **cuOpt is not being
-- rejected on quality. It is being outrun.**
--
-- ══ §4 THE PRECEDENCE TABLE DOES NOT GOVERN THE PROPOSER THAT WINS ════════════
--
-- `ottoq_proposer_precedence` declares four seats: `forward_lex` 0, `cuopt` 10, `cuopt_fallback` 11,
-- `llm_advisor` 20, all `holds_tick`. **`greedy_constrained` has no row and carries
-- `proposer_rank IS NULL` on all 16,246 of its dispositions** — and it takes 97.7% of enactments,
-- while the seat ranked 0 takes 0.7%.
--
-- **This is NOT presented as a defect, and the difference matters.** `greedy_constrained` is the
-- in-process local proposer (`D001` records it as "in-process"); the precedence table exists to order
-- the EXTERNAL proposer seats against each other and against the local path's right to dispose. An
-- unranked in-process proposer beating ranked external ones is the propose/dispose design working:
-- the kernel disposes, and it is not obliged to wait.
--
-- **What IS worth a decision is that the declared architecture describes 2.3% of the behaviour.**
-- CLAUDE.md 2.5 reads as though CP-SAT schedules inside the site and cuOpt routes between sites.
-- On one depot there is no inter-site layer (rule 8), and inside the site the ranked solvers enact
-- 110 decisions against the local path's 4,700.
--
-- ══ §5 SO WHAT IS cuOPT'S TRUE ROLE, ANSWERED FROM THE WIRING ═════════════════
--
-- It has one, it is explicit in code, and it is not the one `D001` left it with.
-- `supabase/functions/_shared/cpsat_agent_chain.ts` declares:
--
--     export const PRIMARY_ASSIGNMENT_ENGINE  = "cp_sat_forward_lex";
--     export const FALLBACK_ASSIGNMENT_ENGINE = "cuopt";
--
-- and `ottoq-cpsat-propose`'s catch block calls `queueCuOptFallback(...)` on every failure path. So
-- **cuOpt is today the CP-SAT chain's failure handler**, and `ottoq_proposer_precedence` says the
-- same in data: *"NVIDIA cuOpt specialist and service-failure fallback. Lower priority than CP-SAT."*
--
-- **That role is load-bearing precisely because CP-SAT fails often.** 467 of CP-SAT's 487 real calls
-- ended in all-abstain, timeout or 500 — and each of those hands off to cuOpt. A fallback behind a
-- primary that answers 4.1% of the time is not a vestige.
--
-- **AND `D001` HAS NOT BEEN REVISITED, WITH AN ARITHMETIC COINCIDENCE THAT MAKES THE POINT EXACTLY.**
-- It decided on 2026-09-03 to "retire cuOpt from the decide path," it is the only file in
-- `docs/decisions/`, and nothing supersedes it. Of cuOpt's 1,159 endpoint-carrying calls, **1,143
-- happened AFTER 2026-09-03 — leaving exactly 16 before it.** Sixteen is the number `D001` and
-- `0220` both reasoned from. So the entire evidence base for retiring cuOpt is the 1.4% of its
-- calls that predate the decision, and **98.6% of everything cuOpt has ever done, it did after being
-- retired.** The documented decision and the running system disagree, and the running system is the
-- one serving traffic. Reconciling that is Chase's call, not a cleanup — which is why this file
-- stops here.
--
-- ══ §6 THE THREE THINGS THAT WOULD SETTLE THE EDGE QUESTION ═══════════════════
--
-- **(a) Why CP-SAT abstains 420 times out of 487.** This is the highest-value unknown in the whole
-- solver layer, and abstention is not failure — it is CP-SAT declining a frame. `0372` already
-- showed it declining a frame our own pointer census called four-free when all four stalls were
-- `Faulted`, i.e. it was RIGHT and the census was wrong. The request carries `max_assets: 8` and
-- `det_budget_s: 0.25` against a depot at 87%/80% occupancy on the two stall types that matter
-- (`0250`), so the hypothesis to test is that it is being handed frames with no feasible assignment
-- rather than failing to find one. That is a measurement, not an opinion, and it is not taken here.
--
-- **(b) Whether supersession is fixable by the deferral it already has — AND THE OBVIOUS VERSION OF
-- THIS EXPERIMENT IS FORBIDDEN, WHICH I NEARLY MISSED.** cuOpt's 995 supersessions are the signature
-- of a proposal with no protected window: `cuopt_first_refusal_max_defers` is **0** at global scope.
-- The tempting one-row fix is to raise the global to 1. **Do not.** The catalog says why in its own
-- description — *"0152: global tier is 0 — the deterministic core runs alone. Re-enable per run with
-- a run-scoped 1"* — and the same is true of `cuopt_propose_enabled`. A global defer would give a
-- nondeterministic network proposer a hold inside the certified deterministic path, which is exactly
-- what CLAUDE.md 2.5 forbids in terms: *"cuOpt can never sit inside the certified deterministic
-- path."* The global 0 is a certification invariant, not an oversight.
--
-- So the experiment is **run-scoped and already half-run**: `ottoq_agentic_arm` writes 1 on every
-- armed run, so armed runs already carry the protected window and unarmed ones do not. The
-- measurement is therefore available from existing evidence without changing any dial — partition
-- cuOpt's dispositions by whether their run was armed, and see whether `superseded` falls and
-- `enacted`/`refused` rise. `refused` would be the honest good outcome there, because it means the
-- shield actually judged the proposal instead of the clock discarding it. That partition is the next
-- query to write, and it is NOT taken here because it needs the per-run arm state joined in.
--
-- **(c) The comparison that does not exist.** `D001` §"the finding that matters more" still stands
-- word for word: we cannot show OTTO-Q beats anything, because the arms have not been run. None of
-- §3's enactment rates is an outcome measure — a proposer that enacts 28.9% is not thereby better
-- than one that enacts 6.2%, it is only louder and earlier. **Enactment share is a measure of who
-- got there first, not of who was right.** C5's four-policy CRN comparison is the only thing that
-- converts any of this into an edge claim in either direction.
--
-- ══ §7 WHAT MAY AND MAY NOT BE SAID ══════════════════════════════════════════
--
-- SAY: *"cuOpt reached the NVIDIA endpoint 1,159 times, answered 1,141 of them for 5,063 proposals
-- at 2.7 s average, and 74 of its proposals were enacted; it is wired as the CP-SAT chain's fallback
-- engine, and 84% of its proposals are superseded rather than refused — outrun, not rejected."*
--
-- DO NOT SAY: "cuOpt is retired" (it is live, and it is a declared fallback); "cuOpt never worked"
-- (98.4% answer rate); "CP-SAT replaced cuOpt" (it answers 4.1% of its calls and enacts 0.9% of its
-- proposals); "cpsat_service made 3,638 calls" (487); "4,248 Nemotron calls" (zero carry an
-- endpoint); or any enactment rate stated as a performance comparison (§6c).

\echo '=== 0322 §1 — the predicate: which ledger rows are actually calls ==='
SELECT provider, count(*) AS ledger_rows,
       count(*) FILTER (WHERE endpoint IS NOT NULL) AS real_calls,
       round(100.0*count(*) FILTER (WHERE endpoint IS NULL)/count(*), 1) AS pct_not_a_call,
       round(avg(latency_ms))                                  AS avg_ms_all_rows,
       round(avg(latency_ms) FILTER (WHERE endpoint IS NOT NULL)) AS avg_ms_real_calls
  FROM public.ottoq_model_call_ledger
 GROUP BY 1 ORDER BY 2 DESC;
-- cuOpt is the only provider whose "calls" are calls. cpsat_service's average latency is understated
-- 7.4x by 3,151 decision rows that never left the database.

\echo '=== 0322 §2 — what the CP-SAT service actually does when it IS called ==='
SELECT outcome, count(*) AS real_calls, round(avg(latency_ms)) AS avg_ms
  FROM public.ottoq_model_call_ledger
 WHERE provider='cpsat_service' AND endpoint IS NOT NULL
 GROUP BY 1 ORDER BY 2 DESC;
-- 420 all-abstain, 44 timeouts at the 20 s bound, 20 answers, 3 server errors.

\echo '=== 0322 §3 — dispositions: superseded is not refused, and that is the diagnosis ==='
SELECT source, proposer_rank, count(*) AS proposals,
       count(*) FILTER (WHERE status='enacted')    AS enacted,
       count(*) FILTER (WHERE status='refused')    AS refused,
       count(*) FILTER (WHERE status='superseded') AS superseded,
       round(100.0*count(*) FILTER (WHERE status='enacted')/count(*), 1) AS pct_enacted
  FROM public.ottoq_proposal_disposition_ledger
 GROUP BY 1,2 ORDER BY enacted DESC;
-- The unranked in-process proposer takes 97.7% of enactments. That is propose/dispose working, NOT a
-- defect -- and it is also why no enactment rate here is an outcome measure.

\echo '=== 0322 §4 — cuOpt has no protected window globally, AND THAT IS ON PURPOSE ==='
SELECT c.param_key, c.default_value, c.min_value, c.max_value, c.description
  FROM public.ottoq_policy_param_catalog c
 WHERE c.param_key IN ('cuopt_first_refusal_max_defers','cuopt_propose_enabled')
 ORDER BY c.param_key;
-- Read the descriptions before touching either: "0152: global tier is 0 -- the deterministic core
-- runs alone. Re-enable per run with a run-scoped 1." Raising the GLOBAL defer would put a
-- nondeterministic network proposer inside the certified path (CLAUDE.md 2.5 forbids exactly this).
-- ottoq_agentic_arm writes 1 per armed run, so the experiment is run-scoped and needs no dial change.

\echo '=== 0322 §5 — the documented decision and the running system disagree ==='
SELECT 'D001 decided 2026-09-03: retire cuOpt from the decide path' AS decision,
       (SELECT count(*) FROM public.ottoq_model_call_ledger
         WHERE provider='nvidia_cuopt' AND endpoint IS NOT NULL
           AND called_at > '2026-09-03') AS cuopt_calls_since,
       (SELECT max(called_at) FROM public.ottoq_model_call_ledger
         WHERE provider='nvidia_cuopt' AND endpoint IS NOT NULL) AS last_cuopt_call;
-- Nothing in docs/decisions/ supersedes D001. Reconciling it is a product decision, not a cleanup.
