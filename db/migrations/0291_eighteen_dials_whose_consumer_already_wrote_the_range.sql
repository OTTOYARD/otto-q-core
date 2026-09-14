-- migration-version: PENDING
-- migration-name:    0291_eighteen_dials_whose_consumer_already_wrote_the_range
--
-- 0291  EIGHTEEN DIALS WHOSE CONSUMER ALREADY WROTE THE RANGE
--
-- Seventh file under the 0282 rule, and the cheapest of them, because for these
-- eighteen dials the range is not derived at all. IT IS COPIED. Each of these
-- consumers already clamps the value inline at its own read site, with a
-- literal, in live prosrc. This file lifts that literal into the catalog and
-- pins the source so the copy cannot drift from the original.
--
-- ---------------------------------------------------------------------------
-- FIRST, A CORRECTION TO WHAT THIS SERIES HAS BEEN FOR.
--
-- Every file from 0282 on has described the catalog as a place where a dial's
-- safe range is recorded. That is true and it is not the main thing. MEASURED
-- 2026-09-14, with an uncatalogued dial and a real consumer:
--
--   ottoq_policy_set('run', <run>, 'yard_taxi_speed_mps', 0.1)  -> ok=false
--   ottoq_policy_set('run', <run>, 'yard_taxi_speed_mps', 3.5)  -> ok=false
--   ottoq_policy_set('run', <run>, 'yard_taxi_speed_mps', 0)    -> ok=false
--
-- and after each one, ottoq_itin_travel_leg was called and reported
-- speed_mps 3.5 -- its own hard-coded default -- over a 60.6 m leg, 37 s. The
-- setter refused all three writes because the key is not in the catalog.
--
-- SO THE CATALOG IS THE ALLOW-LIST FOR WRITING. An uncatalogued dial is not a
-- dial with an unknown range; it is a dial NOBODY CAN TURN through the
-- sanctioned path. The 53 still-uncatalogued keys are 53 knobs the engine reads
-- and the agent layer cannot reach. That is the cost this series is paying
-- down, and it is a larger one than "annotate the ranges" suggested.
--
-- (And it is the answer to a question 0290 left hanging: metres_per_plan_unit
-- cannot be driven to 0 by anyone today, because it cannot be written at all.
-- G61 is "this dial cannot be OPENED safely", not "this dial is unsafe".)
--
-- ---------------------------------------------------------------------------
-- THE EIGHTEEN, AND WHERE EACH NUMBER COMES FROM
--
-- Every min and max below is the LITERAL IN THE CONSUMER'S OWN INLINE CLAMP,
-- read out of live prosrc. Every default is the consumer's own ottoq_policy_get
-- fallback, from the same expression. Nothing here was chosen.
--
--   dial                          min   max    dflt  consumer
--   bay_defer_horizon_min          30    -      480  ottoq.ottoq_reconcile_bay_reservations
--   bay_defer_max                   1    -        8  ottoq.ottoq_reconcile_bay_reservations
--   bay_taxi_min                    0    -        3  ottoq.ottoq_reconcile_bay_reservations
--   bay_fault_outage_min            1    -       45  twin.ottoq_sim_bay_fault_handler
--   bay_fault_rate_per_tick         0    -        0  twin.ottoq_sim_bay_fault_handler
--   cuopt_fire_beat_heartbeat_s     5    -       60  public.ottoq_sim_decide_and_dispatch
--   demo_max_real_minutes           1    -       60  public.ottoq_demo_metronome
--   night_wave_bands                1    -        3  public.ottoq_recall_naive_threshold_v1
--   prearrival_no_show_grace_min    1    -       20  ottoq.ottoq_release_expired_bookings
--   prearrival_shift_horizon_min   10    -      240  ottoq.ottoq_reserve_inbound_bays
--   prime_inbound_fraction          0   0.60   0.30  twin.ottoq_sim_prime_deployment
--   reopened_need_dwell_min         0    -        5  ottoq.ottoq_readmit_reopened_needs
--   run_governor_max_sim_minutes    1    -      139  public.ottoq_run_governor_auto_stop
--   run_stall_timeout_minutes       2    -       10  public.ottoq_run_governor_auto_stop
--   tick_cadence_floor_s          0.2    -      2.0  public.ottoq_demo_metronome
--   tow_retrieval_min               0    -       25  twin.ottoq_sim_vehicle_exception_handler
--   yard_manoeuvre_s                0    -       20  public.ottoq_itin_travel_leg
--   yard_taxi_speed_mps           0.5    -      3.5  public.ottoq_itin_travel_leg
--
-- prime_inbound_fraction is the only one with a ceiling, and it is the only one
-- whose consumer wrote LEAST as well as GREATEST:
--   LEAST(0.60, GREATEST(0, COALESCE(ottoq_policy_get(...,'prime_inbound_fraction',0.30), 0.30)))
--
-- THREE HAVE A LIVE ROW: night_wave_bands 3, run_stall_timeout_minutes 10, and
-- run_governor_max_sim_minutes 540 -- all written 2026-08-13 by claude_* labels.
-- None would be clamped by the bounds above (checked before this file was
-- written). THE OTHER FIFTEEN HAVE NO ROW AT ALL: they have only ever run on the
-- consumer's hard-coded fallback, because nothing could write them.
--
-- Note run_governor_max_sim_minutes: the catalog's default_value is 139, the
-- consumer's own fallback, while the live global row says 540. default_value
-- documents what the code does when no row exists; it does not override a row.
--
-- ---------------------------------------------------------------------------
-- AND A WARNING ABOUT THE SWEEP THAT FOUND THESE, because the next sweep will
-- hit the same two traps. FIVE OF EIGHT extractions were WRONG until the source
-- lines were read directly rather than regexed:
--
--   1. A COALESCE FALLBACK LOOKS EXACTLY LIKE A BOUND.
--        GREATEST(COALESCE(ottoq_policy_get(r,'bay_defer_max',8), 8), 1)
--      The 8 is the policy_get default REPEATED as the COALESCE fallback. The
--      bound is 1. A regex anchored on the first literal after the call reads 8.
--   2. THE LITERAL SITS ON EITHER SIDE.
--        GREATEST(0.5, ottoq_policy_get(...))   and
--        GREATEST(ottoq_policy_get(...), 10)
--      are both common here. A sweep written for one shape silently reports
--      nothing for the other, which reads as "no bound declared".
--   Mis-read this way: bay_taxi_min (3, really 0), bay_defer_max (8, really 1),
--   bay_defer_horizon_min (480, really 30), reopened_need_dwell_min (5, really
--   0), tow_retrieval_min (25, really 0). And prime_inbound_fraction's ceiling
--   was missed entirely by the first pass.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE DOES NOT CLAIM. These eighteen clamps already work. The engine
-- has never used an out-of-range value for any of them, because the consumer
-- guards itself. Cataloguing changes nothing about what the engine DOES; it
-- changes what the engine will ACCEPT, from "nothing" to "anything inside the
-- bound the consumer was already enforcing". That is the whole of the benefit
-- and it should not be described as a safety fix.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0291 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0291 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0291 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0291 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. PREMISE + THE forces_recert=false ARGUMENT -----------------------------
DO $p0$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog c
   WHERE c.param_key = ANY (ARRAY[
     'bay_defer_horizon_min','bay_defer_max','bay_taxi_min','bay_fault_outage_min',
     'bay_fault_rate_per_tick','cuopt_fire_beat_heartbeat_s','demo_max_real_minutes',
     'night_wave_bands','prearrival_no_show_grace_min','prearrival_shift_horizon_min',
     'prime_inbound_fraction','reopened_need_dwell_min','run_governor_max_sim_minutes',
     'run_stall_timeout_minutes','tick_cadence_floor_s','tow_retrieval_min',
     'yard_manoeuvre_s','yard_taxi_speed_mps']);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0291 P0: % of the eighteen keys are already catalogued', v_n;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get';
  IF v_src IS NULL OR position('ottoq_policy_param_catalog' in v_src) > 0 THEN
    RAISE EXCEPTION '0291 P0: ottoq_policy_get is missing or now reads the catalog';
  END IF;
  RAISE NOTICE '0291 P0: eighteen keys uncatalogued; the read path still ignores the catalog';
