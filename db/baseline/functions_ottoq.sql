-- GENERATED / SNAPSHOT FILE — DO NOT EDIT. Changes go in db/migrations/.
-- ---------------------------------------------------------------------------
-- Snapshot of the live otto-q-core brain (Supabase gxdrcyphqjzjsuhxuqtg).
-- Nothing reads this file at runtime. Editing it changes NOTHING about the
-- running system. To change the brain: add a numbered file in db/migrations/,
-- apply it per scripts/APPLYING.md, then re-export this baseline.
-- Baseline date: 2026-08-04 (export captured 2026-08-03; verified live 2026-08-04).
-- ---------------------------------------------------------------------------

-- ============================================================================
-- OTTO-Q-CORE  |  Supabase project gxdrcyphqjzjsuhxuqtg
-- USER-DEFINED FUNCTIONS / PROCEDURES  (schema: ottoq)
-- ----------------------------------------------------------------------------
-- Exported verbatim via pg_get_functiondef(oid). Read-only snapshot.
-- Count: 48 user-defined routines (extension-owned routines are EXCLUDED
--        via pg_depend deptype='e').
-- Order: proname, oid.  Each routine is preceded by "-- ===== <name> =====".
--
-- NOTE: the `ottoq` schema was NOT part of the 2026-07-13 snapshot. This is the
--       FIRST capture of this schema. Its diff will therefore show as all-new.
--       `db/functions.sql` remains public-schema only so its diff against the
--       2026-07-13 export stays clean and comparable.
-- ============================================================================

-- ===== ottoq_activate_due_bay_reservations =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_activate_due_bay_reservations(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_res record; v_n int := 0; v_prev uuid; v_state text; v_verb text;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  FOR v_res IN
    SELECT b.booking_id, b.vehicle_id, b.stall_id, b.purpose, b.leg_id,
           s.stall_type::text AS stall_type
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state      = 'held'
       AND s.depot_id   = p_depot_id
       AND s.stall_type IN ('wash_bay'::stall_type,'detail_bay'::stall_type,'service_bay'::stall_type)
       AND s.status NOT IN ('maintenance','closed')
       -- the appointment has STARTED but not yet lapsed
       AND lower(b.during) <= p_clock
       AND upper(b.during) >  p_clock
       -- the bay is physically free for this car
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = b.vehicle_id)
       -- the car is HOME and IDLE. Never interrupt live work; never touch a fault state.
       AND v.home_depot_id = p_depot_id
       AND v.current_state IN ('arrived_at_gate'::vehicle_state,
                               'staged_awaiting_service'::vehicle_state,
                               'charge_complete_holding'::vehicle_state,
                               'service_complete_holding'::vehicle_state)
     ORDER BY lower(b.during), b.booking_id
  LOOP
    -- CAS the stall. If someone else took it first, leave the reservation alone and
    -- let the existing grace/replan path deal with it -- we never force.
    CONTINUE WHEN NOT public.ottoq_reserve_stall(v_res.stall_id, v_res.vehicle_id, p_clock, 900);

    v_state := CASE
                 WHEN v_res.stall_type = 'service_bay' THEN 'in_service_bay'
                 WHEN v_res.purpose    = 'detail'      THEN 'in_detail_bay'
                 WHEN v_res.stall_type = 'detail_bay'  THEN 'in_detail_bay'
                 ELSE 'in_wash_bay' END;
    v_verb  := CASE WHEN v_state = 'in_service_bay' THEN 'enter_service' ELSE 'enter_wash' END;

    -- Close out whatever space the car is vacating (same contract as enact_space_assignment).
    SELECT vv.current_stall_id INTO v_prev FROM public.vehicles vv WHERE vv.id = v_res.vehicle_id;
    IF v_prev IS NOT NULL AND v_prev <> v_res.stall_id THEN
      UPDATE public.ottoq_stall_bookings
         SET state = 'done', released_at = p_clock,
             release_reason = 'vehicle_moved_to_next_leg',
             during = tstzrange(lower(during),
                        GREATEST(lower(during) + interval '1 second',
                                 LEAST(upper(during), p_clock)), '[)')
       WHERE sim_run_id = p_sim_run_id AND stall_id = v_prev
         AND vehicle_id = v_res.vehicle_id AND state IN ('held','active');
    END IF;

    -- OCCUPY.
    UPDATE public.vehicles
       SET current_stall_id = v_res.stall_id,
           current_state    = v_state::vehicle_state,
           last_state_change = p_clock
     WHERE id = v_res.vehicle_id;
    UPDATE public.stalls
       SET current_vehicle_id = v_res.vehicle_id, status = 'occupied'
     WHERE id = v_res.stall_id;

    -- The reservation is now a REAL occupancy, and is stamped so provenance can see
    -- that it was activated rather than booked fresh.
    UPDATE public.ottoq_stall_bookings
       SET state = 'active', booked_by = 'otto_q_enacted', source = 'bay_reservation_activated'
     WHERE booking_id = v_res.booking_id;

    IF v_res.leg_id IS NOT NULL THEN
      UPDATE public.ottoq_itinerary_legs
         SET to_stall_id = v_res.stall_id, status = 'active',
             actual_start_sim = COALESCE(actual_start_sim, p_clock)
       WHERE leg_id = v_res.leg_id AND status = 'planned';
    END IF;

    BEGIN
      PERFORM public.ottoq_emit_vehicle_command(
        p_sim_run_id, p_depot_id, v_res.vehicle_id, v_verb,
        jsonb_build_object('stall_id',   v_res.stall_id,
                           'booking_id', v_res.booking_id,
                           'leg_id',     v_res.leg_id,
                           'purpose',    v_res.purpose,
                           'via',        'bay_reservation_activated'), p_clock);
    EXCEPTION WHEN OTHERS THEN NULL;  -- an un-emitted command must never cost the move
    END;

    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_activate_due_bay_reservations: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$

-- ===== ottoq_activate_present_bookings =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_activate_present_bookings(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  -- The window must have STARTED (an early arrival stays 'held' until its slot opens),
  -- but a window that has already ELAPSED still activates when the vehicle is standing
  -- on the stall: the occupancy was real and must be recorded as 'done', not 'no_show'.
  -- `during` is deliberately not rewritten here -- widening a range can collide with a
  -- neighbouring booking and would raise inside the caller's transaction.
  UPDATE public.ottoq_stall_bookings b
     SET state = 'active'
   WHERE b.sim_run_id = p_sim_run_id
     AND b.state = 'held'
     AND lower(b.during) <= p_clock
     AND EXISTS (SELECT 1 FROM public.vehicles v
                  WHERE v.id = b.vehicle_id AND v.current_stall_id = b.stall_id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_activate_present_bookings: FAILED sqlstate=% msg=% run=%',
    SQLSTATE, SQLERRM, p_sim_run_id;
  RETURN 0;
END
$function$

-- ===== ottoq_admit_stranded_vehicles =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_admit_stranded_vehicles(p_depot_id uuid, p_sim_run_id uuid, p_clock timestamp with time zone, p_floor numeric DEFAULT 80, p_limit integer DEFAULT 12)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_free int; v_waiting int; v_slots int; v_admitted int;
BEGIN
  -- usable charging capacity right now
  SELECT count(*) INTO v_free
    FROM stalls s
    JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = p_depot_id
     AND s.stall_type::text IN ('dcfc','l2')
     AND s.current_vehicle_id IS NULL
     AND c.station_state = 'Available'
     AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_clock);

  -- cars already queued for one
  SELECT count(*) INTO v_waiting
    FROM vehicles
   WHERE home_depot_id = p_depot_id AND category = 'autonomous'
     AND current_state IN ('arrived_at_gate','staged_awaiting_service');

  v_slots := GREATEST(0, LEAST(p_limit, COALESCE(v_free,0) - COALESCE(v_waiting,0)));
  IF v_slots = 0 THEN RETURN 0; END IF;

  WITH cand AS (
    SELECT v.id
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.category = 'autonomous'
       AND v.current_state = 'offline'
       AND v.current_stall_id IS NULL
       AND v.current_soc < p_floor
       AND (v.owning_sim_run_id IS NULL OR v.owning_sim_run_id = p_sim_run_id)
     ORDER BY v.current_soc ASC, v.id          -- most depleted first
     LIMIT v_slots
  ), upd AS (
    UPDATE vehicles v
       SET current_state = 'arrived_at_gate'::vehicle_state,
           last_state_change = p_clock,
           owning_sim_run_id = COALESCE(v.owning_sim_run_id, p_sim_run_id),
           config = COALESCE(v.config,'{}'::jsonb) || jsonb_build_object('svc_step','need_charge')
      FROM cand c WHERE v.id = c.id
    RETURNING v.id
  )
  SELECT count(*) INTO v_admitted FROM upd;
  RETURN COALESCE(v_admitted, 0);
END;
$function$

-- ===== ottoq_arrival_disposition =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_arrival_disposition(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_clock timestamp with time zone, p_long_hold_threshold_min integer DEFAULT 90, p_dcfc_wait_tolerance_min integer DEFAULT 15, p_tech_hold_min integer DEFAULT 120)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_need RECORD; v_quarantine boolean := false; v_flagged boolean := false;
  v_needs_charge boolean := false; v_free_dcfc uuid; v_free_l2 uuid;
  v_next_dcfc timestamptz; v_wait_min numeric;
BEGIN
  SELECT vn.visit_id, vn.urgency, vn.dispatch_due_at, vn.atoms INTO v_need
    FROM public.ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
   ORDER BY vn.created_at DESC LIMIT 1;

  SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_need.atoms,'[]'::jsonb)) a
     WHERE COALESCE(a->>'status','pending') IN ('pending','in_progress')
       AND (a->>'svc') IN ('quarantine','immobilize','tow','safety_hold')) INTO v_quarantine;
  IF v_quarantine THEN
    RETURN jsonb_build_object('action','quarantine','reason','major_issue_flagged',
      'stage_from', p_clock, 'stage_until', p_clock + make_interval(mins => p_tech_hold_min*2),
      'needs_tech_clearance', true, 'visit_id', v_need.visit_id);
  END IF;

  SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_need.atoms,'[]'::jsonb)) a
     WHERE COALESCE(a->>'status','pending') IN ('pending','in_progress')
       AND (COALESCE((a->>'requires_tech_greenlight')::boolean,false)
            OR (a->>'svc') = 'item_retrieval')) INTO v_flagged;
  IF v_flagged THEN
    RETURN jsonb_build_object('action','temp_stage_tech_hold','reason','flagged_awaiting_tech_confirmation',
      'stage_from', p_clock, 'stage_until', p_clock + make_interval(mins => p_tech_hold_min),
      'needs_tech_clearance', true, 'visit_id', v_need.visit_id);
  END IF;

  IF v_need.urgency = 'overnight_hold' AND v_need.dispatch_due_at IS NOT NULL
     AND v_need.dispatch_due_at > p_clock THEN
    RETURN jsonb_build_object('action','perimeter_hold','reason','overnight_or_long_hold',
      'stage_from', p_clock, 'stage_until', v_need.dispatch_due_at,
      'hold_minutes', ROUND(EXTRACT(EPOCH FROM (v_need.dispatch_due_at - p_clock))/60.0,1),
      'visit_id', v_need.visit_id);
  END IF;

  SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_need.atoms,'[]'::jsonb)) a
     WHERE COALESCE(a->>'status','pending') IN ('pending','in_progress') AND (a->>'svc')='charge')
    INTO v_needs_charge;

  IF v_need.visit_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(v_need.atoms,'[]'::jsonb)) a
     WHERE COALESCE(a->>'status','pending') IN ('pending','in_progress')) THEN
    RETURN jsonb_build_object('action','redeploy','reason','no_outstanding_needs','visit_id', v_need.visit_id);
  END IF;

  IF v_needs_charge THEN
    SELECT f.stall_id INTO v_free_dcfc FROM ottoq.ottoq_stall_free_between(
      p_sim_run_id, p_depot_id, p_clock, p_clock + interval '1 minute', 'dcfc', NULL, 200) f
     WHERE NOT EXISTS (SELECT 1 FROM public.stalls s2 WHERE s2.id=f.stall_id
       AND (s2.current_vehicle_id IS NOT NULL
            OR (s2.reserved_by IS NOT NULL AND COALESCE(s2.reservation_expires_at,p_clock) > p_clock)))
     LIMIT 1;
    IF v_free_dcfc IS NOT NULL THEN
      RETURN jsonb_build_object('action','proceed_to_charge','reason','dcfc_available_now',
        'stall_id', v_free_dcfc, 'stall_type','dcfc','concurrent_interior', true,'visit_id', v_need.visit_id);
    END IF;

    SELECT MIN(upper(b.during)) INTO v_next_dcfc
      FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id=b.stall_id
     WHERE b.sim_run_id=p_sim_run_id AND s.depot_id=p_depot_id AND s.stall_type::text='dcfc'
       AND b.state IN ('held','active') AND upper(b.during) > p_clock;
    v_wait_min := CASE WHEN v_next_dcfc IS NULL THEN NULL
                       ELSE ROUND(EXTRACT(EPOCH FROM (v_next_dcfc - p_clock))/60.0,1) END;

    IF v_wait_min IS NOT NULL AND v_wait_min <= p_dcfc_wait_tolerance_min THEN
      RETURN jsonb_build_object('action','temp_stage_await_resource','reason','dcfc_frees_shortly_worth_waiting',
        'stage_from', p_clock,'stage_until', v_next_dcfc,'await_stall_type','dcfc',
        'await_until', v_next_dcfc,'wait_minutes', v_wait_min,'visit_id', v_need.visit_id);
    END IF;

    SELECT f.stall_id INTO v_free_l2 FROM ottoq.ottoq_stall_free_between(
      p_sim_run_id, p_depot_id, p_clock, p_clock + interval '1 minute', 'l2', NULL, 200) f
     WHERE NOT EXISTS (SELECT 1 FROM public.stalls s2 WHERE s2.id=f.stall_id
       AND (s2.current_vehicle_id IS NOT NULL
            OR (s2.reserved_by IS NOT NULL AND COALESCE(s2.reservation_expires_at,p_clock) > p_clock)))
     LIMIT 1;
    IF v_free_l2 IS NOT NULL THEN
      RETURN jsonb_build_object('action','proceed_to_charge','reason','l2_available_now',
        'stall_id', v_free_l2,'stall_type','l2','concurrent_interior', true,'visit_id', v_need.visit_id);
    END IF;

    IF v_wait_min IS NOT NULL AND v_wait_min >= p_long_hold_threshold_min THEN
      RETURN jsonb_build_object('action','perimeter_hold','reason','charger_wait_is_a_long_hold',
        'stage_from', p_clock,'stage_until', v_next_dcfc,'hold_minutes', v_wait_min,'visit_id', v_need.visit_id);
    END IF;

    RETURN jsonb_build_object('action','temp_stage_await_resource','reason','all_chargers_busy',
      'stage_from', p_clock,
      'stage_until', COALESCE(v_next_dcfc, p_clock + make_interval(mins => p_dcfc_wait_tolerance_min)),
      'await_stall_type','any_charger','await_until', v_next_dcfc,'wait_minutes', v_wait_min,
      'visit_id', v_need.visit_id);
  END IF;

  RETURN jsonb_build_object('action','temp_stage_await_resource','reason','service_only_awaiting_bay',
    'stage_from', p_clock,'stage_until', p_clock + make_interval(mins => p_dcfc_wait_tolerance_min),
    'await_stall_type','bay','visit_id', v_need.visit_id);
END
$function$

