-- migration-version: 20260927060333
-- migration-name:    the_ledger_records_what_the_charge_was_booked_for_and_aimed_at
--
-- 0515  **G240, step 1b: the charge-duration ledger records, for every charge it captures from here on, the SoC the
--       charge was stopping at, the SoC its visit asked for, the SoC the car was at when it stopped, and the booking
--       window the calendar gave it. Without the first, a charge the run's stop cut short cannot be placed on the
--       duration scale, and a calibration fitted from finished charges alone is biased toward the short ones; without
--       the last, whether a charge outlasted its booking can only be read while the purgeable calendar survives.**
--       `db/checks/0386`.
--
-- ══ §1 WHAT WAS MEASURED (2026-09-27, 06:00 UTC, the ledger 0514 made) ════════════════════════════════════════
--
--   On the ten operator runs in 0514's ledger that ran two hours or more, a run's stop cut short 280 L2 charges and
--   finished 267, and in the hottest band 107 against 50. A cut charge is not a failure and not a success: the run
--   stopped, not the charge. Its information is "this charge took longer than it had run", and using it needs the
--   charge's own nominal, i.e. the SoC it was going to stop at. The ledger has no such column, and it cannot be
--   recovered later from `vehicles`, which holds only today's target (checked: the L2 ratio to a nominal built on
--   today's target reads p90 3.99 where the ratio to the charge's own span reads 1.78).
--   The size of the bias this hides: among L2 charges whose run gave them twice their nominal to finish, the median
--   nominal is 40-65 minutes; across all L2 charges it is 130-160. Three-hour runs finish the short L2 charges and cut
--   the long ones, so "the L2 factor" fitted from finished charges describes short L2 charges only.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) Nine columns on `public.ottoq_charge_duration_ledger`, filled by the capture from this migration on and NULL
--       on the 968 rows captured before it (never back-filled: the ledger is append-only evidence, and a value
--       reconstructed today is not what was true then). `capture_version` says which: 1 for 0514's rows, 2 from here.
--       - `charge_target_soc`: the SoC the charge was stopping at -- the car's target capped by the charger type's cap,
--         `LEAST(COALESCE(vehicles.target_soc, ottoq_default_target_soc()), ottoq_target_soc_cap(stall_type, start))`,
--         which is the rule `twin.ottoq_sim_advance_charge_sessions` stops a charge by.
--       - `visit_target_soc`, `visit_id`: the car's open visit in the run and the target it carries, which is what
--         the booking writer (`ottoq.ottoq_record_enacted_booking`) sizes a charge window to (it defaults to 85).
--       - `soc_at_stop`: the car's SoC when the session stopped, so a cut charge says how far it got.
--       - `booking_id`, `booked_from`, `booked_to`, `booking_state`, `booking_source`: the car's charge booking on that
--         stall nearest the session's start, as it stood when the session stopped. The capture fires at the end of
--         the stop's own UPDATE, before anything later in the tick touches the booking.
--   (2) The capture is replaced by the same function plus those reads, each in its own error-swallowing block, so a
--       failed lookup costs the one column, never the row and never the session's write (0340's rule).
--   (3) And a latent hole in 0514's capture is closed on the way: it read the run's kind from a record that is never
--       assigned when a session has no run, which raises inside the capture and is swallowed by its handler, so a
--       production session -- the kind with no run -- would never have been captured. None has existed yet (0385
--       §1(b) reads 0 sessions with no run), so nothing was lost. The capture now reads into scalars, and V3 plants a
--       session with no run and requires it captured.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   A certification or A/B arm's stop still returns at the capture's first lookup and writes nothing. No certified
--   atom reads the ledger. The new reads run only for an operator or production charge.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0515 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_charge_duration_ledger') IS NULL
     OR EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'ottoq_charge_duration_ledger'
                   AND column_name IN ('charge_target_soc','booking_id','capture_version')) THEN
    RAISE EXCEPTION '0515 P2: the ledger is missing, or already carries the columns this adds';
  END IF;
  IF to_regprocedure('public.ottoq_target_soc_cap(text,timestamptz)') IS NULL
     OR to_regprocedure('public.ottoq_default_target_soc()') IS NULL THEN
    RAISE EXCEPTION '0515 P2: the stop-target helpers are not the ones this file reads';
  END IF;
  -- the rule the twin stops a charge by, which charge_target_soc restates
  IF position('LEAST(COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc()), public.ottoq_target_soc_cap(v_session.stall_type::TEXT, v_session.started_at))'
              IN pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0515 P2: the twin no longer stops a charge at the car''s target capped by the charger type';
  END IF;
  -- the capture this replaces is 0514's, byte for byte (md5 read 2026-09-27 06:05 UTC)
  IF md5(pg_get_functiondef('public.ottoq_capture_charge_duration()'::regprocedure)) <> '23cc75285e481c3325bca18f9a91c29d' THEN
    RAISE EXCEPTION '0515 P2: the capture is not 0514''s';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0515_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_capture_charge_duration()'::regprocedure;

-- (1) the columns. capture_version: the rows 0514 captured read 1 (a constant default fills them without a rewrite
--     and without an UPDATE, so the append-only guard is not involved); every capture from here on writes 2.
ALTER TABLE public.ottoq_charge_duration_ledger
  ADD COLUMN capture_version   smallint NOT NULL DEFAULT 1,
  ADD COLUMN charge_target_soc numeric,        -- LEAST(car target, charger-type cap): where the charge was stopping
  ADD COLUMN visit_target_soc  numeric,        -- the open visit's target_soc (the booking writer defaults it to 85)
  ADD COLUMN visit_id          uuid,
  ADD COLUMN soc_at_stop       numeric,        -- vehicles.current_soc when the session stopped
  ADD COLUMN booking_id        uuid,           -- the car's charge booking on this stall nearest the session's start
  ADD COLUMN booked_from       timestamptz,
  ADD COLUMN booked_to         timestamptz,
  ADD COLUMN booking_state     text,
  ADD COLUMN booking_source    text;
ALTER TABLE public.ottoq_charge_duration_ledger ALTER COLUMN capture_version SET DEFAULT 2;

COMMENT ON COLUMN public.ottoq_charge_duration_ledger.capture_version IS
  '1 = captured by 0514 (the columns 0515 added are NULL, never back-filled); 2 = captured under 0515.';
COMMENT ON COLUMN public.ottoq_charge_duration_ledger.charge_target_soc IS
  '0515: the SoC the charge was stopping at, LEAST(COALESCE(vehicles.target_soc, ottoq_default_target_soc()), '
  'ottoq_target_soc_cap(stall_type, started_at)), read when the session stopped. With soc_start it places a charge '
  'the run cut short on the duration scale.';
COMMENT ON COLUMN public.ottoq_charge_duration_ledger.booked_to IS
  '0515: upper(during) of the car''s charge booking on this stall nearest the session''s start, as it stood when the '
  'session stopped. A completed charge with ended_at > booked_to outlasted its booking.';

-- (2) the capture, 0514's plus the new reads. Scalars throughout: 0514 read `v_run.run_by` from a record that is
--     never assigned when a session has no run, which raises "record is not assigned yet" -- swallowed by the capture's
--     own handler, so every session without a run (production) would have been silently not captured. None exists
--     yet (0385 §1(b)); a record read the same way in the new blocks would have had the same hole.
CREATE OR REPLACE FUNCTION public.ottoq_capture_charge_duration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, twin, ottoq, extensions
AS $fn$
DECLARE
  v_run_by    text;
  v_tick      integer;
  v_stype     text;
  v_ckw       numeric;
  v_sdepot    uuid;
  v_vkw       numeric;
  v_vkwh      numeric;
  v_vtarget   numeric;
  v_vsoc      numeric;
  v_nom       numeric;
  v_air       numeric;
  v_tgt       numeric;       -- 0515
  v_vis_id    uuid;          -- 0515
  v_vis_tgt   numeric;       -- 0515
  v_bk_id     uuid;          -- 0515
  v_bk_from   timestamptz;   -- 0515
  v_bk_to     timestamptz;   -- 0515
  v_bk_state  text;          -- 0515
  v_bk_source text;          -- 0515
BEGIN
  IF NEW.sim_run_id IS NOT NULL THEN
    SELECT r.run_by, r.tick_interval_seconds INTO v_run_by, v_tick
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id;
    IF COALESCE(v_run_by, '') NOT IN ('operator_demo', 'production_live') THEN
      RETURN NULL;   -- a certification or A/B arm, or a run this ledger does not time
    END IF;
  END IF;

  SELECT s.stall_type::text, COALESCE(s.connector_max_kw, 50), s.depot_id
    INTO v_stype, v_ckw, v_sdepot FROM public.stalls s WHERE s.id = NEW.stall_id;
  SELECT COALESCE(v.inlet_max_kw, v.max_charge_rate_kw, 150), COALESCE(v.battery_capacity_kwh, 75),
         v.target_soc, v.current_soc
    INTO v_vkw, v_vkwh, v_vtarget, v_vsoc FROM public.vehicles v WHERE v.id = NEW.vehicle_id;

  BEGIN
    IF NEW.soc_start IS NOT NULL AND NEW.soc_end IS NOT NULL AND NEW.soc_end > NEW.soc_start THEN
      v_nom := public.ottoq_charge_minutes_between(NEW.soc_start, NEW.soc_end, v_ckw, v_vkw, v_vkwh);
    END IF;
  EXCEPTION WHEN OTHERS THEN v_nom := NULL;
  END;
  BEGIN
    IF NEW.sim_run_id IS NOT NULL AND NEW.started_at IS NOT NULL THEN
      v_air := twin.ottoq_sim_site_ambient_c(NEW.sim_run_id, NEW.started_at);
    END IF;
  EXCEPTION WHEN OTHERS THEN v_air := NULL;
  END;
  -- 0515: where the charge was stopping (the twin's own rule), the visit's target, and the booking the calendar held
  BEGIN
    v_tgt := LEAST(COALESCE(v_vtarget, public.ottoq_default_target_soc()),
                   public.ottoq_target_soc_cap(v_stype, NEW.started_at));
  EXCEPTION WHEN OTHERS THEN v_tgt := NULL;
  END;
  BEGIN
    SELECT vn.visit_id, vn.target_soc INTO v_vis_id, v_vis_tgt
      FROM public.ottoq_visit_needs vn
     WHERE vn.vehicle_id = NEW.vehicle_id
       AND vn.sim_run_id IS NOT DISTINCT FROM NEW.sim_run_id
       AND vn.status IN ('open','in_progress')
     ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_vis_id := NULL; v_vis_tgt := NULL;
  END;
  BEGIN
    SELECT b.booking_id, lower(b.during), upper(b.during), b.state, b.source
      INTO v_bk_id, v_bk_from, v_bk_to, v_bk_state, v_bk_source
      FROM public.ottoq_stall_bookings b
     WHERE b.sim_run_id IS NOT DISTINCT FROM NEW.sim_run_id
       AND b.vehicle_id = NEW.vehicle_id
       AND b.stall_id = NEW.stall_id
       AND b.purpose IN ('charge_dcfc','charge_l2')
       AND lower(b.during) <= NEW.started_at + interval '30 minutes'
       AND upper(b.during) >= NEW.started_at - interval '30 minutes'
     ORDER BY abs(EXTRACT(epoch FROM lower(b.during) - NEW.started_at)), b.booked_at DESC, b.booking_id
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_bk_id := NULL; v_bk_from := NULL; v_bk_to := NULL; v_bk_state := NULL; v_bk_source := NULL;
  END;

  INSERT INTO public.ottoq_charge_duration_ledger (
    session_id, source_kind, sim_run_id, run_by, tick_interval_seconds, depot_id, stall_id, charger_type, charger_kw,
    vehicle_id, vehicle_kw, battery_kwh, soc_start, soc_end, ambient_temp_c, depot_air_c, started_at, ended_at,
    duration_min, energy_delivered_kwh, stopped_reason, nominal_min,
    capture_version, charge_target_soc, visit_target_soc, visit_id, soc_at_stop,
    booking_id, booked_from, booked_to, booking_state, booking_source)
  VALUES (
    NEW.id, 'capture', NEW.sim_run_id, v_run_by, v_tick, COALESCE(NEW.depot_id, v_sdepot),
    NEW.stall_id, v_stype, v_ckw, NEW.vehicle_id, v_vkw, v_vkwh, NEW.soc_start, NEW.soc_end,
    NEW.ambient_temp_c, v_air, NEW.started_at, NEW.ended_at,
    round((EXTRACT(epoch FROM NEW.ended_at - NEW.started_at) / 60.0)::numeric, 3),
    NEW.energy_delivered_kwh, NEW.stopped_reason, round(v_nom, 3),
    2, v_tgt, v_vis_tgt, v_vis_id, v_vsoc,
    v_bk_id, v_bk_from, v_bk_to, v_bk_state, v_bk_source)
  ON CONFLICT (session_id) DO NOTHING;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '0515 charge-duration capture: %', SQLERRM;   -- never break the session's own write
  RETURN NULL;
END
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_capture_charge_duration() FROM PUBLIC, anon, authenticated;

DO $verify$
BEGIN
  -- V1: the columns exist; 0514's rows read capture_version 1 with the new columns empty; the default is now 2
  IF (SELECT count(*) FROM public.ottoq_charge_duration_ledger WHERE capture_version <> 1) <> 0
     OR (SELECT count(*) FROM public.ottoq_charge_duration_ledger
          WHERE charge_target_soc IS NOT NULL OR booking_id IS NOT NULL OR visit_target_soc IS NOT NULL) <> 0
     OR (SELECT column_default FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'ottoq_charge_duration_ledger'
            AND column_name = 'capture_version') IS DISTINCT FROM '2' THEN
    RAISE EXCEPTION '0515 V1: the ledger''s existing rows or its capture_version default are not as intended';
  END IF;
  -- V2: the trigger still points at the capture, the capture is SECURITY DEFINER, the browser keys cannot run it
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_capture_charge_duration_trg'
                  AND tgrelid = 'public.ocpp_sessions'::regclass
                  AND tgfoid = 'public.ottoq_capture_charge_duration()'::regprocedure)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_capture_charge_duration()'::regprocedure)
     OR has_function_privilege('anon', 'public.ottoq_capture_charge_duration()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_capture_charge_duration()', 'EXECUTE') THEN
    RAISE EXCEPTION '0515 V2: the capture trigger, its security or its grants are not as intended';
  END IF;
END $verify$;

-- V3: rolled back. On the newest finished operator run, six and nine hours past its end on its own clock (so the
--     stall's calendar there is empty and the planted booking cannot meet the EXCLUDE constraints, which cover `done`
--     bookings): a charge planted with a booking and stopped is captured with capture_version 2, its stop target, the
--     car's SoC and exactly the planted booking; a charge planted with no booking is still captured, the booking
--     columns empty; a certification arm writes nothing.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_cert uuid; v_sess uuid; v_sess2 uuid; v_sess3 uuid; v_sess4 uuid; v_bk uuid; n int; r record;
  v_expect_tgt numeric;
BEGIN
  BEGIN
    SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'operator_demo' AND sr.status = 'completed'
       AND EXISTS (SELECT 1 FROM public.ocpp_sessions os WHERE os.sim_run_id = sr.sim_run_id
                      AND os.stopped_reason = 'completed' AND os.soc_end > os.soc_start)
     ORDER BY sr.started_at DESC LIMIT 1;
    SELECT sr.sim_run_id INTO v_cert FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'cert_harness' ORDER BY sr.started_at DESC LIMIT 1;
    IF v_run IS NULL OR v_cert IS NULL THEN RAISE EXCEPTION '0515 V3 FAILED: no operator run or no cert arm to plant on'; END IF;
    SELECT os.* INTO r FROM public.ocpp_sessions os
     WHERE os.sim_run_id = v_run AND os.stopped_reason = 'completed' AND os.soc_end > os.soc_start
     ORDER BY os.started_at LIMIT 1;
    IF r.id IS NULL THEN RAISE EXCEPTION '0515 V3 FAILED: the operator run has no completed session to copy'; END IF;
    SELECT LEAST(COALESCE(v.target_soc, public.ottoq_default_target_soc()),
                 public.ottoq_target_soc_cap(st.stall_type::text, r.started_at))
      INTO v_expect_tgt
      FROM public.vehicles v, public.stalls st WHERE v.id = r.vehicle_id AND st.id = r.stall_id;

    -- (a) with a booking, six hours past the run's end: planted 3 minutes before the start, 40 minutes long
    v_bk := gen_random_uuid();
    INSERT INTO public.ottoq_stall_bookings (booking_id, sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by, source, booked_at_sim)
    SELECT v_bk, v_run, r.stall_id, r.vehicle_id,
           CASE WHEN st.stall_type::text = 'dcfc' THEN 'charge_dcfc' ELSE 'charge_l2' END,
           tstzrange(r.started_at + interval '6 hours' - interval '3 minutes', r.started_at + interval '6 hours 37 minutes'),
           'done', '0515_v3', '0515_v3', r.started_at + interval '6 hours' - interval '3 minutes'
      FROM public.stalls st WHERE st.id = r.stall_id;
    v_sess := gen_random_uuid();
    INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                      connector_id, status, started_at, soc_start, ambient_temp_c, sim_run_id)
    VALUES (v_sess, r.depot_id, r.stall_id, r.vehicle_id, r.charge_point_id, '0515-v3-' || v_sess::text, r.evse_id,
            r.connector_id, r.status, r.started_at + interval '6 hours', r.soc_start, r.ambient_temp_c, v_run);
    UPDATE public.ocpp_sessions SET ended_at = r.ended_at + interval '6 hours', soc_end = r.soc_end,
           stopped_reason = 'completed', energy_delivered_kwh = r.energy_delivered_kwh
     WHERE id = v_sess;
    SELECT count(*) INTO n FROM public.ottoq_charge_duration_ledger l
     WHERE l.session_id = v_sess AND l.capture_version = 2 AND l.source_kind = 'capture'
       AND l.charge_target_soc = v_expect_tgt AND l.soc_at_stop IS NOT NULL
       AND l.booking_id = v_bk AND l.booked_from = r.started_at + interval '6 hours' - interval '3 minutes'
       AND l.booked_to = r.started_at + interval '6 hours 37 minutes' AND l.booking_state = 'done'
       AND l.booking_source = '0515_v3' AND l.nominal_min IS NOT NULL AND l.depot_air_c IS NOT NULL;
    IF n <> 1 THEN RAISE EXCEPTION '0515 V3 FAILED (a): the stop with a booking was not captured with its target and booking'; END IF;

    -- (b) without a booking, nine hours past the run's end: still captured, the booking columns empty
    v_sess2 := gen_random_uuid();
    INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                      connector_id, status, started_at, soc_start, ambient_temp_c, sim_run_id)
    VALUES (v_sess2, r.depot_id, r.stall_id, r.vehicle_id, r.charge_point_id, '0515-v3-' || v_sess2::text, r.evse_id,
            r.connector_id, r.status, r.started_at + interval '9 hours', r.soc_start, r.ambient_temp_c, v_run);
    UPDATE public.ocpp_sessions SET ended_at = r.ended_at + interval '9 hours', soc_end = r.soc_end,
           stopped_reason = 'completed' WHERE id = v_sess2;
    SELECT count(*) INTO n FROM public.ottoq_charge_duration_ledger l
     WHERE l.session_id = v_sess2 AND l.capture_version = 2 AND l.booking_id IS NULL AND l.booked_to IS NULL
       AND l.charge_target_soc IS NOT NULL;
    IF n <> 1 THEN RAISE EXCEPTION '0515 V3 FAILED (b): the stop without a booking was not captured, or found a booking'; END IF;

    -- (c) a certification arm still writes nothing
    v_sess3 := gen_random_uuid();
    INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                      connector_id, status, started_at, soc_start, ambient_temp_c, sim_run_id)
    VALUES (v_sess3, r.depot_id, r.stall_id, r.vehicle_id, r.charge_point_id, '0515-v3-' || v_sess3::text, r.evse_id,
            r.connector_id, r.status, r.started_at, r.soc_start, r.ambient_temp_c, v_cert);
    UPDATE public.ocpp_sessions SET ended_at = r.ended_at, soc_end = r.soc_end, stopped_reason = 'completed' WHERE id = v_sess3;
    SELECT count(*) INTO n FROM public.ottoq_charge_duration_ledger WHERE session_id = v_sess3;
    IF n <> 0 THEN RAISE EXCEPTION '0515 V3 FAILED (c): a certification arm''s stop was captured'; END IF;

    -- (d) a session with no run -- production -- is captured: the path 0514's record read could not reach
    v_sess4 := gen_random_uuid();
    INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                      connector_id, status, started_at, soc_start, ambient_temp_c, sim_run_id)
    VALUES (v_sess4, r.depot_id, r.stall_id, r.vehicle_id, r.charge_point_id, '0515-v3-' || v_sess4::text, r.evse_id,
            r.connector_id, r.status, r.started_at + interval '12 hours', r.soc_start, r.ambient_temp_c, NULL);
    UPDATE public.ocpp_sessions SET ended_at = r.ended_at + interval '12 hours', soc_end = r.soc_end,
           stopped_reason = 'completed' WHERE id = v_sess4;
    SELECT count(*) INTO n FROM public.ottoq_charge_duration_ledger l
     WHERE l.session_id = v_sess4 AND l.capture_version = 2 AND l.sim_run_id IS NULL AND l.run_by IS NULL
       AND l.nominal_min IS NOT NULL AND l.charge_target_soc IS NOT NULL;
    IF n <> 1 THEN RAISE EXCEPTION '0515 V3 FAILED (d): a session with no run was not captured'; END IF;

    RAISE EXCEPTION '0515 V3 PASSED: a stop is captured as version 2 with its stop target, its visit, the car''s SoC and the booking the calendar held; a stop with no booking still captured; a session with no run captured; a certification arm writes nothing';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0515 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0515 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: CREATE OR REPLACE the capture from the `0515_pre` snapshot. The columns stay (they are evidence once written).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0515_the_ledger_records_what_the_charge_was_booked_for_and_aimed_at', false,
  'G240 step 1b: the charge-duration ledger records each captured charge''s stop target, visit target, SoC at stop and '
  'booking window. The capture still returns at its first lookup on a certification arm; no certified atom reads it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
