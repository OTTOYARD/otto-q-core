-- =====================================================================================
-- 0022_run_scope_certification.sql
--
-- WHAT THIS IS. The re-runnable battery behind db/evidence/P0022_run_scope_certification.md:
-- the first certification of migration 0022 (`a_run_owns_its_rows`, ledger 20260808182226)
-- against live simulation runs.
--
-- 0022 shipped with its 9 in-transaction assertions passing and its OUTCOME unproven:
-- nothing had yet tried to reproduce, on two real runs, the cross-run collision that
-- started this whole line of work. This file is that outcome.
--
-- READ-ONLY. Creates nothing, drops nothing, starts no run. It reads the evidence
-- tables captured during the certification.
--
-- THE RUNS (both crossed 20:00-06:00 CST; night = ticks 24..44 of 48)
--   RUN A  seed 20260830  ottoq_sim_run_scenario('normal_day', 20260830, 'operator_demo')
--   RUN B  seed 20260831  ottoq_sim_run_scenario('normal_day', 20260831, 'operator_demo')
--   RUN C  seed 20260832  ottoq_start_demo_run(...)          <- the "normal start button"
--
-- WHY THE KEYS COLLIDE WITHOUT BEING FORCED TO. `ottoq_sim_run_scenario` sets
--   v_start := date_trunc('day', now() AT TIME ZONE 'America/Chicago') + interval '8 hours'
-- whenever p_run_by = 'operator_demo'. Every run started on the SAME REAL CALENDAR DAY
-- therefore gets a byte-identical `sim_clock_start`, and the tick grid is a fixed
-- 30 sim-min. `visit_key` = vehicle_id || ':' || to_char(clock,'YYYYMMDDHH24MISS'), so
-- two same-day runs mint byte-identical keys for the same vehicle at the same grid slot.
-- Nothing was rigged. The collision is the DEFAULT behaviour of the shipped entry point.
--
-- CLOCK DOMAINS, stated once. `sim_clock_*`, `raised_at_sim_clock`, `arrived_at` and
-- `during` are SIM domain. `started_at`, `ended_at`, `created_at`, `measured_at` are REAL
-- wall clock. `ottoq_sim_stop_and_reset` writes the REAL clock into the sim-domain
-- `actual_return_at`; no run here was ever stopped -- all three reached
-- status='completed' on their own at sim_clock_end -- so no teardown row exists to
-- exclude. That is stated as a fact about the runs, not as a filter.
--
-- EVIDENCE TABLES (do not drop):
--   cert0022_a_{runrow,visitneeds,bookings,flags,dispatches,stalls}   RUN A, pre-stop
--   cert0022_b_{...same...}                                          RUN B, pre-stop
--   cert0022_a_after_b        RUN A's ledger re-read AFTER run B finished
--   cert0022_collision        the byte-identical visit_key pairs across runs A and B
--   cert0022_fk_orphan_sweep  every FK in the database, orphan count, per phase
--   cert0022_orphans_by_class run-scope registry orphan census, per phase
--   cert0022_orphan_refusal   the six deliberate attempts to CREATE an orphan
--   cert0022_purge_receipt    what ottoq_purge_prior_runs actually cleared
--   cert0022_misc             single-value probes (428C9, instance latency)
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- (1) 🔴 THE ASSERTION. Two runs, one clock, colliding keys -- is run A's ledger intact?
--
--     A vacuous pass is the failure mode to guard against here: if ZERO keys collided,
--     this test proves NOTHING. `colliding_keys` is reported FIRST and on its own for
--     exactly that reason. Read it before reading the verdict.
-- -------------------------------------------------------------------------------------
SELECT count(*) AS colliding_keys_byte_identical,
       count(DISTINCT vehicle_id) AS vehicles_involved
  FROM public.cert0022_collision;

-- Run A's rows, before run B existed vs after run B finished.
--   whole_row_md5     -- every column
--   payload_md5       -- every column EXCEPT `status`
-- The split is deliberate and is NOT a way of excusing a difference. `status` is the one
-- field a later run legitimately transitions: ottoq_sim_run_scenario carries
--     UPDATE ottoq_visit_needs SET status='superseded' ... WHERE status IN ('open','in_progress')
-- scoped by DEPOT, not by run. That write is reported in section (2) as its own finding.
-- The CLOBBER 0020 fixed replaced `atoms` and `meta` -- those live in payload_md5.
SELECT count(*)                                              AS run_a_rows,
       count(*) FILTER (WHERE b.payload_md5 = a.payload_md5) AS payload_identical,
       count(*) FILTER (WHERE b.payload_md5 <> a.payload_md5) AS payload_CHANGED,
       count(*) FILTER (WHERE b.whole_row_md5 = a.whole_row_md5) AS whole_row_identical,
       count(*) FILTER (WHERE b.whole_row_md5 <> a.whole_row_md5) AS whole_row_changed
  FROM public.cert0022_a_visitneeds a
  JOIN public.cert0022_a_after_b b USING (visit_id);

