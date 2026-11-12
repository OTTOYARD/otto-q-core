-- migration-version: 20261112060812
-- migration-name:    0816_a_car_still_to_charge_keeps_its_deep_clean_for_its_posts_arm
--
-- 0816  **A car still to charge keeps its interior deep clean for its post's arm.**
--
-- WHY. 0815 gave the interior deep clean to the fast charger's cleaning arm, so that no door opens in the wash bay
-- (Chase, 2026-11-11). Its §3 said what it did not do: a car the arm did not reach still took the detail seat, and
-- "routing such a car to a post for the clean alone is a planner change, not made here". Chase, 2026-11-11 (evening),
-- asked for that change: "Yes to all three, go and execute".
--
-- §1 WHAT WAS SO, measured on the first run with 0815 on (893a0313, twin depot, read 2026-11-12 05:35 UTC, sim clock
--   22:33 of a 24-hour day): 33 interior deep cleans. 28 were done by a post's arm. 4 were done in the detail seat of a
--   wash bay, and 1 was pending for it. All 5 cars charged on a fast-charger post in the same visit. So 0815 §3's
--   reason ("a car that never charges on a post") was not the cause. Two things were:
--   (a) THE SEAT CAME BEFORE THE CHARGE. With bay_open_shop (0782) a car waiting for a charger takes bay work while
--       it waits, and the service flow's wash lane seats a booked car from charge_complete_holding. Either door gave
--       the car a detail seat before it reached the post whose arm would have done the clean. Visit 1a3ddf8c: deep
--       clean credited in the bay at 14:49, first fast charge at 15:05.
--   (b) A DEEP CLEAN CUT SHORT BY A CHARGER FAULT WAS NOT TAKEN UP AT THE NEXT POST. The completion loop sees that the
--       car left the arm's post only when the program's planned end passes. Visit 3611f930: the arm began at 20:48 on
--       post 9753cfd9, the charger faulted at 20:55, the car was on post ab17cc0e at 20:56, and the starter there (at
--       21:00:22) still saw a deep clean "in progress" and began the tidy alone. The deep clean went back to pending
--       20 seconds later, with the arm already busy, and was left for the detail seat. 0798 fixed the same order for
--       the arm's routine clean and not for the deep program, which did not exist then.
--
-- §2 WHAT THIS DOES. All of it is behind cabin_robot_deep_clean (0815; default 0, 1 at the twin depot).
--   (a) public.ottoq_deep_clean_waits_for_post(run, vehicle): true when the dial is on, the stalls have cleaning arms
--       (stall_cabin_robot at 1 or 2), and the car's open visit has an interior deep clean still to do AND a charge
--       still to do. Such a car is going to a charger, and at a fast-charger post the arm does the clean.
--   (b) public.ottoq_visit_wants_detail: false for such a car. So a seat it is given now (for an exterior wash) is a
--       wash seat, doors shut, and credits no cabin work.
--   (c) twin.ottoq_sim_advance_service_flow, the wash lane's need gate: the deep clean of such a car is not a reason
--       to seat it.
--   (d) public.ottoq_decide_tick, the needs card's space routing (4b): the deep clean of such a car is not routed to
--       a bay. Its other bay work (an exterior wash, a service bay job) is routed as before.
--   (e) twin.ottoq_sim_advance_visit_atoms: before the starter runs, a deep program (and the tidy it covers) whose car
--       is no longer on the program's post goes back to pending, as the completion loop would write it at the planned
--       end: the interruption recorded, the detail leg back to planned, nothing credited. The starter then gives it to
--       the arm of the car's current post in the same pass. This is 0798's order, for the deep program.
--
-- §3 RULE 9, CHECKED. No service is skipped, shortened or deferred past departure. The deep clean stays a must-do:
--   0543's departure test keeps the car until it is done. The moment the charge is done, (a) is false, and a deep
--   clean the arm did not do (the car charged on an L2, the arm was faulted) is seated in the detail bay exactly as
--   before. The car does not wait longer for this: it was waiting for its charger anyway, and the clean now runs
--   while it charges. RULE 14: the rule reads no owner, and moves no car behind another.
--
-- §4 WHAT THIS DOES NOT DO.
--   - It does not send a car with no charge to do to a post for the clean alone. With the charge target at 100
--     (0539) nearly every arriving car has a charge to do. A car that has none keeps the detail seat. So "no door
--     opens in the wash bay" holds for every car that charges on a post, and is still not absolute.
--   - It does not release a wash-bay booking already held for a detail seat. The calendar's own release does.
--
-- §5 PRECONDITIONS AND CHECKS.
--   P0 nothing in flight, no run live (V3 stages a past run as running). P1 the bodies are the ones this file was
--   written against (md5 of prosrc below), and 0815 is applied. P2 once. V1 each patched body with its patches
--   reversed is its pre-image. V2 every anchor matched once. V3 the behaviour, staged on a past visit inside a block
--   that is rolled back. What it measured goes into the lineage note.
--     twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)   f871ecad1ccb2c9a85d92a2c466de2d6
--     public.ottoq_decide_tick(uuid)                                       d2d321397876ac693a5fe69c634f8bdb
--     twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)                 effa3c91090e874f19521aac4d2933dd
--     public.ottoq_visit_wants_detail(uuid)                                9f34be03a1e76e53a2a4be2ad03da1a5
--
-- §6 CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: at cabin_robot_deep_clean 0 (the default, and
--   what every certification arm and dial experiment runs at) the helper is false and v_deep_arm is false, so no new
--   branch is reached. Already ON at the twin depot through 0815's dial (rule 12).
--
-- ROLLBACK: EXECUTE the four `definition`s in ottoq_schema_snapshots WHERE label = '0816_pre'; DROP FUNCTION
--   public.ottoq_deep_clean_waits_for_post(uuid, uuid); DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0816_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0816 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0816 P0: a run is live. V3 stages a past run as running, so apply between runs';
  END IF;
