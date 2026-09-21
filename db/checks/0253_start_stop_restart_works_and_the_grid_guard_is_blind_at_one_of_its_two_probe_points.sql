-- 0253  START / STOP / RESTART WORKS END TO END OVER HTTP, WITH THE AUDIT LOG
--       INTACT. AND THE GRID-CAPACITY RULE PASSES 8,219 OF 8,663 EVALUATIONS
--       WITHOUT CHECKING ANYTHING.
--
-- Chase's acceptance criteria, in his words: "visual validation of the twin
-- simulator, running OTTO-Q from simulation, starts and restarts with audit log
-- in the UI." This file tests those mechanically and then goes looking for the
-- blind spot he asked for. It found one, and it is in the L1 shield.
--
-- ══ 1. THE RESTART CYCLE, DRIVEN OVER HTTP EXACTLY AS THE UI DRIVES IT ══════
--
-- Against the DEPLOYED `otto-twin-control` (v1.8.0-time-scale) with the anon key,
-- on the twin depot only (rule 8). Not the database functions directly -- the same
-- HTTP routes the cockpit calls, so a route that 404s or an auth posture that
-- refuses would have shown up here.
--
--   GET  /health                    -> ok, v1.8.0-time-scale
--   GET  /scenarios                 -> ok, catalog returned
--   POST /scenarios/start           -> run fa7c2782, busy_day, speed 60
--   GET  /sim_runs/:id/status       -> running, tick 0, depot 11111111-…
--   (pg_cron metronome drives it)   -> tick 63
--   POST /scenarios/stop            -> see below
--   POST /scenarios/start           -> run 1fd7bfbb, 8 seconds later
--
-- BOTH RUNS CAME UP ARMED 7 of 7 WITHOUT ANY MANUAL ARMING STEP. That is the
-- thing most likely to be wrong and was not: `ottoq_intelligence_stack(run)
-- ->'arming'->>'verdict'` reads `armed` with `satisfied` 7 of a required 7 on
-- each. The agent/solver loop is live on a UI-started run, not only on one a
-- migration armed by hand.
--
-- THE STOP RESPONSE IS THE INTERESTING ONE, because it is the audit handoff:
--
--   archived                  true
--   release_mode              world_reset
--   blackbox_ready            true
--   depot_reset_to_empty      true
--   sessions_ended            28
--   vehicles_unplaced         116
--   vehicles_residue_stripped 0
--   reproducible_from         {policy: otto_q, depot_id, scenario: busy_day,
--                              config_hash 7801abb6…, engine_hash b7b86a07…,
--                              random_seed 8999354396410455346}
--
-- `reproducible_from` is 2.9's credibility rule discharged at the exit door: the
-- stop hands back everything needed to replay the run. And `blackbox_ready: true`
-- is what the cockpit's BlackBoxPanel downloads.
--
-- ══ 2. THE PRIOR RUN'S AUDIT LOG SURVIVES THE RESTART ══════════════════════
--
-- The question that matters for a demo: does restarting erase what the last run
-- did? Measured after run #2 was up: run fa7c2782 still answers
-- `ottoq_activity_feed` with **325 rows**, and carries **1 `ottoq_run_archives`
-- row**. So the UI can show the previous run's audit trail after a restart.
--
-- WHY IT SURVIVES, and this is worth knowing rather than being lucky about:
-- there are TWO start paths with DIFFERENT purge semantics.
--   * `ottoq_start_demo_run`   calls `ottoq_purge_prior_runs` -- prior runs'
--     class='engine' rows are deleted. This is the 0231 mechanism.
--   * `ottoq_sim_run_scenario` (what the UI's POST /scenarios/start calls) does
--     NOT purge. Measured: `prosrc` contains no reference to the purge.
-- So a UI restart preserves prior-run evidence and a demo-run restart does not.
-- Neither is wrong, but anyone reasoning about what survives must know WHICH
-- start was used. Q5 asserts the asymmetry so it cannot quietly change.
--
-- ══ 3. THE BLIND SPOT: EN.001 GRID CAPACITY FAILS OPEN AT `task_start` ══════
--
-- `ottoq_eval_en_001_grid_capacity` opens with:
--
--     IF v_depot_id IS NULL OR v_request_kw <= 0 THEN
--       RETURN ROW(TRUE, 'no depot/request context', NULL, '{}'::jsonb, NULL)
--              ::ottoq_rule_result;
--
-- It returns **TRUE -- passed -- when it has no load to check.** Measured over
-- every EN.001 evaluation the engine has ever logged:
--
--   action_context     evaluations   with requested_kw   abstained   ever failed
--   task_start               8,219                   0       8,219             0
--   stall_assignment           444                 443           1             0
--
-- **8,219 of 8,663 evaluations (94.9%) are abstentions recorded as passes.** At
-- the `task_start` probe point the context has never once carried `requested_kw`,
-- so the rule has never once evaluated there -- not in this run, not in the
-- engine's life.
--
-- AND THE REGIME MAKES IT MATTER RATHER THAN BEING ACADEMIC. Where the rule DOES
-- get its context it is doing real work: 446 evaluations carry a headroom figure,
-- and the **minimum headroom reached is 26.1 kW against a 1,620 kW engineering
-- cap** (1,800 kW nameplate less a 10% safety margin). The depot ran to within
-- **1.6%** of its engineering limit. A guard that is blind at one of its two
-- probe points, in a depot that demonstrably approaches its cap, is not a
-- theoretical gap.
--
-- WHAT THIS IS NOT. Passing with no load is CORRECT for a non-charging action.
-- Of the **68** context-less passes on run fa7c2782 at its final tick:
--
--   (target is not a stall code at all)   41   -- task_start targets, e.g. promote_ready
--   wash_bay                              16   -- no kW; right answer
--   staging                               10   -- no kW; right answer
--   l2                                     1   -- THE GAP
--
-- So exactly **one** assignment to a charging stall skipped the grid check on
-- this run. On `stall_assignment` the wiring is essentially right, and the defect
-- is specific: EN.001 is registered at `task_start`, that probe point cannot
-- supply `requested_kw`, and the rule reports a pass instead of reporting that it
-- did not apply.
--
-- ⚠️ AND THE FIRST VERSION OF THAT TABLE WAS WRONG IN THIS REPO'S SIGNATURE WAY,
-- IN THE FILE WHOSE SUBJECT IS RULE 8. Q4 joins the feed's `target` to
-- `stalls.stall_code`, and my first version carried **no depot predicate**. It
-- reported 32 wash_bay / 20 staging / 2 l2 -- every stall-resolving row exactly
-- doubled -- because **158 of 330 `stall_code` values are duplicated across the
-- five depots** (172 distinct codes, 330 rows). The tell was arithmetic: the split
-- summed to 95 while Q6 counted 68 placeholder rows, and a split that does not sum
-- to its own population is a join fault, not a finding. Scoped to the twin depot it
-- sums to 68 exactly. Fifth instance of the 0145 / 0146 / 0229 / 0250 class, and
-- the lesson is sharper than "add a predicate": **`stall_code` is not unique, so
-- any join on it needs `depot_id` even when only one depot is under test.**
--
-- WHY THIS IS WORSE THAN G44 RATHER THAN THE SAME. G44 is nine declared rules
-- with no caller -- visibly absent, and countable. This rule IS called, 8,219
-- times, and every one of those calls lands in `ottoq_rule_evaluations` as
-- `passed = true`, indistinguishable from a real check by any count that does not
-- parse the reason string. **It inflates the shield's apparent coverage.** The
-- honest sentence for EN.001 is "evaluated 444 times at stall_assignment, 446
-- carrying a measured headroom, never failed, minimum margin 26.1 kW -- and
-- abstained 8,219 times at task_start, where it cannot see a load."
--
-- Tracked as G74. NOT FIXED HERE, and the fix is scoped rather than hand-waved:
--   * The hash-safe part: `ottoq_hash_rule_evaluations` digests `passed`,
--     `result_payload` and `parameters_used` and **does NOT digest `reason`**
--     (measured), so rewording the abstention costs no recert.
--   * The part that DOES force recert: making the abstention countable needs a
--     marker in `result_payload` (or a distinct outcome), and that column IS
--     digested. It belongs in a migration classified `forces_recert: TRUE`.
--   * The real question underneath is whether EN.001 should be registered at
--     `task_start` at all, or whether that probe point should supply
--     `requested_kw`. A charging task_start does imply load. That is a wiring
--     decision, not a text change, and it is the one worth making.
--   * Either way the rule must not report a pass for a check it did not run.
--
-- ══ 4. AND ONE PRESENTATION CONSEQUENCE, SINCE THE UI IS THE CRITERION ══════
--
-- `ottoq_activity_feed` is what `TwinDecisionLogTab` polls every 4 seconds, and
-- the abstention's reason string is rendered verbatim. Measured on the live run
-- with the UI's own fallback logic (`decisionReasonText`: prefer `reason`, else
-- flatten `rationale`, else null):
--
--   rows                                     164
--   render with NO explanation at all           0   <- good
--   render the literal "no depot/request context" 18   (11%)
--
-- So the log is never blank -- but 11% of rows show an internal placeholder to
-- whoever is watching, and all 18 are `stall_assignment`, the decision type an
-- auditor clicks first. Fixing §3's wording fixes this at the same time, which is
-- why the two are one finding and not two.
--
-- Nothing in this file changes engine state.
--
-- ── THE QUERIES ────────────────────────────────────────────────────────────

