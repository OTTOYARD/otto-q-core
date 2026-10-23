-- migration-version: PENDING
-- migration-name:    every_car_that_charges_gets_the_overhead_arms_cabin_clean
--
-- 0764  **Every car that charges on a robotic post has its cabin cleaned by the post's overhead arm, during the
--       charge.** (G483)
--
-- ══ §0 CHASE'S CALL ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-23 at 6:47 AM CT, watching the first demo run on the 30-post depot (b5e80522, busy_day): "It's
--   running. I don't see the overhead arms working and doors opening, etc." Asked at 7:02 AM CT how the arm should work,
--   he chose "Clean every car": every car that charges gets its doors opened and the overhead arm cleans one side, then
--   the other, during the charge. It is how he described the post on 2026-10-19: "The vehicle doors open up, and then
--   the car begins to mate with the robotic charging arm as the overhead or taller or longer robotic. Cleaning arm
--   reaches inside the vehicle to clean on one side, retracts adjust, and then enters the other side to clean again."
--
-- ══ §1 WHAT THE TWIN DID, MEASURED (run b5e80522, read 2026-10-23 between 6:48 and 7:01 AM CT) ══════════════════════════
--
--   0758's arm takes a car's interior tidy, and the twin derives a tidy for about one visit in four; the charger's
--   sensors inspect every cabin, and the triage clears about a third of the uncertain tidies (the cabin was clean). By
--   sim 14:06, 66 sim-minutes in: 23 interior tidies derived, 6 cleared by the triage, 5 done by the arm, 6 by
--   technicians and 6 still to do, against about 80 fast charges. Every technician's tidy started after its car's
--   charge had ended: on cars that were charging when the run began, whose visits were made after the charge, and on
--   tidies the triage confirmed once the charge was over. So the arms worked on about one charge in sixteen, about one
--   arm at a time across thirty posts: the app showed one cycle (post 28) in 2.5 minutes of watching, and none in the
--   next 5.
--
-- ══ §2 WHAT THIS CHANGES (all behind stall_cabin_robot = 2; at 0 and 1 nothing decides differently) ═══════════════════
--
--   (a) The dial: stall_cabin_robot gains the value 2 (catalog max 1 -> 2). 1 is 0758's arm; 2 is 1, and every car that
--       charges on a fast-charger post has its cabin cleaned by the post's arm during the charge.
--   (b) The starter (public.ottoq_start_concurrent_atoms): at 2, after its pass over the visit's atoms, when the car is
--       charging on a fast-charger post (0758's own test: charging_dcfc on a dcfc stall), its visit has no interior tidy
--       to do, under way or done (none was derived, or the triage cleared it), and the visit's routine has not been
--       decided: if an active session is there and the planner's estimate of the charge left is at least the arm's
--       cycle (0758's own test, so the arm is home before the charge ends and no car waits for it), the arm cleans the
--       cabin now: a new interior_tidy atom, in progress, must-do, performed_by stall_cabin_robot with its stall and
--       cycle as 0758 writes them, arm_routine true, and its own itinerary leg (interior_tidy, active, the post, the
--       cycle's times) on the visit's active itinerary, whose id the atom carries, so the clean ends in a service
--       record like any tidy. If the charge has less than the cycle left, the routine is skipped for the visit: no car
--       waits for a clean it did not need, and a needed tidy still goes to a technician as 0758 leaves it. The decision
--       is recorded once on the visit (meta.arm_routine: when, the outcome, the stall, and for a skip the minutes left
--       and the cycle). With no active session yet nothing is decided, and the next pass looks again. A tidy waiting on
--       the triage is waited for: the triage still decides whether the cabin needs more (an escalation still adds the
--       detail bay's deep clean), and a tidy it confirms is the arm's by 0758's path.
--   (c) The completion step (twin.ottoq_sim_advance_visit_atoms): at 2 its first pass also hands the starter a car
--       charging on a fast-charger post whose visit has no interior tidy to do, under way or done and no routine
--       decided (the pass hands the starter only cars with cabin work pending, so without this the starter would never
--       see such a car); a routine clean closes its own leg, by its id, with real times; and a routine clean whose car
--       left the post before the cycle ended (a charger fault, an emergency: only a path 0758's hold does not cover) is
--       cancelled, its leg skipped, the interruption recorded and nothing credited. It was not a need, so no technician
--       is sent for it.
--   Unchanged: the hold (0758 (c)) keeps the car on its post while the arm works; the technicians still do any needed
--   tidy the arm cannot; the triage, its verdicts and its escalations. Rule 9: nothing a car needs is skipped, and no
--   car waits for the routine. No research arm, cell or experiment sets the dial to 2.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the two bodies are those 0758 left (prosrc md5s, read on live 2026-10-23), 0763 is applied,
--   the dial is catalogued 0..1 as 0758 left it, and no visit carries the routine's keys. P2 once. Pre-images to
--   ottoq_schema_snapshots as '0764_pre'. Each anchor matches once in its function. V1 each body less its changes is its
--   pre-image. V2 the dial is catalogued 0..2, a person's, and this file sets it nowhere.
--   tests/test_every_car_cabin_clean_sql.py runs this file on the scratch PostgreSQL over 0758's fixture and 0758 (the
--   live bodies, md5 asserted): at 0 and at 1 the same world leaves byte-identical visits with and without 0764; at 2 a
--   charging car with no tidy, and one whose tidy the triage cleared, are cleaned by the arm through the completion
--   step's own pass, with a leg that closes by its id and a ledger credit, and take no technician; a tidy waiting on
--   the triage is waited for, and once confirmed is the arm's by 0758's path with no second clean; a needed tidy is
--   0758's; a charge shorter than the cycle is recorded once and skipped; no active session decides nothing; a standard
--   charger is left alone; a routine clean whose car left the post is cancelled, its leg skipped, nothing credited; a
--   visit with no itinerary is still cleaned; and 0764 refuses a second apply, a body it did not read, a database
--   without 0763 and a dial not as 0758 left it.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ══════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: at 0 and 1 the starter and the completion step decide exactly as before (V1; every new branch
--   needs the dial at 2, or an atom or visit key only the dial at 2 writes). forces_dial_restart FALSE: no cell, pair or
--   experiment sets the dial to 2.
--
-- ══ §5 ON AT THE TWIN DEPOT, A PERSON'S (CLAUDE.md rule 12) ════════════════════════════════════════════════════════════
--
--   After this file, in the same sitting:
--     SELECT public.ottoq_policy_set('depot', '11111111-1111-1111-1111-111111111111', 'stall_cabin_robot', 2,
--                                    'chase_2026_10_23');
--   A run reads the dial on every pass (run, then depot, then global), so a run live at the switch takes it from its
--   next pass. The 32 research sweeps at the twin depot are paused (db/checks/0460 (W1)) and no cell sets the dial, so
--   nothing queued changes under it. Undo: the same statement with 1.
--
-- ROLLBACK: EXECUTE the two `definition`s in ottoq_schema_snapshots WHERE label = '0764_pre'; set the dial to 1 wherever
--   it is 2; UPDATE the catalog row back to max_value 1 and 0758's description; DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0764_every_car_that_charges_gets_the_overhead_arms_cabin_clean'. Routine atoms and legs already written
--   stay as the record of the cleans they were.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0764 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the two bodies 0758 left, 0763, the dial as 0758 left it, and no routine anywhere yet ──
DO $p1$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM 'ce0a831c29f421948d2d44f966cff233'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM 'c1741376dc7e9d9597b5e8a15aed42e5' THEN
    RAISE EXCEPTION '0764 P1: a function this file patches is not the body it was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0763_canopy_c_is_restriped_and_the_twin_depot_has_no_standard_chargers') THEN
    RAISE EXCEPTION '0764 P1: 0763 is not applied; apply in order';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'stall_cabin_robot' AND default_value = 0 AND min_value = 0 AND max_value = 1
         AND NOT COALESCE(agent_writable, false)) <> 1 THEN
    RAISE EXCEPTION '0764 P1: stall_cabin_robot is not catalogued 0..1 as 0758 left it';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn
              WHERE COALESCE(vn.meta, '{}'::jsonb) ? 'arm_routine'
                 OR EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                             WHERE a ? 'arm_routine' OR a ? 'robot_leg_id')) THEN
    RAISE EXCEPTION '0764 P1: a visit already carries the routine clean''s keys';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0764_every_car_that_charges_gets_the_overhead_arms_cabin_clean') THEN
    RAISE EXCEPTION '0764 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0764_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'::regprocedure,
                 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure);