-- Rows that vanished or appeared -- a clobber would show as a row whose sim_run_id moved.
SELECT (SELECT count(*) FROM public.cert0022_a_visitneeds a
         WHERE NOT EXISTS (SELECT 1 FROM public.cert0022_a_after_b b WHERE b.visit_id=a.visit_id))
                                                                     AS run_a_rows_LOST,
       (SELECT count(*) FROM public.cert0022_a_after_b b
         WHERE NOT EXISTS (SELECT 1 FROM public.cert0022_a_visitneeds a WHERE a.visit_id=b.visit_id))
                                                                     AS run_a_rows_APPEARED;

-- Does a run-scoped query return ONLY that run's rows?
SELECT sim_run_id, count(*) AS rows_returned
  FROM public.ottoq_visit_needs
 WHERE sim_run_id = (SELECT sim_run_id FROM public.cert0022_a_runrow)
 GROUP BY 1;


-- -------------------------------------------------------------------------------------
-- (2) THE CROSS-RUN WRITE THAT SURVIVES 0022, reported because it is real.
--     `ottoq_sim_run_scenario` supersedes open/in_progress needs by DEPOT, run-blind, so
--     starting run B rewrites `status` on a FINISHED run A's rows. It cannot lose work
--     (0020 made uniqueness run-scoped and 0022 made the row's run un-droppable) and
--     'superseded' is an honest terminal label for a need that never completed -- but it
--     IS a later run reaching into an earlier run's ledger, and it is not fixed here.
-- -------------------------------------------------------------------------------------
SELECT a.status AS status_before_run_b, b.status AS status_after_run_b, count(*)
  FROM public.cert0022_a_visitneeds a JOIN public.cert0022_a_after_b b USING (visit_id)
 GROUP BY 1,2 ORDER BY 3 DESC;


-- -------------------------------------------------------------------------------------
-- (3) ORPHANS ARE NOT CREATABLE. Six deliberate attempts, including one on the table
--     whose FK is NOT VALID. A refusal here is a 23503 raised by the constraint itself,
--     not a NOT NULL or a unique index firing first and being misread as success.
-- -------------------------------------------------------------------------------------
SELECT target, probe, verdict, sqlstate, left(detail, 90) AS detail
  FROM public.cert0022_orphan_refusal ORDER BY target, probe;


-- -------------------------------------------------------------------------------------
-- (4) ORPHAN CENSUS, generated from the registry -- never a hand-written table list.
--     engine    -> must die with its run. Any orphan here is a defect.
--     stamp     -> vehicles.owning_sim_run_id, SET NULL, row is permanent.
--     evidence  -> exists IN ORDER to outlive its run. Orphans here are the POINT.
--     run_ledger-> ottoq_run_archives: the archive of a run that has been purged.
-- -------------------------------------------------------------------------------------
SELECT phase, class, count(*) AS tables_with_orphans, sum(orphan_rows) AS orphan_rows
  FROM public.cert0022_orphans_by_class GROUP BY 1,2 ORDER BY 1,2;

SELECT phase, class, table_name, column_name, orphan_rows, dead_runs
  FROM public.cert0022_orphans_by_class
 WHERE class IN ('engine','stamp','run_ledger') ORDER BY phase, class, orphan_rows DESC;


-- -------------------------------------------------------------------------------------
-- (5) PROTECT -- 0 orphaned FKs, key list GENERATED from pg_constraint.
-- -------------------------------------------------------------------------------------
SELECT phase, count(*) AS keys_with_orphans, sum(orphans) AS orphan_rows
  FROM public.cert0022_fk_orphan_sweep GROUP BY 1 ORDER BY 1;
SELECT * FROM public.cert0022_fk_orphan_sweep ORDER BY phase, orphans DESC;

-- PROTECT -- 0 double-bookings. OWN pairwise `during && during`, not the exclusion
-- constraint. Scoped WITHIN a run: two runs replaying the SAME sim_clock_start put two
-- different runs' bookings on the same stall at the same SIM instant by construction,
-- so a run-blind pairwise test measures the replayed clock, not a conflict.
SELECT 'A' AS run, count(*) AS overlapping_pairs_within_run
  FROM public.cert0022_a_bookings x JOIN public.cert0022_a_bookings y
    ON y.stall_id=x.stall_id AND y.booking_id>x.booking_id AND x.during && y.during
   AND x.sim_run_id = y.sim_run_id
   AND x.state IN ('held','active','done','interrupted')
   AND y.state IN ('held','active','done','interrupted')
UNION ALL
SELECT 'B', count(*)
  FROM public.cert0022_b_bookings x JOIN public.cert0022_b_bookings y
    ON y.stall_id=x.stall_id AND y.booking_id>x.booking_id AND x.during && y.during
   AND x.sim_run_id = y.sim_run_id
   AND x.state IN ('held','active','done','interrupted')
   AND y.state IN ('held','active','done','interrupted');

-- PROTECT -- 0010 geometry. Heading-aware oriented footprint. relative_x/relative_y are
-- in FEET; do NOT apply the 1.5699 conversion.
WITH fp AS (
  SELECT s.id, s.depot_id,
         st_rotate(st_makeenvelope(s.relative_x - s.stall_width_ft/2.0,
                                   s.relative_y - s.stall_depth_ft/2.0,
                                   s.relative_x + s.stall_width_ft/2.0,
                                   s.relative_y + s.stall_depth_ft/2.0, 0),
                   radians(s.heading_degrees::double precision), s.relative_x, s.relative_y) AS geom
    FROM public.stalls s)
SELECT (SELECT count(*) FROM fp) AS assessed,
       (SELECT count(*) FROM public.stalls
         WHERE relative_x IS NULL OR relative_y IS NULL OR heading_degrees IS NULL
            OR stall_width_ft IS NULL OR stall_depth_ft IS NULL) AS not_assessed,
       (SELECT count(*) FROM fp a JOIN fp b ON b.depot_id=a.depot_id AND b.id>a.id
         AND st_intersects(a.geom,b.geom)
         AND st_area(st_intersection(a.geom,b.geom))>0.01) AS overlapping_pairs;

SELECT depot_id, count(*) AS total, stall_type::text, count(*) AS n
  FROM public.stalls GROUP BY depot_id, stall_type ORDER BY depot_id, n DESC;

-- PROTECT -- 0008 laundering, DIRECTIONAL. Naive value-equality flags 0.000 = 0.000 on
-- freshly-washed cars; that is NOT laundering.
SELECT count(*) AS pairs,
       count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)) AS naive_value_equality,
       count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)
                          AND NOT (p.exterior_soil_level = 0 AND round(w.soil_index,3) = 0))
         AS real_copied_nonzero
  FROM public.vehicle_need_profile p JOIN public.ottoq_vehicle_wear w USING (vehicle_id);

