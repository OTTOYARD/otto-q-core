-- migration-version: PENDING
-- migration-name:    0845_a_car_that_owes_its_tire_job_does_not_leave_before_the_robot_has_done_it
--
-- 0845  **A car that owes the service bay's tire robot a job (a worn set, or a rotation that is due) does not leave the
--        depot until the job is done, and is seated for it, whether or not the job is on a visit.**
--
-- WHY. Read on 2026-11-18 against check 0498 §4(b), which left it unmeasured. public.ottoq_departure_clear (0543) is the
--   one departure test: section (2) of the decide tick, ottoq_plan_dispatch_tick, twin.ottoq_sim_dispatch_vehicle,
--   ottoq_v2_apply and the 0544 refusal trigger all read it. It asks whether any service on the car's OPEN VISIT is
--   unfinished, and never reads the needs card. A car on the depot when its run begins has no visit, so a tire job 0842
--   grades must-do lives on its card alone, and a charged car with a worn set was clear to leave. On both check runs the
--   worn car (Waymo-AV-038, 2.9 mm, staged for departure at 14:00:00) was held by its charge, 89% against a 100% target
--   (twin.departure_recheck, remedy need_charge, at 14:06:50 on 0dc17f83 and 14:04:21 on eb4e90ca), not by its tires. A
--   worn car that begins its run charged would have been released with them. Rule 9: no car leaves with a service still
--   needed. Saying no at the door is not enough by itself, and three more places were read before writing this:
--   (a) twin.ottoq_sim_departure_recheck sends a car staged to leave that is not clear back to what it needs, by what
--       its visit names. With nothing open on the visit its remedy is NULL and the car stays where it is. Section (4b),
--       the needs card's seat, takes cars only from staged_awaiting_service, so the car would have stood in staging,
--       refused at departure and never seated.
--   (b) twin.ottoq_sim_advance_service_flow's 0468 block rewrites need_service to need_deploy for a car with no
--       service-bay atom on its visit, no technician flag and no live service booking, and the deploy gate below it
--       releases a car whose visit is finished. With both service bays busy, a card-only tire job would have gone round
--       need_service, need_deploy, staged_for_departure and the recheck, every tick.
--   (c) section (5), service sequencing, admits a car whose step says need_service when a bay is free
--       (ottoq_l2_propose_service). Its command does not name a job the visit does not carry, and the bay exit credits
--       outstanding atoms, flags and the seat's own need (0458), so a seat from there would have credited nothing.
--
-- §1 WHAT THIS DOES.
--   public.ottoq_tire_job_owed(vehicle, clock): the needs card's own must-do rule for the two tire jobs, read from the
--     car's profile row: public.ottoq_tire_replacement_due (tread under 3.0 mm), or public.ottoq_service_urgency over
--     public.ottoq_tire_rotation_ratio at 'due' or worse. Unknown tread or last rotation is never owed, as on the card.
--   public.ottoq_departure_clear: and the car owes no tire job.
--   twin.ottoq_sim_departure_recheck: a remedy of need_service for a tire job owed, after every remedy its visit names.
--   twin.ottoq_sim_advance_service_flow (0468): a car that owes a tire job keeps need_service, as a flagged car does.
--   public.ottoq_decide_tick (5): passes over a car that owes a tire job its visit does not carry. (4b) seats it and
--     names the job, so the bay exit credits it and resets the tread or the rotation clock (0842).
--   A tire job on a visit (a car that came in through the gate) is unchanged: its visit already held the car.
--   Rules: nothing a car needs is skipped, and no car is released with a need open (9). No setting (10). Checked by the
--   probe below; the busy_day seed's worn car begins below its charge target, so a demo run on it does not reach this
--   path (12). No owner's car moves in any line (14).
--
-- §2 PRECONDITIONS AND CHECKS. P0 no certification in flight and no live run at the twin depot. P1 the four bodies (md5
--   of prosrc, as 0844 and earlier left them). P2 once. V1 each anchor matched once; each function is stored as patched,
--   and with its patch reversed is its snapshot. V2 a probe, rolled back, on the twin depot's newest finished run: car A
--   with a worn set (2.6 mm), car B with a rotation due (2,200 h since the last), car C with neither; all charged,
--   staged for departure, with no visit and nothing else owed. V2a before the patches, V2b after:
--     M1 departure_clear: A and B clear before (the defect), not after; C clear both times.
--     M2 the helper agrees with the needs card on every car at the depot that carries no open visit.
--     M3 the recheck: A and B left staged for departure before; sent to need_service after; C left as it was.
--     M4 the service flow, A waiting on need_service with no booking: released to staged_for_departure before (the
--        round trip of (b)); kept on need_service after.
--     M5 the decide tick, both service bays clear, A waiting on need_service: sent to a bay once, by the needs card, for
--        tire_replacement, its booking held for 12 minutes, both times.
--
-- §3 CLASSIFICATION. forces_recert TRUE: departures and service-bay seats change. forces_dial_restart FALSE.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0845_pre'; DROP FUNCTION
--   public.ottoq_tire_job_owed(uuid, timestamptz); DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0845_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0845 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') THEN
    RAISE EXCEPTION '0845 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_departure_clear(uuid,uuid,timestamptz,boolean)'))
     IS DISTINCT FROM 'd5e4d262f68870a3b8d72e113fe68d45' THEN
    RAISE EXCEPTION '0845 P1: public.ottoq_departure_clear is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('twin.ottoq_sim_departure_recheck(uuid,timestamptz,uuid)'))
     IS DISTINCT FROM '4060e9d844d293468748c3a2d04cdd8f' THEN
    RAISE EXCEPTION '0845 P1: twin.ottoq_sim_departure_recheck is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)'))
     IS DISTINCT FROM '47e96d6f76d8b6597b8474facfddc19b' THEN
    RAISE EXCEPTION '0845 P1: twin.ottoq_sim_advance_service_flow is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_decide_tick(uuid)'))
     IS DISTINCT FROM '17cedddda8c9c211346a1ba8eec6cc62' THEN
    RAISE EXCEPTION '0845 P1: public.ottoq_decide_tick is not the body this file was written against';
  END IF;
  IF to_regprocedure('public.ottoq_tire_job_owed(uuid,timestamptz)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0845_%') THEN
    RAISE EXCEPTION '0845 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0845_pre', 'function', split_part(f, '.', 1), f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_departure_clear(uuid,uuid,timestamptz,boolean)',
                    'twin.ottoq_sim_departure_recheck(uuid,timestamptz,uuid)',
                    'twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)',
                    'public.ottoq_decide_tick(uuid)']) AS f;

