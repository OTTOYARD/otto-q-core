-- migration-version: PENDING
-- migration-name:    0314_vehicles_get_a_position_and_the_eta_stops_being_a_constant
--
-- 0314  GIVE THE TWIN A POSITION, AND DERIVE AN ETA THAT MOVES
--
-- NEW FUNCTIONS ONLY. Nothing calls them yet, so this migration changes no
-- behaviour and forces no recertification. 0315 wires them in; that one will.
-- Splitting it this way means the model can be exercised against live runs and
-- argued about BEFORE it is allowed to move a booking calendar.
--
-- ---------------------------------------------------------------------------
-- WHY
--
-- ottoq_return_eta_minutes takes a vehicle id and a depot id and ignores both:
--     SELECT GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id,'return_eta_minutes',30), 30));
-- All 123,665 dispatch rows carrying return_eta_minutes hold the single value
-- 30, and the engine stamps its own guess honestly -- eta_source reads
-- 'policy_constant:return_eta_minutes' on 44,046 rows, and the evidence blob
-- literally carries 'eta_minutes_is_a_parameter', true.
--
-- That constant is the TIME AXIS of the forward demand curve (0312 fixed the
-- magnitude axis). A curve that knows how much energy is inbound but places
-- every arrival at the same instant carries one bit of information: the count.
--
-- You cannot compute a travel time without knowing where the vehicle is, and
-- the engine did not know: ottoq_telemetry_packets.current_lat / .current_lng
-- are the ONLY latitude/longitude columns in the database and both were NULL
-- in all 406,054 rows. This migration closes that.
--
-- ---------------------------------------------------------------------------
-- THE MODEL, AND WHICH PARTS ARE SOURCED
--
-- SOURCED, from the calibration registry already in this database (each row
-- carries its own source_url and date range):
--   * measured speed: ottoq_telemetry_packets.speed_kmh, 394,334 packets,
--     mean 35.2 km/h, p10 15.5, p90 57.2. Each vehicle's own recent speed is
--     preferred; the fleet mean is the fallback.
--   * depot coordinates: public.depots.origin_lat / origin_lng (3 of 5 depots
--     populated; the model returns NULL for a depot without coordinates rather
--     than inventing one).
--
-- SOURCED, by direct search on 2026-09-14 under the amended firewall (a claim,
-- a date, a URL):
--   * TomTom Traffic Index, Nashville TN, 2025 edition
--     https://www.tomtom.com/traffic-index/city/nashville-tn/
--     city-wide average speed 27.5 km/h; 57 hours lost in rush hour in 2025,
--     5 h 06 min more than 2024. The depots are Nashville (36.140, -86.773),
--     which is also the NOAA GHCN station already calibrated here (USW00013897).
--
-- ASSUMPTION -- pending R-14, and labelled as such in the function body:
--   * the SHAPE within each regime. TomTom's hour-by-hour table is rendered
--     client-side and was not retrievable as text; the page exposes only
--     "24/7", "All days", "Morning rush hour", "Evening rush hour". So the
--     peak/off-peak CONTRAST is sourced and the hourly curve is not. The three
--     regime factors below are chosen to average to 1.0 over 24 hours so they
--     re-time arrivals without silently re-scaling the fleet's mean speed.
--   * the rush-hour clock windows (07:00-09:00 and 16:00-18:00 LOCAL).
--   * weather is NOT modelled here at all. R-14 question 4 asks for a published
--     speed-reduction factor per mm of precipitation; until it lands, adding one
--     would be inventing a coefficient to remove a constant, which is the defect
--     class 0238 convicted.
--
-- TWO INTERNAL CANDIDATES WERE REJECTED RATHER THAN USED, and the reasons
-- matter more than the choice:
--   * nyc_tlc / trip_duration_minutes is fitted over 3,503,651 samples but at
--     segment='global' only -- there is no hourly segment, and the raw rows are
--     not in the database, only the fitted grid.
--   * our own speed_kmh by hour varies over a band of only +/-6% (31.5 to 37.2
--     km/h) on wildly unequal samples -- 126,626 packets at 02:00 UTC against
--     179 at 08:00 -- because 1,082 of 1,110 sim runs start at 21:00 CT. Fitting
--     a congestion curve to that would be circular (the twin generated those
--     speeds) and thin.
--
-- ---------------------------------------------------------------------------
-- DETERMINISM. Every draw is keyed on the run's random_seed through
-- twin.ottoq_sim_seeded_random, which is a pure hash with no sequence to fall
-- out of step. Bearings key on (vehicle, dispatch) so a vehicle keeps ONE
-- heading for a whole trip rather than re-drawing per tick. Every read is
-- run-scoped and bounded by the SIM clock. Local time is derived with
-- AT TIME ZONE 'America/Chicago' so daylight saving is handled by the database
-- rather than by an offset constant (CLAUDE.md rule 7: storage stays UTC).
--
-- forces_recert: FALSE. Four new functions, zero callers. Asserted in A4.
-- Lineage row IN THIS FILE.
-- ===========================================================================

