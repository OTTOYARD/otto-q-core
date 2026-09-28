-- migration-version: 20260928235524
-- migration-name:    a_faulted_cars_repair_goes_first_in_its_plan
-- (applied 2026-09-28, 6:55 PM CT, after check 0411's run ended; the dry run passed first and left nothing behind.)
--
-- 0558  **A faulted car's repair goes first in its plan, and no charger is held for it before the repair.** (G292;
--       CLAUDE.md rule 9)
--
-- ══ §1 WHY (measured on check 0411's run cdf87081, 2026-09-28, 6:10 PM CT, sim 9:17 AM) ══════════════════════════════
--
--   Zoox-AV-080 took a `sensor_suite_fault` (critical, not immobilizing) at 4:44 AM sim. The fault handler's step (6)
--   (0555) routed it to the service bay at 5:09:47 AM and asked the planner for a plan. The planner
--   (`public.ottoq_plan_visit_itinerary`) always plans the charge first and the bay work after it, the repair last
--   (exterior_wash 1, interior_deep_clean 2, sensor_calibration 3, mechanical_pm 4, fault_repair 5). So the car's plan
--   read: an 8-hour L2 charge from 5:09 AM, the wash at 1:16 PM, the repair at 1:24 PM. The booker booked the wash bay
--   and the service bay for those times at 5:10 AM.
--
--   Since 0557 the emission gate refuses a charge to a car with an open fault until the repair is done. So the plan's
--   first leg can never start, and the repair waits behind it: a circular wait. The flow contract slid the plan 20
--   minutes every 20 minutes (12 `amend_plan` decisions, 5:29 AM to 9:13 AM), and re-booked the charge three times.
--   By 9:17 AM the car had waited 4 h 33 min at 46%, unrepaired and uncharged, its repair still booked for 1:24 PM, two
--   minutes before the run's end. Meanwhile one L2 charger (CANOPY-03 E-32) stood idle from 6:20 AM, booked for a car
--   that could not charge: no other car arrived on it. The service bays were busy (both occupied 227 of 257 minutes
--   since 5:09 AM, 14 visits), so the repair would have queued in any order; it should have queued at the front of its
--   own plan, not behind a charge the gate refuses.
--
--   0557 made this. Before it the car charged with its fault open (G291) and was repaired afterwards; 0557 stopped the
--   charge and did not move the repair ahead of it. And 0557's step (6) change has a second gap its V3 did not look
--   for: the planner builds no plan over one that still has legs to go, so a car routed to repair from the charge line
--   keeps its charge-first plan and gets no repair leg at all.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The planner (`public.ottoq_plan_visit_itinerary`), for a car with an open vehicle fault and a repair still to do
--       on its card, plans the repair's service leg first, at the start of the plan, and every other leg after it: the
--       charge and the work done during it start when the repair is planned to end, then the wash and other bay work,
--       then the readiness check.
--   (b) The booker (`ottoq.ottoq_book_workflow_legs`) books no charger for a car with an open vehicle fault. The leg
--       stays unbooked, counted as `waits_for_repair`; the placer's next pass after the repair books it.
--   (c) The fault handler's step (6) (`ottoq.ottoq_route_faulted_cars_to_repair`):
--       (i)  releases every held charge booking of a car with an open fault (`vehicle_fault_open`), unbooks its charge
--            leg, and clears a charger reserved for it that it is not standing on;
--       (ii) re-plans a staged car awaiting its repair whose plan does not put the repair ahead of every charge and bay
--            leg still to go: those legs are skipped, their held bay bookings released (`replanned_repair_first`; a
--            parking hold stays, the car is parked on it), the plan closed, and the planner plans again, repair first.
--            The booker's rule of one live service booking per car (0130's invariant 2) would otherwise refuse the new
--            repair booking while the old one is held.
--       Its summary event carries the counts of both.
--   Nothing else changes. The repair queues for the service bay like any other bay work: the booker books the first free
--   window from the plan's start, walking forward.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   The planner, the booker and the fault handler's step (6) run in every arm.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - Priority. A faulted car's repair takes the first free service-bay window; it does not move another car's booked
--     maintenance. Every car at the depot leaves only with its work done (0543), so a bumped car is a car held longer,
--     and the service bays' order stays the calendar's (G270 orders bay admission by deadline).
--   - The flow contract still slides a waiting plan 20 minutes at a time (`amend_plan`), booked legs included, while
--     their bookings stay put. The seat follows the booking, so this changes no outcome; it is noise in the decision
--     stream.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0558 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 edits twin cars, visits, plans, chargers and bookings on an ended run) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0558 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the three functions are the ones measured on 2026-09-28 after 0557 (md5 of their source) ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)',                    '5e51d7ce498454993ac040379e772307'),
      ('ottoq.ottoq_book_workflow_legs(uuid,uuid,uuid,timestamp with time zone,integer,integer,text[],timestamp with time zone,text)',
                                                                                                  '5e627c00a761823854fd84701a19e93d'),
      ('ottoq.ottoq_route_faulted_cars_to_repair(uuid,uuid,timestamp with time zone)',            'e04e790f6e4f843c6de1b08078f7b52e')) x(sig, md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0558 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0558_pre', 'function', p.pronamespace::regnamespace::text, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'ottoq.ottoq_book_workflow_legs(uuid,uuid,uuid,timestamp with time zone,integer,integer,text[],timestamp with time zone,text)'::regprocedure,
                 'ottoq.ottoq_route_faulted_cars_to_repair(uuid,uuid,timestamp with time zone)'::regprocedure);

