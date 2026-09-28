-- migration-version: 20260928220015
-- migration-name:    a_faulted_car_is_repaired_before_it_charges
-- (applied 2026-09-28, 5:00 PM CT, after the 0555/0556 sweep passed 9 of 9, verdicts 594-602.)
--
-- 0557  **A car with an open vehicle fault is repaired before it charges.** (G291; CLAUDE.md rule 9)
--
-- ══ §1 WHY (found reading the charge paths, 2026-09-28, while 0555's recert sweep ran) ═══════════════════════════════════
--
--   0555 stages a faulted car for the service bay: the readmit paths and the fault handler's step (6) give it a must-do
--   `fault_repair` and `svc_step` need_service. But two writers that can put a staged car in the charge line read where
--   the car is parked, not what it waits for:
--     - the decide tick's charge cursor takes any `staged_awaiting_service` car below its target while a charger is free,
--       whatever its step;
--     - the service flow's stranded-recharge sweep (STEP 0) relabels any staged car below the deploy floor (80%) with an
--       open charge atom `need_charge`, and books it a staging hold.
--   So a faulted car routed to the service bay with a charge still to do can be charged first. For a `hv_battery_thermal`
--   or `charge_system_fault` (the handler's `service_incompatible` faults: it yanks such a car off its charger because
--   the charge must not continue) that is a charge on a battery or charging system that has faulted. Before 0555 the gap
--   was wider: the readmit sent such a car straight back to need_charge. Not observed on 0410's run, whose two faults
--   were a major fault and a steering/brake fault; the paths were read, not measured.
--
--   CLAUDE.md rule 9 names the order: a vehicle emergency takes the car offline or routes it to a service stall. Every
--   fault the twin raises takes the car offline (the handler sends every faulted car to `tow_requested`), so a faulted car
--   is repaired first, then charged, then released.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The decide tick's charge cursor does not take a car with an open vehicle fault (`public.ottoq_vehicle_fault_open`).
--   (b) The service flow's STEP 0 does not relabel it need_charge.
--   (c) The emission gate (`ottoq.ottoq_validate_assignment`) refuses `begin_charge` for it with `vehicle_fault_open`: the
--       floor under (a) and (b) for every other door a charge can start from (the proposers, the refusal reactor, the
--       hardware recall). The refusal reactor reroutes only `target_occupied` and `resource_faulted`, so this code is
--       never rerouted to another charger.
--   (d) The fault handler's step (6) (`ottoq.ottoq_route_faulted_cars_to_repair`) also takes a car already staged with an
--       open fault on any step but need_service back to need_service, with its repair on the card. Whatever relabels a
--       staged car (a sweep, a triage, an approval), a faulted car is back in the service bay's line within a tick. A car
--       already staged keeps its clock (0546 (a)); only a move into staging stamps it.
--   (e) The opportunistic top-off planner does not ask a person to approve a top-off for a car awaiting its repair.
--   (f) The cockpit's charge queue (`public.ottoq_depot_queue`) leaves it out, as the cursor does.
--   A car whose fault lets its current charge finish (the handler's deferred eviction: immobilizing, not
--   service-incompatible) keeps that session to its end as before. This file is about starting a charge.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   The decide tick, the service flow, the emission gate and the fault handler's step (6) run in every arm.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - The cuOpt and CP-SAT frames still list a faulted car among the cars waiting for a charger. Their proposals are
--     enacted only through the cursor, which no longer takes it, so no charge starts; a solution may still spend a
--     charger on it that another car could have had.
--   - G288 (the cockpit's queue leaves out staged cars while no charger is free, and reservation holders).

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0557 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 edits twin cars, visits, chargers and bookings on an ended run) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0557 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the six functions are the ones measured on 2026-09-28 after 0555 + 0556 (md5 of their source) ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_decide_tick(uuid)',                                                          '2187f8565d4e8d33c646f8efb7316e2c'),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',         '0b852abe1944dd93f8e35c9d2f6967bd'),
      ('ottoq.ottoq_validate_assignment(uuid,uuid,text,timestamp with time zone,uuid)',           'd896e3b23991675840157f7357190ba5'),
      ('ottoq.ottoq_route_faulted_cars_to_repair(uuid,uuid,timestamp with time zone)',            'eb428364241f3d112ea59d4787b82e7c'),
      ('ottoq.ottoq_plan_opportunistic_charges(uuid,uuid,timestamp with time zone,bigint)',       '7b010072f6f3b52f534aa4e6194e6afa'),
      ('public.ottoq_depot_queue(uuid,uuid)',                                                     'b1c77098b93d8ff19e209aa5811c48b6')) x(sig, md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0557 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0557_pre', 'function', p.pronamespace::regnamespace::text, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_decide_tick(uuid)'::regprocedure,
                 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure,
                 'ottoq.ottoq_validate_assignment(uuid,uuid,text,timestamp with time zone,uuid)'::regprocedure,
                 'ottoq.ottoq_route_faulted_cars_to_repair(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'ottoq.ottoq_plan_opportunistic_charges(uuid,uuid,timestamp with time zone,bigint)'::regprocedure,
                 'public.ottoq_depot_queue(uuid,uuid)'::regprocedure);