-- ── (a) the dial gains 2 ──
UPDATE public.ottoq_policy_param_catalog
   SET max_value = 2,
       description = '0758 (G476), 0764 (G483): 1 = at a fast-charger stall, its cleaning arm does the car''s must-do '
                     'interior tidy while the car charges: it starts as the charge session is active, when the charge has '
                     'at least the arm''s cycle left by the planner''s estimate; it takes no technician; it runs 2 x '
                     'cabin_robot_side_min + cabin_robot_motion_min; and the car stays on the stall until the arm is home. '
                     '2 = 1, and every car that charges on a fast-charger post has its cabin cleaned by the post''s arm '
                     'during the charge, needed or not: when the visit has no interior tidy to do, under way or done, the '
                     'arm cleans it as a routine (arm_routine), with its own itinerary leg, when the charge has at least '
                     'the cycle left, and skips it otherwise, so no car waits for it (Chase, 2026-10-23). 0 = the interior '
                     'tidy waits for a technician, as before 0758.',
       affects = 'public.ottoq_start_concurrent_atoms; ottoq.ottoq_uplink_transfer_holds; twin.ottoq_sim_advance_visit_atoms'
 WHERE param_key = 'stall_cabin_robot';

-- ── the patches: (b) the starter, (c) the completion step ──
CREATE TEMP TABLE _0764_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0764_patch VALUES
  -- S1: the starter's variables for the routine
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 1,
   $s1o$  v_run uuid; v_robot_dial boolean := false; v_robot boolean := false; v_robot_cycle numeric; v_robot_left numeric;
