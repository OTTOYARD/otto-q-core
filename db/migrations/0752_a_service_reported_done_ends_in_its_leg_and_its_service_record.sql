-- migration-version: 20261018112438
-- migration-name:    a_service_reported_done_ends_in_its_leg_and_its_service_record
--
-- 0752  **A service reported done ends in its itinerary leg and its service record.** (G466)
--       In production a robot or a technician reports the work it finished through public.ottoq_ingest_service_complete,
--       with the list of services done. The seam marks those atoms done and credits the car's wear, and that is all: it
--       closes no itinerary leg, so the leg trigger issues no SDR, and it judges no completion at task_completion. The
--       twin's own completion of the same work, in twin.ottoq_sim_advance_visit_atoms, does both, and is the twin's timer:
--       it runs only where the twin feeds the depot. So once a real feed drives a depot, no work done in place there would
--       leave a service record, and the shield would never see a piece of it finish. Research wing, rule 10: under 0750's
--       dial, which asks the same question of the bay exit.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-18 between 12:37 and 1:11 AM CT; db/checks/0456) ═══════════════════════════════
--
--   The seam (prosrc md5 e64f5376): with a list, it counts the visit's outstanding atoms among the reported services,
--   calls ottoq_mark_visit_atoms_done, credits each service's wear, records ops.services_completed_reported and returns;
--   nothing in it names a leg, an SDR or a probe, (1). An SDR is issued when an itinerary leg turns done
--   (trg_0043_leg_done_sdr) or a schedule task completes, and nowhere else. The only caller of ottoq_close_atom_leg, which
--   closes the leg of work done in place, is twin.ottoq_sim_advance_visit_atoms (three sites), and the branch that
--   completes an atom there, closes its leg, credits it and probes task_completion opens
--   `ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND ends_at <= p_clock`: the twin's timer, (2). In the twin that
--   branch covers 94-100% of the work done in place with an SDR (db/checks/0454 (1)); at a depot a real feed drives it
--   never runs, and the seam is the only door left. ottoq_mark_visit_atoms_done (be7dc4f2) only rewrites the atoms, (3).
--   The seven leg types of the work done in place issue SDRs (inspect, interior_tidy, item_retrieval,
--   remote_diagnostics, sensor_clean, software_update, triage_check), (4). Not live, as G465: no production tick is
--   scheduled, no production run is running, and no real depot is in external mode.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The dial bay_exit_closes_its_leg (0750) now also governs the seam; its catalog entry says so.
--   (b) public.ottoq_close_reported_work_legs(run, car, services, clock): NULL below 1 or for a missing run, car, clock or
--       list. At 1, on the visit ottoq_mark_visit_atoms_done is about to mark (picked by its own selector), each reported
--       service the visit still has outstanding and that is done in place closes its leg through ottoq_close_atom_leg,
--       with the atom's start (none if it never started) and the report's clock, so the leg trigger issues its SDR, and
--       is judged by ottoq_probe_task_completion, as the twin's completion does; the readiness check closes its leg and
--       is not probed, as the twin's readiness branch does. A bay service is left to the bay exit (0750: the exit's credit
--       closes its leg there with the seat's times) and a charge to its session's stop. It returns the legs closed, their
--       service records, the services probed and what it left to which door.
--   (c) public.ottoq_ingest_service_complete, four anchored edits on its list branch: it calls (b) in its own
--       subtransaction before it marks the atoms, as the twin closes and probes an atom before storing it, so a failure is
--       a warning and the report stands; and when (b) returned something, its event and its reply carry it as `records`.
--       At 0 (b) returns NULL, and the event and the reply are byte for byte today's.
--   Not changed: which atoms a report marks or how it counts them, the wear it credits, the report with no list (a bay's
--   "done", which 0750 serves at the exit), the departure test (rule 9: it reads neither legs nor SDRs). Not covered,
--   and named in G466: a green-light an atom requires is not raised here (G467), and a bay service reported in the list
--   while the car is still in its bay is marked done before the exit, so the exit's credit no longer names it and 0750
--   records the seat as a leg of its own while the service's planned leg stays planned.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, and no run live at the twin depot (V3 starts a probe run there, and a depot holds one running
--   run). P1 the seam, the atom marker and the atom leg close are the bodies read (e64f5376, be7dc4f2, efd2dbb8), the
--   task_completion probe has the signature called, the leg trigger is enabled on a done status, the seven leg types of
--   the work done in place issue SDRs, 0750 is applied, and nothing of this file exists. P2 not already applied.
--   Pre-image to ottoq_schema_snapshots as '0752_pre'. Each anchor matches once. V1 the seam less its edits is its
--   pre-image. V2 at the dial's default, and for a missing run, car, clock or list, (b) returns NULL. V3 on live, in a
--   block rolled back by its own raise, through the seam at the twin depot on a probe run with the dial on: a sensor clean
--   started earlier and a software update never started, reported with a wash and a charge, close their two planned
--   legs, each with its SDR, and are probed; the wash and the charge legs stay planned and are named as left to their
--   doors; the event and the reply carry the records; with the dial off a reported service marks its atom and closes
--   nothing; nothing is left behind.
--   tests/test_reported_work_closes_its_leg_sql.py executes (b) and the patched seam on the scratch PostgreSQL against
--   the live seam, atom marker, atom leg close, leg helpers, leg trigger and SDR emitter (md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. The twin never calls the seam: it is the door of a real feed, and
--   no certification arm, canon cell, dial experiment or sweep reaches it. At the dial's default the seam does what it
--   did (V1; V2), and the dial stays 0 everywhere until 0750's arms are read and a person ships it.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0752_pre'; DROP FUNCTION
--   public.ottoq_close_reported_work_legs(uuid, uuid, text[], timestamptz); restore the dial's description and affects
--   from 0750's text; DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0752_a_service_reported_done_ends_in_its_leg_and_its_service_record'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, no run live at the twin depot ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0752 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
              WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
                AND r.status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0752 P0: a run is live at the twin depot';
  END IF;
END $inflight$;

-- ── P1: the bodies read, the probe, the trigger, the catalog, 0750, nothing of this file ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_ingest_service_complete(uuid,text,text,text[])'))
     IS DISTINCT FROM 'e64f53765109e6cad248150cc6f75bc3' THEN
    RAISE EXCEPTION '0752 P1: public.ottoq_ingest_service_complete is not the body read (md5 e64f5376)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_mark_visit_atoms_done(uuid,text[],timestamp with time zone)'))
     IS DISTINCT FROM 'be7dc4f2393b0b451543e12450f2df88' THEN
    RAISE EXCEPTION '0752 P1: public.ottoq_mark_visit_atoms_done is not the body read (md5 be7dc4f2)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_close_atom_leg(uuid,uuid,text,timestamp with time zone,timestamp with time zone)'))
     IS DISTINCT FROM 'efd2dbb8701e59a2be02500e53c03191' THEN
    RAISE EXCEPTION '0752 P1: public.ottoq_close_atom_leg is not the body read (md5 efd2dbb8)';
  END IF;
  IF to_regprocedure('public.ottoq_probe_task_completion(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION '0752 P1: public.ottoq_probe_task_completion is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.ottoq_itinerary_legs'::regclass AND t.tgname = 'trg_0043_leg_done_sdr'
                    AND t.tgfoid = 'public.ottoq_trg_leg_done_sdr()'::regprocedure AND t.tgenabled IN ('O', 'A')
                    AND pg_get_triggerdef(t.oid) LIKE '%AFTER UPDATE OF status ON public.ottoq_itinerary_legs FOR EACH ROW WHEN (((new.status = ''done''::text) AND (old.status IS DISTINCT FROM ''done''::text)))%') THEN
    RAISE EXCEPTION '0752 P1: the leg trigger is not enabled on a leg turning done';
  END IF;
  IF (SELECT count(DISTINCT leg_type) FROM public.ottoq_operation_catalog
       WHERE leg_type IN ('inspect', 'interior_tidy', 'item_retrieval', 'remote_diagnostics', 'sensor_clean',
                          'software_update', 'triage_check') AND emits_sdr) <> 7 THEN
    RAISE EXCEPTION '0752 P1: the seven leg types of the work done in place do not all issue an SDR';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0750_every_bay_seat_ends_in_its_leg_and_its_service_record')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_exit_closes_its_leg') THEN
    RAISE EXCEPTION '0752 P1: 0750 is not applied (its lineage row and its dial)';
  END IF;
  IF to_regprocedure('public.ottoq_close_reported_work_legs(uuid,uuid,text[],timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0752 P1: public.ottoq_close_reported_work_legs already exists';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0752_a_service_reported_done_ends_in_its_leg_and_its_service_record') THEN
    RAISE EXCEPTION '0752 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0752_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_ingest_service_complete(uuid,text,text,text[])'::regprocedure;

-- ── (a) the dial now names the seam ──
UPDATE public.ottoq_policy_param_catalog
   SET description = description || ' 0752 (G466): the same dial governs the production seam. At 1, each service a '
                     'robot or technician reports done in place through public.ottoq_ingest_service_complete closes its '
                     'itinerary leg, so its service record is issued, and is judged at task_completion, as the twin''s own '
                     'completion of it is; at 0 the seam marks the atoms and credits wear only, as before 0752.',
       affects = affects || ', public.ottoq_ingest_service_complete, public.ottoq_close_reported_work_legs'
 WHERE param_key = 'bay_exit_closes_its_leg';

-- ── (b) the reported work closes its legs ──
CREATE FUNCTION public.ottoq_close_reported_work_legs(p_sim_run_id uuid, p_vehicle_id uuid, p_services text[],
                                                      p_clock timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0752 (G466): a service reported done through the production seam ends as the twin's own completion of it ends: its
-- itinerary leg closed done, so the leg trigger issues its service record, and the completion judged at
-- task_completion. Called by public.ottoq_ingest_service_complete with its list, before it marks the atoms, as
-- twin.ottoq_sim_advance_visit_atoms closes and probes an atom before it stores it. Only the work done in place: a bay
-- service's seat is closed at the bay exit (0750), and a charge's leg at its session's stop. NULL with the dial off.
DECLARE
  v_depot uuid; v_atoms jsonb; v_a jsonb; v_svc text; v_started timestamptz;
  v_done_before uuid[]; v_closed uuid[]; v_in_place text[] := '{}'; v_bay text[] := '{}'; v_charge text[] := '{}';
  v_probed text[] := '{}';
BEGIN
  IF p_sim_run_id IS NULL OR p_vehicle_id IS NULL OR p_clock IS NULL OR COALESCE(cardinality(p_services), 0) = 0 THEN
    RETURN NULL;
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_exit_closes_its_leg', 0), 0) < 1 THEN
    RETURN NULL;
  END IF;
  -- the visit ottoq_mark_visit_atoms_done is about to mark, picked by its own selector
  SELECT vn.depot_id, vn.atoms INTO v_depot, v_atoms
    FROM public.ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open', 'in_progress')
     AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0
                      WHERE r0.status = 'running' AND r0.depot_id = vn.depot_id
                      ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)
   ORDER BY vn.created_at DESC LIMIT 1;
  IF v_atoms IS NULL THEN
    RETURN jsonb_build_object('legs_closed', 0, 'service_records', '[]'::jsonb, 'note', 'no open visit');
  END IF;
  SELECT COALESCE(array_agg(l.leg_id), '{}') INTO v_done_before
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = p_vehicle_id AND l.status = 'done';

  FOR v_a IN SELECT e.value FROM jsonb_array_elements(v_atoms) AS e LOOP
    v_svc := v_a ->> 'svc';
    -- the seam's own count: a reported service the visit still has outstanding
    CONTINUE WHEN v_svc IS NULL OR NOT COALESCE(v_svc = ANY (p_services), false)
               OR COALESCE(v_a ->> 'status', 'pending') IN ('done', 'cancelled');
    IF v_svc = 'charge' THEN
      v_charge := v_charge || v_svc;
      CONTINUE;
    END IF;
    IF v_svc IN ('exterior_wash', 'interior_deep_clean', 'mechanical_pm', 'sensor_calibration', 'fault_repair',
                 'cosmetic_repair') THEN
      v_bay := v_bay || v_svc;
      CONTINUE;
    END IF;
    v_in_place := v_in_place || v_svc;
    -- its start if it was started (never after the report), and none if it was not: LEAST would read a missing start
    -- as the report's own clock and record the work as taking no time
    v_started := CASE WHEN NULLIF(v_a ->> 'started_at', '') IS NOT NULL
                      THEN LEAST((v_a ->> 'started_at')::timestamptz, p_clock) END;
    PERFORM public.ottoq_close_atom_leg(p_sim_run_id, p_vehicle_id, v_svc, v_started, p_clock);
    -- the twin probes every completion but the readiness check's
    IF v_svc <> 'readiness_check' THEN
      BEGIN
        PERFORM public.ottoq_probe_task_completion(p_sim_run_id, v_depot, p_vehicle_id, v_svc, v_started, p_clock);
        v_probed := v_probed || v_svc;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '0752 task_completion probe (vehicle % svc %): % %', p_vehicle_id, v_svc, SQLSTATE, SQLERRM;
      END;
    END IF;
  END LOOP;

  SELECT COALESCE(array_agg(l.leg_id ORDER BY l.seq, l.leg_id), '{}') INTO v_closed
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = p_vehicle_id AND l.status = 'done'
     AND NOT (l.leg_id = ANY (v_done_before));
  RETURN jsonb_build_object(
    'legs_closed', cardinality(v_closed),
    'service_records', COALESCE((SELECT jsonb_agg(r.sdr_id ORDER BY r.sdr_seq)
                                   FROM public.ottoq_service_detail_records r WHERE r.leg_id = ANY (v_closed)),
                                '[]'::jsonb),
    'in_place', to_jsonb(v_in_place),
    'probed', to_jsonb(v_probed),
    'left_to_the_bay_exit', to_jsonb(v_bay),
    'left_to_the_charge', to_jsonb(v_charge));
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_close_reported_work_legs(uuid, uuid, text[], timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_close_reported_work_legs(uuid, uuid, text[], timestamptz) TO service_role;

-- ── (c) the seam ──
CREATE TEMP TABLE _0752_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0752_patch VALUES
  -- 1: the records
  (1, $o1$  v_before int; v_after int;
$o1$,
   $n1$  v_before int; v_after int;
  v_records jsonb;   -- 0752 (G466)
$n1$),
  -- 2: before the atoms are marked, the reported work closes its legs
  (2, $o2$    PERFORM ottoq_mark_visit_atoms_done(p_vehicle_id, p_services, v_clock);
$o2$,
   $n2$    -- 0752 (G466): with bay_exit_closes_its_leg on, each service reported done in place closes its itinerary leg, so
    -- the leg trigger issues its service record, and is judged at task_completion, as the twin's own completion of it
    -- is; before the atoms are marked, as the twin closes and probes an atom before storing it. Off, it returns NULL at
    -- once and nothing below changes. A failure is a warning, never the report's.
    BEGIN
      v_records := public.ottoq_close_reported_work_legs(v_run.sim_run_id, p_vehicle_id, p_services, v_clock);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0752 reported work (vehicle %): % %', p_vehicle_id, SQLSTATE, SQLERRM;
    END;
    PERFORM ottoq_mark_visit_atoms_done(p_vehicle_id, p_services, v_clock);
$n2$),
  -- 3: the event carries them
  (3, $o3$                                        'state', v_veh.current_state::text, 'source', p_source),
$o3$,
   $n3$                                        'state', v_veh.current_state::text, 'source', p_source)
                     || CASE WHEN v_records IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('records', v_records) END,
$n3$),
  -- 4: so does the reply
  (4, $o4$      'note', CASE WHEN v_before - v_after = 0 THEN 'no open workflow atoms matched the reported services' ELSE NULL END);
