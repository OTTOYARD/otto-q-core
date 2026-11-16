-- migration-version: PENDING
-- migration-name:    0841_a_visit_made_with_no_run_id_carries_what_the_visit_it_replaces_still_owes
--
-- 0841  **A new visit made by a caller that passes no run id carries the required work the visit it replaces still
--        owes. The wash triage no longer drops an arm's deep clean that is under way, and the car no longer leaves
--        without it.** (G552; CLAUDE.md rule 9: "vehicles cannot leave the depot with any remaining service still
--        needed, EVER.")
--
-- WHY. db/checks/0496 (G552), found reading the clean arms' records for 0840's canopy boards: on runs 5ea96a57 and
--   6f9a1b0e, 4 cars each left the depot with a required interior deep clean not done. Each clean had been started by
--   an arm on a cabin-stop visit; the car's visit was then replaced, the new visit did not have the clean, and the
--   departure test reads the live visit. The cars came back for it 1.5 to 5 hours later. Chase, 2026-11-16: "Sure, keep
--   building what you see necessary."
--
-- §1 WHAT WAS SO (read 2026-11-16, production, twin depot).
--   ottoq.ottoq_derive_visit_needs supersedes every open or in-progress visit of the car (unscoped) and inserts the new
--   one under v_run (= p_run, the run its caller resolved). 0698 (G413) made it carry, onto the new visit, every
--   required atom those visits still owe "on THIS run", and it matches the run against the caller's p_sim_run_id as
--   passed. 0200's header recorded that gap and left it open on purpose: "a NULL-run caller (wash triage) can never
--   consume a carryover ... both are named so they can be closed on purpose." 0698 copied the same scope.
--   twin.ottoq_sim_wash_triage calls twin.ottoq_sim_generate_service_manifest(car, NULL, NULL), which resolves the live
--   run as p_run and passes p_sim_run_id NULL to the deriver. So on that path the carry looks for owed work on visits
--   with no run, finds none, and the supersede closes the car's visit anyway.
--   The cabin stop (ottoq_cabin_stop_mark, 0817) opens a visit of its own for a car with no open visit, holding only
--   the deep clean; the arm starts it; a wash triage then derives the car's next visit. Read on the three runs still in
--   the database: the required work left on superseded visits that have a next visit is only interior deep cleans
--   (12, 11 and 6 on runs 5ea96a57, 6f9a1b0e and bf447eb4); the next visit lacked the clean 4, 4 and 3 times; the
--   carry moved none on any run.
--   A probe on production, rolled back (the same as V3 below): with the body as it was, nothing was carried, and once
--   the new visit's own work was done the departure test let the car leave; with this file's line, the deep clean was
--   carried, still under way, and the departure test held the car.
--
-- §2 WHAT THIS DOES. One line of the deriver: the carry matches the old visits' run against
--   COALESCE(p_sim_run_id, v_run, zero) instead of COALESCE(p_sim_run_id, zero). v_run is the run the new visit's row
--   is written under; it is set from p_run when declared and never reassigned. A caller that passes its run id carries
--   exactly as before, and so does production, where both are NULL. The 'carried_over' block (0193's scope) and the
--   unscoped supersede stay as 0200 recorded them.
--   Downstream, nothing new: a carried arm atom that is under way stays under way on the new visit. If its car is
--   still on the post at its end, it is done (the atom advancer's completion); if the car has left the post, it goes
--   back to pending for a technician or another post's arm (0758, 0815). public.ottoq_departure_clear holds the car
--   while it is open (0543).
--   Rule 9: the car does not leave with it. Rule 10: no setting; it is a defect closed. Rule 12: one demo run to see
--   it working; no pair, no sweep. Rule 14: no car's place in any line changes.
--
-- §3 PRECONDITIONS AND CHECKS. P0 no certification in flight and no live run at the twin depot. P1 the deriver's body
--   (md5 of prosrc). P2 once.
--   V1 the patched definition with the patch reversed is the snapshot. V2 the anchor matched once, and the stored
--   definition is the patched one.
--   V3 a probe, rolled back, on the twin depot's newest finished run: a car at 100% charge has a cabin-stop visit whose
--   arm deep clean is under way; the deriver is called with no run id, as the wash triage calls it; the new visit's own
--   work is marked done. V3a, before the patch: nothing is carried and the car may leave (the defect, reproduced).
--   V3b, after it: the deep clean is carried, under way, and the car may not leave.
--
-- §4 CLASSIFICATION. forces_recert TRUE: on the twin's wash-triage path a visit now carries required work it used to
--   drop, and the decisions that read visits follow. forces_dial_restart FALSE.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0841_pre'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name LIKE '0841_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0841 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') THEN
    RAISE EXCEPTION '0841 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'))
     IS DISTINCT FROM '1c0bbc70a8391d6c4c2afbd4c69dfa3c' THEN
    RAISE EXCEPTION '0841 P1: ottoq.ottoq_derive_visit_needs is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0841_%') THEN RAISE EXCEPTION '0841 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0841_pre', 'function', 'ottoq', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)']) AS f;

