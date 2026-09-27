-- migration-version: 20260927074236
-- migration-name:    the_charger_s_sensors_cannot_finish_an_inspection_on_a_car_that_has_left
--
-- 0519  **G245: an interior inspection the charger's sensors started was marked done when its minutes ran out, even
--       when the charge had faulted and the car had driven to staging or to another charger before then. The sensors
--       belong to a stall; the work is theirs only while the car is in front of them. Now the starter records the
--       stall, and the completer finishes the work only if the car is still on it, else returns it to pending with
--       the interruption recorded, to be done again at the car's next charger.**
--       `db/checks/0377` §4(d); `db/checks/0388`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   0511 (G236) gave the charger's sensors the interior inspection and the cabin-only triage check of a car on the
--   charger: `ottoq_start_concurrent_atoms` starts them with `performed_by = 'charger_sensors'` and an `ends_at` of the
--   work's minutes, and `twin.ottoq_sim_advance_visit_atoms` marks any in-progress atom done once `ends_at` passes. It
--   never asks where the car is. On the night's two operator runs 5 sensor inspections finished after their charge had
--   ended, every one a charge cut by a charger fault 1.8 to 4.5 minutes after the plug-in (connector cable, station
--   hardware, communication dropout, session aborted twice), each inspection started 22 to 27 seconds after its
--   plug-in, as meant, and each "done" 0.7 to 2.6 minutes after the car had unplugged: four cars were in staging by
--   then and the fifth (Waymo-AV-016 on caf85837) on a different L2, after a stop in staging. 0377 §4(d) counted them
--   (3 of 85 on caf85837) and said Waymo-AV-016 "stayed parked" on its charger; it did not (`db/checks/0388` §1).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) The starter stamps `sensor_stall_id`, the car's stall, beside `performed_by = 'charger_sensors'`.
--   (2) The completer, for an atom the sensors are doing whose minutes have run out: if the car is still on that stall
--       it is done, as before; if not, it goes back to `pending`, without its start, end, performer or stall, and with
--       the interruption appended to `interrupted` (when, why -- `left_the_charger` -- when it had started, and the
--       stall). Nothing is credited, no leg is closed and nothing is probed for it, because nothing was completed.
--       Back at `pending`, 0511's rules take it again: the sensors at the car's next charger while its charge is still
--       to do, else a technician or the catch-ups.
--   An atom started before this migration carries no `sensor_stall_id` and completes as it did, so a run in flight
--   at the apply keeps its meaning. Only the twin's clock branch (`v_feed_sim`) is touched; a real feed completes
--   its atoms from telemetry.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Both functions run in every certified arm and the atoms are hashed, and a charger fault during a sensor
--   inspection now changes what is done and when. Applied with no run live and in the same recert window as 0518.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0519 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_start text; v_adv text;
BEGIN
  v_start := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  v_adv   := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  IF position('sensor_stall_id' IN v_start) > 0 OR position('sensor_stall_id' IN v_adv) > 0 THEN
    RAISE EXCEPTION '0519 P2: already applied';
  END IF;
  -- the only writer of performed_by = charger_sensors is the starter, and the only reader besides the snapshot
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc LIKE '%charger_sensors%') <> 2 THEN
    RAISE EXCEPTION '0519 P2: charger_sensors is written or read somewhere this file does not know about';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0519_pre', 'function', f.nsp, f.fn, pg_get_functiondef(f.oid), md5(pg_get_functiondef(f.oid))
  FROM (VALUES ('public', 'ottoq_start_concurrent_atoms', 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure::oid),
               ('twin', 'ottoq_sim_advance_visit_atoms', 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure::oid))
       AS f(nsp, fn, oid);

