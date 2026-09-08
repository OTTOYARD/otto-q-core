-- ---------------------------------------------------------------------------
-- 0136 — G23, re-framed by measurement. Three corrections, one of them to
--        CLAUDE.md and one to G23's own premise.
--
--        1. The biggest table is NOT ottoq_stall_bookings. It is
--           ottoq_rule_evaluations, at 5,063 MB against bookings' 916 MB.
--        2. Bookings' problem is not storage at all. It is 1,957,342
--           sequential scans reading 49.3 BILLION tuples — a READ problem,
--           the class 0216 fixed with an index, not a retention problem.
--        3. `n_tup_ins`/`n_tup_del` are not a lifetime record for
--           ottoq_events and ottoq_decisions, and this is provable by
--           arithmetic rather than by argument. Every purge-rate percentage
--           quoted from them for those two tables — including CLAUDE.md's —
--           says more than the counters know.
--
-- Measured 2026-09-08 14:33 UTC, catalog only: no table was scanned to write
-- this file, deliberately, because a certification pair was running and
-- counting ottoq_stall_bookings is itself one of the reads the file is about.
-- ---------------------------------------------------------------------------

-- Q1. THE TABLE. Sizes, purge counters, and read pressure side by side.
SELECT c.relname,
       c.reltuples::bigint                            AS est_rows,
       pg_size_pretty(pg_total_relation_size(c.oid))  AS total,
       s.n_tup_ins, s.n_tup_del,
       s.n_tup_ins - s.n_tup_del                      AS ins_minus_del,
       s.seq_scan, s.seq_tup_read
  FROM pg_class c JOIN pg_stat_user_tables s ON s.relid = c.oid
 WHERE c.relname IN ('ottoq_stall_bookings','ottoq_events','ottoq_decisions',
                     'ottoq_telemetry_packets','ottoq_rule_evaluations',
                     'ottoq_service_detail_records','ocpp_sessions')
 ORDER BY pg_total_relation_size(c.oid) DESC;
--
--  table                        est_rows     total    n_tup_ins   n_tup_del  ins-del    seq_scan    seq_tup_read
--  ottoq_rule_evaluations      5,522,701  5,063 MB   10,646,302   4,766,150  5,880,152      7,494      39,776,565
--  ottoq_events                2,334,584  3,441 MB    9,538,009   9,195,864    342,145      9,150     448,863,966
--  ottoq_decisions             1,592,534  1,910 MB    3,005,534   4,854,763 -1,849,229      6,277     269,904,984
--  ottoq_stall_bookings          787,631    916 MB      946,748     134,089    812,659  1,957,342  49,320,046,018
--  ottoq_telemetry_packets       267,281    112 MB    3,348,879   3,239,161    109,718    218,365     128,894,465
--  ottoq_service_detail_records  184,567    110 MB      198,698      12,589    186,109         80       3,049,426
--  ocpp_sessions                  44,900     33 MB      125,341      78,791     46,550    203,403   2,089,179,174

-- Q2. CORRECTION 1 — THE STORAGE STORY IS RULE EVALUATIONS.
--
--     G23 says "the calendar is an accumulation, not a rolling window, growing
--     ~800 rows per pair forever". True, and it is 916 MB. ottoq_rule_evaluations
--     is FIVE AND A HALF TIMES that, and ottoq_events is nearly four times it.
--     If the question is "what is filling the disk", bookings is the fourth
--     answer, not the first.
--
--     rule_evaluations is also the one whose growth is least examined: 44.8% of
--     its inserts have been deleted, which is a real purge, and it still holds
--     5.5M rows in 5 GB. The L1 shield logs every evaluation of 29 active rule
--     codes on every tick of every arm of every pair. That is the volume, and
--     nobody has asked what the retention window on it should be.

-- Q3. CORRECTION 2 — BOOKINGS IS A READ PROBLEM, AND THE RATIO IS THE PROOF.
--
--     Divide seq_tup_read by seq_scan and the tables separate cleanly:
--
--       ottoq_stall_bookings    49,320,046,018 / 1,957,342 =  25,197 tuples/scan
--       ocpp_sessions            2,089,179,174 /   203,403 =  10,271 tuples/scan
--       ottoq_events               448,863,966 /     9,150 =  49,056 tuples/scan
--       ottoq_rule_evaluations      39,776,565 /     7,494 =   5,308 tuples/scan
--
--     Bookings is not scanned because it is big; it is scanned TWO MILLION
--     TIMES. Nothing else in the database is scanned even a tenth as often.
--     Deleting rows would shrink each scan and leave the two million intact —
--     and the count would climb straight back, because it is driven by how
--     often the engine asks, not by how much history it holds.
--
--     0216 is the shape of the real fix and it is already proven on this exact
--     table: `ottoq_trg_leg_done_sdr` filtered `leg_id` with no index on it —
--     a 965 ms parallel seq scan, ~2,236 times per pair — and one partial index
--     took its lookup to 0.295 ms, 50,769 blocks to 25. That is one call site.
--     The census of who else scans this table has not been done, and it is the
--     work G23 should be, rather than a retention argument.
SELECT relname,
       seq_scan,
       seq_tup_read,
       CASE WHEN seq_scan > 0 THEN (seq_tup_read/seq_scan)::bigint END AS tuples_per_scan
  FROM pg_stat_user_tables
 WHERE relname IN ('ottoq_stall_bookings','ocpp_sessions','ottoq_events',
                   'ottoq_rule_evaluations','ottoq_decisions')
 ORDER BY seq_scan DESC;