CREATE TEMP TABLE _0841_patch (c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0841_patch VALUES (
$o1$       AND COALESCE(o.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
$o1$,
$n1$       AND COALESCE(o.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         -- 0841 (G552, rule 9): a caller that passes no run id (the wash triage) still carries what this run's
         -- visits owe: the run is the one the new visit's row is written under
         = COALESCE(p_sim_run_id, v_run, '00000000-0000-0000-0000-000000000000'::uuid)
$n1$);

-- V3: the probe. It runs inside its own block and raises to roll its writes back; the answer comes back as the
-- exception's detail.
CREATE FUNCTION pg_temp._0841_probe() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_car uuid; v_stall uuid; v_clock timestamptz := '2099-01-01 00:00:00+00'; v_key text; v_r jsonb; v_detail text;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs WHERE depot_id = c_depot AND status = 'completed'
   ORDER BY started_at DESC LIMIT 1;
  SELECT id INTO v_car FROM public.vehicles WHERE home_depot_id = c_depot ORDER BY id LIMIT 1;
  SELECT id INTO v_stall FROM public.stalls WHERE depot_id = c_depot AND stall_type::text = 'dcfc' ORDER BY id LIMIT 1;
  IF v_run IS NULL OR v_car IS NULL OR v_stall IS NULL THEN RAISE EXCEPTION '0841 V3: no run, car or post to probe with'; END IF;
  v_key := v_car::text || ':0841probe';
  BEGIN
    UPDATE public.vehicles SET current_soc = 100 WHERE id = v_car;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency, atoms,
                                          status, source, meta)
    VALUES (v_car, v_run, c_depot, v_clock, v_key, 'C_cabin_stop', 'standard',
            jsonb_build_array(jsonb_build_object('svc', 'interior_deep_clean', 'must_do', true, 'deferrable', false,
              'status', 'in_progress', 'performed_by', 'stall_cabin_robot', 'robot_stall_id', v_stall,
              'started_at', v_clock, 'ends_at', v_clock + interval '10 minutes 48 seconds', 'raised_in_depot', true)),
            'open', 'cabin_post_stop', '{"generator":"0841 V3"}');
    -- as the wash triage calls it: no run id, the run resolved by the caller
    PERFORM ottoq.ottoq_derive_visit_needs(v_car, NULL, v_run, v_clock + interval '3 minutes', c_depot, '{}'::jsonb);
    -- the new visit's own work all finishes; only what was carried can still hold the car
    UPDATE public.ottoq_visit_needs n
       SET atoms = (SELECT jsonb_agg(CASE WHEN COALESCE((a->>'carried')::boolean, false) THEN a
                                          ELSE a || jsonb_build_object('status', 'done', 'done_at', v_clock + interval '5 minutes') END)
                      FROM jsonb_array_elements(n.atoms) a)
     WHERE n.vehicle_id = v_car AND n.sim_run_id = v_run AND n.status = 'open';
    v_r := jsonb_build_object(
      'old_visit', (SELECT status FROM public.ottoq_visit_needs WHERE visit_key = v_key AND sim_run_id = v_run),
      'carried', (SELECT COALESCE(jsonb_agg(jsonb_build_object('svc', a->>'svc', 'status', a->>'status')), '[]'::jsonb)
                    FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                   WHERE n.vehicle_id = v_car AND n.sim_run_id = v_run AND n.status = 'open' AND (a->>'carried')::boolean),
      'may_leave', public.ottoq_departure_clear(v_car, v_run, v_clock + interval '6 minutes', false));
    RAISE EXCEPTION USING ERRCODE = 'OQ841', MESSAGE = '0841 V3 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ841' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

DO $v3a$
DECLARE v_r jsonb := pg_temp._0841_probe();
BEGIN
  IF (v_r->>'old_visit') IS DISTINCT FROM 'superseded' OR COALESCE(jsonb_array_length(v_r->'carried'), -1) <> 0
     OR NOT COALESCE((v_r->>'may_leave')::boolean, false) THEN
    RAISE EXCEPTION '0841 V3a: the defect did not reproduce on the body as it was: %', v_r;
  END IF;
END $v3a$;

DO $patch$
DECLARE p record; v_def text; v_old text; n int;
BEGIN
  SELECT * INTO p FROM _0841_patch;
  v_old := pg_get_functiondef(to_regprocedure('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'));
  n := (length(v_old) - length(replace(v_old, p.c_old, ''))) / length(p.c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0841 V2: the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_old, p.c_old, p.c_new);
  EXECUTE v_def;
  IF pg_get_functiondef(to_regprocedure('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)')) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0841 V2: the deriver is not stored as patched';
  END IF;
  -- V1: the patch reversed is the snapshot
  IF md5(replace(v_def, p.c_new, p.c_old)) IS DISTINCT FROM
     (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0841_pre' ORDER BY snapshot_id DESC LIMIT 1) THEN
    RAISE EXCEPTION '0841 V1: the patched definition with the patch reversed is not the snapshot';
  END IF;
END $patch$;

DO $v3b$
DECLARE v_r jsonb := pg_temp._0841_probe();
BEGIN
  IF (v_r->>'old_visit') IS DISTINCT FROM 'superseded'
     OR NOT COALESCE((v_r->'carried') @> '[{"svc": "interior_deep_clean", "status": "in_progress"}]'::jsonb, false)
     OR COALESCE((v_r->>'may_leave')::boolean, true) THEN
    RAISE EXCEPTION '0841 V3b: the deep clean was not carried, or the car may leave: %', v_r;
  END IF;
  RAISE NOTICE '0841 V3b: %', v_r;
END $v3b$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0841_a_visit_made_with_no_run_id_carries_what_the_visit_it_replaces_still_owes', true, false,
        'G552 (rule 9): the deriver''s 0698 carry matches the run the new visit is written under when its caller passes '
        || 'no run id (the wash triage), so an arm''s deep clean under way is no longer dropped and the car is held until '
        || 'it is done. One line; the deriver''s pre-image is 0841_pre.', now());
COMMIT;