-- ===== ottoq_bay_purpose_atoms =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_bay_purpose_atoms(p_purpose text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  -- MUST MIRROR twin.ottoq_sim_advance_service_flow STEP 1, which is what marks these atoms
  -- done on bay exit. TOTAL: an unknown purpose returns '{}' and re-plans nothing, it never
  -- raises. (Twin vocabulary is OPEN; OTTO-Q's is CLOSED.)
  SELECT CASE COALESCE(p_purpose,'')
    WHEN 'wash'    THEN ARRAY['exterior_wash','sensor_clean']
    WHEN 'detail'  THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
    WHEN 'service' THEN ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair']
    WHEN 'inspect' THEN ARRAY['interior_inspection']
    ELSE '{}'::text[]
  END;
$function$

-- ===== ottoq_bay_purpose_leg_types =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_bay_purpose_leg_types(p_purpose text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT CASE COALESCE(p_purpose,'')
    WHEN 'wash'    THEN ARRAY['wash','exterior_wash','sensor_clean']
    WHEN 'detail'  THEN ARRAY['detail','interior_deep_clean','interior_tidy']
    WHEN 'service' THEN ARRAY['service','mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair']
    WHEN 'inspect' THEN ARRAY['inspect','interior_inspection']
    ELSE '{}'::text[]
  END;
$function$

-- ===== ottoq_bind_unbooked_bay_occupants =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_bind_unbooked_bay_occupants(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD; v_type text; v_purpose text; v_leg uuid; v_until timestamptz;
  v_bkg uuid; v_space jsonb; v_stall uuid; v_how text; v_dec uuid;
  v_bound int := 0; v_inplace int := 0; v_refused int := 0; v_tick bigint;
  v_displaced int := 0; v_disp_rows jsonb := '[]'::jsonb;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN
    RETURN jsonb_build_object('bound',0,'in_place',0,'refused',0,'displaced',0);
  END IF;

  SELECT COALESCE(tick_count,0) INTO v_tick FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;

  FOR v_rec IN
    SELECT v.id, v.current_state::text AS st, v.current_stall_id, v.config, v.fleet_operator_id
      FROM public.vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.current_state IN ('in_wash_bay'::vehicle_state,
                               'in_detail_bay'::vehicle_state,
                               'in_service_bay'::vehicle_state)
       AND NOT EXISTS (
             SELECT 1 FROM public.ottoq_stall_bookings b
              JOIN public.stalls s ON s.id = b.stall_id
              WHERE b.sim_run_id = p_sim_run_id
                AND b.vehicle_id = v.id
                AND b.state IN ('held','active')
                AND s.stall_type IN ('wash_bay'::stall_type,'service_bay'::stall_type))
     ORDER BY v.last_state_change NULLS FIRST, v.id
     LIMIT 40
  LOOP
    v_type    := CASE WHEN v_rec.st = 'in_service_bay' THEN 'service_bay' ELSE 'wash_bay' END;
    v_purpose := CASE v_rec.st WHEN 'in_service_bay' THEN 'service'
                               WHEN 'in_detail_bay'  THEN 'detail'
                               ELSE 'wash' END;
    v_leg := NULL; v_until := NULL; v_bkg := NULL; v_space := NULL; v_stall := NULL; v_dec := NULL;

    -- WHY is this vehicle in this space: the leg it is working. Open leg first, then the
    -- planned one. TOTAL: an unmatched vehicle just books with leg_id NULL, never raises.
    SELECT l.leg_id, COALESCE(l.planned_end_sim, l.actual_end_sim)
      INTO v_leg, v_until
      FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_rec.id
       AND l.status IN ('active','planned')
       AND l.leg_type = (CASE WHEN v_rec.st = 'in_service_bay' THEN 'service'
                              WHEN v_rec.st = 'in_detail_bay'  THEN 'detail'
                              ELSE 'wash' END)
     ORDER BY (l.status = 'active') DESC, l.seq
     LIMIT 1;

    -- Duration: the TWIN owns timing. config.service_ends_at is what the twin itself set
    -- when it admitted the vehicle, so the booking window is the world's own window.
    v_until := GREATEST(
                 COALESCE((v_rec.config->>'service_ends_at')::timestamptz, v_until,
                          p_clock + make_interval(mins => CASE WHEN v_type = 'service_bay'
                            THEN public.ottoq_policy_get(p_sim_run_id,'service_bay_default_min',45)::int
                            ELSE public.ottoq_policy_get(p_sim_run_id,'wash_bay_default_min',25)::int END)),
                 p_clock + interval '1 minute');

    IF v_rec.current_stall_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.stalls s
                    WHERE s.id = v_rec.current_stall_id AND s.depot_id = p_depot_id
                      AND s.stall_type::text = v_type) THEN
      -- ALREADY PHYSICALLY IN A REAL BAY -> book it IN PLACE. Never move a car mid-service.
      v_stall := v_rec.current_stall_id;
      v_how   := 'in_place';
      v_bkg   := ottoq.ottoq_record_enacted_booking(
                   p_sim_run_id, v_stall, v_rec.id, p_clock,
                   v_leg, p_clock, v_until, v_purpose, 'bay_reconcile_in_place');
      IF v_bkg IS NOT NULL THEN v_inplace := v_inplace + 1; ELSE v_refused := v_refused + 1; END IF;
    ELSE
      -- ADMITTED BY THE TWIN WITH NO STALL AT ALL -> give it a real one, atomically.
      v_how   := 'twin_admit';
      v_space := ottoq.ottoq_enact_space_assignment(
                   p_sim_run_id, p_depot_id, v_rec.id, v_type, v_purpose,
                   p_clock, v_until, v_leg, 'bay_reconcile_twin_admit');
      IF COALESCE((v_space->>'assigned')::boolean,false) THEN
        v_bound := v_bound + 1;
        v_stall := NULLIF(v_space->>'stall_id','')::uuid;
        v_bkg   := NULLIF(v_space->>'booking_id','')::uuid;
      ELSE
        -- ══════════════ REALITY MUST OUTRANK A PLAN ══════════════
        -- The ordinary picker just told us every bay of this type is spoken for.
        -- But this car is PHYSICALLY IN A BAY RIGHT NOW. If the stalls are held
        -- only by claims for cars that are NOT standing in them, those claims are
        -- fiction and the fiction yields. Previously this branch gave up with
        -- reason=no_free_space ~34 times per run and the car went unrecorded --
        -- the guard's "success" was partly that reality went unrecorded.
        -- The displacement helper refuses to touch any stall a car is actually in,
        -- so this can never re-route an in-depot vehicle.
        v_space := ottoq.ottoq_reconcile_displace_stale_claim(
                     p_sim_run_id, p_depot_id, v_rec.id, v_type, v_purpose,
                     p_clock, v_until, v_leg, 'bay_reconcile_displace', v_tick);

        IF COALESCE((v_space->>'assigned')::boolean,false) THEN
          v_how       := 'displace';
          v_bound     := v_bound + 1;
          v_displaced := v_displaced + COALESCE((v_space->>'displaced')::int, 0);
          v_disp_rows := v_disp_rows || COALESCE(v_space->'displaced_claims','[]'::jsonb);
          v_stall     := NULLIF(v_space->>'stall_id','')::uuid;
          v_bkg       := NULLIF(v_space->>'booking_id','')::uuid;
        ELSE
          v_refused := v_refused + 1;
          -- LOUD, NEVER SILENT: a vehicle is physically in a bay the depot cannot back with
          -- a real stall EVEN AFTER displacing every stale claim. That is genuine
          -- over-admission by the twin's staff-capacity rule, now provably so.
          RAISE WARNING 'ottoq_bind_unbooked_bay_occupants: UNBACKED BAY OCCUPANT run=% vehicle=% state=% type=% reason=%',
            p_sim_run_id, v_rec.id, v_rec.st, v_type, COALESCE(v_space->>'reason','unknown');
        END IF;
      END IF;
    END IF;

    -- EVERY BOOKING GETS A DECISION BEHIND IT -- including the refusals, which are the
    -- honest record of the twin admitting past the depot's physical bay count.
    BEGIN
      INSERT INTO public.ottoq_decisions
        (sim_run_id, tick_seq, sim_clock, depot_id, action_context, resolved_action_context,
         entity_type, entity_id, context_frame, proposed_action, enacted_action,
         outcome_status, propose_latency_ms, total_latency_ms)
      VALUES
        (p_sim_run_id, v_tick, p_clock, p_depot_id, 'bay_reconcile', 'bay_reconcile',
         'vehicle', v_rec.id,
         jsonb_build_object('vehicle_state', v_rec.st, 'stall_type', v_type,
                            'purpose', v_purpose, 'bind_mode', v_how,
                            'reason', 'physically_in_bay_without_booking'),
         jsonb_build_object('verb','bind_bay_occupant','stall_type',v_type,'purpose',v_purpose),
         jsonb_build_object('verb', CASE WHEN v_bkg IS NULL THEN 'unbacked_bay_occupant'
                                         WHEN v_how = 'displace' THEN 'displace_and_bind'
                                         ELSE 'bind_bay_occupant' END,
                            'stall_id', v_stall, 'booking_id', v_bkg, 'leg_id', v_leg,
                            'purpose', v_purpose, 'stall_type', v_type, 'bind_mode', v_how,
                            'displaced', COALESCE((v_space->>'displaced')::int, 0),
                            'displaced_claims', COALESCE(v_space->'displaced_claims','[]'::jsonb)),
         CASE WHEN v_bkg IS NOT NULL THEN 'enacted' ELSE 'noop_no_candidate' END, 0, 0)
      RETURNING decision_id INTO v_dec;

      -- ROUTE THE WRITE THROUGH THE LEDGER, BY KEY. The booking now points at the
      -- decision that caused it, so "an otto_q_enacted booking with no decision
      -- behind it" becomes checkable instead of inferred from (vehicle, stall).
      IF v_bkg IS NOT NULL AND v_dec IS NOT NULL THEN
        UPDATE public.ottoq_stall_bookings
           SET decision_id   = COALESCE(decision_id, v_dec),
               decision_link = COALESCE(decision_link, 'writer_inline')
         WHERE booking_id = v_bkg;
        UPDATE public.space_conflict_ledger
           SET decision_id = v_dec
         WHERE new_booking_id = v_bkg AND decision_id IS NULL;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'ottoq_bind_unbooked_bay_occupants: decision row FAILED % %', SQLSTATE, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('bound', v_bound, 'in_place', v_inplace, 'refused', v_refused,
                            'displaced', v_displaced, 'displaced_claims', v_disp_rows);

EXCEPTION WHEN OTHERS THEN
  -- NO-ABORT GUARANTEE (2026-08-01 leg_type lesson): reconciliation is bookkeeping and
  -- must never take ottoq_decide_tick down.
  RAISE WARNING 'ottoq_bind_unbooked_bay_occupants: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN jsonb_build_object('bound',0,'in_place',0,'refused',0,'displaced',0,'error',SQLSTATE);
END
$function$

-- ===== ottoq_book_appointment =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_book_appointment(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamp with time zone, p_trigger text, p_urgency text, p_is_deferrable boolean, p_eta_minutes numeric, p_soc numeric, p_depot_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_had_need boolean; v_atoms jsonb; v_has_charge boolean;
  v_want_class text; v_stall uuid; v_stall_type text; v_ttl int;
  v_corr jsonb; v_eta_at timestamptz; v_cmd_type text; v_inlet text; v_plan jsonb; v_chg_kw numeric; v_new_est int; v_vv record; v_cplan jsonb;
BEGIN
  v_depot := COALESCE(p_depot_id,
                      (SELECT depot_id FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id),
                      (SELECT home_depot_id FROM vehicles WHERE id = p_vehicle_id));
  IF v_depot IS NULL THEN RETURN jsonb_build_object('secured', false, 'reason', 'no_depot'); END IF;

  SELECT inlet_type INTO v_inlet FROM vehicles WHERE id = p_vehicle_id;
  v_eta_at := p_clock + (GREATEST(COALESCE(p_eta_minutes, 30), 5)::text || ' minutes')::interval;

  SELECT EXISTS(SELECT 1 FROM ottoq_visit_needs vn
                 WHERE vn.vehicle_id = p_vehicle_id AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id AND vn.status IN ('open','in_progress'))
    INTO v_had_need;
  IF NOT v_had_need THEN
    BEGIN
      PERFORM ottoq_sim_generate_service_manifest(p_vehicle_id, p_sim_run_id, NULL);
    EXCEPTION WHEN OTHERS THEN NULL; -- booking survives a manifest hiccup (tick hot path)
    END;
  END IF;

  BEGIN PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, p_vehicle_id, v_eta_at);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  SELECT vn.atoms INTO v_atoms FROM ottoq_visit_needs vn
    WHERE vn.vehicle_id = p_vehicle_id AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id AND vn.status IN ('open','in_progress')
    ORDER BY vn.created_at DESC NULLS LAST LIMIT 1;

  v_has_charge := COALESCE((SELECT EXISTS(
      SELECT 1 FROM jsonb_array_elements(COALESCE(v_atoms, '[]'::jsonb)) a
       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))), false);

  -- CHARGE DOCTRINE: the per-visit charge plan decides class + target.
  -- Chemistry-aware (LFP 100 / NMC 90 + periodic balance), slack-aware (L2 all night
  -- when there is time, DCFC when there is not). Persisted so the SESSION runs to it,
  -- and so no mid-session class switch is ever needed to hit the target.
  v_want_class := NULL; v_cplan := NULL;
  IF v_has_charge THEN
    BEGIN
      v_cplan := ottoq_charge_plan_for_visit(p_vehicle_id, p_clock, NULL);
      IF COALESCE((v_cplan->>'ok')::boolean, false) THEN
        v_want_class := v_cplan->>'charger_class';
        -- SAFETY OVERRIDE: a critically-drained vehicle never waits on a slow charger.
        IF COALESCE(p_soc, 100) < 25 OR p_urgency IN ('critical','urgent') THEN
          v_want_class := 'dcfc';
          v_cplan := v_cplan || jsonb_build_object('class_override','urgency_dcfc');
        END IF;
        UPDATE vehicles
           SET target_soc = GREATEST(COALESCE((v_cplan->>'target_soc')::numeric, 90), COALESCE(p_soc,0)),
               config = COALESCE(config,'{}'::jsonb) || jsonb_build_object(
                 'charge_plan', jsonb_build_object(
                   'class', v_want_class, 'target_soc', (v_cplan->>'target_soc')::numeric,
                   'reason', CASE WHEN v_cplan ? 'class_override'
                      THEN 'urgency_dcfc_override(planned:' || COALESCE(v_cplan->>'reason','?') || ')'
                      ELSE v_cplan->>'reason' END,
                   'no_mid_session_switch', true,
                   'planned_at', p_clock))
         WHERE id = p_vehicle_id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_cplan := NULL;  -- booking survives a policy hiccup (tick hot path)
    END;
    -- charge_atom_target_stamped: push the planned target onto the manifest atom
    IF v_cplan IS NOT NULL AND COALESCE((v_cplan->>'ok')::boolean,false)
       AND v_atoms IS NOT NULL AND jsonb_typeof(v_atoms)='array' THEN
      SELECT jsonb_agg(CASE WHEN a->>'svc' = 'charge'
                            THEN a || jsonb_build_object(
                                   'target_soc', (v_cplan->>'target_soc')::numeric,
                                   'charger_class', v_want_class)
                            ELSE a END)
        INTO v_atoms FROM jsonb_array_elements(v_atoms) a;
    END IF;

    IF v_want_class IS NULL THEN   -- fallback: prior heuristic
      v_want_class := CASE
        WHEN p_trigger IN ('overnight_prestage','wash_cadence') THEN 'l2'
        WHEN COALESCE(p_soc, 100) < 45 OR p_urgency IN ('critical','urgent') THEN 'dcfc'
        ELSE 'l2' END;
    END IF;
  END IF;

  v_ttl := (GREATEST(COALESCE(p_eta_minutes, 30), 10) + 40)::int * 60;

  IF v_has_charge THEN
    -- reserve only an INLET-COMPATIBLE charge stall so the booking is honourable on arrival
    SELECT s.id, s.stall_type INTO v_stall, v_stall_type
      FROM stalls s
      JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = v_depot AND s.stall_type IN ('dcfc','l2')
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= p_clock)
       AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '35 minutes'
       AND (v_inlet IS NULL
            OR s.connector_type = v_inlet
            OR (s.connector_type = 'Multi' AND v_inlet = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
            OR (s.connector_type = 'NACS'  AND v_inlet IN ('NACS','Tesla_Proprietary')))
     ORDER BY (s.stall_type::text = v_want_class) DESC, s.relative_y ASC NULLS LAST, s.id
     LIMIT 1;
    IF v_stall IS NOT NULL AND NOT ottoq_reserve_stall(v_stall, p_vehicle_id, p_clock, v_ttl) THEN
      v_stall := NULL;
    END IF;
  END IF;

  IF v_stall IS NULL THEN
    SELECT s.id, s.stall_type INTO v_stall, v_stall_type FROM stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= p_clock)
     ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id
     LIMIT 1;
    IF v_stall IS NOT NULL AND NOT ottoq_reserve_stall(v_stall, p_vehicle_id, p_clock, v_ttl) THEN
      v_stall := NULL;
    END IF;
  END IF;

  IF v_stall IS NULL THEN
    RETURN jsonb_build_object('secured', false, 'reason', 'no_free_stall',
                              'has_charge', v_has_charge, 'want_class', v_want_class);
  END IF;

  -- ORCH-1: the full TIMED workflow plan, decided while the vehicle is en route.
  -- booked-charger recompute: the manifest priced the charge atom at a nominal
  -- DCFC; re-estimate against the RESERVED stall's real charger power (an L2
  -- overnight top-up is hours, not minutes) before building the timeline.
  BEGIN
    IF v_has_charge AND v_stall_type IN ('dcfc','l2') THEN
      SELECT c.max_kw INTO v_chg_kw
        FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
       WHERE s.id = v_stall;
      SELECT v.battery_capacity_kwh, v.inlet_max_kw,
             (v.config->>'battery_soh_pct')::numeric AS soh,
             (v.config->>'charge_curve_scalar')::numeric AS curve,
             COALESCE(v.target_soc,85) AS tsoc
        INTO v_vv FROM vehicles v WHERE v.id = p_vehicle_id;
      IF v_chg_kw IS NOT NULL THEN
        v_new_est := GREATEST(5, round(COALESCE(ottoq_estimate_charge_minutes(
            COALESCE(p_soc, 50), v_vv.tsoc, v_chg_kw, COALESCE(v_vv.inlet_max_kw, v_chg_kw),
            COALESCE(v_vv.battery_capacity_kwh, 75), 25, COALESCE(v_vv.soh, 95),
            GREATEST(0.2, ottoq_profile_rate_mult(p_sim_run_id,'charge_time')
                          / GREATEST(0.2, COALESCE(v_vv.curve, 1.0)))), 25)))::int;
        SELECT jsonb_agg(CASE WHEN a->>'svc' = 'charge'
                              THEN a || jsonb_build_object('est_min', v_new_est, 'charger_kw', v_chg_kw)
                              ELSE a END)
          INTO v_atoms FROM jsonb_array_elements(COALESCE(v_atoms,'[]'::jsonb)) a;
      END IF;
    END IF;
    v_plan := ottoq_build_workflow_plan(p_vehicle_id, p_sim_run_id, v_eta_at, v_atoms);
    UPDATE ottoq_visit_needs vn
       SET atoms = COALESCE(v_atoms, vn.atoms),
           meta = COALESCE(vn.meta,'{}'::jsonb)
              || jsonb_build_object('workflow_plan', v_plan, 'planned_at', p_clock,
                                    'booked_stall_id', v_stall, 'booked_stall_type', v_stall_type)
     WHERE vn.vehicle_id = p_vehicle_id AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id
       AND vn.status IN ('open','in_progress');
  EXCEPTION WHEN OTHERS THEN v_plan := NULL; -- plan is additive; booking never fails on it
  END;

  v_cmd_type := CASE WHEN v_stall_type = 'staging' THEN 'stage' ELSE 'proceed_to_stall' END;
  BEGIN
    v_corr := ottoq_comms_send_command(p_sim_run_id, p_vehicle_id, v_cmd_type,
      jsonb_build_object('stall_id', v_stall, 'stall_type', v_stall_type, 'eta_at', v_eta_at,
                         'workflow', COALESCE(v_atoms, '[]'::jsonb), 'plan', v_plan, 'trigger', p_trigger, 'urgency', p_urgency),
      p_clock, false);
  EXCEPTION WHEN OTHERS THEN v_corr := NULL; END;
  BEGIN
    PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, p_vehicle_id, v_cmd_type,
      jsonb_build_object('stall_id', v_stall, 'stall_type', v_stall_type, 'ttl_s', v_ttl,
                         'eta_at', v_eta_at, 'plan', v_plan, 'trigger', p_trigger, 'urgency', p_urgency, 'appointment', true,
                         'correlation_id', v_corr->>'correlation_id'), p_clock);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('secured', true, 'stall_id', v_stall, 'stall_type', v_stall_type,
                            'charger_class', v_want_class, 'ttl_s', v_ttl, 'command_type', v_cmd_type,
                            'correlation_id', v_corr->>'correlation_id', 'has_charge', v_has_charge,
                            'projected_ready_at', v_plan->>'projected_ready_at',
                            'plan_total_min', v_plan->>'total_min');
END;
$function$

-- ===== ottoq_book_hold_stall =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_book_hold_stall(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_visit_id uuid DEFAULT NULL::uuid, p_leg_id uuid DEFAULT NULL::uuid, p_long_threshold_min integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_minutes numeric; v_is_long boolean; v_purpose text;
  v_booking uuid; v_tier text;
  v_park_zones text[];
  c_ring CONSTANT text[] := ARRAY['staging_north','staging_south','staging_east','staging_west'];
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from THEN
    RETURN jsonb_build_object('booked', false, 'reason', 'invalid_window');
  END IF;

  v_minutes := EXTRACT(EPOCH FROM (p_to - p_from)) / 60.0;
  v_is_long := v_minutes >= p_long_threshold_min;
  v_purpose := CASE WHEN v_is_long THEN 'perimeter_hold' ELSE 'temp_hold' END;

  -- Derived, not hardcoded: every staging zone at this depot EXCEPT the inspection lane.
  -- A new staging zone added later is picked up automatically; a new inspection zone is
  -- excluded automatically as long as it is named 'arrival_inspection'.
  SELECT array_agg(DISTINCT s.zone) INTO v_park_zones
    FROM public.stalls s
   WHERE s.depot_id = p_depot_id
     AND s.stall_type::text = 'staging'
     AND s.zone <> 'arrival_inspection';

  IF v_park_zones IS NULL OR array_length(v_park_zones,1) IS NULL THEN
    v_park_zones := c_ring;   -- degenerate depot: still never NULL (NULL would mean "anywhere")
  END IF;

  IF v_is_long THEN
    -- PERIMETER HOLD: the outer ring is the PURPOSE, not an overflow tier.
    v_booking := ottoq.ottoq_find_and_book_stall(p_sim_run_id, p_depot_id, p_vehicle_id,
      v_purpose, p_from, p_to, 'staging', 'long', p_visit_id, p_leg_id, 'otto_q', c_ring);
    v_tier := 'perimeter_ring';

    IF v_booking IS NULL THEN
      v_booking := ottoq.ottoq_find_and_book_stall(p_sim_run_id, p_depot_id, p_vehicle_id,
        v_purpose, p_from, p_to, 'staging', 'long', p_visit_id, p_leg_id, 'otto_q', v_park_zones);
      v_tier := 'long_dwell_interior';
    END IF;

    IF v_booking IS NULL THEN
      v_booking := ottoq.ottoq_find_and_book_stall(p_sim_run_id, p_depot_id, p_vehicle_id,
        v_purpose, p_from, p_to, 'staging', 'temp', p_visit_id, p_leg_id, 'otto_q', v_park_zones);
      v_tier := 'temp_fallback';
    END IF;
  ELSE
    -- TEMP HOLD: the short-dwell pressure valve. Interior staging only.
    v_booking := ottoq.ottoq_find_and_book_stall(p_sim_run_id, p_depot_id, p_vehicle_id,
      v_purpose, p_from, p_to, 'staging', 'temp', p_visit_id, p_leg_id, 'otto_q', v_park_zones);
    v_tier := 'temp';

    IF v_booking IS NULL THEN
      v_booking := ottoq.ottoq_find_and_book_stall(p_sim_run_id, p_depot_id, p_vehicle_id,
        v_purpose, p_from, p_to, 'staging', 'long', p_visit_id, p_leg_id, 'otto_q', v_park_zones);
      v_tier := 'long_fallback';
    END IF;
  END IF;

  -- LAST RESORT. Only reached when all 86 non-inspection staging stalls are unavailable for
  -- the window. Keeps the no-starvation promise absolute while making any squat auditable.
  IF v_booking IS NULL THEN
    v_booking := ottoq.ottoq_find_and_book_stall(p_sim_run_id, p_depot_id, p_vehicle_id,
      v_purpose, p_from, p_to, 'staging', NULL, p_visit_id, p_leg_id, 'otto_q',
      ARRAY['arrival_inspection']);
    v_tier := 'inspection_last_resort';
  END IF;

  RETURN jsonb_build_object(
    'booked',       v_booking IS NOT NULL,
    'booking_id',   v_booking,
    'hold_class',   CASE WHEN v_is_long THEN 'perimeter' ELSE 'temp' END,
    'tier_used',    CASE WHEN v_booking IS NULL THEN NULL ELSE v_tier END,
    'purpose',      v_purpose,
    'hold_minutes', ROUND(v_minutes, 1),
    'fell_back',    v_booking IS NOT NULL AND v_tier NOT IN ('perimeter_ring','temp'),
    'squatted_inspection', v_booking IS NOT NULL AND v_tier = 'inspection_last_resort',
    'reason',       CASE WHEN v_booking IS NULL THEN 'no_staging_capacity_in_window' END
  );
END
$function$

-- ===== ottoq_book_stall =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_book_stall(p_sim_run_id uuid, p_stall_id uuid, p_vehicle_id uuid, p_purpose text, p_from timestamp with time zone, p_to timestamp with time zone, p_visit_id uuid DEFAULT NULL::uuid, p_leg_id uuid DEFAULT NULL::uuid, p_booked_by text DEFAULT 'otto_q'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_id uuid; v_w jsonb; v_zone text;
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from THEN
    RETURN NULL;                     -- a zero or negative window is not a booking
  END IF;

  -- ══════════════ INVARIANT 1: PARKING MAY NOT TAKE INSPECTION CAPACITY (2026-08-03) ══════════════
  -- Phase 9 measured 343.6 of 616.1 occupied stall-minutes in zone='arrival_inspection' (55.8%)
  -- consumed by temp_hold / perimeter_hold / staging. ottoq_book_hold_stall and
  -- ottoq_react_to_refusals had ALREADY been zone-excluded on their primary tiers, yet 27 parking
  -- bookings still landed there -- via their explicit 'inspection_last_resort' tiers and via
  -- ottoq_decide_tick's (3b) raw staging SELECT, which carried no zone predicate at all.
  -- Measured at every one of those 27 squats there were >=6 free temp AND >=31 free long
  -- non-inspection staging stalls, so the "last resort" was never reached on capacity grounds.
  -- Capacity proof for making this absolute: peak CONCURRENT parking demand in the phase-9 run
  -- was 70 bookings against 86 non-inspection staging stalls (81.4%, 16 stalls of headroom), and
  -- perimeter_hold peaked at 2 -- so this cannot starve staging nor push cars into perimeter hold
  -- (which is a PURPOSE, not an overflow tier).
  -- Kill-switch: policy 'parking_may_use_inspection_zone' >= 1 restores the old behaviour.
  IF p_purpose IN ('temp_hold','perimeter_hold','staging')
     AND public.ottoq_policy_get(p_sim_run_id, 'parking_may_use_inspection_zone', 0) < 1 THEN
    SELECT s.zone INTO v_zone FROM public.stalls s WHERE s.id = p_stall_id;
    IF v_zone = 'arrival_inspection' THEN
      RETURN NULL;                   -- caller walks to its next candidate / next tier
    END IF;
  END IF;

  -- ══════════════ INVARIANT 2: ONE LIVE BAY RESERVATION PER (VEHICLE, PURPOSE) (2026-08-03) ══════
  -- Root cause of the bay no-show regression 0.0% -> 7.3%. All 6 no-shows came from just 3
  -- vehicles, and they are all the SAME defect: a vehicle accumulating forward reservations for
  -- one need without ever giving up the earlier one. Measured peak simultaneous reservations held
  -- by a SINGLE vehicle in the phase-9 run:
  --     perimeter_hold 23 | temp_hold 6 | detail 5 | service 2
  --     charge_l2 1 | charge_dcfc 1 | wash 1 | staging 1 | inspect 1
  -- The purposes that cap at 1 are exactly the ones routed through
  -- ottoq_record_enacted_booking's adopt/supersede block; the four that do not are exactly the
  -- ones that produced the squats and the no-shows. Vehicle 616a06de held NINE detail bookings on
  -- a 3-bay wash lane, two PAIRS of which overlapped in time -- a vehicle cannot be in two bays at
  -- once, so one of each pair was guaranteed to time out as no_show_grace_elapsed. Vehicle
  -- 0d43459d held SVC-01 and SVC-02 for the identical window 15:36-16:19.
  -- This refuses the DUPLICATE at creation rather than superseding it afterwards, so it does not
  -- inflate the protected churn metric. The 15-minute grace
  -- (policy 'booking_no_show_grace_min') is deliberately NOT touched.
  -- 'interrupted' is intentionally NOT live here: re-planning interrupted work must still book.
  IF p_purpose IN ('wash','detail','service')
     AND public.ottoq_policy_get(p_sim_run_id, 'one_live_bay_reservation_per_purpose', 1) >= 1
     AND EXISTS (
           SELECT 1 FROM public.ottoq_stall_bookings b
            WHERE b.sim_run_id = p_sim_run_id
              AND b.vehicle_id = p_vehicle_id
              AND b.purpose    = p_purpose
              AND b.state IN ('held','active'))
  THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.ottoq_stall_bookings
    (sim_run_id, stall_id, vehicle_id, visit_id, leg_id, purpose, during, booked_by)
  VALUES
    (p_sim_run_id, p_stall_id, p_vehicle_id, p_visit_id, p_leg_id, p_purpose,
     tstzrange(p_from, p_to, '[)'), p_booked_by)
  RETURNING booking_id INTO v_id;

  -- WHY THIS VEHICLE IS IN THIS SPACE (2026-08-02).
  -- Runs only after a successful INSERT (contended attempts exit via exclusion_violation below),
  -- so it costs one resolve per booking actually written. Fully sub-blocked: a "why" we cannot
  -- compute must never cost us the booking.
  BEGIN
    v_w := ottoq.ottoq_booking_why(p_sim_run_id, p_vehicle_id, p_stall_id,
                                   p_purpose, p_from, p_to, p_leg_id, p_visit_id);
    UPDATE public.ottoq_stall_bookings b
       SET leg_id      = COALESCE(b.leg_id,   (v_w->>'leg_id')::uuid),
           visit_id    = COALESCE(b.visit_id, (v_w->>'visit_id')::uuid),
           leg_source  = COALESCE(b.leg_source,  v_w->>'leg_source'),
           need_code   = COALESCE(b.need_code,   v_w->>'need_code'),
           need_atom   = COALESCE(b.need_atom,   v_w->>'need_atom'),
           need_source = COALESCE(b.need_source, v_w->>'need_source'),
           why         = COALESCE(b.why,         v_w->>'why')
     WHERE b.booking_id = v_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_book_stall: could not stamp why on booking % (%): %', v_id, SQLSTATE, SQLERRM;
  END;

  RETURN v_id;
EXCEPTION
  WHEN exclusion_violation THEN
    RETURN NULL;                     -- stall is spoken for; caller tries the next one
  WHEN check_violation THEN
    -- TOTAL-FUNCTION GUARD (2026-08-01 leg_type-abort lesson). A booking we cannot classify is
    -- simply NOT recorded; the tick lives. Deliberately silent: no ottoq_record_event
    -- (that table is 9GB and must not be written here).
    RETURN NULL;
END
$function$

-- ===== ottoq_book_workflow =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_book_workflow(p_sim_run_id uuid, p_vehicle_id uuid, p_depot_id uuid, p_clock timestamp with time zone, p_max_shift_min integer DEFAULT 240, p_shift_step_min integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_leg        RECORD;
  v_want_type  text;
  v_purpose    text;
  v_booking    uuid;
  v_from       timestamptz;
  v_to         timestamptz;
  v_dur        interval;
  v_shift_min  int;
  v_hold       jsonb;
  v_booked     int := 0;
  v_shifted    int := 0;
  v_failed     int := 0;
  v_skipped    int := 0;
  v_detail     jsonb := '[]'::jsonb;
BEGIN
  FOR v_leg IN
    SELECT l.leg_id, l.seq, l.leg_type, l.planned_start_sim, l.planned_end_sim, l.itinerary_id
      FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_sim_run_id
       AND l.vehicle_id = p_vehicle_id
       AND l.status = 'planned'
       AND l.to_stall_id IS NULL
       AND l.planned_start_sim IS NOT NULL
       AND l.planned_end_sim   IS NOT NULL
       AND l.planned_end_sim   > p_clock
     ORDER BY l.seq
  LOOP
    -- Which physical resource does this leg need?
    v_want_type := CASE v_leg.leg_type
      WHEN 'charge_dcfc' THEN 'dcfc'
      WHEN 'charge_l2'   THEN 'l2'
      WHEN 'wash'        THEN 'wash_bay'
      WHEN 'detail'      THEN 'wash_bay'   -- no detail_bay stalls are seeded; detail shares the wash lane
      WHEN 'service'     THEN 'service_bay'
      ELSE NULL
    END;

    -- 'stage' is a hold: temp vs perimeter is chosen by DURATION, not by type.
    IF v_leg.leg_type = 'stage' THEN
      v_hold := ottoq.ottoq_book_hold_stall(
        p_sim_run_id, p_depot_id, p_vehicle_id,
        v_leg.planned_start_sim, v_leg.planned_end_sim, NULL, v_leg.leg_id);
      IF COALESCE((v_hold->>'booked')::boolean, false) THEN
        UPDATE public.ottoq_itinerary_legs
           SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                               WHERE b.booking_id = (v_hold->>'booking_id')::uuid)
         WHERE leg_id = v_leg.leg_id;
        v_booked := v_booked + 1;
        v_detail := v_detail || jsonb_build_object('seq', v_leg.seq, 'leg', v_leg.leg_type,
                      'booked', true, 'class', v_hold->>'hold_class', 'tier', v_hold->>'tier_used');
      ELSE
        v_failed := v_failed + 1;
        v_detail := v_detail || jsonb_build_object('seq', v_leg.seq, 'leg', v_leg.leg_type, 'booked', false);
      END IF;
      CONTINUE;
    END IF;

    -- Concurrent cabin work + movement legs ride another booking; no stall of their own.
    IF v_want_type IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    v_purpose := CASE v_leg.leg_type
      WHEN 'charge_dcfc' THEN 'charge_dcfc' WHEN 'charge_l2' THEN 'charge_l2'
      WHEN 'wash' THEN 'wash' WHEN 'detail' THEN 'detail' WHEN 'service' THEN 'service' END;

    v_dur      := v_leg.planned_end_sim - v_leg.planned_start_sim;
    v_shift_min := 0;
    v_booking  := NULL;

    -- Try the planned window; if contended, walk forward until something opens.
    WHILE v_booking IS NULL AND v_shift_min <= p_max_shift_min LOOP
      v_from := v_leg.planned_start_sim + make_interval(mins => v_shift_min);
      v_to   := v_from + v_dur;
      v_booking := ottoq.ottoq_find_and_book_stall(
        p_sim_run_id, p_depot_id, p_vehicle_id, v_purpose, v_from, v_to,
        v_want_type, NULL, NULL, v_leg.leg_id, 'otto_q', NULL);
      IF v_booking IS NULL THEN
        v_shift_min := v_shift_min + GREATEST(p_shift_step_min, 1);
      END IF;
    END LOOP;

    IF v_booking IS NOT NULL THEN
      UPDATE public.ottoq_itinerary_legs
         SET to_stall_id      = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                                  WHERE b.booking_id = v_booking),
             planned_start_sim = v_from,
             planned_end_sim   = v_to
       WHERE leg_id = v_leg.leg_id;
      v_booked := v_booked + 1;
      IF v_shift_min > 0 THEN v_shifted := v_shifted + 1; END IF;
      v_detail := v_detail || jsonb_build_object('seq', v_leg.seq, 'leg', v_leg.leg_type,
                    'booked', true, 'stall_type', v_want_type, 'shifted_min', v_shift_min);
    ELSE
      v_failed := v_failed + 1;
      v_detail := v_detail || jsonb_build_object('seq', v_leg.seq, 'leg', v_leg.leg_type,
                    'booked', false, 'stall_type', v_want_type,
                    'reason', 'no capacity within ' || p_max_shift_min || ' min');
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'vehicle_id', p_vehicle_id, 'booked', v_booked, 'shifted', v_shifted,
    'unbookable', v_failed, 'rides_another_booking', v_skipped, 'legs', v_detail);
