-- 0429  **What the 23 GB hold, what may go, and the tests that decided it.**
--        Chase, 2026-10-09, 1:45 PM CT: clear out "truly unnecessary or useless items ... old simulation or run data that
--        becomes stale the second a new run has started", for storage and speed; "If it even closely resembles production
--        data or something that pertains to active runs or intelligence, do not delete." Then, approving the plan: "Be
--        extremely cautious and test when needed. If anything breaks, revert it and go around it. Leave Hermes and MVP
--        alone."
--
--        Written 2026-10-09, 1:50-4:00 PM CT, against otto-q-core (gxdrcyphqjzjsuhxuqtg) only. The MVP project, Hermes's
--        intelligence_events and the paused Fleet Dashboard were measured once and not touched. Nothing in this file
--        deletes anything: every figure is a read, and every rehearsal ended in a forced rollback. The changes it led to
--        are db/migrations/0645 and 0646, tested by tests/test_run_purge_sql.py.
--
-- ══ §1 WHERE THE SPACE IS (reproduce: (1)) ══
--
--   24,993,959,059 bytes at 18:51 UTC (1:51 PM CT). The 50 class-'engine' tables (run-scoped working data, "must not
--   outlive its run") hold 22 GB; the 94 evidence tables 220 MB; the stamp and run-ledger tables 173 MB.
--
--     table                         size      class      what reads it after the run           verdict
--     ottoq_rule_evaluations       9.1 GB     engine     nothing that learns or grades (§3)    0250 allow-list: may go
--     ottoq_events                 3.6 GB     engine     the fault model, the hindsight grader  KEEP
--     ottoq_decisions              2.4 GB     engine     audit trail (0250: "its own decision") KEEP
--     ottoq_ocpp_messages          1.2 GB     engine     the charge clock (meter values)         KEEP
--     ottoq_comms_messages         1.1 GB     engine     nothing                                0250 allow-list: may go
--     ottoq_decision_snapshots     0.9 GB     engine     anti-cheat frames                      KEEP
--     ottoq_stall_bookings         0.7 GB     engine     KPI 2/4 of that run; the challenger    0250 allow-list: may go
--     vehicle_state_log            0.7 GB     unregistered  the production API (otto-q-api)      KEEP
--     ottoq_recall_decisions       0.7 GB     engine     the C9 ledger (0250 protected)         KEEP
--     ottoq_variability_cards      0.6 GB     engine     nothing (a cache of a pure hash)       0250 allow-list: may go
--     ottoq_itinerary_legs         0.2 GB     engine     KPI 5 of that run; 3D playback         0250 allow-list: may go
--     ottoq_bay_binding_witness    0.2 GB     engine     nothing                                0250 allow-list: may go
--
--   Who owns it: 210 runs, every one completed; none purged. Production is 0.0-0.2% of each big table (a 1% block
--   sample per table). ottoq_rule_evaluations by owner: research sweep and experiment arms 74.2%, operator demos 16.2%,
--   certification arms 9.6%, no run 0.0%. Every non-production row is from a run started on or after 2026-09-29.
--
--   Runs that ENDED more than 7 days ago, are archived and not production: 102 at 19:40 UTC (32 sweep arms, 54
--   certification arms, 15 demos, 09-29 to 10-02), 118 at 20:24 UTC as 10-02's runs aged past the line. They carry
--   about 46% of each of the six allow-listed tables -- roughly 5.5 GB. At 48 hours for research and certification
--   runs it would be about 9.2 GB, but that changes the OEM 7-day views (§3e), so 7 days was used.
--
-- ══ §2 WHY IT PILED UP (reproduce: (2)) ══
--
--   (a) cron 625 (ottoq_retention_purge_runs) last deleted a row on 2026-09-19 (ottoq_retention_state 'engine_rows'
--       updated 09:00:10 UTC, 7,351,467 lifetime). Since 2026-09-20 20:16 UTC (3:16 PM CT), when the recert runner (cron
--       746) first ran, every pass returns in about 10 ms: the 0269 round guard matches any ACTIVE cron job whose command
--       names the certification pair, and 746 is always active and names it. db/checks/0204 predicted this latch for a
--       carelessly named purge job; it arrived through a different job. Its in-flight probe could not see 746's pairs
--       either (G194).
--   (b) When 625 did run, 09-15, 09-16 and 09-17 each ended at exactly 2:00 with "canceling statement due to statement
--       timeout": the server's statement_timeout is 2 minutes and cron inherits it, so the 300-second budget never fit.
--   (c) The twin's start door stopped purging: edge-functions/otto-twin-control moved to ottoq_operator_start_run, which
--       does not call ottoq_purge_prior_runs, to stay inside PostgREST's timeout.
--   (d) cron 11 (the 7-day wall-clock worker) spent its whole 90-second budget on events on 10-08 and 10-09 and never
--       reached ottoq_rule_evaluations, whose rows from 09-29 are still there.
--
-- ══ §3 WHAT THE LEARNING, THE GRADERS AND THE DASHBOARDS READ -- MEASURED, NOT INFERRED (reproduce: (3)) ══
--
--   A deletion rehearsal was not possible: the Supabase connector holds every DELETE for a person's confirmation (even
--   `DELETE ... WHERE false`), and each attempt timed out unexecuted -- confirmed after each one: no run stamped, the
--   sample run's 63,266 comms rows intact. So the dependency was measured directly instead, with
--   pg_stat_xact_user_tables: run a function in a transaction, then read which tables that transaction touched.
--
--     (a) ottoq_charge_time_v2_params (the charge clock), through 2026-10-03 over 5 days -- the window the doomed runs
--         occupy, where 11,608 of 14,877 charge-ledger rows come from 48 doomed runs: the six tables 0 rows; it read
--         ottoq_ocpp_messages 1,016,547, ottoq_charge_duration_ledger 132,660, vehicles 3,686.
--     (b) ottoq_return_model_params and ottoq_charge_fault_params, over that window and over 21 days through
--         2026-10-09 18:00 UTC: the six tables 0; they read ocpp_sessions 304,452, ottoq_visit_needs 215,848,
--         ottoq_vehicle_dispatches 215,837, ottoq_events, the ledgers.
--     (c) ottoq_arbiter_self_assessment_v3 (7 days), the three active experiments' verdicts, ottoq_charge_order_realized
--         and ottoq_charge_order_grade_compute (order 741): the six tables 0.
--     (d) Verdicts and sweep scores read stored metrics (ottoq_dial_pair_ledger.metrics_a/_b,
--         ottoq_throughput_sweep_arms.scorecard); ottoq_dial_arm_metrics runs once, when the arm runs.
--     (e) The OEM views read rule evaluations over the last 7 days / 24 hours by wall clock. The newest evaluation of any
--         run that ended more than 7 days ago was 2026-10-02 20:21:42 UTC, against a window opening at 20:24:28, and no
--         run writes an evaluation after it ends: so a 7-day cutoff by END time can never remove a row they show.
--     (f) The challenger's free-charger check (Q2) reads held/active bookings at the depot with no run filter: no finished
--         run holds one (0 rows), so a purge cannot change it.
--     (g) purged_at is read by ottoq_kpi_five (a 'purged' block: nulls mean GONE, not zero), ottoq_twin_kpi_board, and --
--         the one that shaped 0645 -- ottoq_charge_order_grade_pending and ottoq_charge_order_regrade, which refuse a
--         stamped run. No doomed run has a charge order today (the first snapshot is 2026-10-08 13:54 UTC), but from
--         10-15 one would; so 0645 keeps a run carrying charge orders for 21 days, the window the nightly fits read.
--     (h) The canon's boot fingerprint counts foreign rows in live states only (bookings held/active/interrupted, legs
--         planned/active/in_progress, dispatches, visit needs). The doomed runs hold 0 and 0 of the two the purge
--         touches, so purging them cannot rebase a canon (G46, db/checks/0191).
--     (i) No foreign key with ON DELETE CASCADE points into any of the six tables; the only DELETE triggers on them are
--         the engine's append-only guards, released by ottoq.retention = 'on'.
--
--   So the six 0250 seeds are exactly the safe set once ottoq_events is taken out of it, and nothing that learns, grades,
--   reviews or runs an experiment reads them.
--
-- ══ §4 THE CHANGE ══
--
--   0645 (the run purge): the round guard ignores the recert runner (matched by its advisory-lock key); the in-flight
--   probe is ottoq_certification_in_flight(false) at the start and before every batch; doomed means ENDED more than 7
--   days ago, not running or paused, archived, not production_live, and -- with charge orders -- ended more than 21 days
--   ago; ottoq_events leaves the allow-list; cron 625 runs hourly 04:17-11:17 UTC (11:17 PM-6:17 AM CDT) at 100 s.
--   0646 (the wall-clock worker): its rule-evaluation walk spares running and production_live runs, as its events walk
--   always has. The production run c4ee1572 (2026-10-09, 877 evaluations) would otherwise go on or after 10-17.
--
--   The diff of 0645's body against the live one is five hunks and nothing else: one variable; the guard clause
--   `AND j.command NOT ILIKE '%ottoq_recert_runner%'`; the probe; the doomed-set predicates; the labelled loop and its
--   per-batch exit. 0646's is one predicate. Both bodies were built from base64 of pg_get_functiondef (md5 890d2de1...
--   and dff3b880...) and are asserted by md5 after the apply.
--
--   tests/test_run_purge_sql.py executes both against those live bodies (12 tests): the latch reproduces before 0645;
--   after it, of eleven seeded runs the four doomed ones lose exactly their six-table rows and keep their events, and
--   production, running, paused, ended-2-days-ago, ended-1-day-ago, unarchived and 10-day-old-with-charge-orders runs
--   are untouched; ottoq_sim_runs keeps every row; a certification in flight stops it at the start, and one starting
--   mid-purge stops it after the batch in hand. Mutation-checked: put ottoq_events back on the allow-list and the
--   doomed run's events go (the test requires 7, it would read 0); drop the ended_at predicate and the run that ended 2
--   days ago is purged (it would read 0 for 7).
--
-- ══ §5 THE BASELINE TO RE-CHECK AFTER THE PURGE (reproduce: (5)), measured 20:05-20:08 UTC ══
--
--     learning, at fixed T (deterministic: the same md5 at 19:13 and 20:06 UTC)
--       ottoq_charge_time_v2_params (twin, '2026-10-03', 5 days, 3)   4ba080af2bacd31cfe3edad1e22f9513
--       ottoq_return_model_params   (twin, '2026-10-03', 5 days)      3d7029c7d5d08a56ab8f2f978e452ef0
--       ottoq_charge_fault_params   (twin, '2026-10-03', 5 days)      370cbb7244e7713b0b218ee3950c5ad6
--       ottoq_charge_fault_params   (twin, '2026-10-09 18:00', 21 days)  1be54cee2f59add8f5cac622d7c556fc
--       ottoq_return_model_params   (twin, '2026-10-09 18:00', 21 days)  2bd086b30a37a3eee1ecba181bfd245a
--     verdicts: 82c5568b 98b81cf0db157b76933f7e74e5725e03, f2120031 171ad0ca80f54bbf023043e54deca632,
--               04e101de ade287a1449f3cf9e61df95e3f95b50d (change only if a new pair is recorded)
--     ottoq_kpi_five, production runs: 3eeb5dc5 d1d02498..., b54929ce a78606e4..., 35aa33e3 959d1271...,
--       aced4889 14de311a..., 237029f1 0ae0ffbd..., f653bef9 15407649..., fef8cc01 cdd2de6e..., c4ee1572 8f0d96bb...;
--       e8a0ba01 already raises "field name must not be null" (§6e). Kept runs: 72b09010 81b9b9f8..., 64251eb8
--       311c011e..., 63cdee1b cf55ab58..., aaa92496 f596eef4..., b0d0982f a6b0addf..., 15cd2e23 3d9a7742...,
--       244f3075 b609c711.... Doomed sample ae8a4908 12a21eb6... (after: its 'purged' block, by design).
--     production rows in the six tables: rule evaluations 877, comms 128, bookings 246, cards 764, legs 458, witness 406.
--     n_tup_del outside the six tables, by class: evidence (92 tables) 350, run_ledger 4,873, stamp 816,199.
--
-- ══ §6 FOUND, NOT CHANGED -- FOR CHASE ══
--
--   (a) The fault model already learns repair times from 61% of its window: of 2,572 faulted charges in its 21 days,
--       1,558 still have their charge.session_faulted event. 596 went with runs deleted before 09-29; 418 are gone from
--       runs that still exist, most likely to cron 11, which judges an event's age by the SIM clock (research arms run
--       on a 2026-09-01 clock, so their events are "old" the day they are written). Fixing it changes cron 11's events
--       walk, which house rule 3 keeps out of a cleanup.
--   (b) Rows with no run (sim_run_id IS NULL), which the engine_rows policy's own note calls production rows, are
--       deleted by cron 11 after 7 days by design. 0646 leaves that as it is; whether production retention should be
--       longer is a decision.
--   (c) ottoq_start_demo_run still calls ottoq_purge_prior_runs, which deletes EVERY non-production run's rows in every
--       engine table, ottoq_events and ottoq_ocpp_messages included. No cron job and no function calls it except
--       ottoq_start_busy_run (called only by ottoq_start_busy_run_once), and the twin's start door calls
--       ottoq_operator_start_run instead; every run since 09-29 still holds its rows. But ottoq_purge_prior_runs,
--       ottoq_start_busy_run and ottoq_start_busy_run_once are executable by `authenticated` (has_function_privilege,
--       21:10 UTC), so one request from any signed-in caller would erase the 21 days the nightly fits learn from.
--   (d) ottoq_incident_reports (0 rows) has no run column, so cron 11 would take a production incident after 7 days.
--   (e) ottoq_kpi_five raises "field name must not be null" for production run e8a0ba01 (2026-08-30). Pre-existing.
--   (f) Kept, though old: up to ~3 GB of research rows in ottoq_decisions, ottoq_decision_snapshots,
--       ottoq_vehicle_commands, ottoq_recall_decisions and ottoq_telemetry_packets (0250 named each as needing its own
--       decision); 167 scratch tables (57 MB, many cited certification evidence); vehicle_state_log.
--   (g) Space comes back to the disk only by rewriting the tables (VACUUM FULL takes each table's ACCESS EXCLUSIVE lock;
--       the booking calendar's three exclusion constraints cannot be rebuilt concurrently -- PostgreSQL 17 docs,
--       sql-reindex, fetched 2026-10-09), and Supabase shrinks the billed disk only at a project upgrade
--       (supabase.com/docs/guides/troubleshooting/disk-size-not-shrinking-after-deleting-data-135390, fetched
--       2026-10-09). Without that, freed space is reused and the database stops growing.
--   (h) Pure dead space, no data: vehicles is a 74 MB file holding about 0.3 MB of rows and has been sequentially
--       scanned 225,478 times; stalls 6 MB for 0.1 MB; ottoq_ocpp_chargers 6.8 MB for 39 kB; net._http_response 94 MB for
--       0.8 MB; cron.job_run_details 244 MB, 171,341 of its 290,682 rows older than 30 days, read by no function.
--
-- ══ §7 DONE IN THIS SESSION, NO ROW DELETED (reproduce: (7)) ══
--
--   VACUUM (FULL, SKIP_LOCKED, ANALYZE), one table at a time, 21:00:57-21:01:42 UTC (4:00-4:02 PM CT), with no run active and no certification
--   in flight; SKIP_LOCKED so it would skip rather than queue behind anything. Each keeps every row:
--     stalls                 7,952 kB -> 328 kB     330 rows before and after
--     ottoq_ocpp_chargers    8,504 kB -> 112 kB      94 rows before and after
--     vehicles                  83 MB -> 544 kB     226 rows before and after (heap 74 MB -> 344 kB)
--   net._http_response belongs to supabase_admin and was left to Supabase. Plain VACUUM is not held for confirmation
--   by the connector; DELETE is, which is why 0645 and 0646 are written and committed but wait for Chase to apply.

