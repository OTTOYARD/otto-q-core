-- 0287  ALL NINE CANON COLUMNS CERTIFIED, PASSED, 14 ATOMS EACH, ZERO DISAGREEING AND ZERO
--       NULL — THE FIRST TIME THE COMPLETE MATRIX HAS EVER BEEN HELD IN A DURABLE RECORD.
--
-- Read-only. Scope: the canon columns as `ottoq_cert_columns` declares them — seven on the
-- twin depot 11111111-1111-1111-1111-111111111111 and two `grid_smoke` on fixture depot
-- `aacd0bb0-…`, a rule-8 call Chase resolved on 2026-09-20 (see §4). Every row below lives
-- in `public.ottoq_determinism_verdict_ledger`, which `0386` made append-only and
-- `class='evidence'` with deliberately no FK to `ottoq_sim_runs`, so unlike everything this
-- matrix used to be written to, it survives the next demo run.
--
-- ══ 1. THE MATRIX ══════════════════════════════════════════════════════════
--
--   scenario     seed     ticks  outcome  atoms  disagreeing  null   certified (UTC)
--   grid_smoke   239001      6   passed     14        0        0     19:08:00
--   grid_smoke   424242      6   passed     14        0        0     19:09:00
--   busy_day     171717     12   passed     14        0        0     19:10:00
--   busy_day     314159     12   passed     14        0        0     19:13:07
--   busy_day     424242     12   passed     14        0        0     19:16:22
--   normal_day   171717     12   passed     14        0        0     19:19:47
--   busy_day     171717     24   passed     14        0        0     20:39:00
--   busy_day     424242     24   passed     14        0        0     20:45:41
--   busy_day     171717     48   passed     14        0        0     20:52:52
--
-- Nine of nine `satisfies_floor`, against a recert floor of **19:01:10** set by `0388`. All
-- fourteen atoms compared on every column, none disagreeing, none null — and `null_atoms`
-- matters as much as `disagreeing_atoms` here, because `0386` built it precisely so a NULL
-- hash could not masquerade as agreement.
--
-- **What this licenses, exactly.** CLAUDE.md 2.9a calls the fourteen-atom byte-identical
-- verdict a *product property* rather than a test practice, on the grounds that R-12
-- established the leading GPU solver in this space cannot promise byte-identical output at
-- all. Until today that claim rested on verdicts that **did not survive their run** — G93
-- measured 1,166 archived arms carrying zero recoverable verdicts. The sentence is now
-- backed by a record that outlives the engine state it describes.

SELECT scenario, seed, ticks, outcome, atoms_compared,
       COALESCE(array_length(disagreeing_atoms, 1), 0) AS disagreeing,
       COALESCE(array_length(null_atoms, 1), 0)        AS null_atoms,
       certified_at::timestamp(0) AS certified_at
  FROM public.ottoq_determinism_verdict_ledger
 WHERE certified_at > public.ottoq_cert_recert_floor()
 ORDER BY ticks, scenario, seed;

SELECT scenario, seed, ticks, status, outcome, satisfies_floor
  FROM public.ottoq_determinism_canon
 ORDER BY ticks, scenario, seed;

-- ══ 2. WHAT THE LEDGER'S OWN TOTALS SAY, INCLUDING THE FAILURES ════════════
--
--   rows in the ledger                **24**   (first ever: 2026-09-20 17:42)
--   passed                            **21**
--   **inconclusive**                   **3**
--   distinct engine_hash values         **4**
--
-- **The three `inconclusive` rows are not determinism failures and must not be reported as
-- any.** They are arms that ran out of their time budget: at 24 ticks under the runner's
-- original 240-second default, arm A finished all 24 while arm B reached 21, then 22. **The
-- two arms are not symmetric** — a pair runs both inside ONE transaction, so arm B ticks
-- with arm A's rows already visible to it and is therefore slower. The fix was to scale the
-- budget with the work, `p_arm_budget_s => GREATEST(240, ticks * 30)`, not to suspect the
-- engine. Recorded because "inconclusive" beside "passed" in a determinism ledger is exactly
-- the kind of row a later reader will misread as a near-miss.
--
-- Four distinct `engine_hash` values across 24 rows is the migration lineage moving under
-- the matrix during the same evening (`0383`, `0385`, `0387`, `0388`), which is the recert
-- floor doing its job rather than drift.

