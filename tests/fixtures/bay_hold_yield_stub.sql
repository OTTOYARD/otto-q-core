-- tests/fixtures/bay_hold_yield_stub.sql: the bay yield and its ETA as live, for tests/test_bay_hold_eta_reads_charge_sql.py
-- (db/migrations/0785). Loaded after tests/fixtures/agent_charge_order_stub.sql (vehicles, stalls, bookings, runs, the
-- policy reader, the one charge target) and tests/fixtures/bay_activation_stub.sql (the itinerary legs, the reconcile's
-- log, the calendar's no-overlap constraint, the event stand-in). Read from the live catalog on 2026-10-25 at 22:49 UTC
-- (5:49 PM CT); the test asserts each md5 of prosrc: ottoq.ottoq_bay_hold_car_eta 12670129 and
-- ottoq.ottoq_yield_bay_holds fd2c5cfe, both as 0553 left them. The charge sessions table carries only the columns the
-- ETA reads.
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid,
  sim_run_id uuid, status text, started_at timestamptz, ended_at timestamptz, soc_start numeric, soc_end numeric);

CREATE OR REPLACE FUNCTION ottoq.ottoq_bay_hold_car_eta(p_sim_run_id uuid, p_vehicle_id uuid, p_clock timestamp with time zone, p_taxi_min numeric)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
-- 0553 (G283): the earliest a car holding a bay booking could be at the bay. NULL: it could come now, or it is not known;
-- a NULL never yields a hold. 'infinity': not before something it has not started (a charge it owes) or it has left.
DECLARE
  v RECORD; v_threshold numeric; v_end timestamptz; v_sess RECORD; v_min_per_pt numeric;
  v_taxi interval := make_interval(secs => GREATEST(COALESCE(p_taxi_min, 0), 0) * 60);
BEGIN
  IF p_sim_run_id IS NULL OR p_vehicle_id IS NULL OR p_clock IS NULL THEN RETURN NULL; END IF;
  SELECT current_state::text AS state, current_soc, config INTO v FROM public.vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF v.state IN ('offline', 'deployed', 'en_route_to_deployment', 'out_of_service', 'tow_requested') THEN
    RETURN 'infinity'::timestamptz;
  END IF;
  IF v.state IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay') THEN
    RETURN GREATEST(COALESCE(NULLIF(v.config->>'service_ends_at', 'null')::timestamptz, p_clock), p_clock) + v_taxi;
  END IF;
  IF v.state IN ('charging_dcfc', 'charging_l2') THEN
    SELECT max(l.planned_end_sim) INTO v_end
      FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = p_vehicle_id
       AND l.leg_type IN ('charge_l2', 'charge_dcfc') AND l.status IN ('planned', 'active', 'in_progress')
       AND l.actual_end_sim IS NULL AND l.planned_end_sim > p_clock;
    IF v_end IS NULL THEN
      -- The charge has outrun its plan (G240). What is left, at this session's own pace so far; no pace, no ETA.
      SELECT o.started_at, o.soc_start INTO v_sess FROM public.ocpp_sessions o
       WHERE o.vehicle_id = p_vehicle_id AND o.sim_run_id = p_sim_run_id AND o.status = 'active'
       ORDER BY o.started_at DESC LIMIT 1;
      IF v_sess.started_at IS NULL OR COALESCE(v.current_soc, 0) - COALESCE(v_sess.soc_start, 0) < 2 THEN RETURN NULL; END IF;
      v_min_per_pt := EXTRACT(EPOCH FROM (p_clock - v_sess.started_at)) / 60.0 / (v.current_soc - v_sess.soc_start);
      v_end := p_clock + make_interval(secs => GREATEST(public.ottoq_effective_target_soc_at(p_vehicle_id, p_clock) - 1
                                                        - v.current_soc, 0) * v_min_per_pt * 60);
    END IF;
    RETURN v_end + v_taxi;
  END IF;
  v_threshold := COALESCE((SELECT vn.target_soc FROM public.ottoq_visit_needs vn
                            WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open', 'in_progress')
                              AND vn.sim_run_id = p_sim_run_id
                            ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1),
                          public.ottoq_default_target_soc()) - 1;
  IF COALESCE(v.current_soc, 0) < v_threshold THEN
    RETURN 'infinity'::timestamptz;   -- owes a charge it has not started: the needs card seats it in a bay only after
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END $function$
;

