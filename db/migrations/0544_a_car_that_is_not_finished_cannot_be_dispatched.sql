-- migration-version: 20260928033602
-- migration-name:    a_car_that_is_not_finished_cannot_be_dispatched
--
-- 0544  **A car that is not finished cannot be dispatched. The dispatch door refuses it, and the dispatch ledger cannot
--        record it.**
--
-- ══ §1 WHY (Chase, 2026-09-27 8:00 PM CT; CLAUDE.md rule 9; G268) ═══════════════════════════════════════════════════
--
--   "Vehicles cannot leave the depot with any remaining service still needed, EVER." 0543 made that a predicate
--   (`public.ottoq_departure_clear`) at both dispatchers and said, in its §4, that the schema would refuse the write
--   only after a validation run showed zero such departures: measure first, then enforce. Validation run 9eab647f
--   (busy_day at 8x on c9d14225's seed, the first operator day under 0542 and 0543, 9:15-10:24 PM CT): 0402 §2 read
--   112 departures, 0 with a service open and 0 below 99%.
--
--   Every writer of a departure, traced before this file (comment-stripped census of every function that writes a
--   dispatch row or moves a car to `deployed` / `en_route_to_deployment`, 2026-09-28 03:00 UTC):
--     - `twin.ottoq_sim_dispatch_vehicle`, the dispatch door. The only writer on an operator path. Its one caller,
--       `twin.ottoq_sim_auto_dispatch_tick`, dispatches the deploy plan's release list and counts a dispatch only when
--       the door returns an id (0019).
--     - `twin.ottoq_sim_prime_deployment`, the boot: cars already out when the day begins, each dated at or before the
--       run's start (dispatched_at = start - the trip's elapsed minutes).
--     - `ottoq_cert_arm`, `ottoq_cert_arm_start`, `ottoq_cert_arm_wave`, `ottoq_fr1_cert_arm`: benchmark arms that seed
--       a fleet already out, dated at the run's start (the wave arm nine hours before it).
--     - `ottoq_fifo_tick`, `ottoq_manual_tick`: C5 baselines that write `en_route_to_deployment` with no dispatch row,
--       on no operator path (0543 §4).
--     - The decide tick's redeployment writes a decision, not a departure (0075: the decision row is the deploy signal
--       the deploy plan ranks by).
--   Measured over every run that still holds dispatch rows (7 runs): all 327 rows with no door witness at the start are
--   dated at or before their run's start, and all 80 door dispatches after it. (Three July rows after the start have no
--   witness left: their events were purged. They predate the door's event.) So "dated after the run's start" is
--   exactly what 0402 §2 measured as a departure, and the boundary this file enforces is the one it measured.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The door. `twin.ottoq_sim_dispatch_vehicle` refuses a car that is not departure-clear, asked exactly as the
--       deploy plan asks (`ottoq_departure_clear(car, run, clock, true)`: charge at its effective target - 1, no service
--       open, readiness check done). It refuses as 0019 refuses a car owing a due rider-flag cleaning: one warning
--       event, `twin.dispatch_refused_unfinished`, naming what is open and the charge against its target, and NULL,
--       which its caller already counts as no dispatch. The car stays where it is, and the next tick's recheck (0543
--       (d)) sends it back to what it needs. Under the deploy plan's own filter this branch is never taken; if it ever
--       is, it says so out loud.
--   (b) The floor. A BEFORE INSERT trigger on `public.ottoq_vehicle_dispatches` rejects an `active` dispatch of a car
--       that is not departure-clear at its `dispatched_at`, readiness check included. A row dated at or before its
--       run's start is the day's initial conditions, a car already out, and passes. A row with no run (production) has
--       no initial conditions and is always judged. The rejection is a check violation naming the car. `returning`
--       rows (the boot's inbound slice) are cars coming home, not departures, and are not judged.
--   Why both: the door keeps the tick alive and makes a refusal visible; the floor makes impossible a departure the
--   door never saw, whoever writes it. The predicate plans, the door refuses, the schema forbids (rule 6: assignment
--   plus verification, always).
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   The door asks the deploy plan's own predicate, at the same clock, in the same tick, so it refuses nothing the plan
--   releases; the floor passes every seeding row and every clear departure. No arm writes anything it did not write
--   before. V3 proves both halves on a stored run.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - The vehicle's own state. A car can be recorded `deployed` with no dispatch row: the C5 baselines, and in
--     production a real vehicle's own signal. Reality is recorded, never refused. A car that leaves without OTTO-Q's
--     release is an incident to witness, not a write to reject, and no such writer runs on an operator path today.
--   - An owner's request. Rule 9 honours an owner's request to take a car as the owner's requirement. No path for one
--     exists. When one is built, it passes this floor with a waiver the owner records before the dispatch, never by
--     disabling the trigger.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0544 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the door is the one measured, the predicate exists, and the writers of a dispatch row are the six traced ──
DO $premises$
DECLARE v_writers text[];
  c_six CONSTANT text[] := ARRAY['public.ottoq_cert_arm', 'public.ottoq_cert_arm_start', 'public.ottoq_cert_arm_wave',
                                 'public.ottoq_fr1_cert_arm', 'twin.ottoq_sim_dispatch_vehicle', 'twin.ottoq_sim_prime_deployment'];
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamp with time zone)'::regprocedure)
     <> 'bd0e74ec2fd0378e0f3fcfe4cb01e64d' THEN
    RAISE EXCEPTION '0544 P2: twin.ottoq_sim_dispatch_vehicle is not the function measured';
  END IF;
  IF to_regprocedure('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)') IS NULL THEN
    RAISE EXCEPTION '0544 P2: public.ottoq_departure_clear (0543) is missing';
  END IF;
  IF to_regprocedure('public.ottoq_refuse_unfinished_departure()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.ottoq_vehicle_dispatches'::regclass
                                           AND tgname = 'trg_dispatch_departure_clear') THEN
    RAISE EXCEPTION '0544 P2: an object this file creates already exists';
  END IF;
  SELECT array_agg(DISTINCT n.nspname || '.' || p.proname) INTO v_writers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
         ~* 'insert\s+into\s+(public\.)?ottoq_vehicle_dispatches';
  -- compared as sets: the census is the six traced, no more and no fewer
  IF NOT (v_writers @> c_six AND v_writers <@ c_six) THEN
    RAISE EXCEPTION '0544 P2: the writers of a dispatch row are not the six traced: %', v_writers;
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0544_pre', 'function', 'twin', 'ottoq_sim_dispatch_vehicle',
       pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamp with time zone)'::regprocedure),
       md5(pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamp with time zone)'::regprocedure));

