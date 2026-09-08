-- ---------------------------------------------------------------------------
-- 0128 — the first per-pair I/O profile this project has ever taken. The pair
--        reads 9.6 GB from disk and 7.0 GB of it is FIVE sequential scans of
--        ottoq_events.
--
-- Measured, not inferred: pg_stat_user_tables and pg_statio_user_tables were
-- snapshotted into public.g19_seq_before / public.g19_io_pref at
-- 2026-09-08 10:00:53 UTC with nothing running, and differenced after round
-- 25's pair f (busy_day / 424242 / 24 ticks, flagship) committed at ~10:34.
-- The window contains that one pair plus ~22 minutes of the usual background
-- cron (metronome every 60 s, depot tick and run governor every 120 s).
--
-- THE COUNTERS DO NOT MOVE WHILE A PAIR RUNS. Both arms are one transaction and
-- pgstat flushes at commit, so a mid-pair delta of zero means nothing. This
-- caught me out at 10:15 and is why the reading protocol went into
-- db/canons/round25.md before the numbers existed.
-- ---------------------------------------------------------------------------

-- Q1. THE WHOLE PAIR, IN SIX NUMBERS.
--
--       disk blocks read      1,227,704   =  9,591 MB
--         heap                1,148,828
--         index                  78,876
--       buffer hits           228,017,784
--         heap                 97,700,314
--         index               130,317,470
--       index scans            66,411,075
--       sequential scans           11,197
--
--     66 MILLION index scans in one pair — 1.4 million per tick-execution
--     across 24 ticks and two arms. That is the shape of the engine: enormous
--     numbers of tiny lookups. It is NOT where the time goes.
SELECT sum(io.heap_blks_read - b.heap_blks_read)                                    AS heap_read,
       sum(COALESCE(io.idx_blks_read,0) - COALESCE(b.idx_blks_read,0))              AS idx_read,
       pg_size_pretty((sum(io.heap_blks_read - b.heap_blks_read)
                     + sum(COALESCE(io.idx_blks_read,0)
                         - COALESCE(b.idx_blks_read,0)))::bigint * 8192)            AS disk_read,
       sum(io.heap_blks_hit - b.heap_blks_hit)                                      AS heap_hit,
       sum(COALESCE(io.idx_blks_hit,0) - COALESCE(b.idx_blks_hit,0))                AS idx_hit,
       sum(n.seq_scan - s.seq_scan)                                                 AS seq_scans,
       sum(n.idx_scan - s.idx_scan)                                                 AS idx_scans
FROM pg_statio_user_tables io
JOIN public.g19_io_pref  b ON b.relid = io.relid
JOIN pg_stat_user_tables n ON n.relid = io.relid
JOIN public.g19_seq_before s ON s.relid = io.relid;

-- Q2. AND WHERE THE 9.6 GB GOES. THIS IS G19.
--
--       table                     disk read   seq scans   idx scans   heap size
--       ottoq_events                7,040 MB          5          62    2,956 MB
--       ottoq_visit_needs             609 MB          4      45,744      183 MB
--       ottoq_stall_bookings          576 MB          4     316,364      417 MB
--       ottoq_itinerary_legs          537 MB          4      29,432      165 MB
--       space_conflict_ledger         201 MB         32           0      100 MB
--       ottoq_rule_evaluations        168 MB          0          60    4,238 MB
--       ottoq_vehicle_dispatches       79 MB          4      17,089       81 MB
--
--     **73% of the pair's disk reads are five sequential scans of one table.**
--     Five scans of a 2,956 MB heap is ~15 GB of logical reads, of which 7 GB
--     missed the 1 GB shared_buffers. Everything else is rounding.
--
--     And that is the drift, exactly: the workload is fixed — same seed, same
--     scenario, same tick count — but ottoq_events GROWS, so the cost of
--     scanning it five times grows with it, monotonically, in calendar time.
--     Same defect class as db/checks/0098 and 0123: a query whose cost is set
--     by history rather than by the run. This one is inside the certification
--     pair itself.
--
--     Note what is NOT here. ottoq_rule_evaluations is the biggest table in the
--     database at 4,238 MB and the pair reads 168 MB from it across ZERO
--     sequential scans. Size alone was never the predictor; being scanned is.
SELECT n.relname,
       pg_size_pretty(((io.heap_blks_read - b.heap_blks_read)
                     + (COALESCE(io.idx_blks_read,0)
                      - COALESCE(b.idx_blks_read,0)))::bigint * 8192) AS disk_read,
       (n.seq_scan - s.seq_scan) AS seq_scans,
       (n.idx_scan - s.idx_scan) AS idx_scans,
       pg_size_pretty(pg_table_size(io.relid)) AS heap_size
FROM pg_statio_user_tables io
JOIN public.g19_io_pref  b ON b.relid = io.relid
JOIN pg_stat_user_tables n ON n.relid = io.relid
JOIN public.g19_seq_before s ON s.relid = io.relid
ORDER BY (io.heap_blks_read - b.heap_blks_read)
       + (COALESCE(io.idx_blks_read,0) - COALESCE(b.idx_blks_read,0)) DESC
LIMIT 10;