END $p0$;

-- P1. THE CONSUMER STILL WRITES EVERY ONE OF THESE NUMBERS ITSELF ------------
-- The load-bearing precondition of the file. Each row is a regex over live
-- prosrc that must match EXACTLY the stated number of times. If a consumer's
-- inline clamp is edited, retyped, or removed, the catalog row copied from it
-- is stale and this refuses to apply rather than shipping a bound the engine
-- no longer enforces.
DO $p1$
DECLARE
  r record; v_src text; v_hits int;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ottoq.ottoq_reconcile_bay_reservations','bay_defer_horizon_min',
       'GREATEST\(COALESCE\(public\.ottoq_policy_get\(p_sim_run_id,''bay_defer_horizon_min'',480\),480\),30\)',1),
      ('ottoq.ottoq_reconcile_bay_reservations','bay_defer_max',
       'GREATEST\(COALESCE\(public\.ottoq_policy_get\(p_sim_run_id,''bay_defer_max'',8\),8\),1\)',1),
      ('ottoq.ottoq_reconcile_bay_reservations','bay_taxi_min',
       'GREATEST\(COALESCE\(public\.ottoq_policy_get\(p_sim_run_id,''bay_taxi_min'',3\),3\),0\)',1),
      ('twin.ottoq_sim_bay_fault_handler','bay_fault_outage_min',
       'GREATEST\(1, COALESCE\(ottoq_policy_get\(p_sim_run_id, ''bay_fault_outage_min'', 45\), 45\)\)',1),
      ('twin.ottoq_sim_bay_fault_handler','bay_fault_rate_per_tick',
       'GREATEST\(0, COALESCE\(ottoq_policy_get\(p_sim_run_id, ''bay_fault_rate_per_tick'', 0\), 0\)\)',1),
      ('public.ottoq_sim_decide_and_dispatch','cuopt_fire_beat_heartbeat_s',
       'GREATEST\(5, ottoq_policy_get\(p_sim_run_id, ''cuopt_fire_beat_heartbeat_s'', 60\)::int\)',1),
      ('public.ottoq_demo_metronome','demo_max_real_minutes',
       'GREATEST\(1, ottoq_policy_get\(v_run\.sim_run_id, ''demo_max_real_minutes'', 60\)\)',1),
      ('public.ottoq_recall_naive_threshold_v1','night_wave_bands',
       'GREATEST\(1, ottoq_policy_get\(p_sim_run_id, ''night_wave_bands'', 3\)::int\)',1),
      ('ottoq.ottoq_release_expired_bookings','prearrival_no_show_grace_min',
       'GREATEST\(public\.ottoq_policy_get\(p_sim_run_id, ''prearrival_no_show_grace_min'', 20\), 1\)::int',1),
      ('ottoq.ottoq_reserve_inbound_bays','prearrival_shift_horizon_min',
       'GREATEST\(public\.ottoq_policy_get\(p_sim_run_id, ''prearrival_shift_horizon_min'', 240\), 10\)::int',1),
      ('twin.ottoq_sim_prime_deployment','prime_inbound_fraction',
       'LEAST\(0\.60, GREATEST\(0, COALESCE\(ottoq_policy_get\(p_sim_run_id,''prime_inbound_fraction'',0\.30\), 0\.30\)\)\)',1),
      ('ottoq.ottoq_readmit_reopened_needs','reopened_need_dwell_min',
       'GREATEST\(COALESCE\(public\.ottoq_policy_get\(p_sim_run_id,''reopened_need_dwell_min'',5\),5\), 0\)',1),
      ('public.ottoq_run_governor_auto_stop','run_governor_max_sim_minutes',
       'GREATEST\(1, public\.ottoq_policy_get\([^)]*''run_governor_max_sim_minutes'', 139\)\)::int',2),
      ('public.ottoq_run_governor_auto_stop','run_stall_timeout_minutes',
       'GREATEST\(2, public\.ottoq_policy_get\([^)]*''run_stall_timeout_minutes'', 10\)\)::int',1),
      ('public.ottoq_demo_metronome','tick_cadence_floor_s',
       'GREATEST\(0\.2, ottoq_policy_get\(v_run\.sim_run_id, ''tick_cadence_floor_s'', 2\.0\)\)',1),
      ('twin.ottoq_sim_vehicle_exception_handler','tow_retrieval_min',
       'GREATEST\(COALESCE\(ottoq_policy_get\(p_sim_run_id,''tow_retrieval_min'',25\),25\), 0\)',1),
      ('public.ottoq_itin_travel_leg','yard_manoeuvre_s',
       'GREATEST\(0,   ottoq_policy_get\(p_sim_run_id, ''yard_manoeuvre_s'',    20\)\)',1),
      ('public.ottoq_itin_travel_leg','yard_taxi_speed_mps',
       'GREATEST\(0\.5, ottoq_policy_get\(p_sim_run_id, ''yard_taxi_speed_mps'', 3\.5\)\)',1)
    ) AS t(fn, param_key, rx, n_sites)
  LOOP
    SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE (n.nspname || '.' || p.proname) = r.fn;
    IF v_src IS NULL THEN
      RAISE EXCEPTION '0291 P1: consumer % does not exist', r.fn;
    END IF;
    SELECT count(*) INTO v_hits FROM regexp_matches(v_src, r.rx, 'g');
    IF v_hits <> r.n_sites THEN
      RAISE EXCEPTION '0291 P1: %.% -- expected % inline clamp site(s), found %. '
                      'The catalog row for this dial is a COPY of that clamp; if the '
                      'clamp moved, the copy is wrong and must be re-read, not patched',
                      r.fn, r.param_key, r.n_sites, v_hits;
    END IF;
  END LOOP;
  RAISE NOTICE '0291 P1: all eighteen inline clamps are where the catalog rows say they are';
