-- migration-version: 20261112030415
-- migration-name:    0815_the_fast_chargers_arm_does_the_interior_deep_clean_so_no_door_opens_in_the_wash_bay
--
-- 0815  **The fast charger's arm does the interior deep clean, so no door opens in the wash bay.**
--
-- WHY. Chase, 2026-11-11: "lets consider if a vehicle needs an interior vaccuum one in the large wash bay, since all
-- charge stations have internal vaccuum arms for quick clean. I don't think doors should open whatsoever once in the
-- large external wash bay since there will be water and dampness. Only external wash/rinse, dry, and then
-- sensor/camera gentle wipe." Asked which of two ways the interior deep clean should go, he chose the fast charger's
-- overhead arm running a longer program ("Go with your recommendations on all four and execute").
--
-- §1 WHAT WAS SO. An interior deep clean is a `bay` atom (requires_bay 'detail'). The service flow seats its car in a
--   wash bay as `in_detail_bay`, where the doors open for a robot arm at wash_lane_physics 2 (0746), and the seat
--   credits interior_deep_clean, exterior_wash and interior_tidy together. Measured on the twin depot's last three
--   runs (9a909c7b, 54c0d20f, 672e7c1d; read 2026-11-12 02:57 UTC): 43 deep-clean atoms, 9 done in their run, and 33
--   of the 43 on a car that had a fast-charger session in the same run.
--
-- §2 WHAT THIS DOES, behind `cabin_robot_deep_clean` (default 0: nothing below is reached).
--   (a) public.ottoq_start_concurrent_atoms: a car charging on a fast-charger post (the same test 0758 uses: state
--       charging_dcfc, a dcfc stall, an active session in the run) whose visit has an interior deep clean pending and
--       confirmed, and whose arm is not already at work, has it done by the post's cleaning arm. The program is
--       2 x cabin_robot_deep_side_min + cabin_robot_motion_min (10.8 minutes at the defaults; the 5.0 a side is 0746's
--       ten minutes in the cabin, an ASSUMPTION pending R-21). The atom is written exactly as 0758 writes the tidy
--       (performed_by stall_cabin_robot, robot_stall_id, robot_cycle_min) plus `deep_program` and `robot_leg_id`, so
--       0758's hold keeps the car on the post until the arm is home, 0814's found-item stop applies, and a car that
--       leaves early (a charger fault, an emergency) has the work put back to pending with nothing credited.
--       The planned `detail` leg is claimed through the engine's own leg door (ottoq_itin_leg_open), so the clean ends
--       in one service record at the post, not a second leg.
--       RULE 9: the deep clean is a need. It starts however little of the charge is left, and an immediate turnaround
--       gets it too: no car leaves with a service still needed.
--   (b) the visit's interior tidy, when it has one to do, is covered by the same program: it runs with the deep clean
--       (`with_deep_clean`) and ends with it, as the detail seat credited both. No technician is taken.
--   (c) 0764's routine clean is not added to a visit whose deep clean the arm does or did.
--   (d) twin.ottoq_sim_advance_visit_atoms: such a car is among those the starter is called for; the deep program
--       closes its own leg by id with real times (as 0764's routine does); an interrupted one returns its leg to
--       planned.
--   (e) twin.ottoq_sim_cabin_found_items_tick (0814) checks one atom a clean: not the covered tidy as well.
--
-- §3 WHAT THIS DOES NOT DO.
--   - It does not remove the detail seat. A car that never charges on a fast-charger post in its visit (10 of the 43
--     above) still has its deep clean done in the wash bay as before, because rule 9 does not let the service go
--     undone. Routing such a car to a post for the clean alone is a planner change, not made here. Until it is made,
--     "no door opens in the wash bay" holds for the cars the arm reaches, not for every car.
--   - It does not release a wash-bay booking already held for the detail seat. The calendar's own release does that
--     when the car does not come (28 such releases stand in the twin depot's calendar today).
--   - A car whose deep clean the arm did and which still needs an exterior wash is seated as `in_wash_bay`
--     (ottoq_visit_wants_detail reads the atom's status), so its doors stay shut there.
--
-- §4 COST, STATED. The post is held for up to one deep program past the end of a short charge (10.8 minutes at the
--   defaults, against 5.8 for the tidy). That is charger time. It is a capacity finding to measure on a run, never a
--   reason to shorten the clean (rule 9).
--
-- §5 PRECONDITIONS AND CHECKS.
--   P0 nothing in flight. P1 the three bodies are the ones this file was written against (md5 below), and 0814 is
--   applied. P2 once. V1 each body with its patches reversed is its pre-image. V2 every anchor matched once (the patch
--   block raises otherwise). V3 the behaviour, staged on a past visit inside a block that is rolled back: start, hold,
--   end, leg, and the seat the car would then get. What it measured goes into the lineage note.
--     public.ottoq_start_concurrent_atoms(uuid, timestamptz)   25052205e0b6aa2c74504652b840869c
--     twin.ottoq_sim_advance_visit_atoms(uuid, timestamptz)    d5400144f61d8eb3d2f2123571f32084
--
-- §6 CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: at cabin_robot_deep_clean 0 (the default, and
--   what every certification arm and dial experiment runs at) v_deep and v_deep_arm are false and no new branch is
--   reached. ON at the twin depot (rule 12), under "Chase (delegated to Claude Code: 0815)". Undo: DELETE that
--   ottoq_policy_params row.
--
-- ROLLBACK: EXECUTE the three `definition`s in ottoq_schema_snapshots WHERE label = '0815_pre'; DELETE FROM
--   public.ottoq_policy_params WHERE param_key IN ('cabin_robot_deep_clean','cabin_robot_deep_side_min'); DELETE FROM
--   public.ottoq_policy_param_catalog WHERE param_key IN ('cabin_robot_deep_clean','cabin_robot_deep_side_min');
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0815_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0815 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0815 P0: a run is live. V3 stages a past run as running, so apply between runs';
  END IF;
END $inflight$;

-- ── P1: the bodies this file was written against ──
DO $p1$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_start_concurrent_atoms(uuid,timestamptz)', '25052205e0b6aa2c74504652b840869c'),
      ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',  'd5400144f61d8eb3d2f2123571f32084')) v(fn, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0815 P1: % is not the body this file was written against', r.fn;
    END IF;
  END LOOP;
  IF to_regprocedure('twin.ottoq_sim_cabin_found_items_tick(uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0815 P1: 0814 is not applied';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0815_%') THEN
    RAISE EXCEPTION '0815 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0815_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure,
                 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure,
                 'twin.ottoq_sim_cabin_found_items_tick(uuid,timestamptz)'::regprocedure);

-- ── (a) the dials ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
  ('cabin_robot_deep_clean',
   '0815: 1 = a car charging on a fast-charger post has its interior deep clean done by the post''s cleaning arm, as a '
   'longer program (2 x cabin_robot_deep_side_min + cabin_robot_motion_min), with the visit''s interior tidy covered by '
   'the same program. The car stays on the post until the arm is home. No door then opens in the wash bay for that car '
   '(Chase, 2026-11-11). A car that never charges on a post keeps the detail seat, so the service is never left undone. '
   '0 = the deep clean is done in the detail seat of a wash bay, as before 0815. Needs stall_cabin_robot at 1 or 2.',
   0, 0, 1, 'public.ottoq_start_concurrent_atoms; twin.ottoq_sim_advance_visit_atoms', false),
  ('cabin_robot_deep_side_min',
   '0815: minutes the fast-charger stall''s cleaning arm spends in the cabin on each side in its deep program (vacuum, '
   'air blow-out, wipe of the hard surfaces). 5.0 a side is the ten minutes in the cabin 0746 gave the wash bay''s '
   'interior robot. ASSUMPTION pending R-21: no public source gives a measured robot-arm interior cycle for a car.',
   5.0, 1, 20, 'public.ottoq_start_concurrent_atoms', false);

-- ── the patches ──
CREATE TEMP TABLE _0815_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0815_patch VALUES
-- starter 1: the declarations
(1, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o$  v_robot_short boolean := false; v_urgency text;   -- 0765: a charge shorter than the arm's cycle; the visit's urgency
$o$,
$n$  v_robot_short boolean := false; v_urgency text;   -- 0765: a charge shorter than the arm's cycle; the visit's urgency
  -- 0815: the arm's longer program for an interior deep clean (cabin_robot_deep_clean)
  v_deep boolean := false; v_deep_started boolean := false; v_deep_cycle numeric; v_deep_ends timestamptz; v_deep_leg uuid;
$n$),
-- starter 2: decide the deep program before the loop, and start it on the deep-clean atom
(2, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o$  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF COALESCE(v_a->>'status','pending') = 'pending'
       AND v_a->>'concurrency' IN ('cabin','exterior','digital')
$o$,
$n$  -- 0815: with cabin_robot_deep_clean on, the post's arm does the visit's interior deep clean as a longer program.
  -- v_robot_cycle and v_robot_left are set only for a car charging on a fast-charger stall with an active session and
  -- stall_cabin_robot on (above). The deep clean is a need (rule 9): it starts however little of the charge is left,
  -- and 0758's hold keeps the car on the post until the arm is home. One program at a time: an arm at work is waited for.
  IF v_robot_cycle IS NOT NULL AND v_robot_left IS NOT NULL
     AND COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_deep_clean', 0), 0) >= 1
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) d
                  WHERE d->>'svc' = 'interior_deep_clean' AND COALESCE(d->>'status','pending') = 'pending'
                    AND NOT COALESCE((d->>'confirm_required')::boolean, false))
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) b
                      WHERE b->>'status' = 'in_progress' AND b->>'performed_by' = 'stall_cabin_robot') THEN
    v_deep_cycle := 2 * GREATEST(0, COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_deep_side_min', 5.0), 5.0))
                    + GREATEST(0, COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_motion_min', 0.8), 0.8));
    v_deep := v_deep_cycle > 0;
    v_deep_ends := p_clock + make_interval(secs => (round(v_deep_cycle * 60))::double precision);
  END IF;
  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF v_deep AND NOT v_deep_started AND v_a->>'svc' = 'interior_deep_clean'
       AND COALESCE(v_a->>'status','pending') = 'pending'
       AND NOT COALESCE((v_a->>'confirm_required')::boolean, false) THEN
      -- the planned `detail` leg is claimed through the engine's own leg door, then written to the post: one leg, one
      -- service record, at the place the work was done
      v_deep_leg := public.ottoq_itin_leg_open(v_run, v_depot, p_vehicle, p_clock, 'detail', NULL, v_deep_ends,
                      jsonb_build_object('atom', 'interior_deep_clean', 'kind', 'stall_cabin_robot',
                                         'deep_program', true, 'concurrent_with', 'charge'),
                      'stall_cabin_robot');
      UPDATE ottoq_itinerary_legs SET to_stall_id = v_stall WHERE leg_id = v_deep_leg;
      v_a := v_a || jsonb_build_object('status', 'in_progress', 'started_at', to_jsonb(p_clock),
               'ends_at', to_jsonb(v_deep_ends), 'performed_by', 'stall_cabin_robot', 'robot_stall_id', v_stall,
               'robot_cycle_min', v_deep_cycle, 'deep_program', true, 'robot_leg_id', v_deep_leg);
      v_started := v_started + 1;
      v_deep_started := true;
    ELSIF COALESCE(v_a->>'status','pending') = 'pending'
       AND v_a->>'concurrency' IN ('cabin','exterior','digital')
$n$),
-- starter 3: the deep program covers the visit's interior tidy
(3, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o$      ELSIF v_robot AND v_a->>'svc' = 'interior_tidy' AND COALESCE((v_a->>'must_do')::boolean, false) THEN
$o$,
$n$      -- 0815: the deep program cleans the whole cabin, so the visit's interior tidy runs with it and ends with it (as
      -- the detail seat credited both). It is the arm's, and takes no technician.
      ELSIF v_deep AND v_a->>'svc' = 'interior_tidy' THEN
        v_a := v_a || jsonb_build_object('status', 'in_progress', 'started_at', to_jsonb(p_clock),
                 'ends_at', to_jsonb(v_deep_ends), 'performed_by', 'stall_cabin_robot', 'robot_stall_id', v_stall,
                 'robot_cycle_min', v_deep_cycle, 'with_deep_clean', true);
        v_started := v_started + 1;
      ELSIF v_robot AND v_a->>'svc' = 'interior_tidy' AND COALESCE((v_a->>'must_do')::boolean, false) THEN
$n$),
-- starter 4: no routine clean beside, or after, the arm's deep clean
(4, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o$                          AND COALESCE(t->>'status', 'pending') IN ('pending', 'in_progress', 'done')) THEN
$o$,
$n$                          AND COALESCE(t->>'status', 'pending') IN ('pending', 'in_progress', 'done'))
       -- 0815: nor when the arm does, or did, this visit's deep clean: that program cleans the whole cabin
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) d
                        WHERE d->>'svc' = 'interior_deep_clean' AND d->>'performed_by' = 'stall_cabin_robot'
                          AND d->>'status' IN ('in_progress', 'done')) THEN
