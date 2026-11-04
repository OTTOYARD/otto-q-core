-- migration-version: 20261103041827
-- migration-name:    a_faulted_post_lets_its_car_go_whatever_the_cleaning_arm_is_doing
--
-- 0792  **A faulted post lets its car go, whatever the cleaning arm is doing.** (G506)
--       0760 taught the tether sweep (public.ottoq_release_expired_tethers) to keep a car on its fast charger while
--       the stall's OTTO-CLEAN ARM is at work in its cabin, on the reasoning (0760 §2) that "the car has already
--       reached its target and waits for the arm". That is true when a charge ENDS. It is false when the charger
--       FAULTS: the car has not reached its target, its charger is out of service, and rule 9 says the car is
--       re-queued to finish. The sweep never asked why the charge ended, so a car whose charger faulted mid-clean was
--       held on the dead post until the whole cleaning cycle ran out.
--       Chase, 2026-11-02, from the twin (screenshot of a post with its fault beacon and red bay-closed marks, a car in
--       it and the charge arm in the car's port): "Looks like a faulted charger station was given a vehicle to
--       charge/clean. Major issue. resolve that".
--
-- ══ §1 WHY, MEASURED (read-only, demo run 8c0b2e04, busy_day at the twin depot, 9:37-9:47 PM CT on 2026-11-02,
--      03:37:10-03:47:13 UTC on 2026-11-03; read 9:59-10:10 PM CT, 03:59-04:10 UTC; db/checks/0474) ══════════════════
--
--   Six charge sessions ended `faulted` in the run's 129 ticks. Two cars were inside their post's cabin clean when
--   their charger faulted, and both were held on the dead post until the clean was done:
--
--     post        car       fault (sim, UTC)               clean on that post (sim)   left the post    held
--     DCFC-22     2cd2cbf3  14:04:15 thermal_emergency     14:03:53-14:09:41, done    14:09:54         339.1 s
--     DCFC-02     ca2624fc  14:04:45 session_aborted_other 14:03:53-14:09:41, done    14:09:54         309.2 s
--     DCFC-18     c3333333  14:06:32 connector_cable       none                       14:06:43          11.7 s
--     DCFC-11     b2222222  14:09:00 communication_dropout cancelled, redone at DCFC-29 14:09:00     0.0 s
--     DCFC-29     5ea53696  14:24:39 session_aborted_other none                       14:24:39          0.0 s
--     DCFC-13     a1111111  14:27:36 connector_cable       none                       14:27:36          0.0 s
--
--   Why two paths: twin.ottoq_sim_stop_charge_session re-queues a faulted car at once only when it is more than 5
--   points under its target (`v_requeue`); a car within 5 points takes the robot's demate tether (11.5 s) and leaves
--   when the sweep releases it. 2cd2cbf3 and ca2624fc were within 5 points, so they took the tether, and the tether's
--   release waited on 0760's predicate for the full 5.8-minute cycle. Their bookings were released at the end of the
--   demate (`charge_session_faulted`, 14:04:26.98 and 14:04:56.89), so for five minutes the calendar called the post
--   free while the car's pointer still stood in it.
--   Nothing else gave a car to a faulted charger: in each fault window there were 0 sessions started and 0 bookings
--   made for another car before the repair (0372's candidate source, HW.002 and twin.ottoq_sim_recover_chargers hold
--   as 0612 measured). The renderer drew the charge arm still in the port because its interlock keeps a latched
--   connector in while the cleaning arm is out "whatever the charge or the tether says" (ottoyarddepot-sim
--   roboticService.armSessionInput); that side is fixed in ottoyarddepot-sim, the same evening.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_release_expired_tethers gets one anchored insertion inside 0760's predicate: an expired demate tether
--   is held for the stall's cleaning arm only while the stall's charger is NOT `Faulted`
--   (ottoq_ocpp_chargers.station_state through stalls.ocpp_charger_id). On a faulted post the car is released when the
--   demate window ends, as a car with no clean is. The rest is the machinery that already handles a car leaving its
--   post mid-clean: twin.ottoq_sim_advance_visit_atoms cancels the arm's routine clean (0764,
--   `left_the_cabin_robot`) or puts a needed tidy back to pending, and 0767 has the car's next post clean it. Rule 9
--   holds both ways: the charge is re-queued to finish, and no service is skipped.
--   Unchanged: a charge that ends normally (0760's hold stands), a charging or inbound tether, a car with no arm at
--   work, a stall with no charger, and every depot where stall_cabin_robot is 0 (no atom carries the performer).
--   A production depot reads the same column from the charger's own OCPP status, so this is no twin-only path.
--   Known limit, recorded not fixed: between the release and the arm's own exit the engine no longer holds the car
--   for the arm (0758's hold asks about the stall the car stands on). The renderer's clean gate keeps the drawn car
--   until the arm is home (bounded 30 s). A real depot needs the robot's clear signal for that window; see the
--   frontier plan's interlock item.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   - P0: nothing in flight.
--   - P1: not already applied; 0760 is applied; the sweep is the body read (prosrc md5 bad69ddf, read 2026-11-03
--     04:00 UTC); the columns the new predicate reads exist.
--   - The pre-image goes to ottoq_schema_snapshots as '0792_pre'.
--   - The anchor matches exactly once.
--   - V1: the body minus its insertion is its pre-image.
--   - V2: the new predicate runs bare on the live tables (the sweep swallows its own errors and returns 0, so running
--     the sweep could not tell a broken predicate from a quiet tick).
--   Executed by tests/test_faulted_post_lets_its_car_go_sql.py on the scratch PostgreSQL: the fixture of 0760's test
--   with 0760 applied reproduces the live body to the md5, then this file runs whole.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At stall_cabin_robot 0, the default and every certification
--   arm's, no atom carries the performer, so 0760's predicate is true for every car and the added conjunct changes
--   nothing (V1).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0792_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0792_a_faulted_post_lets_its_car_go_whatever_the_cleaning_arm_is_doing'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0792 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: not applied, 0760 applied, the sweep as read, the columns read ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0792_a_faulted_post_lets_its_car_go_whatever_the_cleaning_arm_is_doing') THEN
    RAISE EXCEPTION '0792 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0760_a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go') THEN
    RAISE EXCEPTION '0792 P1: 0760 is not applied (this file narrows its hold)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_release_expired_tethers(timestamp with time zone)'))
     IS DISTINCT FROM 'bad69ddf41e763b91e7f18c3d28d7d02' THEN
    RAISE EXCEPTION '0792 P1: public.ottoq_release_expired_tethers is not the body read (md5 bad69ddf)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'stalls' AND column_name = 'ocpp_charger_id')
     OR (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'ottoq_ocpp_chargers'
            AND column_name IN ('charger_id', 'station_state')) <> 2 THEN
    RAISE EXCEPTION '0792 P1: a column the new predicate reads is missing';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0792_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure;

