-- migration-version: PENDING
-- migration-name:    the_twins_operators_send_telemetry_and_faults_through_the_door
--
-- 0692  **The twin's operators send their cars' telemetry and faults through the v2 door, behind a flag, and the
--        twin's world stops reading OTTO-Q's packets as its own truth.** Stages 1 and 2 of the sending side
--        (docs/TWIN_SENDING_SIDE.md), step 4 of the twin data contract review. Chase, 2026-10-09: route the twin's
--        sending signals through the door first, full separation later.
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The twin writes each deployed car's telemetry straight into public.ottoq_telemetry_packets
--   (twin.ottoq_sim_emit_telemetry, one packet a tick, its only caller twin.ottoq_sim_advance_deployed_telemetry), in
--   OTTO-Q's own transaction. A real operator could not: it would send com.ottoyard.vehicle.telemetry to the door,
--   which judges the key, the car, the order and the clock, and drops a road position (contract rule 5). And the
--   twin's world reads those packets back as its own truth: twin.ottoq_sim_advance_wear_counters takes each car's
--   speed from its latest packet and the tick's worst DTC from the packets' dtc_codes. The twin's DTCs are proprietary
--   (ottoq_dtc_catalog, AV-*), which the contract carries as a fault report's fault_codes, never as OBD-II telemetry.
--
-- ══ §2 WHAT THIS CHANGES (all behind twin_operator_publish; 0, unset everywhere, is today byte for byte) ═════════
--
--   (a) The flag twin_operator_publish (0 = the twin writes packets itself, as today; 1 = its operators send them),
--       a person's dial, per run.
--   (b) twin.ottoq_twin_drive_log: per deployed car per tick, the speed it drove, the DTC it raised and whether its
--       telemetry reached OTTO-Q. Run-scoped (class engine, plain FK).
--   (c) twin.ottoq_twin_operator_publish(run, clock, car, ...): logs the tick; finds the car's operator (a car no
--       operator speaks for keeps the old direct path); numbers the car's events in the operator's per-car sequence;
--       rolls the same loss dice as the old path (3% x the run's telemetry_dropout, same seed and salt), and a lost
--       packet still uses its sequence number, so the door records the gap; sends com.ottoyard.vehicle.telemetry
--       (state of charge, battery power positive into the battery, speed, battery and air temperature, tires in kPa,
--       position; no DTC list) and, when the tick raised a DTC, com.ottoyard.vehicle.fault.summary (category from the
--       catalog's: perception and sensor to sensor_anomaly, hardware and powertrain to vehicle_malfunction, the rest
--       other; severity info and minor to low, moderate to medium, major to high, safety_critical to critical; the code
--       as fault_codes; takes_vehicle_offline false), in one batch under the operator's key on the run's clock.
--   (d) twin.ottoq_sim_advance_deployed_telemetry calls it in place of ottoq_sim_emit_telemetry when the run's flag is
--       on.
--   (e) twin.ottoq_sim_advance_wear_counters reads the speed and the DTCs from the drive log when the run's flag is on.
--       One difference by design: a lost packet no longer reads to the world as a car standing still (today a dropped
--       packet's row is the latest and its speed reads as 0).
--   (f) The research wing's pair, registered as a dial experiment (as 0656).
--
--   What a real operator's telemetry loses through the door the twin's loses too: the 12% of packets the old path
--   marked partial arrive whole (the contract has no such field), signal strength is not sent, and road positions are
--   dropped by the door. No engine reader uses any of the three (docs/TWIN_SENDING_SIDE.md). Each DTC now reaches OTTO-Q
--   as an open exception carrying its run (0691), which it did not before; nothing in the twin resolves it, and none
--   blocks progression (blocks_progression defaults false; SLA.007 counts only blocking exceptions tied to a task).
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   The flag is set nowhere. At 0 both patched functions take the branch that is their old body word for word (V1
--   runs a tick at 0 and requires no drive log row, no inbox row and a packet written the old way). Setting the flag
--   is a certified change after the pair, and forces a recertification then.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the two definitions in ottoq_schema_snapshots WHERE label = '0692_pre'; mark the experiment created_by
--   '0692' abandoned. The new table and function stay (dropping them needs a person at the connector's prompt) and
--   nothing calls the function once the definitions are restored.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0692 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0691_a_twin_operators_fault_report_goes_with_its_run') THEN
    RAISE EXCEPTION '0692 P1: 0691 is not classified; apply in order';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure))
       <> '10c31929ce82ab46f8821401f384b603' THEN
    RAISE EXCEPTION '0692 P1: twin.ottoq_sim_advance_deployed_telemetry is not the definition this file patches (0690''s)';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_wear_counters(uuid,timestamptz,numeric,bigint,uuid[])'::regprocedure))
       <> 'be209981f4f396283047756bf4ab5832' THEN
    RAISE EXCEPTION '0692 P1: twin.ottoq_sim_advance_wear_counters is not the definition this file patches';
  END IF;
  IF md5(pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure))
       <> 'ed2895cacce4fe27325f7648ed2f208a' THEN
    RAISE EXCEPTION '0692 P1: the door''s apply is not 0691''s, which stamps a twin fault report with its run';
  END IF;
  IF to_regclass('twin.ottoq_twin_drive_log') IS NOT NULL
     OR to_regprocedure('twin.ottoq_twin_operator_publish(uuid,timestamptz,uuid,numeric,numeric,numeric,numeric,text,text)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'twin_operator_publish')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_operator_publish')
     OR EXISTS (SELECT 1 FROM public.ottoq_dial_experiments WHERE param_key = 'twin_operator_publish') THEN
    RAISE EXCEPTION '0692 P1: an object or a key this file creates exists already';
  END IF;
  IF (SELECT count(*) FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
       WHERE k.is_active AND k.data_source = 'twin' AND 'telemetry' = ANY (k.streams) AND 'incident' = ANY (k.streams)) < 2 THEN
    RAISE EXCEPTION '0692 P1: the twin''s two operators do not both hold active twin keys with the telemetry and incident streams';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0692 P1: a run is live; apply between runs';
  END IF;