BEGIN
$s1o$,
   $s1n$  v_run uuid; v_robot_dial boolean := false; v_robot boolean := false; v_robot_cycle numeric; v_robot_left numeric;
  -- 0764: the arm cleans every car that charges on its post (stall_cabin_robot 2), once a visit, with its own leg
  v_robot_every boolean := false; v_meta jsonb; v_itin uuid; v_leg uuid; v_routine jsonb;
BEGIN
$s1n$),
  -- S2: the dial at 2
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 2,
   $s2o$  v_robot_dial := COALESCE(public.ottoq_policy_get(v_run, 'stall_cabin_robot', 0), 0) >= 1;
$s2o$,
   $s2n$  v_robot_dial := COALESCE(public.ottoq_policy_get(v_run, 'stall_cabin_robot', 0), 0) >= 1;
  v_robot_every := COALESCE(public.ottoq_policy_get(v_run, 'stall_cabin_robot', 0), 0) >= 2;   -- 0764
$s2n$),
  -- S3: the routine, after the pass over the visit's atoms
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 3,
   $s3o$    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;
  IF v_started > 0 OR (v_needs_triage AND NOT v_has_triage) THEN
$s3o$,
   $s3n$    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;
  -- 0764: with stall_cabin_robot at 2, the post's arm cleans the cabin of every car that charges on it, needed or not
  -- (Chase, 2026-10-23). v_robot_cycle is set only for a car charging on a fast-charger stall with the dial on (above).
  -- When the visit has no interior tidy to do, under way or done (none derived, or the triage cleared it; one waiting
  -- on the triage is waited for, and one this pass started is the arm's by 0758's branch), the arm cleans it as a
  -- routine when the charge has at least the cycle left by the same estimate, so it is home before the charge ends,
  -- with its own leg so the clean ends in a service record. A shorter charge skips it, so no car waits for it. The
  -- decision is recorded once on the visit; with no active session yet (no estimate) nothing is decided.
  IF v_robot_every AND v_robot_cycle IS NOT NULL THEN
    SELECT meta INTO v_meta FROM ottoq_visit_needs WHERE visit_id = v_visit;
    IF NOT (COALESCE(v_meta, '{}'::jsonb) ? 'arm_routine')
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) t
                        WHERE t->>'svc' = 'interior_tidy'
                          AND COALESCE(t->>'status', 'pending') IN ('pending', 'in_progress', 'done')) THEN
      IF v_robot THEN
        SELECT i.itinerary_id INTO v_itin FROM ottoq_vehicle_itineraries i
         WHERE i.visit_id = v_visit AND i.status = 'active'
         ORDER BY i.sim_created_at DESC NULLS LAST, i.itinerary_id LIMIT 1;
        IF v_itin IS NOT NULL THEN
          INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, to_stall_id,
                                            planned_start_sim, planned_end_sim, planned_duration_s, duration_basis,
                                            actual_start_sim, status)
          SELECT v_itin, v_run, p_vehicle, COALESCE(max(l.seq), 0) + 1, 'interior_tidy', v_stall,
                 p_clock, p_clock + make_interval(secs => (round(v_robot_cycle * 60))::double precision),
                 round(v_robot_cycle * 60),
                 jsonb_build_object('atom', 'interior_tidy', 'kind', 'stall_cabin_robot', 'arm_routine', true,
                                    'concurrent_with', 'charge'),
                 p_clock, 'active'
            FROM ottoq_itinerary_legs l WHERE l.itinerary_id = v_itin
          RETURNING leg_id INTO v_leg;
        END IF;
        v_new := v_new || jsonb_build_array(jsonb_build_object(
                   'svc', 'interior_tidy', 'must_do', true, 'deferrable', false, 'est_min', v_robot_cycle,
                   'concurrency', 'cabin', 'status', 'in_progress', 'started_at', to_jsonb(p_clock),
                   'ends_at', to_jsonb(p_clock + make_interval(secs => (round(v_robot_cycle * 60))::double precision)),
                   'performed_by', 'stall_cabin_robot', 'robot_stall_id', v_stall, 'robot_cycle_min', v_robot_cycle,
                   'arm_routine', true, 'robot_leg_id', v_leg));
        v_started := v_started + 1;
        v_routine := jsonb_build_object('at', p_clock, 'outcome', 'cleaned', 'stall_id', v_stall);
      ELSIF v_robot_left IS NOT NULL THEN
        v_routine := jsonb_build_object('at', p_clock, 'outcome', 'charge_shorter_than_the_cycle', 'stall_id', v_stall,
                                        'charge_left_min', round(v_robot_left, 1), 'cycle_min', v_robot_cycle);
      END IF;
      IF v_routine IS NOT NULL THEN
        UPDATE ottoq_visit_needs SET meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object('arm_routine', v_routine)
         WHERE visit_id = v_visit;
      END IF;
    END IF;
  END IF;
  IF v_started > 0 OR (v_needs_triage AND NOT v_has_triage) THEN
