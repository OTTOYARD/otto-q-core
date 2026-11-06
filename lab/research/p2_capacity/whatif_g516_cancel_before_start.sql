-- What-if for a lab day only (capacity_day.py --lab-sql): G516's fix, as a candidate for a migration.
--
-- The post's cleaning arm begins a routine clean of every car that charges on its post (0764). When a charger faults at
-- plug-in the car leaves the post at once, but the routine stays "in progress" until its planned end (5.8 minutes), so
-- the starter (0767) cannot begin it again at the car's next post; and twin.ottoq_sim_advance_visit_atoms runs its
-- starter before its completion step, so even a routine cancelled the tick its car left would be begun again only a tick
-- later. A short second charge (5-10 minutes) is over by then, and the car leaves without the clean (FINDINGS G516:
-- 3 of the 6 cut short at 150 cars).
--
-- The change: a pass before the starter cancels the arm's routine of any car no longer on the routine's post, whatever
-- its planned end, exactly as the 0764 branch of the completion step cancels it (status cancelled, the interruption
-- recorded with reason left_the_cabin_robot, its leg skipped, nothing credited). The starter then sees it cancelled and
-- interrupted, and 0767's condition lets it begin the routine at the car's current post in the same pass. Nothing else
-- in the function changes.
DO $whatif$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid, timestamp with time zone)'::regprocedure);
  c_anchor constant text := $a$  v_arm_every := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 2;   -- 0764
$a$;
  c_insert constant text := $i$
  -- G516 (lab what-if): the arm's routine clean of a car no longer on the routine's post is cancelled now, whatever its
  -- planned end, before the starter runs, so 0767's starter can begin it at the car's next post in this same pass.
  IF v_feed_sim AND v_arm_every THEN
    FOR v_rec IN
      SELECT vn.visit_id, vn.atoms, v.current_stall_id
        FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
       WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
         AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
             = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                      WHERE a->>'status' = 'in_progress' AND a->>'performed_by' = 'stall_cabin_robot'
                        AND COALESCE((a->>'arm_routine')::boolean, false) AND a->>'robot_stall_id' IS NOT NULL
                        AND v.current_stall_id::text IS DISTINCT FROM a->>'robot_stall_id')
       ORDER BY vn.vehicle_id
    LOOP
      v_new := '[]'::jsonb;
      FOR v_a IN SELECT x.e FROM jsonb_array_elements(v_rec.atoms) WITH ORDINALITY AS x(e, o) ORDER BY x.o LOOP
        IF v_a->>'status' = 'in_progress' AND v_a->>'performed_by' = 'stall_cabin_robot'
           AND COALESCE((v_a->>'arm_routine')::boolean, false) AND v_a->>'robot_stall_id' IS NOT NULL
           AND v_rec.current_stall_id::text IS DISTINCT FROM v_a->>'robot_stall_id' THEN
          v_a := v_a || jsonb_build_object('status', 'cancelled',
                   'interrupted', COALESCE(v_a->'interrupted', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                       'at', p_clock, 'reason', 'left_the_cabin_robot',
                       'started_at', v_a->'started_at', 'stall_id', v_a->'robot_stall_id')));
          UPDATE ottoq_itinerary_legs SET status = 'skipped', actual_end_sim = p_clock
           WHERE leg_id = (v_a->>'robot_leg_id')::uuid AND status IN ('planned', 'active');
        END IF;
        v_new := v_new || jsonb_build_array(v_a);
      END LOOP;
      UPDATE ottoq_visit_needs SET atoms = v_new WHERE visit_id = v_rec.visit_id;
    END LOOP;
  END IF;
$i$;
BEGIN
  IF (length(v_def) - length(replace(v_def, c_anchor, ''))) / length(c_anchor) <> 1 THEN
    RAISE EXCEPTION 'G516 what-if: anchor not found exactly once in twin.ottoq_sim_advance_visit_atoms';
  END IF;
  EXECUTE replace(v_def, c_anchor, c_anchor || c_insert);
END
$whatif$;
