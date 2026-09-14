-- migration-version: 20260914164649
-- migration-name:    0315_the_speed_cancelled_out_of_my_own_eta
--
-- 0315  THE ETA 0314 SHIPPED LOOKED LIKE DISTANCE OVER SPEED AND WAS NOT
--
-- Replaces two of the four functions 0314 added. Still ZERO callers, so this
-- forces no recertification either. 0314 was applied 45 minutes ago and its own
-- assertions passed; the defect below was found by MEASURING the live output,
-- which is the only reason it was caught before anything depended on it.
--
-- ---------------------------------------------------------------------------
-- DEFECT 1 -- THE SPEED CANCELLED
--
-- 0314's ottoq_trip_geometry set the trip radius from the vehicle's own speed:
--     radius_km := planned_duration_min / 2.0 * v_speed / 60.0;
-- and ottoq_computed_eta_minutes then divided by that same speed:
--     v_eta := distance_km / (v_speed * congestion) * 60.0;
--
-- Substituting, v_speed cancels exactly:
--     eta = (planned_duration/2 * shape) / congestion
--
-- So the ETA was remaining planned trip time divided by a congestion factor,
-- wearing the costume of distance over speed. It varied, it responded to rush
-- hour, and it read the vehicle's position not at all.
--
-- MEASURED, which is how it was caught: of 100 deployed vehicles, 50 shared
-- progress 0.857143 with distances spanning 20.6 to 37.1 km -- and every one of
-- them returned the identical ETA of 57.1 minutes. Different distances, same
-- answer. A quantity that cannot distinguish 20.6 km from 37.1 km is not a
-- travel time.
--
-- This is the same class 0238 convicted -- an instrument answering a slightly
-- different question than the one asked -- committed by this agent, in a
-- migration whose own header criticised the class. The fix is that the radius
-- must come from a source INDEPENDENT of the speed it is later divided by.
--
-- DEFECT 2 -- OVERDUE VEHICLES WERE MODELLED AS ALREADY HOME
--
-- The triangular profile distance = radius * (1 - |2p - 1|) returns 0 at p=1,
-- and progress was clamped to [0,1]. Measured: 34 of 100 open dispatches have
-- elapsed past their planned duration, so 34 vehicles reported distance 0.0 km
-- and the ETA floor of 1.0 minute -- i.e. "arriving now" -- while still
-- dispatched and still out. A vehicle with an OPEN dispatch is by definition
-- not at its depot.
--
-- ---------------------------------------------------------------------------
-- THE FIX, AND WHERE THE NUMBERS COME FROM
--
-- RADIUS is now drawn from NREL Fleet DNA daily_miles_driven -- 14,792 samples,
-- mean 122.07 miles, range 10.2 to 330.5, already fitted in
-- ottoq_calibration_distributions with its own source_url
-- (https://www.nrel.gov/transportation/fleettest-fleet-dna.html) -- through the
-- existing ottoq_sample_calibrated draw, which is seeded and therefore
-- deterministic. Divided by 2 (out and back) and by the MEASURED 4.00 trips per
-- vehicle per day (computed over every dispatch in ottoq_vehicle_dispatches
-- with at least 3 trips), and converted at 1.609 km per mile:
--
--     radius_km = daily_miles_draw * 1.609 / (2 * 4.00)
--
-- A mean draw of 122 miles gives a ~24.5 km service radius; the 221-mile draw
-- observed at seed 171717 gives 44.4 km. Nothing in that expression is the
-- vehicle's speed, which is the entire point.
--
-- OVERDUE vehicles are held on the return leg instead of teleported home: once
-- progress reaches 1 the distance floors at 1.0 km while the dispatch stays
-- open, so the ETA reads as "a few minutes out" rather than "arrived". That
-- floor is a statement about dispatch state, not a tuned parameter: an open
-- dispatch means not home.
--
-- forces_recert: FALSE -- still zero callers, asserted in A4.
-- ===========================================================================

DO $pre$
DECLARE v_same int;
BEGIN
  -- P1. BOTH FUNCTIONS EXIST (0314 applied) so this is a replacement, not a new install.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='ottoq_trip_geometry') THEN
    RAISE EXCEPTION '0315 P1: ottoq_trip_geometry is absent; 0314 has not been applied';
  END IF;

  -- P2. THE DEFECT IS STILL PRESENT. If the speed no longer cancels, something
  --     else changed and this migration must not be applied blind.
  IF (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_trip_geometry')
     NOT LIKE '%planned_duration_min / 2.0 * v_speed / 60.0%' THEN
    RAISE EXCEPTION '0315 P2: the speed-derived radius is not in ottoq_trip_geometry; the defect this migration fixes is absent';
  END IF;

  -- P3. THE CALIBRATED DRAW THIS FIX DEPENDS ON REALLY RESOLVES.
  IF public.ottoq_sample_calibrated('daily_miles_driven','global', 171717, '0315_pre') IS NULL THEN
    RAISE EXCEPTION '0315 P3: ottoq_sample_calibrated returns NULL for daily_miles_driven; the radius would have no source';
  END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.ottoq_trip_geometry(
  p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock timestamp with time zone)
 RETURNS TABLE(bearing_deg numeric, radius_km numeric, progress numeric, distance_km numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_disp record; v_seed bigint; v_elapsed numeric; v_miles numeric; v_raw numeric;
  -- Measured over every vehicle-run with >=3 dispatches: 4.00 trips per vehicle
  -- per day. Used to turn a DAILY mileage draw into a single-trip radius.
  c_trips_per_day CONSTANT numeric := 4.00;
  c_km_per_mile   CONSTANT numeric := 1.609;
  -- An open dispatch means the vehicle is not at its depot. 0314 let overdue
  -- vehicles report distance 0 and therefore "arriving now"; 34 of 100 did.
  c_open_floor_km CONSTANT numeric := 1.0;
BEGIN
  SELECT d.dispatch_id, d.dispatched_at, d.planned_duration_min INTO v_disp
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.vehicle_id = p_vehicle_id
     AND d.sim_run_id = p_sim_run_id
     AND d.status IN ('active','returning')
     AND d.dispatched_at IS NOT NULL
   ORDER BY d.dispatched_at DESC, d.dispatch_id DESC
   LIMIT 1;
  IF v_disp.dispatch_id IS NULL OR COALESCE(v_disp.planned_duration_min,0) <= 0 THEN RETURN; END IF;

  SELECT r.random_seed INTO v_seed FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_seed IS NULL THEN RETURN; END IF;

  bearing_deg := round((twin.ottoq_sim_seeded_random(
                          v_seed, 'trip_bearing:'||p_vehicle_id::text||':'||v_disp.dispatch_id::text) * 360.0)::numeric, 3);

  -- 0315: the radius is drawn from NREL Fleet DNA daily_miles_driven and is
  -- INDEPENDENT OF SPEED. 0314 derived it from the vehicle's own speed and then
  -- divided by that same speed, so the speed cancelled and the ETA could not
  -- tell 20.6 km from 37.1 km.
  v_miles := public.ottoq_sample_calibrated(
               'daily_miles_driven', 'global', v_seed,
               'trip_radius:'||p_vehicle_id::text||':'||v_disp.dispatch_id::text);
  radius_km := round((COALESCE(v_miles, 122.07) * c_km_per_mile / (2.0 * c_trips_per_day))::numeric, 3);

  v_elapsed := EXTRACT(EPOCH FROM (p_sim_clock - v_disp.dispatched_at))/60.0;
  progress  := round(LEAST(1.0, GREATEST(0.0, v_elapsed / v_disp.planned_duration_min))::numeric, 6);

  v_raw := radius_km * (1.0 - abs(2.0*progress - 1.0));
  -- While the dispatch is OPEN the vehicle is not home, whatever the plan said.
  distance_km := round(GREATEST(v_raw, c_open_floor_km)::numeric, 3);

  RETURN NEXT;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_trip_geometry(uuid,uuid,timestamptz) IS
'Where a deployed vehicle is along an out-and-back trip: a bearing held constant for the whole dispatch, '
'the service radius it reaches at the midpoint, progress 0..1, and current distance from the depot. '
'0315: the radius is drawn from NREL Fleet DNA daily_miles_driven (14,792 samples, mean 122.07 miles, '
'https://www.nrel.gov/transportation/fleettest-fleet-dna.html) via ottoq_sample_calibrated, divided by 2 '
'for out-and-back and by the MEASURED 4.00 trips per vehicle per day. It is INDEPENDENT OF SPEED by '
'construction -- 0314 derived it FROM the vehicle''s speed and ottoq_computed_eta_minutes then divided by '
'that same speed, so the speed cancelled exactly and the ETA could not distinguish a 20.6 km vehicle from '
'a 37.1 km one (50 live vehicles, identical 57.1 min). Distance floors at 1.0 km while the dispatch is '
'open, because an open dispatch means the vehicle is not at its depot; 0314 let 34 of 100 overdue vehicles '
'report distance 0 and therefore "arriving now". Deterministic: every draw is seeded on the run seed plus '
'(vehicle, dispatch), so nothing re-draws per tick.';

CREATE OR REPLACE FUNCTION public.ottoq_computed_eta_minutes(
  p_vehicle_id uuid, p_depot_id uuid, p_sim_run_id uuid, p_sim_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_g record; v_speed numeric; v_eta numeric;
BEGIN
  SELECT * INTO v_g FROM public.ottoq_trip_geometry(p_vehicle_id, p_sim_run_id, p_sim_clock);
  IF v_g.distance_km IS NULL THEN RETURN NULL; END IF;

  -- The vehicle's OWN measured speed. Since 0315 the radius no longer derives
  -- from this quantity, so it does not cancel: a slow vehicle at a given
  -- distance now genuinely reports a longer ETA than a fast one.
  SELECT COALESCE(avg(tp.speed_kmh), 35.2) INTO v_speed
    FROM public.ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at <= p_sim_clock AND tp.speed_kmh > 0;
  v_speed := GREATEST(COALESCE(v_speed, 35.2), 5.0) * public.ottoq_congestion_factor(p_sim_clock);

  v_eta := v_g.distance_km / v_speed * 60.0;
  RETURN round(LEAST(240.0, GREATEST(1.0, v_eta))::numeric, 1);
END;
$function$;

DO $post$
DECLARE v_pairs int; v_varying int; v_floor_open int; v_callers int; v_n int; v_d int;
BEGIN
  -- A1. THE DECISIVE TEST: at the SAME progress, different vehicles must now
  --     return DIFFERENT ETAs. This is precisely what failed before 0315 and no
  --     other assertion would have caught it.
  WITH live AS (
    SELECT d.vehicle_id, r.depot_id, d.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) AS clk
      FROM public.ottoq_vehicle_dispatches d
      JOIN public.ottoq_sim_runs r ON r.sim_run_id=d.sim_run_id
     WHERE d.status IN ('active','returning') AND COALESCE(r.sim_clock_current, r.sim_clock_start) IS NOT NULL
  ), calc AS (
    SELECT g.progress,
           public.ottoq_computed_eta_minutes(l.vehicle_id,l.depot_id,l.sim_run_id,l.clk) AS eta
      FROM live l LEFT JOIN LATERAL public.ottoq_trip_geometry(l.vehicle_id,l.sim_run_id,l.clk) g ON TRUE
  ), grp AS (
    SELECT progress, count(*) AS n, count(DISTINCT eta) AS d
      FROM calc WHERE progress IS NOT NULL AND eta IS NOT NULL GROUP BY progress HAVING count(*) >= 3
  )
  SELECT count(*), count(*) FILTER (WHERE d > 1) INTO v_pairs, v_varying FROM grp;

  IF v_pairs = 0 THEN
    RAISE NOTICE '0315 A1: no progress bucket has 3+ vehicles right now; the cancellation test is unexercised';
  ELSIF v_varying = 0 THEN
    RAISE EXCEPTION '0315 A1: across % progress bucket(s) with 3+ vehicles each, EVERY bucket still returns a '
                    'single distinct ETA -- the speed still cancels and this migration fixed nothing', v_pairs;
  ELSE
    RAISE NOTICE '0315 A1 OK -- % of % multi-vehicle progress buckets now show varying ETAs', v_varying, v_pairs;
  END IF;

  -- A2. NO OPEN DISPATCH MAY REPORT ITSELF HOME.
  SELECT count(*) INTO v_floor_open
    FROM public.ottoq_vehicle_dispatches d
    JOIN public.ottoq_sim_runs r ON r.sim_run_id=d.sim_run_id
    LEFT JOIN LATERAL public.ottoq_trip_geometry(d.vehicle_id, d.sim_run_id,
                 COALESCE(r.sim_clock_current, r.sim_clock_start)) g ON TRUE
   WHERE d.status IN ('active','returning')
     AND COALESCE(r.sim_clock_current, r.sim_clock_start) IS NOT NULL
     AND g.distance_km IS NOT NULL AND g.distance_km <= 0;
  IF v_floor_open > 0 THEN
    RAISE EXCEPTION '0315 A2: % open dispatch(es) report distance 0 km; an open dispatch is not at the depot', v_floor_open;
  END IF;

  -- A3. REPRODUCIBLE.
  IF EXISTS (
    SELECT 1 FROM public.ottoq_vehicle_dispatches d
      JOIN public.ottoq_sim_runs r ON r.sim_run_id=d.sim_run_id
     WHERE d.status IN ('active','returning')
       AND COALESCE(r.sim_clock_current, r.sim_clock_start) IS NOT NULL
       AND public.ottoq_computed_eta_minutes(d.vehicle_id, r.depot_id, d.sim_run_id,
             COALESCE(r.sim_clock_current, r.sim_clock_start))
        IS DISTINCT FROM
           public.ottoq_computed_eta_minutes(d.vehicle_id, r.depot_id, d.sim_run_id,
             COALESCE(r.sim_clock_current, r.sim_clock_start))) THEN
    RAISE EXCEPTION '0315 A3: the ETA is not reproducible within a single statement';
  END IF;

  -- A4. STILL ZERO CALLERS -- the basis for forces_recert=false.
  SELECT count(*) INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.proname NOT IN ('ottoq_congestion_factor','ottoq_trip_geometry',
                           'ottoq_vehicle_position','ottoq_computed_eta_minutes')
     AND (p.prosrc LIKE '%ottoq_computed_eta_minutes%' OR p.prosrc LIKE '%ottoq_vehicle_position%'
          OR p.prosrc LIKE '%ottoq_trip_geometry%' OR p.prosrc LIKE '%ottoq_congestion_factor%');
  IF v_callers <> 0 THEN
    RAISE EXCEPTION '0315 A4: % function(s) now call this code; forces_recert=false is then false', v_callers;
  END IF;

  SELECT count(*), count(DISTINCT public.ottoq_computed_eta_minutes(d.vehicle_id, r.depot_id, d.sim_run_id,
             COALESCE(r.sim_clock_current, r.sim_clock_start)))
    INTO v_n, v_d
    FROM public.ottoq_vehicle_dispatches d
    JOIN public.ottoq_sim_runs r ON r.sim_run_id=d.sim_run_id
   WHERE d.status IN ('active','returning') AND COALESCE(r.sim_clock_current, r.sim_clock_start) IS NOT NULL;
  RAISE NOTICE '0315 applied -- % deployed vehicles now yield % distinct ETAs (0314 yielded 9)', v_n, v_d;
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0315_the_speed_cancelled_out_of_my_own_eta', false,
   'Replaces ottoq_trip_geometry and ottoq_computed_eta_minutes from 0314. 0314 set the trip radius from '
   'the vehicle''s own speed and then divided by that same speed, so the speed cancelled exactly and the '
   'ETA reduced to remaining planned time over congestion -- measured: 50 live vehicles at progress '
   '0.857143 with distances 20.6 to 37.1 km all returned an identical 57.1 minutes. 0315 draws the radius '
   'from NREL Fleet DNA daily_miles_driven via ottoq_sample_calibrated, divided by 2 for out-and-back and '
   'by the measured 4.00 trips per vehicle per day, making it independent of speed by construction. It '
   'also floors distance at 1.0 km while a dispatch is open, because 0314 let 34 of 100 overdue vehicles '
   'report distance 0 and therefore "arriving now". Still ZERO callers (A4), so forces_recert=false; A1 is '
   'the decisive test that ETAs now vary WITHIN a progress bucket.',
   now())
ON CONFLICT (name) DO NOTHING;
