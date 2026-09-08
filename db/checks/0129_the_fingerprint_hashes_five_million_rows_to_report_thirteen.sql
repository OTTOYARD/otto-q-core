-- ---------------------------------------------------------------------------
-- 0129 — G19 SOLVED, this time with a stopwatch and a statement name.
--        ottoq_boot_state_fingerprint JSON-serializes and MD5s 1.36 MILLION
--        rows per call, four times per pair, to report on THIRTEEN of them.
--
-- Measured 2026-09-08 by r25_g, round 25's sixth pair, which ran with
-- track_functions='pl' and pg_stat_statements.track='all' set in its own
-- session (10:52–11:04 UTC, busy_day/314159/12t, flagship). Snapshots in
-- public.g19_stmt_before / g19_io_before / g19_fn_before.
--
-- Three previous attempts guessed and were wrong: the metronome, the missing
-- sim_run_id indexes, and 0216's leg_id index. A fourth — my own reading in
-- db/checks/0127 that ottoq_validate_assignment was the carrier — was costed at
-- 1% and stands corrected there. This one is not a guess.
-- ---------------------------------------------------------------------------

-- Q1. THE PAIR, BY STATEMENT. Ranked by total_exec_time, nesting noted.
--
--   calls   secs   blks_read   statement
--       1  700.7     302,125   SELECT ottoq_determinism_pair(...)      <- the whole pair
--      24  439.0      83,583     SELECT ottoq_sim_advance_tick(v_run)
--      24  388.7      46,033       SELECT * FROM ottoq_sim_decide_and_dispatch(...)
--      24   50.3      37,549       SELECT * FROM ottoq_sim_advance_tick_world(...)
--       4  255.3     211,044   WITH vn AS (SELECT (t.sim_run_id IS NOT NULL AND
--                              t.sim_run_id <> p_run) AS fgn, ... md5(to_jsonb(t)...
--       2  128.2     119,783   SELECT jsonb_build_object(..., v_boot, ...)
--     612    4.9      20,739   SELECT b.vehicle_id FROM ottoq_stall_bookings ...
--
--   The arithmetic closes: 439 s of ticks + 255 s of the `vn` statement = 694 s
--   of a 700.7 s pair. **Thirty-six percent of the pair is FOUR calls to one
--   statement**, and it is not in the tick at all — it is the boot fingerprint,
--   run twice at boot and twice in the verdict.
--
--   Note the 612-call row: that is ottoq_validate_assignment, the carrier 0127
--   convicted, at **4.9 seconds — 0.7% of the pair**. 0127 predicted ~1% from a
--   microbenchmark before this profile existed. Confirmed, and still not G19.
SELECT s.calls - COALESCE(b.calls,0) AS calls,
       round((s.total_exec_time - COALESCE(b.total_exec_time,0))::numeric/1000,1) AS secs,
       s.shared_blks_read - COALESCE(b.shared_blks_read,0) AS blks_read,
       left(regexp_replace(s.query, '\s+', ' ', 'g'), 120) AS query
FROM pg_stat_statements s
LEFT JOIN public.g19_stmt_before b ON b.queryid = s.queryid
WHERE (s.total_exec_time - COALESCE(b.total_exec_time,0)) > 3000
ORDER BY (s.total_exec_time - COALESCE(b.total_exec_time,0)) DESC;

-- Q2. WHAT THE STATEMENT DOES. public.ottoq_boot_state_fingerprint(depot, run)
--     — the `endst` verdict atom, made id-blind by 0139 — walks four tables
--     scoped to the DEPOT and to nothing else:
--
--       vn  ottoq_visit_needs        WHERE depot_id = p_depot
--       bk  ottoq_stall_bookings     WHERE EXISTS (stall at that depot)
--       lg  ottoq_itinerary_legs     WHERE EXISTS (vehicle homed at that depot)
--       dp  ottoq_vehicle_dispatches WHERE EXISTS (vehicle homed at that depot)
--
--     and for EVERY row computes md5(to_jsonb(t)::text) — a full row-to-JSON
--     serialization plus a hash. There is no run predicate, deliberately: the
--     point is to see rows belonging to OTHER runs (`fgn`) so residue from a
--     previous run cannot hide. That is the V7 guarantee and it must survive.
--
--     But look at what the fgn branches actually consume:
--
--       visit_needs  fgn AND st IN ('open','in_progress','carried_over')
--       bookings     fgn AND st IN ('held','active','interrupted')
--       legs         fgn AND st IN ('planned','active','in_progress')
--       dispatches   fgn AND st IN ('active','returning')
--
--     Every foreign row in a TERMINAL state is serialized, hashed, and then
--     discarded by a filter three lines later.

-- Q3. AND THE COUNTS ARE ABSURD. At the flagship depot, right now:
--
--       table                    rows scanned   rows the fgn branch can use
--       ottoq_stall_bookings          786,457                             0
--       ottoq_itinerary_legs          485,526                            13
--       ottoq_visit_needs              88,932                             0
--       ------------------------------------------------------------------
--       total                       1,360,915                            13
--
--     1.36 million rows serialized and hashed PER CALL, four calls per pair —
--     **5.4 million row-hashes per pair** — to characterise thirteen rows, plus
--     the current run's own few thousand, which the `vis` branch needs.
--
--     And this is precisely the drift's shape. Every pair appends ~800 bookings
--     and ~680 legs to those tables, so the fingerprint costs more on every
--     subsequent run, forever, on an unchanged workload. Same class as
--     db/checks/0098 and 0123, now inside the certification's own verdict.
WITH d AS (SELECT '11111111-1111-1111-1111-111111111111'::uuid AS depot)
SELECT 'ottoq_stall_bookings' AS t, count(*) AS scanned,
       count(*) FILTER (WHERE b.state IN ('held','active','interrupted')) AS fgn_usable
  FROM public.ottoq_stall_bookings b, d
 WHERE EXISTS (SELECT 1 FROM public.stalls s WHERE s.id=b.stall_id AND s.depot_id=d.depot)
UNION ALL
SELECT 'ottoq_itinerary_legs', count(*),
       count(*) FILTER (WHERE l.status IN ('planned','active','in_progress'))
  FROM public.ottoq_itinerary_legs l, d
 WHERE EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id=l.vehicle_id AND v.home_depot_id=d.depot)
UNION ALL
SELECT 'ottoq_visit_needs', count(*),
       count(*) FILTER (WHERE n.status IN ('open','in_progress','carried_over'))
  FROM public.ottoq_visit_needs n, d WHERE n.depot_id = d.depot;

-- Q4. THE FIX IS ONE PREDICATE, AND IT IS PROVABLY OUTPUT-IDENTICAL.
--     Push the branches' own filters down into the CTEs:
--
--       AND (t.sim_run_id IS NULL OR t.sim_run_id = p_run
--            OR t.<state> IN (<that table's fgn state set>))
--
--     A row this excludes has sim_run_id NOT NULL, <> p_run, and a state
--     outside the fgn set — so `vis` (NOT fgn) cannot see it and `fgn`'s own
--     WHERE already rejects it. Neither count(*) nor either string_agg can
--     change. The V7 guarantee is untouched: every foreign row in a live state
--     is still hashed.
--
--     Expected effect: 1,360,915 rows per call down to roughly the current
--     run's own few thousand plus thirteen. Migration 0222.

-- Q5. WHAT THIS CORRECTS IN db/checks/0128, WRITTEN NINETY MINUTES EARLIER.
--     0128 measured pair f and found ottoq_events at 7,040 MB — 73% of that
--     pair's disk reads — off five sequential scans, and called that G19. The
--     statement profile says otherwise. On THIS pair the same instrument gives
--
--       ottoq_stall_bookings   1,544 MB      <- fingerprint
--       ottoq_visit_needs        614 MB      <- fingerprint
--       ottoq_itinerary_legs     500 MB      <- fingerprint
--       ottoq_events             146 MB
--
--     The fingerprint's three tables are 88% here and ottoq_events is 6%.
--     Two pairs, two very different I/O profiles, because pair f ran after 22
--     minutes of idle on a cold cache and this one ran straight after it.
--
--     Which is the lesson worth keeping: **I/O share is a cache artefact and
--     ranks differently on every run; total_exec_time per statement does not.**
--     0128's tables stand as measurements of that pair. Its conclusion does
--     not, and this file supersedes it. The instrument that settled it was the
--     one that names statements, not the one that names tables.
SELECT b.relname,
       pg_size_pretty((((io.heap_blks_read - b.heap_blks_read)
         + (COALESCE(io.idx_blks_read,0)-COALESCE(b.idx_blks_read,0)))::bigint)*8192) AS disk_read_this_pair
FROM pg_statio_user_tables io
JOIN public.g19_io_before b ON b.relid = io.relid
ORDER BY (io.heap_blks_read - b.heap_blks_read)
       + (COALESCE(io.idx_blks_read,0)-COALESCE(b.idx_blks_read,0)) DESC
LIMIT 6;
