-- =====================================================================================
-- 0019_wash_path_certification.sql
--
-- WHAT THIS IS. A re-runnable verification battery for the two wash paths that
-- migration 0018 installed: (PATH 1) the every-third-night wash rotation whose
-- `wash_group` is now redrawn per run from the run seed, and (PATH 2) the
-- rider-flagged cleaning recall.
--
-- Nothing in 0018 had ever executed when this battery was written:
-- `ottoq_rider_cleaning_flags` was empty and every `rider_flag_pending` was false.
-- Three runs were executed to settle six questions. This file is the queries,
-- with the answers recorded as comments so a later session can re-run and compare
-- rather than re-derive.
--
-- THE RUNS (all crossed a full night window; night = Chicago hour >= 20 or < 6)
--   A  92760504-92f5-4b04-9a68-d4f73237e7a4  seed 6666 (explicit)      24 sim-h
--   B  499b2baa-eb0f-48b3-a752-2e80eae5f216  seed 131313 (explicit)    16.5 sim-h
--   C  85135f9d-447d-4f4b-82ad-1f88369cebbe  seed 3185052694047452824 (NO p_seed
--                                            passed -- drawn fresh)    24 sim-h
--
-- HOW NIGHT WAS REACHED. `ottoq_start_demo_run` forces live playback, and
-- `ottoq_set_playback` clamps speed_x to 3.0, so one real hour buys three sim
-- hours and a demo run physically cannot reach night. The runs were started
-- normally and then switched back to FIXED playback, where a tick advances
-- tick_interval_seconds * time_scale / 60 = 30 sim-minutes and a 24-sim-hour day
-- is 48 ticks. The wash gate was never the obstacle; the clock was.
--
-- EVIDENCE TABLES (do not drop): p0019_before_washgroups, p0019_after_{a,b,c}_washgroups,
-- p0019_prestop_{a,b,c}_*, p0019_witness_all, p0019_fk_sweep.
-- Occupancy / placement / per-vehicle state were captured BEFORE each stop;
-- ledger / witness / flag reads were taken after. STOP empties the depot.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- (b) DOES THE BOOT DRAW PERSIST wash_group INTO vehicles.config AT RUN START?
--     ANSWER: YES -- but only for the RUN'S OWN DEPOT.
--     116 of 220 vehicles redrawn in every run. The other 104 are 100 autonomous
--     vehicles homed at the second depot plus 4 retail vehicles; `ottoq_run_boot_draw`
--     filters `home_depot_id = v_run.depot_id AND category='autonomous' AND is_active`,
--     so those 104 keep their OLD fixed-salt wash_group indefinitely.
--     Of the 116 redrawn: A changed 73 / kept 43, B changed 77 / kept 39,
--     C changed 74 / kept 42. "Kept" is chance -- 1/3 of 116 is 38.7.
-- -------------------------------------------------------------------------------------
WITH a AS (SELECT id, wash_group, drawn_run FROM public.p0019_after_a_washgroups),
     bf AS (SELECT id, wash_group FROM public.p0019_before_washgroups)
SELECT count(*) FILTER (WHERE a.drawn_run IS NOT NULL)                                    AS redrawn,
       count(*) FILTER (WHERE a.drawn_run IS NULL)                                        AS not_redrawn,
       count(*) FILTER (WHERE a.drawn_run IS NOT NULL
                          AND a.wash_group IS DISTINCT FROM bf.wash_group)                AS changed_value
  FROM a JOIN bf USING (id);


-- -------------------------------------------------------------------------------------
-- (d) DO DIFFERENT SEEDS PRODUCE DIFFERENT WASH COHORTS?  ANSWER: YES.
--     Over the same 116 redrawn vehicles: A/B agree on 39, A/C on 38, B/C on 41,
--     all three on 15. Chance for three independent thirds is 38.7 pairwise and
--     12.9 for all three. The draws are independent; the cohorts genuinely differ.
--     The "pin" was a caller habit (every recent operator_demo run sent 424242),
--     not a property of the chain -- run C passed no seed and received a fresh
--     19-digit random one.
-- -------------------------------------------------------------------------------------
WITH a AS (SELECT id, wash_group FROM public.p0019_after_a_washgroups WHERE drawn_run IS NOT NULL),
     b AS (SELECT id, wash_group FROM public.p0019_after_b_washgroups WHERE drawn_run IS NOT NULL),
     c AS (SELECT id, wash_group FROM public.p0019_after_c_washgroups WHERE drawn_run IS NOT NULL)