-- ══ queries ══

-- (1) Sizes, and the run census
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_total;
SELECT c.relname, pg_size_pretty(pg_total_relation_size(c.oid)) AS total, s.n_live_tup, s.n_tup_ins, s.n_tup_del
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
 ORDER BY pg_total_relation_size(c.oid) DESC LIMIT 25;
SELECT run_by, status, count(*), min(started_at)::date, max(started_at) FROM public.ottoq_sim_runs GROUP BY 1, 2 ORDER BY 1, 2;

-- (2) The latch, and its history
SELECT jobid, jobname, active, command ILIKE '%ottoq_determinism_pair%' AS matches_the_round_guard,
       command ILIKE '%ottoq_recert_runner%' AS is_the_recert_runner
  FROM cron.job ORDER BY jobid;
SELECT jobid, status, start_time, end_time - start_time AS took, left(return_message, 120)
  FROM cron.job_run_details WHERE jobid IN (625, 746) ORDER BY start_time DESC LIMIT 20;
SELECT * FROM public.ottoq_retention_state;

-- (3) What a learning function touches: run it, then read this transaction's own counters
DO $counters$
DECLARE v jsonb;
BEGIN
  PERFORM public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, '2026-10-03 00:00+00', interval '5 days');
  PERFORM public.ottoq_charge_fault_params('11111111-1111-1111-1111-111111111111'::uuid, '2026-10-03 00:00+00', interval '5 days');
  SELECT jsonb_object_agg(relname, coalesce(seq_tup_read, 0) + coalesce(idx_tup_fetch, 0)) INTO v
    FROM pg_stat_xact_user_tables WHERE seq_scan > 0 OR coalesce(idx_scan, 0) > 0
       OR relname IN ('ottoq_rule_evaluations', 'ottoq_comms_messages', 'ottoq_stall_bookings', 'ottoq_variability_cards',
                      'ottoq_itinerary_legs', 'ottoq_bay_binding_witness');
  RAISE NOTICE 'tables touched: %', v;
