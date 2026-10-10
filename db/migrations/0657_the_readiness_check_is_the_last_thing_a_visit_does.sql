-- migration-version: 20261010112938
-- migration-name:    the_readiness_check_is_the_last_thing_a_visit_does
--
-- 0657  **A visit's readiness check closes only when every other atom of the visit is done.** (G398; db/checks/0431
--        §4.) The readiness check is the last step of every visit: it confirms the car is fit to leave. It could close
--        before the work it confirms.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   twin.ottoq_sim_advance_visit_atoms closes a pending readiness_check when the car is staged_for_departure, or
--   staged_awaiting_service with config svc_step 'ready', and reads a car with no svc_step as 'ready'. It never asks
--   whether the visit's other atoms are done. Measured (0431 (6), (7)): on the operator door's first pair, 115 of the
--   treatment arm's 150 readiness checks closed before their visit's other required work, about 3 minutes after the
--   car came back (the operators stage a car at the start of a beat, before the world gives it a svc_step); 0 of the
--   control's 83. With the door off it was already there: 411 of 18,349 checks (2.2%) on 182 earlier twin-depot runs,
--   252 of 1,367 (18.4%) on operator demo runs. No car left early because of it (ottoq_departure_clear reads every
--   atom on its own), but a check done before the work means nothing, and KPI 5 read the early leg as fast service.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   twin.ottoq_sim_advance_visit_atoms, patched at one anchor between md5s of the live definition
--   (911bd88b7ff9a121ebf615387520d3c6 before, f073e5be363fea71d436c34d790ff610 after): the readiness branch also needs
--   every other atom of the visit done or cancelled, as ottoq_departure_clear reads them, or finishing in the same pass
--   by the branch above it (an in-progress atom whose ends_at has come, unless the charger's sensors lost the car). So
--   a check whose visit's last work finishes now still closes now, as before. A triage check finishing in the same
--   pass is waited for, one pass, since what triage finds is added after the loop.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ══════════════════════════════════════════════════════════════
--
--   It changes the twin's world with the operator door off too: about 2.2% of readiness checks close later, and a
--   departure that waited on one can move. Every certified digest that a departure reaches can move, so the canon
--   recertifies and dial experiments restart their count, as 0573, 0591 and 0642 did.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0657_pre'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0657 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0656_the_research_wing_measures_the_operator_door_in_the_twin') THEN
    RAISE EXCEPTION '0657 P1: 0656 is not classified; apply in order';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)) <> '911bd88b7ff9a121ebf615387520d3c6' THEN
    RAISE EXCEPTION '0657 P1: twin.ottoq_sim_advance_visit_atoms is not the definition this file patches';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0657 P1: a run is live; the world changes between runs';
  END IF;
END $premises$;

-- ── snapshot: the definition as it stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0657_pre', 'function', 'twin', 'ottoq_sim_advance_visit_atoms(uuid,timestamptz)', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure) AS def) d;

-- ── a probe visit, run through the function before and after the patch (each in a sub-block that rolls back) ──
CREATE TEMP TABLE p0657 (phase text PRIMARY KEY, atoms text) ON COMMIT DROP;

CREATE FUNCTION pg_temp.p0657_probe(p_phase text, p_charge jsonb) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_twin uuid := '11111111-1111-1111-1111-111111111111'; v_run uuid; v_clock timestamptz; v_car uuid; v_visit uuid;
  v_atoms text; v_msg text;
BEGIN
  SELECT sim_run_id, COALESCE(sim_clock_current, started_at) INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = v_twin AND COALESCE(run_by, '') <> 'production_live' AND status <> 'running'
   ORDER BY started_at DESC LIMIT 1;
  SELECT id INTO v_car FROM public.vehicles
   WHERE home_depot_id = v_twin AND fleet_operator_id IS NOT NULL ORDER BY display_name LIMIT 1;
  IF v_run IS NULL OR v_car IS NULL THEN RAISE EXCEPTION '0657 probe: no stopped twin run or no fleet car'; END IF;
  BEGIN
    -- a car staged with no svc_step: the state the operator door left a just-returned car in
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_stall_id = NULL,
           config = COALESCE(config, '{}'::jsonb) - 'svc_step' WHERE id = v_car;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency,
                                          target_soc, atoms, status, source, meta)
    VALUES (v_car, v_run, v_twin, v_clock - interval '1 hour', 'probe0657:' || p_phase, 'probe', 'standard', 100,
            jsonb_build_array(
              CASE WHEN p_charge IS NULL THEN jsonb_build_object('svc', 'charge', 'status', 'pending', 'must_do', true)
                   ELSE p_charge || jsonb_build_object('svc', 'charge', 'must_do', true,
                                                       'started_at', v_clock - interval '30 minutes',
                                                       'ends_at', v_clock - interval '1 minute') END,
              jsonb_build_object('svc', 'readiness_check', 'status', 'pending', 'must_do', true)),
            'open', 'probe_0657', '{}'::jsonb)
    RETURNING visit_id INTO v_visit;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_clock);
    SELECT string_agg((x ->> 'svc') || ':' || COALESCE(x ->> 'status', 'pending'), ',' ORDER BY x ->> 'svc')
      INTO v_atoms FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x WHERE vn.visit_id = v_visit;
    RAISE EXCEPTION '0657 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0657 PROBED' THEN RAISE EXCEPTION '0657 probe % failed: %', p_phase, v_msg; END IF;
  INSERT INTO p0657 VALUES (p_phase, v_atoms);
END $fn$;

