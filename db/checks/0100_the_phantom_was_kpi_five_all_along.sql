-- =====================================================================
-- 0100  The phantom was KPI 5 all along
-- =====================================================================
-- CORRECTION TO db/checks/0098 SECTION 4, appended here rather than
-- rewritten there, per db/canons/README.md. 0098 recorded ~5.4 s of the
-- CLI's 6.9 s as UNATTRIBUTED and refused to name a cause:
--
--   "I do not know what the remaining time is. ... Recorded as an open
--    question rather than a plausible story, because a plausible story
--    about performance is how a 22-second view survived this long."
--
-- That was the right call and the question is now CLOSED by measurement.
-- It was KPI 5 the whole time.
--
-- SECTION 1 — THE INDEX
-- ---------------------------------------------------------------------
-- KPI 5 joins ottoq_itinerary_legs on (sim_run_id, vehicle_id). The
-- closest index was idx_itin_legs_vehicle (vehicle_id, status), so:
--
--   Index Scan using idx_itin_legs_vehicle
--     Index Cond: (vehicle_id = d.vehicle_id)
--     Filter:     (... AND sim_run_id = <run>)
--     Rows Removed by Filter: 3,065      x 118 loops
--
-- ~362,000 index entries traversed to return 531 rows. The other
-- candidate, idx_itin_legs_run_live (sim_run_id, status) WHERE status IN
-- ('planned','active'), is PARTIAL on a status this query never
-- constrains, so it was unusable - the same trap 0187 hit on
-- ottoq_events, where a partial index looked available and was not.
--
-- 0190 adds idx_itin_legs_run_vehicle (sim_run_id, vehicle_id):
--
--   Index Cond: ((sim_run_id = <run>) AND (vehicle_id = d.vehicle_id))
--   Rows Removed by Filter: 2
--
--   KPI 5 view      378.7 ms  ->    1.664 ms     (~228x)
--   ottoq_kpi_five  6,934 ms  ->   50.9 ms
--
-- SECTION 2 — WHY THE GAP LOOKED LIKE A PHANTOM
-- ---------------------------------------------------------------------
-- 0098 reasoned: KPI 5 measures 356-378 ms standalone, ottoq_kpi_five
-- reads it four times, so ~1.5 s of the 6.9 s is accounted and ~5.4 s is
-- not. Every step of that arithmetic was correct and the conclusion was
-- wrong, because the input was.
--
-- The index removed 6,883 ms from the CLI and touched NOTHING but KPI 5.
-- So the four reads were costing ~1,720 ms each, not 356-378 ms - the
-- standalone measurement understated in-function cost by about 4.5x.
--
-- The likeliest reason is cache: an isolated EXPLAIN ANALYZE re-runs a
-- query whose ~362,000 index entries the immediately preceding identical
-- query just warmed, while four reads inside one function call do not get
-- that gift. LIKELIEST, not established - what is measured is the
-- 6,883 ms and that only KPI 5 changed.
--
-- THE LESSON, which is the durable part:
--
--   Timing a view in isolation and multiplying by its call count is not a
--   measurement of the caller. Here it was 4.5x low and sent me hunting a
--   phantom that did not exist.
--
-- The same discipline that made 0098 refuse to invent a cause is what let
-- this be checked rather than argued: the open question stayed open, in
-- writing, until an experiment closed it.
--
-- SECTION 3 — THE FULL ARC
-- ---------------------------------------------------------------------
--   ottoq_kpi_five, one run:
--
--     before 0187        54,609 ms
--     after  0187         6,934 ms    KPI 4 pushdown restored
--     after  0190            50.9 ms  KPI 5 index
--
--   1,073x from where the evening started, on a command whose numbers
--   nobody could previously have waited for.
--
-- NO VALUE MOVED. An index cannot change a result, and the KPI 5 checksum
-- is asserted anyway: e6c7983378589856da7f66ca53398fab, identical.
--
-- SECTION 4 — THE COST, because an index is never free
-- ---------------------------------------------------------------------
--   5,856 kB against 161 MB of table (3.4%); table now 167 MB
--   fifth index on ottoq_itinerary_legs
--   355,898 legs across 601 runs, ~590 per run
--
-- Every leg insert now maintains one more btree. That is the trade: a few
-- microseconds per insert against 6.9 seconds per KPI call. If
-- leg-insert throughput ever becomes the constraint this index is the
-- first thing to re-examine, and the way to do that is to measure insert
-- cost with and without it - not to reason about it, which is what
-- produced the phantom above.
--
-- SECTION 5 — STILL OPEN
-- ---------------------------------------------------------------------
-- - KPI 1's date_trunc resolves in the SESSION timezone; day keys are
--   zone-dependent. Needs a canonical bucket zone - definitional.
-- - KPI 2's points_used denominator - definitional, undecided on purpose.
-- - KPI 4's turns filter is still an inline COPY of KPI 2's; they agree
--   today only because both were corrected.
-- - CLAUDE.md Part 3 row counts are stale (ottoq_events 20,799 -> ~2.49M;
--   the file itself says it was verified 2026-08-18).
-- - The rules-layer gap: 9 of 29 active rules never evaluate, 6 of them
--   block-severity, because the engine announces decisions but never
--   state transitions.
-- - The pg_cron stall mechanism (round 12) is still unnamed.
-- =====================================================================

-- §1 — the plan must show BOTH columns as index conditions. A Filter on
-- sim_run_id here means the composite index was lost again.
EXPLAIN (ANALYZE, TIMING OFF, SUMMARY ON)
SELECT p95_time_to_service_min, dispatches_total
  FROM public.ottoq_kpi_p95_time_to_service
 WHERE sim_run_id = '85034701-a556-4853-b148-b8d40c35b490';

-- §3 — the CLI end to end. 54,609 -> 6,934 -> 50.9 ms.
EXPLAIN (ANALYZE, TIMING OFF, SUMMARY ON)
SELECT public.ottoq_kpi_five('85034701-a556-4853-b148-b8d40c35b490'::uuid);

-- §3 — no value moved. Must equal e6c7983378589856da7f66ca53398fab.
SELECT md5(string_agg(sim_run_id::text||'|'||coalesce(p95_time_to_service_min::text,'N')||'|'||returns_measured||'|'||
           returns_unserved||'|'||coalesce(p50_time_to_service_min::text,'N')||'|'||
           coalesce(max_time_to_service_min::text,'N')||'|'||returns_deferred_beyond_horizon,
           E'\n' ORDER BY sim_run_id)) AS kpi5_checksum
  FROM public.ottoq_kpi_p95_time_to_service WHERE dispatches_admitted > 0;

-- §4 — the cost, and that the index is valid
SELECT pg_size_pretty(pg_relation_size('public.idx_itin_legs_run_vehicle'))  AS index_size,
       pg_size_pretty(pg_total_relation_size('public.ottoq_itinerary_legs')) AS table_total,
       (SELECT count(*) FROM pg_index WHERE indrelid='public.ottoq_itinerary_legs'::regclass) AS indexes_on_legs,
       (SELECT indisvalid FROM pg_index WHERE indexrelid='public.idx_itin_legs_run_vehicle'::regclass) AS is_valid;
