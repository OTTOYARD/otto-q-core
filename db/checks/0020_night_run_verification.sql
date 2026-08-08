-- =====================================================================================
-- 0020_night_run_verification.sql
--
-- WHAT THIS IS. The re-runnable battery behind db/evidence/P0020_night_run_proof.md:
-- the first execution of migration 0019 (`rider_flag_holds_the_vehicle`, ledger
-- 20260808153457) against live simulation runs. 0019 shipped with its gates proven
-- STRUCTURALLY and its outcome unproven; this is the outcome.
--
-- READ-ONLY. Creates nothing, drops nothing, starts no run.
--
-- THE RUNS (both crossed 20:00-06:00; night = ticks 24..44 of 48)
--   R1  a30661fd-e8c5-4fd5-8f6e-1915cd02da30  seed 20260820  rider_flag_daily_pct 3.0
--                                             (shipped default)          2 flags
--   R2  b857fd29-c726-4d41-8686-c198b4293796  seed 20260821  rider_flag_daily_pct 12.0
--                                             (raised for denominator,
--                                              restored to 3.0 immediately after)
--                                                                       16 flags
--
-- HOW NIGHT WAS REACHED, AND WHY IT MATTERS FOR THE FLAG CLOCK.
--   ottoq_start_demo_run forces `live` playback (ottoq_set_playback clamps to 3x, so a
--   demo run cannot reach night) AND rebases sim_clock_start to a random minute-of-day
--   AFTER ottoq_run_boot_draw has already anchored every rider flag's
--   raised_at_sim_clock to the pre-rebase start. That anchoring defect is why the 0019
--   evidence run produced ZERO flag-linked recalls.
--   These runs call ottoq_sim_run_scenario('normal_day', <seed>, 'operator_demo')
--   DIRECTLY: no rebase, playback stays fixed (30 sim-min/tick), and the metronome
--   still drives it because it skips only 'production_live' and 'cert_harness'.
--   No code was changed to do this.
--
-- TEARDOWN CONTAMINATION: none, and not by filtering. Both runs reached
-- status='completed' on their own at sim_clock_end and were NEVER stopped, so
-- ottoq_sim_stop_and_reset never wrote a real wall clock into actual_return_at.
--
-- EVIDENCE TABLES (do not drop):
--   p0020_prestop_r1_{runrow,dispatches,flags,bookings,visitneeds,vehicles,stalls}
--   p0020_prestop_r2_{...same...}, p0020_alwayshold_r1, p0020_r2_flags_t0
-- All captured at tick 48, PRE-stop.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- (1) DISPATCH CHURN -- the defect 0019 exists to kill.
--     BASELINE (0018-era): 9 of 10 flag-linked dispatches went out with the flag due.
--     ANSWER: 0 of 33.
--
--     ⚠️ THE NAIVE METRIC LIES. `dispatched_at >= raised_at_sim_clock` catches every
--     LATER, LEGITIMATE dispatch of a car whose cleaning already finished, because the
--     flag row keeps raised_at forever (12 of 33 here; all had the clean done first).
--     The gate keys on status='pending', so the honest test is whether the flag was
--     still UNCONSUMED at that instant.
-- -------------------------------------------------------------------------------------
WITH j AS (
  SELECT 'R1' AS run, d.return_trigger, d.dispatched_at,
         f.raised_at_sim_clock AS raised, f.recalled_at_sim_clock AS consumed
    FROM public.p0020_prestop_r1_dispatches d
    JOIN public.p0020_prestop_r1_flags f ON f.vehicle_id = d.vehicle_id
  UNION ALL
  SELECT 'R2', d.return_trigger, d.dispatched_at,
         f.raised_at_sim_clock, f.recalled_at_sim_clock
    FROM public.p0020_prestop_r2_dispatches d
    JOIN public.p0020_prestop_r2_flags f ON f.vehicle_id = d.vehicle_id)
