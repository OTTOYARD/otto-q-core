-- migration-version: PENDING
-- migration-name:    the_v2_door_takes_cloudevents_keeps_their_time_drops_duplicates_and_orders_them
--
-- 0650  **The v2 door takes an operator's CloudEvents: it keeps their time, drops duplicates, and applies each car's
--        events in the order its operator numbered them.** (Step 3 of the twin data contract review, 2026-10-08; the
--        contract is contract/README.md. Chase, 2026-10-09 CT: "Start building.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The one external door, ottoq-ingest, stamps every row with the time it arrived (packet_at = now()), has no
--   duplicate check, applies a late packet over a newer one, and takes the car's depot state from the payload. 0649
--   made its depot and data source come from the credential. A key still names no fleet, so it can speak for any car
--   at its depot. The contract (step 2) fixes all of that on paper; this is the door that keeps it.
--
--   The door's logic lives here, in SQL, so that the HTTP door (edge function ottoq-depot-v2, step 3d) and the twin
--   (step 4) go through one code path. The HTTP door validates the whole event against contract/schemas first; this
--   function repeats every check its own logic depends on, so a caller that skips the HTTP door cannot skip them.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottow_api_keys.fleet_operator_ids: the fleets whose cars a key speaks for. NULL = none, so a key with no
--       fleet sends no car's events. Set only by public.ottoq_scope_source_key (service_role), through 0649's door.
--   (b) public.ottoq_v2_inbox: every event the door accepted, as sent, with what it did. UNIQUE NULLS NOT DISTINCT
--       (source_name, ce_source, ce_id, sim_run_id) is the duplicate check (CloudEvents: source + id is unique).
--       public.ottoq_v2_cursors: per operator and event source (one car), the last sequence applied, and counts.
--       Both carry sim_run_id, registered class 'engine' with a foreign key: a twin or replay key's rows are scoped to
--       the run whose clock judged them and go with that run; a production key's rows carry none and are kept.
--   (c) public.ottoq_v2_signal_ttl: how long a signal stays true (README rule 2), seeded for production and shadow
--       with the README's defaults. Twin and replay have none until step 4 sets them against the run's tick length.
--   (d) public.ottoq_v2_take_events(key_hash, events, dry_run): the door. Per event: the fields its logic reads, the
--       source naming this key's operator and the car, the stream the key carries, the car among the key's fleets at
--       its depot, once only, then in order (applied) or late (stored, never applied over newer state). A refused
--       event is not stored, so it can be corrected and resent with the same id. dry_run does everything and keeps
--       nothing. The clock is the data source's: now() for production and shadow, the running run's sim clock for
--       twin and replay.
--   (e) What "applied" does, type by type, through the writers the old door uses:
--         telemetry      one ottoq_telemetry_packets row timed by the event (VSS units converted back), and the car's
--                        SoC when fresh by (c). Location only inside the depot geofence. No depot state is taken.
--         arrival intent ottoq_ingest_vehicle_signal (OTTO-Q's return decision) with the ETA on the right clock, and
--                        en_route_to_depot for a car that is out. charge_target_pct is never applied (only the
--                        owner's settings set it, CLAUDE.md rule 9); services_needed and ready_by are kept, not wired.
--         fault summary  one exceptions row (title included; the old door's incident stream never wrote one, because
--                        title is NOT NULL and it sent none).
--         departed       kept, not applied: the depot's release of what it held is wired when the twin sends it (step 4).
--         ack            the directive's status, through the closed reason list mapped onto the engine's own
--                        reason_code (the contract reason kept verbatim in payload.ack), and one signed directive.ack
--                        event.
--   (f) The twin depot (rule 8, the only depot it is set for) gets its geofence: the stalls' convex hull, buffered by
--       50 m. No function, view or app reads depots.geofence today (the grid fixture builder copies a depot without it).
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   No tick path calls anything here, and no tick path reads ottow_api_keys, the new tables, or depots.geofence.
--   ottoq-ingest is untouched (the old door stays until nothing uses it). Every run, pair and dial arm behaves byte for
--   byte as before. V1 exercises the door inside a sub-block that rolls back, so the apply leaves no packet, SoC,
--   exception, command status or event behind.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0650_pre' (it returns the twin depot's geofence to
--   NULL). Dropping the three tables, the five functions and the column needs a person at the connector's prompt.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0650 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE v_cat text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0649_source_keys_are_issued_by_the_platform_and_bind_a_depot_and_a_data_source') THEN
    RAISE EXCEPTION '0650 P1: 0649 is not classified; apply in order';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottow_api_keys'
                AND column_name = 'fleet_operator_ids') THEN
    RAISE EXCEPTION '0650 P1: ottow_api_keys.fleet_operator_ids exists already';
  END IF;
  IF to_regclass('public.ottoq_v2_inbox') IS NOT NULL OR to_regclass('public.ottoq_v2_cursors') IS NOT NULL
     OR to_regclass('public.ottoq_v2_signal_ttl') IS NOT NULL THEN
    RAISE EXCEPTION '0650 P1: a table this file creates exists already';
  END IF;
  IF to_regprocedure('public.ottoq_v2_take_events(text,jsonb,boolean)') IS NOT NULL
     OR to_regprocedure('public.ottoq_scope_source_key(uuid,uuid[])') IS NOT NULL
     OR to_regprocedure('ottoq.ottoq_v2_take_one(uuid,uuid,uuid,timestamptz,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION '0650 P1: a function this file creates exists already';
  END IF;
  IF to_regprocedure('public.ottoq_ingest_vehicle_signal(uuid,numeric,numeric,text)') IS NULL THEN
    RAISE EXCEPTION '0650 P1: ottoq_ingest_vehicle_signal(uuid,numeric,numeric,text) is missing';
  END IF;
  IF (SELECT pg_get_function_identity_arguments(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'ottoq_record_event') IS DISTINCT FROM
     'p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid, p_payload jsonb, p_actor_id text, p_actor_metadata jsonb, p_fleet_operator_id uuid, p_depot_id uuid, p_previous_state jsonb, p_new_state jsonb, p_severity text, p_correlation_id uuid, p_parent_event_id uuid, p_related_task_id uuid, p_related_schedule_id uuid, p_related_decision_id uuid, p_outcome text, p_latency_ms integer, p_ingest_source text, p_signing_key_id text, p_data_source text, p_sim_run_id uuid' THEN
    RAISE EXCEPTION '0650 P1: ottoq_record_event is not the signature this file calls';
  END IF;
  -- every fault category the contract allows is an exception_type label
  SELECT string_agg(c, ',') INTO v_cat
    FROM unnest(ARRAY['vehicle_damage', 'vehicle_malfunction', 'sensor_anomaly', 'tire_issue', 'excessive_contamination',
                      'vehicle_unresponsive', 'safety_concern', 'other']) c
   WHERE NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                      WHERE t.typname = 'exception_type' AND e.enumlabel = c);
  IF v_cat IS NOT NULL THEN
    RAISE EXCEPTION '0650 P1: exception_type lacks %', v_cat;
  END IF;
  -- the engine reason codes the ack mapping writes
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
       WHERE conname = 'ottoq_vehicle_commands_reason_code_check' AND conrelid = 'public.ottoq_vehicle_commands'::regclass)
     IS DISTINCT FROM 'CHECK (((reason_code IS NULL) OR (reason_code = ANY (ARRAY[''target_occupied''::text, ''resource_faulted''::text, ''target_unknown''::text, ''vehicle_unresponsive''::text, ''command_malformed''::text, ''no_capacity''::text, ''superseded''::text, ''vehicle_state_incompatible''::text, ''run_ended''::text, ''vehicle_declined''::text]))))' THEN
    RAISE EXCEPTION '0650 P1: ottoq_vehicle_commands_reason_code_check is not the constraint this file maps onto';
  END IF;
  IF (SELECT geofence FROM public.depots WHERE id = '11111111-1111-1111-1111-111111111111') IS NOT NULL THEN
    RAISE EXCEPTION '0650 P1: the twin depot has a geofence already';
  END IF;
  IF (SELECT count(*) FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                                         AND absolute_point IS NOT NULL) < 100 THEN
    RAISE EXCEPTION '0650 P1: the twin depot''s stalls do not carry their positions';
  END IF;
END $premises$;

-- ── snapshot: the one existing value this file changes ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0650_pre', 'data', 'public', 'depots.geofence (twin depot)', d.def, md5(d.def)
  FROM (SELECT 'UPDATE public.depots SET geofence = NULL WHERE id = ''11111111-1111-1111-1111-111111111111'';' AS def) d;