DO $pre$
DECLARE v_depots int; v_with_coords int;
BEGIN
  -- P1. NONE OF THESE NAMES IS ALREADY TAKEN. A CREATE OR REPLACE that
  --     silently overwrote an existing function would be a disaster wearing a
  --     success message.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public'
                AND p.proname IN ('ottoq_congestion_factor','ottoq_trip_geometry',
                                  'ottoq_vehicle_position','ottoq_computed_eta_minutes')) THEN
    RAISE EXCEPTION '0314 P1: one of the four function names already exists; this migration would overwrite it';
  END IF;

  -- P2. THE SUBSTRATE THE MODEL READS IS REALLY THERE.
  SELECT count(*), count(origin_lat) INTO v_depots, v_with_coords FROM public.depots;
  IF v_with_coords = 0 THEN
    RAISE EXCEPTION '0314 P2: no depot has origin_lat; every position would be NULL';
  END IF;
  RAISE NOTICE '0314: % of % depots carry coordinates', v_with_coords, v_depots;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='twin' AND p.proname='ottoq_sim_seeded_random') THEN
    RAISE EXCEPTION '0314 P2: twin.ottoq_sim_seeded_random is absent; there is no deterministic draw to key on';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='st_project') THEN
    RAISE EXCEPTION '0314 P2: PostGIS ST_Project is absent; positions cannot be projected';
  END IF;
END $pre$;