-- ── (a) the door ──
DO $door$
DECLARE v_def text; n int;
  c_old CONSTANT text := $o$  v_seed := abs(hashtextextended(p_vehicle_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), 42));$o$;
  c_new CONSTANT text := $n$  -- ═══════════════ 0544 (CLAUDE.md rule 9): THE SECOND DOOR — NO CAR LEAVES UNFINISHED ═══════════════
  -- The deploy plan already offers only a car that is departure-clear (0543). This asks the same question, at the same
  -- clock, where the dispatch row is actually written, so that no present or future caller can send a car out with a
  -- service open or its charge short of its target. Under the plan's filter this branch is never taken; if it is, the
  -- event says so, the car stays where it is, and the next tick's recheck sends it back to what it needs.
  IF NOT COALESCE(public.ottoq_departure_clear(p_vehicle_id, p_sim_run_id, p_sim_clock_now, true), false) THEN
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type    := 'ottoq_engine',
        p_actor_id      := 'departure_door',
        p_event_type    := 'twin.dispatch_refused_unfinished',
        p_entity_type   := 'vehicle',
        p_entity_id     := p_vehicle_id,
        p_payload       := jsonb_build_object(
          'reason', 'the car is not finished: a service is open or its charge is short of its target',
          'soc', v_vehicle.current_soc,
          'target_soc', public.ottoq_effective_target_soc_at(p_vehicle_id, p_sim_clock_now),
          'open', (SELECT COALESCE(jsonb_agg(DISTINCT a->>'svc'), '[]'::jsonb)
                     FROM ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
                    WHERE vn.vehicle_id = p_vehicle_id
                      AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                        = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                      AND vn.status IN ('open', 'in_progress')
                      AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')),
          'doctrine', 'no_car_leaves_with_a_service_still_needed',
          'sim_clock', p_sim_clock_now),
        p_severity      := 'warning',
        p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id    := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN NULL;
  END IF;

  v_seed := abs(hashtextextended(p_vehicle_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), 42));$n$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamp with time zone)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0544 door: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $door$;

