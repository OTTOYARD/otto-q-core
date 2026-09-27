-- migration-version: 20260927062217
-- migration-name:    a_calibrated_charge_window_behind_a_dial
--
-- 0517  **G240, step 3: the booking writer sizes a charge's window from a named calibration version when the dial
--       `charge_window_calibration_id` names one, and exactly as before when it is 0 -- which is its default.**
--       `db/checks/0386` §5.
--
-- ══ §1 WHAT CHANGES WHEN THE DIAL NAMES A VERSION ══════════════════════════════════════════════════════════════
--
--   `ottoq.ottoq_record_enacted_booking` sizes a charge it is not handed a window for as the nominal minutes from the
--   car's SoC to its visit's target (85 when there is none), clamped to 15..480. With a version named:
--   (1) the span is the car's own stop target -- its target capped by the charger type's cap, `LEAST(COALESCE(
--       vehicles.target_soc, ottoq_default_target_soc()), ottoq_target_soc_cap(stall type, start))` -- because that is
--       where the charge will stop (the twin's own rule, which 0515 records as `charge_target_soc`), and the
--       calibration's scores were measured against the span each charge actually charged. On the full-day run the stop
--       target sat 0.8 (L2) to 2.2 (DCFC) points above the visit's on average (0386 §2(b)), so sizing to the visit's
--       target would leave part of every charge outside the calibration;
--   (2) that nominal is multiplied by `ottoq_charge_window_factor(version, charger type, depot air at the window's
--       start)` -- the air-band cell when it is adequate, else the charger-type cell -- and then clamped as before.
--   A version that gives no factor, a car already at its stop target, or any error in the lookup leaves the nominal
--   window: a calibration is never allowed to cost a booking. The air is the depot's (`twin.ottoq_sim_site_ambient_c`,
--   0510), which is NULL outside a run; a charge with no air uses its charger type's cell. A production site needs its
--   own air source before this is anything but pooled there, and that is recorded, not built.
--
-- ══ §2 WHY A DIAL, AND WHY forces_recert FALSE ═════════════════════════════════════════════════════════════════
--
--   A calibration is a version the canon must be able to reproduce, so it is named, never "the latest": refitting
--   writes a new version and moving the dial to it is a change the canon sees. At 0 -- the catalog default, and no
--   scope sets it -- the writer reads one policy value and does nothing else, so every certified arm books exactly as
--   before. Turning it on is a paired experiment on the twin at the operator's tick, not a default flip.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0517 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
BEGIN
  -- the booking writer is the body read 2026-09-27 06:20 UTC, and exactly one exists
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking') <> 1
     OR (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking') <> 'afe5aac018163ab5b2636feae488cbfe' THEN
    RAISE EXCEPTION '0517 P2: the booking writer is not the body this file patches';
  END IF;
  IF to_regprocedure('public.ottoq_charge_window_factor(bigint,text,numeric)') IS NULL
     OR to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL
     OR to_regprocedure('twin.ottoq_sim_site_ambient_c(uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0517 P2: 0516, the dial reader or the depot-air helper is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_window_calibration_id') THEN
    RAISE EXCEPTION '0517 P2: the dial is already catalogued';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0517_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking';

-- (1) the dial
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('charge_window_calibration_id',
        '0517 (G240 step 3): the ottoq_charge_window_calibration version the booking writer sizes a charge window '
        'with -- nominal minutes to the car''s own stop target, times the version''s factor for the charger type and '
        'the depot''s air. 0 (the default) leaves the window as it was: nominal to the visit''s target. A version is '
        'immutable; refitting writes a new one and moving this dial to it is a change the canon sees.',
        0, 0, 1000000000, 'ottoq.ottoq_record_enacted_booking (charge window)', false);

-- (2) the booking writer: one block between the nominal and the clamp, and its variables
DO $patch$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$  v_why jsonb; v_leg uuid; v_leg_src text;
BEGIN$o1$,
          $n1$  v_why jsonb; v_leg uuid; v_leg_src text;
  v_cal numeric; v_ctype text; v_stop_tgt numeric; v_air numeric; v_fac jsonb;   -- 0517
BEGIN$n1$],
    ARRAY[$o2$      EXCEPTION WHEN OTHERS THEN v_min := NULL;
      END;
      v_min := LEAST(GREATEST(COALESCE(v_min, 45), 15), 480);$o2$,
          $n2$      EXCEPTION WHEN OTHERS THEN v_min := NULL;
      END;
      -- 0517 (G240 step 3): with a calibration version named by the dial, the window is the charge to where it will
      -- actually stop -- the car's target capped by the charger type, the twin's own rule and 0515's charge_target_soc --
      -- times the version's factor for the charger type and the depot's air. Dial 0, the default, changes nothing; a
      -- version with no factor, or any failure here, leaves the nominal window.
      BEGIN
        v_cal := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_window_calibration_id', 0), 0);
        IF v_cal > 0 THEN
          v_ctype := CASE WHEN v_stall_type IN ('dcfc','l2') THEN v_stall_type
                          WHEN v_purpose = 'charge_dcfc' THEN 'dcfc' ELSE 'l2' END;
          v_stop_tgt := LEAST(COALESCE((SELECT v.target_soc FROM public.vehicles v WHERE v.id = p_vehicle_id),
                                       public.ottoq_default_target_soc()),
                              public.ottoq_target_soc_cap(v_ctype, v_from));
          v_air := twin.ottoq_sim_site_ambient_c(p_sim_run_id, v_from);
          v_fac := public.ottoq_charge_window_factor(v_cal::bigint, v_ctype, v_air);
          IF v_fac IS NOT NULL AND v_stop_tgt > COALESCE(v_soc, 50) THEN
            v_min := public.ottoq_charge_minutes_between(COALESCE(v_soc, 50), v_stop_tgt, v_cmax, v_vmax, v_batt)
                     * (v_fac->>'factor')::numeric;
          END IF;
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      v_min := LEAST(GREATEST(COALESCE(v_min, 45), 15), 480);$n2$]];
  i int; n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking';
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0517: booking-writer patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch$;

