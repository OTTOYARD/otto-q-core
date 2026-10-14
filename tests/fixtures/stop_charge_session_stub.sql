-- tests/fixtures/stop_charge_session_stub.sql -- what 0723 meets. twin.ottoq_sim_stop_charge_session and
-- twin.ottoq_sim_emit_ocpp are the live definitions of 2026-10-14 (pg_get_functiondef, byte for byte: md5
-- 2281c70b3b5d7cc39f3026bf2b09b4cd and 3a421ca5eaa88616bd0b41acaf7c22d9, read as base64 and decoded), so 0723's md5
-- premise and its anchors run against exactly what they will meet. The tables carry the columns those two read and
-- write, with the frame log's two foreign keys as live holds them (charger_id -> ottoq_ocpp_chargers ON DELETE SET
-- NULL, ocpp_session_id -> ocpp_sessions ON DELETE CASCADE) and the stall's charger key (ON DELETE SET NULL). Every
-- function the stop step calls is a stub that logs its name and arguments to t_calls. The 0694 helpers that build
-- the 2.0.1 payloads are loaded by the test from db/migrations/0694 itself.
--
-- twin.ottoq_sim_start_charge_session and twin.ottoq_sim_advance_charge_sessions are NOT the live bodies: they are
-- stand-ins that send their frames the way the live ones do (the start step from v_charger.charger_id, the charger
-- its stall maps to; the advance step from st.ocpp_charger_id through JOIN stalls), which is what 0723's P1 reads in
-- their source and what its V1 drives. The stand-in start mints a session id from (vehicle, stall, clock), so the
-- same script gives the same rows in two databases. Used by tests/test_stop_charge_frames_sql.py.
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS twin; CREATE SCHEMA IF NOT EXISTS ottoq; CREATE SCHEMA IF NOT EXISTS extensions;

CREATE TABLE public.t_inflight (n int NOT NULL DEFAULT 0); INSERT INTO public.t_inflight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql
  AS 'SELECT n FROM public.t_inflight';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
INSERT INTO public.ottoq_cert_lineage VALUES ('0694_the_twins_chargers_speak_ocpp_2_0_1', false, 'stub', now(), false);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial PRIMARY KEY, label text, object_kind text,
  schema_name text, object_name text, definition text, def_md5 text, captured_at timestamptz DEFAULT now());
CREATE TABLE public.t_calls (seq bigserial PRIMARY KEY, fn text NOT NULL, args jsonb);

CREATE TYPE public.ocpp_session_status AS ENUM ('active', 'completed', 'faulted', 'cancelled');
CREATE TYPE public.stall_type AS ENUM ('dcfc', 'l2', 'wash_bay', 'detail_bay', 'service_bay', 'staging', 'parking', 'safety');
CREATE TYPE public.vehicle_state AS ENUM ('arrived_at_gate', 'staged_awaiting_service', 'charging_dcfc', 'charging_l2',
  'charge_complete_holding');

CREATE TABLE public.depots (id uuid PRIMARY KEY);
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid, status text, sim_clock_current timestamptz,
  started_at timestamptz);
CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid,
  ocpp_identifier text NOT NULL, station_state text NOT NULL DEFAULT 'Unavailable',
  station_state_changed_at timestamptz NOT NULL DEFAULT now(), last_heartbeat_at timestamptz, max_kw numeric,
  last_fault_code text, last_fault_at timestamptz, last_fault_payload jsonb);
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, home_depot_id uuid, current_depot_id uuid, fleet_operator_id uuid,
  display_name text, battery_capacity_kwh numeric, current_soc integer, target_soc integer,
  current_state public.vehicle_state, current_stall_id uuid, last_state_change timestamptz, config jsonb,
  robotic_tether_until timestamptz, robotic_tether_stall_id uuid, robotic_tether_direction text, robotic_tether_phase text);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid NOT NULL, stall_code text NOT NULL,
  stall_type public.stall_type NOT NULL, status text NOT NULL DEFAULT 'available', current_vehicle_id uuid,
  ocpp_charger_id uuid REFERENCES public.ottoq_ocpp_chargers (charger_id) ON DELETE SET NULL,
  reserved_by uuid, reserved_at timestamptz, reservation_expires_at timestamptz);
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid NOT NULL,
  stall_id uuid NOT NULL, vehicle_id uuid, charge_point_id text NOT NULL, transaction_id text NOT NULL,
  evse_id integer NOT NULL DEFAULT 1, connector_id integer NOT NULL DEFAULT 1,
  status public.ocpp_session_status NOT NULL DEFAULT 'active', started_at timestamptz NOT NULL, ended_at timestamptz,
  soc_start integer, soc_end integer, energy_delivered_kwh numeric NOT NULL DEFAULT 0, avg_power_kw numeric NOT NULL DEFAULT 0,
  stopped_reason text, id_token text, last_fault_message text, created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), sim_run_id uuid);
