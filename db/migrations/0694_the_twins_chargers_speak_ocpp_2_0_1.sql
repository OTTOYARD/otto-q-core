-- migration-version: PENDING
-- migration-name:    the_twins_chargers_speak_ocpp_2_0_1
--
-- 0694  **The twin's chargers write what an OCPP 2.0.1 station sends, and the charge clock reads either shape.**
--        FINDINGS G412; step 5 of the twin data contract review: "Real OCPP ... speaking OCPP 2.0.1
--        (TransactionEvent, SetChargingProfile). Retires the 1.6 message names."
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_ocpp_messages labels every row 2.0.1, and the twin writes it in OCPP 1.6: StartTransaction,
--   in-transaction MeterValues and StopTransaction, none of which exist in 2.0.1, where a charge is one transaction
--   told as TransactionEvent Started, Updated and Ended with a seqNo counting from 0 and its meter values inside. Its
--   Authorize carries a timestamp 2.0.1 forbids (the request admits idToken, certificate and hash data only), and its
--   meter readings carry a Temperature measurand 2.0.1 dropped. Checked against the OCPP 2.0.1 JSON schemas the
--   `ocpp` library 2.1.0 ships (requirements.txt), 2026-10-10.
--
--   Read 2026-10-10, comment-stripped: one function writes the log, twin.ottoq_sim_emit_ocpp, from seven calls in the
--   twin's start, advance and stop charge-session steps; one function reads it, public.ottoq_charge_time_v2_params_cut,
--   which finds the first in-transaction reading at or past a cut of a charge's state of charge ("the charge in
--   progress"), from MeterValues rows only, the state of charge at sample index 1. No view reads the table, and no
--   cockpit (the twin app and field ops name StopTransaction in comments only). The v1 ingest's ocpp stream stores
--   whatever type a sender gives and is not touched.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Five helpers in twin build 2.0.1 payloads: a sampled value (value, measurand, unitOfMeasure), a list of them,
--       a TransactionEvent request (eventType, timestamp, triggerReason, seqNo, transactionInfo, evse, meterValue,
--       idToken when it opens, customData for the twin's own facts under vendorId com.ottoyard.twin), the next seqNo
--       of a session (its TransactionEvents so far), and the trigger and stopped reason an end takes from the spec's
--       lists: completed (the car reached its target) ChargingStateChanged / SOCLimitReached; a fault AbnormalCondition
--       / GroundFault for the ground fault, Other for the rest; the orphan sweep EVDeparted / EVDisconnected; anything
--       else (sim_reset) RemoteStop / Remote. The twin's own reason is kept in customData.
--   (b) Start: Authorize carries the token only, and StartTransaction becomes TransactionEvent Started (seqNo 0,
--       CablePluggedIn) with the register at 0 kWh and the car's charge; its target and the air go in customData.
--   (c) Advance: each MeterValues becomes TransactionEvent Updated (MeterValuePeriodic) with the power, the car's
--       charge, the tick's energy and the register; the battery's temperature and a fault's warning go in customData.
--   (d) Stop: StopTransaction becomes TransactionEvent Ended with the register, the car's charge, timeSpentCharging and
--       the reasons of (a). The two StatusNotifications are already 2.0.1's shape and stay.
--   (e) ottoq.ottoq_ocpp_meter_soc(type, payload): a reading's state of charge from either shape (1.6 MeterValues at
--       sample index 1, exactly the old test; 2.0.1 TransactionEvent Updated by measurand), and the charge clock's
--       lookup reads it. Started and Ended carry a charge too and are not read, as StartTransaction and StopTransaction
--       were not.
--
--   Every value written is the value written before; only the shape and the names change.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   No determinism atom reads the log (the census in §1), and the one reader returns the same reading from either
--   shape: on every 1.6 row by construction (V1 checks the latest run's rows one by one), and on a 2.0.1 Updated the
--   same value the 1.6 row carried (V1 opens, advances and closes a charge and reads it back). So the clock's fit is
--   the same fit (V1 fits three days before and after the change and requires the two equal), the seating that reads
--   it decides the same, and no evidence regime is recorded: the clock's evidence, the numbers, did not change. G412
--   planned a regime and a recertification for this change; reading the reader showed neither is needed. The next
--   nightly fit's code_md5 changes, as it records which code fitted it; nothing reads code_md5 to choose a fit.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the four definitions in ottoq_schema_snapshots WHERE label = '0694_pre'. The helpers stay (dropping needs
--   a person at the connector's prompt) and nothing calls them once the definitions are restored. Rows written in the
--   2.0.1 shape stay readable by the restored reader only if it is given (e) again, so restore the reader last.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0694 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0693_a_car_leaving_the_depot_is_reported_through_the_door') THEN
    RAISE EXCEPTION '0694 P1: 0693 is not classified; apply in order';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure))
       <> '760276583a77df0e79df3cfebddc063b'
     OR md5(pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure))
       <> 'aa3ec3f7c31c49bd2790a88ebf3895c8'
     OR md5(pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure))
       <> 'e8b2c931cf4e7c944d8a09f0076eaa0b' THEN
    RAISE EXCEPTION '0694 P1: a charge-session step is not the definition this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_charge_time_v2_params_cut(uuid,timestamptz,interval,numeric,jsonb)'::regprocedure))
       <> '11e0fbdfb806672d669854d470649347' THEN
    RAISE EXCEPTION '0694 P1: the charge clock''s reader is not the definition this file patches';
  END IF;
  -- the writer the seven calls go through, unchanged
  IF md5(pg_get_functiondef('twin.ottoq_sim_emit_ocpp(uuid,uuid,uuid,uuid,timestamptz,text,text,jsonb)'::regprocedure))
       <> '3a421ca5eaa88616bd0b41acaf7c22d9' THEN
    RAISE EXCEPTION '0694 P1: twin.ottoq_sim_emit_ocpp is not the writer this file was written against';
  END IF;
  IF to_regprocedure('twin.ottoq_ocpp201_sample(text,numeric,text)') IS NOT NULL
     OR to_regprocedure('twin.ottoq_ocpp201_samples(jsonb[])') IS NOT NULL
     OR to_regprocedure('twin.ottoq_ocpp201_tx_event(text,text,integer,text,timestamptz,text,jsonb,jsonb,text,text,integer)') IS NOT NULL
     OR to_regprocedure('twin.ottoq_ocpp201_next_seq(uuid)') IS NOT NULL
     OR to_regprocedure('twin.ottoq_ocpp201_ended_reasons(text)') IS NOT NULL
     OR to_regprocedure('ottoq.ottoq_ocpp_meter_soc(text,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION '0694 P1: a helper this file creates exists already';
  END IF;
  -- the reader's new branch matches nothing yet, so every fit it has made it makes again
  IF EXISTS (SELECT 1 FROM public.ottoq_ocpp_messages WHERE message_type = 'TransactionEvent') THEN
    RAISE EXCEPTION '0694 P1: the log holds TransactionEvent rows already; this file was written when it held none';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0694 P1: a run is live; apply between runs';
  END IF;
END $premises$;

-- ── snapshots ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0694_pre', 'function', x.s, x.n, x.d, md5(x.d)
  FROM (VALUES
          ('twin', 'ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)',
           pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure)),
          ('twin', 'ottoq_sim_advance_charge_sessions(uuid,timestamptz)',
           pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure)),
          ('twin', 'ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)',
           pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure)),
          ('public', 'ottoq_charge_time_v2_params_cut(uuid,timestamptz,interval,numeric,jsonb)',
           pg_get_functiondef('public.ottoq_charge_time_v2_params_cut(uuid,timestamptz,interval,numeric,jsonb)'::regprocedure))
       ) AS x(s, n, d);