-- ── (1) the starter records the stall whose sensors do the work ──
DO $patch_start$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$  v_state text; v_charging_visit boolean; v_sensors boolean; v_cabin_triage boolean;   -- 0511$o1$,
          $n1$  v_state text; v_charging_visit boolean; v_sensors boolean; v_cabin_triage boolean;   -- 0511
  v_stall uuid;   -- 0519 (G245): the stall whose sensors start the work$n1$],
    ARRAY[$o2$  SELECT v.current_state::text INTO v_state FROM vehicles v WHERE v.id = p_vehicle;$o2$,
          $n2$  SELECT v.current_state::text, v.current_stall_id INTO v_state, v_stall FROM vehicles v WHERE v.id = p_vehicle;$n2$],
    ARRAY[$o3$                   || CASE WHEN v_sensors THEN jsonb_build_object('performed_by', 'charger_sensors') ELSE '{}'::jsonb END;$o3$,
          $n3$                   -- 0519 (G245): and on which stall, since the sensors are that stall's and see only a car on it
                   || CASE WHEN v_sensors THEN jsonb_build_object('performed_by', 'charger_sensors',
                                                                  'sensor_stall_id', v_stall) ELSE '{}'::jsonb END;$n3$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0519: starter patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch_start$;

-- ── (2) the completer finishes the sensors' work only on the stall they are on ──
DO $patch_adv$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state,$o1$,
          $n1$    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state, v.current_stall_id,   /* 0519 */$n1$],
    ARRAY[$o2$      IF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock THEN
        v_a := v_a || jsonb_build_object('status','done','done_at', v_a->'ends_at');$o2$,
          $n2$      IF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'charger_sensors' AND v_a->>'sensor_stall_id' IS NOT NULL
         AND v_rec.current_stall_id IS DISTINCT FROM (v_a->>'sensor_stall_id')::uuid THEN
        -- 0519 (G245): the charger's sensors see only a car on their stall. This car left it (a charge cut by a fault
        -- sends it to staging or another charger) before the work's minutes ran out, so the work was not done: it
        -- goes back to pending, the interruption recorded, and nothing is credited, closed or probed for it.
        v_a := (v_a - 'started_at' - 'ends_at' - 'performed_by' - 'sensor_stall_id')
               || jsonb_build_object('status', 'pending',
                    'interrupted', COALESCE(v_a->'interrupted', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                        'at', p_clock, 'reason', 'left_the_charger',
                        'started_at', v_a->'started_at', 'stall_id', v_a->'sensor_stall_id')));
        v_changed := true;
      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock THEN
        v_a := v_a || jsonb_build_object('status','done','done_at', v_a->'ends_at');$n2$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0519: completer patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch_adv$;