END $p1$;

-- P2. NO LIVE ROW WOULD BE CLAMPED BY WHAT WE ARE ABOUT TO DECLARE -----------
-- If a live value sits outside the bound its own consumer enforces, that is a
-- finding, not something to silently pull into range.
DO $p2$
DECLARE v_bad text; v_rows int;
BEGIN
  SELECT count(*) INTO v_rows FROM public.ottoq_policy_params p
   WHERE p.param_key = ANY (ARRAY['bay_defer_horizon_min','bay_defer_max','bay_taxi_min',
     'bay_fault_outage_min','bay_fault_rate_per_tick','cuopt_fire_beat_heartbeat_s',
     'demo_max_real_minutes','night_wave_bands','prearrival_no_show_grace_min',
     'prearrival_shift_horizon_min','prime_inbound_fraction','reopened_need_dwell_min',
     'run_governor_max_sim_minutes','run_stall_timeout_minutes','tick_cadence_floor_s',
     'tow_retrieval_min','yard_manoeuvre_s','yard_taxi_speed_mps']);
  IF v_rows <> 3 THEN
    RAISE EXCEPTION '0291 P2: expected 3 live rows across the eighteen keys, found %. '
                    'A new row appeared since this file was written; re-read it before applying',
                    v_rows;
  END IF;
  SELECT string_agg(p.param_key || '=' || p.param_value, ', ') INTO v_bad
    FROM public.ottoq_policy_params p
    JOIN (VALUES ('bay_defer_horizon_min',30::numeric,NULL::numeric),('bay_defer_max',1,NULL),
                 ('bay_taxi_min',0,NULL),('bay_fault_outage_min',1,NULL),
                 ('bay_fault_rate_per_tick',0,NULL),('cuopt_fire_beat_heartbeat_s',5,NULL),
                 ('demo_max_real_minutes',1,NULL),('night_wave_bands',1,NULL),
                 ('prearrival_no_show_grace_min',1,NULL),('prearrival_shift_horizon_min',10,NULL),
                 ('prime_inbound_fraction',0,0.60),('reopened_need_dwell_min',0,NULL),
                 ('run_governor_max_sim_minutes',1,NULL),('run_stall_timeout_minutes',2,NULL),
                 ('tick_cadence_floor_s',0.2,NULL),('tow_retrieval_min',0,NULL),
                 ('yard_manoeuvre_s',0,NULL),('yard_taxi_speed_mps',0.5,NULL))
           AS b(param_key, mn, mx) ON b.param_key = p.param_key
   WHERE p.param_value < b.mn OR (b.mx IS NOT NULL AND p.param_value > b.mx);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0291 P2: live value(s) outside the consumer''s own clamp: %', v_bad;
  END IF;
  RAISE NOTICE '0291 P2: 3 live rows, none outside the bound its consumer already enforces';