-- ── the clock's fit over the last three days, before the reader changes (compared in V1a) ──
CREATE TEMP TABLE p0694 (k text PRIMARY KEY, v jsonb) ON COMMIT DROP;
INSERT INTO p0694
SELECT 'fit_before', public.ottoq_charge_time_v2_params('11111111-1111-1111-1111-111111111111', now(), interval '3 days', 3);

-- ── (a) the 2.0.1 payload helpers ──
CREATE FUNCTION twin.ottoq_ocpp201_sample(p_measurand text, p_value numeric, p_unit text)
RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
  -- 0694: one OCPP 2.0.1 SampledValue; NULL when there is no value to send (2.0.1 requires value)
  SELECT CASE WHEN p_value IS NULL THEN NULL
              ELSE jsonb_build_object('value', p_value, 'measurand', p_measurand,
                                      'unitOfMeasure', jsonb_build_object('unit', p_unit)) END
$fn$;

CREATE FUNCTION twin.ottoq_ocpp201_samples(p_samples jsonb[])
RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
  -- 0694: the sampled values that have a value, in the order given
  SELECT COALESCE(jsonb_agg(u.s ORDER BY u.o), '[]'::jsonb)
    FROM unnest(p_samples) WITH ORDINALITY AS u(s, o)
   WHERE u.s IS NOT NULL
$fn$;

