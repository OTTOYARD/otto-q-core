-- migration-version: 20260926214200
-- migration-name:    a_parking_hold_lasts_as_long_as_its_car_is_parked
--
-- 0500  **A car parked in staging to wait for a charger sat on a hold that lapsed, so the calendar called its stall
--       free (G228).** `db/checks/0368` §11, `db/checks/0370`.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   When no charger is free, the charge step (`ottoq_decide_tick` (3)) parks the arrival in a staging stall on a
--   parking hold (`temp_hold`, 12-17 minutes, or `perimeter_hold`) and the car keeps its place in the charge queue. The
--   hold is booked once. A busy-day wait is an hour or more, so the hold ran out while the car was still parked on it,
--   and `ottoq.ottoq_release_expired_bookings` closed it `done / window_elapsed_occupied` (the overstay, G81). From then
--   on the calendar showed the stall free while both pointers held it.
--
--   Measured on validation run `394e1e83`: at sim 10:37 AM 38 of 42 waiting cars sat on a lapsed hold, a mean 54
--   minutes past its window, and at 11:50 AM 33 of 35, 107 minutes past. Nothing was double-parked: the pointer gate
--   refuses a command to an occupied stall, and `calendar_occupancy_guard` (on) keeps an occupied stall out of the
--   candidate source for the next 45 minutes. What was wrong is the calendar itself, which every reader that does not
--   also read the pointer takes as true: a forward booking further out than the guard's horizon, the decision frame's
--   `has_live_booking`, and any count of held staging.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   Before it closes anything, the closer renews each active parking hold (`temp_hold`, `perimeter_hold`) whose window
--   has run out while its car is still parked on it: the stall's pointer names the car AND the car's pointer names the
--   stall (a stale stall pointer alone, G121's shape, renews nothing). The renewal moves the window's end to the clock
--   plus `staging_hold_renew_min` (dial, default 15), so the calendar keeps the stall for as long as the car stays, and
--   once the car leaves the hold ends within one renewal. A renewal that would overlap another booking on the stall is
--   not made, and that hold is closed as before. Charge bookings keep G81's overstay stamp (the frame publishes it as
--   `occupies_charge_stall_unbooked`); this touches parking holds only.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The closer runs in the certified tick (`ottoq_sim_decide_and_dispatch`). Bookings move on any arm where a car
--   outstays its parking hold.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0500 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure))
     <> '1a94b7fbeb1e951b4cf341a560cff05c' THEN
    RAISE EXCEPTION '0500 P2: ottoq.ottoq_release_expired_bookings is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0500_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure;

