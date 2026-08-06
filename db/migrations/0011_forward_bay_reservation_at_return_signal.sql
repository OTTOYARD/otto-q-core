-- migration-version: PENDING
-- 0011_forward_bay_reservation_at_return_signal.sql
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THIS CLOSES
-- ════════════════════════════════════════════════════════════════════════════════════════
-- The depot only learned that a vehicle needed a SERVICE or WASH bay once the vehicle was
-- already standing in the depot. Measured on run f86f9fda (2026-08-06), read BEFORE writing
-- a line of this file:
--
--   * ottoq.ottoq_book_appointment -- the function the return signal calls -- searched
--     stalls for stall_type IN ('dcfc','l2') and then 'staging'. Nothing else. It could
--     secure a charger or a parking space and NOTHING ELSE.
--   * Its only pre-arrival "reservation" was stalls.reserved_by + reservation_expires_at,
--     a TTL flag on the stalls row. It wrote ZERO rows to ottoq_stall_bookings, which is
--     the forward-occupancy calendar every other reader uses. Confirmed in the run's
--     booking ledger: every single charge_dcfc / charge_l2 / wash / detail row carries a
--     non-null `source`, i.e. all 8 charge and 2 wash rows were written at ENACTMENT.
--     The four rows with source IS NULL (2 detail, 4 service, ex-temp_hold) are planner
--     rows written by ottoq_book_workflow -- which is called ONLY from ottoq_decide_tick
--     and ottoq_place_unplaced_vehicles, both of which run on vehicles already inside the
--     depot walls.
--   * Consequence: a bay is only ever held once the car is at the door, so bays
--     oversubscribe. That is the opposite of a forward availability calendar.
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THIS DELIBERATELY REUSES (nothing here is rebuilt)
-- ════════════════════════════════════════════════════════════════════════════════════════
--   ottoq.ottoq_book_workflow        -- already walks planned legs, maps leg -> stall type,
--                                       forward-walks for capacity and stamps to_stall_id
--                                       so enactment ADOPTS the reservation instead of
--                                       booking a second row. It is generalised here, not
--                                       replaced: the whole body moves into
--                                       ottoq_book_workflow_legs and the 6-arg entry point
--                                       becomes a thin delegate with identical behaviour.
--   ottoq.ottoq_find_and_book_stall  -- picker + writer, already calendar-aware
--   ottoq.ottoq_book_stall           -- the ONLY writer of ottoq_stall_bookings
--   ottoq.ottoq_stall_free_between   -- the calendar read, state set aligned to _v3
--   public.ottoq_svc_to_leg_type     -- the TOTAL twin->OTTO-Q vocabulary mapping
--   public.service_cadence_policy    -- lane (the requirement) + est_min_default (the dwell)
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- THREE PREMISES OF THE BRIEF THAT DID NOT SURVIVE READING THE CODE
-- ════════════════════════════════════════════════════════════════════════════════════════
-- (P1) "Anchor the reservation on planned_return_at."
--      planned_return_at is a GENERATED column = dispatched_at + planned_duration_min. It is
--      the DISPATCH-TIME plan. It is NOT when the vehicle arrives. The twin's arrival test
--      (twin.ottoq_sim_advance_deployed_telemetry) is
--          p_sim_clock_now >= returning_started_at + return_eta_minutes
--      i.e. the vehicle arrives at exactly (return-signal clock + ETA) -- which is precisely
--      the v_eta_at that ottoq_book_appointment already computes. On the 13 dispatches of
--      run f86f9fda that completed a real return handshake inside the sim window, the
--      dispatch plan was a median 46.6 min away from the actual arrival while the live ETA
--      was 35.3 min away. Anchoring a 3-bay lane on the dispatch plan would reserve the bay
--      for a window the vehicle is provably not in the depot for.
--      DECISION: anchor on the LIVE arrival estimate; use planned_return_at as the FALLBACK
--      when there is no live ETA, and record both plus their divergence in the booking's
--      `why` so the choice is auditable rather than assumed.
--
-- (P2) "service_definitions.stall_type_required is the ONLY requirement column."
--      service_definitions does not speak the twin's vocabulary. Its 9 active codes are
--      cabin_filter, dcfc_charge, exterior_wash, full_detail, inspection, interior_detail,
--      l2_charge, tire_rotation, wiper_replace. The needs card's atoms are charge,
--      interior_tidy, sensor_clean, interior_deep_clean, exterior_wash, sensor_calibration,
--      mechanical_pm, fault_repair, cosmetic_repair, software_update, remote_diagnostics,
--      triage_check, item_retrieval, interior_inspection, readiness_check. The ONLY code in
--      both sets is exterior_wash -- 1 of 15. Worse, full_detail and interior_detail demand
--      stall_type 'detail_bay', and 0010 settled the depot at 115 staging / 30 l2 / 10 dcfc
--      / 3 wash_bay / 2 service_bay -- ZERO detail_bay stalls exist, so that requirement is
--      unbookable by construction.
--      DECISION: service_cadence_policy.lane is the live requirement column (it covers all
--      15 atoms and is what ottoq_decide_tick (4b) already uses). This migration adds
--      ottoq.ottoq_svc_to_stall_type, a TOTAL resolver that reads lane FIRST and falls back
--      to service_definitions.stall_type_required only when the lane is unknown AND a stall
--      of that type actually exists at the depot. Both columns are used; the live one wins.
--
-- (P3) "ottoq_plan_visit_itinerary is blocked because a deployed vehicle still owns its
--      OUTBOUND itinerary with an un-executed `depart` leg."
--      It does not. twin.ottoq_sim_dispatch_vehicle calls ottoq.ottoq_release_visit_artifacts
--      at dispatch, which skips every planned/active leg and sets the itinerary to
--      'completed'. Measured on run f86f9fda: 63 of 63 `depart` legs are status='skipped'
--      and every one of them sits on a 'completed' itinerary. Zero `depart` legs are
--      'planned'. A deployed vehicle owns NO active itinerary.
--      The guard is still real, and this migration still scopes it -- but the case it
--      actually blocks is different and worth naming: the leftover `inspect` leg. Every
--      itinerary ottoq_plan_visit_itinerary builds ends with a 3-minute 'inspect' leg, and
--      29 of them were still 'planned' on 34 'active' itineraries when the run ended. When
--      the twin regenerates a manifest for a vehicle that is already inside the depot
--      (twin.ottoq_sim_generate_service_manifest supersedes the OLD visit need and inserts
--      a NEW one, but closes NO itinerary), the stale itinerary's planned `inspect` leg
--      blocks the new visit from ever being planned. That is the hole this closes.
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- SAFETY POSTURE
-- ════════════════════════════════════════════════════════════════════════════════════════
--   * Nothing is dropped. One nullable column is added. Every function is CREATE OR REPLACE.
--   * Every new seam is a TOTAL function: an unknown service lands on 'service' or on NO
--     bay at all, and can never raise. (The 2026-08-01 leg_type lesson.)
--   * Every new step in ottoq_book_appointment is inside its own BEGIN ... EXCEPTION block:
--     the appointment survives a bay-reservation hiccup, exactly as it already survives a
--     manifest, charge-plan, workflow-plan or comms hiccup. This is the tick hot path.
--   * Three kill switches, all defaulting ON, all read through ottoq_policy_get so no row
--     needs to exist:
--         prearrival_bay_reservation      (1 = reserve bays at the return signal)
--         stale_itinerary_unblocks_replan (1 = a different visit's itinerary may not block)
--         prearrival_no_show_grace_min    (20 = minutes before an unused hold is released)
--   * No cuOpt, no Nemotron, no LP, no escalation ladder, no approval gate, no geometry.

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════════════════
-- (1) ONE ITINERARY PER VISIT -- the fact the guard was missing
-- ════════════════════════════════════════════════════════════════════════════════════════
-- ottoq_vehicle_itineraries had no idea WHICH visit it was planning for, so
-- ottoq_plan_visit_itinerary could only ask "does an active itinerary have planned legs?"
-- and had to answer conservatively for every visit, including the one it had never seen.
-- Nullable on purpose: pre-0011 rows stay NULL and keep the OLD blocking behaviour, so
-- this column can only ever unblock a case it can positively identify.
ALTER TABLE public.ottoq_vehicle_itineraries
  ADD COLUMN IF NOT EXISTS visit_id uuid;

COMMENT ON COLUMN public.ottoq_vehicle_itineraries.visit_id IS
  '0011: the ottoq_visit_needs.visit_id this itinerary was planned for. NULL on rows written '
  'before 0011. An active itinerary whose visit_id differs from the visit being planned is '
  'stale and may not block the new plan; NULL is treated as unknown and still blocks.';

CREATE INDEX IF NOT EXISTS ottoq_vehicle_itineraries_visit_idx
  ON public.ottoq_vehicle_itineraries (visit_id)
  WHERE visit_id IS NOT NULL;


-- ════════════════════════════════════════════════════════════════════════════════════════
-- (2) ottoq.ottoq_svc_to_stall_type -- TOTAL service -> physical requirement
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Returns the stall_type a service needs, or NULL when it needs no space of its own
-- (cabin / exterior / digital / gate work rides the charge stall; 'anchor' IS the charge
-- stall and is handled by the charge path, never here).
--
-- Reads service_cadence_policy.lane FIRST because that is the column the live catalogue
-- actually populates for all 15 twin services. service_definitions.stall_type_required is
-- consulted as a FALLBACK for vocabulary the cadence policy has not learned yet, and only
-- when a stall of that type is really seeded at the depot -- otherwise resolving
-- 'interior_detail' to the non-existent 'detail_bay' would silently make the work
-- unbookable instead of routing it to the wash lane.
--
-- TOTALITY: unknown service -> NULL -> no bay is reserved and nothing raises. An unknown
-- service still reaches a bay through ottoq_svc_to_leg_type's ELSE 'service' branch in the
-- itinerary, which this function then resolves as service_bay.
CREATE OR REPLACE FUNCTION ottoq.ottoq_svc_to_stall_type(p_svc text, p_depot_id uuid DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_lane text; v_req text;
BEGIN
  IF p_svc IS NULL THEN RETURN NULL; END IF;

  SELECT lane INTO v_lane
    FROM public.service_cadence_policy
   WHERE svc = p_svc AND is_active
   LIMIT 1;

  IF v_lane IS NOT NULL THEN
    RETURN CASE v_lane
      WHEN 'wash_bay'    THEN 'wash_bay'
      -- No detail_bay stalls are seeded (0010: 3 wash_bay, 2 service_bay). Detail shares the
      -- wash lane, exactly as ottoq_book_workflow and ottoq_decide_tick (4b) already do.
      WHEN 'detail'      THEN 'wash_bay'
      WHEN 'service_bay' THEN 'service_bay'
      ELSE NULL          -- anchor / cabin / exterior / digital / gate, and anything new
    END;
  END IF;

  -- Fallback: the catalogue table named in the brief. Only trusted when the type exists.
  SELECT sd.stall_type_required::text INTO v_req
    FROM public.service_definitions sd
   WHERE sd.code = p_svc AND sd.is_active
     AND (p_depot_id IS NULL OR sd.depot_id = p_depot_id)
   ORDER BY sd.depot_id = p_depot_id DESC NULLS LAST
   LIMIT 1;

  IF v_req IS NULL THEN RETURN NULL; END IF;
  IF v_req IN ('dcfc','l2','staging') THEN RETURN NULL; END IF;   -- not a bay
  IF NOT EXISTS (SELECT 1 FROM public.stalls s
                  WHERE s.stall_type::text = v_req
                    AND (p_depot_id IS NULL OR s.depot_id = p_depot_id)) THEN
    -- Requirement names a stall type the depot does not have. Route cleaning work to the
    -- wash lane; anything else to the service lane. Never return an unbookable type.
    RETURN CASE WHEN v_req LIKE '%detail%' OR v_req LIKE '%wash%' THEN 'wash_bay' ELSE 'service_bay' END;
  END IF;
  RETURN v_req;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;   -- TOTAL: a requirement we cannot resolve costs no bay, never a transaction
END
$function$;


-- ════════════════════════════════════════════════════════════════════════════════════════
-- (3) ottoq.ottoq_book_workflow_legs -- the generalised forward booker
-- ════════════════════════════════════════════════════════════════════════════════════════
-- This IS the body of ottoq_book_workflow, unchanged in substance, with three additions
-- needed to make it usable from the return signal:
--   p_leg_types   restrict to a subset of legs (the return signal books BAYS only; the
--                 charge stall keeps its existing reserved_by path untouched)
--   p_not_before  a floor on the window, so a bay can never be held for a moment before
--                 the vehicle can physically be there
--   p_source      stamped onto the booking so a pre-arrival hold is distinguishable from an
--                 enacted one in the SAME ledger (no parallel store)
CREATE OR REPLACE FUNCTION ottoq.ottoq_book_workflow_legs(
  p_sim_run_id     uuid,
  p_vehicle_id     uuid,
  p_depot_id       uuid,
  p_clock          timestamptz,
  p_max_shift_min  integer DEFAULT 240,
  p_shift_step_min integer DEFAULT 10,
  p_leg_types      text[]  DEFAULT NULL,
  p_not_before     timestamptz DEFAULT NULL,
  p_source         text    DEFAULT NULL)
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
       AND (p_leg_types IS NULL OR l.leg_type = ANY (p_leg_types))
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
        GREATEST(v_leg.planned_start_sim, COALESCE(p_not_before, v_leg.planned_start_sim)),
        GREATEST(v_leg.planned_end_sim,
                 GREATEST(v_leg.planned_start_sim, COALESCE(p_not_before, v_leg.planned_start_sim))
                   + interval '1 minute'),
        NULL, v_leg.leg_id);
      IF COALESCE((v_hold->>'booked')::boolean, false) THEN
        UPDATE public.ottoq_itinerary_legs
           SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                               WHERE b.booking_id = (v_hold->>'booking_id')::uuid)
         WHERE leg_id = v_leg.leg_id;
        IF p_source IS NOT NULL THEN
          UPDATE public.ottoq_stall_bookings SET source = COALESCE(source, p_source)
           WHERE booking_id = (v_hold->>'booking_id')::uuid;
        END IF;
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

    v_dur      := GREATEST(v_leg.planned_end_sim - v_leg.planned_start_sim, interval '1 minute');
    v_shift_min := 0;
    v_booking  := NULL;

    -- Try the planned window; if contended, walk forward until something opens.
    -- p_not_before is the arrival floor: a bay is never held for a moment the vehicle
    -- cannot physically be standing in it.
    WHILE v_booking IS NULL AND v_shift_min <= p_max_shift_min LOOP
      v_from := GREATEST(v_leg.planned_start_sim, COALESCE(p_not_before, v_leg.planned_start_sim))
                  + make_interval(mins => v_shift_min);
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
      IF p_source IS NOT NULL THEN
        UPDATE public.ottoq_stall_bookings SET source = COALESCE(source, p_source)
         WHERE booking_id = v_booking;
      END IF;
      v_booked := v_booked + 1;
      IF v_shift_min > 0 THEN v_shifted := v_shifted + 1; END IF;
      v_detail := v_detail || jsonb_build_object('seq', v_leg.seq, 'leg', v_leg.leg_type,
                    'booked', true, 'stall_type', v_want_type, 'shifted_min', v_shift_min,
                    'from', v_from, 'to', v_to);
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
$function$;