CREATE FUNCTION twin.ottoq_ocpp201_tx_event(
  p_event_type text, p_trigger text, p_seq_no integer, p_transaction_id text, p_at timestamptz,
  p_charging_state text, p_samples jsonb, p_custom jsonb DEFAULT NULL, p_id_token text DEFAULT NULL,
  p_stopped_reason text DEFAULT NULL, p_time_spent_s integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE PARALLEL SAFE AS $fn$
  -- 0694 (G412): a TransactionEvent request as an OCPP 2.0.1 station sends it: one EVSE, one connector; the twin's
  -- own facts in customData, the spec's vendor extension
  SELECT jsonb_build_object(
           'eventType', p_event_type, 'timestamp', p_at, 'triggerReason', p_trigger, 'seqNo', p_seq_no,
           'transactionInfo', jsonb_strip_nulls(jsonb_build_object(
             'transactionId', p_transaction_id, 'chargingState', p_charging_state,
             'stoppedReason', p_stopped_reason, 'timeSpentCharging', p_time_spent_s)),
           'evse', jsonb_build_object('id', 1, 'connectorId', 1),
           'meterValue', jsonb_build_array(jsonb_build_object('timestamp', p_at, 'sampledValue', p_samples)))
      || CASE WHEN p_id_token IS NULL THEN '{}'::jsonb
              ELSE jsonb_build_object('idToken', jsonb_build_object('idToken', p_id_token, 'type', 'ISO14443')) END
      || CASE WHEN p_custom IS NULL THEN '{}'::jsonb
              ELSE jsonb_build_object('customData',
                     jsonb_build_object('vendorId', 'com.ottoyard.twin') || jsonb_strip_nulls(p_custom)) END
$fn$;

CREATE FUNCTION twin.ottoq_ocpp201_next_seq(p_session uuid)
RETURNS integer LANGUAGE sql STABLE AS $fn$
  -- 0694: a transaction's events count up from 0 (Started), one for each event the session has sent
  SELECT count(*)::int FROM public.ottoq_ocpp_messages m
   WHERE m.ocpp_session_id = p_session AND m.message_type = 'TransactionEvent'
$fn$;

CREATE FUNCTION twin.ottoq_ocpp201_ended_reasons(p_reason text, OUT trigger_reason text, OUT stopped_reason text)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
  -- 0694: the twin's reason for ending a charge, as 2.0.1's TriggerReasonEnumType and ReasonEnumType
  SELECT CASE WHEN p_reason = 'completed' THEN 'ChargingStateChanged'
              WHEN p_reason LIKE 'fault%' THEN 'AbnormalCondition'
              WHEN p_reason = 'vehicle_departed_orphan_sweep' THEN 'EVDeparted'
              ELSE 'RemoteStop' END,
         CASE WHEN p_reason = 'completed' THEN 'SOCLimitReached'
              WHEN p_reason = 'fault.ground_fault_safety' THEN 'GroundFault'
              WHEN p_reason LIKE 'fault%' THEN 'Other'
              WHEN p_reason = 'vehicle_departed_orphan_sweep' THEN 'EVDisconnected'
              ELSE 'Remote' END
$fn$;

-- ── (e) a reading's state of charge, from either shape ──
CREATE FUNCTION ottoq.ottoq_ocpp_meter_soc(p_message_type text, p_payload jsonb)
RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
  -- 0694: the state of charge of an in-transaction meter reading. OCPP 1.6 MeterValues, as the twin wrote them before
  -- 0694: the second sample, exactly the test the charge clock made. OCPP 2.0.1 TransactionEvent Updated: the sample
  -- whose measurand is SoC. Anything else, Started and Ended included, is not an in-transaction reading: NULL.
  SELECT CASE
    WHEN p_message_type = 'MeterValues' AND p_payload -> 'sampledValue' -> 1 ->> 'measurand' = 'SoC'
      THEN (p_payload -> 'sampledValue' -> 1 ->> 'value')::numeric
    WHEN p_message_type = 'TransactionEvent' AND p_payload ->> 'eventType' = 'Updated'
         AND jsonb_typeof(p_payload -> 'meterValue' -> 0 -> 'sampledValue') = 'array'
      THEN (SELECT (sv ->> 'value')::numeric
              FROM jsonb_array_elements(p_payload -> 'meterValue' -> 0 -> 'sampledValue') sv
             WHERE sv ->> 'measurand' = 'SoC'
             LIMIT 1)
  END
$fn$;

COMMENT ON FUNCTION twin.ottoq_ocpp201_tx_event(text,text,integer,text,timestamptz,text,jsonb,jsonb,text,text,integer) IS
  '0694 (G412): an OCPP 2.0.1 TransactionEvent request as the twin''s chargers send it.';
COMMENT ON FUNCTION ottoq.ottoq_ocpp_meter_soc(text,jsonb) IS
  '0694: the state of charge of an in-transaction meter reading, from OCPP 1.6 MeterValues or OCPP 2.0.1 TransactionEvent Updated.';
REVOKE ALL ON FUNCTION twin.ottoq_ocpp201_sample(text,numeric,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION twin.ottoq_ocpp201_samples(jsonb[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION twin.ottoq_ocpp201_tx_event(text,text,integer,text,timestamptz,text,jsonb,jsonb,text,text,integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION twin.ottoq_ocpp201_next_seq(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION twin.ottoq_ocpp201_ended_reasons(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ottoq.ottoq_ocpp_meter_soc(text,jsonb) FROM PUBLIC, anon, authenticated;

-- ── (b) start ──
DO $p_start$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure);
  a text[] := ARRAY[
$a01$  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'Authorize', jsonb_build_object('idToken', jsonb_build_object('idToken', 'TWIN-' || substr(p_vehicle_id::text, 1, 8), 'type', 'ISO14443'), 'timestamp', v_clock));
  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StartTransaction', jsonb_build_object('connectorId', 1, 'idTag', 'TWIN-' || substr(p_vehicle_id::text, 1, 8),
      'meterStart', 0, 'soc_start_pct', v_vehicle.current_soc, 'target_soc_pct', v_target_soc, 'timestamp', v_clock, 'ambient_temp_c', v_ambient_temp));
$a01$];
  b text[] := ARRAY[
$b01$  -- 0694 (G412): what an OCPP 2.0.1 station sends. Authorize carries the token and nothing else; the transaction opens
  -- as TransactionEvent Started (seqNo 0) with the register at zero and the car's charge; the car's target and the air
  -- ride in customData
  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'Authorize', jsonb_build_object('idToken', jsonb_build_object('idToken', 'TWIN-' || substr(p_vehicle_id::text, 1, 8), 'type', 'ISO14443')));
  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
      'Started', 'CablePluggedIn', 0, (SELECT s.transaction_id FROM ocpp_sessions s WHERE s.id = v_session_id),
      v_clock, 'Charging',
      twin.ottoq_ocpp201_samples(ARRAY[
        twin.ottoq_ocpp201_sample('Energy.Active.Import.Register', 0, 'kWh'),
        twin.ottoq_ocpp201_sample('SoC', v_vehicle.current_soc, 'Percent')]),
      jsonb_build_object('target_soc_pct', v_target_soc, 'ambient_temp_c', v_ambient_temp),
      'TWIN-' || substr(p_vehicle_id::text, 1, 8)));
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '760276583a77df0e79df3cfebddc063b' THEN
    RAISE EXCEPTION '0694: the charge start is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0694: anchor % of the charge start occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '05d725246fd41da9895c173f161e705f' THEN
    RAISE EXCEPTION '0694: the charge start, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure))
       <> '05d725246fd41da9895c173f161e705f' THEN
    RAISE EXCEPTION '0694: the charge start did not read back as written';
  END IF;
END $p_start$;

-- ── (c) advance ──
DO $p_advance$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure);
  a text[] := ARRAY[
$a01$      PERFORM ottoq_sim_emit_ocpp(v_session.id, v_session.ocpp_charger_id, v_session.vehicle_id,
        p_sim_run_id, p_sim_clock_now, 'cs_to_csms', 'MeterValues', jsonb_build_object(
          'connectorId', 1, 'transactionId', v_session.transaction_id,
          'sampledValue', jsonb_build_array(
            jsonb_build_object('value', v_rate_kw, 'measurand', 'Power.Active.Import', 'unit', 'kW'),
            jsonb_build_object('value', v_new_soc, 'measurand', 'SoC', 'unit', 'Percent'),
            jsonb_build_object('value', v_battery_temp, 'measurand', 'Temperature', 'unit', 'Celsius', 'location', 'battery')),
          'fault_imminent', TRUE, 'timestamp', p_sim_clock_now));
$a01$,
$a02$    PERFORM ottoq_sim_emit_ocpp(v_session.id, v_session.ocpp_charger_id, v_session.vehicle_id,
      p_sim_run_id, p_sim_clock_now, 'cs_to_csms', 'MeterValues', jsonb_build_object(
        'connectorId', 1, 'transactionId', v_session.transaction_id,
        'sampledValue', jsonb_build_array(
          jsonb_build_object('value', v_rate_kw, 'measurand', 'Power.Active.Import', 'unit', 'kW'),
          jsonb_build_object('value', v_new_soc, 'measurand', 'SoC', 'unit', 'Percent'),
          jsonb_build_object('value', v_kwh_delta, 'measurand', 'Energy.Active.Import.Interval', 'unit', 'kWh'),
          jsonb_build_object('value', v_battery_temp, 'measurand', 'Temperature', 'unit', 'Celsius', 'location', 'battery')),
        'timestamp', p_sim_clock_now));
$a02$];
  b text[] := ARRAY[
$b01$      -- 0694 (G412): the reading before the fault, as an OCPP 2.0.1 station sends it; the warning rides in customData
      PERFORM ottoq_sim_emit_ocpp(v_session.id, v_session.ocpp_charger_id, v_session.vehicle_id,
        p_sim_run_id, p_sim_clock_now, 'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
          'Updated', 'MeterValuePeriodic', twin.ottoq_ocpp201_next_seq(v_session.id), v_session.transaction_id,
          p_sim_clock_now, 'Charging',
          twin.ottoq_ocpp201_samples(ARRAY[
            twin.ottoq_ocpp201_sample('Power.Active.Import', v_rate_kw, 'kW'),
            twin.ottoq_ocpp201_sample('SoC', v_new_soc, 'Percent')]),
          jsonb_build_object('battery_temp_c', v_battery_temp, 'fault_imminent', true)));