END $inflight$;

-- ── P1: the bodies this file was written against ──
DO $p1$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)', 'f871ecad1ccb2c9a85d92a2c466de2d6'),
      ('public.ottoq_decide_tick(uuid)',                                     'd2d321397876ac693a5fe69c634f8bdb'),
      ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',               'effa3c91090e874f19521aac4d2933dd'),
      ('public.ottoq_visit_wants_detail(uuid)',                              '9f34be03a1e76e53a2a4be2ad03da1a5')) v(fn, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0816 P1: % is not the body this file was written against', r.fn;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'cabin_robot_deep_clean') THEN
    RAISE EXCEPTION '0816 P1: 0815 is not applied';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0816_%') THEN
    RAISE EXCEPTION '0816 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0816_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)'::regprocedure,
                 'public.ottoq_decide_tick(uuid)'::regprocedure,
                 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure,
                 'public.ottoq_visit_wants_detail(uuid)'::regprocedure);

-- ── (a) the one test: this car's deep clean waits for its post's arm ──
CREATE FUNCTION public.ottoq_deep_clean_waits_for_post(p_sim_run_id uuid, p_vehicle uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0816: true when the fast chargers' cleaning arms do the interior deep clean (0815's dial, and stalls that have
  -- arms), and this car's open visit in the run has a deep clean still to do and a charge still to do. Such a car is
  -- going to a charger, and at a fast-charger post the arm does the clean while the car charges. False the moment the
  -- charge is done: a deep clean the arm did not do is then the detail seat's, so the service is never left undone.
  SELECT COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_robot_deep_clean', 0), 0) >= 1
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 1
     AND EXISTS (
       SELECT 1 FROM public.ottoq_visit_needs vn
        WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress')
          AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) d
                       WHERE d->>'svc' = 'interior_deep_clean'
                         AND COALESCE(d->>'status','pending') NOT IN ('done','cancelled','skipped'))
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) c
                       WHERE c->>'svc' = 'charge'
                         AND COALESCE(c->>'status','pending') NOT IN ('done','cancelled','skipped')));
