-- migration-version: 20260926235621
-- migration-name:    an_inspection_closes_its_own_leg_not_the_readiness_check
--
-- 0504  **An interior inspection never closed its own itinerary leg; the car's readiness check closed it instead,
--       hours later (G232).** `db/checks/0372` §5, `db/checks/0374`.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-27 on validation run b0fdc92b) ═════════════════════════════════════════
--
--   The planner draws two kinds of `inspect` leg and tells them apart only by `duration_basis->>'atom'`: the interior
--   inspection (`interior_inspection`, a cabin task) and the readiness check the itinerary ends with
--   (`readiness_check`). `public.ottoq_close_atom_leg` finds the leg to close by `leg_type = p_svc`. So:
--
--     * when an interior inspection finished, `twin.ottoq_sim_advance_visit_atoms` asked it for a leg of type
--       `interior_inspection`, and there is none. Nothing was closed;
--     * when the readiness check finished, the same function asked for a leg of type `inspect` and got the first one
--       by `seq`, which was the interior inspection's whenever that leg was still open. The readiness leg was left to
--       be `skipped` at departure.
--
--   On b0fdc92b, of 91 done interior inspection legs, 26 were closed by the car's readiness check, 65 by the inspection
--   lane's booking, and none by the inspection. Of the 25 the lane never booked, 24 had their inspection finish a
--   median 84.8 minutes before the readiness check closed the leg (max 188.9). Those 25 read a median 67.1 minutes
--   late (20 at 30+), while their inspections started a median 0.0 minutes late (4 at 30+). Of 43 readiness checks
--   performed, 14 closed their own leg, 26 closed an interior inspection's, and 3 found no open inspect leg; 128 of
--   142 readiness legs were `skipped`. Every leg that reaches `done` issues its service detail record
--   (`trg_0043_leg_done_sdr`), so the readiness checks the record missed issued none, and the inspections it misdated
--   were settled at the readiness check's time. (The comment in the patched function says "25 of 91": the 25 without
--   a lane booking. Written before the 26th, which had one, was counted.)
--
--   This is the cause of the late inspections G232 reported. It is not the plan (0372 §5's first reading): the
--   inspections ran on time and their record was stamped by a different task.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_close_atom_leg` also takes a leg whose planner tag names the atom (`duration_basis->>'atom' = p_svc`),
--   except a bay leg (`wash`, `detail`, `service`), which stays with the service flow that opens and closes it. Every
--   leg it found before it still finds, in the same order. `ottoq_sim_advance_visit_atoms` closes the readiness
--   check's leg as `readiness_check` instead of `inspect`. Nothing else changes.
--
--   Effects beyond the record, all intended: a finished inspection's leg is no longer `planned`, so the inspection
--   seam, which only sends a car with a planned interior-inspection leg, no longer sends a car to the inspection
--   lane after its inspection is already done (about 12 of the 66 lane visits on b0fdc92b, matched by car and time
--   because re-derivation supersedes visit ids); readiness legs close and issue their records; KPI 5 counts an
--   inspection leg's real start.
--
--   Not changed: the lane's booking still closes the interior inspection leg when the lane visit ends, whether or not
--   the inspection ran there (G236).
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The leg closer runs in the certified tick: service detail records, the seam's commands and bookings, and events
--   move.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0504 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: no run is live (the tick calls both functions; V3 plants its case on a stopped run, rolled back) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0504 P1: a run is live; apply between runs';
  END IF;
END $live$;

-- ── P2: the bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure))
     <> 'f8775722838512dbd9fcd277718ad137' THEN
    RAISE EXCEPTION '0504 P2: public.ottoq_close_atom_leg is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure))
     <> '4dec883540d1b49c47b8d9c75b80adbe' THEN
    RAISE EXCEPTION '0504 P2: twin.ottoq_sim_advance_visit_atoms is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0504_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure,
                 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);

-- ── patch 1: the closer takes the leg the planner tagged with the atom ──
DO $patch1$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure);
  v_old text := $o$     AND leg_type = p_svc AND status IN ('planned','active')$o$;
  v_new text := $n$     AND (leg_type = p_svc
          /* 0504 (G232): or the leg the planner tagged with this atom. The inspection lane's two kinds of `inspect`
             leg differ only by that tag (interior_inspection, readiness_check), so the type alone never found an
             inspection's leg, and the readiness check's `inspect` closed it instead (25 of 91 on b0fdc92b, a median
             84.8 minutes after the inspection ended). Bay legs stay with the service flow that opens and closes them. */
          OR (duration_basis->>'atom' = p_svc AND leg_type NOT IN ('wash','detail','service')))
     AND status IN ('planned','active')$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0504: the closer''s leg match matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch1$;

-- ── patch 2: the readiness check closes its own leg ──
DO $patch2$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  v_old text := $o$        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, 'inspect',$o$;
  v_new text := $n$        -- 0504 (G232): its own leg, by its atom. 'inspect' took whichever inspect leg came first, which
        -- was the interior inspection's whenever that one was still open.
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, 'readiness_check',$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0504: the readiness close matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch2$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_close regprocedure := 'public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure;
  v_adv   regprocedure := 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure;
  v_cdef  text := pg_get_functiondef('public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure);
  v_adef  text := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
BEGIN
  -- V1: the closer matches the tag outside the bays, once; the tick closes the readiness leg by its atom, and its two
  -- other calls still pass the atom's own svc.
  IF position('OR (duration_basis->>''atom'' = p_svc AND leg_type NOT IN (''wash'',''detail'',''service'')))' IN v_cdef) = 0
     OR position('AND leg_type = p_svc AND' IN v_cdef) > 0
     OR (length(v_adef) - length(replace(v_adef, 'ottoq_close_atom_leg(', ''))) / length('ottoq_close_atom_leg(') <> 3
     OR (length(v_adef) - length(replace(v_adef, 'ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>''svc'',', '')))
          / length('ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>''svc'',') <> 2
     OR position('ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, ''readiness_check'',' IN v_adef) = 0
     OR position('ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, ''inspect''' IN v_adef) > 0 THEN
    RAISE EXCEPTION '0504 V1: the closer or the tick is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer and search path kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_close)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_close)
          <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_close) <> 'search_path=twin, ottoq, public, extensions'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_adv)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_adv) <> 'postgres=X/postgres,service_role=X/postgres'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_adv) <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0504 V2: a patched function''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: the case, planted on the newest stopped operator run and rolled back. One car's open legs are set aside and
-- four are planted in one of its itineraries: an interior tidy (a leg whose type is its atom, the control that must
-- behave as before), the interior inspection, the readiness check, and a wash (a bay leg, which must stay open). Each
-- atom's completion is replayed through the closer in the order the tick meets them.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_clock timestamptz; v_itin uuid; v_car uuid;
  v_tidy uuid; v_insp uuid; v_ready uuid; v_wash uuid; l record;
  v_depot uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  BEGIN
    SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.validation_status IS NULL AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0504 V3 FAILED: no stopped operator run to plant on'; END IF;
    SELECT i.itinerary_id, i.vehicle_id INTO v_itin, v_car FROM public.ottoq_vehicle_itineraries i
     WHERE i.sim_run_id = v_run ORDER BY i.itinerary_id LIMIT 1;
    IF v_itin IS NULL THEN RAISE EXCEPTION '0504 V3 FAILED: the run has no itinerary'; END IF;
    UPDATE public.ottoq_itinerary_legs SET status = 'skipped'
     WHERE sim_run_id = v_run AND vehicle_id = v_car AND status IN ('planned','active');
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
                                             planned_start_sim, planned_end_sim, planned_duration_s, duration_basis)
    VALUES (v_itin, v_run, v_car, 9001, 'interior_tidy', v_clock + interval '5 minutes', v_clock + interval '10 minutes', 300,
            '{"atom":"interior_tidy"}'),
           (v_itin, v_run, v_car, 9002, 'inspect', v_clock + interval '10 minutes', v_clock + interval '14 minutes', 240,
            '{"atom":"interior_inspection"}'),
           (v_itin, v_run, v_car, 9003, 'wash', v_clock + interval '20 minutes', v_clock + interval '32 minutes', 720,
            '{"atom":"exterior_wash"}'),
           (v_itin, v_run, v_car, 9004, 'inspect', v_clock + interval '60 minutes', v_clock + interval '63 minutes', 180,
            '{"atom":"readiness_check"}');
    SELECT leg_id INTO v_tidy  FROM public.ottoq_itinerary_legs WHERE itinerary_id = v_itin AND seq = 9001;
    SELECT leg_id INTO v_insp  FROM public.ottoq_itinerary_legs WHERE itinerary_id = v_itin AND seq = 9002;
    SELECT leg_id INTO v_wash  FROM public.ottoq_itinerary_legs WHERE itinerary_id = v_itin AND seq = 9003;
    SELECT leg_id INTO v_ready FROM public.ottoq_itinerary_legs WHERE itinerary_id = v_itin AND seq = 9004;

    -- the inspection ends first: its own leg closes with its own times, and nothing else does
    PERFORM public.ottoq_close_atom_leg(v_run, v_car, 'interior_inspection', v_clock + interval '2 minutes',
                                        v_clock + interval '6 minutes');
    SELECT * INTO l FROM public.ottoq_itinerary_legs WHERE leg_id = v_insp;
    IF l.status <> 'done' OR l.actual_start_sim <> v_clock + interval '2 minutes'
       OR l.actual_end_sim <> v_clock + interval '6 minutes' THEN
      RAISE EXCEPTION '0504 V3 FAILED: the inspection''s leg reads % % %', l.status, l.actual_start_sim, l.actual_end_sim;
    END IF;
    IF (SELECT count(*) FROM public.ottoq_itinerary_legs WHERE leg_id IN (v_tidy, v_wash, v_ready) AND status = 'planned') <> 3 THEN
      RAISE EXCEPTION '0504 V3 FAILED: the inspection closed a leg that was not its own';
    END IF;

    -- the control: a leg whose type is its atom closes as before
    PERFORM public.ottoq_close_atom_leg(v_run, v_car, 'interior_tidy', v_clock + interval '3 minutes',
                                        v_clock + interval '8 minutes');
    -- a bay atom's svc never closes a bay leg here
    PERFORM public.ottoq_close_atom_leg(v_run, v_car, 'exterior_wash', v_clock + interval '20 minutes',
                                        v_clock + interval '30 minutes');
    -- the readiness check ends last and closes its own leg, as the tick now calls it
    PERFORM public.ottoq_close_atom_leg(v_run, v_car, 'readiness_check', v_clock + interval '57 minutes',
                                        v_clock + interval '60 minutes');

    IF (SELECT status FROM public.ottoq_itinerary_legs WHERE leg_id = v_tidy) <> 'done'
       OR (SELECT status FROM public.ottoq_itinerary_legs WHERE leg_id = v_wash) <> 'planned'
       OR (SELECT status FROM public.ottoq_itinerary_legs WHERE leg_id = v_ready) <> 'done'
       OR (SELECT actual_end_sim FROM public.ottoq_itinerary_legs WHERE leg_id = v_ready) <> v_clock + interval '60 minutes'
       OR (SELECT actual_end_sim FROM public.ottoq_itinerary_legs WHERE leg_id = v_insp) <> v_clock + interval '6 minutes' THEN
      RAISE EXCEPTION '0504 V3 FAILED: tidy %, wash %, readiness %',
        (SELECT status FROM public.ottoq_itinerary_legs WHERE leg_id = v_tidy),
        (SELECT status FROM public.ottoq_itinerary_legs WHERE leg_id = v_wash),
        (SELECT status FROM public.ottoq_itinerary_legs WHERE leg_id = v_ready);
    END IF;
    -- each closed leg issued its service detail record, the inspection's at the inspection's time
    IF (SELECT count(*) FROM public.ottoq_service_detail_records WHERE leg_id IN (v_tidy, v_insp, v_ready)) <> 3 THEN
      RAISE EXCEPTION '0504 V3 FAILED: % service detail records for the three closed legs',
        (SELECT count(*) FROM public.ottoq_service_detail_records WHERE leg_id IN (v_tidy, v_insp, v_ready));
    END IF;
    RAISE EXCEPTION '0504 V3 PASSED: inspection, readiness and tidy legs each closed by their own atom; the wash left open';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0504 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0504 V3: no verdict'); END IF;
END $v3$;

-- Rollback: restore public.ottoq_close_atom_leg and twin.ottoq_sim_advance_visit_atoms from ottoq_schema_snapshots
-- label '0504_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0504_an_inspection_closes_its_own_leg_not_the_readiness_check', true,
  'ottoq_close_atom_leg also takes the leg the planner tagged with the atom (duration_basis->>''atom''), bays excepted, '
  'and the tick closes the readiness check''s leg as readiness_check, not inspect. An interior inspection closes its own '
  'leg with its own times; readiness legs close and issue their SDRs; the seam no longer sends a car whose inspection '
  'is done. SDRs, seam commands, bookings and events move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
