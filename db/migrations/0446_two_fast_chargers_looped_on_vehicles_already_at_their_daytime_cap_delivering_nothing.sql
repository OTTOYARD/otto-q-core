-- migration-version: 20260923042353
-- migration-name:    two_fast_chargers_looped_on_vehicles_already_at_their_daytime_cap_delivering_nothing
--
-- 0446  **Two of the depot's ten fast chargers looped for over an hour on two vehicles already at the fast chargers'
--       daytime cap, delivering nothing.** A DCFC session stops at LEAST(vehicle target, `ottoq_target_soc_cap`)
--       - 0.5, and that cap is 90% by day (06:00-20:00 CT, `dcfc_target_soc_day`) against a 100% vehicle target
--       (`ottoq_default_target_soc`). The stall picker never asks the cap. A vehicle at 90% by day therefore still
--       "needs charge", keeps its DCFC reservation, is assigned back to the same DCFC, starts a session that
--       completes at once, and repeats. FINDINGS G179.
--
-- ══ §1 MEASURED 2026-09-23, RUN 324eb0f1 (busy_day, twin depot) ════════════════════════════════════════════════
--
--   - DCFC sessions that started at >= 85% SoC: 110 by sim 11:24 CT, every one 90.0% -> 90.0%, 0.000 kWh, 21 s on
--     average, from sim 10:11 CT onward, on exactly 2 vehicles (814c9bc7... 73 sessions, b2222222... 43) and 2
--     stalls. By sim 11:43 CT: 156 such sessions. Both vehicles: current_soc 90, target_soc 100.
--   - The loop, in the decide path's own rows: every other tick a `stall_assignment` decision
--     {"verb": "assign_stall", "source": "reservation_honoured", "stall_id": c8049eb3... (DCFC), "soc": 90}, then a
--     `task_start` {"verb": "promote_ready", "step": "need_service"}. A new session about every 50 sim-seconds.
--   - Why the reservation wins: `ottoq_l2_propose_stall_assignment` wants L2 for this vehicle
--     (`v_want_type` is 'dcfc' only below 45% or for an immediate dispatch), but orders its candidates by
--     `reserved_by = p_vehicle_id` BEFORE `stall_type = v_want_type`. The vehicle's own DCFC reservation outranks
--     its wanted type, the assignment renews the reservation, and the next pass honours it again.
--   - Cost: 2 of 10 DCFCs, 20% of the depot's fast charging, held by vehicles that cannot take a single kWh from
--     them until 20:00 CT, while the 32 DCFC sessions that started below 40% SoC ran 63 minutes each on average.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   One predicate in the picker's candidate set, the session's own stop rule turned into an admission rule:
--   a charge stall is a candidate only if the vehicle is below LEAST(its target, the stall type's cap now) - 0.5.
--   The target is `vehicles.target_soc` (falling back to `ottoq_default_target_soc()`), exactly what
--   `ottoq_sim_reconcile_charge_sessions` hands the session. So by day a vehicle at 90% is offered L2 only (cap
--   100) and waits for one if none is free. By night it may take a DCFC as before. Its stale DCFC reservation is no
--   longer renewed and expires on its own 600-second timer.
--
--   Deliberately NOT done here:
--   - A minimum useful session (say "at least 5 points of charge") would stop the last tiny top-off below the cap.
--     That is a policy lever with a readiness trade-off, and belongs to a dial the learning loop can test.
--   - The baseline seats (`ottoq_l2_propose_stall_seat`, 0261) keep their text; no A/B pair is using them.
--   - The cap itself is unchanged.
--
-- ══ §3 forces_recert TRUE ════════════════════════════════════════════════════════════════════════════════════
--
--   The picker is the decide path's stall choice (`ottoq_honour_reservation_proposal` is its only caller, from
--   `ottoq_decide_tick`), and certification runs cross the 06:00 CT boundary, so an assignment can change.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0446 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%'
          OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0446 P0: a pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0446 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the picker as read on 2026-09-23, and its anchors unique ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure;
  IF md5(v_src) <> '335d111fefed5df5d7b5fe15cfa54ed1' THEN
    RAISE EXCEPTION '0446 P1: ottoq_l2_propose_stall_assignment md5 is %', md5(v_src);
  END IF;
  FOREACH v_a IN ARRAY ARRAY[
      E'  v_want_kw numeric; v_ceiling numeric; v_wait_reason text := NULL; v_seat int; /* 0261 */\n',
      E'  SELECT inlet_type, inlet_max_kw, battery_capacity_kwh INTO v_inlet, v_inlet_kw, v_batt_kwh\n    FROM vehicles WHERE id = p_vehicle_id;\n',
      E'       AND c.station_state = ''Available'' AND c.last_heartbeat_at >= v_now - INTERVAL ''90 seconds''\n']
  LOOP
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0446 P1: anchor matched % times: %', v_n, left(v_a, 70); END IF;
  END LOOP;
  -- the session's stop rule this mirrors, as read today
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_charge_sessions'::regproc;
  IF position('IF v_new_soc >= v_target_soc - 0.5 THEN' IN v_src) = 0
     OR position('LEAST(COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc()), public.ottoq_target_soc_cap(v_session.stall_type::TEXT, v_session.started_at))' IN v_src) = 0 THEN
    RAISE EXCEPTION '0446 P1: the session''s stop rule is no longer LEAST(target, cap) - 0.5';
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0446_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure;