-- Q1  §3's headline, and the whole finding in one row set. The `abstained`
--     column is the count that is recorded as a pass.
SELECT e.action_context,
       count(*)                                                              AS evaluations,
       count(*) FILTER (WHERE COALESCE((e.context->>'requested_kw')::numeric,0) > 0)
                                                                            AS with_kw,
       count(*) FILTER (WHERE COALESCE((e.context->>'requested_kw')::numeric,0) <= 0)
                                                                            AS abstained_fail_open,
       count(*) FILTER (WHERE NOT e.passed)                                  AS ever_failed
  FROM public.ottoq_rule_evaluations e
 WHERE e.rule_code LIKE 'EN.001%'
 GROUP BY 1
 ORDER BY evaluations DESC;

-- Q2  the assertion that the abstention is a PASS, which is the defect. If this
--     ever returns false the rule has been changed to fail closed or to report
--     itself, and this finding is stale.
SELECT count(*)                                        AS abstentions,
       count(*) FILTER (WHERE e.passed)                 AS recorded_as_passed,
       count(*) = count(*) FILTER (WHERE e.passed)      AS every_abstention_is_a_pass
  FROM public.ottoq_rule_evaluations e
 WHERE e.rule_code LIKE 'EN.001%'
   AND e.reason = 'no depot/request context';