END $p2$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES
('bay_defer_horizon_min',
 '0291: how far ahead ottoq.ottoq_reconcile_bay_reservations will look when deferring a bay reservation, in minutes. min_value 30 and default 480 are COPIED from the consumer''s own inline clamp, GREATEST(COALESCE(ottoq_policy_get(...,480),480),30) -- the 480 there is the policy_get fallback repeated, not a bound. MAX NULL: the consumer declares no ceiling.',
 480, 30, NULL, 'ottoq.ottoq_reconcile_bay_reservations'),
('bay_defer_max',
 '0291: how many times one bay reservation may be deferred before it is given up on. min_value 1 COPIED from the consumer''s inline GREATEST(COALESCE(ottoq_policy_get(...,8),8),1)::int -- a deferral cap of 0 would mean the reconciler could never defer at all, which is why the consumer floors it at 1. MAX NULL.',
 8, 1, NULL, 'ottoq.ottoq_reconcile_bay_reservations'),
('bay_taxi_min',
 '0291: minutes allowed for the taxi move to a reserved bay, read by ottoq.ottoq_reconcile_bay_reservations. min_value 0 COPIED from its inline GREATEST(COALESCE(ottoq_policy_get(...,3),3),0): 0 is meaningful here (an instantaneous move) and is the edge of the range, not outside it. MAX NULL.',
 3, 0, NULL, 'ottoq.ottoq_reconcile_bay_reservations'),
('bay_fault_outage_min',
 '0291: how long a faulted bay stays out of service in the twin, in minutes. min_value 1 COPIED from twin.ottoq_sim_bay_fault_handler''s inline GREATEST(1, COALESCE(ottoq_policy_get(...,45),45)) -- a 0-minute outage is a fault that never happened, so the consumer floors it at one minute. MAX NULL.',
 45, 1, NULL, 'twin.ottoq_sim_bay_fault_handler'),
('bay_fault_rate_per_tick',
 '0291: probability per tick that a bay faults in the twin. min_value 0 COPIED from the consumer''s inline GREATEST(0, COALESCE(ottoq_policy_get(...,0),0)); 0 is the DEFAULT as well as the floor -- the twin injects no bay faults unless this is raised. MAX NULL: the consumer declares no ceiling, so this is NOT pinned to a probability range here; that would be inventing a bound the engine never wrote.',
 0, 0, NULL, 'twin.ottoq_sim_bay_fault_handler'),
('cuopt_fire_beat_heartbeat_s',
 '0291: seconds the decide path waits on a proposer heartbeat before it stops holding the tick, read by public.ottoq_sim_decide_and_dispatch. min_value 5 COPIED from its inline GREATEST(5, ottoq_policy_get(...,60)::int). NOTE the cuopt_ name: this is the first-refusal/deferral machinery, which carries a cuOpt name historically and is load-bearing for the CP-SAT proposer. Cataloguing it does not touch the decide path -- ottoq_policy_get never reads the catalog.',
 60, 5, NULL, 'public.ottoq_sim_decide_and_dispatch'),
('demo_max_real_minutes',
 '0291: wall-clock minutes a live demo run may occupy before public.ottoq_demo_metronome stops it. min_value 1 COPIED from its inline GREATEST(1, ottoq_policy_get(...,60)). MAX NULL. This is a governor on the metronome, not on any certified path.',
 60, 1, NULL, 'public.ottoq_demo_metronome'),