DO $verify$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking';
  -- V1: one writer, the block once, still SECURITY DEFINER, the browser keys cannot run it
  IF position('charge_window_calibration_id' IN v_def) = 0
     OR (length(v_def) - length(replace(v_def, 'ottoq_charge_window_factor(', ''))) / length('ottoq_charge_window_factor(') <> 1
     OR NOT (SELECT prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking')
     OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking'
                   AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))) THEN
    RAISE EXCEPTION '0517 V1: the patched writer is not as intended';
  END IF;
  -- V2: nothing sets the dial anywhere, so every scope reads the default 0
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'charge_window_calibration_id') THEN
    RAISE EXCEPTION '0517 V2: some scope already sets the dial';
  END IF;
END $verify$;

-- V3: rolled back. On the newest finished operator run with finished charges, four and eight hours past its end on its
--     own clock (an empty calendar there): (a) with the dial at 0, a charge booking's window is exactly the old one --
--     nominal to the visit's target, clamped; (b) with the dial naming a version fitted here, it is the nominal to the
--     car's stop target times the lookup's factor, clamped; (c) a dial naming a version that does not exist books the
--     old window.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_car uuid; v_stall uuid; v_stall2 uuid; v_stall3 uuid; v_end timestamptz; v_t timestamptz;
  v_bk uuid; v_min numeric; v_exp numeric; v_cal bigint; v_fac jsonb; v_soc numeric; v_batt numeric; v_vmax numeric;
  v_cmax numeric; v_target numeric; v_stop numeric; v_air numeric; v_w0 numeric; v_w1 numeric;