$b01$,
$b02$    -- 0694 (G412): each tick's reading as an OCPP 2.0.1 station sends it, TransactionEvent Updated with the power, the
    -- car's charge, the tick's energy and the register; the battery's temperature (2.0.1 has no such measurand) rides
    -- in customData
    PERFORM ottoq_sim_emit_ocpp(v_session.id, v_session.ocpp_charger_id, v_session.vehicle_id,
      p_sim_run_id, p_sim_clock_now, 'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
        'Updated', 'MeterValuePeriodic', twin.ottoq_ocpp201_next_seq(v_session.id), v_session.transaction_id,
        p_sim_clock_now, 'Charging',
        twin.ottoq_ocpp201_samples(ARRAY[
          twin.ottoq_ocpp201_sample('Power.Active.Import', v_rate_kw, 'kW'),
          twin.ottoq_ocpp201_sample('SoC', v_new_soc, 'Percent'),
          twin.ottoq_ocpp201_sample('Energy.Active.Import.Interval', v_kwh_delta, 'kWh'),
          twin.ottoq_ocpp201_sample('Energy.Active.Import.Register',
                                    COALESCE(v_session.energy_delivered_kwh, 0) + v_kwh_delta, 'kWh')]),
        jsonb_build_object('battery_temp_c', v_battery_temp)));