-- ---------------------------------------------------------------------------
-- (1) CONGESTION. A speed multiplier by local hour.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_congestion_factor(p_sim_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- ASSUMPTION -- pending R-14. The peak/off-peak CONTRAST is sourced (TomTom
  -- Traffic Index, Nashville TN 2025: 27.5 km/h city average, 57 hours lost to
  -- rush hour); the hourly SHAPE and these exact window edges are not.
  --
  -- 0.75 on four peak hours and 1.05 on the other twenty average to exactly
  -- 1.0 over the day ((4*0.75 + 20*1.05)/24 = 1.0), so this re-times arrivals
  -- WITHOUT quietly re-scaling the fleet's mean speed. That property is the
  -- reason for these particular numbers and must survive any revision: a
  -- congestion model that also changes the daily mean is two changes wearing
  -- one name.
  SELECT CASE
    WHEN EXTRACT(HOUR FROM (p_sim_clock AT TIME ZONE 'America/Chicago'))::int BETWEEN 7 AND 8  THEN 0.75
    WHEN EXTRACT(HOUR FROM (p_sim_clock AT TIME ZONE 'America/Chicago'))::int BETWEEN 16 AND 17 THEN 0.75
    ELSE 1.05
  END::numeric;
$function$;

COMMENT ON FUNCTION public.ottoq_congestion_factor(timestamptz) IS
'Speed multiplier by LOCAL hour (America/Chicago; the depots are Nashville and storage stays UTC per '
'CLAUDE.md rule 7). 0.75 during 07:00-09:00 and 16:00-18:00, 1.05 otherwise, which averages to exactly '
'1.0 over 24 hours so it re-times arrivals without re-scaling mean speed. The peak/off-peak contrast is '
'sourced -- TomTom Traffic Index Nashville TN 2025, 27.5 km/h city average and 57 hours lost to rush hour, '
'https://www.tomtom.com/traffic-index/city/nashville-tn/ read 2026-09-14. The hourly SHAPE and the window '
'edges are ASSUMPTION pending research request R-14, whose answer replaces this body without touching any '
'call site. Weather is deliberately NOT modelled here: R-14 q4 asks for a published speed-reduction factor '
'per mm of precipitation, and inventing one to remove a constant is the defect class db/checks/0238 convicted.';

-- ---------------------------------------------------------------------------
-- (2) TRIP GEOMETRY. Where along an out-and-back trip the vehicle is.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_trip_geometry(
  p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock timestamp with time zone)
 RETURNS TABLE(bearing_deg numeric, radius_km numeric, progress numeric, distance_km numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_disp record; v_seed bigint; v_speed numeric; v_elapsed numeric;
BEGIN
  SELECT d.dispatch_id, d.dispatched_at, d.planned_duration_min
    INTO v_disp
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.vehicle_id = p_vehicle_id
     AND d.sim_run_id = p_sim_run_id                 -- run-scoped
     AND d.status IN ('active','returning')
     AND d.dispatched_at IS NOT NULL
   ORDER BY d.dispatched_at DESC, d.dispatch_id DESC -- deterministic tiebreak
   LIMIT 1;
  IF v_disp.dispatch_id IS NULL OR COALESCE(v_disp.planned_duration_min,0) <= 0 THEN RETURN; END IF;

  SELECT r.random_seed INTO v_seed FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_seed IS NULL THEN RETURN; END IF;

  -- This vehicle's own recent speed on this trip, else the measured fleet mean.
  -- 35.2 km/h is not a guess: it is avg(speed_kmh) over 394,334 telemetry packets.
  SELECT COALESCE(avg(tp.speed_kmh), 35.2) INTO v_speed
    FROM public.ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id
     AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at >= v_disp.dispatched_at
     AND tp.sim_clock_at <= p_sim_clock                -- SIM clock, never the wall clock
     AND tp.speed_kmh > 0;
  v_speed := GREATEST(COALESCE(v_speed, 35.2), 5.0);

  -- ONE heading per trip: the salt keys on the dispatch, not on the clock, so a
  -- vehicle does not teleport onto a new bearing at every tick.
  bearing_deg := round((twin.ottoq_sim_seeded_random(
                          v_seed, 'trip_bearing:'||p_vehicle_id::text||':'||v_disp.dispatch_id::text) * 360.0)::numeric, 3);

  -- Out and back: the farthest point is reached at the midpoint of the plan, so
  -- the radius is half the planned duration travelled at the vehicle's speed.
  radius_km := round((v_disp.planned_duration_min / 2.0 * v_speed / 60.0)::numeric, 3);

  v_elapsed := EXTRACT(EPOCH FROM (p_sim_clock - v_disp.dispatched_at))/60.0;
  progress  := round(LEAST(1.0, GREATEST(0.0, v_elapsed / v_disp.planned_duration_min))::numeric, 6);

  -- Triangular profile: 0 at dispatch, radius at the midpoint, 0 on return.
  distance_km := round((radius_km * (1.0 - abs(2.0*progress - 1.0)))::numeric, 3);

  RETURN NEXT;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_trip_geometry(uuid,uuid,timestamptz) IS
'Where a deployed vehicle is along an out-and-back trip: a bearing held constant for the whole dispatch, '
'the radius it reaches at the midpoint, its progress 0..1, and its current distance from the depot. '
'Deterministic: the bearing is drawn from twin.ottoq_sim_seeded_random keyed on the run seed plus '
'(vehicle, dispatch) so it does not re-draw per tick; every read is run-scoped and bounded by the sim '
'clock. Radius uses the vehicle''s own mean speed on this trip, falling back to 35.2 km/h, which is the '
'measured mean over 394,334 telemetry packets rather than a chosen number. Returns no row when there is no '
'active dispatch or no planned duration -- absence, not a fabricated position. Added by 0314.';

-- ---------------------------------------------------------------------------
-- (3) POSITION. The geometry projected onto the map from the depot.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_position(
  p_vehicle_id uuid, p_depot_id uuid, p_sim_run_id uuid, p_sim_clock timestamp with time zone)
 RETURNS TABLE(lat double precision, lng double precision, distance_km numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_g record; v_lat double precision; v_lng double precision; v_pt geography;
BEGIN
  SELECT d.origin_lat, d.origin_lng INTO v_lat, v_lng
    FROM public.depots d WHERE d.id = p_depot_id;
  IF v_lat IS NULL OR v_lng IS NULL THEN RETURN; END IF;   -- no coordinates: no position, not a guess

  SELECT * INTO v_g FROM public.ottoq_trip_geometry(p_vehicle_id, p_sim_run_id, p_sim_clock);
  IF v_g.distance_km IS NULL THEN RETURN; END IF;

  -- ST_Project takes metres and an azimuth in RADIANS.
  v_pt := ST_Project(ST_MakePoint(v_lng, v_lat)::geography,
                     (v_g.distance_km * 1000.0)::double precision,
                     radians(v_g.bearing_deg::double precision));
  lat := ST_Y(v_pt::geometry);
  lng := ST_X(v_pt::geometry);
  distance_km := v_g.distance_km;
  RETURN NEXT;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_vehicle_position(uuid,uuid,uuid,timestamptz) IS
'A deployed vehicle''s latitude and longitude, projected from its depot along the bearing and distance '
'ottoq_trip_geometry derives. Returns no row when the depot has no coordinates (2 of 5 depots) or the '
'vehicle has no active dispatch -- a missing position is reported as missing, never as the depot itself, '
'because a vehicle silently sitting at its depot would read as an arrival. Added by 0314; before it, '
'ottoq_telemetry_packets.current_lat/.current_lng were the only lat/lng columns in the database and were '
'NULL in all 406,054 rows.';

-- ---------------------------------------------------------------------------
-- (4) THE ETA THAT MOVES.
-- ---------------------------------------------------------------------------
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
  IF v_g.distance_km IS NULL THEN RETURN NULL; END IF;   -- unknown, never a default

  SELECT COALESCE(avg(tp.speed_kmh), 35.2) INTO v_speed
    FROM public.ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id
     AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at <= p_sim_clock
     AND tp.speed_kmh > 0;
  v_speed := GREATEST(COALESCE(v_speed, 35.2), 5.0) * public.ottoq_congestion_factor(p_sim_clock);

  v_eta := v_g.distance_km / v_speed * 60.0;

  -- Floor of 1 minute so an arriving vehicle never reports zero; cap of 240 so
  -- a pathological radius cannot push a booking a week out. Both are bounds on
  -- an output, not tunables on a model.
  RETURN round(LEAST(240.0, GREATEST(1.0, v_eta))::numeric, 1);
END;
$function$;

COMMENT ON FUNCTION public.ottoq_computed_eta_minutes(uuid,uuid,uuid,timestamptz) IS
'Minutes until this vehicle reaches its depot: its current distance divided by its own recent speed, '
'modulated by ottoq_congestion_factor for the local hour. RECOMPUTED EVERY CALL, so the answer moves as the '
'vehicle moves and as it crosses a rush-hour boundary -- which is the point. Returns NULL when the vehicle '
'has no active dispatch, so callers must fall back explicitly rather than receive a default. Replaces, at '
'0315, ottoq_return_eta_minutes, which took a vehicle id and a depot id, ignored both, and returned the '
'policy constant 30 for all 123,665 dispatch rows in the engine''s history. Bounded to [1, 240] minutes. '
'Added by 0314 with no callers; 0315 wires it and forces recertification.';

DO $post$
DECLARE
  v_n int; v_pos int; v_eta_n int; v_lo numeric; v_hi numeric; v_dist_hi numeric; v_callers int;
  v_f1 numeric; v_f2 numeric;
BEGIN
  -- A1. CONGESTION AVERAGES TO 1.0 OVER THE DAY. If it does not, the model is
  --     silently re-scaling fleet speed as well as re-timing arrivals.
  SELECT round(avg(public.ottoq_congestion_factor(
           ('2026-06-15 00:00:00-05'::timestamptz + (h || ' hours')::interval)))::numeric, 4)
    INTO v_f1 FROM generate_series(0,23) h;
  IF v_f1 <> 1.0000 THEN
    RAISE EXCEPTION '0314 A1: congestion factors average % over 24 hours, not 1.0; the model re-scales mean speed', v_f1;
  END IF;
  -- and it must actually VARY, or it is a constant with extra steps.
  SELECT count(DISTINCT public.ottoq_congestion_factor(
           ('2026-06-15 00:00:00-05'::timestamptz + (h || ' hours')::interval))) INTO v_n
    FROM generate_series(0,23) h;
  IF v_n < 2 THEN
    RAISE EXCEPTION '0314 A1: congestion factor takes % distinct value(s) across the day', v_n;
  END IF;

  -- A2. THE GEOMETRY AND THE POSITION PRODUCE REAL VALUES on live deployed
  --     vehicles, and the ETA VARIES -- the whole defect being fixed is an ETA
  --     that took one value, so a new one that takes one value fixes nothing.
  SELECT count(*), count(x.lat), count(x.eta), min(x.eta), max(x.eta), max(x.dist)
    INTO v_n, v_pos, v_eta_n, v_lo, v_hi, v_dist_hi
    FROM (SELECT (public.ottoq_vehicle_position(d.vehicle_id, r.depot_id, d.sim_run_id,
                    COALESCE(r.sim_clock_current, r.sim_clock_start))).lat AS lat,
                 (public.ottoq_vehicle_position(d.vehicle_id, r.depot_id, d.sim_run_id,
                    COALESCE(r.sim_clock_current, r.sim_clock_start))).distance_km AS dist,
                 public.ottoq_computed_eta_minutes(d.vehicle_id, r.depot_id, d.sim_run_id,
                    COALESCE(r.sim_clock_current, r.sim_clock_start)) AS eta
            FROM public.ottoq_vehicle_dispatches d
            JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
           WHERE d.status IN ('active','returning')
             AND COALESCE(r.sim_clock_current, r.sim_clock_start) IS NOT NULL) x;

  IF v_n = 0 THEN
    RAISE NOTICE '0314 A2: no deployed vehicles to exercise right now';
  ELSE
    IF v_eta_n = 0 THEN
      RAISE EXCEPTION '0314 A2: the computed ETA was NULL for all % deployed vehicles', v_n;
    END IF;
    IF v_lo = v_hi THEN
      RAISE EXCEPTION '0314 A2: the computed ETA took ONE value (%) across % vehicles; '
                      'that is the defect this migration exists to fix', v_lo, v_eta_n;
    END IF;
    IF v_dist_hi IS NOT NULL AND v_dist_hi > 2000 THEN
      RAISE EXCEPTION '0314 A2: max distance from depot is % km, which is not a depot trip', v_dist_hi;
    END IF;
    RAISE NOTICE '0314 A2 OK -- % deployed: % positions, % ETAs spanning % to % min, max distance % km',
                 v_n, v_pos, v_eta_n, v_lo, v_hi, v_dist_hi;
  END IF;

  -- A3. DETERMINISM: the same inputs twice must give the same answer.
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
    RAISE EXCEPTION '0314 A3: the ETA is not reproducible within a single statement';
  END IF;

  -- A4. NOTHING CALLS THESE YET. This is the whole basis of forces_recert=false.
  SELECT count(*) INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.proname NOT IN ('ottoq_congestion_factor','ottoq_trip_geometry',
                           'ottoq_vehicle_position','ottoq_computed_eta_minutes')
     AND (p.prosrc LIKE '%ottoq_computed_eta_minutes%' OR p.prosrc LIKE '%ottoq_vehicle_position%'
          OR p.prosrc LIKE '%ottoq_trip_geometry%' OR p.prosrc LIKE '%ottoq_congestion_factor%');
  IF v_callers <> 0 THEN
    RAISE EXCEPTION '0314 A4: % function(s) already call the new code; forces_recert=false is then false', v_callers;
  END IF;
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0314_vehicles_get_a_position_and_the_eta_stops_being_a_constant', false,
   'Four NEW functions -- ottoq_congestion_factor, ottoq_trip_geometry, ottoq_vehicle_position, '
   'ottoq_computed_eta_minutes -- giving deployed vehicles a position and a travel-time estimate that '
   'recomputes every call. ZERO callers: A4 asserts that no other function references any of the four, '
   'which is the entire basis for forces_recert=false. 0315 wires them into ottoq_return_eta_minutes and '
   'the telemetry emitter and WILL force recertification. Determinism: bearings drawn from '
   'twin.ottoq_sim_seeded_random keyed on the run seed plus (vehicle, dispatch) so they do not re-draw per '
   'tick; all reads run-scoped and sim-clock bounded; A3 asserts reproducibility. The peak/off-peak '
   'contrast is sourced to TomTom Traffic Index Nashville 2025; the hourly shape, the window edges and any '
   'weather effect are ASSUMPTION pending research request R-14.',
   now())
ON CONFLICT (name) DO NOTHING;