CREATE OR REPLACE FUNCTION ottoq.ottoq_yield_bay_holds(p_sim_run_id uuid, p_depot_id uuid, p_stall_type text, p_from timestamp with time zone, p_until timestamp with time zone, p_for_vehicle uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
-- 0553 (G283, CLAUDE.md rule 9): a hold for a car that cannot be at the bay before the waiting car would finish gives way
-- to the waiting car. Frees at most one bay. Never raises.
DECLARE
  v_taxi numeric; v_bay RECORD; v_h RECORD; v_eta timestamptz; v_ok boolean; v_n int := 0;
  v_dur interval; v_try timestamptz; v_shift int; v_moved boolean; v_seq int; v_state text;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_from IS NULL OR p_until IS NULL OR p_until <= p_from
     OR p_stall_type IS NULL OR p_stall_type NOT IN ('wash_bay', 'service_bay') THEN
    RETURN 0;
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_hold_yield_enabled', 1), 1) < 1 THEN RETURN 0; END IF;
  v_taxi := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_taxi_min', 3), 3), 0);

  FOR v_bay IN
    SELECT s.id, s.stall_code
      FROM public.stalls s
     WHERE s.depot_id = p_depot_id AND s.stall_type::text = p_stall_type
       AND s.status NOT IN ('maintenance', 'closed')
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_for_vehicle
            OR s.reservation_expires_at IS NULL OR s.reservation_expires_at <= p_from)
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                        WHERE b.stall_id = s.id AND b.sim_run_id = p_sim_run_id
                          AND b.state IN ('active', 'done', 'interrupted')
                          AND b.during && tstzrange(p_from, p_until, '[)'))
       AND EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                    WHERE b.stall_id = s.id AND b.sim_run_id = p_sim_run_id AND b.state = 'held'
                      AND b.during && tstzrange(p_from, p_until, '[)'))
     ORDER BY s.distance_from_entrance NULLS LAST, s.stall_code
  LOOP
    -- The bay can be freed only if every hold in the window is another car's that cannot be here before p_until.
    v_ok := true;
    FOR v_h IN
      SELECT b.vehicle_id,
             EXISTS (SELECT 1 FROM public.ottoq_itinerary_legs l
                      WHERE l.leg_id = b.leg_id AND l.status IN ('done', 'skipped')) AS leg_closed
        FROM public.ottoq_stall_bookings b
       WHERE b.stall_id = v_bay.id AND b.sim_run_id = p_sim_run_id AND b.state = 'held'
         AND b.during && tstzrange(p_from, p_until, '[)')
    LOOP
      IF v_h.vehicle_id IS NOT DISTINCT FROM p_for_vehicle THEN v_ok := false; EXIT; END IF;
      CONTINUE WHEN v_h.leg_closed;   -- the work this hold was booked for is done
      v_eta := ottoq.ottoq_bay_hold_car_eta(p_sim_run_id, v_h.vehicle_id, p_from, v_taxi);
      IF v_eta IS NULL OR v_eta < p_until THEN v_ok := false; EXIT; END IF;
    END LOOP;
    CONTINUE WHEN NOT v_ok;

    FOR v_h IN
      SELECT b.booking_id, b.vehicle_id, b.leg_id, b.purpose, lower(b.during) AS lo, upper(b.during) AS hi,
             (SELECT l.status FROM public.ottoq_itinerary_legs l
               WHERE l.leg_id = b.leg_id AND l.status IN ('done', 'skipped')) AS leg_closed_as
        FROM public.ottoq_stall_bookings b
       WHERE b.stall_id = v_bay.id AND b.sim_run_id = p_sim_run_id AND b.state = 'held'
         AND b.during && tstzrange(p_from, p_until, '[)')
       ORDER BY lower(b.during), b.booking_id
    LOOP
      v_eta := ottoq.ottoq_bay_hold_car_eta(p_sim_run_id, v_h.vehicle_id, p_from, v_taxi);
      SELECT current_state::text INTO v_state FROM public.vehicles WHERE id = v_h.vehicle_id;
      SELECT count(*) INTO v_seq FROM public.bay_reservation_reconcile_2026_08_02 r
       WHERE r.booking_id = v_h.booking_id AND r.action = 'deferred';
      IF v_h.leg_closed_as IS NOT NULL THEN
        -- the work it was booked for is finished; nothing will ever take this hold up
        UPDATE public.ottoq_stall_bookings
           SET state = 'released', released_at = p_from, release_reason = 'replanned_leg_closed'
         WHERE booking_id = v_h.booking_id AND state = 'held';
        INSERT INTO public.bay_reservation_reconcile_2026_08_02
          (sim_run_id, booking_id, vehicle_id, stall_id, purpose, sim_clock, action, reason, blocked_by,
           old_from, old_to, defer_seq)
        VALUES (p_sim_run_id, v_h.booking_id, v_h.vehicle_id, v_bay.id, v_h.purpose, p_from, 'released',
                'replanned_leg_closed', 'yield:leg_' || v_h.leg_closed_as, v_h.lo, v_h.hi, v_seq);
        v_n := v_n + 1;
        CONTINUE;
      END IF;
      IF v_state IN ('offline', 'deployed', 'en_route_to_deployment', 'out_of_service', 'tow_requested') THEN
        UPDATE public.ottoq_stall_bookings
           SET state = 'released', released_at = p_from, release_reason = 'replanned_vehicle_absent'
         WHERE booking_id = v_h.booking_id AND state = 'held';
        INSERT INTO public.bay_reservation_reconcile_2026_08_02
          (sim_run_id, booking_id, vehicle_id, stall_id, purpose, sim_clock, action, reason, blocked_by,
           old_from, old_to, defer_seq)
        VALUES (p_sim_run_id, v_h.booking_id, v_h.vehicle_id, v_bay.id, v_h.purpose, p_from, 'released',
                'replanned_vehicle_absent', 'yield:' || v_state, v_h.lo, v_h.hi, v_seq);
        v_n := v_n + 1;
        CONTINUE;
      END IF;
      v_dur := v_h.hi - v_h.lo;
      v_moved := false; v_shift := 0;
      WHILE NOT v_moved AND v_shift <= 240 LOOP
        v_try := GREATEST(CASE WHEN v_eta = 'infinity'::timestamptz THEN p_until ELSE v_eta END, p_until)
                 + make_interval(mins => v_shift);
        BEGIN
          UPDATE public.ottoq_stall_bookings SET during = tstzrange(v_try, v_try + v_dur, '[)')
           WHERE booking_id = v_h.booking_id AND state = 'held';
          v_moved := true;
        EXCEPTION WHEN exclusion_violation THEN
          v_shift := v_shift + 10;
        END;
      END LOOP;
      IF v_moved THEN
        IF v_h.leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs SET planned_start_sim = v_try, planned_end_sim = v_try + v_dur
           WHERE leg_id = v_h.leg_id AND status = 'planned';
        END IF;
        INSERT INTO public.bay_reservation_reconcile_2026_08_02
          (sim_run_id, booking_id, vehicle_id, stall_id, purpose, sim_clock, action, reason, blocked_by,
           old_from, old_to, new_from, new_to, defer_seq, eta)
        VALUES (p_sim_run_id, v_h.booking_id, v_h.vehicle_id, v_bay.id, v_h.purpose, p_from, 'deferred',
                'yielded_to_a_car_waiting_now',
                'yield:' || CASE WHEN v_eta = 'infinity'::timestamptz THEN 'owes_a_charge' ELSE v_state END,
                v_h.lo, v_h.hi, v_try, v_try + v_dur, v_seq + 1,
                CASE WHEN v_eta = 'infinity'::timestamptz THEN NULL ELSE v_eta END);
      ELSE
        UPDATE public.ottoq_stall_bookings
           SET state = 'released', released_at = p_from, release_reason = 'replanned_no_window'
         WHERE booking_id = v_h.booking_id AND state = 'held';
        INSERT INTO public.bay_reservation_reconcile_2026_08_02
          (sim_run_id, booking_id, vehicle_id, stall_id, purpose, sim_clock, action, reason, blocked_by,
           old_from, old_to, defer_seq)
        VALUES (p_sim_run_id, v_h.booking_id, v_h.vehicle_id, v_bay.id, v_h.purpose, p_from, 'released',
                'replanned_no_window', 'yield:' || v_state, v_h.lo, v_h.hi, v_seq);
      END IF;
      v_n := v_n + 1;
    END LOOP;

    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'bay_hold_yield',
        p_event_type := 'ottoq.bay_hold_yielded', p_entity_type := 'stall', p_entity_id := v_bay.id,
        p_payload := jsonb_build_object('for_vehicle', p_for_vehicle, 'window_from', p_from, 'window_until', p_until,
          'holds_moved_or_released', v_n, 'stall_code', v_bay.stall_code,
          'note', 'held for cars that could not be here before the waiting car would finish; each hold moved to its car''s ETA'),
        p_severity := 'info', p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'ottoq_yield_bay_holds: event not written (%): %', SQLSTATE, SQLERRM;
    END;
    RETURN v_n;
  END LOOP;
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_yield_bay_holds: FAILED sqlstate=% msg=% run=% depot=% type=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id, p_stall_type;
  RETURN 0;
END $function$
;
