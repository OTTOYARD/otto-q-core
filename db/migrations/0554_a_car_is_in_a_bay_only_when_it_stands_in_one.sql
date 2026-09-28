-- migration-version: PENDING
-- migration-name:    a_car_is_in_a_bay_only_when_it_stands_in_one
--
-- 0554  **A car is in a wash, detail or service bay only when it stands in one.** (G286)
--
-- ══ §1 WHY (check 0409 §21, run eff13379) ══════════════════════════════════════════════════════════════════════════════
--
--   Reading 0553's probe on eff13379 turned up three cars that had left the depot, or were about to, still holding wash-bay
--   bookings for bay legs the itinerary had already closed as done. Two of the three had done their deep clean in no bay.
--   Tesla-AV-060 came off DCFC-07 at 10:40:04 AM (sim, CT) and was set to `in_detail_bay` in the same second. The charge
--   arm let go of it at 10:40:32 and its pointer went to NULL. No bay ever named it. At 11:01:32 the "deep clean" ended,
--   and the car was put on staging stall S008 and deployed at 11:02:25 with the deep clean credited. Its own booking,
--   WSH-01 from 11:33, stayed held.
--   The writer is `twin.ottoq_sim_advance_service_flow`. Its wash lane (STEP 2, cars coming off a charger) and its service
--   lane (cars staged on need_service) admit by staff count alone: LEAST(cleaning_staff, wash_supervisor), and
--   service_staff, less the cars already in a bay STATE. A car that holds a booking whose window contains the clock, on a
--   bay that is free, is moved into that bay. Every other admitted car is set to `in_wash_bay`, `in_detail_bay` or
--   `in_service_bay` all the same, with a `service_ends_at`, and STEP 1 credits the bay's work when the timer ends. The car
--   stands on its staging stall, or on no stall once the charge arm has released it.
--   0409 §21 classes every bay visit of the run by both pointers, the car's and the bays'. By sim ~12:10 PM, 30 of 79
--   visits, 800 of 1,634 bay-minutes, were in no bay: 9 of 9 deep cleans and 5 of 7 washes that came straight off a
--   charger, and 16 of 25 service visits. Every one of the 48 visits that came from staging through OTTO-Q's needs card
--   was in a bay. The count of cars in bay states stayed near the bay count, because staff equals bays at the twin depot
--   (3 and 3, 2 and 2; the service lane reached 3 for 15.3 minutes). The damage is therefore not extra capacity but where
--   the work was: a bay stood empty and, by the calendar, free, while the staff it needed were busy at a car that was not
--   in it. The needs card computes its headroom with the twin's own staff formula, so those cars also filled the headroom
--   OTTO-Q uses to seat a waiting car in the empty bay. And the car's own booking, never taken up, was left to block the
--   bay for others until the no-show grace ran out (G283, 0553).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   In `twin.ottoq_sim_advance_service_flow`, both lanes:
--   (a) take only a car whose bay is booked for now (the booking the lane already looks up). The staff limit then counts
--       only cars it can seat;
--   (b) set the bay state only once the car stands in that bay. The claim can still fail, when another car stands in the
--       bay or the charge arm still holds this one. The car then stays as it is.
--   A car the lanes do not take goes through OTTO-Q's seat, as every car from staging already does. A car coming off a
--   charger with open bay work is staged on need_service in the same tick by the wash triage (`twin.ottoq_sim_wash_triage`,
--   which the world tick calls after the service flow). The needs card then seats it in a bay that is free on the floor
--   and on the calendar, 0553 freeing one held for a car that cannot come. A car staged on need_service waits for the same
--   seat. The door (`twin.ottoq_sim_confirm_commands`) moves it into the bay and writes the bay contract (0458).
--   Nothing a car needs is dropped: its atoms stay open until a bay does the work, and the readiness gate holds it until
--   then (0543).
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Every arm runs the service flow. Vehicle states, stall pointers, the bay calendar and the itinerary are in the
--   canon's atoms.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - A technician flag that names bay work with no atom behind it (`minor_cosmetic`, `wash_due`) reached a bay only
--     through these lanes. It now waits until re-assessment writes the atom, or until the gate's patience flags the car
--     for a person. None was raised on eff13379: the only flag type set was `deploy_gate_stuck`, on 14 cars.
--   - The staff count still bounds both lanes and the needs card, by the twin's formula, which the card mirrors. With
--     every visit in a bay, the bays bound them too.
--   - The FIFO and manual baseline ticks set bay states their own way. They are not the operator's path and are not
--     touched.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0554 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 edits twin bays, cars and bookings on an ended run) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0554 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the service flow is the one measured after 0551 (md5 of its source) ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure)
     <> 'SET_AFTER_0551_IS_APPLIED' THEN
    RAISE EXCEPTION '0554 P2: twin.ottoq_sim_advance_service_flow is not the function measured';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0554_pre', 'function', 'twin', 'ottoq_sim_advance_service_flow',
       pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure),
       md5(pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure));