END
$function$

-- ===== ottoq_booking_authorship =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_booking_authorship(p_source text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    -- No named writer => no authorship claim. Fail closed.
    WHEN NULLIF(BTRIM(COALESCE(p_source,'')),'') IS NULL
      OR BTRIM(LOWER(p_source)) IN ('unknown','unspecified','none')
      THEN 'otto_q'
    WHEN BTRIM(LOWER(p_source)) IN (
           -- The twin had ALREADY put the vehicle in this exact stall and the window comes
           -- from the twin's own config.service_ends_at. OTTO-Q selected neither the space
           -- nor the timing, so claiming enactment here would be a false authorship claim.
           'bay_reconcile_in_place'
         ) THEN 'twin_observed'
    ELSE 'otto_q_enacted'
  END;
$function$

-- ===== ottoq_booking_interrupted =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_booking_interrupted(p_purpose text, p_planned_s numeric, p_actual_s numeric)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  -- "MATERIALLY SHORTER" (BUILD 2, calibrated on run 6b22906b busy_day/424242, 157.3 sim-min):
  --   interrupted  <=>  actual < 80% of planned  AND  shortfall >= 120 s.
  --
  -- WHY 80%: the 24 bay closures of that run are strictly bimodal by completion ratio --
  --   17 rows at ratio <= 0.630 and 7 rows at ratio >= 0.828. The 0.630..0.828 gap is the
  --   widest gap in the whole distribution and 0.80 sits inside it. ANY threshold in that
  --   open interval yields the SAME 17/7 split, so the classification is insensitive to the
  --   exact constant -- it reads a real structural break, not a tuned knob.
  -- WHY the 120 s floor: a wash bay is only 9 min of planned work, so a pure ratio would flag
  --   sub-minute jitter on short bays. At 12 sim-seconds per tick (157.3 sim-min / 787 ticks)
  --   120 s is ~10 ticks of slack. HONESTY NOTE: on the calibration run this floor is INERT --
  --   the smallest shortfall among the 17 flagged rows is 3.33 min. The RATIO is the operative
  --   rule; the floor is a guard rail for short bays, not the thing doing the work.
  SELECT ottoq.ottoq_is_bay_purpose(p_purpose)
     AND p_planned_s IS NOT NULL AND p_planned_s > 0
     AND p_actual_s  IS NOT NULL
     AND p_actual_s < 0.80 * p_planned_s
     AND (p_planned_s - p_actual_s) >= 120;
$function$

-- ===== ottoq_booking_why =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_booking_why(p_sim_run_id uuid, p_vehicle_id uuid, p_stall_id uuid, p_purpose text, p_from timestamp with time zone, p_to timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_visit_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_leg_type text; v_leg uuid; v_leg_src text := 'none';
  v_visit uuid := p_visit_id; v_atoms jsonb; v_a jsonb;
  v_need text; v_atom text; v_need_src text; v_why text;
  v_target numeric; v_soc numeric; v_stall_code text;
  v_from timestamptz := COALESCE(p_from, now());
  v_to   timestamptz := COALESCE(p_to, COALESCE(p_from, now()) + interval '30 minutes');
  -- svc codes the mapper knows EXPLICITLY. Everything else reaches its catch-all ELSE 'service',
  -- which is correct for leg planning but must NOT be allowed to make an unrelated atom look
  -- like the justification for a service bay.
  c_known constant text[] := ARRAY['interior_tidy','sensor_clean','item_retrieval','software_update',
                                   'remote_diagnostics','triage_check','sensor_calibration',
                                   'mechanical_pm','fault_repair','cosmetic_repair',
                                   'exterior_wash','interior_deep_clean','interior_inspection'];
BEGIN
  v_leg_type := CASE p_purpose
    WHEN 'charge_dcfc' THEN 'charge_dcfc'
    WHEN 'charge_l2'   THEN 'charge_l2'
    WHEN 'wash'        THEN 'wash'
    WHEN 'detail'      THEN 'detail'
    WHEN 'service'     THEN 'service'
    WHEN 'inspect'     THEN 'inspect'
    ELSE 'stage'
  END;

  v_leg := p_leg_id;
  IF v_leg IS NOT NULL THEN v_leg_src := 'caller'; END IF;

  -- (a) a leg ALREADY bound to this exact stall. The twin opens charge legs this way
  --     (ottoq_itin_leg_open stamps to_stall_id and flips status to 'active'), which is
  --     precisely why decide_tick's "status='planned' AND to_stall_id IS NULL" lookup
  --     could never see it.
  IF v_leg IS NULL AND p_stall_id IS NOT NULL THEN
    BEGIN
      SELECT l.leg_id INTO v_leg
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id  = p_sim_run_id
         AND l.vehicle_id  = p_vehicle_id
         AND l.to_stall_id = p_stall_id
         AND l.leg_type    = v_leg_type
         AND l.status IN ('planned','active')
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bx
                          WHERE bx.leg_id = l.leg_id AND bx.state IN ('held','active'))
       ORDER BY (l.status = 'active') DESC,
                abs(EXTRACT(EPOCH FROM (COALESCE(l.planned_start_sim, v_from) - v_from)))
       LIMIT 1;
    EXCEPTION WHEN OTHERS THEN v_leg := NULL;
    END;
    IF v_leg IS NOT NULL THEN v_leg_src := 'bound_to_same_stall'; END IF;
  END IF;

  -- (b) an UNBOUND planned leg of the right type whose window is still open
  IF v_leg IS NULL THEN
    BEGIN
      SELECT l.leg_id INTO v_leg
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id
         AND l.vehicle_id = p_vehicle_id
         AND l.to_stall_id IS NULL
         AND l.leg_type   = v_leg_type
         AND l.status     = 'planned'
         AND COALESCE(l.planned_end_sim, v_to) > v_from
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bx
                          WHERE bx.leg_id = l.leg_id AND bx.state IN ('held','active'))
       ORDER BY l.seq
       LIMIT 1;
    EXCEPTION WHEN OTHERS THEN v_leg := NULL;
    END;
    IF v_leg IS NOT NULL THEN v_leg_src := 'planned_unbound'; END IF;
  END IF;

  BEGIN
    IF v_visit IS NULL THEN
      SELECT vn.visit_id, vn.atoms, vn.target_soc
        INTO v_visit, v_atoms, v_target
        FROM public.ottoq_visit_needs vn
       WHERE vn.vehicle_id = p_vehicle_id
         AND vn.sim_run_id = p_sim_run_id
         AND vn.status IN ('open','in_progress')
       ORDER BY vn.created_at DESC LIMIT 1;
    ELSE
      SELECT vn.atoms, vn.target_soc INTO v_atoms, v_target
        FROM public.ottoq_visit_needs vn WHERE vn.visit_id = v_visit;
    END IF;
  EXCEPTION WHEN OTHERS THEN v_atoms := NULL;
  END;

  BEGIN
    IF v_atoms IS NOT NULL THEN
      IF v_leg_type IN ('charge_dcfc','charge_l2') THEN
        SELECT a INTO v_a FROM jsonb_array_elements(v_atoms) a
         WHERE a->>'svc' = 'charge'
           AND COALESCE(a->>'status','pending') <> 'cancelled' LIMIT 1;

      ELSIF v_leg_type = 'inspect' THEN
        -- readiness_check has no distinct spelling in the mapper (it reaches the catch-all),
        -- but the inspect lane is exactly what it justifies.
        SELECT a INTO v_a FROM jsonb_array_elements(v_atoms) a
         WHERE a->>'svc' IN ('interior_inspection','readiness_check','triage_check')
           AND COALESCE(a->>'status','pending') <> 'cancelled' LIMIT 1;

      ELSIF v_leg_type <> 'stage' THEN
        -- ALWAYS route the twin's OPEN vocabulary through the total mapper -- but 'charge' and
        -- 'readiness_check' own dedicated lanes, so they must never be adopted here via the
        -- mapper's catch-all ELSE 'service'. Explicitly-known codes outrank fall-through ones.
        SELECT a INTO v_a FROM jsonb_array_elements(v_atoms) a
         WHERE a->>'svc' NOT IN ('charge','readiness_check')
           AND public.ottoq_svc_to_leg_type(a->>'svc') = v_leg_type
           AND COALESCE(a->>'status','pending') <> 'cancelled'
         ORDER BY (CASE WHEN a->>'svc' = ANY (c_known) THEN 0 ELSE 1 END)
         LIMIT 1;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN v_a := NULL;
  END;

  v_atom := v_a->>'svc';

  IF v_atom IS NOT NULL THEN
    v_need := CASE WHEN v_leg_type IN ('charge_dcfc','charge_l2') THEN 'charge' ELSE v_atom END;
    v_need_src := 'visit_atom';
  ELSE
    v_need := CASE p_purpose
      WHEN 'charge_dcfc'    THEN 'charge'
      WHEN 'charge_l2'      THEN 'charge'
      WHEN 'wash'           THEN 'exterior_wash'
      WHEN 'detail'         THEN 'interior_deep_clean'
      WHEN 'service'        THEN 'service_due'
      WHEN 'inspect'        THEN 'readiness_check'
      WHEN 'staging'        THEN 'staging_hold'
      WHEN 'perimeter_hold' THEN 'perimeter_hold'
      WHEN 'temp_hold'      THEN 'temp_hold'
      ELSE 'unclassified_placement'
    END;
    v_need_src := 'inferred_from_purpose';
  END IF;

  BEGIN
    SELECT v.current_soc INTO v_soc FROM public.vehicles v WHERE v.id = p_vehicle_id;
    SELECT s.stall_code INTO v_stall_code FROM public.stalls s WHERE s.id = p_stall_id;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  v_why := format('%s %s %s-%s to satisfy need %L (%s)%s%s',
             COALESCE(v_stall_code, 'stall'),
             COALESCE(p_purpose,'?'),
             to_char(v_from, 'HH24:MI'), to_char(v_to, 'HH24:MI'),
             v_need, v_need_src,
             CASE WHEN v_leg_type IN ('charge_dcfc','charge_l2')
                  THEN format('; SoC %s%% -> target %s%%',
                              COALESCE(round(v_soc,0)::text,'?'), COALESCE(round(v_target,0)::text,'?'))
                  ELSE '' END,
             CASE WHEN v_leg IS NOT NULL
                  THEN format('; leg %s (%s, matched %s)', left(v_leg::text,8), v_leg_type, v_leg_src)
                  ELSE format('; NO itinerary leg exists at enactment - placement justified by need only (leg_type would be %s)', v_leg_type)
             END);

  RETURN jsonb_build_object(
    'leg_id',      v_leg,
    'leg_source',  v_leg_src,
    'leg_type',    v_leg_type,
    'visit_id',    v_visit,
    'need_code',   v_need,
    'need_atom',   v_atom,
    'need_source', v_need_src,
    'why',         v_why);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('leg_id', p_leg_id, 'leg_source','none', 'visit_id', p_visit_id,
                            'need_code','unresolved','need_source','resolver_error',
                            'why', 'why-resolver failed: '||SQLSTATE);
END
$function$

-- ===== ottoq_decide_return_on_signal =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_decide_return_on_signal(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamp with time zone, p_soc_pct numeric, p_vehicle_soc numeric, p_eta_min numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_ret       RECORD;
  v_intent    boolean;
  v_trigger   text;
  v_urgency   text;
  v_defer     boolean;
  v_eta       numeric;
  v_book      jsonb;
BEGIN
  v_intent := p_eta_min IS NOT NULL;  -- vehicle-initiated return announcement

  -- the same need ladder the twin path uses, with the REAL SoC override
  SELECT er.should_return, er.return_trigger, er.urgency, er.is_deferrable
    INTO v_ret
    FROM ottoq_evaluate_return_need(
           p_vehicle_id, p_sim_run_id, p_clock, 30, p_soc_pct) er;

  IF NOT COALESCE(v_ret.should_return, false) AND NOT v_intent THEN
    RETURN jsonb_build_object('should_return', false,
                              'vehicle_initiated', v_intent,
                              'depart', false);
  END IF;

  v_trigger := CASE WHEN COALESCE(v_ret.should_return, false)
                    THEN COALESCE(v_ret.return_trigger, 'need_unspecified')
                    ELSE 'vehicle_initiated' END;
  v_urgency := COALESCE(v_ret.urgency, 'routine');
  -- an announced inbound vehicle IS coming — never deferrable
  v_defer   := CASE WHEN v_intent THEN false ELSE COALESCE(v_ret.is_deferrable, false) END;
  v_eta     := COALESCE(p_eta_min, ottoq_return_eta_minutes(p_vehicle_id, NULL, p_sim_run_id));

  BEGIN
    v_book := ottoq_book_appointment(
                p_vehicle_id, p_sim_run_id, p_clock,
                v_trigger, v_urgency, v_defer, v_eta, COALESCE(p_soc_pct, p_vehicle_soc), NULL);
  EXCEPTION WHEN OTHERS THEN
    v_book := jsonb_build_object('secured', false, 'reason', 'booking_error', 'error', SQLERRM);
  END;

  -- same departure gate as the twin path: secured resource OR non-deferrable need.
  -- OTTO-Q returns the verdict; the twin performs the state change.
  RETURN jsonb_build_object(
    'should_return', true,
    'trigger', v_trigger,
    'urgency', v_urgency,
    'deferrable', v_defer,
    'eta_min', v_eta,
    'vehicle_initiated', v_intent,
    'depart', (COALESCE((v_book->>'secured')::boolean, false) OR NOT v_defer),
    'appointment', v_book);
END;
$function$

-- ===== ottoq_decide_wash_triage =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_decide_wash_triage(p_vehicle_id uuid, p_depot_id uuid, p_manifest jsonb, p_wash_cap integer, p_in_wash integer, p_sim_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_has_mustdo_clean boolean; v_has_mustdo_bay boolean; v_has_defer_bay boolean;
  v_deferrable jsonb; v_atoms jsonb; v_urgency text;
  v_in_wash        int  := p_in_wash;
  v_next_state     text := NULL;
  v_svc_step       text := NULL;
  v_decision       text := 'hold_for_cleaning';
  v_released_delta int  := 0;
BEGIN
  IF p_manifest IS NULL THEN
    RETURN jsonb_build_object(
      'decision','skip_no_manifest', 'next_state', NULL, 'svc_step', NULL,
      'deferred_services', NULL, 'in_wash_after', v_in_wash, 'released_delta', 0,
      'urgency', NULL, 'has_mustdo_clean', NULL, 'has_mustdo_bay', NULL,
      'has_defer_bay', NULL, 'wash_cap', p_wash_cap, 'depot_id', p_depot_id,
      'clock', p_sim_clock);
  END IF;

  SELECT vn.atoms, vn.urgency INTO v_atoms, v_urgency FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
   ORDER BY vn.created_at DESC LIMIT 1;

  IF v_atoms IS NOT NULL THEN
    SELECT
      EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
               WHERE COALESCE((a->>'must_do')::boolean,false) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
                 AND a->>'svc' IN ('interior_tidy','sensor_clean','item_retrieval')),
      EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
               WHERE COALESCE((a->>'must_do')::boolean,false) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
                 AND a->>'concurrency' = 'bay'),
      EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
               WHERE COALESCE((a->>'deferrable')::boolean,false) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
                 AND a->>'svc' IN ('exterior_wash','interior_deep_clean'))
    INTO v_has_mustdo_clean, v_has_mustdo_bay, v_has_defer_bay;
  ELSE
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(p_manifest) e
                    WHERE COALESCE((e->>'must_do')::boolean,false)
                      AND e->>'svc' IN ('interior_tidy','sensor_clean'))
      INTO v_has_mustdo_clean;
    v_has_mustdo_bay := false; v_has_defer_bay := false;
  END IF;

  SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(p_manifest) e
    WHERE COALESCE((e->>'deferrable')::boolean,false)
    INTO v_deferrable;

  IF v_has_mustdo_bay THEN
    v_decision   := 'stage_awaiting_service';
    v_next_state := 'staged_awaiting_service';
    v_svc_step   := 'need_service';
  ELSIF NOT v_has_mustdo_clean THEN
    IF v_has_defer_bay AND v_in_wash < p_wash_cap AND COALESCE(v_urgency,'standard') <> 'immediate_dispatch' THEN
      v_in_wash  := v_in_wash + 1;
      v_decision := 'hold_for_wash_lane';
    ELSE
      v_decision       := 'release';
      v_next_state     := 'staged_for_departure';
      v_svc_step       := 'ready';
      v_released_delta := 1;
    END IF;
  ELSE
    v_decision := 'hold_for_cleaning';
  END IF;

  RETURN jsonb_build_object(
    'decision', v_decision, 'next_state', v_next_state, 'svc_step', v_svc_step,
    'deferred_services', v_deferrable, 'in_wash_after', v_in_wash,
    'released_delta', v_released_delta, 'urgency', v_urgency,
    'has_mustdo_clean', v_has_mustdo_clean, 'has_mustdo_bay', v_has_mustdo_bay,
    'has_defer_bay', v_has_defer_bay, 'wash_cap', p_wash_cap,
    'depot_id', p_depot_id, 'clock', p_sim_clock);
END; $function$

