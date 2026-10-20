-- migration-version: 20261020213742
-- migration-name:    a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go
--
-- 0760  **A car the cleaning arm is cleaning keeps its stall when the charge arm lets go.** (G479)
--       0758 holds a car on its fast charger while the stall's cleaning arm is at work in it, and taught that hold
--       (ottoq.ottoq_uplink_transfer_holds) to the three movers that take a charged car to its next work. It did not
--       reach the tether sweep. When a charge ends before the arm's cycle does, the charge arm demates and
--       public.ottoq_release_expired_tethers, the one releaser, clears the car's stall and frees the stall in the same
--       tick. The car then stands on no stall, the hold (which asks about the stall the car stands on) no longer applies,
--       and the next mover takes the car away with the arm still in its cabin.
--
-- ══ §1 WHY, MEASURED (read-only, live run c6ec017d, 2026-10-20 4:28-4:29 PM CT, 21:28:43-21:29:07 UTC) ════════════════
--
--   Run c6ec017d: busy_day at the twin depot, with the seven switches of db/checks/0459 on. Car ca2624fc plugged into
--   NASH-DCFC-STALL-08 at sim 9:35:40 AM CT already near full. At 9:39:28 the stall's arm started its must-do tidy, due
--   home at 9:45:16 (the 5.8-minute cycle), because the planner's estimate gave the charge at least that long. The charge
--   reached 100% at 9:44:08 and the charge arm demated (arm.demate_started 9:44:08, arm.demate_cleared 9:45:01). In the
--   same second the car's current_stall_id went to NULL. At 9:45:13 the bay calendar seated the car in NASH-WSH-01 for
--   its deep clean, and at 9:45:30 the completion step put the tidy back to pending ('left_the_cabin_robot'), nothing
--   credited. That was one of the run's first four arm cleans. Rule 9 held, since the tidy stays open until it is done.
--   But the arm's work was thrown away, and the car left the stall 15 seconds before the arm was home, which 0758
--   §2(c) says cannot happen.
--   The releaser was read live (prosrc md5 e93c55436dca059c95b6462873b704ba). It releases every expired demate tether's
--   stall without looking at other work on it. Its callers are public.ottoq_sim_advance_tick_world and
--   twin.ottoq_world_advance, neither of which this file changes.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_release_expired_tethers gets one anchored insertion in its `due` set:
--     - An expired DEMATE tether is not released while the stall it held has its cleaning arm at work in the car. That
--       means an atom performed_by stall_cabin_robot, in progress, whose robot_stall_id is that stall, on one of the
--       car's open visits.
--     - The tether stays expired and the car stays on the stall, so 0758's hold keeps the movers off it.
--     - The first sweep after the completion step marks the arm's work done releases the car exactly as before.
--   Only 0758's dial-on starter writes that performer, so with stall_cabin_robot at 0 the new predicate is always true
--   and the sweep behaves as it did. Untouched: a charging tether's lapse, an inbound tether, and any car with no arm
--   at work.
--   A visit whose atoms are not a JSON array is read as having none. The sweep swallows its own errors and returns 0,
--   so one malformed row would otherwise stop every release at every depot. Nothing enforces the type; all 61,367 live
--   rows were arrays at 4:34 PM CT (21:34:55 UTC).
--   Rule 9: the car has already reached its target and waits for the arm. Its charger is held for the rest of the cycle
--   (at most the 5.8 minutes, here 15 seconds).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   - P0: nothing in flight.
--   - P1: not already applied; 0758 is applied; the releaser is the body read (prosrc md5 e93c5543).
--   - The pre-image goes to ottoq_schema_snapshots as '0760_pre'.
--   - The anchor matches exactly once.
--   - V1: the body minus its insertion is its pre-image.
--   - V2: the new predicate runs bare on the live tables. The sweep swallows its own errors, so running the sweep could
--     not tell a broken predicate from a quiet tick.
--   Executed by tests/test_cabin_arm_keeps_its_stall_sql.py on the scratch PostgreSQL against the live body
--   (tests/fixtures/release_expired_tethers_stub.sql, md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At stall_cabin_robot 0, the default and every certification
--   arm's, no atom carries the performer, so the added predicate is true for every car and the sweep releases what it
--   released before (V1).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0760_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0760_a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0760 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: not applied, 0758 applied, the releaser as read ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0760_a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go') THEN
    RAISE EXCEPTION '0760 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges') THEN
    RAISE EXCEPTION '0760 P1: 0758 is not applied (this file keeps its arm''s car on its stall)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_release_expired_tethers(timestamp with time zone)'))
     IS DISTINCT FROM 'e93c55436dca059c95b6462873b704ba' THEN
    RAISE EXCEPTION '0760 P1: public.ottoq_release_expired_tethers is not the body read (md5 e93c5543)';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0760_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure;

