-- migration-version: 20261106132144
-- migration-name:    the_arm_is_offered_a_car_again_after_the_ticks_completions_and_a_car_off_its_post_is_let_go_at_once
--
-- 0798  **The post's arm is offered a charging car again after the tick's completions, and a routine whose car has left
--        the post is cancelled at once.** (G516)
--
-- ══ §0 CHASE'S CALL, WHICH THIS FILE CARRIES OUT ═════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-23 (0765 §0): "cars should be cleaned via overhead arm while they charge always regardless". The dial
--   stall_cabin_robot has been 2 at the twin depot since then, by Chase; 0764, 0765 and 0767 make 2 clean every car that
--   charges on a fast-charger post, an owner's immediate turnaround on a charge shorter than the arm's cycle excepted.
--   Under the delegation of 2026-11-06 01:24 UTC ("continue building as needed. You're the expert").
--
-- ══ §1 WHAT IS LEFT, MEASURED (the research lab, a copy of production's engine; FINDINGS G516) ══════════════════════════
--
--   twin.ottoq_sim_advance_visit_atoms offers a charging car to the starter (public.ottoq_start_concurrent_atoms) at the
--   top of its pass, before its completion step. Two things the completion step does make a car newly eligible for the
--   routine in the middle of the tick, and neither car is offered again until the next tick, by which time a short
--   charge has ended and the car has left the post:
--   (a) the cabin triage clears a tidy the car turned out not to need: the routine waits on the triage (0764), and the
--       triage completes in the completion step. On the lab's 24-hour normal day at 116 cars (seed 171717, read
--       2026-11-06 between 03:07 and 03:14 UTC) six of the seven fast-charge visits that left with no routine decided are
--       this case: the triage cleared the tidy in the tick the charge ended (e.g. visit 1b8524ef, plugged in 6:40 AM,
--       triage done and charge complete at 6:50, gone at 7:00).
--   (b) 0764's completion branch cancels a routine whose car left the post only when its 5.8-minute cycle would have
--       ended, so a car moved off its post by a charger fault keeps an "in progress" routine on the dead post until then,
--       and 0767's starter cannot begin it again at the car's next post: on the 150-car day (seed 171717) six routines
--       were cut short by a charger fault at plug-in and three of those cars left with the clean cancelled. Cancelling
--       such a routine before the starter (lab what-if whatif_g516_cancel_before_start.sql) took that 3 to 1, and the one
--       left was case (a)'s timing: the car moved off the post later in the tick than the pass.
--   Not a rule-9 breach: the routine is a promise to every charging car (0764), not a need, and a needed tidy the triage
--   cleared was not needed. It is the promise Chase made "always regardless", kept late or not at all for these cars.
--
-- ══ §2 WHAT THIS CHANGES (at stall_cabin_robot = 2 only; at 0 and 1 nothing decides differently) ══════════════════════
--
--   Two anchored insertions in twin.ottoq_sim_advance_visit_atoms, both inside `IF v_feed_sim AND v_arm_every`:
--   (1) before the starter: the arm's routine clean of a car no longer on the routine's post is cancelled now, whatever
--       its planned end, exactly as 0764's completion branch cancels it (status cancelled, the interruption recorded as
--       'left_the_cabin_robot' with the post, its leg skipped, nothing credited). 0767's test then reads it as undecided,
--       so the starter can begin it at the car's current post in the same pass.
--   (2) after the completion step: the cars still charging on a fast-charger post whose visit has no interior tidy to do
--       and no routine decided (or 0767's routine to decide again) are offered to the starter once more, by the same
--       predicate the top of the pass uses for 0764's branch. The starter is unchanged: it decides the routine (the hold
--       keeps the car on its post until the arm is home, 0765; an owner's immediate turnaround on a short charge is
--       recorded and not held).
--   A car is offered at most twice a tick, in vehicle order; a second offer of a car the first one already decided does
--   nothing (the routine is recorded on the visit).
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the completion step is the body 0767 left and production carries (prosrc md5 99f6aa09,
--   read 2026-11-06 03:37:45 UTC), 0767 is applied, and the dial is catalogued 0..2 with 0767's description. P2 once.
--   The pre-image to ottoq_schema_snapshots as '0798_pre'. Each anchor matches once, read with bare newlines whatever line
--   endings the paste carried. V1 the body less its changes is its pre-image. V3 the patched body is byte for byte the
--   one the lab ran (md5). The research lab ran this file on a copy of its template (ottoq_lab_0798) and the lab days
--   from it (lab/research/p2_capacity/jobs_2026-11-06_g516ab.txt): see §6 when they are read.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ══════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: at 0 and 1 the completion step decides exactly as before (V1; both insertions are inside the
--   branch the dial at 2 opens), and no certification arm, canon cell or dial experiment sets the dial to 2.
--   forces_dial_restart FALSE: no experiment varies it.
--
-- ══ §5 ON AT THE TWIN DEPOT (CLAUDE.md rule 12) ═════════════════════════════════════════════════════════════════════════
--
--   The twin depot's dial has been 2 since 0764, by Chase, and this file makes 2 do what it promises, so it is on from
--   each run's next pass after the apply. No statement is needed. Undo: the rollback below.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0798_pre'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name =
--   '0798_the_arm_is_offered_a_car_again_after_the_ticks_completions_and_a_car_off_its_post_is_let_go_at_once'. Cleans,
--   cancellations and legs already written stay as the record of what happened.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0798 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body this file was written against, 0767, and the dial as 0767 left it ──
DO $p1$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM '99f6aa09e973fcb914ae67f1328c0d49' THEN
    RAISE EXCEPTION '0798 P1: twin.ottoq_sim_advance_visit_atoms is not the body this file was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0767_a_cabin_clean_a_charger_fault_cut_short_is_done_at_the_cars_next_post') THEN
    RAISE EXCEPTION '0798 P1: 0767 is not applied; apply in order';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'stall_cabin_robot' AND default_value = 0 AND min_value = 0 AND max_value = 2
         AND NOT COALESCE(agent_writable, false) AND description LIKE '%0767 (G486):%') <> 1 THEN
    RAISE EXCEPTION '0798 P1: stall_cabin_robot is not catalogued 0..2 as 0767 left it';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0798_the_arm_is_offered_a_car_again_after_the_ticks_completions_and_a_car_off_its_post_is_let_go_at_once') THEN
    RAISE EXCEPTION '0798 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0798_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure;