CREATE TABLE public.ottoq_ocpp_messages (message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_seq bigserial UNIQUE,
  ocpp_session_id uuid REFERENCES public.ocpp_sessions (id) ON DELETE CASCADE,
  charger_id uuid REFERENCES public.ottoq_ocpp_chargers (charger_id) ON DELETE SET NULL,
  vehicle_id uuid, sim_run_id uuid, message_at timestamptz NOT NULL DEFAULT now(), sim_clock_at timestamptz,
  direction text NOT NULL CHECK (direction = ANY (ARRAY['cs_to_csms', 'csms_to_cs'])),
  message_type text NOT NULL, ocpp_version text NOT NULL DEFAULT '2.0.1', payload jsonb NOT NULL,
  data_source text NOT NULL DEFAULT 'twin' CHECK (data_source = ANY (ARRAY['production', 'twin', 'replay', 'shadow'])),
  created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_variability_cards (id bigserial PRIMARY KEY, sim_run_id uuid, var_key text, scope_instance text,
  bucket_key text, meta jsonb);
CREATE TABLE twin.arm_cycles (cycle_id uuid PRIMARY KEY, sim_run_id uuid, stall_id uuid, vehicle_id uuid, session_id uuid,
  direction text, outcome text, started_at timestamptz, ended_at timestamptz);
CREATE TABLE public.ottoq_stall_bookings (booking_id uuid PRIMARY KEY, sim_run_id uuid, stall_id uuid, vehicle_id uuid,
  purpose text, during tstzrange, state text, released_at timestamptz, release_reason text);

-- ── what the stop step calls, each a stub that logs its call ──
CREATE FUNCTION public.ottoq_default_target_soc() RETURNS numeric LANGUAGE sql AS 'SELECT 100::numeric';
CREATE FUNCTION public.ottoq_arm_timings(p_sim_run_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql
  AS $s$ SELECT '{"demate_seconds": 11.5}'::jsonb $s$;
CREATE FUNCTION public.ottoq_probe_task_completion_at(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_svc text,
  p_started_at timestamptz, p_ends_at timestamptz, p_stall_id uuid)
  RETURNS TABLE(rule_code text, passed boolean, reason text, severity text, enforcement text, would_block boolean, had_a_stall boolean)
  LANGUAGE plpgsql AS $s$
BEGIN
  INSERT INTO public.t_calls (fn, args) VALUES ('ottoq_probe_task_completion_at',
    jsonb_build_object('vehicle', p_vehicle_id, 'svc', p_svc, 'stall', p_stall_id, 'ends_at', p_ends_at));
  RETURN;
END $s$;
CREATE FUNCTION twin.ottoq_arm_emergency_release(p_vehicle_id uuid, p_reason text, p_actor text DEFAULT 'supervisor'::text,
  p_sim_run_id uuid DEFAULT NULL::uuid, p_clock timestamptz DEFAULT NULL::timestamptz) RETURNS jsonb LANGUAGE plpgsql AS $s$
BEGIN
  INSERT INTO public.t_calls (fn, args) VALUES ('ottoq_arm_emergency_release',
    jsonb_build_object('vehicle', p_vehicle_id, 'reason', p_reason, 'actor', p_actor, 'clock', p_clock));
  UPDATE public.vehicles SET robotic_tether_until = NULL, robotic_tether_stall_id = NULL WHERE id = p_vehicle_id;
  RETURN '{}'::jsonb;
END $s$;
CREATE FUNCTION ottoq.ottoq_book_hold_stall(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_from timestamptz,
  p_to timestamptz, p_visit_id uuid DEFAULT NULL::uuid, p_leg_id uuid DEFAULT NULL::uuid, p_long_threshold_min integer DEFAULT 90)
  RETURNS jsonb LANGUAGE plpgsql AS $s$
DECLARE v_stall uuid; v_id uuid;
BEGIN
  INSERT INTO public.t_calls (fn, args) VALUES ('ottoq_book_hold_stall',
    jsonb_build_object('vehicle', p_vehicle_id, 'from', p_from, 'to', p_to));
  SELECT s.id INTO v_stall FROM public.stalls s
   WHERE s.depot_id = p_depot_id AND s.stall_type = 'staging' AND s.current_vehicle_id IS NULL
   ORDER BY s.stall_code LIMIT 1;
  IF v_stall IS NULL THEN RETURN jsonb_build_object('booked', false); END IF;
  v_id := md5('hold' || p_vehicle_id::text || p_from::text)::uuid;
  INSERT INTO public.ottoq_stall_bookings (booking_id, sim_run_id, stall_id, vehicle_id, purpose, during, state)
  VALUES (v_id, p_sim_run_id, v_stall, p_vehicle_id, 'temp_hold', tstzrange(p_from, p_to, '[)'), 'held');
  RETURN jsonb_build_object('booked', true, 'booking_id', v_id);
END $s$;
CREATE FUNCTION twin.ottoq_arm_begin_cycle(p_sim_run_id uuid, p_vehicle_id uuid, p_stall_id uuid, p_session_id uuid,
  p_direction text, p_clock timestamptz) RETURNS uuid LANGUAGE plpgsql AS $s$
DECLARE v_id uuid := md5(p_direction || p_session_id::text)::uuid;
BEGIN
  INSERT INTO public.t_calls (fn, args) VALUES ('ottoq_arm_begin_cycle',
    jsonb_build_object('vehicle', p_vehicle_id, 'stall', p_stall_id, 'direction', p_direction, 'clock', p_clock));
  INSERT INTO twin.arm_cycles (cycle_id, sim_run_id, stall_id, vehicle_id, session_id, direction, started_at)
  VALUES (v_id, p_sim_run_id, p_stall_id, p_vehicle_id, p_session_id, p_direction, p_clock);
  RETURN v_id;
END $s$;
CREATE FUNCTION public.ottoq_itin_leg_close(p_sim_run_id uuid, p_vehicle_id uuid, p_leg_types text[], p_now timestamptz,
  p_status text DEFAULT 'done'::text) RETURNS integer LANGUAGE plpgsql AS $s$
BEGIN
  INSERT INTO public.t_calls (fn, args) VALUES ('ottoq_itin_leg_close',
    jsonb_build_object('vehicle', p_vehicle_id, 'legs', to_jsonb(p_leg_types), 'now', p_now, 'status', p_status));
  RETURN 1;
END $s$;
CREATE FUNCTION ottoq.ottoq_occupancy_cut_short(p_planned_s numeric, p_actual_s numeric) RETURNS boolean LANGUAGE sql
  AS $s$ SELECT p_actual_s < p_planned_s * 0.5 $s$;
CREATE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text,
  p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text,
  p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid,
  p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text,
  p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_related_task_id uuid DEFAULT NULL::uuid,
  p_related_schedule_id uuid DEFAULT NULL::uuid, p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text,
  p_latency_ms integer DEFAULT NULL::integer, p_ingest_source text DEFAULT 'app'::text,
  p_signing_key_id text DEFAULT 'system:v1'::text, p_data_source text DEFAULT 'production'::text,
  p_sim_run_id uuid DEFAULT NULL::uuid) RETURNS uuid LANGUAGE plpgsql AS $s$
BEGIN
  INSERT INTO public.t_calls (fn, args) VALUES ('ottoq_record_event',
    jsonb_build_object('event_type', p_event_type, 'entity', p_entity_id, 'payload', p_payload, 'severity', p_severity));
  RETURN NULL;
END $s$;

-- ── the live emitter and the live stop step, byte for byte ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_emit_ocpp(p_session_id uuid, p_charger_id uuid, p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock timestamp with time zone, p_direction text, p_message_type text, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_msg_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO ottoq_ocpp_messages (
    message_id, ocpp_session_id, charger_id, vehicle_id, sim_run_id,
    sim_clock_at, direction, message_type, payload, data_source
  ) VALUES (
    v_msg_id, p_session_id, p_charger_id, p_vehicle_id, p_sim_run_id,
    p_sim_clock, p_direction, p_message_type, p_payload, 'twin'
  );
  RETURN v_msg_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION twin.ottoq_sim_stop_charge_session(p_session_id uuid, p_reason text DEFAULT 'completed'::text, p_sim_clock_now timestamp with time zone DEFAULT NULL::timestamp with time zone, p_fault_message text DEFAULT NULL::text, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_session ocpp_sessions%ROWTYPE;
  v_clock TIMESTAMPTZ;
  v_duration_s NUMERIC; v_avg_power NUMERIC; v_vehicle RECORD;
  v_new_status ocpp_session_status;
  v_requeue boolean := false; v_temp_hold jsonb; v_temp_stall uuid; v_fault_depot uuid;
  v_repair_min numeric;
  -- 0011-TETHER: DCFC stalls are robot-served. StopTransaction is NOT the unplug.
  v_is_dcfc boolean := false; v_tether boolean := false;
  v_demate_s numeric := 11.5;   -- robot disconnect time, one named knob (see below)
BEGIN
  v_clock := COALESCE(p_sim_clock_now, NOW());
  SELECT * INTO v_session FROM ocpp_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_session.status <> 'active' THEN
    -- Session already closed elsewhere. Do NOT repeat the accounting, but DO
    -- make sure the physical resources were actually released (this is the
    -- path that used to strand chargers as Occupied on empty stalls).
    UPDATE ottoq_ocpp_chargers c
       SET station_state = 'Available', station_state_changed_at = v_clock
     WHERE c.charger_id IN (SELECT ocpp_charger_id FROM stalls WHERE id = v_session.stall_id)
       AND c.station_state = 'Occupied'
       AND NOT EXISTS (SELECT 1 FROM ocpp_sessions s2
                        WHERE s2.stall_id = v_session.stall_id AND s2.status = 'active');
    -- 0011-TETHER: a tethered car IS the "vehicle that does not point back" -- the robot
    -- is still holding it and vehicles.current_stall_id is already NULL. Without this
    -- guard the strand-cleaner below would hand the plug away mid-demate. The tether
    -- RECORD (not a clock) is the test: ottoq_release_expired_tethers is the single
    -- releaser and it clears the record and the stall together, so deferring to it
    -- cannot strand the stall.
    UPDATE stalls s SET current_vehicle_id = NULL
     WHERE s.id = v_session.stall_id
       AND s.current_vehicle_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM vehicles v
                        WHERE v.id = s.current_vehicle_id AND v.current_stall_id = s.id)
       AND NOT EXISTS (SELECT 1 FROM vehicles tv
                        WHERE tv.id = s.current_vehicle_id
                          AND tv.robotic_tether_stall_id = s.id
                          AND tv.robotic_tether_until IS NOT NULL);
    RETURN;
  END IF;

  v_duration_s := EXTRACT(EPOCH FROM (v_clock - v_session.started_at));
  v_avg_power := CASE WHEN v_duration_s > 0 THEN
    (v_session.energy_delivered_kwh * 3600.0 / v_duration_s) ELSE 0 END;
  SELECT id, fleet_operator_id, current_soc, display_name, COALESCE(target_soc, public.ottoq_default_target_soc()) AS target_soc
    INTO v_vehicle FROM vehicles WHERE id = v_session.vehicle_id;

  v_new_status := (CASE
    WHEN p_reason = 'completed' THEN 'completed'
    WHEN p_reason LIKE 'fault%' THEN 'faulted'
    ELSE 'cancelled' END)::ocpp_session_status;

  UPDATE ocpp_sessions SET
    status = v_new_status, ended_at = v_clock, soc_end = v_vehicle.current_soc,
    avg_power_kw = v_avg_power, stopped_reason = p_reason,
    last_fault_message = p_fault_message, updated_at = NOW()
   WHERE id = p_session_id;

  -- 0694 (G412): the transaction ends as an OCPP 2.0.1 station ends it, TransactionEvent Ended, with the register, the
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
  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StatusNotification', jsonb_build_object(
      'connectorId',1,'connectorStatus','Available','evseId',1,'timestamp',v_clock));

  -- feed-agent: the fault card dealt for this session carries the drawn
  -- repair duration (fitted repair_days grid x staffed-depot x fault mode)
  IF p_reason LIKE 'fault%' AND p_sim_run_id IS NOT NULL THEN
    SELECT (meta->>'repair_minutes')::numeric INTO v_repair_min
      FROM ottoq_variability_cards
     WHERE sim_run_id = p_sim_run_id AND var_key = 'charger_fault'
       AND scope_instance = p_session_id::text
       AND bucket_key = 'session:' || p_session_id::text;
  END IF;

  UPDATE ottoq_ocpp_chargers c SET
    -- 0550 (G281): only a repair clears a fault. A stop that is not a fault leaves a Faulted charger Faulted, and
    -- leaves its stamp alone, because twin.ottoq_sim_recover_chargers reads the stamp as the start of the repair.
    -- Before 0550 a car that charged on through an injected fault put its charger back in service when it finished.
    station_state = CASE WHEN p_reason LIKE 'fault%' THEN 'Faulted'
                         WHEN c.station_state = 'Faulted' THEN 'Faulted' ELSE 'Available' END,
    station_state_changed_at = CASE WHEN p_reason NOT LIKE 'fault%' AND c.station_state = 'Faulted'
                                    THEN c.station_state_changed_at ELSE v_clock END,
    last_fault_code = CASE WHEN p_reason LIKE 'fault%' THEN p_reason ELSE c.last_fault_code END,
    last_fault_at = CASE WHEN p_reason LIKE 'fault%' THEN v_clock ELSE c.last_fault_at END,
    last_fault_payload = CASE WHEN p_reason LIKE 'fault%' THEN
      jsonb_build_object('reason',p_reason,'message',p_fault_message,'session_id',p_session_id,
                         'repair_minutes', v_repair_min)
      ELSE c.last_fault_payload END
   WHERE charger_id IN (SELECT ocpp_charger_id FROM stalls WHERE id = v_session.stall_id);

  -- S3a AUTO RE-ROUTE: fault interrupted the charge with the vehicle still under target →
  -- re-queue so OTTO-Q reassigns a healthy charger; otherwise proceed to disposition.
  -- 0011-TETHER moved this ABOVE the stall release, because the release now depends on it.
  -- Nothing about the expression itself changed.
  v_requeue := (p_reason LIKE 'fault%' AND v_vehicle.current_soc < v_vehicle.target_soc - 5);

  -- ═══════════════════ 0011-TETHER: STOPTRANSACTION IS NOT THE UNPLUG ═══════════════════
  -- DCFC stalls are served by the OTTO-CHARGE ARM. When the session closes the car is
  -- still physically on the end of a cable and the robot needs 11.5 s to demate
  -- (unlatch 2.0 + extract 3.0 + retract 6.5, from armStateMachine.ts in
  -- ottoyarddepot-sim -- keep the two in step). So the plug is NOT handed to the next
  -- vehicle here; ottoq_release_expired_tethers frees it once the window passes.
  --
  -- WHY THE REQUEUE PATH IS EXCLUDED: on a fault-with-low-SoC the block below physically
  -- relocates the car to a booked temp stall. Holding the DCFC stall as well would leave
  -- one vehicle occupying two stalls, which is exactly what the overlap guard exists to
  -- prevent. That path therefore keeps releasing the stall, unchanged from today.
  SELECT (s.stall_type = 'dcfc'::stall_type) INTO v_is_dcfc
    FROM stalls s WHERE s.id = v_session.stall_id;
  -- ...AND ONLY IF THE ARM ACTUALLY LATCHED. A session that opened no mate --
  -- because the car was already at target -- has nothing to disconnect from, and
  -- a demate cycle here would be the arm withdrawing a plug it never inserted.
  -- v_tether governs the stall release, the tether write AND the demate cycle
  -- below, so this one conjunct covers all three: a car that was never connected
  -- is released to move immediately, which is exactly right.
  v_tether := COALESCE(v_is_dcfc, false) AND NOT v_requeue
              AND EXISTS (SELECT 1 FROM twin.arm_cycles c
                           WHERE c.session_id = v_session.id
                             AND c.direction = 'mate'
                             AND c.outcome = 'latched');

  -- ONE KNOB, NOT TWO LITERALS. The disconnect time was hardcoded here as
  -- interval '11.5 seconds', duplicating the value in armStateMachine.ts
  -- (unlatch 2.0 + extract 3.0 + retract 6.5) in the ottoyarddepot-sim repo with nothing
  -- linking them -- retune the arm and the orchestration silently disagrees about how
  -- long the car is mated. It is now the named policy 'robotic_demate_seconds',
  -- overridable per run or per depot, with 11.5 as the default so behaviour is
  -- unchanged until someone deliberately changes it. The renderer remains the physical
  -- source of truth; this is the value OTTO-Q reserves the plug for.
  v_demate_s := GREATEST(0, COALESCE(
    (public.ottoq_arm_timings(p_sim_run_id)->>'demate_seconds')::numeric, 11.5));

  BEGIN
    -- 0489 (G224): the session's own stall, not a lookup that can tie across two bookings.
    PERFORM 1 FROM public.ottoq_probe_task_completion_at(
      p_sim_run_id := p_sim_run_id,
      p_depot_id   := (SELECT depot_id FROM stalls WHERE id = v_session.stall_id),
      p_vehicle_id := v_session.vehicle_id,
      p_svc        := 'charge',
      p_started_at := v_session.started_at,
      p_ends_at    := v_clock,
      p_stall_id   := v_session.stall_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_sim_stop_charge_session: task_completion probe FAILED SAFELY %: %',
      SQLSTATE, SQLERRM;
  END;
  IF NOT v_tether THEN
    UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_session.stall_id;
  END IF;

  -- The fault-requeue path physically relocates this car to a temp stall. Any
  -- charge lease it is holding points at the DCFC stall it is leaving, and a
  -- stale lease would both freeze the car and misreport which stall the robot
  -- has. Drop it, and close whatever cycle was open on that plinth.
  IF v_requeue THEN
    -- ═══════ THROUGH THE FRONT DOOR, NOT AROUND IT ═══════
    -- This is the founder's malfunction case exactly: the charger has died under
    -- a car that still needs charge, so the arm must let go and the car must be
    -- relocated to a temporary stall. It used to clear the tether inline and mark
    -- the cycle 'abandoned' -- which says the world stopped underneath it rather
    -- than that the charger failed and the arm was ordered to release. That
    -- charged the arm's reliability record with somebody else's fault, emitted no
    -- safety event, and never set the disposition flag a supervisor needs.
    --
    -- Must stay AHEAD of the relocation below: since the arm interlock trigger
    -- exists, moving the car with a live tether would be refused outright.
    PERFORM twin.ottoq_arm_emergency_release(
      v_session.vehicle_id,
      'charger fault: ' || COALESCE(NULLIF(p_fault_message, ''), p_reason, 'unspecified'),
      'twin_charger_fault', p_sim_run_id, v_clock);

    -- Belt, for a cycle left open on this plinth with no tether behind it. Scoped
    -- to THIS vehicle: the old predicate was stall-only and would have abandoned
    -- another car's cycle on the same plinth.
    UPDATE twin.arm_cycles SET ended_at = v_clock, outcome = COALESCE(outcome, 'abandoned')
     WHERE stall_id = v_session.stall_id AND vehicle_id = v_session.vehicle_id
       AND ended_at IS NULL;
  END IF;
  IF v_requeue THEN
    -- DOCTRINE (Chase 2026-07-28): a vehicle is NEVER queued at the gate. A charger
      -- dying mid-charge is temp-staging case 3(a): give it a booked temp stall and let
      -- OTTO-Q re-route it to a healthy charger from there.
      SELECT s.depot_id INTO v_fault_depot FROM stalls s WHERE s.id = v_session.stall_id;
      v_temp_hold := ottoq_book_hold_stall(p_sim_run_id, v_fault_depot, v_session.vehicle_id,
                                           v_clock, v_clock + interval '30 minutes');
      IF COALESCE((v_temp_hold->>'booked')::boolean, false) THEN
        SELECT b.stall_id INTO v_temp_stall FROM ottoq_stall_bookings b
         WHERE b.booking_id = (v_temp_hold->>'booking_id')::uuid;
        UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               current_stall_id = v_temp_stall, last_state_change = v_clock,
               -- 0474 (G209): a step, so the deploy gate sees the car and routes it by its open work
               config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', to_jsonb('need_deploy'::text))
         WHERE id = v_session.vehicle_id;
        UPDATE stalls SET current_vehicle_id = v_session.vehicle_id, status = 'occupied'
         WHERE id = v_temp_stall;
      ELSE
        -- Staging genuinely full: still not the gate. Hold state without a stall and
        -- let the next tick place it; this is the only degraded path and it is visible.
        UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               current_stall_id = NULL, last_state_change = v_clock,
               -- 0474 (G209): as above
               config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', to_jsonb('need_deploy'::text))
         WHERE id = v_session.vehicle_id;
      END IF;
  ELSE
    -- 0011-TETHER: the tether is written in the SAME statement that nulls current_stall_id.
    -- That ordering is load-bearing: trg_sync_stall_occupancy is an AFTER UPDATE trigger on
    -- vehicles that frees the old stall whenever current_stall_id changes, and it reads NEW.
    -- Setting the tether in a later statement would let the trigger release the plug first.
    UPDATE vehicles SET current_state = 'charge_complete_holding'::vehicle_state,
                        -- KEEP THE STALL WHILE THE ARM UNLATCHES. Nulling this here is what
                        -- deadlocked the world tick against ottoq_arm_interlock_guard. The car
                        -- is physically still in the stall until the demate tether expires, and
                        -- ottoq_release_expired_tethers clears both the stall and this pointer
                        -- when it does. Because this no longer CHANGES current_stall_id on the
                        -- tethered path, trg_sync_stall_occupancy does not fire, so the original
                        -- 0011-TETHER hazard (the plug being freed before the tether is written)
                        -- cannot occur either.
                        current_stall_id = CASE WHEN v_tether
                          THEN v_session.stall_id ELSE NULL END, last_state_change = v_clock,
                        robotic_tether_until = CASE WHEN v_tether
                          THEN v_clock + make_interval(secs => v_demate_s) ELSE robotic_tether_until END,
                        robotic_tether_stall_id = CASE WHEN v_tether
                          THEN v_session.stall_id ELSE robotic_tether_stall_id END,
                        robotic_tether_direction = CASE WHEN v_tether
                          THEN 'demate' ELSE robotic_tether_direction END,
                        robotic_tether_phase = CASE WHEN v_tether
                          THEN 'unlatch' ELSE robotic_tether_phase END
     WHERE id = v_session.vehicle_id;
  END IF;

  -- ═══════════ THE ARM LETS GO ═══════════
  -- The demate window already existed as a deadline; this gives it a lifecycle
  -- with the same shape as the inbound one, so the cockpit and OTTO-Q read the
  -- arm the same way in both directions. Never allowed to abort the close.
  IF v_tether THEN
    BEGIN
      PERFORM twin.ottoq_arm_begin_cycle(p_sim_run_id, v_session.vehicle_id,
                                         v_session.stall_id, p_session_id, 'demate', v_clock);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm demate begin: %', SQLERRM;
    END;
  END IF;

  -- A2-B2: close the charge leg; deviation_s = actual vs physics-planned end.
  PERFORM ottoq_itin_leg_close(p_sim_run_id, v_session.vehicle_id,
    ARRAY['charge_dcfc','charge_l2'], v_clock, 'done');

  -- 0484 (G217): the session is over, so this charger is no longer this car's. Its charge booking ends when the plug
  -- is free (now, or once the arm has demated a latched DCFC) and its reservation goes with it. Both used to run to
  -- their own expiry, so a car that had finished, or had been moved off a faulted charger, held it from staging.
  UPDATE ottoq_stall_bookings b
     SET state          = CASE WHEN v_new_status::text <> 'completed'
                                    AND ottoq.ottoq_occupancy_cut_short(
                                      EXTRACT(epoch FROM (upper(b.during) - lower(b.during)))::numeric,
                                      EXTRACT(epoch FROM (LEAST(upper(b.during), f.free_at) - lower(b.during)))::numeric)
                               THEN 'interrupted' ELSE 'done' END,
         released_at    = f.free_at,
         release_reason = 'charge_session_' || v_new_status::text,
         during         = tstzrange(lower(b.during),
                                    GREATEST(lower(b.during) + interval '1 second', LEAST(upper(b.during), f.free_at)), '[)')
    FROM (SELECT v_clock + CASE WHEN v_tether THEN make_interval(secs => v_demate_s)
                                ELSE interval '0 seconds' END AS free_at) f
   WHERE b.sim_run_id = p_sim_run_id
     AND b.stall_id   = v_session.stall_id
     AND b.vehicle_id = v_session.vehicle_id
     AND b.purpose IN ('charge_dcfc','charge_l2')
     AND b.state = 'active'
     AND lower(b.during) <= v_clock;
  UPDATE stalls
     SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
   WHERE id = v_session.stall_id AND reserved_by = v_session.vehicle_id;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'twin_charge_orchestrator',
    p_event_type := CASE WHEN p_reason LIKE 'fault%' THEN 'charge.session_faulted'
                                                     ELSE 'charge.session_completed' END,
    p_entity_type := 'ocpp_session', p_entity_id := p_session_id,
    p_fleet_operator_id := v_vehicle.fleet_operator_id, p_depot_id := v_session.depot_id,
    p_payload := jsonb_build_object('reason',p_reason,'fault_message',p_fault_message,
      'vehicle',v_vehicle.display_name,'soc_start',v_session.soc_start,
      'soc_end',v_vehicle.current_soc,'energy_kwh',v_session.energy_delivered_kwh,
      'duration_s',v_duration_s,'avg_power_kw',ROUND(v_avg_power::numeric,2),
      'repair_minutes', v_repair_min,
      'auto_rerouted', v_requeue),
    p_severity := CASE WHEN p_reason LIKE 'fault%' THEN 'warning' ELSE 'info' END,
    p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
END;
$function$
;

-- ── stand-ins (NOT the live bodies): they send their frames from the stall's charger, as the live start and advance
--    steps do, and 0723's P1 reads exactly that in their source ──
CREATE FUNCTION twin.ottoq_sim_start_charge_session(p_vehicle_id uuid, p_stall_id uuid, p_sim_run_id uuid,
  p_target_soc numeric DEFAULT NULL::numeric, p_sim_clock_now timestamp with time zone DEFAULT NULL::timestamp with time zone)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'twin', 'ottoq', 'public', 'extensions' AS $fn$
DECLARE
  v_session_id uuid; v_vehicle RECORD; v_stall RECORD; v_charger ottoq_ocpp_chargers%ROWTYPE; v_clock timestamptz;
BEGIN
  v_clock := COALESCE(p_sim_clock_now, NOW());
  v_session_id := md5(p_vehicle_id::text || p_stall_id::text || v_clock::text)::uuid;
  SELECT id, current_soc, target_soc INTO v_vehicle FROM vehicles WHERE id = p_vehicle_id;
  SELECT s.id, s.depot_id, s.ocpp_charger_id, s.stall_type INTO v_stall FROM stalls s WHERE s.id = p_stall_id;
  IF v_stall.ocpp_charger_id IS NULL THEN RAISE EXCEPTION 'stall % has no associated charger', p_stall_id; END IF;
  SELECT * INTO v_charger FROM ottoq_ocpp_chargers WHERE charger_id = v_stall.ocpp_charger_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'charger for stall % not found', p_stall_id; END IF;
  INSERT INTO ocpp_sessions (id, depot_id, stall_id, vehicle_id, sim_run_id, charge_point_id, transaction_id, status,
                             started_at, soc_start, id_token)
  VALUES (v_session_id, v_stall.depot_id, p_stall_id, p_vehicle_id, p_sim_run_id, v_charger.ocpp_identifier,
          'TXN-' || to_char(v_clock AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS') || '-' || substr(v_session_id::text, 1, 8),
          'active', v_clock, v_vehicle.current_soc, 'TWIN-' || substr(p_vehicle_id::text, 1, 8));
  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StatusNotification', jsonb_build_object('connectorId', 1, 'connectorStatus', 'Occupied', 'evseId', 1, 'timestamp', v_clock));
  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'Authorize', jsonb_build_object('idToken', jsonb_build_object('idToken', 'TWIN-' || substr(p_vehicle_id::text, 1, 8), 'type', 'ISO14443')));
  PERFORM ottoq_sim_emit_ocpp(v_session_id, v_charger.charger_id, p_vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
      'Started', 'CablePluggedIn', 0, (SELECT s.transaction_id FROM ocpp_sessions s WHERE s.id = v_session_id),
      v_clock, 'Charging',
      twin.ottoq_ocpp201_samples(ARRAY[
        twin.ottoq_ocpp201_sample('Energy.Active.Import.Register', 0, 'kWh'),
        twin.ottoq_ocpp201_sample('SoC', v_vehicle.current_soc, 'Percent')]),
      NULL, 'TWIN-' || substr(p_vehicle_id::text, 1, 8)));
  UPDATE ottoq_ocpp_chargers SET station_state = 'Occupied', station_state_changed_at = v_clock WHERE charger_id = v_charger.charger_id;
  UPDATE stalls SET current_vehicle_id = p_vehicle_id WHERE id = p_stall_id;
  UPDATE vehicles SET current_state = (CASE WHEN v_stall.stall_type = 'dcfc' THEN 'charging_dcfc' ELSE 'charging_l2' END)::vehicle_state,
         current_stall_id = p_stall_id, current_depot_id = v_stall.depot_id, last_state_change = v_clock
   WHERE id = p_vehicle_id;
  RETURN v_session_id;