SELECT run,
       count(*)                                                        AS flag_linked_dispatches,
       count(*) FILTER (WHERE dispatched_at >= raised)                 AS naive_after_raise_MISLEADING,
       count(*) FILTER (WHERE dispatched_at >= raised
                          AND (consumed IS NULL OR dispatched_at < consumed))
                                                                       AS dispatched_while_flag_PENDING,
       count(*) FILTER (WHERE return_trigger = 'rider_flag_cleaning')  AS recall_dispatches
  FROM j GROUP BY 1 ORDER BY 1;


-- -------------------------------------------------------------------------------------
-- (2) 🔴 THE STATED CRITERION: do flagged dispatches turn back EARLY vs planned_return_at?
--     ANSWER: NO AS POSED -- 2 of 10 early, median 138 min LATE.
--     AND THE CRITERION IS CONFOUNDED: 8 of the 10 had their flag mature AFTER
--     planned_return_at had already passed (+1 to +409 min), where "early" is
--     arithmetically impossible.
--
--     ROOT CAUSE, and it applies to EVERY trigger: planned_return_at is
--     dispatched_at + planned_duration_min, a drawn nominal plan the system never
--     schedules against. In R1 the median plan was 65 min and the median actual
--     deployment before turning back was 275 min -- ~4x past plan, fleet-wide.
--
--     `verdict` splits the fair subset from the impossible one.
-- -------------------------------------------------------------------------------------
WITH r AS (
  SELECT left(d.vehicle_id::text, 8) AS veh,
         d.planned_duration_min::int AS plan_min,
         round(extract(epoch FROM (f.raised_at_sim_clock - d.planned_return_at))/60)   AS flag_due_minus_plan,
         round(extract(epoch FROM (d.returning_started_at - f.raised_at_sim_clock))/60) AS recall_latency_min,
         round(extract(epoch FROM (d.planned_return_at - d.returning_started_at))/60)   AS early_vs_plan_min
    FROM public.p0020_prestop_r2_dispatches d
    JOIN public.p0020_prestop_r2_flags f ON f.vehicle_id = d.vehicle_id
   WHERE d.return_trigger = 'rider_flag_cleaning'
     AND d.returning_started_at IS NOT NULL)
SELECT veh, plan_min, flag_due_minus_plan, recall_latency_min, early_vs_plan_min,
       CASE WHEN flag_due_minus_plan > 0 THEN 'plan already lapsed - early impossible'
            ELSE 'FAIR TEST' END AS verdict
  FROM r ORDER BY flag_due_minus_plan;

-- The measure that is NOT confounded: how fast the recall fires once the flag matures.
-- ANSWER: median 6 min, max 28 min, 0 of 10 over one 30-min tick.
-- ⚠️ TICK GRANULARITY: returning_started_at is quantised to the 30 sim-min tick grid,
--    so any "early" under 30 min is indistinguishable from quantisation. Of the two
--    fair-test earlies, +60 min (2 ticks) survives this and +16 min does NOT.
WITH r AS (
  SELECT round(extract(epoch FROM (d.returning_started_at - f.raised_at_sim_clock))/60) AS latency
    FROM public.p0020_prestop_r2_dispatches d
    JOIN public.p0020_prestop_r2_flags f ON f.vehicle_id = d.vehicle_id
   WHERE d.return_trigger = 'rider_flag_cleaning' AND d.returning_started_at IS NOT NULL)
SELECT count(*) AS n,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY latency)) AS median_latency_min,
       max(latency)                                                AS max_latency_min,
       count(*) FILTER (WHERE latency > 30)                        AS over_one_tick
  FROM r;


