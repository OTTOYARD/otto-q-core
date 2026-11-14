-- migration-version: 20261114005209
-- migration-name:    0830_the_arm_of_a_car_cleaned_after_its_charge_starts_where_the_charge_is_stopped
--
-- 0830  **The arm of a car cleaned after its charge starts where the charge is stopped, and every such stop says on
--        the visit what the arm was asked and what it did.**
--
-- WHY. 0827 and 0828 missed about 4 in 10 of the arm cleans they moved (db/checks/0491), and the setting has been off
--   since 2026-11-13 21:58:23 UTC. Chase, 2026-11-13 evening CT, asked whether to build a third attempt that records
--   why a start was missed and starts the arm at the stop of the charge: "Go".
--
-- §1 WHAT WAS SO, READ ON RUN c86b46e1 (twin depot, 2026-11-13). 0827's second door and 0828's test both need the car
--   in `charge_complete_holding` when the starter is asked. Of the 124 completed fast-charger sessions of the three
--   kinds of car while the setting was on, the car left `charge_complete_holding` at the SAME sim clock as the session
--   ended in 121, and later in 3. One car read event by event (091fa637, session ended sim 16:02:53): charging_dcfc ->
--   charge_complete_holding -> staged_awaiting_service inside one tick, the tether released at the next. So the
--   starter, which is asked later in the tick, almost never saw the state it was written to see. 0827's first door
--   (the planner's estimate at most the lead) is the only one that worked, and the estimate does not reach the lead
--   on every charge (0828 §1).
--   A second thing, read from the starter's source: while such a car charges with more than the lead left, a needed
--   interior tidy fell to the technician branch, so a technician tidied the car during its charge (12 of the 29
--   misses), through the same door the arm cannot open against the latched connector.
--
-- §2 WHAT THIS DOES.
--   (a) public.ottoq_arm_after_charge_at_stop(vehicle, clock): for a car whose profile says clean_after_charge, with
--       both settings on, it asks the starter at once when 0828's test says the car waits for the arm, and writes on
--       the visit, under meta.arm_after_charge, when it was asked, why (or why not), how many atoms started and what
--       the visit shows after (the arm started, a recorded decision, or nothing). An error is caught and recorded.
--   (b) twin.ottoq_sim_stop_charge_session calls it, for a stop that is not a fault, right after it has put the car
--       under its demate tether, inside the same transaction as the stop. The car is in `charge_complete_holding` on
--       its post at that statement by construction, so the starter's second door (0827) opens: the arm starts the
--       visit's needed tidy, its deep clean or its routine, or records an owner's immediate turnaround. 0760's hold
--       then keeps the car on its post until the arm is home.
--   (c) public.ottoq_start_concurrent_atoms: while such a car charges with more than the lead left, its interior tidy
--       waits for the arm; no technician takes it.
--   (d) This file does NOT change cabin_robot_after_charge: another session's check run (14d6eda7, started
--       2026-11-14 00:47:55 UTC) was live at the apply, and with the setting off this file changes nothing in a run.
--       The setting is turned on at the twin depot after that run ends; the statement and its time are at the foot.
--       The lead stays (3.5 there): a start in the last minutes of the charge still happens when the estimate reads
--       it, and the stop is the start that does not depend on it.
--
-- §3 WHAT IT COSTS, AND WHAT IT DOES NOT DO. A car of the three kinds holds its post one arm cycle (5.8 min at the
--   twin's settings; a deep clean longer) after its charge when the arm starts at the stop: 80 of the twin depot's
--   116 cars. A needed tidy on such a car now waits for the end of its charge. No charge is shortened and no service
--   skipped (rule 9); an owner's immediate turnaround is still not held for a routine clean it did not need (0765).
--   0828's two patches stay; after this they act only on a car the starter could not start.
--
-- §4 PRECONDITIONS AND CHECKS. P0 no certification in flight. P1 the two bodies (md5 of prosrc, read 2026-11-14).
--   P2 once (this file was first numbered 0829; another session applied its own 0829 at 2026-11-14 00:47:43 UTC). V1 each patched body with its patches reversed is its pre-image. V2 each anchor matched once. V3 the new
--   function runs for every car of the twin depot's three kinds without error and writes nothing for a car that is
--   not at a stop (it returns before any write when the car has no demate tether on a fast-charger post), and both
--   patched bodies run once.
--
-- §5 CLASSIFICATION. forces_recert TRUE, forces_dial_restart FALSE.
--
-- ROLLBACK: UPDATE public.ottoq_policy_params SET param_value = 0 WHERE param_key = 'cabin_robot_after_charge';
--   EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0830_pre';
--   DROP FUNCTION public.ottoq_arm_after_charge_at_stop(uuid, timestamptz);
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0830_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0830 P0: a certification is in flight'; END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'))
     IS DISTINCT FROM '0da9732354f975a2cb54e8e78ae3d57d' THEN
    RAISE EXCEPTION '0830 P1: public.ottoq_start_concurrent_atoms is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'))
     IS DISTINCT FROM '877cf0bf0e7611c52ea166ba73679469' THEN
    RAISE EXCEPTION '0830 P1: twin.ottoq_sim_stop_charge_session is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0830_%') THEN RAISE EXCEPTION '0830 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0830_pre', 'function', split_part(f, '.', 1), f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
                    'twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)']) AS f;