DO $patch$
DECLARE
  r record;
  v_def text := pg_get_functiondef('ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure);
  n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('the declarations',
       $o$DECLARE v_n int; v_rows jsonb := '[]'::jsonb; v_rec jsonb; v_depot uuid; v_grace int; v_pre int := 0;
$o$,
       $n$DECLARE v_n int; v_rows jsonb := '[]'::jsonb; v_rec jsonb; v_depot uuid; v_grace int; v_pre int := 0;
  v_renew int;
$n$),
      ('the renewal, before the closer',
       $o$  -- BUILD 2: routed through the SAME predicate as ottoq_release_vacated_spaces so
$o$,
       $n$  -- 0500 (G228): A PARKING HOLD LASTS AS LONG AS ITS CAR IS PARKED. A car parked in staging to wait
  -- for a charger is booked a 12-17 minute hold and waits an hour or more, so the closer below closed
  -- the hold done / window_elapsed_occupied with the car still on the stall, and the calendar called
  -- an occupied stall free. So before closing, renew each active parking hold whose window has run out
  -- while its car is still parked on it, by BOTH pointers (a stale stall pointer alone renews nothing).
  -- The window's end moves to the clock plus staging_hold_renew_min, so a hold outlives its car by one
  -- renewal at most. A renewal that would overlap another booking on the stall is not made, and the
  -- hold closes below as before. Parking holds only: a charge overstay keeps its G81 stamp. In its own
  -- block so it can never cost the closer.
  BEGIN
    v_renew := GREATEST(public.ottoq_policy_get(p_sim_run_id, 'staging_hold_renew_min', 15), 1)::int;
    UPDATE public.ottoq_stall_bookings b
       SET during = tstzrange(lower(b.during), p_clock + make_interval(mins => v_renew), '[)')
      FROM public.stalls s, public.vehicles v
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state = 'active'
       AND b.purpose IN ('temp_hold','perimeter_hold')
       AND upper(b.during) <= p_clock
       AND s.id = b.stall_id AND s.current_vehicle_id = b.vehicle_id
       AND v.id = b.vehicle_id AND v.current_stall_id = b.stall_id
       AND NOT EXISTS (
         SELECT 1 FROM public.ottoq_stall_bookings o
          WHERE o.sim_run_id = b.sim_run_id AND o.stall_id = b.stall_id AND o.booking_id <> b.booking_id
            AND o.state IN ('held','active','done','interrupted')
            AND o.during && tstzrange(upper(b.during), p_clock + make_interval(mins => v_renew), '[)'));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_release_expired_bookings: parking hold renewal failed sqlstate=% msg=%', SQLSTATE, SQLERRM;
  END;

  -- BUILD 2: routed through the SAME predicate as ottoq_release_vacated_spaces so
$n$)
    ) t(what, v_old, v_new)
  LOOP
    n := (length(v_def) - length(replace(v_def, r.v_old, ''))) / length(r.v_old);
    IF n <> 1 THEN RAISE EXCEPTION '0500: % matched % times, not once', r.what, n; END IF;
    v_def := replace(v_def, r.v_old, r.v_new);
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure;
  v_def text := pg_get_functiondef('ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure);
  v_run uuid; v_depot uuid; v_clk timestamptz; v_stall uuid; v_stall2 uuid; v_car uuid; v_car2 uuid;
  v_hold uuid; v_hold2 uuid; v_left uuid; v_st record; v_st2 record; v_left_st record;
BEGIN
  -- V1: the renewal sits once, before the closer's UPDATE, and renews parking holds only.
  IF (length(v_def) - length(replace(v_def, 'staging_hold_renew_min', ''))) / length('staging_hold_renew_min') <> 2
     OR position('AND b.purpose IN (''temp_hold'',''perimeter_hold'')' IN v_def) = 0
     OR position('staging_hold_renew_min'', 15)' IN v_def) > position('-- BUILD 2:' IN v_def) THEN
    RAISE EXCEPTION '0500 V1: the renewal is not in place before the closer';
  END IF;
  -- V2: still volatile and security definer, the same search path and privileges.
  IF (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 'v' OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f) <> 'postgres=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0500 V2: ottoq_release_expired_bookings changed volatility, search path or privileges';
  END IF;
  -- V3: on the newest operator run, at its clock: car 1 parked on staging stall 1 whose active temp hold has run out
  -- (renewed to the clock + 15 min), car 2 parked on staging stall 2 with a lapsed hold and another car booked there
  -- from the clock (closed as before), and a lapsed hold whose car is gone (closed as before). Rolled back.
  SELECT r.sim_run_id, r.depot_id, r.sim_clock_current INTO v_run, v_depot, v_clk
    FROM public.ottoq_sim_runs r
   WHERE r.sim_clock_current IS NOT NULL AND r.depot_id IS NOT NULL AND r.validation_status IS NULL
   ORDER BY r.started_at DESC LIMIT 1;
  SELECT s.id INTO v_stall FROM public.stalls s
   WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging' AND s.zone <> 'arrival_inspection' ORDER BY s.id LIMIT 1;
  SELECT s.id INTO v_stall2 FROM public.stalls s
   WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging' AND s.zone <> 'arrival_inspection' AND s.id <> v_stall
   ORDER BY s.id LIMIT 1;
  SELECT s.id INTO v_left FROM public.stalls s
   WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging' AND s.zone <> 'arrival_inspection'
     AND s.id NOT IN (v_stall, v_stall2) ORDER BY s.id LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v
   WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' ORDER BY v.id LIMIT 1;
  SELECT v.id INTO v_car2 FROM public.vehicles v
   WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.id <> v_car ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_left IS NULL OR v_car2 IS NULL THEN
    RAISE EXCEPTION '0500 V3: no operator run with three staging stalls and two cars to probe with';
  END IF;
  BEGIN
    -- a clean slate on the three stalls and for the two cars
    DELETE FROM public.ottoq_stall_bookings b
     WHERE b.sim_run_id = v_run AND (b.stall_id IN (v_stall, v_stall2, v_left) OR b.vehicle_id IN (v_car, v_car2));
    UPDATE public.vehicles SET current_stall_id = NULL WHERE current_stall_id IN (v_stall, v_stall2, v_left);
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL
     WHERE id IN (v_stall, v_stall2, v_left) OR current_vehicle_id IN (v_car, v_car2);
    -- car 1 parked on stall 1, car 2 parked on stall 2, and both holds (plus one on stall 3, whose car has gone) lapsed
    UPDATE public.stalls SET current_vehicle_id = v_car WHERE id = v_stall;
    UPDATE public.vehicles SET current_stall_id = v_stall WHERE id = v_car;
    UPDATE public.stalls SET current_vehicle_id = v_car2 WHERE id = v_stall2;
    UPDATE public.vehicles SET current_stall_id = v_stall2 WHERE id = v_car2;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by)
    VALUES (v_run, v_stall,  v_car,  'temp_hold', tstzrange(v_clk - interval '40 minutes', v_clk - interval '25 minutes', '[)'), 'active', 'otto_q'),
           (v_run, v_stall2, v_car2, 'temp_hold', tstzrange(v_clk - interval '40 minutes', v_clk - interval '25 minutes', '[)'), 'active', 'otto_q'),
           (v_run, v_left,   v_car2, 'temp_hold', tstzrange(v_clk - interval '60 minutes', v_clk - interval '45 minutes', '[)'), 'active', 'otto_q');
    -- another car's booking on stall 2 from the clock, so car 2's renewal would overlap it
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by)
    SELECT v_run, v_stall2, v.id, 'temp_hold', tstzrange(v_clk, v_clk + interval '15 minutes', '[)'), 'held', 'otto_q'
      FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.id NOT IN (v_car, v_car2)
     ORDER BY v.id LIMIT 1;
    PERFORM ottoq.ottoq_release_expired_bookings(v_run, v_clk);
    SELECT b.state, b.release_reason, upper(b.during) AS hi INTO v_st
      FROM public.ottoq_stall_bookings b WHERE b.sim_run_id = v_run AND b.stall_id = v_stall AND b.vehicle_id = v_car;
    SELECT b.state, b.release_reason, upper(b.during) AS hi INTO v_st2
      FROM public.ottoq_stall_bookings b WHERE b.sim_run_id = v_run AND b.stall_id = v_stall2 AND b.vehicle_id = v_car2;
    SELECT b.state, b.release_reason, upper(b.during) AS hi INTO v_left_st
      FROM public.ottoq_stall_bookings b WHERE b.sim_run_id = v_run AND b.stall_id = v_left AND b.vehicle_id = v_car2;
    IF v_st.state IS DISTINCT FROM 'active' OR v_st.hi IS DISTINCT FROM v_clk + interval '15 minutes' THEN
      RAISE EXCEPTION '0500 V3: the parked car''s lapsed hold was not renewed: % % until %', v_st.state, v_st.release_reason, v_st.hi;
    END IF;
    IF v_st2.state IS DISTINCT FROM 'done' OR v_st2.release_reason IS DISTINCT FROM 'window_elapsed_occupied' THEN
      RAISE EXCEPTION '0500 V3: a renewal that would overlap another booking was made: % %', v_st2.state, v_st2.release_reason;
    END IF;
    IF v_left_st.state IS DISTINCT FROM 'done' OR v_left_st.release_reason IS DISTINCT FROM 'window_elapsed_occupied' THEN
      RAISE EXCEPTION '0500 V3: a lapsed hold whose car has gone was not closed as before: % %', v_left_st.state, v_left_st.release_reason;
    END IF;
    RAISE EXCEPTION '0500_v3_rolled_back';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '0500_v3_rolled_back' THEN RAISE; END IF;
  END;
END $verify$;

-- Rollback: restore ottoq.ottoq_release_expired_bookings from ottoq_schema_snapshots label '0500_pre' (CREATE OR
-- REPLACE, ACL kept). The dial staging_hold_renew_min needs no row: it reads its default, 15.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0500_a_parking_hold_lasts_as_long_as_its_car_is_parked', true,
  'ottoq_release_expired_bookings renews an active temp_hold or perimeter_hold whose window ran out while its car is '
  'still parked on it (both pointers) to the clock plus staging_hold_renew_min (default 15), unless that would overlap '
  'another booking, before it closes anything. Bookings move on any arm where a car outstays its parking hold.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