END $counters$;

-- (4) What is purgeable now, under 0645's predicate, and the canon condition
WITH doomed AS (
  SELECT sr.sim_run_id, sr.run_by FROM public.ottoq_sim_runs sr
   WHERE sr.status NOT IN ('running', 'paused') AND COALESCE(sr.run_by, '') <> 'production_live'
     AND sr.started_at < now() - interval '7 days' AND COALESCE(sr.ended_at, sr.started_at) < now() - interval '7 days'
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id)
     AND (COALESCE(sr.ended_at, sr.started_at) < now() - interval '21 days'
          OR NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_snapshots s WHERE s.sim_run_id = sr.sim_run_id)))
SELECT (SELECT count(*) FROM doomed) AS runs,
       (SELECT count(*) FROM public.ottoq_stall_bookings b WHERE b.sim_run_id IN (SELECT sim_run_id FROM doomed)
           AND b.state IN ('held', 'active', 'interrupted')) AS live_bookings,
       (SELECT count(*) FROM public.ottoq_itinerary_legs l WHERE l.sim_run_id IN (SELECT sim_run_id FROM doomed)
           AND l.status IN ('planned', 'active', 'in_progress')) AS live_legs;

-- (5) The baseline, re-run after the purge (each must equal §5)
SELECT md5(public.ottoq_charge_fault_params('11111111-1111-1111-1111-111111111111'::uuid, '2026-10-09 18:00+00', interval '21 days')::text) AS fault_full,
       md5(public.ottoq_charge_fault_params('11111111-1111-1111-1111-111111111111'::uuid, '2026-10-03 00:00+00', interval '5 days')::text) AS fault_doomed,
       md5(public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, '2026-10-03 00:00+00', interval '5 days')::text) AS return_doomed;
