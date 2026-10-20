-- tests/fixtures/bay_exit_leg_stub.sql: what db/migrations/0750's new functions write through, as live, for
-- tests/test_bay_exit_closes_its_leg_sql.py. Loaded after tests/fixtures/agent_charge_order_stub.sql, whose vehicles,
-- stalls, runs, bookings, visit needs and policy reader it uses. Read from the live catalog on 2026-10-17 between 11:20
-- and 11:40 PM CT (the test asserts each md5 of prosrc):
--   public.ottoq_itin_leg_close 6c33d450, public.ottoq_itin_leg_open 69effd4b, public.ottoq_trg_leg_done_sdr 8aa4c329,
--   public.ottoq_emit_sdr 25e9cbb1
-- and trg_0043_leg_done_sdr as live (AFTER UPDATE OF status, WHEN a leg turns done). The tables carry the live columns
-- these read and write, the live constraints of a service record that bear on it (one per leg, its source kinds), and
-- the live operation catalog rows of the bay leg types. Three stand-ins, noted where defined: the event hash, the SDR
-- signature and the event writer, which here records the event in public.ottoq_events and returns its id.
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS public.depots (id uuid PRIMARY KEY, feed_mode text);
INSERT INTO public.depots (id, feed_mode) VALUES ('11111111-1111-1111-1111-111111111111', 'sim') ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.ottoq_vehicle_itineraries (
  itinerary_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid NOT NULL, depot_id uuid NOT NULL,
  vehicle_id uuid NOT NULL, created_by text NOT NULL DEFAULT 'decide_tick', status text NOT NULL DEFAULT 'active'
    CHECK (status = ANY (ARRAY['active', 'completed', 'amended', 'cancelled'])),
  sim_created_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), visit_id uuid);
CREATE TABLE IF NOT EXISTS public.ottoq_itinerary_legs (
  leg_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  itinerary_id uuid NOT NULL REFERENCES public.ottoq_vehicle_itineraries (itinerary_id) ON DELETE CASCADE,
  sim_run_id uuid NOT NULL, vehicle_id uuid NOT NULL, seq integer NOT NULL, leg_type text NOT NULL, from_stall_id uuid,
  to_stall_id uuid, planned_start_sim timestamptz, planned_end_sim timestamptz, planned_duration_s integer,
  duration_basis jsonb NOT NULL DEFAULT '{}'::jsonb, actual_start_sim timestamptz, actual_end_sim timestamptz,
  status text NOT NULL DEFAULT 'planned' CHECK (status = ANY (ARRAY['planned', 'active', 'done', 'skipped', 'amended'])),
  deviation_s integer, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (itinerary_id, seq));

CREATE TABLE IF NOT EXISTS public.ottoq_operation_catalog (pack_id text, operation_code text, display_name text,
  category text, leg_type text, booking_purpose text, svc_code text, parallel_with_charge boolean, is_movement boolean,
  energy_bearing boolean, emits_sdr boolean, created_at timestamptz DEFAULT now(), PRIMARY KEY (pack_id, operation_code));
INSERT INTO public.ottoq_operation_catalog (pack_id, operation_code, leg_type, svc_code, emits_sdr)
VALUES ('robotaxi', 'wash', 'wash', 'exterior_wash', true), ('robotaxi', 'detail', 'detail', NULL, true),
       ('robotaxi', 'generic_service', 'service', NULL, true), ('robotaxi', 'stage', 'stage', NULL, false)
ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS public.ottoq_service_tariffs (tariff_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pack_id text, operation_code text, asset_class_code text, fleet_operator_id uuid, window_label text, price_usd numeric,
  price_unit text, currency text, effective_from timestamptz, effective_until timestamptz, active boolean,
  created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid,
  sim_run_id uuid, started_at timestamptz, ended_at timestamptz, energy_delivered_kwh numeric, peak_power_kw numeric);