-- PROTECT -- 0009 planned_return_at is a STORED GENERATED column, so any write raises 428C9.
SELECT attname, attgenerated
  FROM pg_attribute
 WHERE attrelid='public.ottoq_vehicle_dispatches'::regclass AND attname='planned_return_at';
SELECT v AS probe_result FROM public.cert0022_misc WHERE k='0009_planned_return_at_sqlstate';

-- PROTECT -- cron 10/11/12 ON, 13 OFF. NEVER disable cron 12 -- it IS the START engine.
SELECT jobid, active, left(command,45) AS cmd FROM cron.job ORDER BY jobid;

-- PROTECT -- run-scope registry drift guard. 0 rows = 0 defects.
SELECT * FROM public.ottoq_check_run_scope_registry();


-- -------------------------------------------------------------------------------------
-- (6) RIDER FLAGS -- 0 silent drops (the 0020 guarantee). Every non-pending flag must be
--     bound to a visit that EXISTS, on the RIGHT vehicle, in the RIGHT run, carrying the
--     atom. `recalled_visit_id` is a real FK column, so "points at nothing" is now
--     structurally impossible -- this re-measures it anyway rather than assuming.
-- -------------------------------------------------------------------------------------
SELECT run, status, count(*) AS flags,
       count(*) FILTER (WHERE recalled_visit_id IS NOT NULL)      AS bound_to_visit,
       count(*) FILTER (WHERE visit_missing)                      AS SILENT_DROP_visit_missing,
       count(*) FILTER (WHERE wrong_vehicle)                      AS SILENT_DROP_wrong_vehicle,
       count(*) FILTER (WHERE wrong_run)                          AS SILENT_DROP_wrong_run,
       count(*) FILTER (WHERE atom_missing)                       AS SILENT_DROP_atom_missing
  FROM (
    SELECT 'A' AS run, f.status, f.recalled_visit_id,
           (f.recalled_visit_id IS NOT NULL AND NOT EXISTS
              (SELECT 1 FROM public.cert0022_a_visitneeds v WHERE v.visit_id=f.recalled_visit_id)) AS visit_missing,
           (f.recalled_visit_id IS NOT NULL AND EXISTS
              (SELECT 1 FROM public.cert0022_a_visitneeds v WHERE v.visit_id=f.recalled_visit_id
                 AND v.vehicle_id <> f.vehicle_id))                                                 AS wrong_vehicle,
           (f.recalled_visit_id IS NOT NULL AND EXISTS
              (SELECT 1 FROM public.cert0022_a_visitneeds v WHERE v.visit_id=f.recalled_visit_id
                 AND v.sim_run_id IS DISTINCT FROM f.sim_run_id))                                   AS wrong_run,
           (f.recalled_visit_id IS NOT NULL AND NOT EXISTS
              (SELECT 1 FROM public.cert0022_a_visitneeds v, jsonb_array_elements(v.atoms) a
                WHERE v.visit_id=f.recalled_visit_id AND a->>'rider_flagged'='true'))               AS atom_missing
      FROM public.cert0022_a_flags f
    UNION ALL
    SELECT 'B', f.status, f.recalled_visit_id,
           (f.recalled_visit_id IS NOT NULL AND NOT EXISTS
              (SELECT 1 FROM public.cert0022_b_visitneeds v WHERE v.visit_id=f.recalled_visit_id)),
           (f.recalled_visit_id IS NOT NULL AND EXISTS
              (SELECT 1 FROM public.cert0022_b_visitneeds v WHERE v.visit_id=f.recalled_visit_id
                 AND v.vehicle_id <> f.vehicle_id)),
           (f.recalled_visit_id IS NOT NULL AND EXISTS
              (SELECT 1 FROM public.cert0022_b_visitneeds v WHERE v.visit_id=f.recalled_visit_id
                 AND v.sim_run_id IS DISTINCT FROM f.sim_run_id)),
           (f.recalled_visit_id IS NOT NULL AND NOT EXISTS
              (SELECT 1 FROM public.cert0022_b_visitneeds v, jsonb_array_elements(v.atoms) a
                WHERE v.visit_id=f.recalled_visit_id AND a->>'rider_flagged'='true'))
      FROM public.cert0022_b_flags f) t
 GROUP BY 1,2 ORDER BY 1,2;

