-- migration-version: 20261113210428
-- migration-name:    0828_the_arm_is_asked_about_a_car_cleaned_after_its_charge_before_the_car_is_released
--
-- 0828  **The arm is asked about a car cleaned after its charge before that car is released.**
--
-- WHY. 0827 missed about 4 in 10 of the arm cleans it was written to move (CLAUDE.md rule 9: a service is not skipped).
--
-- §1 WHAT WAS SO (db/checks/0491, run 7a08f52a, 2026-11-13). Under 0827 a car of the three kinds is cleaned by its
--   post's arm from the last minutes of its charge. Read at tick 706: of 69 charged visits of those cars, 39 had the
--   arm, 3 were an owner's immediate turnaround, and 27 had neither arm work nor an arm decision. The other kinds of
--   car: 38 of 38 charged visits cleaned by the arm. Two causes, both read from the source:
--   (1) twin.ottoq_sim_advance_visit_atoms offers a car to the starter for the arm's routine only while the car's
--       state is charging_dcfc. 0827's second door (the car on its post under its demate tether, charge ended) was
--       therefore reached only when something else made the car eligible: 12 starts in the run.
--   (2) 0827's first door needs the planner's estimate of the minutes left to read at most the lead on some tick.
--       The estimate does not go below 1.8, and often reads more than the lead on the last tick of a charge: the
--       recorded starts were at 1.8 (38), 3.4 (after the lead was set to 3.5) and 0.0.
--   Widening the lead from 2 to 3.5 on the live run did not help: 7 of 18 charged visits after it were still missed.
--   The setting was turned off at 21:01:55 UTC, 2 minutes before this file was applied.
--
-- §2 WHAT THIS DOES.
--   (a) public.ottoq_awaits_arm_after_charge(vehicle): the one test of "this car's charge has ended, it stands on its
--       fast-charger post under its demate tether, its profile says clean_after_charge, both settings are on, the
--       post's charger is not Faulted, and its open visit has no arm work and no arm decision yet".
--   (b) twin.ottoq_sim_advance_visit_atoms offers such a car to the starter.
--   (c) public.ottoq_release_expired_tethers does not release such a car for at most 4 minutes past its tether's end,
--       so the starter, which runs once a tick, is asked first whatever the order inside the tick. The starter then
--       starts the arm (0760's hold takes over) or records its decision (an immediate turnaround), and either ends
--       this hold. A car the starter never reaches is released after the 4 minutes.
--   (d) cabin_robot_after_charge is set back to 1 at the twin depot.
--
-- §3 WHAT IT COSTS, AND WHAT IT DOES NOT DO. A car of the three kinds that is not started by the first door holds its
--   post up to one more tick before the arm starts, and at most 4 minutes if it is never started. It does not change
--   the estimate, the lead (3.5 at the twin depot, 2 by default) or any other kind of car.
--
-- §4 PRECONDITIONS AND CHECKS. P0 no certification in flight (a run may be live). P1 the two bodies (md5 of prosrc,
--   read 2026-11-13 21:0x UTC). P2 once. V1 each patched body with its patch reversed is its pre-image. V2 each anchor
--   matched once. V3 the test runs for every car of the twin depot without error (the release sweep swallows its own
--   errors, so a test that raised would stop every release in silence), and the setting reads 1.
--
-- §5 CLASSIFICATION. forces_recert TRUE, forces_dial_restart FALSE.
--
-- ROLLBACK: UPDATE public.ottoq_policy_params SET param_value = 0 WHERE param_key = 'cabin_robot_after_charge';
--   EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0828_pre';
--   DROP FUNCTION public.ottoq_awaits_arm_after_charge(uuid); DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0828_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0828 P0: a certification is in flight'; END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'))
     IS DISTINCT FROM '511d72ca7a5c519c5bc8b89c0b3ecf88' THEN
    RAISE EXCEPTION '0828 P1: twin.ottoq_sim_advance_visit_atoms is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_release_expired_tethers(timestamptz)'))
     IS DISTINCT FROM '5a97f2dc39e51a3f206dc243a466e975' THEN
    RAISE EXCEPTION '0828 P1: public.ottoq_release_expired_tethers is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0828_%') THEN RAISE EXCEPTION '0828 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0828_pre', 'function', split_part(f, '.', 1), f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)', 'public.ottoq_release_expired_tethers(timestamptz)']) AS f;