-- Q3  §3's "it matters" half: where the rule does evaluate, how close did the
--     depot come to its engineering cap? 26.1 kW of 1,620 is 1.6%.
SELECT (SELECT d.dcfc_max_concurrent_kw FROM public.depots d
          WHERE d.id = '11111111-1111-1111-1111-111111111111')               AS nameplate_kw,
       (SELECT round(d.dcfc_max_concurrent_kw * (1 - COALESCE(d.dcfc_safety_margin_pct,10)/100.0), 1)
          FROM public.depots d WHERE d.id = '11111111-1111-1111-1111-111111111111')
                                                                             AS engineering_cap_kw,
       count(*)        AS evaluations_with_a_headroom_figure,
       min(x.h)        AS min_headroom_kw,
       round(avg(x.h),1) AS avg_headroom_kw
  FROM (SELECT (regexp_match(e.reason, 'headroom ([0-9.]+) kW'))[1]::numeric AS h
          FROM public.ottoq_rule_evaluations e
         WHERE e.rule_code LIKE 'EN.001%'
           AND e.action_context = 'stall_assignment') x
 WHERE x.h IS NOT NULL;

-- Q4  §3's "what this is not": the context-less passes split by what they
--     targeted. wash_bay and staging are the right answer; l2 is the gap.
--     Substitute a live run id; this one is fa7c2782 and is class-engine data.
WITH f AS (
  SELECT * FROM public.ottoq_activity_feed('fa7c2782-3421-4aec-b2e8-a9a1e188a911'::uuid, 2000)
   WHERE reason = 'no depot/request context'
)
--     NOTE the ::text cast. `stalls.stall_type` is an ENUM, so
--     `COALESCE(s.stall_type, '(no stall)')` raises 22P02 -- invalid input value
--     for enum stall_type -- because the literal is coerced to the enum before
--     COALESCE runs. The version of this query actually used to produce §3's
--     numbers had no COALESCE at all; the defect was introduced while tidying it
--     for this file, and caught by running it. Left described rather than
--     silently fixed, in keeping with the rest of this directory.
--     AND NOTE THE DEPOT PREDICATE ON THE JOIN, which is load-bearing rather than
--     decorative: `stall_code` is NOT unique (172 distinct codes over 330 rows), so
--     without it every stall-resolving row doubles. Q4b below asserts that this
--     split sums to Q6's placeholder count, which is what caught it.
SELECT COALESCE(s.stall_type::text, '(target did not resolve to a stall)') AS target_kind,
       count(*) AS skipped_the_grid_check
  FROM f
  LEFT JOIN public.stalls s
         ON s.stall_code = f.target
        AND s.depot_id   = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1
 ORDER BY 2 DESC;

