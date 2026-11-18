-- migration-version: PENDING
-- migration-name:    0846_a_service_bay_seat_says_why_the_car_is_there_and_its_booking_names_the_work
--
-- 0846  **A car seated in a service bay says why it is there: the snapshot's seat carries the needs card's reason for
--        each piece of its work, in plain words, and the needs card's booking names the service it is for.**
--
-- WHY. Chase, on run 52dfc2d3 (9:25 PM CT, 2026-11-17): "Tire/service bays still not working/functioning with vehicles
--   parked in there. Vehicle Q card has no reasoning why it is in there." At 8:16 AM sim both service bays held cars the
--   needs card had seated at 8:03 for 40 minutes: Tesla-AV-046 for fault_repair (open faults P0AA6 and U0100, the worst at
--   severity 1) and Waymo-AV-019 for sensor_calibration (11 days since its last, past its interval). Both were on the
--   depot when the run began, so neither had a visit. What the engine published about them:
--   - the snapshot's bay_seat named the work (0843) and said nothing of why;
--   - ottoq_depot_cards listed no needs and no steps for them;
--   - the seat's own booking read "to satisfy need 'service_due' (inferred_from_purpose); NO itinerary leg exists at
--     enactment". ottoq.ottoq_booking_why looks for the need on the car's open visit, finds none, and infers it from the
--     purpose. The needs card had chosen the seat for one service (v_need.svc in section (4b) of the decide tick) and
--     never passed it on, so the booking's need_atom stayed NULL.
--   The twin's Q card now draws the seat (ottoyarddepot-sim #181) and reads the reason this file publishes.
--
-- §1 WHAT THIS DOES. All of it reads; none of it changes a decision.
--   public.ottoq_service_reason(vehicle, svc, clock): why the needs card asks for a service-bay job, from the inputs and
--     lines it grades on (ottoq_vehicle_needs_card): open fault codes and the worst severity; days since the last
--     calibration against the car's interval, or sensor health under 89%; km since the last maintenance against its
--     interval, or brake wear at 80% or more; tread under 3.0 mm; days since the last rotation against the quarter, or a
--     rotation riding along (0842's 14 days); a reported body repair. NULL when it has nothing to say.
--   public.ottoq_service_reasons(vehicle, work[], clock): those reasons as {svc: words}, NULL when none.
--   public.ottoq_span_words(hours): '11 days', or '36 hours' under two days.
--   public.ottoq_twin_snapshot: bay_seat gains `why`, the reasons for the seat's work (0843's `work`).
--   public.ottoq_decide_tick (4b): a service seat's booking gets need_atom = the service, and its why names the service
--     and the reason where it said 'service_due'. A booking that already names its need is left as it is.
--   Rules: nothing a car needs changes, no decision reads the new text (9). No setting (10). One demo run (12).
--
-- §2 PRECONDITIONS AND CHECKS. P0 no certification in flight and no run at the twin depot running, paused or pending.
--   P1 the two bodies (md5 of prosrc). P2 once. V1 each anchor matched once; each function stored as patched and, with
--   its patch reversed, its snapshot. V2 a probe, rolled back, on the twin depot's newest finished run:
--     snap: car A seated for fault_repair with open faults P0AA6 and U0100 at severity 1; car B for sensor_calibration,
--       266 h since its last against a 250 h interval; car C for tire_rotation, 2,200 h since its last. Before: no `why`
--       on any seat. After: each seat's `why` gives its reason. And every service-bay must-do on any car's needs card at
--       the depot has a reason.
--     tick: car D, on the depot with no visit and an open fault at severity 1, waiting on need_service, both service bays
--       clear. Before: the needs card's booking has no need_atom and reads 'service_due'. After: need_atom fault_repair,
--       and the why names the service and the faults.
--
-- §3 CLASSIFICATION. forces_recert FALSE: no decision changes. The booking's need_atom and why, and the snapshot, are
--   recorded text; no atom digests a booking's why, and need_atom is read only to describe or to probe a rule.
--   forces_dial_restart FALSE.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0846_pre'; DROP FUNCTION
--   public.ottoq_service_reasons(uuid, text[], timestamptz), public.ottoq_service_reason(uuid, text, timestamptz),
--   public.ottoq_span_words(numeric); DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0846_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0846 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                                                   AND status IN ('running', 'paused', 'pending')) THEN
    RAISE EXCEPTION '0846 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_twin_snapshot(uuid)'))
     IS DISTINCT FROM '91068abd372bb7c7e397dadcae8c9cd5' THEN
    RAISE EXCEPTION '0846 P1: public.ottoq_twin_snapshot is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_decide_tick(uuid)'))
     IS DISTINCT FROM 'f031133a812fb6e5852bd971dd93e46f' THEN
    RAISE EXCEPTION '0846 P1: public.ottoq_decide_tick is not the body this file was written against';
  END IF;
  IF to_regprocedure('public.ottoq_service_reason(uuid,text,timestamptz)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0846_%') THEN
    RAISE EXCEPTION '0846 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0846_pre', 'function', split_part(f, '.', 1), f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_twin_snapshot(uuid)', 'public.ottoq_decide_tick(uuid)']) AS f;

