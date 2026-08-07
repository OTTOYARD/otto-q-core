-- migration-version: 20260807015854
-- migration-name:    bay_seat_writes_the_twin_service_timer
--
-- ============================================================================
-- 0016  A SEATED CAR MUST CARRY THE TWIN'S SERVICE TIMER
-- ============================================================================
--
-- WHAT BROKE, AND HOW IT WAS FOUND
--
--   0015 made forward bay reservations actually bind. Run 28e758b8 (busy_day,
--   seed 424242) produced the first causal binding of a 0011 return-signal hold:
--   booking 3f2c6a2b, vehicle 0d43459d, purpose 'service', reserved at sim 13:06
--   for a 14:28 window, SEATED AT 13:48 -- 40 sim-min ahead of its forecast --
--   with the vehicle physically in the reserved stall. The mechanism works.
--
--   But that booking ended 'interrupted' (bay_exit_before_planned_end) after
--   4 minutes of a 38-minute plan, and so did every other early seat. Measured
--   on that run, grouped by the path that seated the car:
--
--       seat path                        legs  planned_min  actual_min  <25% of plan
--       bay_reservation_activated_early     5         15.2         2.9             3
--       (null / twin-driven)                3         17.7        21.0             0
--       bay_reconcile_twin_admit            2         38.2        38.2             0
--
--   6 of the run's 15 twin.service_completed events carried self_healed=true.
--
-- ROOT CAUSE -- A PARTIAL VOCABULARY SEAM
--
--   twin.ottoq_sim_advance_service_flow STEP 1 completes an in-progress service
--   when the vehicle is in a bay state AND:
--
--       ( config->>'service_done' IS TRUE
--         OR (config->>'service_ends_at') IS NULL              <-- "null-timer stuck"
--         OR (config->>'service_ends_at')::timestamptz <= now )
--
--   The NULL branch is a self-heal for stuck cars. The twin's own admission
--   (STEP 2 / STEP 2b) always writes BOTH config->>'svc_step' and
--   config->>'service_ends_at' when it puts a car in a bay, so it never trips it.
--
--   ottoq.ottoq_activate_due_bay_reservations wrote vehicles.current_state to a
--   bay state but NEVER wrote service_ends_at. So on the very next tick the twin
--   saw an in-bay car with a null timer and "self-healed" it to complete --
--   a 38-minute service finished in 2. Seating a car in a bay is a twin<->OTTO-Q
--   vocabulary seam, and this one was PARTIAL, not total.
--
--   This defect is OLDER than 0015 -- the same lines existed before it -- but it
--   was unreachable, because before 0015 this function bound nothing at all
--   (26 holds created, 0 bound). 0015 made the path live and thereby exposed it.
--   That is why the fix here is forward, not a revert of 0015: reverting restores
--   "0 bound", which is the vehicle-first doctrine violation 0015 exists to fix.
--
-- THE FIX
--
--   Write the SAME two config keys the twin's own admission writes, so a bay-seated
--   car behaves identically no matter which path seated it. Nothing else changes:
--   same gate, same contention order, same rebase, same decline-on-displace.
--
--   The timer is pinned to the booking's own window end, so booking, itinerary leg
--   and twin timer all say the same thing -- the lockstep invariant 0015 already
--   states for the leg ("a booking and its leg must never disagree"), now extended
--   to the twin. Floored one minute into the future so a seat can never complete on
--   the same tick it was made.
--
--   ottoq.ottoq_activate_present_bookings does NOT need this: it never touches
--   vehicles at all (verified against pg_proc -- no UPDATE of vehicles, no bay
--   state, no timer). It only flips bookings for cars the twin already seated,
--   and the twin set the timer when it seated them.
-- ============================================================================