SELECT outcome, count(*) AS rows,
       min(certified_at)::timestamp(0) AS first_at,
       max(certified_at)::timestamp(0) AS last_at,
       count(DISTINCT engine_hash) AS engine_hashes
  FROM public.ottoq_determinism_verdict_ledger
 GROUP BY 1 ORDER BY rows DESC;

-- ══ 3. THE RUNNER STAYS ON, AND WHY THAT IS THE SAFE CHOICE ════════════════
--
-- `ottoq-recert-runner` is pg_cron job **746**: `* * * * *`, an advisory xact lock so two
-- firings cannot overlap, a refusal while any run is `running` or `paused`, and it picks the
-- next column from `ottoq_determinism_canon WHERE enabled AND NOT satisfies_floor`.
--
-- **Left scheduled deliberately.** It acts only when a column has fallen below
-- `ottoq_cert_recert_floor()`, so on a settled matrix every firing is a sub-second no-op —
-- which is exactly what the 24 firings between 20:16 and 20:39 were while a demo run held
-- the depot. Leaving it on makes the canon self-maintaining: the next `forces_recert TRUE`
-- migration invalidates the columns it should, and they re-certify without anyone
-- remembering to ask. That closes the gap `0279` found — `ottoq_cert_columns` declared nine
-- canons, `ottoq_cert_matrix` reported them, `ottoq_cert_recert_floor` expired them, and
-- **nothing ran them** — which is the same declared-with-no-executor shape as G86.
--
-- **AND A TRAP I NEARLY FELL INTO WHILE WATCHING IT, recorded because it will catch the next
-- reader too.** `cron.job_run_details` showed 24 firings, all `succeeded`, all with
-- `start_time = end_time`, and then a **five-minute gap with no row at all**. That reads
-- exactly like a job that has stopped firing. It is the opposite: **pg_cron does not write a
-- row until a firing COMPLETES, and will not start an overlapping firing of the same job**,
-- so a gap is the job WORKING. `pg_stat_activity` showed the runner active at 347 seconds —
-- a 24-tick pair mid-flight. The runner's own header already says pg_stat_activity is the
-- only authority for "in flight"; that line is there for the certification guard, and it
-- turns out to be the right authority for watching the runner too.

SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'ottoq-recert-runner';

SELECT count(*) AS firings,
       count(*) FILTER (WHERE status = 'succeeded') AS succeeded,
       count(*) FILTER (WHERE status <> 'succeeded') AS other,
       max(start_time)::timestamp(0) AS last_start,
       round(avg(EXTRACT(EPOCH FROM (end_time - start_time)))::numeric, 1) AS mean_secs
  FROM cron.job_run_details
 WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'ottoq-recert-runner');

-- ══ 4. WHAT IS NOT CLAIMED ═════════════════════════════════════════════════
--
-- * **Not that the engine is deterministic in general.** Nine columns is nine (scenario,
--   seed, ticks) triples. `content_hash` remains OUT of the fourteen enforced atoms per
--   2.9a's blind-spot promotion doctrine, and `db/checks/0216`'s defect — a pair that passed
--   all fourteen while disagreeing with itself on `content_hash` at 44 of 48 ticks — is
--   exactly why a passing matrix is not a general claim.
-- * **The two `grid_smoke` columns are on a fixture depot, not the twin.** That was flagged
--   to Chase as a rule-8 call rather than decided unilaterally, and he resolved it: a
--   determinism pair yields no capacity result — it asserts only that two arms of the same
--   scenario agree byte-for-byte — so rule 8's stated rationale (a result from a second site
--   does not advance the one question the twin exists to answer) does not bite. They are
--   also the only columns exercising the `0132` site power gate under a tight cap, so
--   dropping them would have lost a regression canary and gained no scope discipline.
-- * **Not a claim about any KPI.** A byte-identical pair says the engine reproduces itself;
--   it says nothing about whether the numbers it reproduces are the right ones. `0286` is the
--   standing example — KPI 4 is perfectly reproducible and 8.5x overstated.