-- -------------------------------------------------------------------------------------
-- (3) 🔴 NEW DEFECT -- A FLAG CONSUMED WHOSE WORK NEVER LANDED.  2 of 16, both EXTERIOR.
--     f0077a3a and 99ddf4ff were recalled, advanced to status='recalled', stamped with a
--     recalled_visit_key -- and carry NO rider-flagged atom on any visit. Both ended
--     `staged_for_departure`, free to redeploy, dirty.
--
--     WORSE THAN THE DEFECT IT REPLACED. 0018 left 2 of 18 stuck 'pending' -- visibly
--     unfired. This leaves 2 of 16 marked 'recalled' -- the ledger says handled and
--     nothing was done. It is SILENT. It also contradicts the premise 0019's judgement
--     call rests on ("at the instant the flag is consumed it has become a must_do atom
--     on an open visit"): here ownership lapsed.
--
--     NOT ROOT-CAUSED. Lead: visit_key time base. twin.ottoq_sim_generate_service_manifest
--     builds visit_key from vehicles.last_state_change, which a BEFORE UPDATE trigger
--     clobbers to the REAL clock, while these two recalled_visit_key values
--     (...20260808200000, ...20260809010000) decode as SIM times matching the flag's own
--     maturity. Two clock domains in one key space would explain a key pointing at
--     nothing. Needs its own migration.
-- -------------------------------------------------------------------------------------
WITH best AS (
  SELECT vn.vehicle_id,
         max(CASE WHEN a->>'status' = 'done' THEN 2
                  WHEN a->>'status' IS NULL  THEN 1 ELSE 0 END) AS rank
    FROM public.p0020_prestop_r2_visitneeds vn
    CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
   WHERE a->>'rider_flagged' = 'true'
   GROUP BY 1)
SELECT f.flag_kind,
       count(*)                                        AS flags,
       count(*) FILTER (WHERE b.rank = 2)              AS atom_done,
       count(*) FILTER (WHERE b.rank = 1)              AS atom_placed_unfinished,
       count(*) FILTER (WHERE b.vehicle_id IS NULL)    AS NO_ATOM_AT_ALL,
       count(*) FILTER (WHERE f.recalled_visit_key IS NOT NULL
                          AND NOT EXISTS (SELECT 1 FROM public.p0020_prestop_r2_visitneeds vn
                                           WHERE vn.visit_key = f.recalled_visit_key))
                                                       AS visit_key_points_at_NOTHING
  FROM public.p0020_prestop_r2_flags f
  LEFT JOIN best b ON b.vehicle_id = f.vehicle_id
 GROUP BY 1 ORDER BY 1;


-- -------------------------------------------------------------------------------------
-- (4) ONE RAISE, ONE FIRING.  ANSWER: YES -- 0 double-recalls, 0 atoms on two visits,
--     in BOTH runs. The 0018 residual (one car carrying the atom on two visits) did not
--     recur. Baseline: 1 car was recalled twice over 16 sim-hours.
-- -------------------------------------------------------------------------------------
WITH x AS (
  SELECT 'R1' AS run, f.vehicle_id,
         (SELECT count(*) FROM public.p0020_prestop_r1_dispatches d
           WHERE d.vehicle_id = f.vehicle_id AND d.return_trigger = 'rider_flag_cleaning') AS recalls,
         (SELECT count(*) FROM public.p0020_prestop_r1_visitneeds vn
           WHERE vn.vehicle_id = f.vehicle_id
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'rider_flagged' = 'true'))                            AS visits
    FROM public.p0020_prestop_r1_flags f
  UNION ALL
  SELECT 'R2', f.vehicle_id,
         (SELECT count(*) FROM public.p0020_prestop_r2_dispatches d
           WHERE d.vehicle_id = f.vehicle_id AND d.return_trigger = 'rider_flag_cleaning'),
         (SELECT count(*) FROM public.p0020_prestop_r2_visitneeds vn
           WHERE vn.vehicle_id = f.vehicle_id
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'rider_flagged' = 'true'))
    FROM public.p0020_prestop_r2_flags f)
SELECT run, count(*) AS flags,
       count(*) FILTER (WHERE recalls > 1) AS recalled_twice,
       count(*) FILTER (WHERE visits  > 1) AS atom_on_multiple_visits
  FROM x GROUP BY 1 ORDER BY 1;


