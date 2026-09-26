-- migration-version: 20260926052522
-- migration-name:    the_gate_intake_picked_a_stall_its_own_gate_refused_and_each_refusal_left_a_phantom_hold
--
-- 0467  **The gate intake picked a staging stall its own command gate refuses, and every refusal left a phantom
--       hold on a second stall.** `db/checks/0358` §1. FINDINGS G199 (G197's second half, and a source of G195).
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 317d4331 (busy_day, twin depot `11111111-…`), sim 8:00 AM-12:34 PM CT (275 sim-min), measured after its stop:
--     - 61 gate intakes (`gate_intake_no_charge`, 47 cars), every one logged `outcome_status = 'enacted'`.
--       51 of them were refused before they reached the twin: `ottoq_emit_vehicle_command` ran
--       `ottoq_validate_assignment` and answered `target_occupied`, "calendar booking held by <another car>"
--       (41 cars, 14 stalls). The 51 are exactly the 51 intakes that wrote no staging booking.
--     - Each intake emits TWO `proceed_to_stall` commands to the same stall: one carrying `new_state` and `svc_step`,
--       and one carrying only `reason: gate_intake`. So 102 commands were refused, and the refusal reactor rerouted
--       every one, each to its own stall, reserving it for an hour and booking it `temp_hold` for 60 minutes.
--     - At the door the two reroutes of one intake are two stall commands for one car; the door keeps the newest by
--       `(issued_at, command_type, stall_id DESC, command_seq)`, i.e. by stall id. 70 of the 102 reroutes were retired
--       `superseded`, and 34 of those were the ones carrying the step. 49 superseded reroutes had booked a stall:
--       2,775 stall-minutes of `temp_hold` on staging stalls, each held ~56 minutes by a car that was elsewhere and
--       released only by `window_elapsed` or the run's stop. That is about a tenth of the 101 intake staging stalls'
--       275 sim-minutes, and it is the shape G195 measured: bookings held for cars that are not there.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_decide_tick` (3b) picks a staging stall on the POINTER only (no vehicle, no live reservation). The
--       gate every emitted command passes, `ottoq_validate_assignment`, also refuses a stall in maintenance/closed and
--       one whose calendar holds a live booking for ANOTHER car at this moment (held/active/done/interrupted, the
--       EXCLUDE constraint's own state set). The pick asked one question and the gate asked three, so a stall freed on
--       the pointer while its booking was still live (G195) was picked, refused and rerouted.
--   (b) The intake emits a second `proceed_to_stall` to the same stall with no step. When both are accepted, the door
--       retires the duplicate (`duplicate_reissue_of_in_flight_command`, 15 on 317d4331). When both are refused, they
--       become two reroutes to two stalls, one of them wins at random, and the loser's reservation and booking stay.
--       This is the same defect the charge branch (3) had and fixed ("same branch, no conditional between them, so
--       both always fired"); (3b) kept its copy.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The pick walks its own order and takes the first stall `ottoq_validate_assignment` accepts for this car, this
--       command type and this clock: the same function, with the same arguments, that the emit calls next. The cheap
--       pointer predicates stay in front; `OFFSET 0` keeps the validator above the sort so it runs only until it
--       finds a stall (measured: one call on 317d4331's end state, against 101 for a plain filter). The outer ORDER BY
--       repeats the inner one, so the choice never depends on the plan.
--   (b) One command per intake: `reason: gate_intake` joins the surviving command's payload and the second emit is
--       removed.
--
--   The pick now fails only where the gate would have refused, so a refused intake can no longer be logged as enacted,
--   rerouted twice, or leave a hold behind. Nothing else in (3b) changes: the reservation, the itinerary, the staging
--   booking and the decision row are written exactly as before.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The decide tick runs every tick; intake stalls, the command stream, reroutes, bookings and end state move.
--
--   PREDICTED on the next busy_day run: 0 gate-intake commands refused pre-flight; 0 duplicate intake commands;
--   no `temp_hold` reroute booking behind a superseded reroute of an intake; every intake decision has a booking.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0467 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) <> 'b3e35c09aa8baa1d5430ec4e02ec7e29' THEN
    RAISE EXCEPTION '0467 P2: public.ottoq_decide_tick is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('ottoq.ottoq_validate_assignment(uuid,uuid,text,timestamp with time zone,uuid)'::regprocedure))
     <> '8944026f3f4f8ae5ec5417b997d9098a' THEN
    RAISE EXCEPTION '0467 P2: ottoq.ottoq_validate_assignment is not the gate this file reads';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0467_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;

DO $patch_intake$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  -- (a) the pointer-only pick
  v_pat_pick text := $p$SELECT s\.id INTO v_stage_stall FROM stalls s\s+WHERE s\.depot_id = v_depot AND s\.stall_type = 'staging'\s+AND s\.zone IS DISTINCT FROM 'arrival_inspection'\s+AND s\.current_vehicle_id IS NULL\s+AND \(s\.reserved_by IS NULL OR s\.reservation_expires_at <= v_clock\)\s+ORDER BY \(s\.staging_role = 'temp'\) DESC, s\.distance_from_entrance NULLS LAST, s\.id LIMIT 1;$p$;
  v_new_pick text := $r$-- 0467 (G199): take the first stall, in the intake's own order, that the emission gate accepts.
    -- ottoq_emit_vehicle_command refuses pre-flight whatever ottoq_validate_assignment refuses (pointer,
    -- reservation, stall status, and a live calendar booking held by another car at this moment). The pick
    -- asked only the pointer, so 51 of 61 intakes on 317d4331 were refused and rerouted. OFFSET 0 keeps the
    -- validator above the sort, so it runs only until it finds a stall; the outer ORDER BY pins the choice.
    SELECT c.id INTO v_stage_stall
      FROM (SELECT s.id, (s.staging_role = 'temp') AS temp_first, s.distance_from_entrance AS dist
              FROM stalls s
             WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
               AND s.zone IS DISTINCT FROM 'arrival_inspection'
               AND s.current_vehicle_id IS NULL
               AND (s.reserved_by IS NULL OR s.reservation_expires_at <= v_clock)
             ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id
            OFFSET 0) c
     WHERE COALESCE((ottoq.ottoq_validate_assignment(v_req.vehicle_id, c.id, 'proceed_to_stall',
                                                     v_clock, p_sim_run_id)->>'ok')::boolean, false)
     ORDER BY c.temp_first DESC, c.dist NULLS LAST, c.id LIMIT 1;$r$;
  -- (b) the surviving command carries the reason
  v_pat_emit text := $p$jsonb_build_object\('stall_id', v_stage_stall,\s+'new_state', 'staged_awaiting_service',$p$;
  v_new_emit text := $r$jsonb_build_object('stall_id', v_stage_stall,
                                 'reason', 'gate_intake',   -- 0467 (G199): from the second command, removed below
                                 'new_state', 'staged_awaiting_service',$r$;
  -- (b) the second command
  v_pat_dup text := $p$PERFORM ottoq_emit_vehicle_command\(p_sim_run_id, v_depot, v_req\.vehicle_id, 'proceed_to_stall', jsonb_build_object\('stall_id', v_stage_stall, 'reason', 'gate_intake'\), v_clock\);$p$;
  v_new_dup text := $r$-- 0467 (G199): a second proceed_to_stall to the same stall used to follow here, carrying only
      -- `reason` (now on the command above). Refused, the two became two reroutes to two stalls; the door kept
      -- one by stall id and the other's hour-long reservation and booking stayed behind (49 on 317d4331).$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_pick, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0467: the intake pick matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_emit, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0467: the intake command matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_dup, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0467: the second intake command matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat_pick, v_new_pick);
  v_def := regexp_replace(v_def, v_pat_emit, v_new_emit);
  v_def := regexp_replace(v_def, v_pat_dup, v_new_dup);
  EXECUTE v_def;
END $patch_intake$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_d text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
        n int;
BEGIN
  -- V1: the pick asks the gate, once; the intake emits one command, and it carries the reason and the step.
  SELECT count(*) INTO n FROM regexp_matches(v_d, $x$ottoq\.ottoq_validate_assignment\(v_req\.vehicle_id, c\.id, 'proceed_to_stall',$x$, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0467 V1: the validator call appears % times in the pick', n; END IF;
  IF position($x$jsonb_build_object('stall_id', v_stage_stall, 'reason', 'gate_intake')$x$ IN v_d) > 0 THEN
    RAISE EXCEPTION '0467 V1: the second intake command is still there';
  END IF;
  IF position($x$'reason', 'gate_intake',   -- 0467 (G199)$x$ IN v_d) = 0
     OR position($x$'staging_pick','temp_first'$x$ IN v_d) = 0 THEN
    RAISE EXCEPTION '0467 V1: the intake is not the body this file writes';
  END IF;
  -- V1b: the pointer-only pick is gone.
  IF v_d ~ $x$SELECT s\.id INTO v_stage_stall FROM stalls s\s+WHERE s\.depot_id = v_depot AND s\.stall_type = 'staging'$x$ THEN
    RAISE EXCEPTION '0467 V1b: the pointer-only pick is still there';
  END IF;
  -- V2: one overload, same grants (anon never; authenticated and service_role as before).
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'public' AND p.proname = 'ottoq_decide_tick') <> 1 THEN
    RAISE EXCEPTION '0467 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_decide_tick(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_decide_tick(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_decide_tick(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0467 V2: the grants moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0467_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0467_the_gate_intake_picked_a_stall_its_own_gate_refused_and_each_refusal_left_a_phantom_hold', true,
  'Tick path: ottoq_decide_tick (3b) picks the first staging stall ottoq_validate_assignment accepts and emits one '
  'command per intake. Intake stalls, commands, reroutes, bookings and end state move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