SELECT (SELECT count(*) FROM a)                                                            AS n,
       (SELECT count(*) FROM a JOIN b USING(id) WHERE a.wash_group=b.wash_group)           AS ab_same,
       (SELECT count(*) FROM a JOIN c USING(id) WHERE a.wash_group=c.wash_group)           AS ac_same,
       (SELECT count(*) FROM b JOIN c USING(id) WHERE b.wash_group=c.wash_group)           AS bc_same,
       (SELECT count(*) FROM a JOIN b USING(id) JOIN c USING(id)
         WHERE a.wash_group=b.wash_group AND b.wash_group=c.wash_group)                    AS abc_same;


-- -------------------------------------------------------------------------------------
-- (c) DOES THE NIGHT GATE CONSUME THE NEW wash_group?  ANSWER: YES, EXACTLY.
--     Recomputed independently from the preserved visit rows rather than trusting a
--     tally. The gate is
--       (v_is_night AND wash_group = sim_day % 3) OR soil >= 0.75 OR cycles >= 9.
--
--       run  night  on-rotation  visits  washed
--        A    yes      yes         15      15     <- 100%
--        A    yes      no          28       0
--        A    no       yes         42       0
--        A    no       no          81       0
--        B    yes      yes         10      10     <- 100%
--        B    yes      no          29       0
--        B    no       yes         23       1     <- rider-flag path, NOT a gate leak
--        B    no       no          64       0
--
--     Before 0018 this count was 0, ever. The single daytime wash in run B carries
--     rider_flagged=true and why='Rider-reported exterior cleanliness issue'; that
--     vehicle's cycles_since_wash was 0, so the cycles>=9 backstop did NOT fire.
--     Zero routine washes occurred outside night+on-rotation.
-- -------------------------------------------------------------------------------------
WITH v AS (
  SELECT 'A' AS run, n.vehicle_id, n.arrived_at, n.atoms, w.wash_group
    FROM public.p0019_prestop_a_visitneeds n
    JOIN public.p0019_after_a_washgroups w ON w.id = n.vehicle_id
  UNION ALL
  SELECT 'B', n.vehicle_id, n.arrived_at, n.atoms, w.wash_group
    FROM public.p0019_prestop_b_visitneeds n
    JOIN public.p0019_after_b_washgroups w ON w.id = n.vehicle_id
), e AS (
  SELECT run, wash_group,
         extract(hour FROM (arrived_at AT TIME ZONE 'America/Chicago'))::int AS chi_hour,
         (arrived_at::date - DATE '2020-01-01')                              AS sim_day,
         EXISTS(SELECT 1 FROM jsonb_array_elements(atoms) a
                 WHERE a->>'svc'='exterior_wash')                            AS has_wash,
         EXISTS(SELECT 1 FROM jsonb_array_elements(atoms) a
                 WHERE a->>'svc'='exterior_wash'
                   AND (a->>'rider_flagged')::boolean)                       AS wash_from_riderflag
    FROM v
)
SELECT run, (chi_hour>=20 OR chi_hour<6) AS is_night, (wash_group = sim_day % 3) AS on_rotation,
       count(*) AS visits, count(*) FILTER (WHERE has_wash) AS washed,
       count(*) FILTER (WHERE wash_from_riderflag) AS wash_from_riderflag
  FROM e GROUP BY 1,2,3 ORDER BY run, is_night DESC, on_rotation DESC;