$function$;

COMMENT ON FUNCTION public.ottoq_deep_clean_waits_for_post(uuid, uuid) IS
  '0816: this car''s interior deep clean waits for its fast-charger post''s cleaning arm. True when cabin_robot_deep_clean '
  'is on, the stalls have cleaning arms, and the car''s open visit has a deep clean and a charge still to do. False once '
  'the charge is done, so a clean the arm did not do goes to the detail seat (rule 9).';

-- ── (b) the seat's kind ──
CREATE OR REPLACE FUNCTION public.ottoq_visit_wants_detail(p_vehicle uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
    WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = vn.depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
      AND a->>'svc' = 'interior_deep_clean' AND COALESCE(a->>'status','pending') <> 'done'
      -- 0816: not while the car still has its charge to do: its post's arm does the clean (0815), so a seat it is
      -- given now is a wash seat, doors shut
      AND NOT public.ottoq_deep_clean_waits_for_post(vn.sim_run_id, p_vehicle));
$function$;

-- ── the patches ──
CREATE TEMP TABLE _0816_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0816_patch VALUES
-- (c) the service flow's wash lane: the need gate
(1, 'twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)',
$o$                         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
              OR v.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))$o$,
$n$                         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped')
                         -- 0816: a deep clean that waits for the car's post is not a reason to seat it
                         AND NOT (a->>'svc' = 'interior_deep_clean'
                                  AND public.ottoq_deep_clean_waits_for_post(p_sim_run_id, v.id)))
              OR v.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))$n$),
-- (d) the needs card's space routing
(2, 'public.ottoq_decide_tick(uuid)',
$o$           WHERE p.lane IN ('wash_bay','detail','service_bay')
        ), pick AS ($o$,
$n$           WHERE p.lane IN ('wash_bay','detail','service_bay')
             -- 0816: a deep clean that waits for the car's post is not routed to a bay
             AND NOT (x.svc = 'interior_deep_clean'
                      AND public.ottoq_deep_clean_waits_for_post(p_sim_run_id, k.vehicle_id))
        ), pick AS ($n$),
-- (e) before the starter: a deep program whose car left its post goes back to pending
(3, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
$o$  FOR v_rec IN
    SELECT vn.vehicle_id
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
       AND v.current_state IN ('charging_dcfc','charging_l2','charge_complete_holding',$o$,
$n$  -- 0816: the arm's deep program (0815), and the tidy it covers, of a car no longer on the program's post goes back
  -- to pending now, whatever its planned end, before the starter runs, so the starter can give it to the arm of the
  -- car's current post in this same pass. It is written as the completion loop writes it at the planned end: the
  -- interruption recorded with the post, the detail leg back to planned, nothing credited.
  IF v_feed_sim AND v_deep_arm THEN
    FOR v_rec IN
      SELECT vn.visit_id, vn.atoms, v.current_stall_id
        FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
       WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
         AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
             = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                      WHERE a->>'status' = 'in_progress' AND a->>'performed_by' = 'stall_cabin_robot'
                        AND (COALESCE((a->>'deep_program')::boolean, false) OR COALESCE((a->>'with_deep_clean')::boolean, false))
                        AND a->>'robot_stall_id' IS NOT NULL
                        AND v.current_stall_id::text IS DISTINCT FROM a->>'robot_stall_id')
       ORDER BY vn.vehicle_id
    LOOP
      v_new := '[]'::jsonb;
      FOR v_a IN SELECT x.e FROM jsonb_array_elements(v_rec.atoms) WITH ORDINALITY AS x(e, o) ORDER BY x.o LOOP
        IF v_a->>'status' = 'in_progress' AND v_a->>'performed_by' = 'stall_cabin_robot'
           AND (COALESCE((v_a->>'deep_program')::boolean, false) OR COALESCE((v_a->>'with_deep_clean')::boolean, false))
           AND v_a->>'robot_stall_id' IS NOT NULL
           AND v_rec.current_stall_id::text IS DISTINCT FROM v_a->>'robot_stall_id' THEN
          IF v_a->>'robot_leg_id' IS NOT NULL THEN
            UPDATE ottoq_itinerary_legs SET status = 'planned', actual_start_sim = NULL, to_stall_id = NULL
             WHERE leg_id = (v_a->>'robot_leg_id')::uuid AND status = 'active';
          END IF;
          v_a := (v_a - 'started_at' - 'ends_at' - 'performed_by' - 'robot_stall_id' - 'robot_cycle_min'
                      - 'robot_leg_id' - 'deep_program' - 'with_deep_clean')
                 || jsonb_build_object('status', 'pending',
                      'interrupted', COALESCE(v_a->'interrupted', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                          'at', p_clock, 'reason', 'left_the_cabin_robot',
                          'started_at', v_a->'started_at', 'stall_id', v_a->'robot_stall_id')));
        END IF;
        v_new := v_new || jsonb_build_array(v_a);
      END LOOP;
      UPDATE ottoq_visit_needs SET atoms = v_new WHERE visit_id = v_rec.visit_id;
    END LOOP;
  END IF;

  FOR v_rec IN
    SELECT vn.vehicle_id
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
       AND v.current_state IN ('charging_dcfc','charging_l2','charge_complete_holding',$n$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0816_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0816 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0816: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body with its patches reversed is its pre-image ──
DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0816_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0816_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0816_pre'
                                       AND s.schema_name || '.' || s.object_name = split_part(f.fn, '(', 1)) THEN
      RAISE EXCEPTION '0816 V1: % with its patches reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