$b02$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'aa3ec3f7c31c49bd2790a88ebf3895c8' THEN
    RAISE EXCEPTION '0694: the charge advance is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0694: anchor % of the charge advance occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'c26a997e1c8cab101d275c868d87db1d' THEN
    RAISE EXCEPTION '0694: the charge advance, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure))
       <> 'c26a997e1c8cab101d275c868d87db1d' THEN
    RAISE EXCEPTION '0694: the charge advance did not read back as written';
  END IF;
END $p_advance$;

-- ── (d) stop ──
DO $p_stop$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure);
  a text[] := ARRAY[
$a01$  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StopTransaction', jsonb_build_object(
      'transactionId', v_session.transaction_id,
      'meterStop', v_session.energy_delivered_kwh,
      'soc_end_pct', v_vehicle.current_soc, 'reason', p_reason,
      'energy_delivered_kwh', v_session.energy_delivered_kwh,
      'duration_seconds', v_duration_s, 'timestamp', v_clock));
$a01$];
  b text[] := ARRAY[
$b01$  -- 0694 (G412): the transaction ends as an OCPP 2.0.1 station ends it, TransactionEvent Ended, with the register, the
  -- car's charge, the time it charged, and a trigger and stopped reason from the spec's lists; the twin's own reason
  -- rides in customData
  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
      'Ended', (twin.ottoq_ocpp201_ended_reasons(p_reason)).trigger_reason, twin.ottoq_ocpp201_next_seq(p_session_id),
      v_session.transaction_id, v_clock, 'Idle',
      twin.ottoq_ocpp201_samples(ARRAY[
        twin.ottoq_ocpp201_sample('Energy.Active.Import.Register', v_session.energy_delivered_kwh, 'kWh'),
        twin.ottoq_ocpp201_sample('SoC', v_vehicle.current_soc, 'Percent')]),
      jsonb_build_object('twin_reason', p_reason, 'duration_seconds', v_duration_s),
      NULL, (twin.ottoq_ocpp201_ended_reasons(p_reason)).stopped_reason, round(v_duration_s)::int));
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'e8b2c931cf4e7c944d8a09f0076eaa0b' THEN
    RAISE EXCEPTION '0694: the charge stop is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0694: anchor % of the charge stop occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '2281c70b3b5d7cc39f3026bf2b09b4cd' THEN
    RAISE EXCEPTION '0694: the charge stop, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure))
       <> '2281c70b3b5d7cc39f3026bf2b09b4cd' THEN
    RAISE EXCEPTION '0694: the charge stop did not read back as written';
  END IF;