-- §1 the needs card's must-do rule for the two tire jobs, from the car's profile row
CREATE FUNCTION public.ottoq_tire_job_owed(p_vehicle_id uuid, p_clock timestamptz) RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $f$
  -- 0845 (CLAUDE.md rule 9): the car owes the service bay's tire robot a job, exactly where the needs card grades one
  -- must-do (0842): a worn set (tread under 3.0 mm), or a rotation whose time since the last one has reached the
  -- catalog's due ratio at p_clock. Unknown tread or an unknown last rotation is never owed, as the card grades them.
  SELECT COALESCE((
    SELECT public.ottoq_tire_replacement_due(p.tire_tread_mm)
        OR public.ottoq_service_urgency('tire_rotation',
             public.ottoq_tire_rotation_ratio(p.last_tire_rotation_at, p_clock)) IN ('due', 'overdue', 'critical')
      FROM public.vehicle_need_profile p
     WHERE p.vehicle_id = p_vehicle_id), false)
$f$;
COMMENT ON FUNCTION public.ottoq_tire_job_owed(uuid, timestamptz) IS
  '0845: the car owes the service bay''s tire robot a job (a worn set, or a rotation due), as the needs card grades '
  'it must-do. Read by ottoq_departure_clear, the departure recheck, the service flow''s need gate and the decide tick.';
GRANT EXECUTE ON FUNCTION public.ottoq_tire_job_owed(uuid, timestamptz) TO authenticated;