END $premises$;

-- ── snapshots ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0692_pre', 'function', 'twin', x.n, x.d, md5(x.d)
  FROM (VALUES
          ('ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)',
           pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure)),
          ('ottoq_sim_advance_wear_counters(uuid,timestamptz,numeric,bigint,uuid[])',
           pg_get_functiondef('twin.ottoq_sim_advance_wear_counters(uuid,timestamptz,numeric,bigint,uuid[])'::regprocedure))
       ) AS x(n, d);

-- ── (a) the flag ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('twin_operator_publish',
        '0692: how the twin''s deployed cars report to OTTO-Q. 0 (unset, as before) = the twin writes each packet into '
        'OTTO-Q''s table itself; 1 = each car''s operator (sim-a, sim-b) sends com.ottoyard.vehicle.telemetry, and a '
        'fault report for each DTC, through the v2 door under its own key, and the twin''s wear reads its own drive log. '
        'A person''s dial, never the agent''s; set after the research wing''s pair, as a certified change.',
        0, 0, 1,
        'twin.ottoq_sim_advance_deployed_telemetry, twin.ottoq_sim_advance_wear_counters, twin.ottoq_twin_operator_publish (0692)',
        false);

-- ── (b) the drive log ──
CREATE TABLE twin.ottoq_twin_drive_log (
  sim_run_id    uuid        NOT NULL REFERENCES public.ottoq_sim_runs (sim_run_id),
  vehicle_id    uuid        NOT NULL,
  sim_clock_at  timestamptz NOT NULL,
  speed_kmh     numeric     NOT NULL,
  dtc_code      text,
  delivered     boolean     NOT NULL,
  PRIMARY KEY (sim_run_id, vehicle_id, sim_clock_at)
);
COMMENT ON TABLE twin.ottoq_twin_drive_log IS
  '0692: the twin''s own record of each deployed car''s tick, kept when twin_operator_publish is on: the speed it drove, '
  'the DTC it raised, and whether its telemetry reached OTTO-Q. The world reads this, not OTTO-Q''s packets.';
ALTER TABLE twin.ottoq_twin_drive_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE twin.ottoq_twin_drive_log FROM PUBLIC, anon, authenticated;
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('twin', 'ottoq_twin_drive_log', 'sim_run_id', 'engine',
        '0692: what each deployed car did per tick, the twin''s own truth when its operators publish. Goes with its run.');