-- -------------------------------------------------------------------------------------
-- (a) DOES A RIDER FLAG PRODUCE A REAL MID-DEPLOYMENT RECALL?
--     ANSWER: THE RECALL IS REAL; THE "EARLY DEPARTURE" IS NOT ESTABLISHED.
--
--     Denominator: 18 flags drawn across the three runs (A 3, B 7, C 8).
--     16 reached status 'recalled' or 'served'. 2 never fired (see the gap below).
--     Every recalled flag produced a dispatch stamped return_trigger='rider_flag_cleaning'
--     and a non-deferrable cleaning atom that reached a wash bay.
--
--     ⚠️ THE TRAP THAT ALMOST PRODUCED A FALSE POSITIVE. Measuring "early" as
--     scheduled_return_at - returning_started_at gives EXACTLY 30 minutes for every
--     rider-flag recall -- which looks like a crisp result until you run the control
--     below and find that all 297 dispatches in runs A and B, across all 11 trigger
--     types, return exactly 30. `scheduled_return_at` is REBASED when the return is
--     decided, so that difference is 30 by construction and measures nothing.
--
--     The immutable dispatch plan is `planned_return_at`, a STORED GENERATED column
--     (dispatched_at + planned_duration_min) that cannot be overwritten. Measured
--     against it, all 10 rider-flag-linked dispatches turned for the depot AFTER
--     their planned return -- median 16 minutes LATE, worst 354 minutes late, and
--     not one of them early. `prime_inbound` is the only trigger that consistently
--     returns early (median 14 min early).
--
--     WHY. `ottoq_evaluate_return_need` only evaluates a vehicle that has an ACTIVE
--     dispatch; with no active dispatch it returns should_return=false. So a flag
--     that comes due while the car is sitting in the depot cannot fire. Nothing
--     stops that car from being dispatched, so what actually happens is:
--     flag comes due in depot -> car is dispatched anyway -> the rung fires on the
--     next tick -> car is recalled. 9 of the 10 flag-linked dispatches were
--     dispatched while ALREADY carrying a due flag (flag age at dispatch 43 min to
--     1,349 min). Only ONE (run B, a1111111, dispatched 176 min before its flag came
--     due) was a genuine mid-deployment recall, and it still came home only 30 min
--     -- one tick -- before its plan, at 93% of a 7.4-hour deployment.
-- -------------------------------------------------------------------------------------
-- The control that kills the false positive:
WITH d AS (SELECT 'A' AS run, * FROM public.p0019_prestop_a_dispatches
           UNION ALL SELECT 'B', * FROM public.p0019_prestop_b_dispatches)
SELECT coalesce(return_trigger,'(null)') AS trigger, count(*) AS n,
       count(DISTINCT round(extract(epoch FROM (scheduled_return_at-returning_started_at))/60))
         AS distinct_vals_vs_REBASED_column,   -- always 1, always 30: meaningless
       round(percentile_cont(0.5) WITHIN GROUP (
         ORDER BY extract(epoch FROM (planned_return_at-returning_started_at))/60))
         AS median_min_early_vs_IMMUTABLE_plan -- negative = turned back LATE
  FROM d WHERE returning_started_at IS NOT NULL
 GROUP BY 1 ORDER BY 2 DESC;


-- -------------------------------------------------------------------------------------
-- GAP: A FLAG THAT COMES DUE WHILE THE CAR IS ALREADY INSIDE THE DEPOT NEVER FIRES.
--     2 of 18 flags (run A b696f1b8, run C a1111111) stayed 'pending' for the rest of
--     the run. b696f1b8 arrived 02:04, its flag came due 02:24, and it then sat
--     `staged_for_departure` for 15 more sim-hours. The flag is only actioned on the
--     deployment path (ottoq_evaluate_return_need, which needs an active dispatch) or
--     at manifest generation if it was already due on arrival. Neither applies to a car
--     that is parked when the flag matures and is not dispatched again.
-- -------------------------------------------------------------------------------------
SELECT 'A' AS run, status, count(*) FROM public.p0019_prestop_a_flags GROUP BY 1,2
UNION ALL SELECT 'B', status, count(*) FROM public.p0019_prestop_b_flags GROUP BY 1,2
UNION ALL SELECT 'C', status, count(*) FROM public.p0019_prestop_c_flags GROUP BY 1,2
ORDER BY 1,2;


-- -------------------------------------------------------------------------------------
-- (e) CONTENTION, OBSERVED NOT PROJECTED -- AND DOES THE FORWARD RESERVATION EARN ITS KEEP?
--     ANSWER: THERE IS BARELY ANY CONTENTION, SO IT MOSTLY DOES NOT -- YET.
--     Peak concurrent wash-bay use reached 3 of 3 bays in both runs, but only at a
--     SINGLE moment in each, and never exceeded capacity. Occupancy (done+active+held)
--     was 458 bay-min of 4,320 available in run A (10.6% of the 3-bay day) and
--     370 of 2,970 in run B (12.5%).
--
--     CAUSATION, not correlation: at the moment each wash booking started, how many of
--     the other two bays were busy?
--       run A: 33 bookings -- 10 had both other bays free, 20 had one busy,  3 took the last bay
--       run B: 24 bookings -- 10 had both other bays free, 13 had one busy,  1 took the last bay
--     So a first-free assigner would have found a bay in 53 of 57 cases. The forward
--     reservation was load-bearing in at most 4 of 57 (7%). The night rotation firing
--     is necessary for real competition but is not yet sufficient to create it.
--
--     A5's arithmetic projection (1.35% of wash-bay minutes for rider flags) is the
--     right order of magnitude but is NOT a bound: run B observed 4.42%, 3.3x the
--     projection, because more flags were drawn than assumed (7 vs 3.5) and one
--     flagged vehicle took three bookings. A5's conclusion still holds -- it is far
--     below its own 25% abort threshold -- but the number must not be quoted as a cap.
-- -------------------------------------------------------------------------------------
WITH b AS (SELECT 'A' AS run, * FROM public.p0019_prestop_a_bookings
           UNION ALL SELECT 'B', * FROM public.p0019_prestop_b_bookings),
     wb AS (SELECT b.run, b.booking_id, b.stall_id, b.during
              FROM b JOIN public.stalls s ON s.id = b.stall_id
             WHERE s.stall_type='wash_bay' AND b.state IN ('done','active','held'))