-- §1 the words
CREATE FUNCTION public.ottoq_span_words(p_hours numeric) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public AS $f$
  -- 0846: a span of hours in words: '11 days', or '36 hours' under two days. NULL for NULL.
  SELECT CASE WHEN p_hours IS NULL THEN NULL
              WHEN abs(p_hours) >= 48 THEN round(p_hours / 24.0)::int || ' days'
              WHEN round(p_hours)::int = 1 THEN '1 hour'
              ELSE round(p_hours)::int || ' hours' END
$f$;

CREATE FUNCTION public.ottoq_service_reason(p_vehicle_id uuid, p_svc text, p_clock timestamptz) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public AS $f$
-- 0846: why the needs card asks for a service-bay job, in plain words, from the inputs and lines it grades on
-- (public.ottoq_vehicle_needs_card). Several reasons are joined with '; '. NULL when it has nothing to say.
DECLARE
  p public.vehicle_need_profile%ROWTYPE;
  v_parts text[] := '{}';
  v_h numeric; v_n int; v_cfg jsonb; v_km numeric; v_ratio numeric; v_codes text;
BEGIN
  SELECT * INTO p FROM public.vehicle_need_profile WHERE vehicle_id = p_vehicle_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF p_svc = 'fault_repair' THEN
    v_n := COALESCE(array_length(p.open_fault_codes, 1), 0);
    IF v_n > 0 THEN
      v_codes := CASE WHEN v_n = 1 THEN p.open_fault_codes[1]
                      ELSE array_to_string(p.open_fault_codes[1:v_n - 1], ', ') || ' and ' || p.open_fault_codes[v_n] END;
      v_parts := v_parts || format('%s %s%s', CASE WHEN v_n = 1 THEN 'open fault' ELSE 'open faults' END, v_codes,
                                   CASE WHEN p.worst_fault_severity BETWEEN 1 AND 5
                                        THEN format(', the worst at severity %s, where 1 is the most severe', p.worst_fault_severity)
                                        ELSE '' END);
    END IF;
    SELECT v.config INTO v_cfg FROM public.vehicles v WHERE v.id = p_vehicle_id;
    IF COALESCE(public.ottoq_vehicle_fault_open(v_cfg), false) THEN
      v_parts := v_parts || 'a vehicle fault is reported open'::text;
    END IF;
  ELSIF p_svc = 'sensor_calibration' THEN
    IF p.last_calibration_at IS NOT NULL AND COALESCE(p.calib_interval_h, 0) > 0 AND p_clock IS NOT NULL THEN
      v_h := EXTRACT(EPOCH FROM (p_clock - p.last_calibration_at)) / 3600.0;
      IF public.ottoq_service_urgency('sensor_calibration', round(v_h / p.calib_interval_h, 3)) IN ('due', 'overdue', 'critical') THEN
        v_parts := v_parts || format('%s since its last calibration, due every %s',
                                     public.ottoq_span_words(v_h), public.ottoq_span_words(p.calib_interval_h));
      END IF;
    END IF;
    IF p.sensor_health_pct < 89 THEN
      v_parts := v_parts || format('sensor health %s%%, under the 89%% line', round(p.sensor_health_pct, 1));
    END IF;
  ELSIF p_svc = 'mechanical_pm' THEN
    IF COALESCE(p.pm_interval_km, 0) > 0 AND p.odometer_km IS NOT NULL THEN
      v_km := GREATEST(0, p.odometer_km - COALESCE(p.km_at_last_pm, 0));
      IF public.ottoq_service_urgency('mechanical_pm', round(v_km / p.pm_interval_km, 3)) IN ('due', 'overdue', 'critical') THEN
        v_parts := v_parts || format('%s km since its last maintenance, due every %s km', round(v_km), round(p.pm_interval_km));
      END IF;
    END IF;
    IF p.brake_wear_pct >= 80 THEN
      v_parts := v_parts || format('brake wear %s%%, at or over the 80%% line', round(p.brake_wear_pct));
    END IF;
  ELSIF p_svc = 'tire_replacement' THEN
    IF public.ottoq_tire_replacement_due(p.tire_tread_mm) THEN
      v_parts := v_parts || format('tread %s mm, under the 3.0 mm line', p.tire_tread_mm);
    END IF;
  ELSIF p_svc = 'tire_rotation' THEN
    v_ratio := public.ottoq_tire_rotation_ratio(p.last_tire_rotation_at, p_clock);
    IF v_ratio IS NOT NULL THEN
      v_h := EXTRACT(EPOCH FROM (p_clock - p.last_tire_rotation_at)) / 3600.0;
      v_parts := v_parts || CASE
        WHEN public.ottoq_service_urgency('tire_rotation', v_ratio) IN ('due', 'overdue', 'critical')
          THEN format('%s since its last rotation, due every %s',
                      public.ottoq_span_words(v_h), public.ottoq_span_words(public.ottoq_tire_rotation_interval_h()))
        ELSE format('due in %s, done now while the car is in the bay for its other work',
                    public.ottoq_span_words(public.ottoq_tire_rotation_interval_h() - v_h)) END;
    END IF;
  ELSIF p_svc = 'cosmetic_repair' THEN
    v_parts := v_parts || 'body damage was reported'::text;
  END IF;
  RETURN NULLIF(array_to_string(v_parts, '; '), '');