-- -------------------------------------------------------------------------------------
-- (5) MAPPING TOTALITY. Every atom that needs a bay resolves to a stall type that EXISTS;
--     unrecognised names return NULL = "no bay required", never a demand for a stall type
--     that does not exist. detail folds onto wash_bay because there are 0 detail_bay
--     stalls, so interior and exterior flags compete for the SAME three bays.
-- -------------------------------------------------------------------------------------
WITH probe(svc) AS (
  VALUES ('exterior_wash'),('interior_deep_clean'),('cosmetic_repair'),('fault_repair'),
         ('mechanical_pm'),('sensor_calibration'),('charge'),('readiness_check'),
         ('detail'),('wash'),(''),('a_totally_unknown_atom_name'))
SELECT p.svc,
       ottoq.ottoq_svc_to_stall_type(p.svc, '11111111-1111-1111-1111-111111111111') AS resolved,
       EXISTS (SELECT 1 FROM public.stalls s
                WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
                  AND s.stall_type::text = ottoq.ottoq_svc_to_stall_type(
                        p.svc, '11111111-1111-1111-1111-111111111111'))                AS stall_type_exists
  FROM probe p ORDER BY 2 NULLS LAST, 1;


-- -------------------------------------------------------------------------------------
-- (6) PROTECT. 0 double-bookings (own pairwise `during && during`, NOT the exclusion
--     constraint) over 1,199 (R1) and 1,143 (R2) bookings.
-- -------------------------------------------------------------------------------------
SELECT 'R1' AS run, count(*) AS overlapping_pairs
  FROM public.p0020_prestop_r1_bookings x
  JOIN public.p0020_prestop_r1_bookings y
    ON y.stall_id = x.stall_id AND y.booking_id > x.booking_id AND x.during && y.during
   AND x.state IN ('held','active','done','interrupted')
   AND y.state IN ('held','active','done','interrupted')
UNION ALL
SELECT 'R2', count(*)
  FROM public.p0020_prestop_r2_bookings x
  JOIN public.p0020_prestop_r2_bookings y
    ON y.stall_id = x.stall_id AND y.booking_id > x.booking_id AND x.during && y.during
   AND x.state IN ('held','active','done','interrupted')
   AND y.state IN ('held','active','done','interrupted');

-- PROTECT. 0010 geometry -- heading-aware oriented footprint. relative_x/relative_y are
--          in FEET; do NOT apply the 1.5699 conversion.
--          ANSWER: 320 assessed, 0 not_assessed, 0 overlapping pairs.
WITH fp AS (
  SELECT s.id, s.depot_id,
         st_rotate(st_makeenvelope(s.relative_x - s.stall_width_ft/2.0,
                                   s.relative_y - s.stall_depth_ft/2.0,
                                   s.relative_x + s.stall_width_ft/2.0,
                                   s.relative_y + s.stall_depth_ft/2.0, 0),
                   radians(s.heading_degrees::double precision),
                   s.relative_x, s.relative_y) AS geom
    FROM public.stalls s)
SELECT (SELECT count(*) FROM fp) AS assessed,
       (SELECT count(*) FROM public.stalls
         WHERE relative_x IS NULL OR relative_y IS NULL OR heading_degrees IS NULL
            OR stall_width_ft IS NULL OR stall_depth_ft IS NULL) AS not_assessed,
       (SELECT count(*) FROM fp a JOIN fp b
          ON b.depot_id = a.depot_id AND b.id > a.id
         AND st_intersects(a.geom, b.geom)
         AND st_area(st_intersection(a.geom, b.geom)) > 0.01)    AS overlapping_pairs;

