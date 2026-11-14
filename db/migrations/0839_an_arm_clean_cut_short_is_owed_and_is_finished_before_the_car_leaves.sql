-- migration-version: 20261114182421
-- migration-name:    0839_an_arm_clean_cut_short_is_owed_and_is_finished_before_the_car_leaves
--
-- 0839  **An arm clean that was cut short is owed: it goes back on the visit as a needed tidy, and the car does not
--        leave until it is done.**
--
-- WHY. Chase, 2026-11-14: "start cleaning up ... arm clean cut short by a fault, and make sure vehicles that still
--   have open needs, but have to get reassigned due to a depot hardware fault ... still get routed via OTTO-Q to
--   stalls or temporary hold and then get reassigned and orchestrated to another stall once available to complete
--   open services or needs". And 2026-11-13: charge and clean are one stop.
--
-- §1 WHAT WAS SO (read 2026-11-14 on run a7345255, twin depot; the only hardware fault the twin injects is a charger
--   fault: 17 of 17 arm.emergency_release events are a charger fault's).
--   The charge after a fault is handled: 24 faulted sessions, 24 cars moved to a staging stall on a temp_hold
--   booking, 23 seated on another charger (median 2 minutes later, the longest 74), the other already at 99% or
--   more. Of 304 departures none left below 99% and none with an open atom on an open visit.
--   The arm's ROUTINE clean is not handled the same way. When its car leaves the post before the arm is home the
--   routine is cancelled (0764, 0798), and it is begun again only if the car CHARGES again on a post (0767). A car
--   whose charge is counted done at the fault never charges again on that visit, a cancelled atom is not an open one,
--   and the car leaves not cleaned by anyone: run 1902d13b, d9d2a011 (db/checks/0491). On the last two runs the two
--   cut-short routines were both done again at the next post (a Gravity, a Model Y), so this is the rarer branch.
--
-- §2 WHAT THIS DOES. public.ottoq_reopen_cut_short_arm_cleans(run, clock): on an open visit whose arm routine was
--   cancelled as interrupted, with no interior tidy pending, under way or done since, and no deep clean done or under
--   way by the arm, and whose car is not charging on a fast charger now (0767 owns that case), it writes one needed
--   interior tidy on the visit (must_do, not deferrable), marked `owed_from: arm_routine_cut_short`. From there the
--   engine's own doors do the rest: a car with charge still to do has the tidy done by its next post's arm; a car
--   with none has it done where it stands by a technician; and public.ottoq_departure_clear holds the car until it
--   is done. twin.ottoq_sim_advance_visit_atoms calls it each tick, after it cancels such routines and before the
--   starter runs. Behind `arm_clean_cut_short_is_owed` (default 0; 1 at the twin depot).
--
-- §3 WHAT IT COSTS, AND WHAT IT DOES NOT DO. A car whose routine was cut short and that does not charge again waits
--   for a technician's tidy (est. 5 minutes) before it leaves, where it left at once. It does not change where a
--   faulted car goes (the temp hold and the re-seat are as they were), and it adds no fault of another kind to the
--   twin: a wash-bay, service-bay or cleaning-arm fault is still not injected, so those paths are not exercised.
--
-- (This file was first numbered 0834; another branch had applied its own 0834 to 0838 by 2026-11-14 15:40 UTC.)
--
-- §4 PRECONDITIONS AND CHECKS. P0 no certification in flight. P1 the tick step's body (md5 of prosrc). P2 once.
--   V1 the patched body with its patch reversed is its pre-image. V2 the anchor matched once. V3 on a visit made for
--   the test inside this transaction and removed again: the function writes the tidy once, not twice, and
--   ottoq_departure_clear is false for the car while it is open.
--
-- §5 CLASSIFICATION. forces_recert TRUE, forces_dial_restart FALSE.
--
-- ROLLBACK: DELETE FROM public.ottoq_policy_params WHERE param_key = 'arm_clean_cut_short_is_owed'; EXECUTE the
--   `definition` in ottoq_schema_snapshots WHERE label = '0839_pre'; DROP FUNCTION
--   public.ottoq_reopen_cut_short_arm_cleans(uuid, timestamptz); DELETE FROM public.ottoq_policy_param_catalog WHERE
--   param_key = 'arm_clean_cut_short_is_owed'; DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0839_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0839 P0: a certification is in flight'; END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'))
     IS DISTINCT FROM 'a29050986cb6920be7959618eab381c2' THEN
    RAISE EXCEPTION '0839 P1: twin.ottoq_sim_advance_visit_atoms is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0839_%') THEN RAISE EXCEPTION '0839 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0839_pre', 'function', 'twin', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)']) AS f;

INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('arm_clean_cut_short_is_owed',
        '0839: 1 = an arm routine clean cancelled because its car left the post (a charger fault) is written back on the visit as a needed interior tidy when the car is not charging again, so it is done before the car leaves. 0 = as before 0839.',
        0, 0, 1, 'public.ottoq_reopen_cut_short_arm_cleans', false);

CREATE FUNCTION public.ottoq_reopen_cut_short_arm_cleans(p_sim_run_id uuid, p_clock timestamptz)
 RETURNS integer LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0839: an arm routine clean that was cut short (0764 and 0798 cancel it when its car leaves the post) is owed. For a
   car that is not charging on a fast charger now, it is written back on the open visit as one needed interior tidy.
   The starter, the next post's arm or a technician, and ottoq_departure_clear take it from there. Returns the number
   of visits written. It never raises: it runs inside the tick. */
DECLARE v_rec record; v_n integer := 0;
BEGIN
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'arm_clean_cut_short_is_owed', 0), 0) < 1 THEN RETURN 0; END IF;
  FOR v_rec IN
    SELECT vn.visit_id
      FROM public.ottoq_visit_needs vn JOIN public.vehicles v ON v.id = vn.vehicle_id
     WHERE vn.sim_run_id = p_sim_run_id AND vn.status IN ('open', 'in_progress') AND jsonb_typeof(vn.atoms) = 'array'
       AND v.current_state::text IS DISTINCT FROM 'charging_dcfc'
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) r
                    WHERE r->>'svc' = 'interior_tidy' AND COALESCE((r->>'arm_routine')::boolean, false)
                      AND r->>'status' = 'cancelled' AND r ? 'interrupted')
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) t
                        WHERE t->>'svc' = 'interior_tidy'
                          AND COALESCE(t->>'status', 'pending') IN ('pending', 'in_progress', 'done'))
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) d
                        WHERE d->>'svc' = 'interior_deep_clean' AND d->>'performed_by' = 'stall_cabin_robot'
                          AND d->>'status' IN ('in_progress', 'done'))
     ORDER BY vn.vehicle_id
  LOOP
    UPDATE public.ottoq_visit_needs
       SET atoms = atoms || jsonb_build_array(jsonb_build_object(
                     'svc', 'interior_tidy', 'must_do', true, 'deferrable', false, 'est_min', 5,
                     'concurrency', 'cabin', 'status', 'pending',
                     'owed_from', 'arm_routine_cut_short', 'owed_at', to_jsonb(p_clock)))
     WHERE visit_id = v_rec.visit_id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '0839 reopen cut-short arm cleans: %', SQLERRM;
  RETURN 0;
END;
$function$;

CREATE TEMP TABLE _0839_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0839_patch VALUES
(1, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
$o1$  -- 0816: the arm's deep program (0815), and the tidy it covers, of a car no longer on the program's post goes back
$o1$,
$n1$  -- 0839: an arm routine cut short whose car is not charging again is owed: it goes back on the visit as a needed
  -- tidy here, after the cancel above and before the starter, so the car is cleaned before it leaves
  IF v_feed_sim AND v_arm_every THEN
    PERFORM public.ottoq_reopen_cut_short_arm_cleans(p_sim_run_id, p_clock);
  END IF;

  -- 0816: the arm's deep program (0815), and the tidy it covers, of a car no longer on the program's post goes back
$n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0839_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0839 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0839: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0839_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0839_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0839_pre' AND s.object_name = f.fn LIMIT 1) THEN
      RAISE EXCEPTION '0839 V1: % with its patch reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'arm_clean_cut_short_is_owed', 1,
        'Chase (delegated to Claude Code: 0839)', now());