-- ── (c) the publisher ──
CREATE FUNCTION twin.ottoq_twin_operator_publish(
  p_run uuid, p_clock timestamptz, p_vehicle uuid, p_soc numeric, p_battery_temp numeric, p_speed_kmh numeric,
  p_discharge_kw numeric, p_state text, p_dtc text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = twin, ottoq, public, extensions, pg_temp AS $fn$
DECLARE
  v_veh public.vehicles%ROWTYPE; v_depot uuid; op record; v_seq bigint; v_seed bigint; v_lost boolean; v_ts text;
  v_lat double precision; v_lng double precision; v_air numeric; v_tire numeric; v_signals jsonb; v_events jsonb;
  v_dc record; v_take jsonb; i int;
  c_tel constant text := 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.telemetry.json';
  c_flt constant text := 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.fault.summary.json';
BEGIN
  /* 0692. One deployed car's tick, sent by its operator through the v2 door (docs/TWIN_SENDING_SIDE.md, stages 1-2).
     The twin keeps its own record of the tick first: that is the world, whatever reaches OTTO-Q. */
  SELECT * INTO v_veh FROM public.vehicles WHERE id = p_vehicle;
  SELECT depot_id INTO v_depot FROM public.ottoq_sim_runs WHERE sim_run_id = p_run;
  INSERT INTO twin.ottoq_twin_drive_log (sim_run_id, vehicle_id, sim_clock_at, speed_kmh, dtc_code, delivered)
  VALUES (p_run, p_vehicle, p_clock, COALESCE(p_speed_kmh, 0), p_dtc, true)
  ON CONFLICT (sim_run_id, vehicle_id, sim_clock_at)
  DO UPDATE SET speed_kmh = EXCLUDED.speed_kmh, dtc_code = EXCLUDED.dtc_code, delivered = true;

  SELECT o.source_name, k.key_hash INTO op
    FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
   WHERE o.depot_id = v_depot AND k.is_active AND k.data_source = 'twin'
     AND v_veh.fleet_operator_id = ANY (k.fleet_operator_ids)
   ORDER BY o.source_name LIMIT 1;
  IF op.source_name IS NULL THEN
    -- a car no operator speaks for (the retail cars with no fleet) keeps the old path
    PERFORM ottoq_sim_emit_telemetry(p_vehicle, p_run, p_clock, p_soc, p_battery_temp, p_speed_kmh, p_discharge_kw,
                                     p_state, CASE WHEN p_dtc IS NOT NULL THEN ARRAY[p_dtc] END);
    RETURN jsonb_build_object('path', 'direct', 'reason', 'no_operator');
  END IF;

  -- the old path's loss dice, same seed and salt: a lost packet still used its number, so the door sees the gap
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM public.ottoq_sim_runs WHERE sim_run_id = p_run), '42')
                                 || p_vehicle::text, 42));
  v_lost := ottoq_sim_seeded_random(v_seed, 'integrity:' || p_clock::text)
              < 0.03 * ottoq_profile_rate_mult(p_run, 'telemetry_dropout');
  INSERT INTO twin.ottoq_twin_operator_sequences (sim_run_id, source_name, vehicle_ref, last_seq)
  VALUES (p_run, op.source_name, v_veh.display_name, 1)
  ON CONFLICT (sim_run_id, source_name, vehicle_ref) DO UPDATE SET last_seq = twin.ottoq_twin_operator_sequences.last_seq + 1
  RETURNING last_seq INTO v_seq;
  v_ts := ottoq.ottoq_v2_rfc3339(p_clock);
  v_events := '[]'::jsonb;

  IF v_lost THEN
    UPDATE twin.ottoq_twin_drive_log SET delivered = false
     WHERE sim_run_id = p_run AND vehicle_id = p_vehicle AND sim_clock_at = p_clock;
  ELSE
    SELECT pp.lat, pp.lng INTO v_lat, v_lng
      FROM public.ottoq_vehicle_position(p_vehicle, COALESCE(v_veh.home_depot_id, v_depot), p_run, p_clock) pp;
    v_air := twin.ottoq_sim_site_ambient_c(p_run, p_clock);
    v_signals := '{}'::jsonb;
    IF p_soc IS NOT NULL THEN
      v_signals := v_signals || jsonb_build_object('Vehicle.Powertrain.TractionBattery.StateOfCharge.Current',
                                                   jsonb_build_object('value', p_soc, 'ts', v_ts));
    END IF;
    IF p_discharge_kw IS NOT NULL THEN  -- VSS: positive into the battery
      v_signals := v_signals || jsonb_build_object('Vehicle.Powertrain.TractionBattery.CurrentPower',
                                                   jsonb_build_object('value', -p_discharge_kw * 1000.0, 'ts', v_ts));
    END IF;
    IF p_speed_kmh IS NOT NULL THEN
      v_signals := v_signals || jsonb_build_object('Vehicle.Speed', jsonb_build_object('value', p_speed_kmh, 'ts', v_ts));
    END IF;
    IF p_battery_temp IS NOT NULL THEN
      v_signals := v_signals || jsonb_build_object('Vehicle.Powertrain.TractionBattery.Temperature.Average',
                                                   jsonb_build_object('value', p_battery_temp, 'ts', v_ts));
    END IF;
    IF v_air IS NOT NULL THEN
      v_signals := v_signals || jsonb_build_object('Vehicle.Exterior.AirTemperature', jsonb_build_object('value', v_air, 'ts', v_ts));
    END IF;
    IF v_lat IS NOT NULL AND v_lng IS NOT NULL THEN
      v_signals := v_signals
        || jsonb_build_object('Vehicle.CurrentLocation.Latitude', jsonb_build_object('value', v_lat, 'ts', v_ts))
        || jsonb_build_object('Vehicle.CurrentLocation.Longitude', jsonb_build_object('value', v_lng, 'ts', v_ts));
    END IF;
    -- the four tires together, the old path's draws, psi to kPa (FL, FR, RL, RR)
    FOR i IN 0 .. 3 LOOP
      v_tire := (34 + ottoq_sim_seeded_random(v_seed, 'tire' || i || ':' || p_clock::text) * 4) * 6.894757;
      v_signals := v_signals || jsonb_build_object(
        CASE i WHEN 0 THEN 'Vehicle.Chassis.Axle.Row1.Wheel.Left.Tire.Pressure'
               WHEN 1 THEN 'Vehicle.Chassis.Axle.Row1.Wheel.Right.Tire.Pressure'
               WHEN 2 THEN 'Vehicle.Chassis.Axle.Row2.Wheel.Left.Tire.Pressure'
               ELSE 'Vehicle.Chassis.Axle.Row2.Wheel.Right.Tire.Pressure' END,
        jsonb_build_object('value', round(v_tire, 1), 'ts', v_ts));
    END LOOP;
    v_events := v_events || jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'tel-' || lpad(v_seq::text, 20, '0'),
      'source', 'urn:ottoq:src:' || op.source_name || ':' || v_veh.display_name, 'subject', v_veh.display_name,
      'type', 'com.ottoyard.vehicle.telemetry', 'time', v_ts, 'datacontenttype', 'application/json',
      'dataschema', c_tel, 'sequence', lpad(v_seq::text, 20, '0'), 'data', jsonb_build_object('signals', v_signals)));
  END IF;

  -- a DTC is the operator's own fault code: it travels as a fault report, never in the OBD-II list
  IF p_dtc IS NOT NULL THEN
    SELECT dc.category, dc.severity, dc.title INTO v_dc FROM public.ottoq_dtc_catalog dc WHERE dc.dtc_code = p_dtc;
    UPDATE twin.ottoq_twin_operator_sequences SET last_seq = last_seq + 1
     WHERE sim_run_id = p_run AND source_name = op.source_name AND vehicle_ref = v_veh.display_name
    RETURNING last_seq INTO v_seq;
    v_events := v_events || jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'flt-' || lpad(v_seq::text, 20, '0'),
      'source', 'urn:ottoq:src:' || op.source_name || ':' || v_veh.display_name, 'subject', v_veh.display_name,
      'type', 'com.ottoyard.vehicle.fault.summary', 'time', v_ts, 'datacontenttype', 'application/json',
      'dataschema', c_flt, 'sequence', lpad(v_seq::text, 20, '0'),
      'data', jsonb_strip_nulls(jsonb_build_object(
        'severity', CASE v_dc.severity WHEN 'safety_critical' THEN 'critical' WHEN 'major' THEN 'high'
                                       WHEN 'moderate' THEN 'medium' ELSE 'low' END,
        'category', CASE WHEN v_dc.category IN ('perception', 'sensor') THEN 'sensor_anomaly'
                         WHEN v_dc.category IN ('hardware', 'powertrain') THEN 'vehicle_malfunction'
                         ELSE 'other' END,
        'description', left(v_dc.title, 500),
        'takes_vehicle_offline', false,
        'fault_codes', jsonb_build_array(p_dtc)))));
  END IF;

  IF jsonb_array_length(v_events) = 0 THEN
    RETURN jsonb_build_object('path', 'door', 'operator', op.source_name, 'sequence', v_seq, 'lost', true);
  END IF;
  PERFORM set_config('ottoq.v2_twin_run', p_run::text, true);
  v_take := public.ottoq_v2_take_events(op.key_hash, v_events, false);
  PERFORM set_config('ottoq.v2_twin_run', '', true);
  IF NOT COALESCE((v_take ->> 'ok')::boolean, false) OR COALESCE((v_take ->> 'applied')::int, 0) <> jsonb_array_length(v_events) THEN
    RAISE WARNING 'twin operator %: the door did not apply every event for % at %: %', op.source_name, v_veh.display_name,
      p_clock, v_take;
  END IF;
  RETURN jsonb_build_object('path', 'door', 'operator', op.source_name, 'sequence', v_seq, 'lost', v_lost,
                            'sent', jsonb_array_length(v_events), 'applied', v_take -> 'applied',
                            'refused', v_take -> 'refused');