-- ── V3: the behaviour, staged on a past visit, inside a block that is rolled back ──
-- Takes a past visit at the twin depot with an interior deep clean and a charge, stages its run as running, and reads:
-- (1) with the charge and the deep clean to do, the clean waits for the post and the seat is not a detail seat;
-- (2) with the charge done, it does not wait and the seat is a detail seat (rule 9's fallback);
-- (3) with the dial at 0, nothing waits (the behaviour before this file);
-- (4) a deep program and its covered tidy, in progress on a post the car has left, are back to pending after one pass
--     of the visit-atoms advance, with the interruption recorded and the program's marks gone.
CREATE TEMP TABLE _0816_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_visit uuid; v_run uuid; v_veh uuid; v_post uuid; v_other uuid; v_clock timestamptz;
  v_res jsonb; v_deep jsonb; v_tidy jsonb; v_had_tidy boolean;
BEGIN
  SELECT vn.visit_id, vn.sim_run_id, vn.vehicle_id, r.sim_clock_current
    INTO v_visit, v_run, v_veh, v_clock
    FROM public.ottoq_visit_needs vn
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
   WHERE vn.depot_id = c_depot AND r.depot_id = c_depot
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'interior_deep_clean')
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs o
                      WHERE o.vehicle_id = vn.vehicle_id AND o.sim_run_id = vn.sim_run_id AND o.visit_id <> vn.visit_id)
   ORDER BY r.started_at DESC, vn.visit_id LIMIT 1;
  SELECT s.id INTO v_post FROM public.stalls s
   WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc' AND s.current_vehicle_id IS NULL ORDER BY s.stall_code LIMIT 1;
  SELECT s.id INTO v_other FROM public.stalls s
   WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc' AND s.id <> v_post ORDER BY s.stall_code DESC LIMIT 1;
  IF v_visit IS NULL OR v_post IS NULL OR v_other IS NULL THEN
    INSERT INTO _0816_selftest VALUES (jsonb_build_object('ran', false, 'why', 'no past visit or no two posts to stage'));
    RETURN;
  END IF;
  v_clock := COALESCE(v_clock, now());
  BEGIN
    DELETE FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_run
       AND param_key IN ('cabin_robot_deep_clean', 'stall_cabin_robot');
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'cabin_robot_deep_clean', 1, '0816 self-test', now()),
           ('run', v_run, 'stall_cabin_robot', 2, '0816 self-test', now());
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    -- the visit with its charge and its deep clean (and any tidy) to do
    UPDATE public.ottoq_visit_needs vn
       SET status = 'open',
           atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' IN ('interior_deep_clean', 'interior_tidy', 'charge')
                                          THEN (a - 'started_at' - 'ends_at' - 'done_at' - 'closed_at' - 'closed_by' - 'performed_by'
                                                  - 'robot_stall_id' - 'robot_cycle_min' - 'robot_leg_id' - 'deep_program'
                                                  - 'with_deep_clean' - 'confirm_required' - 'interrupted')
                                               || jsonb_build_object('status', 'pending', 'must_do', true)
                                          ELSE a END ORDER BY ord)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY x(a, ord)
                     WHERE NOT COALESCE((a->>'arm_routine')::boolean, false))
     WHERE vn.visit_id = v_visit;
    v_had_tidy := EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                           WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_tidy');

    -- (1) charge and deep clean to do
    IF NOT public.ottoq_deep_clean_waits_for_post(v_run, v_veh) THEN
      RAISE EXCEPTION '0816 V3: a car with its charge and its deep clean to do does not wait for its post';
    END IF;
    IF public.ottoq_visit_wants_detail(v_veh) THEN
      RAISE EXCEPTION '0816 V3: a car that waits for its post would still be given a detail seat';
    END IF;

    -- (3) the dial at 0: as before this file
    UPDATE public.ottoq_policy_params SET param_value = 0
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'cabin_robot_deep_clean';
    IF public.ottoq_deep_clean_waits_for_post(v_run, v_veh) OR NOT public.ottoq_visit_wants_detail(v_veh) THEN
      RAISE EXCEPTION '0816 V3: with the dial at 0 the seat is not the detail seat it was';
    END IF;
    UPDATE public.ottoq_policy_params SET param_value = 1
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'cabin_robot_deep_clean';

    -- (4) a deep program, and its covered tidy, in progress on a post the car has left
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_stall_id = NULL WHERE id = v_veh;
    UPDATE public.ottoq_visit_needs vn
       SET atoms = (SELECT jsonb_agg(CASE
                      WHEN a->>'svc' = 'interior_deep_clean'
                        THEN a || jsonb_build_object('status', 'in_progress', 'performed_by', 'stall_cabin_robot',
                               'robot_stall_id', v_other, 'robot_cycle_min', 10.8, 'deep_program', true,
                               'started_at', v_clock - interval '2 minutes', 'ends_at', v_clock + interval '8 minutes')
                      WHEN a->>'svc' = 'interior_tidy'
                        THEN a || jsonb_build_object('status', 'in_progress', 'performed_by', 'stall_cabin_robot',
                               'robot_stall_id', v_other, 'robot_cycle_min', 10.8, 'with_deep_clean', true,
                               'started_at', v_clock - interval '2 minutes', 'ends_at', v_clock + interval '8 minutes')
                      ELSE a END ORDER BY ord)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY x(a, ord))
     WHERE vn.visit_id = v_visit;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_clock);
    SELECT a INTO v_deep FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean';
    SELECT a INTO v_tidy FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_tidy';
    IF v_deep->>'status' <> 'pending' OR v_deep ? 'deep_program' OR v_deep ? 'performed_by'
       OR v_deep->'interrupted'->-1->>'reason' <> 'left_the_cabin_robot'
       OR v_deep->'interrupted'->-1->>'stall_id' <> v_other::text THEN
      RAISE EXCEPTION '0816 V3: the deep program of a car that left its post is not back to pending (%)', v_deep;
    END IF;
    IF v_had_tidy AND (v_tidy->>'status' <> 'pending' OR v_tidy ? 'with_deep_clean') THEN
      RAISE EXCEPTION '0816 V3: the covered tidy is not back to pending (%)', v_tidy;
    END IF;

    -- (2) the charge done: the detail seat is the fallback
    UPDATE public.ottoq_visit_needs vn
       SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' = 'charge' THEN a || jsonb_build_object('status', 'done') ELSE a END ORDER BY ord)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY x(a, ord))
     WHERE vn.visit_id = v_visit;
    IF public.ottoq_deep_clean_waits_for_post(v_run, v_veh) OR NOT public.ottoq_visit_wants_detail(v_veh) THEN
      RAISE EXCEPTION '0816 V3: with the charge done, the deep clean the arm did not do is not the detail seat''s';
    END IF;

    v_res := jsonb_build_object('ran', true, 'visit', v_visit, 'run', v_run, 'left_post', v_other, 'tidy_covered', v_had_tidy,
               'waits_with_charge_to_do', true, 'detail_seat_after_charge', true, 'dial_0_unchanged', true,
               'deep_back_to_pending_before_the_starter', true);
    RAISE EXCEPTION USING ERRCODE = 'P0816', MESSAGE = v_res::text;       -- undo everything the test wrote
  EXCEPTION WHEN SQLSTATE 'P0816' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE updated_by = '0816 self-test') THEN
    RAISE EXCEPTION '0816 V3: the self-test left something behind';
  END IF;
  INSERT INTO _0816_selftest VALUES (v_res);
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0816_a_car_still_to_charge_keeps_its_deep_clean_for_its_posts_arm',
        false, false,
        'Behind cabin_robot_deep_clean (0815; default 0, at which the new helper is false and no new branch is reached). '
        'At the twin depot (1): a car with a charge and an interior deep clean still to do is not given a detail seat '
        'before its charge (the service flow''s wash lane, the needs card''s space routing and the seat''s kind all read '
        'public.ottoq_deep_clean_waits_for_post), and a deep program cut short when its car left the post goes back to '
        'pending before the starter runs, so the next post''s arm takes it. Once the charge is done, a deep clean the '
        'arm did not do is the detail seat''s, as before (rule 9). V3 self-test at apply (rolled back): '
        || COALESCE((SELECT result::text FROM _0816_selftest LIMIT 1), 'no result'),
        now());

