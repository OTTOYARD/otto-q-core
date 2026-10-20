-- migration-version: 20261018112027
-- migration-name:    every_bay_seat_ends_in_its_leg_and_its_service_record
--
-- 0750  **Every bay seat ends in its itinerary leg and its service record.** (G464)
--       The kernel's record of a completed operation is the SDR, issued when an itinerary leg turns done. A bay leg turns
--       done at the bay exit only if the seat opened it, and only the service flow's own seats and the calendar's
--       activations open one. The decide seats most bay cars through a command, and the twin's confirm walk never names
--       a leg, so those seats leave with nothing to close, no SDR is issued, and the planned leg stays planned until the
--       car deploys. Research wing, rule 10: under a dial, measured in the twin, then a certified change.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-17 between 10:51 and 11:13 PM CT; db/checks/0454) ═════════════════════════════
--
--   On the twin depot's 11 completed runs since 2026-10-16 (6 normal days, 5 busy days), SDRs cover 10.7% of completed
--   washes (32 of 299 atoms done), 17.7% of details (73 of 413) and 31.7% of service-bay jobs (90 of 284), against
--   94-100% for the work done in place and above 100% for charges, (1). A planned bay leg whose work was done ended
--   skipped 255 times against 32 done for the wash, 298 against 71 for the detail and 183 against 81 for the service bay,
--   (2). The only callers of ottoq_itin_leg_open are the service flow's STEP 2 seats and every charge start;
--   twin.ottoq_sim_confirm_commands names no leg, (3). (4b)'s walk-ins bound a planned leg to their booking 114 times in
--   407 washes, 115 in 414 details and 75 in 143 services, and every one of those legs still ended skipped, (4).
--   ottoq_close_atom_leg (0504, G232) leaves bay legs to "the service flow that opens and closes them", which it does for
--   its own seats only, and ottoq_check_sdr_coverage starts from done legs, so the gap was outside what it counts, (5).
--   The phantom legs cost the plan: of the 20,250 amend_plan decisions the flow contract made on the 11 runs, 7,239
--   (35.7%) were made while the car carried one, (6), and the owner app's ready-by reads the same legs (G454).
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dial bay_exit_closes_its_leg (0..1, default 0; not agent-writable).
--   (b) public.ottoq_close_bay_seat_legs(run, depot, car, bay state, seat, ended, stall, credited): below 1 it returns 0
--       and touches nothing. At 1, in the car's active itinerary of the run (ottoq_itin_leg_open's own pick; with none, it
--       records nothing and creates no itinerary):
--         - each bay service the seat credited (exterior_wash, interior_deep_clean, mechanical_pm, sensor_calibration,
--           fault_repair, cosmetic_repair) closes its planned leg, the one the planner tagged with that service;
--         - a seat that closed no bay leg at this exit, here or in the service flow's own close above it, records one
--           leg of its bay's type, tagged with its first credited bay service;
--         - each such leg is closed done with the seat's start (the minute the car entered the bay, never after the end)
--           and the work's end (the timer STEP 1 completed on), its stall, and its deviation from its planned end; before
--           it closes, the booking that covered the seat in that stall, if it names no leg, learns this one, as
--           ottoq_itin_leg_open's late bind does when a leg opens. The leg trigger (trg_0043_leg_done_sdr) then issues
--           the SDR, with the booking. It returns the legs it closed.
--   (c) twin.ottoq_sim_advance_service_flow, STEP 1, two anchored insertions: its cursor also reads the car's seat
--       minute and bay stall, and after the credit set (STEP D) it calls (b) in its own subtransaction, so a failure
--       is a WARNING and the tick goes on. At 0 the cursor's two extra columns are read by nothing, and (b) returns
--       before reading anything but the dial.
--   (d) public.ottoq_bay_seat_record_coverage(run): each closed bay seat of a run, from its entry and exit events,
--       against a done bay leg and a bay SDR ending inside it, by bay. The census ottoq_check_sdr_coverage could not be.
--   (e) Sweep bayexit_normal_2026_10_18: arm 84's cell (dcfc40.otto_q) with the dial, normal_day from 6 AM CT for 12
--       hours at 5 sim-minutes a tick, value_2026_09_30's first seed, priority 16, arm budget 3,000 s. It pairs with arm 84
--       (b54f6de5); db/checks/0454's queries, re-run on the arm, are its readout.
--   Not changed: what a car needs, which bay serves it, how long anything takes, the bookings the engine makes, the
--   departure test (rule 9: it reads neither legs nor SDRs). What it may move, and why the arm is needed: the flow
--   contract re-times a plan for its late planned legs, (4b) times a walk-in by a planned leg of its type, and the
--   planner does not plan a visit whose itinerary still has a planned leg; a phantom leg closed done is gone from all
--   three. Not covered: ottoq_ingest_service_complete called with a list of services marks atoms done with no leg and
--   no SDR, and a bay leg is still not active while the car is in the bay.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the service flow is the body 0746 left (prosrc md5 d7f2ee27); the leg close and the leg
--   trigger are the bodies read (6c33d450, 8aa4c329) and the trigger is enabled on a done status; the wash, detail and
--   service leg types issue SDRs; nothing of this file exists; arm 84's cell is as read. P2 not already applied.
--   Pre-image to ottoq_schema_snapshots as '0750_pre'. Each anchor matches once. V1 the body less its insertions is its
--   pre-image. V2 at the dial's default, and for a missing run, car or state, (b) returns 0. V3 on live, in a block
--   rolled back by its own raise, with the dial on for one run: a planned wash leg is closed done with the seat's times
--   and its booking, and the SDR issued names both; a seat with no leg records one, and its SDR names its booking; the
--   same exit called twice records nothing more; with the dial off a planned leg stays planned; nothing is left behind.
--   V4 the dial is catalogued as declared and the sweep's cell is arm 84's plus the dial.
--   tests/test_bay_exit_closes_its_leg_sql.py executes (b) and (d) on the scratch PostgreSQL against the live leg
--   helpers, leg trigger and SDR emitter (md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the service flow does what it did (V1: its
--   body less the two insertions is its pre-image; V2: (b) returns 0 and writes nothing), and no certification arm,
--   canon cell or dial experiment sets the dial.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0750_pre'; DROP FUNCTION
--   public.ottoq_close_bay_seat_legs(uuid, uuid, uuid, text, timestamptz, timestamptz, uuid, text[]),
--   public.ottoq_bay_seat_record_coverage(uuid); if no arm has run, DELETE the sweep bayexit_normal_2026_10_18 and its
--   cell and the dial's catalog row;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0750_every_bay_seat_ends_in_its_leg_and_its_service_record'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0750 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, the trigger, the catalog, arm 84's cell, nothing of this file ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'))
     IS DISTINCT FROM 'd7f2ee279455242f966492869305adb1' THEN
    RAISE EXCEPTION '0750 P1: twin.ottoq_sim_advance_service_flow is not the body 0746 left (md5 d7f2ee27)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_itin_leg_close(uuid,uuid,text[],timestamp with time zone,text)'))
     IS DISTINCT FROM '6c33d450e023f83882cbb95f0f4b150f' THEN
    RAISE EXCEPTION '0750 P1: public.ottoq_itin_leg_close is not the body read (md5 6c33d450)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_trg_leg_done_sdr()'))
     IS DISTINCT FROM '8aa4c329836bdb7e0588defe75404498' THEN
    RAISE EXCEPTION '0750 P1: public.ottoq_trg_leg_done_sdr is not the body read (md5 8aa4c329)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.ottoq_itinerary_legs'::regclass AND t.tgname = 'trg_0043_leg_done_sdr'
                    AND t.tgfoid = 'public.ottoq_trg_leg_done_sdr()'::regprocedure AND t.tgenabled IN ('O', 'A')
                    AND pg_get_triggerdef(t.oid) LIKE '%AFTER UPDATE OF status ON public.ottoq_itinerary_legs FOR EACH ROW WHEN (((new.status = ''done''::text) AND (old.status IS DISTINCT FROM ''done''::text)))%') THEN
    RAISE EXCEPTION '0750 P1: the leg trigger is not enabled on a leg turning done';
  END IF;
  IF (SELECT count(DISTINCT leg_type) FROM public.ottoq_operation_catalog
       WHERE leg_type IN ('wash', 'detail', 'service') AND emits_sdr) <> 3 THEN
    RAISE EXCEPTION '0750 P1: the wash, detail and service leg types do not all issue an SDR';
  END IF;
  IF to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL THEN
    RAISE EXCEPTION '0750 P1: public.ottoq_policy_get is missing';
  END IF;
  IF to_regprocedure('public.ottoq_close_bay_seat_legs(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,uuid,text[])') IS NOT NULL
     OR to_regprocedure('public.ottoq_bay_seat_record_coverage(uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_exit_closes_its_leg')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'bayexit_normal_2026_10_18') THEN
    RAISE EXCEPTION '0750 P1: a function, the dial or the sweep of this file already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_power_normal_2026_10_17' AND c.cell_code = 'dcfc40.otto_q'
                    AND c.buildout_code = 'dcfc40' AND s.scenario = 'normal_day'
                    AND s.sim_start = '2026-09-01 11:00:00+00' AND s.ticks = 144 AND s.sim_min_per_tick = 5
                    AND (c.fixed_params ->> 'deploy_peak_fraction')::numeric = 0.9
                    AND c.fixed_params - 'deploy_peak_fraction' = '{}'::jsonb) THEN
    RAISE EXCEPTION '0750 P1: arm 84''s cell (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) is not as read';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0750_every_bay_seat_ends_in_its_leg_and_its_service_record') THEN
    RAISE EXCEPTION '0750 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0750_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_exit_closes_its_leg',
        '0750 (G464): 1 = at a bay exit, a seat that closed no active leg closes the planned bay leg of each service it '
        'credited, with the seat''s start and the work''s end, binding the booking that covered it, or records one in the '
        'car''s plan, so every bay seat ends in a done leg and the leg trigger issues its service record. 0 = only a leg '
        'the seat opened is closed, as before 0750: a car seated through a command leaves no leg and no service record, '
        'and its planned leg is skipped when it deploys. Research days only until certified.',
        0, 0, 1, 'twin.ottoq_sim_advance_service_flow (STEP 1), public.ottoq_close_bay_seat_legs', false);

