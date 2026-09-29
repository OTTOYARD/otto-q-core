-- migration-version: PENDING
-- migration-name:    a_fleet_build_out_borrows_cars_for_one_test_day
--
-- 0572  **A fleet build-out borrows cars for one test day, so the twin depot can be measured at 150 and 200 cars.**
--       Lane A. Chase, 2026-09-29: "150-200 vehicles can be accommodated at any given time through 10-20 DCFC robotic
--       chargers". The twin depot has 116 autonomous cars, and the engine reads a depot's fleet as the autonomous cars
--       homed there: the snapshot, the deploy target, the fleet reset and every cursor filter
--       `category = 'autonomous' AND home_depot_id = <depot>`. So a larger fleet is only a question of which cars are
--       homed at the depot, for one day.
--
-- ══ §1 WHERE THE CARS COME FROM ══════════════════════════════════════════════════════════════════════════════════════
--
--   The Benchmark depot (22222222-..., "OTTOYARD Benchmark (CRN A/B)") holds 100 autonomous cars of the twin's own three
--   classes and operators: Tesla Robotaxi TN 29, Waymo Nashville 42, Zoox Southeast 29, with the same batteries and
--   inlets as the twin's. Measured 2026-09-29: it has hosted no run ever, its one scheduled harness job
--   (`ottoq-cert-battery`) has been inactive since 2026-07-30, its cars were last written 2026-09-19, and none of them
--   has an open visit, a live booking, leg or dispatch, or an open charge session. Borrowing them tests nothing at that
--   depot (CLAUDE.md rule 8): for one test day they are the twin's cars, measured at the twin, and then they go back.
--
-- ══ §2 WHAT THIS BUILDS ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_fleet_buildouts`: fleet150 (+34: Tesla 11, Waymo 13, Zoox 10) and fleet200 (+84: 26, 34, 24), the twin's
--       own class mix (36 / 46 / 34 of 116). The cars are chosen per class in id order, so every arm borrows the same
--       ones.
--   (b) `ottoq_fleet_buildout_apply` / `_restore` / `_census` and a deferred commit guard, 0567's pattern: a fleet
--       build-out lives only inside the transaction that applied it. Apply re-homes the chosen cars to the depot (home and
--       current depot, no stall) and clears the lender's stall pointers to them. Restore writes every car back from its
--       full pre-image and every stall pointer back from its own; only `updated_at`, which a trigger stamps, can differ.
--       Apply refuses a live run at either depot, a chosen car with live rows, and a lender short of cars.
--   (c) `ottoq_throughput_sweeps.fleet_code`: a sweep runs at one fleet size, so its pairs, contrasts, ledger rows and
--       summary never mix two. `ottoq_throughput_sweep_arms` gains `fleet_buildout` and `fleet_restore`, the receipts.
--   (d) `ottoq_throughput_sweep_arm` borrows BEFORE the fleet reset, so the reset seeds the borrowed cars exactly as it
--       seeds the depot's own (SoC from the seed and the car's id, offline, no stall, the whitelisted config), and returns
--       them AFTER the site restore. The run's payload records the receipt. With no fleet_code nothing changes.
--   (e) `ottoq_throughput_cross_sweep_twins` compares only arms at the same fleet size.
--   (f) Night 3: `fleet150_2026_10_01` and `fleet200_2026_10_01`, busy_day at the twin, 12 h from 6 AM CT at 5
--       sim-minutes a tick, deploy_peak_fraction 0.90, the first three of night 1's seeds, due 04:00 UTC 2026-10-02
--       (11 PM CT Oct 1). Three cells each: dcfc20.otto_q, dcfc20.fifo, dcfc10.otto_q. Eighteen arms.
--
-- ══ §3 WHAT IT DOES NOT CLAIM ══════════════════════════════════════════════════════════════════════════════════════════
--
--   * The borrowed cars bring the dispatcher's own demand: the deploy target is the fleet x the hour's fraction x the
--     peak x the scenario's multiplier (0434), so 200 cars ask for 200 cars' work.
--   * A score re-read after the restore sees 116 cars (0530's supply gap reads today's fleet). Read a fleet day from its
--     arm row, which is scored before the teardown.
--   * Staging space is unchanged (113 staging stalls): a full depot overflows to perimeter parking, as rule 9 allows.
--
-- ══ §4 CHECKS AND WHEN TO APPLY ═════════════════════════════════════════════════════════════════════════════════════
--
--   P0: no pair, recert, dial pair or sweep arm is in flight. P1: the arm is 0568's (md5 2c2e0953168b3e53852b2e0db4adb98a
--   of its source), 0571 is applied, the twin has 116 autonomous cars, and the lender has enough of each class with no
--   live rows. P2: not applied. The arm's four patches match exactly once. V1: the arm borrows before the reset and
--   returns after the site restore; the guard is deferred; night 3 is as declared. The round trip is EXECUTED in
--   tests/test_throughput_sweep_sql.py. Apply after 0571, with 0570 and 0571, after night 1. forces_recert and
--   forces_dial_restart FALSE: the canon, the demo and every existing sweep run with no fleet_code, where the arm is
--   unchanged.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0572_pre' (the arm, then the twins view);
--   DELETE night 3's cells and sweeps; ALTER TABLE ottoq_throughput_sweeps DROP COLUMN fleet_code; ALTER TABLE
--   ottoq_throughput_sweep_arms DROP COLUMN fleet_buildout, DROP COLUMN fleet_restore; DROP the four functions and two
--   tables; DELETE the lineage row.

BEGIN;

-- ── P0: no pair in flight (0513's one probe): this replaces the arm ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0572 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the arm is 0568's, 0571 is in, and the lender can lend ──
DO $premises$
DECLARE
  v_md5 text; v_short text; v_live int;
BEGIN
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc
   WHERE oid = to_regprocedure('public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)');
  IF v_md5 IS DISTINCT FROM '2c2e0953168b3e53852b2e0db4adb98a' THEN
    RAISE EXCEPTION '0572 P1: ottoq_throughput_sweep_arm is not 0568''s (md5 %)', v_md5;
  END IF;
  IF to_regclass('public.ottoq_throughput_cross_sweep_twins') IS NULL THEN
    RAISE EXCEPTION '0572 P1: 0571 is not applied (ottoq_throughput_cross_sweep_twins is missing)';
  END IF;
  IF (SELECT count(*) FROM public.vehicles WHERE home_depot_id = '11111111-1111-1111-1111-111111111111'
                                             AND category = 'autonomous') <> 116 THEN
    RAISE EXCEPTION '0572 P1: the twin depot no longer has 116 autonomous cars, so fleet150 and fleet200 would not be 150 and 200';
  END IF;
  SELECT string_agg(need.cls || ' needs ' || need.n || ', has ' || COALESCE(have.n, 0), '; ') INTO v_short
    FROM (VALUES ('tesla_model_y_robotaxi_2024', 26), ('waymo_jaguar_ipace_2024', 34), ('zoox_robotaxi_2024', 24)) AS need(cls, n)
    LEFT JOIN (SELECT vehicle_class_code AS cls, count(*) AS n FROM public.vehicles
                WHERE home_depot_id = '22222222-2222-2222-2222-222222222222' AND category = 'autonomous'
                GROUP BY 1) have USING (cls)
   WHERE COALESCE(have.n, 0) < need.n;
  IF v_short IS NOT NULL THEN
    RAISE EXCEPTION '0572 P1: the lender is short of cars: %', v_short;
  END IF;
  SELECT count(*) INTO v_live FROM public.vehicles v
   WHERE v.home_depot_id = '22222222-2222-2222-2222-222222222222' AND v.category = 'autonomous'
     AND (EXISTS (SELECT 1 FROM public.ottoq_visit_needs n WHERE n.vehicle_id = v.id AND n.status IN ('open','in_progress','carried_over'))
       OR EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b WHERE b.vehicle_id = v.id AND b.state::text IN ('held','active','interrupted'))
       OR EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d WHERE d.vehicle_id = v.id AND d.status IN ('active','returning'))
       OR EXISTS (SELECT 1 FROM public.ocpp_sessions s WHERE s.vehicle_id = v.id AND s.ended_at IS NULL));
  IF v_live > 0 THEN
    RAISE EXCEPTION '0572 P1: % of the lender''s cars have live rows (a visit, booking, dispatch or session)', v_live;
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF to_regclass('public.ottoq_fleet_buildouts') IS NOT NULL THEN
    RAISE EXCEPTION '0572 P2: ottoq_fleet_buildouts already exists; this file has already been applied';
  END IF;
END $fresh$;

-- ── (a) the fleet build-outs ──
CREATE TABLE public.ottoq_fleet_buildouts (
  fleet_code       text PRIMARY KEY CHECK (fleet_code ~ '^[a-z0-9_]+$'),
  depot_id         uuid NOT NULL REFERENCES public.depots(id),
  lender_depot_id  uuid NOT NULL REFERENCES public.depots(id),
  title            text NOT NULL,
  borrow_by_class  jsonb NOT NULL CHECK (jsonb_typeof(borrow_by_class) = 'object'),
  fleet_size       integer NOT NULL CHECK (fleet_size > 0),
  basis            jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (lender_depot_id <> depot_id)
);
ALTER TABLE public.ottoq_fleet_buildouts ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_fleet_buildouts_read ON public.ottoq_fleet_buildouts FOR SELECT TO authenticated, service_role USING (true);
REVOKE ALL ON public.ottoq_fleet_buildouts FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_fleet_buildouts TO authenticated, service_role;
COMMENT ON TABLE public.ottoq_fleet_buildouts IS
'0572. A larger fleet for one test day: which cars a lender depot lends (per class, chosen in id order) and the depot''s autonomous fleet with them. Applied only inside a transaction (ottoq_fleet_buildout_apply / _restore).';

INSERT INTO public.ottoq_fleet_buildouts (fleet_code, depot_id, lender_depot_id, title, borrow_by_class, fleet_size, basis) VALUES
('fleet150', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
 '150 cars: the twin''s 116 and 34 lent by the Benchmark depot, in the twin''s class mix',
 '{"tesla_model_y_robotaxi_2024": 11, "waymo_jaguar_ipace_2024": 13, "zoox_robotaxi_2024": 10}', 150,
 jsonb_build_object('asked', 'Chase, 2026-09-29: 150-200 vehicles through 10-20 robotic DCFC',
                    'mix', 'the twin''s own 36 / 46 / 34 of 116, rounded to 34')),
('fleet200', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
 '200 cars: the twin''s 116 and 84 lent by the Benchmark depot, in the twin''s class mix',
 '{"tesla_model_y_robotaxi_2024": 26, "waymo_jaguar_ipace_2024": 34, "zoox_robotaxi_2024": 24}', 200,
 jsonb_build_object('asked', 'Chase, 2026-09-29: 150-200 vehicles through 10-20 robotic DCFC',
                    'mix', 'the twin''s own 36 / 46 / 34 of 116, rounded to 84'));

-- ── (b) what is applied, and the guard that it never commits ──
CREATE TABLE public.ottoq_fleet_buildout_active (
  depot_id      uuid PRIMARY KEY REFERENCES public.depots(id),
  fleet_code    text NOT NULL REFERENCES public.ottoq_fleet_buildouts(fleet_code),
  applied_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  backend_pid   integer NOT NULL DEFAULT pg_backend_pid(),
  vehicles_pre  jsonb NOT NULL,
  stalls_pre    jsonb NOT NULL
);
ALTER TABLE public.ottoq_fleet_buildout_active ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_fleet_buildout_active FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_fleet_buildout_active TO service_role;
COMMENT ON TABLE public.ottoq_fleet_buildout_active IS
'0572. The fleet build-out applied to a depot inside the current transaction, with the full pre-image of every borrowed car and of every lender stall pointer. A deferred constraint trigger refuses to commit while a row is here.';

CREATE FUNCTION public.ottoq_fleet_buildout_must_not_commit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_fleet_buildout_active a WHERE a.depot_id = NEW.depot_id) THEN
    RAISE EXCEPTION 'fleet build-out % is still applied to depot % at commit. A fleet build-out lives only inside the transaction that applied it: call public.ottoq_fleet_buildout_restore first. This transaction rolls back, and every car is where it was.',
      NEW.fleet_code, NEW.depot_id USING ERRCODE = 'P0001';
  END IF;
  RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION public.ottoq_fleet_buildout_must_not_commit() FROM PUBLIC, anon, authenticated, service_role;
CREATE CONSTRAINT TRIGGER ottoq_fleet_buildout_never_commits
  AFTER INSERT ON public.ottoq_fleet_buildout_active
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_fleet_buildout_must_not_commit();

CREATE FUNCTION public.ottoq_fleet_buildout_apply(p_depot uuid, p_code text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
DECLARE
  f           public.ottoq_fleet_buildouts%ROWTYPE;
  v_ids       uuid[];
  v_want      integer;
  v_live      integer;
  v_vpre      jsonb;
  v_spre      jsonb;
  v_actor_type text := current_setting('ottoq.actor_type', true);
  v_actor_id   text := current_setting('ottoq.actor_id', true);
BEGIN
  SELECT * INTO f FROM public.ottoq_fleet_buildouts WHERE fleet_code = p_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fleet build-out % is not defined', p_code USING ERRCODE = 'P0002';
  END IF;
  IF f.depot_id <> p_depot THEN
    RAISE EXCEPTION 'fleet build-out % is for depot %, not %', p_code, f.depot_id, p_depot USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_fleet_buildout_active WHERE depot_id = p_depot) THEN
    RAISE EXCEPTION 'a fleet build-out is already applied to depot %', p_depot USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id IN (p_depot, f.lender_depot_id)
                                                   AND status IN ('running', 'paused')) THEN
    RAISE EXCEPTION 'fleet build-out %: a run is live at depot % or at the lender %; cars move only between runs',
      p_code, p_depot, f.lender_depot_id USING ERRCODE = '55006';
  END IF;

  -- the cars: per class, the first n at the lender in id order, so every arm borrows the same ones
  SELECT array_agg(z.id ORDER BY z.vehicle_class_code, z.id) INTO v_ids
    FROM (SELECT v.id, v.vehicle_class_code,
                 row_number() OVER (PARTITION BY v.vehicle_class_code ORDER BY v.id) AS k
            FROM public.vehicles v
           WHERE v.home_depot_id = f.lender_depot_id AND v.category = 'autonomous') z
    JOIN jsonb_each_text(f.borrow_by_class) b ON b.key = z.vehicle_class_code
   WHERE z.k <= b.value::int;
  SELECT sum(value::int) INTO v_want FROM jsonb_each_text(f.borrow_by_class);
  IF COALESCE(cardinality(v_ids), 0) <> v_want THEN
    RAISE EXCEPTION 'fleet build-out %: the lender % has % of the % cars it lends', p_code, f.lender_depot_id,
      COALESCE(cardinality(v_ids), 0), v_want USING ERRCODE = 'P0001';
  END IF;
  SELECT count(*) INTO v_live FROM public.vehicles v
   WHERE v.id = ANY (v_ids)
     AND (EXISTS (SELECT 1 FROM public.ottoq_visit_needs n WHERE n.vehicle_id = v.id AND n.status IN ('open','in_progress','carried_over'))
       OR EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b WHERE b.vehicle_id = v.id AND b.state::text IN ('held','active','interrupted'))
       OR EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d WHERE d.vehicle_id = v.id AND d.status IN ('active','returning'))
       OR EXISTS (SELECT 1 FROM public.ocpp_sessions s WHERE s.vehicle_id = v.id AND s.ended_at IS NULL));
  IF v_live > 0 THEN
    RAISE EXCEPTION 'fleet build-out %: % of the cars it would borrow have live rows (a visit, booking, dispatch or session)',
      p_code, v_live USING ERRCODE = 'P0001';
  END IF;

  SELECT jsonb_agg(to_jsonb(v) ORDER BY v.id) INTO v_vpre FROM public.vehicles v WHERE v.id = ANY (v_ids);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', s.id, 'status', s.status, 'current_vehicle_id', s.current_vehicle_id,
                                               'reserved_by', s.reserved_by, 'reserved_at', s.reserved_at,
                                               'reservation_expires_at', s.reservation_expires_at) ORDER BY s.id), '[]'::jsonb)
    INTO v_spre
    FROM public.stalls s WHERE s.current_vehicle_id = ANY (v_ids) OR s.reserved_by = ANY (v_ids);
  INSERT INTO public.ottoq_fleet_buildout_active (depot_id, fleet_code, vehicles_pre, stalls_pre)
  VALUES (p_depot, p_code, v_vpre, v_spre);

  -- say who is acting (0423(C)); the caller files it to no run
  PERFORM set_config('ottoq.actor_type', 'ottoq_engine', true);
  PERFORM set_config('ottoq.actor_id', 'fleet_buildout:' || p_code, true);
  -- parked in the same statement that moves them: offline, no stall, no tether. The stall reassignment guard reads the
  -- car's state when its stall pointer clears, and a lender car frozen mid-work (two sit in_service_bay) would read as
  -- work in progress. The fleet reset that follows seeds the rest.
  UPDATE public.vehicles
     SET home_depot_id = p_depot, current_depot_id = p_depot, current_stall_id = NULL,
         current_state = 'offline'::vehicle_state,
         robotic_tether_phase = NULL, robotic_tether_until = NULL, robotic_tether_stall_id = NULL,
         robotic_tether_direction = NULL
   WHERE id = ANY (v_ids);
  UPDATE public.stalls SET current_vehicle_id = NULL WHERE current_vehicle_id = ANY (v_ids);
  UPDATE public.stalls SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL WHERE reserved_by = ANY (v_ids);
  PERFORM set_config('ottoq.actor_type', COALESCE(v_actor_type, ''), true);
  PERFORM set_config('ottoq.actor_id', COALESCE(v_actor_id, ''), true);

  RETURN jsonb_build_object(
    'fleet_code', p_code, 'depot_id', p_depot, 'lender_depot_id', f.lender_depot_id, 'title', f.title,
    'borrowed', cardinality(v_ids), 'by_class', f.borrow_by_class, 'borrowed_ids', to_jsonb(v_ids),
    'lender_stalls_cleared', jsonb_array_length(v_spre),
    'fleet_size', (SELECT count(*) FROM public.vehicles WHERE home_depot_id = p_depot AND category = 'autonomous'),
    'applied_at', clock_timestamp());
END $fn$;
COMMENT ON FUNCTION public.ottoq_fleet_buildout_apply(uuid, text) IS
'0572. Re-home a fleet build-out''s borrowed cars to the depot for the current transaction, keeping full pre-images. Refuses a live run at either depot, a car with live rows and a short lender. The transaction cannot commit until ottoq_fleet_buildout_restore runs.';

CREATE FUNCTION public.ottoq_fleet_buildout_restore(p_depot uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
DECLARE
  a        public.ottoq_fleet_buildout_active%ROWTYPE;
  v_cols   text;
  v_n      integer;
  v_ns     integer;
  v_bad    integer;
  v_actor_type text := current_setting('ottoq.actor_type', true);
  v_actor_id   text := current_setting('ottoq.actor_id', true);
BEGIN
  SELECT * INTO a FROM public.ottoq_fleet_buildout_active WHERE depot_id = p_depot FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no fleet build-out is applied to depot %', p_depot USING ERRCODE = 'P0002';
  END IF;
  PERFORM set_config('ottoq.actor_type', 'ottoq_engine', true);
  PERFORM set_config('ottoq.actor_id', 'fleet_buildout:' || a.fleet_code, true);

  -- first parked, as apply parks them: whatever stall or tether the day left a car on is let go while the car reads
  -- offline, so no guard mistakes the release for interrupted work
  UPDATE public.vehicles
     SET current_state = 'offline'::vehicle_state, current_stall_id = NULL,
         robotic_tether_phase = NULL, robotic_tether_until = NULL, robotic_tether_stall_id = NULL,
         robotic_tether_direction = NULL
   WHERE id IN (SELECT (e->>'id')::uuid FROM jsonb_array_elements(a.vehicles_pre) e);

  -- then every column but the key, from each car's pre-image: whatever the day wrote, the car goes back as it was
  SELECT string_agg(format('%I = r.%I', attname, attname), ', ' ORDER BY attnum) INTO v_cols
    FROM pg_attribute
   WHERE attrelid = 'public.vehicles'::regclass AND attnum > 0 AND NOT attisdropped AND attgenerated = '' AND attname <> 'id';
  EXECUTE format('UPDATE public.vehicles v SET %s FROM jsonb_populate_recordset(NULL::public.vehicles, $1) r WHERE v.id = r.id',
                 v_cols) USING a.vehicles_pre;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> jsonb_array_length(a.vehicles_pre) THEN
    RAISE EXCEPTION 'fleet build-out %: restored % of % cars', a.fleet_code, v_n, jsonb_array_length(a.vehicles_pre);
  END IF;

  -- the lender's stall pointers, from their own pre-images (after the cars, whose trigger re-points a stall)
  UPDATE public.stalls s
     SET status = p.status, current_vehicle_id = p.current_vehicle_id, reserved_by = p.reserved_by,
         reserved_at = p.reserved_at, reservation_expires_at = p.reservation_expires_at
    FROM jsonb_to_recordset(a.stalls_pre) AS p(id uuid, status text, current_vehicle_id uuid, reserved_by uuid,
                                               reserved_at timestamptz, reservation_expires_at timestamptz)
   WHERE s.id = p.id;
  GET DIAGNOSTICS v_ns = ROW_COUNT;

  -- nothing may differ from the pre-image but the timestamp a trigger stamps
  SELECT count(*) INTO v_bad
    FROM jsonb_array_elements(a.vehicles_pre) e
    JOIN public.vehicles v ON v.id = (e->>'id')::uuid
   WHERE (to_jsonb(v) - 'updated_at') IS DISTINCT FROM (e - 'updated_at');
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'fleet build-out %: % cars differ from their pre-image after the restore', a.fleet_code, v_bad;
  END IF;

  DELETE FROM public.ottoq_fleet_buildout_active WHERE depot_id = p_depot;
  PERFORM set_config('ottoq.actor_type', COALESCE(v_actor_type, ''), true);
  PERFORM set_config('ottoq.actor_id', COALESCE(v_actor_id, ''), true);
  RETURN jsonb_build_object('fleet_code', a.fleet_code, 'restored', true, 'vehicles', v_n, 'lender_stalls', v_ns,
                            'fleet_size', (SELECT count(*) FROM public.vehicles WHERE home_depot_id = p_depot AND category = 'autonomous'));
END $fn$;
COMMENT ON FUNCTION public.ottoq_fleet_buildout_restore(uuid) IS
'0572. Put every borrowed car back from its full pre-image and every lender stall pointer from its own, and check that nothing but updated_at differs. Ends the fleet build-out, so the transaction can commit.';

CREATE FUNCTION public.ottoq_fleet_buildout_census(p_depot uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
  SELECT jsonb_build_object(
    'depot_id', p_depot,
    'fleet', (SELECT count(*) FROM public.vehicles WHERE home_depot_id = p_depot AND category = 'autonomous'),
    'applied', (SELECT a.fleet_code FROM public.ottoq_fleet_buildout_active a WHERE a.depot_id = p_depot))
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_fleet_buildout_apply(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_fleet_buildout_restore(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_fleet_buildout_census(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_fleet_buildout_apply(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_fleet_buildout_restore(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_fleet_buildout_census(uuid) TO authenticated, service_role;

-- ── (c) a sweep runs at one fleet size; an arm keeps its receipts ──
ALTER TABLE public.ottoq_throughput_sweeps
  ADD COLUMN fleet_code text REFERENCES public.ottoq_fleet_buildouts(fleet_code);
COMMENT ON COLUMN public.ottoq_throughput_sweeps.fleet_code IS
'0572. The fleet build-out every arm of this sweep runs with (NULL = the depot''s own fleet). One per sweep, so pairs, contrasts and the margin ledger never mix fleet sizes.';
ALTER TABLE public.ottoq_throughput_sweep_arms
  ADD COLUMN fleet_buildout jsonb,
  ADD COLUMN fleet_restore  jsonb;

-- ── (d) the arm borrows before the reset and returns after the site restore ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0572_pre', 'function', 'public', 'ottoq_throughput_sweep_arm',
       pg_get_functiondef('public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure));

DO $patch$
DECLARE
  v_def text;
  v_old1 text := $o1$  v_bo jsonb; v_restore jsonb; v_run uuid; v_boot jsonb; v_soc0 numeric;$o1$;
  v_new1 text := $n1$  v_bo jsonb; v_restore jsonb; v_run uuid; v_boot jsonb; v_soc0 numeric;
  v_fleet jsonb; v_fleet_restore jsonb;   /* 0572 */$n1$;
  v_old2 text := $o2$  PERFORM set_config('ottoq.sim_run_id', 'none', true);
  PERFORM public.ottoq_tick_invariance_reset_fleet(s.depot_id, p_seed, s.sim_start);$o2$;
  v_new2 text := $n2$  PERFORM set_config('ottoq.sim_run_id', 'none', true);
  -- 0572: a fleet build-out borrows its cars BEFORE the reset, so the reset seeds them exactly as it seeds the depot's own
  IF s.fleet_code IS NOT NULL THEN
    v_fleet := public.ottoq_fleet_buildout_apply(s.depot_id, s.fleet_code);
  END IF;
  PERFORM public.ottoq_tick_invariance_reset_fleet(s.depot_id, p_seed, s.sim_start);$n2$;
  v_old3 text := $o3$                                      'site_buildout', v_bo,$o3$;
  v_new3 text := $n3$                                      'site_buildout', v_bo, 'fleet_buildout', v_fleet,$n3$;
  v_old4 text := $o4$  v_restore := public.ottoq_site_buildout_restore(s.depot_id);$o4$;
  v_new4 text := $n4$  v_restore := public.ottoq_site_buildout_restore(s.depot_id);
  -- 0572: and the borrowed cars go back, after the chargers, from their full pre-images
  IF s.fleet_code IS NOT NULL THEN
    v_fleet_restore := public.ottoq_fleet_buildout_restore(s.depot_id);
  END IF;$n4$;
  v_old5 text := $o5$     boot_md5, h_cal, atoms, buildout, restore, score_id, scorecard, arm_metrics, arm_error)$o5$;
  v_new5 text := $n5$     boot_md5, h_cal, atoms, buildout, restore, score_id, scorecard, arm_metrics, arm_error,
     fleet_buildout, fleet_restore)$n5$;
  v_old6 text := $o6$          md5(v_boot::text), v_boot->'calibration'->>'h', v_atoms, v_bo, v_restore, v_score, v_sc, v_m, v_err)$o6$;
  v_new6 text := $n6$          md5(v_boot::text), v_boot->'calibration'->>'h', v_atoms, v_bo, v_restore, v_score, v_sc, v_m, v_err,
          v_fleet, v_fleet_restore)$n6$;
  n int;
  v_olds text[];
  v_news text[];
  i int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure);
  v_olds := ARRAY[v_old1, v_old2, v_old3, v_old4, v_old5, v_old6];
  v_news := ARRAY[v_new1, v_new2, v_new3, v_new4, v_new5, v_new6];
  FOR i IN 1 .. 6 LOOP
    n := (length(v_def) - length(replace(v_def, v_olds[i], ''))) / length(v_olds[i]);
    IF n <> 1 THEN
      RAISE EXCEPTION '0572: arm patch % matched % times, not once', i, n;
    END IF;
    v_def := replace(v_def, v_olds[i], v_news[i]);
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ── (e) the same cell on two nights is only the same cell at the same fleet size ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0572_pre', 'view', 'public', 'ottoq_throughput_cross_sweep_twins', d, md5(d)
  FROM (SELECT 'CREATE OR REPLACE VIEW public.ottoq_throughput_cross_sweep_twins WITH (security_invoker = true) AS '
               || pg_get_viewdef('public.ottoq_throughput_cross_sweep_twins'::regclass, true) AS d) z;

CREATE OR REPLACE VIEW public.ottoq_throughput_cross_sweep_twins
WITH (security_invoker = true) AS
WITH cur AS (
  SELECT a.arm_id, a.seed, a.ran_at, a.boot_md5, a.atoms, a.sweep_id, s.sweep_code, s.depot_id, s.scenario, s.sim_start,
         s.sim_min_per_tick, s.ticks, s.fleet_code, c.cell_code, c.seat, c.buildout_code, c.fixed_params
    FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE NOT a.replicate AND a.complete AND a.ran_at >= public.ottoq_dial_pair_floor()
)
SELECT e.sweep_code AS earlier_sweep, e.cell_code AS earlier_cell, l.sweep_code AS later_sweep, l.cell_code AS later_cell,
       l.seed, e.arm_id AS earlier_arm, l.arm_id AS later_arm, e.ran_at AS earlier_ran_at, l.ran_at AS later_ran_at,
       l.boot_md5 = e.boot_md5 AND l.atoms = e.atoms                                         AS identical,
       (SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::jsonb)
          FROM jsonb_object_keys(COALESCE(e.atoms, '{}'::jsonb) || COALESCE(l.atoms, '{}'::jsonb)) AS k
         WHERE (e.atoms -> k) IS DISTINCT FROM (l.atoms -> k))                               AS moved
  FROM cur e
  JOIN cur l ON l.sweep_id <> e.sweep_id AND l.ran_at > e.ran_at AND l.seed = e.seed AND l.depot_id = e.depot_id
            AND l.scenario = e.scenario AND l.sim_start = e.sim_start AND l.sim_min_per_tick = e.sim_min_per_tick
            AND l.ticks = e.ticks AND l.seat = e.seat AND l.buildout_code = e.buildout_code
            AND l.fixed_params = e.fixed_params AND l.fleet_code IS NOT DISTINCT FROM e.fleet_code;
COMMENT ON VIEW public.ottoq_throughput_cross_sweep_twins IS
'0571, 0572. Two primary arms of different sweeps that ran one cell definition on one seed at one fleet size: identical when the boot image and every atom (ottoq_ab_arm_atoms) agree. Different sweeps, nights and transactions: cross-transaction determinism (G140), and a real-engine check that an engine change classified as default-neutral moved nothing.';

-- ── (f) night 3 ──
INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority, run_after,
        fleet_code, notes)
SELECT x.code, x.title, f.depot_id, f.scenario, f.sim_start, f.ticks, f.sim_min_per_tick, f.seeds[1:3], 0, 100,
       '2026-10-02 04:00:00+00', x.fleet,
       'Night 3 (0572). The twin depot at ' || x.size || ' cars, the extra ones lent by the Benchmark depot for each arm and '
       'returned after it. 20 robotic fast chargers with OTTO-Q and with FIFO (the margin pair), and 10 with OTTO-Q (what the '
       'second ten chargers buy at this fleet size). Night 1''s first three seeds.'
  FROM public.ottoq_throughput_sweeps f,
       (VALUES ('fleet150_2026_10_01', 'The twin depot at 150 cars: 20 robotic fast chargers against 10, OTTO-Q against FIFO', 'fleet150', 150),
               ('fleet200_2026_10_01', 'The twin depot at 200 cars: 20 robotic fast chargers against 10, OTTO-Q against FIFO', 'fleet200', 200))
         AS x(code, title, fleet, size)
 WHERE f.sweep_code = 'frontier_2026_09_29';
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, c.cell_code, c.ord, c.seat, c.buildout_code, '{"deploy_peak_fraction": 0.90}'::jsonb
  FROM public.ottoq_throughput_sweeps s,
       (VALUES ('dcfc20.otto_q', 1, 'otto_q', 'dcfc20'), ('dcfc20.fifo', 2, 'fifo', 'dcfc20'),
               ('dcfc10.otto_q', 3, 'otto_q', 'dcfc10')) AS c(cell_code, ord, seat, buildout_code)
 WHERE s.sweep_code IN ('fleet150_2026_10_01', 'fleet200_2026_10_01');

-- ── V1 ──
DO $verify$
DECLARE
  v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc WHERE oid = 'public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure;
  -- borrowed before the reset, returned after the site restore, both only for a sweep with a fleet
  IF position('ottoq_fleet_buildout_apply' IN v_src) = 0
     OR position('ottoq_fleet_buildout_apply' IN v_src) > position('ottoq_tick_invariance_reset_fleet' IN v_src)
     OR position('ottoq_fleet_buildout_restore' IN v_src) < position('ottoq_site_buildout_restore' IN v_src)
     OR (length(v_src) - length(replace(v_src, 'IF s.fleet_code IS NOT NULL THEN', ''))) / length('IF s.fleet_code IS NOT NULL THEN') <> 2 THEN
    RAISE EXCEPTION '0572 V1: the arm does not borrow before the reset and return after the site restore';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_fleet_buildout_never_commits' AND tgdeferrable AND tginitdeferred) THEN
    RAISE EXCEPTION '0572 V1: the commit guard is not a deferred constraint trigger';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweeps WHERE sweep_code IN ('fleet150_2026_10_01', 'fleet200_2026_10_01')
                                                            AND cardinality(seeds) = 3 AND replicates = 0) <> 2
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
          WHERE s.sweep_code IN ('fleet150_2026_10_01', 'fleet200_2026_10_01')) <> 6 THEN
    RAISE EXCEPTION '0572 V1: night 3 is not two sweeps of three cells on three seeds';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_fleet_buildouts b
              WHERE b.fleet_size <> 116 + (SELECT sum(value::int) FROM jsonb_each_text(b.borrow_by_class))) THEN
    RAISE EXCEPTION '0572 V1: a fleet build-out''s declared size is not 116 plus what it borrows';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_fleet_buildout_apply(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_fleet_buildout_restore(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0572 V1: grants are not as declared';
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0572_a_fleet_build_out_borrows_cars_for_one_test_day', false, false,
  'Fleet build-outs applied only inside a transaction (borrowed cars re-homed and put back from full pre-images), a '
  'sweep-level fleet_code, the arm borrowing before the reset and returning after the site restore only for a sweep '
  'that names a fleet, and night 3''s sweeps. The canon, the demo and every existing sweep run with no fleet_code, where '
  'the arm does what it did.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
