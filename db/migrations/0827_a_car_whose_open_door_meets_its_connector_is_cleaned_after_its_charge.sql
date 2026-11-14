-- migration-version: 20261113195431
-- migration-name:    0827_a_car_whose_open_door_meets_its_connector_is_cleaned_after_its_charge
--
-- 0827  **A car whose open door meets its charge connector is cleaned by the post's arm after its charge, on the same
--        post.**
--
-- WHY. Chase, 2026-11-12: "If a car can't be cleaned from over head with doors open AND being charged simultaneously,
--   then they can charge first, then clean with doors open (if both services are needed). I'd prefer simultaneously, if
--   at all possible and design allows." And 2026-11-13, asked which order for these cars: "clean after charge is fine".
--
-- §1 WHAT WAS SO. With stall_cabin_robot on, the post's cleaning arm cleans a car's cabin DURING its charge (0758,
--   0764, 0765, 0815). Every charger now stands on the car's left (0826). Measured in ottoyarddepot-sim on 2026-11-13
--   (cleanArmFleet.test.ts, docs/CLEAN-ARM-PER-VEHICLE.md), the charge arm latched at the inlet against the open left
--   door: the Jaguar I-PACE -0.122 m (the front door's leaf swings over the front-wing inlet), the Waymo Ojai -0.124 m
--   and the Zoox -0.123 m (the open sliding panel lies over the inlet; both inlet positions are assumptions). The
--   Model Y, the Gravity and the Cybercab are clear, more than 0.37 m. So for the first three the twin's arm can clean
--   only the right side while the car charges, and its session records the left side as not done.
--
-- §2 WHAT THIS DOES.
--   (a) public.ottoq_charge_port_profiles gains `clean_after_charge`, true for waymo_ipace, waymo_ojai, zoox_robotaxi.
--   (b) A setting, cabin_robot_after_charge (default 0; set to 1 at the twin depot), and its lead,
--       cabin_robot_after_charge_lead_min (default 2).
--   (c) In public.ottoq_start_concurrent_atoms, for a car whose profile says so, on a fast-charger post, with both
--       settings on: while it charges with more than the lead left by the planner's own estimate, NOTHING of the arm's
--       starts (no tidy, no routine, no deep clean, and no decision is recorded). In the last `lead` minutes of the
--       charge, and for a car whose charge has just ended and that still stands on its post under its demate tether,
--       the arm's work starts as 0765's short-charge case does. 0760's hold then keeps the car on its post until the
--       arm is home, at most one cycle after the charge. The twin's arm cleans the right side while the connector is
--       still in and the left side once it is out (ottoyarddepot-sim cleanGate).
--   Nothing changes for a car whose profile does not say so, or with either setting off.
--
-- §3 WHAT IT COSTS, AND WHAT IT DOES NOT DO. A car of these three kinds holds its post up to one arm cycle (5.8 min at
--   the twin's settings, longer for a deep clean) after its charge, where it held it for none. At the twin depot that
--   is 80 of 116 cars (44 + 2 + 34). No charge is shortened and no service skipped (rule 9); an owner's immediate
--   turnaround is still not held for a routine clean it did not need (0765). It does not make the arm reach more of a
--   cabin, and it does not change a cabin stop (0817) or a faulted charger's release (0792).
--   A start can be MISSED: the planner's estimate can read more than the lead on the last tick of a charge, and the
--   release sweep can run before the starter in the tick after. A missed routine clean leaves no record. db/checks/0491
--   counts, on the first run, the charge visits of these cars with and without an arm clean.
--
-- §4 PRECONDITIONS AND CHECKS. P0 no certification in flight (a run may be live). P1 the starter's body (md5 of
--   prosrc, read 2026-11-13 before the apply). P2 once. V1 the patched body with its patch reversed is its pre-image. V2 the
--   anchor matched once. V3 three profiles carry the flag, the other three do not, and every autonomous car at the
--   twin depot resolves a profile.
--
-- §5 CLASSIFICATION. forces_recert TRUE (when the arm's clean starts, and how long a post is held, change at the twin
--   depot), forces_dial_restart FALSE.
--
-- ROLLBACK: DELETE FROM public.ottoq_policy_params WHERE param_key LIKE 'cabin_robot_after_charge%'; EXECUTE the
--   `definition` in ottoq_schema_snapshots WHERE label = '0827_pre'; DELETE FROM public.ottoq_policy_param_catalog
--   WHERE param_key LIKE 'cabin_robot_after_charge%'; ALTER TABLE public.ottoq_charge_port_profiles DROP COLUMN
--   clean_after_charge; DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0827_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0827 P0: a certification is in flight'; END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'))
     IS DISTINCT FROM 'a2da9ddc2c6c1470503f48346bfdf808' THEN
    RAISE EXCEPTION '0827 P1: public.ottoq_start_concurrent_atoms is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0827_%') THEN RAISE EXCEPTION '0827 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0827_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_start_concurrent_atoms(uuid,timestamptz)']) AS f;

-- ── (a) which kinds of vehicle ──
ALTER TABLE public.ottoq_charge_port_profiles ADD COLUMN clean_after_charge boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.ottoq_charge_port_profiles.clean_after_charge IS
  '0827: true when an open door on the inlet''s side meets the latched charge connector, so the post''s cleaning arm works after the charge. Measured in ottoyarddepot-sim (cleanArmFleet.test.ts), 2026-11-13.';
UPDATE public.ottoq_charge_port_profiles SET clean_after_charge = true
 WHERE profile_key IN ('waymo_ipace', 'waymo_ojai', 'zoox_robotaxi');

