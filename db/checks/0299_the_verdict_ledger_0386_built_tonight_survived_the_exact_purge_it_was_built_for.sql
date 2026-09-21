-- 0299  G93 VALIDATED BY ACCIDENT, UNDER THE EXACT CONDITION IT WAS BUILT FOR, HOURS AFTER BEING
--       BUILT. A demo run purged `ottoq_sim_runs` and took all sixteen of tonight's certification
--       rows with it. **`ottoq_determinism_verdict_ledger` — added by `0386` this same night,
--       because `ottoq_run_archives` held 1,166 determinism arms and ZERO verdicts — kept every
--       one.** Nine verdicts, nine passed, one engine hash.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
--
-- ══ 1. WHAT HAPPENED, IN ORDER, AND NONE OF IT WAS PLANNED AS A TEST ═══════
--
--   1. `0396` and `0397` both landed `forces_recert TRUE` and correctly invalidated all nine canon
--      columns (`db/checks/0298` §1b).
--   2. `ottoq-recert-runner` swept them, one pair per firing, over about forty minutes.
--   3. A cron guard I wrote in the same window — `awaiting_recert = 0` AND no live run, with
--      `0395`'s claim row as the mutex — fired the moment the sweep drained and started the
--      post-fix demo run `71942fbf`. It then unschedules itself by tag, which it did.
--   4. **`ottoq_start_demo_run` purges prior runs.** So the sixteen `cert_harness` rows in
--      `ottoq_sim_runs` that carried the sweep's verdicts were deleted, exactly as
--      `ottoq_run_scope_registry` says `class='engine'` data must be.
--
-- Measured immediately afterwards: `ottoq_sim_runs` holds **0** cert-harness rows since 03:19 UTC,
-- and `ottoq_determinism_verdict_ledger` holds **9 verdicts, all `outcome='passed'`, across a single
-- `engine_hash`**. The per-atom columns are intact: `atoms_compared`, `disagreeing_atoms`,
-- `null_atoms`.
--
-- **THIS IS G93's FINDING RUN IN REVERSE AND CONFIRMED.** `0386` was written because
-- `ottoq_run_archives` — registered as *"the permanent per-run record; its whole job is to outlive
-- the run"* — held 1,166 determinism arms and **not one verdict**, the verdict living only in
-- `ottoq_sim_runs`, which the purge deletes. The comment that made it look handled said *"the verdict
-- survives a dropped client: it lives on both run rows"* — true of a dropped HTTP client, false of
-- the next demo run. **Had tonight's sweep run yesterday, its result would now be unrecoverable.**
--
-- So the claim that may now be made, and could not have been made twelve hours ago: *"nine canon
-- columns were re-certified after two `forces_recert TRUE` migrations, all nine passed, and the
-- verdicts are readable after the purge that deleted the runs which produced them."*

SELECT count(*)                                                          AS verdicts_total,
       count(*) FILTER (WHERE certified_at > '2026-09-21 03:19:00+00')    AS since_0397,
       count(*) FILTER (WHERE certified_at > '2026-09-21 03:19:00+00'
                          AND outcome = 'passed')                         AS passed_since_0397,
       count(*) FILTER (WHERE certified_at > '2026-09-21 03:19:00+00'
                          AND outcome <> 'passed')                        AS not_passed_since_0397,
       count(DISTINCT engine_hash) FILTER (WHERE certified_at > '2026-09-21 03:19:00+00')
                                                                          AS engine_hashes
  FROM public.ottoq_determinism_verdict_ledger;

-- the other side of the same moment: the runs that produced those verdicts are gone
SELECT count(*) AS cert_harness_runs_since_0397_in_ottoq_sim_runs
  FROM public.ottoq_sim_runs
 WHERE run_by = 'cert_harness' AND started_at > '2026-09-21 03:19:00+00';