('night_wave_bands',
 '0291: how many bands the overnight recall window is divided into by public.ottoq_recall_naive_threshold_v1. min_value 1 COPIED from its inline GREATEST(1, ottoq_policy_get(...,3)::int) -- zero bands would divide the window into nothing. MAX NULL.',
 3, 1, NULL, 'public.ottoq_recall_naive_threshold_v1'),
('prearrival_no_show_grace_min',
 '0291: minutes a pre-arrival booking is held past its window before ottoq.ottoq_release_expired_bookings releases it. min_value 1 COPIED from its inline GREATEST(ottoq_policy_get(...,20), 1)::int -- note the literal is the SECOND argument here, a shape that a sweep written for GREATEST(<lit>, get(...)) reads as "no bound declared". MAX NULL.',
 20, 1, NULL, 'ottoq.ottoq_release_expired_bookings'),
('prearrival_shift_horizon_min',
 '0291: how far ahead ottoq.ottoq_reserve_inbound_bays will shift an inbound bay reservation, in minutes. min_value 10 COPIED from its inline GREATEST(ottoq_policy_get(...,240), 10)::int, literal second. MAX NULL.',
 240, 10, NULL, 'ottoq.ottoq_reserve_inbound_bays'),
('prime_inbound_fraction',
 '0291: the fraction of the fleet twin.ottoq_sim_prime_deployment places inbound when priming a run. THE ONLY ONE OF THE EIGHTEEN WITH A CEILING, and the consumer wrote both ends: LEAST(0.60, GREATEST(0, COALESCE(ottoq_policy_get(...,0.30), 0.30))). min 0 and max 0.60 are copied from that expression exactly; the 0.60 was missed entirely by the first sweep, which only looked for GREATEST.',
 0.30, 0, 0.60, 'twin.ottoq_sim_prime_deployment'),
('reopened_need_dwell_min',
 '0291: minutes a reopened need must dwell before ottoq.ottoq_readmit_reopened_needs will readmit it. min_value 0 COPIED from its inline GREATEST(COALESCE(ottoq_policy_get(...,5),5), 0) -- the 5 is the policy_get fallback repeated, NOT the bound; reading it as the bound was one of five mis-extractions this file records. MAX NULL.',
 5, 0, NULL, 'ottoq.ottoq_readmit_reopened_needs'),
('run_governor_max_sim_minutes',
 '0291: sim minutes a run may reach before public.ottoq_run_governor_auto_stop stops it. min_value 1 COPIED from its inline GREATEST(1, ottoq_policy_get(...,139))::int, which appears at TWO read sites in that one function, both flooring at 1 (P1 asserts both). default_value 139 is the consumer''s fallback and documents what happens with no row; the live global row says 540 and wins at read time. MAX NULL.',
 139, 1, NULL, 'public.ottoq_run_governor_auto_stop'),
('run_stall_timeout_minutes',
 '0291: wall-clock minutes without a tick before public.ottoq_run_governor_auto_stop declares a run stalled. min_value 2 COPIED from its inline GREATEST(2, ottoq_policy_get(...,10))::int -- the only floor of the eighteen that is neither 0 nor 1, and it is the consumer''s number, not a chosen one. MAX NULL.',
 10, 2, NULL, 'public.ottoq_run_governor_auto_stop'),
('tick_cadence_floor_s',
 '0291: the shortest interval public.ottoq_demo_metronome will wait between ticks of a live run, in seconds. min_value 0.2 COPIED from its inline GREATEST(0.2, ottoq_policy_get(...,2.0)) -- the metronome refuses to spin faster than five ticks a second regardless of what is written here. MAX NULL.',
 2.0, 0.2, NULL, 'public.ottoq_demo_metronome'),
('tow_retrieval_min',
 '0291: minutes a tow takes to retrieve an immobilised vehicle in the twin. min_value 0 COPIED from twin.ottoq_sim_vehicle_exception_handler''s inline GREATEST(COALESCE(ottoq_policy_get(...,25),25), 0); the 25 is the policy_get fallback repeated, not the bound. MAX NULL.',
 25, 0, NULL, 'twin.ottoq_sim_vehicle_exception_handler'),
('yard_manoeuvre_s',
 '0291: fixed per-leg manoeuvring overhead added to every yard move by public.ottoq_itin_travel_leg, in seconds. min_value 0 COPIED from its inline GREATEST(0, ottoq_policy_get(...,20)) -- 0 is meaningful (no overhead) and stays inside the range. MAX NULL.',
 20, 0, NULL, 'public.ottoq_itin_travel_leg'),
('yard_taxi_speed_mps',
 '0291: yard taxi speed in metres per second, read by public.ottoq_itin_travel_leg, which computes leg seconds as GREATEST(5.0, (metres / this) + yard_manoeuvre_s). min_value 0.5 COPIED from its inline GREATEST(0.5, ottoq_policy_get(...,3.5)). THIS IS A DIVISOR, and it is the only divisor among the 53 dials swept for 0290 whose consumer guards it inline -- which is exactly why it is catalogable here and metres_per_plan_unit is not (G61). MAX NULL.',
 3.5, 0.5, NULL, 'public.ottoq_itin_travel_leg');