-- ===== ottoq_emit_booking_interrupted =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_emit_booking_interrupted(p_sim_run_id uuid, p_depot_id uuid, p_booking_id uuid, p_vehicle_id uuid, p_stall_id uuid, p_purpose text, p_clock timestamp with time zone, p_release_reason text, p_planned_s numeric, p_actual_s numeric, p_atoms_reopened integer, p_legs_replanned integer, p_source text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_outstanding int := -1;   -- -1 == "could not be measured", never confused with a real 0
  v_remaining_min numeric;
  v_ratio numeric;
BEGIN
  -- OUTCOME CHECK: is work still DUE for this vehicle after the interruption?
  -- Its own handler: a metric read must never cost us the audit record.
  BEGIN
    SELECT count(*) INTO v_outstanding
      FROM public.ottoq_visit_needs vn
     WHERE vn.vehicle_id = p_vehicle_id
       AND vn.status = 'open'
       AND vn.meta ? 'reopen';
  EXCEPTION WHEN OTHERS THEN
    v_outstanding := -1;
    RAISE WARNING 'booking_interrupted: outstanding_restored probe failed sqlstate=% msg=% booking=%',
      SQLSTATE, SQLERRM, p_booking_id;
  END;

  v_remaining_min := CASE
      WHEN p_planned_s IS NULL OR p_actual_s IS NULL THEN NULL
      ELSE round(GREATEST(p_planned_s - p_actual_s, 0)::numeric / 60.0, 2) END;
  v_ratio := CASE
      WHEN p_planned_s IS NULL OR p_actual_s IS NULL OR p_planned_s = 0 THEN NULL
      ELSE round(p_actual_s / p_planned_s, 3) END;

  BEGIN
    PERFORM public.ottoq_record_event(
      p_actor_type    := 'ottoq_engine',
      p_actor_id      := COALESCE(p_source,'unknown'),
      p_event_type    := 'ottoq.booking_interrupted',
      p_entity_type   := 'vehicle',
      p_entity_id     := p_vehicle_id,
      p_depot_id      := p_depot_id,
      p_payload       := jsonb_build_object(
        -- identity
        'booking_id',            p_booking_id,
        'stall_id',              p_stall_id,
        'purpose',               p_purpose,
        'release_reason',        p_release_reason,
        'source',                p_source,
        -- THE CONTRACT: these four keys are present on EVERY emission, from every path.
        'atoms_reopened',        COALESCE(p_atoms_reopened, 0),
        'legs_replanned',        COALESCE(p_legs_replanned, 0),
        'outstanding_restored',  v_outstanding,
        'minutes_remaining',     v_remaining_min,
        -- supporting detail
        'planned_min',           CASE WHEN p_planned_s IS NULL THEN NULL ELSE round(p_planned_s/60.0,2) END,
        'actual_min',            CASE WHEN p_actual_s  IS NULL THEN NULL ELSE round(p_actual_s /60.0,2) END,
        'completion_ratio',      v_ratio,
        'emitter_version',       2,
        'doctrine',              'full_service_visit_is_atomic; interrupted work stays DUE and must be re-booked'),
      p_severity      := 'warning',
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'booking_interrupted EMISSION DROPPED sqlstate=% msg=% booking=% vehicle=% reason=% source=%',
      SQLSTATE, SQLERRM, p_booking_id, p_vehicle_id, p_release_reason, p_source;
  END;

EXCEPTION WHEN OTHERS THEN
  -- Belt and braces: nothing in here may ever abort a tick.
  RAISE WARNING 'ottoq_emit_booking_interrupted: TOTAL FAILURE sqlstate=% msg=% booking=%',
    SQLSTATE, SQLERRM, p_booking_id;
END
$function$

-- ===== ottoq_emit_vehicle_command =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_emit_vehicle_command(p_run uuid, p_depot uuid, p_vehicle uuid, p_type text, p_payload jsonb, p_clock timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_check jsonb; v_id uuid;
BEGIN
  v_check := ottoq.ottoq_validate_assignment(
               p_vehicle, NULLIF(p_payload->>'stall_id','')::uuid, p_type, p_clock);

  IF COALESCE((v_check->>'ok')::boolean, false) THEN
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at)
    VALUES (p_run, p_depot, p_vehicle, p_type, p_payload, p_clock)
    RETURNING command_id INTO v_id;
  ELSE
    -- OTTO-Q refuses its OWN conflicting instruction pre-flight. It is recorded
    -- for the audit trail and the reaction loop, and never reaches the twin.
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at,
                                               status, reason_code, reason_detail, confirmed_at, confirmed_by)
    VALUES (p_run, p_depot, p_vehicle, p_type, p_payload, p_clock,
            'refused', v_check->>'code', v_check->>'detail', p_clock, 'otto_q_preflight')
    RETURNING command_id INTO v_id;
  END IF;
  RETURN v_id;
END $function$

-- ===== ottoq_enact_inspection_seam =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_enact_inspection_seam(p_sim_run_id uuid, p_depot_id uuid, p_tick bigint, p_snapshot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_row RECORD; v_space jsonb; v_ctx jsonb; v_proposal jsonb; v_action jsonb;
  v_blocks int; v_block_codes text[]; v_rule_rows jsonb;
  v_open int; v_enacted int := 0; v_est_min numeric; v_until timestamptz;
  v_t0 timestamptz; v_prop_ms int; v_shield_ms int; v_enact_ms int;
  v_outcome text; v_over boolean; v_safe boolean;
  v_leg_type text; v_cmd uuid; v_cmd_err text;
  c_svc CONSTANT text := 'interior_inspection';
  c_states CONSTANT text[] := ARRAY['arrived_at_gate','staged_awaiting_service',
                                    'charge_complete_holding','service_complete_holding',
                                    'staged_for_departure'];
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  v_leg_type := public.ottoq_svc_to_leg_type(c_svc);   -- → 'inspect', total by construction

  SELECT GREATEST(COALESCE(est_min_default, 4), 1) INTO v_est_min
    FROM public.service_cadence_policy WHERE svc = c_svc AND is_active;
  v_est_min := COALESCE(v_est_min, 4);

  UPDATE public.ottoq_itinerary_legs l
     SET status = 'done', actual_end_sim = p_clock
   WHERE l.sim_run_id = p_sim_run_id
     AND l.leg_type   = v_leg_type
     AND l.status     = 'planned'
     AND EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                  WHERE b.leg_id = l.leg_id AND b.sim_run_id = p_sim_run_id
                    AND b.purpose = 'inspect' AND b.state = 'done');

  UPDATE public.stalls s
     SET current_vehicle_id = NULL, reserved_by = NULL,
         reservation_expires_at = NULL, status = 'available'
   WHERE s.depot_id = p_depot_id
     AND s.zone     = 'arrival_inspection'
     AND s.status NOT IN ('maintenance','closed')
     AND s.current_vehicle_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                      WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                        AND b.vehicle_id = s.current_vehicle_id
                        AND b.state IN ('held','active')
                        AND upper(b.during) > p_clock);

  -- Clear DEAD reservations in the inspection lane (see fix 3): a stall with no vehicle but
  -- a lapsed reserved_by counts as free physically yet fails the ottoq_reserve_stall CAS.
  UPDATE public.stalls s
     SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
   WHERE s.depot_id = p_depot_id
     AND s.zone     = 'arrival_inspection'
     AND s.current_vehicle_id IS NULL
     AND s.reserved_by IS NOT NULL
     AND (s.reservation_expires_at IS NULL OR s.reservation_expires_at <= p_clock);

  UPDATE public.vehicles v
     SET current_stall_id = NULL
   WHERE v.home_depot_id = p_depot_id
     AND v.current_stall_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.stalls s
                  WHERE s.id = v.current_stall_id
                    AND s.zone = 'arrival_inspection'
                    AND s.current_vehicle_id IS DISTINCT FROM v.id);

  SELECT count(*) INTO v_open
    FROM public.stalls s
   WHERE s.depot_id = p_depot_id
     AND s.zone = 'arrival_inspection'
     AND s.status NOT IN ('maintenance','closed')
     AND s.current_vehicle_id IS NULL;

  IF COALESCE(v_open,0) <= 0 THEN RETURN 0; END IF;

  FOR v_row IN
    SELECT v.id AS vehicle_id, v.fleet_operator_id,
           l.leg_id,
           COALESCE(l.planned_end_sim - l.planned_start_sim,
                    make_interval(mins => v_est_min::int)) AS dur,
           c.minutes_to_deploy, c.fits_window, c.overall_urgency
      FROM public.vehicles v
      JOIN LATERAL (
        SELECT il.leg_id, il.planned_start_sim, il.planned_end_sim
          FROM public.ottoq_itinerary_legs il
         WHERE il.sim_run_id  = p_sim_run_id
           AND il.vehicle_id  = v.id
           AND il.status      = 'planned'
           AND il.leg_type    = v_leg_type
           AND il.to_stall_id IS NULL
         ORDER BY il.seq LIMIT 1) l ON true
      LEFT JOIN public.ottoq_vehicle_needs_card c
             ON c.vehicle_id = v.id AND c.depot_id = p_depot_id
     WHERE v.home_depot_id  = p_depot_id
       AND v.category       = 'autonomous'
       AND v.current_state::text = ANY (c_states)
       AND NOT EXISTS (
             SELECT 1 FROM public.ottoq_stall_bookings wb
              WHERE wb.sim_run_id = p_sim_run_id
                AND wb.vehicle_id = v.id
                AND wb.state IN ('held','active')
                AND wb.purpose IN ('charge_dcfc','charge_l2','wash','detail','service')
                AND lower(wb.during) < p_clock + make_interval(mins => v_est_min::int))
       AND COALESCE(public.ottoq_approach_zone(v.id, p_sim_run_id), 'B') <> 'C'
       AND COALESCE(c.fits_window, true)
       AND (c.minutes_to_deploy IS NULL OR c.minutes_to_deploy >= v_est_min)
       AND NOT EXISTS (SELECT 1 FROM public.stalls s2
                        WHERE s2.id = v.current_stall_id AND s2.zone = 'arrival_inspection')
     ORDER BY public.ottoq_urgency_rank(COALESCE(c.overall_urgency,'ok')) DESC,
              c.minutes_to_deploy ASC NULLS LAST, v.id
     LIMIT 20
  LOOP
    EXIT WHEN v_open <= 0;

    v_t0 := clock_timestamp(); v_over := false; v_safe := false;
    v_block_codes := '{}'; v_rule_rows := NULL; v_cmd := NULL; v_cmd_err := NULL;

    v_ctx := public.ottoq_build_decision_context('task_start','vehicle',v_row.vehicle_id,p_depot_id,p_clock)
             || jsonb_build_object('need',c_svc,'lane','inspection',
                  'stall_type','staging','zone','arrival_inspection','purpose','inspect',
                  'leg_id', v_row.leg_id,
                  'leg_type', v_leg_type,
                  'minutes_to_deploy', v_row.minutes_to_deploy,
                  'fits_window', v_row.fits_window,
                  'requires_charging','false','service','inspect');
    v_proposal := jsonb_build_object('abstain', false, 'verb','assign_stall',
                    'resolved_action_context','stall_assignment', 'source','inspect_seam',
                    'vehicle_id', v_row.vehicle_id, 'stall_type','staging',
                    'purpose','inspect', 'need',c_svc, 'requested_kw', 0);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

    v_t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM public.ottoq_shield_probe('task_start','vehicle',v_row.vehicle_id,v_ctx,v_row.fleet_operator_id,p_depot_id);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

    v_t0 := clock_timestamp();
    IF COALESCE(v_blocks,0) > 0 THEN
      v_action := jsonb_build_object('verb','hold_no_space','reason','shield_block');
      v_safe := true; v_over := true; v_outcome := 'overridden_to_default';
    ELSE
      v_until := GREATEST(p_clock + v_row.dur, p_clock + interval '1 minute');

      v_space := ottoq.ottoq_enact_space_assignment(
                   p_sim_run_id, p_depot_id, v_row.vehicle_id,
                   'staging', 'inspect', p_clock, v_until, v_row.leg_id, 'inspect_seam');

      IF COALESCE((v_space->>'assigned')::boolean, false) THEN
        v_open := v_open - 1; v_enacted := v_enacted + 1;

        -- ISOLATED EMIT. Correct schema (ottoq, not public) + explicit ::text so overload
        -- resolution never sees `unknown`. Its own handler so a comms failure can never
        -- unwind the stall assignment and booking that already succeeded above.
        BEGIN
          v_cmd := ottoq.ottoq_emit_vehicle_command(
                     p_sim_run_id, p_depot_id, v_row.vehicle_id,
                     'proceed_to_stall'::text,
                     jsonb_build_object('stall_id', v_space->>'stall_id',
                                        'booking_id', v_space->>'booking_id',
                                        'leg_id', v_row.leg_id,
                                        'purpose','inspect',
                                        'reason','inspect_seam_interior_inspection'),
                     p_clock);
        EXCEPTION WHEN OTHERS THEN
          v_cmd_err := SQLSTATE||': '||SQLERRM;
          RAISE WARNING 'ottoq_enact_inspection_seam: command emit failed (assignment KEPT) % vehicle=%',
            v_cmd_err, v_row.vehicle_id;
        END;

        v_action := v_proposal || v_space
                    || jsonb_build_object('verb','assign_stall',
                         'stall_id', v_space->>'stall_id',
                         'inspect_booked', (v_space->>'booking_id') IS NOT NULL,
                         'command_id', v_cmd,
                         'command_error', v_cmd_err);
        v_outcome := 'enacted';
      ELSE
        v_action := v_proposal || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('verb','hold_no_space');
        v_outcome := 'noop_no_candidate';
      END IF;
    END IF;
    v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

    INSERT INTO public.ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,p_tick,p_clock,p_depot_id,p_snapshot_id,'task_start','stall_assignment','vehicle',v_row.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  RETURN v_enacted;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_enact_inspection_seam: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$

-- ===== ottoq_enact_opportunistic_charge =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_enact_opportunistic_charge(p_sim_run_id uuid, p_vehicle_id uuid, p_current_soc numeric, p_vehicle_target_soc numeric, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_target numeric; v_oh jsonb; v_os uuid; v_odepot uuid; v_reserved boolean := false;
BEGIN
  v_target := LEAST(90, GREATEST(COALESCE(p_vehicle_target_soc, 80), p_current_soc + 20));

  UPDATE ottoq_visit_needs SET
         atoms = atoms || jsonb_build_array(jsonb_build_object(
           'svc','charge','must_do',false,'deferrable',false,'est_min',15,
           'target_soc', v_target, 'concurrency','anchor','opportunistic',true)),
         target_soc = GREATEST(COALESCE(target_soc,0), v_target),
         status='in_progress'
   WHERE vehicle_id = p_vehicle_id AND status IN ('open','in_progress');

  -- DOCTRINE (Chase 2026-07-28): never bounce to the gate — hold it in a real stall.
  SELECT home_depot_id INTO v_odepot FROM vehicles WHERE id = p_vehicle_id;
  IF v_odepot IS NOT NULL
     AND (SELECT current_stall_id FROM vehicles WHERE id = p_vehicle_id) IS NULL THEN
    v_oh := ottoq_book_hold_stall(p_sim_run_id, v_odepot, p_vehicle_id,
                                  p_clock, p_clock + interval '30 minutes');
    IF COALESCE((v_oh->>'booked')::boolean, false) THEN
      SELECT b.stall_id INTO v_os FROM ottoq_stall_bookings b
       WHERE b.booking_id = (v_oh->>'booking_id')::uuid;
      IF v_os IS NOT NULL AND ottoq_reserve_stall(v_os, p_vehicle_id, p_clock, 1800) THEN
        v_reserved := true;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('vehicle_id', p_vehicle_id, 'depot_id', v_odepot,
    'target_soc', v_target, 'booked_stall_id', v_os, 'reserved', v_reserved,
    'stall_id', CASE WHEN v_reserved THEN v_os ELSE NULL END, 'hold', v_oh);
END
$function$

-- ===== ottoq_enact_space_assignment =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_enact_space_assignment(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_stall_type text, p_purpose text, p_clock timestamp with time zone, p_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_source text DEFAULT 'needs_card'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_cand RECORD; v_stall uuid; v_prev uuid; v_bkg uuid; v_until timestamptz; v_got boolean := false;
  v_pref uuid; v_honoured boolean := false;
  v_zones text[] := NULL;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_vehicle_id IS NULL
     OR p_stall_type IS NULL OR p_clock IS NULL THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'malformed');
  END IF;

  -- ══════════════════════ CHARGE-PATH FIREWALL ══════════════════════
  IF p_stall_type IN ('dcfc','l2') THEN
    RAISE WARNING 'ottoq_enact_space_assignment: REFUSED charge stall_type % (run=%, vehicle=%, source=%) - charging is section (3) only',
      p_stall_type, p_sim_run_id, p_vehicle_id, p_source;
    RETURN jsonb_build_object('assigned', false, 'reason', 'charge_path_firewall');
  END IF;

  -- ══════════════════ BUILD 3: INSPECTION IS ZONE-ADDRESSED ══════════════════
  -- The depot's 14 inspection stalls per depot are NOT distinguishable by stall_type:
  -- stall_kind='inspection' but stall_type='staging', identical to the 86 staging stalls.
  -- The ONLY discriminator in the schema is zone='arrival_inspection'. Without this the
  -- inspect purpose would scatter across ordinary staging and inspection capacity would
  -- stay unreachable -- which is exactly why 177 inspect legs never got a space.
  -- Scoped strictly to p_purpose='inspect': every other purpose keeps v_zones NULL and
  -- therefore behaves byte-for-byte as before.
  IF p_purpose = 'inspect' THEN
    v_zones := ARRAY['arrival_inspection'];
  END IF;

  v_until := GREATEST(COALESCE(p_until, p_clock + interval '30 minutes'), p_clock + interval '1 minute');

  -- ══ HONOUR THE FORWARD RESERVATION (only when it covers NOW) ══
  -- The forward calendar is only trustworthy if the reservation is what actually gets
  -- taken -- but only once its window has opened. `lower(b.during) <= p_clock` is the
  -- load-bearing clause: without it a vehicle can be admitted at 16:00 against a bay it
  -- does not hold until 18:40, which is a double-booking wearing a reservation's clothes.
  IF p_leg_id IS NOT NULL THEN
    SELECT b.stall_id INTO v_pref
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.leg_id     = p_leg_id
       AND b.vehicle_id = p_vehicle_id
       AND b.state IN ('held','active')
       AND lower(b.during) <= p_clock
       AND upper(b.during) >  p_clock
       AND s.depot_id   = p_depot_id
       AND s.stall_type::text = p_stall_type
       -- BUILD 3: an inspect reservation must be honoured only on an INSPECTION stall,
       -- otherwise the zone restriction above could be bypassed by a stale staging hold.
       AND (v_zones IS NULL OR s.zone = ANY (v_zones))
       AND s.status NOT IN ('maintenance','closed')
     ORDER BY b.booked_at DESC LIMIT 1;

    IF v_pref IS NOT NULL AND public.ottoq_reserve_stall(v_pref, p_vehicle_id, p_clock, 900) THEN
      v_stall := v_pref; v_got := true; v_honoured := true;
    END IF;
  END IF;

  -- CHOOSE. ONE search. A candidate must be BOTH calendar-free for the window
  -- (ottoq_stall_free_between) AND physically free (the ottoq_reserve_stall CAS).
  IF NOT v_got THEN
    FOR v_cand IN
      SELECT f.stall_id
        FROM ottoq.ottoq_stall_free_between(
               p_sim_run_id, p_depot_id, p_clock, v_until, p_stall_type, NULL, 10, v_zones) f
    LOOP
      IF public.ottoq_reserve_stall(v_cand.stall_id, p_vehicle_id, p_clock, 900) THEN
        v_stall := v_cand.stall_id; v_got := true; EXIT;
      END IF;
    END LOOP;
  END IF;

  IF NOT v_got THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'no_free_space',
                              'stall_type', p_stall_type, 'purpose', p_purpose);
  END IF;

  -- RELEASE what the vehicle is vacating.
  SELECT v.current_stall_id INTO v_prev FROM public.vehicles v WHERE v.id = p_vehicle_id;

  IF v_prev IS NOT NULL AND v_prev <> v_stall THEN
    UPDATE public.ottoq_stall_bookings
       SET state = 'done', released_at = p_clock, release_reason = 'vehicle_moved_to_next_leg',
           during = tstzrange(lower(during),
                              GREATEST(lower(during) + interval '1 second',
                                       LEAST(upper(during), p_clock)), '[)')
     WHERE sim_run_id = p_sim_run_id AND stall_id = v_prev
       AND vehicle_id = p_vehicle_id AND state IN ('held','active');
  END IF;

  -- OCCUPY.
  UPDATE public.vehicles SET current_stall_id = v_stall WHERE id = p_vehicle_id;
  UPDATE public.stalls SET current_vehicle_id = p_vehicle_id, status = 'occupied' WHERE id = v_stall;

  -- CALENDAR — the P0 atomic path, same transaction, against the EXACT stall taken.
  v_bkg := ottoq.ottoq_record_enacted_booking(
             p_sim_run_id, v_stall, p_vehicle_id, p_clock,
             p_leg_id, p_clock, v_until, p_purpose, p_source);

  IF v_bkg IS NOT NULL AND p_leg_id IS NOT NULL THEN
    UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stall
     WHERE leg_id = p_leg_id AND status = 'planned';
  END IF;

  RETURN jsonb_build_object('assigned', true, 'stall_id', v_stall, 'booking_id', v_bkg,
                            'booked', v_bkg IS NOT NULL, 'purpose', p_purpose,
                            'stall_type', p_stall_type, 'until', v_until,
                            'released_stall_id', v_prev, 'source', p_source,
                            'leg_id', p_leg_id, 'honoured_reservation', v_honoured);

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_enact_space_assignment: FAILED sqlstate=% msg=% run=% vehicle=% type=% purpose=% source=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_vehicle_id, p_stall_type, p_purpose, p_source;
  RETURN jsonb_build_object('assigned', false, 'reason', 'exception', 'sqlstate', SQLSTATE);
END
$function$

-- ===== ottoq_find_and_book_stall =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_find_and_book_stall(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_purpose text, p_from timestamp with time zone, p_to timestamp with time zone, p_stall_type text DEFAULT NULL::text, p_staging_role text DEFAULT NULL::text, p_visit_id uuid DEFAULT NULL::uuid, p_leg_id uuid DEFAULT NULL::uuid, p_booked_by text DEFAULT 'otto_q'::text, p_zones text[] DEFAULT NULL::text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_cand RECORD; v_booking uuid;
BEGIN
  FOR v_cand IN
    SELECT f.stall_id FROM ottoq.ottoq_stall_free_between(
      p_sim_run_id, p_depot_id, p_from, p_to,
      p_stall_type, p_staging_role, 25, p_zones) f
  LOOP
    v_booking := ottoq.ottoq_book_stall(
      p_sim_run_id, v_cand.stall_id, p_vehicle_id, p_purpose,
      p_from, p_to, p_visit_id, p_leg_id, p_booked_by);
    IF v_booking IS NOT NULL THEN RETURN v_booking; END IF;
  END LOOP;
  RETURN NULL;
END
$function$

-- ===== ottoq_is_bay_purpose =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_is_bay_purpose(p_purpose text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  -- The purposes whose completion is defined by TIME IN THE BAY.
  -- Charging is deliberately EXCLUDED: a charge that ends early ended because the vehicle
  -- reached target SoC -- that is a COMPLETE charge, not an interruption. Charge
  -- completeness is an SoC question, not a duration question.
  -- staging / temp_hold / perimeter_hold are parking, not work.
  SELECT COALESCE(p_purpose,'') = ANY (ARRAY['wash','detail','service','inspect']);
$function$

-- ===== ottoq_is_work_purpose =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_is_work_purpose(p_purpose text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  -- Parking a car is not servicing a car. temp_hold, staging and perimeter_hold are all
  -- places a vehicle WAITS; none of them discharge a need on the visit card.
  SELECT COALESCE(p_purpose,'') <> ALL (ARRAY['temp_hold','staging','perimeter_hold']);
$function$

-- ===== ottoq_link_bookings_to_decisions =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_link_bookings_to_decisions(p_sim_run_id uuid, p_tick bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_exact int := 0; v_same int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_tick IS NULL THEN RETURN 0; END IF;

  -- (1) EXACT: the decision names the booking it caused.
  WITH d AS (
    SELECT decision_id, (enacted_action->>'booking_id')::uuid AS bkg
      FROM public.ottoq_decisions
     WHERE sim_run_id = p_sim_run_id AND tick_seq = p_tick
       AND outcome_status = 'enacted'
       AND enacted_action ? 'booking_id'
       AND NULLIF(enacted_action->>'booking_id','') IS NOT NULL
  ), u AS (
    UPDATE public.ottoq_stall_bookings b
       SET decision_id = d.decision_id, decision_link = 'exact_booking_id'
      FROM d
     WHERE b.booking_id = d.bkg AND b.sim_run_id = p_sim_run_id AND b.decision_id IS NULL
    RETURNING 1)
  SELECT count(*) INTO v_exact FROM u;

  -- (2) SAME TICK + SAME VEHICLE + SAME STALL. Exact within a tick: a vehicle holds one
  -- stall at a time, so an enacted decision from this tick naming this vehicle AND this
  -- stall IS the decision that placed it. Deterministic pick if several qualify.
  WITH u AS (
    UPDATE public.ottoq_stall_bookings b
       SET decision_id = (
             SELECT d.decision_id FROM public.ottoq_decisions d
              WHERE d.sim_run_id = p_sim_run_id AND d.tick_seq = p_tick
                AND d.outcome_status = 'enacted'
                AND d.entity_id = b.vehicle_id
                AND NULLIF(d.enacted_action->>'stall_id','')::uuid = b.stall_id
              ORDER BY d.decision_id LIMIT 1),
           decision_link = 'same_tick_vehicle_stall'
     WHERE b.sim_run_id = p_sim_run_id
       AND b.decision_id IS NULL
       AND b.booked_by = 'otto_q_enacted'
       AND EXISTS (
             SELECT 1 FROM public.ottoq_decisions d
              WHERE d.sim_run_id = p_sim_run_id AND d.tick_seq = p_tick
                AND d.outcome_status = 'enacted'
                AND d.entity_id = b.vehicle_id
                AND NULLIF(d.enacted_action->>'stall_id','')::uuid = b.stall_id)
    RETURNING 1)
  SELECT count(*) INTO v_same FROM u;

  RETURN v_exact + v_same;
EXCEPTION WHEN OTHERS THEN
  -- NO-ABORT GUARANTEE: provenance bookkeeping must never take ottoq_decide_tick down.
  RAISE WARNING 'ottoq_link_bookings_to_decisions: FAILED sqlstate=% msg=% run=% tick=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_tick;
  RETURN 0;
END
$function$

-- ===== ottoq_place_unplaced_vehicles =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_place_unplaced_vehicles(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone, p_max integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD; v_disp jsonb; v_hold jsonb; v_stall uuid;
  v_from timestamptz; v_until timestamptz;
  v_placed int := 0; v_failed int := 0; v_workflows int := 0; v_wf jsonb;
BEGIN
  FOR v_rec IN
    SELECT v.id, v.current_state::text AS st
      FROM public.vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.category = 'autonomous'
       AND v.current_stall_id IS NULL
       AND v.current_state::text IN (
             'arrived_at_gate','staged_awaiting_service','staged_for_departure',
             'charge_complete_holding','service_complete_holding')
     ORDER BY v.id
     LIMIT GREATEST(p_max, 1)
  LOOP
    v_disp := ottoq.ottoq_arrival_disposition(p_sim_run_id, p_depot_id, v_rec.id, p_clock);

    -- A 'redeploy' verdict for a vehicle still physically here means "ready, waiting
    -- for a slot". Hold it briefly rather than leaving it nowhere.
    IF (v_disp->>'action') = 'redeploy' THEN
      v_from  := p_clock;
      v_until := p_clock + interval '20 minutes';
    ELSE
      v_from  := COALESCE((v_disp->>'stage_from')::timestamptz, p_clock);
      v_until := COALESCE((v_disp->>'stage_until')::timestamptz, p_clock + interval '30 minutes');
    END IF;

    v_hold := ottoq.ottoq_book_hold_stall(p_sim_run_id, p_depot_id, v_rec.id, v_from, v_until);

    IF COALESCE((v_hold->>'booked')::boolean, false) THEN
      SELECT b.stall_id INTO v_stall FROM public.ottoq_stall_bookings b
       WHERE b.booking_id = (v_hold->>'booking_id')::uuid;
      IF v_stall IS NOT NULL
         AND public.ottoq_reserve_stall(v_stall, v_rec.id, p_clock, 1800) THEN
        -- keep departure intent intact; only give it somewhere to be
        UPDATE public.vehicles
           SET current_stall_id = v_stall, last_state_change = p_clock
         WHERE id = v_rec.id;
        UPDATE public.stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
         WHERE id = v_stall;
        v_placed := v_placed + 1;
      ELSE
        v_failed := v_failed + 1;
      END IF;
    ELSE
      v_failed := v_failed + 1;
    END IF;
  END LOOP;

  FOR v_rec IN
    SELECT DISTINCT l.vehicle_id AS id
      FROM public.ottoq_itinerary_legs l
      JOIN public.vehicles v ON v.id = l.vehicle_id
     WHERE l.sim_run_id = p_sim_run_id
       AND l.status = 'planned'
       AND l.to_stall_id IS NULL
       AND l.planned_end_sim > p_clock
       AND v.home_depot_id = p_depot_id
     LIMIT GREATEST(p_max, 1)
  LOOP
    BEGIN
      v_wf := ottoq.ottoq_book_workflow(p_sim_run_id, v_rec.id, p_depot_id, p_clock);
      v_workflows := v_workflows + COALESCE((v_wf->>'booked')::int, 0);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  RETURN jsonb_build_object('placed', v_placed, 'unplaceable', v_failed,
                            'workflow_legs_booked', v_workflows);
END
$function$

-- ===== ottoq_plan_dispatch_tick =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_plan_dispatch_tick(p_phase text, p_sim_run_id uuid, p_depot_id uuid, p_sim_clock_now timestamp with time zone, p_hour integer DEFAULT NULL::integer, p_seed bigint DEFAULT 0, p_to_dispatch integer DEFAULT 0, p_to_recall integer DEFAULT 0, p_holdout_pct integer DEFAULT 1, p_win_start integer DEFAULT 22, p_win_end integer DEFAULT 3, p_tick_minutes_actual numeric DEFAULT 30, p_vehicles jsonb DEFAULT '[]'::jsonb, p_forced boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_release_cap int; v_forced boolean;
  v_release jsonb := '[]'::jsonb; v_hold jsonb := '[]'::jsonb; v_secured jsonb := '[]'::jsonb;
  v_released int := 0; v_valved int := 0;
  v_vehicle RECORD; v_rc RECORD;
  v_free_intake int; v_cap int; v_book jsonb; v_eta numeric;
BEGIN
  IF p_phase = 'deploy_plan' THEN
    v_release_cap := GREATEST(1, ottoq_policy_get(p_sim_run_id,'deploy_release_per_tick_cap', 6)::int);
    v_forced      := ottoq_policy_get(p_sim_run_id,'rush_valve_forced', 0) > 0;
    IF v_forced THEN v_release_cap := GREATEST(1, v_release_cap / 2); END IF;

    IF COALESCE(p_to_dispatch, 0) > 0 THEN
      FOR v_vehicle IN
        SELECT v.id FROM vehicles v
         WHERE v.category = 'autonomous' AND v.home_depot_id = p_depot_id AND v.current_soc >= 80
           AND ( v.current_state = 'en_route_to_deployment'
              OR v.current_state = 'staged_for_departure'
              OR (v.current_state = 'staged_awaiting_service' AND COALESCE(v.config->>'svc_step','ready') IN ('ready'))
              OR (v.current_state = 'offline'))
           AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
              WHERE d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning'))
           AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open','in_progress')
                AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                             WHERE COALESCE((a->>'must_do')::boolean, false) = true AND a->>'svc' <> 'readiness_check'
                               AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')))
         ORDER BY ottoq_brain_deploy_rank(p_sim_run_id, v.id) ASC NULLS LAST,
                  v.current_soc DESC, ottoq_sim_seeded_random(p_seed, 'pick:' || v.id::text)
         LIMIT p_to_dispatch
      LOOP
        IF v_released < v_release_cap THEN
          v_release  := v_release || to_jsonb(v_vehicle.id); v_released := v_released + 1;
        ELSIF v_valved < v_release_cap THEN
          v_hold := v_hold || to_jsonb(v_vehicle.id); v_valved := v_valved + 1;
        ELSE
          EXIT;
        END IF;
      END LOOP;
    END IF;

    RETURN jsonb_build_object('phase','deploy_plan','release',v_release,'hold',v_hold,
                              'cap',v_release_cap,'forced',v_forced);

  ELSIF p_phase = 'deploy_hold' THEN
    FOR v_vehicle IN
      SELECT t.value::uuid AS id
        FROM jsonb_array_elements_text(COALESCE(p_vehicles,'[]'::jsonb)) WITH ORDINALITY AS t(value, ord)
       ORDER BY t.ord
    LOOP
      BEGIN
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, p_depot_id, v_vehicle.id, 'stage',
          jsonb_build_object('reason','rush_valve_hold','held_at',p_sim_clock_now,
                             'release_expected','next_dispatch_window','forced_by_technician',p_forced),
          p_sim_clock_now);
        PERFORM ottoq_comms_send_command(p_sim_run_id, v_vehicle.id, 'stage',
          jsonb_build_object('reason','rush_valve_hold','release_expected','next_dispatch_window'),
          p_sim_clock_now, false);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      v_valved := v_valved + 1;
    END LOOP;

    RETURN jsonb_build_object('phase','deploy_hold','held',v_valved);

  ELSIF p_phase = 'recall' THEN
    SELECT count(*) INTO v_free_intake FROM stalls s
      WHERE s.depot_id = p_depot_id AND s.current_vehicle_id IS NULL
        AND (s.reserved_by IS NULL OR COALESCE(s.reservation_expires_at, p_sim_clock_now) <= p_sim_clock_now)
        AND s.stall_type IN ('dcfc','l2','staging');

    v_cap := LEAST(p_to_recall, GREATEST(0, v_free_intake),
                   GREATEST(1, CEIL(
                     ottoq_policy_get(p_sim_run_id,'overnight_recall_max_per_tick',24)
                     * COALESCE(p_tick_minutes_actual, 30) / 30.0))::int);

    FOR v_rc IN
      SELECT v.id AS vehicle_id, v.current_soc, d.dispatch_id
        FROM vehicles v
        JOIN ottoq_vehicle_dispatches d
          ON d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status = 'active'
       WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
         AND v.current_state = 'deployed'
         AND ((p_hour >= p_win_end AND p_hour < p_win_start)
              OR NOT ottoq_is_overnight_holdout(v.id, p_sim_run_id, p_sim_clock_now, p_holdout_pct))
         AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                          WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id
                            AND vn.status IN ('open','in_progress'))
       ORDER BY v.current_soc ASC, v.id
       LIMIT GREATEST(0, v_cap)
    LOOP
      v_eta := ottoq_return_eta_minutes(v_rc.vehicle_id, p_depot_id, p_sim_run_id);
      BEGIN
        v_book := ottoq_book_appointment(v_rc.vehicle_id, p_sim_run_id, p_sim_clock_now,
                  'surplus_to_demand', 'overnight_hold', true, v_eta, v_rc.current_soc, p_depot_id);
      EXCEPTION WHEN OTHERS THEN v_book := jsonb_build_object('secured', false, 'reason', 'booking_error');
      END;
      -- LIVE-FAITHFUL GATE: an unsecured booking is skipped entirely, so the twin
      -- never flips a vehicle to en_route_to_depot without a reserved stall.
      IF COALESCE((v_book->>'secured')::boolean, false) THEN
        v_secured := v_secured || jsonb_build_array(jsonb_build_object(
                       'vehicle_id', v_rc.vehicle_id, 'dispatch_id', v_rc.dispatch_id,
                       'soc_at_decision', v_rc.current_soc, 'eta_minutes', v_eta,
                       'appointment', v_book));
      END IF;
    END LOOP;

    RETURN jsonb_build_object('phase','recall','secured',v_secured,
                              'cap',COALESCE(v_cap,0),'free_intake',COALESCE(v_free_intake,0));
  END IF;

  RETURN jsonb_build_object('phase', p_phase, 'error', 'unknown_phase');
END;
$function$

-- ===== ottoq_plan_opportunistic_charges =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_plan_opportunistic_charges(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone, p_seed bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_plan jsonb; v_thresh numeric; v_expiry_min numeric;
  v_free_chargers int; v_gate_needy int; v_forecast numeric;
  v_rec RECORD; v_n int := 0;
BEGIN
  IF p_depot_id IS NULL THEN
    RETURN jsonb_build_object('raised', 0, 'reason', 'no_depot');
  END IF;

  v_plan := ottoq_feed_plan('service_manifest');
  v_thresh := COALESCE((v_plan->>'opportunistic_charge_threshold_soc')::numeric, 60);
  v_expiry_min := COALESCE((v_plan->>'opportunistic_expiry_min')::numeric, 35);

  SELECT count(*) INTO v_free_chargers FROM stalls s
    JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = p_depot_id AND s.stall_type IN ('dcfc','l2')
     AND s.current_vehicle_id IS NULL
     AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_clock)
     AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '35 minutes';
  SELECT count(*) INTO v_gate_needy FROM vehicles v
   WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
     AND v.current_state = 'arrived_at_gate'
     AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
            WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
            ORDER BY vn.created_at DESC LIMIT 1), 85);

  IF v_free_chargers - v_gate_needy > 0 THEN
    SELECT predicted_charge_kw INTO v_forecast FROM ottoq_predict_arrivals(p_depot_id, p_clock, p_sim_run_id, 60);
    FOR v_rec IN
      SELECT vn.visit_id, vn.vehicle_id, v.current_soc
        FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
       WHERE vn.depot_id = p_depot_id AND vn.status IN ('open','in_progress')
         AND vn.urgency <> 'immediate_dispatch'
         AND v.current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding')
         AND v.current_soc < v_thresh
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
         AND NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                          WHERE ap.vehicle_id = vn.vehicle_id AND ap.approval_type = 'opportunistic_charge'
                            AND (ap.status = 'pending' OR ap.visit_id = vn.visit_id))
       LIMIT GREATEST(0, v_free_chargers - v_gate_needy)
    LOOP
      INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, visit_id, sim_run_id, depot_id,
             payload, requested_at, decide_after, expires_at, priority)
      VALUES ('opportunistic_charge', v_rec.vehicle_id, v_rec.visit_id, p_sim_run_id, p_depot_id,
             jsonb_build_object('soc', v_rec.current_soc, 'threshold', v_thresh,
                                'forecast_charge_kw_60m', round(COALESCE(v_forecast,0),0)),
             p_clock,
             p_clock + ((2 + floor(ottoq_sim_seeded_random(p_seed, v_rec.vehicle_id::text || ':opDelay') * 3))::text || ' minutes')::interval,
             p_clock + (v_expiry_min::text || ' minutes')::interval,
             (CASE WHEN COALESCE(v_forecast,0) > 300 THEN 'high' ELSE 'normal' END));
      v_n := v_n + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('raised', v_n, 'free_chargers', v_free_chargers,
    'gate_needy', v_gate_needy, 'headroom', v_free_chargers - v_gate_needy,
    'threshold_soc', v_thresh, 'forecast_charge_kw_60m', round(COALESCE(v_forecast,0),0));
