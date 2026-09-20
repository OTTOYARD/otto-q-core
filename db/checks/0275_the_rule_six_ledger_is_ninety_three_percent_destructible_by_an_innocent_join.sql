-- 0275  THE LEDGER RULE 6 SAYS TO READ IS 93.42% DESTRUCTIBLE BY AN INNOCENT JOIN.
--       THE CANONICAL VIEW DOES NOT MAKE IT. ANYONE WRITING THEIR OWN QUERY WILL.
--
-- Read-only. Guard installed by `0380`. **Nothing we have published is wrong** — that is
-- the first thing to establish and it is established below, not assumed.
--
-- ══ 1. HOW IT WAS FOUND: I DID IT TO MYSELF, TWO QUERIES APART ══════════════
--
-- Measuring `greedy_constrained`'s enactment rate, the same question two ways:
--
--   ledger alone,               GROUP BY sim_run_id          **847 rows**
--   ledger JOIN ottoq_sim_runs, GROUP BY seed, tick_count    **836 rows**
--
-- The missing **11** belong to run `3fb415d8`, which the demo purge deleted. Those are
-- the most valuable rows in the table: the only surviving record of a deleted run, which
-- is the whole reason `ottoq_proposal_disposition_ledger` is `class='evidence'` with
-- deliberately **no FK** to `ottoq_sim_runs`.
--
-- **An inner join re-imposes that forbidden foreign key at query time, silently.** Every
-- one of 0340 / 0364 / 0374 / 0378 records that an enforcing FK on evidence "can only
-- block the purge or, as CASCADE, erase what check (c) forbids erasing". A join does
-- neither — it omits, with no error, and what it omits is exactly the survivors.
--
-- **The pull toward that join is structural, not careless.** Seed, scenario and
-- `tick_count` live only in `ottoq_sim_runs`, and those are what any real analysis wants.

-- ══ 2. THE MAGNITUDE, WHICH IS NOT 11 ROWS ══════════════════════════════════
--
-- `0380`'s guard over the evidence ledgers:
--
--   table                                rows   orphaned   join loss
--   **ottoq_model_call_ledger**          3,543    **3,310    93.42%**
--   ottoq_proposer_fire_log                115        115   100.00%
--   ottoq_ab_runs                           91         91   100.00%
--   ottoq_proposal_disposition_ledger      890         12     1.35%
--   ottoq_layout_backup_0011_…               1          1   100.00%
--
-- **`ottoq_model_call_ledger` is the one that matters, and it is at 93.42%.** CLAUDE.md
-- Part 3 says, in bold: *"Read `public.ottoq_intelligence_ledger`. Never
-- `cuopt_invocation_log`."* That view reads this table. So the single table the brief
-- names as the durable answer to every cuOpt and Nemotron claim loses **93% of its rows**
-- to a join a careful analyst would write on purpose — to scope by depot per rule 8, or
-- by scenario, or by seed.
--
-- Three tables at 100% are less alarming than they look: they predate the runs that
-- currently exist, so *every* row is a survivor. They are still the same hazard.

SELECT * FROM public.ottoq_evidence_join_loss_now ORDER BY rows_orphaned DESC;

-- ══ 3. NOTHING PUBLISHED IS WRONG, AND HERE IS THE CHECK ════════════════════
--
-- The obvious fear is that tonight's cuOpt and Nemotron figures were already corrupted.
-- **They were not.** `pg_get_viewdef('public.ottoq_intelligence_ledger')` reads
-- `FROM ottoq_model_call_ledger l` in a bare subselect — **no join to `ottoq_sim_runs`
-- anywhere in it.** So every rule-6 number quoted from that view includes the purge
-- survivors and is correct as published:
--
--   nvidia_cuopt     872 calls, last 2026-09-20 04:49
--   nvidia_nemotron  2,622 calls, last 2026-09-20 05:16
--   cpsat_service    49 calls, last 2026-09-20 02:45
--
-- **So this is a latent hazard with a very large magnitude, not an active error** — and
-- saying so precisely matters more than the finding, because "the ledger is 93%
-- destructible" reads as "our numbers are wrong" if the next sentence is missing.

SELECT position('ottoq_sim_runs' in pg_get_viewdef('public.ottoq_intelligence_ledger'::regclass, true)) = 0
         AS rule6_view_makes_no_join_to_sim_runs,
       (SELECT count(*) FROM public.ottoq_model_call_ledger) AS ledger_rows;

-- ══ 4. THE FIX IS NOT "DO NOT JOIN" — THE LEDGER ALREADY CARRIES THE SCOPE ══
--
-- `ottoq_model_call_ledger` holds **both `depot_id` and `sim_run_id` as its own
-- columns**, frozen at capture. So rule 8's depot predicate needs no join at all:
--
--   RIGHT   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111'
--   WRONG   JOIN ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id
--            WHERE r.depot_id = '11111111-…'        -- drops 93% silently
--
-- The second form is how the same predicate is written everywhere else in this codebase,
-- because engine tables usually do NOT carry `depot_id` and must reach it through the
-- run. **That habit is correct for engine tables and wrong for evidence tables**, which
-- is precisely why it will keep happening: the muscle memory is right in nine places out
-- of ten.
--
-- What `0380` deliberately does NOT do is forbid the join. Restricting to live runs is
-- sometimes exactly what a caller wants — comparing the two arms of the pair currently on
-- the depot, for instance. It prices the choice instead, which is the same posture as
-- `0370` and `0374`: measure first, and let the number make the decision obvious.