CREATE TABLE IF NOT EXISTS public.ottoq_service_detail_records (
  sdr_id uuid PRIMARY KEY, sdr_seq bigserial, sim_run_id uuid, data_source text, pack_id text, operation_code text,
  vehicle_id uuid, asset_class_code text, fleet_operator_id uuid, depot_id uuid, stall_id uuid,
  source_kind text CHECK (source_kind = ANY (ARRAY['itinerary_leg', 'schedule_task', 'manual', 'backfill_leg', 'backfill_task'])),
  leg_id uuid UNIQUE, schedule_task_id uuid UNIQUE, visit_id uuid, booking_id uuid, ocpp_session_id uuid,
  started_at timestamptz, ended_at timestamptz, duration_min numeric, energy_kwh numeric, peak_kw numeric, tariff_id uuid,
  attribution_id uuid, cost_components jsonb, total_cost_usd numeric, billable_amount_usd numeric, currency text,
  sdr_event_id uuid, payload_hash text, signature text, signature_key_id text, signature_algorithm text,
  status text DEFAULT 'issued', schema_version text, issued_at timestamptz DEFAULT now(),
  CHECK ((leg_id IS NOT NULL) OR (schedule_task_id IS NOT NULL) OR (source_kind = 'manual')),
  FOREIGN KEY (pack_id, operation_code) REFERENCES public.ottoq_operation_catalog (pack_id, operation_code));
CREATE TABLE IF NOT EXISTS public.ottoq_events (event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_seq bigserial,
  occurred_at timestamptz DEFAULT now(), event_type text, entity_type text, entity_id uuid, depot_id uuid,
  payload jsonb, data_source text, sim_run_id uuid, sim_clock_at timestamptz);

-- stand-in: the live hash is ottoq's canonical event hash; any deterministic digest of the payload serves here
CREATE OR REPLACE FUNCTION public.ottoq_compute_event_hash(p jsonb) RETURNS text LANGUAGE sql IMMUTABLE
AS $$ SELECT md5(p::text) $$;
-- stand-in: the live signature is an HMAC over these fields with the key named; a digest of them serves here
CREATE OR REPLACE FUNCTION public.ottoq_sign_sdr(p_sdr_id uuid, p_ended_at timestamp with time zone, p_vehicle_id uuid,
                                                 p_operation_code text, p_payload_hash text, p_key_id text)
RETURNS text LANGUAGE sql IMMUTABLE
AS $$ SELECT md5(p_sdr_id::text || p_ended_at::text || p_vehicle_id::text || p_operation_code || p_payload_hash || p_key_id) $$;
-- stand-in: the live writer signs and chains the event; here it records it and returns its id
CREATE OR REPLACE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text,
  p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text,
  p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid,
  p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text,
  p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid,
  p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid,
  p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer,
  p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text,
  p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
RETURNS uuid LANGUAGE sql
AS $$ INSERT INTO public.ottoq_events (event_type, entity_type, entity_id, depot_id, payload, data_source, sim_run_id)
      VALUES (p_event_type, p_entity_type, p_entity_id, p_depot_id, p_payload, p_data_source, p_sim_run_id)
      RETURNING event_id $$;

