-- tests/fixtures/twenty_post_base_stub.sql -- the twin depot and the engine 0759 changes, as far as 0759 reaches.
-- Standalone: loaded on its own into a fresh scratch database by tests/test_twenty_post_base_sql.py.
-- The functions 0759 replaces or reads are pg_get_functiondef's output, byte for byte, read from the live catalog on
-- 2026-10-19 (prosrc md5: apply cb079839, restore 2c0df4dc, census a2663c6f, the commit guard 4becb796, the scorecard
-- a591253c, the overlap check 725e099f, the fence check 6bab817c, and the stall triggers: state change 1b5668fd,
-- reassignment guard b45ed802, seat 7ce8d314, update_timestamp da5ac28a), and so are ottoq_jsonb_diff and
-- ottoq.ottoq_active_sim_run_id, which the state-change trigger calls. The depot's rows are as read the same day: the
-- 40 charger stalls (every column 0759 reads), the 118 others (code, type, position, zone, kind), the 45 chargers, the
-- 1,400 capabilities of the charger stalls (7 classes x 5 operations each, pack robotaxi, source seed_0043, all active,
-- as live), canopies A-C, the power limits and site_layout, and the 8 build-outs (codes, posts, conversions and power
-- as live; their titles and basis are stand-ins, which 0759's premise digest does not read). Stand-ins, noted where
-- defined: the event signer records the event in public.ottoq_events, the shield probe and the in-depot gate answer
-- nothing and allow, the in-flight count reads a test setting, and the KPI functions and visit outcomes read test
-- tables. Tables carry the columns these functions read; stalls and chargers carry every live column.
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS extensions;
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;

CREATE TYPE public.stall_type AS ENUM ('dcfc', 'l2', 'wash_bay', 'detail_bay', 'service_bay', 'staging', 'parking', 'safety');
CREATE TABLE public.depots (id uuid PRIMARY KEY, feed_mode text, dcfc_max_concurrent_kw numeric, service_max_kw numeric,
  site_layout jsonb, updated_at timestamp with time zone NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_ocpp_chargers (
  charger_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  depot_id uuid REFERENCES public.depots(id) ON DELETE SET NULL,
  ocpp_identifier text NOT NULL UNIQUE,
  vendor text, model text, serial_number text, firmware_version text, ocpp_protocol_version text DEFAULT '2.0.1',
  station_state text NOT NULL DEFAULT 'Unavailable'
    CHECK (station_state = ANY (ARRAY['Available', 'Occupied', 'Reserved', 'Unavailable', 'Faulted', 'Maintenance'])),
  station_state_changed_at timestamp with time zone NOT NULL DEFAULT now(),
  last_heartbeat_at timestamp with time zone, max_kw numeric, num_connectors integer NOT NULL DEFAULT 1,
  connector_states jsonb NOT NULL DEFAULT '{}'::jsonb, last_fault_code text, last_fault_at timestamp with time zone,
  last_fault_payload jsonb, installed_at timestamp with time zone, decommissioned_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(), updated_at timestamp with time zone NOT NULL DEFAULT now());
CREATE TABLE public.stalls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  depot_id uuid NOT NULL REFERENCES public.depots(id) ON DELETE CASCADE,
  stall_code text NOT NULL,
  stall_type public.stall_type NOT NULL,
  display_name text,
  relative_x double precision DEFAULT 0,
  relative_y double precision DEFAULT 0,
  heading_degrees smallint DEFAULT 0 CHECK (heading_degrees >= 0 AND heading_degrees < 360),
  absolute_lat double precision,
  absolute_lng double precision,
  absolute_point text,                -- geography on live; stale since 0561 and untouched by 0759
  distance_from_entrance integer DEFAULT 0,
  status text NOT NULL DEFAULT 'available'
    CHECK (status = ANY (ARRAY['available', 'occupied', 'reserved', 'maintenance', 'closed'])),
  current_vehicle_id uuid,
  equipment_config jsonb DEFAULT '{}'::jsonb,
  fiducial_marker_id text,
  uwb_beacon_id text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  zone text,
  reserved_for_mission_id uuid,
  connector_type text CHECK (connector_type IS NULL OR connector_type = ANY (ARRAY['CCS1', 'CCS2', 'NACS', 'CHAdeMO',
    'Type1', 'Type2', 'Tesla_Proprietary', 'MCS', 'Multi', 'NonCharging', 'Other'])),
  connector_max_kw numeric,
  supported_inlet_types text[] DEFAULT '{}'::text[],
  ocpp_charger_id uuid REFERENCES public.ottoq_ocpp_chargers(charger_id) ON DELETE SET NULL,
  stall_kind text,
  canopy_code text,
  covered boolean NOT NULL DEFAULT false,
  stall_width_ft numeric,
  stall_depth_ft numeric,
  reserved_by uuid,
  reserved_at timestamp with time zone,
  reservation_expires_at timestamp with time zone,
  staging_role text CHECK (staging_role = ANY (ARRAY['temp', 'long'])),
  UNIQUE (depot_id, stall_code));
CREATE UNIQUE INDEX idx_stalls_one_vehicle_per_stall ON public.stalls (current_vehicle_id) WHERE current_vehicle_id IS NOT NULL;
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, current_state text, current_stall_id uuid, robotic_tether_stall_id uuid);
CREATE TABLE public.ottoq_vehicle_classes (vehicle_class_code text PRIMARY KEY);
CREATE TABLE public.ottoq_operation_catalog (pack_id text NOT NULL, operation_code text NOT NULL,
  PRIMARY KEY (pack_id, operation_code));
CREATE TABLE public.ottoq_service_point_capabilities (
  stall_id uuid NOT NULL REFERENCES public.stalls(id) ON DELETE CASCADE,
  asset_class_code text NOT NULL REFERENCES public.ottoq_vehicle_classes(vehicle_class_code),
  pack_id text NOT NULL DEFAULT 'robotaxi',
  operation_code text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  source text NOT NULL DEFAULT 'seed_0043',
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  PRIMARY KEY (stall_id, asset_class_code, operation_code),
  FOREIGN KEY (pack_id, operation_code) REFERENCES public.ottoq_operation_catalog(pack_id, operation_code));
CREATE TABLE public.ottoq_site_structures (
  structure_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid NOT NULL REFERENCES public.depots(id),
  structure_code text NOT NULL, structure_kind text NOT NULL, title text, origin_x_ft numeric NOT NULL,
  origin_y_ft numeric NOT NULL, width_ft numeric, length_ft numeric, height_ft numeric, rotation_deg numeric DEFAULT 0,
  absolute_lat numeric, absolute_lng numeric, properties jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'active', introduced_in text, created_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE (depot_id, structure_code));
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid, status text, scenario_code text,
  random_seed bigint, tick_count integer, policy text, started_at timestamp with time zone, ended_at timestamp with time zone,
  sim_clock_start timestamp with time zone, sim_clock_current timestamp with time zone, tick_interval_seconds integer,
  time_scale numeric, payload jsonb, purged_at timestamp with time zone);
CREATE TABLE public.ottoq_throughput_sweeps (sweep_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sweep_code text NOT NULL,
  depot_id uuid NOT NULL, status text NOT NULL DEFAULT 'active');
CREATE TABLE public.ottoq_dial_experiments (experiment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid,
  param_key text, status text NOT NULL DEFAULT 'active');
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL DEFAULT true, note text NOT NULL,
  classified_at timestamp with time zone NOT NULL DEFAULT now(), forces_dial_restart boolean);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial PRIMARY KEY, taken_at timestamp with time zone NOT NULL DEFAULT now(),
  label text NOT NULL, object_kind text NOT NULL, schema_name text NOT NULL, object_name text NOT NULL, definition text NOT NULL,
  def_md5 text NOT NULL);
CREATE TABLE public.ottoq_stall_bookings (booking_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid,
  stall_id uuid, state text);
-- what the stand-in event signer records (live: the HMAC-signed, append-only event stream)
CREATE TABLE public.ottoq_events (event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at timestamp with time zone NOT NULL DEFAULT now(), actor_type text, actor_id text, event_type text,
  entity_type text, entity_id uuid, depot_id uuid, payload jsonb, new_state jsonb, ingest_source text, data_source text,
  sim_run_id uuid);
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stall_id uuid, vehicle_id uuid,
  started_at timestamp with time zone, ended_at timestamp with time zone, energy_delivered_kwh numeric, avg_power_kw numeric,
  sim_run_id uuid);
CREATE TABLE public.ottoq_run_archives (sim_run_id uuid, engine_hash text, config_hash text);
-- what the stand-in visit outcomes return, by run
CREATE TABLE public._test_visit_outcomes (sim_run_id uuid, visit_id uuid, vehicle_id uuid, archetype text, tier_group text,
  arrived_at timestamp with time zone, due_at timestamp with time zone, departed_at timestamp with time zone,
  door_min numeric, on_time boolean, late_min numeric, soc_out numeric, target_soc numeric,
  needed_open_at_departure integer, cleared_by_triage integer, done_without_time integer, in_depot_at_horizon boolean);