-- ── (a) a key names the fleets it speaks for ──
ALTER TABLE public.ottow_api_keys ADD COLUMN fleet_operator_ids uuid[];
COMMENT ON COLUMN public.ottow_api_keys.fleet_operator_ids IS
  '0650: the fleets whose cars this key speaks for. NULL = none, so the v2 door takes no car''s event from it. Set by '
  'ottoq_scope_source_key only.';

CREATE OR REPLACE FUNCTION public.ottoq_scope_source_key(p_key_id uuid, p_fleet_operator_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_row public.ottow_api_keys%ROWTYPE; v_unknown int;
BEGIN
  /* 0650: the only way a key comes to speak for a fleet's cars. The v2 door names the operator in each event's source
     (urn:ottoq:src:<source_name>:<car>), so a key whose source_name cannot appear there is refused here, not there. */
  SELECT * INTO v_row FROM public.ottow_api_keys WHERE id = p_key_id;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'ottoq_scope_source_key: no key %', p_key_id;
  END IF;
  IF v_row.source_name !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' THEN
    RAISE EXCEPTION 'ottoq_scope_source_key: source_name % cannot name an operator in urn:ottoq:src:<operator>:<car>', v_row.source_name;
  END IF;
  SELECT count(*) INTO v_unknown FROM unnest(COALESCE(p_fleet_operator_ids, ARRAY[]::uuid[])) f
   WHERE NOT EXISTS (SELECT 1 FROM public.fleet_operators o WHERE o.id = f);
  IF v_unknown > 0 THEN
    RAISE EXCEPTION 'ottoq_scope_source_key: % fleet operator id(s) do not exist', v_unknown;
  END IF;
  PERFORM set_config('ottoq.source_key_door', 'on', true);
  UPDATE public.ottow_api_keys
     SET fleet_operator_ids = NULLIF(ARRAY(SELECT DISTINCT f FROM unnest(p_fleet_operator_ids) f ORDER BY f), ARRAY[]::uuid[])
   WHERE id = p_key_id
  RETURNING * INTO v_row;
  PERFORM set_config('ottoq.source_key_door', 'off', true);
  RETURN jsonb_build_object('id', v_row.id, 'key_prefix', v_row.key_prefix, 'source_name', v_row.source_name,
                            'fleet_operator_ids', to_jsonb(v_row.fleet_operator_ids));
END $fn$;

-- ── (b) the inbox and the cursors ──
CREATE TABLE public.ottoq_v2_inbox (
  inbox_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  received_at  timestamptz NOT NULL DEFAULT now(),
  key_id       uuid NOT NULL REFERENCES public.ottow_api_keys (id),
  source_name  text NOT NULL,
  depot_id     uuid NOT NULL REFERENCES public.depots (id),
  data_source  text NOT NULL CHECK (data_source IN ('production', 'twin', 'replay', 'shadow')),
  sim_run_id   uuid REFERENCES public.ottoq_sim_runs (sim_run_id),
  clock_at     timestamptz NOT NULL,
  ce_id        text NOT NULL,
  ce_source    text NOT NULL,
  ce_type      text NOT NULL,
  ce_time      timestamptz NOT NULL,
  ce_subject   text,
  ce_sequence  text NOT NULL,
  vehicle_id   uuid REFERENCES public.vehicles (id),
  disposition  text NOT NULL CHECK (disposition IN ('applied', 'late')),
  detail       jsonb NOT NULL DEFAULT '{}'::jsonb,
  event        jsonb NOT NULL,
  CONSTRAINT ottoq_v2_inbox_once UNIQUE NULLS NOT DISTINCT (source_name, ce_source, ce_id, sim_run_id)
);
CREATE INDEX ottoq_v2_inbox_vehicle_time ON public.ottoq_v2_inbox (vehicle_id, ce_time DESC);
CREATE INDEX ottoq_v2_inbox_run ON public.ottoq_v2_inbox (sim_run_id) WHERE sim_run_id IS NOT NULL;
COMMENT ON TABLE public.ottoq_v2_inbox IS
  '0650: every event the v2 door accepted, as sent, with when (received_at, and clock_at on the data source''s clock) '
  'and what it did (disposition, detail). A refused event is not stored. A twin or replay key''s rows carry the run '
  'whose clock judged them and go with it; a production key''s rows carry none and are kept.';

CREATE TABLE public.ottoq_v2_cursors (
  cursor_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_name    text NOT NULL,
  ce_source      text NOT NULL,
  sim_run_id     uuid REFERENCES public.ottoq_sim_runs (sim_run_id),
  last_sequence  text,
  applied        bigint NOT NULL DEFAULT 0,
  late           bigint NOT NULL DEFAULT 0,
  gaps           numeric NOT NULL DEFAULT 0,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_v2_cursors_one UNIQUE NULLS NOT DISTINCT (source_name, ce_source, sim_run_id)
);
CREATE INDEX ottoq_v2_cursors_run ON public.ottoq_v2_cursors (sim_run_id) WHERE sim_run_id IS NOT NULL;
COMMENT ON TABLE public.ottoq_v2_cursors IS
  '0650: per operator and event source (one car), the last sequence applied. An event at or below it is late: stored, '
  'never applied over newer state. gaps counts sequence numbers skipped; a gap is never waited for.';

-- ── (c) how long a signal stays true ──
CREATE TABLE public.ottoq_v2_signal_ttl (
  data_source text NOT NULL CHECK (data_source IN ('production', 'twin', 'replay', 'shadow')),
  vss_path    text NOT NULL,
  ttl_s       integer NOT NULL CHECK (ttl_s > 0),
  note        text,
  PRIMARY KEY (data_source, vss_path)
);
COMMENT ON TABLE public.ottoq_v2_signal_ttl IS
  '0650: contract/README.md rule 2. A signal older than its TTL, on the data source''s clock, reads as unknown. '
  'Production and shadow carry the README defaults (chosen for depot decisions, not measured). Twin and replay carry '
  'none until step 4 sets them against the run''s tick length.';
INSERT INTO public.ottoq_v2_signal_ttl (data_source, vss_path, ttl_s, note)
SELECT ds, p.path, p.ttl, 'contract/README.md rule 2 default (0650)'
  FROM unnest(ARRAY['production', 'shadow']) ds
 CROSS JOIN (VALUES
   ('Vehicle.Powertrain.TractionBattery.StateOfCharge.Current', 120),
   ('Vehicle.Powertrain.TractionBattery.StateOfCharge.Displayed', 120),
   ('Vehicle.Powertrain.TractionBattery.CurrentPower', 60),
   ('Vehicle.Powertrain.TractionBattery.Charging.IsCharging', 60),
   ('Vehicle.Powertrain.TractionBattery.Charging.TimeToComplete', 120),
   ('Vehicle.Speed', 60),
   ('Vehicle.CurrentLocation.Latitude', 60),
   ('Vehicle.CurrentLocation.Longitude', 60),
   ('Vehicle.Powertrain.TractionBattery.Temperature.Average', 300),
   ('Vehicle.Powertrain.TractionBattery.Range', 300),
   ('Vehicle.Powertrain.Range', 300),
   ('Vehicle.Diagnostics.DTCList', 300),
   ('Vehicle.Exterior.AirTemperature', 900),
   ('Vehicle.TraveledDistance', 3600),
   ('Vehicle.Chassis.Axle.Row1.Wheel.Left.Tire.Pressure', 3600),
   ('Vehicle.Chassis.Axle.Row1.Wheel.Right.Tire.Pressure', 3600),
   ('Vehicle.Chassis.Axle.Row2.Wheel.Left.Tire.Pressure', 3600),
   ('Vehicle.Chassis.Axle.Row2.Wheel.Right.Tire.Pressure', 3600),
   ('Vehicle.Powertrain.TractionBattery.Charging.ChargeLimit', 86400),
   ('Vehicle.Powertrain.TractionBattery.StateOfHealth', 604800),
   ('Vehicle.Powertrain.TractionBattery.NetCapacity', 604800)) AS p(path, ttl);

ALTER TABLE public.ottoq_v2_inbox      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_v2_cursors    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_v2_signal_ttl ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_v2_inbox, public.ottoq_v2_cursors, public.ottoq_v2_signal_ttl FROM anon, authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_v2_inbox', 'sim_run_id', 'engine',
        '0650: the run whose clock judged a twin or replay key''s event. Engine, with its foreign key: those rows go '
        'with their run. A production or shadow key''s rows carry NULL and are never purged.'),
       ('public', 'ottoq_v2_cursors', 'sim_run_id', 'engine',
        '0650: a twin or replay key''s order is per run, so its cursor goes with the run; a production key''s has NULL.');

