-- =====================================================================================
-- 0023_finished_run_readonly_certification.sql
--
-- WHAT THIS IS. The re-runnable battery behind
-- db/evidence/P0023_finished_run_readonly_certification.md -- the certification of
-- migration 0023 (`a_finished_run_is_read_only`, ledger 20260808193142) against live runs.
--
-- READ-ONLY. Creates nothing, drops nothing, starts no run. It reads the evidence tables
-- captured during the certification.
--
-- WHAT 0023 CLAIMS, IN ONE LINE EACH
--   (1) A run closes its OWN needs at its OWN terminal transition (trigger
--       ottoq_sim_runs_close_needs -> ottoq_close_run_needs), so a later run never has to.
--   (2) The start-time supersede is narrowed to OWNERLESS needs (sim_run_id IS NULL).
--   (3) A run-scoped energy read takes the run it is ASKED about, not the globally newest.
--
-- THE TRILOGY. 0020 fixed WHICH row a run writes. 0022 fixed WHETHER a row still has a
-- run. 0023 fixes a run writing into ANOTHER run's rows.
--
-- THE RUNS
--   RUN A  seed 20260840  ottoq_sim_run_scenario('normal_day', 20260840, 'operator_demo')
--   RUN B  seed 20260841  ottoq_sim_run_scenario('normal_day', 20260841, 'operator_demo')
--   Both start at 08:00:00 CST on the same real calendar day, because run_scenario pins
--   sim_clock_start to date_trunc('day', now() AT TIME ZONE 'America/Chicago') + 8h for
--   run_by='operator_demo'. Nothing was rigged: the collision is the shipped default.
--   Fixed playback, 30 sim-min per tick (ottoq_api_twin_get_state reports
--   sim_minutes_per_tick = 30.0), 48 ticks = 08:00 -> 08:00. Night = 20:00-06:00 CST.
--
-- CLOCK DOMAINS, stated once.
--   SIM domain : sim_clock_*, arrived_at, dispatch_due_at, raised_at_sim_clock,
--                recalled_at_sim_clock (nominally), booking `during`.
--   REAL domain: started_at, ended_at, created_at, captured_real, at_ts,
--                meta.closed_at (now() inside ottoq_close_run_needs).
--   TEARDOWN ROWS: ottoq_sim_stop_and_reset writes the REAL wall clock into the
--   sim-domain actual_return_at. Runs A and B were NEVER stopped -- both reached
--   status='completed' on their own at sim_clock_end -- so no teardown row exists to
--   exclude from either. That is a fact about these runs, not a filter.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- (0) THE STOP PATH, measured on a real live run before the A/B pair.
--     Before 0023, ottoq_sim_stop_and_reset did not touch ottoq_visit_needs AT ALL
--     (pg_get_functiondef ILIKE '%ottoq_visit_needs%' -> false), so a properly stopped
--     run left its needs open forever and only the NEXT run's start ever closed them.
-- -------------------------------------------------------------------------------------
SELECT count(*) AS rows_at_stop,
       count(*) FILTER (WHERE status IN ('open','in_progress')) AS open_at_stop
  FROM public.cert0023_stop_pre;
-- (Run 947's rows themselves were purged with the run; the pre-image above is the record,
--  and the post-stop verdict was: 40 of 40 superseded, 40 stamped closed_by=
--  ottoq_close_run_needs, close_reason='run_completed', 0 left open.)


-- -------------------------------------------------------------------------------------
-- (1) THE ASSERTION. Colliding keys FIRST -- zero collisions would make this VACUOUS.
-- -------------------------------------------------------------------------------------
SELECT count(*) AS colliding_visit_keys_byte_identical,
       count(DISTINCT a.vehicle_id) AS vehicles_involved
  FROM public.cert0023_a_visitneeds a
  JOIN public.cert0023_b_visitneeds b
    ON b.visit_key = a.visit_key AND b.sim_run_id <> a.sim_run_id;

-- Column by column. A whole-row md5 can hide a difference behind a hash, so every one of
-- the 15 columns is compared on its own. `status` is the column 0022 measured moving on
-- 99 of 182 rows; it is in this list on the same footing as the rest.
SELECT phase, column_name, rows_compared, differing_rows
  FROM public.cert0023_coldiff ORDER BY phase, differing_rows DESC, column_name;

-- Rows lost or gained -- a clobber would show as a row whose sim_run_id moved.
SELECT (SELECT count(*) FROM public.cert0023_a_visitneeds a
         WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs t WHERE t.visit_id=a.visit_id))
                                                                     AS run_a_rows_LOST,
       (SELECT count(*) FROM public.ottoq_visit_needs t
         WHERE t.sim_run_id=(SELECT sim_run_id FROM public.cert0023_a_runrow)
           AND NOT EXISTS (SELECT 1 FROM public.cert0023_a_visitneeds a WHERE a.visit_id=t.visit_id))
                                                                     AS run_a_rows_APPEARED;


-- -------------------------------------------------------------------------------------
-- (2) WHERE THE STATUS MOVE WENT. It did not disappear -- closing an open need when a run
--     ends is correct and necessary. 0023 moves it from "the next run's depot-wide sweep"
--     to "this run's own terminal transition", and stamps it so it is attributable.
-- -------------------------------------------------------------------------------------
SELECT r.status AS status_mid_run, a.status AS status_at_terminal, count(*)
  FROM public.cert0023_a_running r JOIN public.cert0023_a_visitneeds a USING (visit_id)
 GROUP BY 1,2 ORDER BY 3 DESC;