-- Q3. THE TWO TABLES THE PAIR TOUCHES MOST ARE FREE, AND THAT MATTERS.
--
--       ottoq_policy_params    86,445,351 index hits,     51 blocks read,  2,083 rows
--       ottoq_sim_runs         50,265,281 heap hits,     111 blocks read,    789 rows
--                              36,517,152 index hits
--                               6,814 sequential scans, 5,296,379 tuples
--
--     ottoq_policy_get is called on the order of tens of millions of times per
--     pair and ottoq_sim_runs is read nearly as often — and both are small
--     enough to live in cache, so together they cost about 1.3 MB of I/O. They
--     are a CPU story, not an I/O one, and they are not the drift: 789 rows
--     scanned 6,814 times is 5.3M tuples, and that number grows by two rows per
--     pair rather than by a gigabyte a week.
--
--     Recorded because the touch counts are startling and someone will
--     otherwise chase them. 86 million policy lookups per pair is worth its own
--     task; it is not this one.
SELECT n.relname, (n.seq_scan - s.seq_scan) AS seq_scans,
       (n.seq_tup_read - s.seq_tup_read) AS seq_tuples,
       (io.heap_blks_hit - b.heap_blks_hit) AS heap_hit,
       (COALESCE(io.idx_blks_hit,0) - COALESCE(b.idx_blks_hit,0)) AS idx_hit,
       (io.heap_blks_read - b.heap_blks_read) AS heap_read
FROM pg_statio_user_tables io
JOIN public.g19_io_pref  b ON b.relid = io.relid
JOIN pg_stat_user_tables n ON n.relid = io.relid
JOIN public.g19_seq_before s ON s.relid = io.relid
WHERE n.relname IN ('ottoq_policy_params','ottoq_sim_runs','vehicles','ocpp_sessions')
ORDER BY 4 DESC;

-- Q4. 0126'S PER-PAIR FIGURE WAS RIGHT, AND MY DOUBT ABOUT IT WAS WRONG.
--     db/checks/0126 divided a lifetime counter by 314 pair calls and got
--     ~585,674 blocks, 4.6 GB, per pair. db/checks/0127 then noted that
--     183,901,558 is within 0.13% of ottoq_stall_bookings' LIFETIME
--     heap_blks_read and suggested the estimate was an artefact of that
--     coincidence. It was a coincidence, and the estimate was sound anyway:
--
--       0126, inferred, 12-tick pair      585,674 blocks   4.6 GB
--       0128, measured, 24-tick pair    1,227,704 blocks   9.6 GB
--                              halved     613,852 blocks   4.8 GB
--
--     Four percent apart. Recorded because a correction that is itself wrong is
--     worse than the error it corrects, and this one is now measured either way.
SELECT '0126 inferred, per 12-tick pair' AS source, 585674 AS blocks, '4.6 GB' AS size
UNION ALL SELECT '0128 measured, per 24-tick pair', 1227704, '9.6 GB'
UNION ALL SELECT '0128 measured, halved for comparison', 613852, '4.8 GB';

-- Q5. WHAT IS STILL OPEN: WHICH FIVE STATEMENTS.
--     Five sequential scans of ottoq_events per pair is the finding. WHICH
--     query issues them is not yet established, and this file is not going to
--     guess it — that mistake has been made three times on this task already
--     (the metronome, the missing sim_run_id indexes, the leg_id index in
--     0216, and my own validate_assignment reading in 0127).
--
--     Two facts to hand the next step. No function in public/twin/ottoq reads
--     ottoq_events without mentioning sim_run_id at all, so this is not an
--     unscoped read of the 0145 kind. But at least one — ottoq_event_new_state
--     — scopes it with `COALESCE(e.sim_run_id, c_nil) = COALESCE(...)`, the
--     0123/0124 pattern db/checks/0127 convicted, which no index on that column
--     can read. Whether that is one of the five is a question for the
--     instrument, not for this comment.
--
--     r25_g fires at 10:52 UTC with pg_stat_statements.track='all' set in its
--     own session. Every statement inside the tick is then recorded with its
--     calls, total_exec_time and shared_blks_read, and the one carrying ~877k
--     blocks read names itself. Snapshot in public.g19_stmt_before.
SELECT n.nspname||'.'||p.proname AS reads_events_via_coalesce_scope
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
  AND p.prosrc ~* 'COALESCE\s*\(\s*[a-z_]+\.sim_run_id'
  AND p.prosrc ~* '(FROM|JOIN)\s+(public\.)?ottoq_events\b'
ORDER BY 1;

-- Q6. THE CONTROL, because a delta is only as good as what else was running.
--     A second snapshot (public.g19_idle_before) was taken at 10:38:41 with the
--     pair finished and nothing else in flight, and read back at 10:47:03 —
--     **502 seconds** during which cron.job_run_details records **17 job runs**
--     (metronome every 60 s, depot tick and run governor every 120 s).
--
--       sequential scans, all user tables      0
--       heap blocks read, all user tables      0
--       heap buffer hits, all user tables      0
--       index scans, all user tables          27
--
--     Seventeen firings, twenty-seven index scans, no heap traffic at all: with
--     no sim run active those jobs check whether there is work, find none, and
--     stop. So nothing in the background is quietly scanning ottoq_events, and
--     the 5 sequential scans in Q2 are not somebody else's.
--
--     STATED PRECISELY, because this control does not prove quite as much as it
--     looks like it does: it measures the background WITH NO RUN ACTIVE. During
--     the pair a run IS active, so those jobs may do more than 27 index scans,
--     and their work is inside the Q1/Q2 window with no way to separate it.
--     What the control bounds is the magnitude — a job that does no heap I/O
--     when idle is not the source of 9.6 GB — not the exact attribution.
SELECT round(extract(epoch from (now() - max(snap_at)))) AS idle_secs_at_read,
       (SELECT count(*) FROM cron.job_run_details
         WHERE start_time > (SELECT max(snap_at) FROM public.g19_idle_before)) AS cron_runs
FROM public.g19_idle_before;
