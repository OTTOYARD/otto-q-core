-- ---------------------------------------------------------------------------
-- 0138 — G13, written up at last, and two of its five claims do not survive
--        re-measurement in the form they were recorded.
--
--        THE ONE THAT MATTERS: **64 of the Benchmark depot's 160 stalls are
--        seated by vehicles that belong to no run, and its 154 live
--        reservations expired on 2026-08-22/23 — sixteen days ago.** Forty
--        percent of the depot is unreservable, and nothing will ever clean it,
--        because every cleaner in this system is run-scoped and no run has ever
--        targeted that depot.
--
--        That is the answer to a question left open in the two-lane cadence
--        work: whether the Benchmark depot is a viable second certification
--        lane. It is not, and now the reason has a number.
--
-- Measured 2026-09-08 15:05 UTC, while round 27 column e was running. Every
-- query below is against `stalls` (330 rows), `vehicles` (226) or the catalog.
-- G13 has been an unevidenced one-line entry in FINDINGS.md since it was
-- recorded; this is the file it never had.
-- ---------------------------------------------------------------------------

-- Q1. THE SEATS, AND WHAT IS AND IS NOT WRONG WITH THEM.
--
--     G13 recorded "Benchmark depot carries 64 orphan occupancies". The 64 is
--     exact. "Orphan" is not — not in the sense that first suggests itself.
--     Every one of those 64 stalls has a vehicle whose `current_stall_id`
--     points back at it. The seat and the back-pointer agree; the pair is
--     internally consistent.
SELECT d.name AS depot,
       count(*) FILTER (WHERE s.current_vehicle_id IS NOT NULL)         AS seated,
       count(*) FILTER (WHERE s.current_vehicle_id IS NOT NULL
                          AND v.id IS NULL)                             AS seat_names_no_vehicle,
       count(*) FILTER (WHERE s.current_vehicle_id IS NOT NULL
                          AND v.current_stall_id IS DISTINCT FROM s.id) AS no_backpointer,
       count(*) FILTER (WHERE s.status='occupied'
                          AND s.current_vehicle_id IS NULL)             AS occupied_but_empty,
       count(*) FILTER (WHERE s.reserved_by IS NOT NULL
                          AND s.reservation_expires_at < now())         AS expired_reservations
  FROM public.stalls s
  JOIN public.depots d ON d.id = s.depot_id
  LEFT JOIN public.vehicles v ON v.id = s.current_vehicle_id
 GROUP BY d.name ORDER BY d.name;
--
--   depot                     seated  no_vehicle  no_backptr  occ_empty  expired
--   OTTOYARD Benchmark            64           0           0          0      154
--   OTTOYARD Grid Fixture          0           0           0          0        0
--   OTTOYARD Hardware Lab          0           0           0          0        0
--   OTTOYARD Nashville Flagship    0           0           0          0        0
--   P2 Ledger-Only Proof Rig       0           0           0          0        0
--
--   Every other depot is clean. The flagship — the one the certification
--   actually runs on — is spotless, which is the teardown working.

-- Q2. WHAT MAKES THEM DEAD: THE VEHICLES BELONG TO NO RUN.
SELECT r.status AS owning_run_status, count(*) AS seated_stalls,
       count(DISTINCT v.owning_sim_run_id) AS distinct_owning_runs
  FROM public.stalls s
  JOIN public.vehicles v ON v.id = s.current_vehicle_id
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = v.owning_sim_run_id
 WHERE s.depot_id = '22222222-2222-2222-2222-222222222222'
 GROUP BY 1 ORDER BY 2 DESC;
--   -> NULL | 64 | 0
--
--   `owning_sim_run_id` is NULL on all 64. So 0117's claim-release did its job:
--   the run's hold on the vehicle is gone. What it did not do — because it is
--   not what it does — is vacate the seat.

-- Q3. AND THE RESERVATIONS EXPIRED SIXTEEN DAYS AGO.
SELECT count(*) AS expired, count(DISTINCT depot_id) AS depots,
       min(reservation_expires_at) AS oldest, max(reservation_expires_at) AS newest,
       count(*) FILTER (WHERE current_vehicle_id IS NOT NULL) AS also_seated
  FROM public.stalls
 WHERE reserved_by IS NOT NULL AND reservation_expires_at < now();
