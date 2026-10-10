-- migration-version: PENDING
-- migration-name:    a_new_visit_carries_the_work_the_visit_it_replaces_still_owes
--
-- 0698  **A new visit carries the required work the visit it replaces still owes the car; nothing found is dropped.**
--        (G413; CLAUDE.md rule 9, Chase 2026-09-27: "vehicles cannot leave the depot with any remaining service still
--        needed, EVER.") Found 2026-10-10 reading G399's labels, db/checks/0435.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq.ottoq_derive_visit_needs builds a car's new visit from what it observes now, then supersedes every open or
--   in-progress visit of the car (its "unscoped supersede", RECORDED in its header) and inserts the new one. The only
--   work it takes from an older visit is from a 'carried_over' one. Work still owed on an OPEN visit goes with the
--   supersede.
--
--   Where that bites, measured on the twin depot's runs since 0543 (0435 (1)-(4)): a rider's cleaning report that comes
--   due while the car is parked is put on a visit of its own by ottoq.ottoq_rider_flag_indepot_sweep (the flag is then
--   consumed, so the deriver's own rider-flag branch, which reads only 'pending' and 'recalled' flags, never sees it
--   again). When the twin then derives a new visit for the car, that visit carries only the new visit's work, which
--   finishes; ottoq_departure_clear reads the new visit and clears the car. 44 such visits were superseded with their
--   cleaning still owed; 39 of those cars then left; in 24 the cleaning was done anyway by the twin's service flow, and
--   15 left with no record of it (twin.service_completed crediting it between the report and the departure): 13 interior
--   deep cleans and 2 exterior washes, all on busy_day (171 of the 184 runs). Those are 15 runs and 7 distinct cars,
--   since pair arms replay one world (G153), so they are not 15 independent observations.
--   The car traced end to end (0435 (4); the run's sim clock, in CT): the report opened its visit at 9:09 AM, the twin
--   derived a pass-through visit at 9:51 AM whose own meta reads rider_flag_kind 'interior', its four quick atoms
--   closed, and the car left at 9:59 AM uncleaned.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   The deriver, at one anchor (just before it names the visit's archetype): every required atom (must_do) that an open
--   or in-progress visit of the car on THIS run still owes (status neither done nor cancelled) is added to the new
--   visit, as it stood, with carried true and carried_from_visit (the old visit's key), unless the new visit already has
--   that service. In the order the old visits arrived (sim clock), then their keys, then the atoms' order: all three
--   deterministic, so a pair's arms carry the same atoms in the same order (a visit id is random and is not used).
--   Not carried, and why:
--     - the charge and the readiness check: the deriver sets both afresh from the car as it is now, and
--       ottoq_departure_clear checks the charge against the owner's target on its own;
--     - an atom the guard tagged as not required (ottoq_atoms_guard's no-executor demotion): carrying a task nothing
--       can perform would hold the car forever; that gap is the guard's to report, not this file's;
--     - another run's open visit: the supersede is unscoped, the carry is not.
--   The new visit's readiness check then waits for the carried work (0657), and the departure test reads it.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════
--
--   It changes the twin's world with every flag off: a car whose rider report landed on a superseded visit now waits
--   for its cleaning before it leaves (44 such visits in the 184 twin-depot runs since 0543, 0435 (2)), and that moves
--   every digest downstream of a departure. Written to ride the recertification and the restart 0657 and 0696 force the same
--   morning, applied after 0696.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0698_pre'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0698 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0696_the_twins_roads_crash_at_the_filed_rate_and_the_cold_is_counted_once') THEN
    RAISE EXCEPTION '0698 P1: 0696 is not classified; apply in order';
  END IF;
  IF to_regprocedure('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)') IS NULL THEN
    RAISE EXCEPTION '0698 P1: ottoq.ottoq_derive_visit_needs does not exist';
  END IF;
  IF md5(pg_get_functiondef(to_regprocedure('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)')))
       <> '9ae0558f6a6ce8ca6d14ba3b9dc3c28b' THEN
    RAISE EXCEPTION '0698 P1: the deriver is not the definition 0695 left, which this file patches';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0698 P1: a run is live; the world changes between runs';
  END IF;
END $premises$;

-- ── snapshot: the definition as it stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0698_pre', 'function', 'ottoq', 'ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure) AS def) d;

-- ── a probe: a car with a visit still owing work, a new visit derived over it (each in a sub-block that rolls back) ──
CREATE TEMP TABLE p0698 (phase text PRIMARY KEY, r jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.p0698_probe(p_phase text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_other uuid; v_clock timestamptz; v_veh uuid; v_same uuid; v_atoms jsonb; v_r jsonb; v_msg text;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = v_twin AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  SELECT r.sim_run_id INTO v_other
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = v_twin AND r.status = 'completed' AND r.sim_run_id IS DISTINCT FROM v_run
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  SELECT v.id INTO v_veh FROM public.vehicles v
   WHERE v.home_depot_id = v_twin AND v.category = 'autonomous' AND v.fleet_operator_id IS NOT NULL
   ORDER BY v.display_name LIMIT 1;
  IF v_run IS NULL OR v_other IS NULL OR v_veh IS NULL THEN
    RAISE EXCEPTION '0698 probe: no two stopped twin runs or no autonomous fleet car';
  END IF;
  v_clock := v_clock + interval '1 hour 7 minutes 13 seconds';   -- a second no visit of the run is keyed on
  BEGIN
    UPDATE public.vehicles SET current_soc = 100, current_state = 'arrived_at_gate', current_stall_id = NULL,
           robotic_tether_until = NULL, last_state_change = v_clock
     WHERE id = v_veh;
    -- the visit the car is having on this run, as the in-depot rider sweep leaves one: a rider's cleaning and a
    -- calibration owed, a tidy done, a charge and a readiness check pending; each atom marked so it can be found again
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency,
                                          target_soc, atoms, status, source, meta)
    VALUES (v_veh, v_run, v_twin, v_clock - interval '40 minutes', 'probe0698:same', 'probe', 'standard', 100,
            jsonb_build_array(
              jsonb_build_object('svc', 'interior_deep_clean', 'must_do', true, 'deferrable', false, 'est_min', 35,
                                 'concurrency', 'bay', 'requires_bay', 'detail', 'rider_flagged', true,
                                 'p0698', 'clean'),
              jsonb_build_object('svc', 'sensor_calibration', 'must_do', true, 'deferrable', true, 'est_min', 30,
                                 'concurrency', 'bay', 'requires_bay', 'service_bay', 'p0698', 'calib'),
              jsonb_build_object('svc', 'interior_tidy', 'must_do', true, 'status', 'done', 'p0698', 'done'),
              jsonb_build_object('svc', 'charge', 'must_do', true, 'status', 'pending', 'p0698', 'charge'),
              jsonb_build_object('svc', 'readiness_check', 'must_do', true, 'status', 'pending', 'p0698', 'ready')),
            'open', 'probe_0698', '{}'::jsonb)
    RETURNING visit_id INTO v_same;
    -- an open visit of the same car on another run, owing a repair: never this run's to carry
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency,
                                          target_soc, atoms, status, source, meta)
    VALUES (v_veh, v_other, v_twin, v_clock - interval '40 minutes', 'probe0698:other', 'probe', 'standard', 100,
            jsonb_build_array(jsonb_build_object('svc', 'mechanical_pm', 'must_do', true, 'deferrable', true,
                                                 'est_min', 60, 'concurrency', 'bay', 'requires_bay', 'service_bay',
                                                 'p0698', 'other')),
            'open', 'probe_0698', '{}'::jsonb);
    v_atoms := ottoq.ottoq_derive_visit_needs(v_veh, v_run, v_run, v_clock, v_twin,
                                              jsonb_build_object('observer', 'probe_0698', 'generator', 'probe_0698'));
    v_r := jsonb_build_object(
      'carried', (SELECT COALESCE(jsonb_agg(e->>'p0698' ORDER BY e->>'p0698'), '[]'::jsonb)
                    FROM jsonb_array_elements(v_atoms) e WHERE e ? 'p0698'),
      'from', (SELECT COALESCE(jsonb_agg(DISTINCT e->>'carried_from_visit'), '[]'::jsonb)
                 FROM jsonb_array_elements(v_atoms) e WHERE e ? 'p0698'),
      'clean_owed', (SELECT count(*) FROM jsonb_array_elements(v_atoms) e
                      WHERE e->>'svc' = 'interior_deep_clean'
                        AND COALESCE(e->>'status', 'pending') NOT IN ('done', 'cancelled')),
      'calib_owed', (SELECT count(*) FROM jsonb_array_elements(v_atoms) e
                      WHERE e->>'svc' = 'sensor_calibration'
                        AND COALESCE(e->>'status', 'pending') NOT IN ('done', 'cancelled')),
      'old_status', (SELECT status FROM public.ottoq_visit_needs WHERE visit_id = v_same),
      'open_visits', (SELECT count(*) FROM public.ottoq_visit_needs
                       WHERE vehicle_id = v_veh AND sim_run_id = v_run AND status = 'open'),
      'stored', (SELECT COALESCE(jsonb_agg(e->>'p0698' ORDER BY e->>'p0698'), '[]'::jsonb)
                   FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) e
                  WHERE vn.vehicle_id = v_veh AND vn.sim_run_id = v_run AND vn.status = 'open' AND e ? 'p0698'));
    RAISE EXCEPTION '0698 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0698 PROBED' THEN RAISE EXCEPTION '0698 probe % failed: %', p_phase, v_msg; END IF;
  INSERT INTO p0698 VALUES (p_phase, v_r);
END $fn$;

-- ── P2: the defect, on the live deriver: the old visit is superseded and none of its owed work reaches the new one ──
DO $p2$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.p0698_probe('before');
  SELECT r INTO v FROM p0698 WHERE phase = 'before';
  IF v->>'old_status' IS DISTINCT FROM 'superseded' OR v->'carried' IS DISTINCT FROM '[]'::jsonb
     OR (v->>'calib_owed')::int <> 0 THEN
    RAISE EXCEPTION '0698 P2: the live deriver did not drop the owed work (%); this file''s premise is wrong', v;
  END IF;
END $p2$;

-- ── the deriver carries what the visits it supersedes still owe ──
DO $p_carry$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure);
  a text[] := ARRAY[
$a01$  v_archetype := CASE
    WHEN v_fault THEN 'E_tech_hold_fault'
$a01$];
  b text[] := ARRAY[
$b01$  -- 0698 (G413, CLAUDE.md rule 9): the supersede below closes every open visit of the car, and the new visit must not
  -- lose what they still owe. Every required atom an open or in-progress visit of the car on THIS run has not done or
  -- cancelled comes onto the new visit as it stood (carried, with the old visit's key), unless the new visit already
  -- has that service. Not the charge or the readiness check (set afresh here from the car as it is now), not an atom
  -- the guard tagged as not required (no executor: it would hold the car forever), not another run's. Ordered by the
  -- old visits' sim-clock arrival, then key, then atom order, so a pair's arms carry the same atoms the same way.
  FOR v_atom IN
    SELECT x.a || jsonb_build_object('carried', true, 'carried_from_visit', o.visit_key)
      FROM public.ottoq_visit_needs o
     CROSS JOIN LATERAL jsonb_array_elements(o.atoms) WITH ORDINALITY AS x(a, k)
     WHERE o.vehicle_id = p_vehicle_id AND o.status IN ('open','in_progress')
       AND COALESCE(o.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
       AND COALESCE((x.a->>'must_do')::boolean, false)
       AND COALESCE(x.a->>'status', 'pending') NOT IN ('done', 'cancelled')
       AND COALESCE(x.a->>'svc', '') NOT IN ('charge', 'readiness_check', '')
     ORDER BY o.arrived_at, o.visit_key, x.k
  LOOP
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_atom->>'svc') THEN
      v_m := v_m || v_atom;
    END IF;
  END LOOP;

  v_archetype := CASE
    WHEN v_fault THEN 'E_tech_hold_fault'
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '9ae0558f6a6ce8ca6d14ba3b9dc3c28b' THEN
    RAISE EXCEPTION '0698: the deriver is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0698: anchor % of the deriver occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'cd5c513bb164a14614003e308009a347' THEN
    RAISE EXCEPTION '0698: the deriver, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure))
       <> 'cd5c513bb164a14614003e308009a347' THEN
    RAISE EXCEPTION '0698: the deriver did not read back as written';
  END IF;
END $p_carry$;

-- ── V1: the same car, patched: the cleaning and the calibration are carried, nothing else is ──
DO $v1$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.p0698_probe('after');
  SELECT r INTO v FROM p0698 WHERE phase = 'after';
  -- the calibration is the deriver's to raise only from an observation flag the probe does not send, so it is carried;
  -- the cleaning is carried, or the deriver raised its own (then the new visit owes it either way)
  IF NOT (v->'carried' ? 'calib') OR (v->>'calib_owed')::int <> 1 OR (v->>'clean_owed')::int < 1
     OR NOT ((v->'carried') <@ '["calib", "clean"]'::jsonb)
     OR v->'from' IS DISTINCT FROM '["probe0698:same"]'::jsonb
     OR v->'stored' IS DISTINCT FROM v->'carried'
     OR v->>'old_status' IS DISTINCT FROM 'superseded' OR (v->>'open_visits')::int <> 1 THEN
    RAISE EXCEPTION '0698 V1 FAILED: %', v;
  END IF;
  RAISE NOTICE '0698 V1 PASSED: before %, after %; all rolled back',
    (SELECT r FROM p0698 WHERE phase = 'before'), v;
END $v1$;

-- ── V2: the definition as written, and no probe visit left ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure))
       <> 'cd5c513bb164a14614003e308009a347' THEN
    RAISE EXCEPTION '0698 V2 FAILED: the deriver is not as written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs WHERE source = 'probe_0698') THEN
    RAISE EXCEPTION '0698 V2 FAILED: a probe visit outlived its rollback';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0698_a_new_visit_carries_the_work_the_visit_it_replaces_still_owes', true, true,
  'G413 (db/checks/0435): ottoq.ottoq_derive_visit_needs carries every required atom an open or in-progress visit of '
  'the car on the same run still owes (not the charge or the readiness check, not a guard-demoted atom) onto the new '
  'visit before it supersedes the old. Since 0543, 15 twin-depot departures left with a rider-reported cleaning owed '
  'on a visit superseded this way (15 runs, 7 distinct cars). Changes the twin''s world with every flag off: TRUE/TRUE.',
  now());

COMMIT;