-- ── (b) the bay exit closes the seat's leg ──
CREATE FUNCTION public.ottoq_close_bay_seat_legs(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_bay_state text,
                                                 p_seat_at timestamptz, p_ended timestamptz, p_stall_id uuid,
                                                 p_credited text[])
RETURNS integer
LANGUAGE plpgsql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0750 (G464): at a bay exit the seat ends in a done itinerary leg, so the leg trigger issues its service record. Before
-- 0750 only a leg the seat had opened was closed there, and only the service flow's own seats and the calendar's
-- activations open one; a car seated through a command left with nothing to close, and its planned leg stayed planned
-- until the car deployed and was then skipped. Called by STEP 1 of twin.ottoq_sim_advance_service_flow after its own
-- close, with the services the seat credited.
DECLARE
  v_type text; v_start timestamptz; v_itin uuid; v_svc text; v_leg uuid; v_legs uuid[] := '{}'; v_seq int;
  v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_vehicle_id IS NULL OR p_ended IS NULL
     OR p_bay_state IS NULL OR p_bay_state NOT IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay') THEN
    RETURN 0;
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_exit_closes_its_leg', 0), 0) < 1 THEN
    RETURN 0;
  END IF;
  v_type := CASE p_bay_state WHEN 'in_wash_bay' THEN 'wash' WHEN 'in_detail_bay' THEN 'detail' ELSE 'service' END;
  v_start := LEAST(COALESCE(p_seat_at, p_ended), p_ended);
  -- the car's plan in this run, picked as ottoq_itin_leg_open picks it; with none there is no plan to record the seat in
  SELECT i.itinerary_id INTO v_itin
    FROM public.ottoq_vehicle_itineraries i
   WHERE i.sim_run_id = p_sim_run_id AND i.vehicle_id = p_vehicle_id AND i.status = 'active'
   ORDER BY i.sim_created_at DESC, i.created_at DESC, i.itinerary_id DESC /* 0129 */ LIMIT 1;
  IF v_itin IS NULL THEN
    RETURN 0;
  END IF;

  -- the planned bay leg of each bay service the seat credited: its work was done in this seat
  FOREACH v_svc IN ARRAY COALESCE(p_credited, ARRAY[]::text[]) LOOP
    CONTINUE WHEN v_svc IS NULL OR v_svc NOT IN ('exterior_wash', 'interior_deep_clean', 'mechanical_pm',
                                                 'sensor_calibration', 'fault_repair', 'cosmetic_repair');
    v_leg := NULL;
    SELECT l.leg_id INTO v_leg
      FROM public.ottoq_itinerary_legs l
     WHERE l.itinerary_id = v_itin AND l.status = 'planned'
       AND l.leg_type = CASE v_svc WHEN 'exterior_wash' THEN 'wash' WHEN 'interior_deep_clean' THEN 'detail'
                                   ELSE 'service' END
       AND l.duration_basis ->> 'atom' = v_svc
       AND NOT l.leg_id = ANY (v_legs)
     ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;
    IF v_leg IS NOT NULL THEN
      v_legs := v_legs || v_leg;
    END IF;
  END LOOP;

  -- a seat that closed no bay leg at this exit, here or in the service flow's own close, records one of its bay's type
  IF cardinality(v_legs) = 0
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_itinerary_legs l
                      WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = p_vehicle_id AND l.status = 'done'
                        AND l.leg_type IN ('wash', 'detail', 'service') AND l.actual_end_sim = p_ended) THEN
    SELECT COALESCE(max(l.seq), 0) + 1 INTO v_seq FROM public.ottoq_itinerary_legs l WHERE l.itinerary_id = v_itin;
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, to_stall_id,
                                             planned_start_sim, planned_end_sim, planned_duration_s, duration_basis,
                                             actual_start_sim, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle_id, v_seq, v_type, p_stall_id, v_start, p_ended,
            GREATEST(0, EXTRACT(EPOCH FROM (p_ended - v_start)))::int,
            jsonb_build_object('kind', 'bay_seat', 'recorded_at_exit', '0750',
                               'atom', (SELECT c.svc FROM unnest(COALESCE(p_credited, ARRAY[]::text[])) WITH ORDINALITY c(svc, o)
                                         WHERE CASE c.svc WHEN 'exterior_wash' THEN 'wash'
                                                          WHEN 'interior_deep_clean' THEN 'detail'
                                                          WHEN 'mechanical_pm' THEN 'service'
                                                          WHEN 'sensor_calibration' THEN 'service'
                                                          WHEN 'fault_repair' THEN 'service'
                                                          WHEN 'cosmetic_repair' THEN 'service' END = v_type
                                         ORDER BY c.o LIMIT 1)),
            v_start, 'active')
    RETURNING leg_id INTO v_leg;
    v_legs := ARRAY[v_leg];
  END IF;

  FOREACH v_leg IN ARRAY v_legs LOOP
    -- the booking that covered the seat in this stall learns its leg, as ottoq_itin_leg_open's late bind does when a
    -- leg opens, so the service record names it. Sub-blocked: a problem here never costs the leg its record.
    BEGIN
      IF p_stall_id IS NOT NULL THEN
        UPDATE public.ottoq_stall_bookings b
           SET leg_id     = v_leg,
               leg_source = CASE WHEN COALESCE(b.leg_source, 'none') = 'none' THEN 'bay_exit_0750' ELSE b.leg_source END,
               why        = COALESCE(b.why, '') || format(' | leg %s closed at the bay exit at %s (0750)',
                                                          left(v_leg::text, 8), to_char(p_ended, 'HH24:MI'))
         WHERE b.booking_id = (
                 SELECT bb.booking_id FROM public.ottoq_stall_bookings bb
                  WHERE bb.sim_run_id = p_sim_run_id AND bb.vehicle_id = p_vehicle_id AND bb.stall_id = p_stall_id
                    AND bb.leg_id IS NULL AND bb.state IN ('held', 'active', 'done')
                    AND bb.during && tstzrange(v_start, p_ended, '[]')
                  ORDER BY abs(EXTRACT(EPOCH FROM (lower(bb.during) - v_start))), lower(bb.during), bb.booking_id DESC /* 0129 */
                  LIMIT 1)
           AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bz WHERE bz.leg_id = v_leg);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    UPDATE public.ottoq_itinerary_legs
       SET status = 'done',
           to_stall_id = COALESCE(to_stall_id, p_stall_id),
           actual_start_sim = COALESCE(actual_start_sim, v_start),
           actual_end_sim = p_ended,
           deviation_s = CASE WHEN planned_end_sim IS NULL THEN NULL
                              ELSE EXTRACT(EPOCH FROM (p_ended - planned_end_sim))::int END,
           duration_basis = duration_basis || jsonb_build_object('closed_at_bay_exit', '0750')
     WHERE leg_id = v_leg;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_close_bay_seat_legs(uuid, uuid, uuid, text, timestamptz, timestamptz, uuid, text[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_close_bay_seat_legs(uuid, uuid, uuid, text, timestamptz, timestamptz, uuid, text[])
  TO service_role;

-- ── (d) the census by seat ──
CREATE FUNCTION public.ottoq_bay_seat_record_coverage(p_sim_run_id uuid)
RETURNS TABLE (bay text, seats integer, with_done_leg integer, with_sdr integer)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  -- 0750 (G464): each closed bay seat of a run, from the car's entry and exit events, against a done bay leg and a bay
  -- SDR ending inside it. ottoq_check_sdr_coverage starts from done legs, so it cannot see a seat that never had one.
  WITH ev AS (
    SELECT e.entity_id AS vehicle_id,
           e.payload -> 'diff' -> 'current_state' ->> 'from' AS s_from,
           e.payload -> 'diff' -> 'current_state' ->> 'to' AS s_to,
           COALESCE((e.payload -> 'diff' -> 'last_state_change' ->> 'to')::timestamptz, e.sim_clock_at) AS at
      FROM public.ottoq_events e
     WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'vehicle.state_changed'
       AND e.payload -> 'diff' ? 'current_state'),
  seats AS (
    SELECT a.vehicle_id, a.s_to AS bay, a.at AS seat_at,
           (SELECT min(b.at) FROM ev b WHERE b.vehicle_id = a.vehicle_id AND b.s_from = a.s_to AND b.at >= a.at) AS exit_at
      FROM ev a WHERE a.s_to IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay'))
  SELECT s.bay, count(*)::int,
         count(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM public.ottoq_itinerary_legs l
            WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = s.vehicle_id AND l.status = 'done'
              AND l.leg_type IN ('wash', 'detail', 'service')
              AND l.actual_end_sim >= s.seat_at AND l.actual_end_sim <= s.exit_at))::int,
         count(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM public.ottoq_service_detail_records r
            WHERE r.sim_run_id = p_sim_run_id AND r.vehicle_id = s.vehicle_id
              AND r.operation_code IN ('wash', 'detail', 'generic_service')
              AND r.ended_at >= s.seat_at AND r.ended_at <= s.exit_at))::int
    FROM seats s
   WHERE s.exit_at IS NOT NULL
   GROUP BY s.bay
   ORDER BY s.bay;
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_bay_seat_record_coverage(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_bay_seat_record_coverage(uuid) TO service_role;

-- ── (c) STEP 1 of the service flow ──
CREATE TEMP TABLE _0750_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0750_patch VALUES
  -- 1: the cursor also reads the seat's minute and its bay stall
  (1, $o1$    SELECT id, current_state, config FROM vehicles
     WHERE home_depot_id = p_depot_id
       AND current_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
$o1$,
   $n1$    SELECT id, current_state, config,
           last_state_change AS bay_seat_at, current_stall_id AS bay_stall_id   -- 0750 (G464): the seat, for its leg
      FROM vehicles
     WHERE home_depot_id = p_depot_id
       AND current_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
$n1$),
  -- 2: after the credit set, the seat's legs
  (2, $o2$    v_credit := ARRAY(SELECT t.svc FROM unnest(v_bay_caps) AS t(svc)
                       WHERE t.svc = ANY(v_outstanding || v_flag_svcs));
$o2$,
   $n2$    v_credit := ARRAY(SELECT t.svc FROM unnest(v_bay_caps) AS t(svc)
                       WHERE t.svc = ANY(v_outstanding || v_flag_svcs));
    -- 0750 (G464): with bay_exit_closes_its_leg on, a seat that closed no active leg above closes the planned bay leg of
    -- each service it credited, or records one, so it ends in a done leg and its service record. Off, this returns at
    -- once. A failure is a warning, never the tick's.
    BEGIN
      PERFORM public.ottoq_close_bay_seat_legs(p_sim_run_id, p_depot_id, v_rec.id, v_rec.current_state::text,
                                               v_rec.bay_seat_at, v_end_ts, v_rec.bay_stall_id, v_credit);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0750 bay exit leg (vehicle %): % %', v_rec.id, SQLSTATE, SQLERRM;
    END;
$n2$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0750_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0750: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0750: the service flow is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure;
  FOR p IN SELECT * FROM _0750_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'd7f2ee279455242f966492869305adb1' THEN
    RAISE EXCEPTION '0750 V1: the service flow less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: at the dial's default, and without a run, a car or a bay state, nothing is recorded ──
DO $v2$
DECLARE v_run uuid; v_car uuid;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY r.started_at DESC LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY v.id LIMIT 1;
  IF public.ottoq_close_bay_seat_legs(v_run, '11111111-1111-1111-1111-111111111111', v_car, 'in_wash_bay',
                                      now() - interval '5 minutes', now(), NULL, ARRAY['exterior_wash']) <> 0
     OR public.ottoq_close_bay_seat_legs(NULL, NULL, v_car, 'in_wash_bay', now(), now(), NULL, NULL) <> 0
     OR public.ottoq_close_bay_seat_legs(v_run, NULL, NULL, 'in_wash_bay', now(), now(), NULL, NULL) <> 0
     OR public.ottoq_close_bay_seat_legs(v_run, NULL, v_car, 'staged_awaiting_service', now(), now(), NULL, NULL) <> 0 THEN
    RAISE EXCEPTION '0750 V2: the bay exit recorded a leg at the dial''s default or without a run, a car or a bay state';
  END IF;
END $v2$;

-- ── V3: the whole path on live, rolled back by its own raise ──
DO $v3$
DECLARE
  v_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_t0 constant timestamptz := '2031-01-01 12:00:00+00';
  v_t1 constant timestamptz := '2031-01-01 13:00:00+00';
  v_run uuid; v_car uuid; v_stall uuid; v_itin uuid; v_leg uuid; v_bk1 uuid; v_bk2 uuid; v_n int; r record;
BEGIN
  SELECT x.sim_run_id INTO v_run FROM public.ottoq_sim_runs x
   WHERE x.depot_id = v_depot AND x.status = 'completed' ORDER BY x.started_at DESC LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v WHERE v.home_depot_id = v_depot ORDER BY v.id LIMIT 1;
  SELECT s.id INTO v_stall FROM public.stalls s
   WHERE s.depot_id = v_depot AND s.stall_type = 'wash_bay'::stall_type ORDER BY s.stall_code LIMIT 1;
  IF v_run IS NULL OR v_car IS NULL OR v_stall IS NULL THEN
    RAISE EXCEPTION '0750 V3: no completed run, car or wash bay at the twin depot to probe with';
  END IF;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'bay_exit_closes_its_leg', 1, '0750 V3 probe, rolled back', now());
    INSERT INTO public.ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at)
    VALUES (v_run, v_depot, v_car, '0750_v3_probe', v_t0) RETURNING itinerary_id INTO v_itin;
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, planned_start_sim,
                                             planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, v_run, v_car, 1, 'wash', v_t0 + interval '30 minutes', v_t0 + interval '40 minutes', 600,
            '{"kind": "flow_contract", "atom": "exterior_wash"}'::jsonb, 'planned')
    RETURNING leg_id INTO v_leg;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_at,
                                             booked_by, source)
    VALUES (v_run, v_stall, v_car, 'wash', tstzrange(v_t0, v_t0 + interval '9 minutes', '[)'), 'active', now(),
            'otto_q_enacted', 'needs_card')
    RETURNING booking_id INTO v_bk1;

    -- a walk-in wash with a planned leg: the leg is closed done with the seat's times and learns the booking
    v_n := public.ottoq_close_bay_seat_legs(v_run, v_depot, v_car, 'in_wash_bay', v_t0, v_t0 + interval '5 minutes',
                                            v_stall, ARRAY['exterior_wash', 'sensor_clean']);
    SELECT l.status, l.actual_start_sim, l.actual_end_sim, l.to_stall_id INTO r
      FROM public.ottoq_itinerary_legs l WHERE l.leg_id = v_leg;
    IF v_n <> 1 OR r.status <> 'done' OR r.actual_start_sim <> v_t0 OR r.actual_end_sim <> v_t0 + interval '5 minutes'
       OR r.to_stall_id <> v_stall THEN
      RAISE EXCEPTION '0750 V3: the planned wash leg was not closed with the seat (% legs, %)', v_n, row_to_json(r);
    END IF;
    IF (SELECT b.leg_id FROM public.ottoq_stall_bookings b WHERE b.booking_id = v_bk1) IS DISTINCT FROM v_leg THEN
      RAISE EXCEPTION '0750 V3: the walk-in booking did not learn its leg';
    END IF;
    SELECT d.operation_code, d.started_at, d.ended_at, d.booking_id, d.stall_id, d.duration_min, d.source_kind INTO r
      FROM public.ottoq_service_detail_records d WHERE d.leg_id = v_leg;
    IF r.operation_code IS DISTINCT FROM 'wash' OR r.started_at <> v_t0 OR r.ended_at <> v_t0 + interval '5 minutes'
       OR r.booking_id IS DISTINCT FROM v_bk1 OR r.stall_id IS DISTINCT FROM v_stall OR r.duration_min <> 5
       OR r.source_kind <> 'itinerary_leg' THEN
      RAISE EXCEPTION '0750 V3: the wash''s service record is not the seat''s (%)', row_to_json(r);
    END IF;

    -- a second wash, no planned leg left: the seat records its own leg, and its record names its booking
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_at,
                                             booked_by, source)
    VALUES (v_run, v_stall, v_car, 'wash', tstzrange(v_t1, v_t1 + interval '9 minutes', '[)'), 'active', now(),
            'otto_q_enacted', 'needs_card')
    RETURNING booking_id INTO v_bk2;
    v_n := public.ottoq_close_bay_seat_legs(v_run, v_depot, v_car, 'in_wash_bay', v_t1, v_t1 + interval '6 minutes',
                                            v_stall, ARRAY['exterior_wash']);
    SELECT d.leg_id, d.booking_id, d.started_at, d.ended_at, l.seq, l.duration_basis ->> 'atom' AS atom INTO r
      FROM public.ottoq_service_detail_records d JOIN public.ottoq_itinerary_legs l USING (leg_id)
     WHERE l.itinerary_id = v_itin AND d.ended_at = v_t1 + interval '6 minutes';
    IF v_n <> 1 OR r.leg_id IS NULL OR r.booking_id IS DISTINCT FROM v_bk2 OR r.started_at <> v_t1 OR r.seq <> 2
       OR r.atom IS DISTINCT FROM 'exterior_wash' THEN
      RAISE EXCEPTION '0750 V3: a seat with no leg did not record its own (% legs, %)', v_n, row_to_json(r);
    END IF;

    -- the same exit again: nothing more
    IF public.ottoq_close_bay_seat_legs(v_run, v_depot, v_car, 'in_wash_bay', v_t1, v_t1 + interval '6 minutes',
                                        v_stall, ARRAY['exterior_wash']) <> 0
       OR (SELECT count(*) FROM public.ottoq_itinerary_legs l WHERE l.itinerary_id = v_itin) <> 2 THEN
      RAISE EXCEPTION '0750 V3: the same exit was recorded twice';
    END IF;

    -- the dial off: a planned leg stays planned
    UPDATE public.ottoq_policy_params SET param_value = 0
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'bay_exit_closes_its_leg';
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, planned_start_sim,
                                             planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, v_run, v_car, 3, 'wash', v_t1 + interval '30 minutes', v_t1 + interval '40 minutes', 600,
            '{"kind": "flow_contract", "atom": "exterior_wash"}'::jsonb, 'planned')
    RETURNING leg_id INTO v_leg;
    IF public.ottoq_close_bay_seat_legs(v_run, v_depot, v_car, 'in_wash_bay', v_t1 + interval '20 minutes',
                                        v_t1 + interval '25 minutes', v_stall, ARRAY['exterior_wash']) <> 0
       OR (SELECT l.status FROM public.ottoq_itinerary_legs l WHERE l.leg_id = v_leg) <> 'planned' THEN
      RAISE EXCEPTION '0750 V3: with the dial off a planned leg was closed';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OT750', MESSAGE = 'probe passed';
  EXCEPTION WHEN SQLSTATE 'OT750' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_vehicle_itineraries WHERE created_by = '0750_v3_probe')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params
                 WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'bay_exit_closes_its_leg')
     OR EXISTS (SELECT 1 FROM public.ottoq_stall_bookings WHERE booking_id IN (v_bk1, v_bk2)) THEN
    RAISE EXCEPTION '0750 V3: the probe left something behind';
  END IF;