$o4$,
   $n4$      'note', CASE WHEN v_before - v_after = 0 THEN 'no open workflow atoms matched the reported services' ELSE NULL END)
      || CASE WHEN v_records IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('records', v_records) END;
$n4$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_ingest_service_complete(uuid,text,text,text[])'::regprocedure);
  FOR p IN SELECT * FROM _0752_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0752: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_ingest_service_complete(uuid,text,text,text[])'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0752: the seam is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched seam less its edits is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'public.ottoq_ingest_service_complete(uuid,text,text,text[])'::regprocedure;
  FOR p IN SELECT * FROM _0752_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'e64f53765109e6cad248150cc6f75bc3' THEN
    RAISE EXCEPTION '0752 V1: the seam less its edits is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: at the dial's default, and without a run, a car, a clock or a list, nothing is closed ──
DO $v2$
DECLARE v_run uuid; v_car uuid;
BEGIN
  -- a run the dial is at its default for (0750's own arm sets it for its run)
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_params pp
                      WHERE pp.scope_type = 'run' AND pp.scope_id = r.sim_run_id AND pp.param_key = 'bay_exit_closes_its_leg')
   ORDER BY r.started_at DESC LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY v.id LIMIT 1;
  IF public.ottoq_close_reported_work_legs(v_run, v_car, ARRAY['sensor_clean'], now()) IS NOT NULL
     OR public.ottoq_close_reported_work_legs(NULL, v_car, ARRAY['sensor_clean'], now()) IS NOT NULL
     OR public.ottoq_close_reported_work_legs(v_run, NULL, ARRAY['sensor_clean'], now()) IS NOT NULL
     OR public.ottoq_close_reported_work_legs(v_run, v_car, ARRAY['sensor_clean'], NULL) IS NOT NULL
     OR public.ottoq_close_reported_work_legs(v_run, v_car, ARRAY[]::text[], now()) IS NOT NULL THEN
    RAISE EXCEPTION '0752 V2: the reported work closed something at the dial''s default or without its inputs';
  END IF;