-- ════════════════════════════════════════════════════════════════════════════════════════
-- (3b) ottoq.ottoq_book_workflow -- unchanged behaviour, now a delegate
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Same signature, same semantics, ONE implementation. Callers (ottoq_decide_tick,
-- ottoq_place_unplaced_vehicles) are untouched and see identical behaviour: p_leg_types
-- NULL means every leg type, p_not_before NULL means the planned window stands, p_source
-- NULL means the booking's source is left for the enactment path to stamp.
CREATE OR REPLACE FUNCTION ottoq.ottoq_book_workflow(
  p_sim_run_id uuid, p_vehicle_id uuid, p_depot_id uuid, p_clock timestamptz,
  p_max_shift_min integer DEFAULT 240, p_shift_step_min integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT ottoq.ottoq_book_workflow_legs(
           p_sim_run_id, p_vehicle_id, p_depot_id, p_clock,
           p_max_shift_min, p_shift_step_min, NULL, NULL, NULL);
$function$;


-- ════════════════════════════════════════════════════════════════════════════════════════
-- (4) public.ottoq_plan_visit_itinerary -- the guard, scoped rather than deleted
-- ════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THE GUARD PROTECTS: re-entering this function on an itinerary that is already fully
-- planned would append a SECOND complete set of legs (v_seq continues from MAX(seq)), and
-- every one of those duplicate legs is a candidate for a duplicate stall booking. That
-- protection is kept, exactly, for the visit the itinerary belongs to.
--
-- WHAT CHANGES: an active itinerary that belongs to a DIFFERENT, already-superseded visit
-- is stale. It is closed the same way a redeploy closes one (planned legs -> 'skipped',
-- itinerary -> 'completed') and planning proceeds for the visit that is actually inbound.
-- Rows written before 0011 have visit_id NULL, are treated as unknown, and still block.
--
-- ALSO: the bay-loop dwell now falls back to service_cadence_policy.est_min_default instead
-- of a hardcoded 20 minutes when the atom carries no est_min. A dwell window is a lookup.
CREATE OR REPLACE FUNCTION public.ottoq_plan_visit_itinerary(p_sim_run_id uuid, p_vehicle uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_visit RECORD; v_veh RECORD; v_itin uuid; v_depot uuid;
  v_a jsonb; v_cursor timestamptz; v_charge_start timestamptz; v_charge_end timestamptz;
  v_min numeric; v_seq int := 0; v_n int := 0;
  v_wash_wait numeric; v_svc_wait numeric;
  v_charger_kw numeric; v_charge_leg_type text;
  v_itin_visit uuid;                       -- 0011
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
  SELECT vn.visit_id, vn.atoms, vn.urgency, vn.dispatch_due_at, vn.target_soc INTO v_visit
    FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress')
   ORDER BY vn.created_at DESC LIMIT 1;
  IF v_visit.visit_id IS NULL THEN RETURN 0; END IF;
  SELECT home_depot_id, current_soc, COALESCE(inlet_max_kw,150) AS inlet_kw,
         COALESCE(battery_capacity_kwh,75) AS pack_kwh
    INTO v_veh FROM vehicles WHERE id = p_vehicle;
  v_depot := v_veh.home_depot_id;

  SELECT itinerary_id, visit_id INTO v_itin, v_itin_visit
    FROM ottoq_vehicle_itineraries
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle AND status = 'active'
   ORDER BY created_at DESC LIMIT 1;

  -- ══════════════════ 0011: STALE-ITINERARY UNBLOCK ══════════════════
  -- An active itinerary that names a DIFFERENT visit is a leftover. Closing it is the same
  -- act ottoq_release_visit_artifacts performs at redeploy, so no new lifecycle is invented.
  IF v_itin IS NOT NULL
     AND v_itin_visit IS NOT NULL
     AND v_itin_visit <> v_visit.visit_id
     AND public.ottoq_policy_get(p_sim_run_id, 'stale_itinerary_unblocks_replan', 1) >= 1 THEN
    UPDATE ottoq_itinerary_legs SET status = 'skipped'
     WHERE itinerary_id = v_itin AND status IN ('planned');
    UPDATE ottoq_vehicle_itineraries SET status = 'completed' WHERE itinerary_id = v_itin;
    v_itin := NULL; v_itin_visit := NULL;
  END IF;

  -- Unchanged protection: never double-plan the visit this itinerary already covers.
  IF v_itin IS NOT NULL AND EXISTS (SELECT 1 FROM ottoq_itinerary_legs
        WHERE itinerary_id = v_itin AND status = 'planned') THEN
    RETURN 0;
  END IF;
  IF v_itin IS NULL THEN
    INSERT INTO ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at, visit_id)
    VALUES (p_sim_run_id, v_depot, p_vehicle, 'flow_contract_m4', p_clock, v_visit.visit_id)
    RETURNING itinerary_id INTO v_itin;
  ELSE
    -- Appending to an existing active itinerary for this same visit: stamp the visit if the
    -- row predates 0011, so the next call can tell stale from current.
    UPDATE ottoq_vehicle_itineraries SET visit_id = COALESCE(visit_id, v_visit.visit_id)
     WHERE itinerary_id = v_itin;
  END IF;
  SELECT COALESCE(MAX(seq),0) INTO v_seq FROM ottoq_itinerary_legs WHERE itinerary_id = v_itin;

  SELECT count(*) * 10.0 / GREATEST(1, ottoq_sim_lane_capacity(NULL,'cleaning_staff',3)) INTO v_wash_wait
    FROM vehicles WHERE home_depot_id = v_depot AND current_state IN ('in_wash_bay','in_detail_bay');
  SELECT count(*) * 40.0 / GREATEST(1, ottoq_sim_lane_capacity(NULL,'service_staff',2)) INTO v_svc_wait
    FROM vehicles WHERE home_depot_id = v_depot AND current_state = 'in_service_bay';

  v_cursor := p_clock;

  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_visit.atoms) a
              WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')) THEN
    SELECT a INTO v_a FROM jsonb_array_elements(v_visit.atoms) a
     WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled') LIMIT 1;
    v_charger_kw := (CASE WHEN v_veh.current_soc < 45 THEN 100 ELSE 11 END);
    v_charge_leg_type := (CASE WHEN v_veh.current_soc < 45 THEN 'charge_dcfc' ELSE 'charge_l2' END);
    BEGIN
      SELECT ottoq_estimate_charge_minutes(v_veh.current_soc,
             COALESCE((v_a->>'target_soc')::numeric, v_visit.target_soc, 80),
             v_charger_kw, v_veh.inlet_kw, v_veh.pack_kwh, 20, 100, 1.0) INTO v_min;
    EXCEPTION WHEN OTHERS THEN
      v_min := GREATEST(10, (COALESCE((v_a->>'target_soc')::numeric, 80) - v_veh.current_soc) * 1.2);
    END;
    v_min := COALESCE(v_min, 25);
    v_charge_start := v_cursor; v_charge_end := v_cursor + (v_min::text || ' minutes')::interval;
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, v_charge_leg_type, v_charge_start, v_charge_end,
           (v_min*60)::int, jsonb_build_object('kind','flow_contract','charger_kw_assumed',v_charger_kw), 'planned');
    FOR v_a IN SELECT a FROM jsonb_array_elements(v_visit.atoms) a LOOP
      IF v_a->>'concurrency' IN ('cabin','exterior','digital')
         AND v_a->>'svc' NOT IN ('readiness_check')
         AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
        v_seq := v_seq + 1; v_n := v_n + 1;
        INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
               planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
        VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, public.ottoq_svc_to_leg_type(v_a->>'svc'), v_charge_start,
               v_charge_start + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval,
               (COALESCE((v_a->>'est_min')::numeric,5)*60)::int,
               jsonb_build_object('kind','flow_contract','concurrent_with','charge','atom',v_a->>'svc'), 'planned');
      END IF;
    END LOOP;
    v_cursor := v_charge_end;
  ELSE
    FOR v_a IN SELECT a FROM jsonb_array_elements(v_visit.atoms) a LOOP
      IF v_a->>'concurrency' IN ('cabin','exterior','digital')
         AND v_a->>'svc' NOT IN ('readiness_check')
         AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
        v_seq := v_seq + 1; v_n := v_n + 1;
        INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
               planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
        VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, public.ottoq_svc_to_leg_type(v_a->>'svc'), v_cursor,
               v_cursor + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval,
               (COALESCE((v_a->>'est_min')::numeric,5)*60)::int,
               jsonb_build_object('kind','flow_contract','atom',v_a->>'svc'), 'planned');
      END IF;
    END LOOP;
    v_cursor := v_cursor + interval '10 minutes';
  END IF;

  FOR v_a IN
    SELECT a FROM jsonb_array_elements(v_visit.atoms) a
    WHERE a->>'concurrency' = 'bay' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
    ORDER BY (CASE a->>'svc' WHEN 'exterior_wash' THEN 1 WHEN 'interior_deep_clean' THEN 2
                             WHEN 'sensor_calibration' THEN 3 WHEN 'mechanical_pm' THEN 4
                             WHEN 'fault_repair' THEN 5 ELSE 6 END)
  LOOP
    -- Duration is the SERVICE time only; the forward calendar expresses contention
      -- by moving the leg, not by inflating it. (queue_wait_min is still recorded in
      -- duration_basis below for diagnostics.)
      -- 0011: the dwell is a LOOKUP. Atom est_min first (the manifest already priced it),
      -- then service_cadence_policy.est_min_default, then 20 as a last resort.
      v_min := COALESCE((v_a->>'est_min')::numeric,
                        (SELECT scp.est_min_default FROM public.service_cadence_policy scp
                          WHERE scp.svc = v_a->>'svc' AND scp.is_active LIMIT 1),
                        20);
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq,
           (CASE v_a->>'svc' WHEN 'exterior_wash' THEN 'wash' WHEN 'interior_deep_clean' THEN 'detail'
                             ELSE 'service' END),
           v_cursor, v_cursor + (v_min::text || ' minutes')::interval, (v_min*60)::int,
           jsonb_build_object('kind','flow_contract','atom',v_a->>'svc','queue_wait_min',
             round((CASE WHEN v_a->>'requires_bay' IN ('wash_bay','detail') THEN COALESCE(v_wash_wait,0) ELSE COALESCE(v_svc_wait,0) END),1)), 'planned');
    v_cursor := v_cursor + (v_min::text || ' minutes')::interval;
  END LOOP;

  IF v_visit.urgency = 'overnight_hold' AND v_visit.dispatch_due_at IS NOT NULL AND v_visit.dispatch_due_at > v_cursor THEN
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, 'stage', v_cursor, v_visit.dispatch_due_at,
           GREATEST(0, EXTRACT(EPOCH FROM (v_visit.dispatch_due_at - v_cursor)))::int,
           jsonb_build_object('kind','flow_contract','reason','overnight_hold'), 'planned');
    v_cursor := v_visit.dispatch_due_at;
  END IF;
  v_seq := v_seq + 1; v_n := v_n + 1;
  INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
         planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
  VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, 'inspect', v_cursor, v_cursor + interval '3 minutes',
         180, jsonb_build_object('kind','flow_contract','atom','readiness_check'), 'planned');
  RETURN v_n;