-- Q4b the arithmetic guard that caught Q4's missing predicate. A split of a
--     population must sum to that population; if this ever returns false, the
--     join is multiplying rows again.
WITH f AS (
  SELECT * FROM public.ottoq_activity_feed('fa7c2782-3421-4aec-b2e8-a9a1e188a911'::uuid, 2000)
   WHERE reason = 'no depot/request context'
),
split AS (
  SELECT count(*) AS n
    FROM f
    LEFT JOIN public.stalls s
           ON s.stall_code = f.target
          AND s.depot_id   = '11111111-1111-1111-1111-111111111111'
)
SELECT (SELECT n FROM split)                                   AS split_total,
       (SELECT count(*) FROM f)                                AS population,
       (SELECT n FROM split) = (SELECT count(*) FROM f)          AS split_sums_to_population,
       (SELECT count(*) FROM public.stalls)                     AS stall_rows,
       (SELECT count(DISTINCT stall_code) FROM public.stalls)   AS distinct_stall_codes;

-- Q5  §2's asymmetry, asserted rather than described: exactly one of the two
--     start paths purges prior runs, and it is not the one the UI calls.
SELECT p.proname,
       (p.prosrc ~* 'ottoq_purge_prior_runs') AS purges_prior_runs
  FROM pg_proc p
 WHERE p.proname IN ('ottoq_start_demo_run', 'ottoq_sim_run_scenario')
 ORDER BY 1;

-- Q6  §4: what the UI renders. `renders_blank` must stay 0; `renders_placeholder`
--     is the number §3's fix drives to 0.
SELECT count(*)                                                            AS rows,
       count(*) FILTER (WHERE (reason IS NULL OR btrim(reason) = '')
                          AND rationale IS NULL)                            AS renders_blank,
       count(*) FILTER (WHERE reason = 'no depot/request context')          AS renders_placeholder
  FROM public.ottoq_activity_feed('fa7c2782-3421-4aec-b2e8-a9a1e188a911'::uuid, 2000);

-- Q7  §1: the restart left the prior run's audit trail queryable and archived.
SELECT (SELECT count(*) FROM public.ottoq_activity_feed(
          'fa7c2782-3421-4aec-b2e8-a9a1e188a911'::uuid, 2000))              AS prior_run_feed_rows,
       (SELECT count(*) FROM public.ottoq_run_archives
         WHERE sim_run_id = 'fa7c2782-3421-4aec-b2e8-a9a1e188a911')          AS prior_run_archived,
       (SELECT count(*) FROM public.ottoq_sim_runs
         WHERE depot_id = '11111111-1111-1111-1111-111111111111'
           AND started_at > '2026-09-19 23:00:00+00')                       AS runs_started_this_test;
