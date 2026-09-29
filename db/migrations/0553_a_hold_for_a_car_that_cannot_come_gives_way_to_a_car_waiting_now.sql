-- migration-version: 20260928184413
-- migration-name:    a_hold_gives_way_and_a_car_is_in_a_bay_only_when_it_stands_in_one
-- (applied 2026-09-28, 1:44 PM CT, together with 0554 in ONE transaction through apply_migration, which wrote one
--  ledger row for the two files: this version and the joint name above. 0554 carries APPLIED-NO-LEDGER-ROW and points
--  here. The ledger name has no ottoq_cert_lineage row of its own, so the recert floor reads it as forcing, which is
--  what both files' own lineage rows, 0553_... and 0554_..., also say.)
--
-- 0553  **A bay held for a car that cannot come in time gives way to a car waiting for it now.** (G283; CLAUDE.md rule 9)
--
-- ══ §1 WHY (check 0409 §19c-§19d, run eff13379; 0408 §19) ═════════════════════════════════════════════════════════════
--
--   On ca448d95 two cars at 100% waited 250 and 330 minutes for a deep clean while the three wash bays (deep cleans run
--   there; the twin depot has no detail bay) were 54-57% occupied. On eff13379 the needs-card seat had been refused a wash
--   bay 304 times by sim 9:15 AM CT (113 deep cleans, 191 washes). Every refusal came back as `no_free_space` from
--   `ottoq.ottoq_enact_space_assignment`, and not one came with all three bays physically full: on average 2.18 of the 3
--   were empty at a refused deep clean. The chooser, `ottoq.ottoq_stall_free_between`, refuses a bay whose calendar has a
--   booking in the job's window, 25 minutes for a deep clean, and what held the empty bays was held bookings for cars that
--   were not there:
--     - holds for a car still charging after its charge leg's planned end. Zoox-AV-099's wash and deep clean, booked at
--       5:32 AM, had been moved to 8:49 AM, the leg's planned end (8:46) plus the taxi. The charge ran on to 9:10 (G240),
--       so at 8:49 the reconciler no longer counted the car as blocked, and the holds kept two bays until `window_elapsed`
--       (8:57:29) and `no_show_grace_elapsed` (9:04:57);
--     - holds for cars still charging or in another bay. `ottoq.ottoq_reconcile_bay_reservations` moves such a hold to its
--       car's ETA only when its start is within the 3-minute taxi time, so until then it blocks the bay's next 25 minutes.
--       Zoox-AV-094's wash hold, 8:55-9:05, sat in the window until 8:53:01, when it was deferred to 10:58; Waymo-004's
--       deep-clean hold, 8:58-9:23, until 8:58:21, when it was deferred to 10:28.
--   Waymo-AV-014, at 100%, was refused every minute from 8:50 to 8:57 AM and seated at 8:58:21, the tick after a release.
--   A third kind was found reading this file's probe at sim 10:58 AM: holds whose bay leg the itinerary had already closed
--   as done. Waymo-AV-003 (wash, 11:16), Tesla-AV-060 (deep clean, 11:33) and Tesla-RT-001 (deep clean, 1:02 PM) each
--   held a wash bay for work already done, and each had left or was about to leave. Two of the three had done their deep
--   clean in no bay at all (G286, 0409 §21), so nothing ever took up or released their hold. A car that has left is
--   released by the no-show grace only after its window begins; a car still on site whose work is done is not released at
--   all until then.
--   Rule 9: every service OTTO-Q finds a car to need is done before it leaves, so a car held for a deep clean is held at
--   the gate until a bay takes it, and each refusal is time it could have been working.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq.ottoq_bay_hold_car_eta(run, vehicle, clock, taxi)`: the earliest a car holding a bay booking could be at
--       the bay. In another bay: its service's end plus the taxi. Charging: its charge leg's planned end plus the taxi, or,
--       when the charge has outrun its plan (G240), what is left at the session's own pace so far. Owing a charge it has not
--       started: not before that charge (`infinity`), because the needs card seats a car in a bay only once it no longer
--       owes one. Gone from the site: `infinity`. Otherwise NULL: it could come now, or it is not known, and NULL never
--       yields.
--   (b) `ottoq.ottoq_yield_bay_holds(run, depot, stall type, from, until, waiting car)`: finds the first bay of the type
--       that is physically free (no car, no live reservation by another car, no real occupancy in the window) and blocked
--       only by held bookings of other cars that cannot be there before `until`. It moves each of those holds to its car's
--       ETA, and never earlier than `until`; a hold for a car that has left the site is released, as the reconciler
--       releases it, and so is a hold whose itinerary leg is already closed (`done` or `skipped`), wherever its car is,
--       because the work it was booked for is finished (`replanned_leg_closed`). A move that collides walks forward in 10-minute steps, up to 240 minutes, on the same bay; a hold with
--       no room is released (`replanned_no_window`, the reconciler's own reason). Each move is logged in the reconciler's
--       table (`deferred`, reason `yielded_to_a_car_waiting_now`), and its itinerary leg is re-timed. It returns the
--       number of holds moved or released, 0 when no bay can be freed, and never raises. The dial
--       `bay_hold_yield_enabled` (default 1) turns it off.
--   (c) The needs-card seat in `ottoq_decide_tick`: when the space assignment answers `no_free_space` for a wash or
--       service bay, it asks (b) to free one for the waiting car and, if a hold moved, tries the assignment once more. The
--       decision records `yielded_holds`.
--   Nothing a car needs is dropped. A moved hold is a forward reservation, not the service. The car's atom stays open, the
--   card seats the car when it is ready, and the readiness gate holds it until the work is done (0543).
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Every arm runs the decide tick's needs-card seat, and the bay calendar is in the canon's bookings atom.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - The reconciler's own look-ahead stays the taxi time. A wider one would move holds that no waiting car needs moved,
--     and each move counts toward its defer cap.
--   - The service flow's wash and service lanes take their own path, unchanged. They seat a car in a bay only when it
--     holds a booking due now, and otherwise set it to a bay state in no bay (G286). That is its own file.
--   - Holds booked hours ahead are still booked hours ahead. This file stops them blocking a car that is here.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0553 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 edits twin bays, cars and bookings on an ended run) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0553 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the decide tick is the one measured after 0551 (md5 of its source), and the names this file creates are free ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure)
     <> '9c5f7289e50a83c5a2e5ca65c6595a75' THEN
    RAISE EXCEPTION '0553 P2: public.ottoq_decide_tick is not the function measured';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('ottoq_bay_hold_car_eta', 'ottoq_yield_bay_holds')) THEN
    RAISE EXCEPTION '0553 P2: a function this file creates already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0553_pre', 'function', 'public', 'ottoq_decide_tick', pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));

-- ── (a) when could a holding car be at the bay ──
CREATE OR REPLACE FUNCTION ottoq.ottoq_bay_hold_car_eta(p_sim_run_id uuid, p_vehicle_id uuid, p_clock timestamptz,
                                                        p_taxi_min numeric)
RETURNS timestamptz
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
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
END $fn$;
COMMENT ON FUNCTION ottoq.ottoq_bay_hold_car_eta(uuid, uuid, timestamptz, numeric) IS
  '0553 (G283): the earliest a car holding a bay booking could be at the bay (NULL = could come now or unknown; '
  'infinity = owes a charge it has not started, or has left the site).';

-- ── (b) free one bay for the car waiting now ──
CREATE OR REPLACE FUNCTION ottoq.ottoq_yield_bay_holds(p_sim_run_id uuid, p_depot_id uuid, p_stall_type text,
                                                       p_from timestamptz, p_until timestamptz, p_for_vehicle uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
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
END $fn$;
COMMENT ON FUNCTION ottoq.ottoq_yield_bay_holds(uuid, uuid, text, timestamptz, timestamptz, uuid) IS
  '0553 (G283): frees one bay for a car waiting now by moving the held bookings of cars that cannot be there before it '
  'would finish to their ETA (logged as yielded_to_a_car_waiting_now), and releasing a hold whose leg is already closed '
  '(replanned_leg_closed) or whose car has left. Returns holds moved or released; never raises.';

-- ── (c) the needs-card seat asks for a bay to be freed, and tries once more ──
DO $seat$
DECLARE v_def text; n int;
  c_old CONSTANT text := E'          v_space := ottoq.ottoq_enact_space_assignment(\n'
    || E'                       p_sim_run_id, v_depot, v_need.vehicle_id, v_need.stall_type,\n'
    || E'                       v_need.purpose, v_clock, v_bay_until, v_bay_leg_id, ''needs_card'');\n';
  c_new CONSTANT text := c_old
    || E'          -- 0553 (G283): a bay held for a car that cannot be here before this one would finish gives way to it.\n'
    || E'          -- ottoq_yield_bay_holds moves those holds to their car''s ETA; then the assignment is tried once more.\n'
    || E'          IF NOT COALESCE((v_space->>''assigned'')::boolean, false)\n'
    || E'             AND COALESCE(v_space->>''reason'', '''') = ''no_free_space'' THEN\n'
    || E'            IF ottoq.ottoq_yield_bay_holds(p_sim_run_id, v_depot, v_need.stall_type, v_clock, v_bay_until,\n'
    || E'                                           v_need.vehicle_id) > 0 THEN\n'
    || E'              v_space := ottoq.ottoq_enact_space_assignment(\n'
    || E'                           p_sim_run_id, v_depot, v_need.vehicle_id, v_need.stall_type,\n'
    || E'                           v_need.purpose, v_clock, v_bay_until, v_bay_leg_id, ''needs_card'')\n'
    || E'                         || jsonb_build_object(''yielded_holds'', true);\n'
    || E'            END IF;\n'
    || E'          END IF;\n';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0553 seat: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $seat$;

-- ── V1 (comment-stripped): the seat yields once and retries ──
DO $verify$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'IF ottoq\.ottoq_yield_bay_holds\(p_sim_run_id, v_depot, v_need\.stall_type, v_clock, v_bay_until,\s*v_need\.vehicle_id\) > 0 THEN\s*v_space := ottoq\.ottoq_enact_space_assignment\(', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, '''yielded_holds''', 'g')) <> 1 THEN
    RAISE EXCEPTION '0553 V1: the needs-card seat does not yield and retry once';
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0553_a_hold_for_a_car_that_cannot_come_gives_way_to_a_car_waiting_now', true, true,
  'G283: when the needs-card seat is refused a wash or service bay (no_free_space), ottoq.ottoq_yield_bay_holds frees '
  'the first bay that is physically free and blocked only by held bookings of other cars that cannot be there before the '
  'waiting car would finish (ottoq.ottoq_bay_hold_car_eta: charging past the window, in another bay, owing a charge not '
  'started, or gone). It moves each hold to its car''s ETA, never before the waiting car''s window ends, releases a gone '
  'car''s hold and a hold whose leg is already closed, logs each move in bay_reservation_reconcile_2026_08_02, and the seat tries the assignment once more. '
  'Dial bay_hold_yield_enabled (default 1).', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest ended operator run at the twin depot. The three wash bays, each empty:
--   bay 1 held 5-15 minutes from now for car C, charging on L2: 20% to 60% in its session's first 60 minutes, so 1.5
--     minutes a point and 58.5 minutes left to 99% (its charge has no leg ending later, the G240 case);
--   bay 2 held 5-15 minutes from now for car R, staged at 100% and ready;
--   bay 3 held 5-15 minutes from now for car G, at the gate at 40% (it owes a charge).
--   Car W, at 100%, needs a deep clean now (25 minutes).
--   (i) the assignment is refused (`no_free_space`); (ii) the yield frees bay 1 (the first in order whose holds cannot
--   come), moving C's hold to C's ETA (58.5 minutes plus the 3-minute taxi), and leaves R's hold alone; (iii) the retry seats W on
--   bay 1. (iv) With bay 1 taken, a second waiting car W2 is refused, and the yield frees bay 3, moving G's hold to the end
--   of W2's window. R's hold is never moved. (v) R's hold is then pointed at a leg already closed as done: a third
--   waiting car W3 is refused, the yield releases R's hold (`replanned_leg_closed`), and W3 takes bay 2.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; bay uuid[]; car uuid[]; c uuid; r uuid; g uuid; w uuid; w2 uuid; w3 uuid;
  bc uuid; br uuid; bg uuid; v_l2 uuid; s1 jsonb; s2 jsonb; s3 jsonb; s4 jsonb; s5 jsonb; s6 jsonb; y1 int; y2 int; y3 int;
  v_c_from timestamptz; v_r_from timestamptz; v_g_from timestamptz; v_leg_done uuid; v_r_state text; v_r_reason text;
BEGIN
  BEGIN
    SELECT r0.sim_run_id INTO v_run FROM public.ottoq_sim_runs r0
     WHERE r0.depot_id = v_depot AND r0.run_by = 'operator_demo' AND r0.status NOT IN ('initializing', 'running', 'paused')
     ORDER BY r0.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0553 V3: no ended operator run at the twin depot'; END IF;
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t WHERE sim_run_id = v_run;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);

    SELECT array_agg(id ORDER BY distance_from_entrance NULLS LAST, stall_code) INTO bay
      FROM public.stalls WHERE depot_id = v_depot AND stall_type::text = 'wash_bay' AND status NOT IN ('maintenance', 'closed');
    IF coalesce(array_length(bay, 1), 0) < 3 THEN RAISE EXCEPTION '0553 V3: fewer than three wash bays'; END IF;
    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 6) q;
    IF coalesce(array_length(car, 1), 0) < 6 THEN RAISE EXCEPTION '0553 V3: fewer than six free twin cars'; END IF;
    c := car[1]; r := car[2]; g := car[3]; w := car[4]; w2 := car[5]; w3 := car[6];

    -- clear the bays and their calendar from t on, as an empty depot
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL,
           status = 'available' WHERE id = ANY (bay);
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = t, release_reason = 'v3_0553'
     WHERE stall_id = ANY (bay) AND state IN ('held', 'active') AND upper(during) > t;
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.vehicles
       SET current_state = CASE WHEN id = c THEN 'charging_l2' WHEN id = g THEN 'arrived_at_gate'
                                ELSE 'staged_awaiting_service' END::vehicle_state,
           current_soc = CASE WHEN id = c THEN 60 WHEN id = g THEN 40 ELSE 100 END,
           current_depot_id = v_depot, target_soc = 100, last_state_change = t - interval '30 minutes'
     WHERE id = ANY (car);
    -- C's session: 20% at t - 60 minutes, 60% now
    SELECT id INTO v_l2 FROM public.stalls WHERE depot_id = v_depot AND stall_type::text = 'l2' ORDER BY stall_code LIMIT 1;
    INSERT INTO public.ocpp_sessions(depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id, connector_id,
                                     status, started_at, soc_start, energy_delivered_kwh, sim_run_id)
    VALUES (v_depot, v_l2, c, 'V3-0553-C', 'V3-0553-C', 1, 1, 'active', t - interval '60 minutes', 20, 30, v_run);
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_at, booked_at_sim, booked_by)
    VALUES (v_run, bay[1], c, 'wash', tstzrange(t + interval '5 minutes', t + interval '15 minutes'), 'held', now(), t - interval '60 minutes', 'v3_0553')
    RETURNING booking_id INTO bc;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_at, booked_at_sim, booked_by)
    VALUES (v_run, bay[2], r, 'wash', tstzrange(t + interval '5 minutes', t + interval '15 minutes'), 'held', now(), t - interval '60 minutes', 'v3_0553')
    RETURNING booking_id INTO br;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_at, booked_at_sim, booked_by)
    VALUES (v_run, bay[3], g, 'detail', tstzrange(t + interval '5 minutes', t + interval '15 minutes'), 'held', now(), t - interval '60 minutes', 'v3_0553')
    RETURNING booking_id INTO bg;

    -- (i) W is refused
    s1 := ottoq.ottoq_enact_space_assignment(v_run, v_depot, w, 'wash_bay', 'detail', t, t + interval '25 minutes', NULL, 'needs_card');
    IF COALESCE((s1->>'assigned')::boolean, false) OR s1->>'reason' <> 'no_free_space' THEN
      RAISE EXCEPTION '0553 V3 FAILED (i): W was not refused: %', s1;
    END IF;
    -- (ii) the yield frees bay 1: C's hold moves to C's ETA (t + 58.5 + 3), R's stays
    y1 := ottoq.ottoq_yield_bay_holds(v_run, v_depot, 'wash_bay', t, t + interval '25 minutes', w);
    SELECT lower(during) INTO v_c_from FROM public.ottoq_stall_bookings WHERE booking_id = bc;
    SELECT lower(during) INTO v_r_from FROM public.ottoq_stall_bookings WHERE booking_id = br;
    IF y1 <> 1 OR v_c_from IS DISTINCT FROM t + interval '61.5 minutes' OR v_r_from IS DISTINCT FROM t + interval '5 minutes' THEN
      RAISE EXCEPTION '0553 V3 FAILED (ii): yield %, C''s hold at %, R''s at %', y1, v_c_from, v_r_from;
    END IF;
    -- (iii) the retry seats W on bay 1
    s2 := ottoq.ottoq_enact_space_assignment(v_run, v_depot, w, 'wash_bay', 'detail', t, t + interval '25 minutes', NULL, 'needs_card');
    IF NOT COALESCE((s2->>'assigned')::boolean, false) OR (s2->>'stall_id')::uuid IS DISTINCT FROM bay[1] THEN
      RAISE EXCEPTION '0553 V3 FAILED (iii): W was not seated on bay 1: %', s2;
    END IF;
    -- (iv) W2: refused, then bay 3 freed (G owes a charge), R's hold untouched
    s3 := ottoq.ottoq_enact_space_assignment(v_run, v_depot, w2, 'wash_bay', 'detail', t, t + interval '25 minutes', NULL, 'needs_card');
    y2 := ottoq.ottoq_yield_bay_holds(v_run, v_depot, 'wash_bay', t, t + interval '25 minutes', w2);
    SELECT lower(during) INTO v_g_from FROM public.ottoq_stall_bookings WHERE booking_id = bg;
    SELECT lower(during) INTO v_r_from FROM public.ottoq_stall_bookings WHERE booking_id = br;
    s4 := ottoq.ottoq_enact_space_assignment(v_run, v_depot, w2, 'wash_bay', 'detail', t, t + interval '25 minutes', NULL, 'needs_card');
    IF COALESCE((s3->>'assigned')::boolean, false) OR y2 <> 1 OR v_g_from IS DISTINCT FROM t + interval '25 minutes'
       OR v_r_from IS DISTINCT FROM t + interval '5 minutes'
       OR NOT COALESCE((s4->>'assigned')::boolean, false) OR (s4->>'stall_id')::uuid IS DISTINCT FROM bay[3] THEN
      RAISE EXCEPTION '0553 V3 FAILED (iv): first try %, yield %, G''s hold at %, R''s at %, retry %', s3, y2, v_g_from, v_r_from, s4;
    END IF;
    -- (v) R's hold, for a car ready now, becomes a hold for work already done: W3 is refused, the yield releases it
    SELECT l.leg_id INTO v_leg_done FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = v_run AND l.status = 'done' ORDER BY l.leg_id LIMIT 1;
    IF v_leg_done IS NULL THEN RAISE EXCEPTION '0553 V3: no closed leg on run %', v_run; END IF;
    UPDATE public.ottoq_stall_bookings SET leg_id = v_leg_done WHERE booking_id = br;
    s5 := ottoq.ottoq_enact_space_assignment(v_run, v_depot, w3, 'wash_bay', 'detail', t, t + interval '25 minutes', NULL, 'needs_card');
    y3 := ottoq.ottoq_yield_bay_holds(v_run, v_depot, 'wash_bay', t, t + interval '25 minutes', w3);
    SELECT state, release_reason INTO v_r_state, v_r_reason FROM public.ottoq_stall_bookings WHERE booking_id = br;
    s6 := ottoq.ottoq_enact_space_assignment(v_run, v_depot, w3, 'wash_bay', 'detail', t, t + interval '25 minutes', NULL, 'needs_card');
    IF COALESCE((s5->>'assigned')::boolean, false) OR y3 <> 1 OR v_r_state IS DISTINCT FROM 'released'
       OR v_r_reason IS DISTINCT FROM 'replanned_leg_closed'
       OR NOT COALESCE((s6->>'assigned')::boolean, false) OR (s6->>'stall_id')::uuid IS DISTINCT FROM bay[2] THEN
      RAISE EXCEPTION '0553 V3 FAILED (v): first try %, yield %, R''s hold % (%), retry %', s5, y3, v_r_state, v_r_reason, s6;
    END IF;

    RAISE EXCEPTION '0553 V3 PASSED on run %: W was refused, the yield moved C''s hold (58.5 minutes of charge left at its session''s pace) to its ETA and W took bay 1; W2 was refused, the yield moved G''s hold (owes a charge) past W2''s window and W2 took bay 3; R''s hold (a car ready now) was never moved, and once its leg was closed the yield released it and W3 took bay 2',
      v_run;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0553 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0553 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0553_pre' (the decide tick) as it is; the
--   two new functions are then called by nothing.

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-28 to gxdrcyphqjzjsuhxuqtg, 1:44 PM CT (ledger 20260928184413), in one transaction with 0554.
--   public.ottoq_decide_tick  9c5f7289e50a83c5a2e5ca65c6595a75 -> 2187f8565d4e8d33c646f8efb7316e2c
--   ottoq.ottoq_bay_hold_car_eta and ottoq.ottoq_yield_bay_holds created. V1 and V3 passed: the transaction commits
--   only if both do. ottoq_cert_recert_floor() moved to 2026-09-28 18:44:13.338283+00; the sweep restarted.
