-- 0248  THE OUTSTANDING EVIDENCE PR #194 §5 SAID IT DID NOT HAVE.
--
-- PR #194 closed with an explicit refusal to claim an end-to-end run:
--
--   "The A/B proves G60's mechanism at full population on the live function. It
--    is NOT an end-to-end run showing forward_lex submitting and the kernel
--    enacting. ottoq_start_demo_run could not be driven from this session..."
--
-- This file is that run. `ottoq_start_demo_run` completed for the first time in
-- this engine's recorded life, on 2026-09-19, after four defects were cleared in
-- sequence (0344 constraint, 0345 delete order, 0347 unindexed FK, 0348 the
-- append-only guard). Every number below is read from the live engine, not from
-- a migration's own assertions.
--
-- ══ 1. THE START COMPLETED ═════════════════════════════════════════════════
--
-- Driven from pg_cron so no client timeout could truncate it. Returned:
--
--   { "ok": true,
--     "sim_run_id": "dde654cc-b734-4c75-a401-0358f4e02d2d",
--     "scenario": "busy_day", "demo_speed_x": 8.0,
--     "elapsed_ms": 210880,
--     "purged_prior": { "ok": true, "rows_purged": 7032541,
--                       "retry_passes": 0, "retention_armed": true } }
--
-- 7,032,541 rows purged in 210,880 ms -- 33,350 rows/sec -- and **retry_passes
-- 0**, so 0345's dependency ordering needed no retry at all: the topological
-- order it computes was correct on the first pass. The bounded retry it added is
-- a backstop that did not have to fire.
--
-- Largest contributors, from `cleared_by_table`:
--   ottoq_decisions 2,393,274 · ottoq_vehicle_commands 865,245
--   ottoq_ocpp_messages 588,707 · ottoq_telemetry_packets 542,218
--   space_conflict_ledger 290,346 · ottoq_recall_decisions 282,764
--   ottoq_oem_webhook_log 136,105 · ottoq_visit_needs 135,741
--   ottoq_vehicle_wear 129,491 · ottoq_deploy_log 105,002
--   ...and **ottoq_recall_refusals 6**.
--
-- Six rows. That is the table 0348 fixed, and deleting those six is what the
-- other 7,032,535 were waiting on.
--
-- ══ 2. THE EVIDENCE LEDGER SURVIVED THE PURGE. THIS IS 0340 PROVEN. ════════
--
-- 0340 created `ottoq_model_call_ledger` as class 'evidence' precisely so that
-- external model calls would outlive the run that made them, and CLAUDE.md rule
-- 6's hedge ("the true lifetime count is not recoverable from this table") could
-- be retired. Until today that was an assertion inside a migration. A purge of
-- 7,032,541 rows is the experiment, and it ran:
--
--   cuopt_invocation_log  (class engine)    -- 27,320 rows DELETED by the purge
--   ottoq_model_call_ledger (class evidence) -- reconstructed = 515, INTACT
--
-- `ottoq_intelligence_ledger` reports `reconstructed 515` for nvidia_cuopt after
-- the purge: every one of the 515 historical NVIDIA calls 0340 backfilled is
-- still there, while the engine-class table that originally held them lost all
-- 27,320 of its rows. The evidence class works, measured rather than argued.
--
-- ══ 3. THE LOOP IS RUNNING, AND cuOpt IS LIVE ══════════════════════════════
--
-- `ottoq_intelligence_ledger`, read at 17:16 UTC against the same view's values
-- from before the run (PR #194's table):
--
--   provider          calls           proposals        last call
--   nvidia_cuopt      515 -> **516**  2,738 -> **2,759**  2026-09-19 17:12:52
--   nvidia_nemotron 1,120 -> **1,127**      0             2026-09-19 17:15:50
--   cpsat_service      41 ->     41         0             2026-09-14 09:23:39
--
-- A new real call to optimize.api.nvidia.com and 21 new proposals, inside this
-- run. `cpsat_service` did NOT move -- see §6.
--
-- ══ 4. THE RUN IS FULLY ARMED, INCLUDING 0339'S DIAL ═══════════════════════
--
-- `ottoq_agentic_arming('dde654cc-...')` -> verdict **armed**, satisfied 7 of 7,
-- missing []. All seven keys in force, including
-- `prearrival_charge_yields_to_solver = 1` -- the G60 fix 0339 shipped default-off.
-- So this is not a default run that happens to tick; it is an agentic run with
-- the starvation gate open.
--
-- ══ 5. THE COCKPIT TELLS THE TRUTH, INCLUDING WHERE THERE IS NOTHING ═══════
--
-- `ottoq_activity_feed(run, 400)` grouped by action and engine:
--
--   task_start          deterministic_v1                              73
--   redeployment        deterministic_v1                              60
--   stall_assignment    inspect_seam                                  51
--   bess_dispatch       deterministic_v1                              33
--   stall_assignment    deterministic_v1                              30
--   stall_assignment    reservation_honoured                          22
--   stall_assignment    **cuopt**                                     21
--   gate_intake_no_charge deterministic_v1                            17
--   bay_reconcile       deterministic_v1                              14
--   orchestrator_agent  nemotron-3-ultra-550b -> **no solver call recorded** 12
--   triage_verdict      deterministic_v1                               4
--   orchestrator_agent  nemotron-3-ultra-550b -> **nvidia_cuopt**       2
--   orchestrator_agent  none -> no solver call recorded                 2
--   itinerary_amended   deterministic_v1                               2
--   stall_assignment    greedy_constrained                             1
--   stall_assignment    needs_card                                     1
--
-- THE TWO NUMBERS THAT MATTER HERE ARE 2 AND 12, AND 0346 IS WHY. Before 0346
-- the feed joined the fire log on a key present on 0 of 112 rows and COALESCEd
-- the result onto a hardcoded 'cp_sat_forward_lex' literal, so **all sixteen** of
-- these orchestrator_agent rows would have read "CP-SAT" -- on a run where
-- CP-SAT submitted nothing and has not been called since 2026-09-14. They now
-- read `-> nvidia_cuopt` where a solver was actually reached (2) and
-- `-> no solver call recorded` where none was (12). The absence is reported as
-- absence. That is the whole point of 0346 and of the renderer half in
-- ottoyarddepot-sim PR #101.
--
-- ══ 6. WHAT THIS RUN DOES *NOT* SHOW, STATED PLAINLY ═══════════════════════
--
-- `ottoq_agent_review(run, 3)` over the three most recent chains returns
-- verdict **`solver_returned_nothing`**, with `linkage: none`, `kernel: null`,
-- `proposals_returned: 0`, and `frame: {submitted: 0, empty_fires: 0}`.
--
-- Read that carefully, because it is NOT the G60 signature. G60's signature is
-- `solver_saw_empty_frame` with empty_fires > 0 -- the proposer fires and is
-- handed an instance with nothing in it. Here `empty_fires` is **0**: the
-- proposer was not fired in these chains at all. The agent ran, analysed, wrote
-- policy dials, and no proposer fire was linked to its chain.
--
-- So the loop's legs are in two different states on this run, and the honest
-- split is:
--
--   PROVEN END TO END   agent -> policy write -> shield -> deterministic
--                       disposal -> cockpit. Live, with real reasoning:
--                       "22 charge + 41 readiness_check + 11 interior_deep_clean
--                        + 6 interior_inspection atoms dominate pending work;
--                        6 inbound vehicles need immediate service clearance to
--                        sustain throughput" -> objective readiness_first, and
--                       energy_demand_factor_peak walked 0.9 -> 0.85 -> 0.8
--                       across three consecutive chains.
--
--   PROVEN SEPARATELY   cuOpt proposing and the kernel enacting -- 21
--                       stall_assignment rows with engine 'cuopt' in this run's
--                       feed, and 2 orchestrator_agent rows that do carry a
--                       linked cuOpt call.
--
--   NOT PROVEN HERE     that the agent's objective reaches a proposer fire on
--                       the SAME chain. 12 of 16 agent rows recorded no solver
--                       call.
--
-- AND THE MEASUREMENT THAT MAKES §6 SHARPER THAN "not proven". The whole
-- `ottoq_proposer_fire_log`, read after the purge (its sim_run_id is class
-- evidence, so it survived):
--
--   declared_source  status      fires  n_submitted  last_fire
--   forward_lex      empty          75            0  2026-09-17 00:29:33
--   forward_lex      submitted      37          208  2026-09-14 09:23:34
--
-- Two things follow, and the second is the finding. First, `forward_lex` is the
-- ONLY declared_source in the table -- cuOpt does not fire through this path.
-- Second, and decisively: **the most recent fire of any kind predates this run
-- by two and a half days.** This run started 2026-09-19 17:09. So the declared
-- rank-0 proposer did not fire ONCE on a fully armed run, and `empty_fires: 0`
-- in the agent review is not "fired and found nothing" -- it is "never fired".
--
-- PR #194's outstanding item is therefore not merely still outstanding; it is
-- now known to be blocked one stage earlier than 0339 addressed. 0339 opened the
-- gate that was taking the resource before the fire. The fire itself is not
-- happening.
--
-- Tracked as G66, and it must NOT be filed as a recurrence of G60. G60 was a
-- contract taking the scarce resource before the proposer fired -- fire present,
-- instance empty. G66 is no fire at all. A fix aimed at G60's mechanism cannot
-- move it, and the A/B that proved G60 says nothing about it.
--
-- ══ 7. TWO INSTRUMENT FAILURES, RECORDED BECAUSE THEY COST THE MOST TIME ═══
--
-- (a) `cron.job_run_details.return_message` is updated WHILE a job runs, so read
--     mid-flight it names the statement currently executing, not the outcome.
--     The same job read as "SET", then "INSERT 0 1", then "DO". Twice I
--     concluded from this that pg_cron was skipping the final statement of a
--     multi-statement command. It was not. A progress field read as a result
--     field is not evidence, and a status of 'succeeded' on such a row can
--     coexist with a transaction that rolled back.
--
-- (b) THE ONE THAT ACTUALLY DESTROYED A RESULT. An earlier wrapper's last act,
--     inside the same subtransaction as the work, was
--     `PERFORM cron.unschedule('ottoq-0348-start')`. I had removed that job by
--     hand moments before. It raised XX000 'could not find valid entry for job',
--     the EXCEPTION handler caught it, and plpgsql rolled the block back to its
--     BEGIN -- discarding a purge and a created run that had both **succeeded**,
--     after 209,577 ms of work. The log row reads:
--
--       stage 'start_raised',
--       { "sqlstate": "XX000", "elapsed_ms": 209577,
--         "message": "could not find valid entry for job 'ottoq-0348-start'" }
--
--     209,577 ms is the tell: it is the duration of a COMPLETE purge. The
--     failure was in the bookkeeping, not the work. Bookkeeping that can raise
--     does not belong in the same subtransaction as the thing it books.
--
-- ══ 8. QUERIES ═════════════════════════════════════════════════════════════
-- Read-only. Substitute the run id; none of this mutates anything.

\set run '''dde654cc-b734-4c75-a401-0358f4e02d2d'''

-- 8.1 the run exists, is ticking, and is armed
SELECT sim_run_id, status, tick_count, sim_clock_current, demo_speed_x, run_by
  FROM public.ottoq_sim_runs WHERE sim_run_id = :run::uuid;

SELECT public.ottoq_agentic_arming(:run::uuid) -> 'verdict'  AS verdict,
       public.ottoq_agentic_arming(:run::uuid) -> 'satisfied' AS satisfied,
       public.ottoq_agentic_arming(:run::uuid) -> 'missing'   AS missing;

-- 8.2 §2: the evidence ledger outlived the purge that emptied its engine-class
--     counterpart. reconstructed must still be 515 for nvidia_cuopt.
SELECT provider, calls, reconstructed, proposals, last_call
  FROM public.ottoq_intelligence_ledger ORDER BY calls DESC;

SELECT count(*) AS cuopt_invocation_log_rows_after_purge
  FROM public.cuopt_invocation_log;

-- 8.3 §5: the cockpit's own grouping. The two rows to read are
--     orchestrator_agent '-> nvidia_cuopt' and '-> no solver call recorded'.
WITH f AS (SELECT * FROM public.ottoq_activity_feed(:run::uuid, 400))
SELECT action, engine, count(*) AS n FROM f GROUP BY 1,2 ORDER BY n DESC;

-- 8.4 §6: the return leg's own verdict. Expect solver_returned_nothing with
--     empty_fires = 0 -- which is NOT G60's solver_saw_empty_frame.
SELECT jsonb_pretty(public.ottoq_agent_review(:run::uuid, 3));

-- 8.5 §6/G66: the declared primary proposer. The column is `n_submitted`, not
--     `submitted`. Read max(fired_at) against the run's started_at: if the last
--     fire predates the run, the proposer never fired and "empty frame" is the
--     wrong diagnosis.
SELECT declared_source, status, count(*) AS fires,
       sum(COALESCE(n_submitted,0)) AS n_submitted, max(fired_at) AS last_fire
  FROM public.ottoq_proposer_fire_log
 GROUP BY 1,2 ORDER BY 1,2;

SELECT (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = :run::uuid) AS run_started,
       (SELECT max(fired_at) FROM public.ottoq_proposer_fire_log)                   AS last_fire_any,
       (SELECT count(*) FROM public.ottoq_proposer_fire_log f
         WHERE f.fired_at >= (SELECT started_at FROM public.ottoq_sim_runs
                               WHERE sim_run_id = :run::uuid))                      AS fires_during_this_run;