SELECT c.column_name
  FROM information_schema.columns c
 WHERE c.table_schema = 'public' AND c.table_name = 'ottoq_model_call_ledger'
   AND c.column_name IN ('depot_id','sim_run_id','tick_seq','sim_clock','called_at')
 ORDER BY c.column_name;

-- ══ 5. AND A NUMBER I QUOTED THIS MORNING THAT THE SAME BREAKDOWN CORRECTS ══
--
-- `ottoq_proposer_scorecard` reports `greedy_constrained` at **35.30% enacted**, against
-- `db/checks/0266`'s 22.52%, and I read the rise as improvement from tonight's fixes.
-- **It is not improvement. It is a change in what got counted.**
--
--   experiment                                        runs   disp   enacted%
--   seed 777777, 1,260 ticks — the demo run              1    108    **24.1**
--   seed 171717, 12 ticks — certification pair arms      8    728    **37.4**
--   seed 777777, 1,245 ticks — PURGED, evidence only     1     11      9.1
--
-- **728 rows of twelve-tick certification arms outvote the demo run seven to one**, and
-- pull the aggregate up eleven points. The run that represents actual operation reads
-- **24.1%**. Same defect class as `0266` §1(d) — denominators that are not comparable
-- populations — and `0250`, an unscoped aggregate answering a different question. The
-- scorecard is not lying; it is averaging a certification harness with a demo, and
-- nothing in it says so.
--
-- **AND ONE GENUINELY GOOD THING FROM THE SAME BREAKDOWN.** Those eight arms agree at
-- **exactly 91 dispositions and 34 enacted, every time**, across four separate pairs.
-- Identical inputs, identical proposal dispositions. That is determinism evidence at a
-- level which is **not** one of the fourteen enforced atoms — per 2.9a's blind-spot
-- promotion doctrine it would be a candidate to add MEASURED, and the measurement
-- already exists.

WITH g AS (
  SELECT l.sim_run_id, r.random_seed, r.tick_count, l.status
    FROM public.ottoq_proposal_disposition_ledger l
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id   --: LEFT, on purpose
   WHERE l.source = 'greedy_constrained'
)
SELECT COALESCE(random_seed::text, '(purged)') AS seed,
       COALESCE(tick_count::text, '(purged)')  AS ticks,
       count(DISTINCT sim_run_id)              AS runs,
       count(*)                                AS dispositions,
       count(*) FILTER (WHERE status = 'enacted') AS enacted,
       round(100.0 * count(*) FILTER (WHERE status = 'enacted') / count(*), 1) AS enacted_pct
  FROM g
 GROUP BY 1, 2
 ORDER BY runs DESC;

-- Note the LEFT JOIN in the query above, which is the point of the whole file: it is the
-- form that keeps the purged run visible as `(purged)` instead of deleting it from the
-- analysis. An inner join here would have silently produced a cleaner-looking table with
-- one experiment missing.

-- ══ 6. THE GUARD FOUND ZERO COMMITTED VIOLATIONS, AND THE NEAR-MISS TEACHES ══
--
-- Twenty-four committed files reference one of the four evidence ledgers. Four of them
-- also join `ottoq_sim_runs`. Checked one by one rather than reported by count:
--
--   `0380`, `0275`  mine, deliberate — and `0275` §5's is a **LEFT** join, which is the
--                   form that keeps the purged run visible as `(purged)` instead of
--                   deleting it from the analysis.
--   `0269`          joins `ottoq_sim_runs` to `ottoq_rule_evaluations` (an ENGINE table),
--                   and does it LEFT. Not the hazard.
--   `0250`          inner-joins `ottoq_proposer_fire_log` — which this guard reports at
--                   **100% orphaned** — to `ottoq_sim_runs`.
--
-- **I was about to file that last one as a live instance of the defect. It is not.** Read
-- rather than pattern-matched:
--
--   (SELECT count(*) FROM public.ottoq_proposer_fire_log f
--     JOIN public.ottoq_sim_runs r ON r.sim_run_id = f.sim_run_id
--    WHERE r.status = 'running')                        AS rows_for_live_run
--
-- The column is named **`rows_for_live_run`** and the predicate is `r.status =
-- 'running'`. Restricting to live runs is precisely the legitimate case `0380`'s own
-- comment carves out, the inner join is the right tool for it, and the outer query counts
-- all 115 rows with no join at all. **The query is correct and its column says what it
-- means.**
--
-- So: **zero committed violations.** The hazard is entirely latent, which is the right
-- time to install a guard — before it costs a number rather than after.
--
-- **And the near-miss is the third time today that reading beat pattern-matching**, after
-- grepping `num_workers` when the parameter is `num_search_workers` (`db/checks/0274` §1)
-- and reading "93% destructible" as "our published numbers are wrong" before checking the
-- view definition (§3 above). The standing form: **a match is a candidate, not a finding,
-- and the thing that turns one into the other is reading the code it points at.**

SELECT count(*) AS fire_log_rows_total,
       (SELECT count(*) FROM public.ottoq_proposer_fire_log f
         JOIN public.ottoq_sim_runs r ON r.sim_run_id = f.sim_run_id
        WHERE r.status = 'running')          AS rows_for_live_run_0250s_question,
       (SELECT count(*) FROM public.ottoq_proposer_fire_log f
         JOIN public.ottoq_sim_runs r ON r.sim_run_id = f.sim_run_id)
                                             AS rows_surviving_any_inner_join
  FROM public.ottoq_proposer_fire_log;
