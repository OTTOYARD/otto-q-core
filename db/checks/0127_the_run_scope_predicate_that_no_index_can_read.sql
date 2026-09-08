-- ---------------------------------------------------------------------------
-- 0127 — G19, NOT solved: the table is named, one carrier is convicted and
--        costed, and the cost turns out to be about one percent of the pair.
--
-- *** CORRECTED 2026-09-08 10:05 UTC, BEFORE APPLYING ANYTHING. This check was
-- *** first written with the title "G19 SOLVED" and that was wrong. Everything
-- *** below Q1-Q4 is measurement and stands. The inference from it did not, and
-- *** Q6 -- a warm stopwatch on the actual query, run twice -- is what refutes
-- *** it. Recorded rather than rewritten away, because the failure mode here is
-- *** the one this file was written to warn about: a plan cost is not a
-- *** stopwatch, and two earlier fixes measured beautifully and bought nothing.
--
-- What IS established: the run-scope predicate 0123/0124 added is a function of
-- the column, so no index can read it, and its cost is set by every run that
-- ever happened.
--
-- Traced 2026-09-08 09:40-09:50 UTC, read-only, while round 25's pair e ran.
-- Continues db/checks/0126, which decomposed the tick into two halves that had
-- both grown ~3.4x in lockstep and concluded "what they SHARE degraded",
-- nominating buffer cache. What follows is the same defect class as 0098 and
-- 0123 — a query whose cost is set by history rather than by the run — but see
-- Q6: it is a carrier, not THE cause.
--
-- A NOTE ON THE THEORY THIS REPLACES, because the wrong one was nearly written
-- up: the first draft of this check argued that ~28,000 inserted rows per pair
-- were paying ~20 disk block reads each in index maintenance, on the evidence
-- that every random-uuid-keyed index sits at 84-92% buffer hit while every
-- append-keyed index on the same tables sits at 97-99.5%. That contrast is
-- real. It is also not where the time goes, and the number that showed it was
-- one query away.
-- ---------------------------------------------------------------------------

-- Q1. ONE TABLE IS 53% OF EVERY DISK READ THIS DATABASE HAS EVER DONE.
--
--       relation                heap_blks_read   total read   heap size
--       ottoq_stall_bookings      183,664,015      1,415 GB      410 MB
--       ottoq_events               49,694,168        475 GB    2,956 MB
--       ottoq_decisions            36,029,804        286 GB    1,728 MB
--       ottoq_rule_evaluations     15,877,657        165 GB    4,238 MB
--       ---------------------------------------------------------------
--       whole database                              2,670 GB
--
--     ottoq_stall_bookings' heap is 52,480 blocks. It has been read from disk
--     183.7 MILLION times: three and a half THOUSAND full passes over the
--     table, from a table that is one seventh the size of ottoq_events and one
--     tenth of ottoq_rule_evaluations. It is also 8.88 BILLION buffer hits.
--
--     And 0126's "183,901,558 blocks read from disk over 314 pair calls",
--     offered there as a whole-database figure, is within 0.13% of this ONE
--     table's heap_blks_read. The 4.6 GB per pair was never diffuse. It was
--     here.
SELECT relname, heap_blks_read, heap_blks_hit, idx_blks_read,
       pg_size_pretty((heap_blks_read + COALESCE(idx_blks_read,0))::bigint * 8192) AS read_total,
       pg_size_pretty(pg_table_size(relid)) AS heap_size
FROM pg_statio_user_tables
ORDER BY heap_blks_read + COALESCE(idx_blks_read,0) DESC LIMIT 8;

-- Q2. AND IT IS NOT BEING SCANNED FOR NOTHING — LOOK AT THE TUPLE COUNT.
--
--       ottoq_stall_bookings   seq_scan 1,957,327   seq_tup_read 49,308,274,942
--       ottoq_itinerary_legs   seq_scan 1,660,102   seq_tup_read  7,123,171,955
--
--     49.3 BILLION tuples read sequentially from a table with 780,700 live
--     rows. The lifetime average is 25,192 tuples per scan, against 780,700
--     rows today — which is not an inconsistency, it is the drift itself
--     written down: the same scans, over a table that has grown ~31x since
--     most of them ran.
SELECT relname, seq_scan, seq_tup_read,
       round(seq_tup_read::numeric/nullif(seq_scan,0)) AS avg_tup_per_seq_scan,
       idx_scan, n_live_tup, n_tup_ins, n_tup_upd
