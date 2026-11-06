-- migration-version: PENDING
-- migration-name:    the_arms_registration_draw_is_keyed_on_what_a_run_reproduces_not_on_the_cycles_minted_id
--
-- 0801  **The robotic arm's registration draw is keyed on what a run reproduces, not on the cycle's minted id.** (G525)
--
-- ══ §1 WHAT IS WRONG (FINDINGS G525; read in the research lab, 2026-11-06 between 07:50 and 07:56 UTC) ═════════════
--
--   twin.ottoq_arm_registration_check draws the car's true pose at the post (lateral, vertical, yaw: "salted on the CYCLE
--   only, deliberately NOT on the attempt") and the marker detection from v_key := p_cycle_id. twin.arm_cycles mints that
--   id with gen_random_uuid() on every run, where every other twin draw is keyed on the seed and the car, the stall or the
--   sim clock. So the same seed draws a different pose for the same plug on every run, and a pose outside the arm's reach is
--   a restage (the plug fails, the car must move). On the lab's normal_day at 116 cars, seed 424242, three runs latched
--   every plug-in (260 of 262 started, the other two still under way at 6 PM) and a fourth restaged one (1 of 257, car
--   9e209f49 at post 27 at 11:40): that car left its post a tick early without the arm's unplug, the seating changed from
--   11:55, and the day ended with 5 fewer charging sessions and 11 fewer visits served (217 against 228). Same class as
--   0137, 0139, 0216 and 0329: a draw or a hash over a minted id.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   One anchored replacement of the key: the car, the stall, the cycle's direction and its start in sim time through
--   twin.ottoq_sim_clock_salt (whole seconds since the run's own start, the salt the twin's charge draws use), read from
--   twin.arm_cycles by the cycle id; a cycle the table does not hold keeps the old fallback (car:stall). The design is
--   kept: one pose per cycle, not per attempt, and a fresh detection draw per attempt. Nothing else in the function moves.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; the function is the body as it stands (prosrc md5 adbc96a5, production read
--   2026-11-06 07:56:08 UTC, and the lab). The anchor matches once. V1 the body less its insertion is its pre-image. V2 two
--   cycles of one plug (the same car, post, direction and start, two minted ids) draw the same pose and verdict, and the
--   draw is modelled (a probe rolled back with its rows). V3 the patched body is byte for byte the one the lab ran.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE: the twin's draws change, so a canon or a dial pair recorded under the
--   old key is no longer the twin's world (rule 12: testing is off; nothing acts on either). Rule 9: no car's need is
--   touched; the plug's chance of a restage is unchanged in distribution, only which plug restages becomes reproducible.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0801_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0801_the_arms_registration_draw_is_keyed_on_what_a_run_reproduces_not_on_the_cycles_minted_id'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0801 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0801_the_arms_registration_draw_is_keyed_on_what_a_run_reproduces_not_on_the_cycles_minted_id') THEN
    RAISE EXCEPTION '0801 P1: already applied';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_arm_registration_check(uuid,uuid,uuid,uuid,integer,timestamp with time zone)'))
     IS DISTINCT FROM 'adbc96a5f656b20cdfdbcf2fc269d6e1' THEN
    RAISE EXCEPTION '0801 P1: twin.ottoq_arm_registration_check is not the body as it stood (md5 adbc96a5)';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0801_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_arm_registration_check(uuid,uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure;

CREATE TEMP TABLE _0801_patch (c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0801_patch VALUES (
$o$  v_key := COALESCE(p_cycle_id::text, p_vehicle_id::text || ':' || p_stall_id::text);$o$,
$n$  -- 0801 (G525): the key a run reproduces: the car, the stall, the cycle's direction and its start in sim time (the clock
  -- salt the twin's charge draws use). The cycle id is minted fresh each run (gen_random_uuid), so keyed on it the same
  -- seed drew a different pose for the same plug, and a re-run's day could differ.
  SELECT p_vehicle_id::text || ':' || p_stall_id::text || ':' || c.direction || ':'
         || twin.ottoq_sim_clock_salt(p_sim_run_id, c.started_at)
    INTO v_key FROM twin.arm_cycles c WHERE c.cycle_id = p_cycle_id;
  v_key := COALESCE(v_key, p_vehicle_id::text || ':' || p_stall_id::text);$n$);

UPDATE _0801_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  SELECT * INTO p FROM _0801_patch;
  v_def := pg_get_functiondef('twin.ottoq_arm_registration_check(uuid,uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
  IF n <> 1 THEN
    RAISE EXCEPTION '0801: the anchor matches % times, not 1', n;
  END IF;
  v_def := replace(v_def, p.c_old, p.c_new);
  EXECUTE v_def;
  IF pg_get_functiondef('twin.ottoq_arm_registration_check(uuid,uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0801: the function is not stored as patched';
  END IF;
END $patch$;

DO $v1$
DECLARE p record; v_body text;
BEGIN
  SELECT * INTO p FROM _0801_patch;
  v_body := replace(pg_get_functiondef('twin.ottoq_arm_registration_check(uuid,uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure),
                    p.c_new, p.c_old);
  IF md5(v_body) IS DISTINCT FROM (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0801_pre') THEN
    RAISE EXCEPTION '0801 V1: the function less its insertion is not its pre-image';
  END IF;
END $v1$;

-- ── V2: two cycles of one plug, two minted ids, one pose and one verdict; the probe and its rows rolled back ──
DO $v2$
DECLARE
  v_st uuid; v_veh uuid; a jsonb; b jsonb;
  c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid();
  t timestamptz := '2026-09-01 12:00:00+00';
BEGIN
  SELECT s.id INTO v_st FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'dcfc' AND s.fiducial_marker_id IS NOT NULL
   ORDER BY s.stall_code LIMIT 1;
  SELECT v.id INTO v_veh FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous' ORDER BY v.id LIMIT 1;
  IF v_st IS NULL OR v_veh IS NULL THEN
    RAISE EXCEPTION '0801 V2: no robotic post with a marker, or no car, at the twin depot to probe';
  END IF;
  BEGIN
    -- written closed (ended_at set), so the probe never holds a post open (arm_cycles_one_open_per_stall)
    INSERT INTO twin.arm_cycles (cycle_id, sim_run_id, stall_id, vehicle_id, direction, phase, phase_started_at,
                                 phase_deadline, started_at, ended_at)
    VALUES (c1, NULL, v_st, v_veh, 'mate', 'align', t, t, t, t), (c2, NULL, v_st, v_veh, 'mate', 'align', t, t, t, t);
    a := twin.ottoq_arm_registration_check(c1, NULL, v_st, v_veh, 0, t);
    b := twin.ottoq_arm_registration_check(c2, NULL, v_st, v_veh, 0, t);
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '0801 V2: roll the probe back';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN
    NULL;
  END;
  IF NOT COALESCE((a->>'modelled')::boolean, false) OR NOT COALESCE((b->>'modelled')::boolean, false) THEN
    RAISE EXCEPTION '0801 V2: the registration was not modelled: % / %', a, b;
  END IF;
  IF a IS DISTINCT FROM b THEN
    RAISE EXCEPTION '0801 V2: two cycles of one plug drew different poses: % / %', a, b;
  END IF;
  RAISE NOTICE '0801 V2: two cycles of one plug drew one pose (verdict %, true lateral % mm)', a->>'verdict', a->>'true_lateral_mm';
END $v2$;

-- ── V3: the patched body is byte for byte the one the research lab ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'twin.ottoq_arm_registration_check(uuid,uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM '3e2bfb19d800e709d9cb92941eb00110' THEN
    RAISE EXCEPTION '0801 V3: the patched body is not the one the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc
        WHERE oid = 'twin.ottoq_arm_registration_check(uuid,uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure);
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0801_the_arms_registration_draw_is_keyed_on_what_a_run_reproduces_not_on_the_cycles_minted_id', true, true,
        'G525. twin.ottoq_arm_registration_check draws the pose and the detection from the car, the stall, the cycle''s '
        'direction and its start in sim time, not the cycle''s minted id: the same seed now reproduces each plug''s '
        'registration. The twin''s draws change, so a canon or a dial pair recorded under the old key is not its world.',
        now());

COMMIT;