-- ── the signed event an ack leaves ──
INSERT INTO public.ottoq_event_types_catalog (event_type, category, description, emitter, default_severity, introduced_in)
VALUES ('directive.ack', 'integration_event',
        'An operator''s answer to one version of one directive, taken by the v2 door: accepted, rejected or unable, '
        'with a reason from the contract''s closed list (contract/README.md rule 9).',
        'operator_door_v2', 'info', '0650')
ON CONFLICT (event_type) DO NOTHING;

-- ── (d) the door: helpers ──
CREATE OR REPLACE FUNCTION ottoq.ottoq_v2_tstz(p text)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  /* 0650: an RFC 3339 time with an offset, or NULL. A well-formed but impossible date (2026-02-30) is NULL too. */
  IF p IS NULL OR p !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$' THEN
    RETURN NULL;
  END IF;
  RETURN p::timestamptz;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END $fn$;

CREATE OR REPLACE FUNCTION ottoq.ottoq_v2_num(p_signals jsonb, p_path text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $fn$
  /* 0650: a signal's value when it is a JSON number, else NULL. */
  SELECT CASE WHEN jsonb_typeof(p_signals -> p_path -> 'value') = 'number'
              THEN (p_signals -> p_path ->> 'value')::numeric END
$fn$;

-- ── (e) the door: what an event in order does ──
CREATE OR REPLACE FUNCTION ottoq.ottoq_v2_apply(
  p_key_id uuid, p_engine_run uuid, p_clock timestamptz, p_type text, p_vehicle uuid, p_time timestamptz, p_ev jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  k public.ottow_api_keys%ROWTYPE;
  d jsonb := p_ev -> 'data';
  s jsonb;
  v_veh public.vehicles%ROWTYPE;
  v_run_scoped boolean;
  -- telemetry
  v_soc numeric; v_soc_ts timestamptz; v_ttl integer; v_soc_applied boolean := false; v_soc_why text;
  v_lat numeric; v_lng numeric; v_loc text; v_tires numeric[]; v_dtc text[]; v_packet uuid; v_unstored text[];
  -- arrival
  v_eta timestamptz; v_eta_min numeric; v_signal jsonb; v_rows int; v_kept text[]; v_ignored text[];
  -- fault
  v_exc uuid;
  -- ack
  v_cmd public.ottoq_vehicle_commands%ROWTYPE; v_disp text; v_reason text; v_code text; v_status text;
  v_cmd_ds text; v_event uuid;
BEGIN
  SELECT * INTO k FROM public.ottow_api_keys WHERE id = p_key_id;
  SELECT * INTO v_veh FROM public.vehicles WHERE id = p_vehicle;
  v_run_scoped := k.data_source IN ('twin', 'replay');

  CASE p_type
  -- ────────────────────────────────────────────────────────────────────────────────────────────────── telemetry
  WHEN 'com.ottoyard.vehicle.telemetry' THEN
    s := d -> 'signals';
    IF jsonb_typeof(s) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'telemetry carries no signals object' USING ERRCODE = 'OQ001';
    END IF;
    v_soc    := ottoq.ottoq_v2_num(s, 'Vehicle.Powertrain.TractionBattery.StateOfCharge.Current');
    v_soc_ts := COALESCE(ottoq.ottoq_v2_tstz(s -> 'Vehicle.Powertrain.TractionBattery.StateOfCharge.Current' ->> 'ts'), p_time);
    -- location: kept only inside the depot (README rule 5)
    v_lat := ottoq.ottoq_v2_num(s, 'Vehicle.CurrentLocation.Latitude');
    v_lng := ottoq.ottoq_v2_num(s, 'Vehicle.CurrentLocation.Longitude');
    IF v_lat IS NULL OR v_lng IS NULL THEN
      v_loc := 'not_sent'; v_lat := NULL; v_lng := NULL;
    ELSIF (SELECT geofence FROM public.depots WHERE id = k.depot_id) IS NULL THEN
      v_loc := 'dropped_no_geofence'; v_lat := NULL; v_lng := NULL;
    ELSIF NOT (SELECT ST_Covers(geofence, ST_SetSRID(ST_MakePoint(v_lng::float8, v_lat::float8), 4326)::geography)
                 FROM public.depots WHERE id = k.depot_id) THEN
      v_loc := 'dropped_outside_geofence'; v_lat := NULL; v_lng := NULL;
    ELSE
      v_loc := 'kept_inside_geofence';
    END IF;
    -- tires: the four together, kPa back to psi, index 1..4 = FL, FR, RL, RR (contract/vss_mapping.json)
    IF ottoq.ottoq_v2_num(s, 'Vehicle.Chassis.Axle.Row1.Wheel.Left.Tire.Pressure') IS NOT NULL
       AND ottoq.ottoq_v2_num(s, 'Vehicle.Chassis.Axle.Row1.Wheel.Right.Tire.Pressure') IS NOT NULL
       AND ottoq.ottoq_v2_num(s, 'Vehicle.Chassis.Axle.Row2.Wheel.Left.Tire.Pressure') IS NOT NULL
       AND ottoq.ottoq_v2_num(s, 'Vehicle.Chassis.Axle.Row2.Wheel.Right.Tire.Pressure') IS NOT NULL THEN
      v_tires := ARRAY[
        round(ottoq.ottoq_v2_num(s, 'Vehicle.Chassis.Axle.Row1.Wheel.Left.Tire.Pressure')  / 6.894757, 2),
        round(ottoq.ottoq_v2_num(s, 'Vehicle.Chassis.Axle.Row1.Wheel.Right.Tire.Pressure') / 6.894757, 2),
        round(ottoq.ottoq_v2_num(s, 'Vehicle.Chassis.Axle.Row2.Wheel.Left.Tire.Pressure')  / 6.894757, 2),
        round(ottoq.ottoq_v2_num(s, 'Vehicle.Chassis.Axle.Row2.Wheel.Right.Tire.Pressure') / 6.894757, 2)];
    END IF;
    IF jsonb_typeof(s -> 'Vehicle.Diagnostics.DTCList' -> 'value') = 'array' THEN
      v_dtc := ARRAY(SELECT jsonb_array_elements_text(s -> 'Vehicle.Diagnostics.DTCList' -> 'value'));
    END IF;
    SELECT array_agg(key ORDER BY key) INTO v_unstored FROM jsonb_object_keys(s) key
     WHERE key IN ('Vehicle.Powertrain.TractionBattery.StateOfCharge.Displayed',
                   'Vehicle.Powertrain.TractionBattery.StateOfHealth', 'Vehicle.Powertrain.TractionBattery.NetCapacity',
                   'Vehicle.Powertrain.TractionBattery.Charging.IsCharging', 'Vehicle.Powertrain.TractionBattery.Charging.ChargeLimit',
                   'Vehicle.Powertrain.TractionBattery.Charging.TimeToComplete', 'Vehicle.Powertrain.Range');

    INSERT INTO public.ottoq_telemetry_packets (
      vehicle_id, sim_run_id, fleet_operator_id, packet_at, sim_clock_at,
      soc_pct, soc_source, battery_temp_c, ambient_temp_c, tire_pressures_psi, speed_kmh, current_lat, current_lng,
      instant_power_kw, vehicle_state, odometer_km, range_remaining_km, dtc_codes, data_source, packet_integrity)
    VALUES (
      p_vehicle, p_engine_run, v_veh.fleet_operator_id, p_time, CASE WHEN v_run_scoped THEN p_time END,
      v_soc, 'oem_telemetry',
      ottoq.ottoq_v2_num(s, 'Vehicle.Powertrain.TractionBattery.Temperature.Average'),
      ottoq.ottoq_v2_num(s, 'Vehicle.Exterior.AirTemperature'),
      v_tires,
      ottoq.ottoq_v2_num(s, 'Vehicle.Speed'),
      v_lat, v_lng,
      -ottoq.ottoq_v2_num(s, 'Vehicle.Powertrain.TractionBattery.CurrentPower') / 1000.0,  -- VSS: positive INTO the battery
      v_veh.current_state::text,                                                             -- the depot's own state
      ottoq.ottoq_v2_num(s, 'Vehicle.TraveledDistance') / 1000.0,
      ottoq.ottoq_v2_num(s, 'Vehicle.Powertrain.TractionBattery.Range') / 1000.0,
      v_dtc, k.data_source, 'full')
    RETURNING packet_id INTO v_packet;

    -- the car's charge, when fresh on the data source's clock (README rule 2)
    IF v_soc IS NOT NULL THEN
      SELECT ttl_s INTO v_ttl FROM public.ottoq_v2_signal_ttl
       WHERE data_source = k.data_source AND vss_path = 'Vehicle.Powertrain.TractionBattery.StateOfCharge.Current';
      IF v_ttl IS NOT NULL AND v_soc_ts < p_clock - make_interval(secs => v_ttl) THEN
        v_soc_why := 'stale';
      ELSE
        UPDATE public.vehicles
           SET current_soc = round(v_soc)::int, current_soc_updated_at = v_soc_ts, current_soc_source = 'oem_telemetry'
         WHERE id = p_vehicle;
        v_soc_applied := true;
        v_soc_why := CASE WHEN v_ttl IS NULL THEN 'applied_no_ttl_for_' || k.data_source ELSE 'applied_fresh' END;
      END IF;
    END IF;
    RETURN jsonb_strip_nulls(jsonb_build_object(
      'effect', 'telemetry_packet', 'packet_id', v_packet, 'soc', v_soc_why, 'location', v_loc,
      'kept_in_inbox_only', to_jsonb(v_unstored)));

  -- ───────────────────────────────────────────────────────────────────────────────────────────── arrival intent
  WHEN 'com.ottoyard.depot.arrival.intent' THEN
    v_eta := ottoq.ottoq_v2_tstz(d ->> 'eta');
    IF v_eta IS NULL THEN
      RAISE EXCEPTION 'eta is not an RFC 3339 time' USING ERRCODE = 'OQ001';
    END IF;
    v_eta_min := round(extract(epoch FROM (v_eta - p_clock)) / 60.0, 1);
    v_signal := public.ottoq_ingest_vehicle_signal(
      p_vehicle,
      CASE WHEN jsonb_typeof(d -> 'predicted_soc_pct') = 'number' THEN (d ->> 'predicted_soc_pct')::numeric END,
      greatest(v_eta_min, 0), 'v2:' || k.source_name);
    UPDATE public.vehicles SET current_state = 'en_route_to_depot'::vehicle_state, last_state_change = p_clock
     WHERE id = p_vehicle AND current_state::text IN ('deployed', 'offline', 'en_route_to_deployment');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    SELECT array_agg(f ORDER BY f) INTO v_kept FROM unnest(ARRAY['services_needed', 'ready_by', 'eta_spread_s']) f WHERE d ? f;
    IF d ? 'charge_target_pct' THEN
      v_ignored := ARRAY['charge_target_pct: only the owner''s own settings set a car''s target (CLAUDE.md rule 9)'];
    END IF;
    RETURN jsonb_strip_nulls(jsonb_build_object(
      'effect', 'return_signal', 'eta_min', v_eta_min, 'marked_en_route', v_rows > 0, 'signal', v_signal,
      'kept_in_inbox_only', to_jsonb(v_kept), 'not_applied', to_jsonb(v_ignored)));

  -- ────────────────────────────────────────────────────────────────────────────────────────────── fault summary
  WHEN 'com.ottoyard.vehicle.fault.summary' THEN
    INSERT INTO public.exceptions (vehicle_id, depot_id, exception_type, severity, status, title, description, metadata, data_source)
    VALUES (p_vehicle, k.depot_id, (d ->> 'category')::exception_type, (d ->> 'severity')::exception_severity, 'open',
            'Operator fault: ' || replace(d ->> 'category', '_', ' '),
            COALESCE(d ->> 'description', 'Reported by ' || k.source_name || ' through the v2 door.'),
            jsonb_strip_nulls(jsonb_build_object(
              'door', 'v2', 'operator', k.source_name, 'ce_id', p_ev ->> 'id', 'ce_source', p_ev ->> 'source',
              'observed_at', p_time, 'services_needed', d -> 'services_needed',
              'takes_vehicle_offline', d -> 'takes_vehicle_offline', 'fault_codes', d -> 'fault_codes')),
            k.data_source)
    RETURNING id INTO v_exc;
    RETURN jsonb_build_object('effect', 'exception', 'exception_id', v_exc);

  -- ─────────────────────────────────────────────────────────────────────────────────────────────────── departed
  WHEN 'com.ottoyard.vehicle.departed' THEN
    RETURN jsonb_build_object('effect', 'kept_in_inbox_only',
      'why', 'the depot''s release of what it held for the car is wired when the twin sends departures (step 4)');

  -- ──────────────────────────────────────────────────────────────────────────────────────────────────────── ack
  WHEN 'com.ottoyard.directive.ack' THEN
    IF k.data_source NOT IN ('production', 'twin') THEN
      RAISE EXCEPTION 'acks_not_taken_for_%', k.data_source USING ERRCODE = 'OQ001';
    END IF;
    v_cmd_ds := k.data_source;
    SELECT * INTO v_cmd FROM public.ottoq_vehicle_commands c
     WHERE c.command_id::text = d ->> 'directive_id' AND c.vehicle_id = p_vehicle
       AND c.depot_id = k.depot_id AND c.data_source = v_cmd_ds;
    IF v_cmd.command_id IS NULL THEN
      RAISE EXCEPTION 'directive_not_found' USING ERRCODE = 'OQ001';
    END IF;
    IF jsonb_typeof(d -> 'directive_version') IS DISTINCT FROM 'number' OR (d ->> 'directive_version') <> '1' THEN
      RAISE EXCEPTION 'directive_version_unknown' USING ERRCODE = 'OQ001';
    END IF;
    v_disp   := d ->> 'disposition';
    v_reason := d ->> 'reason';
    IF v_disp IS NULL OR v_disp NOT IN ('accepted', 'rejected', 'unable')
       OR (v_disp = 'accepted' AND v_reason IS NOT NULL)
       OR (v_disp <> 'accepted' AND (v_reason IS NULL OR v_reason NOT IN (
             'occupied', 'vehicle_unresponsive', 'unsafe', 'charger_fault', 'vehicle_not_at_depot', 'owner_override',
             'expired', 'superseded', 'other')))
       OR (v_reason = 'other' AND COALESCE(d ->> 'detail', '') = '') THEN
      RAISE EXCEPTION 'ack_disposition_or_reason' USING ERRCODE = 'OQ001';
    END IF;
    IF v_cmd.status <> 'issued' THEN
      RETURN jsonb_build_object('effect', 'already_terminal', 'directive_id', v_cmd.command_id, 'status', v_cmd.status);
    END IF;
    -- the contract's closed reasons onto the engine's (the contract reason itself is kept verbatim in payload.ack)
    v_code := CASE v_reason
      WHEN 'occupied'             THEN 'target_occupied'
      WHEN 'charger_fault'        THEN 'resource_faulted'
      WHEN 'vehicle_unresponsive' THEN 'vehicle_unresponsive'
      WHEN 'superseded'           THEN 'superseded'
      WHEN 'vehicle_not_at_depot' THEN 'vehicle_state_incompatible'
      WHEN 'owner_override'       THEN 'vehicle_declined'
      WHEN 'unsafe'               THEN 'vehicle_declined'
      WHEN 'other'                THEN 'vehicle_declined'
      ELSE NULL END;
    v_status := CASE WHEN v_disp = 'accepted' THEN 'confirmed' WHEN v_reason = 'expired' THEN 'expired' ELSE 'refused' END;
    UPDATE public.ottoq_vehicle_commands
       SET status        = v_status,
           confirmed_at  = p_clock,
           confirmed_by  = 'operator:' || k.source_name,
           reason_code   = CASE WHEN v_status = 'refused' THEN v_code ELSE reason_code END,
           reason_detail = CASE WHEN v_status = 'confirmed' THEN reason_detail ELSE COALESCE(d ->> 'detail', reason_detail) END,
           payload       = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('ack', jsonb_strip_nulls(jsonb_build_object(
                             'disposition', v_disp, 'reason', v_reason, 'detail', d ->> 'detail',
                             'observed_at', d ->> 'observed_at', 'ce_id', p_ev ->> 'id', 'door', 'v2')))
     WHERE command_id = v_cmd.command_id;
    v_event := public.ottoq_record_event(
      p_actor_type := 'oem_dispatch_webhook', p_actor_id := k.source_name,
      p_event_type := 'directive.ack', p_entity_type := 'vehicle', p_entity_id := p_vehicle,
      p_payload := jsonb_strip_nulls(jsonb_build_object(
        'directive_id', v_cmd.command_id, 'command_type', v_cmd.command_type, 'disposition', v_disp,
        'reason', v_reason, 'engine_status', v_status, 'engine_reason_code', CASE WHEN v_status = 'refused' THEN v_code END,
        'ce_id', p_ev ->> 'id')),
      p_fleet_operator_id := v_veh.fleet_operator_id, p_depot_id := k.depot_id,
      p_severity := CASE WHEN v_disp = 'accepted' THEN 'info' ELSE 'warning' END,
      p_ingest_source := 'v2_door', p_data_source := k.data_source, p_sim_run_id := v_cmd.sim_run_id);
    RETURN jsonb_strip_nulls(jsonb_build_object(
      'effect', 'directive_status', 'directive_id', v_cmd.command_id, 'status', v_status,
      'reason_code', CASE WHEN v_status = 'refused' THEN v_code END, 'event_id', v_event));
  ELSE
    RAISE EXCEPTION 'type_not_inbound' USING ERRCODE = 'OQ001';
  END CASE;
END $fn$;

-- ── (d) the door: one event ──
CREATE OR REPLACE FUNCTION ottoq.ottoq_v2_take_one(p_key_id uuid, p_run uuid, p_engine_run uuid, p_clock timestamptz, p_ev jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  k public.ottow_api_keys%ROWTYPE;
  v_id text := p_ev ->> 'id'; v_source text := p_ev ->> 'source'; v_type text := p_ev ->> 'type';
  v_seq text := p_ev ->> 'sequence'; v_subject text := p_ev ->> 'subject';
  v_time timestamptz; v_op text; v_ref text; v_stream text; v_vehicle uuid; v_n int;
  v_cur public.ottoq_v2_cursors%ROWTYPE; v_disp text; v_detail jsonb; v_refuse text; v_gap numeric;
BEGIN
  SELECT * INTO k FROM public.ottow_api_keys WHERE id = p_key_id;
  BEGIN
    -- 1. the fields this door's own logic reads (the whole schema is the HTTP door's: contract/schemas)
    v_time := ottoq.ottoq_v2_tstz(p_ev ->> 'time');
    v_refuse := CASE
      WHEN jsonb_typeof(p_ev) IS DISTINCT FROM 'object'             THEN 'not_an_event'
      WHEN p_ev ->> 'specversion' IS DISTINCT FROM '1.0'             THEN 'specversion'
      WHEN COALESCE(length(v_id), 0) NOT BETWEEN 1 AND 128           THEN 'id'
      WHEN v_type IS NULL OR v_type NOT IN ('com.ottoyard.vehicle.telemetry', 'com.ottoyard.depot.arrival.intent',
             'com.ottoyard.vehicle.fault.summary', 'com.ottoyard.vehicle.departed', 'com.ottoyard.directive.ack')
                                                                     THEN 'type_not_inbound'
      WHEN v_source IS NULL OR v_source !~ '^urn:ottoq:src:[a-z0-9][a-z0-9_.-]{0,62}:[A-Za-z0-9._:-]{1,64}$'
                                                                     THEN 'source'
      WHEN v_seq IS NULL OR v_seq !~ '^[0-9]{20}$'                   THEN 'sequence'
      WHEN v_time IS NULL                                            THEN 'time'
      WHEN p_ev ->> 'dataschema' IS DISTINCT FROM
           'https://ottoyard.com/schemas/ottoq/contract/0.1/' || substr(v_type, 14) || '.json'
                                                                     THEN 'dataschema'
      WHEN jsonb_typeof(p_ev -> 'data') IS DISTINCT FROM 'object'    THEN 'data'
      WHEN p_ev ? 'ottoqsig'                                         THEN 'operator_events_are_not_signed'
      ELSE NULL END;
    IF v_refuse IS NULL THEN
      v_op  := split_part(substr(v_source, 15), ':', 1);      -- urn:ottoq:src: is 14 characters
      v_ref := substr(v_source, 15 + length(v_op) + 1);
      v_refuse := CASE
        WHEN v_op <> k.source_name             THEN 'source_is_not_this_key'
        WHEN v_subject IS DISTINCT FROM v_ref  THEN 'subject_is_not_the_source_car'
        ELSE NULL END;
    END IF;
    -- 2. the stream (an ack needs none: it answers a directive this key's own operator was sent)
    IF v_refuse IS NULL THEN
      v_stream := CASE v_type
        WHEN 'com.ottoyard.vehicle.telemetry'     THEN 'telemetry'
        WHEN 'com.ottoyard.depot.arrival.intent'  THEN 'arrival'
        WHEN 'com.ottoyard.vehicle.departed'      THEN 'arrival'
        WHEN 'com.ottoyard.vehicle.fault.summary' THEN 'incident'
        ELSE NULL END;
      IF v_stream IS NOT NULL AND NOT (v_stream = ANY (COALESCE(k.streams, ARRAY[]::text[]))) THEN
        v_refuse := 'stream_not_allowed';
      END IF;
    END IF;
    -- 3. the car, among the key's own fleets at the key's depot; anything else reads as not found
    IF v_refuse IS NULL THEN
      IF COALESCE(cardinality(k.fleet_operator_ids), 0) = 0 THEN
        v_refuse := 'key_speaks_for_no_fleet';
      ELSE
        SELECT count(*), (array_agg(v.id))[1] INTO v_n, v_vehicle FROM public.vehicles v
         WHERE v.display_name = v_ref AND v.fleet_operator_id = ANY (k.fleet_operator_ids)
           AND (v.home_depot_id = k.depot_id OR v.current_depot_id = k.depot_id);
        IF v_n = 0 THEN v_refuse := 'vehicle_not_found'; v_vehicle := NULL;
        ELSIF v_n > 1 THEN v_refuse := 'vehicle_ref_ambiguous'; v_vehicle := NULL;
        END IF;
      END IF;
    END IF;
    IF v_refuse IS NOT NULL THEN
      RETURN jsonb_build_object('id', v_id, 'source', v_source, 'disposition', 'refused', 'reason', v_refuse);
    END IF;

    -- 4. once. The cursor row is locked first, so a concurrent copy of this event waits here and then sees it.
    INSERT INTO public.ottoq_v2_cursors (source_name, ce_source, sim_run_id) VALUES (k.source_name, v_source, p_run)
    ON CONFLICT (source_name, ce_source, sim_run_id) DO NOTHING;
    SELECT * INTO v_cur FROM public.ottoq_v2_cursors
     WHERE source_name = k.source_name AND ce_source = v_source AND sim_run_id IS NOT DISTINCT FROM p_run
     FOR UPDATE;
    IF EXISTS (SELECT 1 FROM public.ottoq_v2_inbox i
                WHERE i.source_name = k.source_name AND i.ce_source = v_source AND i.ce_id = v_id
                  AND i.sim_run_id IS NOT DISTINCT FROM p_run) THEN
      RETURN jsonb_build_object('id', v_id, 'source', v_source, 'disposition', 'duplicate');
    END IF;

    -- 5. in order, or late. Applying runs in its own subtransaction: a failure refuses this event and moves nothing.
    IF v_cur.last_sequence IS NULL OR v_seq > v_cur.last_sequence THEN
      BEGIN
        v_detail := ottoq.ottoq_v2_apply(k.id, p_engine_run, p_clock, v_type, v_vehicle, v_time, p_ev);
      EXCEPTION
        WHEN SQLSTATE 'OQ001' THEN
          RETURN jsonb_build_object('id', v_id, 'source', v_source, 'disposition', 'refused', 'reason', SQLERRM);
        WHEN OTHERS THEN
          RETURN jsonb_build_object('id', v_id, 'source', v_source, 'disposition', 'refused', 'reason', 'apply_failed',
                                    'sqlstate', SQLSTATE, 'detail', SQLERRM);
      END;
      v_disp := 'applied';
      v_gap := CASE WHEN v_cur.last_sequence IS NULL THEN 0
                    ELSE greatest(v_seq::numeric - v_cur.last_sequence::numeric - 1, 0) END;
      UPDATE public.ottoq_v2_cursors
         SET last_sequence = v_seq, applied = applied + 1, gaps = gaps + v_gap, updated_at = now()
       WHERE cursor_id = v_cur.cursor_id;
      IF v_gap > 0 THEN
        v_detail := v_detail || jsonb_build_object('gap_before', v_gap);
      END IF;
    ELSE
      v_disp := 'late';
      v_detail := jsonb_build_object('last_applied_sequence', v_cur.last_sequence);
      UPDATE public.ottoq_v2_cursors SET late = late + 1, updated_at = now() WHERE cursor_id = v_cur.cursor_id;
    END IF;

    INSERT INTO public.ottoq_v2_inbox (key_id, source_name, depot_id, data_source, sim_run_id, clock_at, ce_id, ce_source,
                                       ce_type, ce_time, ce_subject, ce_sequence, vehicle_id, disposition, detail, event)
    VALUES (k.id, k.source_name, k.depot_id, k.data_source, p_run, p_clock, v_id, v_source,
            v_type, v_time, v_subject, v_seq, v_vehicle, v_disp, v_detail, p_ev);
    RETURN jsonb_build_object('id', v_id, 'source', v_source, 'disposition', v_disp, 'detail', v_detail);
  EXCEPTION
    WHEN unique_violation THEN
      RETURN jsonb_build_object('id', v_id, 'source', v_source, 'disposition', 'duplicate');
    WHEN OTHERS THEN
      RETURN jsonb_build_object('id', v_id, 'source', v_source, 'disposition', 'refused', 'reason', 'error',
                                'sqlstate', SQLSTATE, 'detail', SQLERRM);
  END;
END $fn$;

-- ── (d) the door ──
CREATE OR REPLACE FUNCTION public.ottoq_v2_take_events(p_key_hash text, p_events jsonb, p_dry_run boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  k public.ottow_api_keys%ROWTYPE;
  v_run uuid; v_engine_run uuid; v_clock timestamptz;
  v_ev jsonb; v_res jsonb; v_out jsonb := '[]'::jsonb; v_n int;
BEGIN
  /* 0650: the v2 door (contract/README.md). The HTTP door hashes the X-OTTO-Q-API-Key it was handed (SHA-256,
     lowercase hex) and passes the hash and the events it has already checked against contract/schemas. */
  SELECT * INTO k FROM public.ottow_api_keys WHERE key_hash = p_key_hash AND is_active LIMIT 1;
  IF k.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_or_revoked_key');
  END IF;
  IF jsonb_typeof(p_events) IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'events_must_be_an_array');
  END IF;
  v_n := jsonb_array_length(p_events);
  IF v_n NOT BETWEEN 1 AND 500 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'batch_size', 'detail', '1 to 500 events per request', 'received', v_n);
  END IF;

  -- the data source's clock (README rule 2)
  IF k.data_source IN ('twin', 'replay') THEN
    SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
      FROM public.ottoq_sim_runs r
     WHERE r.depot_id = k.depot_id AND r.status = 'running' AND COALESCE(r.run_by, '') <> 'production_live'
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL OR v_clock IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'no_running_run',
        'detail', 'a twin or replay key is judged on its run''s clock, and no run is running at its depot');
    END IF;
    v_engine_run := v_run;
  ELSE
    v_clock := now();
    SELECT r.sim_run_id INTO v_engine_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = k.depot_id AND r.status = 'running' AND r.run_by = 'production_live'
     ORDER BY r.started_at DESC LIMIT 1;
  END IF;

  UPDATE public.ottow_api_keys SET last_used_at = now() WHERE id = k.id;

  BEGIN
    FOR v_ev IN SELECT value FROM jsonb_array_elements(p_events) LOOP
      v_res := ottoq.ottoq_v2_take_one(k.id, v_run, v_engine_run, v_clock, v_ev);
      v_out := v_out || jsonb_build_array(v_res);
    END LOOP;
    IF p_dry_run THEN
      RAISE EXCEPTION 'ottoq_v2_dry_run';
    END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'ottoq_v2_dry_run' THEN
      RAISE;
    END IF;
  END;

  RETURN jsonb_build_object(
    'ok', true, 'dry_run', p_dry_run, 'key_prefix', k.key_prefix, 'operator', k.source_name, 'depot_id', k.depot_id,
    'data_source', k.data_source, 'sim_run_id', v_run, 'clock', v_clock, 'received', v_n,
    'applied',   (SELECT count(*) FROM jsonb_array_elements(v_out) r WHERE r ->> 'disposition' = 'applied'),
    'late',      (SELECT count(*) FROM jsonb_array_elements(v_out) r WHERE r ->> 'disposition' = 'late'),
    'duplicate', (SELECT count(*) FROM jsonb_array_elements(v_out) r WHERE r ->> 'disposition' = 'duplicate'),
    'refused',   (SELECT count(*) FROM jsonb_array_elements(v_out) r WHERE r ->> 'disposition' = 'refused'),
    'results', v_out);
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_scope_source_key(uuid,uuid[])                         FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_v2_take_events(text,jsonb,boolean)                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ottoq.ottoq_v2_take_one(uuid,uuid,uuid,timestamptz,jsonb)          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ottoq.ottoq_v2_tstz(text)                                          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ottoq.ottoq_v2_num(jsonb,text)                                     FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_scope_source_key(uuid,uuid[])      TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_v2_take_events(text,jsonb,boolean) TO service_role;

-- ── (f) the twin depot's geofence ──
UPDATE public.depots d
   SET geofence = (SELECT ST_Buffer(ST_ConvexHull(ST_Collect(s.absolute_point::geometry))::geography, 50)
                     FROM public.stalls s WHERE s.depot_id = d.id AND s.absolute_point IS NOT NULL)
 WHERE d.id = '11111111-1111-1111-1111-111111111111';

-- ── V1: the door, end to end, inside a sub-block that rolls back ──
DO $v1$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_fleet uuid; v_other_fleet uuid; v_car text; v_car_id uuid; v_other_car text;
  k jsonb; k2 jsonb; k3 jsonb; h text; h2 text; h3 text; v_t text := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  r_first jsonb; r_again jsonb; r_gap jsonb; r_late jsonb; r_scope jsonb; r_fault jsonb; r_stream jsonb; r_nofleet jsonb;
  r_dry jsonb; r_ack jsonb; r_unknown jsonb;
  v_soc_after_gap int; v_soc_after_late int; v_packet_time timestamptz; v_inbox_dry bigint; v_inbox_before_dry bigint;
  v_exc_title text; v_cursor_gaps numeric; v_inbox_kept bigint;
  v_inbox_rows_before bigint; v_inbox_rows_after bigint;
  v_in_lat float8; v_in_lng float8; r_in jsonb; r_out jsonb; v_in_pkt record; v_out_pkt record; v_power numeric;
BEGIN
  SELECT count(*) INTO v_inbox_rows_before FROM public.ottoq_v2_inbox;
  -- a car and its fleet at the twin depot, and a car of another fleet there
  SELECT v.fleet_operator_id, v.display_name, v.id INTO v_fleet, v_car, v_car_id FROM public.vehicles v
   WHERE v.home_depot_id = v_twin AND v.fleet_operator_id IS NOT NULL ORDER BY v.display_name LIMIT 1;
  SELECT v.fleet_operator_id, v.display_name INTO v_other_fleet, v_other_car FROM public.vehicles v
   WHERE v.home_depot_id = v_twin AND v.fleet_operator_id IS NOT NULL AND v.fleet_operator_id <> v_fleet
   ORDER BY v.display_name LIMIT 1;
  IF v_car IS NULL OR v_other_car IS NULL THEN RAISE EXCEPTION '0650 V1: the twin depot lacks two fleets to probe with'; END IF;
  SELECT ST_Y(s.absolute_point::geometry), ST_X(s.absolute_point::geometry) INTO v_in_lat, v_in_lng
    FROM public.stalls s WHERE s.depot_id = v_twin AND s.absolute_point IS NOT NULL ORDER BY s.stall_code LIMIT 1;

  BEGIN
    -- a production-data key (wall clock, so the probe needs no running run), two streams and one fleet
    k := public.ottoq_issue_source_key(v_twin, 'fleet_api', 'probe-0650', 'production', ARRAY['telemetry', 'arrival', 'incident']);
    PERFORM public.ottoq_scope_source_key((k->>'id')::uuid, ARRAY[v_fleet]);
    h := encode(extensions.digest(k->>'key', 'sha256'), 'hex');
    -- a key without the incident stream, and a key with no fleet
    k2 := public.ottoq_issue_source_key(v_twin, 'fleet_api', 'probe-0650', 'production', ARRAY['telemetry']);
    PERFORM public.ottoq_scope_source_key((k2->>'id')::uuid, ARRAY[v_fleet]);
    h2 := encode(extensions.digest(k2->>'key', 'sha256'), 'hex');
    k3 := public.ottoq_issue_source_key(v_twin, 'fleet_api', 'probe-0650', 'production', ARRAY['telemetry']);
    h3 := encode(extensions.digest(k3->>'key', 'sha256'), 'hex');

    r_first := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-1', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.telemetry', 'time', v_t, 'sequence', '00000000000000000001',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.telemetry.json',
      'data', jsonb_build_object('signals', jsonb_build_object(
        'Vehicle.Powertrain.TractionBattery.StateOfCharge.Current', jsonb_build_object('value', 41.4, 'ts', v_t),
        'Vehicle.Powertrain.TractionBattery.CurrentPower', jsonb_build_object('value', -11800, 'ts', v_t))))));
    SELECT packet_at, instant_power_kw INTO v_packet_time, v_power FROM public.ottoq_telemetry_packets
     WHERE packet_id = (r_first->'results'->0->'detail'->>'packet_id')::uuid;
    r_again := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-1', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.telemetry', 'time', v_t, 'sequence', '00000000000000000001',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.telemetry.json',
      'data', jsonb_build_object('signals', jsonb_build_object(
        'Vehicle.Powertrain.TractionBattery.StateOfCharge.Current', jsonb_build_object('value', 41.4, 'ts', v_t))))));
    -- sequence 3 after 1: applied, one gap
    r_gap := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-3', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.telemetry', 'time', v_t, 'sequence', '00000000000000000003',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.telemetry.json',
      'data', jsonb_build_object('signals', jsonb_build_object(
        'Vehicle.Powertrain.TractionBattery.StateOfCharge.Current', jsonb_build_object('value', 63, 'ts', v_t))))));
    SELECT current_soc INTO v_soc_after_gap FROM public.vehicles WHERE id = v_car_id;
    -- sequence 2 now: late, never applied over 3
    r_late := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-2', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.telemetry', 'time', v_t, 'sequence', '00000000000000000002',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.telemetry.json',
      'data', jsonb_build_object('signals', jsonb_build_object(
        'Vehicle.Powertrain.TractionBattery.StateOfCharge.Current', jsonb_build_object('value', 12, 'ts', v_t))))));
    SELECT current_soc INTO v_soc_after_late FROM public.vehicles WHERE id = v_car_id;
    SELECT gaps INTO v_cursor_gaps FROM public.ottoq_v2_cursors
     WHERE source_name = 'probe-0650' AND ce_source = 'urn:ottoq:src:probe-0650:' || v_car AND sim_run_id IS NULL;
    -- another fleet's car, and a source naming another operator, in one batch
    r_scope := public.ottoq_v2_take_events(h, jsonb_build_array(
      jsonb_build_object('specversion', '1.0', 'id', 'p-x', 'source', 'urn:ottoq:src:probe-0650:' || v_other_car,
        'subject', v_other_car, 'type', 'com.ottoyard.vehicle.departed', 'time', v_t, 'sequence', '00000000000000000001',
        'datacontenttype', 'application/json',
        'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.departed.json',
        'data', jsonb_build_object('departed_at', v_t, 'reason', 'dispatched')),
      jsonb_build_object('specversion', '1.0', 'id', 'p-y', 'source', 'urn:ottoq:src:someone-else:' || v_car,
        'subject', v_car, 'type', 'com.ottoyard.vehicle.departed', 'time', v_t, 'sequence', '00000000000000000001',
        'datacontenttype', 'application/json',
        'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.departed.json',
        'data', jsonb_build_object('departed_at', v_t, 'reason', 'dispatched'))));
    -- a fault summary: one exceptions row, titled
    r_fault := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-f', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.fault.summary', 'time', v_t, 'sequence', '00000000000000000004',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.fault.summary.json',
      'data', jsonb_build_object('severity', 'high', 'category', 'sensor_anomaly', 'fault_codes', jsonb_build_array('AV-S0010')))));
    SELECT title INTO v_exc_title FROM public.exceptions WHERE id = (r_fault->'results'->0->'detail'->>'exception_id')::uuid;
    -- the same fault from a key without the incident stream, and telemetry from a key with no fleet
    r_stream := public.ottoq_v2_take_events(h2, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-f2', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.fault.summary', 'time', v_t, 'sequence', '00000000000000000005',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.fault.summary.json',
      'data', jsonb_build_object('severity', 'low', 'category', 'other'))));
    r_nofleet := public.ottoq_v2_take_events(h3, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-n', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.telemetry', 'time', v_t, 'sequence', '00000000000000000009',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.telemetry.json',
      'data', jsonb_build_object('signals', jsonb_build_object(
        'Vehicle.Speed', jsonb_build_object('value', 0, 'ts', v_t))))));
    -- an ack for a directive that is not this car's
    r_ack := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-a', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.directive.ack', 'time', v_t, 'sequence', '00000000000000000006',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/directive.ack.json',
      'data', jsonb_build_object('directive_id', gen_random_uuid(), 'directive_version', 1,
                                 'disposition', 'accepted', 'observed_at', v_t))));
    -- a position inside the depot is kept with the tyres converted back to psi; one 80 km away is dropped
    r_in := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-in', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.telemetry', 'time', v_t, 'sequence', '00000000000000000010',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.telemetry.json',
      'data', jsonb_build_object('signals', jsonb_build_object(
        'Vehicle.CurrentLocation.Latitude', jsonb_build_object('value', v_in_lat, 'ts', v_t),
        'Vehicle.CurrentLocation.Longitude', jsonb_build_object('value', v_in_lng, 'ts', v_t),
        'Vehicle.Chassis.Axle.Row1.Wheel.Left.Tire.Pressure', jsonb_build_object('value', 241, 'ts', v_t),
        'Vehicle.Chassis.Axle.Row1.Wheel.Right.Tire.Pressure', jsonb_build_object('value', 241, 'ts', v_t),
        'Vehicle.Chassis.Axle.Row2.Wheel.Left.Tire.Pressure', jsonb_build_object('value', 241, 'ts', v_t),
        'Vehicle.Chassis.Axle.Row2.Wheel.Right.Tire.Pressure', jsonb_build_object('value', 241, 'ts', v_t))))));
    SELECT current_lat, current_lng, tire_pressures_psi INTO v_in_pkt FROM public.ottoq_telemetry_packets
     WHERE packet_id = (r_in->'results'->0->'detail'->>'packet_id')::uuid;
    r_out := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-out', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.telemetry', 'time', v_t, 'sequence', '00000000000000000011',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.telemetry.json',
      'data', jsonb_build_object('signals', jsonb_build_object(
        'Vehicle.CurrentLocation.Latitude', jsonb_build_object('value', v_in_lat + 0.72, 'ts', v_t),
        'Vehicle.CurrentLocation.Longitude', jsonb_build_object('value', v_in_lng, 'ts', v_t))))));
    SELECT current_lat, current_lng INTO v_out_pkt FROM public.ottoq_telemetry_packets
     WHERE packet_id = (r_out->'results'->0->'detail'->>'packet_id')::uuid;
    -- a dry run keeps nothing
    SELECT count(*) INTO v_inbox_before_dry FROM public.ottoq_v2_inbox;
    r_dry := public.ottoq_v2_take_events(h, jsonb_build_array(jsonb_build_object(
      'specversion', '1.0', 'id', 'p-d', 'source', 'urn:ottoq:src:probe-0650:' || v_car, 'subject', v_car,
      'type', 'com.ottoyard.vehicle.departed', 'time', v_t, 'sequence', '00000000000000000012',
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.departed.json',
      'data', jsonb_build_object('departed_at', v_t, 'reason', 'dispatched'))), true);
    SELECT count(*) INTO v_inbox_dry FROM public.ottoq_v2_inbox;
    SELECT count(*) INTO v_inbox_kept FROM public.ottoq_v2_inbox WHERE source_name = 'probe-0650';
    r_unknown := public.ottoq_v2_take_events(md5('no such key'), '[]'::jsonb);
    RAISE EXCEPTION '0650 V1 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0650 V1 PROBED' THEN RAISE EXCEPTION '0650 V1: the probe itself failed: %', v_msg; END IF;
  SELECT count(*) INTO v_inbox_rows_after FROM public.ottoq_v2_inbox;

  IF r_first->'results'->0->>'disposition' <> 'applied' THEN RAISE EXCEPTION '0650 V1 FAILED: in-order telemetry: %', r_first; END IF;
  IF v_packet_time IS DISTINCT FROM v_t::timestamptz THEN
    RAISE EXCEPTION '0650 V1 FAILED: the packet is timed % and the event %', v_packet_time, v_t;
  END IF;
  IF v_power IS DISTINCT FROM 11.8 THEN
    RAISE EXCEPTION '0650 V1 FAILED: CurrentPower -11800 W (out of the battery) stored as % kW, not 11.8', v_power;
  END IF;
  IF r_in->'results'->0->'detail'->>'location' <> 'kept_inside_geofence' OR v_in_pkt.current_lat IS NULL
     OR v_in_pkt.tire_pressures_psi IS DISTINCT FROM ARRAY[34.95, 34.95, 34.95, 34.95]::numeric[] THEN
    RAISE EXCEPTION '0650 V1 FAILED: a position inside the depot: %, packet %', r_in, to_jsonb(v_in_pkt);
  END IF;
  IF r_out->'results'->0->'detail'->>'location' <> 'dropped_outside_geofence' OR v_out_pkt.current_lat IS NOT NULL
     OR v_out_pkt.current_lng IS NOT NULL THEN
    RAISE EXCEPTION '0650 V1 FAILED: a position 80 km away: %, packet %', r_out, to_jsonb(v_out_pkt);
  END IF;
  IF r_again->'results'->0->>'disposition' <> 'duplicate' THEN RAISE EXCEPTION '0650 V1 FAILED: a resent event: %', r_again; END IF;
  IF r_gap->'results'->0->>'disposition' <> 'applied' OR v_cursor_gaps <> 1 OR v_soc_after_gap <> 63 THEN
    RAISE EXCEPTION '0650 V1 FAILED: sequence 3 after 1: %, gaps %, soc %', r_gap, v_cursor_gaps, v_soc_after_gap;
  END IF;
  IF r_late->'results'->0->>'disposition' <> 'late' OR v_soc_after_late <> 63 THEN
    RAISE EXCEPTION '0650 V1 FAILED: sequence 2 after 3: %, soc %', r_late, v_soc_after_late;
  END IF;
  IF r_scope->'results'->0->>'reason' <> 'vehicle_not_found' OR r_scope->'results'->1->>'reason' <> 'source_is_not_this_key' THEN
    RAISE EXCEPTION '0650 V1 FAILED: another fleet''s car or another operator''s source: %', r_scope;
  END IF;
  IF r_fault->'results'->0->>'disposition' <> 'applied' OR v_exc_title IS DISTINCT FROM 'Operator fault: sensor anomaly' THEN
    RAISE EXCEPTION '0650 V1 FAILED: a fault summary: %, title %', r_fault, v_exc_title;
  END IF;
  IF r_stream->'results'->0->>'reason' <> 'stream_not_allowed' THEN RAISE EXCEPTION '0650 V1 FAILED: a stream the key lacks: %', r_stream; END IF;
  IF r_nofleet->'results'->0->>'reason' <> 'key_speaks_for_no_fleet' THEN RAISE EXCEPTION '0650 V1 FAILED: a key with no fleet: %', r_nofleet; END IF;
  IF r_ack->'results'->0->>'reason' <> 'directive_not_found' THEN RAISE EXCEPTION '0650 V1 FAILED: an ack for no directive of this car: %', r_ack; END IF;
  IF r_dry->'results'->0->>'disposition' <> 'applied' OR v_inbox_dry <> v_inbox_before_dry THEN
    RAISE EXCEPTION '0650 V1 FAILED: a dry run kept something: %, % -> %', r_dry, v_inbox_before_dry, v_inbox_dry;
  END IF;
  IF v_inbox_kept <> 6 THEN RAISE EXCEPTION '0650 V1 FAILED: % probe rows in the inbox, expected 6 (1, 3, 2 late, fault, in, out)', v_inbox_kept; END IF;
  IF COALESCE((r_unknown->>'ok')::boolean, true) OR r_unknown->>'reason' <> 'unknown_or_revoked_key' THEN
    RAISE EXCEPTION '0650 V1 FAILED: an unknown key: %', r_unknown;
  END IF;
  IF v_inbox_rows_after <> v_inbox_rows_before THEN RAISE EXCEPTION '0650 V1 FAILED: the probe did not roll back'; END IF;
  RAISE NOTICE '0650 V1 PASSED: in-order telemetry applied and timed by the event, its power sign turned to the twin''s; a position inside the depot kept with the tyres back in psi, one 80 km away dropped; a resend is a duplicate; 3 after 1 applied with one gap; 2 after 3 late and not applied over it; another fleet''s car not found, another operator''s source refused; a fault summary writes a titled exception; a missing stream, a key with no fleet, an ack for no directive of this car and an unknown key refused; a dry run keeps nothing; all rolled back';
