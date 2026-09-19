-- ============================================================================
-- 0250 — STARTING A TWIN RUN NOW TAKES OVER FIFTEEN MINUTES. FOUR DAYS AGO THE
--        IDENTICAL CALL RETURNED IN SECONDS. THIS BLOCKS ALL PAIRED TESTING.
-- ============================================================================
-- Found while trying to judge 0330's P1-P3, which need a fresh pair on seed
-- 771771 against the control in db/checks/0249.
--
-- ── WHAT IS MEASURED ───────────────────────────────────────────────────────
-- 2026-09-19 ~16:2x UTC. `SELECT public.ottoq_sim_run_scenario('busy_day',
-- 771771, 'claude_0330_treatment')` ran for 937+ seconds without returning and
-- without creating a run row. The SAME call with run_by='claude_0328_verify'
-- and 'claude_0329_treatment' returned a run id in seconds on 2026-09-14/15.
--
-- The backend carries `SET statement_timeout = 0`, so the 60-second client
-- timeout does NOT stop it -- the client gives up, the work continues. A second
-- identical call issued after the first client timeout did not fail either: it
-- queued on `Lock: transactionid` behind the first and would have created a
-- DUPLICATE run once the lock cleared. It was cancelled with
-- pg_cancel_backend. ANYONE RETRYING A TIMED-OUT RUN START IS QUEUEING A
-- SECOND RUN, NOT RETRYING THE FIRST. That is worth knowing on its own.
--
-- The stuck backend holds RowExclusiveLock on the engine's largest tables --
-- ottoq_decisions, ottoq_events, ottoq_rule_evaluations, ottoq_stall_bookings,
-- ottoq_variability_cards, ottoq_comms_messages, ottoq_vehicle_commands,
-- ottoq_decision_snapshots, ottoq_bay_binding_witness, ottoq_ocpp_messages,
-- ottoq_visit_needs, ottoq_itinerary_legs -- which is the signature of the
-- prior-run purge, and the run-scope registry lists 47 tables in class
-- `engine` for it to walk.
--
-- ── WHAT THE TABLES LOOK LIKE, AND THE INFERENCE I FIRST DREW AND WITHDREW ──
--   table                    heap    total   live_tup   dead_tup  %dead
--   ottoq_decisions        2238 MB  2955 MB  2,385,592   161,248    6.3
--   ottoq_events           1225 MB  2099 MB     35,925       794    2.2
--   ottoq_comms_messages    498 MB   549 MB     22,709         0    0.0
--   ottoq_vehicle_commands  429 MB   486 MB    858,990    14,063    1.6
--   ottoq_stall_bookings    398 MB  1039 MB      8,214       437    5.1
--   ottoq_rule_evaluations  317 MB  1270 MB     24,059        62    0.3
--
-- My first reading was "massive dead-tuple bloat, autovacuum is not keeping
-- up." THAT IS WRONG and I withdrew it on measuring: %dead is 0.0-11.2
-- everywhere, autovacuum_count runs 213-1241 per table, and several of these
-- were autovacuumed TODAY. Autovacuum is working fine.
--
-- What the numbers actually show is FREE-SPACE bloat: autovacuum marks space
-- reusable but never returns it to the filesystem, so ottoq_events keeps a
-- 1,225 MB heap to hold 35,925 live rows and ottoq_stall_bookings keeps 398 MB
-- to hold 8,214. Any sequential scan still reads every page. The lifetime churn
-- explains how the files got that big: n_tup_del is 19,214,424 on
-- ottoq_decisions, 14,269,476 on ottoq_events, 12,816,519 on
-- ottoq_rule_evaluations.
--
-- ── WHAT IS *NOT* ESTABLISHED, AND MUST NOT BE QUOTED AS IF IT WERE ────────
-- 1. That the purge is the slow step. It is inferred from the lock set, not
--    timed in isolation. The next move is to time ottoq_purge_prior_runs on its
--    own against a scratch run id.
-- 2. That free-space bloat is the CAUSE of the slowness. The bloat is measured;
--    the causal link to the 937 s is not. A 2.2 GB heap and a slow purge can
--    both be consequences of the same churn without one causing the other.
-- 3. Whether anything other than data growth changed between 09-15 and 09-19.
--    0330 was applied on 09-19 but only touches ottoq_release_departed_spaces
--    and adds ottoq_vehicle_absent_from_site; neither is on the run-start path.
--    That is an argument, not a measurement, and it should be checked by timing
--    a start with the 0330 objects present but a purge that has nothing to do.
--
-- ── WHY IT MATTERS BEYOND ONE SLOW CALL ────────────────────────────────────
-- Every demo run purges prior runs at start. The purge cost grows with
-- accumulated history, and each run adds history. If that is the mechanism it
-- is self-compounding, and the twin gets slower every time it is used -- which
-- is exactly the shape of the arc db/checks/0229 already fought once (519 s ->
-- 122 s). It also silently raises the cost of every future paired test, which
-- is the instrument this whole staging thread depends on.
-- ============================================================================

-- A. Is a start in flight, and for how long? (pg_stat_activity is the only
--    authority; the client timing out tells you nothing.)
SELECT pid, state, wait_event_type, wait_event,
       round(extract(epoch FROM (now()-xact_start))::numeric,0) AS xact_age_s,
       left(regexp_replace(query,'\s+',' ','g'), 100) AS q
  FROM pg_stat_activity
 WHERE datname=current_database() AND pid<>pg_backend_pid()
   AND query ILIKE '%ottoq_sim_run_scenario%'
 ORDER BY xact_start;

-- B. Heap size against live rows -- the free-space picture.
SELECT relname,
       pg_size_pretty(pg_relation_size(relid)) AS heap,
       pg_size_pretty(pg_total_relation_size(relid)) AS total,
       n_live_tup, n_dead_tup,
       CASE WHEN n_live_tup+n_dead_tup>0
            THEN round(100.0*n_dead_tup/(n_live_tup+n_dead_tup),1) END AS pct_dead,
       n_tup_del, autovacuum_count,
       to_char(last_autovacuum,'MM-DD HH24:MI') AS last_autovac
  FROM pg_stat_user_tables
 WHERE schemaname='public' AND pg_relation_size(relid) > 100*1024*1024
 ORDER BY pg_relation_size(relid) DESC;
-- READ IT THIS WAY: a LOW pct_dead with a LARGE heap is free-space bloat and
-- autovacuum will never fix it. A HIGH pct_dead would be a different problem
-- with a different fix. On 2026-09-19 every row read the first way.

-- C. How much work the purge has to do: engine-class tables it must walk.
SELECT class, count(*) AS tables
  FROM public.ottoq_run_scope_registry GROUP BY class ORDER BY 2 DESC;
-- Expected 2026-09-19: evidence 176, engine 47, stamp 3, run_ledger 2.

-- D. THE NEXT MEASUREMENT, not yet taken. Time the purge alone, so claim 1
--    above stops being an inference:
--      \timing on
--      BEGIN; SELECT ottoq_purge_prior_runs(<a scratch run id>); ROLLBACK;
--    and compare against a start whose purge has nothing to delete.
