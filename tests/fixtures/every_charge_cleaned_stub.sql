-- tests/fixtures/every_charge_cleaned_stub.sql -- what 0765 adds to 0764's test world (0758's fixture with 0758 and 0764
-- applied). Two live bodies, pg_get_functiondef's output byte for byte, read from the live catalog on 2026-10-23
-- (prosrc md5: ottoq.ottoq_sim_prearrival_contracts d612cbeb, public.ottoq_itin_leg_open 69effd4b), and the columns
-- and stand-ins they reach. The stand-ins are noted where they are defined: the service-list generator writes the
-- ledger as ottoq.ottoq_derive_visit_needs does (it supersedes the car's open visits, inserts the visit in the run and
-- caches the list in the car's config) and records its call; the itinerary planner and the stall reservation record
-- their calls or do nothing.
SET client_min_messages = warning;
-- the live itinerary table: an id and a status by default, the depot, who made it and when (ottoq_itin_leg_open
-- inserts the first three and orders by the last)
ALTER TABLE public.ottoq_vehicle_itineraries ALTER COLUMN itinerary_id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN status SET DEFAULT 'active', ADD COLUMN IF NOT EXISTS depot_id uuid,
  ADD COLUMN IF NOT EXISTS created_by text DEFAULT 'decide_tick',
  ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now();
CREATE TABLE IF NOT EXISTS public.ottoq_vehicle_dispatches (dispatch_id uuid DEFAULT gen_random_uuid(), vehicle_id uuid,
  sim_run_id uuid, scheduled_return_at timestamp with time zone, actual_return_at timestamp with time zone);
-- what the stand-ins record, for the tests to read
CREATE TABLE IF NOT EXISTS public._test_manifests (vehicle_id uuid, sim_run_id uuid, seed bigint,
  at timestamp with time zone DEFAULT clock_timestamp());
CREATE TABLE IF NOT EXISTS public._test_plans (sim_run_id uuid, vehicle_id uuid, at timestamp with time zone);

-- STAND-IN: the twin's door to the need derivation. It writes what ottoq.ottoq_derive_visit_needs writes for the
-- ledger: every open visit of the car superseded (unscoped, as the live one), the new visit in the run (the running
-- run when none is given) arriving at the car's last state change, and the list cached in the car's config. The list
-- is the charge, and whatever the test puts in test.manifest_extra; the urgency is test.manifest_urgency (standard).
CREATE OR REPLACE FUNCTION twin.ottoq_sim_generate_service_manifest(p_vehicle_id uuid, p_sim_run_id uuid DEFAULT NULL,
  p_seed bigint DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_m jsonb; v_run uuid; v_depot uuid; v_clock timestamptz;
BEGIN
  INSERT INTO public._test_manifests (vehicle_id, sim_run_id, seed) VALUES (p_vehicle_id, p_sim_run_id, p_seed);
  SELECT home_depot_id, COALESCE(last_state_change, now()) INTO v_depot, v_clock FROM public.vehicles WHERE id = p_vehicle_id;
  v_run := COALESCE(p_sim_run_id, (SELECT r.sim_run_id FROM public.ottoq_sim_runs r
                                    WHERE r.status = 'running' AND r.depot_id = v_depot ORDER BY r.started_at DESC LIMIT 1));
  v_m := jsonb_build_array(jsonb_build_object('svc', 'charge', 'must_do', true, 'deferrable', false, 'est_min', 20,
                                              'target_soc', 100, 'concurrency', 'anchor'))
         || COALESCE(NULLIF(current_setting('test.manifest_extra', true), '')::jsonb, '[]'::jsonb);
  UPDATE public.ottoq_visit_needs SET status = 'superseded' WHERE vehicle_id = p_vehicle_id AND status IN ('open', 'in_progress');
  INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, status, atoms,
                                        meta, created_at)
  VALUES (p_vehicle_id, v_run, v_depot, v_clock, p_vehicle_id::text || ':' || to_char(v_clock, 'YYYYMMDDHH24MISS'),
          COALESCE(NULLIF(current_setting('test.manifest_urgency', true), ''), 'standard'), 'open', v_m, '{}'::jsonb, now());
  UPDATE public.vehicles SET config = jsonb_set(COALESCE(config, '{}'::jsonb), '{service_manifest}', v_m)
   WHERE id = p_vehicle_id;
  RETURN v_m;
END $$;
-- STAND-INS: the itinerary planner (recorded) and the stall reservation (nothing), as the backstops call them
CREATE OR REPLACE FUNCTION public.ottoq_plan_visit_itinerary(p_sim_run_id uuid, p_vehicle_id uuid,
  p_at timestamp with time zone) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public._test_plans VALUES (p_sim_run_id, p_vehicle_id, p_at) RETURNING NULL::uuid
$$;
CREATE OR REPLACE FUNCTION public.ottoq_reserve_stall(p_stall uuid, p_vehicle uuid, p_clock timestamp with time zone,
  p_ttl integer) RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;

-- ══ the live bodies ══
CREATE OR REPLACE FUNCTION ottoq.ottoq_sim_prearrival_contracts(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_rec RECORD; v_eta timestamptz; v_stall uuid; v_n int := 0;
  v_has_charge boolean; v_ttl int; v_eta_min numeric;
  --: 0339. 0 = pre-reserve the charge stall from en_route (the original
  --: behaviour); 1 = reserve staging only and let the gate decide.
  v_yield_to_solver int := 0;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  --: 0339. Read once per call, at RUN scope, so a single beat cannot see
  --: the dial change halfway through its own loop.
  v_yield_to_solver := COALESCE(public.ottoq_policy_get(
    p_sim_run_id, 'prearrival_charge_yields_to_solver', 0), 0)::int;

  -- BACKSTOP 1: en_route car with no workflow (AP-4 books at need-fire; this catches cars that
  -- reached en_route by another path). Provenance stays 'twin_generator' (honest derivation).
  FOR v_rec IN
    SELECT v.id AS vehicle_id
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'en_route_to_depot'
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                        WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */)
     ORDER BY v.id   /* 0054: run-stable order before LIMIT */
     LIMIT 40
  LOOP
    PERFORM ottoq_sim_generate_service_manifest(v_rec.vehicle_id, p_sim_run_id, NULL);
    SELECT COALESCE(MAX(d.scheduled_return_at), p_clock) INTO v_eta
      FROM ottoq_vehicle_dispatches d
     WHERE d.vehicle_id = v_rec.vehicle_id AND d.actual_return_at IS NULL AND COALESCE(d.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0193 */;
    PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.vehicle_id, GREATEST(p_clock, v_eta));
    v_n := v_n + 1;
  END LOOP;

  -- BACKSTOP 2: en_route car with no live reservation gets one (widened to the whole approach,
  -- ETA-derived TTL so the hold survives transit + gate queue).
  FOR v_rec IN
    SELECT v.id AS vehicle_id, vn.atoms, vn.urgency, v.current_soc,
           (SELECT MIN(d.scheduled_return_at) FROM ottoq_vehicle_dispatches d
             WHERE d.vehicle_id = v.id AND d.actual_return_at IS NULL AND COALESCE(d.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0193 */) AS eta_at
      FROM vehicles v
      JOIN ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'en_route_to_depot'
       AND NOT EXISTS (SELECT 1 FROM stalls s WHERE s.reserved_by = v.id
                         AND s.reservation_expires_at > p_clock)
     ORDER BY v.id   /* 0054: run-stable order before LIMIT */
     LIMIT 40
  LOOP
    v_eta_min := GREATEST(EXTRACT(EPOCH FROM (COALESCE(v_rec.eta_at, p_clock + interval '15 min') - p_clock))/60.0, 10);
    v_ttl := (v_eta_min + 40)::int * 60;
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(v_rec.atoms) a
                    WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
      INTO v_has_charge;
    v_stall := NULL;
    --: 0339. THE GATE. When the run yields, v_stall stays NULL here and
    --: the staging fallback below takes over -- the vehicle still gets a
    --: place to wait, and the charge assignment reaches the proposer,
    --: the shield and the disposer instead of being settled by this
    --: ORDER BY forty minutes before the vehicle arrives.
    IF v_has_charge AND v_yield_to_solver = 0 THEN
      SELECT s.id INTO v_stall FROM stalls s
        JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
       WHERE s.depot_id = v_depot AND s.stall_type IN ('dcfc','l2')
         AND s.current_vehicle_id IS NULL
         AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_clock)
         AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '35 minutes'
       ORDER BY (s.stall_type::text = (CASE WHEN v_rec.urgency = 'immediate_dispatch' OR v_rec.current_soc < 45
                                      THEN 'dcfc' ELSE 'l2' END)) DESC,
                s.relative_y ASC NULLS LAST, s.id
       LIMIT 1;
    END IF;
    IF v_stall IS NULL THEN
      -- THE PERIMETER IS A LONG HOLD, NOT A FRONT DOOR.
      -- This ordering used to be ASC, which sorts false first and therefore
      -- handed every inbound car a perimeter stall before it had even arrived.
      -- Because this reservation is taken while the car is still en_route and
      -- refreshed to +40 min, it beat decide_tick's correct temp-first picker
      -- every time: the car drove straight to the ring. That is the "vehicles
      -- enter and immediately park" symptom.
      --
      -- Now the preference INVERTS on the kind of hold. An overnight_hold car
      -- genuinely wants the perimeter -- that is what the perimeter is for.
      -- Everything else takes a short-term spot and only spills onto the ring
      -- when the temp pool is full, which is the documented overflow case.
      -- Both COALESCEs matter: a NULL urgency must read as "not a long hold"
      -- rather than poisoning the comparison to NULL and randomising the sort.
      --
      -- The zone exclusion mirrors ottoq_decide_tick (3b). A pre-arrival
      -- reservation on a stall the arrival picker would never choose is a stall
      -- held out of service for nothing.
      SELECT s.id INTO v_stall FROM stalls s
       WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
         AND s.zone IS DISTINCT FROM 'arrival_inspection'
         AND s.current_vehicle_id IS NULL
         AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_clock)
       ORDER BY ((COALESCE(s.staging_role,'') = 'temp')
                 <> COALESCE(v_rec.urgency = 'overnight_hold', false)) DESC,
                s.distance_from_entrance NULLS LAST, s.id
       LIMIT 1;
    END IF;
    IF v_stall IS NOT NULL THEN
      PERFORM ottoq_reserve_stall(v_stall, v_rec.vehicle_id, p_clock, v_ttl);
      v_n := v_n + 1;
    END IF;
  END LOOP;

  -- M1 REFRESH: keep a booked car's own reservation alive while it approaches / queues at the
  -- gate, so an ETA slip cannot drop the hold before the arrival assignment claims it.
  UPDATE stalls s
     SET reservation_expires_at = p_clock + interval '40 minutes'
    FROM vehicles v
   WHERE s.reserved_by = v.id
     AND v.home_depot_id = v_depot AND v.category = 'autonomous'
     AND v.current_state IN ('arrived_at_gate','en_route_to_depot')
     AND s.reservation_expires_at > p_clock
     AND s.reservation_expires_at <= p_clock + interval '20 minutes'
     AND s.current_vehicle_id IS NULL;

  RETURN v_n;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.ottoq_itin_leg_open(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_now timestamp with time zone, p_leg_type text, p_to_stall uuid, p_planned_end timestamp with time zone, p_basis jsonb, p_created_by text DEFAULT 'decide_tick'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_itin uuid; v_seq int; v_leg uuid;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN NULL; END IF;
  SELECT itinerary_id INTO v_itin FROM ottoq_vehicle_itineraries
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle_id AND status = 'active'
   ORDER BY sim_created_at DESC, created_at DESC, itinerary_id DESC /* 0129 */ LIMIT 1;
  IF v_itin IS NULL THEN
    INSERT INTO ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at)
    VALUES (p_sim_run_id, p_depot_id, p_vehicle_id, p_created_by, p_now)
    RETURNING itinerary_id INTO v_itin;
  END IF;
  -- N2/M4: reality CLAIMS the matching planned leg (plan-vs-actual per leg);
  -- unplanned events still insert fresh legs below.
  SELECT leg_id INTO v_leg FROM ottoq_itinerary_legs
   WHERE itinerary_id = v_itin AND leg_type = p_leg_type AND status = 'planned'
   ORDER BY seq, planned_start_sim, planned_end_sim, leg_id /* 0129 */ LIMIT 1;
  IF v_leg IS NOT NULL THEN
    UPDATE ottoq_itinerary_legs
       SET actual_start_sim = p_now, status = 'active', to_stall_id = COALESCE(p_to_stall, to_stall_id),
           duration_basis = duration_basis || COALESCE(p_basis, '{}'::jsonb)
     WHERE leg_id = v_leg;
  ELSE
    SELECT COALESCE(MAX(seq), 0) + 1 INTO v_seq FROM ottoq_itinerary_legs WHERE itinerary_id = v_itin;
    INSERT INTO ottoq_itinerary_legs (
      itinerary_id, sim_run_id, vehicle_id, seq, leg_type, to_stall_id,
      planned_start_sim, planned_end_sim, planned_duration_s, duration_basis,
      actual_start_sim, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle_id, v_seq, p_leg_type, p_to_stall,
      p_now, p_planned_end,
      CASE WHEN p_planned_end IS NULL THEN NULL
           ELSE GREATEST(0, EXTRACT(EPOCH FROM (p_planned_end - p_now)))::int END,
      COALESCE(p_basis, '{}'::jsonb), p_now, 'active')
    RETURNING leg_id INTO v_leg;
  END IF;

  -- LATE BIND (2026-08-02). The calendar row already standing in this stall learns its leg
  -- the moment the leg becomes real. We bind at most ONE live row -- the one whose window
  -- sits closest to now -- and only if no other live row already carries this leg.
  -- 'none' is the resolver's "I looked and found nothing", i.e. UNSET for provenance
  -- purposes -- it must be overwritten here, not preserved.
  -- Fully sub-blocked: this function runs with the CALLER's privileges, so a permission or
  -- constraint problem here must never abort the twin's transaction.
  BEGIN
    IF v_leg IS NOT NULL AND p_to_stall IS NOT NULL THEN
      UPDATE public.ottoq_stall_bookings b
         SET leg_id     = v_leg,
             leg_source = CASE WHEN COALESCE(b.leg_source,'none') = 'none'
                               THEN 'late_bind_leg_open' ELSE b.leg_source END,
             why        = COALESCE(b.why, '') ||
                          format(' | leg %s (%s) opened here at %s',
                                 left(v_leg::text,8), p_leg_type, to_char(p_now,'HH24:MI'))
       WHERE b.booking_id = (
               SELECT bb.booking_id FROM public.ottoq_stall_bookings bb
                WHERE bb.sim_run_id = p_sim_run_id
                  AND bb.stall_id   = p_to_stall
                  AND bb.vehicle_id = p_vehicle_id
                  AND bb.leg_id IS NULL
                  AND bb.state IN ('held','active')
                  AND bb.during && tstzrange(p_now - interval '90 minutes',
                                             p_now + interval '90 minutes', '[)')
                ORDER BY abs(EXTRACT(EPOCH FROM (lower(bb.during) - p_now))), lower(bb.during), bb.stall_id, bb.booking_id DESC /* 0129 */ LIMIT 1)
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bz
                          WHERE bz.leg_id = v_leg AND bz.state IN ('held','active'));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_leg;
END; $function$
;