END; $function$;


-- ════════════════════════════════════════════════════════════════════════════════════════
-- (5) ottoq.ottoq_reserve_inbound_bays -- THE NEW ACT
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Called from the return signal, once, while the vehicle is still deployed. It does exactly
-- one thing: put the vehicle's BAY work on the forward calendar, anchored on when the
-- vehicle will actually be at the depot.
--
-- ANCHOR (see P1 in the header). Live arrival estimate first (p_eta_at, which the twin's own
-- arrival test reproduces exactly), dispatch plan second, +30 min last. Never earlier than
-- one minute from now. Both anchors and their divergence are written into the visit's meta,
-- so a reader can always see which one was used and how far apart they were.
--
-- CHARGE IS NOT TOUCHED. p_leg_types is bays only. The charge stall keeps the reserved_by
-- TTL path that is measured working today; this migration does not move it.
--
-- ATOMIC VISIT. The bay windows come from the itinerary, whose cursor starts at the arrival
-- anchor and advances past the charge leg first, then each bay leg in cadence order. So the
-- reserved window is (arrival + charge + preceding bays), which is the atomic-visit ordering
-- rather than an independent guess.
--
-- HOLD, DO NOT DEPLOY DIRTY. If no bay can be found anywhere in the forward horizon, nothing
-- is booked and 'unbookable' is reported. The need STAYS OPEN on ottoq_visit_needs, which is
-- what keeps the vehicle from being redeployed with outstanding work -- the existing hold,
-- not a new one. The miss is recorded so it is visible instead of silent.
CREATE OR REPLACE FUNCTION ottoq.ottoq_reserve_inbound_bays(
  p_sim_run_id   uuid,
  p_vehicle_id   uuid,
  p_depot_id     uuid,
  p_signal_clock timestamptz,
  p_eta_at       timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_arrival   timestamptz;
  v_plan_at   timestamptz;
  v_visit     uuid;
  v_res       jsonb;
  v_wanted    int := 0;
  v_anchor    text;
  v_horizon   int;
BEGIN
  IF public.ottoq_policy_get(p_sim_run_id, 'prearrival_bay_reservation', 1) < 1 THEN
    RETURN jsonb_build_object('enabled', false);
  END IF;
  IF p_sim_run_id IS NULL OR p_vehicle_id IS NULL OR p_depot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_key');
  END IF;

  -- The dispatch-time plan, for the record and as the fallback anchor.
  SELECT d.planned_return_at INTO v_plan_at
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.vehicle_id = p_vehicle_id
     AND d.sim_run_id IS NOT DISTINCT FROM p_sim_run_id
     AND d.status IN ('active','returning')
   ORDER BY d.dispatched_at DESC LIMIT 1;

  v_anchor  := CASE WHEN p_eta_at IS NOT NULL THEN 'live_eta'
                    WHEN v_plan_at IS NOT NULL AND v_plan_at > p_signal_clock THEN 'planned_return_at'
                    ELSE 'default_30min' END;
  v_arrival := GREATEST(
                 COALESCE(p_eta_at,
                          CASE WHEN v_plan_at > p_signal_clock THEN v_plan_at END,
                          p_signal_clock + interval '30 minutes'),
                 p_signal_clock + interval '1 minute');

  SELECT vn.visit_id INTO v_visit
    FROM public.ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle_id
     AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id
     AND vn.status IN ('open','in_progress')
   ORDER BY vn.created_at DESC LIMIT 1;

  SELECT count(*)::int INTO v_wanted
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = p_vehicle_id
     AND l.status = 'planned' AND l.to_stall_id IS NULL
     AND l.leg_type IN ('wash','detail','service');

  IF v_wanted = 0 THEN
    RETURN jsonb_build_object('ok', true, 'bays_needed', 0, 'booked', 0,
                              'anchor', v_anchor, 'arrival_at', v_arrival,
                              'planned_return_at', v_plan_at);
  END IF;

  v_horizon := GREATEST(public.ottoq_policy_get(p_sim_run_id, 'prearrival_shift_horizon_min', 240), 10)::int;

  v_res := ottoq.ottoq_book_workflow_legs(
             p_sim_run_id, p_vehicle_id, p_depot_id,
             p_signal_clock,                       -- cursor floor: legs must end in the future
             v_horizon, 10,
             ARRAY['wash','detail','service'],     -- BAYS ONLY. Charge keeps its own path.
             v_arrival,                            -- never before the vehicle can be here
             'return_signal_prearrival');

  v_res := COALESCE(v_res, '{}'::jsonb) || jsonb_build_object(
    'ok', true,
    'bays_needed', v_wanted,
    'anchor', v_anchor,
    'arrival_at', v_arrival,
    'live_eta_at', p_eta_at,
    'planned_return_at', v_plan_at,
    'plan_minus_live_min', CASE WHEN v_plan_at IS NOT NULL AND p_eta_at IS NOT NULL
      THEN round((EXTRACT(EPOCH FROM (v_plan_at - p_eta_at)) / 60.0)::numeric, 1) END,
    'signal_clock', p_signal_clock,
    'hold_required', (COALESCE((v_res->>'unbookable')::int, 0) > 0));

  -- Truthful record in the SAME place the workflow plan already lives. No parallel store.
  BEGIN
    UPDATE public.ottoq_visit_needs vn
       SET meta = COALESCE(vn.meta,'{}'::jsonb) || jsonb_build_object('bay_reservation', v_res)
     WHERE vn.visit_id = v_visit;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_res;
EXCEPTION WHEN OTHERS THEN
  -- TOTAL. A bay we cannot reserve must never cost the appointment or the tick.
  RETURN jsonb_build_object('ok', false, 'reason', 'reserve_error', 'sqlstate', SQLSTATE);
END
$function$;


-- ════════════════════════════════════════════════════════════════════════════════════════
-- (6) ottoq.ottoq_release_expired_bookings -- the leak closer
-- ════════════════════════════════════════════════════════════════════════════════════════
-- A forward reservation made before arrival can be orphaned in two ways the existing closer
-- cannot see, because that closer only fires once the window has FULLY elapsed
-- (upper(during) <= clock) -- which for a bay held hours ahead means hours of dead capacity,
-- and, worse, ottoq_book_stall's one-live-bay-reservation-per-purpose rule means that dead
-- hold BLOCKS the vehicle's next attempt to reserve the same kind of bay.
--
--  (a) the visit it was reserved for is gone (manifest regenerated, needs superseded, visit
--      completed) -> the reservation has nothing left to serve
--  (b) the window OPENED and the vehicle never took it -> no-show. A real arrival flips the
--      hold to 'active' (ottoq_activate_due_bay_reservations / ottoq_activate_present_bookings),
--      so anything still 'held' more than prearrival_no_show_grace_min after its window
--      opened is capacity nobody is standing in.
--
-- Both are scoped to source='return_signal_prearrival', so this can only ever release rows
-- THIS migration created. Enacted bookings and planner bookings are untouched.
-- Released rows leave the exclusion constraints' live state set, so the capacity is genuinely
-- returned to the calendar rather than merely relabelled.
CREATE OR REPLACE FUNCTION ottoq.ottoq_release_expired_bookings(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int; v_rows jsonb := '[]'::jsonb; v_rec jsonb; v_depot uuid; v_grace int; v_pre int := 0;
BEGIN
  -- ══════════════ 0011: PRE-ARRIVAL NO-SHOW / DEAD-VISIT RELEASE ══════════════
  -- Runs FIRST so the capacity is free for this same tick's planning, and in its own block
  -- so it can never cost the closer that follows it.
  BEGIN
    v_grace := GREATEST(public.ottoq_policy_get(p_sim_run_id, 'prearrival_no_show_grace_min', 20), 1)::int;
    UPDATE public.ottoq_stall_bookings b
       SET state          = 'released',
           released_at    = p_clock,
           release_reason = CASE
             WHEN b.visit_id IS NOT NULL AND NOT EXISTS (
                    SELECT 1 FROM public.ottoq_visit_needs vn
                     WHERE vn.visit_id = b.visit_id AND vn.status IN ('open','in_progress'))
               THEN 'prearrival_visit_superseded'
             ELSE 'prearrival_no_show' END
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state = 'held'
       AND b.source = 'return_signal_prearrival'
       AND (
             (b.visit_id IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM public.ottoq_visit_needs vn
                 WHERE vn.visit_id = b.visit_id AND vn.status IN ('open','in_progress')))
          OR lower(b.during) < p_clock - make_interval(mins => v_grace)
           );
    GET DIAGNOSTICS v_pre = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_release_expired_bookings: prearrival sweep failed sqlstate=% msg=%', SQLSTATE, SQLERRM;
    v_pre := 0;
  END;

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

  RETURN COALESCE(v_n,0) + COALESCE(v_pre,0);

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_release_expired_bookings: FAILED sqlstate=% msg=% run=%',
    SQLSTATE, SQLERRM, p_sim_run_id;
  RETURN 0;
END
$function$;


-- ════════════════════════════════════════════════════════════════════════════════════════
-- (7) ottoq.ottoq_book_appointment -- the return signal now reserves BAYS, not just a plug
-- ════════════════════════════════════════════════════════════════════════════════════════
-- ONE new step, placed immediately after the inbound itinerary is planned and BEFORE the
-- charge-stall search. That position is deliberate: the bay a vehicle needs in two hours does
-- not depend on whether a charger is free right now, and the old code's
-- `RETURN ... 'no_free_stall'` early-exit would otherwise skip the bay reservation entirely
-- on exactly the busy ticks where holding a bay matters most.
--
-- Everything else in this function is byte-identical to the version 0011 replaced.
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
  v_bays jsonb;   -- 0011
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

  -- ══════════════ 0011: FORWARD BAY RESERVATION AT THE RETURN SIGNAL ══════════════
  -- The vehicle is still deployed. The itinerary above laid its bay work out from the
  -- arrival estimate forward (charge first, then bays in cadence order); this puts those
  -- windows on ottoq_stall_bookings, the same ledger everything else reads, with a source
  -- that says plainly that they are pre-arrival holds.
  BEGIN
    v_bays := ottoq.ottoq_reserve_inbound_bays(p_sim_run_id, p_vehicle_id, v_depot, p_clock, v_eta_at);
  EXCEPTION WHEN OTHERS THEN
    v_bays := jsonb_build_object('ok', false, 'reason', 'bay_reservation_error');
  END;

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
    -- 0011: the bay reservation is reported even here. No charger and no staging space right
    -- now does NOT mean the depot forgot the service work it just committed to.
    RETURN jsonb_build_object('secured', false, 'reason', 'no_free_stall',
                              'has_charge', v_has_charge, 'want_class', v_want_class,
                              'bay_reservation', v_bays);
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
                         'workflow', COALESCE(v_atoms, '[]'::jsonb), 'plan', v_plan, 'trigger', p_trigger, 'urgency', p_urgency,
                         'bay_reservation', v_bays),
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
                            'plan_total_min', v_plan->>'total_min',
                            'bay_reservation', v_bays);
END;
$function$;

COMMIT;