-- ── (a)-(c), (e), (f): one line in each reader of the charge line ──
DO $splice$
DECLARE v_def text; n int; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_decide_tick(uuid)',
$o$       AND NOT public.ottoq_cuopt_defer_hold(p_sim_run_id, v.id, v_tick)
$o$,
$n$       AND NOT public.ottoq_cuopt_defer_hold(p_sim_run_id, v.id, v_tick)
       -- 0557 (G291, CLAUDE.md rule 9): a car with an open vehicle fault is repaired before it charges. It waits in
       -- staging for the service bay, and this cursor reads a staged car by where it is parked, not what it waits for.
       AND NOT public.ottoq_vehicle_fault_open(v.config)
$n$),
    ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
$o$       AND v.current_state IN ('charge_complete_holding','staged_awaiting_service','staged_for_departure')
       AND v.current_soc < v_floor
$o$,
$n$       AND v.current_state IN ('charge_complete_holding','staged_awaiting_service','staged_for_departure')
       AND v.current_soc < v_floor
       -- 0557 (G291): not a car with an open vehicle fault. It is staged for its repair, and relabelling it need_charge
       -- would put it in the charge line first.
       AND NOT public.ottoq_vehicle_fault_open(v.config)
$n$),
    ('ottoq.ottoq_validate_assignment(uuid,uuid,text,timestamp with time zone,uuid)',
$o$  IF v_veh.st IN ('tow_requested','out_of_service') THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_unresponsive','detail','vehicle is '||v_veh.st);
  END IF;
$o$,
$n$  IF v_veh.st IN ('tow_requested','out_of_service') THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_unresponsive','detail','vehicle is '||v_veh.st);
  END IF;
  -- 0557 (G291, CLAUDE.md rule 9): a car with an open vehicle fault is repaired before it charges. The floor under the
  -- charge cursor and the stranded-recharge sweep, for every other door a charge can start from.
  IF p_command_type = 'begin_charge'
     AND public.ottoq_vehicle_fault_open((SELECT v2.config FROM vehicles v2 WHERE v2.id = p_vehicle_id)) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_fault_open',
                              'detail','the car carries a vehicle fault that has not been repaired');
  END IF;
$n$),
    ('ottoq.ottoq_plan_opportunistic_charges(uuid,uuid,timestamp with time zone,bigint)',
$o$         AND v.current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding')
         AND v.current_soc < v_thresh
$o$,
$n$         AND v.current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding')
         AND v.current_soc < v_thresh
         AND NOT public.ottoq_vehicle_fault_open(v.config)   -- 0557 (G291): no top-off offered before the repair
$n$),
    ('public.ottoq_depot_queue(uuid,uuid)',
$o$       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
$o$,
$n$       AND NOT public.ottoq_vehicle_fault_open(v.config)   -- 0557 (G291): as the cursor
       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
$n$)) x(sig, a_old, a_new)
  LOOP
    v_def := pg_get_functiondef(r.sig::regprocedure);
    n := (length(v_def) - length(replace(v_def, r.a_old, ''))) / length(r.a_old);
    IF n <> 1 THEN RAISE EXCEPTION '0557 splice: the anchor matches % times in %, not 1', n, r.sig; END IF;
    EXECUTE replace(v_def, r.a_old, r.a_new);
  END LOOP;
END $splice$;