-- ── THE PREDICATE ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure);
  v_new := replace(v_def,
    E'  v_want_kw numeric; v_ceiling numeric; v_wait_reason text := NULL; v_seat int; /* 0261 */\n',
    E'  v_want_kw numeric; v_ceiling numeric; v_wait_reason text := NULL; v_seat int; /* 0261 */\n'
    || E'  v_veh_target numeric;   /* 0446 */\n');
  v_new := replace(v_new,
    E'  SELECT inlet_type, inlet_max_kw, battery_capacity_kwh INTO v_inlet, v_inlet_kw, v_batt_kwh\n    FROM vehicles WHERE id = p_vehicle_id;\n',
    E'  SELECT inlet_type, inlet_max_kw, battery_capacity_kwh, target_soc INTO v_inlet, v_inlet_kw, v_batt_kwh, v_veh_target\n'
    || E'    FROM vehicles WHERE id = p_vehicle_id;\n');
  v_new := replace(v_new,
    E'       AND c.station_state = ''Available'' AND c.last_heartbeat_at >= v_now - INTERVAL ''90 seconds''\n',
    E'       AND c.station_state = ''Available'' AND c.last_heartbeat_at >= v_now - INTERVAL ''90 seconds''\n'
    || E'       /* 0446 (G179): the session stops at LEAST(target, this stall type''s cap now) - 0.5, so a stall that\n'
    || E'          would stop the session before it starts is not a candidate. Without this, a vehicle at the DCFC\n'
    || E'          daytime cap kept its DCFC reservation and looped on it, delivering nothing. */\n'
    || E'       AND v_soc < LEAST(COALESCE(v_veh_target, public.ottoq_default_target_soc()),\n'
    || E'                         public.ottoq_target_soc_cap(s.stall_type::text, v_now)) - 0.5\n');
  IF v_new = v_def OR position('public.ottoq_target_soc_cap(s.stall_type::text, v_now)) - 0.5' IN v_new) = 0
     OR position('target_soc INTO v_inlet, v_inlet_kw, v_batt_kwh, v_veh_target' IN v_new) = 0 THEN
    RAISE EXCEPTION '0446: the picker splices did not all apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: the loop, recreated and refused (rolled back). All twin charge stalls free, chargers available and
--       heartbeating at the probe clock, one vehicle with no inlet restriction and a 100% target, at 90% SoC. ──
DO $$
DECLARE v_vid uuid; v_dcfc uuid; v_day timestamptz := '2026-09-01 17:00:00+00';   -- 12:00 CT
  v_night timestamptz := '2026-09-01 08:00:00+00';                                -- 03:00 CT
  r jsonb; v_msg text;