-- DISPATCH CHURN. The naive metric lies: a flag row keeps raised_at forever, so
-- `dispatched_at >= raised` catches every later legitimate dispatch of a car whose
-- cleaning already finished. The honest test is whether the flag was still UNCONSUMED.
WITH j AS (
  SELECT 'A' AS run, d.dispatched_at, f.raised_at_sim_clock AS raised, f.recalled_at_sim_clock AS consumed
    FROM public.cert0022_a_dispatches d JOIN public.cert0022_a_flags f ON f.vehicle_id=d.vehicle_id
  UNION ALL
  SELECT 'B', d.dispatched_at, f.raised_at_sim_clock, f.recalled_at_sim_clock
    FROM public.cert0022_b_dispatches d JOIN public.cert0022_b_flags f ON f.vehicle_id=d.vehicle_id)
SELECT run, count(*) AS flag_linked_dispatches,
       count(*) FILTER (WHERE dispatched_at >= raised) AS naive_after_raise_MISLEADING,
       count(*) FILTER (WHERE dispatched_at >= raised
                          AND (consumed IS NULL OR dispatched_at < consumed)) AS dispatched_while_flag_PENDING
  FROM j GROUP BY 1 ORDER BY 1;

-- RECALL LATENCY -- flag due -> returning_started_at. Bound = 0 over one 30-min tick.
-- "Early vs planned_return_at" is a BROKEN acceptance test (the fleet runs ~4x past that
-- nominal plan) and is deliberately not used.
WITH r AS (
  SELECT 'A' AS run, round(extract(epoch FROM (d.returning_started_at - f.raised_at_sim_clock))/60) AS latency
    FROM public.cert0022_a_dispatches d JOIN public.cert0022_a_flags f ON f.vehicle_id=d.vehicle_id
   WHERE d.return_trigger='rider_flag_cleaning' AND d.returning_started_at IS NOT NULL
  UNION ALL
  SELECT 'B', round(extract(epoch FROM (d.returning_started_at - f.raised_at_sim_clock))/60)
    FROM public.cert0022_b_dispatches d JOIN public.cert0022_b_flags f ON f.vehicle_id=d.vehicle_id
   WHERE d.return_trigger='rider_flag_cleaning' AND d.returning_started_at IS NOT NULL)