-- ---------------------------------------------------------------------------
-- A1. THE SETTER ACCEPTS THE THREE LIVE VALUES, UNCLAMPED.
DO $a1$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029100cc'::uuid;
  v_r jsonb; k text; v numeric; v_n int := 0;
BEGIN
  FOR k, v IN
    SELECT DISTINCT param_key, param_value FROM public.ottoq_policy_params
     WHERE param_key IN ('night_wave_bands','run_governor_max_sim_minutes',
                         'run_stall_timeout_minutes')
       AND updated_by <> '0291_proof'
  LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, v, '0291_proof');
    IF NOT COALESCE((v_r->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'A1 FAILED: the setter still refuses %: %', k, v_r;
    END IF;
    IF COALESCE((v_r->>'clamped')::boolean,true) THEN
      RAISE EXCEPTION 'A1 FAILED: the live value % = % was altered by the catalog: %', k, v, v_r;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'A1 FAILED: re-offered % live values, expected 3', v_n;
  END IF;
  RAISE NOTICE 'A1 OK: all three live values pass through unchanged';
END $a1$;

-- A2. EVERY FLOOR FIRES AT ITS OWN NUMBER, AND ONLY ONE CEILING EXISTS.
DO $a2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029100cc'::uuid;
  v_r jsonb; r record; v_n int := 0;
BEGIN
  FOR r IN
    -- filter on the description tag alone: an affects-list could silently
    -- under-select and then A2 would pass by testing fewer dials than the file
    -- inserted, which is the narrower-comparison defect G25 was about.
    SELECT c.param_key, c.min_value, c.max_value
      FROM public.ottoq_policy_param_catalog c
     WHERE c.description LIKE '0291:%'
     ORDER BY c.param_key
  LOOP
    -- one below the floor must clamp UP TO THE FLOOR, not to some other number
    v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, r.min_value - 1, '0291_proof');
    IF COALESCE((v_r->>'applied')::numeric, -999) <> r.min_value
       OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
      RAISE EXCEPTION 'A2 FAILED: % below its floor should clamp to % and say so: %',
                      r.param_key, r.min_value, v_r;
    END IF;
    IF r.max_value IS NULL THEN
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, 99999, '0291_proof');
      IF COALESCE((v_r->>'applied')::numeric,-1) <> 99999
         OR COALESCE((v_r->>'clamped')::boolean,true) THEN
        RAISE EXCEPTION 'A2 FAILED: % has no ceiling and must not be clamped at 99999: %',
                        r.param_key, v_r;
      END IF;
    ELSE
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, r.max_value + 1, '0291_proof');
      IF COALESCE((v_r->>'applied')::numeric,-1) <> r.max_value
         OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
        RAISE EXCEPTION 'A2 FAILED: % has a ceiling of % and must clamp to it: %',
                        r.param_key, r.max_value, v_r;
      END IF;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 18 THEN
    RAISE EXCEPTION 'A2 FAILED: tested % dials, the file inserted 18. A test that '
                    'silently covers less than it claims is not a test', v_n;
  END IF;
  RAISE NOTICE 'A2 OK: all 18 floors fire at their own number; the one ceiling fires too';
END $a2$;