END $v2$;

-- ── V3: through the seam on live, rolled back by its own raise ──
DO $v3$
DECLARE
  v_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_t0 constant timestamptz := '2031-01-01 12:00:00+00';
  v_t1 constant timestamptz := '2031-01-01 12:20:00+00';
  v_src uuid; v_run uuid := gen_random_uuid(); v_car uuid; v_state text; v_itin uuid; v_visit uuid;
  v_clean uuid; v_update uuid; v_wash uuid; v_charge uuid; v_tidy uuid; v_reply jsonb; r record;
BEGIN
  SELECT x.sim_run_id INTO v_src FROM public.ottoq_sim_runs x
   WHERE x.depot_id = v_depot AND x.status = 'completed' ORDER BY x.started_at DESC LIMIT 1;
  SELECT v.id, v.current_state::text INTO v_car, v_state FROM public.vehicles v
   WHERE v.home_depot_id = v_depot
   ORDER BY (v.current_state::text IN ('deployed', 'en_route_to_deployment', 'offline')),
            (v.robotic_tether_until IS NOT NULL), v.id
   LIMIT 1;
  IF v_src IS NULL OR v_car IS NULL THEN
    RAISE EXCEPTION '0752 V3: no completed run or car at the twin depot to probe with';
  END IF;
  BEGIN
    INSERT INTO public.ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, depot_id, status, started_at,
                                       sim_clock_start, sim_clock_current, sim_clock_end, random_seed, run_by, policy)
    SELECT v_run, x.scenario_id, x.scenario_code, v_depot, 'running', now(), v_t0, v_t1, v_t1 + interval '1 day', 42,
           '0752_v3_probe', 'otto_q'
      FROM public.ottoq_sim_runs x WHERE x.sim_run_id = v_src;
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'bay_exit_closes_its_leg', 1, '0752 V3 probe, rolled back', now());
    IF v_state IN ('deployed', 'en_route_to_deployment', 'offline') THEN
      UPDATE public.vehicles SET current_state = 'staged_awaiting_service'::vehicle_state WHERE id = v_car;
    END IF;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status, source)
    VALUES (v_car, v_run, v_depot, v_t0, '0752_v3_probe',
            jsonb_build_array(
              jsonb_build_object('svc', 'sensor_clean', 'status', 'in_progress', 'started_at', v_t0 + interval '5 minutes'),
              jsonb_build_object('svc', 'software_update', 'status', 'pending'),
              jsonb_build_object('svc', 'exterior_wash', 'status', 'pending'),
              jsonb_build_object('svc', 'charge', 'status', 'pending'),
              jsonb_build_object('svc', 'interior_tidy', 'status', 'pending')),
            'in_progress', '0752_v3_probe')
    RETURNING visit_id INTO v_visit;
    INSERT INTO public.ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at)
    VALUES (v_run, v_depot, v_car, '0752_v3_probe', v_t0) RETURNING itinerary_id INTO v_itin;
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, planned_start_sim,
                                             planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, v_run, v_car, 1, 'sensor_clean', v_t0 + interval '5 minutes', v_t0 + interval '11 minutes', 360,
            '{"kind": "flow_contract", "atom": "sensor_clean"}'::jsonb, 'planned')
    RETURNING leg_id INTO v_clean;
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, planned_start_sim,
                                             planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, v_run, v_car, 2, 'software_update', v_t0 + interval '5 minutes', v_t0 + interval '35 minutes', 1800,
            '{"kind": "flow_contract", "atom": "software_update"}'::jsonb, 'planned')
    RETURNING leg_id INTO v_update;
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, planned_start_sim,
                                             planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, v_run, v_car, 3, 'wash', v_t0 + interval '40 minutes', v_t0 + interval '49 minutes', 540,
            '{"kind": "flow_contract", "atom": "exterior_wash"}'::jsonb, 'planned')
    RETURNING leg_id INTO v_wash;
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, planned_start_sim,
                                             planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, v_run, v_car, 4, 'charge_dcfc', v_t0 + interval '50 minutes', v_t0 + interval '90 minutes', 2400,
            '{"kind": "flow_contract", "atom": "charge"}'::jsonb, 'planned')
    RETURNING leg_id INTO v_charge;
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, planned_start_sim,
                                             planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, v_run, v_car, 5, 'interior_tidy', v_t0 + interval '50 minutes', v_t0 + interval '60 minutes', 600,
            '{"kind": "flow_contract", "atom": "interior_tidy"}'::jsonb, 'planned')
    RETURNING leg_id INTO v_tidy;

    -- the dial on: the work done in place closes its legs, each with its record; the wash and the charge wait for their doors
    v_reply := public.ottoq_ingest_service_complete(v_car, 'production', '0752 V3 probe',
                                                    ARRAY['sensor_clean', 'software_update', 'exterior_wash', 'charge']);
    IF (v_reply ->> 'atoms_matched')::int <> 4 OR (v_reply -> 'records' ->> 'legs_closed')::int <> 2
       OR v_reply -> 'records' -> 'probed' <> '["sensor_clean", "software_update"]'::jsonb
       OR v_reply -> 'records' -> 'left_to_the_bay_exit' <> '["exterior_wash"]'::jsonb
       OR v_reply -> 'records' -> 'left_to_the_charge' <> '["charge"]'::jsonb
       OR jsonb_array_length(v_reply -> 'records' -> 'service_records') <> 2 THEN
      RAISE EXCEPTION '0752 V3: the reply does not carry what the report closed (%)', v_reply;
    END IF;
    SELECT l.status, l.actual_start_sim, l.actual_end_sim INTO r FROM public.ottoq_itinerary_legs l WHERE l.leg_id = v_clean;
    IF r.status <> 'done' OR r.actual_start_sim <> v_t0 + interval '5 minutes' OR r.actual_end_sim <> v_t1 THEN
      RAISE EXCEPTION '0752 V3: the sensor clean''s leg was not closed with its start and the report (%)', row_to_json(r);
    END IF;
    SELECT l.status, l.actual_start_sim, l.actual_end_sim INTO r FROM public.ottoq_itinerary_legs l WHERE l.leg_id = v_update;
    IF r.status <> 'done' OR r.actual_start_sim IS NOT NULL OR r.actual_end_sim <> v_t1 THEN
      RAISE EXCEPTION '0752 V3: the software update''s leg was not closed at the report with no start (%)', row_to_json(r);
    END IF;
    IF (SELECT count(*) FROM public.ottoq_itinerary_legs l
         WHERE l.leg_id IN (v_wash, v_charge, v_tidy) AND l.status = 'planned') <> 3 THEN
      RAISE EXCEPTION '0752 V3: a leg the report did not close changed';
    END IF;
    SELECT d.operation_code, d.started_at, d.ended_at, d.duration_min, d.source_kind INTO r
      FROM public.ottoq_service_detail_records d WHERE d.leg_id = v_clean;
    IF r.operation_code IS DISTINCT FROM 'sensor_clean' OR r.started_at <> v_t0 + interval '5 minutes'
       OR r.ended_at <> v_t1 OR r.duration_min <> 15 OR r.source_kind <> 'itinerary_leg' THEN
      RAISE EXCEPTION '0752 V3: the sensor clean''s service record is not the report''s (%)', row_to_json(r);
    END IF;
    SELECT d.operation_code, d.started_at, d.duration_min INTO r
      FROM public.ottoq_service_detail_records d WHERE d.leg_id = v_update;
    IF r.operation_code IS DISTINCT FROM 'software_update' OR r.started_at IS NOT NULL OR r.duration_min IS NOT NULL THEN
      RAISE EXCEPTION '0752 V3: the software update''s service record is not the report''s (%)', row_to_json(r);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_events e
                    WHERE e.event_type = 'ops.services_completed_reported' AND e.entity_id = v_car
                      AND e.sim_run_id = v_run AND (e.payload -> 'records' ->> 'legs_closed')::int = 2) THEN
      RAISE EXCEPTION '0752 V3: the report''s event does not carry its records';
    END IF;

    -- the dial off: the report marks its atom, closes nothing, and its reply is today's
    UPDATE public.ottoq_policy_params SET param_value = 0
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'bay_exit_closes_its_leg';
    v_reply := public.ottoq_ingest_service_complete(v_car, 'production', '0752 V3 probe', ARRAY['interior_tidy']);
    IF (v_reply ->> 'atoms_matched')::int <> 1 OR v_reply ? 'records'
       OR (SELECT l.status FROM public.ottoq_itinerary_legs l WHERE l.leg_id = v_tidy) <> 'planned'
       OR EXISTS (SELECT 1 FROM public.ottoq_service_detail_records d WHERE d.leg_id = v_tidy) THEN
      RAISE EXCEPTION '0752 V3: with the dial off the report closed something or its reply changed (%)', v_reply;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OT752', MESSAGE = 'probe passed';
  EXCEPTION WHEN SQLSTATE 'OT752' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run)
     OR EXISTS (SELECT 1 FROM public.ottoq_visit_needs WHERE visit_key = '0752_v3_probe')
     OR EXISTS (SELECT 1 FROM public.ottoq_vehicle_itineraries WHERE created_by = '0752_v3_probe')
     OR (SELECT v.current_state::text FROM public.vehicles v WHERE v.id = v_car) IS DISTINCT FROM v_state THEN
    RAISE EXCEPTION '0752 V3: the probe left something behind';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0752_a_service_reported_done_ends_in_its_leg_and_its_service_record', false, false,
        'G466. public.ottoq_close_reported_work_legs, called by four anchored edits in the list branch of '
        'public.ottoq_ingest_service_complete before it marks the atoms: with 0750''s dial bay_exit_closes_its_leg on, each '
        'service reported done in place closes its itinerary leg through ottoq_close_atom_leg, so the leg trigger issues '
        'its SDR, and is probed at task_completion, as the twin''s own completion is; bay services and charges are left to '
        'their doors; the event and the reply carry the records. At 0 it returns NULL and the seam is byte for byte '
        'today''s (V1, V2). The twin never calls the seam, so no certification arm, canon cell, dial experiment or sweep '
        'reaches it.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:24:38 UTC (6:24 AM CT), ledger version 20261018112438 ══════════════════════════════════════
--
--   Dry-run first on live, read at 11:23:25 UTC (6:23 AM CT): the executable part in one execute_sql ending in a block
--   that raises, so it rolled back. Every premise and check passed, V3's probe run and its report through the seam
--   included, and the seam after it read 7f9dbcbe403914d46986b4216ca9ac4a. Then through apply_migration after 0750, with
--   nothing in flight and no run live at the twin depot (the file's own P0 at the apply; read after). The text sent,
--   BEGIN through COMMIT and one newline, is 24,917 characters, md5 ba0cfaad92f0884589a812059df752b6, equal to the
--   ledger's statements[1] read back; its executable part is 24,901 characters, md5 ecfe4b1637c09aa97315796defefe2b3,
--   equal to this file's. public.ottoq_ingest_service_complete is now md5 7f9dbcbe403914d46986b4216ca9ac4a (prosrc) and
--   calls public.ottoq_close_reported_work_legs; the dial's catalog description names 0752.
