-- 0266  THE FIRST LEDGER-BACKED HIT RATE ANY PROPOSER IN THIS ENGINE HAS EVER HAD,
--       AND IT SURVIVED A PURGE TO GET HERE.
--
-- Read-only. `public.ottoq_proposer_scorecard` over
-- `public.ottoq_proposal_disposition_ledger` (0364). Scope: twin depot
-- 11111111-1111-1111-1111-111111111111 (rule 8).
--
-- G72 said cuOpt's proposal-to-enactment rate was "not measurable from any durable
-- table", because `ottoq_external_proposals` is a per-tick working set that each
-- proposer deletes from before writing, and is `class='engine'` so the demo purge
-- takes whatever survives the tick. 0364 answered it. This is the answer arriving.
--
-- ══ 1. THE SCORECARD, READ AT 2026-09-20 05:11 UTC ══════════════════════════
--
--   source                  rank  disp  enacted  refused  superseded  rescued  enacted%  runs
--   cuopt                     10    24       16        7           1        4   **66.67**     1
--   greedy_constrained       NULL   111       25       33          53        0   **22.52**     2
--   ottoq_service_priority   NULL     2        0        0           2        0     0.00      2
--
-- `enacted_pct_of_committed` divides by NON-ABSTAINED dispositions, which is 0364's
-- whole point and G78's lesson: a proposer that correctly declines must not be
-- scored as having missed.
--
-- **THREE THINGS THIS SAYS, AND ONE IT DOES NOT.**
--
-- (a) **cuOpt's hit rate is three times the kernel's own fallback optimizer's** --
--     66.67% against 22.52%, on the same depot, in the same window. That comparison
--     has never been computable before tonight.
--
-- (b) **`rescued_by_promotion = 4`.** That is `ottoq_promote_proposal_candidates`
--     (0358, corrected by 0359) firing on cuOpt proposals -- the ranked-candidate
--     rescue path that `db/checks/0256` recorded as having "shipped inert for two
--     migrations" because no proposer emitted a `candidates` array until
--     `ottoq-cuopt-propose` v27. Four proposals that would have been refused for a
--     taken stall were re-pointed at a listed alternative instead.
--
-- (c) **`greedy_constrained` spans TWO runs** (`runs = 2`, first disposition
--     03:47:11, last 05:11:03), and one of those runs was deleted outright by the
--     purge that started `5b37ee46`. The scorecard still counts it. That is the
--     evidence-class property doing exactly what 0364 was built for, visible in a
--     column rather than argued from a registry row.
--
-- (d) **WHAT IT DOES NOT SAY: that cuOpt is three times better than the local
--     optimizer.** The denominators are not comparable populations. cuOpt proposes
--     SELECTIVELY -- its SQL gate declines when there is nothing to propose, which is
--     why `cuopt_invocation_log` is mostly gate refusals -- while
--     `greedy_constrained` is the kernel's fallback and proposes on essentially every
--     opportunity. And greedy's 53 `superseded` are not failures: a superseded
--     proposal is one a better proposal displaced, which is the propose/dispose
--     pipeline working as designed. **The honest sentence is "of the proposals each
--     source commits, cuOpt's are enacted three times as often" -- a statement about
--     selectivity as much as about quality.** Settling which it is needs the A/B
--     rig's `p_policy` (C5), not this view.

SELECT * FROM public.ottoq_proposer_scorecard;

-- ══ 2. THE TWO UNRANKED SOURCES ARE NOT AN OVERSIGHT ════════════════════════
--
-- `proposer_rank` is NULL for `greedy_constrained` and `ottoq_service_priority`
-- because neither is in `ottoq_proposer_precedence`, which holds four rows:
-- `forward_lex` 0, `cuopt` 10, `cuopt_fallback` 11, `llm_advisor` 20. `db/checks/0257`
-- §4 checked this before filing it as anything, because **G79 was filed wrong in
-- exactly this shape**: the absence is DELIBERATE where it is load-bearing --
-- `ottoq_cuopt_defer_hold` restricts the one-tick right of first refusal to sources
-- in that table, and its own comment records that an older test wrongly accepted
-- `greedy_constrained`. What remains undeclared is the SELECTION side, where both
-- sort last by a `COALESCE(rank, 2147483647)` default rather than by a decision.
--
-- For the kernel's own fallback optimizer "last" is the plausible intent. Nothing in
-- the schema says so, and until it does the scorecard's NULL rank cannot distinguish
-- "deliberately last" from "forgotten".

SELECT pp.source, pp.rank, pp.holds_tick,
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger l
         WHERE l.source = seen.source) AS ledger_dispositions
  FROM (SELECT DISTINCT source FROM public.ottoq_proposal_disposition_ledger
        UNION SELECT source FROM public.ottoq_proposer_precedence) seen
  LEFT JOIN public.ottoq_proposer_precedence pp ON pp.source = seen.source
 ORDER BY pp.rank NULLS LAST, seen.source;

-- ══ 3. THE ONE THING THE LEDGER STILL CANNOT SEE ════════════════════════════
--
-- `forward_lex` -- CP-SAT -- has **zero** rows. Not because it loses: because it has
-- not proposed. The in-engine path is `ottoq-cpsat-propose` calling
-- `OTTOQ_INTEL_URL`, and that host has had nothing behind it since **2026-09-20
-- 02:45 UTC** -- `cpsat_service`'s 49 calls run from `first_call` 2026-09-14 00:35 to
-- `last_call` 2026-09-20 02:45, and an earlier draft of `SOLVER_STATE.md` §13 quoted
-- the FIRST call's date as the last, turning a few hours of silence into six days. `db/checks/0264` judged it instead through the
-- offline bridge on four matched frames, where it declined all four with a reasoned
-- breakdown -- correct behaviour that produces no ledger row, because an abstention
-- the disposer never sees cannot be recorded.
--
-- So the scorecard cannot yet rank the three proposers against each other, and the
-- missing row is an infrastructure fact rather than a result. **That is the concrete
-- cost of the AWS decision, stated as a gap in a table rather than as an opinion.**

SELECT pp.source, pp.rank,
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger l
         WHERE l.source = pp.source) AS ledger_dispositions,
       (SELECT max(i.last_call)::text FROM public.ottoq_intelligence_ledger i
         WHERE (pp.source = 'cuopt'       AND i.provider = 'nvidia_cuopt')
            OR (pp.source = 'forward_lex' AND i.provider = 'cpsat_service')
            OR (pp.source = 'llm_advisor' AND i.provider = 'nvidia_nemotron')) AS provider_last_call
  FROM public.ottoq_proposer_precedence pp
 ORDER BY pp.rank;
