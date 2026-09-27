-- migration-version: 20260927085218
-- migration-name:    the_charger_s_sensors_see_only_a_car_on_a_charger
--
-- 0521  **G246: the charger's sensors were credited with interior inspections and cabin triage checks on cars that
--       were not on a charger, because the starter took the car's state for its place: `charge_complete_holding` is
--       also the state of a car the gate intake holds on staging with no charge to do, and of a car that has left its
--       charger for a bay. Now "on a charger" means the car's stall is one, in both places the starter asks: the
--       sensors start work only there, and a visit with its charge still to do keeps its cabin work for the charger
--       unless the car is on one (or staged for departure, the catch-up that stays).**
--       `db/checks/0388` §4; `db/checks/0390`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   0511 (G236) gave the charger's sensors the interior inspection and the cabin-only triage check of a car "on the
--   charger", and decided "on the charger" by state: `charging_dcfc`, `charging_l2` or `charge_complete_holding`. 0519
--   (G245) stamped the stall the sensors started on, and that stamp is what showed the rule wrong. On validation run
--   c4afb873, 6 of 72 sensor starts were on cars in `charge_complete_holding` that were on no charger:
--     - 3 on staging stalls, cars the gate intake had parked on arrival: Zoox-AV-091, with no charge on its visit
--       (NASH-STG-I010, then again on NASH-STG-W021 after 0519 caught the move), and Waymo-AV-002 (NASH-STG-I010),
--       whose visit still had its charge step open -- closed two minutes later, not by a charge;
--     - 3 with no stall at all, the starter running in the tick between a car's arrival or unplug and its next stall:
--       Tesla-AV-043, 30 seconds after its charge on NASH-L2-STALL-14 ended and as it entered NASH-WSH-01; Waymo-AV-027,
--       an inspection and a cabin triage, at the gate as it was parked on NASH-STG-I011.
--   4 of the 66 sensor completions on the run were therefore credited to sensors that do not exist: three on a staging
--   stall and one in a wash bay. None of the cars but Tesla-AV-043 had an OCPP session on the run, and Tesla-AV-043's
--   ended before the work began. Waymo-AV-002 shows the same proxy in a second place: the cabin hold (0511) keeps a
--   visit's cabin work for the charger while its charge is to do, and excuses `charge_complete_holding` as "still on
--   the charger after the charge" -- so a car parked on staging with its charge step open had its inspection started.
--   0519 caught two of the six only by accident (the car moved between two staging stalls) and could catch none of the
--   three with no stall, since it records the stall it is given and a missing one passes its check. The night's two
--   earlier runs, read from the signed event stream (which cannot order two changes in one tick, so the count is a
--   floor): 2 of 184 on 4bc19d29 (a staging stall at 8:13 AM, a wash bay at 1:47 PM) and 2 of 98 on caf85837 (staging,
--   8:02 AM).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_start_concurrent_atoms` reads once whether the car's stall is a charger (`dcfc` or `l2`, the house
--   idiom and, measured, the only stall types any of the 48,920 OCPP sessions on record ever ran on), and uses it in
--   both places it asked the state instead:
--   (1) the sensors take an inspection or a cabin-only triage only from a car in a charging state ON a charger;
--   (2) the cabin hold excuses a charging visit's cabin work from waiting only for a car in a charging state on a
--       charger, or staged for departure (0385's catch-up, unchanged: nothing may wait forever at the exit).
--   Everything else in the starter stands: the state test, the technician pool, the digital work. So a car in
--   `charge_complete_holding` on staging, in a bay or between stalls has its inspection started by a technician when
--   one is free -- counted against the pool, as sensor work is not -- if its visit has no charge left to do; and if it
--   has, the inspection waits for the charger, the step's close (0518's one rule closes it or books the charger) or
--   the exit, exactly as for a car at the gate.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The starter runs in every certified arm and the atoms are hashed; who does an inspection now changes the
--   technician pool and so what else starts. Applied between dial pairs (P0), before the G240 experiment's pairs
--   accumulate on an engine this would retire.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0521 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_start text;
BEGIN
  v_start := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  IF position('v_on_charger' IN v_start) > 0 THEN
    RAISE EXCEPTION '0521 P2: already applied';
  END IF;
  IF position('''sensor_stall_id'', v_stall' IN v_start) = 0 THEN
    RAISE EXCEPTION '0521 P2: 0519 is not applied; this file patches the starter 0519 left';
  END IF;
  -- the writers and readers of charger_sensors are the three this file and 0519 know: the starter, 0519's completer
  -- and the twin snapshot
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc LIKE '%charger_sensors%') <> 3 THEN
    RAISE EXCEPTION '0521 P2: charger_sensors is written or read somewhere this file does not know about';
  END IF;
  -- a charger is a dcfc or l2 stall: no charge session on record ran on any other kind
  IF EXISTS (SELECT 1 FROM public.ocpp_sessions os JOIN public.stalls s ON s.id = os.stall_id
              WHERE s.stall_type::text NOT IN ('dcfc','l2')) THEN
    RAISE EXCEPTION '0521 P2: a charge session ran on a stall that is neither dcfc nor l2';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0521_pre', 'function', 'public', 'ottoq_start_concurrent_atoms',
       pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure));

-- ── the starter asks the car's stall, not its state, whether it is on a charger: for the sensors and for the hold ──
DO $patch_start$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$  v_stall uuid;   -- 0519 (G245): the stall whose sensors start the work$o1$,
          $n1$  v_stall uuid;   -- 0519 (G245): the stall whose sensors start the work
  v_on_charger boolean;   -- 0521 (G246): whether that stall is a charger at all$n1$],
    ARRAY[$o2$  SELECT v.current_state::text, v.current_stall_id INTO v_state, v_stall FROM vehicles v WHERE v.id = p_vehicle;$o2$,
          $n2$  SELECT v.current_state::text, v.current_stall_id INTO v_state, v_stall FROM vehicles v WHERE v.id = p_vehicle;
  -- 0521 (G246): the sensors are a charger's, so the car must be on one. The state alone does not say so:
  -- `charge_complete_holding` is also a car the gate intake holds on staging with no charge to do, and a car that has
  -- left its charger for a bay, and on c4afb873 six sensor starts were on such cars.
  v_on_charger := EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text IN ('dcfc','l2'));$n2$],
    ARRAY[$o3$       AND NOT (v_a->>'concurrency' = 'cabin' AND v_charging_visit
                AND COALESCE(v_state, '') NOT IN ('charging_dcfc','charging_l2','charge_complete_holding','staged_for_departure')) THEN$o3$,
          $n3$       AND NOT (v_a->>'concurrency' = 'cabin' AND v_charging_visit
                -- 0521 (G246): a charging state excuses the hold only on a charger; staged for departure always does
                AND NOT (COALESCE(v_state, '') = 'staged_for_departure'
                         OR (COALESCE(v_state, '') IN ('charging_dcfc','charging_l2','charge_complete_holding') AND v_on_charger))) THEN$n3$],
    ARRAY[$o4$                   AND COALESCE(v_state, '') IN ('charging_dcfc','charging_l2','charge_complete_holding');$o4$,
          $n4$                   AND COALESCE(v_state, '') IN ('charging_dcfc','charging_l2','charge_complete_holding')
                   AND v_on_charger;   -- 0521 (G246)$n4$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0521: starter patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch_start$;

DO $verify$
DECLARE v_start text;
BEGIN
  v_start := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  -- V1: the charger test, the sensors and the hold both gated on it (the old state list gone), 0519's stamp kept,
  --     still SECURITY DEFINER on its search_path
  IF position('v_on_charger := EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text IN (''dcfc'',''l2''))' IN v_start) = 0
     OR position('AND v_on_charger;   -- 0521 (G246)' IN v_start) = 0
     OR position('OR (COALESCE(v_state, '''') IN (''charging_dcfc'',''charging_l2'',''charge_complete_holding'') AND v_on_charger))) THEN' IN v_start) = 0
     OR position('NOT IN (''charging_dcfc'',''charging_l2'',''charge_complete_holding'',''staged_for_departure'')' IN v_start) > 0
     OR position('''sensor_stall_id'', v_stall' IN v_start) = 0
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)
     OR (SELECT proconfig FROM pg_proc WHERE oid = 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)
        IS DISTINCT FROM ARRAY['search_path=twin, ottoq, public, extensions'] THEN
    RAISE EXCEPTION '0521 V1: the patched starter is not as intended';
  END IF;
END $verify$;

-- V3: rolled back. On the newest finished operator run -- marked running inside the test, because the starter finds
--     only the depot's running run's visits -- with one car planted in `charge_complete_holding` against an open visit
--     with no charge to do and a pending interior inspection: (a) on a staging stall, the sensors do not take it;
--     (b) on no stall, they do not take it; (c) on an L2, they take it and record that stall. In (a) and (b) the
--     inspection is either still pending or started by a technician, whichever the pool allows at that moment; the test
--     asserts only that no sensor is credited, and reports which. Then the visit gets its charge step back, open:
--     (d) on the staging stall the hold keeps the inspection pending, as Waymo-AV-002's should have been; (e) on the L2
--     the sensors take it, since that is where a charging visit's cabin work belongs.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_end timestamptz; v_car uuid; v_l2 uuid; v_stg uuid; v_visit uuid; v_atom jsonb;
  v_pending jsonb := jsonb_build_array(
                       jsonb_build_object('svc', 'readiness_check', 'status', 'pending', 'must_do', true, 'est_min', 3,
                                          'concurrency', 'gate'),
                       jsonb_build_object('svc', 'interior_inspection', 'status', 'pending', 'must_do', true, 'est_min', 4,
                                          'concurrency', 'cabin', 'at_charge_stall', true));
  v_charging jsonb := jsonb_build_array(
                        jsonb_build_object('svc', 'charge', 'status', 'pending', 'must_do', true, 'target_soc', 100,
                                           'concurrency', 'anchor'),
                        jsonb_build_object('svc', 'interior_inspection', 'status', 'pending', 'must_do', true, 'est_min', 4,
                                           'concurrency', 'cabin', 'at_charge_stall', true));
  v_seen text := '';
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
      RAISE EXCEPTION '0521 V3 FAILED: a run is live; the starter would look at it, not at the planted visit';
    END IF;
    SELECT sr.sim_run_id, sr.sim_clock_current INTO v_run, v_end FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'operator_demo' AND sr.status = 'completed' ORDER BY sr.started_at DESC LIMIT 1;
    -- a car on no stall, tethered to none and pointed at by none (0519 V3's lesson: idx_stalls_one_vehicle_per_stall)
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
       AND v.current_stall_id IS NULL AND v.robotic_tether_until IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id)
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn WHERE vn.vehicle_id = v.id AND vn.sim_run_id = v_run
                          AND vn.status IN ('open','in_progress'))
     ORDER BY v.id LIMIT 1;
    SELECT s.id INTO v_l2 FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'l2'
       AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id) AND s.current_vehicle_id IS NULL
     ORDER BY s.id LIMIT 1;
    SELECT s.id INTO v_stg FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'staging'
       AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id) AND s.current_vehicle_id IS NULL
     ORDER BY s.id LIMIT 1;
    IF v_run IS NULL OR v_car IS NULL OR v_l2 IS NULL OR v_stg IS NULL THEN
      RAISE EXCEPTION '0521 V3 FAILED: nothing to plant on';
    END IF;
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    v_visit := gen_random_uuid();
    INSERT INTO public.ottoq_visit_needs (visit_id, visit_key, vehicle_id, depot_id, sim_run_id, status, arrived_at, target_soc, atoms)
    VALUES (v_visit, v_car::text || ':0521v3', v_car, '11111111-1111-1111-1111-111111111111', v_run, 'open',
            v_end + interval '2 hours', 90, v_pending);

    -- (a) held on staging by the gate intake, as Zoox-AV-091 and Waymo-AV-002 were
    UPDATE public.vehicles SET current_stall_id = v_stg WHERE id = v_car;
    UPDATE public.vehicles SET current_state = 'charge_complete_holding', current_soc = 98 WHERE id = v_car;
    PERFORM public.ottoq_start_concurrent_atoms(v_car, v_end + interval '2 hours');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF v_atom ? 'performed_by' OR v_atom ? 'sensor_stall_id'
       OR COALESCE(v_atom->>'status', 'pending') NOT IN ('pending', 'in_progress') THEN
      RAISE EXCEPTION '0521 V3 FAILED (a): the sensors took an inspection on a staging stall: %', v_atom;
    END IF;
    v_seen := v_seen || '(a) ' || COALESCE(v_atom->>'status', 'pending');

    -- (b) between stalls, as Tesla-AV-043 and Waymo-AV-027 were
    UPDATE public.ottoq_visit_needs SET atoms = v_pending, status = 'open' WHERE visit_id = v_visit;
    UPDATE public.vehicles SET current_stall_id = NULL WHERE id = v_car;
    PERFORM public.ottoq_start_concurrent_atoms(v_car, v_end + interval '2 hours 1 minute');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF v_atom ? 'performed_by' OR v_atom ? 'sensor_stall_id'
       OR COALESCE(v_atom->>'status', 'pending') NOT IN ('pending', 'in_progress') THEN
      RAISE EXCEPTION '0521 V3 FAILED (b): the sensors took an inspection on a car on no stall: %', v_atom;
    END IF;
    v_seen := v_seen || ', (b) ' || COALESCE(v_atom->>'status', 'pending');

    -- (c) still on the charger after the charge: 0511's catch-up, which stays the sensors'
    UPDATE public.ottoq_visit_needs SET atoms = v_pending, status = 'open' WHERE visit_id = v_visit;
    UPDATE public.vehicles SET current_stall_id = v_l2 WHERE id = v_car;
    PERFORM public.ottoq_start_concurrent_atoms(v_car, v_end + interval '2 hours 2 minutes');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF v_atom->>'status' IS DISTINCT FROM 'in_progress' OR v_atom->>'performed_by' IS DISTINCT FROM 'charger_sensors'
       OR (v_atom->>'sensor_stall_id')::uuid IS DISTINCT FROM v_l2 THEN
      RAISE EXCEPTION '0521 V3 FAILED (c): the sensors did not take the inspection of a car still on its charger: %', v_atom;
    END IF;

    -- (d) the charge still to do, parked on staging: the hold keeps the cabin work for the charger
    UPDATE public.ottoq_visit_needs SET atoms = v_charging, status = 'open' WHERE visit_id = v_visit;
    UPDATE public.vehicles SET current_stall_id = v_stg WHERE id = v_car;
    PERFORM public.ottoq_start_concurrent_atoms(v_car, v_end + interval '2 hours 3 minutes');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF COALESCE(v_atom->>'status', 'pending') <> 'pending' OR v_atom ? 'performed_by' OR v_atom ? 'started_at' THEN
      RAISE EXCEPTION '0521 V3 FAILED (d): a charging visit''s inspection started on staging: %', v_atom;
    END IF;
    -- (e) the same visit on the L2: the sensors take it there
    UPDATE public.vehicles SET current_stall_id = v_l2 WHERE id = v_car;
    PERFORM public.ottoq_start_concurrent_atoms(v_car, v_end + interval '2 hours 4 minutes');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF v_atom->>'status' IS DISTINCT FROM 'in_progress' OR v_atom->>'performed_by' IS DISTINCT FROM 'charger_sensors'
       OR (v_atom->>'sensor_stall_id')::uuid IS DISTINCT FROM v_l2 THEN
      RAISE EXCEPTION '0521 V3 FAILED (e): the sensors did not take a charging visit''s inspection on the charger: %', v_atom;
    END IF;
    RAISE EXCEPTION '0521 V3 PASSED: on staging and on no stall no sensor was credited (%); on the L2 the sensors took it with that stall; with the charge still to do it waited on staging and the sensors took it on the L2', v_seen;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0521 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0521 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore the starter from `0521_pre` (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0521_the_charger_s_sensors_see_only_a_car_on_a_charger', true,
  'G246: "on a charger" is read from the car''s stall (dcfc or l2), not its state: the charger''s sensors start an '
  'interior inspection or cabin triage only there, and a visit with its charge still to do keeps its cabin work for '
  'the charger unless the car is on one or staged for departure. A car in charge_complete_holding on staging, in a bay '
  'or on no stall gets a technician, or waits for its charge. The starter runs in every certified arm and the atoms '
  'are hashed.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