$n$),
-- completion 1 and 2: the dial
(5, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
$o$  v_arm_every boolean := false;   -- 0764: stall_cabin_robot at 2, the arm cleans every car that charges on its post
$o$,
$n$  v_arm_every boolean := false;   -- 0764: stall_cabin_robot at 2, the arm cleans every car that charges on its post
  v_deep_arm boolean := false;    -- 0815: cabin_robot_deep_clean, the arm does the interior deep clean
$n$),
(6, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
$o$  v_arm_every := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 2;   -- 0764
$o$,
$n$  v_arm_every := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 2;   -- 0764
  v_deep_arm := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_robot_deep_clean', 0), 0) >= 1;   -- 0815
$n$),
-- completion 3: the starter is called for a charging car with a deep clean to do
(7, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
$o$            -- 0764: with stall_cabin_robot at 2, a car charging on a fast-charger post whose visit has no interior
$o$,
$n$            -- 0815: a car charging on a fast-charger post with an interior deep clean to do and its arm free, so
            -- the starter can give the clean to the post's arm
            OR (v_deep_arm AND v.current_state = 'charging_dcfc'
                AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) dc
                             WHERE dc->>'svc' = 'interior_deep_clean' AND COALESCE(dc->>'status','pending') = 'pending'
                               AND NOT COALESCE((dc->>'confirm_required')::boolean, false))
                AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) db
                                 WHERE db->>'status' = 'in_progress' AND db->>'performed_by' = 'stall_cabin_robot')
                AND EXISTS (SELECT 1 FROM stalls sdc
                             WHERE sdc.id = v.current_stall_id AND sdc.stall_type::text = 'dcfc'))
            -- 0764: with stall_cabin_robot at 2, a car charging on a fast-charger post whose visit has no interior