-- ── (a) and (b): splices in the planner and the booker ──
DO $splice$
DECLARE v_def text; n int; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    -- (a) 1: the flag
    ('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)',
$o$BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
$o$,
$n$  v_fault_first boolean := false;          -- 0558 (G292)
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
$n$),
    -- (a) 2: the repair first
    ('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)',
$o$  v_cursor := p_clock;
$o$,
$n$  v_cursor := p_clock;

  -- 0558 (G292, CLAUDE.md rule 9): a car with an open vehicle fault is repaired first. The emission gate refuses its
  -- charge until the repair is done (0557), so a plan with the charge first and the repair after it can never start:
  -- on 0411's run the car waited from 5:09 AM behind an 8-hour charge, its repair booked for 1:24 PM. The repair's
  -- service leg goes first, at the plan's start, and every other leg after it.
  v_fault_first := public.ottoq_vehicle_fault_open((SELECT vh.config FROM vehicles vh WHERE vh.id = p_vehicle))
                   AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_visit.atoms) a
                                WHERE a->>'svc' = 'fault_repair' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'));
  IF v_fault_first THEN
    SELECT a INTO v_a FROM jsonb_array_elements(v_visit.atoms) a
     WHERE a->>'svc' = 'fault_repair' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled') LIMIT 1;
    v_min := COALESCE((v_a->>'est_min')::numeric,
                      (SELECT scp.est_min_default FROM public.service_cadence_policy scp
                        WHERE scp.svc = 'fault_repair' AND scp.is_active LIMIT 1),
                      20);
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, 'service',
           v_cursor, v_cursor + (v_min::text || ' minutes')::interval, (v_min*60)::int,
           jsonb_build_object('kind','flow_contract','atom','fault_repair',
                              'queue_wait_min',round(COALESCE(v_svc_wait,0),1),'first_because','vehicle_fault_open'),
           'planned');
    v_cursor := v_cursor + (v_min::text || ' minutes')::interval;
  END IF;
$n$),
    -- (a) 3: the bay loop does not plan the repair a second time
    ('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)',
$o$    WHERE a->>'concurrency' = 'bay' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
$o$,
$n$    WHERE a->>'concurrency' = 'bay' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
      AND NOT (v_fault_first AND a->>'svc' = 'fault_repair')   -- 0558 (G292): planned first, above
$n$),
    -- (b) 1: the count
    ('ottoq.ottoq_book_workflow_legs(uuid,uuid,uuid,timestamp with time zone,integer,integer,text[],timestamp with time zone,text)',
$o$  v_skipped    int := 0;
$o$,
$n$  v_skipped    int := 0;
  v_fault_wait int := 0;   -- 0558 (G292)
$n$),
    -- (b) 2: no charger for a car that cannot charge
    ('ottoq.ottoq_book_workflow_legs(uuid,uuid,uuid,timestamp with time zone,integer,integer,text[],timestamp with time zone,text)',
$o$    IF v_want_type IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;
$o$,
$n$    IF v_want_type IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- 0558 (G292, CLAUDE.md rule 9): no charger is held for a car with an open vehicle fault. The emission gate refuses
    -- its charge until the repair is done (0557), so the charger would stand idle: on 0411's run an L2 stood idle from
    -- 6:20 AM for a car that could not charge. The leg stays unbooked; the next pass after the repair books it.
    IF v_leg.leg_type IN ('charge_dcfc','charge_l2')
       AND public.ottoq_vehicle_fault_open((SELECT vh.config FROM public.vehicles vh WHERE vh.id = p_vehicle_id)) THEN
      v_fault_wait := v_fault_wait + 1;
      v_detail := v_detail || jsonb_build_object('seq', v_leg.seq, 'leg', v_leg.leg_type, 'booked', false,
                    'stall_type', v_want_type, 'reason', 'vehicle_fault_open');
      CONTINUE;
    END IF;
$n$),
    -- (b) 3: say so
    ('ottoq.ottoq_book_workflow_legs(uuid,uuid,uuid,timestamp with time zone,integer,integer,text[],timestamp with time zone,text)',
$o$'unbookable', v_failed, 'rides_another_booking', v_skipped, 'legs', v_detail);
$o$,
$n$'unbookable', v_failed, 'rides_another_booking', v_skipped, 'waits_for_repair', v_fault_wait,
    'legs', v_detail);