END $v3$;

-- ── (e) the pair: arm 84's cell with the dial ──
INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, notes)
VALUES ('bayexit_normal_2026_10_18',
        'Every bay seat ends in its leg and its service record: arm 84''s 40 robotic fast chargers with bay_exit_closes_its_leg',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 16, 3000, 'active',
        '0750 (G464). Pairs with arm 84 (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q, run b54f6de5) on '
        'value_2026_09_30''s first seed; it differs only by the dial. Readout: db/checks/0454''s queries on both runs and '
        'public.ottoq_bay_seat_record_coverage.');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40.otto_q.bay_exit_leg', 1, 'otto_q', 'dcfc40',
       '{"deploy_peak_fraction": 0.90, "bay_exit_closes_its_leg": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'bayexit_normal_2026_10_18';

-- ── V4: the dial and the cell ──
DO $v4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'bay_exit_closes_its_leg' AND default_value = 0 AND min_value = 0 AND max_value = 1
                    AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0750 V4: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'bayexit_normal_2026_10_18') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                     JOIN public.ottoq_throughput_sweep_cells c84 ON c84.cell_code = 'dcfc40.otto_q'
                     JOIN public.ottoq_throughput_sweeps s84 ON s84.sweep_id = c84.sweep_id
                                                            AND s84.sweep_code = 'dcfc40_power_normal_2026_10_17'
                     WHERE s.sweep_code = 'bayexit_normal_2026_10_18'
                       AND c.buildout_code = c84.buildout_code AND c.seat = c84.seat
                       AND (s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds[1])
                         = (s84.scenario, s84.sim_start, s84.ticks, s84.sim_min_per_tick, s84.seeds[1])
                       AND c.fixed_params - 'bay_exit_closes_its_leg' = c84.fixed_params
                       AND c.fixed_params ->> 'bay_exit_closes_its_leg' = '1') THEN
    RAISE EXCEPTION '0750 V4: the sweep''s cell is not arm 84''s plus the dial';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0750_every_bay_seat_ends_in_its_leg_and_its_service_record', false, false,
        'G464. Dial bay_exit_closes_its_leg (default 0); public.ottoq_close_bay_seat_legs, called from two anchored '
        'insertions in STEP 1 of twin.ottoq_sim_advance_service_flow, closes at the bay exit the planned bay leg of each '
        'service the seat credited, or records one, so the leg trigger issues its SDR; at 0 it returns before writing '
        '(V1: body less insertions is its pre-image; V2). public.ottoq_bay_seat_record_coverage, a census by seat. Sweep '
        'bayexit_normal_2026_10_18 (arm 84''s cell plus the dial, one seed, priority 16). No certification arm, canon '
        'cell or dial experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:20:27 UTC (6:20 AM CT), ledger version 20261018112027 ══════════════════════════════════════