BEGIN
  BEGIN
    SELECT sr.sim_run_id, sr.sim_clock_current INTO v_run, v_end FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'operator_demo' AND sr.status = 'completed'
       AND (SELECT count(*) FROM public.ocpp_sessions os WHERE os.sim_run_id = sr.sim_run_id AND os.stopped_reason = 'completed') >= 20
     ORDER BY sr.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0517 V3 FAILED: no finished operator run with finished charges'; END IF;
    -- a car below 60% that the run knew, and three L2 stalls of the twin depot
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.current_soc < 60
       AND COALESCE(v.target_soc, public.ottoq_default_target_soc()) > v.current_soc + 10
     ORDER BY v.current_soc, v.id LIMIT 1;
    SELECT s.id INTO v_stall FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'l2' ORDER BY s.stall_code LIMIT 1;
    SELECT s.id INTO v_stall2 FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'l2' ORDER BY s.stall_code OFFSET 1 LIMIT 1;
    SELECT s.id INTO v_stall3 FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'l2' ORDER BY s.stall_code OFFSET 2 LIMIT 1;
    IF v_car IS NULL OR v_stall3 IS NULL THEN RAISE EXCEPTION '0517 V3 FAILED: no car below 60%% or too few L2 stalls'; END IF;
    SELECT v.current_soc, COALESCE(v.battery_capacity_kwh, 75), COALESCE(v.inlet_max_kw, v.max_charge_rate_kw, 150)
      INTO v_soc, v_batt, v_vmax FROM public.vehicles v WHERE v.id = v_car;
    SELECT COALESCE(s.connector_max_kw, 50) INTO v_cmax FROM public.stalls s WHERE s.id = v_stall;
    v_target := COALESCE((SELECT vn.target_soc FROM public.ottoq_visit_needs vn
                           WHERE vn.vehicle_id = v_car AND vn.status IN ('open','in_progress') AND vn.sim_run_id = v_run
                           ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), 85);

    -- (a) dial 0: the old window
    v_t := v_end + interval '4 hours';
    v_bk := ottoq.ottoq_record_enacted_booking(v_run, v_stall, v_car, v_t, NULL, NULL, NULL, NULL, '0517_v3');
    SELECT EXTRACT(epoch FROM upper(b.during) - lower(b.during)) / 60 INTO v_w0 FROM public.ottoq_stall_bookings b WHERE b.booking_id = v_bk;
    v_exp := LEAST(GREATEST(COALESCE(public.ottoq_charge_minutes_between(COALESCE(v_soc, 50), v_target, v_cmax, v_vmax, v_batt), 45), 15), 480)::int;
    IF v_bk IS NULL OR v_w0 IS DISTINCT FROM v_exp THEN
      RAISE EXCEPTION '0517 V3 FAILED (a): dial 0 booked % minutes where the old window is %', v_w0, v_exp;
    END IF;

    -- (b) dial naming a version fitted here
    v_cal := public.ottoq_fit_charge_window_calibration('11111111-1111-1111-1111-111111111111', 0.10, 2.0, 30, 120, '{5,15,25}', NULL, '0517 V3');
    PERFORM public.ottoq_policy_set('run', v_run, 'charge_window_calibration_id', v_cal, '0517_v3');
    v_t := v_end + interval '8 hours';
    v_bk := ottoq.ottoq_record_enacted_booking(v_run, v_stall2, v_car, v_t, NULL, NULL, NULL, NULL, '0517_v3');
    SELECT EXTRACT(epoch FROM upper(b.during) - lower(b.during)) / 60 INTO v_w1 FROM public.ottoq_stall_bookings b WHERE b.booking_id = v_bk;
    v_stop := LEAST(COALESCE((SELECT v.target_soc FROM public.vehicles v WHERE v.id = v_car), public.ottoq_default_target_soc()),
                    public.ottoq_target_soc_cap('l2', v_t));
    v_air := twin.ottoq_sim_site_ambient_c(v_run, v_t);
    v_fac := public.ottoq_charge_window_factor(v_cal, 'l2', v_air);
    IF v_fac IS NULL THEN RAISE EXCEPTION '0517 V3 FAILED (b): the fitted version gives no L2 factor to test with'; END IF;
    v_exp := LEAST(GREATEST(public.ottoq_charge_minutes_between(COALESCE(v_soc, 50), v_stop, v_cmax, v_vmax, v_batt)
                            * (v_fac->>'factor')::numeric, 15), 480)::int;
    IF v_bk IS NULL OR v_w1 IS DISTINCT FROM v_exp OR v_w1 <= v_w0 THEN
      RAISE EXCEPTION '0517 V3 FAILED (b): the calibrated window is % minutes, expected % (old window %)', v_w1, v_exp, v_w0;
    END IF;

    -- (c) a dial naming no version books the old window
    PERFORM public.ottoq_policy_set('run', v_run, 'charge_window_calibration_id', 999999999, '0517_v3');
    v_t := v_end + interval '12 hours';
    v_bk := ottoq.ottoq_record_enacted_booking(v_run, v_stall3, v_car, v_t, NULL, NULL, NULL, NULL, '0517_v3');
    SELECT EXTRACT(epoch FROM upper(b.during) - lower(b.during)) / 60 INTO v_min FROM public.ottoq_stall_bookings b WHERE b.booking_id = v_bk;
    IF v_bk IS NULL OR v_min IS DISTINCT FROM v_w0 THEN
      RAISE EXCEPTION '0517 V3 FAILED (c): a dial naming no version booked % minutes, not the old %', v_min, v_w0;
    END IF;

    RAISE EXCEPTION '0517 V3 PASSED: dial 0 books the old % minute window; the version fitted here books % minutes (% x %, cell %); a missing version books the old window',
      v_w0, v_w1, round(public.ottoq_charge_minutes_between(COALESCE(v_soc, 50), v_stop, v_cmax, v_vmax, v_batt), 1),
      v_fac->>'factor', v_fac->>'cell';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0517 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0517 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore ottoq.ottoq_record_enacted_booking from `0517_pre` (CREATE OR REPLACE, ACL kept); DELETE the
-- catalog row once no scope sets it.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0517_a_calibrated_charge_window_behind_a_dial', false,
  'G240 step 3: the booking writer sizes a charge window from a named calibration version when the dial '
  'charge_window_calibration_id names one; at 0, the catalog default set by no scope, it books exactly as before.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