END $f$;

CREATE FUNCTION public.ottoq_service_reasons(p_vehicle_id uuid, p_work text[], p_clock timestamptz) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $f$
  -- 0846: the reason for each service of a seat's work, as {svc: words}; NULL when none has one
  SELECT jsonb_object_agg(x.w, x.r)
    FROM (SELECT w, public.ottoq_service_reason(p_vehicle_id, w, p_clock) AS r FROM unnest(p_work) AS w) x
   WHERE x.r IS NOT NULL
$f$;

COMMENT ON FUNCTION public.ottoq_service_reason(uuid, text, timestamptz) IS
  '0846: why the needs card asks for a service-bay job, in plain words, from the inputs and lines it grades on. Read by '
  'the twin snapshot''s bay_seat.why and the needs card''s booking. Changes no decision.';
GRANT EXECUTE ON FUNCTION public.ottoq_span_words(numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_service_reason(uuid, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_service_reasons(uuid, text[], timestamptz) TO authenticated;

CREATE TEMP TABLE _0846_patch (fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0846_patch VALUES
('public.ottoq_twin_snapshot(uuid)',
$o$                                  'work', to_jsonb(public.ottoq_bay_seat_work(v.id, v.current_state::text,
                                                                              v_run.sim_run_id, v.config)))$o$,
$n$                                  'work', to_jsonb(public.ottoq_bay_seat_work(v.id, v.current_state::text,
                                                                              v_run.sim_run_id, v.config)),
                                  -- 0846: why OTTO-Q seated it, for each service of that work, in plain words (the
                                  -- needs card's own lines), so the car's card can say why it is in the bay
                                  'why', public.ottoq_service_reasons(v.id,
                                           public.ottoq_bay_seat_work(v.id, v.current_state::text, v_run.sim_run_id, v.config),
                                           v_clock))$n$),
('public.ottoq_decide_tick(uuid)',
$o$-- 0039: bay entry handled by twin on command confirmation below
            IF v_need.stall_type = 'wash_bay' THEN$o$,
$n$-- 0039: bay entry handled by twin on command confirmation below
            -- 0846: the seat names the work it is for. ottoq_booking_why reads the need from the car's open visit; a car
            -- on the depot when its run began has none, so a service seat read "need 'service_due'
            -- (inferred_from_purpose)" while this block had chosen it for one service. Record that service, and why.
            IF v_need.purpose = 'service' AND (v_space->>'booking_id') IS NOT NULL THEN
              UPDATE public.ottoq_stall_bookings b
                 SET need_atom = v_need.svc,
                     why = replace(b.why, 'need ''service_due'' (inferred_from_purpose)',
                                   format('need %L (needs card: %s)', v_need.svc,
                                          COALESCE(public.ottoq_service_reason(v_need.vehicle_id, v_need.svc, v_clock),
                                                   'must-do now')))
               WHERE b.booking_id = (v_space->>'booking_id')::uuid AND b.need_atom IS NULL;
            END IF;
            IF v_need.stall_type = 'wash_bay' THEN$n$);

-- V2: the probe. It raises to roll its writes back; the answer comes back as the exception's detail.
CREATE FUNCTION pg_temp._0846_probe(p_mode text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_cars uuid[]; v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_snap jsonb;
  v_r jsonb := '{}'::jsonb; v_detail text;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot AND r.status IN ('completed', 'stopped')
   ORDER BY r.started_at DESC LIMIT 1;
  SELECT array_agg(s.id ORDER BY s.id) INTO v_cars FROM (
    SELECT v.id FROM public.vehicles v
     WHERE v.home_depot_id = c_depot AND v.category = 'autonomous' AND v.is_active ORDER BY v.id LIMIT 4) s;
  v_a := v_cars[1]; v_b := v_cars[2]; v_c := v_cars[3]; v_d := v_cars[4];
  IF v_run IS NULL OR v_d IS NULL THEN RAISE EXCEPTION '0846 V2: no run or cars to probe with'; END IF;
  BEGIN
    -- the four cars: nothing owed but what is set below, no visit, no booking
    UPDATE public.vehicle_need_profile
       SET open_fault_codes = CASE WHEN vehicle_id IN (v_a, v_d) THEN ARRAY['P0AA6', 'U0100'] ELSE '{}'::text[] END,
           worst_fault_severity = CASE WHEN vehicle_id IN (v_a, v_d) THEN 1 ELSE 99 END,
           last_calibration_at = CASE WHEN vehicle_id = v_b THEN v_clock - interval '266 hours' ELSE v_clock END,
           calib_interval_h = CASE WHEN vehicle_id = v_b THEN 250 ELSE calib_interval_h END,
           sensor_health_pct = CASE WHEN vehicle_id = v_b THEN 93 ELSE 99 END,
           last_tire_rotation_at = CASE WHEN vehicle_id = v_c THEN v_clock - interval '2200 hours' ELSE v_clock - interval '10 days' END,
           tire_tread_mm = 6.0, km_at_last_pm = odometer_km, brake_wear_pct = 10, exterior_soil_level = 0, cabin_condition = 'clean',
           last_wash_at = v_clock, last_deep_clean_at = v_clock, software_version = sw_target_version, item_retrieval_pending = false
     WHERE vehicle_id = ANY (v_cars);
    UPDATE public.ottoq_vehicle_wear SET km_at_last_pm = drive_km_total, hours_at_last_calibration = drive_hours_total
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run;
    UPDATE public.ottoq_visit_needs SET status = 'complete' WHERE vehicle_id = ANY (v_cars) AND status IN ('open', 'in_progress');
    UPDATE public.ottoq_stall_bookings SET state = 'released'
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run AND state IN ('held', 'active', 'interrupted');
    UPDATE public.vehicles SET current_soc = 100, config = COALESCE(config, '{}'::jsonb) - 'exception' - 'deploy_gate'
     WHERE id = ANY (v_cars);

    IF p_mode = 'snap' THEN
      UPDATE public.vehicles v
         SET current_state = 'in_service_bay', last_state_change = v_clock,
             config = COALESCE(v.config, '{}'::jsonb)
                      || jsonb_build_object('service_ends_at', (v_clock + interval '40 minutes')::text,
                                            'bay_need', jsonb_build_object(
                                              'svc', CASE v.id WHEN v_a THEN 'fault_repair' WHEN v_b THEN 'sensor_calibration'
                                                               ELSE 'tire_rotation' END,
                                              'ends_at', (v_clock + interval '40 minutes')::text))
       WHERE v.id IN (v_a, v_b, v_c);
      v_snap := public.ottoq_twin_snapshot(v_run);
      v_r := jsonb_build_object(
        'a', (SELECT x -> 'bay_seat' FROM jsonb_array_elements(v_snap #> '{fleet,vehicles}') x WHERE (x ->> 'id')::uuid = v_a),
        'b', (SELECT x -> 'bay_seat' FROM jsonb_array_elements(v_snap #> '{fleet,vehicles}') x WHERE (x ->> 'id')::uuid = v_b),
        'c', (SELECT x -> 'bay_seat' FROM jsonb_array_elements(v_snap #> '{fleet,vehicles}') x WHERE (x ->> 'id')::uuid = v_c),
        'must_do', (SELECT jsonb_build_object('total', count(*),
                                              'missing', count(*) FILTER (WHERE public.ottoq_service_reason(c.vehicle_id, s.svc, c.sim_clock) IS NULL),
                                              'missing_list', COALESCE(jsonb_agg(jsonb_build_object('car', c.vehicle_id, 'svc', s.svc))
                                                FILTER (WHERE public.ottoq_service_reason(c.vehicle_id, s.svc, c.sim_clock) IS NULL), '[]'::jsonb))
                      FROM public.ottoq_vehicle_needs_card c
                      CROSS JOIN LATERAL unnest(COALESCE(c.must_do_now, '{}'::text[])) AS s(svc)
                     WHERE c.depot_id = c_depot
                       AND s.svc IN ('fault_repair', 'sensor_calibration', 'mechanical_pm', 'tire_replacement', 'tire_rotation')
                       AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn
                                        WHERE vn.vehicle_id = c.vehicle_id AND vn.status IN ('open', 'in_progress'))));
    ELSE
      -- D waits on need_service with an open fault at severity 1; both service bays clear
      UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, status = 'available'
       WHERE depot_id = c_depot AND stall_type::text = 'service_bay';
      UPDATE public.ottoq_stall_bookings b SET state = 'released'
        FROM public.stalls s WHERE s.id = b.stall_id AND s.depot_id = c_depot AND s.stall_type::text = 'service_bay'
         AND b.state IN ('held', 'active') AND b.during && tstzrange(v_clock - interval '2 hours', v_clock + interval '4 hours');
      UPDATE public.vehicles
         SET current_state = 'staged_awaiting_service', last_state_change = v_clock - interval '5 minutes',
             config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', '"need_service"'::jsonb)
       WHERE id = v_d;
      v_r := v_r || jsonb_build_object('tick', (SELECT to_jsonb(t) FROM public.ottoq_decide_tick(v_run) t));
      v_r := v_r || jsonb_build_object('d', (
        SELECT jsonb_build_object('need_atom', b.need_atom, 'why', b.why, 'src', to_jsonb(b) ->> 'source')
          FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
         WHERE b.vehicle_id = v_d AND b.sim_run_id = v_run AND s.stall_type::text = 'service_bay' AND lower(b.during) = v_clock
         ORDER BY b.booked_at DESC NULLS LAST LIMIT 1));
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OQ846', MESSAGE = '0846 V2 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ846' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

CREATE TEMP TABLE _0846_out (phase text, r jsonb) ON COMMIT DROP;

DO $v2a$
DECLARE v_r jsonb := jsonb_build_object('snap', pg_temp._0846_probe('snap'), 'tick', pg_temp._0846_probe('tick'));
BEGIN
  INSERT INTO _0846_out VALUES ('before', v_r);
  IF (v_r #> '{snap,a,why}') IS NOT NULL OR (v_r #> '{snap,b,work}') IS DISTINCT FROM '["sensor_calibration"]'::jsonb THEN
    RAISE EXCEPTION '0846 V2a: the seats were not as this file was written against: %', v_r;
  END IF;
  IF (v_r #>> '{tick,d,need_atom}') IS NOT NULL OR COALESCE(v_r #>> '{tick,d,why}', '') NOT LIKE '%need ''service_due'' (inferred_from_purpose)%' THEN
    RAISE EXCEPTION '0846 V2a: the needs card''s booking was not as this file was written against: %', v_r;
  END IF;
  RAISE NOTICE '0846 V2a (before): %', v_r;
END $v2a$;

DO $patch$
DECLARE p record; v_def text; v_old text; n int;
BEGIN
  FOR p IN SELECT * FROM _0846_patch LOOP
    v_old := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_old) - length(replace(v_old, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0846 V1: the anchor in % matches % times, not 1', p.fn, n; END IF;
    v_def := replace(v_old, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0846 V1: % is not stored as patched', p.fn;
    END IF;
    IF md5(replace(v_def, p.c_new, p.c_old)) IS DISTINCT FROM
       (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0846_pre' AND object_name = p.fn
         ORDER BY snapshot_id DESC LIMIT 1) THEN
      RAISE EXCEPTION '0846 V1: % with its patch reversed is not its snapshot', p.fn;
    END IF;
  END LOOP;
END $patch$;

DO $v2b$
DECLARE v_r jsonb := jsonb_build_object('snap', pg_temp._0846_probe('snap'), 'tick', pg_temp._0846_probe('tick'));
BEGIN
  INSERT INTO _0846_out VALUES ('after', v_r);
  IF (v_r #>> '{snap,a,why,fault_repair}') IS DISTINCT FROM 'open faults P0AA6 and U0100, the worst at severity 1, where 1 is the most severe'
     OR (v_r #>> '{snap,b,why,sensor_calibration}') IS DISTINCT FROM '11 days since its last calibration, due every 10 days'
     OR (v_r #>> '{snap,c,why,tire_rotation}') IS DISTINCT FROM '92 days since its last rotation, due every 91 days' THEN
    RAISE EXCEPTION '0846 V2b snap: a seat does not say why: %', v_r;
  END IF;
  IF COALESCE((v_r #>> '{snap,must_do,missing}')::int, -1) <> 0 THEN
    RAISE EXCEPTION '0846 V2b snap: a service-bay must-do on a needs card has no reason: %', v_r;
  END IF;
  IF COALESCE((v_r #>> '{tick,tick,errored}')::int, -1) <> 0 OR (v_r #>> '{tick,d,need_atom}') IS DISTINCT FROM 'fault_repair'
     OR COALESCE(v_r #>> '{tick,d,why}', '') NOT LIKE '%need ''fault_repair'' (needs card: open faults P0AA6 and U0100%' THEN
    RAISE EXCEPTION '0846 V2b tick: the needs card''s booking does not name its work and why: %', v_r;
  END IF;
  RAISE NOTICE '0846 V2b (after): %', v_r;
END $v2b$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0846_a_service_bay_seat_says_why_the_car_is_there_and_its_booking_names_the_work', false, false,
        'The twin snapshot''s bay_seat carries `why`, the needs card''s reason for each service of the seat''s work, and '
        || 'the needs card''s service booking names its need_atom and reason instead of service_due. New helpers '
        || 'public.ottoq_service_reason, ottoq_service_reasons, ottoq_span_words. No decision changes. Pre-image 0846_pre.', now());
COMMIT;