END $fn$;

CREATE FUNCTION twin.ottoq_sim_advance_charge_sessions(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
RETURNS TABLE(out_session_id uuid, out_action text, out_new_soc numeric, out_charge_rate_kw numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'twin', 'ottoq', 'public', 'extensions' AS $fn$
DECLARE v_session RECORD;
BEGIN
  FOR v_session IN
    SELECT s.*, st.ocpp_charger_id, st.stall_type
      FROM ocpp_sessions s
      JOIN stalls st ON st.id = s.stall_id
     WHERE s.sim_run_id = p_sim_run_id AND s.status = 'active'
     ORDER BY s.id
  LOOP
    UPDATE ocpp_sessions SET energy_delivered_kwh = energy_delivered_kwh + 5 WHERE id = v_session.id;
    PERFORM ottoq_sim_emit_ocpp(v_session.id, v_session.ocpp_charger_id, v_session.vehicle_id, p_sim_run_id, p_sim_clock_now,
      'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event('Updated', 'MeterValuePeriodic',
        twin.ottoq_ocpp201_next_seq(v_session.id), v_session.transaction_id, p_sim_clock_now, 'Charging',
        twin.ottoq_ocpp201_samples(ARRAY[
          twin.ottoq_ocpp201_sample('Energy.Active.Import.Register', v_session.energy_delivered_kwh + 5, 'kWh')])));
    out_session_id := v_session.id; out_action := 'advanced'; out_new_soc := NULL; out_charge_rate_kw := NULL;
    RETURN NEXT;
  END LOOP;
END $fn$;