END $p_stop$;

-- ── (e) the charge clock's reader takes either shape ──
DO $p_reader$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_charge_time_v2_params_cut(uuid,timestamptz,interval,numeric,jsonb)'::regprocedure);
  a text[] := ARRAY[
$a01$        SELECT mm.sim_clock_at AS t_at, (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric AS soc_at
          FROM ottoq_ocpp_messages mm
         WHERE mm.ocpp_session_id = cut.sid AND mm.message_type = 'MeterValues'
           AND (mm.payload -> 'sampledValue' -> 1 ->> 'measurand') = 'SoC'
           AND (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric >= cut.soc_cut
$a01$];
  b text[] := ARRAY[
$b01$        -- 0694 (G412): an in-transaction reading in either shape, OCPP 1.6 MeterValues or 2.0.1 TransactionEvent Updated
        SELECT mm.sim_clock_at AS t_at, ottoq.ottoq_ocpp_meter_soc(mm.message_type, mm.payload) AS soc_at
          FROM ottoq_ocpp_messages mm
         WHERE mm.ocpp_session_id = cut.sid AND mm.message_type IN ('MeterValues', 'TransactionEvent')
           AND ottoq.ottoq_ocpp_meter_soc(mm.message_type, mm.payload) >= cut.soc_cut
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '11e0fbdfb806672d669854d470649347' THEN
    RAISE EXCEPTION '0694: the charge clock''s reader is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0694: anchor % of the charge clock''s reader occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '9e6f1694936726fd47338b75bd9345c1' THEN
    RAISE EXCEPTION '0694: the charge clock''s reader, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.ottoq_charge_time_v2_params_cut(uuid,timestamptz,interval,numeric,jsonb)'::regprocedure))
       <> '9e6f1694936726fd47338b75bd9345c1' THEN
    RAISE EXCEPTION '0694: the charge clock''s reader did not read back as written';
  END IF;
END $p_reader$;

-- ── V1a: the reader reads every stored reading as it did, and the clock fits the same three days to the same fit ──
DO $v1a$
DECLARE v_run uuid; v_rows bigint; v_diff bigint; v_before jsonb; v_after jsonb;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed'
     AND EXISTS (SELECT 1 FROM public.ottoq_ocpp_messages m WHERE m.sim_run_id = r.sim_run_id AND m.message_type = 'MeterValues')
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  SELECT count(*),
         count(*) FILTER (WHERE ottoq.ottoq_ocpp_meter_soc(m.message_type, m.payload) IS DISTINCT FROM
                                CASE WHEN (m.payload -> 'sampledValue' -> 1 ->> 'measurand') = 'SoC'
                                     THEN (m.payload -> 'sampledValue' -> 1 ->> 'value')::numeric END)
    INTO v_rows, v_diff
    FROM public.ottoq_ocpp_messages m
   WHERE m.sim_run_id = v_run AND m.message_type = 'MeterValues';
  IF v_run IS NULL OR v_rows = 0 OR v_diff <> 0 THEN
    RAISE EXCEPTION '0694 V1 FAILED: the reader read % of % stored readings of run % differently', v_diff, v_rows, v_run;
  END IF;
  SELECT v INTO v_before FROM p0694 WHERE k = 'fit_before';
  v_after := public.ottoq_charge_time_v2_params('11111111-1111-1111-1111-111111111111', now(), interval '3 days', 3);
  IF jsonb_typeof(v_before) IS DISTINCT FROM 'object' OR v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION '0694 V1 FAILED: the clock''s fit over the last three days changed with the reader';
  END IF;
  RAISE NOTICE '0694 V1a PASSED: % stored readings of run % read the same; the three-day fit (% charges, % runs) is the same fit',
    v_rows, v_run, v_after #>> '{diagnostics,n}', v_after #>> '{diagnostics,runs}';
END $v1a$;

-- ── V1b: a charge opened, advanced and closed on a stopped run marked running, in a block that rolls back ──
CREATE FUNCTION pg_temp.p0694_session() RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  v_run uuid; v_clock timestamptz; v_veh uuid; v_stall uuid; v_charger uuid; v_sid uuid; v_tx text;
  v_r jsonb; v_msg text; i int;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  -- a free L2 stall whose charger is not faulted
  SELECT s.id, s.ocpp_charger_id INTO v_stall, v_charger
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'l2'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.vehicles x WHERE x.current_stall_id = s.id)
     AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions o WHERE o.stall_id = s.id AND o.status = 'active')
     AND c.station_state IS DISTINCT FROM 'Faulted'
   ORDER BY s.stall_code, s.id LIMIT 1;
  -- a car with a battery, no charge under way, and no stall holding it
  SELECT v.id INTO v_veh
    FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND COALESCE(v.battery_capacity_kwh, 0) > 0
     AND v.fleet_operator_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions o WHERE o.vehicle_id = v.id AND o.status = 'active')
     AND NOT EXISTS (SELECT 1 FROM public.stalls st WHERE st.current_vehicle_id = v.id OR st.reserved_by = v.id)
   ORDER BY v.display_name LIMIT 1;
  IF v_run IS NULL OR v_stall IS NULL OR v_veh IS NULL THEN
    RAISE EXCEPTION '0694 V1: no stopped twin run, no free L2 stall or no car to probe';
  END IF;
  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    -- the charger heard from at the run's clock, as the tick stamps it before its charge steps (0424)
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = v_clock WHERE charger_id = v_charger;
    UPDATE public.vehicles
       SET current_soc = 50, current_state = 'staged_awaiting_service', current_stall_id = NULL,
           robotic_tether_until = NULL, last_state_change = v_clock
     WHERE id = v_veh;
    v_sid := twin.ottoq_sim_start_charge_session(v_veh, v_stall, v_run, NULL, v_clock);
    IF v_sid IS NULL THEN
      RAISE EXCEPTION '0694 V1: the shield refused the probe''s charge start';
    END IF;
    SELECT transaction_id INTO v_tx FROM public.ocpp_sessions WHERE id = v_sid;
    FOR i IN 1 .. 2 LOOP
      UPDATE public.ottoq_sim_runs SET sim_clock_current = v_clock + make_interval(mins => 10 * i) WHERE sim_run_id = v_run;
      PERFORM count(*) FROM twin.ottoq_sim_advance_charge_sessions(v_run, v_clock + make_interval(mins => 10 * i));
    END LOOP;
    IF EXISTS (SELECT 1 FROM public.ocpp_sessions WHERE id = v_sid AND status = 'active') THEN
      PERFORM twin.ottoq_sim_stop_charge_session(v_sid, 'completed', v_clock + interval '25 minutes', NULL, v_run);
    END IF;
    SELECT jsonb_build_object(
             'tx', v_tx,
             'msgs', jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                       't', m.message_type, 'v', m.ocpp_version,
                       'e', m.payload ->> 'eventType', 's', m.payload -> 'seqNo',
                       'tr', m.payload ->> 'triggerReason', 'sr', m.payload #>> '{transactionInfo,stoppedReason}',
                       'tx', m.payload #>> '{transactionInfo,transactionId}', 'tok', m.payload #>> '{idToken,idToken}',
                       'vendor', m.payload #>> '{customData,vendorId}',
                       'soc', ottoq.ottoq_ocpp_meter_soc(m.message_type, m.payload),
                       'sample_soc', (SELECT (sv ->> 'value')::numeric
                                        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(m.payload #> '{meterValue,0,sampledValue}') = 'array'
                                                                       THEN m.payload #> '{meterValue,0,sampledValue}' ELSE '[]'::jsonb END) sv
                                       WHERE sv ->> 'measurand' = 'SoC' LIMIT 1),
                       'keys', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_object_keys(m.payload) k)))
                     ORDER BY m.message_seq))
      INTO v_r
      FROM public.ottoq_ocpp_messages m WHERE m.ocpp_session_id = v_sid;
    RAISE EXCEPTION '0694 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0694 PROBED' THEN RAISE EXCEPTION '0694 charge probe failed: %', v_msg; END IF;
  RETURN v_r;