--   -> 154 | 1 | 2026-08-22 23:00 | 2026-08-23 09:00 | 63
--
--   One depot. A ten-hour window on 22-23 August. 63 of the 154 are also
--   seated, so the two residues overlap but are not the same rows.

-- Q4. THE OPERATIONAL COST, WHICH IS THE POINT.
--
--     `public.ottoq_reserve_stall` is the CAS, and its first condition is
--     `current_vehicle_id IS NULL`:
--
--       UPDATE stalls SET reserved_by = p_vehicle_id, ...
--        WHERE id = p_stall_id
--          AND current_vehicle_id IS NULL
--          AND (reserved_by IS NULL OR reserved_by = p_vehicle_id
--               OR reservation_expires_at IS NULL OR reservation_expires_at <= p_now)
--
--     The CAS is CORRECT — a single conditional UPDATE, atomic under row
--     locking, and it treats an expired reservation as free, which is why the
--     154 are harmless on their own. The 64 seats are not: an occupied stall
--     can never be reserved, whatever the age of the occupancy.
SELECT count(*) AS stalls_total,
       count(*) FILTER (WHERE current_vehicle_id IS NOT NULL) AS held_by_a_dead_seat,
       count(*) FILTER (WHERE current_vehicle_id IS NULL
                          AND (reserved_by IS NULL OR reservation_expires_at IS NULL
                               OR reservation_expires_at <= now()))  AS reservable_now,
       round(100.0*count(*) FILTER (WHERE current_vehicle_id IS NOT NULL)/count(*),1) AS pct_dead
  FROM public.stalls WHERE depot_id='22222222-2222-2222-2222-222222222222';
--   -> 160 | 64 | 96 | 40.0
--
--   **Forty percent of the Benchmark depot cannot be reserved by anyone.**

-- Q5. WHY NOTHING WILL EVER CLEAN IT. Three mechanisms, none of which applies.
--
--     (a) THE TEARDOWNS DO CLEAR SEATS. Both `ottoq_sim_release_depot` and
--         `ottoq_tick_invariance_reset_fleet` touch `current_vehicle_id`,
--         `reserved_by` and `current_stall_id`. This is NOT a missing
--         capability. Both are DEPOT-SCOPED and RUN-TRIGGERED: they clean the
--         depot a run is about to use, or has just finished using.
SELECT p.proname,
       (p.prosrc ILIKE '%current_vehicle_id%') AS clears_seat,
       (p.prosrc ILIKE '%reserved_by%')        AS clears_reservation,
       (p.prosrc ILIKE '%current_stall_id%')   AS clears_backpointer
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.proname IN ('ottoq_sim_release_depot','ottoq_tick_invariance_reset_fleet')
 ORDER BY 1;
--   -> both true/true/true
--
--     (b) THE RUN GOVERNOR EXEMPTS THE HARNESS, IN BOTH ITS LOOPS:
--
--           WHERE status = 'running'
--             AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
--
--         The exemption is deliberate and its reasoning is in the body: the
--         metronome exempts the same two values, so an exempt run never
--         advances and the ceiling would fire on a run that is simply being
--         driven by something else. Correct for a healthy pair. It also means
--         the one janitor that runs on a schedule will never touch a
--         cert_harness run, healthy or dead.
--
--     (c) THE NIGHTLY PURGE DOES NOT COVER ANY OF THIS:
--
--           CALL ottoq_retention_purge_worker(90, 2000, '48 hours',
--                ARRAY['ottoq_events','ottoq_rule_evaluations','ottoq_incident_reports']);
--
--         Three event-shaped tables. Not `stalls`, not `vehicles`, not
--         `ottoq_sim_runs`.
--
--     So cleanup happens only as a side effect of the NEXT run on that depot.
--     A depot nobody runs again stays exactly as the last thing left it,
--     forever. **There is no janitor.**

