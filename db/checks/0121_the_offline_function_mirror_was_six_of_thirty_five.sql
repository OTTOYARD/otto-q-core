-- ---------------------------------------------------------------------------
-- 0121 — db/fn_current/ said "current" and was 6 of 35.
--
-- The directory is the offline record of the live engine: what an agent reads
-- to know what the decide path does without a database. It was captured on
-- 2026-08-19 (run2/C4 and run3/C7) and never re-measured. Twenty-eight of its
-- thirty-five files describe an engine that stopped existing somewhere across
-- migrations 0154..0209, one captures a function the catalog no longer has,
-- and five shipped with no md5 pin at all.
--
-- Nothing here changes the database. These are the queries that produced the
-- drift table in db/fn_current/README.md, so the reading can be reproduced and,
-- more to the point, RE-taken: the whole defect was that nobody re-took it.
--
-- Readings recorded 2026-09-08 against gxdrcyphqjzjsuhxuqtg.
-- ---------------------------------------------------------------------------

-- Q1. THE LIVE IDENTITY OF EVERY FUNCTION THE MIRROR CLAIMS TO HOLD.
--     Compare each md5 against the `-- md5 at capture:` line in the matching
--     db/fn_current/<schema>.<name>.sql. p.prokind = 'f' matters: without it
--     pg_get_functiondef raises on aggregates ("st_extent is an aggregate
--     function"), which is how this query failed the first time it was written.
--
--     RESULT 2026-09-08: 34 rows. public.ottoq_demo_metronome returns nothing —
--     it is the one capture with no live counterpart.
SELECT n.nspname || '.' || p.proname AS fn,
       md5(pg_get_functiondef(p.oid)) AS live_md5,
       length(pg_get_functiondef(p.oid)) AS chars
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prokind = 'f'
  AND n.nspname IN ('public', 'twin')
  AND p.proname IN (
    'cuopt_log_gate','ottoq_benchmark_reset','ottoq_charge_plan_for_visit',
    'ottoq_comms_emit_telemetry','ottoq_cron_tick','ottoq_cuopt_first_refusal_arm',
    'ottoq_cuopt_refresh','ottoq_decide_tick','ottoq_demo_metronome',
    'ottoq_evaluate_return_need','ottoq_fn_backup_enact_cuopt_batch',
    'ottoq_is_overnight_holdout','ottoq_l2_optimize_assignments',
    'ottoq_release_expired_tethers','ottoq_run_governor_auto_stop',
    'ottoq_sim_decide_and_dispatch','ottoq_twin_snapshot','ottoq_arm_refuse_move',
    'ottoq_sim_advance_charge_sessions','ottoq_sim_advance_deployed_telemetry',
    'ottoq_sim_advance_grid','ottoq_sim_advance_service_flow',
    'ottoq_sim_advance_site_energy','ottoq_sim_advance_weather_and_solar',
    'ottoq_sim_auto_charge_assign_tick','ottoq_sim_auto_dispatch_tick',
    'ottoq_sim_bay_fault_handler','ottoq_sim_bess_step','ottoq_sim_confirm_commands',
    'ottoq_sim_dispatch_vehicle','ottoq_sim_emit_arrival_webhook',
    'ottoq_sim_start_charge_session','ottoq_sim_start_run',
    'ottoq_sim_stop_charge_session','ottoq_sim_vehicle_exception_handler')
ORDER BY 1;

-- Q2. THE ONE THAT IS GONE.
--     RESULT 2026-09-08: 0.
SELECT count(*) AS demo_metronome_still_exists
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prokind = 'f' AND n.nspname = 'public' AND p.proname = 'ottoq_demo_metronome';

-- Q3. THE RECALL SPLIT, WHICH IS WHY ONE FILE IS STALE AND STILL CORRECT.
--     Migration 0206 copied the rung ladder out of ottoq_evaluate_return_need
--     into ottoq_recall_naive_threshold_v1 and left a dispatcher behind. The
--     captured body is byte-exact for the LADDER: rename the live ladder back
--     and it md5s to the captured 0c463ada, and the name occurs exactly once,
--     so the rename is the entire difference.
--
--     RESULT 2026-09-08:
--       live_wrapper       53018872b12d8032f8728851dff719e7
--       live_ladder        cd3ffc2ad5c6f18f391c753e8bda42f1
--       ladder_renamed     0c463ada1588296a31ec1761d16a83d4  <- equals the capture
--       name_occurrences   1
WITH d AS (
  SELECT pg_get_functiondef(p.oid) AS src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ottoq_recall_naive_threshold_v1'
)
SELECT md5(pg_get_functiondef('public.ottoq_evaluate_return_need'::regproc)) AS live_wrapper,
       md5(src)                                                             AS live_ladder,
       md5(replace(src, 'ottoq_recall_naive_threshold_v1',
                        'ottoq_evaluate_return_need'))                      AS ladder_renamed,
       (length(src) - length(replace(src, 'ottoq_recall_naive_threshold_v1', '')))
         / length('ottoq_recall_naive_threshold_v1')                        AS name_occurrences
FROM d;

-- Q4. THE RECALL LEDGER IS LIVE AND THE REGISTRY REALLY DRIVES IT (G6, C9).
--     ottoq_evaluate_return_need reads recall_implementation_id from the run's
--     policy, looks the row up in ottoq_recall_implementations, and EXECUTEs
--     whatever evaluator_function it names. Config-swappable in the database on
--     the same terms recall/ is in Python.
--
--     RESULT 2026-09-08:
--       decisions 8390 | implementations 2 | wrapper_dispatches_dynamically t
SELECT (SELECT count(*) FROM public.ottoq_recall_decisions)         AS decisions,
       (SELECT count(*) FROM public.ottoq_recall_implementations)   AS implementations,
       pg_get_functiondef('public.ottoq_evaluate_return_need'::regproc)
         LIKE '%EXECUTE format%evaluator_function%'                 AS wrapper_dispatches_dynamically;

-- Q5. THE REGISTRY CARRIES A STATUS THE WRAPPER DOES NOT READ.
--     fixed_window_dummy is registered `parked` — it exists to prove the swap,
--     and it is not a policy anyone should run. The wrapper selects the row by
--     impl_id alone, so nothing stops a run from naming it. Recorded here as an
--     open observation, not a fix: it is a live decide-path change and belongs
--     in its own migration with its own A/B.
--
--     RESULT 2026-09-08, BEFORE migration 0210:
--       naive_threshold_v1 | active | ottoq_recall_naive_threshold_v1
--       fixed_window_dummy | parked | ottoq_recall_fixed_window_dummy
--       wrapper_reads_status = false
--
--     CLOSED THE SAME DAY by migration 0210, so re-running Q5 now reads
--     wrapper_reads_status = true. The observation above is left as the
--     point-in-time reading it was. 0210 refuses a non-active implementation
--     only on a run whose run_by is 'production_live' — the parked dummy still
--     runs on the twin, because deleting the swap proof to protect production
--     would remove the evidence that the Recall Decision is an interface at all.
--     Measured, not argued: an A/B over four replayed decisions that reach the
--     rung ladder was byte-identical under the active implementation, so
--     forces_recert is FALSE and the recert floor did not move.
SELECT i.implementation, i.status, i.evaluator_function,
       pg_get_functiondef('public.ottoq_evaluate_return_need'::regproc)
         LIKE '%status%' AS wrapper_reads_status
FROM public.ottoq_recall_implementations i
ORDER BY i.impl_id;