$n$)) x(sig, a_old, a_new)
  LOOP
    v_def := pg_get_functiondef(r.sig::regprocedure);
    n := (length(v_def) - length(replace(v_def, r.a_old, ''))) / length(r.a_old);
    IF n <> 1 THEN RAISE EXCEPTION '0558 splice: the anchor matches % times in %, not 1: %', n, r.sig, left(r.a_old, 80); END IF;
    EXECUTE replace(v_def, r.a_old, r.a_new);
  END LOOP;
END $splice$;

-- ── (c) step (6): no charger held for a faulted car, and its plan re-made repair first ──
CREATE OR REPLACE FUNCTION ottoq.ottoq_route_faulted_cars_to_repair(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0555 (G290): a car the tow brought into emergency staging, with no cut-short visit for the readmit to resume, is not
-- left there for the rest of the day. Its repair goes on its card and it is staged for the service bay. The departure
-- test holds it until the repair is done.
-- 0557 (G291): and a car already staged with an open fault, on any step but need_service, goes back to need_service with
-- its repair on the card. Whatever relabels a staged car (a sweep, a triage, an approval), a faulted car does not wait
-- in the charge line or the wash line for work it does not get before its repair. A car already staged keeps its clock
-- (0546 (a), G272): only a move into staging stamps it.
-- 0558 (G292): and the plan a faulted car follows puts its repair first, with no charger held for it before the repair.
-- (i) A held charge booking of a car with an open fault is released and its charge leg unbooked, and a charger reserved
-- for it that it is not standing on is cleared: the emission gate refuses its charge (0557), so the charger would stand
-- idle. (ii) A staged car awaiting its repair whose plan does not put the repair ahead of every charge and bay leg still
-- to go is re-planned: those legs are skipped, their held bay bookings released (a parking hold stays), the plan closed,
-- and the planner, which puts an open fault's repair first, plans again. The planner builds no plan over one with legs
-- still to go, so without (ii) a car routed here from the charge line kept a plan whose first leg the gate refuses.
DECLARE v_rec record; v_n int := 0; v_cars jsonb := '[]'::jsonb; v_visit uuid; v_was_staged boolean;
        v_rel int := 0; v_unres int := 0; v_rp int := 0; v_relb int := 0; v_rp_cars jsonb := '[]'::jsonb; k int; kb int;
BEGIN
  IF p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;
  FOR v_rec IN
    SELECT vh.id, vh.config, vh.current_state::text AS st
      FROM public.vehicles vh
     WHERE vh.home_depot_id = p_depot_id AND vh.category = 'autonomous'
       AND public.ottoq_vehicle_fault_open(vh.config)
       AND ((vh.current_state = 'emergency_staged'
             AND COALESCE(vh.config->'exception'->>'status', '') = 'retrieved_staged')
         OR (vh.current_state = 'staged_awaiting_service'
             AND COALESCE(vh.config->>'svc_step', '') <> 'need_service'))
     ORDER BY vh.id   -- run-stable cursor order (0050)
  LOOP
    v_was_staged := v_rec.st = 'staged_awaiting_service';
    v_visit := ottoq.ottoq_add_fault_repair(p_sim_run_id, p_depot_id, v_rec.id, p_clock);
    IF v_was_staged THEN
      UPDATE public.vehicles
         SET config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', to_jsonb('need_service'::text))
                      || jsonb_build_object('exception', (config->'exception')
                           || jsonb_build_object('status', 'awaiting_repair', 'routed_to_repair_at', p_clock))
       WHERE id = v_rec.id;
    ELSE
      UPDATE public.vehicles
         SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_clock,
             config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', to_jsonb('need_service'::text))
                      || jsonb_build_object('exception', (config->'exception')
                           || jsonb_build_object('status', 'awaiting_repair', 'routed_to_repair_at', p_clock))
       WHERE id = v_rec.id;
    END IF;
    BEGIN
      PERFORM public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.id, p_clock);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0555 route to repair: re-plan failed for %: % %', v_rec.id, SQLSTATE, SQLERRM;
    END;
    v_n := v_n + 1;
    v_cars := v_cars || jsonb_build_array(jsonb_build_object(
                'vehicle_id', v_rec.id, 'visit_id', v_visit,
                'from', CASE WHEN v_was_staged THEN 'staged on ' || COALESCE(v_rec.config->>'svc_step', 'no step')
                             ELSE 'emergency_staged' END,
                'fault_class', v_rec.config->'exception'->>'fault_class',
                'severity', v_rec.config->'exception'->>'severity',
                'immobilizing', v_rec.config->'exception'->'immobilizing'));
  END LOOP;

  -- 0558 (G292) (i): no charger held for a car that cannot charge before its repair
  FOR v_rec IN
    SELECT b.booking_id, b.leg_id
      FROM public.ottoq_stall_bookings b
      JOIN public.vehicles vh ON vh.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id AND b.state = 'held' AND b.purpose IN ('charge_dcfc', 'charge_l2')
       AND vh.home_depot_id = p_depot_id AND public.ottoq_vehicle_fault_open(vh.config)
     ORDER BY b.vehicle_id, lower(b.during), b.stall_id   -- run-stable cursor order (0050): no minted id
  LOOP
    UPDATE public.ottoq_stall_bookings b
       SET state = 'released', released_at = GREATEST(p_clock, COALESCE(b.booked_at_sim, p_clock)),
           release_reason = 'vehicle_fault_open'
     WHERE b.booking_id = v_rec.booking_id AND b.state = 'held';
    UPDATE public.ottoq_itinerary_legs SET to_stall_id = NULL
     WHERE leg_id = v_rec.leg_id AND status = 'planned';
    v_rel := v_rel + 1;
  END LOOP;
  UPDATE public.stalls s
     SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
    FROM public.vehicles vh
   WHERE s.reserved_by = vh.id AND s.current_vehicle_id IS NULL AND s.depot_id = p_depot_id
     AND s.stall_type::text IN ('dcfc', 'l2')
     AND vh.home_depot_id = p_depot_id AND public.ottoq_vehicle_fault_open(vh.config);
  GET DIAGNOSTICS v_unres = ROW_COUNT;

  -- 0558 (G292) (ii): a staged car awaiting its repair follows a plan with the repair first
  FOR v_rec IN
    SELECT vh.id
      FROM public.vehicles vh
     WHERE vh.home_depot_id = p_depot_id AND vh.category = 'autonomous'
       AND vh.current_state = 'staged_awaiting_service'
       AND COALESCE(vh.config->>'svc_step', '') = 'need_service'
       AND public.ottoq_vehicle_fault_open(vh.config)
       -- the visit the planner reads (the newest open one) still owes the repair
       AND EXISTS (SELECT 1
                     FROM (SELECT n.atoms FROM public.ottoq_visit_needs n
                            WHERE n.vehicle_id = vh.id AND n.status IN ('open', 'in_progress')
                              AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                            ORDER BY n.created_at DESC, n.visit_key DESC LIMIT 1) nv,
                          jsonb_array_elements(nv.atoms) a
                    WHERE a->>'svc' = 'fault_repair' AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled'))
       -- and its plan does not have the repair ahead of every charge and bay leg still to go
       AND NOT EXISTS (
             SELECT 1
               FROM public.ottoq_vehicle_itineraries i
               JOIN public.ottoq_itinerary_legs lr ON lr.itinerary_id = i.itinerary_id
              WHERE i.vehicle_id = vh.id AND i.sim_run_id = p_sim_run_id AND i.status = 'active'
                AND lr.status IN ('planned', 'active') AND lr.leg_type = 'service'
                AND lr.duration_basis->>'atom' = 'fault_repair'
                AND NOT EXISTS (SELECT 1 FROM public.ottoq_itinerary_legs lo
                                 WHERE lo.itinerary_id = i.itinerary_id AND lo.status IN ('planned', 'active')
                                   AND lo.leg_type IN ('charge_dcfc', 'charge_l2', 'wash', 'detail', 'service')
                                   AND lo.seq < lr.seq))
     ORDER BY vh.id   -- run-stable cursor order (0050)
  LOOP
    BEGIN
      UPDATE public.ottoq_stall_bookings b
         SET state = 'released', released_at = GREATEST(p_clock, COALESCE(b.booked_at_sim, p_clock)),
             release_reason = 'replanned_repair_first'
        FROM public.ottoq_itinerary_legs l
        JOIN public.ottoq_vehicle_itineraries i ON i.itinerary_id = l.itinerary_id
       WHERE b.leg_id = l.leg_id AND b.vehicle_id = v_rec.id AND b.state = 'held'
         AND b.purpose IN ('charge_dcfc', 'charge_l2', 'wash', 'detail', 'service', 'inspect')
         AND i.vehicle_id = v_rec.id AND i.sim_run_id = p_sim_run_id AND i.status = 'active' AND l.status = 'planned';
      GET DIAGNOSTICS kb = ROW_COUNT;
      UPDATE public.ottoq_itinerary_legs l SET status = 'skipped'
        FROM public.ottoq_vehicle_itineraries i
       WHERE l.itinerary_id = i.itinerary_id AND i.vehicle_id = v_rec.id AND i.sim_run_id = p_sim_run_id
         AND i.status = 'active' AND l.status = 'planned';
      UPDATE public.ottoq_vehicle_itineraries SET status = 'completed'
       WHERE vehicle_id = v_rec.id AND sim_run_id = p_sim_run_id AND status = 'active';
      k := COALESCE(public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.id, p_clock), 0);
      v_rp := v_rp + 1; v_relb := v_relb + kb;
      v_rp_cars := v_rp_cars || jsonb_build_array(jsonb_build_object(
                     'vehicle_id', v_rec.id, 'legs_planned', k, 'bay_bookings_released', kb));
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0558 re-plan repair first: failed for %: % %', v_rec.id, SQLSTATE, SQLERRM;
    END;
  END LOOP;

  IF v_n > 0 OR v_rel > 0 OR v_unres > 0 OR v_rp > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'route_faulted_cars_to_repair',
        p_event_type := 'ottoq.faulted_car_routed_to_repair', p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_depot_id := p_depot_id,
        p_payload := jsonb_build_object('routed', v_n, 'cars', v_cars,
          'charge_bookings_released', v_rel, 'charger_reservations_cleared', v_unres,
          'replanned_repair_first', v_rp, 'replanned_cars', v_rp_cars, 'bay_bookings_released', v_relb,
          'note', 'a faulted car goes to the service bay for its repair before anything else, and does not charge or '
                  || 'leave until it is repaired (CLAUDE.md rule 9)'),
        p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0555 route to repair: summary event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END IF;
  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- never allowed to take the tick down (house rule 4)
  RAISE WARNING 'ottoq.ottoq_route_faulted_cars_to_repair FAILED SAFELY: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END
