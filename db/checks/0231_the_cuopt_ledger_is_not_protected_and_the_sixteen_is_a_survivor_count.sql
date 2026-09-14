-- db/checks/0231
-- THE cuOpt LEDGER IS NOT PROTECTED FROM THE PURGE, ITS OWN COMMENT SAYS IT IS,
-- AND "SIXTEEN CALLS" IS A COUNT OF SURVIVORS
--
-- Surfaced by the six-dimension read-only audit 2026-09-14 and then re-measured
-- leg by leg here, because the sentence it invalidates is one CLAUDE.md rule 6
-- calls "the only one to quote."
--
-- ===========================================================================
-- A. THE CLAIM THAT IS FALSE, IN THE TABLE'S OWN COMMENT
--
-- public.cuopt_invocation_log's COMMENT ends:
--
--   "Deliberately NOT named ottoq* so ottoq_purge_prior_runs cannot delete
--    prior-run evidence."
--
-- That protection has never existed. public.ottoq_purge_prior_runs does not
-- match on names at all. It reads the REGISTRY and deletes by dynamic SQL:
--
--   FOR r IN SELECT table_name AS t, column_name AS c
--              FROM public.ottoq_run_scope_registry WHERE class = 'engine' ...
--     EXECUTE format('DELETE FROM public.%1$I WHERE %2$I = ANY($1)', r.t, r.c)
--       USING v_doomed;
--
-- MEASURED: the string 'cuopt' does not appear anywhere in that function's
-- source. And cuopt_invocation_log IS in the registry, class 'engine', whose
-- registry note reads "run-scoped working data; must not outlive its run."
--
-- So the table is not merely reachable by the purge -- it is REGISTERED FOR
-- DELETION, while its comment tells the reader it is safe. A naming convention
-- was relied on to defeat a mechanism that does not read names.
--
-- Same defect class as everything else this build has cost itself: a guard
-- that answers a different question than the one being asked. 0098 (a stale
-- row count), 0137/0139/0216 (a hash over the wrong bytes), 0145/0146 (an
-- unscoped read), 0296 (a regex blind to its own call sites), 0304 (a bound
-- read at the wrong expression). This one is a COMMENT that documents a
-- defence rather than implementing one.
--
-- ===========================================================================
-- B. WHAT WAS MEASURED, 2026-09-14 (each figure re-run for this file)
--
--   registry class for cuopt_invocation_log        engine   <- purgeable
--   'cuopt' appears in ottoq_purge_prior_runs      false    <- name-independent
--   ottoq_purge_prior_runs has a live caller       public.ottoq_start_demo_run
--   in the NIGHTLY retention allowlist             NO (that list holds 7 tables)
--
--   pg_stat_user_tables n_tup_ins                  48,897
--   pg_stat_user_tables n_tup_del                  63,755
--   max(invocation_id)                             48,897
--   allocated ids ABSENT from the table            28,262
--   rows carrying an http_status (NVIDIA reached)  16
--
--   earliest SURVIVING called_at in the ledger     2026-08-02 04:05:28.173842+00
--   earliest fired_at in ottoq_cuopt_fire_log      2026-07-18 05:40:00.244949+00
--   ottoq_cuopt_fire_log rows                      442
--
-- The last pair is the independent witness and it is the one that settles it:
-- a SECOND table records cuOpt firings fifteen days EARLIER than anything that
-- survives in the invocation ledger. The ledger has lost its own early history.
--
-- ONE PRECISION THE AUDIT GOT RIGHT AND THIS FILE KEEPS: 28,262 is ALLOCATED
-- IDS ABSENT, not rows deleted. nextval is non-transactional and
-- public.cuopt_log_gate's INSERT sits inside an EXCEPTION handler, so an
-- aborted insert also burns an id. n_tup_del = 63,755 is what proves
-- large-scale deletion; the gap count alone does not attribute all 28,262 to
-- the purge.
--
-- AND ONE MECHANISM CORRECTION: the NIGHTLY job is not the deleter. cron 625
-- runs ottoq_retention_purge_runs, which joins the registry to
-- ottoq_retention_engine_allowlist -- 7 tables, and cuopt_invocation_log is
-- not one of them. The deleter is the DEMO-RUN path:
-- ottoq_start_demo_run -> ottoq_purge_prior_runs.
--
-- ===========================================================================
-- C. THEREFORE THE HONEST SENTENCE IS NOT THE ONE IN THE BRIEF
--
-- CLAUDE.md rule 6 currently instructs that this is the only sentence to
-- quote:
--
--   "cuOpt was called sixteen times in this engine's life, returned 136
--    proposals, and has not been called since 2026-08-30."
--
-- "In this engine's life" is the false part. Sixteen is a count of rows that
-- SURVIVE in a ledger registered for deletion and demonstrably purged, whose
-- earliest surviving row postdates a sibling log by fifteen days.
--
-- WHAT MAY BE SAID, and it is still a strong sentence:
--
--   "Sixteen calls to the NVIDIA endpoint survive in the invocation ledger,
--    the last on 2026-08-30. The true lifetime count is AT LEAST sixteen and
--    is not recoverable from this table: it is registered as run-scoped engine
--    data and the demo-run purge has deleted from it, leaving 28,262 allocated
--    ids absent and no surviving row older than 2026-08-02 -- while
--    ottoq_cuopt_fire_log still holds firings from 2026-07-18."
--
-- WHAT MAY NOT BE SAID: any lifetime total, in either direction. Rule 6
-- forbids unquantified cuOpt claims "in both directions," and a purged ledger
-- makes the low direction unquantifiable too. "cuOpt has barely been used" is
-- now as unsupported as "cuOpt is heavily used."
--
-- ===========================================================================
-- D. THE FIX, AND WHY IT IS NOT IN THIS FILE
--
-- The registry already has the right class: 'evidence'. Eleven cuopt-related
-- tables are registered, and EIGHT of them are already 'evidence'
-- (cuopt_supply_proof_*, phase7/10/11_cuopt_log_*, p12_contaminated_*). The
-- three that are 'engine' -- cuopt_invocation_log, ottoq_cuopt_fire_log,
-- ottoq_cuopt_deferrals -- are the three that are actually load-bearing, and
-- the ledger among them is the one we quote outward.
--
-- Moving cuopt_invocation_log to 'evidence' would stop the deletion in one
-- row of one table. IT IS NOT DONE HERE because it is a behaviour change with
-- a real risk that must be measured first: prior-run rows would start
-- surviving, and if ANY cuOpt reader is unscoped it would then see them. That
-- is precisely the 0145/0146 defect class, and this build has already paid for
-- assuming scoping rather than checking it. The reader audit belongs in the
-- cuOpt cut window (task #116), where those readers are being removed anyway
-- and the scoping question answers itself.
--
-- What IS safe and should ship with that window: delete the false sentence
-- from the table COMMENT, whatever else is decided. A comment that documents a
-- defence which does not exist is worse than no comment.
--
-- ===========================================================================
-- E. RE-MEASURE

SELECT 'registry class (engine = purgeable)' AS leg,
       g.table_name, g.column_name, g.class::text AS class
  FROM public.ottoq_run_scope_registry g
 WHERE g.table_name IN ('cuopt_invocation_log','ottoq_cuopt_fire_log','ottoq_cuopt_deferrals')
 ORDER BY g.table_name;

SELECT 'purge names cuopt?' AS leg,
       (position('cuopt' in p.prosrc) > 0) AS mentions_cuopt,
       (position('DELETE FROM public.%1$I WHERE %2$I = ANY($1)' in p.prosrc) > 0) AS deletes_dynamically
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_purge_prior_runs';

SELECT 'the false comment is still there' AS leg,
       (obj_description('public.cuopt_invocation_log'::regclass,'pg_class')
          LIKE '%Deliberately NOT named ottoq%') AS still_claims_protection;

SELECT 'ledger integrity' AS leg,
       (SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='cuopt_invocation_log') AS inserts,
       (SELECT n_tup_del FROM pg_stat_user_tables WHERE relname='cuopt_invocation_log') AS deletes,
       (SELECT max(invocation_id) FROM public.cuopt_invocation_log)                      AS max_id,
       (SELECT count(*) FROM public.cuopt_invocation_log)                                AS rows_now,
       (SELECT count(*) FROM public.cuopt_invocation_log WHERE http_status IS NOT NULL)  AS nvidia_calls_surviving;

SELECT 'the independent witness' AS leg,
       (SELECT min(called_at) FROM public.cuopt_invocation_log) AS ledger_earliest,
       (SELECT min(fired_at)  FROM public.ottoq_cuopt_fire_log) AS fire_log_earliest,
       (SELECT min(called_at) FROM public.cuopt_invocation_log)
         - (SELECT min(fired_at) FROM public.ottoq_cuopt_fire_log) AS history_lost;
