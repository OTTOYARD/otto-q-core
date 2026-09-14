-- ---------------------------------------------------------------------------
-- 0191 — G23 MEETS G46: THE RETENTION PURGE IS A CANON-REBASING EVENT, AND
-- TURNING IT ON NIGHTLY WITHOUT G46'S FIX GUARANTEES RECURRING FALSE RESETS.
--
-- Found 2026-09-13 05:30 UTC while looking for G23's next step (one observed
-- purge pass, then REINDEX, then cron). The two items are coupled and neither
-- write-up says so.
--
-- G46 (db/checks/0187): the certification canon moved because
-- endst.legs.fgn.n -- a count of OTHER runs' itinerary legs in live states --
-- went 13 -> 9. The nine survivors all belong to run
-- 9291ec6d-12b2-4d44-b4f9-35d47f08e9da (operator_demo, completed 2026-08-29).
--
-- G23: public.ottoq_retention_purge_runs deletes engine rows for runs that are
-- finished, not production, older than the keep interval, and archived.
-- ---------------------------------------------------------------------------

-- 1. THE COLLISION, in one row.
SELECT
  (SELECT keep_interval::text FROM public.ottoq_retention_policy
    WHERE policy_key = 'engine_rows' AND enabled)                        AS keep_interval,
  (SELECT count(*) FROM public.ottoq_retention_engine_allowlist)          AS allowlist_tables,
  (SELECT bool_or(table_name = 'ottoq_itinerary_legs')
     FROM public.ottoq_retention_engine_allowlist)                       AS legs_allowlisted,
  (SELECT class FROM public.ottoq_run_scope_registry
    WHERE table_name = 'ottoq_itinerary_legs' AND table_schema = 'public'
    LIMIT 1)                                                             AS legs_class,
  (SELECT EXISTS (SELECT 1 FROM public.ottoq_run_archives a
                   WHERE a.sim_run_id = '9291ec6d-12b2-4d44-b4f9-35d47f08e9da')) AS residue_run_archived,
  (SELECT status FROM public.ottoq_sim_runs
    WHERE sim_run_id = '9291ec6d-12b2-4d44-b4f9-35d47f08e9da')            AS residue_run_status,
  (SELECT count(*) FROM public.ottoq_sim_runs sr
    WHERE sr.status <> 'running'
      AND COALESCE(sr.run_by,'') <> 'production_live'
      AND sr.started_at < now() - COALESCE((SELECT keep_interval FROM public.ottoq_retention_policy
                                             WHERE policy_key='engine_rows' AND enabled),
                                           interval '48 hours')
      AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id))
                                                                         AS doomed_runs;
-- MEASURED 2026-09-13 05:30 UTC:
--   keep_interval 48:00:00 | allowlist_tables 7 | legs_allowlisted TRUE |
--   legs_class 'engine' | residue_run_archived TRUE | residue_run_status 'completed' |
--   doomed_runs 939
--
-- Read that together: ottoq_itinerary_legs is allow-listed AND class=engine, and
-- the run holding all nine residue legs is finished, not production, three weeks
-- old and archived -- so it is in the doomed set. THE PURGE WILL DELETE THOSE NINE
-- LEGS, endst.legs.fgn.n will go 9 -> 0, AND EVERY FLAGSHIP CANON WILL REBASE
-- AGAIN -- with no engine change, exactly as it did last night.

-- 2. AND IT IS NOT A ONE-OFF. 939 doomed runs, purged in time-budgeted
--    micro-batches, biggest table first. So the residue set will keep changing
--    across passes, which means the canon keeps moving, every night, forever.
SELECT a.table_name,
       g.column_name,
       pg_size_pretty(pg_total_relation_size(('public.' || a.table_name)::regclass)) AS size,
       g.class
  FROM public.ottoq_retention_engine_allowlist a
  LEFT JOIN public.ottoq_run_scope_registry g
         ON g.table_name = a.table_name AND g.table_schema = 'public' AND g.class = 'engine'
 ORDER BY pg_total_relation_size(('public.' || a.table_name)::regclass) DESC;