-- A3. THE CONSUMER, END TO END, AND A NUMBER THAT MOVES.
--
-- Not "the setter returned 0.5" but "ottoq_itin_travel_leg planned a different
-- leg because of it". Measured before this file: with the dial uncatalogued the
-- setter REFUSED 0.1 (ok=false) and the consumer used its own hard-coded 3.5
-- over a 60.6 m leg for 37 s.
--
-- IT PLANS THE SAME LEG TWICE AND COMPARES THE TWO, rather than comparing one
-- leg against 37. 0290's A3 shipped a magic-number threshold in its first draft
-- and the threshold, not the code, is what failed: the constant had been written
-- for a world an earlier assertion had since changed. The same trap is here in a
-- different costume -- this probe picks whatever finished run is most recent, so
-- the depot, the stall pair and therefore the leg LENGTH are not fixed, and any
-- assertion against 37 would silently be measuring a different leg. So: leg one
-- with no run-scoped row (the consumer's own 3.5), leg two after the catalog
-- admits 0.1 and clamps it to 0.5, same vehicle, same two stalls. Half the speed
-- over the same distance must take longer, whatever the distance is.
--
-- THE WRITES THIS MAKES ROLL THEMSELVES BACK. ottoq_itin_travel_leg inserts an
-- itinerary and a leg against a real sim run -- there is a foreign key, so a
-- scratch uuid cannot be used. The call therefore happens inside a nested
-- BEGIN/EXCEPTION block that RAISEs on success: PL/pgSQL's implicit savepoint
-- discards every row the block wrote, while the plpgsql variables survive to be
-- asserted on out here. Nothing of this probe reaches the run.
DO $a3$
DECLARE
  v_run uuid; v_depot uuid; v_veh uuid; v_a uuid; v_b uuid;
  v_set jsonb; v_leg uuid; v_err text;
  v_basis1 jsonb; v_secs1 int; v_basis2 jsonb; v_secs2 int; v_rows int;
BEGIN
  BEGIN
    SELECT r.sim_run_id, r.depot_id INTO v_run, v_depot
      FROM public.ottoq_sim_runs r
     WHERE r.status <> 'running' AND r.depot_id IS NOT NULL
     ORDER BY r.started_at DESC LIMIT 1;
    SELECT id INTO v_veh FROM vehicles WHERE home_depot_id = v_depot ORDER BY id LIMIT 1;
    SELECT id INTO v_a FROM stalls WHERE depot_id = v_depot ORDER BY id LIMIT 1;
    SELECT id INTO v_b FROM stalls WHERE depot_id = v_depot AND id <> v_a ORDER BY id DESC LIMIT 1;
    IF v_run IS NULL OR v_veh IS NULL OR v_a IS NULL OR v_b IS NULL THEN
      RAISE EXCEPTION 'A3 SETUP: no finished run with a depot, vehicle and two stalls to probe';
    END IF;
    -- the run must not already carry this dial, or leg one is not the baseline
    SELECT count(*) INTO v_rows FROM public.ottoq_policy_params
     WHERE param_key = 'yard_taxi_speed_mps' AND scope_type = 'run' AND scope_id = v_run;
    IF v_rows <> 0 THEN
      RAISE EXCEPTION 'A3 SETUP: run % already has a yard_taxi_speed_mps row; the baseline '
                      'leg would not be the consumer default', v_run;
    END IF;

    -- LEG ONE: no row, so the consumer falls back to its own hard-coded speed
    v_leg := public.ottoq_itin_travel_leg(v_run, v_depot, v_veh, v_a, v_b,
                                          '2026-09-14 12:00:00+00'::timestamptz, 'taxi', '0291_proof');
    SELECT duration_basis, planned_duration_s INTO v_basis1, v_secs1
      FROM public.ottoq_itinerary_legs WHERE leg_id = v_leg;

    -- LEG TWO: same vehicle, same two stalls, with the dial now writable
    v_set := public.ottoq_policy_set('run', v_run, 'yard_taxi_speed_mps', 0.1, '0291_proof');
    v_leg := public.ottoq_itin_travel_leg(v_run, v_depot, v_veh, v_a, v_b,
                                          '2026-09-14 12:00:00+00'::timestamptz, 'taxi', '0291_proof');
    SELECT duration_basis, planned_duration_s INTO v_basis2, v_secs2
      FROM public.ottoq_itinerary_legs WHERE leg_id = v_leg;

    RAISE EXCEPTION 'A3_ROLLBACK_PROBE';
  EXCEPTION WHEN others THEN
    v_err := SQLERRM;
    IF v_err <> 'A3_ROLLBACK_PROBE' THEN
      RAISE EXCEPTION 'A3 FAILED: the probe itself errored: % (%)', v_err, SQLSTATE;
    END IF;
  END;
  IF NOT COALESCE((v_set->>'ok')::boolean,false) THEN
    RAISE EXCEPTION 'A3 FAILED: the setter still refuses yard_taxi_speed_mps: %', v_set;
  END IF;
  IF NOT COALESCE((v_set->>'clamped')::boolean,false)
     OR COALESCE((v_set->>'applied')::numeric,-1) <> 0.5 THEN
    RAISE EXCEPTION 'A3 FAILED: 0.1 should clamp to the consumer''s own floor of 0.5: %', v_set;
  END IF;
  IF COALESCE(v_basis1->>'metres','') <> COALESCE(v_basis2->>'metres','x') THEN
    RAISE EXCEPTION 'A3 FAILED: the two legs are not the same leg (% m vs % m); the '
                    'comparison below would be meaningless',
                    v_basis1->>'metres', v_basis2->>'metres';
  END IF;
  IF COALESCE((v_basis2->>'speed_mps')::numeric,-1) <> 0.5 THEN
    RAISE EXCEPTION 'A3 FAILED: the CONSUMER planned leg two at % m/s, not the 0.5 the '
                    'catalog admitted -- so the dial did not reach it',
                    COALESCE(v_basis2->>'speed_mps','NULL');
  END IF;
  IF COALESCE((v_basis1->>'speed_mps')::numeric,-1) <= 0.5 THEN
    RAISE EXCEPTION 'A3 FAILED: leg one was planned at % m/s, which is not faster than the '
                    'clamped 0.5, so there is nothing for the comparison to show',
                    COALESCE(v_basis1->>'speed_mps','NULL');
  END IF;
  IF v_secs1 IS NULL OR v_secs2 IS NULL OR v_secs2 <= v_secs1 THEN
    RAISE EXCEPTION 'A3 FAILED: the same % m leg took % s at % m/s and % s at % m/s. The '
                    'slower one must take longer; a duration that does not move is not '
                    'evidence the dial was reached',
                    v_basis1->>'metres', v_secs1, v_basis1->>'speed_mps',
                    v_secs2, v_basis2->>'speed_mps';
  END IF;
  RAISE NOTICE 'A3 OK: the same % m leg planned at % m/s in % s with no row, and at % m/s '
               'in % s once the catalog admitted 0.1 and clamped it to the consumer''s own floor',
               v_basis1->>'metres', v_basis1->>'speed_mps', v_secs1,
               v_basis2->>'speed_mps', v_secs2;
END $a3$;

-- A4. metres_per_plan_unit IS STILL REFUSED. 0290's omission survives this file.
DO $a4$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000029100cc'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'metres_per_plan_unit', 0.5, '0291_proof');
  IF COALESCE((v_r->>'ok')::boolean, true)
     OR COALESCE(v_r->>'error','') <> 'unknown_param' THEN
    RAISE EXCEPTION 'A4 FAILED: metres_per_plan_unit is no longer refused as unknown_param: %', v_r;
  END IF;
  RAISE NOTICE 'A4 OK: the one dial the catalog cannot describe is still closed (G61)';
END $a4$;

-- A5. THE SCRATCH IS GONE AND THE THREE LIVE ROWS SURVIVE.
DO $a5$
DECLARE v_n int;
BEGIN
  DELETE FROM public.ottoq_policy_params WHERE updated_by = '0291_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 18 THEN
    RAISE EXCEPTION 'A5 FAILED: expected to remove 18 scratch rows (one per dial), removed %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('night_wave_bands','run_governor_max_sim_minutes','run_stall_timeout_minutes');
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'A5 FAILED: % rows remain across the three keys that had one, expected 3', v_n;
  END IF;
  RAISE NOTICE 'A5 OK: scratch removed, the original 3 live rows survive';
END $a5$;

-- A6. THE GAP INSTRUMENT AGREES, AND G61 IS STILL THE ONLY ONE LEFT OPEN
--     FOR A REASON RATHER THAN FOR LACK OF WORK.
DO $a6$
DECLARE v_ok int; v_gap int; v_mpu text;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'ok') INTO v_ok
    FROM public.ottoq_policy_catalog_gap
   WHERE param_key IN ('bay_defer_horizon_min','bay_defer_max','bay_taxi_min',
     'bay_fault_outage_min','bay_fault_rate_per_tick','cuopt_fire_beat_heartbeat_s',
     'demo_max_real_minutes','night_wave_bands','prearrival_no_show_grace_min',
     'prearrival_shift_horizon_min','prime_inbound_fraction','reopened_need_dwell_min',
     'run_governor_max_sim_minutes','run_stall_timeout_minutes','tick_cadence_floor_s',
     'tow_retrieval_min','yard_manoeuvre_s','yard_taxi_speed_mps');
  IF v_ok <> 18 THEN
    RAISE EXCEPTION 'A6 FAILED: expected all eighteen to report ok, found %', v_ok;
  END IF;
  SELECT count(*) INTO v_gap FROM public.ottoq_policy_catalog_gap
   WHERE status = 'read_uncatalogued';
  IF v_gap <> 35 THEN
    RAISE EXCEPTION 'A6 FAILED: the gap should be 35 after this file, it is %', v_gap;
  END IF;
  SELECT status INTO v_mpu FROM public.ottoq_policy_catalog_gap
   WHERE param_key = 'metres_per_plan_unit';
  IF v_mpu <> 'read_uncatalogued' THEN
    RAISE EXCEPTION 'A6 FAILED: metres_per_plan_unit reports %, expected read_uncatalogued', v_mpu;
  END IF;
  RAISE NOTICE 'A6 OK: eighteen closed, gap 53 -> 35, G61 still the one deliberate hole';