FROM pg_stat_user_tables
WHERE relname IN ('ottoq_stall_bookings','ottoq_itinerary_legs','ottoq_visit_needs',
                  'ottoq_events','ottoq_decisions','ottoq_rule_evaluations')
ORDER BY seq_tup_read DESC;

-- Q3. THE CARRIER, NAMED. ottoq.ottoq_validate_assignment, the forward-calendar
--     conflict check called by ottoq_emit_vehicle_command on EVERY assignment:
--
--       SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
--        WHERE b.stall_id = p_stall_id
--          AND b.state IN ('held','active','done','interrupted')
--          AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
--          AND COALESCE(b.sim_run_id,'000…000'::uuid)          <-- HERE
--            = COALESCE(p_sim_run_id,'000…000'::uuid)
--        ORDER BY lower(b.during), b.vehicle_id, b.booking_id LIMIT 1;
--
--     ottoq_stall_bookings_live_stall_idx is btree (sim_run_id, stall_id) WHERE
--     state IN ('held','active','done','interrupted') — an exact match for this
--     query's state set, built for exactly this lookup. The planner cannot use
--     its LEADING COLUMN, because COALESCE(b.sim_run_id, …) is a function of
--     the column, not the column. So it enters the index on stall_id alone —
--     the second column — and walks every booking that stall has ever had,
--     across every run in history, filtering afterwards.
--
--     Two EXPLAINs of the same query, differing only in that predicate, taken
--     on the live database:
--
--       COALESCE(b.sim_run_id,…) = COALESCE(p,…)
--         Index Cond: (stall_id = …)
--         Filter:     (COALESCE(sim_run_id, …) = …) AND (during @> now()) …
--         cost 5311.29
--
--       b.sim_run_id = p_sim_run_id
--         Index Cond: ((sim_run_id = …) AND (stall_id = …))
--         cost 2.65
--
--     2,004x, and the expensive plan's cost is a function of total history
--     while the cheap one's is not. On a typical flagship stall the walk is
--     1,247 index entries and heap fetches per call TODAY. One arm emits 569
--     vehicle commands, so ~710,000 tuple fetches per arm, ~1.4M per pair, and
--     that number rises with every run ever archived. A week ago the same call
--     touched about 40.
EXPLAIN
SELECT b.vehicle_id FROM public.ottoq_stall_bookings b
 WHERE b.stall_id = (SELECT id FROM public.stalls
                      WHERE depot_id='11111111-1111-1111-1111-111111111111' LIMIT 1)
   AND b.state IN ('held','active','done','interrupted')
   AND b.vehicle_id <> '00000000-0000-0000-0000-000000000001'::uuid
   AND b.during @> now()
   AND COALESCE(b.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
     = COALESCE('a269bad3-268e-4ee0-9473-8b3a9cb522a8'::uuid,'00000000-0000-0000-0000-000000000000'::uuid)
 ORDER BY lower(b.during), b.vehicle_id, b.booking_id LIMIT 1;

-- Q4. IT IS A CLASS, NOT A QUERY — 33 FUNCTIONS CARRY IT.
--     The pattern came in with migrations 0123 and 0124, which were RIGHT: they
--     closed the 0145 defect class by scoping reads of run-scoped tables to
--     their own run. The scope predicate was written as
--
--         COALESCE(<column>.sim_run_id, nil) = COALESCE(<param>, nil)
--
--     so that a NULL run id (production) would match a NULL run id. Correct,
--     and unreadable by every index on the column it scopes. The comment
--     markers those migrations left — /* 0123 */, /* 0124 */ — make the class
--     greppable, which is the one good thing about how this happened.
--
--     Tables reached: ottoq_visit_needs (most), ottoq_stall_bookings,
--     ottoq_vehicle_dispatches, ottoq_charging_sessions, ottoq_events.
--     ottoq_visit_needs survives it — 88,296 live rows and a vehicle_id
--     predicate to narrow on. ottoq_stall_bookings does not: 780,700 rows and
--     the only other predicate is the index's SECOND column.
SELECT n.nspname||'.'||p.proname AS fn,
       (SELECT count(*) FROM regexp_matches(p.prosrc,
          'COALESCE\s*\(\s*[a-z_]+\.sim_run_id', 'gi')) AS occurrences
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
  AND p.prosrc ~* 'COALESCE\s*\(\s*[a-z_]+\.sim_run_id'
ORDER BY occurrences DESC, 1;

-- Q5. WHY THE TWO EARLIER FIXES BOUGHT NOTHING, WHICH IS THE CHECK ON THIS ONE.
--     0216 added ottoq_stall_bookings_leg_idx after measuring a trigger lookup
--     at 965 ms cold. Real scan, real index, zero seconds off the pair — the
--     trigger fires 433 times per arm and the pair was not spending its time
--     there. The metronome was flat all week. Both were guesses at a table that
--     was, in fact, the right table for the wrong reason.
--
--     The discipline that applies to THIS diagnosis is the same one that
--     refuted those: a planner cost ratio is not a stopwatch. What follows is
--     the prediction, stated before the fix so it can be wrong:
--
--       1. Rewriting ONLY ottoq_validate_assignment's predicate to the sargable
--          form (migration 0221) must leave every verdict atom on every column
--          UNCHANGED. The row set is provably identical — the two forms differ
--          only if a booking carries sim_run_id = the all-zero uuid, and there
--          are 0 such rows and 0 such runs. If any atom moves, the rewrite
--          changed behaviour and must be reverted, not explained.
--       2. The pair should get materially faster. If it does not, this
--          diagnosis is as wrong as the last two and the next step is the
--          pg_stat_statements capture from the 10:40 profiled run, which
--          records every nested statement rather than reasoning about plans.
--       3. Only if (2) holds does the remaining class get swept. One change,
--          measured, then generalise — not 33 rewrites on a theory.
SELECT (SELECT count(*) FROM public.ottoq_stall_bookings
         WHERE sim_run_id = '00000000-0000-0000-0000-000000000000') AS zero_uuid_bookings,
       (SELECT count(*) FROM public.ottoq_sim_runs
         WHERE sim_run_id = '00000000-0000-0000-0000-000000000000') AS zero_uuid_runs,
       (SELECT count(*) FROM public.ottoq_stall_bookings
         WHERE sim_run_id IS NULL) AS production_bookings;

-- Q6. THE STOPWATCH, WHICH IS WHY THIS FILE'S TITLE CHANGED.
--     Q3's 2,004x is a PLANNER COST RATIO. Q5 said in as many words that a cost
--     ratio is not a stopwatch. So: both forms, run through plpgsql variables
--     exactly as the function runs them, across all 158 flagship stalls, warmed
--     and then measured twice.
--
--       pass   COALESCE form   sargable form   ratio   per call
--         1       1237.0 ms         5.6 ms      221x   7.83 ms -> 0.035 ms
--         2       1166.3 ms         3.9 ms      299x   7.38 ms -> 0.025 ms
--
--     The defect is real, the fix is real, and it is roughly 300x on the call.
--     Now the arithmetic nobody did before writing "SOLVED":
--
--       one arm emits 569 vehicle commands
--       569 x 7.4 ms                       =   4.2 s per arm
--                                          =   8.4 s per pair
--       the pair is                            812 s
--
--     ONE PERCENT. To account for the ~566 s of tick time in a 12-tick pair
--     (0126: 12 ticks x 23.6 s x 2 arms) this query would have to be called
--     ~38,000 times per arm — 67 times per emitted command. It is not.
--
--     So 0221 is worth applying: it is a genuine unbounded-in-history read on
--     the hot path, it gets monotonically worse, and it costs nothing to fix.
--     It is not G19.
--
-- Q7. WHAT G19 STILL IS, STATED AS THE OPEN QUESTION IT IS.
--     Q2's 1,957,327 SEQUENTIAL scans of ottoq_stall_bookings reading 49.3
--     BILLION tuples are NOT this query — Q6 shows it plans onto an index scan
--     even through plpgsql variables, which is why it costs 7.4 ms rather than
--     the ~100 ms a warm scan of a 410 MB table would cost. Some other query
--     seq-scans that table, roughly two million times, and that is where 1.4 TB
--     of heap reads and 8.88 billion buffer touches actually go.
--
--     Two measurements are already scheduled to name it rather than guess a
--     third time:
--       * public.g19_seq_before — pg_stat_user_tables and pg_statio_user_tables
--         snapshotted 2026-09-08 10:00:53 UTC with ottoq_stall_bookings at
--         seq_scan = 1,957,331. Differencing after the next pair gives SEQUENTIAL
--         SCANS PER PAIR exactly, with no inference at all.
--       * r25_g at 10:52 UTC runs with pg_stat_statements.track='all' in its own
--         session, so every nested statement inside the tick is recorded with its
--         calls, total_exec_time and shared_blks_read. That names the query.
SELECT relname, seq_scan, seq_tup_read, snap_at
FROM public.g19_seq_before
WHERE relname IN ('ottoq_stall_bookings','ottoq_itinerary_legs')
ORDER BY seq_tup_read DESC;