--
--   Dry-run first on live, at 11:18:46 UTC (6:18 AM CT) by the server log: the executable part in one
--   execute_sql ending in a block that raises, so it rolled back. Every premise and check passed, V3's end-to-end probe
--   of the leg trigger and the live SDR emitter included, and the service flow after it read
--   f871ecad1ccb2c9a85d92a2c466de2d6. Then through apply_migration with nothing in flight (the file's own P0 at the
--   apply; no run live, read after). The text sent, BEGIN through COMMIT and one newline, is 29,661 characters, md5
--   a12602c3168015953c550945c551f2ff, equal to the ledger's statements[1] read back; its executable part is 29,645
--   characters, md5 35c0beb783d31e33c2a74a0fda606fc7, equal to this file's. twin.ottoq_sim_advance_service_flow is now
--   md5 f871ecad1ccb2c9a85d92a2c466de2d6 (prosrc), the dry run's. Sweep bayexit_normal_2026_10_18 is queued (one cell,
--   priority 16).
--
--   End to end on live, rolled back by its own raise at 11:48:17 UTC (6:48 AM CT): a probe run at the twin depot; a car
--   in_wash_bay on NASH-WSH-01 seated five minutes before the clock through a needs_card wash booking, a planned wash
--   leg tagged exterior_wash, its timer up at the clock; twin.ottoq_sim_advance_service_flow for the run at the clock.
--   At the dial's default the car left the bay and its leg stayed planned with no SDR; with bay_exit_closes_its_leg 1
--   the car left, the leg was done from the seat to the timer's end, the booking named it and an SDR (wash) named both.
--   public.ottoq_bay_seat_record_coverage on arm 84's run (b54f6de5) read the wash 2 of 29 seats with a done leg and an
--   SDR (6.9%), the detail 7 of 41 (17.1%) and the service bay 1 of 14 (7.1%).
