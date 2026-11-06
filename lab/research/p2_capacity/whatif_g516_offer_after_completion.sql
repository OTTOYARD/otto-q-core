-- What-if for a lab day only (capacity_day.py --lab-sql): G516's second half, as a candidate for a migration. Run it
-- with whatif_g516_cancel_before_start.sql (the first half); each anchors on its own text and the two do not overlap.
--
-- The post's cleaning arm cleans every car that charges on its post (0764, Chase 2026-10-23: "always regardless"), and
-- twin.ottoq_sim_advance_visit_atoms offers a charging car to the starter (ottoq_start_concurrent_atoms) only at the top
-- of its pass, before its completion step. Two things the completion step does make a car newly eligible for the
-- routine in the middle of the tick: the cabin triage clears a needed tidy the car turned out not to need (the routine
-- waits on the triage, 0764), and 0764's branch cancels a routine whose car left the post. Neither car is offered again
-- until the next tick, and a short charge is over by then: later in the same tick the charge ends and the car leaves the
-- post. On the 24-hour lab day at 116 cars (seed 171717, read 2026-11-06 between 03:07 and 03:14 UTC) six of the seven fast-charge visits
-- that left with no routine decided are this case: the triage cleared the tidy in the tick the charge ended.
--
-- The change: after the completion step, the cars still charging on a fast-charger post whose visit has no interior
-- tidy to do and no routine decided (or 0767's routine to decide again) are offered to the starter once more, with the
-- same predicate the top of the pass uses for 0764's branch. The starter is unchanged: it decides the routine (the hold
-- keeps the car on its post until the arm is home, 0765; an owner's immediate turnaround on a short charge is recorded
-- and not held). Nothing else in the function changes.
DO $whatif$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid, timestamp with time zone)'::regprocedure);
  c_anchor constant text := $a$
  UPDATE ottoq_visit_needs vn SET status =
    CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                       WHERE COALESCE((a->>'carryover_eligible')::boolean,false)$a$;
  c_insert constant text := $i$
  -- G516 (lab what-if, second half): after this pass's completions, the cars still charging on a fast-charger post that
  -- the completions made eligible for the arm's routine (a triage that cleared the tidy, a routine cancelled because its
  -- car left the post) are offered to the starter again, so a short charge does not end before the next pass.
  IF v_feed_sim AND v_arm_every THEN
    FOR v_rec IN
      SELECT vn.vehicle_id
        FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
       WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
         AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
             = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         AND v.current_state = 'charging_dcfc'
         AND (NOT (COALESCE(vn.meta, '{}'::jsonb) ? 'arm_routine')
              OR (vn.meta -> 'arm_routine' ->> 'outcome' = 'cleaned'
                  AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) r
                               WHERE r->>'svc' = 'interior_tidy' AND COALESCE((r->>'arm_routine')::boolean, false)
                                 AND r->>'status' = 'cancelled' AND r ? 'interrupted')))
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) t
                          WHERE t->>'svc' = 'interior_tidy'
                            AND COALESCE(t->>'status', 'pending') IN ('pending', 'in_progress', 'done'))
         AND EXISTS (SELECT 1 FROM stalls sd WHERE sd.id = v.current_stall_id AND sd.stall_type::text = 'dcfc')
       ORDER BY vn.vehicle_id
    LOOP
      PERFORM ottoq_start_concurrent_atoms(v_rec.vehicle_id, p_clock);
    END LOOP;
  END IF;
$i$;
BEGIN
  IF (length(v_def) - length(replace(v_def, c_anchor, ''))) / length(c_anchor) <> 1 THEN
    RAISE EXCEPTION 'G516 second-half what-if: anchor not found exactly once in twin.ottoq_sim_advance_visit_atoms';
  END IF;
  EXECUTE replace(v_def, c_anchor, c_insert || c_anchor);
END
$whatif$;