CREATE OR REPLACE FUNCTION ottoq.ottoq_activate_due_bay_reservations(
  p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_res record; v_n int := 0; v_prev uuid; v_state text; v_verb text;
        v_early int := 0; v_declined int := 0; v_rebased boolean;
        v_end_ts timestamptz;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  FOR v_res IN
    SELECT b.booking_id, b.vehicle_id, b.stall_id, b.purpose, b.leg_id,
           s.stall_type::text AS stall_type,
           (lower(b.during) <= p_clock)   AS in_window,
           (upper(b.during) - lower(b.during)) AS dur,
           upper(b.during)                AS win_end
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state      = 'held'
       AND s.depot_id   = p_depot_id
       AND s.stall_type IN ('wash_bay'::stall_type,'detail_bay'::stall_type,'service_bay'::stall_type)
       AND s.status NOT IN ('maintenance','closed')
       -- ══════════════════ 0015: THE WINDOW GATE, NARROWED ══════════════════
       -- UNCHANGED: a hold whose window has already lapsed never seats. The grace
       -- sweep in ottoq_release_vacated_spaces owns that row.
       AND upper(b.during) >  p_clock
       -- WAS: AND lower(b.during) <= p_clock   ("not before the forecast")
       -- NOW: in window, OR the car is ready. VEHICLE-FIRST -- a free bay beats a
       -- prediction. The physical-presence guarantee the lower bound used to give is
       -- carried entirely by the v.current_state predicate below, which already means
       -- "standing in this depot, idle, not in another bay, not faulted"; readiness
       -- adds the one thing it misses -- no unfinished charge leg.
       AND ( lower(b.during) <= p_clock
             OR ottoq.ottoq_vehicle_bay_ready(p_sim_run_id, b.vehicle_id, p_clock) )
       -- the bay is physically free for this car
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = b.vehicle_id)
       -- the car is HOME and IDLE. Never interrupt live work; never touch a fault state.
       -- This is also the in-depot reassignment gate: a car that is IN a bay, charging,
       -- deployed or faulted is not in this list, so 0015 can never re-route it.
       AND v.home_depot_id = p_depot_id
       AND v.current_state IN ('arrived_at_gate'::vehicle_state,
                               'staged_awaiting_service'::vehicle_state,
                               'charge_complete_holding'::vehicle_state,
                               'service_complete_holding'::vehicle_state)
     -- CONTENTION ORDER: due-now beats early; then earliest forecast; then the PK,
     -- so the order is total and stable across ticks.
     ORDER BY (lower(b.during) <= p_clock) DESC, lower(b.during), b.booking_id
  LOOP
    -- CAS the stall. If someone else took it first, leave the reservation alone and
    -- let the existing grace/replan path deal with it -- we never force.
    CONTINUE WHEN NOT public.ottoq_reserve_stall(v_res.stall_id, v_res.vehicle_id, p_clock, 900);

    -- ══════════════ 0015: REBASE THE WINDOW ON AN EARLY SEAT ══════════════
    -- Duration preserved exactly. The exclusion constraints adjudicate displacement:
    -- if any other held/active/done/interrupted booking on this stall already owns
    -- part of [now, now+dur) we DECLINE the early seat outright -- we never push and
    -- never drop the other booking -- and hand the stall reservation back.
    v_rebased := true;
    IF NOT v_res.in_window THEN
      BEGIN
        UPDATE public.ottoq_stall_bookings
           SET during = tstzrange(p_clock, p_clock + v_res.dur, '[)')
         WHERE booking_id = v_res.booking_id AND state = 'held';
      EXCEPTION WHEN exclusion_violation THEN
        v_rebased := false;
      END;
    END IF;

    IF NOT v_rebased THEN
      UPDATE public.stalls
         SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
       WHERE id = v_res.stall_id
         AND reserved_by = v_res.vehicle_id
         AND current_vehicle_id IS NULL;
      v_declined := v_declined + 1;
      CONTINUE;
    END IF;

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
    -- 0016: and carry the TWIN'S SERVICE CONTRACT with it. Writing current_state
    -- without config->>'service_ends_at' left this seam PARTIAL: twin's
    -- ottoq_sim_advance_service_flow STEP 1 reads a null timer on an in-bay car as
    -- "null-timer stuck" and self-heals it to complete on the next tick, which turned
    -- a 38-minute service into 2 minutes. These are the same two keys the twin's own
    -- admission writes, so a bay-seated car behaves identically either way.
    -- Pinned to the booking's own window end -> booking, leg and twin timer agree.
    -- Floored 1 minute ahead so a seat can never complete on the tick that made it.
    v_end_ts := GREATEST(
                  CASE WHEN v_res.in_window THEN v_res.win_end
                       ELSE p_clock + v_res.dur END,
                  p_clock + interval '1 minute');
    UPDATE public.vehicles
       SET current_stall_id = v_res.stall_id,
           current_state    = v_state::vehicle_state,
           last_state_change = p_clock,
           config = jsonb_set(
                      jsonb_set(COALESCE(config, '{}'::jsonb),
                                '{svc_step}',
                                to_jsonb(CASE WHEN v_state = 'in_service_bay'
                                              THEN 'servicing' ELSE 'washing' END)),
                      '{service_ends_at}', to_jsonb(v_end_ts::text))
     WHERE id = v_res.vehicle_id;
    UPDATE public.stalls
       SET current_vehicle_id = v_res.vehicle_id, status = 'occupied'
     WHERE id = v_res.stall_id;

    -- The reservation is now a REAL occupancy, and is stamped so provenance can see
    -- that it was activated rather than booked fresh -- and, from 0015, whether the
    -- free bay beat the forecast.
    UPDATE public.ottoq_stall_bookings
       SET state = 'active', booked_by = 'otto_q_enacted',
           source = CASE WHEN v_res.in_window THEN 'bay_reservation_activated'
                         ELSE 'bay_reservation_activated_early' END
     WHERE booking_id = v_res.booking_id;

    IF v_res.leg_id IS NOT NULL THEN
      -- keep the leg in lockstep with the (possibly rebased) booking: ottoq_stall_free_between
      -- reads planned_end_sim, so a booking and its leg must never disagree.
      UPDATE public.ottoq_itinerary_legs
         SET to_stall_id = v_res.stall_id, status = 'active',
             planned_start_sim = CASE WHEN v_res.in_window THEN planned_start_sim ELSE p_clock END,
             planned_end_sim   = CASE WHEN v_res.in_window THEN planned_end_sim   ELSE p_clock + v_res.dur END,
             actual_start_sim  = COALESCE(actual_start_sim, p_clock)
       WHERE leg_id = v_res.leg_id AND status = 'planned';
    END IF;

    BEGIN
      PERFORM public.ottoq_emit_vehicle_command(
        p_sim_run_id, p_depot_id, v_res.vehicle_id, v_verb,
        jsonb_build_object('stall_id',   v_res.stall_id,
                           'booking_id', v_res.booking_id,
                           'leg_id',     v_res.leg_id,
                           'purpose',    v_res.purpose,
                           'via',        CASE WHEN v_res.in_window
                                              THEN 'bay_reservation_activated'
                                              ELSE 'bay_reservation_activated_early' END), p_clock);
    EXCEPTION WHEN OTHERS THEN NULL;  -- an un-emitted command must never cost the move
    END;

    IF NOT v_res.in_window THEN v_early := v_early + 1; END IF;
    v_n := v_n + 1;
  END LOOP;

  -- ONE summary event per tick (event-write amplification is the known tick-cost driver).
  IF v_early > 0 OR v_declined > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'bay_reservation_early_activation',
        p_event_type := 'ottoq.bay_reservation_activated_early', p_entity_type := 'depot',
        p_entity_id := p_depot_id,
        p_payload := jsonb_build_object(
          'seated_early', v_early, 'declined_would_displace', v_declined, 'seated_total', v_n,
          'note','a ready car took a free bay ahead of its forecast window; declined means a '
                 'later booking on that stall already owned the time, so the early seat was refused'),
        p_severity := 'info',
        p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  RETURN v_n;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_activate_due_bay_reservations: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$;