$n$),
-- completion 4: an interrupted deep program returns its leg to planned
(8, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
$o$        v_a := (v_a - 'started_at' - 'ends_at' - 'performed_by' - 'robot_stall_id' - 'robot_cycle_min')
$o$,
$n$        -- 0815: the deep program's leg goes back to planned, for the next post's arm or the detail seat
        IF v_a->>'robot_leg_id' IS NOT NULL THEN
          UPDATE ottoq_itinerary_legs SET status = 'planned', actual_start_sim = NULL, to_stall_id = NULL
           WHERE leg_id = (v_a->>'robot_leg_id')::uuid AND status = 'active';
        END IF;
        v_a := (v_a - 'started_at' - 'ends_at' - 'performed_by' - 'robot_stall_id' - 'robot_cycle_min'
                    - 'robot_leg_id' - 'deep_program' - 'with_deep_clean')
$n$),
-- completion 5: the deep program closes its own leg, by id, with real times
(9, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
$o$        IF COALESCE((v_a->>'arm_routine')::boolean, false) AND v_a->>'robot_leg_id' IS NOT NULL THEN
$o$,
$n$        IF (COALESCE((v_a->>'arm_routine')::boolean, false) OR COALESCE((v_a->>'deep_program')::boolean, false))   -- 0815
           AND v_a->>'robot_leg_id' IS NOT NULL THEN
$n$),
-- 0814's tick: one check a clean, not the covered tidy as well
(10, 'twin.ottoq_sim_cabin_found_items_tick(uuid,timestamptz)',
$o$      IF v_a->>'status' = 'in_progress' AND v_a->>'performed_by' = 'stall_cabin_robot' AND NOT (v_a ? 'item_check')
$o$,
$n$      IF v_a->>'status' = 'in_progress' AND v_a->>'performed_by' = 'stall_cabin_robot' AND NOT (v_a ? 'item_check')
         AND NOT COALESCE((v_a->>'with_deep_clean')::boolean, false)   -- 0815: one check a clean
$n$);
UPDATE _0815_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0815_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0815 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0815: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each body with its patches reversed is its pre-image ──
DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0815_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0815_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0815_pre'
                                       AND s.schema_name || '.' || s.object_name = split_part(f.fn, '(', 1)) THEN
      RAISE EXCEPTION '0815 V1: % with its patches reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