SELECT meta->>'closed_by' AS closed_by, meta->>'close_reason' AS close_reason, count(*)
  FROM public.cert0023_a_visitneeds GROUP BY 1,2 ORDER BY 3 DESC;


-- -------------------------------------------------------------------------------------
-- (3) THE ENERGY READS. Probed live, both depots.
--     TOTAL BEHAVIOUR: a run with no snapshot of its own gets JSON null -- never another
--     run's row, never a depot-wide row, never a default, and it does not raise.
-- -------------------------------------------------------------------------------------
SELECT k, v FROM public.cert0023_energy_probe ORDER BY k;

-- The NULL-run rows are excluded BY CONSTRUCTION: `se.sim_run_id = <uuid>` is NULL, not
-- TRUE, for every one of them. This is not academic -- the newest row at depot 1111 by
-- sim timestamp is an untagged row dated 2026-08-15, a sim WEEK past the live run's clock.
SELECT depot_id, sim_run_id IS NULL AS untagged, count(*) AS n, max(timestamp) AS newest
  FROM public.site_energy_snapshots GROUP BY 1,2 ORDER BY 1,2;

-- Every caller now passes the run it was asked about.
SELECT p.proname,
       substring(pg_get_functiondef(p.oid) FROM 'ottoq_build_decision_frame\s*\([^)]*\)') AS call_site
  FROM pg_proc p
 WHERE p.pronamespace='public'::regnamespace AND p.prokind='f'
   AND p.proname <> 'ottoq_build_decision_frame'
   AND pg_get_functiondef(p.oid) ILIKE '%ottoq_build_decision_frame%'
 ORDER BY 1;


-- -------------------------------------------------------------------------------------
-- (4) PROTECT. Re-measured; a regression here is a HARD FAIL.
-- -------------------------------------------------------------------------------------
-- 0 orphaned FKs. Key list GENERATED from pg_constraint, never hand-written.
-- The ONLY accepted orphans are the 2 declared ottoq_events rows behind a NOT VALID FK.
SELECT phase, count(*) AS keys, sum(orphans) AS orphan_rows,
       count(*) FILTER (WHERE orphans>0) AS keys_with_orphans
  FROM public.cert0023_fk_orphan_sweep GROUP BY 1 ORDER BY 1;
SELECT phase, conname, child, parent, orphans
  FROM public.cert0023_fk_orphan_sweep WHERE orphans>0 ORDER BY phase, orphans DESC;

-- 0 double-bookings: OWN pairwise `during && during`, WITHIN a run (not the exclusion
-- constraint). Run-blind pairwise would measure the replayed clock, not a conflict.
SELECT 'A' AS run, count(*) AS overlapping_pairs_within_run
  FROM public.cert0023_a_bookings x JOIN public.cert0023_a_bookings y
    ON y.stall_id=x.stall_id AND y.booking_id>x.booking_id AND x.during && y.during
   AND x.sim_run_id=y.sim_run_id
   AND x.state IN ('held','active','done','interrupted')
   AND y.state IN ('held','active','done','interrupted')
UNION ALL
SELECT 'B', count(*)
  FROM public.cert0023_b_bookings x JOIN public.cert0023_b_bookings y
    ON y.stall_id=x.stall_id AND y.booking_id>x.booking_id AND x.during && y.during
   AND x.sim_run_id=y.sim_run_id
   AND x.state IN ('held','active','done','interrupted')
   AND y.state IN ('held','active','done','interrupted');

-- 0010 geometry. Heading-aware oriented footprint. relative_x/y are in FEET -- do NOT
-- apply the 1.5699 conversion.
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
SELECT depot_id, stall_type::text, count(*) FROM public.stalls GROUP BY 1,2 ORDER BY 1,3 DESC;

-- 0008 laundering, DIRECTIONAL. Naive value-equality flags 0.000=0.000 on freshly-washed
-- cars; that is NOT laundering.
SELECT count(*) AS pairs,
       count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)) AS naive_value_equality,
       count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)
                          AND NOT (p.exterior_soil_level = 0 AND round(w.soil_index,3) = 0))
         AS real_copied_nonzero
  FROM public.vehicle_need_profile p JOIN public.ottoq_vehicle_wear w USING (vehicle_id);

-- 0009 planned_return_at is STORED GENERATED, so any write raises 428C9.
SELECT attname, attgenerated FROM pg_attribute
 WHERE attrelid='public.ottoq_vehicle_dispatches'::regclass AND attname='planned_return_at';
SELECT v AS probe_result FROM public.cert0023_misc WHERE k='0009_planned_return_at_sqlstate';

-- cron 10/11/12 ON, 13 OFF. NEVER disable cron 12 -- it IS the START engine.
SELECT jobid, active, left(command,45) AS cmd FROM cron.job ORDER BY jobid;

-- 0022's run-scope registry drift guard. 0 rows = 0 defects.
SELECT * FROM public.ottoq_check_run_scope_registry();

-- Drift: routine counts against the committed baseline in scripts/check-drift.sql.
SELECT sch, live_n, CASE sch WHEN 'public' THEN 349 WHEN 'ottoq' THEN 55 WHEN 'twin' THEN 71 END AS baseline_n
  FROM (SELECT n.nspname::text AS sch, count(*)::int AS live_n
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname IN ('public','ottoq','twin')
           AND NOT EXISTS (SELECT 1 FROM pg_depend dd WHERE dd.objid=p.oid AND dd.deptype='e')
         GROUP BY 1) t ORDER BY sch;
