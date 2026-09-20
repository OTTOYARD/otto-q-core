-- 0257  G72 CLOSED, WITH THE ONE WITNESS THAT ACTUALLY PROVES IT: A PROPOSAL
--       THAT IS 1 ROW IN THE LEDGER AND 0 ROWS IN THE WORKING SET.
--
-- Read-only. Verifies migration 0364 (`ottoq_proposal_disposition_ledger`,
-- applied `20260920035200`) on live run `3fb415d8-3e06-4084-9436-7248f6c40449`
-- (cuOpt-only arm, seed 777777, busy_day, twin depot per rule 8).
--
-- G72 said: cuOpt's proposal-to-enactment rate is not measurable from any durable
-- table, because `ottoq_external_proposals` is a per-tick working set -- each
-- proposer opens with `DELETE FROM ottoq_external_proposals WHERE sim_run_id = …
-- AND source = <its own>` -- and is registered `class='engine'`, so what survives
-- the tick is taken by the next demo run's purge. 0364 answers it. This file is
-- the measurement, not the argument.
--
-- ══ 1. THE WITNESS ══════════════════════════════════════════════════════════
--
-- Measured 2026-09-20 03:51 UTC, four minutes after the trigger was created:
--
--   in_ledger        1
--   in_working_set   0
--
-- for proposal `caa2159e-39cd-4180-9091-46df11ae3771` -- `greedy_constrained`,
-- `enacted`, `enacted_by_kernel`, disposed tick 930. The working set had already
-- deleted it. Nothing else in this file matters as much as those two numbers:
-- they are the loss G72 described, happening, with the ledger holding what was
-- lost. Re-run after any new activity and substitute a fresh proposal_id.

SELECT 'in_ledger' AS where_, count(*) AS n
  FROM public.ottoq_proposal_disposition_ledger
 WHERE proposal_id = 'caa2159e-39cd-4180-9091-46df11ae3771'
UNION ALL
SELECT 'in_working_set', count(*)
  FROM public.ottoq_external_proposals
 WHERE proposal_id = 'caa2159e-39cd-4180-9091-46df11ae3771';

-- ══ 2. THE TRIGGER IS LIVE, NOT A ONE-OFF ═══════════════════════════════════
--
-- A second capture arrived unprompted between two readings of this file:
-- `ottoq_service_priority`, `superseded`, disposed 2026-09-20 03:51:47 UTC. Two
-- sources, two outcome classes, no intervention. Q2 is the standing coverage
-- assertion: every terminal-status row still visible in the working set whose
-- disposition happened at or after the ledger's earliest capture MUST have a
-- ledger row. Measured: `uncaptured_since_birth = 0`.
--
-- Note why `terminal_since_birth` also read 0 at the first run: the only row
-- disposed in that window was the one section 1 shows the working set had
-- already deleted. A zero here is not evidence of nothing happening -- read it
-- together with `ledger_rows`.

WITH birth AS (
  SELECT min(captured_at) AS t FROM public.ottoq_proposal_disposition_ledger
)
SELECT (SELECT t::text FROM birth) AS earliest_capture,
       (SELECT count(*) FROM public.ottoq_external_proposals ep
         WHERE ep.status <> 'pending'
           AND ep.disposed_at >= (SELECT t FROM birth)) AS terminal_since_birth,
       (SELECT count(*) FROM public.ottoq_external_proposals ep
         WHERE ep.status <> 'pending'
           AND ep.disposed_at >= (SELECT t FROM birth)
           AND NOT EXISTS (
             SELECT 1 FROM public.ottoq_proposal_disposition_ledger l
              WHERE l.proposal_id = ep.proposal_id)) AS uncaptured_since_birth,
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger) AS ledger_rows;

-- ══ 3. A TIMESTAMP THAT WILL BE MISREAD IF IT IS NOT WRITTEN DOWN ═══════════
--
-- `captured_at` defaults to `now()`, which in PostgreSQL is TRANSACTION START,
-- not statement time. The witnessed row's `captured_at` equals its
-- `proposal_created_at` to the microsecond (both 03:47:07.684486) while its
-- `disposed_at` is 03:47:11.147827 -- because that proposal was created AND
-- enacted inside one `decide_tick` transaction, and `disposed_at` is not
-- transaction-clocked.
--
-- So: `captured_at` is the transaction that disposed the proposal, and it can
-- legitimately precede `disposed_at`. For any elapsed-time reasoning use
-- `disposed_at - proposal_created_at`. Reading `captured_at - proposal_created_at`
-- as latency would report 0 ms for a proposal that took 3.5 s to dispose. This is
-- the G75 defect class (two clocks under names that read as a pair) and is
-- recorded here before someone divides by it.