-- ── V3: the behaviour, staged on a past visit, inside a block that is rolled back ──
-- Takes a past visit at the twin depot with an interior deep clean whose car had a fast-charger session in that run,
-- stages the run as running, the session as active and the car as charging on that post, and plays: the start (the
-- deep clean and the tidy are the arm's, the detail leg is claimed, no routine clean is added), the hold, the end (both
-- done, the leg done at the post) and the seat the car would then be given. Everything it writes is undone.
CREATE TEMP TABLE _0815_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_visit uuid; v_run uuid; v_veh uuid; v_sess uuid; v_stall uuid; v_t0 timestamptz; v_clock timestamptz;
  v_n int; v_deep jsonb; v_tidy jsonb; v_leg record; v_res jsonb; v_had_tidy boolean; v_cycle numeric; v_end timestamptz;
BEGIN
  SELECT vn.visit_id, vn.sim_run_id, vn.vehicle_id, os.id, os.stall_id, os.started_at
    INTO v_visit, v_run, v_veh, v_sess, v_stall, v_t0
    FROM public.ottoq_visit_needs vn
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
    JOIN public.ocpp_sessions os ON os.sim_run_id = vn.sim_run_id AND os.vehicle_id = vn.vehicle_id
    JOIN public.stalls s ON s.id = os.stall_id AND s.stall_type::text = 'dcfc' AND s.ocpp_charger_id IS NOT NULL
   WHERE vn.depot_id = c_depot AND r.depot_id = c_depot
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'interior_deep_clean')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs o
                      WHERE o.vehicle_id = vn.vehicle_id AND o.sim_run_id = vn.sim_run_id AND o.visit_id <> vn.visit_id)
   ORDER BY r.started_at DESC, vn.visit_id, os.started_at LIMIT 1;
  IF v_visit IS NULL THEN
    INSERT INTO _0815_selftest VALUES (jsonb_build_object('ran', false, 'why', 'no past visit to stage'));
    RETURN;
  END IF;
  v_clock := v_t0 + interval '1 minute';
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'cabin_robot_deep_clean', 1, '0815 self-test', now());
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    UPDATE public.ocpp_sessions SET status = 'active', ended_at = NULL WHERE id = v_sess;
    UPDATE public.vehicles SET current_state = 'charging_dcfc', current_stall_id = v_stall, current_soc = 40 WHERE id = v_veh;
    -- the visit as it stood on arrival at the post: the deep clean and any tidy to do, nothing by the arm yet
    UPDATE public.ottoq_visit_needs vn
       SET status = 'open', meta = COALESCE(meta, '{}'::jsonb) - 'arm_routine',
           atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' IN ('interior_deep_clean', 'interior_tidy')
                                          THEN (a - 'started_at' - 'ends_at' - 'done_at' - 'performed_by' - 'robot_stall_id'
                                                  - 'robot_cycle_min' - 'robot_leg_id' - 'item_check' - 'found_item'
                                                  - 'confirm_required' - 'interrupted')
                                               || jsonb_build_object('status', 'pending', 'must_do', true)
                                          ELSE a END ORDER BY ord)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY x(a, ord)
                     WHERE NOT COALESCE((a->>'arm_routine')::boolean, false))
     WHERE vn.visit_id = v_visit;
    UPDATE public.ottoq_itinerary_legs SET status = 'planned', actual_start_sim = NULL, actual_end_sim = NULL
     WHERE sim_run_id = v_run AND vehicle_id = v_veh AND leg_type = 'detail';
    v_had_tidy := EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                           WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_tidy');

    -- the start
    v_n := public.ottoq_start_concurrent_atoms(v_veh, v_clock);
    SELECT a INTO v_deep FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean' LIMIT 1;
    SELECT a INTO v_tidy FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_tidy' LIMIT 1;
    v_cycle := (v_deep->>'robot_cycle_min')::numeric;
    v_end := (v_deep->>'ends_at')::timestamptz;
    IF v_deep->>'status' IS DISTINCT FROM 'in_progress' OR v_deep->>'performed_by' IS DISTINCT FROM 'stall_cabin_robot'
       OR v_deep->>'robot_stall_id' IS DISTINCT FROM v_stall::text OR v_cycle IS DISTINCT FROM 10.8
       OR v_end IS DISTINCT FROM v_clock + interval '648 seconds' THEN
      RAISE EXCEPTION '0815 V3: the arm did not start the deep clean as written (started %, atom %)', v_n, v_deep;
    END IF;
    IF v_had_tidy AND (v_tidy->>'status' IS DISTINCT FROM 'in_progress' OR v_tidy->>'ends_at' IS DISTINCT FROM v_deep->>'ends_at'
                       OR NOT COALESCE((v_tidy->>'with_deep_clean')::boolean, false)) THEN
      RAISE EXCEPTION '0815 V3: the tidy does not run with the deep clean (%)', v_tidy;
    END IF;
    IF (SELECT count(*) FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
         WHERE vn.visit_id = v_visit AND a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' = 'in_progress')
       <> 1 + v_had_tidy::int THEN
      RAISE EXCEPTION '0815 V3: the arm has more work than the one program';
    END IF;
    SELECT l.* INTO v_leg FROM public.ottoq_itinerary_legs l WHERE l.leg_id = (v_deep->>'robot_leg_id')::uuid;
    IF v_leg.status IS DISTINCT FROM 'active' OR v_leg.leg_type IS DISTINCT FROM 'detail' OR v_leg.to_stall_id IS DISTINCT FROM v_stall THEN
      RAISE EXCEPTION '0815 V3: the detail leg is not active at the post (%, %, %)', v_leg.status, v_leg.leg_type, v_leg.to_stall_id;
    END IF;
    -- a second pass while the arm works starts nothing more
    PERFORM public.ottoq_start_concurrent_atoms(v_veh, v_clock + interval '30 seconds');
    IF (SELECT count(*) FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
         WHERE vn.visit_id = v_visit AND a->>'performed_by' = 'stall_cabin_robot') <> 1 + v_had_tidy::int THEN
      RAISE EXCEPTION '0815 V3: a second pass gave the arm more work';
    END IF;
    -- the hold: the car is among those the arm keeps on its post
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a, public.vehicles v
                    WHERE vn.visit_id = v_visit AND v.id = v_veh AND a->>'performed_by' = 'stall_cabin_robot'
                      AND a->>'status' = 'in_progress' AND a->>'robot_stall_id' = v.current_stall_id::text) THEN
      RAISE EXCEPTION '0815 V3: 0758''s hold would not see the deep program';
    END IF;

    -- the end
    UPDATE public.ottoq_sim_runs SET sim_clock_current = v_end + interval '1 second' WHERE sim_run_id = v_run;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_end + interval '1 second');
    SELECT a INTO v_deep FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean' LIMIT 1;
    SELECT a INTO v_tidy FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'svc' = 'interior_tidy' LIMIT 1;
    IF v_deep->>'status' IS DISTINCT FROM 'done' OR (v_had_tidy AND v_tidy->>'status' IS DISTINCT FROM 'done') THEN
      RAISE EXCEPTION '0815 V3: the program did not end as done (deep %, tidy %)', v_deep->>'status', v_tidy->>'status';
    END IF;
    SELECT l.* INTO v_leg FROM public.ottoq_itinerary_legs l WHERE l.leg_id = (v_deep->>'robot_leg_id')::uuid;
    IF v_leg.status IS DISTINCT FROM 'done' OR v_leg.actual_end_sim IS DISTINCT FROM v_end OR v_leg.to_stall_id IS DISTINCT FROM v_stall THEN
      RAISE EXCEPTION '0815 V3: the detail leg did not close at the post with real times (%, %)', v_leg.status, v_leg.actual_end_sim;
    END IF;
    IF public.ottoq_visit_wants_detail(v_veh) THEN
      RAISE EXCEPTION '0815 V3: the car would still be seated for a detail in the wash bay';
    END IF;

    v_res := jsonb_build_object('ran', true, 'visit', v_visit, 'run', v_run, 'post', v_stall, 'cycle_min', v_cycle,
               'tidy_covered', v_had_tidy, 'leg', v_leg.leg_id, 'seat_after', 'wash, doors shut');
    RAISE EXCEPTION USING ERRCODE = 'P0815', MESSAGE = v_res::text;       -- undo everything the test wrote
  EXCEPTION WHEN SQLSTATE 'P0815' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'cabin_robot_deep_clean') THEN
    RAISE EXCEPTION '0815 V3: the self-test left something behind';
  END IF;
  INSERT INTO _0815_selftest VALUES (v_res);