CREATE TABLE public.ottoq_site_buildouts (
  buildout_code          text PRIMARY KEY CHECK (buildout_code ~ '^[a-z0-9_]+$'),
  depot_id               uuid NOT NULL REFERENCES public.depots(id),
  title                  text NOT NULL,
  dcfc_posts             integer NOT NULL CHECK (dcfc_posts > 0),
  convert_l2             text[] NOT NULL DEFAULT '{}',
  dcfc_max_concurrent_kw numeric NOT NULL CHECK (dcfc_max_concurrent_kw > 0),
  service_max_kw         numeric NOT NULL CHECK (service_max_kw > 0),
  basis                  jsonb NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_site_buildout_active (
  depot_id      uuid PRIMARY KEY REFERENCES public.depots(id),
  buildout_code text NOT NULL REFERENCES public.ottoq_site_buildouts(buildout_code),
  applied_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  backend_pid   integer NOT NULL DEFAULT pg_backend_pid(),
  pre_image     jsonb NOT NULL);

-- ── the live bodies ──
CREATE OR REPLACE FUNCTION public.update_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_jsonb_diff(old_doc jsonb, new_doc jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_result JSONB := '{}'::jsonb;
  v_key TEXT;
  v_old_val JSONB;
  v_new_val JSONB;
BEGIN
  -- Keys that changed
  FOR v_key IN
    SELECT DISTINCT key FROM (
      SELECT jsonb_object_keys(COALESCE(old_doc, '{}'::jsonb)) AS key
      UNION
      SELECT jsonb_object_keys(COALESCE(new_doc, '{}'::jsonb)) AS key
    ) k
  LOOP
    v_old_val := COALESCE(old_doc, '{}'::jsonb) -> v_key;
    v_new_val := COALESCE(new_doc, '{}'::jsonb) -> v_key;
    IF v_old_val IS DISTINCT FROM v_new_val THEN
      v_result := v_result || jsonb_build_object(v_key,
        jsonb_build_object('from', v_old_val, 'to', v_new_val));
    END IF;
  END LOOP;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION ottoq.ottoq_active_sim_run_id()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_txt text; v_id uuid;
BEGIN
  v_txt := NULLIF(current_setting('ottoq.sim_run_id', true), '');
  IF v_txt IS NOT NULL THEN
    IF v_txt = 'none' THEN RETURN NULL; END IF;
    RETURN v_txt::uuid;
  END IF;

  SELECT r.sim_run_id INTO v_id
    FROM public.ottoq_sim_runs r
   WHERE r.status = 'running'
   ORDER BY r.started_at DESC
   LIMIT 1;

  -- 0092: NEVER cache a miss. A 'none' cached before a run exists blinds the whole
  -- transaction (measured: 12 ticks of trigger events written as production/NULL).
  IF v_id IS NOT NULL THEN
    PERFORM set_config('ottoq.sim_run_id', v_id::text, true);
  END IF;
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_stalls_state_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  DECLARE
    v_payload      JSONB;
    v_diff         JSONB;
    v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
    v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
    v_event_type   TEXT;
    v_run          UUID;
    v_data_source  TEXT;
  BEGIN
    v_run := ottoq.ottoq_active_sim_run_id();

    -- ══════════════════════════ 0387 (G44) ══════════════════════════
    -- ATTRIBUTE THE ENGINE. `ottoq.actor_type` is read here and by
    -- ottoq_eval_sm_transition_validity, and NOTHING IN THE DATABASE SETS IT on this
    -- path: measured, 129,060 of 129,060 vehicle/stall state_changed events carried
    -- actor_type='unknown'. Meanwhile all 82 rows of ottoq_state_transitions declare a
    -- non-empty allowed_actor_types and NOT ONE admits 'unknown', so probing the
    -- state-machine rules without fixing this first would have failed every transition
    -- on the role gate and said nothing at all about transition legality.
    -- Inside a sim run the engine is the actor -- the twin simulates its technicians --
    -- so say so. Production (no active run) keeps 'unknown', because there it genuinely
    -- is unidentified and inventing an actor would be worse than admitting none.
    -- SAFE FOR KPI 4: ottoq_kpi_touch_actor_types marks BOTH 'unknown' and
    -- 'ottoq_engine' human_actor=false, so touch_events_per_turn cannot move.
    IF v_actor_type = 'unknown' AND v_run IS NOT NULL THEN
      v_actor_type := 'ottoq_engine';
    END IF;

    -- 0228 (G16). See the vehicles trigger. A stall always carries its depot,
    -- so there is no COALESCE chain to walk -- but the same fallback is kept
    -- for the case where the depot row is missing, because a trigger that
    -- cannot answer should say what it used to say rather than say NULL.
    SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
      INTO v_data_source
      FROM public.depots d WHERE d.id = NEW.depot_id;
    v_data_source := COALESCE(
      v_data_source,
      CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END);

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'stall.created';
      PERFORM ottoq_record_event(
        p_actor_type    := v_actor_type,
        p_actor_id      := v_actor_id,
        p_event_type    := v_event_type,
        p_entity_type   := 'stall',
        p_entity_id     := NEW.id,
        p_depot_id      := NEW.depot_id,
        p_payload       := jsonb_build_object('new', to_jsonb(NEW)),
        p_new_state     := to_jsonb(NEW),
        p_ingest_source := 'trigger',
        p_data_source   := v_data_source,
        p_sim_run_id    := v_run
      );
      RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
      IF to_jsonb(OLD) = to_jsonb(NEW) THEN RETURN NEW; END IF;
      v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
      IF NOT EXISTS (
        SELECT 1 FROM jsonb_object_keys(v_diff) AS k
         WHERE k <> ALL (ARRAY['updated_at','reservation_expires_at','reserved_at'])
      ) THEN
        RETURN NEW;
      END IF;

      -- ══════════════════════════ 0387 (G44) ══════════════════════════
      -- SM.003.stall_transition_validity has had a callable evaluator and NO CALLER since it was written. Probe it
      -- HERE because a state-machine invariant is a property of a TRANSITION, and all six
      -- existing probe points sit where something STARTS -- db/checks/0192 and 0273
      -- diagnosed exactly that and stopped at the diagnosis.
      --
      -- MEASURE ONLY. ottoq_shield_probe logs every evaluation and returns `would_block`;
      -- nothing here reads it. The rule is declared enforcement='block', and promoting it
      -- is a SEPARATE decision under 2.9a's blind-spot doctrine -- which cannot be taken
      -- before the pass rate is known, and until this line existed it could not be.
      --
      -- Guarded on the state column actually moving: without that, SoC-only updates reach
      -- this point (the churn filter above deliberately lets current_soc through as real
      -- signal) and the evaluator would return its 'no-op transition' pass tens of
      -- thousands of times -- logging green for comparisons it never made, which is the
      -- G28 defect class.
      --
      -- Own exception handler: a probe must never abort a tick.
      IF NEW.status IS DISTINCT FROM OLD.status THEN
        BEGIN
          PERFORM 1 FROM public.ottoq_shield_probe(
            p_action_context := 'stall_state_change',
            p_entity_type    := 'stall',
            p_entity_id      := NEW.id,
            p_context        := jsonb_build_object(
                                  'from_state', OLD.status,
                                  'to_state',   NEW.status,
                                  'actor_type', v_actor_type),
            p_depot_id       := NEW.depot_id);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'ottoq_stalls_state_change: SM.003 probe FAILED SAFELY %: %',
            SQLSTATE, SQLERRM;
        END;
      END IF;
      v_event_type := 'stall.state_changed';
      v_payload := jsonb_build_object('diff', v_diff);
      PERFORM ottoq_record_event(
        p_actor_type     := v_actor_type,
        p_actor_id       := v_actor_id,
        p_event_type     := v_event_type,
        p_entity_type    := 'stall',
        p_entity_id      := NEW.id,
        p_depot_id       := NEW.depot_id,
        p_payload        := v_payload,
        p_new_state      := to_jsonb(NEW),
        p_ingest_source  := 'trigger',
        p_data_source    := v_data_source,
        p_sim_run_id     := v_run
      );
      RETURN NEW;
    END IF;
    RETURN NEW;
  END;
  $function$;

CREATE OR REPLACE FUNCTION public.ottoq_trg_reassignment_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
    DECLARE
      v_guard jsonb;
      v_vehicle_id uuid;
      v_sim_run_id uuid;
      v_state text;
      v_granted text;
      v_cur uuid;      -- 0547: the car's own stall
      v_tether uuid;   -- 0547: the stall the car is tethered to
    BEGIN
      IF NEW.current_vehicle_id IS NULL AND OLD.current_vehicle_id IS NOT NULL THEN
        v_vehicle_id := OLD.current_vehicle_id;

        -- ── (1) ONLY WORK IN PROGRESS IS PROTECTED ──────────────────────────────
        -- Exactly ottoq_indepot_reassignment_guard's own v_mid set. A vehicle in a
        -- holding state (staged_awaiting_service, charge_complete_holding,
        -- service_complete_holding, staged_for_departure, ...) has nothing to cut
        -- short, so vacating its stall is not a re-route and needs no approval.
        -- ::text on purpose: an unknown label can only fail to match, never raise.
        SELECT v.current_state::text, v.current_stall_id, v.robotic_tether_stall_id
          INTO v_state, v_cur, v_tether FROM vehicles v WHERE v.id = v_vehicle_id;
        IF v_state IS NULL OR v_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay',
                                              'charging_dcfc','charging_l2') THEN
          RETURN NEW;
        END IF;

        -- ── (1b) 0547 (G276): A CHARGER ITS CAR HAS LEFT FOR A BAY IS FREE ──────
        -- A car in a bay is not charging, so the charger it came from holds no work
        -- in progress. Reading the state alone made such a car look mid-work at the
        -- charger it had left: the pointer was put back, the charger read available
        -- with a car that was elsewhere, and nothing could offer it (G121). The car
        -- is still at the charger only if it names it itself, by its current_stall_id
        -- or its tether. A car in a bay keeps its bay, even with its own pointer
        -- empty (0535 §1).
        IF v_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
           AND OLD.stall_type::text IN ('dcfc','l2')
           AND v_cur IS DISTINCT FROM OLD.id AND v_tether IS DISTINCT FROM OLD.id THEN
          RETURN NEW;
        END IF;

        -- ── (2) THE GATE DOES NOT SECOND-GUESS ITSELF ───────────────────────────
        -- A fault handler that already asked and was granted carries a transaction-local
        -- grant. Without this, the trigger re-asks with 'automated_reassignment', gets
        -- the catch-all defer, and reverses a decision the gate itself just made --
        -- which is what would strand a faulted vehicle mid-bay with no technician to
        -- release it.
        v_granted := current_setting('ottoq.reassign_ok', true);
        IF v_granted IS NOT NULL AND position(v_vehicle_id::text in v_granted) > 0 THEN
          RETURN NEW;
        END IF;

        SELECT sim_run_id INTO v_sim_run_id
          FROM ottoq_sim_runs
         WHERE depot_id = NEW.depot_id AND status = 'running'
         ORDER BY started_at DESC LIMIT 1;
        IF v_sim_run_id IS NOT NULL THEN
          v_guard := ottoq_indepot_reassignment_guard(
            v_vehicle_id, v_sim_run_id,
            'automated_reassignment',
            jsonb_build_object('from_stall', OLD.id)
          );
          IF (v_guard->>'allowed')::boolean IS FALSE THEN
            NEW.current_vehicle_id := OLD.current_vehicle_id;
          END IF;
        END IF;
      END IF;
      RETURN NEW;
    END;
    $function$;

CREATE OR REPLACE FUNCTION public.ottoq_stall_seat_is_exclusive()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.current_vehicle_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.current_vehicle_id IS DISTINCT FROM OLD.current_vehicle_id)
  THEN
    -- Release every OTHER stall still claiming this vehicle. Physically a car is
    -- in one place; the unique index says so, and until now nothing made it true.
    UPDATE public.stalls s
       SET current_vehicle_id = NULL,
           status = CASE WHEN s.status = 'occupied' THEN 'available' ELSE s.status END
     WHERE s.current_vehicle_id = NEW.current_vehicle_id
       AND s.id <> NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_site_buildout_must_not_commit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildout_active a WHERE a.depot_id = NEW.depot_id) THEN
    RAISE EXCEPTION 'build-out % is still applied to depot % at commit. A build-out lives only inside the transaction that applied it: call public.ottoq_site_buildout_restore first. This transaction rolls back, and the depot is as built.',
      NEW.buildout_code, NEW.depot_id USING ERRCODE = 'P0001';
  END IF;
  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.ottoq_site_buildout_apply(p_depot uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  b        public.ottoq_site_buildouts%ROWTYPE;
  v_ids    uuid[];
  v_found  integer;
  v_bad    text;
  v_dcfc   integer;
  v_pre    jsonb;
  v_actor_type text := current_setting('ottoq.actor_type', true);
  v_actor_id   text := current_setting('ottoq.actor_id', true);
BEGIN
  SELECT * INTO b FROM public.ottoq_site_buildouts WHERE buildout_code = p_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'site_buildout_apply: no build-out %', p_code USING ERRCODE = 'P0002';
  END IF;
  IF b.depot_id IS DISTINCT FROM p_depot THEN
    RAISE EXCEPTION 'site_buildout_apply: build-out % belongs to depot %, not %', p_code, b.depot_id, p_depot
      USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot) THEN
    RAISE EXCEPTION 'site_buildout_apply: build-out % is already applied to depot % in this transaction; restore it first',
      (SELECT buildout_code FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot), p_depot USING ERRCODE = 'P0001';
  END IF;
  -- Only between runs: a run in progress was dealt the depot as it was.
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = p_depot AND status IN ('running', 'paused')) THEN
    RAISE EXCEPTION 'site_buildout_apply: a run is live at depot %; a build-out is applied only before a test day starts', p_depot
      USING ERRCODE = '55006';
  END IF;

  SELECT array_agg(s.id ORDER BY u.ord), count(*) INTO v_ids, v_found
    FROM unnest(b.convert_l2) WITH ORDINALITY AS u(code, ord)
    JOIN public.stalls s ON s.stall_code = u.code AND s.depot_id = p_depot
                        AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL;
  v_ids := COALESCE(v_ids, '{}'::uuid[]);
  IF COALESCE(v_found, 0) <> cardinality(b.convert_l2) THEN
    SELECT string_agg(u.code, ', ') INTO v_bad
      FROM unnest(b.convert_l2) AS u(code)
     WHERE NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.stall_code = u.code AND s.depot_id = p_depot
                          AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL);
    RAISE EXCEPTION 'site_buildout_apply: % names spaces that are not L2 chargers at depot %: %', p_code, p_depot, v_bad
      USING ERRCODE = 'P0001';
  END IF;
  SELECT count(*) INTO v_dcfc FROM public.stalls WHERE depot_id = p_depot AND stall_type = 'dcfc';
  IF v_dcfc + cardinality(b.convert_l2) <> b.dcfc_posts THEN
    RAISE EXCEPTION 'site_buildout_apply: % declares % fast chargers, but the depot has % and it converts %', p_code,
      b.dcfc_posts, v_dcfc, cardinality(b.convert_l2) USING ERRCODE = 'P0001';
  END IF;

  -- Exactly the columns this changes, so the restore puts back exactly what it found.
  v_pre := jsonb_build_object(
    'stalls', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'id', s.id, 'stall_type', s.stall_type::text, 'connector_max_kw', s.connector_max_kw,
                 'fiducial_marker_id', s.fiducial_marker_id, 'uwb_beacon_id', s.uwb_beacon_id,
                 'equipment_config', s.equipment_config, 'zone', s.zone) ORDER BY s.id)
               FROM public.stalls s WHERE s.id = ANY (v_ids)), '[]'::jsonb),
    'chargers', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'charger_id', c.charger_id, 'max_kw', c.max_kw, 'vendor', c.vendor, 'model', c.model) ORDER BY c.charger_id)
               FROM public.ottoq_ocpp_chargers c JOIN public.stalls s ON s.ocpp_charger_id = c.charger_id
              WHERE s.id = ANY (v_ids)), '[]'::jsonb),
    'capabilities', COALESCE((SELECT jsonb_agg(jsonb_build_object('stall_id', k.stall_id, 'asset_class_code', k.asset_class_code)
                                               ORDER BY k.stall_id, k.asset_class_code)
               FROM public.ottoq_service_point_capabilities k
              WHERE k.stall_id = ANY (v_ids) AND k.operation_code = 'charge_l2'), '[]'::jsonb),
    'depot', (SELECT jsonb_build_object('dcfc_max_concurrent_kw', d.dcfc_max_concurrent_kw, 'service_max_kw', d.service_max_kw)
                FROM public.depots d WHERE d.id = p_depot));

  INSERT INTO public.ottoq_site_buildout_active (depot_id, buildout_code, pre_image) VALUES (p_depot, p_code, v_pre);

  -- Say who is acting: the stall trigger signs an event for each converted space (0423(C)'s doctrine).
  PERFORM set_config('ottoq.actor_type', 'ottoq_engine', true);
  PERFORM set_config('ottoq.actor_id', 'site_buildout:' || p_code, true);

  UPDATE public.stalls s
     SET stall_type         = 'dcfc',
         connector_max_kw   = 350.0,
         fiducial_marker_id = 'FID-BO-' || regexp_replace(s.stall_code, '^[A-Z]+-', '') || '-A',
         uwb_beacon_id      = 'UWB-BO-' || regexp_replace(s.stall_code, '^[A-Z]+-', ''),
         equipment_config   = COALESCE(s.equipment_config, '{}'::jsonb)
                              || jsonb_build_object('charger_kw', 350, 'robotic_arm', true, 'buildout', p_code),
         zone               = 'dcfc_zone'
   WHERE s.id = ANY (v_ids);
  UPDATE public.ottoq_ocpp_chargers c
     SET max_kw = 350, vendor = 'ABB', model = 'Terra HP 350'
    FROM public.stalls s
   WHERE s.ocpp_charger_id = c.charger_id AND s.id = ANY (v_ids);
  UPDATE public.ottoq_service_point_capabilities k
     SET operation_code = 'charge_dcfc'
   WHERE k.stall_id = ANY (v_ids) AND k.operation_code = 'charge_l2';
  UPDATE public.depots d
     SET dcfc_max_concurrent_kw = b.dcfc_max_concurrent_kw, service_max_kw = b.service_max_kw
   WHERE d.id = p_depot;

  PERFORM set_config('ottoq.actor_type', COALESCE(v_actor_type, ''), true);
  PERFORM set_config('ottoq.actor_id', COALESCE(v_actor_id, ''), true);

  RETURN jsonb_build_object(
    'buildout_code', p_code, 'depot_id', p_depot, 'title', b.title,
    'dcfc_posts', b.dcfc_posts,
    'converted', COALESCE((SELECT jsonb_agg(jsonb_build_object('stall_id', s.id, 'stall_code', s.stall_code) ORDER BY u.ord)
                             FROM unnest(v_ids) WITH ORDINALITY AS u(id, ord) JOIN public.stalls s ON s.id = u.id), '[]'::jsonb),
    'converted_stall_ids', to_jsonb(v_ids),
    'dcfc_max_concurrent_kw', b.dcfc_max_concurrent_kw, 'service_max_kw', b.service_max_kw,
    'applied_at', clock_timestamp());
END $function$;

CREATE OR REPLACE FUNCTION public.ottoq_site_buildout_restore(p_depot uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  a public.ottoq_site_buildout_active%ROWTYPE;
  v_stalls int; v_chargers int; v_caps int;
  v_actor_type text := current_setting('ottoq.actor_type', true);
  v_actor_id   text := current_setting('ottoq.actor_id', true);
BEGIN
  SELECT * INTO a FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('restored', false, 'depot_id', p_depot, 'why', 'no build-out is applied');
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = p_depot AND status IN ('running', 'paused')) THEN
    RAISE EXCEPTION 'site_buildout_restore: a run is live at depot %; restore after its teardown', p_depot USING ERRCODE = '55006';
  END IF;

  PERFORM set_config('ottoq.actor_type', 'ottoq_engine', true);
  PERFORM set_config('ottoq.actor_id', 'site_buildout:' || a.buildout_code, true);

  UPDATE public.stalls s
     SET stall_type         = (x->>'stall_type')::public.stall_type,
         connector_max_kw   = (x->>'connector_max_kw')::numeric,
         fiducial_marker_id = x->>'fiducial_marker_id',
         uwb_beacon_id      = x->>'uwb_beacon_id',
         equipment_config   = CASE WHEN jsonb_typeof(x->'equipment_config') = 'null' THEN NULL ELSE x->'equipment_config' END,
         zone               = x->>'zone'
    FROM jsonb_array_elements(a.pre_image->'stalls') AS x
   WHERE s.id = (x->>'id')::uuid;
  GET DIAGNOSTICS v_stalls = ROW_COUNT;
  UPDATE public.ottoq_ocpp_chargers c
     SET max_kw = (x->>'max_kw')::numeric, vendor = x->>'vendor', model = x->>'model'
    FROM jsonb_array_elements(a.pre_image->'chargers') AS x
   WHERE c.charger_id = (x->>'charger_id')::uuid;
  GET DIAGNOSTICS v_chargers = ROW_COUNT;
  UPDATE public.ottoq_service_point_capabilities k
     SET operation_code = 'charge_l2'
    FROM jsonb_array_elements(a.pre_image->'capabilities') AS x
   WHERE k.stall_id = (x->>'stall_id')::uuid AND k.asset_class_code = x->>'asset_class_code'
     AND k.operation_code = 'charge_dcfc';
  GET DIAGNOSTICS v_caps = ROW_COUNT;
  UPDATE public.depots d
     SET dcfc_max_concurrent_kw = (a.pre_image->'depot'->>'dcfc_max_concurrent_kw')::numeric,
         service_max_kw         = (a.pre_image->'depot'->>'service_max_kw')::numeric
   WHERE d.id = p_depot;

  IF v_stalls <> jsonb_array_length(a.pre_image->'stalls')
     OR v_chargers <> jsonb_array_length(a.pre_image->'chargers')
     OR v_caps <> jsonb_array_length(a.pre_image->'capabilities') THEN
    RAISE EXCEPTION 'site_buildout_restore: % put back % of % spaces, % of % chargers and % of % capabilities; the depot is not as built',
      a.buildout_code, v_stalls, jsonb_array_length(a.pre_image->'stalls'), v_chargers,
      jsonb_array_length(a.pre_image->'chargers'), v_caps, jsonb_array_length(a.pre_image->'capabilities')
      USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot;
  PERFORM set_config('ottoq.actor_type', COALESCE(v_actor_type, ''), true);
  PERFORM set_config('ottoq.actor_id', COALESCE(v_actor_id, ''), true);

  RETURN jsonb_build_object('restored', true, 'buildout_code', a.buildout_code, 'depot_id', p_depot,
                            'spaces', v_stalls, 'chargers', v_chargers, 'capabilities', v_caps);
END $function$;

CREATE OR REPLACE FUNCTION public.ottoq_site_buildout_census(p_depot uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'depot_id', p_depot,
    'dcfc', (SELECT count(*) FROM public.stalls WHERE depot_id = p_depot AND stall_type = 'dcfc'),
    'l2',   (SELECT count(*) FROM public.stalls WHERE depot_id = p_depot AND stall_type = 'l2'),
    'dcfc_max_concurrent_kw', (SELECT dcfc_max_concurrent_kw FROM public.depots WHERE id = p_depot),
    'service_max_kw',         (SELECT service_max_kw FROM public.depots WHERE id = p_depot),
    'applied',                (SELECT buildout_code FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot));
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_check_stall_overlap(p_depot_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'check', 'stall_overlap',
    'passed', count(*) = 0,
    'failure_count', count(*),
    'failures', COALESCE(jsonb_agg(
      jsonb_build_object('a', a_code, 'b', b_code, 'dist_ft', round(dist::numeric,1))
    ) FILTER (WHERE a_code IS NOT NULL), '[]'::jsonb)
  )
  FROM (
    SELECT a.stall_code AS a_code, b.stall_code AS b_code,
           SQRT(POWER(a.relative_x - b.relative_x, 2) + POWER(a.relative_y - b.relative_y, 2)) AS dist
      FROM stalls a
      JOIN stalls b ON b.depot_id = a.depot_id AND b.id > a.id
     WHERE (p_depot_id IS NULL OR a.depot_id = p_depot_id)
       AND a.heading_degrees = b.heading_degrees
       AND SQRT(POWER(a.relative_x - b.relative_x, 2) + POWER(a.relative_y - b.relative_y, 2)) < 5.0
  ) t
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_check_fence_containment(p_depot_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_failures jsonb := '[]'::jsonb;
  v_rec RECORD;
  v_fence RECORD;
BEGIN
  FOR v_fence IN
    SELECT ss.depot_id, ss.origin_x_ft AS x0, ss.origin_y_ft AS y0,
           ss.origin_x_ft + ss.width_ft AS x1,
           ss.origin_y_ft + ss.length_ft AS y1
      FROM ottoq_site_structures ss
     WHERE ss.structure_kind = 'perimeter_wall'
       AND (p_depot_id IS NULL OR ss.depot_id = p_depot_id)
  LOOP
    FOR v_rec IN
      SELECT s.stall_code, s.relative_x, s.relative_y
        FROM stalls s
       WHERE s.depot_id = v_fence.depot_id
         AND (s.relative_x < v_fence.x0 OR s.relative_x > v_fence.x1
              OR s.relative_y < v_fence.y0 OR s.relative_y > v_fence.y1)
    LOOP
      v_failures := v_failures || jsonb_build_object(
        'check', 'fence_containment',
        'stall_code', v_rec.stall_code,
        'detail', format('stall at (%.2f,%.2f) outside fence (%.2f-%.2f, %.2f-%.2f)',
                         v_rec.relative_x, v_rec.relative_y,
                         v_fence.x0, v_fence.x1, v_fence.y0, v_fence.y1)
      );
    END LOOP;
  END LOOP;
  
  RETURN jsonb_build_object(
    'check', 'fence_containment',
    'passed', jsonb_array_length(v_failures) = 0,
    'failures', v_failures
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_throughput_scorecard(p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_five   jsonb;
  v_wait   jsonb;
  v_svc    jsonb;
  v_errors jsonb := '{}'::jsonb;
  v_bo     jsonb;
  v_conv   uuid[];
  v_out    jsonb;
BEGIN
  -- The KPI functions this reuses are read as they are. One that fails on a run (ottoq_kpi_five raises "field name
  -- must not be null" on the August production run e8a0ba01) is reported under kpi_errors, never allowed to take the
  -- throughput numbers down with it.
  BEGIN v_five := public.ottoq_kpi_five(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('kpi_five', SQLERRM); END;
  BEGIN v_wait := public.ottoq_kpi_charge_wait(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('charge_wait', SQLERRM); END;
  BEGIN v_svc := public.ottoq_kpi_service_completion(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('service_completion', SQLERRM); END;

  -- 0567: a day that ran on a build-out carries its own census (payload.site_buildout, stamped by the caller that
  -- applied it). After the restore the stall table says L2 again, so a later re-score must read the day's record.
  SELECT sr.payload->'site_buildout' INTO v_bo FROM public.ottoq_sim_runs sr WHERE sr.sim_run_id = p_run;
  IF jsonb_typeof(v_bo) = 'object' THEN
    SELECT COALESCE(array_agg(e::uuid), '{}'::uuid[]) INTO v_conv
      FROM jsonb_array_elements_text(COALESCE(v_bo->'converted_stall_ids', '[]'::jsonb)) AS e;
  ELSE
    v_bo := NULL;
    v_conv := '{}'::uuid[];
  END IF;

  WITH r AS (
    SELECT sr.sim_run_id, sr.depot_id, sr.scenario_code, sr.random_seed, sr.tick_count, sr.policy, sr.status,
           sr.sim_clock_start, sr.sim_clock_current,
           round((sr.tick_interval_seconds * COALESCE(sr.time_scale, 1) / 60.0)::numeric, 2) AS step_min_nominal,
           round((extract(epoch FROM (sr.sim_clock_current - sr.sim_clock_start)) / 60.0
                  / NULLIF(sr.tick_count, 0))::numeric, 2) AS step_min,
           GREATEST(extract(epoch FROM (sr.sim_clock_current - sr.sim_clock_start)) / 3600.0, 0)::numeric AS horizon_h
      FROM public.ottoq_sim_runs sr
     WHERE sr.sim_run_id = p_run
  ), o AS (
    SELECT * FROM public.ottoq_visit_outcomes(p_run)
  ), s AS (
    SELECT * FROM o WHERE departed_at IS NOT NULL
  ), grp AS (
    SELECT g.tier_group,
           count(*)                                                       AS visits,
           count(*) FILTER (WHERE g.departed_at IS NOT NULL)              AS served,
           count(*) FILTER (WHERE g.in_depot_at_horizon)                  AS in_depot,
           percentile_cont(0.5)  WITHIN GROUP (ORDER BY g.door_min)       AS p50,
           percentile_cont(0.95) WITHIN GROUP (ORDER BY g.door_min)       AS p95,
           count(*) FILTER (WHERE g.due_at IS NOT NULL AND g.departed_at IS NOT NULL) AS due_served,
           count(*) FILTER (WHERE g.on_time)                              AS on_time
      FROM o g
     GROUP BY g.tier_group
  ), peak AS (
    SELECT COALESCE(max(n), 0) AS n
      FROM (SELECT (SELECT count(*) FROM s s2
                     WHERE s2.departed_at >= s1.departed_at
                       AND s2.departed_at <  s1.departed_at + interval '60 minutes') AS n
              FROM s s1) z
  ), sess AS (
    SELECT CASE WHEN x.stall_id = ANY (v_conv) THEN 'dcfc' ELSE st.stall_type::text END AS stall_type,
           x.stall_id, x.started_at, x.ended_at, x.energy_delivered_kwh, x.avg_power_kw
      FROM public.ocpp_sessions x
      JOIN public.stalls st ON st.id = x.stall_id
     WHERE x.sim_run_id = p_run AND x.started_at IS NOT NULL
  ), dc AS (
    SELECT count(*)                                                                          AS sessions,
           count(DISTINCT stall_id)                                                          AS chargers_used,
           sum(extract(epoch FROM (ended_at - started_at)) / 3600.0) FILTER (WHERE ended_at IS NOT NULL) AS hours,
           sum(energy_delivered_kwh)                                                         AS kwh,
           avg(avg_power_kw)                                                                 AS mean_kw,
           avg(extract(epoch FROM (ended_at - started_at)) / 60.0) FILTER (WHERE ended_at IS NOT NULL) AS mean_min
      FROM sess
     WHERE stall_type = 'dcfc'
  ), fleet AS (
    SELECT COALESCE((v_bo->>'dcfc_posts')::bigint,
                    (SELECT count(*) FROM public.stalls st, r WHERE st.depot_id = r.depot_id AND st.stall_type = 'dcfc'))
             AS dcfc_at_depot
  ), ar AS (
    SELECT a.engine_hash, a.config_hash FROM public.ottoq_run_archives a WHERE a.sim_run_id = p_run LIMIT 1
  )
  SELECT jsonb_build_object(
    'sim_run_id', r.sim_run_id,
    'scorecard_version', '0567',
    'run', jsonb_build_object(
       'scenario', r.scenario_code, 'seed', r.random_seed, 'ticks', r.tick_count, 'policy', r.policy,
       'status', r.status, 'depot_id', r.depot_id, 'sim_start', r.sim_clock_start, 'horizon', r.sim_clock_current,
       'horizon_h', round(r.horizon_h, 2),
       'engine_hash', (SELECT engine_hash FROM ar), 'config_hash', (SELECT config_hash FROM ar),
       'site_buildout', v_bo->>'buildout_code'),
    'step_min', r.step_min,
    'step_min_nominal', r.step_min_nominal,
    'throughput', jsonb_build_object(
       'visits',              (SELECT count(*) FROM o),
       'visits_served',       (SELECT count(*) FROM s),
       'vehicles_served',     (SELECT count(DISTINCT vehicle_id) FROM s),
       'in_depot_at_horizon', (SELECT count(*) FROM o WHERE in_depot_at_horizon),
       'served_per_day',      CASE WHEN r.horizon_h >= 6
                                   THEN round((SELECT count(*) FROM s) * 24.0 / r.horizon_h, 1) END,
       'peak_hour_served',    (SELECT n FROM peak)),
    'by_tier_group', COALESCE((SELECT jsonb_object_agg(tier_group, jsonb_build_object(
       'visits', visits, 'served', served, 'in_depot', in_depot,
       'door_p50_min', round(p50::numeric, 0), 'door_p95_min', round(p95::numeric, 0),
       'due_served', due_served, 'on_time', on_time,
       'on_time_pct', CASE WHEN due_served > 0 THEN round(100.0 * on_time / due_served, 1) END)) FROM grp), '{}'::jsonb),
    'timeliness', jsonb_build_object(
       'door_p50_min', (SELECT round((percentile_cont(0.5)  WITHIN GROUP (ORDER BY door_min))::numeric, 0) FROM s),
       'door_p95_min', (SELECT round((percentile_cont(0.95) WITHIN GROUP (ORDER BY door_min))::numeric, 0) FROM s),
       'due_served',   (SELECT count(*) FROM s WHERE due_at IS NOT NULL),
       'on_time',      (SELECT count(*) FROM s WHERE on_time),
       'on_time_pct',  (SELECT CASE WHEN count(*) FILTER (WHERE due_at IS NOT NULL) > 0
                                    THEN round(100.0 * count(*) FILTER (WHERE on_time)
                                               / count(*) FILTER (WHERE due_at IS NOT NULL), 1) END FROM s),
       'late_p50_min', (SELECT round((percentile_cont(0.5)  WITHIN GROUP (ORDER BY late_min))::numeric, 0) FROM s
                         WHERE late_min IS NOT NULL),
       'late_p95_min', (SELECT round((percentile_cont(0.95) WITHIN GROUP (ORDER BY late_min))::numeric, 0) FROM s
                         WHERE late_min IS NOT NULL)),
    'rule9', jsonb_build_object(
       'departures',                  (SELECT count(*) FROM s),
       'left_below_target',           (SELECT count(*) FROM s
                                        WHERE soc_out IS NOT NULL AND soc_out < COALESCE(target_soc, 100) - 1),
       'left_with_needed_work_open',  (SELECT count(*) FROM s WHERE needed_open_at_departure > 0),
       'charge_unknown_at_departure', (SELECT count(*) FROM s WHERE soc_out IS NULL),
       'atoms_cleared_by_triage',     (SELECT COALESCE(sum(cleared_by_triage), 0) FROM o),
       'done_atoms_without_a_time',   (SELECT COALESCE(sum(done_without_time), 0) FROM o)),
    'fast_chargers', jsonb_build_object(
       'at_depot',                  (SELECT dcfc_at_depot FROM fleet),
       'used',                      dc.chargers_used,
       'sessions',                  dc.sessions,
       'turns_per_charger_per_day', CASE WHEN r.horizon_h >= 6 AND (SELECT dcfc_at_depot FROM fleet) > 0
                                         THEN round(dc.sessions * 24.0 / r.horizon_h
                                                    / (SELECT dcfc_at_depot FROM fleet), 2) END,
       'busy_pct',                  CASE WHEN r.horizon_h > 0 AND (SELECT dcfc_at_depot FROM fleet) > 0
                                         THEN round(100.0 * COALESCE(dc.hours, 0)
                                                    / (r.horizon_h * (SELECT dcfc_at_depot FROM fleet)), 1) END,
       'mean_session_min',          round(dc.mean_min::numeric, 1),
       'mean_kw',                   round(dc.mean_kw::numeric, 1),
       'kwh_per_session_hour',      round((dc.kwh / NULLIF(dc.hours, 0))::numeric, 1)),
    'l2_sessions', (SELECT count(*) FROM sess WHERE stall_type = 'l2'),
    'charge_wait', v_wait,
    'service_completion', CASE WHEN v_svc IS NOT NULL THEN
                            jsonb_build_object('must_do', v_svc->'must_do', 'must_do_done', v_svc->'must_do_done',
                                               'pct', v_svc->'service_completion_pct') END,
    'kpi', CASE WHEN v_five IS NOT NULL THEN
             jsonb_build_object('peak_site_kw', v_five->'peak_site_kw',
                                'peak_site_kw_demand', v_five->'peak_site_kw_demand',
                                'touch_events_per_turn', v_five->'touch_events_per_turn',
                                'p95_time_to_service_min', v_five->'p95_time_to_service_min') END,
    'kpi_errors', v_errors,
    'comparability', jsonb_build_object(
       'all_policies', 'visits, dispatches and charge sessions: every arm''s vehicles produce them, because the policy only proposes and the kernel disposes (0261)',
       'rule', 'db/checks/0149: a comparative metric read from an artifact only one arm produces measures which arm it is'),
    'caveats', (SELECT jsonb_agg(u.c ORDER BY u.o) FROM unnest(ARRAY[
       format('Times are quantized to the run''s %s-minute steps. A visit needs about three steps (arrive, plug, close) before it can leave, so coarse steps add time to every visit.', r.step_min),
       CASE WHEN r.horizon_h < 6 THEN format('The run covers %s hours, under 6, so per-day rates are not extrapolated from it.', round(r.horizon_h, 2)) END,
       CASE WHEN v_bo IS NOT NULL THEN format('This day ran on build-out %s (%s robotic fast chargers, %s kW DC, %s kW service). Its charger count and its converted spaces come from the run''s own record, not from today''s stall table.',
                                              v_bo->>'buildout_code', v_bo->>'dcfc_posts', v_bo->>'dcfc_max_concurrent_kw', v_bo->>'service_max_kw') END,
       'tier_group groups the generator''s visit archetypes. It is not yet a commercial tier.',
       'A visit still in the depot at the horizon is counted in in_depot_at_horizon and kept out of every time percentile.'])
       WITH ORDINALITY AS u(c, o) WHERE u.c IS NOT NULL))
    INTO v_out
  FROM r, dc;
  RETURN v_out;
END $function$;

-- ── the triggers, as live ──
CREATE TRIGGER trg_depots_updated BEFORE UPDATE ON public.depots FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
CREATE TRIGGER trg_ottoq_stall_seat_is_exclusive BEFORE INSERT OR UPDATE OF current_vehicle_id ON public.stalls
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_stall_seat_is_exclusive();
CREATE TRIGGER trg_ottoq_stalls_state_change AFTER INSERT OR UPDATE ON public.stalls
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_stalls_state_change();
CREATE TRIGGER trg_reassignment_guard BEFORE UPDATE ON public.stalls
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_trg_reassignment_guard();
CREATE TRIGGER trg_stalls_updated BEFORE UPDATE ON public.stalls FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
CREATE CONSTRAINT TRIGGER ottoq_site_buildout_never_commits
  AFTER INSERT ON public.ottoq_site_buildout_active
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_buildout_must_not_commit();

-- ── stand-ins ──
-- STAND-IN: the event signer (live: HMAC-signs and appends to ottoq_events). Records what the stall trigger says.
CREATE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text,
  p_entity_id uuid DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL,
  p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL, p_depot_id uuid DEFAULT NULL,
  p_previous_state jsonb DEFAULT NULL, p_new_state jsonb DEFAULT NULL, p_severity text DEFAULT NULL,
  p_correlation_id uuid DEFAULT NULL, p_parent_event_id uuid DEFAULT NULL, p_related_task_id uuid DEFAULT NULL,
  p_related_schedule_id uuid DEFAULT NULL, p_related_decision_id uuid DEFAULT NULL, p_outcome text DEFAULT NULL,
  p_latency_ms integer DEFAULT NULL, p_ingest_source text DEFAULT 'app', p_signing_key_id text DEFAULT 'system:v1',
  p_data_source text DEFAULT 'production', p_sim_run_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.ottoq_events (actor_type, actor_id, event_type, entity_type, entity_id, depot_id, payload, new_state,
                                   ingest_source, data_source, sim_run_id)
  VALUES (p_actor_type, p_actor_id, p_event_type, p_entity_type, p_entity_id, p_depot_id, p_payload, p_new_state,
          p_ingest_source, p_data_source, p_sim_run_id)
  RETURNING event_id
$$;
-- STAND-IN: the shield probe (live: logs an evaluation). The state-change trigger calls it only when a status moves.
CREATE FUNCTION public.ottoq_shield_probe(p_action_context text, p_entity_type text DEFAULT NULL, p_entity_id uuid DEFAULT NULL,
  p_context jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL, p_depot_id uuid DEFAULT NULL,
  p_triggered_by_event_id uuid DEFAULT NULL, p_override_id uuid DEFAULT NULL)
RETURNS TABLE(rule_code text, passed boolean, reason text, enforcement_taken text, evaluation_id uuid, severity text,
              enforcement text, suggested_action text, would_block boolean)
LANGUAGE sql AS $$ SELECT NULL::text, true, NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text, false WHERE false $$;
-- STAND-IN: the in-depot gate (live: decides a reassignment). The guard asks it only when a car leaves a stall.
CREATE FUNCTION public.ottoq_indepot_reassignment_guard(p_vehicle_id uuid, p_sim_run_id uuid, p_reason text DEFAULT 'optimization',
  p_payload jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"allowed": true}'::jsonb $$;
-- STAND-IN: a rig in flight is what the test says (test.in_flight, default 0).
CREATE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('test.in_flight', true), '')::int, 0)
$$;
-- STAND-INS: the KPI functions the scorecard reuses, constant per run, and the visit outcomes from the test table.
CREATE FUNCTION public.ottoq_kpi_five(p_run uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('peak_site_kw', 812.5, 'peak_site_kw_demand', 790.0, 'touch_events_per_turn', 0.12,
                            'p95_time_to_service_min', 17)
$$;
CREATE FUNCTION public.ottoq_kpi_charge_wait(p_run uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('waits', 3, 'p50_min', 4)
$$;
CREATE FUNCTION public.ottoq_kpi_service_completion(p_run uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('must_do', 10, 'must_do_done', 9, 'service_completion_pct', 90.0)
$$;
CREATE FUNCTION public.ottoq_visit_outcomes(p_run uuid)
RETURNS TABLE(visit_id uuid, vehicle_id uuid, archetype text, tier_group text, arrived_at timestamp with time zone,
              due_at timestamp with time zone, departed_at timestamp with time zone, door_min numeric, on_time boolean,
              late_min numeric, soc_out numeric, target_soc numeric, needed_open_at_departure integer,
              cleared_by_triage integer, done_without_time integer, in_depot_at_horizon boolean)
LANGUAGE sql STABLE AS $$
  SELECT o.visit_id, o.vehicle_id, o.archetype, o.tier_group, o.arrived_at, o.due_at, o.departed_at, o.door_min, o.on_time,
         o.late_min, o.soc_out, o.target_soc, o.needed_open_at_departure, o.cleared_by_triage, o.done_without_time,
         o.in_depot_at_horizon
    FROM public._test_visit_outcomes o WHERE o.sim_run_id = p_run
$$;

-- ── grants, as live ──
REVOKE ALL ON FUNCTION public.ottoq_site_buildout_apply(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_site_buildout_restore(uuid)     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_site_buildout_census(uuid)      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_site_buildout_apply(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_site_buildout_restore(uuid)     TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_site_buildout_census(uuid)      TO authenticated, service_role;

-- ── the twin depot, as read on 2026-10-19 ──
INSERT INTO public.depots (id, feed_mode, dcfc_max_concurrent_kw, service_max_kw, site_layout) VALUES ('11111111-1111-1111-1111-111111111111', 'sim', 1800, 2500, '{"units": "feet; 1 render unit = 1.56988189 ft", "y_axis": "north_positive", "l2_count": 30, "wash_bays": 3, "dcfc_count": 10, "gate_egress": "SW", "orientation": "east_west", "gate_ingress": "SE", "service_bays": 2, "bess_power_kw": 1500, "flow_doctrine": "continuous_motion_no_back_out_through_service", "flow_sequence": ["ingress", "arrival_inspection", "charging", "cleaning", "service_if_needed", "staging", "egress"], "layout_source": "ottoyarddepot-sim src/lib/sitePlan.ts via scripts/buildLayoutSeed.mjs", "origin_corner": "SW", "rail_adjacent": "north", "stall_dims_ft": {"parking": "10x18 nominal, trimmed to run pitch", "charging": "10x20 nominal, trimmed to run pitch", "wash_bay": "14x35 ASSUMPTION", "service_bay": "14x30 ASSUMPTION"}, "lane_widths_ft": {"one_way": 20, "two_way": 26}, "solar_canopies": 3, "staging_stalls": 115, "bess_energy_kwh": 3000, "staging_covered": true, "layout_migration": "0010_unify_depot_layout", "rendering_source": "renderer sitePlan v2 (human reviewed)", "solar_total_kw_dc": 720, "frontage_direction": "south", "expected_fleet_size": 100, "staging_canopy_kind": "metal_roof", "service_bay_capacity": 2, "expected_visits_per_vehicle_per_day": "2-3"}'::jsonb);
INSERT INTO public.ottoq_vehicle_classes VALUES ('generic_av_dcfc'), ('generic_av_l2'), ('generic_passenger_av'), ('generic_robotaxi'), ('tesla_model_y_robotaxi_2024'), ('waymo_jaguar_ipace_2024'), ('zoox_robotaxi_2024');
INSERT INTO public.ottoq_operation_catalog VALUES ('robotaxi', 'charge_dcfc'), ('robotaxi', 'charge_l2'), ('robotaxi', 'interior_tidy'), ('robotaxi', 'remote_diagnostics'), ('robotaxi', 'sensor_clean'), ('robotaxi', 'software_update');
INSERT INTO public.ottoq_ocpp_chargers (charger_id, depot_id, ocpp_identifier, vendor, model, firmware_version,
  ocpp_protocol_version, station_state, max_kw, num_connectors, connector_states, installed_at, decommissioned_at) VALUES
  ('04c6b817-f973-41c7-8b6c-e427d5058bfd', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-01', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Available', 350, 1, '{}'::jsonb, NULL, NULL),
  ('c5a11716-0cb5-436d-9780-fe4c7a9f9399', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-02', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Faulted', 350, 1, '{}'::jsonb, NULL, NULL),
  ('c2c3b01a-c2b2-4697-b72d-db69095c3bbc', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-03', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Available', 350, 1, '{}'::jsonb, NULL, NULL),
  ('40ecb991-3f24-4b7d-8b3c-8e860627c888', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-04', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Available', 350, 1, '{}'::jsonb, NULL, NULL),
  ('ddb36fd4-770a-41ad-8b46-ce092c365089', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-05', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Faulted', 350, 1, '{}'::jsonb, NULL, NULL),
  ('4dc571e1-413b-4976-9337-e14912d0e6da', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-06', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Available', 350, 1, '{}'::jsonb, NULL, NULL),
  ('70b5ff96-e6b7-44f0-b2d9-2fec47948c6d', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-07', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Available', 350, 1, '{}'::jsonb, NULL, NULL),
  ('420702d7-e8cf-4ae8-b071-c373231ee4cf', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-08', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Available', 350, 1, '{}'::jsonb, NULL, NULL),
  ('90df3986-3281-4a78-b334-92156bd83c11', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-09', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Available', 350, 1, '{}'::jsonb, NULL, NULL),
  ('59f30cfb-7392-49eb-a5f7-7e29b4703f7e', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-10', 'ABB', 'Terra HP 350', '1.4.2', '1.6J', 'Available', 350, 1, '{}'::jsonb, NULL, NULL),
  ('d301c043-64d2-4a48-9b9b-166497befbfe', '11111111-1111-1111-1111-111111111111', 'NASH-L2-01', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('f523b1b5-54c1-435b-8a64-13082061761a', '11111111-1111-1111-1111-111111111111', 'NASH-L2-02', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('bf363754-6e2b-4e0b-ba76-0a884e9815a2', '11111111-1111-1111-1111-111111111111', 'NASH-L2-03', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('f94ec0c0-f581-4951-bb75-6d22e81bac18', '11111111-1111-1111-1111-111111111111', 'NASH-L2-04', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('0d46cfd0-4c47-43dc-b596-4e82cff27e2e', '11111111-1111-1111-1111-111111111111', 'NASH-L2-05', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('669cc797-fabd-4edf-a498-84d34c075cd3', '11111111-1111-1111-1111-111111111111', 'NASH-L2-06', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('31a902ac-7b83-475f-a207-45822814de93', '11111111-1111-1111-1111-111111111111', 'NASH-L2-07', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('224e1d48-f919-4400-af8a-a71ddfd0ffd4', '11111111-1111-1111-1111-111111111111', 'NASH-L2-08', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Faulted', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('63e198f2-3575-482a-ae6a-98f8711129cc', '11111111-1111-1111-1111-111111111111', 'NASH-L2-09', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('eda6ec6a-621e-4ccb-bc00-df69af992ab2', '11111111-1111-1111-1111-111111111111', 'NASH-L2-10', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('bc472f1f-9ce1-4a72-a875-b2f6d1d25da2', '11111111-1111-1111-1111-111111111111', 'NASH-L2-11', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('57a451e4-4643-4b97-8d06-931b2343d404', '11111111-1111-1111-1111-111111111111', 'NASH-L2-12', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('1c93ef7b-1be7-49a9-ad3f-c7a67043903b', '11111111-1111-1111-1111-111111111111', 'NASH-L2-13', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('29d483e5-84e5-4578-90c3-474efc3eb605', '11111111-1111-1111-1111-111111111111', 'NASH-L2-14', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('ad150cbb-b526-4b96-b7af-3f73bbfacd1c', '11111111-1111-1111-1111-111111111111', 'NASH-L2-15', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('1c0a3045-c430-453e-8b87-bb7464bd70cd', '11111111-1111-1111-1111-111111111111', 'NASH-L2-16', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('0b2ae0e1-172b-45ce-9164-c441d1ec6a74', '11111111-1111-1111-1111-111111111111', 'NASH-L2-17', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('57b526e7-c09c-4736-84ed-f55b25362935', '11111111-1111-1111-1111-111111111111', 'NASH-L2-18', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('ad5dfafc-9c22-4199-a210-c98ac7468bf3', '11111111-1111-1111-1111-111111111111', 'NASH-L2-19', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('da614701-ef70-4eb6-b6c5-59e2bd2d4fe6', '11111111-1111-1111-1111-111111111111', 'NASH-L2-20', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('90ef969b-e3f2-4501-ac0a-b43eae7c5ffd', '11111111-1111-1111-1111-111111111111', 'NASH-L2-21', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('d53a849a-9c82-4c61-87ba-46a5cd34843a', '11111111-1111-1111-1111-111111111111', 'NASH-L2-22', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('8d143ee0-6a25-4771-b423-67700277d49c', '11111111-1111-1111-1111-111111111111', 'NASH-L2-23', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('7e417349-056c-42bf-81fa-1df3b04a1a11', '11111111-1111-1111-1111-111111111111', 'NASH-L2-24', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('186a0d66-eca5-4201-ada9-d79fa173c64a', '11111111-1111-1111-1111-111111111111', 'NASH-L2-25', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('d9f483b1-73a0-4936-95e5-60a278f8c5dd', '11111111-1111-1111-1111-111111111111', 'NASH-L2-26', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('e211c51f-2f13-4d2e-8216-4539ca674fa7', '11111111-1111-1111-1111-111111111111', 'NASH-L2-27', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('f0813a87-9d60-4fe8-bfd1-dc4c5924aa89', '11111111-1111-1111-1111-111111111111', 'NASH-L2-28', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('5b918708-e2ae-4727-bedf-27496628aa73', '11111111-1111-1111-1111-111111111111', 'NASH-L2-29', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('e9a32d48-f506-48a0-94cd-7e1d3a2a7933', '11111111-1111-1111-1111-111111111111', 'NASH-L2-30', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('ef25544a-9d8f-4928-bee0-738aec3c7c1f', '11111111-1111-1111-1111-111111111111', 'NASH-L2-31', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('76fdb945-47f9-4398-ba81-34d2b8fb7d64', '11111111-1111-1111-1111-111111111111', 'NASH-L2-32', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('3caee32b-a3f3-4c40-b598-be5146fb5eff', '11111111-1111-1111-1111-111111111111', 'NASH-L2-33', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('a273725f-61da-4de5-827b-257d6b95de88', '11111111-1111-1111-1111-111111111111', 'NASH-L2-34', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Available', 19.2, 1, '{}'::jsonb, NULL, NULL),
  ('443a7c32-7914-4002-955f-c9cb100f6a79', '11111111-1111-1111-1111-111111111111', 'NASH-L2-35', 'ChargePoint', 'CT4000 Family', '5.105.1', '1.6J', 'Faulted', 19.2, 1, '{}'::jsonb, NULL, NULL);
INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, display_name, relative_x, relative_y, heading_degrees,
  absolute_lat, absolute_lng, distance_from_entrance, status, equipment_config, fiducial_marker_id, uwb_beacon_id, zone,
  connector_type, connector_max_kw, supported_inlet_types, ocpp_charger_id, stall_kind, canopy_code, covered,
  stall_width_ft, stall_depth_ft, current_vehicle_id, reserved_by) VALUES
  ('765adddb-3dc3-4cd4-be62-28c76ed8e737', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-01', 'dcfc', 'CANOPY-01 W-01', 141.2894, 185.2461, 60, 36.14020892, -86.77231936, 243, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "W"}'::jsonb, 'FID-D1-01-A', 'UWB-D1-01', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '04c6b817-f973-41c7-8b6c-e427d5058bfd', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('609910b1-c888-4624-8077-76c2fc83615f', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-02', 'dcfc', 'CANOPY-01 W-02', 141.2894, 163.2677, 60, 36.14014854, -86.77231936, 225, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "W"}'::jsonb, 'FID-D1-02-A', 'UWB-D1-02', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'c5a11716-0cb5-436d-9780-fe4c7a9f9399', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('bcff04b2-ad01-40fe-89fd-3c262af75305', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-03', 'dcfc', 'CANOPY-01 W-03', 141.2894, 141.2894, 60, 36.14008816, -86.77231936, 209, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "W"}'::jsonb, 'FID-D1-03-A', 'UWB-D1-03', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'c2c3b01a-c2b2-4697-b72d-db69095c3bbc', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('51a1c43b-8982-4023-ae3e-b9ef41cf0b89', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-04', 'dcfc', 'CANOPY-01 W-04', 141.2894, 119.311, 60, 36.14002778, -86.77231936, 194, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "W"}'::jsonb, 'FID-D1-04-A', 'UWB-D1-04', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '40ecb991-3f24-4b7d-8b3c-8e860627c888', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('364caf8d-6757-43c7-88e7-b4a0f9582751', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-05', 'dcfc', 'CANOPY-01 W-05', 141.2894, 97.3327, 60, 36.1399674, -86.77231936, 182, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "W"}'::jsonb, 'FID-D1-05-A', 'UWB-D1-05', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'ddb36fd4-770a-41ad-8b46-ce092c365089', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('91ebbf41-666a-4127-aea7-aad80f8f0adc', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-06', 'dcfc', 'CANOPY-01 E-06', 163.2677, 185.2461, 300, 36.14020892, -86.77224459, 229, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "E"}'::jsonb, 'FID-D1-06-A', 'UWB-D1-06', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '4dc571e1-413b-4976-9337-e14912d0e6da', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('c8049eb3-5ff8-478d-8a33-78fdd037ab35', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-07', 'dcfc', 'CANOPY-01 E-07', 163.2677, 163.2677, 300, 36.14014854, -86.77224459, 210, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "E"}'::jsonb, 'FID-D1-07-A', 'UWB-D1-07', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '70b5ff96-e6b7-44f0-b2d9-2fec47948c6d', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('9753cfd9-7abe-4bfd-a5a0-fa3b33de442c', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-08', 'dcfc', 'CANOPY-01 E-08', 163.2677, 141.2894, 300, 36.14008816, -86.77224459, 192, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "E"}'::jsonb, 'FID-D1-08-A', 'UWB-D1-08', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '420702d7-e8cf-4ae8-b071-c373231ee4cf', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('3a7310ac-5dfe-45fc-af3a-82d169345f30', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-09', 'dcfc', 'CANOPY-01 E-09', 163.2677, 119.311, 300, 36.14002778, -86.77224459, 176, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "E"}'::jsonb, 'FID-D1-09-A', 'UWB-D1-09', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '90df3986-3281-4a78-b334-92156bd83c11', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('0c916ac0-cecd-418f-9f0e-b086597489f3', '11111111-1111-1111-1111-111111111111', 'NASH-DCFC-STALL-10', 'dcfc', 'CANOPY-01 E-10', 163.2677, 97.3327, 300, 36.1399674, -86.77224459, 162, 'available', '{"charger_kw": 350, "canopy_code": "CANOPY-01", "canopy_side": "E"}'::jsonb, 'FID-D1-10-A', 'UWB-D1-10', 'dcfc_zone', 'Multi', 350, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '59f30cfb-7392-49eb-a5f7-7e29b4703f7e', 'charging', 'CANOPY-01', true, 10, 19.0276, NULL, NULL),
  ('a643de50-a12a-417d-b677-f7f9acf6e303', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-01', 'l2', 'CANOPY-02 W-01', 215.0738, 188.5428, 60, 36.14021797, -86.77206836, 204, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'd301c043-64d2-4a48-9b9b-166497befbfe', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('53b217b7-1d89-429a-9030-6295438ad32c', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-02', 'l2', 'CANOPY-02 W-02', 215.0738, 175.3558, 60, 36.14018175, -86.77206836, 190, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'f523b1b5-54c1-435b-8a64-13082061761a', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('fe18413d-9273-4199-8ae3-b063d633b27d', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-03', 'l2', 'CANOPY-02 W-03', 215.0738, 162.1688, 60, 36.14014552, -86.77206836, 175, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'bf363754-6e2b-4e0b-ba76-0a884e9815a2', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('70fa3080-2092-4d54-bd94-4f874bf3d161', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-04', 'l2', 'CANOPY-02 W-04', 215.0738, 148.9818, 60, 36.14010929, -86.77206836, 161, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'f94ec0c0-f581-4951-bb75-6d22e81bac18', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('ab17cc0e-479d-484b-8ccf-e0aba55b7078', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-05', 'l2', 'CANOPY-02 W-05', 215.0738, 135.7948, 60, 36.14007306, -86.77206836, 148, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '0d46cfd0-4c47-43dc-b596-4e82cff27e2e', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('55fe979e-00b1-44e7-bbcf-066f787976cd', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-06', 'l2', 'CANOPY-02 W-06', 215.0738, 122.6078, 60, 36.14003683, -86.77206836, 135, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '669cc797-fabd-4edf-a498-84d34c075cd3', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('74f716c7-77dd-475c-bd59-54b9ee2b200e', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-07', 'l2', 'CANOPY-02 W-07', 215.0738, 109.4208, 60, 36.14000061, -86.77206836, 123, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '31a902ac-7b83-475f-a207-45822814de93', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('fbb3a3df-d872-41e5-b834-a304186f82f2', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-08', 'l2', 'CANOPY-02 W-08', 215.0738, 96.2338, 60, 36.13996438, -86.77206836, 112, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '224e1d48-f919-4400-af8a-a71ddfd0ffd4', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('d5b7d268-e4d5-4141-b3f6-1d00df5e6357', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-09', 'l2', 'CANOPY-02 E-09', 237.0522, 181.9493, 300, 36.14019986, -86.77199359, 188, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '63e198f2-3575-482a-ae6a-98f8711129cc', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('7d9cedda-5016-4a47-9c29-b5a53651a9ef', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-10', 'l2', 'CANOPY-02 E-10', 237.0522, 168.7623, 300, 36.14016363, -86.77199359, 172, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'eda6ec6a-621e-4ccb-bc00-df69af992ab2', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('ccac745f-a9ca-47eb-94f4-8a3a1080d79c', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-11', 'l2', 'CANOPY-02 E-11', 237.0522, 155.5753, 300, 36.1401274, -86.77199359, 157, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'bc472f1f-9ce1-4a72-a875-b2f6d1d25da2', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('ce92a558-430f-4b2e-b248-621c568415ba', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-12', 'l2', 'CANOPY-02 E-12', 237.0522, 142.3883, 300, 36.14009118, -86.77199359, 141, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '57a451e4-4643-4b97-8d06-931b2343d404', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('95fe1b50-7e51-4b47-813f-b87774d53642', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-13', 'l2', 'CANOPY-02 E-13', 237.0522, 129.2013, 300, 36.14005495, -86.77199359, 126, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '1c93ef7b-1be7-49a9-ad3f-c7a67043903b', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('baded1fa-b635-43a1-9745-30f5ea1e3932', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-14', 'l2', 'CANOPY-02 E-14', 237.0522, 116.0143, 300, 36.14001872, -86.77199359, 112, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '29d483e5-84e5-4578-90c3-474efc3eb605', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('f7ac0175-e8b2-4a15-a9aa-c29537ab78da', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-15', 'l2', 'CANOPY-02 E-15', 237.0522, 102.8273, 300, 36.13998249, -86.77199359, 99, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-02", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'ad150cbb-b526-4b96-b7af-3f73bbfacd1c', 'charging', 'CANOPY-02', true, 10, 19.0276, NULL, NULL),
  ('56f6854b-63f7-46db-b145-6e445ee4eb3b', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-16', 'l2', 'CANOPY-03 W-16', 288.8583, 188.5428, 60, 36.14021797, -86.77181735, 185, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '1c0a3045-c430-453e-8b87-bb7464bd70cd', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('e9952b02-4f4c-4c4e-bb4b-fdd130f3051c', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-17', 'l2', 'CANOPY-03 W-17', 288.8583, 175.3558, 60, 36.14018175, -86.77181735, 168, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '0b2ae0e1-172b-45ce-9164-c441d1ec6a74', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('f0d61886-45fa-4187-acb0-9560f85390cb', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-18', 'l2', 'CANOPY-03 W-18', 288.8583, 162.1688, 60, 36.14014552, -86.77181735, 151, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '57b526e7-c09c-4736-84ed-f55b25362935', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('87f204a1-c4eb-43ba-85f9-5d967f91b706', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-19', 'l2', 'CANOPY-03 W-19', 288.8583, 148.9818, 60, 36.14010929, -86.77181735, 135, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'ad5dfafc-9c22-4199-a210-c98ac7468bf3', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('d01cc4ff-a0dd-4db0-a6ec-f8e5b95d7be7', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-20', 'l2', 'CANOPY-03 W-20', 288.8583, 135.7948, 60, 36.14007306, -86.77181735, 118, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'da614701-ef70-4eb6-b6c5-59e2bd2d4fe6', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('254d40a1-4c83-4b4f-a1b5-477300c3bc3f', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-26', 'l2', 'CANOPY-03 W-26', 288.8583, 122.6078, 60, 36.14003683, -86.77181735, 102, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'd9f483b1-73a0-4936-95e5-60a278f8c5dd', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('6b043f2d-e7b5-485b-beb1-3e7b7c283964', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-27', 'l2', 'CANOPY-03 W-27', 288.8583, 109.4208, 60, 36.14000061, -86.77181735, 85, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'e211c51f-2f13-4d2e-8216-4539ca674fa7', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('c957b07b-8481-446d-af1b-974421a10641', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-28', 'l2', 'CANOPY-03 W-28', 288.8583, 96.2338, 60, 36.13996438, -86.77181735, 69, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "W"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'f0813a87-9d60-4fe8-bfd1-dc4c5924aa89', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('c1808c59-6c55-406e-9821-25ba548698bc', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-29', 'l2', 'CANOPY-03 E-29', 310.8366, 181.9493, 300, 36.14019986, -86.77174259, 176, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '5b918708-e2ae-4727-bedf-27496628aa73', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('3f2338b8-5844-4bc3-a7d9-152439279fcd', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-30', 'l2', 'CANOPY-03 E-30', 310.8366, 168.7623, 300, 36.14016363, -86.77174259, 159, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'e9a32d48-f506-48a0-94cd-7e1d3a2a7933', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('bed6e8cf-4816-4451-b6ee-5294291912cd', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-31', 'l2', 'CANOPY-03 E-31', 310.8366, 155.5753, 300, 36.1401274, -86.77174259, 141, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'ef25544a-9d8f-4928-bee0-738aec3c7c1f', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('1bcc7405-d157-43ae-ac0c-ccb88791a451', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-32', 'l2', 'CANOPY-03 E-32', 310.8366, 142.3883, 300, 36.14009118, -86.77174259, 124, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '76fdb945-47f9-4398-ba81-34d2b8fb7d64', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('f517a13e-c512-485f-af8b-4e92e9aae972', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-33', 'l2', 'CANOPY-03 E-33', 310.8366, 129.2013, 300, 36.14005495, -86.77174259, 107, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '3caee32b-a3f3-4c40-b598-be5146fb5eff', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('f99a8657-b524-46a5-9080-c37f25c6a33d', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-34', 'l2', 'CANOPY-03 E-34', 310.8366, 116.0143, 300, 36.14001872, -86.77174259, 90, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], 'a273725f-61da-4de5-827b-257d6b95de88', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL),
  ('35c6e6f3-8291-42e6-95a0-a9a4dc7daec1', '11111111-1111-1111-1111-111111111111', 'NASH-L2-STALL-35', 'l2', 'CANOPY-03 E-35', 310.8366, 102.8273, 300, 36.13998249, -86.77174259, 72, 'available', '{"charger_kw": 19.2, "canopy_code": "CANOPY-03", "canopy_side": "E"}'::jsonb, NULL, NULL, 'l2_zone', 'Multi', 19.2, ARRAY['CCS1', 'CCS1', 'NACS']::text[], '443a7c32-7914-4002-955f-c9cb100f6a79', 'charging', 'CANOPY-03', true, 10, 19.0276, NULL, NULL);
INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, relative_x, relative_y, heading_degrees, zone,
  stall_kind, status) VALUES
  ('edd32618-2500-46bd-ac2b-ad3cd5621152', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B001', 'staging', 357.1481, 188.1503, 270, 'staging_buffer', 'staging', 'available'),
  ('aa9576a8-9785-41fc-bffd-9aef6056cdfa', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B002', 'staging', 357.1481, 177.6321, 270, 'staging_buffer', 'staging', 'available'),
  ('f40b19b9-b46a-4be0-b178-991dfa3803da', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B003', 'staging', 357.1481, 167.1139, 270, 'staging_buffer', 'staging', 'available'),
  ('321e4142-0afc-447c-a9ab-5b764d6b74d0', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B004', 'staging', 357.1481, 156.5957, 270, 'staging_buffer', 'staging', 'available'),
  ('9b1306c1-ceb7-46ed-904a-c4a27f09bd8b', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B005', 'staging', 357.1481, 146.0775, 270, 'staging_buffer', 'staging', 'available'),
  ('9c3a5d66-7d0c-4a0c-97c2-e570593cb62a', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B006', 'staging', 357.1481, 135.5593, 270, 'staging_buffer', 'staging', 'available'),
  ('06acce00-803c-4b41-b53c-43dcf092ff3d', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B007', 'staging', 357.1481, 125.0411, 270, 'staging_buffer', 'staging', 'available'),
  ('7b62a825-f2ee-42d5-9ff2-e384aae06190', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B008', 'staging', 357.1481, 114.5229, 270, 'staging_buffer', 'staging', 'occupied'),
  ('e0f2bf3a-04ca-48c7-81db-56a1217355b7', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B009', 'staging', 357.1481, 104.0047, 270, 'staging_buffer', 'staging', 'available'),
  ('a06d087f-d3d9-40c5-b390-096db034768c', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B010', 'staging', 357.1481, 93.4865, 270, 'staging_buffer', 'staging', 'available'),
  ('72a4c5cf-693e-4e21-ba64-99ab5da46c34', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B011', 'staging', 357.1481, 82.9683, 270, 'staging_buffer', 'staging', 'available'),
  ('ddedafd3-916d-4476-abfb-97291b6691ba', '11111111-1111-1111-1111-111111111111', 'NASH-STG-B012', 'staging', 357.1481, 72.45, 270, 'staging_buffer', 'staging', 'available'),
  ('ea308bdd-5116-4447-824d-9e950f760834', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E001', 'staging', 441.9218, 251.1811, 90, 'staging_east', 'staging', 'available'),
  ('cddbeec9-9dc7-441d-a77d-3719cc21cf8f', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E002', 'staging', 441.9218, 242.2328, 90, 'staging_east', 'staging', 'available'),
  ('cf20d99e-6cf7-4cc5-882d-0c1d8f9f0ae1', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E003', 'staging', 441.9218, 233.2844, 90, 'staging_east', 'staging', 'available'),
  ('ed7a3d5b-3fbc-42bf-abad-d82e23241489', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E004', 'staging', 441.9218, 224.3361, 90, 'staging_east', 'staging', 'available'),
  ('52ca8378-da6d-48de-8576-f98919e71325', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E005', 'staging', 441.9218, 215.3878, 90, 'staging_east', 'staging', 'available'),
  ('705a5923-50b1-48d3-b7a6-fb0bd96a07bb', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E006', 'staging', 441.9218, 206.4395, 90, 'staging_east', 'staging', 'available'),
  ('9001b2d9-c967-4e4f-b346-720144be4b9d', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E007', 'staging', 441.9218, 197.4911, 90, 'staging_east', 'staging', 'available'),
  ('df3abf1b-de55-4797-9055-a02fcd5203ac', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E008', 'staging', 441.9218, 188.5428, 90, 'staging_east', 'staging', 'available'),
  ('b351e468-4d12-45ec-bf8e-ee46d3aa7f04', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E009', 'staging', 441.9218, 179.5945, 90, 'staging_east', 'staging', 'available'),
  ('43470598-0664-4f5e-b8cc-bb045e69215a', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E010', 'staging', 441.9218, 170.6462, 90, 'staging_east', 'staging', 'available'),
  ('3e6aa7d1-ca74-4945-8977-1cae630189a6', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E011', 'staging', 441.9218, 161.6978, 90, 'staging_east', 'staging', 'available'),
  ('84856861-9704-4ebe-87e7-2eebaa30cd62', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E012', 'staging', 441.9218, 152.7495, 90, 'staging_east', 'staging', 'available'),
  ('3b632e63-5438-499e-8c8e-c8dc4f18550f', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E013', 'staging', 441.9218, 143.8012, 90, 'staging_east', 'staging', 'available'),
  ('9454f83f-2427-4de8-bd2c-5cdf4a275f5f', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E014', 'staging', 441.9218, 134.8529, 90, 'staging_east', 'staging', 'available'),
  ('4c28b133-6d52-4a78-844c-f83351cd52be', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E015', 'staging', 441.9218, 125.9045, 90, 'staging_east', 'staging', 'available'),
  ('8f32ff01-cd1c-41ab-96aa-2c3c215e0d88', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E016', 'staging', 441.9218, 116.9562, 90, 'staging_east', 'staging', 'available'),
  ('565826f1-4e43-441f-b2db-ee795d329160', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E017', 'staging', 441.9218, 108.0079, 90, 'staging_east', 'staging', 'available'),
  ('a74d1388-fcb8-4853-922b-605484f11b20', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E018', 'staging', 441.9218, 99.0595, 90, 'staging_east', 'staging', 'available'),
  ('95a5bfe9-a556-495f-8256-7680bf16ad22', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E019', 'staging', 441.9218, 90.1112, 90, 'staging_east', 'staging', 'available'),
  ('64337de3-e511-4ca6-8a75-d4654dddc4c7', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E020', 'staging', 441.9218, 81.1629, 90, 'staging_east', 'staging', 'available'),
  ('7f2dad9b-16e6-46c0-9395-670bb14f1bc9', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E021', 'staging', 441.9218, 72.2146, 90, 'staging_east', 'staging', 'available'),
  ('2b5e3934-a836-468b-8cfa-d2947295b5cd', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E022', 'staging', 441.9218, 63.2662, 90, 'staging_east', 'staging', 'available'),
  ('0b1ce992-6eb8-41cf-88ad-bf96b77dc01b', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E023', 'staging', 441.9218, 54.3179, 90, 'staging_east', 'staging', 'available'),
  ('3bfa7361-187d-4b75-9e0b-072a91a3b279', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E024', 'staging', 441.9218, 45.3696, 90, 'staging_east', 'staging', 'available'),
  ('9cc9c0aa-3f79-4580-8183-c53dfea20bfc', '11111111-1111-1111-1111-111111111111', 'NASH-STG-E025', 'staging', 441.9218, 36.4213, 90, 'staging_east', 'staging', 'available'),
  ('16229eb4-693b-405d-924e-ef413ca4df24', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I001', 'staging', 399.5349, 188.1503, 90, 'arrival_inspection', 'inspection', 'available'),
  ('d9274bd6-5bb5-4194-8150-a033cf1995b7', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I002', 'staging', 399.5349, 177.6321, 90, 'arrival_inspection', 'inspection', 'available'),
  ('75f94ee9-691c-4503-b469-629d1f3af1fb', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I003', 'staging', 399.5349, 167.1139, 90, 'arrival_inspection', 'inspection', 'available'),
  ('908e94ac-03bd-4c50-90d4-96b879db552a', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I004', 'staging', 399.5349, 156.5957, 90, 'arrival_inspection', 'inspection', 'available'),
  ('7c20e64e-f19c-48c2-be75-20d49f4a86f8', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I005', 'staging', 399.5349, 146.0775, 90, 'arrival_inspection', 'inspection', 'available'),
  ('a13d155b-adb0-4ae5-9954-45246fdc0737', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I006', 'staging', 399.5349, 135.5593, 90, 'arrival_inspection', 'inspection', 'available'),
  ('f4d2620e-09b9-4266-8879-df60e3f2f4f8', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I007', 'staging', 399.5349, 125.0411, 90, 'arrival_inspection', 'inspection', 'available'),
  ('2073cfe4-b9cf-4d53-89d6-db2d1cbbd53a', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I008', 'staging', 399.5349, 114.5229, 90, 'arrival_inspection', 'inspection', 'available'),
  ('6ff2fbd6-737d-4646-ae47-446ac8ce30b3', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I009', 'staging', 399.5349, 104.0047, 90, 'arrival_inspection', 'inspection', 'available'),
  ('bf082cbd-f0c3-450e-8b04-80dd8815cb11', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I010', 'staging', 399.5349, 93.4865, 90, 'arrival_inspection', 'inspection', 'available'),
  ('d31325c3-8090-4213-9ba0-241a37aa8d41', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I011', 'staging', 399.5349, 82.9683, 90, 'arrival_inspection', 'inspection', 'occupied'),
  ('aaab302d-dedb-4841-ad21-bc1af8be9a3e', '11111111-1111-1111-1111-111111111111', 'NASH-STG-I012', 'staging', 399.5349, 72.45, 90, 'arrival_inspection', 'inspection', 'available'),
  ('0b717fd2-3162-497f-8593-d702256f1e27', '11111111-1111-1111-1111-111111111111', 'NASH-STG-N001', 'staging', 343.8041, 266.8799, 0, 'staging_north', 'staging', 'available'),
  ('bcfce849-19aa-4cfd-8288-b2829016e3a4', '11111111-1111-1111-1111-111111111111', 'NASH-STG-N002', 'staging', 353.2234, 266.8799, 0, 'staging_north', 'staging', 'available'),
  ('9f2e801c-f75f-4b91-8d4d-5891a8bc0827', '11111111-1111-1111-1111-111111111111', 'NASH-STG-N003', 'staging', 362.6427, 266.8799, 0, 'staging_north', 'staging', 'available'),
  ('600f3ed0-a59d-465a-9cb1-31d201bfa496', '11111111-1111-1111-1111-111111111111', 'NASH-STG-N004', 'staging', 372.062, 266.8799, 0, 'staging_north', 'staging', 'available'),
  ('c3302229-dc31-4625-a376-e6b22d2cdfdf', '11111111-1111-1111-1111-111111111111', 'NASH-STG-N005', 'staging', 381.4813, 266.8799, 0, 'staging_north', 'staging', 'available'),
  ('e1e25a56-7cc0-426b-a5c6-5b7b2de7ac95', '11111111-1111-1111-1111-111111111111', 'NASH-STG-N006', 'staging', 390.9006, 266.8799, 0, 'staging_north', 'staging', 'available'),
  ('53c971c7-6339-44fe-9329-e34388dc8cae', '11111111-1111-1111-1111-111111111111', 'NASH-STG-N007', 'staging', 400.3199, 266.8799, 0, 'staging_north', 'staging', 'available'),
  ('c11a019a-066e-4575-a2ae-75bcef7dfadc', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S001', 'staging', 28.2579, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('c2502ade-7735-49e0-9d37-f01a6e315998', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S002', 'staging', 38.3051, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('37ea4a5e-c417-42f4-b75e-f585d7eace68', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S003', 'staging', 48.3524, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('1d72edc7-bb12-4e02-bf21-3f810d270e19', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S004', 'staging', 58.3996, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('0882c6bf-edb3-448d-867a-10309e732cad', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S005', 'staging', 68.4469, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('4125e6a3-254b-4627-9108-b644eb432fb8', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S006', 'staging', 78.4941, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('4d079d35-abfe-405d-8492-5f8c9713d3eb', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S007', 'staging', 88.5413, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('5a4a589f-bd06-46cf-80bc-f0bda77c3394', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S008', 'staging', 98.5886, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('3b74da73-9bba-4c95-b498-3c56f5236495', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S009', 'staging', 108.6358, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('3621b5a6-0271-4750-8c9b-1c9fab123cd2', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S010', 'staging', 118.6831, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('064cd348-4530-44a1-bc9f-9c2eb6eb55e3', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S011', 'staging', 128.7303, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('d1389961-9c82-432f-a503-6b65c763d180', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S012', 'staging', 166.4075, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('b8b5b980-ef54-4611-a6a9-6e29f49f0693', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S013', 'staging', 177.2397, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('8d393775-d68e-4222-b4ab-f237e61ae6fc', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S014', 'staging', 188.0719, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('04d65645-3c56-493b-b745-d7c8e60695d0', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S015', 'staging', 198.904, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('1e3aae00-3613-4e31-a217-0785bb5332a1', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S016', 'staging', 209.7362, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('28b2f4fa-ff9a-4d16-954b-d22c9304506d', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S017', 'staging', 220.5684, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('c747ff79-0d45-4d45-97c6-385b9130e62b', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S018', 'staging', 231.4006, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('2059acb2-53ae-42b1-b056-2220dc26e44a', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S019', 'staging', 242.2328, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('a7c459b3-5340-4069-8204-c320fb8e73dc', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S020', 'staging', 253.065, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('b5660c4c-1e8c-491d-9c33-6a77d8a2a014', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S021', 'staging', 263.8971, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('bc469f6a-edfd-46b9-b71f-be3d9e249c74', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S022', 'staging', 274.7293, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('ef90f15d-5f7b-4435-841a-9b43db798e28', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S023', 'staging', 285.5615, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('6ef1c4c5-4deb-4a6f-98c5-9fa90ff57586', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S024', 'staging', 323.3957, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('0c20ea1d-81bf-4eb5-8bdd-0216a304d5b2', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S025', 'staging', 333.4429, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('53a3c935-8639-5f30-a251-8182198f611d', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S026', 'staging', 343.4902, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('f2b216a7-867d-5ed0-85f9-0a61aa0fa87b', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S027', 'staging', 353.5374, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('f75e515c-fcef-5e36-bb8d-a80301f33a38', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S028', 'staging', 363.5846, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('684df10b-3ecf-5dde-9938-f50952c2083e', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S029', 'staging', 373.6319, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('83bd04af-44db-580f-93c4-d1ce6742017c', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S030', 'staging', 383.6791, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('6bcfdc16-f1c2-5a61-a1d4-f3d50ac6a25f', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S031', 'staging', 393.7264, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('da2b6c48-baa5-5709-89a6-3ab2d3f058fd', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S032', 'staging', 403.7736, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('fafdf93c-c51c-5a52-aa4b-094f2b878d70', '11111111-1111-1111-1111-111111111111', 'NASH-STG-S033', 'staging', 413.8209, 14.1289, 0, 'staging_south', 'staging', 'available'),
  ('e49d641c-3103-425d-867f-5d42d30ab85d', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W001', 'staging', 14.9139, 232.3425, 90, 'staging_west', 'staging', 'available'),
  ('0f40a5ce-e1f1-4e20-a9be-f0739f72d8fc', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W002', 'staging', 14.9139, 223.3942, 90, 'staging_west', 'staging', 'available'),
  ('f39d9e37-af8f-4cea-861f-cb0a2657ecf3', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W003', 'staging', 14.9139, 214.4459, 90, 'staging_west', 'staging', 'available'),
  ('da2bbed2-a874-47cf-8c04-550155e48243', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W004', 'staging', 14.9139, 205.4975, 90, 'staging_west', 'staging', 'available'),
  ('66752732-3230-451d-b292-54c71dddb2ca', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W005', 'staging', 14.9139, 196.5492, 90, 'staging_west', 'staging', 'available'),
  ('b589dc72-8399-42c5-b7c0-e4e71889253b', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W006', 'staging', 14.9139, 187.6009, 90, 'staging_west', 'staging', 'available'),
  ('4c017eb1-8753-47a6-8c65-29ad5a85b0a8', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W007', 'staging', 14.9139, 178.6526, 90, 'staging_west', 'staging', 'available'),
  ('f44b8c6f-91f0-40ed-8d69-80d82c71e4e1', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W008', 'staging', 14.9139, 169.7042, 90, 'staging_west', 'staging', 'available'),
  ('86ccfc5f-ade1-4e29-bc6c-48e63cdfab69', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W009', 'staging', 14.9139, 160.7559, 90, 'staging_west', 'staging', 'available'),
  ('57511667-f4f1-44fa-9896-174cd3e02dd6', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W010', 'staging', 14.9139, 151.8076, 90, 'staging_west', 'staging', 'available'),
  ('8d100030-d211-42a9-a933-3386dfe39b78', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W011', 'staging', 14.9139, 142.8593, 90, 'staging_west', 'staging', 'available'),
  ('a44afde8-3ae9-4357-acba-e86fd21aec29', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W012', 'staging', 14.9139, 133.9109, 90, 'staging_west', 'staging', 'available'),
  ('65af8ebd-4db3-4664-936f-1e4ee0946592', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W013', 'staging', 14.9139, 124.9626, 90, 'staging_west', 'staging', 'available'),
  ('4d656095-9645-496c-b6ce-b6407a397c08', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W014', 'staging', 14.9139, 116.0143, 90, 'staging_west', 'staging', 'available'),
  ('31b80354-e50d-4f93-81dd-9199c2cf696c', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W015', 'staging', 14.9139, 107.0659, 90, 'staging_west', 'staging', 'available'),
  ('479b38df-870b-47b6-9145-24e53e2ec9b0', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W016', 'staging', 14.9139, 98.1176, 90, 'staging_west', 'staging', 'available'),
  ('ff709acf-ab3f-49fc-be39-37e8867a4b6b', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W017', 'staging', 14.9139, 89.1693, 90, 'staging_west', 'staging', 'available'),
  ('5bdb64d5-f47e-5676-a826-7292f285b55b', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W018', 'staging', 14.9139, 80.221, 90, 'staging_west', 'staging', 'available'),
  ('92d2500a-bfd2-5932-af30-d196f2c285ac', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W019', 'staging', 14.9139, 71.2726, 90, 'staging_west', 'staging', 'available'),
  ('23db519a-aad0-5638-9744-da6b9e6e2875', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W020', 'staging', 14.9139, 62.3243, 90, 'staging_west', 'staging', 'available'),
  ('6195dc57-8c01-57f6-8100-885950d21739', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W021', 'staging', 14.9139, 53.376, 90, 'staging_west', 'staging', 'available'),
  ('48acb7ba-cbe5-5986-92af-fefdd9092d4f', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W022', 'staging', 14.9139, 44.4277, 90, 'staging_west', 'staging', 'available'),
  ('15ee200d-bfc0-543e-bcdf-921cbc990dc3', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W023', 'staging', 14.9139, 35.4793, 90, 'staging_west', 'staging', 'available'),
  ('93789324-63d8-5b61-9c28-fcf7c031857c', '11111111-1111-1111-1111-111111111111', 'NASH-STG-W024', 'staging', 14.9139, 26.531, 90, 'staging_west', 'staging', 'available'),
  ('6ff1e0a5-aef0-4b3f-b8bb-b7b5f0e90402', '11111111-1111-1111-1111-111111111111', 'NASH-SVC-01', 'service_bay', 178.9665, 259.0305, 0, 'service', 'service', 'available'),
  ('e8c670f7-cace-4615-8c46-26d1e1c17881', '11111111-1111-1111-1111-111111111111', 'NASH-SVC-02', 'service_bay', 207.2244, 259.0305, 0, 'service', 'service', 'available'),
  ('c9466ca6-5dca-487d-be44-f6c45f5eb6a3', '11111111-1111-1111-1111-111111111111', 'NASH-WSH-01', 'wash_bay', 254.3209, 259.0305, 0, 'cleaning', 'wash', 'available'),
  ('6277d0cc-da92-49a2-8f0c-e0d534e6fb1a', '11111111-1111-1111-1111-111111111111', 'NASH-WSH-02', 'wash_bay', 282.5787, 259.0305, 0, 'cleaning', 'wash', 'available'),
  ('ec443362-dbf3-4a73-aa5b-a597bc837c66', '11111111-1111-1111-1111-111111111111', 'NASH-WSH-03', 'wash_bay', 310.8366, 259.0305, 0, 'cleaning', 'wash', 'available');
-- the charger stalls' capabilities: every asset class, its charge operation and the four that ride along
INSERT INTO public.ottoq_service_point_capabilities (stall_id, asset_class_code, operation_code)
SELECT s.id, c.vehicle_class_code, o.op
  FROM public.stalls s CROSS JOIN public.ottoq_vehicle_classes c
  CROSS JOIN LATERAL unnest(ARRAY[CASE WHEN s.stall_type = 'dcfc' THEN 'charge_dcfc' ELSE 'charge_l2' END,
                                  'interior_tidy', 'remote_diagnostics', 'sensor_clean', 'software_update']) AS o(op)
 WHERE s.stall_type IN ('dcfc', 'l2');
INSERT INTO public.ottoq_site_structures (structure_id, depot_id, structure_code, structure_kind, title, origin_x_ft,
  origin_y_ft, width_ft, length_ft, height_ft, rotation_deg, absolute_lat, absolute_lng, properties, status, introduced_in,
  created_at) VALUES
  ('e8137314-926a-4fcf-9889-f4879c464d30', '11111111-1111-1111-1111-111111111111', 'CANOPY-01', 'solar_canopy', 'Solar Canopy A (DCFC)', 128.7303, 65.935, 47.0965, 131.8701, 14.0, 0.0, 36.14006228, -86.77228197, '{"chargers": {"dcfc": 10}, "panel_count": 288, "solar_kw_dc": 180, "stall_capacity": 10}'::jsonb, 'active', '0010_unify_depot_layout', '2026-05-28T03:27:04.338541+00:00'),
  ('86e820f4-1c60-4316-b796-99808fb16ff7', '11111111-1111-1111-1111-111111111111', 'CANOPY-02', 'solar_canopy', 'Solar Canopy B (L2)', 202.5148, 65.935, 47.0965, 131.8701, 14.0, 0.0, 36.14006228, -86.77203097, '{"chargers": {"l2": 15}, "panel_count": 288, "solar_kw_dc": 180, "stall_capacity": 15}'::jsonb, 'active', '0010_unify_depot_layout', '2026-05-28T03:27:04.338541+00:00'),
  ('82b5f7e9-a73b-402b-8252-d0093de3765a', '11111111-1111-1111-1111-111111111111', 'CANOPY-03', 'solar_canopy', 'Solar Canopy C (L2)', 276.2992, 65.935, 47.0965, 131.8701, 14.0, 0.0, 36.14006228, -86.77177997, '{"chargers": {"l2": 15}, "panel_count": 288, "solar_kw_dc": 180, "stall_capacity": 15}'::jsonb, 'active', '0010_unify_depot_layout', '2026-05-28T03:27:04.338541+00:00');
-- the build-outs: codes, posts, conversions and power as live; titles and basis are stand-ins
INSERT INTO public.ottoq_site_buildouts (buildout_code, depot_id, title, dcfc_posts, convert_l2, dcfc_max_concurrent_kw,
  service_max_kw, basis) VALUES
  ('dcfc10', '11111111-1111-1111-1111-111111111111', 'stand-in title for dcfc10', 10, '{}'::text[], 1800, 2500, '{"note": "stand-in basis", "dc_kw_per_added_charger": 180}'::jsonb),
  ('dcfc15', '11111111-1111-1111-1111-111111111111', 'stand-in title for dcfc15', 15, ARRAY['NASH-L2-STALL-01', 'NASH-L2-STALL-02', 'NASH-L2-STALL-03', 'NASH-L2-STALL-04', 'NASH-L2-STALL-05']::text[], 2700, 3431.5, '{"note": "stand-in basis", "dc_kw_per_added_charger": 180}'::jsonb),
  ('dcfc20', '11111111-1111-1111-1111-111111111111', 'stand-in title for dcfc20', 20, ARRAY['NASH-L2-STALL-01', 'NASH-L2-STALL-02', 'NASH-L2-STALL-03', 'NASH-L2-STALL-04', 'NASH-L2-STALL-05', 'NASH-L2-STALL-06', 'NASH-L2-STALL-07', 'NASH-L2-STALL-08', 'NASH-L2-STALL-09', 'NASH-L2-STALL-10']::text[], 3600, 4363, '{"note": "stand-in basis", "dc_kw_per_added_charger": 180}'::jsonb),
  ('dcfc20_grid_today', '11111111-1111-1111-1111-111111111111', 'stand-in title for dcfc20_grid_today', 20, ARRAY['NASH-L2-STALL-01', 'NASH-L2-STALL-02', 'NASH-L2-STALL-03', 'NASH-L2-STALL-04', 'NASH-L2-STALL-05', 'NASH-L2-STALL-06', 'NASH-L2-STALL-07', 'NASH-L2-STALL-08', 'NASH-L2-STALL-09', 'NASH-L2-STALL-10']::text[], 1800, 2500, '{"note": "stand-in basis", "dc_kw_per_added_charger": 180}'::jsonb),
  ('dcfc40', '11111111-1111-1111-1111-111111111111', 'stand-in title for dcfc40', 40, ARRAY['NASH-L2-STALL-01', 'NASH-L2-STALL-02', 'NASH-L2-STALL-03', 'NASH-L2-STALL-04', 'NASH-L2-STALL-05', 'NASH-L2-STALL-06', 'NASH-L2-STALL-07', 'NASH-L2-STALL-08', 'NASH-L2-STALL-09', 'NASH-L2-STALL-10', 'NASH-L2-STALL-11', 'NASH-L2-STALL-12', 'NASH-L2-STALL-13', 'NASH-L2-STALL-14', 'NASH-L2-STALL-15', 'NASH-L2-STALL-16', 'NASH-L2-STALL-17', 'NASH-L2-STALL-18', 'NASH-L2-STALL-19', 'NASH-L2-STALL-20', 'NASH-L2-STALL-26', 'NASH-L2-STALL-27', 'NASH-L2-STALL-28', 'NASH-L2-STALL-29', 'NASH-L2-STALL-30', 'NASH-L2-STALL-31', 'NASH-L2-STALL-32', 'NASH-L2-STALL-33', 'NASH-L2-STALL-34', 'NASH-L2-STALL-35']::text[], 7200, 8089, '{"note": "stand-in basis", "dc_kw_per_added_charger": 180}'::jsonb),
  ('dcfc40_cab2400', '11111111-1111-1111-1111-111111111111', 'stand-in title for dcfc40_cab2400', 40, ARRAY['NASH-L2-STALL-01', 'NASH-L2-STALL-02', 'NASH-L2-STALL-03', 'NASH-L2-STALL-04', 'NASH-L2-STALL-05', 'NASH-L2-STALL-06', 'NASH-L2-STALL-07', 'NASH-L2-STALL-08', 'NASH-L2-STALL-09', 'NASH-L2-STALL-10', 'NASH-L2-STALL-11', 'NASH-L2-STALL-12', 'NASH-L2-STALL-13', 'NASH-L2-STALL-14', 'NASH-L2-STALL-15', 'NASH-L2-STALL-16', 'NASH-L2-STALL-17', 'NASH-L2-STALL-18', 'NASH-L2-STALL-19', 'NASH-L2-STALL-20', 'NASH-L2-STALL-26', 'NASH-L2-STALL-27', 'NASH-L2-STALL-28', 'NASH-L2-STALL-29', 'NASH-L2-STALL-30', 'NASH-L2-STALL-31', 'NASH-L2-STALL-32', 'NASH-L2-STALL-33', 'NASH-L2-STALL-34', 'NASH-L2-STALL-35']::text[], 2400, 2500, '{"note": "stand-in basis", "dc_kw_per_added_charger": 180}'::jsonb),
  ('dcfc40_grid_dcfc20', '11111111-1111-1111-1111-111111111111', 'stand-in title for dcfc40_grid_dcfc20', 40, ARRAY['NASH-L2-STALL-01', 'NASH-L2-STALL-02', 'NASH-L2-STALL-03', 'NASH-L2-STALL-04', 'NASH-L2-STALL-05', 'NASH-L2-STALL-06', 'NASH-L2-STALL-07', 'NASH-L2-STALL-08', 'NASH-L2-STALL-09', 'NASH-L2-STALL-10', 'NASH-L2-STALL-11', 'NASH-L2-STALL-12', 'NASH-L2-STALL-13', 'NASH-L2-STALL-14', 'NASH-L2-STALL-15', 'NASH-L2-STALL-16', 'NASH-L2-STALL-17', 'NASH-L2-STALL-18', 'NASH-L2-STALL-19', 'NASH-L2-STALL-20', 'NASH-L2-STALL-26', 'NASH-L2-STALL-27', 'NASH-L2-STALL-28', 'NASH-L2-STALL-29', 'NASH-L2-STALL-30', 'NASH-L2-STALL-31', 'NASH-L2-STALL-32', 'NASH-L2-STALL-33', 'NASH-L2-STALL-34', 'NASH-L2-STALL-35']::text[], 3600, 4363, '{"note": "stand-in basis", "dc_kw_per_added_charger": 180}'::jsonb),
  ('dcfc40_grid_today', '11111111-1111-1111-1111-111111111111', 'stand-in title for dcfc40_grid_today', 40, ARRAY['NASH-L2-STALL-01', 'NASH-L2-STALL-02', 'NASH-L2-STALL-03', 'NASH-L2-STALL-04', 'NASH-L2-STALL-05', 'NASH-L2-STALL-06', 'NASH-L2-STALL-07', 'NASH-L2-STALL-08', 'NASH-L2-STALL-09', 'NASH-L2-STALL-10', 'NASH-L2-STALL-11', 'NASH-L2-STALL-12', 'NASH-L2-STALL-13', 'NASH-L2-STALL-14', 'NASH-L2-STALL-15', 'NASH-L2-STALL-16', 'NASH-L2-STALL-17', 'NASH-L2-STALL-18', 'NASH-L2-STALL-19', 'NASH-L2-STALL-20', 'NASH-L2-STALL-26', 'NASH-L2-STALL-27', 'NASH-L2-STALL-28', 'NASH-L2-STALL-29', 'NASH-L2-STALL-30', 'NASH-L2-STALL-31', 'NASH-L2-STALL-32', 'NASH-L2-STALL-33', 'NASH-L2-STALL-34', 'NASH-L2-STALL-35']::text[], 1800, 2500, '{"note": "stand-in basis", "dc_kw_per_added_charger": 180}'::jsonb);