CREATE TEMP TABLE _0845_patch (fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0845_patch VALUES
('public.ottoq_departure_clear(uuid,uuid,timestamptz,boolean)',
$o$AND NOT public.ottoq_owner_departure_blocked(v.id, p_sim_run_id, p_clock)$o$,
$n$AND NOT public.ottoq_owner_departure_blocked(v.id, p_sim_run_id, p_clock)
     -- 0845 (rule 9): and it owes the service bay's tire robot no job, a worn set or a rotation that is due, as the
     -- needs card grades them must-do. A car on the depot when its run began has no visit, so its tire job is on its
     -- card alone, and this test read only the visit: a charged car with a worn set was clear to leave.
     AND NOT public.ottoq_tire_job_owed(v.id, p_clock)$n$),
('twin.ottoq_sim_departure_recheck(uuid,timestamptz,uuid)',
$o$ELSE NULL END;
    CONTINUE WHEN v_remedy IS NULL;$o$,
$n$-- 0845 (rule 9): a tire job owed that no visit carries, only the needs card. The card's seat, section (4b)
                  -- of the decide tick, takes a car only from staged_awaiting_service: without this the car stood
                  -- here, refused at departure and never seated.
                  WHEN public.ottoq_tire_job_owed(v_rec.id, p_sim_clock_now)        THEN 'need_service'
                  ELSE NULL END;
    CONTINUE WHEN v_remedy IS NULL;$n$),
('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)',
$o$AND NOT public.ottoq_flag_needs_service(v.config)   -- 0556 (G289): but not the readiness gate's own flag$o$,
$n$AND NOT public.ottoq_flag_needs_service(v.config)   -- 0556 (G289): but not the readiness gate's own flag
     -- 0845 (rule 9): nor a car that owes a tire job (0842), which may be on its needs card alone. It waits here for
     -- the needs card's seat, as a flagged car does. On need_deploy the gate below released it with the job open, and
     -- the departure recheck sent it back, every tick the service bays were busy.
     AND NOT public.ottoq_tire_job_owed(v.id, p_sim_clock_now)$n$),
('public.ottoq_decide_tick(uuid)',
$o$                          AND vc.issued_at = v_clock AND vc.status = 'issued' AND vc.payload ? 'stall_id')
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40$o$,
$n$                          AND vc.issued_at = v_clock AND vc.status = 'issued' AND vc.payload ? 'stall_id')
       -- 0845: nor a car that owes a tire job its visit does not carry (it is on the needs card alone: a car on the depot
       -- when its run began has no visit). (4b) above seats it and names the job. Admitted here, its command named no
       -- job the visit carries, and the bay exit would have credited nothing. It is seen again once the job is done.
       AND NOT (public.ottoq_tire_job_owed(v.id, v_clock)
                AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs n2, jsonb_array_elements(n2.atoms) a2
                                 WHERE n2.vehicle_id = v.id AND n2.status IN ('open','in_progress')
                                   AND COALESCE(n2.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                     = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                   AND a2->>'svc' IN ('tire_replacement','tire_rotation')
                                   AND COALESCE(a2->>'status','pending') NOT IN ('done','cancelled','skipped')))
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40$n$);