-- the one test both doors ask: is this car waiting, on its post under its demate tether, for the arm's decision?
CREATE FUNCTION public.ottoq_awaits_arm_after_charge(p_vehicle uuid)
 RETURNS boolean LANGUAGE sql STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  /* 0828: a car whose port profile says clean_after_charge (0827), whose charge has ended, that still stands on its
     fast-charger post under its demate tether, and whose open visit has no arm work and no arm decision yet. False
     with cabin_robot_after_charge or stall_cabin_robot off, and where the post's charger is Faulted (0792). */
  SELECT EXISTS (
    SELECT 1
      FROM public.vehicles v
      JOIN public.stalls s ON s.id = v.robotic_tether_stall_id AND s.stall_type::text = 'dcfc'
      JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.status IN ('open', 'in_progress')
     WHERE v.id = p_vehicle
       AND v.current_state::text = 'charge_complete_holding'
       AND v.robotic_tether_until IS NOT NULL
       AND v.current_stall_id = v.robotic_tether_stall_id
       AND COALESCE(v.robotic_tether_direction, 'demate') = 'demate'
       AND COALESCE((public.ottoq_vehicle_port_profile(v.id)).clean_after_charge, false)
       AND COALESCE(public.ottoq_policy_get(vn.sim_run_id, 'cabin_robot_after_charge', 0), 0) >= 1
       AND COALESCE(public.ottoq_policy_get(vn.sim_run_id, 'stall_cabin_robot', 0), 0) >= 1
       AND jsonb_typeof(vn.atoms) = 'array'
       AND NOT (COALESCE(vn.meta, '{}'::jsonb) ? 'arm_routine')
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'performed_by' = 'stall_cabin_robot')
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) t
                        WHERE t->>'svc' = 'interior_tidy' AND t->>'status' IN ('in_progress', 'done'))
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers fc
                        WHERE fc.charger_id = s.ocpp_charger_id AND fc.station_state = 'Faulted'));
$function$;

CREATE TEMP TABLE _0828_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0828_patch VALUES
(1, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
$o1$WHERE sd.id = v.current_stall_id AND sd.stall_type::text = 'dcfc')))
     ORDER BY (vn.urgency = 'immediate_dispatch') DESC,$o1$,
$n1$WHERE sd.id = v.current_stall_id AND sd.stall_type::text = 'dcfc'))
            -- 0828: or a car cleaned AFTER its charge (0827) that stands on its post under its demate tether with
            -- the arm's decision still to take: the starter is asked for it, where before only a charging car was
            OR public.ottoq_awaits_arm_after_charge(v.id))
     ORDER BY (vn.urgency = 'immediate_dispatch') DESC,$n1$),
(2, 'public.ottoq_release_expired_tethers(timestamptz)',
$o2$                                 WHERE fs.id = v.robotic_tether_stall_id
                                   AND fc.station_state = 'Faulted'))
$o2$,
$n2$                                 WHERE fs.id = v.robotic_tether_stall_id
                                   AND fc.station_state = 'Faulted'))
       -- 0828: nor, for at most 4 minutes past the tether's end, a car cleaned AFTER its charge (0827) whose arm
       -- decision the starter has not yet taken. The starter runs once a tick; without this the sweep could free the
       -- car first, and the arm's clean was then never started (run 7a08f52a: about 4 in 10). Bounded, so a car the
       -- starter never reaches is still released.
       AND NOT (v.robotic_tether_until > v_now - interval '4 minutes'
                AND public.ottoq_awaits_arm_after_charge(v.id))
$n2$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0828_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0828 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0828: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0828_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0828_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0828_pre' AND s.object_name = f.fn LIMIT 1) THEN
      RAISE EXCEPTION '0828 V1: % with its patch reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

-- the rule back on at the twin depot, with 0827's lead as first set
UPDATE public.ottoq_policy_params SET param_value = 1, updated_by = 'Chase (delegated to Claude Code: 0828)', updated_at = now()
 WHERE scope_type = 'depot' AND scope_id = '11111111-1111-1111-1111-111111111111' AND param_key = 'cabin_robot_after_charge';

CREATE TEMP TABLE _0828_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_cars int; v_wait int; v_dial numeric;
BEGIN
  -- the test runs for every car of the depot without error (the sweep swallows its own errors, so a test that raised
  -- would stop every release and say nothing)
  SELECT count(*), count(*) FILTER (WHERE public.ottoq_awaits_arm_after_charge(v.id)) INTO v_cars, v_wait
    FROM public.vehicles v WHERE v.home_depot_id = c_depot;
  SELECT param_value INTO v_dial FROM public.ottoq_policy_params
   WHERE scope_type = 'depot' AND scope_id = c_depot AND param_key = 'cabin_robot_after_charge';
  IF COALESCE(v_dial, 0) < 1 THEN RAISE EXCEPTION '0828 V3: cabin_robot_after_charge is not on at the twin depot'; END IF;
  INSERT INTO _0828_selftest VALUES (jsonb_build_object('cars_tested', v_cars, 'awaiting_the_arm_now', v_wait));
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0828_the_arm_is_asked_about_a_car_cleaned_after_its_charge_before_the_car_is_released', true, false,
        'cabin_robot_after_charge back to 1 at the twin depot. V3 at apply: '
        || COALESCE((SELECT result::text FROM _0828_selftest LIMIT 1), 'no result'), now());
COMMIT;

-- APPLIED 2026-11-13 at 21:04:28 UTC (3:04 PM CT), ledger 20261113210428, through apply_migration, on the first send.
--   Before it, the same statements ran once against the live engine inside a transaction that ended on a raised
--   exception, with run 7a08f52a live: both anchors matched once, V1 held, the test ran for 120 cars, and the patched
--   tick step and release sweep each ran once without error.
--   Run 7a08f52a was live at the apply, at tick 743 of its day. V3 at apply: cars_tested 120, awaiting_the_arm_now 0.
--   Stored after the apply, md5(prosrc): ottoq_sim_advance_visit_atoms a29050986cb6920be7959618eab381c2,
--   ottoq_release_expired_tethers 1037f381572a240a4548f75bf0b222b1.