END $fn$;
COMMENT ON FUNCTION twin.ottoq_twin_operator_publish(uuid,timestamptz,uuid,numeric,numeric,numeric,numeric,text,text) IS
  '0692: one deployed car''s tick, sent by its operator through the v2 door: com.ottoyard.vehicle.telemetry, and a '
  'com.ottoyard.vehicle.fault.summary when the tick raised a DTC. Logs the tick in twin.ottoq_twin_drive_log first.';
REVOKE ALL ON FUNCTION twin.ottoq_twin_operator_publish(uuid,timestamptz,uuid,numeric,numeric,numeric,numeric,text,text)
  FROM PUBLIC, anon, authenticated;

-- ── (d) the deployed tick calls it when the run's flag is on ──
DO $p_deployed$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure);
  a text[] := ARRAY[
$a01$  v_out_drain_pct_h NUMERIC;  -- 0486: SoC points per hour a car is out, beyond what it drives
$a01$,
$a02$  FOR v_dispatch IN
$a02$,
$a03$    PERFORM ottoq_sim_emit_telemetry(
      v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
      v_new_soc, v_battery_temp, v_avg_speed * v_active_frac,
      v_discharge_kw, v_dispatch.v_state::text,
      CASE WHEN v_dtc IS NOT NULL THEN ARRAY[v_dtc] ELSE NULL END);
$a03$];
  b text[] := ARRAY[
$b01$  v_out_drain_pct_h NUMERIC;  -- 0486: SoC points per hour a car is out, beyond what it drives
  v_publish BOOLEAN;  -- 0692: the run's twin_operator_publish flag
$b01$,
$b02$  -- 0692: at twin_operator_publish 1 each car's operator sends its telemetry through the v2 door
  v_publish := ottoq_policy_get(p_sim_run_id, 'twin_operator_publish', 0) >= 1;

  FOR v_dispatch IN
$b02$,
$b03$    IF v_publish THEN
      PERFORM twin.ottoq_twin_operator_publish(
        p_sim_run_id, p_sim_clock_now, v_dispatch.vehicle_id,
        v_new_soc, v_battery_temp, v_avg_speed * v_active_frac,
        v_discharge_kw, v_dispatch.v_state::text, v_dtc);
    ELSE
    PERFORM ottoq_sim_emit_telemetry(
      v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
      v_new_soc, v_battery_temp, v_avg_speed * v_active_frac,
      v_discharge_kw, v_dispatch.v_state::text,
      CASE WHEN v_dtc IS NOT NULL THEN ARRAY[v_dtc] ELSE NULL END);
    END IF;
$b03$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '10c31929ce82ab46f8821401f384b603' THEN
    RAISE EXCEPTION '0692: the deployed tick is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0692: anchor % of the deployed tick occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '97741c8984abf858fa5e5c9bdb1dbb32' THEN
    RAISE EXCEPTION '0692: the deployed tick, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure))
       <> '97741c8984abf858fa5e5c9bdb1dbb32' THEN
    RAISE EXCEPTION '0692: the deployed tick did not read back as written';
  END IF;
END $p_deployed$;

-- ── (e) the wear reads the drive log when the run's flag is on ──
DO $p_wear$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_wear_counters(uuid,timestamptz,numeric,bigint,uuid[])'::regprocedure);
  a text[] := ARRAY[
$a11$  v_attempted    int := 0;  v_written int := 0; v_nseed bigint;
$a11$,
$a12$  IF v_depot IS NULL THEN RETURN 0; END IF;
$a12$,
$a13$           COALESCE((
             SELECT tp.speed_kmh FROM ottoq_telemetry_packets tp
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
              ORDER BY tp.sim_clock_at DESC LIMIT 1), 0) AS speed_kmh,
           COALESCE((
             SELECT ottoq_dtc_severity_rank(dc.severity)
               FROM ottoq_telemetry_packets tp
               CROSS JOIN LATERAL unnest(COALESCE(tp.dtc_codes, ARRAY[]::text[])) AS code
               JOIN ottoq_dtc_catalog dc ON dc.dtc_code = code
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
                AND tp.sim_clock_at > p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
              ORDER BY 1 ASC LIMIT 1), 99) AS tick_worst_rank,
           COALESCE((
             SELECT count(*) FROM ottoq_telemetry_packets tp
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
                AND tp.sim_clock_at > p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
                AND COALESCE(array_length(tp.dtc_codes,1),0) > 0), 0) AS tick_dtc_rows,
$a13$];
  b text[] := ARRAY[
$b11$  v_attempted    int := 0;  v_written int := 0; v_nseed bigint;
  v_publish      boolean;  -- 0692: the run's twin_operator_publish flag
$b11$,
$b12$  IF v_depot IS NULL THEN RETURN 0; END IF;
  -- 0692: at twin_operator_publish 1 the world reads its own drive log, not what reached OTTO-Q
  v_publish := ottoq_policy_get(p_sim_run_id, 'twin_operator_publish', 0) >= 1;
$b12$,
$b13$           CASE WHEN v_publish THEN COALESCE((
             SELECT dl.speed_kmh FROM twin.ottoq_twin_drive_log dl
              WHERE dl.sim_run_id = p_sim_run_id AND dl.vehicle_id = d.vehicle_id
                AND dl.sim_clock_at <= p_sim_clock_now
              ORDER BY dl.sim_clock_at DESC LIMIT 1), 0)
           ELSE
           COALESCE((
             SELECT tp.speed_kmh FROM ottoq_telemetry_packets tp
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
              ORDER BY tp.sim_clock_at DESC LIMIT 1), 0) END AS speed_kmh,
           CASE WHEN v_publish THEN COALESCE((
             SELECT ottoq_dtc_severity_rank(dc.severity)
               FROM twin.ottoq_twin_drive_log dl
               JOIN ottoq_dtc_catalog dc ON dc.dtc_code = dl.dtc_code
              WHERE dl.sim_run_id = p_sim_run_id AND dl.vehicle_id = d.vehicle_id
                AND dl.sim_clock_at <= p_sim_clock_now
                AND dl.sim_clock_at > p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
              ORDER BY 1 ASC LIMIT 1), 99)
           ELSE
           COALESCE((
             SELECT ottoq_dtc_severity_rank(dc.severity)
               FROM ottoq_telemetry_packets tp
               CROSS JOIN LATERAL unnest(COALESCE(tp.dtc_codes, ARRAY[]::text[])) AS code
               JOIN ottoq_dtc_catalog dc ON dc.dtc_code = code
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
                AND tp.sim_clock_at > p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
              ORDER BY 1 ASC LIMIT 1), 99) END AS tick_worst_rank,
           CASE WHEN v_publish THEN COALESCE((
             SELECT count(*) FROM twin.ottoq_twin_drive_log dl
              WHERE dl.sim_run_id = p_sim_run_id AND dl.vehicle_id = d.vehicle_id
                AND dl.sim_clock_at <= p_sim_clock_now
                AND dl.sim_clock_at > p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
                AND dl.dtc_code IS NOT NULL), 0)
           ELSE
           COALESCE((
             SELECT count(*) FROM ottoq_telemetry_packets tp
              WHERE tp.sim_run_id = p_sim_run_id AND tp.vehicle_id = d.vehicle_id
                AND tp.sim_clock_at <= p_sim_clock_now
                AND tp.sim_clock_at > p_sim_clock_now - (p_tick_minutes || ' minutes')::interval
                AND COALESCE(array_length(tp.dtc_codes,1),0) > 0), 0) END AS tick_dtc_rows,
$b13$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'be209981f4f396283047756bf4ab5832' THEN
    RAISE EXCEPTION '0692: the wear counters are not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0692: anchor % of the wear counters occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'ba486da643dddba31a436f8140f6ee0b' THEN
    RAISE EXCEPTION '0692: the wear counters, patched, are not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_wear_counters(uuid,timestamptz,numeric,bigint,uuid[])'::regprocedure))
       <> 'ba486da643dddba31a436f8140f6ee0b' THEN
    RAISE EXCEPTION '0692: the wear counters did not read back as written';
  END IF;