END $v3$;

-- ── §6: on at the twin depot ──
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'cabin_robot_deep_clean', 1,
        'Chase (delegated to Claude Code: 0815)', now());

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0815_the_fast_chargers_arm_does_the_interior_deep_clean_so_no_door_opens_in_the_wash_bay',
        false, false,
        'Behind cabin_robot_deep_clean (default 0, at which no new branch is reached). At the twin depot (1): a car '
        'charging on a fast-charger post has its interior deep clean done by the post''s cleaning arm as a 10.8-minute '
        'program (5.0 a side, an ASSUMPTION pending R-21), with the visit''s interior tidy covered; the planned detail '
        'leg is claimed and closes at the post. A car that never charges on a post keeps the detail seat (rule 9). No '
        'certification arm, canon cell or dial experiment sets the dial. V3 self-test at apply (rolled back): '
        || COALESCE((SELECT result::text FROM _0815_selftest LIMIT 1), 'no result'),
        now());

COMMIT;

-- APPLIED 2026-11-12 at 03:04:15 UTC (9:04 PM CT on 2026-11-11), ledger 20261112030415, through apply_migration, on
--   the first send. No run was live and nothing was in flight (P0). The text sent was this file from BEGIN to COMMIT.
--   V3 (rolled back) staged visit 1a67768c of run 9a909c7b on post 6b043f2d: the arm started the deep clean as a
--   10.8-minute program with the visit's tidy covered, a second pass started nothing more, both ended done, the
--   detail leg 6670dd9c closed at the post with real times, and the car would then be seated for a wash with its
--   doors shut. Stored after the apply, md5(prosrc): ottoq_start_concurrent_atoms 6e70f6eb180101cea1dd43e592052378,
--   ottoq_sim_advance_visit_atoms effa3c91090e874f19521aac4d2933dd, ottoq_sim_cabin_found_items_tick
--   57b9adfbc9ea5334bb22f14f5b564cc7. cabin_robot_deep_clean = 1 at the twin depot. NOT YET SEEN ON A RUN: the check
--   in one demo run (rule 12) is owed, for this file and for 0814.