-- ── the patches ──
CREATE TEMP TABLE _0798_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0798_patch VALUES
  -- (1) before the starter: a routine whose car has left the post is cancelled at once
  (1,
   $p1o$  v_arm_every := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 2;   -- 0764
$p1o$,
   $p1n$  v_arm_every := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 2;   -- 0764

  -- 0798 (G516): the arm's routine clean of a car no longer on the routine's post is cancelled now, whatever its
  -- planned end, before the starter runs, so 0767's starter can begin it at the car's current post in this same pass.
  -- As 0764's completion branch cancels it: the interruption recorded with the post, its leg skipped, nothing credited.
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
$p1n$),
  -- (2) after the completion step: the cars it made eligible are offered to the starter again
  (2,
   $p2o$
  UPDATE ottoq_visit_needs vn SET status =
    CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                       WHERE COALESCE((a->>'carryover_eligible')::boolean,false)$p2o$,
   $p2n$
  -- 0798 (G516): after this pass's completions, the cars still charging on a fast-charger post that the completions
  -- made eligible for the arm's routine (a triage that cleared the tidy, a routine cancelled because its car left the
  -- post) are offered to the starter again, by the predicate the top of the pass uses for 0764's branch, so a short
  -- charge does not end before the next pass.
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

  UPDATE ottoq_visit_needs vn SET status =
    CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                       WHERE COALESCE((a->>'carryover_eligible')::boolean,false)$p2n$);

-- A paste can arrive with Windows line endings; the stored body ends its lines in a bare newline, so the anchors and
-- their replacements are read with bare newlines.
UPDATE _0798_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0798_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0798: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0798: twin.ottoq_sim_advance_visit_atoms is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the body less its changes is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0798_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '99f6aa09e973fcb914ae67f1328c0d49' THEN
    RAISE EXCEPTION '0798 V1: the body less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V3: the patched body is byte for byte the one the research lab ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM 'd5400144f61d8eb3d2f2123571f32084' THEN
    RAISE EXCEPTION '0798 V3: the patched body is not the one the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure);
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0798_the_arm_is_offered_a_car_again_after_the_ticks_completions_and_a_car_off_its_post_is_let_go_at_once',
        false, false,
        'G516. At stall_cabin_robot 2: twin.ottoq_sim_advance_visit_atoms cancels the arm''s routine of a car no longer '
        'on the routine''s post before the starter runs (as 0764''s completion branch does at the cycle''s end), and '
        'after the completion step offers the starter once more the cars still charging on a fast-charger post that '
        'have no tidy to do and no routine decided (or 0767''s to decide again). At 0 and 1 none of it runs (V1). No '
        'certification arm, canon cell or dial experiment sets the dial to 2.',
        now());

COMMIT;

-- APPLIED 2026-11-06 at 13:21:44 UTC (7:21 AM CT), ledger 20261106132144, through apply_migration, on Chase's word ("Yes,
--   just keep building", read 2026-11-06 by 13:20 UTC, in reply to the report that asked "approve 0798, 0799, 0800, 0801,
--   0802"). Nothing live (no run running), 0798 not in the lineage, and the function at the md5 P1 names, 99f6aa09 (read
--   13:20:36 UTC). The text sent was this file before its version line and this footer were set: 17,093 bytes, md5
--   e97b18b7aded4bb0ab73fa3ff9a19311, equal to the ledger's statements[1] read back. P0, P1, P2, the anchors, V1 and V3
--   passed inside the apply. Read back at 13:21:52 UTC: md5(prosrc) of twin.ottoq_sim_advance_visit_atoms d5400144, the
--   body ottoq_lab_0798 ran; the lineage row FALSE/FALSE at 13:21:44. On at the twin depot from each run's next pass
--   (stall_cabin_robot has been 2 since 0764). Not yet seen in a demo run (rule 12): none has started since. The lab
--   template ottoq_lab took the same text and ledger row at 13:28 UTC and holds the same body (d5400144).
