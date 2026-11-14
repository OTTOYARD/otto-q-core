-- migration-version: 20261114031206
-- migration-name:    0831_a_car_cleaned_after_its_charge_is_cleaned_on_an_immediate_turnaround_too
--
-- 0831  **A car cleaned after its charge is cleaned by its post's arm on an owner's immediate turnaround too.**
--
-- WHY. Chase, 2026-11-13, 9:1x PM CT, on the 28 immediate turnarounds of run c8913ea2 that left with no arm clean:
--   "if they have to be done separately or back to back, that shouldn't interfere with the necessity for charging and
--   cleaning ... they can just occur back to back and that is still considered one stop even though they aren't
--   occurring simultaneously."
--
-- §1 WHAT WAS SO. 0765 does not hold an owner's immediate turnaround past its charge for a routine arm clean. For
--   every other car the routine runs during the charge, so 0765 skips it only on a charge shorter than the arm's cycle.
--   For a car cleaned AFTER its charge (0827: I-PACE, Ojai, Zoox) the clean always ends after the charge, so every
--   immediate turnaround of these kinds skipped it: 28 of 135 charged visits on run c8913ea2 (db/checks/0491).
--
-- §2 WHAT THIS DOES. In public.ottoq_start_concurrent_atoms, when 0827's rule applies to the car (its profile, both
--   settings on, a fast-charger post), 0765's immediate-turnaround exception does not: the arm cleans the car, and
--   0760's hold keeps it on its post until the arm is home. Nothing changes for any other car or with a setting off.
--
-- §3 WHAT IT COSTS. An owner's immediate turnaround of these three kinds leaves its post up to one arm cycle (5.8 min
--   at the twin's settings) after its charge ends. Charge and clean are one stop (Chase, above). No charge is
--   shortened and no service skipped (rule 9).
--
-- §4 PRECONDITIONS AND CHECKS. P0 no certification in flight and no run running. P1 the starter's body (md5 of
--   prosrc, as 0830 stored it). P2 once. V1 the patched body with its patches reversed is its pre-image. V2 each
--   anchor matched once. V3 the patched body runs once.
--
-- §5 CLASSIFICATION. forces_recert TRUE, forces_dial_restart FALSE.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0831_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0831_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0831 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN RAISE EXCEPTION '0831 P0: a run is live'; END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'))
     IS DISTINCT FROM '92c596b52649ba4efeeff1b46e7982bd' THEN
    RAISE EXCEPTION '0831 P1: public.ottoq_start_concurrent_atoms is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0831_%') THEN RAISE EXCEPTION '0831 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0831_pre', 'function', split_part(f, '.', 1), f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_start_concurrent_atoms(uuid,timestamptz)']) AS f;

CREATE TEMP TABLE _0831_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0831_patch VALUES
(1, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o1$  v_arm_waits boolean := false;    -- 0830: the car is cleaned after its charge and still charges; its tidy waits for the arm
$o1$,
$n1$  v_arm_waits boolean := false;    -- 0830: the car is cleaned after its charge and still charges; its tidy waits for the arm
  v_after_rule boolean := false;   -- 0831: 0827's rule applies to this car on this post
$n1$),
(2, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o2$    IF COALESCE(v_state, '') = 'charging_dcfc' THEN
      IF v_robot_cycle IS NOT NULL AND v_robot_left IS NOT NULL
         AND v_robot_left <= $o2$,
$n2$    v_after_rule := true;   -- 0831
    IF COALESCE(v_state, '') = 'charging_dcfc' THEN
      IF v_robot_cycle IS NOT NULL AND v_robot_left IS NOT NULL
         AND v_robot_left <= $n2$),
(3, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
$o3$      IF v_robot AND NOT (v_robot_short AND COALESCE(v_urgency, '') = 'immediate_dispatch') THEN
$o3$,
$n3$      -- 0831: for a car cleaned AFTER its charge (0827) charge and clean are one stop, back to back (Chase,
      -- 2026-11-13), so 0765's exception does not apply to it: the arm cleans it and 0760's hold keeps it on its post
      IF v_robot AND NOT (v_robot_short AND COALESCE(v_urgency, '') = 'immediate_dispatch' AND NOT v_after_rule) THEN
$n3$);
DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0831_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0831 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0831: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0831_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0831_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0831_pre' AND s.object_name = f.fn LIMIT 1) THEN
      RAISE EXCEPTION '0831 V1: % with its patches reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

DO $v3$
BEGIN
  PERFORM public.ottoq_start_concurrent_atoms(gen_random_uuid(), now());
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0831_a_car_cleaned_after_its_charge_is_cleaned_on_an_immediate_turnaround_too', true, false,
        'No setting changed. cabin_robot_after_charge was ' || COALESCE((SELECT param_value::text FROM public.ottoq_policy_params
           WHERE scope_type = 'depot' AND scope_id = '11111111-1111-1111-1111-111111111111' AND param_key = 'cabin_robot_after_charge'), 'unset')
        || ' at the twin depot at the apply.', now());
COMMIT;

-- APPLIED 2026-11-14 at 03:12:06 UTC (2026-11-13, 9:12 PM CT), ledger 20261114031206, through apply_migration, on the
--   first send. No run was live. cabin_robot_after_charge was 1 at the twin depot at the apply.
--   Stored after the apply, md5(prosrc): ottoq_start_concurrent_atoms 945eb1352d036d62aeabcd34526b0df5.
--   The run started to check it: 1902d13b (read in db/checks/0491 when it has run).
--   READ at tick 349 of run 1902d13b (03:46 UTC): the three kinds, 88 charged visits: 87 cleaned by the arm, 27 of
--   them an owner's immediate turnaround, 0 left for being one; 1 not cleaned (a charger fault cut the arm's clean
--   short: 0832). No car under a demate tether more than 12 sim minutes past its end.