END $p_wear$;

-- ── (f) the research wing's pair ──
INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
   guardrail_alpha, hypothesis, status, sim_min_per_tick, run_after)
VALUES
 ('0692', '11111111-1111-1111-1111-111111111111', 'twin_operator_publish', 0, 1,
  '{}'::jsonb, 'busy_day', 90, '2026-09-01T13:00:00+00:00', 'deployed_car_hours', 'higher',
  6, 12, 0.05, 2, 0.5, 0.2,
  'A measurement, not a tuning (0692 §2). With twin_operator_publish on, each deployed car''s operator sends its '
  'telemetry, and a fault report for each DTC, through the v2 door, and the twin''s wear reads its own drive log. The '
  'pair shows the treatment runs a whole day with no arm error and every event applied, and how much the door''s '
  'differences move what the twin models: OTTO-Q reads a whole-number state of charge, a lost packet no longer reads '
  'to the world as a stopped car, and each DTC reaches OTTO-Q as an open exception. The flag is set by a person as a '
  'certified change; no verdict here is a recommendation. Nothing changes a charge target or a service (rule 9). Arms '
  'at 6 sim-minutes a tick from 8:00 AM CT for 90 ticks, the shipped defaults in both.',
  'active', 6, NULL);

-- ── V1: one synthetic deployed car on a stopped run marked running, three ticks with the flag off and three with it
--        on, each in a block that rolls back ──
CREATE TEMP TABLE p0692 (phase text PRIMARY KEY, r jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.p0692_ticks(p_phase text, p_flag numeric) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_run uuid; v_clock timestamptz; v_veh uuid; v_ref text; v_disp uuid; v_t timestamptz; k int; v_msg text; v_r jsonb;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  -- a car sim-a speaks for
  SELECT v.id, v.display_name INTO v_veh, v_ref
    FROM public.vehicles v
    JOIN public.ottow_api_keys k ON v.fleet_operator_id = ANY (k.fleet_operator_ids)
    JOIN twin.ottoq_twin_operators o ON o.key_id = k.id AND o.source_name = 'sim-a'
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND COALESCE(v.battery_capacity_kwh, 0) > 0 AND k.is_active
   ORDER BY v.display_name LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL THEN RAISE EXCEPTION '0692 V1: no stopped twin run or no sim-a car to probe'; END IF;
  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    IF p_flag IS NOT NULL THEN
      INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
      VALUES ('run', v_run, 'twin_operator_publish', p_flag, '0692_probe', now());
    END IF;
    -- 'returning', so the rule-9 departure check (which guards a new 'active' dispatch) does not judge a synthetic car
    INSERT INTO public.ottoq_vehicle_dispatches
      (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
    VALUES (v_veh, v_run, v_clock, v_clock + interval '3 hours', 180, 90, 'returning')
    RETURNING dispatch_id INTO v_disp;
    v_t := v_clock;
    FOR k IN 1 .. 3 LOOP
      v_t := v_t + interval '5 minutes';
      UPDATE public.ottoq_sim_runs SET sim_clock_current = v_t WHERE sim_run_id = v_run;
      PERFORM count(*) FROM twin.ottoq_sim_advance_deployed_telemetry(v_run, v_t, 5);
    END LOOP;
    -- the fault path, straight through the publisher, on the same car
    IF p_flag IS NOT NULL THEN
      v_t := v_t + interval '5 minutes';
      UPDATE public.ottoq_sim_runs SET sim_clock_current = v_t WHERE sim_run_id = v_run;
      PERFORM twin.ottoq_twin_operator_publish(v_run, v_t, v_veh, 80, 30, 40, 9, 'deployed',
                (SELECT dtc_code FROM public.ottoq_dtc_catalog WHERE category = 'sensor' ORDER BY dtc_code LIMIT 1));
    END IF;
    -- and the wear over the same car, which reads the drive log at 1 and the packets at 0
    PERFORM twin.ottoq_sim_advance_wear_counters(v_run, v_t, 5, 0, ARRAY[v_disp]);
    v_r := jsonb_build_object(
      'run', v_run, 'car', v_ref,
      'drive_log', (SELECT count(*) FROM twin.ottoq_twin_drive_log WHERE sim_run_id = v_run AND vehicle_id = v_veh),
      'delivered', (SELECT count(*) FROM twin.ottoq_twin_drive_log WHERE sim_run_id = v_run AND vehicle_id = v_veh AND delivered),
      'inbox_telemetry_applied', (SELECT count(*) FROM public.ottoq_v2_inbox i WHERE i.sim_run_id = v_run AND i.vehicle_id = v_veh
                                    AND i.ce_type = 'com.ottoyard.vehicle.telemetry' AND i.disposition = 'applied'),
      'inbox_fault_applied', (SELECT count(*) FROM public.ottoq_v2_inbox i WHERE i.sim_run_id = v_run AND i.vehicle_id = v_veh
                                AND i.ce_type = 'com.ottoyard.vehicle.fault.summary' AND i.disposition = 'applied'),
      'fault_exceptions_on_run', (SELECT count(*) FROM public.exceptions e WHERE e.vehicle_id = v_veh AND e.sim_run_id = v_run),
      'packets', (SELECT count(*) FROM public.ottoq_telemetry_packets t WHERE t.sim_run_id = v_run AND t.vehicle_id = v_veh
                    AND t.sim_clock_at > v_clock),
      'packets_full_with_speed', (SELECT count(*) FROM public.ottoq_telemetry_packets t WHERE t.sim_run_id = v_run
                                    AND t.vehicle_id = v_veh AND t.sim_clock_at > v_clock
                                    AND t.packet_integrity = 'full' AND t.speed_kmh IS NOT NULL),
      'positions_outside_geofence', (SELECT count(*) FROM public.ottoq_telemetry_packets t
                                       JOIN public.depots dp ON dp.id = '11111111-1111-1111-1111-111111111111'
                                      WHERE t.sim_run_id = v_run AND t.vehicle_id = v_veh AND t.sim_clock_at > v_clock
                                        AND t.current_lat IS NOT NULL
                                        AND NOT ST_Covers(dp.geofence, ST_SetSRID(ST_MakePoint(t.current_lng::float8,
                                                                                    t.current_lat::float8), 4326)::geography)),
      'soc_applied', (SELECT count(*) FROM public.ottoq_v2_inbox i WHERE i.sim_run_id = v_run AND i.vehicle_id = v_veh
                        AND i.ce_type = 'com.ottoyard.vehicle.telemetry' AND i.detail ->> 'soc' LIKE 'applied%'),
      'gaps', (SELECT COALESCE(sum(c.gaps), 0) FROM public.ottoq_v2_cursors c WHERE c.sim_run_id = v_run
                 AND c.ce_source = 'urn:ottoq:src:sim-a:' || v_ref),
      'positions_dropped', (SELECT count(*) FROM public.ottoq_v2_inbox i WHERE i.sim_run_id = v_run AND i.vehicle_id = v_veh
                              AND i.detail ->> 'location' = 'dropped_outside_geofence'));
    RAISE EXCEPTION '0692 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0692 PROBED' THEN RAISE EXCEPTION '0692 probe % failed: %', p_phase, v_msg; END IF;
  INSERT INTO p0692 VALUES (p_phase, v_r);
END $fn$;

DO $v1$
DECLARE v_off jsonb; v_on jsonb;
BEGIN
  PERFORM pg_temp.p0692_ticks('off', NULL);
  PERFORM pg_temp.p0692_ticks('on', 1);
  SELECT r INTO v_off FROM p0692 WHERE phase = 'off';
  SELECT r INTO v_on FROM p0692 WHERE phase = 'on';
  -- at 0: the old path, untouched
  IF (v_off ->> 'drive_log')::int <> 0 OR (v_off ->> 'inbox_telemetry_applied')::int <> 0 OR (v_off ->> 'packets')::int <> 3 THEN
    RAISE EXCEPTION '0692 V1 FAILED: with the flag unset the tick did not take the old path: %', v_off;
  END IF;
  -- at 1: every tick logged; every delivered tick applied by the door as a packet the door wrote, its charge applied;
  -- the fault applied, an exception on the run; no position outside the depot kept; a lost tick is never a packet, and
  -- shows as a gap unless it was the car's first event (a first event has no predecessor to measure from)
  IF (v_on ->> 'drive_log')::int <> 4
     OR (v_on ->> 'inbox_telemetry_applied')::int <> (v_on ->> 'delivered')::int
     OR (v_on ->> 'packets')::int <> (v_on ->> 'delivered')::int
     OR (v_on ->> 'packets_full_with_speed')::int <> (v_on ->> 'packets')::int
     OR (v_on ->> 'delivered')::int < 3
     OR (v_on ->> 'inbox_fault_applied')::int <> 1 OR (v_on ->> 'fault_exceptions_on_run')::int <> 1
     OR (v_on ->> 'positions_outside_geofence')::int <> 0
     OR (v_on ->> 'soc_applied')::int <> (v_on ->> 'delivered')::int
     OR (v_on ->> 'gaps')::numeric > 4 - (v_on ->> 'delivered')::int THEN
    RAISE EXCEPTION '0692 V1 FAILED: with the flag on: %', v_on;
  END IF;
  RAISE NOTICE '0692 V1 PASSED: flag unset, three ticks took the old path (3 packets, no drive log, no inbox); flag on, % (all rolled back)', v_on;
END $v1$;

-- ── V2: the definitions as written, the flag set nowhere, the experiment as written, the purge's check still passes ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure))
       <> '97741c8984abf858fa5e5c9bdb1dbb32'
     OR md5(pg_get_functiondef('twin.ottoq_sim_advance_wear_counters(uuid,timestamptz,numeric,bigint,uuid[])'::regprocedure))
       <> 'ba486da643dddba31a436f8140f6ee0b' THEN
    RAISE EXCEPTION '0692 V2 FAILED: a patched definition is not as written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_operator_publish') THEN
    RAISE EXCEPTION '0692 V2 FAILED: the flag is set somewhere';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_dial_experiments e JOIN public.ottoq_policy_param_catalog c USING (param_key)
                  WHERE e.created_by = '0692' AND e.status = 'active' AND e.param_key = 'twin_operator_publish'
                    AND e.control_value BETWEEN c.min_value AND c.max_value
                    AND e.treatment_value BETWEEN c.min_value AND c.max_value) THEN
    RAISE EXCEPTION '0692 V2 FAILED: the experiment is not active with its dial in range';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block') THEN
    RAISE EXCEPTION '0692 V2 FAILED: the run-scope registry reports a blocking defect, so the purge would refuse';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0692_the_twins_operators_send_telemetry_and_faults_through_the_door', false, false,
  'Stages 1-2 of the twin''s sending side: the flag twin_operator_publish, the twin''s drive log, the publisher (telemetry '
  'and a fault report per DTC through the v2 door under each operator''s key), and the deployed tick and the wear '
  'counters reading the flag; the pair registered. The flag is set nowhere and at 0 both functions take their old body '
  '(V1): FALSE/FALSE. Setting it is a certified change after the pair.',
  now());

COMMIT;