END $a6$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0291_eighteen_dials_whose_consumer_already_wrote_the_range', false,
 'Eighteen rows in ottoq_policy_param_catalog whose min, max and default are COPIED, not derived: each of these consumers already clamps its dial inline at the read site with a literal, and this file lifts that literal into the catalog. P1 pins all eighteen inline clamps by regex over live prosrc, with an exact site count (run_governor_max_sim_minutes has two, both flooring at 1), so an edited clamp refuses the file rather than leaving a stale copy behind. Reframes what the catalog is: ottoq_policy_set REFUSES every uncatalogued key, so an uncatalogued dial is unwritable through the sanctioned path -- measured, three refused writes of yard_taxi_speed_mps while the consumer went on using its own 3.5. Fifteen of the eighteen had no live row at all and had only ever run on the consumer fallback. A3 is end-to-end and self-consistent: it plans the SAME leg twice inside one probe -- once with no run-scoped row, so public.ottoq_itin_travel_leg uses its own hard-coded speed, then again after the catalog admits 0.1 and clamps it to 0.5 -- and asserts the slower one takes longer, with no threshold constant, because the probe picks whatever finished run is most recent and the leg length is therefore not fixed. An earlier draft compared against the 37 s measured beforehand, which is the magic-number contamination 0290's A3 had already been caught by once. The probe runs inside a nested BEGIN/EXCEPTION block that raises on success, so every row it wrote against the real run is discarded by the implicit savepoint while the measured values survive to be asserted. Records the two extraction traps that made five of eight first-pass readings wrong: a COALESCE fallback repeating the policy_get default reads exactly like a bound, and the bounding literal sits on either side of the GREATEST. forces_recert=false, asserted in P0: ottoq_policy_get never reads the catalog, so nothing on any decide or tick path changes.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
