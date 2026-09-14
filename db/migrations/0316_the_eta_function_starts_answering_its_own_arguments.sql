-- migration-version: 20260914165752
-- migration-name:    0316_the_eta_function_starts_answering_its_own_arguments
--
-- 0316  WIRE THE COMPUTED ETA IN. THE DIAL BECOMES THE FALLBACK.
--
-- This is the behaviour change 0314 and 0315 were built for, and the first of
-- the three that is NOT free: it moves arrival times, which moves the booking
-- calendar, so forces_recert is TRUE.
--
-- ---------------------------------------------------------------------------
-- BEFORE
--
--   ottoq_return_eta_minutes(p_vehicle_id uuid, p_depot_id uuid, p_sim_run_id uuid)
--     SELECT GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id,'return_eta_minutes',30), 30));
--
-- It takes a vehicle and a depot and ignores both. All 123,665 dispatch rows
-- carrying return_eta_minutes hold the single value 30, and eta_source stamps
-- 'policy_constant:return_eta_minutes' on 44,046 of them while the evidence
-- blob carries 'eta_minutes_is_a_parameter', true. The engine has been
-- documenting its own guess.
--
-- AFTER: the function answers with its arguments -- distance over speed via
-- ottoq_computed_eta_minutes (0314, corrected by 0315) -- and falls back to the
-- policy constant only when the computation cannot be made honestly (no active
-- dispatch, no depot coordinates, fewer than two telemetry points). The dial
-- stops being the answer and becomes the fallback.
--
-- Measured before wiring, over the 100 currently deployed vehicles: 62 distinct
-- ETAs spanning 1.2 to 60.9 minutes, against the one value they all share today.
--
-- ---------------------------------------------------------------------------
-- THE CALL SITES, READ RATHER THAN ASSUMED -- and two of them matter
--
--   ottoq.ottoq_decide_return_on_signal     (p_vehicle_id, NULL, p_sim_run_id)
--   ottoq.ottoq_plan_dispatch_tick          (v_rc.vehicle_id, p_depot_id, p_sim_run_id)
--   public.ottoq_recall_fixed_window_dummy  (p_vehicle_id, v_depot, p_sim_run_id)
--   public.ottoq_recall_naive_threshold_v1  (p_vehicle_id, v_depot, p_sim_run_id)
--   twin.ottoq_sim_advance_deployed_telemetry (v_dispatch.vehicle_id, NULL, p_sim_run_id)
--
-- TWO OF THE FIVE PASS NULL FOR THE DEPOT, and ottoq_computed_eta_minutes needs
-- a depot to find the coordinates to measure distance from. Had this been
-- written from the signature rather than from the call sites, those two paths
-- would have silently fallen back to the constant forever and the wiring would
-- have looked like it worked. So the depot is resolved in this order:
--     the argument, then vehicles.home_depot_id, then ottoq_sim_runs.depot_id.
--
-- THE SIGNATURE IS UNCHANGED. Adding a clock parameter would be cleaner, but
-- CREATE OR REPLACE cannot add one -- it would create a second overload beside
-- the old function and make every existing 3-argument call ambiguous, and
-- dropping the old one is forbidden by scripts/APPLYING.md. So the sim clock is
-- resolved inside, from the run.
--
-- ---------------------------------------------------------------------------
-- DETERMINISM. The clock comes from ottoq_sim_runs.sim_clock_current for the
-- run being asked about, so each arm of a certification pair reads its OWN
-- clock -- never the wall clock, never another run's. Everything downstream is
-- already seeded: the bearing and the radius are drawn through
-- twin.ottoq_sim_seeded_random and ottoq_sample_calibrated keyed on the run
-- seed plus (vehicle, dispatch), and 0315's A3 asserted reproducibility.
--
-- forces_recert: TRUE, and unlike 0313 this one is argued from effect rather
-- than from reachability: arrival times move, so ottoq_stall_bookings moves,
-- so the bookings atom and the energy atom both move. Lineage row IN THIS FILE.
-- ===========================================================================