SELECT source, status, disposition_reason, disposed_tick,
       proposal_created_at::text, disposed_at::text, captured_at::text,
       (disposed_at - proposal_created_at) AS elapsed_correct,
       (captured_at  - proposal_created_at) AS elapsed_wrong
  FROM public.ottoq_proposal_disposition_ledger
 ORDER BY disposition_id;

-- ══ 4. WHAT THE SCORECARD IMMEDIATELY SHOWED, AND IT IS NOT A DEFECT ════════
--
-- `ottoq_proposer_scorecard` reports `proposer_rank = NULL` for both sources it
-- has seen, because NEITHER IS IN `ottoq_proposer_precedence`. That table holds
-- four rows -- forward_lex 0, cuopt 10, cuopt_fallback 11, llm_advisor 20 -- and
-- the two proposers that have actually written to the ledger are not among them:
--
--   ottoq_service_priority   written by public.ottoq_service_priority_propose,
--                            called from ottoq_sim_decide_and_dispatch inside a
--                            BEGIN … EXCEPTION WHEN OTHERS THEN NULL block
--   greedy_constrained       written by public.ottoq_l2_optimize_assignments,
--                            the kernel's own local optimizer
--
-- CHECKED BEFORE FILING, because G79 was filed wrong in exactly this shape.
-- The absence is DELIBERATE where it is load-bearing: `ottoq_cuopt_defer_hold`
-- restricts the tick hold to `p.source IN (SELECT pp.source FROM
-- ottoq_proposer_precedence pp)`, and its own comment records why -- "old test
-- (ottoq_l2_external_proposal(...) IS NULL) accepted greedy_constrained". So an
-- unregistered proposer correctly gets no right of first refusal.
--
-- What is NOT established is the selection side. `ottoq_l2_external_proposal`
-- orders on `COALESCE(pp.rank, 2147483647) ASC`, so both of these sort LAST by
-- a COALESCE default rather than by a declared decision, and 0362's rank guard
-- gives them no protection for the same reason. For the kernel's own fallback
-- optimizer "last" is the plausible intent; nothing in the schema says so.
--
-- FILED AS AN OBSERVATION, NOT A DEFECT: `ottoq_proposer_precedence` reads like
-- the register of proposers and is not one -- it is the register of proposers
-- that hold the tick. Two live proposers are governed only by a COALESCE default.
-- The cheap fix is rows with explicit high ranks and `holds_tick = false`, which
-- would change no behaviour and would make the scorecard's NULL rank mean
-- "forgotten" again rather than "deliberately last".

-- NOTE: select `seen.source`, never `pp.source`. The first cut of this query
-- selected the precedence side of the outer join and printed NULL for exactly
-- the two rows it was written to expose -- a query that hides its own finding.
SELECT seen.source,
       pp.rank,
       pp.holds_tick,
       (SELECT count(*) FROM public.ottoq_external_proposals ep
         WHERE ep.source = seen.source) AS working_set_rows,
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger l
         WHERE l.source = seen.source) AS ledger_rows
  FROM (
   SELECT DISTINCT source FROM public.ottoq_external_proposals
   UNION SELECT DISTINCT source FROM public.ottoq_proposal_disposition_ledger
   UNION SELECT source FROM public.ottoq_proposer_precedence
 ) seen
 LEFT JOIN public.ottoq_proposer_precedence pp ON pp.source = seen.source
 ORDER BY pp.rank NULLS LAST, seen.source;

-- ══ 5. THE LIMIT, STATED BEFORE ANYONE QUOTES THE FIX ═══════════════════════
--
-- ACROSS-RUN SURVIVAL IS STRUCTURAL, NOT YET WITNESSED. No demo run has started
-- since the ledger was created, so "it survives ottoq_purge_prior_runs" rests on
-- (a) `class='evidence'` in `ottoq_run_scope_registry` and (b) the deliberate
-- absence of any FK to `ottoq_sim_runs` -- the same reasoning 0340 used, and the
-- registry's own check (b) requires an FK of `engine`/`stamp` only. Both were
-- asserted when 0364 applied. Neither is an observation of a purge sparing it.
-- The first new run converts this; until then say "registered to survive", not
-- "survived".
--
-- Q5 is what to re-run after the next `ottoq_start_demo_run`: ledger rows whose
-- sim_run_id is no longer the running run are the proof.

SELECT (SELECT count(DISTINCT sim_run_id) FROM public.ottoq_proposal_disposition_ledger) AS runs_in_ledger,
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger l
         WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                            WHERE r.sim_run_id = l.sim_run_id
                              AND r.status = 'running')) AS rows_outliving_their_run,
       (SELECT class FROM public.ottoq_run_scope_registry
         WHERE table_name = 'ottoq_proposal_disposition_ledger' LIMIT 1) AS registry_class;