-- live: public.ottoq_itin_leg_close (prosrc md5 6c33d450e023f83882cbb95f0f4b150f)
CREATE OR REPLACE FUNCTION public.ottoq_itin_leg_close(p_sim_run_id uuid, p_vehicle_id uuid, p_leg_types text[], p_now timestamp with time zone, p_status text DEFAULT 'done'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
  UPDATE ottoq_itinerary_legs
     SET actual_end_sim = p_now, status = p_status,
         deviation_s = CASE WHEN planned_end_sim IS NULL THEN NULL
                            ELSE EXTRACT(EPOCH FROM (p_now - planned_end_sim))::int END
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle_id
     AND status = 'active' AND leg_type = ANY(p_leg_types);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- live: public.ottoq_itin_leg_open (prosrc md5 69effd4b79c76a99b2cb019410172164)
CREATE OR REPLACE FUNCTION public.ottoq_itin_leg_open(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_now timestamp with time zone, p_leg_type text, p_to_stall uuid, p_planned_end timestamp with time zone, p_basis jsonb, p_created_by text DEFAULT 'decide_tick'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_itin uuid; v_seq int; v_leg uuid;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN NULL; END IF;
  SELECT itinerary_id INTO v_itin FROM ottoq_vehicle_itineraries
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle_id AND status = 'active'
   ORDER BY sim_created_at DESC, created_at DESC, itinerary_id DESC /* 0129 */ LIMIT 1;
  IF v_itin IS NULL THEN
    INSERT INTO ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at)
    VALUES (p_sim_run_id, p_depot_id, p_vehicle_id, p_created_by, p_now)
    RETURNING itinerary_id INTO v_itin;
  END IF;
  -- N2/M4: reality CLAIMS the matching planned leg (plan-vs-actual per leg);
  -- unplanned events still insert fresh legs below.
  SELECT leg_id INTO v_leg FROM ottoq_itinerary_legs
   WHERE itinerary_id = v_itin AND leg_type = p_leg_type AND status = 'planned'
   ORDER BY seq, planned_start_sim, planned_end_sim, leg_id /* 0129 */ LIMIT 1;
  IF v_leg IS NOT NULL THEN
    UPDATE ottoq_itinerary_legs
       SET actual_start_sim = p_now, status = 'active', to_stall_id = COALESCE(p_to_stall, to_stall_id),
           duration_basis = duration_basis || COALESCE(p_basis, '{}'::jsonb)
     WHERE leg_id = v_leg;
  ELSE
    SELECT COALESCE(MAX(seq), 0) + 1 INTO v_seq FROM ottoq_itinerary_legs WHERE itinerary_id = v_itin;
    INSERT INTO ottoq_itinerary_legs (
      itinerary_id, sim_run_id, vehicle_id, seq, leg_type, to_stall_id,
      planned_start_sim, planned_end_sim, planned_duration_s, duration_basis,
      actual_start_sim, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle_id, v_seq, p_leg_type, p_to_stall,
      p_now, p_planned_end,
      CASE WHEN p_planned_end IS NULL THEN NULL
           ELSE GREATEST(0, EXTRACT(EPOCH FROM (p_planned_end - p_now)))::int END,
      COALESCE(p_basis, '{}'::jsonb), p_now, 'active')
    RETURNING leg_id INTO v_leg;
  END IF;

  -- LATE BIND (2026-08-02). The calendar row already standing in this stall learns its leg
  -- the moment the leg becomes real. We bind at most ONE live row -- the one whose window
  -- sits closest to now -- and only if no other live row already carries this leg.
  -- 'none' is the resolver's "I looked and found nothing", i.e. UNSET for provenance
  -- purposes -- it must be overwritten here, not preserved.
  -- Fully sub-blocked: this function runs with the CALLER's privileges, so a permission or
  -- constraint problem here must never abort the twin's transaction.
  BEGIN
    IF v_leg IS NOT NULL AND p_to_stall IS NOT NULL THEN
      UPDATE public.ottoq_stall_bookings b
         SET leg_id     = v_leg,
             leg_source = CASE WHEN COALESCE(b.leg_source,'none') = 'none'
                               THEN 'late_bind_leg_open' ELSE b.leg_source END,
             why        = COALESCE(b.why, '') ||
                          format(' | leg %s (%s) opened here at %s',
                                 left(v_leg::text,8), p_leg_type, to_char(p_now,'HH24:MI'))
       WHERE b.booking_id = (
               SELECT bb.booking_id FROM public.ottoq_stall_bookings bb
                WHERE bb.sim_run_id = p_sim_run_id
                  AND bb.stall_id   = p_to_stall
                  AND bb.vehicle_id = p_vehicle_id
                  AND bb.leg_id IS NULL
                  AND bb.state IN ('held','active')
                  AND bb.during && tstzrange(p_now - interval '90 minutes',
                                             p_now + interval '90 minutes', '[)')
                ORDER BY abs(EXTRACT(EPOCH FROM (lower(bb.during) - p_now))), lower(bb.during), bb.stall_id, bb.booking_id DESC /* 0129 */ LIMIT 1)
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bz
                          WHERE bz.leg_id = v_leg AND bz.state IN ('held','active'));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_leg;
END; $function$;