-- V2: the probe. It raises to roll its writes back; the answer comes back as the exception's detail.
CREATE FUNCTION pg_temp._0845_probe(p_mode text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_cars uuid[]; v_a uuid; v_b uuid; v_c uuid; v_r jsonb := '{}'::jsonb; v_detail text;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot AND r.status IN ('completed', 'stopped')
   ORDER BY r.started_at DESC LIMIT 1;
  SELECT array_agg(s.id ORDER BY s.id) INTO v_cars FROM (
    SELECT v.id FROM public.vehicles v
     WHERE v.home_depot_id = c_depot AND v.category = 'autonomous' AND v.is_active ORDER BY v.id LIMIT 3) s;
  v_a := v_cars[1]; v_b := v_cars[2]; v_c := v_cars[3];
  IF v_run IS NULL OR v_c IS NULL THEN RAISE EXCEPTION '0845 V2: no run or cars to probe with'; END IF;
  BEGIN
    -- the three cars: nothing owed but the tire job under test, charged, staged to leave, no visit, no booking
    UPDATE public.vehicle_need_profile
       SET tire_tread_mm = CASE WHEN vehicle_id = v_a THEN 2.6 ELSE 6.0 END,
           last_tire_rotation_at = CASE WHEN vehicle_id = v_b THEN v_clock - interval '2200 hours'
                                        ELSE v_clock - interval '10 days' END,
           km_at_last_pm = odometer_km, brake_wear_pct = 10, last_calibration_at = v_clock, sensor_health_pct = 99,
           worst_fault_severity = 99, open_fault_codes = '{}'::text[], exterior_soil_level = 0, cabin_condition = 'clean',
           last_wash_at = v_clock, last_deep_clean_at = v_clock, software_version = sw_target_version,
           item_retrieval_pending = false
     WHERE vehicle_id = ANY (v_cars);
    UPDATE public.ottoq_vehicle_wear SET km_at_last_pm = drive_km_total, hours_at_last_calibration = drive_hours_total
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run;
    UPDATE public.ottoq_visit_needs SET status = 'complete' WHERE vehicle_id = ANY (v_cars) AND status IN ('open', 'in_progress');
    UPDATE public.ottoq_stall_bookings SET state = 'released'
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run AND state IN ('held', 'active', 'interrupted');
    UPDATE public.vehicles
       SET current_soc = 100, current_state = 'staged_for_departure', last_state_change = v_clock - interval '30 days',
           config = (COALESCE(config, '{}'::jsonb) - 'exception' - 'deploy_gate' - 'departure_hold' - 'flagged_issue'
                     - 'flagged_issue_type' - 'bay_need' - 'service_ends_at') || '{"svc_step": "ready"}'::jsonb
     WHERE id = ANY (v_cars);

    IF p_mode = 'flow' THEN
    -- M1 the departure test; M2 the helper against the needs card
    v_r := v_r || jsonb_build_object('m1', jsonb_build_object(
             'a', public.ottoq_departure_clear(v_a, v_run, v_clock, true),
             'b', public.ottoq_departure_clear(v_b, v_run, v_clock, true),
             'c', public.ottoq_departure_clear(v_c, v_run, v_clock, true)));
    v_r := v_r || jsonb_build_object('m2', (
      SELECT jsonb_build_object(
               'cars', count(*),
               'owed', count(*) FILTER (WHERE public.ottoq_tire_job_owed(c.vehicle_id, c.sim_clock)),
               'disagree', count(*) FILTER (WHERE public.ottoq_tire_job_owed(c.vehicle_id, c.sim_clock)
                             IS DISTINCT FROM (COALESCE(c.must_do_now, '{}'::text[]) && ARRAY['tire_replacement', 'tire_rotation'])),
               'disagreeing', COALESCE(jsonb_agg(jsonb_build_object('car', c.vehicle_id, 'must', c.must_do_now))
                                FILTER (WHERE public.ottoq_tire_job_owed(c.vehicle_id, c.sim_clock)
                                  IS DISTINCT FROM (COALESCE(c.must_do_now, '{}'::text[]) && ARRAY['tire_replacement', 'tire_rotation'])), '[]'::jsonb),
               'abc', jsonb_agg(jsonb_build_object('car', c.vehicle_id, 'must', c.must_do_now)) FILTER (WHERE c.vehicle_id = ANY (v_cars)))
        FROM public.ottoq_vehicle_needs_card c
       WHERE c.depot_id = c_depot
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn
                          WHERE vn.vehicle_id = c.vehicle_id AND vn.status IN ('open', 'in_progress'))));

    -- M3 the departure recheck
    PERFORM twin.ottoq_sim_departure_recheck(v_run, v_clock, c_depot);
    v_r := v_r || jsonb_build_object('m3', (
      SELECT jsonb_object_agg(CASE WHEN id = v_a THEN 'a' WHEN id = v_b THEN 'b' ELSE 'c' END,
                              current_state::text || '/' || COALESCE(config ->> 'svc_step', ''))
        FROM public.vehicles WHERE id = ANY (v_cars)));

    -- M4 the service flow, A waiting on need_service with no booking
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', last_state_change = v_clock - interval '30 days',
           config = jsonb_set(config - 'departure_hold' - 'deploy_gate', '{svc_step}', '"need_service"'::jsonb)
     WHERE id = v_a;
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, v_clock, 30, c_depot);
    v_r := v_r || jsonb_build_object('m4', (
      SELECT current_state::text || '/' || COALESCE(config ->> 'svc_step', '') FROM public.vehicles WHERE id = v_a));

    ELSE
    -- M5 the decide tick, both service bays clear, A waiting on need_service (its own pass: the service flow above
    -- moves other cars, and a car it seats takes a service technician from the needs card's headroom)
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, status = 'available'
     WHERE depot_id = c_depot AND stall_type::text = 'service_bay';
    UPDATE public.ottoq_stall_bookings b SET state = 'released'
      FROM public.stalls s WHERE s.id = b.stall_id AND s.depot_id = c_depot AND s.stall_type::text = 'service_bay'
       AND b.state IN ('held', 'active') AND b.during && tstzrange(v_clock - interval '2 hours', v_clock + interval '4 hours');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', last_state_change = v_clock - interval '5 minutes',
           config = jsonb_set(config - 'deploy_gate', '{svc_step}', '"need_service"'::jsonb)
     WHERE id = v_a;
    v_r := v_r || jsonb_build_object('tick', (SELECT to_jsonb(t) FROM public.ottoq_decide_tick(v_run) t));
    v_r := v_r || jsonb_build_object('m5', jsonb_build_object(
      'sent', (SELECT COALESCE(jsonb_agg(c.payload ->> 'need'), '[]'::jsonb) FROM public.ottoq_vehicle_commands c
                WHERE c.vehicle_id = v_a AND c.sim_run_id = v_run AND c.issued_at = v_clock AND c.payload ? 'stall_id'
                  AND c.command_type = 'enter_service'),
      'booking', (SELECT jsonb_build_object('state', b.state, 'src', to_jsonb(b) ->> 'source',
                                 'seconds', round(EXTRACT(EPOCH FROM (upper(b.during) - lower(b.during)))))
                    FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
                   WHERE b.vehicle_id = v_a AND b.sim_run_id = v_run AND s.stall_type::text = 'service_bay'
                     AND lower(b.during) = v_clock
                   ORDER BY b.booked_at DESC NULLS LAST LIMIT 1),
      'after', (SELECT jsonb_object_agg(CASE WHEN id = v_a THEN 'a' WHEN id = v_b THEN 'b' ELSE 'c' END,
                                        current_state::text || '/' || COALESCE(config ->> 'svc_step', ''))
                  FROM public.vehicles WHERE id = ANY (v_cars))));
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OQ845', MESSAGE = '0845 V2 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ845' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

CREATE TEMP TABLE _0845_out (phase text, r jsonb) ON COMMIT DROP;

DO $v2a$
DECLARE v_r jsonb := pg_temp._0845_probe('flow') || pg_temp._0845_probe('tick');
BEGIN
  INSERT INTO _0845_out VALUES ('before', v_r);
  IF (v_r #>> '{m1,a}') IS DISTINCT FROM 'true' OR (v_r #>> '{m1,b}') IS DISTINCT FROM 'true'
     OR (v_r #>> '{m1,c}') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0845 V2a: the departure test did not clear the three cars as it was: %', v_r;
  END IF;
  IF COALESCE((v_r #>> '{m2,disagree}')::int, -1) <> 0 OR COALESCE((v_r #>> '{m2,owed}')::int, 0) < 2 THEN
    RAISE EXCEPTION '0845 V2a: the helper does not agree with the needs card: %', v_r;
  END IF;
  IF (v_r #>> '{m3,a}') IS DISTINCT FROM 'staged_for_departure/ready' OR (v_r #>> '{m3,b}') IS DISTINCT FROM 'staged_for_departure/ready' THEN
    RAISE EXCEPTION '0845 V2a: the recheck moved a car it had cleared: %', v_r;
  END IF;
  IF (v_r ->> 'm4') IS DISTINCT FROM 'staged_for_departure/ready' THEN
    RAISE EXCEPTION '0845 V2a: the service flow did not release the waiting car as it was: %', v_r;
  END IF;
  IF COALESCE((v_r #>> '{tick,errored}')::int, -1) <> 0 OR (v_r #> '{m5,sent}') IS DISTINCT FROM '["tire_replacement"]'::jsonb THEN
    RAISE EXCEPTION '0845 V2a: the needs card did not seat the waiting car for its tire job as it was: %', v_r;
  END IF;
  RAISE NOTICE '0845 V2a (before): %', v_r;
END $v2a$;

DO $patch$
DECLARE p record; v_def text; v_old text; n int;
BEGIN
  FOR p IN SELECT * FROM _0845_patch LOOP
    v_old := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_old) - length(replace(v_old, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0845 V1: the anchor in % matches % times, not 1', p.fn, n; END IF;
    v_def := replace(v_old, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0845 V1: % is not stored as patched', p.fn;
    END IF;
    IF md5(replace(v_def, p.c_new, p.c_old)) IS DISTINCT FROM
       (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0845_pre' AND object_name = p.fn
         ORDER BY snapshot_id DESC LIMIT 1) THEN
      RAISE EXCEPTION '0845 V1: % with its patch reversed is not its snapshot', p.fn;
    END IF;
  END LOOP;
END $patch$;

DO $v2b$
DECLARE v_r jsonb := pg_temp._0845_probe('flow') || pg_temp._0845_probe('tick');
BEGIN
  INSERT INTO _0845_out VALUES ('after', v_r);
  IF (v_r #>> '{m1,a}') IS DISTINCT FROM 'false' OR (v_r #>> '{m1,b}') IS DISTINCT FROM 'false'
     OR (v_r #>> '{m1,c}') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0845 V2b M1: A and B are not held at departure, or C is: %', v_r;
  END IF;
  IF COALESCE((v_r #>> '{m2,disagree}')::int, -1) <> 0 THEN
    RAISE EXCEPTION '0845 V2b M2: the helper does not agree with the needs card: %', v_r;
  END IF;
  IF (v_r #>> '{m3,a}') IS DISTINCT FROM 'staged_awaiting_service/need_service'
     OR (v_r #>> '{m3,b}') IS DISTINCT FROM 'staged_awaiting_service/need_service'
     OR (v_r #>> '{m3,c}') IS DISTINCT FROM 'staged_for_departure/ready' THEN
    RAISE EXCEPTION '0845 V2b M3: the recheck did not send A and B to the service bay and leave C: %', v_r;
  END IF;
  IF (v_r ->> 'm4') IS DISTINCT FROM 'staged_awaiting_service/need_service' THEN
    RAISE EXCEPTION '0845 V2b M4: the service flow did not keep the waiting car on need_service: %', v_r;
  END IF;
  IF COALESCE((v_r #>> '{tick,errored}')::int, -1) <> 0 OR (v_r #> '{m5,sent}') IS DISTINCT FROM '["tire_replacement"]'::jsonb
     OR (v_r #>> '{m5,booking,state}') IS DISTINCT FROM 'held'
     OR COALESCE((v_r #>> '{m5,booking,seconds}')::numeric, 0) <> 720 THEN
    RAISE EXCEPTION '0845 V2b M5: the car was not sent once, for its tire job, with its 12-minute booking held: %', v_r;
  END IF;
  RAISE NOTICE '0845 V2b (after): %', v_r;
END $v2b$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0845_a_car_that_owes_its_tire_job_does_not_leave_before_the_robot_has_done_it', true, false,
        'A car that owes the tire robot a job (worn set, or rotation due) is not departure-clear, the recheck sends it '
        || 'to need_service, the service flow keeps it there and the decide tick leaves it to the needs card''s seat. '
        || 'Before, a car with no visit carried its tire job on its card alone and the departure test read only the '
        || 'visit. New helper public.ottoq_tire_job_owed. Pre-image 0845_pre.', now());
COMMIT;