BEGIN
  BEGIN
    SELECT v.id INTO v_vid FROM vehicles v WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
     ORDER BY v.id LIMIT 1;
    UPDATE vehicles SET inlet_type = NULL, target_soc = 100 WHERE id = v_vid;
    UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL
     WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type IN ('dcfc','l2');
    UPDATE ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = v_day
     WHERE depot_id = '11111111-1111-1111-1111-111111111111';

    -- (a) by day, at the DCFC cap, with its own DCFC reservation: L2, not the reserved DCFC
    SELECT s.id INTO v_dcfc FROM stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'dcfc'
     ORDER BY s.id LIMIT 1;
    UPDATE stalls SET reserved_by = v_vid, reservation_expires_at = v_day + interval '10 minutes' WHERE id = v_dcfc;
    r := public.ottoq_l2_propose_stall_assignment(v_vid, '11111111-1111-1111-1111-111111111111',
           jsonb_build_object('current_soc', 90, 'now_ts', v_day, 'headroom_kw', 5000));
    IF COALESCE((r->>'abstain')::boolean, true) OR r->>'stall_type' <> 'l2' THEN
      RAISE EXCEPTION '0446 V1(a): by day at 90%% the picker returned %', r;
    END IF;

    -- (b) by day, no L2 available: abstain rather than the DCFC
    UPDATE ottoq_ocpp_chargers c SET station_state = 'Faulted'
      FROM stalls s WHERE s.ocpp_charger_id = c.charger_id AND s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'l2';
    r := public.ottoq_l2_propose_stall_assignment(v_vid, '11111111-1111-1111-1111-111111111111',
           jsonb_build_object('current_soc', 90, 'now_ts', v_day, 'headroom_kw', 5000));
    IF NOT COALESCE((r->>'abstain')::boolean, false) THEN
      RAISE EXCEPTION '0446 V1(b): by day at 90%% with no L2 the picker returned %', r;
    END IF;

    -- (c) the same vehicle below the cap is still offered the DCFC by day
    r := public.ottoq_l2_propose_stall_assignment(v_vid, '11111111-1111-1111-1111-111111111111',
           jsonb_build_object('current_soc', 40, 'now_ts', v_day, 'headroom_kw', 5000));
    IF COALESCE((r->>'abstain')::boolean, true) OR r->>'stall_type' <> 'dcfc' THEN
      RAISE EXCEPTION '0446 V1(c): by day at 40%% the picker returned %', r;
    END IF;

    -- (d) by night the DCFC cap is 100, so at 90% the DCFC is a candidate again
    UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_night WHERE depot_id = '11111111-1111-1111-1111-111111111111';
    UPDATE stalls SET reservation_expires_at = v_night + interval '10 minutes' WHERE id = v_dcfc;
    r := public.ottoq_l2_propose_stall_assignment(v_vid, '11111111-1111-1111-1111-111111111111',
           jsonb_build_object('current_soc', 90, 'now_ts', v_night, 'headroom_kw', 5000));
    IF COALESCE((r->>'abstain')::boolean, true) OR r->>'stall_type' <> 'dcfc' THEN
      RAISE EXCEPTION '0446 V1(d): by night at 90%% the picker returned %', r;
    END IF;

    RAISE EXCEPTION USING MESSAGE = '0446_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> '0446_probe_rollback' THEN RAISE; END IF;
  END;
END $$;

-- ── V2: what shipped is what the header says ──
DO $$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc WHERE oid = 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure;
  IF position('v_soc < LEAST(COALESCE(v_veh_target, public.ottoq_default_target_soc()),' IN v_src) = 0
     OR position('public.ottoq_target_soc_cap(s.stall_type::text, v_now)) - 0.5' IN v_src) = 0
     OR position('v_soc < LEAST(COALESCE(v_veh_target' IN v_src) > position('SELECT id, stall_type, connector_max_kw, eff_kw' IN v_src) THEN
    RAISE EXCEPTION '0446 V2: the cap predicate is not in the candidate set';
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0446_two_fast_chargers_looped_on_vehicles_already_at_their_daytime_cap_delivering_nothing',
   true,
   'G179: ottoq_l2_propose_stall_assignment admits a charge stall only if the vehicle is below LEAST(its target, '
   'ottoq_target_soc_cap(stall type, now)) - 0.5, the session''s own stop rule. By day a vehicle at the DCFC cap is '
   'offered L2 only; its stale DCFC reservation expires. TRUE: the decide path''s stall choice changes on any tick '
   'where a vehicle at or above the DCFC day cap would have been handed a DCFC.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert TRUE. Live proof: the next busy_day run has no DCFC session that starts at or above the DCFC cap
-- by day (324eb0f1: 156 by sim 11:43 CT). Rollback: restore the picker from ottoq_schema_snapshots label '0446_pre'.