-- ── the sweep: the cleaning arm's hold does not apply on a faulted post ──
CREATE TEMP TABLE _0792_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0792_patch VALUES
  (1,
   $o1$                               AND a->>'robot_stall_id' = v.robotic_tether_stall_id::text))
  ), cleared AS ($o1$,
   $n1$                               AND a->>'robot_stall_id' = v.robotic_tether_stall_id::text)
                -- 0792 (G506): ...and only while the stall's charger is not Faulted. 0760's hold is for a charge that
                -- ENDED, its car at target and waiting for the arm. A charger that faulted has ended nothing: its car
                -- is re-queued to finish (rule 9), so it is released when the demate window ends, and the car's next
                -- post cleans the cabin (0764 cancels the routine, 0767 begins it again; a needed tidy goes back to
                -- pending). A stall with no charger, or a charger in any other state, holds the car as 0760 did.
                AND NOT EXISTS (SELECT 1
                                  FROM public.stalls fs
                                  JOIN public.ottoq_ocpp_chargers fc ON fc.charger_id = fs.ocpp_charger_id
                                 WHERE fs.id = v.robotic_tether_stall_id
                                   AND fc.station_state = 'Faulted'))
  ), cleared AS ($n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0792_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0792: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0792: the sweep is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertion is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0792_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'bad69ddf41e763b91e7f18c3d28d7d02' THEN
    RAISE EXCEPTION '0792 V1: the sweep less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the new predicate runs on the live tables, over every car (the sweep would swallow an error and return 0) ──
DO $v2$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
    FROM public.vehicles v
   WHERE NOT EXISTS (SELECT 1
                       FROM public.stalls fs
                       JOIN public.ottoq_ocpp_chargers fc ON fc.charger_id = fs.ocpp_charger_id
                      WHERE fs.id = v.robotic_tether_stall_id
                        AND fc.station_state = 'Faulted');
  IF n IS NULL THEN
    RAISE EXCEPTION '0792 V2: the predicate did not run';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0792_a_faulted_post_lets_its_car_go_whatever_the_cleaning_arm_is_doing', false, false,
        'G506. One anchored insertion in public.ottoq_release_expired_tethers, inside 0760''s predicate: the cleaning '
        'arm''s hold on an expired demate tether applies only while the stall''s charger is not Faulted. Demo run '
        '8c0b2e04 (2026-11-02): two cars whose chargers faulted mid-clean were held on the dead post 309 and 339 s, '
        'until the 5.8-minute clean ran out. On a faulted post the car is now released when the demate window ends, and '
        'its next post cleans the cabin (0764, 0767). At stall_cabin_robot 0 nothing changes (V1).',
        now());

COMMIT;