-- ── (d) step (6) also takes a staged car with an open fault on any other step back to the service bay's line ──
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
DECLARE v_rec record; v_n int := 0; v_cars jsonb := '[]'::jsonb; v_visit uuid; v_was_staged boolean;
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
  IF v_n > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'route_faulted_cars_to_repair',
        p_event_type := 'ottoq.faulted_car_routed_to_repair', p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_depot_id := p_depot_id,
        p_payload := jsonb_build_object('routed', v_n, 'cars', v_cars,
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
  '0555 (G290), 0557 (G291): step (6) of the fault handler. A car in emergency staging (retrieved_staged) that the readmit '
  'did not take, and a car already staged with an open fault on any step but need_service, get their fault_repair on the '
  'card and are staged for the service bay (exception status awaiting_repair).';

-- ── V1 (comment-stripped): each change is in the live source ──
DO $verify$
DECLARE r record; v_src text; k int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_decide_tick(uuid)',
       'AND NOT public\.ottoq_cuopt_defer_hold\(p_sim_run_id, v\.id, v_tick\)\s+AND NOT public\.ottoq_vehicle_fault_open\(v\.config\)', 1),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
       'AND v\.current_soc < v_floor\s+AND NOT public\.ottoq_vehicle_fault_open\(v\.config\)', 1),
      ('ottoq.ottoq_validate_assignment(uuid,uuid,text,timestamp with time zone,uuid)',
       'IF p_command_type = ''begin_charge''\s+AND public\.ottoq_vehicle_fault_open\(\(SELECT v2\.config FROM vehicles v2 WHERE v2\.id = p_vehicle_id\)\) THEN\s+RETURN jsonb_build_object\(''ok'',false,''code'',''vehicle_fault_open''', 1),
      ('ottoq.ottoq_plan_opportunistic_charges(uuid,uuid,timestamp with time zone,bigint)',
       'AND v\.current_soc < v_thresh\s+AND NOT public\.ottoq_vehicle_fault_open\(v\.config\)', 1),
      ('public.ottoq_depot_queue(uuid,uuid)',
       'AND NOT public\.ottoq_vehicle_fault_open\(v\.config\)\s+AND \(v\.current_state = ''arrived_at_gate''', 1),
      ('ottoq.ottoq_route_faulted_cars_to_repair(uuid,uuid,timestamp with time zone)',
       'OR \(vh\.current_state = ''staged_awaiting_service''\s+AND COALESCE\(vh\.config->>''svc_step'', ''''\) <> ''need_service''\)', 1)
    ) x(sig, pat, want)
  LOOP
    v_src := regexp_replace(regexp_replace(pg_get_functiondef(r.sig::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
    k := (SELECT count(*) FROM regexp_matches(v_src, r.pat, 'g'));
    IF k <> r.want THEN RAISE EXCEPTION '0557 V1: % matches % times in %, not %', r.pat, k, r.sig, r.want; END IF;
  END LOOP;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0557_a_faulted_car_is_repaired_before_it_charges', true, true,
  'G291: a car staged for its fault repair could be sent to a charger first. The charge cursor reads a staged car by '
  'where it is parked, and the service flow''s stranded-recharge sweep relabels a staged car below the floor need_charge, '
  'so a battery or charging-system fault could be charged before its repair. The cursor, the sweep, the opportunistic '
  'top-off and the cockpit''s queue now leave a car with an open fault out; the emission gate refuses begin_charge for it '
  '(vehicle_fault_open); the fault handler''s step (6) puts a staged faulted car on any other step back on need_service '
  'with its repair.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest ended operator run at the twin depot, pinned as the active run for this transaction.
--   Every other twin car is offline (the run's teardown) and every twin charger but one free L2 is faulted. Three cars
--   staged at 50%, below the 80% floor STEP 0 acts on, each with a charge still to do:
--   H has an open `hv_battery_thermal` fault, is on need_service with its repair on the card, and has waited 120 minutes
--     (its ratio, (120 + 50) / 50 = 3.4, would put it first in the charge line);
--   C has no fault, is on need_charge, and has waited 10 minutes (ratio 1.2). C is the first free twin car by id, the
--     car 0551's V3 saw take an L2 charger from the decide tick;
--   K has the same fault as H but was relabelled need_charge, with no repair on its card yet.
--   (1) the emission gate refuses begin_charge for H with vehicle_fault_open and accepts it for C;
--   (2) a pass of the service flow leaves H on need_service (STEP 0 would have relabelled it need_charge);
--   (3) the cockpit's charge queue lists C and not H; the decide tick gives the one charger to C, and no begin_charge to
--       H or K;
--   (4) the fault handler's step (6) puts K back on need_service, with a must-do fault_repair, the exception at
--       awaiting_repair, and its clock kept.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; car uuid[]; l2 uuid[]; ch uuid[]; h uuid; cc uuid; k uuid;
  va_h jsonb; va_c jsonb; qh int; qc int; sh text; kh int; kc int; v_by uuid;
  sk text; xk text; frk int; lsc_k timestamptz; lsc_k2 timestamptz; nr int; v_pass text;
BEGIN
  BEGIN
    SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.run_by = 'operator_demo' AND r.status NOT IN ('initializing', 'running', 'paused')
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0557 V3: no ended operator run at the twin depot'; END IF;
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t, tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);

    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 3) q;
    IF coalesce(array_length(car, 1), 0) < 3 THEN RAISE EXCEPTION '0557 V3: fewer than three free twin cars'; END IF;
    cc := car[1]; h := car[2]; k := car[3];
    SELECT array_agg(id ORDER BY stall_code), array_agg(charger_id ORDER BY stall_code) INTO l2, ch FROM (
      SELECT s.id, s.stall_code, s.ocpp_charger_id AS charger_id FROM public.stalls s
       WHERE s.depot_id = v_depot AND s.stall_type::text = 'l2' AND s.ocpp_charger_id IS NOT NULL
         AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id OR v.robotic_tether_stall_id = s.id)
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bk
                          WHERE bk.stall_id = s.id AND bk.state IN ('held', 'active')
                            AND bk.during && tstzrange(t - interval '1 day', t + interval '1 day'))
       ORDER BY s.stall_code LIMIT 1) x;
    IF coalesce(array_length(l2, 1), 0) < 1 THEN RAISE EXCEPTION '0557 V3: no free L2 stall'; END IF;

    -- only these three in play, staged at 50% with a charge to do; H and K with an open battery fault
    UPDATE public.vehicles SET current_state = 'offline'
     WHERE home_depot_id = v_depot AND NOT (id = ANY (car)) AND robotic_tether_until IS NULL AND current_state <> 'offline';
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', current_depot_id = v_depot, current_soc = 50, target_soc = 100,
           last_state_change = CASE WHEN id = h THEN t - interval '120 minutes' ELSE t - interval '10 minutes' END,
           config = (COALESCE(config, '{}'::jsonb) - 'charge_wait' - 'remedy_wait' - 'deploy_gate' - 'flagged_issue'
                     - 'flagged_issue_type' - 'service_ends_at' - 'exception' - 'bay_need')
                    || jsonb_build_object('svc_step', CASE WHEN id = h THEN 'need_service' ELSE 'need_charge' END)
                    || CASE WHEN id = cc THEN '{}'::jsonb
                            ELSE jsonb_build_object('exception', jsonb_build_object(
                                   'type', 'vehicle_fault', 'flagged_at', t - interval '150 minutes', 'status', 'awaiting_repair',
                                   'severity', 'critical', 'fault_class', 'hv_battery_thermal', 'immobilizing', true,
                                   'service_incompatible', true)) END
     WHERE id = ANY (car);
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, target_soc, atoms,
                                          status, source)
    SELECT x.vid, v_run, v_depot, t - interval '3 hours', 'V3-0557-' || x.vid::text, 'standard', 100,
           jsonb_build_array(jsonb_build_object('svc', 'charge', 'concurrency', 'anchor', 'must_do', true, 'status', 'pending'),
                             jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending')),
           'open', 'v3_0557'
      FROM unnest(car) AS x(vid);
    PERFORM ottoq.ottoq_add_fault_repair(v_run, v_depot, h, t);
    -- one free L2 charger; every other twin charger faulted. V3 calls the ticks alone, a day past the run's end, so it
    -- stamps the free charger's heartbeat itself (the world tick does, 0424), as 0551's V3 does.
    UPDATE public.ottoq_ocpp_chargers c2 SET station_state = 'Faulted'
      FROM public.stalls s
     WHERE s.ocpp_charger_id = c2.charger_id AND s.depot_id = v_depot AND s.stall_type::text IN ('dcfc', 'l2') AND s.id <> l2[1];
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = t + interval '10 minutes'
     WHERE charger_id = ch[1];

    -- (1) the emission gate
    va_h := ottoq.ottoq_validate_assignment(h, l2[1], 'begin_charge', t + interval '10 minutes', v_run);
    va_c := ottoq.ottoq_validate_assignment(cc, l2[1], 'begin_charge', t + interval '10 minutes', v_run);
    IF COALESCE((va_h->>'ok')::boolean, true) OR va_h->>'code' IS DISTINCT FROM 'vehicle_fault_open'
       OR NOT COALESCE((va_c->>'ok')::boolean, false) THEN
      RAISE EXCEPTION '0557 V3 FAILED (1): the emission gate read H % and C %', va_h, va_c;
    END IF;

    -- (2) a pass of the service flow at t + 10
    UPDATE public.ottoq_sim_runs SET sim_clock_current = t + interval '10 minutes', tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, t + interval '10 minutes', 30, v_depot);
    SELECT config->>'svc_step' INTO sh FROM public.vehicles WHERE id = h;
    IF sh IS DISTINCT FROM 'need_service' THEN
      RAISE EXCEPTION '0557 V3 FAILED (2): the service flow moved H (an open battery fault, at 50%%) to step %', sh;
    END IF;

    -- (3) the cockpit's charge queue, then the decide tick at t + 10
    SELECT count(*) FILTER (WHERE vehicle_id = h), count(*) FILTER (WHERE vehicle_id = cc) INTO qh, qc
      FROM public.ottoq_depot_queue(v_depot, v_run) WHERE queue_kind = 'charge';
    PERFORM public.ottoq_decide_tick(v_run);
    SELECT reserved_by INTO v_by FROM public.stalls WHERE id = l2[1];
    SELECT count(*) FILTER (WHERE vehicle_id IN (h, k)), count(*) FILTER (WHERE vehicle_id = cc) INTO kh, kc
      FROM public.ottoq_vehicle_commands
     WHERE sim_run_id = v_run AND issued_at = t + interval '10 minutes' AND command_type = 'begin_charge'
       AND vehicle_id IN (h, cc, k);
    IF qh <> 0 OR qc <> 1 OR kh <> 0 OR kc <> 1 OR v_by IS DISTINCT FROM cc THEN
      RAISE EXCEPTION '0557 V3 FAILED (3): the queue lists H % and C % times; begin_charge to H or K %, to C %; the charger is reserved by % (C is %)',
        qh, qc, kh, kc, v_by, cc;
    END IF;

    -- (4) step (6) of the fault handler takes K back to the service bay's line
    SELECT last_state_change INTO lsc_k FROM public.vehicles WHERE id = k;
    nr := ottoq.ottoq_route_faulted_cars_to_repair(v_run, v_depot, t + interval '10 minutes');
    SELECT config->>'svc_step', config->'exception'->>'status', last_state_change INTO sk, xk, lsc_k2 FROM public.vehicles WHERE id = k;
    SELECT count(*) INTO frk FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.vehicle_id = k AND n.sim_run_id = v_run AND n.status IN ('open', 'in_progress')
       AND a->>'svc' = 'fault_repair' AND (a->>'must_do')::boolean AND COALESCE(a->>'status', 'pending') = 'pending';
    IF nr < 1 OR sk IS DISTINCT FROM 'need_service' OR xk IS DISTINCT FROM 'awaiting_repair' OR frk <> 1
       OR lsc_k2 IS DISTINCT FROM lsc_k THEN
      RAISE EXCEPTION '0557 V3 FAILED (4): step (6) routed % and left K on % (exception %, % open fault_repair, clock % -> %)',
        nr, sk, xk, frk, lsc_k, lsc_k2;
    END IF;

    v_pass := format('0557 V3 PASSED on run %s: the emission gate refused begin_charge for H (open hv_battery_thermal) '
                     || 'with vehicle_fault_open and accepted it for C; the service flow left H on need_service; the '
                     || 'cockpit''s queue listed C and not H; the decide tick gave the one charger to C (H would have '
                     || 'ranked first) and no begin_charge to H or K; step (6) put K back on need_service with a must-do '
                     || 'fault_repair, its exception awaiting_repair and its clock kept', v_run);
    RAISE EXCEPTION '%', v_pass;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0557 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0557 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0557_pre' as it is (five splices, and
-- 0555's step (6) as it was).

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-28 to gxdrcyphqjzjsuhxuqtg, 5:00 PM CT (ledger 20260928220015).
--   public.ottoq_decide_tick                         2187f8565d4e8d33c646f8efb7316e2c -> 1595b2f51574023543dc1c6ed5c76aea
--   twin.ottoq_sim_advance_service_flow              0b852abe1944dd93f8e35c9d2f6967bd -> 1c90e987c63f44deab38f22d1986e743
--   ottoq.ottoq_validate_assignment                  d896e3b23991675840157f7357190ba5 -> 623d97cf801d1123b04160d3862a74b5
--   ottoq.ottoq_route_faulted_cars_to_repair         eb428364241f3d112ea59d4787b82e7c -> e04e790f6e4f843c6de1b08078f7b52e
--   ottoq.ottoq_plan_opportunistic_charges           7b010072f6f3b52f534aa4e6194e6afa -> a181dddde70d2a4d46c3f37d1cac752b
--   public.ottoq_depot_queue                         b1c77098b93d8ff19e209aa5811c48b6 -> b1988a81261ce4ba3295099e526df1cf
--   V1 and V3 passed: the transaction commits only if both do. A dry run (ROLLBACK in place of COMMIT) passed first and
--   left nothing behind. ottoq_cert_recert_floor() moved to 2026-09-28 22:00:15.710223+00; the sweep restarted.