-- live: public.ottoq_emit_sdr (prosrc md5 25e9cbb1a3040668fa47125dd43d02c3)
CREATE OR REPLACE FUNCTION public.ottoq_emit_sdr(p_source_kind text, p_operation_code text, p_pack_id text, p_vehicle_id uuid, p_sim_run_id uuid, p_leg_id uuid, p_schedule_task_id uuid, p_visit_id uuid, p_booking_id uuid, p_stall_id uuid, p_depot_id uuid, p_started_at timestamp with time zone, p_ended_at timestamp with time zone, p_energy_kwh numeric DEFAULT NULL::numeric, p_peak_kw numeric DEFAULT NULL::numeric, p_key_id text DEFAULT 'system:v1'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_sdr_id uuid := gen_random_uuid();
  v_class text; v_operator uuid; v_tariff uuid;
  v_payload jsonb; v_hash text; v_sig text; v_event uuid;
  v_data_source text := COALESCE((SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END FROM public.depots d WHERE d.id = COALESCE(p_depot_id, (SELECT COALESCE(v.current_depot_id, v.home_depot_id) FROM public.vehicles v WHERE v.id = p_vehicle_id))), 'twin');
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);

  IF p_leg_id IS NOT NULL AND EXISTS
     (SELECT 1 FROM ottoq_service_detail_records WHERE leg_id = p_leg_id) THEN
    RETURN NULL;
  END IF;
  IF p_schedule_task_id IS NOT NULL AND EXISTS
     (SELECT 1 FROM ottoq_service_detail_records WHERE schedule_task_id = p_schedule_task_id) THEN
    RETURN NULL;
  END IF;

  SELECT v.vehicle_class_code, v.fleet_operator_id INTO v_class, v_operator
    FROM vehicles v WHERE v.id = p_vehicle_id;

  SELECT t.tariff_id INTO v_tariff
    FROM ottoq_service_tariffs t
   WHERE t.pack_id = p_pack_id AND t.operation_code = p_operation_code
     AND t.active
     AND (t.fleet_operator_id IS NULL OR t.fleet_operator_id = v_operator)
     AND (t.asset_class_code  IS NULL OR t.asset_class_code  = v_class)
     AND (t.effective_until IS NULL OR t.effective_until > p_ended_at)
   ORDER BY (t.fleet_operator_id IS NOT NULL) DESC,
            (t.asset_class_code  IS NOT NULL) DESC,
            t.effective_from DESC
   LIMIT 1;

  v_payload := jsonb_build_object(
    'operation_code', p_operation_code, 'pack_id', p_pack_id,
    'vehicle_id', p_vehicle_id, 'asset_class_code', v_class,
    'fleet_operator_id', v_operator, 'stall_id', p_stall_id,
    'started_at', p_started_at, 'ended_at', p_ended_at,
    'energy_kwh', p_energy_kwh, 'source_kind', p_source_kind,
    'leg_id', p_leg_id, 'schedule_task_id', p_schedule_task_id);
  v_hash := ottoq_compute_event_hash(v_payload);
  v_sig  := ottoq_sign_sdr(v_sdr_id, p_ended_at, p_vehicle_id,
                           p_operation_code, v_hash, p_key_id);

  v_event := ottoq_record_event(
    p_actor_type => 'system', p_event_type => 'sdr_issued',
    p_entity_type => 'service_detail_record', p_entity_id => v_sdr_id,
    p_payload => v_payload, p_actor_id => 'ottoq_emit_sdr',
    p_actor_metadata => '{}'::jsonb,
    p_fleet_operator_id => v_operator, p_depot_id => p_depot_id,
    p_previous_state => NULL, p_new_state => NULL, p_severity => NULL,
    p_correlation_id => NULL, p_parent_event_id => NULL,
    p_related_task_id => p_schedule_task_id, p_related_schedule_id => NULL,
    p_related_decision_id => NULL, p_outcome => 'succeeded', p_latency_ms => NULL,
    p_ingest_source => 'kernel', p_signing_key_id => p_key_id,
    p_data_source => v_data_source, p_sim_run_id => p_sim_run_id);

  INSERT INTO ottoq_service_detail_records
    (sdr_id, sim_run_id, data_source, pack_id, operation_code, vehicle_id,
     asset_class_code, fleet_operator_id, depot_id, stall_id, source_kind,
     leg_id, schedule_task_id, visit_id, booking_id,
     started_at, ended_at, duration_min, energy_kwh, peak_kw,
     tariff_id, sdr_event_id, payload_hash, signature, signature_key_id)
  VALUES
    (v_sdr_id, p_sim_run_id, v_data_source, p_pack_id, p_operation_code, p_vehicle_id,
     v_class, v_operator, p_depot_id, p_stall_id, p_source_kind,
     p_leg_id, p_schedule_task_id, p_visit_id, p_booking_id,
     p_started_at, p_ended_at,
     CASE WHEN p_started_at IS NOT NULL
          THEN round(EXTRACT(EPOCH FROM (p_ended_at - p_started_at))/60.0, 2) END,
     p_energy_kwh, p_peak_kw,
     v_tariff, v_event, v_hash, v_sig, p_key_id)
  ON CONFLICT DO NOTHING;

  RETURN v_sdr_id;