END
$function$

-- ===== ottoq_plan_overnight_drain_admissions =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_plan_overnight_drain_admissions(p_depot_id uuid, p_sim_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hour int; v_drain_cap int; v_draining int; v_admit int;
  v_rec RECORD; v_item jsonb; v_dur numeric;
  v_admissions jsonb := '[]'::jsonb;
BEGIN
  v_hour := EXTRACT(HOUR FROM (p_sim_clock AT TIME ZONE 'America/Chicago'))::int;
  v_drain_cap := ottoq_policy_get(p_sim_run_id,'overnight_drain_concurrency',3)::int;

  IF (v_hour >= 22 OR v_hour < 6) THEN
    -- headroom is intentionally counted AFTER the twin completed elapsed drains this
    -- tick, and intentionally has NO category filter (verbatim from the fused original).
    SELECT COUNT(*) INTO v_draining FROM vehicles
     WHERE home_depot_id = p_depot_id AND config->>'svc_step' = 'overnight_draining';
    v_admit := GREATEST(0, v_drain_cap - v_draining);

    IF v_admit > 0 THEN
      FOR v_rec IN
        SELECT id, config, (config->'deferred_services'->0) AS item FROM vehicles
         WHERE home_depot_id = p_depot_id AND category='autonomous'
           AND current_state = 'staged_for_departure'
           AND COALESCE(config->>'svc_step','ready') = 'ready'
           AND jsonb_array_length(COALESCE(config->'deferred_services','[]'::jsonb)) > 0
           AND NOT jsonb_exists(config, 'draining_item')
         ORDER BY jsonb_array_length(config->'deferred_services') DESC, last_state_change
         LIMIT v_admit
      LOOP
        v_item := v_rec.item;
        v_dur  := GREATEST(5, COALESCE((v_item->>'est_min')::numeric, 20));
        v_admissions := v_admissions || jsonb_build_array(
          jsonb_build_object('vehicle_id', v_rec.id, 'item', v_item, 'dur_min', v_dur));
      END LOOP;
    END IF;

    RETURN jsonb_build_object(
      'hour_cst', v_hour, 'window_open', true, 'drain_cap', v_drain_cap,
      'draining_now', v_draining, 'admit', v_admit, 'admissions', v_admissions);
  END IF;

  RETURN jsonb_build_object(
    'hour_cst', v_hour, 'window_open', false, 'drain_cap', v_drain_cap,
    'draining_now', NULL::int, 'admit', 0, 'admissions', '[]'::jsonb);
END;
$function$

-- ===== ottoq_react_to_refusals =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_react_to_refusals(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD; v_cand RECORD; v_n int := 0;
  v_stype text; v_purpose text; v_booking uuid; v_new_stall uuid; v_new_cmd uuid;
  v_outcome jsonb; v_zones text[];
BEGIN
  FOR v_rec IN
    SELECT command_id, vehicle_id, command_type, payload, reason_code, reason_detail
      FROM public.ottoq_vehicle_commands
     WHERE sim_run_id = p_sim_run_id AND status = 'refused' AND reacted_at IS NULL
     ORDER BY issued_at
     LIMIT 20
  LOOP
    v_new_cmd := NULL; v_new_stall := NULL; v_booking := NULL; v_outcome := NULL; v_zones := NULL;

    IF v_rec.reason_code IN ('target_occupied','resource_faulted')
       AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
      v_stype := COALESCE(v_rec.payload->>'stall_type',
                   CASE WHEN v_rec.command_type = 'stage' THEN 'staging' ELSE 'dcfc' END);
      v_purpose := CASE v_stype WHEN 'dcfc' THEN 'charge_dcfc'
                                WHEN 'l2'   THEN 'charge_l2'
                                ELSE 'temp_hold' END;

      -- A rerouted PARKING hold must not take inspection capacity. Charge reroutes are
      -- unaffected (dcfc/l2 stalls are not in the arrival_inspection zone).
      IF v_stype = 'staging' THEN
        SELECT array_agg(DISTINCT s.zone) INTO v_zones
          FROM public.stalls s
         WHERE s.depot_id = p_depot_id
           AND s.stall_type::text = 'staging'
           AND s.zone <> 'arrival_inspection';
      END IF;

      -- reserve-first walk (the legacy pointer is the scarcer gate)
      FOR v_cand IN
        SELECT f.stall_id FROM ottoq.ottoq_stall_free_between(
          p_sim_run_id, p_depot_id, p_clock, p_clock + interval '60 minutes',
          v_stype, NULL, 25, v_zones) f
      LOOP
        IF ottoq_reserve_stall(v_cand.stall_id, v_rec.vehicle_id, p_clock, 3600) THEN
          v_booking := ottoq.ottoq_book_stall(
            p_sim_run_id, v_cand.stall_id, v_rec.vehicle_id, v_purpose,
            p_clock, p_clock + interval '60 minutes', NULL, NULL, 'otto_q_reaction');
          v_new_stall := v_cand.stall_id;
          EXIT;
        END IF;
      END LOOP;

      -- LAST RESORT for parking only: never strand a refused vehicle. Reached solely when
      -- every non-inspection staging stall is unavailable for the window.
      IF v_new_stall IS NULL AND v_stype = 'staging' AND v_zones IS NOT NULL THEN
        FOR v_cand IN
          SELECT f.stall_id FROM ottoq.ottoq_stall_free_between(
            p_sim_run_id, p_depot_id, p_clock, p_clock + interval '60 minutes',
            v_stype, NULL, 25, ARRAY['arrival_inspection']) f
        LOOP
          IF ottoq_reserve_stall(v_cand.stall_id, v_rec.vehicle_id, p_clock, 3600) THEN
            v_booking := ottoq.ottoq_book_stall(
              p_sim_run_id, v_cand.stall_id, v_rec.vehicle_id, v_purpose,
              p_clock, p_clock + interval '60 minutes', NULL, NULL, 'otto_q_reaction_last_resort');
            v_new_stall := v_cand.stall_id;
            EXIT;
          END IF;
        END LOOP;
      END IF;

      IF v_new_stall IS NOT NULL THEN
        v_new_cmd := ottoq.ottoq_emit_vehicle_command(
          p_sim_run_id, p_depot_id, v_rec.vehicle_id, v_rec.command_type,
          (v_rec.payload - 'apply_required')
            || jsonb_build_object('stall_id', v_new_stall, 'stall_type', v_stype,
                 'apply_required', true, 'reroute_after', v_rec.command_id,
                 'reroute_reason', v_rec.reason_code),
          p_clock);
        v_outcome := jsonb_build_object('action','rerouted','new_command_id',v_new_cmd,
                                        'new_stall_id',v_new_stall,'booking_id',v_booking);
      ELSE
        v_outcome := jsonb_build_object('action','escalated','reason','no_capacity');
        BEGIN
          PERFORM ottoq_record_event(
            p_actor_type:='ottoq_engine', p_actor_id:='refusal_reactor',
            p_event_type:='ottoq.refusal_escalated', p_entity_type:='vehicle',
            p_entity_id:=v_rec.vehicle_id, p_depot_id:=p_depot_id,
            p_payload:=jsonb_build_object('command_id',v_rec.command_id,
              'reason_code','no_capacity','original_refusal',v_rec.reason_code),
            p_severity:='warning', p_ingest_source:='production', p_data_source:='production',
            p_sim_run_id:=p_sim_run_id);
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

    ELSE
      v_outcome := jsonb_build_object('action','escalated','reason',v_rec.reason_code);
      BEGIN
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='refusal_reactor',
          p_event_type:='ottoq.refusal_escalated', p_entity_type:='vehicle',
          p_entity_id:=v_rec.vehicle_id, p_depot_id:=p_depot_id,
          p_payload:=jsonb_build_object('command_id',v_rec.command_id,
            'reason_code',v_rec.reason_code,'reason_detail',v_rec.reason_detail),
          p_severity:=CASE WHEN v_rec.reason_code='vehicle_unresponsive' THEN 'warning' ELSE 'info' END,
          p_ingest_source:='production', p_data_source:='production', p_sim_run_id:=p_sim_run_id);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    UPDATE public.ottoq_vehicle_commands
       SET reacted_at = p_clock,
           payload = payload || jsonb_build_object('reaction', v_outcome)
     WHERE command_id = v_rec.command_id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $function$

-- ===== ottoq_readmit_reopened_needs =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_readmit_reopened_needs(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD;
  v_n int := 0; v_escalated int := 0;
  v_max int; v_dwell numeric; v_attempts int;
  v_legs int := 0; v_planned int := 0;
  v_svc_step text; v_needs_charge boolean;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id,'reopened_need_readmit_enabled',1),1) < 1
    THEN RETURN 0; END IF;

  -- SAME cap as the old path. Never hit in cert (max observed 2); a need that cannot be
  -- placed ESCALATES TO A FLAG, it never loops.
  v_max   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'visit_readmit_max_attempts',3),3)::int, 0);
  -- SIM-DOMAIN dwell. exception.flagged_at lives inside config jsonb, so unlike
  -- last_state_change it is NOT clobbered by the BEFORE UPDATE trigger. Verified sim-domain
  -- on live data: range 13:38-16:29 against a sim clock of 13:30-16:29.
  v_dwell := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'reopened_need_dwell_min',5),5), 0);

  FOR v_rec IN
    SELECT vh.id, vh.fleet_operator_id, vh.current_state::text AS vstate,
           COALESCE(vh.config,'{}'::jsonb) AS config, vn.visit_id, vn.atoms
      FROM vehicles vh
      JOIN LATERAL (
        SELECT n.visit_id, n.atoms
          FROM public.ottoq_visit_needs n
         WHERE n.vehicle_id = vh.id
           AND n.status = 'open'
           AND n.meta ? 'reopen'                       -- proves this visit was cut short
           AND (n.sim_run_id = p_sim_run_id OR n.sim_run_id IS NULL)
           AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a
                        WHERE lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'))
         ORDER BY n.created_at DESC LIMIT 1
      ) vn ON true
     WHERE vh.home_depot_id = p_depot_id
       AND vh.category = 'autonomous'
       -- the post-fault HOLDING states. Structurally cannot pick up a vehicle that is
       -- charging, washing or being serviced, so it can never re-route work in progress.
       AND vh.current_state IN ('tow_requested','emergency_staged')
       -- the fault must be CLEARED. Same set tow retrieval itself accepts.
       AND COALESCE(vh.config->'exception'->>'status','')
             IN ('auto_staged','technician_approved','retrieved_staged')
       -- a car that cannot drive cannot be sent to a plug.
       AND COALESCE((vh.config->'exception'->>'immobilizing')::boolean, false) = false
       AND COALESCE((vh.config->'exception'->>'flagged_at')::timestamptz, p_clock)
             <= p_clock - make_interval(mins => v_dwell::int)
       -- HUMAN DECISION OUTSTANDING => never move it.
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_ops_approvals ap
                        WHERE ap.vehicle_id = vh.id
                          AND ap.status = 'pending'
                          AND ap.approval_type IN ('indepot_reassign','tech_greenlight'))
     -- oldest interruption first: the work that has waited longest resumes first.
     ORDER BY COALESCE((vh.config->'exception'->>'flagged_at')::timestamptz, p_clock)
     LIMIT 40
  LOOP
    v_attempts := COALESCE((v_rec.config->'exception'->>'readmit_attempts')::int, 0);

    -- THRASH BOUND: at the cap, FLAG. Never loop.
    IF v_attempts >= v_max THEN
      UPDATE vehicles
         SET config = jsonb_set(jsonb_set(COALESCE(config,'{}'::jsonb),
                        '{exception,status}',            to_jsonb('resume_escalated'::text)),
                        '{exception,resume_escalated_at}', to_jsonb(p_clock))
       WHERE id = v_rec.id;
      v_escalated := v_escalated + 1;
      CONTINUE;
    END IF;

    -- (a) DROP STALE HOLDS. An eviction can leave the vehicle named on the stall it was
    --     thrown out of, which silently withholds a space from the yard.
    UPDATE stalls s
       SET reserved_by = NULL, reservation_expires_at = NULL
     WHERE s.depot_id = p_depot_id AND s.reserved_by = v_rec.id;

    -- (b) THE LEG GOES BACK TO 'planned'. Both enactment cursors draw status='planned'.
    --     Scoped strictly to legs whose OWN booking was interrupted.
    UPDATE public.ottoq_itinerary_legs l
       SET status            = 'planned',
           to_stall_id       = NULL,
           actual_start_sim  = NULL,
           actual_end_sim    = NULL,
           planned_start_sim = p_clock,
           planned_end_sim   = p_clock + make_interval(secs => GREATEST(COALESCE(l.planned_duration_s,900),300)),
           duration_basis    = COALESCE(l.duration_basis,'{}'::jsonb)
                               || jsonb_build_object('replanned_from','interrupted',
                                                     'replanned_at', p_clock,
                                                     'replan_reason','atomic_visit_resume')
     WHERE l.sim_run_id = p_sim_run_id
       AND l.vehicle_id = v_rec.id
       AND l.status = 'active'
       AND l.actual_end_sim IS NULL
       AND EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                    WHERE b.leg_id = l.leg_id AND b.state = 'interrupted');
    GET DIAGNOSTICS v_legs = ROW_COUNT;

    v_needs_charge := EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(v_rec.atoms,'[]'::jsonb)) a
       WHERE a->>'svc' = 'charge'
         AND lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'));
    v_svc_step := CASE WHEN v_needs_charge THEN 'need_charge' ELSE 'need_service' END;

    -- (c) RE-ADMIT to the HOLDING state the intake cursors already read. No space is
    --     claimed here on purpose -- see the header.
    UPDATE vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state,
           last_state_change = p_clock,
           config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(COALESCE(config,'{}'::jsonb),
                      '{exception,status}',           to_jsonb('readmitted_resume'::text)),
                      '{exception,readmit_attempts}', to_jsonb(v_attempts + 1)),
                      '{exception,readmitted_at}',    to_jsonb(p_clock)),
                      '{svc_step}',                   to_jsonb(v_svc_step))
     WHERE id = v_rec.id;

    -- (d) NO REVIVABLE LEG -> BUILD ONE from the open needs row.
    IF v_legs = 0 THEN
      BEGIN
        v_planned := COALESCE(public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.id, p_clock), 0);
      EXCEPTION WHEN OTHERS THEN
        v_planned := 0;
        RAISE WARNING 'reopened-need re-plan failed for %: % %', v_rec.id, SQLSTATE, SQLERRM;
      END;
    END IF;

    v_n := v_n + 1;
  END LOOP;

  -- ONE summary event per tick (event-write amplification is the known tick-cost driver).
  IF v_n > 0 OR v_escalated > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'readmit_reopened_needs',
        p_event_type := 'ottoq.reopened_need_readmitted',
        p_entity_type := 'depot', p_entity_id := p_depot_id, p_depot_id := p_depot_id,
        p_payload := jsonb_build_object('readmitted', v_n, 'escalated', v_escalated,
                      'max_attempts', v_max, 'dwell_min', v_dwell,
                      'doctrine','reopened_need_is_first_class_demand',
                      'gate','resumption_is_not_reroute_no_tech_approval_required'),
        p_severity := CASE WHEN v_escalated > 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'reopened_need_readmitted summary event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- never allowed to abort ottoq_decide_tick (the leg_type-abort lesson of 2026-08-01).
  RAISE WARNING 'ottoq_readmit_reopened_needs FAILED: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$