-- ── (b) the floor ──
CREATE FUNCTION public.ottoq_refuse_unfinished_departure() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
DECLARE v_t0 timestamptz;
BEGIN
  -- 0544 (CLAUDE.md rule 9): an active dispatch is a car leaving the depot, and a car leaves only when it is finished
  -- (public.ottoq_departure_clear, readiness check included). A row dated at or before its run's start is the day's
  -- initial conditions (a car already out when the run begins: the boot's prime deployment, the benchmark arms), not a
  -- departure. A row with no run is production and is always judged.
  IF NEW.sim_run_id IS NOT NULL THEN
    SELECT r.sim_clock_start INTO v_t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id;
    IF NEW.dispatched_at <= v_t0 THEN
      RETURN NEW;
    END IF;
  END IF;
  IF NOT COALESCE(public.ottoq_departure_clear(NEW.vehicle_id, NEW.sim_run_id, NEW.dispatched_at, true), false) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'check_violation',
      MESSAGE = format('0544 (CLAUDE.md rule 9): vehicle %s may not leave the depot at %s: a service is open, its '
                       'readiness check is not done, or its charge is short of its target', NEW.vehicle_id, NEW.dispatched_at),
      HINT    = 'Finish the car first. public.ottoq_departure_clear(vehicle, run, clock, true) says when it may leave.';
  END IF;
  RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.ottoq_refuse_unfinished_departure() IS
  '0544 (CLAUDE.md rule 9): BEFORE INSERT on ottoq_vehicle_dispatches (status active). Rejects the dispatch of a car '
  'that is not departure-clear at dispatched_at. Rows dated at or before their run''s start are initial conditions and '
  'pass; rows with no run are always judged.';

CREATE TRIGGER trg_dispatch_departure_clear
  BEFORE INSERT ON public.ottoq_vehicle_dispatches
  FOR EACH ROW WHEN (NEW.status = 'active')
  EXECUTE FUNCTION public.ottoq_refuse_unfinished_departure();

-- ── V1 (comment-stripped): the door asks the plan's question before it writes, and the floor is armed ──
DO $verify$
DECLARE v_src text; p_clear int; p_insert int;
BEGIN
  v_src := regexp_replace(regexp_replace(
             pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamp with time zone)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  p_clear  := position('public.ottoq_departure_clear(p_vehicle_id, p_sim_run_id, p_sim_clock_now, true)' IN v_src);
  p_insert := position('INSERT INTO ottoq_vehicle_dispatches' IN v_src);
  IF p_clear = 0 OR p_insert = 0 OR p_clear > p_insert THEN
    RAISE EXCEPTION '0544 V1: the door does not ask the departure predicate before it writes (at %, insert at %)',
      p_clear, p_insert;
  END IF;
  IF position('''twin.dispatch_refused_unfinished''' IN v_src) = 0 THEN
    RAISE EXCEPTION '0544 V1: the door does not say when it refuses';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.ottoq_vehicle_dispatches'::regclass
                    AND t.tgname = 'trg_dispatch_departure_clear' AND t.tgenabled = 'O'
                    AND t.tgfoid = 'public.ottoq_refuse_unfinished_departure()'::regprocedure
                    AND pg_get_triggerdef(t.oid) ~ 'BEFORE INSERT ON public\.ottoq_vehicle_dispatches FOR EACH ROW WHEN \(\(new\.status = ''active''::text\)\)') THEN
    RAISE EXCEPTION '0544 V1: the floor is not armed as written';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0544_a_car_that_is_not_finished_cannot_be_dispatched', false, false,
  'Rule 9, enforced after 0402 measured zero: the dispatch door (twin.ottoq_sim_dispatch_vehicle) refuses a car that '
  'is not departure-clear, with one warning event and NULL as 0019 does, and a BEFORE INSERT trigger on '
  'ottoq_vehicle_dispatches rejects an active dispatch of a car that is not departure-clear (rows at or before their '
  'run''s start are initial conditions). The door asks the deploy plan''s own predicate at the same clock, so no arm '
  'writes anything it did not write before.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the ended validation run 9eab647f (its cars and visits are still on record):
--   (a) the door refuses a full car with an open wash: NULL, no dispatch row, the car still staged, one refusal event
--       naming the wash.
--   (b) with the wash done the door dispatches it: an id, the car deployed.
--   (c) the floor rejects a direct insert of a car at 95% dated after the run's start, as a check violation.
--   (d) the floor passes the same row dated at the run's start (initial conditions), and a returning row after it.
--   (e) the floor judges a row with no run: the car at 95% is rejected.
DO $v3$
DECLARE
  v_msg text; v_run uuid := '9eab647f-01ae-4c32-92eb-a9803f1397af'; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz; v_t0 timestamptz; v_cars uuid[]; c1 uuid; c2 uuid; v_visit uuid;
  a_id uuid; a_rows int; a_state text; a_events int; a_open jsonb; b_id uuid; b_state text;
  c_state text; d_seed int; d_ret int; e_state text;
BEGIN
  BEGIN
    SELECT r.sim_clock_current, r.sim_clock_start INTO v_clock, v_t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    IF v_clock IS NULL THEN RAISE EXCEPTION '0544 V3: run % is gone; point V3 at a run that exists', v_run; END IF;
    -- two twin cars that nothing else holds at the clock: no live dispatch, not tethered, no rider flag due
    SELECT array_agg(id ORDER BY id) INTO v_cars FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_twin AND v.category = 'autonomous'
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d
                          WHERE d.vehicle_id = v.id AND d.sim_run_id = v_run AND d.status IN ('active', 'returning'))
         AND NOT public.ottoq_vehicle_is_tethered(v.id, v_clock)
         AND NOT public.ottoq_rider_flag_due(v.id, v_run, v_clock)
       ORDER BY v.id LIMIT 2) q;
    IF coalesce(array_length(v_cars, 1), 0) < 2 THEN RAISE EXCEPTION '0544 V3: fewer than two free twin cars'; END IF;
    c1 := v_cars[1]; c2 := v_cars[2];
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.vehicles SET current_state = 'staged_for_departure'::vehicle_state, current_soc = 100,
                               config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', '"ready"')
     WHERE id = ANY (v_cars);

    -- (a) the door refuses c1, full, with an open wash
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    VALUES (c1, v_run, v_twin, v_clock - interval '60 minutes', '0544_v3_a',
            '[{"svc":"exterior_wash","must_do":true,"status":"pending","concurrency":"bay","requires_bay":"wash_bay"}]'::jsonb,
            'open')
    RETURNING visit_id INTO v_visit;
    a_id := twin.ottoq_sim_dispatch_vehicle(c1, v_run, v_clock);
    SELECT count(*) INTO a_rows FROM public.ottoq_vehicle_dispatches
     WHERE vehicle_id = c1 AND sim_run_id = v_run AND dispatched_at = v_clock;
    SELECT v.current_state::text INTO a_state FROM public.vehicles v WHERE v.id = c1;
    SELECT count(*), (array_agg(e.payload->'open'))[1] INTO a_events, a_open FROM public.ottoq_events e
     WHERE e.sim_run_id = v_run AND e.entity_id = c1 AND e.event_type = 'twin.dispatch_refused_unfinished';
    IF a_id IS NOT NULL OR a_rows <> 0 OR a_state IS DISTINCT FROM 'staged_for_departure' OR a_events <> 1
       OR NOT COALESCE(a_open @> '["exterior_wash"]'::jsonb, false) THEN
      RAISE EXCEPTION '0544 V3 FAILED (a): id %, rows %, state %, refusal events %, open %', a_id, a_rows, a_state, a_events, a_open;
    END IF;

    -- (b) with the wash done the door dispatches c1
    UPDATE public.ottoq_visit_needs SET atoms = jsonb_set(atoms, '{0,status}', '"done"') WHERE visit_id = v_visit;
    b_id := twin.ottoq_sim_dispatch_vehicle(c1, v_run, v_clock);
    SELECT v.current_state::text INTO b_state FROM public.vehicles v WHERE v.id = c1;
    IF b_id IS NULL OR b_state IS DISTINCT FROM 'deployed' THEN
      RAISE EXCEPTION '0544 V3 FAILED (b): a finished car was not dispatched (id %, state %)', b_id, b_state;
    END IF;

    -- (c) the floor rejects a direct insert of c2 at 95%, dated after the run's start
    UPDATE public.vehicles SET current_soc = 95 WHERE id = c2;
    BEGIN
      INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                   planned_duration_min, soc_at_dispatch_pct, status)
      VALUES (c2, v_run, v_clock, v_clock + interval '60 minutes', 60, 95, 'active');
      c_state := 'admitted';
    EXCEPTION WHEN check_violation THEN
      c_state := CASE WHEN SQLERRM LIKE '0544 (CLAUDE.md rule 9)%' THEN 'rejected' ELSE 'other: ' || SQLERRM END;
    END;
    IF c_state IS DISTINCT FROM 'rejected' THEN RAISE EXCEPTION '0544 V3 FAILED (c): the floor %', c_state; END IF;

    -- (d) the same row at the run's start is initial conditions, and a returning row after it is a car coming home
    INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                 planned_duration_min, soc_at_dispatch_pct, status)
    VALUES (c2, v_run, v_t0, v_t0 + interval '60 minutes', 60, 95, 'active');
    GET DIAGNOSTICS d_seed = ROW_COUNT;
    INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                 planned_duration_min, soc_at_dispatch_pct, status)
    VALUES (c2, v_run, v_clock, v_clock + interval '60 minutes', 60, 95, 'returning');
    GET DIAGNOSTICS d_ret = ROW_COUNT;
    IF d_seed <> 1 OR d_ret <> 1 THEN
      RAISE EXCEPTION '0544 V3 FAILED (d): initial conditions % row(s), returning % row(s)', d_seed, d_ret;
    END IF;

    -- (e) a row with no run is always judged: c2 at 95% is rejected
    BEGIN
      INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                   planned_duration_min, soc_at_dispatch_pct, status, data_source)
      VALUES (c2, NULL, now(), now() + interval '60 minutes', 60, 95, 'active', 'production');
      e_state := 'admitted';
    EXCEPTION WHEN check_violation THEN
      e_state := CASE WHEN SQLERRM LIKE '0544 (CLAUDE.md rule 9)%' THEN 'rejected' ELSE 'other: ' || SQLERRM END;
    END;
    IF e_state IS DISTINCT FROM 'rejected' THEN RAISE EXCEPTION '0544 V3 FAILED (e): the floor %', e_state; END IF;

    RAISE EXCEPTION '0544 V3 PASSED: the door refused a full car with an open wash (no row, still %, one event naming %), then dispatched it with the wash done (%); the floor rejected a 95%% departure after the start, passed the same row at the start and a returning row, and rejected a 95%% row with no run',
      a_state, a_open, b_state;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0544 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0544 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: DROP TRIGGER trg_dispatch_departure_clear ON public.ottoq_vehicle_dispatches;
--   DROP FUNCTION public.ottoq_refuse_unfinished_departure(); then EXECUTE the one `definition` in
--   ottoq_schema_snapshots WHERE label = '0544_pre' as it is.
COMMIT;