END;
$function$;

-- live: public.ottoq_trg_leg_done_sdr (prosrc md5 8aa4c329836bdb7e0588defe75404498)
CREATE OR REPLACE FUNCTION public.ottoq_trg_leg_done_sdr()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_op record; v_booking uuid; v_visit uuid; v_depot uuid;
  v_kwh numeric; v_peak numeric; v_sessions int; v_session uuid; v_sdr uuid;   -- 0508
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);
  SELECT oc.pack_id, oc.operation_code INTO v_op
    FROM ottoq_operation_catalog oc
   WHERE oc.leg_type = NEW.leg_type AND oc.emits_sdr
   ORDER BY oc.pack_id, oc.operation_code   -- 0216: unambiguous today (no leg_type
   LIMIT 1;                                 -- has two emits_sdr rows), ordered anyway
  IF v_op IS NULL THEN RETURN NEW; END IF;

  --: 0216. THE SETTLEMENT RECORD NAMES THE BOOKING THAT HAPPENED.
  --: A leg can carry several bookings — the superseded plans churn left behind.
  --: Measured: 188 of 202 done-legs have exactly ONE booking in a settled
  --: state, 0 have more than one, 14 have none at all. So "not superseded"
  --: decides it whenever it can, and content decides the rest. Every key is
  --: arm-stable; no uuid ordering, no clock. Without this the answer came from
  --: the heap and differed on 23 of 284 SDRs across a passing pair's two arms.
  SELECT b.booking_id, b.visit_id INTO v_booking, v_visit
    FROM ottoq_stall_bookings b
   WHERE b.leg_id = NEW.leg_id
   ORDER BY (b.state IN ('superseded','released','cancelled')),
            lower(b.during), upper(b.during), b.stall_id, b.booked_at_sim, b.state
   LIMIT 1;

  SELECT i.depot_id INTO v_depot
    FROM ottoq_vehicle_itineraries i WHERE i.itinerary_id = NEW.itinerary_id;

  --: 0508 (G239). A charge's record carries what its session delivered: the energy and the peak of this car's
  --: sessions that overlap the leg (normally one, the session whose stop closed it), summed and maxed so that no
  --: order is needed, and that session's id when exactly one overlaps. The energy and peak are signed with the
  --: record; the id is set after, outside the signature and outside ottoq_hash_sdrs.
  IF NEW.leg_type IN ('charge_dcfc','charge_l2') AND NEW.actual_start_sim IS NOT NULL THEN
    SELECT sum(os.energy_delivered_kwh), max(os.peak_power_kw), count(*),
           CASE WHEN count(*) = 1 THEN (array_agg(os.id))[1] END
      INTO v_kwh, v_peak, v_sessions, v_session
      FROM ocpp_sessions os
     WHERE os.vehicle_id = NEW.vehicle_id
       AND os.sim_run_id IS NOT DISTINCT FROM NEW.sim_run_id
       AND os.started_at < COALESCE(NEW.actual_end_sim, now())
       AND COALESCE(os.ended_at, 'infinity'::timestamptz) > NEW.actual_start_sim;
  END IF;

  v_sdr := ottoq_emit_sdr(
    'itinerary_leg', v_op.operation_code, v_op.pack_id,
    NEW.vehicle_id, NEW.sim_run_id,
    NEW.leg_id, NULL, v_visit, v_booking,
    NEW.to_stall_id, v_depot,
    NEW.actual_start_sim, COALESCE(NEW.actual_end_sim, now()),
    v_kwh, v_peak);
  IF v_sdr IS NOT NULL AND v_session IS NOT NULL THEN
    UPDATE ottoq_service_detail_records SET ocpp_session_id = v_session WHERE sdr_id = v_sdr;
  END IF;
  RETURN NEW;
END;
$function$;

-- live: trg_0043_leg_done_sdr
CREATE TRIGGER trg_0043_leg_done_sdr AFTER UPDATE OF status ON public.ottoq_itinerary_legs FOR EACH ROW
  WHEN (((new.status = 'done'::text) AND (old.status IS DISTINCT FROM 'done'::text))) EXECUTE FUNCTION ottoq_trg_leg_done_sdr();