-- ── (a) + (b), both lanes ──
DO $lanes$
DECLARE v_def text; n int; i int;
  a_old text[] := ARRAY[
    -- the wash lane's cursor
    E'    ) q\n'
    || E'     -- 0100: run-stable tiebreak; ord ties on same-tick last_state_change (heap below).\n'
    || E'     ORDER BY (q.booked_stall IS NULL), q.ord, q.id\n',
    -- the wash lane's state write
    E'    UPDATE vehicles\n'
    || E'       SET current_state = (CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>''flagged_issue_type'' IN (''minor_cosmetic'',''wash_due'')) THEN ''in_detail_bay'' ELSE ''in_wash_bay'' END)::vehicle_state,\n',
    -- the service lane's cursor
    E'    ) q\n'
    || E'     -- 0100: run-stable tiebreak; lsc ties on same-tick transitions (heap below).\n'
    || E'     ORDER BY (q.booked_stall IS NULL), q.lsc, q.id LIMIT GREATEST(0, v_svc_cap - v_in_svc)\n',
    -- the service lane's state write
    E'    UPDATE vehicles SET current_state = ''in_service_bay''::vehicle_state, last_state_change = p_sim_clock_now,\n'];
  a_new text[];
BEGIN
  a_new := ARRAY[
    E'    ) q\n'
    || E'     -- 0554 (G286): only a car whose bay is booked for now can be seated here. The rest are seated by OTTO-Q''s\n'
    || E'     -- needs card, in a bay free on the floor and on the calendar.\n'
    || E'     WHERE q.booked_stall IS NOT NULL\n'
    || E'     -- 0100: run-stable tiebreak; ord ties on same-tick last_state_change (heap below).\n'
    || E'     ORDER BY (q.booked_stall IS NULL), q.ord, q.id\n',
    E'    -- 0554 (G286): the bay state only for a car standing in its bay. The claim above fails when another car stands\n'
    || E'    -- in the bay or the charge arm still holds this one; the car then stays as it is, and this tick''s wash triage\n'
    || E'    -- routes it.\n'
    || E'    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM vehicles vb\n'
    || E'                               WHERE vb.id = v_rec.id AND vb.current_stall_id = v_rec.booked_stall);\n'
    || a_old[2],
    E'    ) q\n'
    || E'     -- 0554 (G286): only a car whose bay is booked for now can be seated here. The rest are seated by OTTO-Q''s\n'
    || E'     -- needs card, in a bay free on the floor and on the calendar.\n'
    || E'     WHERE q.booked_stall IS NOT NULL\n'
    || E'     -- 0100: run-stable tiebreak; lsc ties on same-tick transitions (heap below).\n'
    || E'     ORDER BY (q.booked_stall IS NULL), q.lsc, q.id LIMIT GREATEST(0, v_svc_cap - v_in_svc)\n',
    E'    -- 0554 (G286): the bay state only for a car standing in its bay (see the wash lane).\n'
    || E'    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM vehicles vb\n'
    || E'                               WHERE vb.id = v_rec.id AND vb.current_stall_id = v_rec.booked_stall);\n'
    || a_old[4]];
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  FOR i IN 1 .. 4 LOOP
    n := (length(v_def) - length(replace(v_def, a_old[i], ''))) / length(a_old[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0554 lanes: anchor % matches % times, not 1', i, n; END IF;
    v_def := replace(v_def, a_old[i], a_new[i]);
  END LOOP;
  EXECUTE v_def;
END $lanes$;

-- ── V1 (comment-stripped): both lanes take only a booked car and set the state only once it stands in the bay ──
DO $verify$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace(pg_get_functiondef(
             'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src, '\)\s*q\s+WHERE q\.booked_stall IS NOT NULL\s+ORDER BY \(q\.booked_stall IS NULL\)', 'g')) <> 2 THEN
    RAISE EXCEPTION '0554 V1: the two lanes do not both take only a car whose bay is booked for now';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'CONTINUE WHEN NOT EXISTS \(SELECT 1 FROM vehicles vb\s+WHERE vb\.id = v_rec\.id AND vb\.current_stall_id = v_rec\.booked_stall\);\s+UPDATE vehicles\s+SET current_state = ', 'g')) <> 2 THEN
    RAISE EXCEPTION '0554 V1: a lane sets a bay state without the car standing in its bay';
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0554_a_car_is_in_a_bay_only_when_it_stands_in_one', true, true,
  'G286: twin.ottoq_sim_advance_service_flow''s wash lane (cars off a charger) and service lane (staged on need_service) '
  'admitted by staff count alone and set in_wash_bay / in_detail_bay / in_service_bay whether or not the car was seated, '
  'so the work was credited with the car on a staging stall or on none (0409 §21: 30 of 79 visits on eff13379). Both '
  'lanes now take only a car whose bay is booked for now and set the bay state only once it stands in that bay. Any other '
  'car goes to OTTO-Q''s needs card through the wash triage, as cars from staging already did.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest ended operator run at the twin depot, pinned as the active run for this transaction. The
--   other twin cars in the lanes' states are taken off the site first, so only these four are in play:
--   A, off a charger at 100%, owes a deep clean and has no bay booked;
--   B, off a charger at 100%, owes a wash and holds wash bay 1 from a minute ago;
--   C, staged on need_service, owes a sensor calibration (a service-bay atom) and has no bay booked;
--   D, staged on need_service, owes a sensor calibration and holds service bay 1 from a minute ago.
--   One pass of the service flow: B stands in wash bay 1 in `in_wash_bay`; D stands in service bay 1 in `in_service_bay`;
--   A and C are in no bay state and in no bay (before 0554 both would have been set to a bay state, the staff limits
--   allowing). Then the wash triage stages A, the route to the needs card.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; car uuid[]; wb uuid[]; sb uuid[]; a uuid; b uuid; c uuid; d uuid;
  v_wash_head int; v_svc_head int;
  sa text; sb_ text; sc text; sd text; pa uuid; pb uuid; pc uuid; pd uuid; wb1 uuid; sb1 uuid; step_a text; step_c text;
BEGIN
  BEGIN
    SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.run_by = 'operator_demo' AND r.status NOT IN ('initializing', 'running', 'paused')
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0554 V3: no ended operator run at the twin depot'; END IF;
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t, tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);

    v_wash_head := LEAST(twin.ottoq_sim_lane_capacity(v_run, 'cleaning_staff', 3),
                         public.ottoq_depot_staffing_count(v_depot, 'wash_supervisor'));
    v_svc_head := twin.ottoq_sim_lane_capacity(v_run, 'service_staff', 2);
    IF COALESCE(v_wash_head, 0) < 2 OR COALESCE(v_svc_head, 0) < 2 THEN
      RAISE EXCEPTION '0554 V3: the lanes'' staff at % allow % washes and % services; two of each are needed to show a car left out by the bay, not the staff',
        t, v_wash_head, v_svc_head;
    END IF;

    SELECT array_agg(id ORDER BY distance_from_entrance NULLS LAST, stall_code) INTO wb
      FROM public.stalls WHERE depot_id = v_depot AND stall_type::text = 'wash_bay' AND status NOT IN ('maintenance', 'closed');
    SELECT array_agg(id ORDER BY distance_from_entrance NULLS LAST, stall_code) INTO sb
      FROM public.stalls WHERE depot_id = v_depot AND stall_type::text = 'service_bay' AND status NOT IN ('maintenance', 'closed');
    IF coalesce(array_length(wb, 1), 0) < 1 OR coalesce(array_length(sb, 1), 0) < 1 THEN
      RAISE EXCEPTION '0554 V3: no open wash bay or service bay';
    END IF;
    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 4) q;
    IF coalesce(array_length(car, 1), 0) < 4 THEN RAISE EXCEPTION '0554 V3: fewer than four free twin cars'; END IF;
    a := car[1]; b := car[2]; c := car[3]; d := car[4];

    -- only these four in the lanes: every other twin car in a lane's state leaves the site; the bays are empty and free
    UPDATE public.vehicles SET current_state = 'offline'
     WHERE home_depot_id = v_depot AND NOT (id = ANY (car)) AND robotic_tether_until IS NULL
       AND current_state IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay', 'charge_complete_holding',
                             'staged_awaiting_service', 'service_complete_holding');
    UPDATE public.vehicles SET current_stall_id = NULL WHERE current_stall_id = ANY (wb || sb) AND NOT (id = ANY (car));
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL,
           status = 'available' WHERE id = ANY (wb || sb);
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = t, release_reason = 'v3_0554'
     WHERE stall_id = ANY (wb || sb) AND sim_run_id = v_run AND state IN ('held', 'active') AND upper(during) > t - interval '1 day';
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.vehicles
       SET current_depot_id = v_depot, current_soc = 100, target_soc = 100, last_state_change = t - interval '5 minutes',
           current_state = CASE WHEN id IN (a, b) THEN 'charge_complete_holding' ELSE 'staged_awaiting_service' END::vehicle_state,
           config = CASE WHEN id IN (c, d)
                         THEN jsonb_set(COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type' - 'service_ends_at',
                                        '{svc_step}', '"need_service"'::jsonb)
                         ELSE COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type' - 'service_ends_at' - 'svc_step' END
     WHERE id = ANY (car);
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, target_soc, atoms, status, source)
    SELECT x.vid, v_run, v_depot, t - interval '2 hours', 'V3-0554-' || x.tag, 'standard', 100,
           jsonb_build_array(jsonb_build_object('svc', x.svc, 'concurrency', 'bay', 'must_do', true, 'deferrable', false,
                                                'status', 'pending', 'est_min', x.est)), 'open', 'v3_0554'
      FROM (VALUES (a, 'A', 'interior_deep_clean', 27), (b, 'B', 'exterior_wash', 9),
                   (c, 'C', 'sensor_calibration', 40), (d, 'D', 'sensor_calibration', 40)) x(vid, tag, svc, est);
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_at, booked_at_sim, booked_by)
    VALUES (v_run, wb[1], b, 'wash', tstzrange(t - interval '1 minute', t + interval '9 minutes'), 'held', now(), t - interval '60 minutes', 'v3_0554'),
           (v_run, sb[1], d, 'service', tstzrange(t - interval '1 minute', t + interval '39 minutes'), 'held', now(), t - interval '60 minutes', 'v3_0554');

    PERFORM twin.ottoq_sim_advance_service_flow(v_run, t, 30, v_depot);

    SELECT current_state::text, current_stall_id INTO sa, pa FROM public.vehicles WHERE id = a;
    SELECT current_state::text, current_stall_id INTO sb_, pb FROM public.vehicles WHERE id = b;
    SELECT current_state::text, current_stall_id INTO sc, pc FROM public.vehicles WHERE id = c;
    SELECT current_state::text, current_stall_id INTO sd, pd FROM public.vehicles WHERE id = d;
    SELECT current_vehicle_id INTO wb1 FROM public.stalls WHERE id = wb[1];
    SELECT current_vehicle_id INTO sb1 FROM public.stalls WHERE id = sb[1];
    IF sb_ NOT IN ('in_wash_bay', 'in_detail_bay') OR pb IS DISTINCT FROM wb[1] OR wb1 IS DISTINCT FROM b THEN
      RAISE EXCEPTION '0554 V3 FAILED: B (booked on wash bay 1) is % on % and the bay names %', sb_, pb, wb1;
    END IF;
    IF sd IS DISTINCT FROM 'in_service_bay' OR pd IS DISTINCT FROM sb[1] OR sb1 IS DISTINCT FROM d THEN
      RAISE EXCEPTION '0554 V3 FAILED: D (booked on service bay 1) is % on % and the bay names %', sd, pd, sb1;
    END IF;
    IF sa IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay') OR sc IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay') THEN
      RAISE EXCEPTION '0554 V3 FAILED: a car with no bay was set to a bay state: A % on %, C % on %', sa, pa, sc, pc;
    END IF;
    IF EXISTS (SELECT 1 FROM public.stalls WHERE current_vehicle_id IN (a, c) AND id = ANY (wb || sb)) THEN
      RAISE EXCEPTION '0554 V3 FAILED: a bay names A or C';
    END IF;

    PERFORM twin.ottoq_sim_wash_triage(v_depot, t);
    SELECT current_state::text, config->>'svc_step', current_stall_id INTO sa, step_a, pa FROM public.vehicles WHERE id = a;
    SELECT config->>'svc_step' INTO step_c FROM public.vehicles WHERE id = c;
    IF sa IS DISTINCT FROM 'staged_awaiting_service' THEN
      RAISE EXCEPTION '0554 V3 FAILED: after the triage A is % (step %) on %', sa, step_a, pa;
    END IF;

    RAISE EXCEPTION '0554 V3 PASSED on run %: B (booked) stands in wash bay 1 in %, D (booked) in service bay 1 in in_service_bay; A (a deep clean, no booking) and C (a calibration, no booking, step %) were set to no bay state and stand in no bay; the triage then staged A (step %) for the needs card',
      v_run, sb_, step_c, step_a;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0554 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0554 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0554_pre' as it is.

COMMIT;
