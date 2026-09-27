-- migration-version: PENDING
-- migration-name:    a_visit_with_no_charge_does_its_cabin_work_where_the_car_is_parked
--
-- 0526  **G251: a visit with nothing to charge could not have its cabin work started while its car waited for a bay.
--       The twin offers cabin work only to a car that is charging, holding after a charge, or staged for departure;
--       the gate intake puts a no-charge car waiting for a wash or a detail straight into `staged_awaiting_service`;
--       and the readiness gate will not stage a car for departure with must-do work open. So its interior inspection
--       waited for the gate's 240-minute escape hatch. Now a car parked for its bay work, with no charge left on its
--       visit, has its cabin work started by a technician where it stands.**
--       `db/checks/0394`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_advance_visit_atoms` picks the cars whose atoms the starter may begin. For cabin work it admits
--   `charging_dcfc`, `charging_l2`, `charge_complete_holding` and `staged_for_departure` (M3_cabin_at_charger: cabin work
--   is a technician's at the charger, during the charge; the last two are catch-ups so nothing waits forever). That
--   rule presumes every visit charges. On validation run 6ddd827e three no-charge visits -- Tesla-AV-041, Waymo-AV-016,
--   Waymo-AV-020, each with a wash or a detail pending -- went from the gate to `staged_awaiting_service` in one tick,
--   sat on a staging stall with their inspection never offered, and were released by `twin.deploy_gate_override`'s
--   "escape hatch 3" at 240.1 minutes with the inspection and the bay work still open ("this is a DEFECT to
--   investigate, not a normal path", the hatch's own note). The inspection then started in the exit catch-up. The
--   full-day run before 0521 shows the same trap for other cabin work (4bc19d29: a no-charge interior tidy started
--   after 262 minutes); 0521 widened it to the inspection by ending the sensors' false credits at the gate intake,
--   which had been finishing those inspections on cars that were on no charger (G246).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The candidate filter also admits cabin work for a car in `staged_awaiting_service`, parked on a stall, whose visit
--   has no charge left to do -- the starter's own test for a charging visit (a `charge` atom not `done` or `cancelled`),
--   negated. Nothing else moves: the starter still gives such work to a technician from the general pool (its cabin
--   hold binds only a charging visit, and the sensors only a car on a charger, 0521), a charging visit still does its
--   cabin work at the charger, and the two catch-ups stay.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart left NULL (restarts) ═════════════════════════════════════════════
--
--   The filter runs every tick in every certified arm, and who starts what moves the technician pool. It also moves a
--   dial arm, so the dial experiments restart from this file (0523). Applied after a dial window, so the pairs a window
--   gathers are not cut in half by it.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0526 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_adv text; v_start text;
BEGIN
  v_adv   := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  v_start := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  IF position('0526 (G251)' IN v_adv) > 0 THEN
    RAISE EXCEPTION '0526 P2: already applied';
  END IF;
  -- the starter has no state test of its own for cabin work, holds it only for a charging visit, and defines a charging
  -- visit the way this file's filter does
  IF position('v_charging_visit := EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) c' IN v_start) = 0
     OR position('WHERE c->>''svc'' = ''charge'' AND COALESCE(c->>''status'',''pending'') NOT IN (''done'',''cancelled''));' IN v_start) = 0
     OR position('AND NOT (v_a->>''concurrency'' = ''cabin'' AND v_charging_visit' IN v_start) = 0 THEN
    RAISE EXCEPTION '0526 P2: the starter is not the one 0521 left';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0526_pre', 'function', 'twin', 'ottoq_sim_advance_visit_atoms',
       pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure),
       md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure));

DO $patch$
DECLARE
  v_def text;
  v_old text := $o$                                                       'staged_for_departure'))
                         OR (a->>'concurrency' IN ('exterior','digital')) ))$o$;
  v_new text := $n$                                                       'staged_for_departure'))
                         -- 0526 (G251): a visit with no charge left to do has no charger to wait for. Its car, parked
                         -- for its bay work, has its cabin work done where it stands, by a technician (the starter's
                         -- hold binds only a charging visit, and its sensors only a car on a charger). Without this the
                         -- work waited for the deploy gate's 240-minute escape hatch.
                         OR (a->>'concurrency' = 'cabin' AND v.current_state = 'staged_awaiting_service'
                             AND v.current_stall_id IS NOT NULL
                             AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) c
                                              WHERE c->>'svc' = 'charge'
                                                AND COALESCE(c->>'status','pending') NOT IN ('done','cancelled')))
                         OR (a->>'concurrency' IN ('exterior','digital')) ))$n$;
  n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0526: filter patch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

DO $verify$
DECLARE v_adv text;
BEGIN
  v_adv := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  -- V1: the new branch is there once, inside the candidate filter; the old branches and the catch-ups are unchanged;
  --     still SECURITY DEFINER on its search_path
  IF (length(v_adv) - length(replace(v_adv, 'OR (a->>''concurrency'' = ''cabin'' AND v.current_state = ''staged_awaiting_service''', '')))
       / length('OR (a->>''concurrency'' = ''cabin'' AND v.current_state = ''staged_awaiting_service''') <> 1
     OR position('''staged_for_departure''))' IN v_adv) = 0
     OR position('OR (a->>''concurrency'' IN (''exterior'',''digital'')) ))' IN v_adv) = 0
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)
     OR (SELECT proconfig FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)
        IS DISTINCT FROM ARRAY['search_path=twin, ottoq, public, extensions'] THEN
    RAISE EXCEPTION '0526 V1: the patched filter is not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule): forces_recert TRUE, forces_dial_restart left NULL.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0526_a_visit_with_no_charge_does_its_cabin_work_where_the_car_is_parked', true,
  'The twin''s cabin-work candidate filter, which runs every tick in every certified arm: a car in '
  'staged_awaiting_service on a stall, whose visit has no charge left, may have its cabin work started (by a '
  'technician, which moves the pool). Moves dial arms too, so forces_dial_restart is left NULL (G251).', now())
ON CONFLICT (name) DO NOTHING;

-- V3: rolled back, with no run live at the depot. On the newest finished operator run -- marked running inside the
--     test, because the filter reads the depot's running run's visits -- one car parked on a staging stall in
--     `staged_awaiting_service`, with an open visit: (a) no charge, an interior inspection and a wash pending: the
--     inspection starts, by a technician; (b) the same with a charge still to do: it stays pending (a charging visit
--     does its cabin work at the charger); (c) no charge, but the car on no stall: it stays pending.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_end timestamptz; v_car uuid; v_stg uuid; v_visit uuid; v_atom jsonb;
  v_nocharge jsonb := jsonb_build_array(
                        jsonb_build_object('svc', 'interior_inspection', 'status', 'pending', 'must_do', true, 'est_min', 4,
                                           'concurrency', 'cabin'),
                        jsonb_build_object('svc', 'exterior_wash', 'status', 'pending', 'must_do', true, 'est_min', 12,
                                           'concurrency', 'bay'),
                        jsonb_build_object('svc', 'readiness_check', 'status', 'pending', 'must_do', true, 'est_min', 3,
                                           'concurrency', 'gate'));
  v_charging jsonb := jsonb_build_array(
                        jsonb_build_object('svc', 'charge', 'status', 'pending', 'must_do', true, 'target_soc', 100,
                                           'concurrency', 'anchor'),
                        jsonb_build_object('svc', 'interior_inspection', 'status', 'pending', 'must_do', true, 'est_min', 4,
                                           'concurrency', 'cabin'));
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
                WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('running','paused')) THEN
      RAISE EXCEPTION '0526 V3 FAILED: a run is live at the twin depot; the filter would look at it';
    END IF;
    SELECT sr.sim_run_id, sr.sim_clock_current INTO v_run, v_end FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'operator_demo' AND sr.status = 'completed'
       AND sr.depot_id = '11111111-1111-1111-1111-111111111111'
     ORDER BY sr.started_at DESC LIMIT 1;
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
       AND v.current_stall_id IS NULL AND v.robotic_tether_until IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id)
     ORDER BY v.id LIMIT 1;
    SELECT s.id INTO v_stg FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'staging'
       AND s.current_vehicle_id IS NULL AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id)
     ORDER BY s.stall_code LIMIT 1;
    IF v_run IS NULL OR v_car IS NULL OR v_stg IS NULL THEN
      RAISE EXCEPTION '0526 V3 FAILED: nothing to plant on (run %, car %, stall %)', v_run, v_car, v_stg;
    END IF;
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    v_visit := gen_random_uuid();
    INSERT INTO public.ottoq_visit_needs (visit_id, visit_key, vehicle_id, depot_id, sim_run_id, status, arrived_at, target_soc, atoms)
    VALUES (v_visit, v_car::text || ':0526v3', v_car, '11111111-1111-1111-1111-111111111111', v_run, 'open',
            v_end + interval '2 hours', 90, v_nocharge);
    UPDATE public.vehicles SET current_stall_id = v_stg WHERE id = v_car;
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_soc = 90 WHERE id = v_car;

    -- (a) no charge, parked for its wash: the inspection starts, by a technician
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_end + interval '2 hours');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF v_atom->>'status' IS DISTINCT FROM 'in_progress' OR v_atom ? 'performed_by' THEN
      RAISE EXCEPTION '0526 V3 FAILED (a): a no-charge car parked for its wash did not have its inspection started by a technician: %', v_atom;
    END IF;

    -- (b) a charge still to do: the inspection waits for the charger
    UPDATE public.ottoq_visit_needs SET atoms = v_charging, status = 'open' WHERE visit_id = v_visit;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_end + interval '2 hours 1 minute');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF COALESCE(v_atom->>'status', 'pending') <> 'pending' OR v_atom ? 'started_at' THEN
      RAISE EXCEPTION '0526 V3 FAILED (b): a charging visit''s inspection started on staging: %', v_atom;
    END IF;

    -- (c) no charge, but on no stall: it waits until the car is parked
    UPDATE public.ottoq_visit_needs SET atoms = v_nocharge, status = 'open' WHERE visit_id = v_visit;
    UPDATE public.vehicles SET current_stall_id = NULL WHERE id = v_car;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_end + interval '2 hours 2 minutes');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_inspection';
    IF COALESCE(v_atom->>'status', 'pending') <> 'pending' OR v_atom ? 'started_at' THEN
      RAISE EXCEPTION '0526 V3 FAILED (c): an inspection started on a car on no stall: %', v_atom;
    END IF;
    RAISE EXCEPTION '0526 V3 PASSED: a no-charge car parked for its wash had its inspection started by a technician; a charging visit''s waited for the charger; a car on no stall waited to be parked';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0526 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0526 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0526_pre'.
COMMIT;