SELECT run, count(*) AS n,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY latency)) AS median_latency_min,
       max(latency) AS max_latency_min,
       count(*) FILTER (WHERE latency > 30) AS over_one_tick
  FROM r GROUP BY 1 ORDER BY 1;

-- PLACED vs CLEANED, reported separately. "placed" is not "cleaned".
SELECT run, count(*) AS rider_flagged_atoms,
       count(*) FILTER (WHERE st='done')                    AS CLEANED_done,
       count(*) FILTER (WHERE st IS DISTINCT FROM 'done')   AS PLACED_not_done
  FROM (
    SELECT 'A' AS run, a->>'status' AS st FROM public.cert0022_a_visitneeds v,
           jsonb_array_elements(v.atoms) a WHERE a->>'rider_flagged'='true'
    UNION ALL
    SELECT 'B', a->>'status' FROM public.cert0022_b_visitneeds v,
           jsonb_array_elements(v.atoms) a WHERE a->>'rider_flagged'='true') t
 GROUP BY 1 ORDER BY 1;


-- -------------------------------------------------------------------------------------
-- (7) ALWAYS HOLD. Measured PRE-STOP (STOP empties the depot). PRE-EXISTING at 4/73-7/82
--     with the same four ids (4cd2b777, 9926e267, c433a36d, c98ef465), zero bookings
--     anywhere, none rider-flagged. Cause is twin.ottoq_sim_seed_fleet seating the fleet
--     at run start and writing no booking row. FILED, NOT A REVERT TRIGGER -- the only
--     question this asks is whether it got WORSE.
-- -------------------------------------------------------------------------------------
SELECT run, seated, defects, round(100.0*defects/NULLIF(seated,0),1) AS pct
  FROM (
    SELECT 'A' AS run, count(*) AS seated,
           count(*) FILTER (WHERE NOT EXISTS (
             SELECT 1 FROM public.cert0022_a_bookings b
              WHERE b.stall_id=s.id AND b.vehicle_id=s.current_vehicle_id
                AND b.state IN ('held','active','done'))) AS defects
      FROM public.cert0022_a_stalls s WHERE s.current_vehicle_id IS NOT NULL
    UNION ALL
    SELECT 'B', count(*),
           count(*) FILTER (WHERE NOT EXISTS (
             SELECT 1 FROM public.cert0022_b_bookings b
              WHERE b.stall_id=s.id AND b.vehicle_id=s.current_vehicle_id
                AND b.state IN ('held','active','done')))
      FROM public.cert0022_b_stalls s WHERE s.current_vehicle_id IS NOT NULL) t
 ORDER BY run;

-- The four known ids must still be the four known ids, and still hold zero bookings.
SELECT run, veh, bookings_anywhere, rider_flags FROM (
  SELECT 'A' AS run, left(s.current_vehicle_id::text,8) AS veh,
         (SELECT count(*) FROM public.cert0022_a_bookings b WHERE b.vehicle_id=s.current_vehicle_id) AS bookings_anywhere,
         (SELECT count(*) FROM public.cert0022_a_flags f WHERE f.vehicle_id=s.current_vehicle_id)    AS rider_flags
    FROM public.cert0022_a_stalls s WHERE s.current_vehicle_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.cert0022_a_bookings b
                      WHERE b.stall_id=s.id AND b.vehicle_id=s.current_vehicle_id
                        AND b.state IN ('held','active','done'))) t
 ORDER BY veh;


-- -------------------------------------------------------------------------------------
-- (8) THE PURGE, on the real path. `ottoq_start_demo_run` (the normal start button) calls
--     ottoq_purge_prior_runs at the end, so run C exercised it for real against runs A
--     and B. NO ACTION means that if the children-first sweep missed one table, the
--     parent DELETE RAISES 23503 instead of silently orphaning -- so a clean receipt with
--     a non-zero row count is the positive result, and an exception would have been the
--     negative one.
-- -------------------------------------------------------------------------------------
SELECT * FROM public.cert0022_purge_receipt ORDER BY at_ts;


-- -------------------------------------------------------------------------------------
-- (9) INSTANCE HEALTH. Probed with a plpgsql LOOP, not a CTE -- a CTE is evaluated once
--     and yields ten identical values. Healthy ~190-205 ms; it has shown 17,748 ms of
--     host starvation. The first sample includes cold-cache cost and is not the signal.
-- -------------------------------------------------------------------------------------
SELECT v AS instance_probe_ms FROM public.cert0022_misc WHERE k='instance_probe_ms';