COMMIT;

-- APPLIED 2026-11-12 at 06:08:12 UTC (12:08 AM CT), ledger 20261112060812, through apply_migration, on the first
--   send. No run was live and nothing was in flight (P0): run 893a0313 was ended first, after its reading (§1). The
--   text sent was this file from BEGIN to COMMIT. V3 (rolled back) staged visit 3434e8c6 of run 893a0313: with its
--   charge and its deep clean to do the car waits for its post and is not given a detail seat; with the dial at 0 the
--   seat is the detail seat it was; a deep program in progress on post 3f2338b8, which the car had left, was back to
--   pending after one pass, the interruption recorded; and with the charge done the deep clean is the detail seat's.
--   That visit had no tidy, so the covered tidy's return to pending was not exercised. Stored after the apply,
--   md5(prosrc): ottoq_sim_advance_service_flow d96b1456ad268de7fd7458beffef0881, ottoq_decide_tick
--   544c41b17aadb9860a4a6752d54f9f10, ottoq_sim_advance_visit_atoms 46e591cf3489a8b29cc3dcf4c0a08ac9,
--   ottoq_visit_wants_detail b274608749b35caa8672927c815c6e98, ottoq_deep_clean_waits_for_post
--   496773fc2b8ea7a06697ce2ddb686178. NOT YET SEEN ON A RUN when this note was written: demo run 5480be1f was started
--   at 06:08:28 UTC for the check rule 12 asks for.
-- CORRECTION, 2026-11-12 (db/checks/0483 §2): §1's "4 were done in the detail seat" counts deep-clean ATOMS that a bay
--   closed. It does not count seats. From the itinerary's legs, run 893a0313 gave 23 detail seats in a wash bay: 4 are
--   this file's case, 5 were cars with no visit record, and 14 were cars with no deep clean open. This file closes the
--   4. db/checks/0483 §5 says what is open.