-- Q6. AND NO RUN EXPLAINS THE RESIDUE, WHICH IS THE SHARPEST PART.
--
--     The obvious story is "a Benchmark run died and left this behind". The
--     ledger refuses it. `ottoq_sim_runs` is NOT one of the purged tables (Q5c)
--     and holds 811 runs going back to 2026-06-19 — two months before these
--     reservations expired. Runs on the Benchmark depot in that ledger:
SELECT count(*) AS benchmark_runs_ever
  FROM public.ottoq_sim_runs
 WHERE depot_id = '22222222-2222-2222-2222-222222222222';
--   -> 0
SELECT count(*) AS runs_total, count(DISTINCT depot_id) AS depots_with_runs,
       min(started_at)::date AS earliest_surviving
  FROM public.ottoq_sim_runs;
--   -> 811 | 3 | 2026-06-19
--
--     **Zero.** Not "purged" — the table is not purged and reaches back well
--     past August. So these 64 seats and 154 reservations were not written by
--     any sim run this database has a record of. They are fixture or demo
--     residue, and calling them "orphan occupancies from a run" — as G13 did —
--     attributes them to a parent that never existed.

-- Q7. WHAT SURVIVES OF G13, ITEM BY ITEM.
--
--     G13's line was: "Reserve CAS lets 96 double-seat attempts reach the
--     unique index; Benchmark depot carries 64 orphan occupancies; the grant is
--     keyed by run; seven 0129 leg cursors; per-seat subtransactions."
--
--     * "64 orphan occupancies"  — COUNT CONFIRMED, CAUSE WRONG. Not orphans of
--       a run (Q6: there is no run). Fixture residue that no run-scoped cleaner
--       will ever reach. The real finding is bigger than the original: 40% of
--       the depot is dead and there is no janitor.
--
--     * "Reserve CAS lets 96 double-seat attempts reach the unique index" —
--       NOT REPRODUCED, and the CAS reads as correct (Q4). The unique index in
--       question is `idx_stalls_one_vehicle_per_stall`, and note its name is
--       INVERTED: it is `UNIQUE (current_vehicle_id) WHERE current_vehicle_id
--       IS NOT NULL`, which enforces one STALL PER VEHICLE, not one vehicle per
--       stall (that is structural — stall id is the primary key). A constraint
--       guarding the assignment-plus-verification invariant is named backwards.
--       Whether 96 attempts once reached it cannot be settled from here: the
--       counter that would show it lives in `pg_stat_database.xact_rollback`,
--       which is not attributable to a statement.
--
--     * "the grant is keyed by run", "seven 0129 leg cursors", "per-seat
--       subtransactions" — NOT INVESTIGATED HERE. Each is a separate claim and
--       each needs its own measurement; recording that they are untouched is
--       better than implying this file covered them.

-- Q8. WHAT TO DO, in the order the costs argue for.
--
--     1. **CLEAR THE BENCHMARK RESIDUE — a data operation, not a migration.**
--        `ottoq_tick_invariance_reset_fleet(depot, seed, clock)` already does
--        exactly this and is the function the certification calls before every
--        arm. Pointing it at the Benchmark depot once returns 64 stalls. It
--        must NOT be run while a pair is in flight, and it is worth doing
--        before anyone tries the two-lane cadence, because a second lane on a
--        depot with 40% of its stalls held is not a second lane.
--
--     2. **DECIDE WHETHER A JANITOR SHOULD EXIST.** Today cleanup rides on the
--        next run. That is efficient and it means a depot's dirtiness is
--        unbounded in time. A periodic sweep — seats whose vehicle owns no
--        running run, reservations expired by more than an hour — would make
--        the invariant continuous rather than eventual. It is a product
--        decision because it changes what a depot looks like between runs, and
--        the twin's `data_source` discipline means anything it touches is
--        visible to the metrics layer.
--
--     3. **RENAME `idx_stalls_one_vehicle_per_stall`** to say what it enforces.
--        Cosmetic until someone reasons from the name, at which point it is not.
SELECT 'see Q1-Q8; this file changes nothing' AS status;