END $v1$;

-- ── V2: who may call and read what ──
DO $v2$
DECLARE r record;
BEGIN
  FOR r IN SELECT unnest(ARRAY['public.ottoq_scope_source_key(uuid,uuid[])',
                               'public.ottoq_v2_take_events(text,jsonb,boolean)'])::regprocedure AS f
  LOOP
    IF has_function_privilege('anon', r.f, 'EXECUTE') OR has_function_privilege('authenticated', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0650 V2 FAILED: % is executable by anon or authenticated', r.f;
    END IF;
    IF NOT has_function_privilege('service_role', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0650 V2 FAILED: service_role cannot execute %', r.f;
    END IF;
  END LOOP;
  FOR r IN SELECT unnest(ARRAY['ottoq.ottoq_v2_take_one(uuid,uuid,uuid,timestamptz,jsonb)',
                               'ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'])::regprocedure AS f
  LOOP
    IF has_function_privilege('anon', r.f, 'EXECUTE') OR has_function_privilege('authenticated', r.f, 'EXECUTE')
       OR has_function_privilege('service_role', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0650 V2 FAILED: % is callable around the door', r.f;
    END IF;
  END LOOP;
  FOR r IN SELECT unnest(ARRAY['public.ottoq_v2_inbox', 'public.ottoq_v2_cursors', 'public.ottoq_v2_signal_ttl']) AS t
  LOOP
    IF has_table_privilege('anon', r.t, 'SELECT') OR has_table_privilege('authenticated', r.t, 'SELECT') THEN
      RAISE EXCEPTION '0650 V2 FAILED: anon or authenticated can read %', r.t;
    END IF;
  END LOOP;
END $v2$;

-- ── V3: the purge's registry still holds, and the geofence is the twin depot's alone ──
DO $v3$
DECLARE v_block int; v_inside int; v_stalls int; v_others int;
BEGIN
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN RAISE EXCEPTION '0650 V3 FAILED: % blocking run-scope defect(s) after registering the new tables', v_block; END IF;
  SELECT count(*), count(*) FILTER (WHERE ST_Covers(d.geofence, s.absolute_point)) INTO v_stalls, v_inside
    FROM public.stalls s JOIN public.depots d ON d.id = s.depot_id
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.absolute_point IS NOT NULL;
  IF v_inside <> v_stalls THEN RAISE EXCEPTION '0650 V3 FAILED: the geofence covers % of % stalls', v_inside, v_stalls; END IF;
  SELECT count(*) INTO v_others FROM public.depots WHERE geofence IS NOT NULL AND id <> '11111111-1111-1111-1111-111111111111';
  IF v_others > 0 THEN RAISE EXCEPTION '0650 V3 FAILED: % other depot(s) have a geofence', v_others; END IF;
  RAISE NOTICE '0650 V3 PASSED: no blocking run-scope defect; the twin depot geofence covers its % stalls; no other depot has one', v_stalls;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0650_the_v2_door_takes_cloudevents_keeps_their_time_drops_duplicates_and_orders_them', false, false,
  'Step 3 of the twin data contract review: ottow_api_keys.fleet_operator_ids + ottoq_scope_source_key; '
  'ottoq_v2_inbox / ottoq_v2_cursors (engine, FK) / ottoq_v2_signal_ttl; ottoq_v2_take_events (service_role only) '
  'keeps event time, drops duplicates on source+id, applies in sequence order per car, refuses another fleet''s car; '
  'the twin depot gets a geofence nothing reads yet. No tick path calls or reads any of it. FALSE/FALSE.',
  now());

COMMIT;