SELECT w.run, count(*) AS bookings,
       count(*) FILTER (WHERE o.busy = 0) AS both_other_bays_free,
       count(*) FILTER (WHERE o.busy = 1) AS one_other_busy,
       count(*) FILTER (WHERE o.busy = 2) AS took_the_last_bay
  FROM wb w CROSS JOIN LATERAL (
    SELECT count(*) AS busy FROM wb o
     WHERE o.run=w.run AND o.booking_id<>w.booking_id AND o.stall_id<>w.stall_id
       AND o.during @> lower(w.during)) o
 GROUP BY 1;


-- -------------------------------------------------------------------------------------
-- (f) IS THE FLAG GENUINELY NON-DEFERRABLE UNDER CONTENTION?  ANSWER: YES.
--     In run B, 7 flags competed with the nightly rotation for the same 3 bays and all
--     7 obtained a wash-bay booking; none was refused, dropped or deferred. In the
--     manifest the rider-flag atom is written must_do=true, deferrable=false,
--     carryover_eligible=false, and in ottoq_evaluate_return_need the rung sits below
--     safety and reserve but above everything routine, with lead_ticks=0 and NOT behind
--     the contention gate. Caveat: (e) shows contention was light, so this is a weaker
--     test than the wording "busy depot" implies.
-- -------------------------------------------------------------------------------------


-- -------------------------------------------------------------------------------------
-- BAY RESERVATION LIFECYCLE -- from the witness. NEVER filter
-- `source='return_signal_prearrival' AND state='active'`: ottoq_activate_due_bay_reservations
-- REWRITES source on success, so that combination returns ~0 rows THROUGH THE SUCCESS PATH.
-- Discriminate on new_source. `inside_window` is true by construction on early
-- activations (0015 rebases `during` before flipping state), so it is not evidence.
--   bay_reservation_activated        (bound inside the real forecast window):  3 active,  3 done
--   bay_reservation_activated_early  (vehicle-first override):                15 active, 14 done
-- 18 activations, 17 reached done, and 15 of 18 were the vehicle-first override rather
-- than a forecast-window binding.
-- -------------------------------------------------------------------------------------
SELECT new_source, new_state, count(*) AS n,
       count(*) FILTER (WHERE seated_on_reserved) AS seated_on_reserved
  FROM public.p0019_witness_all
 WHERE new_source IN ('bay_reservation_activated','bay_reservation_activated_early')
 GROUP BY 1,2 ORDER BY 1,2;


-- =====================================================================================
-- PROTECT BATTERY -- re-measured. One breach, and it is NOT attributable to 0018.
-- =====================================================================================

-- PASS. 0 double-bookings. Own pairwise `during && during`, NOT the exclusion constraint.
--       0 overlapping pairs in run A, run B, and the live table.
WITH b AS (SELECT 'A' AS run, * FROM public.p0019_prestop_a_bookings
           UNION ALL SELECT 'B', * FROM public.p0019_prestop_b_bookings)
SELECT x.run, count(*) AS overlapping_pairs
  FROM b x JOIN b y ON y.run=x.run AND y.stall_id=x.stall_id AND y.booking_id>x.booking_id
       AND x.during && y.during
       AND x.state IN ('held','active','done') AND y.state IN ('held','active','done')
 GROUP BY 1;

-- PASS. 225 foreign keys generated from pg_constraint, 0 with orphans, 0 errored.
--       Matches the catalogue's reported 225 in `public`. See public.p0019_fk_sweep.