-- ===== ottoq_readmit_resumed_visits =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_readmit_resumed_visits(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD; v_n int := 0; v_max int; v_attempts int;
  v_legs int := 0; v_planned int := 0; v_svc_step text; v_needs_charge boolean;
BEGIN
  IF p_depot_id IS NULL THEN RETURN 0; END IF;
  v_max := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'visit_readmit_max_attempts',3)::int, 3), 0);

  FOR v_rec IN
    SELECT vh.id, vh.fleet_operator_id, vh.current_stall_id,
           COALESCE(vh.config,'{}'::jsonb) AS config,
           vn.visit_id, vn.atoms
      FROM vehicles vh
      JOIN LATERAL (
        SELECT n.visit_id, n.atoms
          FROM public.ottoq_visit_needs n
         WHERE n.vehicle_id = vh.id
           AND n.status = 'open'
           AND n.meta ? 'reopen'                      -- proves this visit was actually cut short
           AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a
                        WHERE lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'))
         ORDER BY n.created_at DESC LIMIT 1
      ) vn ON true
     WHERE vh.home_depot_id = p_depot_id
       AND vh.category = 'autonomous'
       AND vh.current_state = 'emergency_staged'
       AND COALESCE(vh.config->'exception'->>'status','') = 'retrieved_staged'
       -- IN-DEPOT REASSIGNMENT GATE: never move a vehicle whose human decision is outstanding.
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_ops_approvals ap
                        WHERE ap.vehicle_id = vh.id
                          AND ap.status = 'pending'
                          AND ap.approval_type IN ('indepot_reassign','tech_greenlight'))
  LOOP
    v_attempts := COALESCE((v_rec.config->'exception'->>'readmit_attempts')::int, 0);

    -- ── THRASH BOUND: at the cap, FLAG. Never loop. ──────────────────────────────────────
    IF v_attempts >= v_max THEN
      UPDATE vehicles
         SET config = jsonb_set(jsonb_set(COALESCE(config,'{}'::jsonb),
                        '{exception,status}', to_jsonb('resume_escalated'::text)),
                        '{exception,resume_escalated_at}', to_jsonb(p_clock))
       WHERE id = v_rec.id;
      BEGIN
        PERFORM public.ottoq_record_event(
          p_actor_type := 'ottoq_engine', p_actor_id := 'readmit_resumed_visits',
          p_event_type := 'ottoq.replan_escalated',
          p_entity_type := 'vehicle', p_entity_id := v_rec.id,
          p_fleet_operator_id := v_rec.fleet_operator_id, p_depot_id := p_depot_id,
          p_payload := jsonb_build_object('visit_id', v_rec.visit_id, 'attempts', v_attempts,
                        'max_attempts', v_max, 'reason','readmit_cap_reached',
                        'doctrine','bounded_replan_then_flag'),
          p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
          p_sim_run_id := p_sim_run_id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'readmit escalation stamp dropped: % %', SQLSTATE, SQLERRM;
      END;
      CONTINUE;
    END IF;

    -- ── (a) DROP STALE HOLDS. An eviction can leave the vehicle named on the stall it was
    --        thrown out of. Left in place that stall keeps the vehicle in ZONE C via
    --        ottoq_approach_band.c_hardware, and it silently withholds a space from the yard.
    UPDATE stalls s
       SET reserved_by = NULL, reservation_expires_at = NULL
     WHERE s.depot_id = p_depot_id
       AND s.reserved_by = v_rec.id
       AND s.id IS DISTINCT FROM v_rec.current_stall_id;

    -- ── (b) THE LEG GOES BACK TO 'planned'. 48 of the 52 measured interruptions left their
    --        leg stranded at status='active', and BOTH enactment cursors draw
    --        status='planned' AND to_stall_id IS NULL AND planned_end_sim > clock. Scoped
    --        strictly to legs whose OWN booking was interrupted, so nothing else moves.
    UPDATE public.ottoq_itinerary_legs l
       SET status            = 'planned',
           to_stall_id       = NULL,
           actual_start_sim  = NULL,
           actual_end_sim    = NULL,
           planned_start_sim = p_clock,
           planned_end_sim   = p_clock + make_interval(secs => GREATEST(COALESCE(l.planned_duration_s,900), 300)),
           duration_basis    = COALESCE(l.duration_basis,'{}'::jsonb)
                               || jsonb_build_object('replanned_from','interrupted',
                                                     'replanned_at', p_clock,
                                                     'replan_reason','atomic_visit_resume')
     WHERE l.sim_run_id = p_sim_run_id
       AND l.vehicle_id = v_rec.id
       AND l.status = 'active'
       AND l.actual_end_sim IS NULL
       AND EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                    WHERE b.leg_id = l.leg_id AND b.state = 'interrupted');
    GET DIAGNOSTICS v_legs = ROW_COUNT;

    v_needs_charge := EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(v_rec.atoms,'[]'::jsonb)) a
       WHERE a->>'svc' = 'charge'
         AND lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'));
    v_svc_step := CASE WHEN v_needs_charge THEN 'need_charge' ELSE 'need_service' END;

    -- ── (c) RE-ADMIT. The twin owns vehicle state; OTTO-Q is not mutating it here.
    UPDATE vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state,
           last_state_change = p_clock,
           config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(COALESCE(config,'{}'::jsonb),
                      '{exception,status}',           to_jsonb('readmitted_resume'::text)),
                      '{exception,readmit_attempts}', to_jsonb(v_attempts + 1)),
                      '{exception,readmitted_at}',    to_jsonb(p_clock)),
                      '{svc_step}',                   to_jsonb(v_svc_step))
     WHERE id = v_rec.id;

    -- ── (d) NO REVIVABLE LEG -> BUILD ONE. ottoq_plan_visit_itinerary reads the open needs
    --        row and emits fresh 'planned' legs for every atom that is not done/cancelled.
    --        It early-returns when a planned leg already exists, so calling it after (b)
    --        would be a no-op anyway; gated for clarity and to avoid duplicate legs.
    IF v_legs = 0 THEN
      BEGIN
        v_planned := COALESCE(public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.id, p_clock), 0);
      EXCEPTION WHEN OTHERS THEN
        v_planned := 0;
        RAISE WARNING 'resume re-plan failed for %: % %', v_rec.id, SQLSTATE, SQLERRM;
      END;
    ELSE
      v_planned := 0;
    END IF;

    v_n := v_n + 1;
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'readmit_resumed_visits',
        p_event_type := 'ottoq.visit_resume_readmitted',
        p_entity_type := 'vehicle', p_entity_id := v_rec.id,
        p_fleet_operator_id := v_rec.fleet_operator_id, p_depot_id := p_depot_id,
        p_payload := jsonb_build_object(
          'visit_id', v_rec.visit_id,
          'from_state','emergency_staged', 'to_state','staged_awaiting_service',
          'legs_replanned', v_legs, 'legs_created', v_planned,
          'needs_charge', v_needs_charge, 'svc_step', v_svc_step,
          'readmit_attempts', v_attempts + 1, 'max_attempts', v_max,
          'doctrine','atomic_visit_resume_not_reroute',
          'gate','indepot_reassignment_gate_untouched_no_pending_approval'),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'visit_resume_readmitted audit event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END LOOP;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- Never allowed to abort the twin tick (cf. the leg_type abort root cause).
  RAISE WARNING 'ottoq_readmit_resumed_visits FAILED: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$

-- ===== ottoq_reconcile_bay_reservations =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_reconcile_bay_reservations(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_taxi   numeric; v_max_defer int; v_horizon numeric;
  v_step   int := 10;      -- forward walk granularity when the new window collides
  v_maxsh  int := 240;     -- bounded walk budget per booking per tick
  v_b      RECORD;
  v_dur    interval; v_eta timestamptz; v_blk text; v_block_at timestamptz; v_try timestamptz;
  v_ok     boolean; v_shift int; v_seq int;
  v_def    int := 0; v_rel int := 0; v_moved int := 0;
  v_alt    RECORD; v_newstall uuid;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_reservation_reconcile_enabled',1),1) < 1
    THEN RETURN 0; END IF;

  -- bay_taxi_min defaults to 3: the MEASURED maximum depot taxi leg is 0.67 min, so 3 min
  -- is measured-max + a margin for tick granularity. It is a travel allowance, NOT a grace.
  v_taxi      := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_taxi_min',3),3),0);
  v_max_defer := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_defer_max',8),8),1)::int;
  v_horizon   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_defer_horizon_min',480),480),30);

  FOR v_b IN
    SELECT b.booking_id, b.vehicle_id, b.stall_id, b.purpose, b.leg_id,
           lower(b.during) AS lo, upper(b.during) AS hi,
           v.current_state::text AS vstate, v.config AS vcfg,
           s.depot_id AS depot_id, s.stall_type AS stall_type
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state = 'held'
       AND s.depot_id = p_depot_id
       AND s.stall_type IN ('wash_bay'::stall_type,'service_bay'::stall_type)
       -- only reservations that are DUE (window already open, or opening within the taxi
       -- allowance). Far-future bookings are left completely alone.
       AND lower(b.during) <= p_clock + make_interval(mins => v_taxi::int)
       -- a vehicle already standing on its own booked stall is honouring it; leave it for
       -- ottoq_activate_present_bookings to flip held -> active.
       AND v.current_stall_id IS DISTINCT FROM b.stall_id
     ORDER BY lower(b.during)
  LOOP
    v_dur := v_b.hi - v_b.lo;
    v_block_at := NULL; v_blk := NULL;

    -- ── the vehicle is not even in the depot: the reservation is dead. Release it
    --    EXPLICITLY (auditable) instead of letting the grace sweep call it a no-show.
    --    MEASURED: 6 of 6 of these in the phase-11 cert were blocked_by='tow_requested',
    --    i.e. genuinely absent -- so the re-plan is CORRECT not to follow the vehicle here.
    IF v_b.vstate IN ('offline','deployed','en_route_to_deployment','out_of_service','tow_requested') THEN
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock, release_reason='replanned_vehicle_absent'
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,
              'released','replanned_vehicle_absent',v_b.vstate,v_b.lo,v_b.hi,NULL);
      v_rel := v_rel + 1;
      CONTINUE;
    END IF;

    -- ── BLOCKER 1: an unfinished charge leg. THIS IS THE 70.6% CASE. Keyed off
    --    planned_end_sim rather than leg status, because charge legs frequently never
    --    close (75 'active' vs 1 'done' in the cert run) -- status is not trustworthy here.
    SELECT max(l.planned_end_sim) INTO v_try
      FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_b.vehicle_id
       AND l.leg_type IN ('charge_l2','charge_dcfc')
       AND l.status IN ('planned','active','in_progress')
       AND l.actual_end_sim IS NULL
       AND l.planned_end_sim > p_clock;
    IF v_try IS NOT NULL THEN v_block_at := v_try; v_blk := 'charging'; END IF;

    -- ── BLOCKER 2: still standing in a different bay.
    IF v_b.vstate IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
      v_try := GREATEST(COALESCE(NULLIF(v_b.vcfg->>'service_ends_at','null')::timestamptz, p_clock), p_clock);
      IF v_block_at IS NULL OR v_try > v_block_at THEN v_block_at := v_try; END IF;
      v_blk := COALESCE(v_blk||'+','') || 'in_other_bay';
    END IF;

    -- ── BLOCKER 3: THE READINESS GATE AND THE CALENDAR NOW SEE EACH OTHER.
    --    twin.ottoq_sim_advance_service_flow STEP 3 pins a vehicle in staging with
    --    config.deploy_gate (remedy need_charge / need_service). Before this line, that
    --    vehicle's bay reservation kept ticking down while it was held -- the gate could
    --    manufacture its own no-show. A gated vehicle can no longer hold a live window.
    IF v_b.vcfg ? 'deploy_gate' THEN
      v_try := p_clock + make_interval(mins => v_taxi::int);
      IF v_block_at IS NULL OR v_try > v_block_at THEN v_block_at := v_try; END IF;
      v_blk := COALESCE(v_blk||'+','') || 'deploy_gate:'
               || COALESCE(v_b.vcfg#>>'{deploy_gate,remedy}','?');
    END IF;

    -- nothing blocks it: the vehicle CAN go now, so the reservation is honourable as
    -- booked. Leave it entirely alone -- the twin admission cursor consumes it.
    IF v_block_at IS NULL THEN CONTINUE; END IF;

    v_eta := v_block_at + make_interval(mins => v_taxi::int);
    IF v_eta <= v_b.lo THEN CONTINUE; END IF;    -- already lines up with reality

    SELECT count(*) INTO v_seq
      FROM public.bay_reservation_reconcile_2026_08_02 r
     WHERE r.booking_id = v_b.booking_id AND r.action = 'deferred';

    -- ── NO DEADLOCK, NO HOSTAGE SPACE. A reservation may be re-planned a bounded number
    --    of times and only within a bounded horizon. Past either bound OTTO-Q gives the
    --    space up DELIBERATELY and says so. The vehicle's service atom stays open, so the
    --    normal booking path re-books it on a later tick: no vehicle is permanently
    --    unable to get a bay.
    IF v_seq >= v_max_defer OR v_eta > v_b.lo + make_interval(mins => v_horizon::int) THEN
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock,
             release_reason = CASE WHEN v_seq >= v_max_defer
                                   THEN 'replanned_defer_cap' ELSE 'replanned_beyond_horizon' END
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,'released',
              CASE WHEN v_seq >= v_max_defer THEN 'replanned_defer_cap' ELSE 'replanned_beyond_horizon' END,
              v_blk,v_b.lo,v_b.hi,v_seq,v_eta);
      v_rel := v_rel + 1;
      CONTINUE;
    END IF;

    -- ── DEFER: slide the window to when the vehicle can ACTUALLY be there. Duration is
    --    preserved exactly, so this can only ever FREE near-term capacity, never consume
    --    more of it. Both exclusion constraints still adjudicate every write; a collision
    --    walks forward -- and now ALSO sideways to a sibling bay -- rather than
    --    overwriting anyone. Double-booking stays impossible.
    v_ok := false; v_shift := 0; v_newstall := NULL;
    WHILE NOT v_ok AND v_shift <= v_maxsh LOOP
      v_try := v_eta + make_interval(mins => v_shift);
      -- the ORIGINALLY booked bay always gets first refusal at this instant.
      BEGIN
        UPDATE public.ottoq_stall_bookings
           SET during = tstzrange(v_try, v_try + v_dur, '[)')
         WHERE booking_id = v_b.booking_id AND state = 'held';
        v_ok := true; v_newstall := v_b.stall_id;
      EXCEPTION WHEN exclusion_violation THEN
        -- SIDEWAYS BEFORE FORWARD: a sibling bay of the SAME type, free at this same
        -- instant, serves the vehicle sooner than sliding the window later does.
        FOR v_alt IN
          SELECT s2.id
            FROM public.stalls s2
           WHERE s2.depot_id   = v_b.depot_id
             AND s2.stall_type = v_b.stall_type
             AND s2.status NOT IN ('maintenance','closed')
             AND s2.id <> v_b.stall_id
           ORDER BY s2.distance_from_entrance NULLS LAST, s2.id
        LOOP
          BEGIN
            UPDATE public.ottoq_stall_bookings
               SET stall_id = v_alt.id, during = tstzrange(v_try, v_try + v_dur, '[)')
             WHERE booking_id = v_b.booking_id AND state = 'held';
            v_ok := true; v_newstall := v_alt.id;
            EXIT;
          EXCEPTION WHEN exclusion_violation THEN
            NULL;   -- that sibling is busy too; try the next one
          END;
        END LOOP;
        IF NOT v_ok THEN v_shift := v_shift + v_step; END IF;
      END;
    END LOOP;

    IF v_ok THEN
      IF v_newstall IS DISTINCT FROM v_b.stall_id THEN v_moved := v_moved + 1; END IF;
      -- keep the itinerary leg in lockstep: ottoq_stall_free_between's occupancy guard
      -- reads planned_end_sim, so a booking and its leg must never disagree.
      IF v_b.leg_id IS NOT NULL THEN
        UPDATE public.ottoq_itinerary_legs
           SET planned_start_sim = v_try, planned_end_sim = v_try + v_dur
         WHERE leg_id = v_b.leg_id AND status = 'planned';
      END IF;
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,new_from,new_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,COALESCE(v_newstall,v_b.stall_id),v_b.purpose,p_clock,'deferred',
              CASE WHEN v_newstall IS DISTINCT FROM v_b.stall_id
                   THEN 'vehicle_not_yet_releasable_relocated_bay'
                   ELSE 'vehicle_not_yet_releasable' END,
              v_blk,v_b.lo,v_b.hi,v_try,v_try+v_dur,v_seq+1,v_eta);
      v_def := v_def + 1;
    ELSE
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock, release_reason='replanned_no_window'
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,'released',
              'replanned_no_window',v_blk,v_b.lo,v_b.hi,v_seq,v_eta);
      v_rel := v_rel + 1;
    END IF;
  END LOOP;

  -- ONE summary event per tick (event-write amplification is the known tick-cost driver).
  IF v_def > 0 OR v_rel > 0 THEN
   BEGIN
    PERFORM public.ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_actor_id := 'bay_reservation_reconcile',
      p_event_type := 'ottoq.bay_reservation_replanned', p_entity_type := 'depot',
      p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('deferred',v_def,'released',v_rel,'relocated',v_moved,
        'taxi_min',v_taxi,'defer_max',v_max_defer,'horizon_min',v_horizon,
        'note','a reservation is honoured or re-planned; it is never left to rot'),
      p_severity := CASE WHEN v_rel > 0 THEN 'warning' ELSE 'info' END,
      p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
   EXCEPTION WHEN OTHERS THEN
     RAISE WARNING 'bay_reservation_reconcile: summary event not written (%): %', SQLSTATE, SQLERRM;
   END;
  END IF;

  RETURN v_def + v_rel;

EXCEPTION WHEN OTHERS THEN
  -- never allowed to abort ottoq_decide_tick (the leg_type-abort lesson of 2026-08-01).
  RAISE WARNING 'ottoq_reconcile_bay_reservations: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$

-- ===== ottoq_reconcile_displace_stale_claim =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_reconcile_displace_stale_claim(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_stall_type text, p_purpose text, p_clock timestamp with time zone, p_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_source text DEFAULT 'bay_reconcile_displace'::text, p_tick bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_from timestamptz; v_until timestamptz;
  v_stall uuid; v_bkg uuid; v_state text; v_disp jsonb := '[]'::jsonb;
  v_ids uuid[]; v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_vehicle_id IS NULL
     OR p_stall_type IS NULL OR p_clock IS NULL THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'malformed');
  END IF;

  -- ══ FIREWALL: bay reconciliation ONLY. Not charging, not staging, not parking.
  IF p_stall_type NOT IN ('wash_bay','service_bay','detail_bay') THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'displace_firewall_non_bay',
                              'stall_type', p_stall_type);
  END IF;

  -- ══ REALITY CHECK: this authority exists only because the car IS there.
  -- If the vehicle is not physically in a bay this is a plan, not a fact, and a
  -- plan has no right to displace anything.
  SELECT v.current_state::text INTO v_state
    FROM public.vehicles v
   WHERE v.id = p_vehicle_id AND v.home_depot_id = p_depot_id;

  IF v_state IS NULL OR v_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'not_physically_present',
                              'vehicle_state', v_state);
  END IF;

  v_from  := p_clock;
  v_until := GREATEST(COALESCE(p_until, p_clock + interval '30 minutes'),
                      p_clock + interval '1 minute');

  -- ══ CHOOSE the stall whose claim is weakest, among stalls NOBODY IS IN.
  -- A genuinely free stall (0 active, 0 held) sorts first, so this is also a
  -- safe fallback and not only a displacement path.
  SELECT s.id INTO v_stall
    FROM public.stalls s
   WHERE s.depot_id = p_depot_id
     AND s.stall_type::text = p_stall_type
     AND s.status NOT IN ('maintenance','closed')
     AND NOT EXISTS (
           SELECT 1 FROM public.vehicles vx
            WHERE vx.current_stall_id = s.id
              AND vx.current_state IN ('in_wash_bay'::vehicle_state,
                                       'in_detail_bay'::vehicle_state,
                                       'in_service_bay'::vehicle_state))
   ORDER BY
     (SELECT count(*) FROM public.ottoq_stall_bookings b
       WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
         AND b.state = 'active' AND b.during && tstzrange(v_from, v_until, '[)')) ASC,
     (SELECT count(*) FROM public.ottoq_stall_bookings b
       WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
         AND b.state = 'held' AND b.during && tstzrange(v_from, v_until, '[)')) ASC,
     s.distance_from_entrance NULLS LAST, s.stall_code
   LIMIT 1;

  IF v_stall IS NULL THEN
    -- Genuine over-admission: the twin put more cars in bays than the depot has
    -- bays, and every bay has a real car in it. Nothing to displace.
    RETURN jsonb_build_object('assigned', false, 'reason', 'no_physically_free_stall',
                              'stall_type', p_stall_type);
  END IF;

  -- ══ CAPTURE the losing claims BEFORE overwriting them (RETURNING would hand
  -- back the new state, and the old state is the audit-relevant fact).
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'booking_id', b.booking_id, 'vehicle_id', b.vehicle_id,
           'leg_id', b.leg_id, 'state', b.state, 'booked_by', b.booked_by,
           'during', to_jsonb(b.during))), '[]'::jsonb),
         COALESCE(array_agg(b.booking_id), ARRAY[]::uuid[])
    INTO v_disp, v_ids
    FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = p_sim_run_id
     AND b.stall_id   = v_stall
     AND b.state IN ('held','active')
     AND b.during && tstzrange(v_from, v_until, '[)')
     AND b.vehicle_id <> p_vehicle_id;

  IF array_length(v_ids,1) > 0 THEN
    UPDATE public.ottoq_stall_bookings b
       SET state = 'superseded', released_at = p_clock,
           release_reason = 'displaced_by_physical_occupant'
     WHERE b.booking_id = ANY (v_ids);

    -- Hand the displaced legs back to the planner. PLANNED only — an active or
    -- in_progress leg is never touched, which is what keeps this out of the
    -- reassignment gate's territory.
    UPDATE public.ottoq_itinerary_legs l
       SET to_stall_id = NULL
     WHERE l.leg_id IN (SELECT (e->>'leg_id')::uuid FROM jsonb_array_elements(v_disp) e
                         WHERE NULLIF(e->>'leg_id','') IS NOT NULL)
       AND l.leg_id IS DISTINCT FROM p_leg_id
       AND l.status = 'planned';
  END IF;

  -- ══ Clear the stale PHYSICAL claim. Proven safe: we established above that no
  -- vehicle is physically in this stall.
  UPDATE public.stalls
     SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL
   WHERE id = v_stall;

  IF NOT public.ottoq_reserve_stall(v_stall, p_vehicle_id, p_clock, 900) THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'reserve_cas_lost',
                              'stall_id', v_stall);
  END IF;

  -- ══ OCCUPY. Only the PRESENT vehicle's pointer is written.
  UPDATE public.vehicles SET current_stall_id = v_stall WHERE id = p_vehicle_id;
  UPDATE public.stalls SET current_vehicle_id = p_vehicle_id, status = 'occupied'
   WHERE id = v_stall;

  v_bkg := ottoq.ottoq_record_enacted_booking(
             p_sim_run_id, v_stall, p_vehicle_id, p_clock,
             p_leg_id, v_from, v_until, p_purpose, p_source);

  IF v_bkg IS NOT NULL AND p_leg_id IS NOT NULL THEN
    UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stall
     WHERE leg_id = p_leg_id AND status = 'planned';
  END IF;

  -- ══ FIRST-CLASS CONFLICT RECORD. One row per displaced claim. This is the
  -- point of the exercise: a displacement that is not recorded is indistinguish-
  -- able from a bug, and "zero double-bookings" would again be a statement about
  -- writes that never happened rather than about conflicts that were resolved.
  BEGIN
    INSERT INTO public.space_conflict_ledger
      (sim_run_id, depot_id, sim_clock, tick_seq, stall_id, stall_type,
       conflict_kind, resolution, present_vehicle_id, present_vehicle_state,
       displaced_vehicle_id, displaced_booking_id, displaced_state,
       displaced_during, displaced_leg_id, displaced_booked_by,
       new_booking_id, detail)
    SELECT p_sim_run_id, p_depot_id, p_clock, p_tick, v_stall, p_stall_type,
           'stale_claim_displaced', 'reality_outranks_plan',
           p_vehicle_id, v_state,
           NULLIF(e->>'vehicle_id','')::uuid,
           NULLIF(e->>'booking_id','')::uuid,
           e->>'state',
           tstzrange(((e->'during')->>'lower')::timestamptz,
                     ((e->'during')->>'upper')::timestamptz, '[)'),
           NULLIF(e->>'leg_id','')::uuid,
           e->>'booked_by',
           v_bkg,
           jsonb_build_object('source', p_source, 'purpose', p_purpose,
                              'window_from', v_from, 'window_to', v_until,
                              'booked', v_bkg IS NOT NULL)
      FROM jsonb_array_elements(v_disp) e;
    GET DIAGNOSTICS v_n = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'displace_stale_claim: conflict ledger write FAILED % % (stall=%, vehicle=%)',
      SQLSTATE, SQLERRM, v_stall, p_vehicle_id;
  END;

  RETURN jsonb_build_object('assigned', true, 'stall_id', v_stall, 'booking_id', v_bkg,
                            'booked', v_bkg IS NOT NULL, 'displaced', v_n,
                            'displaced_claims', v_disp, 'purpose', p_purpose,
                            'stall_type', p_stall_type, 'until', v_until,
                            'source', p_source, 'leg_id', p_leg_id);

EXCEPTION WHEN OTHERS THEN
  -- NO-ABORT GUARANTEE. Reconciliation must never take decide_tick down.
  RAISE WARNING 'ottoq_reconcile_displace_stale_claim: FAILED % % run=% vehicle=% type=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_vehicle_id, p_stall_type;
  RETURN jsonb_build_object('assigned', false, 'reason', 'exception', 'sqlstate', SQLSTATE);
END
$function$