CREATE FUNCTION public.ottoq_arm_after_charge_at_stop(p_vehicle uuid, p_clock timestamptz)
 RETURNS jsonb LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0830: called where a charge is stopped. For a car cleaned AFTER its charge (0827) that stands on its fast-charger
   post under its demate tether, it asks the starter now, and writes on the visit what was asked and what came of it.
   It returns NULL, and writes nothing, for any other car. It never raises. */
DECLARE
  v_stall uuid; v_visit uuid; v_run uuid; v_atoms jsonb; v_meta jsonb;
  v_why text; v_started int := 0; v_err text; v_result text; v_rec jsonb;
BEGIN
  IF NOT COALESCE((public.ottoq_vehicle_port_profile(p_vehicle)).clean_after_charge, false) THEN RETURN NULL; END IF;
  SELECT v.robotic_tether_stall_id INTO v_stall
    FROM public.vehicles v JOIN public.stalls s ON s.id = v.robotic_tether_stall_id AND s.stall_type::text = 'dcfc'
   WHERE v.id = p_vehicle AND v.robotic_tether_until IS NOT NULL
     AND COALESCE(v.robotic_tether_direction, 'demate') = 'demate';
  IF v_stall IS NULL THEN RETURN NULL; END IF;
  SELECT vn.visit_id, vn.sim_run_id, vn.atoms, COALESCE(vn.meta, '{}'::jsonb) INTO v_visit, v_run, v_atoms, v_meta
    FROM public.ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open', 'in_progress') AND jsonb_typeof(vn.atoms) = 'array'
   ORDER BY vn.created_at DESC LIMIT 1;
  IF v_visit IS NULL THEN RETURN NULL; END IF;
  IF COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_after_charge', 0), 0) < 1
     OR COALESCE(public.ottoq_policy_get(v_run, 'stall_cabin_robot', 0), 0) < 1 THEN RETURN NULL; END IF;

  v_why := CASE
    WHEN public.ottoq_awaits_arm_after_charge(p_vehicle) THEN 'asked'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
                  WHERE a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' = 'in_progress') THEN 'arm_at_work'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
                  WHERE a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' = 'done') THEN 'arm_done'
    WHEN v_meta ? 'arm_routine' THEN 'decided:' || COALESCE(v_meta -> 'arm_routine' ->> 'outcome', '?')
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
                  WHERE a->>'svc' = 'interior_tidy' AND a->>'status' IN ('in_progress', 'done')) THEN 'tidied_by_another'
    WHEN EXISTS (SELECT 1 FROM public.stalls fs JOIN public.ottoq_ocpp_chargers fc ON fc.charger_id = fs.ocpp_charger_id
                  WHERE fs.id = v_stall AND fc.station_state = 'Faulted') THEN 'charger_faulted'
    ELSE 'not_waiting:' || COALESCE((SELECT v.current_state::text FROM public.vehicles v WHERE v.id = p_vehicle), '?')
  END;

  IF v_why = 'asked' THEN
    BEGIN
      v_started := COALESCE(public.ottoq_start_concurrent_atoms(p_vehicle, p_clock), 0);
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;
    END;
    SELECT CASE
             WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                           WHERE a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' = 'in_progress') THEN 'arm_started'
             WHEN COALESCE(vn.meta, '{}'::jsonb) ? 'arm_routine'
               THEN 'decided:' || COALESCE(vn.meta -> 'arm_routine' ->> 'outcome', '?')
             ELSE 'nothing_started' END
      INTO v_result
      FROM public.ottoq_visit_needs vn WHERE vn.visit_id = v_visit;
  END IF;

  v_rec := jsonb_strip_nulls(jsonb_build_object(
             'at', p_clock, 'stall_id', v_stall, 'why', v_why, 'atoms_started', v_started,
             'result', v_result, 'error', v_err));
  UPDATE public.ottoq_visit_needs SET meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object('arm_after_charge', v_rec)
   WHERE visit_id = v_visit;
  RETURN v_rec;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