-- Q4. CORRECTION 3 — THE PURGE COUNTERS ARE NOT A LIFETIME RECORD, AND
--     ottoq_decisions PROVES IT WITHOUT NEEDING AN ARGUMENT.
--
--       ottoq_decisions:  3,005,534 inserted, 4,854,763 deleted
--                         → ins - del = -1,849,229
--                         → and the table holds 1,592,534 rows.
--
--     A table cannot have had more rows deleted than were ever inserted into it
--     and still contain 1.6 million. The only way both numbers are true is that
--     the counters do not cover the table's whole life: rows that existed
--     before the counters started have been deleted since, so their deletion is
--     counted and their insertion is not.
--
--     `pg_stat_database.stats_reset` is NULL, which is often read as "the
--     counters have never been reset". It does not mean that. It records
--     EXPLICIT resets only; statistics lost to an unclean shutdown restart at
--     zero and set nothing. Four of the seven tables above reconcile to within
--     a few percent (ocpp_sessions to 868 rows, SDRs to 1,542, bookings to 3%,
--     rule_evaluations to 6%) and two — events and decisions — do not, one of
--     them impossibly. That pattern is what a partial statistics loss looks
--     like, and it is not something the counters can tell you about themselves.
SELECT datname, stats_reset,
       'NULL means no EXPLICIT reset; it does not mean the counters are lifetime'
         AS what_null_means
  FROM pg_stat_database WHERE datname = current_database();

-- Q5. WHAT THIS CORRECTS IN CLAUDE.md, precisely.
--
--     Part 3's 2026-09-08 refresh says:
--
--       "The nightly retention purge is doing its job — pg_stat_user_tables
--        records 9,419,289 inserts against 9,195,864 deletes on that table
--        over its life"
--
--     "over its life" is the part the counters do not support: 9,538,009 minus
--     9,195,864 is 342,145, and the table holds 2,334,584 rows. The counters
--     know about a window, not a lifetime.
--
--     THE CONCLUSION AROUND IT SURVIVES, and by better evidence than the
--     counters. CLAUDE.md's own refresh table shows ottoq_events going DOWN,
--     2,487,708 → 2,231,792, between the 09-03 and 09-08 pulls. A table that
--     shrinks while the twin runs is being purged, and that is a direct
--     observation rather than an inference from a counter. The sentence to
--     keep is the one already in the file: "2,487,708 was a high-water mark,
--     not a floor... Cite the run, not the table."
--
--     Same correction applies to G23's own headline, which reads "ottoq_events
--     97% purged over its life; ottoq_stall_bookings 14%". The 14% figure is
--     sound — bookings reconciles — and the 97% is a window figure wearing a
--     lifetime label. The COMPARISON between them is what G23 rests on, and it
--     survives: one table is aggressively purged and the other is barely
--     touched, whatever window the counters cover.

-- Q6. THE QUESTION FOR CHASE, NARROWED BY THE ABOVE.
--
--     G23 asked one question — are a finished twin run's bookings evidence
--     worth keeping? — and the measurements split it into three, of which only
--     the first is his:
--
--     (a) RETENTION, and the table is ottoq_rule_evaluations, not bookings.
--         5 GB, 5.5M rows, growing with every tick of every arm. What is the
--         window? This is a product question: the L1 evaluation ledger is a
--         moat asset (CLAUDE.md 2.3 calls it "the L1 foothold") and throwing it
--         away has a cost that is not measured in gigabytes.
--
--     (b) THE BOOKINGS SCANS, which are mine and are not a retention question
--         at all. Census every caller that sequentially scans
--         ottoq_stall_bookings, the way 0123 censused the run-scope reads, and
--         index the ones that matter. 0216 already proved the payoff on one
--         call site.
--
--     (c) THE COUNTERS, which are now documented above so that the next person
--         to quote a purge percentage knows which ones reconcile.
SELECT 'see Q1-Q6; this file changes nothing' AS status;
