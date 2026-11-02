-- migration-version: PENDING
-- migration-name:    a_car_on_a_charger_comes_to_its_bay_when_the_charge_it_is_on_ends
--
-- 0785  **A car on a charger comes to its bay when the charge it is on ends, not when its plan's last charge leg does.
--       The bay yield read a charging car's latest planned charge leg, so a car minutes from full read as hours away and
--       gave its bay hold to another car; on a full calendar it lost its place altogether.** (G505; db/checks/0473 §8 (f))
--       Chase, 2026-09-27 (CLAUDE.md rule 9): "OTTO-Q has to be all seeing and all knowing." And 2026-10-24 (rule 14):
--       "we don't own our own vehicles, we manage for others". The yield gives one owner's bay to another owner's car
--       on an estimate; this file makes the estimate the car's.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-25 5:36-5:42 PM CT; run 763734d4; db/checks/0473 §8 (f), queries (7)-(8)) ════
--
--   ottoq.ottoq_yield_bay_holds (0553, G283) frees a bay for a car waiting now when every hold in the way belongs to a
--   car that cannot be there before the waiting car would finish, moving each such hold to its car's ETA, or releasing it
--   when no slot opens within 240 minutes of that ETA. The ETA, ottoq.ottoq_bay_hold_car_eta, answers for a car on a
--   charger (charging_dcfc, charging_l2) with the latest planned_end_sim over every open charge leg of the car: the plan,
--   not the charge it is on. At the twin depot as built since 0763 (30 robotic fast chargers, no standard charger) the
--   itinerary still plans a standard charge by its fixed rule (G459), which nothing will run (G500, 0780).
--   Run 763734d4-17dc-4f77-9cd6-effdd0bcafd0, busy_day at the twin depot (rule 8), 13:00-22:00:20 sim. At 13:40:58 car
--   7ec698b8-b6ac-4e77-b9f8-a3a42a34e2c7 (Tesla Robotaxi TN; a fault repair owed; held for NASH-SVC-01 14:00-15:29, booked
--   at 13:00:39) was on a fast charger at 94%, its fast-charge leg planned to end 13:54. Its itinerary also carried a
--   charge_l2 leg planned 21:40-22:31. The ETA read 22:34, the yield gave the bay to a car waiting now
--   (a1111111-0001-0001-0001-000000000005, Waymo Nashville, 13:40:58-14:20:58), no slot opened within 240 minutes of
--   22:34, and the hold was released ('replanned_no_window', blocked_by 'yield:charging_dcfc'). The car was at 100% by
--   13:58:08 (a station fault cut its first charge at 13:41:14; plugged in again at 13:48:16), about 14:01 at the bay with
--   the depot's 3-minute taxi: before the waiting car would have finished, so by 0553's own rule the hold should not have
--   given way. It then waited until the run stopped, held 244 times for "must_do_service_outstanding_bay_busy", never
--   booked into a service bay again, its repair still owed after 8 hours. One of the run's two yields; the other moved a
--   detail hold for a car in a service bay, as designed. One car on one run.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dial bay_hold_eta_reads_charge (0..1, default 0; not agent-writable).
--   (b) ottoq.ottoq_bay_hold_car_eta, one anchored insertion that acts only at 1: for a car on a charger, the latest
--       planned end over the charge legs of its charger's kind (charge_dcfc on a fast charger, charge_l2 on a standard
--       one) that have begun (an actual start, or a planned start not after the clock). Without one, 0553's fallback
--       answers as before: what is left of the charge at the session's own pace so far (G240), or NULL, which never
--       yields a hold. A charge leg the car is not on is never its ETA.
--   Not changed: the yield's rule, the move or release of a hold, the ETA of a car in a bay, out of the depot or not on
--   a charger; how full a car charges, which services it needs, when it may leave (rule 9: the departure test reads the
--   car's battery). Whether a hold the yield releases should be booked again ahead of holds made after it is G505's
--   other question, not this file's.
--
-- ══ §3 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the body is the one this file patches (prosrc md5 12670129); the dial is absent. P2 not
--   already applied. Pre-image to ottoq_schema_snapshots as '0785_pre'. The anchor matches once. V1 the body less its
--   insertion is its pre-image. V2 at the default, every car of the latest twin-depot run reads, at that run's last
--   clock, the ETA the pre-image gives (a copy of it in pg_temp). V3 the dial is catalogued 0..1 default 0 and not
--   agent-writable; in a sub-block that rolls back, with the dial at 1 on that run, every car's ETA is computed and every
--   car not on a charger reads as before. Executed in full by tests/test_bay_hold_eta_reads_charge_sql.py on the scratch
--   PostgreSQL over the live bodies (md5 asserted), where a car on a charger with a phantom leg is built and read.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the body computes what it computed before
--   (V1), and no certification arm, canon cell or dial experiment sets the dial. Rule 12: switched on at the twin depot
--   after the apply, as its own statement, under the deciding person's name; no sweep, no pair.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0785_pre';
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_hold_eta_reads_charge' (and its policy rows);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0785_a_car_on_a_charger_comes_to_its_bay_when_the_charge_it_is_on_ends'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0785 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body read, nothing of this file ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('ottoq.ottoq_bay_hold_car_eta(uuid,uuid,timestamp with time zone,numeric)'))
     IS DISTINCT FROM '12670129429dc811e86eabb69ee38456' THEN
    RAISE EXCEPTION '0785 P1: ottoq.ottoq_bay_hold_car_eta is not the body this file patches (md5 12670129)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_hold_eta_reads_charge') THEN
    RAISE EXCEPTION '0785 P1: the dial already exists';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0785_a_car_on_a_charger_comes_to_its_bay_when_the_charge_it_is_on_ends') THEN
    RAISE EXCEPTION '0785 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0785_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_bay_hold_car_eta(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_hold_eta_reads_charge',
        '0785 (G505): 1 = the bay yield''s ETA for a car on a charger is the end of the charge it is on (a charge leg of '
        'its charger''s kind that has begun; without one, the session''s own pace), never a charge leg it is not on, so a '
        'car minutes from full keeps its bay hold against a phantom standard charge (G459). 0 = the latest planned end '
        'over every open charge leg, as before 0785.',
        0, 0, 1, 'ottoq.ottoq_bay_hold_car_eta (ottoq.ottoq_yield_bay_holds)', false);