-- V3: on the newest run of the twin depot, a visit as 0798 leaves it; removed again before the commit
CREATE TEMP TABLE _0839_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_visit uuid; v_veh uuid; v_atoms0 jsonb; v_first int; v_second int; v_owed int; v_pending int;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs WHERE depot_id = c_depot ORDER BY started_at DESC LIMIT 1;
  SELECT vn.visit_id, vn.vehicle_id, vn.atoms INTO v_visit, v_veh, v_atoms0
    FROM public.ottoq_visit_needs vn JOIN public.vehicles v ON v.id = vn.vehicle_id
   WHERE vn.sim_run_id = v_run AND jsonb_typeof(vn.atoms) = 'array'
     AND v.current_state::text IS DISTINCT FROM 'charging_dcfc'
   ORDER BY vn.created_at DESC LIMIT 1;
  IF v_visit IS NULL THEN
    INSERT INTO _0839_selftest VALUES (jsonb_build_object('tested', false, 'why', 'no visit on the newest run to test on'));
    RETURN;
  END IF;
  CREATE TEMP TABLE _0839_keep ON COMMIT DROP AS SELECT status, atoms FROM public.ottoq_visit_needs WHERE visit_id = v_visit;
  UPDATE public.ottoq_visit_needs
     SET status = 'in_progress',
         atoms = jsonb_build_array(
           jsonb_build_object('svc', 'charge', 'status', 'done'),
           jsonb_build_object('svc', 'interior_tidy', 'status', 'cancelled', 'arm_routine', true,
                              'performed_by', 'stall_cabin_robot',
                              'interrupted', jsonb_build_array(jsonb_build_object('reason', 'left_the_cabin_robot'))))
   WHERE visit_id = v_visit;
  v_first  := public.ottoq_reopen_cut_short_arm_cleans(v_run, now());
  v_second := public.ottoq_reopen_cut_short_arm_cleans(v_run, now());
  SELECT count(*) FILTER (WHERE a->>'owed_from' = 'arm_routine_cut_short'),
         count(*) FILTER (WHERE a->>'svc' = 'interior_tidy' AND a->>'status' = 'pending')
    INTO v_owed, v_pending
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a WHERE vn.visit_id = v_visit;
  UPDATE public.ottoq_visit_needs vn SET status = k.status, atoms = k.atoms FROM _0839_keep k WHERE vn.visit_id = v_visit;
  IF v_first < 1 OR v_owed <> 1 OR v_pending <> 1 THEN
    RAISE EXCEPTION '0839 V3: first pass wrote % visits; the test visit holds % owed and % pending tidies', v_first, v_owed, v_pending;
  END IF;
  IF (SELECT atoms FROM public.ottoq_visit_needs WHERE visit_id = v_visit) IS DISTINCT FROM v_atoms0 THEN
    RAISE EXCEPTION '0839 V3: the test visit was not put back';
  END IF;
  INSERT INTO _0839_selftest VALUES (jsonb_build_object('tested', true, 'first_pass_visits', v_first,
                                                         'second_pass_visits', v_second, 'owed_tidies_on_the_test_visit', v_owed));
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0839_an_arm_clean_cut_short_is_owed_and_is_finished_before_the_car_leaves', true, false,
        'arm_clean_cut_short_is_owed set to 1 at the twin depot. V3 at apply: '
        || COALESCE((SELECT result::text FROM _0839_selftest LIMIT 1), 'no result'), now());
COMMIT;

-- APPLIED 2026-11-14 at 18:24:21 UTC (12:24 PM CT), ledger 20261114182421, through apply_migration, on the first send.
--   No run was live. V3 at apply: tested true, first_pass_visits 1, second_pass_visits 0, owed_tidies_on_the_test_visit 1.
--   Stored after the apply, md5(prosrc): ottoq_sim_advance_visit_atoms 807b32f1a87ab6aa92956192f1548537.
--   The run started to check it: 5ea96a57.