-- PASS. 0010 geometry. 320 of 320 stalls assessed (0 not_assessed: no null x/y, heading
--       or dimensions), 0 overlapping pairs, inventory 115 staging / 30 l2 / 10 dcfc /
--       3 wash_bay / 2 service_bay = 160 at BOTH depots.
--       UNIT NOTE, to avoid repeating the 1.57x outage: relative_x/relative_y in
--       public.stalls are in FEET, not cockpit units. Proven empirically -- staging
--       nearest-neighbour spacing is 8.948 and staging stall_width_ft is 8.94; l2
--       nearest-neighbour is 16.170 and l2 stall_depth_ft is 16.18. No conversion.
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
       (SELECT count(*) FROM fp a JOIN fp b ON b.depot_id=a.depot_id AND b.id>a.id
          AND st_intersects(a.geom,b.geom)
          AND st_area(st_intersection(a.geom,b.geom)) > 0.01) AS overlapping_pairs;

-- PASS. 0008 laundering = 0 -- and this is exactly the trap the brief warns about.
--       Naive value-equality flags 21 of 207 profile x wear pairs. ALL 21 are
--       0.000 = 0.000 on freshly-washed cars. Directional, non-zero laundering: 0.
SELECT count(*) AS pairs,
       count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)) AS naive_value_equality,
       count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)
                          AND NOT (p.exterior_soil_level = 0 AND round(w.soil_index,3) = 0))
         AS real_copied_nonzero
  FROM public.vehicle_need_profile p JOIN public.ottoq_vehicle_wear w USING (vehicle_id);

-- PASS. 0009 credit honesty. Run C: 81 bay exits, 263 would have been credited under the
--       old fixed array, 44 credited now, 219 false credits prevented, 0 OVER-credits
--       (no exit credited more than the bay was capable of), 0 exits that were capable
--       and credited nothing while suppressing nothing.
--       fault_repair credited twice against 22 fault_repair atoms in the ledger of which
--       9 reached done -- so the 2 credits are genuine, not the old blanket credit.
--       OPEN QUESTION, not a pass: 9 done vs 2 credited may be under-credit on paths
--       other than the service-bay exit. Needs its own test.
-- PASS. planned_return_at is still un-writable -- attgenerated='s' (STORED GENERATED),
--       expression dispatched_at + planned_duration_min, so any write raises 428C9.

-- PASS. cron 10 (depot-tick) ON, 11 (retention) ON, 12 (metronome, the START engine) ON,
--       13 (cert-battery) OFF.

-- 🔴 BREACH. ALWAYS HOLD is NOT 0. Measured PRE-STOP (STOP empties the depot):
--       run A: 82 seated vehicles, 7 with no booking of any state covering the seat
--       run B: 79 seated vehicles, 6 with the same
--     In run A: 4 have NO booking anywhere in the entire run -- including one vehicle
--     in state `charging_l2` sitting on an L2 stall with zero bookings on that stall
--     and zero for that vehicle -- and 3 are `emergency_staged` holding only
--     done/released bookings. Stall and vehicle agree on the stall id in all 7, so this
--     is not a capture-skew artifact.
--     NOT ATTRIBUTABLE TO 0018: 0 of the 7 offenders is rider-flagged, and 0018 touches
--     only the wash draw and the flag path -- it seats no vehicles. Reverting 0018 would
--     not clear this. What is missing is a pre-0018 baseline for this exact query; until
--     that exists, "regression" is unproven and so is "pre-existing".
WITH s AS (SELECT id, current_vehicle_id FROM public.p0019_prestop_a_stalls
            WHERE current_vehicle_id IS NOT NULL)
SELECT count(*) AS seated,
       count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM public.p0019_prestop_a_bookings b
          WHERE b.stall_id=s.id AND b.vehicle_id=s.current_vehicle_id
            AND b.state IN ('held','active','done'))) AS always_hold_defects
  FROM s;


-- =====================================================================================
-- TWO DEFECTS FOUND BY READING, NOT BY MEASURING. Both dormant here; neither blocks.
--
-- 1. TIMEZONE SPLIT IN THE NIGHT GATE. In twin.ottoq_sim_generate_service_manifest,
--    v_hour is Chicago-local but v_sim_day (which selects the rotation third via
--    sim_day % 3) is the UTC date. For America/Chicago a whole night falls inside one
--    UTC date, so the rotation day is well defined BY LUCK. At a depot near UTC+0 a
--    single night would straddle midnight UTC and split across two rotation groups.
--
-- 2. `seed_was_explicit` IS INFERRED, NOT RECORDED. ottoq_run_boot_draw computes it as
--    (notes IS NOT NULL AND seed IS NOT NULL AND seed < 100000000) -- a heuristic on the
--    seed's magnitude, not a record of whether the caller passed p_seed. It happens to
--    be right for these runs, but it is a guess and should be a real flag if anyone is
--    going to rely on it to prove the pin is gone.
-- =====================================================================================