-- ── (b) the anchored insertion ──
CREATE TEMP TABLE _0785_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0785_patch VALUES
  (1, 'ottoq.ottoq_bay_hold_car_eta(uuid,uuid,timestamp with time zone,numeric)'::regprocedure,
   $o1$       AND l.actual_end_sim IS NULL AND l.planned_end_sim > p_clock;
    IF v_end IS NULL THEN
$o1$,
   $n1$       AND l.actual_end_sim IS NULL AND l.planned_end_sim > p_clock;
    -- 0785 (G505): with bay_hold_eta_reads_charge on, the end of the charge the car is on: a leg of its charger's kind
    -- that has begun. Never a charge leg it is not on: at a depot whose itinerary plans a charge the depot cannot give
    -- (G459), that leg ends hours after the car is full, and a car minutes from full would read as hours away.
    IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_hold_eta_reads_charge', 0), 0) >= 1 THEN
      SELECT max(l.planned_end_sim) INTO v_end
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = p_vehicle_id
         AND l.leg_type = CASE v.state WHEN 'charging_dcfc' THEN 'charge_dcfc' ELSE 'charge_l2' END
         AND l.status IN ('planned', 'active', 'in_progress')
         AND l.actual_end_sim IS NULL AND l.planned_end_sim > p_clock
         AND (l.actual_start_sim IS NOT NULL OR l.planned_start_sim <= p_clock);
    END IF;
    IF v_end IS NULL THEN
$n1$);

DO $patch$
DECLARE f regprocedure; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0785_patch LOOP
    v_def := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0785_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0785: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0785: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: the patched body less its insertion is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'ottoq.ottoq_bay_hold_car_eta(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;
  FOR p IN SELECT * FROM _0785_patch LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '12670129429dc811e86eabb69ee38456' THEN
    RAISE EXCEPTION '0785 V1: ottoq_bay_hold_car_eta less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: at the default, every car of the latest twin-depot run reads the pre-image's ETA ──