-- PROTECT. 0008 laundering, DIRECTIONAL. ANSWER: 421 pairs, 2 naive value-equality,
--          0 directional -- and both naive hits are 0.000 = 0.000 on freshly-washed cars,
--          which is exactly the trap the brief warns about.
SELECT count(*) AS pairs,
       count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)) AS naive_value_equality,
       count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)
                          AND NOT (p.exterior_soil_level = 0 AND round(w.soil_index,3) = 0))
         AS real_copied_nonzero
  FROM public.vehicle_need_profile p JOIN public.ottoq_vehicle_wear w USING (vehicle_id);

-- PROTECT. cron 10/11/12 ON, 13 OFF. NEVER disable cron 12 -- it IS the START engine.
SELECT jobid, active, left(command, 45) AS cmd FROM cron.job ORDER BY jobid;


-- -------------------------------------------------------------------------------------
-- (7) 🔴 ALWAYS HOLD -- STILL BREACHED, AND NOW DEFINITIVELY PRE-EXISTING.
--     R1: 5 of 65 seated.  R2: 6 of 67 seated.  (prior 0019 run 5/91, run A 7/82.)
--
--     RESOLVED, on evidence the previous session could not obtain: the SAME FOUR vehicles
--     -- 4cd2b777, 9926e267, c433a36d, c98ef465 -- have ZERO bookings anywhere in run A,
--     the prior 0019 run, R1 AND R2. Four runs, four different seeds, a different entry
--     point, and 0 of them rider-flagged in any of them. That is the signature of
--     twin.ottoq_sim_seed_fleet, which seats the fleet at run start and writes no
--     ottoq_stall_bookings row. The rest are `emergency_staged` cars holding bookings
--     elsewhere but none on the seat.
--     0019 neither caused it nor worsened it. FILED, NOT A REVERT TRIGGER.
-- -------------------------------------------------------------------------------------
SELECT 'R1' AS run, count(*) AS seated,
       count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM public.p0020_prestop_r1_bookings b
          WHERE b.stall_id = s.id AND b.vehicle_id = s.current_vehicle_id
            AND b.state IN ('held','active','done'))) AS always_hold_defects
  FROM public.p0020_prestop_r1_stalls s WHERE s.current_vehicle_id IS NOT NULL
UNION ALL
SELECT 'R2', count(*),
       count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM public.p0020_prestop_r2_bookings b
          WHERE b.stall_id = s.id AND b.vehicle_id = s.current_vehicle_id
            AND b.state IN ('held','active','done')))
  FROM public.p0020_prestop_r2_stalls s WHERE s.current_vehicle_id IS NOT NULL;


-- -------------------------------------------------------------------------------------
-- (8) DID THE HOLD STARVE THE FLEET?  ANSWER: NO.
--     R1 (2 flags) 199 dispatches; R2 (16 flags, 8x the load) 201. Both ran all 48 ticks
--     and completed on schedule. ALWAYS HOLD x oversubscription would present as a
--     DEADLOCK, not a parameter problem -- there is none.
--     Wash bays, the contended resource: 421 of 4,320 bay-minutes = 9.8% of the 3-bay
--     day, peak concurrency touching 3 of 3 exactly once.
-- -------------------------------------------------------------------------------------
WITH wb AS (
  SELECT b.booking_id, b.during
    FROM public.p0020_prestop_r2_bookings b JOIN public.stalls s ON s.id = b.stall_id
   WHERE s.stall_type = 'wash_bay' AND b.state IN ('held','active','done'))
SELECT (SELECT count(*) FROM public.p0020_prestop_r1_dispatches)                      AS r1_dispatches,
       (SELECT count(*) FROM public.p0020_prestop_r2_dispatches)                      AS r2_dispatches,
       (SELECT count(*) FROM wb)                                                      AS r2_wash_bookings,
       (SELECT round(sum(extract(epoch FROM (upper(during)-lower(during)))/60)) FROM wb) AS bay_minutes_used,
       3*24*60                                                                        AS bay_minutes_available,
       (SELECT max(busy) FROM (SELECT (SELECT count(*) FROM wb o
                                        WHERE o.during @> lower(w.during)) AS busy
                                 FROM wb w) t)                                        AS peak_concurrent_bays;