-- ── P2: the defect, on the live function: a staged car's readiness check closes while its charge is pending ──
DO $p2$
BEGIN
  PERFORM pg_temp.p0657_probe('before', NULL);
  IF (SELECT atoms FROM p0657 WHERE phase = 'before') IS DISTINCT FROM 'charge:pending,readiness_check:done' THEN
    RAISE EXCEPTION '0657 P2: the live function did not close the readiness check early (%); this file''s premise is wrong',
      (SELECT atoms FROM p0657 WHERE phase = 'before');
  END IF;
END $p2$;

-- ── the readiness check waits for the rest of its visit ──
DO $p_atoms$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  a text[] := ARRAY[$a01$      ELSIF v_a->>'svc' = 'readiness_check' AND COALESCE(v_a->>'status','pending') = 'pending'
         AND (v_rec.current_state = 'staged_for_departure'
              OR (v_rec.current_state = 'staged_awaiting_service' AND v_rec.svc_step IN ('ready'))) THEN   /* 0437 */
$a01$];
  b text[] := ARRAY[$b01$      ELSIF v_a->>'svc' = 'readiness_check' AND COALESCE(v_a->>'status','pending') = 'pending'
         AND (v_rec.current_state = 'staged_for_departure'
              OR (v_rec.current_state = 'staged_awaiting_service' AND v_rec.svc_step IN ('ready')))   /* 0437 */
         -- 0657 (G398): the readiness check is the LAST atom of its visit. Every other atom is done or cancelled, as
         -- ottoq_departure_clear reads them, or finishes in this very pass by the branch above (read off the visit as
         -- the pass began; a triage check that finishes now is waited for, since what it finds is added after this
         -- loop). A car staged before its work is done, or with no svc_step yet, no longer has its check closed for it.
         AND NOT EXISTS (
               SELECT 1 FROM jsonb_array_elements(v_rec.atoms) o
                WHERE o->>'svc' <> 'readiness_check'
                  AND COALESCE(o->>'status','pending') NOT IN ('done','cancelled')
                  AND NOT COALESCE(v_feed_sim AND o->>'svc' <> 'triage_check'
                                   AND o->>'status' = 'in_progress' AND (o->>'ends_at')::timestamptz <= p_clock
                                   AND NOT (COALESCE(o->>'performed_by','') = 'charger_sensors'
                                            AND o->>'sensor_stall_id' IS NOT NULL
                                            AND v_rec.current_stall_id IS DISTINCT FROM (o->>'sensor_stall_id')::uuid),
                                   false)) THEN
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '911bd88b7ff9a121ebf615387520d3c6' THEN
    RAISE EXCEPTION '0657: the visit-atom advancer is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0657: anchor % of the visit-atom advancer occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'f073e5be363fea71d436c34d790ff610' THEN
    RAISE EXCEPTION '0657: the visit-atom advancer, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)) <> 'f073e5be363fea71d436c34d790ff610' THEN
    RAISE EXCEPTION '0657: the visit-atom advancer did not read back as written';
  END IF;
END $p_atoms$;

-- ── V1: the same car, patched: the check waits for a pending charge, and closes in the pass its last work ends ──
DO $v1$
BEGIN
  PERFORM pg_temp.p0657_probe('after', NULL);
  PERFORM pg_temp.p0657_probe('finishing', jsonb_build_object('status', 'in_progress'));
  IF (SELECT atoms FROM p0657 WHERE phase = 'after') IS DISTINCT FROM 'charge:pending,readiness_check:pending' THEN
    RAISE EXCEPTION '0657 V1 FAILED: with the charge pending the check did not wait: %', (SELECT atoms FROM p0657 WHERE phase = 'after');
  END IF;
  IF (SELECT atoms FROM p0657 WHERE phase = 'finishing') IS DISTINCT FROM 'charge:done,readiness_check:done' THEN
    RAISE EXCEPTION '0657 V1 FAILED: the check did not close in the pass its last work ended: %', (SELECT atoms FROM p0657 WHERE phase = 'finishing');
  END IF;
  RAISE NOTICE '0657 V1 PASSED: before [%], after [%], last work ending this pass [%]; all rolled back',
    (SELECT atoms FROM p0657 WHERE phase = 'before'), (SELECT atoms FROM p0657 WHERE phase = 'after'),
    (SELECT atoms FROM p0657 WHERE phase = 'finishing');
END $v1$;

-- ── V2: the definition as written, and no probe visit left ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)) <> 'f073e5be363fea71d436c34d790ff610' THEN
    RAISE EXCEPTION '0657 V2 FAILED: the visit-atom advancer is not as written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs WHERE source = 'probe_0657') THEN
    RAISE EXCEPTION '0657 V2 FAILED: a probe visit outlived its rollback';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0657_the_readiness_check_is_the_last_thing_a_visit_does', true, true,
  'G398 (db/checks/0431 §4): twin.ottoq_sim_advance_visit_atoms closes a readiness check only when every other atom of '
  'its visit is done or cancelled, or finishes in the same pass (a triage check finishing now is waited for). It closed '
  'before the work in 2.2% of checks with the operator door off and in 77% of the door''s first pair. Changes the twin''s '
  'world with the door off: TRUE/TRUE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 11:29:38 UTC (6:29 AM CT), version 20261010112938 ═════════════════════════════════════════════
--   Claude, MCP apply_migration, the file as committed in 9eeaa49; the ledger's stored statement is that file byte for
--   byte (md5 0b1b478be3ff895867f3a0e01e92d73f, 12,760 characters, 13,556 bytes). P1, V1, V2 passed in the apply's
--   transaction. Read after: the visit-atom advancer's definition md5 f073e5be363fea71d436c34d790ff610 as written; no
--   probe visit left; lineage TRUE/TRUE, so the recert floor moved to 11:29:38 UTC and all 9 enabled canon columns
--   read unsatisfied (read 11:29:45 UTC). The recert runner, cron job 746, was paused at 11:29:00 UTC so that 0657,
--   0696 and 0698 ride one recertification.