$fn$;
COMMENT ON FUNCTION ottoq.ottoq_route_faulted_cars_to_repair(uuid, uuid, timestamptz) IS
  '0555 (G290), 0557 (G291), 0558 (G292): step (6) of the fault handler. A car in emergency staging (retrieved_staged) '
  'that the readmit did not take, and a car already staged with an open fault on any step but need_service, get their '
  'fault_repair on the card and are staged for the service bay (exception status awaiting_repair). No charger is held '
  'for a car with an open fault, and a staged car awaiting its repair follows a plan with the repair first.';

-- ── V1 (comment-stripped): each change is in the live source ──
DO $verify$
DECLARE r record; v_src text; k int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)',
       'v_fault_first := public\.ottoq_vehicle_fault_open\(\(SELECT vh\.config FROM vehicles vh WHERE vh\.id = p_vehicle\)\)', 1),
      ('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)',
       '''first_because'',''vehicle_fault_open''', 1),
      ('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)',
       'AND NOT \(v_fault_first AND a->>''svc'' = ''fault_repair''\)', 1),
      ('ottoq.ottoq_book_workflow_legs(uuid,uuid,uuid,timestamp with time zone,integer,integer,text[],timestamp with time zone,text)',
       'IF v_leg\.leg_type IN \(''charge_dcfc'',''charge_l2''\)\s+AND public\.ottoq_vehicle_fault_open', 1),
      ('ottoq.ottoq_book_workflow_legs(uuid,uuid,uuid,timestamp with time zone,integer,integer,text[],timestamp with time zone,text)',
       '''waits_for_repair'', v_fault_wait', 1),
      ('ottoq.ottoq_route_faulted_cars_to_repair(uuid,uuid,timestamp with time zone)',
       'release_reason = ''vehicle_fault_open''', 1),
      ('ottoq.ottoq_route_faulted_cars_to_repair(uuid,uuid,timestamp with time zone)',
       'release_reason = ''replanned_repair_first''', 1),
      ('ottoq.ottoq_route_faulted_cars_to_repair(uuid,uuid,timestamp with time zone)',
       'lr\.duration_basis->>''atom'' = ''fault_repair''', 1)
    ) x(sig, pat, want)
  LOOP
    v_src := regexp_replace(regexp_replace(pg_get_functiondef(r.sig::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
    k := (SELECT count(*) FROM regexp_matches(v_src, r.pat, 'g'));
    IF k <> r.want THEN RAISE EXCEPTION '0558 V1: % matches % times in %, not %', r.pat, k, r.sig, r.want; END IF;
  END LOOP;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0558_a_faulted_cars_repair_goes_first_in_its_plan', true, true,
  'G292: the planner put a faulted car''s repair after its charge, and since 0557 the gate refuses that charge until the '
  'repair is done, so the plan could never start (0411: a car waited from 5:09 AM behind an 8-hour charge, its repair '
  'booked for 1:24 PM, while an L2 stood idle booked for it). The planner now puts an open fault''s repair first; the '
  'booker books no charger for a faulted car; the fault handler''s step (6) releases a faulted car''s held charge '
  'bookings and re-plans a staged car awaiting its repair whose plan does not put the repair first.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest ended operator run at the twin depot, pinned as the active run for this transaction.
--   Two free twin cars, every other twin car offline, every twin L2 charger reporting Available. Both are staged at
--   50% on need_charge with a visit that owes a charge, an exterior wash and the readiness check, and both are planned
--   and booked while neither has a fault: the charge first, then the wash. C stays fault-free (the control). F then
--   takes a critical sensor-suite fault that does not immobilize it, waiting where it is.
--   (1) step (6) at t + 1 min puts F on need_service with its repair, releases its charge booking (vehicle_fault_open)
--       and its wash booking (replanned_repair_first), closes its old plan, and plans again: the repair's service leg
--       first, at t + 1 min, and the charge after the repair's planned end. C's plan and charge booking are untouched.
--   (2) the booker books F's repair on a service bay and no charger (waits_for_repair = 1);
--   (3) a second pass of step (6) leaves F's plan and its repair booking alone;
--   (4) once the repair is done (the exception gone, the atom credited), the booker books F's charge.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; car uuid[]; cc uuid; f uuid;
  it_c0 uuid; it_c1 uuid; it_f0 uuid; it_f1 uuid; it_f2 uuid; bc_chg uuid; bf_chg uuid; bf_wash uuid;
  st_bf_chg text; rr_bf_chg text; st_bf_wash text; rr_bf_wash text; st_bc_chg text; it_f0_status text;
  n_old_planned int; n_old_skipped int; rep_leg uuid; rep_seq int; first_seq int;
  rep_start timestamptz; rep_end timestamptz; chg_start timestamptz;
  wf jsonb; wf2 jsonb; svc_bk int; chg_bk_f int; chg_bk_f2 int; nr int; nr2 int; sf text; xf text; v_pass text;
BEGIN
  BEGIN
    SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.run_by = 'operator_demo' AND r.status NOT IN ('initializing', 'running', 'paused')
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0558 V3: no ended operator run at the twin depot'; END IF;
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t, tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);

    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 2) q;
    IF coalesce(array_length(car, 1), 0) < 2 THEN RAISE EXCEPTION '0558 V3: fewer than two free twin cars'; END IF;
    cc := car[1]; f := car[2];

    -- only these two in play; every twin L2 charger reporting Available
    UPDATE public.vehicles SET current_state = 'offline'
     WHERE home_depot_id = v_depot AND NOT (id = ANY (car)) AND robotic_tether_until IS NULL AND current_state <> 'offline';
    UPDATE public.ottoq_ocpp_chargers c2 SET station_state = 'Available', last_heartbeat_at = t
      FROM public.stalls s
     WHERE s.ocpp_charger_id = c2.charger_id AND s.depot_id = v_depot AND s.stall_type::text = 'l2';
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.ottoq_vehicle_itineraries SET status = 'completed'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status = 'active';
    UPDATE public.ottoq_stall_bookings
       SET state = 'released', released_at = GREATEST(t, COALESCE(booked_at_sim, t)), release_reason = 'v3_0558_setup'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND state IN ('held', 'active');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', current_depot_id = v_depot, current_soc = 50, target_soc = 100,
           last_state_change = t - interval '10 minutes',
           config = (COALESCE(config, '{}'::jsonb) - 'charge_wait' - 'remedy_wait' - 'deploy_gate' - 'flagged_issue'
                     - 'flagged_issue_type' - 'service_ends_at' - 'exception' - 'bay_need')
                    || jsonb_build_object('svc_step', 'need_charge')
     WHERE id = ANY (car);
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, target_soc, atoms,
                                          status, source)
    SELECT x.vid, v_run, v_depot, t - interval '1 hour', 'V3-0558-' || x.vid::text, 'standard', 100,
           jsonb_build_array(jsonb_build_object('svc', 'charge', 'concurrency', 'anchor', 'must_do', true, 'status', 'pending'),
                             jsonb_build_object('svc', 'exterior_wash', 'concurrency', 'bay', 'must_do', true, 'status', 'pending',
                                                'est_min', 8, 'requires_bay', 'wash_bay'),
                             jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending')),
           'open', 'v3_0558'
      FROM unnest(car) AS x(vid);

    -- both planned and booked while neither has a fault: the charge first, then the wash
    PERFORM public.ottoq_plan_visit_itinerary(v_run, cc, t);
    PERFORM public.ottoq_plan_visit_itinerary(v_run, f, t);
    PERFORM ottoq.ottoq_book_workflow_legs(v_run, cc, v_depot, t);
    PERFORM ottoq.ottoq_book_workflow_legs(v_run, f, v_depot, t);
    SELECT itinerary_id INTO it_c0 FROM public.ottoq_vehicle_itineraries WHERE vehicle_id = cc AND sim_run_id = v_run AND status = 'active';
    SELECT itinerary_id INTO it_f0 FROM public.ottoq_vehicle_itineraries WHERE vehicle_id = f AND sim_run_id = v_run AND status = 'active';
    SELECT booking_id INTO bc_chg FROM public.ottoq_stall_bookings
     WHERE vehicle_id = cc AND sim_run_id = v_run AND state = 'held' AND purpose IN ('charge_dcfc', 'charge_l2');
    SELECT booking_id INTO bf_chg FROM public.ottoq_stall_bookings
     WHERE vehicle_id = f AND sim_run_id = v_run AND state = 'held' AND purpose IN ('charge_dcfc', 'charge_l2');
    SELECT booking_id INTO bf_wash FROM public.ottoq_stall_bookings
     WHERE vehicle_id = f AND sim_run_id = v_run AND state = 'held' AND purpose = 'wash';
    IF it_c0 IS NULL OR it_f0 IS NULL OR bc_chg IS NULL OR bf_chg IS NULL OR bf_wash IS NULL THEN
      RAISE EXCEPTION '0558 V3 setup: plans C % and F %, C''s charge booking %, F''s charge booking % and wash booking %',
        it_c0, it_f0, bc_chg, bf_chg, bf_wash;
    END IF;

    -- F's fault opens: critical, not immobilizing, while it waits on need_charge
    UPDATE public.vehicles
       SET config = config || jsonb_build_object('exception', jsonb_build_object(
             'type', 'vehicle_fault', 'flagged_at', t, 'status', 'retrieved_staged', 'severity', 'critical',
             'fault_class', 'sensor_suite_fault', 'immobilizing', false, 'service_incompatible', false))
     WHERE id = f;

    -- (1) step (6) at t + 1 minute
    nr := ottoq.ottoq_route_faulted_cars_to_repair(v_run, v_depot, t + interval '1 minute');
    SELECT config->>'svc_step', config->'exception'->>'status' INTO sf, xf FROM public.vehicles WHERE id = f;
    SELECT state, release_reason INTO st_bf_chg, rr_bf_chg FROM public.ottoq_stall_bookings WHERE booking_id = bf_chg;
    SELECT state, release_reason INTO st_bf_wash, rr_bf_wash FROM public.ottoq_stall_bookings WHERE booking_id = bf_wash;
    SELECT state INTO st_bc_chg FROM public.ottoq_stall_bookings WHERE booking_id = bc_chg;
    SELECT status INTO it_f0_status FROM public.ottoq_vehicle_itineraries WHERE itinerary_id = it_f0;
    SELECT count(*) FILTER (WHERE status = 'planned'), count(*) FILTER (WHERE status = 'skipped')
      INTO n_old_planned, n_old_skipped FROM public.ottoq_itinerary_legs WHERE itinerary_id = it_f0;
    SELECT itinerary_id INTO it_f1 FROM public.ottoq_vehicle_itineraries
     WHERE vehicle_id = f AND sim_run_id = v_run AND status = 'active' ORDER BY sim_created_at DESC, created_at DESC LIMIT 1;
    SELECT itinerary_id INTO it_c1 FROM public.ottoq_vehicle_itineraries
     WHERE vehicle_id = cc AND sim_run_id = v_run AND status = 'active' ORDER BY sim_created_at DESC, created_at DESC LIMIT 1;
    SELECT l.leg_id, l.seq, l.planned_start_sim, l.planned_end_sim INTO rep_leg, rep_seq, rep_start, rep_end
      FROM public.ottoq_itinerary_legs l
     WHERE l.itinerary_id = it_f1 AND l.leg_type = 'service' AND l.duration_basis->>'atom' = 'fault_repair' AND l.status = 'planned';
    SELECT min(seq) INTO first_seq FROM public.ottoq_itinerary_legs
     WHERE itinerary_id = it_f1 AND status = 'planned' AND leg_type IN ('charge_dcfc', 'charge_l2', 'wash', 'detail', 'service');
    SELECT min(planned_start_sim) INTO chg_start FROM public.ottoq_itinerary_legs
     WHERE itinerary_id = it_f1 AND status = 'planned' AND leg_type IN ('charge_dcfc', 'charge_l2');
    IF nr < 1 OR sf IS DISTINCT FROM 'need_service' OR xf IS DISTINCT FROM 'awaiting_repair'
       OR st_bf_chg IS DISTINCT FROM 'released' OR rr_bf_chg IS DISTINCT FROM 'vehicle_fault_open'
       OR st_bf_wash IS DISTINCT FROM 'released' OR rr_bf_wash IS DISTINCT FROM 'replanned_repair_first'
       OR it_f0_status IS DISTINCT FROM 'completed' OR n_old_planned <> 0 OR n_old_skipped < 1
       OR it_f1 IS NULL OR it_f1 = it_f0 OR rep_leg IS NULL OR rep_seq IS DISTINCT FROM first_seq
       OR rep_start IS DISTINCT FROM t + interval '1 minute' OR chg_start IS NULL OR chg_start < rep_end
       OR st_bc_chg IS DISTINCT FROM 'held' OR it_c1 IS DISTINCT FROM it_c0 THEN
      RAISE EXCEPTION '0558 V3 FAILED (1): routed %, F on % (exception %); F''s charge booking % (%), wash booking % (%); '
                      'old plan % with % planned and % skipped legs; new plan % (old %): repair leg % at seq % (first %) from % '
                      'to %, charge from %; C''s charge booking %, plan % (was %)',
        nr, sf, xf, st_bf_chg, rr_bf_chg, st_bf_wash, rr_bf_wash, it_f0_status, n_old_planned, n_old_skipped,
        it_f1, it_f0, rep_leg, rep_seq, first_seq, rep_start, rep_end, chg_start, st_bc_chg, it_c1, it_c0;
    END IF;

    -- (2) the booker books F's repair on a service bay and no charger
    wf := ottoq.ottoq_book_workflow_legs(v_run, f, v_depot, t + interval '1 minute');
    SELECT count(*) INTO svc_bk FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.vehicle_id = f AND b.sim_run_id = v_run AND b.state = 'held' AND b.purpose = 'service'
       AND b.leg_id = rep_leg AND s.stall_type::text = 'service_bay';
    SELECT count(*) INTO chg_bk_f FROM public.ottoq_stall_bookings
     WHERE vehicle_id = f AND sim_run_id = v_run AND state = 'held' AND purpose IN ('charge_dcfc', 'charge_l2');
    IF COALESCE((wf->>'waits_for_repair')::int, -1) <> 1 OR svc_bk <> 1 OR chg_bk_f <> 0 THEN
      RAISE EXCEPTION '0558 V3 FAILED (2): the booker returned %; F holds % service booking(s) for its repair and % charge booking(s)',
        wf, svc_bk, chg_bk_f;
    END IF;

    -- (3) a second pass of step (6) leaves F's plan and its repair booking alone
    nr2 := ottoq.ottoq_route_faulted_cars_to_repair(v_run, v_depot, t + interval '2 minutes');
    SELECT itinerary_id INTO it_f2 FROM public.ottoq_vehicle_itineraries
     WHERE vehicle_id = f AND sim_run_id = v_run AND status = 'active' ORDER BY sim_created_at DESC, created_at DESC LIMIT 1;
    SELECT count(*) INTO svc_bk FROM public.ottoq_stall_bookings
     WHERE vehicle_id = f AND sim_run_id = v_run AND state = 'held' AND purpose = 'service' AND leg_id = rep_leg;
    IF nr2 <> 0 OR it_f2 IS DISTINCT FROM it_f1 OR svc_bk <> 1 THEN
      RAISE EXCEPTION '0558 V3 FAILED (3): the second pass routed %, F''s plan is % (was %), its repair booking count %',
        nr2, it_f2, it_f1, svc_bk;
    END IF;

    -- (4) the repair done (the service bay removes the exception and credits the atom): the booker books F's charge
    UPDATE public.vehicles SET config = config - 'exception' WHERE id = f;
    UPDATE public.ottoq_visit_needs n
       SET atoms = (SELECT jsonb_agg(CASE WHEN x.a->>'svc' = 'fault_repair'
                                          THEN x.a || jsonb_build_object('status', 'done', 'done_at', t + interval '80 minutes')
                                          ELSE x.a END ORDER BY x.o)
                      FROM jsonb_array_elements(n.atoms) WITH ORDINALITY x(a, o))
     WHERE n.vehicle_id = f AND n.sim_run_id = v_run AND n.status IN ('open', 'in_progress');
    UPDATE public.ottoq_itinerary_legs SET status = 'done' WHERE leg_id = rep_leg;
    UPDATE public.ottoq_stall_bookings SET state = 'done'
     WHERE vehicle_id = f AND sim_run_id = v_run AND leg_id = rep_leg AND state = 'held';
    wf2 := ottoq.ottoq_book_workflow_legs(v_run, f, v_depot, t + interval '80 minutes');
    SELECT count(*) INTO chg_bk_f2 FROM public.ottoq_stall_bookings
     WHERE vehicle_id = f AND sim_run_id = v_run AND state = 'held' AND purpose IN ('charge_dcfc', 'charge_l2');
    IF COALESCE((wf2->>'waits_for_repair')::int, -1) <> 0 OR chg_bk_f2 <> 1 THEN
      RAISE EXCEPTION '0558 V3 FAILED (4): after the repair the booker returned % and F holds % charge booking(s)', wf2, chg_bk_f2;
    END IF;

    v_pass := format('0558 V3 PASSED on run %s: step (6) put F (an open sensor-suite fault) on need_service, released '
                     || 'its charge booking (vehicle_fault_open) and wash booking (replanned_repair_first), closed its '
                     || 'charge-first plan and planned the repair first (seq %s, %s to %s) with the charge from %s; the '
                     || 'booker booked the repair on a service bay and no charger (waits_for_repair 1); a second pass '
                     || 'left the plan alone; after the repair the booker booked the charge; C''s plan and charge '
                     || 'booking were untouched', v_run, rep_seq, rep_start, rep_end, chg_start);
    RAISE EXCEPTION '%', v_pass;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0558 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0558 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0558_pre' as it is (the planner and the
-- booker as they were, and step (6) as 0557 left it).

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-28 to gxdrcyphqjzjsuhxuqtg, 6:55 PM CT (ledger 20260928235524).
--   public.ottoq_plan_visit_itinerary               5e51d7ce498454993ac040379e772307 -> 990e9481a4917ae0d23dc78e205896aa
--   ottoq.ottoq_book_workflow_legs                  5e627c00a761823854fd84701a19e93d -> 6fd66cb3893bcc250d13a9e71758cf3b
--   ottoq.ottoq_route_faulted_cars_to_repair        e04e790f6e4f843c6de1b08078f7b52e -> c35dd18bb69226bfdcacb800e2a86305
--   V1 and V3 passed: the transaction commits only if both do. A dry run (ROLLBACK in place of COMMIT) passed first and
--   left nothing behind (the three md5s unchanged, no 0558_pre snapshot, no lineage row). ottoq_cert_recert_floor()
--   moved to 2026-09-28 23:55:24.089925+00; the sweep restarted.