-- ── the sweep: a demate tether waits for the stall's cleaning arm ──
CREATE TEMP TABLE _0760_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0760_patch VALUES
  (1,
   $o1$     WHERE v.robotic_tether_until IS NOT NULL
       AND v.robotic_tether_until <= v_now
$o1$,
   $n1$     WHERE v.robotic_tether_until IS NOT NULL
       AND v.robotic_tether_until <= v_now
       -- 0760 (G479): a demate tether is not released while the stall it held has its cleaning arm at work in the car
       -- (0758's performer, in progress on that stall). The car stays on the stall, so 0758's hold keeps the movers off
       -- it, and the first sweep after the arm's work is done releases it as before. Only 0758's dial-on starter writes
       -- the performer, so at stall_cabin_robot 0 nothing here is ever true. A visit whose atoms are not an array is
       -- read as empty: this sweep swallows its own errors, so one malformed row must not stop every release.
       AND NOT (COALESCE(v.robotic_tether_direction, 'demate') = 'demate'
                AND EXISTS (SELECT 1
                              FROM public.ottoq_visit_needs vn
                              CROSS JOIN LATERAL jsonb_array_elements(
                                CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]'::jsonb END) a
                             WHERE vn.vehicle_id = v.id
                               AND vn.status IN ('open', 'in_progress')
                               AND a->>'performed_by' = 'stall_cabin_robot'
                               AND a->>'status' = 'in_progress'
                               AND a->>'robot_stall_id' = v.robotic_tether_stall_id::text))
$n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0760_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0760: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0760: the sweep is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertion is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0760_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'e93c55436dca059c95b6462873b704ba' THEN
    RAISE EXCEPTION '0760 V1: the sweep less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the new predicate runs on the live tables. The sweep swallows its own errors and returns 0, so running it
--    could not tell a broken predicate from a quiet tick; the predicate is run bare instead, over every car. ──
DO $v2$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
    FROM public.vehicles v
   WHERE NOT (COALESCE(v.robotic_tether_direction, 'demate') = 'demate'
              AND EXISTS (SELECT 1
                            FROM public.ottoq_visit_needs vn
                            CROSS JOIN LATERAL jsonb_array_elements(
                              CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]'::jsonb END) a
                           WHERE vn.vehicle_id = v.id
                             AND vn.status IN ('open', 'in_progress')
                             AND a->>'performed_by' = 'stall_cabin_robot'
                             AND a->>'status' = 'in_progress'
                             AND a->>'robot_stall_id' = v.robotic_tether_stall_id::text));
  IF n IS NULL THEN
    RAISE EXCEPTION '0760 V2: the predicate did not run';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0760_a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go', false, false,
        'G479. One anchored insertion in public.ottoq_release_expired_tethers: an expired demate tether is not released '
        'while its stall''s cleaning arm is at work in the car (0758''s performer, in progress on that stall), so the car '
        'keeps its stall and 0758''s hold keeps the movers off it until the arm is home. Live run c6ec017d, car ca2624fc: '
        'the sweep freed the stall 15 s before the arm was home and the tidy was thrown away. At stall_cabin_robot 0 no '
        'atom carries the performer and the sweep is unchanged (V1: body less insertion is its pre-image).',
        now());

COMMIT;