END $fn$;

DO $v1b$
DECLARE
  v jsonb := pg_temp.p0694_session();
  te jsonb; n int; i int;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY o), '[]'::jsonb) INTO te
    FROM jsonb_array_elements(v -> 'msgs') WITH ORDINALITY AS z(x, o) WHERE x ->> 't' = 'TransactionEvent';
  n := jsonb_array_length(te);
  -- no OCPP 1.6 name, every row labelled 2.0.1, Authorize carrying the token only
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'msgs') x
              WHERE x ->> 't' IN ('StartTransaction', 'StopTransaction', 'MeterValues') OR x ->> 'v' IS DISTINCT FROM '2.0.1')
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'msgs') x
                 WHERE x ->> 't' = 'Authorize' AND x -> 'keys' IS DISTINCT FROM '["idToken"]'::jsonb)
     OR (SELECT count(*) FROM jsonb_array_elements(v -> 'msgs') x WHERE x ->> 't' = 'StatusNotification') <> 2 THEN
    RAISE EXCEPTION '0694 V1 FAILED: the charge''s messages are not 2.0.1''s: %', v;
  END IF;
  -- one transaction: Started (seqNo 0, the token), Updated..., Ended (a stopped reason), seqNo counting up, one id
  IF n < 3 OR te -> 0 ->> 'e' IS DISTINCT FROM 'Started' OR te -> 0 ->> 'tok' IS NULL
     OR te -> 0 ->> 'tr' IS DISTINCT FROM 'CablePluggedIn'
     OR te -> (n - 1) ->> 'e' IS DISTINCT FROM 'Ended' OR te -> (n - 1) ->> 'sr' IS NULL OR te -> (n - 1) ->> 'tr' IS NULL
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(te) WITH ORDINALITY AS z(x, o)
                 WHERE (x ->> 's')::int IS DISTINCT FROM (o - 1)::int
                    OR x ->> 'tx' IS DISTINCT FROM v ->> 'tx'
                    OR x ->> 'vendor' IS DISTINCT FROM 'com.ottoyard.twin'
                    OR (o BETWEEN 2 AND n - 1 AND x ->> 'e' IS DISTINCT FROM 'Updated')) THEN
    RAISE EXCEPTION '0694 V1 FAILED: the charge is not one 2.0.1 transaction: %', te;
  END IF;
  -- the reader takes each Updated's charge, and only the Updated ones
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(te) x
              WHERE (x ->> 'e' = 'Updated' AND ((x ->> 'soc') IS NULL
                                                OR (x ->> 'soc')::numeric IS DISTINCT FROM (x ->> 'sample_soc')::numeric))
                 OR (x ->> 'e' <> 'Updated' AND x ? 'soc')) THEN
    RAISE EXCEPTION '0694 V1 FAILED: the charge clock''s reader does not read the 2.0.1 readings as written: %', te;
  END IF;
  RAISE NOTICE '0694 V1b PASSED: one charge sent % messages, % of them one TransactionEvent (seqNo 0 to %), no 1.6 name (all rolled back)',
    jsonb_array_length(v -> 'msgs'), n, n - 1;