-- ══ 2. AND THE SELF-SEQUENCING GATE IS WORTH RECORDING AS A PATTERN ════════
--
-- The problem it solved: the post-fix five-KPI run had to come AFTER `0396`, per `0297` — landing it
-- between a measurement and its interpretation is `0294` §2's confound committed a second time — and
-- also after the recert sweep, because `ottoq-recert-runner` refuses to start while any run is
-- `running`/`paused` and a demo run's purge churns the tables the sweep writes. Two orderings, no
-- human in the loop, and I was not going to sit and poll for it.
--
-- The shape, which is reusable: a `* * * * *` job whose body is entirely a **precondition test**, and
-- whose single action is `0395`'s claim-guarded starter.
--
--     IF EXISTS (SELECT 1 FROM ottoq_determinism_canon WHERE enabled AND NOT satisfies_floor)
--        THEN RETURN; END IF;                       -- the sweep has not drained
--     IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status IN ('running','paused'))
--        THEN RETURN; END IF;                       -- something is already running
--     PERFORM ottoq_start_busy_run_once('g107_postfix_run', 8.0, 1, 100020);
--
-- `0395`'s `ottoq_run_once_claim` makes the PRIMARY KEY insert the mutex, so the job cannot
-- double-start however often it fires — which is the whole reason `0395` exists, after an
-- `IF EXISTS` guard started two demo runs fourteen seconds apart and the second purged the first.
-- The function unschedules the job by its own tag once it wins. Verified: the claim row exists, the
-- cron job is gone, and exactly one run started.
--
-- **The reason this is a pattern and not a one-off:** a precondition that is cheap to test and
-- expensive to wait for should be tested by the database on a timer, not by an agent on a poll. The
-- guard is auditable after the fact (the claim row is the receipt), it cannot double-fire, and it
-- costs nothing while the precondition is false.

SELECT (SELECT count(*) FROM public.ottoq_run_once_claim WHERE tag = 'g107_postfix_run') AS claim_rows,
       (SELECT count(*) FROM cron.job WHERE jobname = 'g107_postfix_run')                AS job_still_scheduled,
       (SELECT count(*) FROM public.ottoq_determinism_canon WHERE enabled AND NOT satisfies_floor)
                                                                                         AS awaiting_recert,
       (SELECT count(*) FROM public.ottoq_determinism_canon WHERE enabled AND satisfies_floor)
                                                                                         AS at_floor;

-- ══ 3. THE POST-FIX RUN IS LIVE, AND ITS CLOCK IS THE FIRST PROOF IN ANGER ══
--
-- Run `71942fbf` started 2026-09-21 04:01:56 UTC at seed 100020, and its `sim_clock_start` reads
-- **2026-09-20 05:35:00+00 — 00:35 Central**, the same value `c9b0a87e` carried. That is `0396`
-- working as designed on a real run rather than a rolled-back probe: **the clock did not move, and
-- the world is now built against it.** `0298` §1 proved the consequence on a probe (dispatches born
-- in the sim future 45 -> 0); this is the first live run where it holds.
--
-- **NOT YET MEASURED, and deliberately not claimed:** the five KPIs. The run needs its 540 sim-minute
-- horizon, and `0297`'s instruction stands — the post-fix measurement comes after the fix and is the
-- outstanding deliverable of G107. What can be said now is only what the run key says.

SELECT left(sim_run_id::text, 8)                                          AS run,
       status, tick_count, random_seed,
       sim_clock_start,
       to_char(sim_clock_start AT TIME ZONE 'America/Chicago', 'HH24:MI') AS start_ct,
       payload->'boot_prime'->>'start_hour_cst'                           AS world_built_for_hour_ct,
       payload->'boot_prime'->>'primed'                                   AS primed,
       (SELECT count(*) FROM public.ottoq_vehicle_dispatches d
         WHERE d.sim_run_id = r.sim_run_id AND d.dispatched_at > r.sim_clock_start)
                                                                          AS dispatched_in_the_future
  FROM public.ottoq_sim_runs r
 WHERE r.status = 'running'
 ORDER BY r.started_at DESC LIMIT 1;

-- OPEN-ITEM: the post-fix five-KPI measurement on run 71942fbf is still owed -- it needs the run's 540 sim-minute horizon, and 0297 requires it to come after 0396 rather than before. Record it before any subsequent demo run purges the class='engine' tables it is computed from, which is what 0395 exists for. Tracked as G107.