DO $verify$
DECLARE v_start text; v_adv text;
BEGIN
  v_start := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  v_adv   := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  -- V1: the stamp in the starter, the check and the pending branch in the completer, both still SECURITY DEFINER
  IF position('''sensor_stall_id'', v_stall' IN v_start) = 0
     OR position('left_the_charger' IN v_adv) = 0
     OR position('v_rec.current_stall_id IS DISTINCT FROM (v_a->>''sensor_stall_id'')::uuid' IN v_adv) = 0
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure) THEN
    RAISE EXCEPTION '0519 V1: the patched functions are not as intended';
  END IF;
END $verify$;

-- V3: rolled back. On the newest finished operator run -- marked running inside the test, because the starter finds
--     only the depot's running run's visits -- at a clock past its end, with one car planted on a free L2 charging
--     against an open visit that still has its charge to do and a pending interior inspection: (a) the sensors start
--     it and record that stall; (b) the car moves to staging before the minutes run out, and at the end of them the
--     inspection is pending again, not done, with one interruption naming the stall; (c) on a second L2 the sensors
--     start it again with that stall, and it is done at the end of its minutes with its interruption kept.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_end timestamptz; v_car uuid; v_l2a uuid; v_l2b uuid; v_stg uuid; v_visit uuid; v_atom jsonb;
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
      RAISE EXCEPTION '0519 V3 FAILED: a run is live; the starter would look at it, not at the planted visit';
    END IF;
    SELECT sr.sim_run_id, sr.sim_clock_current INTO v_run, v_end FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'operator_demo' AND sr.status = 'completed' ORDER BY sr.started_at DESC LIMIT 1;
    -- a car on no stall, tethered to none and pointed at by none, so the occupancy trigger (sync_stall_occupancy)
    -- moves it cleanly from stall to stall under idx_stalls_one_vehicle_per_stall
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
       AND v.current_stall_id IS NULL AND v.robotic_tether_until IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id)
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn WHERE vn.vehicle_id = v.id AND vn.sim_run_id = v_run
                          AND vn.status IN ('open','in_progress'))
     ORDER BY v.id LIMIT 1;
    SELECT s.id INTO v_l2a FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'l2'
       AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id) AND s.current_vehicle_id IS NULL
     ORDER BY s.id LIMIT 1;
    SELECT s.id INTO v_l2b FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'l2' AND s.id <> v_l2a
       AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id) AND s.current_vehicle_id IS NULL
     ORDER BY s.id LIMIT 1;
    SELECT s.id INTO v_stg FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'staging'
       AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id) AND s.current_vehicle_id IS NULL
     ORDER BY s.id LIMIT 1;
    IF v_run IS NULL OR v_car IS NULL OR v_l2a IS NULL OR v_l2b IS NULL OR v_stg IS NULL THEN
      RAISE EXCEPTION '0519 V3 FAILED: nothing to plant on';
    END IF;
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    UPDATE public.vehicles SET current_state = 'charging_l2', current_stall_id = v_l2a, current_soc = 60 WHERE id = v_car;
    v_visit := gen_random_uuid();
    INSERT INTO public.ottoq_visit_needs (visit_id, visit_key, vehicle_id, depot_id, sim_run_id, status, arrived_at, target_soc, atoms)
    VALUES (v_visit, v_car::text || ':0519v3', v_car, '11111111-1111-1111-1111-111111111111', v_run, 'open',
            v_end + interval '2 hours', 90,
            jsonb_build_array(
              jsonb_build_object('svc', 'charge', 'status', 'pending', 'must_do', true, 'target_soc', 90, 'concurrency', 'anchor'),
              jsonb_build_object('svc', 'interior_inspection', 'status', 'pending', 'must_do', true, 'est_min', 4,
                                 'concurrency', 'cabin', 'at_charge_stall', true)));
    -- (a) on the charger, the sensors start it and say where
    PERFORM public.ottoq_start_concurrent_atoms(v_car, v_end + interval '2 hours');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF v_atom->>'status' <> 'in_progress' OR v_atom->>'performed_by' IS DISTINCT FROM 'charger_sensors'
       OR (v_atom->>'sensor_stall_id')::uuid IS DISTINCT FROM v_l2a THEN
      RAISE EXCEPTION '0519 V3 FAILED (a): the sensors did not start it on the planted charger: %', v_atom;
    END IF;
    -- (b) the charge faults and the car goes to staging before the 4 minutes are up
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_stall_id = v_stg WHERE id = v_car;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_end + interval '2 hours 5 minutes');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF v_atom->>'status' <> 'pending' OR v_atom ? 'done_at' OR v_atom ? 'started_at' OR v_atom ? 'performed_by'
       OR jsonb_array_length(COALESCE(v_atom->'interrupted', '[]'::jsonb)) <> 1
       OR v_atom->'interrupted'->0->>'reason' IS DISTINCT FROM 'left_the_charger'
       OR (v_atom->'interrupted'->0->>'stall_id')::uuid IS DISTINCT FROM v_l2a THEN
      RAISE EXCEPTION '0519 V3 FAILED (b): an inspection whose car left the charger was not returned to pending: %', v_atom;
    END IF;
    -- (c) on a second charger the sensors start it again, and it is done on the stall they are on. The car moves first
    --     and plugs in after, as the engine does it: a stall is not let go of a car already charging (the reassignment
    --     guard on `stalls` keeps the pointer of a car mid-work), so moving and plugging in one statement would leave
    --     the staging stall holding it.
    UPDATE public.vehicles SET current_stall_id = v_l2b WHERE id = v_car;
    UPDATE public.vehicles SET current_state = 'charging_l2' WHERE id = v_car;
    PERFORM public.ottoq_start_concurrent_atoms(v_car, v_end + interval '2 hours 6 minutes');
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_end + interval '2 hours 11 minutes');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF v_atom->>'status' <> 'done' OR (v_atom->>'sensor_stall_id')::uuid IS DISTINCT FROM v_l2b
       OR (v_atom->>'done_at')::timestamptz <> v_end + interval '2 hours 10 minutes'
       OR jsonb_array_length(COALESCE(v_atom->'interrupted', '[]'::jsonb)) <> 1 THEN
      RAISE EXCEPTION '0519 V3 FAILED (c): the second charger''s inspection did not complete where it ran: %', v_atom;
    END IF;
    RAISE EXCEPTION '0519 V3 PASSED: started on the charger with its stall; returned to pending when the car left it; done on the next charger with the interruption kept';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0519 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0519 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore both functions from `0519_pre` (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0519_the_charger_s_sensors_cannot_finish_an_inspection_on_a_car_that_has_left', true,
  'G245: an inspection or cabin triage the charger''s sensors started records its stall, and is done only if the car '
  'is still on it when its minutes run out; else it returns to pending with the interruption recorded. Both functions '
  'run in every certified arm and the atoms are hashed.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