DO $v2$
DECLARE v_pre text; r record; v_n int := 0; v_bad int := 0;
BEGIN
  SELECT definition INTO v_pre FROM public.ottoq_schema_snapshots
   WHERE label = '0785_pre' AND object_kind = 'function' AND object_name = 'ottoq_bay_hold_car_eta'
   ORDER BY snapshot_id DESC LIMIT 1;
  v_pre := replace(v_pre, 'FUNCTION ottoq.ottoq_bay_hold_car_eta(', 'FUNCTION pg_temp.ottoq_bay_hold_car_eta_0785_pre(');
  IF strpos(v_pre, 'pg_temp.ottoq_bay_hold_car_eta_0785_pre(') = 0 THEN
    RAISE EXCEPTION '0785 V2: the pre-image could not be copied into pg_temp';
  END IF;
  EXECUTE v_pre;
  FOR r IN
    SELECT s.sim_run_id, s.sim_clock_current AS clock, v.id AS vehicle_id
      FROM (SELECT sim_run_id, sim_clock_current FROM public.ottoq_sim_runs
             WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_current IS NOT NULL
             ORDER BY started_at DESC NULLS LAST LIMIT 1) s
      CROSS JOIN public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
  LOOP
    v_n := v_n + 1;
    IF ottoq.ottoq_bay_hold_car_eta(r.sim_run_id, r.vehicle_id, r.clock, 3)
       IS DISTINCT FROM pg_temp.ottoq_bay_hold_car_eta_0785_pre(r.sim_run_id, r.vehicle_id, r.clock, 3) THEN
      v_bad := v_bad + 1;
    END IF;
  END LOOP;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0785 V2: at the default % of % cars read another ETA than the pre-image gives', v_bad, v_n;
  END IF;
  RAISE NOTICE '0785 V2: at the default % of % cars of the latest twin-depot run read the pre-image''s ETA', v_n - v_bad, v_n;
END $v2$;

-- ── V3: the dial; and at 1, every car's ETA is computed and every car not on a charger reads as before ──
DO $v3$
DECLARE b record; r record; v_msg text; v_n int := 0; v_on int := 0; v_bad int := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'bay_hold_eta_reads_charge' AND default_value = 0 AND min_value = 0 AND max_value = 1
                    AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0785 V3: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
  SELECT sim_run_id, sim_clock_current AS clock INTO b FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_current IS NOT NULL
   ORDER BY started_at DESC NULLS LAST LIMIT 1;
  IF b.sim_run_id IS NULL THEN
    RAISE NOTICE '0785 V3: no twin-depot run to read; the dial is catalogued';
    RETURN;
  END IF;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value)
    VALUES ('run', b.sim_run_id, 'bay_hold_eta_reads_charge', 1);
    FOR r IN SELECT v.id, v.current_state::text AS state FROM public.vehicles v
              WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous' LOOP
      v_n := v_n + 1;
      IF r.state IN ('charging_dcfc', 'charging_l2') THEN
        v_on := v_on + 1;
        PERFORM ottoq.ottoq_bay_hold_car_eta(b.sim_run_id, r.id, b.clock, 3);
      ELSIF ottoq.ottoq_bay_hold_car_eta(b.sim_run_id, r.id, b.clock, 3)
            IS DISTINCT FROM pg_temp.ottoq_bay_hold_car_eta_0785_pre(b.sim_run_id, r.id, b.clock, 3) THEN
        v_bad := v_bad + 1;
      END IF;
    END LOOP;
    IF v_bad > 0 THEN
      v_msg := format('with the dial at 1, %s cars not on a charger read another ETA', v_bad);
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0785', MESSAGE = 'v3 done';
  EXCEPTION WHEN SQLSTATE 'P0785' THEN
    NULL;   -- the dial row rolls back here
  END;
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION '0785 V3: %', v_msg;
  END IF;
  RAISE NOTICE '0785 V3: with the dial at 1 on run %: % cars read, % on a charger, every other car as before',
    left(b.sim_run_id::text, 8), v_n, v_on;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0785_a_car_on_a_charger_comes_to_its_bay_when_the_charge_it_is_on_ends', false, false,
        'Dial bay_hold_eta_reads_charge (default 0); one anchored insertion in ottoq.ottoq_bay_hold_car_eta, acting only '
        'at 1: a car on a charger is due at its bay when the charge leg of its charger''s kind that has begun ends '
        '(without one, the session''s pace, as before), never at the end of a charge leg it is not on (V1: the body less '
        'its insertion is its pre-image). No certification arm, canon cell or dial experiment sets the dial.',
        now());

COMMIT;