$s3n$),
  -- A1: the completion step's variable
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 1,
   $a1o$  v_escalations jsonb; v_tick bigint; v_feed_sim boolean := true;
BEGIN
$a1o$,
   $a1n$  v_escalations jsonb; v_tick bigint; v_feed_sim boolean := true;
  v_arm_every boolean := false;   -- 0764: stall_cabin_robot at 2, the arm cleans every car that charges on its post
BEGIN
$a1n$),
  -- A2: the dial at 2
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 2,
   $a2o$  v_feed_sim := COALESCE(v_feed_sim, true);
$a2o$,
   $a2n$  v_feed_sim := COALESCE(v_feed_sim, true);
  v_arm_every := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 2;   -- 0764
$a2n$),
  -- A3, A4: the first pass also hands the starter a charging car whose cabin has no work and no routine decided
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 3,
   $a3o$       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE COALESCE(a->>'status','pending') = 'pending'
                      AND a->>'svc' <> 'readiness_check'
$a3o$,
   $a3n$       AND (EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE COALESCE(a->>'status','pending') = 'pending'
                      AND a->>'svc' <> 'readiness_check'
$a3n$),
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 4,
   $a4o$                                                         AND su.stall_type::text IN ('dcfc','l2','service_bay')))) ))
     ORDER BY (vn.urgency = 'immediate_dispatch') DESC,
$a4o$,
   $a4n$                                                         AND su.stall_type::text IN ('dcfc','l2','service_bay')))) ))
            -- 0764: with stall_cabin_robot at 2, a car charging on a fast-charger post whose visit has no interior
            -- tidy to do, under way or done, and no routine decided, so the starter can have the post's arm clean it
            OR (v_arm_every AND v.current_state = 'charging_dcfc'
                AND NOT (COALESCE(vn.meta, '{}'::jsonb) ? 'arm_routine')
                AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) t
                                 WHERE t->>'svc' = 'interior_tidy'
                                   AND COALESCE(t->>'status', 'pending') IN ('pending', 'in_progress', 'done'))
                AND EXISTS (SELECT 1 FROM stalls sd
                             WHERE sd.id = v.current_stall_id AND sd.stall_type::text = 'dcfc')))
     ORDER BY (vn.urgency = 'immediate_dispatch') DESC,
$a4n$),
  -- A5: a routine clean whose car left the post is cancelled, not sent to a technician
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 5,
   $a5o$      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'stall_cabin_robot' AND v_a->>'robot_stall_id' IS NOT NULL
         AND v_rec.current_stall_id::text IS DISTINCT FROM v_a->>'robot_stall_id' THEN