DO $pre$
DECLARE v_md5 text; v_defs int; v_deployed int; v_computable int;
BEGIN
  -- P1. THE FUNCTION IS WHAT THIS MIGRATION READ, and there is exactly one of it.
  SELECT count(*), md5(string_agg(p.prosrc,'')) INTO v_defs, v_md5
    FROM pg_proc p WHERE p.proname='ottoq_return_eta_minutes';
  IF v_defs <> 1 THEN
    RAISE EXCEPTION '0316 P1: expected exactly 1 ottoq_return_eta_minutes, found %', v_defs;
  END IF;
  IF v_md5 IS DISTINCT FROM '069496eb63896727d912c52674d78242' THEN
    RAISE EXCEPTION '0316 P1: prosrc md5 is %, expected 069496eb63896727d912c52674d78242', COALESCE(v_md5,'ABSENT');
  END IF;

  -- P2. THE MACHINERY IT WILL CALL IS PRESENT AND CORRECTED. 0315 must be in,
  --     not just 0314 -- wiring 0314's cancelling ETA would be worse than the
  --     constant, because it would LOOK like it read position.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='ottoq_computed_eta_minutes') THEN
    RAISE EXCEPTION '0316 P2: ottoq_computed_eta_minutes is absent; 0314 has not been applied';
  END IF;
  IF (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_trip_geometry') LIKE '%v_speed / 60.0%' THEN
    RAISE EXCEPTION '0316 P2: ottoq_trip_geometry still derives its radius from speed; 0315 has not been applied '
                    'and wiring 0314''s cancelling ETA would be worse than the constant it replaces';
  END IF;

  -- P3. THE COMPUTATION ACTUALLY RESOLVES FOR MOST DEPLOYED VEHICLES. If it
  --     mostly returned NULL the wiring would be a no-op wearing a changelog.
  SELECT count(*), count(public.ottoq_computed_eta_minutes(
                          d.vehicle_id, COALESCE(v.home_depot_id, r.depot_id), d.sim_run_id,
                          COALESCE(r.sim_clock_current, r.sim_clock_start)))
    INTO v_deployed, v_computable
    FROM public.ottoq_vehicle_dispatches d
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
    LEFT JOIN public.vehicles v ON v.id = d.vehicle_id
   WHERE d.status IN ('active','returning')
     AND COALESCE(r.sim_clock_current, r.sim_clock_start) IS NOT NULL;
  IF v_deployed > 0 AND v_computable * 2 < v_deployed THEN
    RAISE EXCEPTION '0316 P3: only % of % deployed vehicles yield a computed ETA; wiring would mostly fall back',
                    v_computable, v_deployed;
  END IF;
  RAISE NOTICE '0316: % of % deployed vehicles yield a computed ETA before wiring', v_computable, v_deployed;

  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE state='active' AND pid <> pg_backend_pid()
                AND (query ILIKE '%determinism_pair%' OR query ILIKE '%cert_arm%' OR query ILIKE '%ab_pair%')) THEN
    RAISE EXCEPTION '0316 P4: a certification pair is in flight; this migration moves the recert floor';
  END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.ottoq_return_eta_minutes(
  p_vehicle_id uuid, p_depot_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_clock timestamptz; v_eta numeric;
BEGIN
  -- No run means no world to measure in: the dial is all there is.
  IF p_sim_run_id IS NULL THEN
    RETURN GREATEST(1, COALESCE(ottoq_policy_get(NULL, 'return_eta_minutes', 30), 30));
  END IF;

  -- 0316: two of the five call sites pass NULL for the depot, so resolve it
  -- rather than assume the caller supplied one. Argument, then the vehicle's
  -- home depot, then the run's depot.
  SELECT COALESCE(p_depot_id, v.home_depot_id, r.depot_id),
         COALESCE(r.sim_clock_current, r.sim_clock_start)
    INTO v_depot, v_clock
    FROM public.ottoq_sim_runs r
    LEFT JOIN public.vehicles v ON v.id = p_vehicle_id
   WHERE r.sim_run_id = p_sim_run_id;

  IF v_depot IS NOT NULL AND v_clock IS NOT NULL THEN
    v_eta := public.ottoq_computed_eta_minutes(p_vehicle_id, v_depot, p_sim_run_id, v_clock);
  END IF;

  -- The dial is the FALLBACK now, not the answer. NULL means the computation
  -- refused (no open dispatch, no depot coordinates, too few telemetry points),
  -- and a refusal must not be mistaken for a measurement.
  RETURN GREATEST(1, COALESCE(v_eta, ottoq_policy_get(p_sim_run_id, 'return_eta_minutes', 30), 30));
END;
$function$;

COMMENT ON FUNCTION public.ottoq_return_eta_minutes(uuid,uuid,uuid) IS
'Minutes until this vehicle reaches its depot. Since 0316 this is COMPUTED -- distance over speed via '
'ottoq_computed_eta_minutes, recomputed on every call so it moves as the vehicle moves and as it crosses a '
'rush-hour boundary -- and the return_eta_minutes policy dial is only the FALLBACK for when the '
'computation honestly cannot be made. Before 0316 the body was a single line that took a vehicle id and a '
'depot id and ignored both, returning the dial for every vehicle in every run: all 123,665 dispatch rows '
'carrying return_eta_minutes hold the value 30. The depot is resolved as argument, then '
'vehicles.home_depot_id, then ottoq_sim_runs.depot_id, because 2 of the 5 call sites pass NULL for it. The '
'sim clock is read from the run, never from the wall clock, so each arm of a certification pair reads its '
'own. Signature deliberately unchanged: adding a clock parameter would create a second overload and make '
'every existing 3-argument call ambiguous.';

DO $post$
DECLARE
  v_md5 text; v_n int; v_d int; v_lo numeric; v_hi numeric; v_thirty int; v_src text;
BEGIN
  SELECT md5(p.prosrc), p.prosrc INTO v_md5, v_src
    FROM pg_proc p WHERE p.proname='ottoq_return_eta_minutes';

  -- A1. THE SWAP LANDED, the computation is called, and the dial survives as fallback.
  IF v_md5 = '069496eb63896727d912c52674d78242' THEN
    RAISE EXCEPTION '0316 A1: prosrc md5 unchanged; the replacement did not take';
  END IF;
  IF position('ottoq_computed_eta_minutes' in v_src) = 0 THEN
    RAISE EXCEPTION '0316 A1: the new body does not call the computation';
  END IF;
  IF position('return_eta_minutes' in v_src) = 0 THEN
    RAISE EXCEPTION '0316 A1: the dial vanished; it must remain as the fallback';
  END IF;
  IF (SELECT count(*) FROM pg_proc WHERE proname='ottoq_return_eta_minutes') <> 1 THEN
    RAISE EXCEPTION '0316 A1: an overload was created; existing 3-argument calls are now ambiguous';
  END IF;

  -- A2. THE FUNCTION NOW VARIES. This is the whole point: one distinct value
  --     across the fleet is the defect, and a wiring that produced one value
  --     would pass A1 and change nothing.
  SELECT count(*), count(DISTINCT e.eta), min(e.eta), max(e.eta),
         count(*) FILTER (WHERE e.eta = 30)
    INTO v_n, v_d, v_lo, v_hi, v_thirty
    FROM (SELECT public.ottoq_return_eta_minutes(d.vehicle_id, NULL, d.sim_run_id) AS eta
            FROM public.ottoq_vehicle_dispatches d
            JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
           WHERE d.status IN ('active','returning')
             AND COALESCE(r.sim_clock_current, r.sim_clock_start) IS NOT NULL) e;

  IF v_n = 0 THEN
    RAISE NOTICE '0316 A2: no deployed vehicles to exercise';
  ELSE
    IF v_d < 2 THEN
      RAISE EXCEPTION '0316 A2: ottoq_return_eta_minutes still returns a single value (%) across % vehicles; '
                      'the wiring changed nothing', v_lo, v_n;
    END IF;
    RAISE NOTICE '0316 A2 OK -- % deployed vehicles now yield % distinct ETAs, % to % min; % still fall back to 30',
                 v_n, v_d, v_lo, v_hi, v_thirty;
  END IF;

  -- A3. THE NULL-DEPOT PATH WORKS. Two call sites use it, and if the resolution
  --     chain were wrong they would silently fall back to 30 forever while the
  --     other three looked fine.
  IF v_n > 0 AND v_thirty = v_n THEN
    RAISE EXCEPTION '0316 A3: every NULL-depot call fell back to 30; the depot resolution chain is not working';
  END IF;

  RAISE NOTICE '0316 applied. RECERT REQUIRED: arrival times move, so bookings and energy move with them.';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0316_the_eta_function_starts_answering_its_own_arguments', true,
   'ottoq_return_eta_minutes now COMPUTES distance over speed via ottoq_computed_eta_minutes and keeps the '
   'return_eta_minutes dial only as the fallback for when the computation cannot honestly be made. Before '
   '0316 the body ignored both its vehicle and depot arguments and returned the dial: all 123,665 dispatch '
   'rows carrying return_eta_minutes hold the single value 30. The depot is resolved as argument, then '
   'vehicles.home_depot_id, then the run''s depot, because 2 of the 5 call sites '
   '(ottoq_decide_return_on_signal and ottoq_sim_advance_deployed_telemetry) pass NULL for it -- written '
   'from the signature instead of the call sites, those two paths would have fallen back forever while '
   'appearing to work. forces_recert=true argued from EFFECT, not reachability: arrival times move, so '
   'ottoq_stall_bookings moves, so the bookings and energy atoms both move. A2 requires more than one '
   'distinct ETA across deployed vehicles and A3 requires the NULL-depot path not to be uniformly falling '
   'back.',
   now())
ON CONFLICT (name) DO NOTHING;