-- ===== ottoq_record_enacted_booking =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_record_enacted_booking(p_sim_run_id uuid, p_stall_id uuid, p_vehicle_id uuid, p_clock timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_purpose text DEFAULT NULL::text, p_source text DEFAULT 'unknown'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_stall_type text; v_cmax numeric;
  v_purpose text; v_from timestamptz; v_to timestamptz;
  v_existing uuid; v_bkg uuid; v_min numeric;
  v_soc numeric; v_target numeric; v_batt numeric; v_vmax numeric;
  v_visit uuid;
  v_why jsonb; v_leg uuid; v_leg_src text;
BEGIN
  IF p_sim_run_id IS NULL OR p_stall_id IS NULL OR p_vehicle_id IS NULL OR p_clock IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT s.stall_type::text, COALESCE(s.connector_max_kw, 50)
    INTO v_stall_type, v_cmax
    FROM public.stalls s WHERE s.id = p_stall_id;

  IF v_stall_type IS NULL THEN
    RAISE WARNING 'ottoq_record_enacted_booking: stall % not found (run=%, vehicle=%, source=%)',
      p_stall_id, p_sim_run_id, p_vehicle_id, p_source;
    RETURN NULL;
  END IF;

  -- TOTAL FUNCTION SEAM (2026-08-01 leg_type-abort lesson applied forward).
  v_purpose := COALESCE(p_purpose, CASE v_stall_type
      WHEN 'dcfc'        THEN 'charge_dcfc'
      WHEN 'l2'          THEN 'charge_l2'
      WHEN 'wash_bay'    THEN 'wash'
      WHEN 'detail_bay'  THEN 'detail'
      WHEN 'service_bay' THEN 'service'
      WHEN 'staging'     THEN 'staging'
      WHEN 'parking'     THEN 'staging'
      WHEN 'safety'      THEN 'perimeter_hold'
      ELSE 'temp_hold'
    END);

  IF v_purpose NOT IN ('charge_dcfc','charge_l2','wash','detail','service',
                       'inspect','temp_hold','perimeter_hold','staging') THEN
    RAISE WARNING 'ottoq_record_enacted_booking: unmappable purpose % for stall_type % (stall=%, source=%) - recording as temp_hold',
      v_purpose, v_stall_type, p_stall_id, p_source;
    v_purpose := 'temp_hold';
  END IF;

  -- WHY THIS VEHICLE IS IN THIS SPACE, part 2: the visit. Run-scoped on purpose --
  -- ottoq_visit_needs.visit_key is NOT run-scoped, so an un-scoped lookup can hand back
  -- a previous run's visit. Never allowed to abort: a missing visit just leaves NULL.
  BEGIN
    SELECT vn.visit_id INTO v_visit
      FROM public.ottoq_visit_needs vn
     WHERE vn.vehicle_id = p_vehicle_id
       AND vn.sim_run_id = p_sim_run_id
       AND vn.status IN ('open','in_progress')
     ORDER BY vn.created_at DESC LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_visit := NULL;
  END;

  v_from := COALESCE(p_from, p_clock);
  v_to   := p_to;

  IF v_to IS NULL OR v_to <= v_from THEN
    IF v_purpose IN ('charge_dcfc','charge_l2') THEN
      SELECT v.current_soc, COALESCE(v.battery_capacity_kwh, 75),
             COALESCE(v.inlet_max_kw, v.max_charge_rate_kw, 150)
        INTO v_soc, v_batt, v_vmax
        FROM public.vehicles v WHERE v.id = p_vehicle_id;

      v_target := COALESCE((SELECT vn.target_soc FROM public.ottoq_visit_needs vn
                             WHERE vn.vehicle_id = p_vehicle_id
                               AND vn.status IN ('open','in_progress')
                             ORDER BY vn.created_at DESC LIMIT 1), 85);
      BEGIN
        v_min := public.ottoq_charge_minutes_between(
                   COALESCE(v_soc, 50), v_target, v_cmax, v_vmax, v_batt);
      EXCEPTION WHEN OTHERS THEN v_min := NULL;
      END;
      v_min := LEAST(GREATEST(COALESCE(v_min, 45), 15), 480);
    ELSE
      v_min := CASE v_purpose
                 WHEN 'wash' THEN 20 WHEN 'detail' THEN 45 WHEN 'service' THEN 60
                 WHEN 'inspect' THEN 15 ELSE 30 END;
    END IF;
    v_to := v_from + make_interval(mins => v_min::int);
  END IF;

  -- WHY THIS VEHICLE IS IN THIS SPACE, part 3: the LEG + the NEED (2026-08-02).
  -- Callers pass p_leg_id NULL on the dominant (charge) path because ottoq_decide_tick looks
  -- up "status='planned' AND to_stall_id IS NULL", while the leg that actually records the
  -- charge is opened LATER by the twin (ottoq_itin_leg_open) already 'active' with
  -- to_stall_id set -- so that predicate can never match it. The resolver looks for a leg
  -- that genuinely exists and ALWAYS records the need that justified the placement.
  -- It cannot raise; a failure here must never cost us the booking.
  BEGIN
    v_why := ottoq.ottoq_booking_why(p_sim_run_id, p_vehicle_id, p_stall_id,
                                     v_purpose, v_from, v_to, p_leg_id, v_visit);
  EXCEPTION WHEN OTHERS THEN v_why := NULL;
  END;
  v_leg     := COALESCE((v_why->>'leg_id')::uuid, p_leg_id);
  v_leg_src := COALESCE(v_why->>'leg_source', CASE WHEN p_leg_id IS NOT NULL THEN 'caller' ELSE 'none' END);
  v_visit   := COALESCE(v_visit, (v_why->>'visit_id')::uuid);

  -- IDEMPOTENCY. This is also the seam where a FORWARD RESERVATION the vehicle is now
  -- physically taking gets adopted instead of duplicated.
  SELECT b.booking_id INTO v_existing
    FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = p_sim_run_id
     AND b.stall_id   = p_stall_id
     AND b.vehicle_id = p_vehicle_id
     AND b.purpose    = v_purpose
     AND b.state IN ('held','active')
     AND upper(b.during) >= v_from
   ORDER BY b.booked_at DESC LIMIT 1;

  IF v_existing IS NOT NULL THEN
    UPDATE public.ottoq_stall_bookings
       SET leg_id      = COALESCE(leg_id,      v_leg),
           visit_id    = COALESCE(visit_id,    v_visit),
           source      = COALESCE(source,      p_source),
           leg_source  = COALESCE(leg_source,  v_leg_src),
           need_code   = COALESCE(need_code,   v_why->>'need_code'),
           need_atom   = COALESCE(need_atom,   v_why->>'need_atom'),
           need_source = COALESCE(need_source, v_why->>'need_source'),
           why         = COALESCE(why,         v_why->>'why')
     WHERE booking_id = v_existing;
    BEGIN
      UPDATE public.ottoq_stall_bookings b
         SET during = tstzrange(LEAST(lower(b.during), v_from),
                                GREATEST(upper(b.during), v_from + interval '1 minute'), '[)')
       WHERE b.booking_id = v_existing
         AND lower(b.during) > v_from;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'ottoq_record_enacted_booking: could not widen adopted booking % (%): %',
        v_existing, SQLSTATE, SQLERRM;
    END;
    IF v_leg IS NOT NULL AND v_leg_src = 'planned_unbound' THEN
      BEGIN
        UPDATE public.ottoq_itinerary_legs SET to_stall_id = p_stall_id
         WHERE leg_id = v_leg AND status = 'planned' AND to_stall_id IS NULL;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
    RETURN v_existing;
  END IF;

  -- CONFLICT PATH (held/active) -- unchanged.
  WITH sup AS (
    UPDATE public.ottoq_stall_bookings b
       SET state          = 'superseded',
           released_at    = p_clock,
           release_reason = 'superseded_by_enacted_decision'
     WHERE b.sim_run_id = p_sim_run_id
       AND b.stall_id   = p_stall_id
       AND b.state IN ('held','active')
       AND b.during && tstzrange(v_from, v_to, '[)')
       AND (b.vehicle_id = p_vehicle_id
            OR NOT EXISTS (SELECT 1 FROM public.vehicles vx
                            WHERE vx.id = b.vehicle_id
                              AND vx.current_stall_id = b.stall_id))
    RETURNING b.leg_id AS leg_id)
  UPDATE public.ottoq_itinerary_legs l
     SET to_stall_id = NULL
    FROM sup
   WHERE l.leg_id = sup.leg_id
     AND l.leg_id IS DISTINCT FROM v_leg
     AND l.status = 'planned';

  -- CONFLICT PATH FOR 'done' -- unchanged.
  UPDATE public.ottoq_stall_bookings b
     SET during = tstzrange(lower(b.during), v_from, '[)')
   WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = p_stall_id
     AND b.state = 'done'
     AND b.during && tstzrange(v_from, v_to, '[)')
     AND lower(b.during) < v_from;

  UPDATE public.ottoq_stall_bookings b
     SET state = 'superseded', released_at = p_clock,
         release_reason = 'superseded_by_enacted_decision'
   WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = p_stall_id
     AND b.state = 'done'
     AND b.during && tstzrange(v_from, v_to, '[)')
     AND lower(b.during) >= v_from;

  -- SIBLING-HOLD RELEASE (2026-08-03). The vehicle is taking THIS stall; any other bay it is
  -- still holding for the same purpose is now stale and must not survive to become a no-show.
  UPDATE public.ottoq_stall_bookings b
     SET state          = 'superseded',
         released_at    = p_clock,
         release_reason = 'superseded_by_enacted_same_purpose'
   WHERE b.sim_run_id = p_sim_run_id
     AND b.vehicle_id = p_vehicle_id
     AND b.purpose    = v_purpose
     AND b.stall_id  <> p_stall_id
     AND b.state      = 'held'
     AND NOT EXISTS (SELECT 1 FROM public.vehicles vx
                      WHERE vx.id = b.vehicle_id AND vx.current_stall_id = b.stall_id);

  v_bkg := ottoq.ottoq_book_stall(
             p_sim_run_id, p_stall_id, p_vehicle_id, v_purpose,
             v_from, v_to, v_visit, v_leg, ottoq.ottoq_booking_authorship(p_source));

  IF v_bkg IS NOT NULL THEN
    -- PROVENANCE: booked_by says who claims authorship, source says which code path wrote it,
    -- need_code/why say WHY the vehicle is in this space -- present even with no leg.
    UPDATE public.ottoq_stall_bookings
       SET source      = p_source,
           leg_source  = v_leg_src,
           need_code   = v_why->>'need_code',
           need_atom   = v_why->>'need_atom',
           need_source = v_why->>'need_source',
           why         = v_why->>'why'
     WHERE booking_id = v_bkg;

    IF v_leg IS NOT NULL AND v_leg_src = 'planned_unbound' THEN
      BEGIN
        UPDATE public.ottoq_itinerary_legs SET to_stall_id = p_stall_id
         WHERE leg_id = v_leg AND status = 'planned' AND to_stall_id IS NULL;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END IF;

  IF v_bkg IS NULL THEN
    RAISE WARNING 'ottoq_record_enacted_booking: booking REFUSED run=% stall=% (type=%) vehicle=% purpose=% window=[%,%) leg=% source=%',
      p_sim_run_id, p_stall_id, v_stall_type, p_vehicle_id, v_purpose, v_from, v_to, v_leg, p_source;
  END IF;

  RETURN v_bkg;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_record_enacted_booking: FAILED sqlstate=% msg=% run=% stall=% vehicle=% purpose=% source=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_stall_id, p_vehicle_id, COALESCE(v_purpose,'<unresolved>'), p_source;
  RETURN NULL;
END
$function$

-- ===== ottoq_release_expired_bookings =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_release_expired_bookings(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int; v_rows jsonb := '[]'::jsonb; v_rec jsonb; v_depot uuid;
BEGIN
  -- BUILD 2: routed through the SAME predicate as ottoq_release_vacated_spaces so
  -- "materially shorter" has exactly ONE definition in the codebase.
  -- HONESTY NOTE: this path fires only when upper(during) <= p_clock, i.e. the booking ran
  -- its FULL planned window, so actual == planned and the predicate is provably INERT here
  -- today (measured: 0 rows with release_reason='window_elapsed_before_planned_end' across the
  -- phase-10 cert). It is wired anyway so the two closers cannot drift apart -- and as of the
  -- emission fix it now EMITS too, so if it ever does start firing it cannot fire blind.
  WITH upd AS (
    UPDATE public.ottoq_stall_bookings b
       SET state = CASE
                     WHEN b.state <> 'active' THEN 'released'
                     WHEN ottoq.ottoq_booking_interrupted(
                            b.purpose,
                            EXTRACT(epoch FROM (upper(b.during) - lower(b.during)))::numeric,
                            EXTRACT(epoch FROM (LEAST(upper(b.during), p_clock) - lower(b.during)))::numeric)
                       THEN 'interrupted'
                     ELSE 'done' END,
           released_at = p_clock,
           release_reason = CASE
                     WHEN b.state <> 'active' THEN 'window_elapsed'
                     WHEN ottoq.ottoq_booking_interrupted(
                            b.purpose,
                            EXTRACT(epoch FROM (upper(b.during) - lower(b.during)))::numeric,
                            EXTRACT(epoch FROM (LEAST(upper(b.during), p_clock) - lower(b.during)))::numeric)
                       THEN 'window_elapsed_before_planned_end'
                     ELSE 'window_elapsed_occupied' END
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state IN ('held','active')
       AND upper(b.during) <= p_clock
    RETURNING b.booking_id, b.vehicle_id, b.stall_id, b.purpose, b.state,
              EXTRACT(epoch FROM (upper(b.during) - lower(b.during)))::numeric AS planned_s,
              EXTRACT(epoch FROM (LEAST(upper(b.during), p_clock) - lower(b.during)))::numeric AS actual_s
  )
  SELECT count(*)::int,
         COALESCE(jsonb_agg(to_jsonb(u)) FILTER (WHERE u.state = 'interrupted'), '[]'::jsonb)
    INTO v_n, v_rows
    FROM upd u;

  -- EMISSION PARITY. Per-row handler: an audit write must never abort the closer.
  FOR v_rec IN SELECT * FROM jsonb_array_elements(v_rows) LOOP
    BEGIN
      SELECT s.depot_id INTO v_depot
        FROM public.stalls s WHERE s.id = (v_rec->>'stall_id')::uuid;
    EXCEPTION WHEN OTHERS THEN v_depot := NULL;
    END;
    PERFORM ottoq.ottoq_emit_booking_interrupted(
      p_sim_run_id, v_depot,
      (v_rec->>'booking_id')::uuid, (v_rec->>'vehicle_id')::uuid, (v_rec->>'stall_id')::uuid,
      v_rec->>'purpose', p_clock, 'window_elapsed_before_planned_end',
      (v_rec->>'planned_s')::numeric, (v_rec->>'actual_s')::numeric,
      0, 0, 'release_expired_bookings');
  END LOOP;

  RETURN v_n;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_release_expired_bookings: FAILED sqlstate=% msg=% run=%',
    SQLSTATE, SQLERRM, p_sim_run_id;
  RETURN 0;
END
$function$

-- ===== ottoq_release_stall_reservation =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_release_stall_reservation(p_stall_id uuid, p_vehicle_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  UPDATE stalls SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
   WHERE id = p_stall_id AND (reserved_by = p_vehicle_id OR reserved_by IS NULL);
$function$

-- ===== ottoq_release_vacated_spaces =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_release_vacated_spaces(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int := 0; v_m int := 0; v_grace int; v_rec record; v_reopened int;
        v_legs int := 0; v_leg_cap int := 3; v_needs_open int := 0;
        v_activated int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  -- (a) vehicle still POINTS at a bay it is no longer working in -> drop the pointer.
  UPDATE public.vehicles v
     SET current_stall_id = NULL
   WHERE v.home_depot_id    = p_depot_id
     AND v.current_stall_id IS NOT NULL
     AND v.current_state NOT IN ('in_wash_bay'::vehicle_state,
                                 'in_detail_bay'::vehicle_state,
                                 'in_service_bay'::vehicle_state)
     AND EXISTS (SELECT 1 FROM public.stalls s
                  WHERE s.id = v.current_stall_id
                    AND s.stall_type IN ('wash_bay'::stall_type,'service_bay'::stall_type));
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- (b) bay stalls whose occupant no longer claims them -> hard-free. Never dcfc/l2/staging.
  UPDATE public.stalls s
     SET current_vehicle_id = NULL, reserved_by = NULL,
         reservation_expires_at = NULL, status = 'available'
   WHERE s.depot_id = p_depot_id
     AND s.stall_type IN ('wash_bay'::stall_type,'service_bay'::stall_type)
     AND s.status NOT IN ('maintenance','closed')
     AND (s.current_vehicle_id IS NOT NULL OR s.reserved_by IS NOT NULL)
     AND NOT EXISTS (
           SELECT 1 FROM public.vehicles v
            WHERE v.id = COALESCE(s.current_vehicle_id, s.reserved_by)
              AND v.current_stall_id = s.id
              AND v.current_state IN ('in_wash_bay'::vehicle_state,
                                      'in_detail_bay'::vehicle_state,
                                      'in_service_bay'::vehicle_state));
  GET DIAGNOSTICS v_m = ROW_COUNT;

  v_grace   := GREATEST(public.ottoq_policy_get(p_sim_run_id,'booking_no_show_grace_min',15)::int, 0);
  v_leg_cap := GREATEST(public.ottoq_policy_get(p_sim_run_id,'leg_replan_max_attempts',3)::int, 0);

  -- ══════════ PHASE 11 (b2): KEEP THE APPOINTMENT BEFORE BURNING THE GRACE ══════════
  -- MUST run after (a)/(b) -- those free the stalls this sweep needs -- and BEFORE the
  -- grace sweep in (c), which is what was silently converting un-enacted reservations
  -- into `no_show_grace_elapsed`. The grace itself is UNCHANGED at v_grace minutes.
  -- Self-contained handler: a failure here can never cost us the release logic below.
  BEGIN
    v_activated := ottoq.ottoq_activate_due_bay_reservations(p_sim_run_id, p_depot_id, p_clock);
  EXCEPTION WHEN OTHERS THEN
    v_activated := 0;
    RAISE WARNING 'activate_due_bay_reservations FAILED sqlstate=% msg=% run=%',
      SQLSTATE, SQLERRM, p_sim_run_id;
  END;

  -- (c) CALENDAR.
  -- BUILD 2: `done` now MEANS FINISHED. A bay booking whose actual occupancy is materially
  -- shorter than its planned window closes as the terminal state `interrupted` instead.
  -- The planned window is read from b.during BEFORE the clip (RHS of an UPDATE sees OLD).
  FOR v_rec IN
    WITH cand AS (
      SELECT b.booking_id, b.state AS old_state, b.purpose,
             lower(b.during) AS lo, upper(b.during) AS hi,
             GREATEST(lower(b.during) + interval '1 second',
                      LEAST(upper(b.during), p_clock)) AS clip_hi
        FROM public.ottoq_stall_bookings b
       WHERE b.sim_run_id = p_sim_run_id
         AND b.state IN ('held','active')
         -- 'active' closes on the EXIT EVENT (the NOT EXISTS below IS that event) -- no grace,
         -- because the space is genuinely free the moment the vehicle is gone.
         -- 'held' is a forward reservation nobody has taken: only the no-show grace closes it.
         AND ( b.state = 'active'
               OR lower(b.during) + make_interval(mins => v_grace) <= p_clock )
         AND EXISTS (SELECT 1 FROM public.stalls s
                      WHERE s.id = b.stall_id AND s.depot_id = p_depot_id
                        AND s.stall_type IN ('wash_bay'::stall_type,'service_bay'::stall_type))
         AND NOT EXISTS (SELECT 1 FROM public.vehicles v
                          WHERE v.id = b.vehicle_id AND v.current_stall_id = b.stall_id
                            AND v.current_state IN ('in_wash_bay'::vehicle_state,
                                                    'in_detail_bay'::vehicle_state,
                                                    'in_service_bay'::vehicle_state))
    ), decided AS (
      SELECT c.*,
             EXTRACT(epoch FROM (c.hi - c.lo))::numeric      AS planned_s,
             EXTRACT(epoch FROM (c.clip_hi - c.lo))::numeric AS actual_s,
             CASE WHEN c.old_state = 'active' THEN
                    CASE WHEN ottoq.ottoq_booking_interrupted(
                                c.purpose,
                                EXTRACT(epoch FROM (c.hi - c.lo))::numeric,
                                EXTRACT(epoch FROM (c.clip_hi - c.lo))::numeric)
                         THEN 'interrupted' ELSE 'done' END
                  ELSE 'released' END                        AS new_state
        FROM cand c
    ), upd AS (
      UPDATE public.ottoq_stall_bookings b
         SET state          = d.new_state,
             released_at    = p_clock,
             release_reason = CASE d.new_state
                                WHEN 'interrupted' THEN 'bay_exit_before_planned_end'
                                WHEN 'done'        THEN 'bay_exit_transition'
                                ELSE                    'no_show_grace_elapsed' END,
             during         = CASE WHEN d.old_state = 'active'
                                   THEN tstzrange(d.lo, d.clip_hi, '[)')
                                   ELSE b.during END
        FROM decided d
       WHERE b.booking_id = d.booking_id
      RETURNING b.booking_id, b.vehicle_id, b.stall_id, b.purpose,
                d.lo, d.planned_s, d.actual_s, d.new_state
    )
    SELECT * FROM upd WHERE new_state = 'interrupted'
  LOOP
    -- RE-PLAN. The vehicle still needs this work; the full-service visit is not complete.
    v_reopened := public.ottoq_reopen_visit_atoms(
                    v_rec.vehicle_id,
                    ottoq.ottoq_bay_purpose_atoms(v_rec.purpose),
                    v_rec.lo,
                    'bay_session_interrupted');

    -- ══════════════ FIX 1(b) — UN-STRAND THE BOUND LEG ══════════════
    v_legs := 0;
    BEGIN
      UPDATE public.ottoq_itinerary_legs l
         SET status            = 'planned',
             to_stall_id       = NULL,
             actual_start_sim  = NULL,
             actual_end_sim    = NULL,
             planned_start_sim = p_clock,
             planned_end_sim   = p_clock + make_interval(secs =>
                                   GREATEST(COALESCE(l.planned_duration_s,
                                            EXTRACT(epoch FROM (l.planned_end_sim - l.planned_start_sim))::int,
                                            1800), 60)),
             duration_basis    = COALESCE(l.duration_basis,'{}'::jsonb) || jsonb_build_object(
                                   'replan', jsonb_build_object(
                                     'reason','bay_session_interrupted',
                                     'at', p_clock,
                                     'attempts', COALESCE((l.duration_basis->'replan'->>'attempts')::int,0) + 1,
                                     'max_attempts', v_leg_cap,
                                     'booking_id', v_rec.booking_id,
                                     'prev_planned_start', l.planned_start_sim,
                                     'prev_planned_end', l.planned_end_sim,
                                     'prev_actual_start', l.actual_start_sim))
       WHERE l.sim_run_id = p_sim_run_id
         AND l.vehicle_id = v_rec.vehicle_id
         AND l.status     = 'active'
         AND l.actual_end_sim IS NULL
         AND (l.to_stall_id = v_rec.stall_id
              OR l.leg_type = ANY (ottoq.ottoq_bay_purpose_leg_types(v_rec.purpose)))
         AND COALESCE((l.duration_basis->'replan'->>'attempts')::int,0) < v_leg_cap;
      GET DIAGNOSTICS v_legs = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
      v_legs := -1;
      RAISE WARNING 'leg un-strand FAILED sqlstate=% msg=% vehicle=%', SQLSTATE, SQLERRM, v_rec.vehicle_id;
    END;

    -- OUTCOME CHECK, not an intention check: did the vehicle actually end up with work DUE?
    BEGIN
      SELECT count(*) INTO v_needs_open
        FROM public.ottoq_visit_needs vn
       WHERE vn.vehicle_id = v_rec.vehicle_id
         AND vn.status = 'open'
         AND vn.meta->>'reopen_reason' = 'bay_session_interrupted';
    EXCEPTION WHEN OTHERS THEN v_needs_open := -1;
    END;

    -- AUDIT.
    PERFORM ottoq.ottoq_emit_booking_interrupted(
      p_sim_run_id, p_depot_id, v_rec.booking_id, v_rec.vehicle_id, v_rec.stall_id,
      v_rec.purpose, p_clock, 'bay_exit_before_planned_end',
      v_rec.planned_s, v_rec.actual_s, v_reopened, v_legs, 'release_vacated_spaces');
  END LOOP;

  RETURN v_n + v_m + v_activated;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_release_vacated_spaces: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$

-- ===== ottoq_release_visit_artifacts =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_release_visit_artifacts(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamp with time zone, p_reason text DEFAULT 'redeployed'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_legs int := 0; v_itin int := 0; v_needs int := 0; v_res int := 0;
BEGIN
  UPDATE ottoq_itinerary_legs l
     SET status = 'skipped'
    FROM ottoq_vehicle_itineraries i
   WHERE l.itinerary_id = i.itinerary_id
     AND i.vehicle_id = p_vehicle_id
     AND i.status = 'active'
     AND l.status IN ('planned','active');
  GET DIAGNOSTICS v_legs = ROW_COUNT;

  UPDATE ottoq_vehicle_itineraries
     SET status = 'completed'
   WHERE vehicle_id = p_vehicle_id AND status = 'active';
  GET DIAGNOSTICS v_itin = ROW_COUNT;

  UPDATE ottoq_visit_needs
     SET status = 'superseded'
   WHERE vehicle_id = p_vehicle_id
     AND status IN ('open','in_progress','carried_over');
  GET DIAGNOSTICS v_needs = ROW_COUNT;

  UPDATE stalls
     SET reserved_by = NULL, reservation_expires_at = NULL
   WHERE reserved_by = p_vehicle_id;
  GET DIAGNOSTICS v_res = ROW_COUNT;

  RETURN jsonb_build_object('reason',p_reason,'legs_skipped',v_legs,
    'itineraries_closed',v_itin,'needs_superseded',v_needs,'reservations_released',v_res);
END;
$function$

-- ===== ottoq_reoptimize_reservation_book =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_reoptimize_reservation_book(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE; v_rec RECORD;
  v_swaps int := 0; v_cuopt int := 0;
  v_atoms jsonb; v_plan jsonb; v_new_stall uuid; v_src text;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND OR COALESCE(v_run.policy,'otto_q') <> 'otto_q' THEN
    RETURN jsonb_build_object('swaps', 0);
  END IF;

  FOR v_rec IN
    SELECT v.id AS vehicle_id, v.current_soc, s.id AS old_stall, s.stall_type::text AS old_type,
           d.return_eta_minutes
      FROM stalls s
      JOIN vehicles v ON v.id = s.reserved_by
      LEFT JOIN ottoq_vehicle_dispatches d ON d.vehicle_id = v.id
             AND d.sim_run_id = p_sim_run_id AND d.status = 'returning'
     WHERE s.depot_id = v_run.depot_id
       AND s.reserved_by IS NOT NULL
       AND COALESCE(s.reservation_expires_at, p_clock) >= p_clock
       AND v.current_state IN ('deployed','en_route_to_depot')
       AND v.current_soc < 45
       AND s.stall_type::text <> 'dcfc'
     LIMIT 10
  LOOP
    v_new_stall := NULL; v_src := NULL;
    -- 1) a FRESH cuOpt proposal for this vehicle targeting a free healthy DCFC wins the swap
    SELECT (p.proposal->>'stall_id')::uuid INTO v_new_stall
      FROM ottoq_external_proposals p
      JOIN stalls s2 ON s2.id = (p.proposal->>'stall_id')::uuid
      JOIN ottoq_ocpp_chargers ch ON ch.charger_id = s2.ocpp_charger_id
     WHERE p.sim_run_id = p_sim_run_id AND p.status = 'pending' AND p.source = 'cuopt'
       AND p.entity_id = v_rec.vehicle_id AND p.action_context = 'stall_assignment'
       AND COALESCE(p.expires_at, p.created_at + interval '90 seconds') >= now()
       AND s2.stall_type::text = 'dcfc' AND s2.status = 'available' AND s2.reserved_by IS NULL
       AND ch.station_state = 'Available'
     ORDER BY p.created_at DESC LIMIT 1;
    IF v_new_stall IS NOT NULL THEN v_src := 'cuopt'; END IF;
    -- 2) local improvement floor: any free healthy DCFC
    IF v_new_stall IS NULL THEN
      SELECT s2.id INTO v_new_stall FROM stalls s2
        JOIN ottoq_ocpp_chargers ch ON ch.charger_id = s2.ocpp_charger_id
       WHERE s2.depot_id = v_run.depot_id AND s2.stall_type::text = 'dcfc'
         AND s2.status = 'available' AND s2.reserved_by IS NULL AND ch.station_state = 'Available'
       ORDER BY s2.stall_code LIMIT 1;
      IF v_new_stall IS NOT NULL THEN v_src := 'reservation_reopt'; END IF;
    END IF;
    CONTINUE WHEN v_new_stall IS NULL;

    -- claim the NEW stall first, then release the old — the vehicle is never unreserved
    IF NOT ottoq_reserve_stall(v_new_stall, v_rec.vehicle_id, p_clock,
             GREATEST(600, (COALESCE(v_rec.return_eta_minutes, 30) * 60)::int + 1200)) THEN
      CONTINUE;
    END IF;
    UPDATE stalls SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE id = v_rec.old_stall AND reserved_by = v_rec.vehicle_id;

    -- rebuild the timed plan against the upgraded stall + tell the vehicle
    BEGIN
      SELECT vn.atoms INTO v_atoms FROM ottoq_visit_needs vn
       WHERE vn.vehicle_id = v_rec.vehicle_id AND vn.status IN ('open','in_progress')
       ORDER BY vn.created_at DESC LIMIT 1;
      v_plan := ottoq_build_workflow_plan(v_rec.vehicle_id, p_sim_run_id,
                  p_clock + (COALESCE(v_rec.return_eta_minutes, 20) || ' minutes')::interval, v_atoms);
      PERFORM ottoq_comms_send_command(p_sim_run_id, v_rec.vehicle_id, 'proceed_to_stall',
        jsonb_build_object('plan_update', 'upgraded', 'stall_id', v_new_stall, 'plan', v_plan),
        p_clock, false);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'reopt replan downlink: %', SQLERRM;
    END;

    INSERT INTO ottoq_decisions (sim_run_id, tick_seq, sim_clock, depot_id, action_context,
      resolved_action_context, entity_type, entity_id, context_frame,
      proposed_action, enacted_action, outcome_status, propose_latency_ms, total_latency_ms)
    VALUES (p_sim_run_id, v_run.tick_count, p_clock, v_run.depot_id, 'stall_assignment',
      'reservation_reopt', 'vehicle', v_rec.vehicle_id,
      jsonb_build_object('old_stall', v_rec.old_stall, 'old_type', v_rec.old_type, 'soc', v_rec.current_soc),
      jsonb_build_object('verb', 'rebook', 'stall_id', v_new_stall, 'source', v_src),
      jsonb_build_object('verb', 'rebook', 'stall_id', v_new_stall, 'source', v_src),
      'enacted', 0, 0);
    v_swaps := v_swaps + 1;
    IF v_src = 'cuopt' THEN
      v_cuopt := v_cuopt + 1;
      UPDATE ottoq_external_proposals SET status = 'enacted'
       WHERE sim_run_id = p_sim_run_id AND entity_id = v_rec.vehicle_id
         AND status = 'pending' AND source = 'cuopt';
    END IF;
  END LOOP;
  RETURN jsonb_build_object('swaps', v_swaps, 'cuopt', v_cuopt);
END;
$function$

-- ===== ottoq_replan_after_charger_fault =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_replan_after_charger_fault(p_vehicle_id uuid, p_sim_run_id uuid, p_depot_id uuid, p_stall_type text, p_charger_id uuid, p_fault_code text, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_gate jsonb; v_new_stall uuid; v_disp text;
BEGIN
  -- in-depot reassignment doctrine: a resource fault is the sanctioned auto-reroute
  v_gate := ottoq_indepot_reassignment_guard(p_vehicle_id, p_sim_run_id, 'resource_fault',
              jsonb_build_object('charger_id', p_charger_id, 'fault', p_fault_code));

  -- prefer a healthy stall of the SAME class
  SELECT s2.id INTO v_new_stall
    FROM stalls s2
    JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
   WHERE s2.depot_id = p_depot_id
     AND s2.stall_type::text = p_stall_type
     AND s2.status = 'available'
     AND s2.current_vehicle_id IS NULL
     AND (s2.reserved_by IS NULL OR COALESCE(s2.reservation_expires_at, p_clock) <= p_clock)
     AND c2.station_state = 'Available'
   ORDER BY s2.stall_code
   LIMIT 1;

  IF v_new_stall IS NOT NULL AND ottoq_reserve_stall(v_new_stall, p_vehicle_id, p_clock, 3600) THEN
    v_disp := 'requeued_same_class';
  ELSE
    -- else temp-stage it: never leave a displaced vehicle without somewhere to be
    SELECT s3.id INTO v_new_stall
      FROM stalls s3
     WHERE s3.depot_id = p_depot_id
       AND s3.stall_type::text = 'staging'
       AND s3.status = 'available'
       AND s3.current_vehicle_id IS NULL
       AND (s3.reserved_by IS NULL OR COALESCE(s3.reservation_expires_at, p_clock) <= p_clock)
     ORDER BY (s3.staging_role = 'temp') DESC, s3.stall_code
     LIMIT 1;
    IF v_new_stall IS NOT NULL AND ottoq_reserve_stall(v_new_stall, p_vehicle_id, p_clock, 3600) THEN
      v_disp := 'temp_parked_awaiting_charger';
    ELSE
      v_disp := 'no_space_escalated'; v_new_stall := NULL;
    END IF;
  END IF;

  BEGIN
    IF v_new_stall IS NOT NULL AND p_sim_run_id IS NOT NULL THEN
      PERFORM ottoq_comms_send_command(p_sim_run_id, p_vehicle_id,
        CASE WHEN v_disp = 'temp_parked_awaiting_charger' THEN 'stage' ELSE 'proceed_to_stall' END,
        jsonb_build_object('plan_update','charger_fault_reroute','stall_id',v_new_stall,
                           'faulted_charger',p_charger_id,'disposition',v_disp),
        p_clock, false);
    END IF;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'fault reroute downlink: %', SQLERRM; END;

  RETURN jsonb_build_object('vehicle_id', p_vehicle_id, 'disposition', v_disp,
                            'new_stall', v_new_stall, 'gate_mode', v_gate->>'mode');
END
$function$

-- ===== ottoq_replan_stranded_undercharge =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_replan_stranded_undercharge(p_vehicle_id uuid, p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_h          jsonb;
  v_s          uuid;
  v_has_stall  boolean;
  v_booked     boolean := false;
  v_reserved   boolean := false;
BEGIN
  SELECT (v.current_stall_id IS NOT NULL) INTO v_has_stall
    FROM vehicles v WHERE v.id = p_vehicle_id;

  IF COALESCE(v_has_stall, false) THEN
    -- already parked somewhere real: flag only, place nothing (matches pre-split behaviour)
    RETURN jsonb_build_object(
      'vehicle_id', p_vehicle_id, 'state', 'staged_awaiting_service',
      'svc_step', 'need_charge', 'needs_placement', false,
      'disposition', 'already_stalled', 'booked', false,
      'booking_id', NULL::text, 'stall_id', NULL::uuid,
      'reserved', false, 'hold', NULL::jsonb);
  END IF;

  v_h := ottoq_book_hold_stall(p_sim_run_id, p_depot_id, p_vehicle_id,
                               p_clock, p_clock + interval '30 minutes');
  v_booked := COALESCE((v_h->>'booked')::boolean, false);

  IF v_booked THEN
    SELECT b.stall_id INTO v_s FROM ottoq_stall_bookings b
     WHERE b.booking_id = (v_h->>'booking_id')::uuid;
    IF v_s IS NOT NULL
       AND ottoq_reserve_stall(v_s, p_vehicle_id, p_clock, 1800) THEN
      v_reserved := true;
    ELSE
      -- booking calendar said yes but the live stall is taken/held: no placement,
      -- exactly as the pre-split code did (it only placed inside the IF).
      v_s := NULL;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'vehicle_id', p_vehicle_id, 'state', 'staged_awaiting_service',
    'svc_step', 'need_charge', 'needs_placement', true,
    'disposition', CASE WHEN v_reserved THEN 'temp_staged_for_recharge'
                        WHEN v_booked   THEN 'booked_not_reservable'
                        ELSE 'no_staging_capacity' END,
    'booked', v_booked, 'booking_id', v_h->>'booking_id',
    'stall_id', v_s, 'reserved', v_reserved, 'hold', v_h);
END
$function$

-- ===== ottoq_sim_prearrival_contracts =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_sim_prearrival_contracts(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_rec RECORD; v_eta timestamptz; v_stall uuid; v_n int := 0;
  v_has_charge boolean; v_ttl int; v_eta_min numeric;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  -- BACKSTOP 1: en_route car with no workflow (AP-4 books at need-fire; this catches cars that
  -- reached en_route by another path). Provenance stays 'twin_generator' (honest derivation).
  FOR v_rec IN
    SELECT v.id AS vehicle_id
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'en_route_to_depot'
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                        WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress'))
     LIMIT 40
  LOOP
    PERFORM ottoq_sim_generate_service_manifest(v_rec.vehicle_id, p_sim_run_id, NULL);
    SELECT COALESCE(MAX(d.scheduled_return_at), p_clock) INTO v_eta
      FROM ottoq_vehicle_dispatches d
     WHERE d.vehicle_id = v_rec.vehicle_id AND d.actual_return_at IS NULL;
    PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.vehicle_id, GREATEST(p_clock, v_eta));
    v_n := v_n + 1;
  END LOOP;

  -- BACKSTOP 2: en_route car with no live reservation gets one (widened to the whole approach,
  -- ETA-derived TTL so the hold survives transit + gate queue).
  FOR v_rec IN
    SELECT v.id AS vehicle_id, vn.atoms, vn.urgency, v.current_soc,
           (SELECT MIN(d.scheduled_return_at) FROM ottoq_vehicle_dispatches d
             WHERE d.vehicle_id = v.id AND d.actual_return_at IS NULL) AS eta_at
      FROM vehicles v
      JOIN ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'en_route_to_depot'
       AND NOT EXISTS (SELECT 1 FROM stalls s WHERE s.reserved_by = v.id
                         AND s.reservation_expires_at > p_clock)
     LIMIT 40
  LOOP
    v_eta_min := GREATEST(EXTRACT(EPOCH FROM (COALESCE(v_rec.eta_at, p_clock + interval '15 min') - p_clock))/60.0, 10);
    v_ttl := (v_eta_min + 40)::int * 60;
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(v_rec.atoms) a
                    WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
      INTO v_has_charge;
    v_stall := NULL;
    IF v_has_charge THEN
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
      SELECT s.id INTO v_stall FROM stalls s
       WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
         AND s.current_vehicle_id IS NULL
         AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_clock)
       ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id
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

-- ===== ottoq_stage_advance_approval =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_stage_advance_approval(p_vehicle_id uuid, p_sim_run_id uuid, p_depot_id uuid, p_stage text, p_next_stage text DEFAULT NULL::text, p_visit_id uuid DEFAULT NULL::uuid, p_clock timestamp with time zone DEFAULT NULL::timestamp with time zone, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_now         timestamptz := COALESCE(p_clock, now());
  v_need_tech   boolean;
  v_status      text;
  v_decided_at  timestamptz;
  v_decided_by  text;
  v_approval_id uuid;
BEGIN
  -- 0 (default) = no technicians on site, advance automatically.
  v_need_tech := COALESCE(
    public.ottoq_policy_get(p_sim_run_id, 'tech_approvals_required', 0), 0) > 0;

  IF v_need_tech THEN
    v_status := 'pending'; v_decided_at := NULL; v_decided_by := NULL;
  ELSE
    v_status := 'approved'; v_decided_at := v_now; v_decided_by := 'auto_advance_no_tech';
  END IF;

  INSERT INTO public.ottoq_ops_approvals
    (approval_type, vehicle_id, visit_id, sim_run_id, depot_id,
     status, priority, payload, requested_at, decided_at, decided_by)
  VALUES
    ('tech_greenlight', p_vehicle_id, p_visit_id, p_sim_run_id, p_depot_id,
     v_status, 'normal',
     COALESCE(p_payload,'{}'::jsonb) || jsonb_build_object(
       'stage_completed', p_stage,
       'next_stage',      p_next_stage,
       'auto_advanced',   NOT v_need_tech,
       'marked_at',       v_now),
     v_now, v_decided_at, v_decided_by)
  RETURNING approval_id INTO v_approval_id;

  RETURN jsonb_build_object(
    'approved',    v_status = 'approved',
    'approval_id', v_approval_id,
    'mode',        CASE WHEN v_need_tech THEN 'awaiting_tech' ELSE 'auto_no_tech' END,
    'stage',       p_stage,
    'next_stage',  p_next_stage,
    'decided_by',  v_decided_by,
    'decided_at',  v_decided_at
  );
END
$function$

-- ===== ottoq_stage_after_tow_retrieval =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_stage_after_tow_retrieval(p_vehicle_id uuid, p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_stall uuid;
BEGIN
  -- Same filter, ORDER BY, tie-break and LIMIT as the fused original.
  -- NOTE: the live body ALREADY honoured reservation_expires_at, so the known
  -- expired-hold defect is NOT present here. The COALESCE is defensive alignment
  -- with ottoq_reserve_stall's own predicate (NULL expiry == free), verified a
  -- no-op on live data: 0 rows have reserved_by NOT NULL with a NULL expiry.
  SELECT s.id INTO v_stall FROM stalls s
   WHERE s.depot_id = p_depot_id AND s.stall_type = 'staging'
     AND s.current_vehicle_id IS NULL
     AND (s.reserved_by IS NULL OR COALESCE(s.reservation_expires_at, p_clock) <= p_clock)
   ORDER BY s.distance_from_entrance NULLS LAST, s.id LIMIT 1;

  IF v_stall IS NOT NULL AND ottoq_reserve_stall(v_stall, p_vehicle_id, p_clock, 1800) THEN
    RETURN jsonb_build_object('vehicle_id', p_vehicle_id, 'disposition', 'retrieved_staged',
                              'stall_id', v_stall, 'ttl_seconds', 1800);
  END IF;

  RETURN jsonb_build_object('vehicle_id', p_vehicle_id, 'disposition', 'no_staging_capacity',
                            'stall_id', NULL::uuid, 'ttl_seconds', 1800);
END;
$function$

-- ===== ottoq_stall_free_between =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_stall_free_between(p_sim_run_id uuid, p_depot_id uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_stall_type text DEFAULT NULL::text, p_staging_role text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_zones text[] DEFAULT NULL::text[])
 RETURNS TABLE(stall_id uuid, stall_code text, stall_type text, staging_role text, zone text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH g AS MATERIALIZED (
    SELECT
      (public.ottoq_policy_get(p_sim_run_id, 'calendar_occupancy_guard', 0) >= 1) AS guard_on,
      GREATEST(public.ottoq_policy_get(p_sim_run_id, 'occupied_stall_horizon_min',     45), 1) AS horizon_min,
      GREATEST(public.ottoq_policy_get(p_sim_run_id, 'occupied_stall_horizon_max_min', 240), 1) AS horizon_max_min,
      COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
                 WHERE r.sim_run_id = p_sim_run_id), p_from) AS now_sim
  )
  SELECT s.id, s.stall_code, s.stall_type::text, s.staging_role, s.zone
  FROM public.stalls s CROSS JOIN g
  WHERE s.depot_id = p_depot_id
    AND s.status NOT IN ('maintenance','closed')
    AND (p_stall_type   IS NULL OR s.stall_type::text = p_stall_type)
    AND (p_staging_role IS NULL OR s.staging_role     = p_staging_role)
    AND (p_zones        IS NULL OR s.zone             = ANY (p_zones))
    -- ══════════════════ CALENDAR READ — MUST MATCH THE CONSTRAINT ══════════════════
    -- 2026-08-03 (P1): state set aligned to ottoq_stall_bookings_no_overlap_v3:
    -- held / active / done / interrupted. Any divergence between what the picker
    -- treats as busy and what the database refuses to double-book turns straight back
    -- into silent oversubscription (the 2026-08-02 finding: picker read held/active,
    -- which had been emptied every tick, so 22 vehicles were booked into ONE bay).
    -- 'done' and 'interrupted' are REAL past occupancy. Both are safe to include only
    -- because every close path TRUNCATES `during` to the true end of occupancy --
    -- verified 2026-08-03: 40 of 40 interrupted rows have upper(during) <= released_at,
    -- phantom tail 0.00 min -- so neither can block a window the vehicle did not use.
    -- 'released' / 'superseded' mean the occupancy never happened and remain invisible.
    AND NOT EXISTS (
      SELECT 1 FROM public.ottoq_stall_bookings b
      WHERE b.stall_id   = s.id
        AND b.sim_run_id = p_sim_run_id
        AND b.state IN ('held','active','done','interrupted')
        AND b.during && tstzrange(p_from, p_to, '[)')
    )
    -- ============================ OCCUPANCY GUARD ============================
    AND (
      NOT g.guard_on
      OR s.current_vehicle_id IS NULL
      OR NOT (
           tstzrange(
             g.now_sim,
             GREATEST(
               g.now_sim + interval '1 second',
               LEAST(
                 COALESCE(
                   (SELECT min(l.planned_end_sim)
                      FROM public.ottoq_itinerary_legs l
                     WHERE l.sim_run_id       = p_sim_run_id
                       AND l.vehicle_id       = s.current_vehicle_id
                       AND l.to_stall_id      = s.id
                       AND l.status IN ('planned','active','in_progress')
                       AND l.planned_end_sim  > g.now_sim),
                   g.now_sim + make_interval(mins => g.horizon_min::int)),
                 g.now_sim + make_interval(mins => g.horizon_max_min::int))
             ), '[)')
           && tstzrange(p_from, p_to, '[)')
         )
    )
  ORDER BY s.distance_from_entrance NULLS LAST, s.stall_code
  LIMIT GREATEST(p_limit, 1)
$function$

-- ===== ottoq_state_service_atoms =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_state_service_atoms(p_state text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT CASE COALESCE(p_state,'')
    WHEN 'charging_dcfc'  THEN ARRAY['charge']
    WHEN 'charging_l2'    THEN ARRAY['charge']
    WHEN 'in_wash_bay'    THEN ARRAY['exterior_wash','sensor_clean']
    WHEN 'in_detail_bay'  THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
    WHEN 'in_service_bay' THEN ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair']
    ELSE '{}'::text[]
  END;
$function$

-- ===== ottoq_validate_assignment =====
CREATE OR REPLACE FUNCTION ottoq.ottoq_validate_assignment(p_vehicle_id uuid, p_stall_id uuid, p_command_type text, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh RECORD; v_stall RECORD; v_charger_state text; v_cal_conflict uuid;
BEGIN
  SELECT id, current_state::text AS st, current_stall_id INTO v_veh
    FROM vehicles WHERE id = p_vehicle_id;
  IF v_veh.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','target_unknown','detail','vehicle not found');
  END IF;
  IF v_veh.st IN ('tow_requested','out_of_service') THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_unresponsive','detail','vehicle is '||v_veh.st);
  END IF;

  IF p_stall_id IS NULL THEN
    IF p_command_type IN ('proceed_to_stall','begin_charge') THEN
      RETURN jsonb_build_object('ok',false,'code','command_malformed','detail','stall_id required for '||p_command_type);
    END IF;
    RETURN jsonb_build_object('ok',true);   -- advisory command, no resource claim
  END IF;

  SELECT s.id, s.status, s.current_vehicle_id, s.reserved_by, s.reservation_expires_at,
         s.stall_type::text AS stype, s.ocpp_charger_id, s.depot_id
    INTO v_stall FROM stalls s WHERE s.id = p_stall_id;
  IF v_stall.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','target_unknown','detail','stall '||p_stall_id||' not found');
  END IF;
  IF v_veh.current_stall_id = v_stall.id THEN
    RETURN jsonb_build_object('ok',true,'already_in_place',true);
  END IF;
  IF v_stall.status IN ('maintenance','closed') THEN
    RETURN jsonb_build_object('ok',false,'code','resource_faulted','detail','stall '||v_stall.status);
  END IF;
  IF v_stall.current_vehicle_id IS NOT NULL AND v_stall.current_vehicle_id <> p_vehicle_id THEN
    RETURN jsonb_build_object('ok',false,'code','target_occupied','detail','stall occupied by '||v_stall.current_vehicle_id);
  END IF;
  IF v_stall.reserved_by IS NOT NULL AND v_stall.reserved_by <> p_vehicle_id
     AND COALESCE(v_stall.reservation_expires_at, p_clock) > p_clock THEN
    RETURN jsonb_build_object('ok',false,'code','target_occupied','detail','stall reserved by '||v_stall.reserved_by);
  END IF;
  IF p_command_type = 'begin_charge' AND v_stall.ocpp_charger_id IS NOT NULL THEN
    SELECT c.station_state::text INTO v_charger_state
      FROM ottoq_ocpp_chargers c WHERE c.charger_id = v_stall.ocpp_charger_id;
    IF v_charger_state IS DISTINCT FROM 'Available' THEN
      RETURN jsonb_build_object('ok',false,'code','resource_faulted','detail','charger '||COALESCE(v_charger_state,'unknown'));
    END IF;
  END IF;
  -- forward calendar: an assignment must not collide with a live booking held
  -- by ANOTHER vehicle covering this moment
  --
  -- 2026-08-03 (P1): state set aligned to ottoq_stall_bookings_no_overlap_v3 and to
  -- ottoq.ottoq_stall_free_between -- held/active/done/interrupted. A validator that
  -- returns ok=true for a stall the EXCLUDE constraint would then refuse to book is
  -- the picker-vs-constraint divergence that produced the one-bay pile-up.
  -- 'done' and 'interrupted' are REAL past occupancy and every close path truncates
  -- `during` to the true end of occupancy (interrupted verified 40 of 40, phantom
  -- tail 0.00 min), so such a row can only match @> p_clock while the space is
  -- genuinely still held. 'released'/'superseded' mean the occupancy never happened
  -- and stay invisible here, so this can never make an idle stall look busy.
  -- Direction of change is STRICTLY tighter: it can only ever turn a true into a
  -- false, so it cannot create a double-booking.
  SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
   WHERE b.stall_id = p_stall_id AND b.state IN ('held','active','done','interrupted')
     AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
   LIMIT 1;
  IF v_cal_conflict IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','target_occupied','detail','calendar booking held by '||v_cal_conflict);
  END IF;

  RETURN jsonb_build_object('ok',true);
END $function$