$a5o$,
   $a5n$      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'stall_cabin_robot' AND v_a->>'robot_stall_id' IS NOT NULL
         AND COALESCE((v_a->>'arm_routine')::boolean, false)
         AND v_rec.current_stall_id::text IS DISTINCT FROM v_a->>'robot_stall_id' THEN
        -- 0764: the arm's routine clean of a car that left the post before the cycle ended (a charger fault, an
        -- emergency). It was not a need, so it is cancelled rather than sent to a technician: its leg skipped, the
        -- interruption recorded, nothing credited.
        v_a := v_a || jsonb_build_object('status', 'cancelled',
                 'interrupted', COALESCE(v_a->'interrupted', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                     'at', p_clock, 'reason', 'left_the_cabin_robot',
                     'started_at', v_a->'started_at', 'stall_id', v_a->'robot_stall_id')));
        UPDATE ottoq_itinerary_legs SET status = 'skipped', actual_end_sim = p_clock
         WHERE leg_id = (v_a->>'robot_leg_id')::uuid AND status IN ('planned', 'active');
        v_changed := true;
      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'stall_cabin_robot' AND v_a->>'robot_stall_id' IS NOT NULL
         AND v_rec.current_stall_id::text IS DISTINCT FROM v_a->>'robot_stall_id' THEN
$a5n$),
  -- A6: a routine clean closes its own leg, by its id
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 6,
   $a6o$        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc',
                (v_a->>'started_at')::timestamptz, (v_a->>'ends_at')::timestamptz);
$a6o$,
   $a6n$        IF COALESCE((v_a->>'arm_routine')::boolean, false) AND v_a->>'robot_leg_id' IS NOT NULL THEN
          -- 0764: the arm's routine clean closes its own leg, by its id, with real times, as ottoq_close_atom_leg would
          UPDATE ottoq_itinerary_legs
             SET status = 'done', to_stall_id = COALESCE(to_stall_id, v_rec.current_stall_id),
                 actual_start_sim = COALESCE(actual_start_sim, (v_a->>'started_at')::timestamptz),
                 actual_end_sim = (v_a->>'ends_at')::timestamptz,
                 deviation_s = CASE WHEN planned_end_sim IS NULL THEN NULL
                                    ELSE EXTRACT(EPOCH FROM ((v_a->>'ends_at')::timestamptz - planned_end_sim))::int END
           WHERE leg_id = (v_a->>'robot_leg_id')::uuid AND status IN ('planned', 'active');
        ELSE
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc',
                (v_a->>'started_at')::timestamptz, (v_a->>'ends_at')::timestamptz);
        END IF;
$a6n$);

DO $patch$
DECLARE f text; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0764_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(f::regprocedure);
    FOR p IN SELECT * FROM _0764_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0764: anchor % of % matches % times, not 1', p.seq, f, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f::regprocedure) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0764: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each body less its changes is its pre-image ──
DO $v1$
DECLARE r record; p record; v_body text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
             ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 'ce0a831c29f421948d2d44f966cff233'),
             ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 'c1741376dc7e9d9597b5e8a15aed42e5'))
             AS x(fn, pre) LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = r.fn::regprocedure;
    FOR p IN SELECT * FROM _0764_patch WHERE fn = r.fn ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM r.pre THEN
      RAISE EXCEPTION '0764 V1: % less its changes is not its pre-image (md5 %)', r.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: the dial, as declared, and set nowhere by this file ──
DO $v2$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'stall_cabin_robot' AND default_value = 0 AND min_value = 0 AND max_value = 2
         AND NOT COALESCE(agent_writable, false) AND description LIKE '%0764 (G483)%') <> 1
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'stall_cabin_robot' AND param_value >= 2) THEN
    RAISE EXCEPTION '0764 V2: the dial is not catalogued 0..2 as declared, or a parameter row sets it to 2';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0764_every_car_that_charges_gets_the_overhead_arms_cabin_clean', false, false,
        'G483. stall_cabin_robot gains 2 (catalog max 1 -> 2). At 2, public.ottoq_start_concurrent_atoms, after its pass, '
        'has the fast-charger post''s arm clean the cabin of a car charging there whose visit has no interior tidy to '
        'do, under way or done and no routine decided: an interior_tidy atom in progress, performed_by '
        'stall_cabin_robot, arm_routine true, with its own active itinerary leg (robot_leg_id), when the planner''s '
        'estimate of the charge left is at least the arm''s cycle; a shorter charge skips it; the decision is recorded '
        'once in the visit''s meta.arm_routine. twin.ottoq_sim_advance_visit_atoms hands the starter such a car, closes '
        'a routine clean''s leg by its id, and cancels a routine clean whose car left the post (leg skipped, nothing '
        'credited). At 0 and 1 none of it runs (V1). No certification arm, canon cell or dial experiment sets the dial '
        'to 2.',
        now());

COMMIT;