SELECT md5(public.ottoq_charge_time_v2_params('11111111-1111-1111-1111-111111111111'::uuid, '2026-10-03 00:00+00', interval '5 days', 3)::text) AS clock_doomed;
SELECT r.sim_run_id, md5(public.ottoq_kpi_five(r.sim_run_id)::text) FROM public.ottoq_sim_runs r
 WHERE r.run_by = 'production_live' AND r.sim_run_id <> 'e8a0ba01-56e3-4138-9479-f2639ef86a67' ORDER BY r.started_at;
SELECT coalesce(g.class, 'unregistered') AS class, sum(s.n_tup_del)
  FROM pg_stat_user_tables s
  LEFT JOIN (SELECT DISTINCT table_name, class FROM public.ottoq_run_scope_registry WHERE table_schema = 'public') g
         ON g.table_name = s.relname
 WHERE s.schemaname = 'public' AND g.class IN ('evidence', 'run_ledger', 'stamp') GROUP BY 1 ORDER BY 1;

-- (7) The three compacted tables
SELECT c.relname, pg_size_pretty(pg_total_relation_size(c.oid)) AS total, s.n_live_tup, s.seq_scan
  FROM pg_class c JOIN pg_stat_user_tables s ON s.relid = c.oid
 WHERE c.oid IN ('public.vehicles'::regclass, 'public.stalls'::regclass, 'public.ottoq_ocpp_chargers'::regclass);