CREATE TEMP TABLE _0830_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0830_patch VALUES
(1, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o1$  v_cabin_stop boolean := false;   -- 0817: the car stands on a fast-charger post for the arm's program, not plugged in
$o1$,
$n1$  v_cabin_stop boolean := false;   -- 0817: the car stands on a fast-charger post for the arm's program, not plugged in
  v_arm_waits boolean := false;    -- 0830: the car is cleaned after its charge and still charges; its tidy waits for the arm
$n1$),
(2, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o2$        v_robot_cycle := NULL;
        v_robot_left := NULL;
      END IF;
$o2$,
$n2$        v_robot_cycle := NULL;
        v_robot_left := NULL;
        v_arm_waits := true;   -- 0830
      END IF;
$n2$),
(3, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o3$      IF COALESCE((v_a->>'needs_uplink')::boolean, false) AND NOT COALESCE(v_uplink, false) THEN
        NULL;
$o3$,
$n3$      IF COALESCE((v_a->>'needs_uplink')::boolean, false) AND NOT COALESCE(v_uplink, false) THEN
        NULL;
      -- 0830: a car cleaned after its charge (0827) that still charges: its interior tidy waits for the post's arm,
      -- which starts it in the last minutes of the charge or where the charge is stopped. No technician takes it:
      -- the door the arm cannot open against the latched connector is the same door.
      ELSIF v_arm_waits AND v_a->>'svc' = 'interior_tidy' THEN
        NULL;
$n3$),
(4, 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)',
$o4$    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm demate begin: %', SQLERRM;
    END;
  END IF;
$o4$,
$n4$    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm demate begin: %', SQLERRM;
    END;
  END IF;

  -- 0830: a car cleaned AFTER its charge (0827) has its post's arm asked here, where the charge is stopped and the car
  -- stands on its post under its demate tether. Later in the tick the car's state has moved on (run c86b46e1: 121 of
  -- 124 stops) and the starter no longer sees it. Not for a fault: that car is re-queued to finish (0792). The call
  -- records on the visit what was asked and what came of it, and never aborts the close.
  IF v_tether AND COALESCE(p_reason, '') NOT LIKE 'fault%' THEN
    BEGIN
      PERFORM public.ottoq_arm_after_charge_at_stop(v_session.vehicle_id, v_clock);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm after charge: %', SQLERRM;
    END;
  END IF;
$n4$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0830_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0830 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0830: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0830_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0830_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0830_pre' AND s.object_name = f.fn LIMIT 1) THEN
      RAISE EXCEPTION '0830 V1: % with its patches reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

CREATE TEMP TABLE _0830_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_cars int; v_err int; v_wrote int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE r ? 'error'), count(*) FILTER (WHERE r IS NOT NULL AND NOT r ? 'error')
    INTO v_cars, v_err, v_wrote
    FROM (SELECT public.ottoq_arm_after_charge_at_stop(v.id, now()) AS r
            FROM public.vehicles v WHERE v.home_depot_id = c_depot) q;
  IF v_err > 0 THEN RAISE EXCEPTION '0830 V3: the stop door raised for % cars', v_err; END IF;
  -- both patched bodies compile and run (a car and a session that do not exist: each returns at its first test)
  PERFORM public.ottoq_start_concurrent_atoms(gen_random_uuid(), now());
  PERFORM twin.ottoq_sim_stop_charge_session(gen_random_uuid(), 'completed', now(), NULL, NULL);
  INSERT INTO _0830_selftest VALUES (jsonb_build_object('cars_tested', v_cars, 'at_a_stop_now', v_wrote));
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0830_the_arm_of_a_car_cleaned_after_its_charge_starts_where_the_charge_is_stopped', true, false,
        'cabin_robot_after_charge is not changed by this file. V3 at apply: '
        || COALESCE((SELECT result::text FROM _0830_selftest LIMIT 1), 'no result'), now());
COMMIT;

-- APPLIED 2026-11-14 at 00:52:09 UTC (2026-11-13, 6:52 PM CT), ledger 20261114005209, through apply_migration, on the
--   first send. It was not run beforehand inside a rolled-back transaction as 0827 and 0828 were; V3 runs both patched
--   bodies once inside the apply instead. Run 14d6eda7 (another session's check of its 0829) was live, at tick 51 just
--   after. V3 at apply: cars_tested 120, at_a_stop_now 0.
--   Stored after the apply, md5(prosrc): ottoq_start_concurrent_atoms 92c596b52649ba4efeeff1b46e7982bd,
--   ottoq_sim_stop_charge_session 9a77b89af1c864f69cae788498fe367b, ottoq_arm_after_charge_at_stop
--   acfc71471598f0e7959cca7f0cc29d38.
--   cabin_robot_after_charge at the twin depot: 0 at the apply (off since 2026-11-13 21:58:23 UTC).