-- ── (b) the settings ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
  ('cabin_robot_after_charge',
   '0827: 1 = a car whose port profile says clean_after_charge is cleaned by its post''s arm at the end of its charge and after it, on the same post, not during the charge. 0 = as before 0827.',
   0, 0, 1, 'public.ottoq_start_concurrent_atoms', false),
  ('cabin_robot_after_charge_lead_min',
   '0827: minutes of charge left, by the planner''s estimate, at which that car''s arm clean may start.',
   2, 0, 15, 'public.ottoq_start_concurrent_atoms', false);

-- ── (c) the patch ──
CREATE TEMP TABLE _0827_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0827_patch VALUES
(1, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o1$      v_robot := true;
      v_robot_short := true;
    END IF;
  END IF;
$o1$,
$n1$      v_robot := true;
      v_robot_short := true;
    END IF;
  END IF;
  /* 0827: a car whose open door meets its latched connector (its port profile's clean_after_charge) is cleaned by the
     arm AFTER its charge, on the same post (Chase, 2026-11-12 and 2026-11-13). While it charges with more than the
     lead left, nothing of the arm's starts and nothing is decided. In the last minutes of the charge, and while the
     car still stands on its post under its demate tether, the arm starts as 0765's short-charge case does, and 0760's
     hold keeps the car on the post until the arm is home. */
  IF v_robot_dial
     AND COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_after_charge', 0), 0) >= 1
     AND COALESCE((public.ottoq_vehicle_port_profile(p_vehicle)).clean_after_charge, false)
     AND EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text = 'dcfc') THEN
    IF COALESCE(v_state, '') = 'charging_dcfc' THEN
      IF v_robot_cycle IS NOT NULL AND v_robot_left IS NOT NULL
         AND v_robot_left <= GREATEST(0, COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_after_charge_lead_min', 2), 2)) THEN
        v_robot := v_robot_cycle > 0;
        v_robot_short := true;
      ELSE
        v_robot := false;
        v_robot_short := false;
        v_robot_cycle := NULL;
        v_robot_left := NULL;
      END IF;
    ELSIF COALESCE(v_state, '') = 'charge_complete_holding'
          AND EXISTS (SELECT 1 FROM public.vehicles tv
                       WHERE tv.id = p_vehicle AND tv.robotic_tether_until IS NOT NULL
                         AND tv.robotic_tether_stall_id = v_stall
                         AND COALESCE(tv.robotic_tether_direction, 'demate') = 'demate') THEN
      v_robot_cycle := 2 * GREATEST(0, COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_side_min', 2.5), 2.5))
                       + GREATEST(0, COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_motion_min', 0.8), 0.8));
      v_robot_left := 0;
      v_robot := v_robot_cycle > 0;
      v_robot_short := true;
    END IF;
  END IF;
$n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0827_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0827 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0827: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0827_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0827_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0827_pre' AND s.object_name = f.fn LIMIT 1) THEN
      RAISE EXCEPTION '0827 V1: % with its patch reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

-- ── on at the twin depot (rule 12) ──
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'cabin_robot_after_charge', 1,
        'Chase (delegated to Claude Code: 0827)', now());

CREATE TEMP TABLE _0827_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_flag int; v_all int; v_cars int; v_after int; v_none int;
BEGIN
  SELECT count(*) FILTER (WHERE clean_after_charge), count(*) INTO v_flag, v_all FROM public.ottoq_charge_port_profiles;
  IF v_flag <> 3 OR v_all <> 6 THEN RAISE EXCEPTION '0827 V3: % of % profiles carry the flag, not 3 of 6', v_flag, v_all; END IF;
  SELECT count(*), count(*) FILTER (WHERE pf.clean_after_charge), count(*) FILTER (WHERE pf.profile_key IS NULL)
    INTO v_cars, v_after, v_none
    FROM public.vehicles v LEFT JOIN LATERAL public.ottoq_vehicle_port_profile(v.id) pf ON true
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous';
  IF v_none > 0 THEN RAISE EXCEPTION '0827 V3: % autonomous cars at the twin depot resolve no profile', v_none; END IF;
  INSERT INTO _0827_selftest VALUES (jsonb_build_object('cars', v_cars, 'cars_cleaned_after_their_charge', v_after));
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0827_a_car_whose_open_door_meets_its_connector_is_cleaned_after_its_charge', true, false,
        'cabin_robot_after_charge set to 1 at the twin depot. V3 at apply: '
        || COALESCE((SELECT result::text FROM _0827_selftest LIMIT 1), 'no result'), now());
COMMIT;

-- APPLIED 2026-11-13 at 19:54:31 UTC (1:54 PM CT), ledger 20261113195431, through apply_migration, on the first send.
--   Before it, the same statements ran once against the live engine inside a transaction that ended on a raised
--   exception: the anchor matched once, V1 held, and the patched starter ran for one car without error.
--   No run was live at the apply. V3 at apply: cars 116, cars_cleaned_after_their_charge 80.
--   Stored after the apply, md5(prosrc): ottoq_start_concurrent_atoms 0da9732354f975a2cb54e8e78ae3d57d.
--   The run started to check it (9a055337) was superseded 3 minutes later by an operator's run, 7a08f52a, which ran
--   under it and is read in db/checks/0491: it MISSED about 4 in 10 of the arm cleans of the three kinds of car. The
--   setting was turned off at 21:01:55 UTC and 0828 fixes the cause.