END $v1b$;

-- ── V2: the definitions as written, no writer names a 1.6 message, the helpers the owner's, no probe row left ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure))
       <> '05d725246fd41da9895c173f161e705f'
     OR md5(pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure))
       <> 'c26a997e1c8cab101d275c868d87db1d'
     OR md5(pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure))
       <> '2281c70b3b5d7cc39f3026bf2b09b4cd'
     OR md5(pg_get_functiondef('public.ottoq_charge_time_v2_params_cut(uuid,timestamptz,interval,numeric,jsonb)'::regprocedure))
       <> '9e6f1694936726fd47338b75bd9345c1' THEN
    RAISE EXCEPTION '0694 V2 FAILED: a patched definition is not as written';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(ARRAY[
               pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure),
               pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure),
               pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure)]) d
              WHERE regexp_replace(d, '--[^\n]*', '', 'g') ~ '''(StartTransaction|StopTransaction|MeterValues)''') THEN
    RAISE EXCEPTION '0694 V2 FAILED: a charge-session step still writes an OCPP 1.6 message';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_ocpp201_tx_event(text,text,integer,text,timestamptz,text,jsonb,jsonb,text,text,integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'ottoq.ottoq_ocpp_meter_soc(text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '0694 V2 FAILED: the public key can call a helper';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_ocpp_messages WHERE message_type = 'TransactionEvent') THEN
    RAISE EXCEPTION '0694 V2 FAILED: the probe''s messages outlived its rollback';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0694_the_twins_chargers_speak_ocpp_2_0_1', false, false,
  'G412: the twin''s charge start, advance and stop write OCPP 2.0.1 (Authorize with the token only; TransactionEvent '
  'Started, Updated and Ended with seqNo, meter values, the spec''s trigger and stopped reasons, the twin''s own facts in '
  'customData) in place of StartTransaction, MeterValues and StopTransaction; the charge clock''s reader takes a '
  'reading''s charge from either shape. No atom reads the log, every stored reading reads the same, and the clock fits '
  'three days to the same fit before and after (V1): FALSE/FALSE, and no evidence regime (the clock''s numbers did not '
  'change).',
  now());

COMMIT;