-- MEASURED 2026-09-13 05:32 UTC (all seven allow-listed, all class=engine, all
-- keyed on sim_run_id):
--   ottoq_rule_evaluations     5657 MB
--   ottoq_events               3441 MB
--   ottoq_stall_bookings       1168 MB
--   ottoq_variability_cards     789 MB
--   ottoq_comms_messages        670 MB
--   ottoq_bay_binding_witness   431 MB
--   ottoq_itinerary_legs        346 MB   <- the residue table, purged LAST
--
-- ~12.5 GB across seven tables, purged biggest first in time-budgeted
-- micro-batches. So the legs table is the LAST thing a pass reaches, and a single
-- 60-second pass will not reach it at all -- which is worse, not better: it makes
-- the canon rebase arrive on some unpredictable later night rather than on the
-- night you ran the purge and were watching.

-- 3. WHAT THE PURGE ALREADY GETS RIGHT, so the fix does not re-litigate it.
--    (Read from the procedure body, public.ottoq_retention_purge_runs.)
--      * advisory lock: two purges cannot overlap;
--      * refuses outright if ottoq_check_run_scope_registry() reports any
--        'block' severity defect;
--      * refuses if the allow-list is not a subset of class='engine';
--      * refuses if an allow-listed table parents a NO ACTION/RESTRICT FK;
--      * SKIPS (does not refuse) while a determinism pair is in flight -- the
--        same pg_stat_activity authority the bridge now uses;
--      * only touches runs that are finished, non-production, past the keep
--        interval and ARCHIVED -- the archive is the reproducibility key, so a
--        purged run can still be re-derived;
--      * stamps the run as purged (0251) so ottoq_kpi_five says "gone", not "zero".
--    None of that is in question. The gap is narrower and it is G46's: the canon
--    comparison cannot tell "the engine changed" from "the janitor ran".

-- ---------------------------------------------------------------------------
-- THE CONSEQUENCE FOR SEQUENCING, which is the point of this file
--
-- BUILD_QUEUE's apply order (written 05:25 UTC, one hour before this was found)
-- had the G46+G48 matrix fix first and round 42 fourth. This file inserts a step
-- and fixes its position:
--
--   1. G46 + G48 matrix fix          <- must be first, unchanged
--   2. ONE OBSERVED PURGE PASS       <- NEW, and it must come AFTER 1 and BEFORE
--                                       round 42, so the residue it removes
--                                       cannot be mistaken for an engine change
--   3. REINDEX, then the nightly cron (G23's remaining steps)
--   4. 0263, 0264
--   5. round 42, on a canon that is stable BECAUSE the janitor already ran
--
-- Doing it in the other order -- purge first, fix later -- costs a round and
-- produces a canon nobody can interpret. Turning on the nightly cron before the
-- fix costs a round EVERY NIGHT the purge reaches a run with live residue.
--
-- AND ONE DESIGN SIMPLIFICATION, handed to G46's migration: candidate (a) in
-- db/checks/0187 proposed a bespoke scoped UPDATE to retire the nine stale legs.
-- It does not need one. The purge is the approved mechanism, it already has all
-- the guards above, and it will retire them as a side effect of doing its job.
-- The migration should therefore fix the INSTRUMENT and let the janitor clean the
-- floor -- which is the smaller change and the one with precedent.
--
-- ===========================================================================
-- CORRECTION 2026-09-13 05:55 UTC — "LET THE JANITOR CLEAN THE FLOOR" IS RIGHT
-- ABOUT THE INSTRUMENT AND WRONG ABOUT THE HAMMER (db/checks/0193).
--
-- The retention purge's doomed set is **939 runs carrying roughly 3.9 million
-- rows** across four tables (measured by the review: 1,133,286 ottoq_events,
-- 915,817 ottoq_stall_bookings, 591,871 ottoq_itinerary_legs, and the rest).
-- Firing an irreversible multi-million-row delete to retire NINE legs is
-- disproportionate, and this file must not be read as recommending it.
--
-- Corrected position: the purge stays the right mechanism for RETENTION, and its
-- collision with the canon (everything above this note) stands unchanged -- it is
-- still a canon-rebasing event and still must not go on a nightly cron before the
-- matrix fix. But THIS residue is retired by a nine-row, depot-scoped, run-scoped,
-- `ROW_COUNT = 9`-asserted UPDATE setting 'planned' -> 'skipped' (the value 0089's
-- janitor uses; NOT 'amended', which is for 'active'). Smaller, reversible in
-- effect, and it cannot reach a second depot -- which the sketch in 0187 could,
-- and did in measurement: 2,301 rows across two depots.
-- ===========================================================================
-- ---------------------------------------------------------------------------
