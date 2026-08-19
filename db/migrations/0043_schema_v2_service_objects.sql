-- migration-version: 20260819031500
-- migration-name:    schema_v2_service_objects
-- 0043 — SCHEMA V2: kernel naming layer + the six service objects + the SDR rule
--
-- Run 2 / Phase C3 (CLAUDE.md). Verified on a scratch instance 2026-08-19 (see
-- db/checks/0043_schema_v2_certification.sql and SCHEMA_V2.md §6). NOT YET APPLIED
-- TO PRODUCTION — apply per scripts/APPLYING.md after founder merge.
--
-- Design laws honored here:
--   * Migration path over what exists — every change below is classified in
--     SCHEMA_V2.md as rename(view-wrap) / extend / new-object. NOTHING is dropped,
--     no existing column is altered, no existing row is modified except the
--     labeled class backfill on vehicles (§2, nullable column, heuristic, reversible).
--   * ottoq_stall_bookings and its EXCLUDE constraint are UNTOUCHED.
--   * Every completed operation terminates in a ServiceDetailRecord — structural,
--     catalog-driven, enforced by triggers (§7) + backfill (§8) + coverage check (§9).
--   * New run-scoped column registered in ottoq_run_scope_registry (§10) with an FK
--     to ottoq_sim_runs, or ottoq_purge_prior_runs would rightly refuse to run.
--   * data_source sim/real co-existence preserved: SDRs carry data_source and
--     nullable sim_run_id exactly like ottoq_events.

-- ============================================================================
-- §1  ASSET CLASS (extend) — ottoq_vehicle_classes is the AssetClass foothold
--     Adds the pack binding and the energy-curve / duty-cycle refs (2.3).
-- ============================================================================
ALTER TABLE public.ottoq_vehicle_classes
  ADD COLUMN IF NOT EXISTS pack_id            text  NOT NULL DEFAULT 'robotaxi',
  ADD COLUMN IF NOT EXISTS energy_curve       jsonb,
  ADD COLUMN IF NOT EXISTS duty_cycle_profile jsonb;

COMMENT ON COLUMN public.ottoq_vehicle_classes.pack_id IS
  'Sector pack this asset class belongs to. Kernel code never branches on its value.';
COMMENT ON COLUMN public.ottoq_vehicle_classes.energy_curve IS
  'Piecewise charge-acceptance curve, [{above_soc_pct, accept_frac}] — the 2.5 '
  '"piecewise demand above ~70% SoC" requirement, expressed as class data.';
COMMENT ON COLUMN public.ottoq_vehicle_classes.duty_cycle_profile IS
  'Reference duty-cycle shape for the class (work-side demand prior), as data.';

-- v0 curve for existing classes that have none: full accept to 70%, taper after.
UPDATE public.ottoq_vehicle_classes
   SET energy_curve = '[{"above_soc_pct":0,"accept_frac":1.0},
                        {"above_soc_pct":70,"accept_frac":0.6},
                        {"above_soc_pct":85,"accept_frac":0.35}]'::jsonb
 WHERE energy_curve IS NULL;

-- ============================================================================
-- §2  ASSET (extend) — bind vehicles to their class. The binding did not exist.
--     Nullable, FK'd, heuristic backfill labeled in the column comment.
-- ============================================================================
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS vehicle_class_code text
    REFERENCES public.ottoq_vehicle_classes(vehicle_class_code);

COMMENT ON COLUMN public.vehicles.vehicle_class_code IS
  'AssetClass binding (C3, 0043). Backfilled heuristically from av_platform; '
  'NULL means unclassified — treat as generic_robotaxi at read time, never write '
  'the guess back.';

UPDATE public.vehicles v
   SET vehicle_class_code = m.code
  FROM (VALUES
        ('waymo', 'waymo_jaguar_ipace_2024'),
        ('zoox',  'zoox_robotaxi_2024'),
        ('tesla', 'tesla_model_y_robotaxi_2024')
       ) AS m(platform, code)
  JOIN public.ottoq_vehicle_classes c ON c.vehicle_class_code = m.code
 WHERE v.vehicle_class_code IS NULL
   AND v.platform::text = m.platform;

UPDATE public.vehicles v
   SET vehicle_class_code = 'generic_robotaxi'
 WHERE v.vehicle_class_code IS NULL
   AND v.category = 'autonomous'
   AND EXISTS (SELECT 1 FROM public.ottoq_vehicle_classes
                WHERE vehicle_class_code = 'generic_robotaxi');

-- ============================================================================
-- §3  OPERATION CATALOG (new; PACK DATA) — the robotaxi operation catalog (2.4)
--     as rows, not schema. The SDR trigger consults emits_sdr, so what counts
--     as a settleable operation is pack data, not kernel code.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.ottoq_operation_catalog (
  pack_id              text NOT NULL DEFAULT 'robotaxi',
  operation_code       text NOT NULL,
  display_name         text,
  category             text NOT NULL CHECK (category IN
                         ('energy','clean','data','maintenance','inspection','movement','staging')),
  leg_type             text,          -- crosswalk: ottoq_itinerary_legs.leg_type
  booking_purpose      text,          -- crosswalk: ottoq_stall_bookings.purpose
  svc_code             text,          -- crosswalk: service_cadence_policy.svc / schedule_tasks.service_code
  parallel_with_charge boolean NOT NULL DEFAULT false,   -- 2.3: concurrency within a point
  is_movement          boolean NOT NULL DEFAULT false,   -- 2.3: moves are scheduled ops
  energy_bearing       boolean NOT NULL DEFAULT false,
  emits_sdr            boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (pack_id, operation_code)
);
COMMENT ON TABLE public.ottoq_operation_catalog IS
  'Per-pack operation catalog (CLAUDE.md 2.4). Kernel behavior (SDR emission, '
  'concurrency, movement handling) keys off these rows. A new sector = new rows.';

INSERT INTO public.ottoq_operation_catalog
  (pack_id, operation_code, display_name, category, leg_type, booking_purpose, svc_code,
   parallel_with_charge, is_movement, energy_bearing, emits_sdr) VALUES
 ('robotaxi','charge_dcfc',       'DC fast charge',       'energy',     'charge_dcfc','charge_dcfc','charge',              false, false, true,  true),
 ('robotaxi','charge_l2',         'L2 charge',            'energy',     'charge_l2',  'charge_l2',  'charge',              false, false, true,  true),
 ('robotaxi','wash',              'Exterior wash',        'clean',      'wash',       'wash',       'exterior_wash',       false, false, false, true),
 ('robotaxi','detail',            'Detail',               'clean',      'detail',     'detail',     NULL,                  false, false, false, true),
 ('robotaxi','interior_tidy',     'Interior reset',       'clean',      'interior_tidy',NULL,       'interior_tidy',       true,  false, false, true),
 ('robotaxi','interior_deep_clean','Interior deep clean', 'clean',      'interior_deep_clean',NULL, 'interior_deep_clean', false, false, false, true),
 ('robotaxi','sensor_clean',      'Sensor clean',         'clean',      'sensor_clean',NULL,        'sensor_clean',        true,  false, false, true),
 ('robotaxi','item_retrieval',    'Item retrieval',       'clean',      'item_retrieval',NULL,      'item_retrieval',      true,  false, false, true),
 ('robotaxi','software_update',   'Software update',      'data',       'software_update',NULL,     'software_update',     true,  false, false, true),
 ('robotaxi','remote_diagnostics','Remote diagnostics',   'data',       'remote_diagnostics',NULL,  'remote_diagnostics',  true,  false, false, true),
 ('robotaxi','inspect',           'Inspection',           'inspection', 'inspect',    'inspect',    'interior_inspection', false, false, false, true),
 ('robotaxi','triage_check',      'Triage check',         'inspection', 'triage_check',NULL,        'triage_check',        true,  false, false, true),
 ('robotaxi','readiness_check',   'Readiness check',      'inspection', NULL,         NULL,         'readiness_check',     true,  false, false, true),
 ('robotaxi','sensor_calibration','ADAS/sensor calibration','maintenance','sensor_calibration',NULL,'sensor_calibration',  false, false, false, true),
 ('robotaxi','mechanical_pm',     'Mechanical PM',        'maintenance','mechanical_pm',NULL,       'mechanical_pm',       false, false, false, true),
 ('robotaxi','fault_repair',      'Fault repair',         'maintenance','fault_repair',NULL,        'fault_repair',        false, false, false, true),
 ('robotaxi','cosmetic_repair',   'Cosmetic repair',      'maintenance','cosmetic_repair',NULL,     'cosmetic_repair',     false, false, false, true),
 ('robotaxi','generic_service',   'Generic service',      'maintenance','service',    'service',    NULL,                  false, false, false, true),
 -- movement / staging: scheduled operations (they consume time and path resources)
 -- but not settleable service events today. Flipping emits_sdr is a data change.
 ('robotaxi','arrive',            'Arrive',               'movement',   'arrive',     NULL,         NULL,                  false, true,  false, false),
 ('robotaxi','taxi',              'Inter-point move',     'movement',   'taxi',       NULL,         NULL,                  false, true,  false, false),
 ('robotaxi','settle',            'Settle',               'movement',   'settle',     NULL,         NULL,                  false, true,  false, false),
 ('robotaxi','depart',            'Depart',               'movement',   'depart',     NULL,         NULL,                  false, true,  false, false),
 ('robotaxi','stage',             'Park / stage',         'staging',    'stage',      'staging',    NULL,                  false, false, false, false)
ON CONFLICT (pack_id, operation_code) DO NOTHING;

-- ============================================================================
-- §4  SERVICE POINT CAPABILITIES (new) — stalls stay; capabilities become
--     (asset_class, operation) pairs per point (2.3). Seeded from what the
--     physical stall data already says.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.ottoq_service_point_capabilities (
  stall_id         uuid NOT NULL REFERENCES public.stalls(id) ON DELETE CASCADE,
  asset_class_code text NOT NULL REFERENCES public.ottoq_vehicle_classes(vehicle_class_code),
  pack_id          text NOT NULL DEFAULT 'robotaxi',
  operation_code   text NOT NULL,
  active           boolean NOT NULL DEFAULT true,
  source           text NOT NULL DEFAULT 'seed_0043',
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (stall_id, asset_class_code, operation_code),
  FOREIGN KEY (pack_id, operation_code)
    REFERENCES public.ottoq_operation_catalog(pack_id, operation_code)
);
COMMENT ON TABLE public.ottoq_service_point_capabilities IS
  'ServicePoint capability pairs (CLAUDE.md 2.3): which operations this point can '
  'host for which asset class. Seeded 0043 from stall_type + inlet compatibility; '
  'the scheduler may narrow, never widen, without a data change here.';

-- Seed: stall_type -> operations; charge stalls honor inlet compatibility when
-- both sides declare it, all other operations are class-agnostic today.
WITH op_map(stall_type, operation_code) AS (
  VALUES ('dcfc','charge_dcfc'), ('dcfc','sensor_clean'), ('dcfc','interior_tidy'),
         ('dcfc','software_update'), ('dcfc','remote_diagnostics'),
         ('l2','charge_l2'), ('l2','sensor_clean'), ('l2','interior_tidy'),
         ('l2','software_update'), ('l2','remote_diagnostics'),
         ('wash_bay','wash'), ('wash_bay','detail'),
         ('detail_bay','detail'), ('detail_bay','interior_deep_clean'),
         ('service_bay','generic_service'), ('service_bay','inspect'),
         ('service_bay','mechanical_pm'), ('service_bay','fault_repair'),
         ('service_bay','cosmetic_repair'), ('service_bay','sensor_calibration'),
         ('service_bay','triage_check'), ('service_bay','item_retrieval'),
         ('service_bay','interior_deep_clean'),
         ('staging','stage'), ('staging','interior_tidy'), ('staging','sensor_clean'),
         ('staging','software_update'), ('staging','remote_diagnostics'),
         ('staging','readiness_check'),
         ('parking','stage')
)
INSERT INTO public.ottoq_service_point_capabilities
  (stall_id, asset_class_code, pack_id, operation_code)
SELECT s.id, c.vehicle_class_code, 'robotaxi', m.operation_code
  FROM public.stalls s
  JOIN op_map m ON m.stall_type = s.stall_type::text
  CROSS JOIN public.ottoq_vehicle_classes c
 WHERE c.status = 'active'
   AND (m.operation_code NOT IN ('charge_dcfc','charge_l2')
        OR s.supported_inlet_types IS NULL
        OR cardinality(s.supported_inlet_types) = 0
        OR c.inlet_type IS NULL
        OR c.inlet_type = ANY (s.supported_inlet_types))
ON CONFLICT DO NOTHING;

-- ============================================================================
-- §5  SERVICE TOKENS + SERVICE TARIFFS (new tables; the L2 objects)
-- ============================================================================
-- ServiceToken <- OCPI Token analogue: operator + asset + entitlements.
CREATE TABLE IF NOT EXISTS public.ottoq_service_tokens (
  token_id          uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  fleet_operator_id uuid REFERENCES public.fleet_operators(id) ON DELETE SET NULL,
  vehicle_id        uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
  asset_class_code  text REFERENCES public.ottoq_vehicle_classes(vehicle_class_code),
  entitlements      jsonb NOT NULL DEFAULT '{"operations": "*"}'::jsonb,
  status            text NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active','suspended','revoked')),
  valid_from        timestamptz NOT NULL DEFAULT now(),
  valid_until       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.ottoq_service_tokens IS
  'ServiceToken (OCPI Token analogue): operator + asset scope + entitlements. '
  'v0 seeds one all-operations token per operator with an active SLA.';

INSERT INTO public.ottoq_service_tokens (fleet_operator_id, entitlements)
SELECT DISTINCT s.fleet_operator_id, '{"operations": "*"}'::jsonb
  FROM public.ottoq_fleet_operator_slas s
 WHERE s.status = 'active'
   AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_tokens t
                    WHERE t.fleet_operator_id = s.fleet_operator_id);

-- ServiceTariff <- OCPI Tariff analogue, keyed (asset_class, operation, operator,
-- window) per 2.6. Energy tariffs (tariff_schedules / ottoq_depot_tariffs) remain
-- the utility-cost layer; THIS prices the service event itself.
CREATE TABLE IF NOT EXISTS public.ottoq_service_tariffs (
  tariff_id         uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  pack_id           text NOT NULL DEFAULT 'robotaxi',
  operation_code    text NOT NULL,
  asset_class_code  text REFERENCES public.ottoq_vehicle_classes(vehicle_class_code),
  fleet_operator_id uuid REFERENCES public.fleet_operators(id) ON DELETE CASCADE,
  window_label      text NOT NULL DEFAULT 'any',   -- 'any' | tariff_label values
  price_usd         numeric,                        -- NULL = unpriced placeholder
  price_unit        text NOT NULL DEFAULT 'per_event'
                      CHECK (price_unit IN ('per_event','per_minute','per_kwh')),
  currency          text NOT NULL DEFAULT 'USD',
  effective_from    timestamptz NOT NULL DEFAULT now(),
  effective_until   timestamptz,
  active            boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (pack_id, operation_code)
    REFERENCES public.ottoq_operation_catalog(pack_id, operation_code),
  UNIQUE (pack_id, operation_code, asset_class_code, fleet_operator_id, window_label, effective_from)
);
COMMENT ON TABLE public.ottoq_service_tariffs IS
  'ServiceTariff (OCPI Tariff analogue) per (asset_class, operation, operator, '
  'window). NULL asset_class/operator = house default. price_usd NULL = placeholder '
  'until commercial rates land; the SDR link is structural either way.';

-- House default (operator NULL, class NULL) per settleable operation.
INSERT INTO public.ottoq_service_tariffs (pack_id, operation_code, price_unit)
SELECT oc.pack_id, oc.operation_code,
       CASE WHEN oc.energy_bearing THEN 'per_kwh' ELSE 'per_event' END
  FROM public.ottoq_operation_catalog oc
 WHERE oc.emits_sdr
   AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_tariffs t
                    WHERE t.pack_id = oc.pack_id AND t.operation_code = oc.operation_code
                      AND t.asset_class_code IS NULL AND t.fleet_operator_id IS NULL);

-- ============================================================================
-- §6  THE SERVICE DETAIL RECORD (new table; the strategic object)
--     SDR <- OCPI CDR analogue for ANY completed service event — signed,
--     tariffed, operator-attributed, asset-class-tagged. Evolves from
--     ottoq_visit_cost_attribution + the signed event stream (links to both);
--     it does not replace either.
-- ============================================================================
CREATE SEQUENCE IF NOT EXISTS public.ottoq_sdr_seq;

CREATE TABLE IF NOT EXISTS public.ottoq_service_detail_records (
  sdr_id            uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  sdr_seq           bigint NOT NULL DEFAULT nextval('public.ottoq_sdr_seq'),
  -- run scoping + provenance (mirrors ottoq_events: engine-class, nullable for production)
  sim_run_id        uuid REFERENCES public.ottoq_sim_runs(sim_run_id),
  data_source       text NOT NULL DEFAULT 'production',
  -- what happened, to whom, where
  pack_id           text NOT NULL DEFAULT 'robotaxi',
  operation_code    text NOT NULL,
  vehicle_id        uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
  asset_class_code  text,            -- captured at issuance; survives asset deletion
  fleet_operator_id uuid,            -- operator attribution (loose ref by design)
  depot_id          uuid,
  stall_id          uuid,
  -- session anchors (ServiceSession view unifies these)
  source_kind       text NOT NULL CHECK (source_kind IN
                      ('itinerary_leg','schedule_task','manual','backfill_leg','backfill_task')),
  leg_id            uuid UNIQUE,     -- twin/tick path anchor
  schedule_task_id  uuid UNIQUE,     -- production path anchor
  visit_id          uuid,
  booking_id        uuid,
  ocpp_session_id   uuid,
  -- when and how much
  started_at        timestamptz,
  ended_at          timestamptz NOT NULL,
  duration_min      numeric,
  energy_kwh        numeric,
  peak_kw           numeric,
  -- money (phase 2 of issuance: attribution attach, see trigger §7.3)
  tariff_id         uuid REFERENCES public.ottoq_service_tariffs(tariff_id),
  attribution_id    uuid,            -- ottoq_visit_cost_attribution.attribution_id
  cost_components   jsonb NOT NULL DEFAULT '{}'::jsonb,
  total_cost_usd    numeric,
  billable_amount_usd numeric,
  currency          text NOT NULL DEFAULT 'USD',
  -- integrity (same machinery as ottoq_events)
  sdr_event_id      uuid,            -- the signed 'sdr_issued' ottoq_events row
  payload_hash      text NOT NULL,
  signature         text,
  signature_key_id  text,
  signature_algorithm text NOT NULL DEFAULT 'HMAC-SHA-256',
  status            text NOT NULL DEFAULT 'issued'
                      CHECK (status IN ('issued','voided','superseded')),
  schema_version    text NOT NULL DEFAULT '2.0.0',
  issued_at         timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (pack_id, operation_code)
    REFERENCES public.ottoq_operation_catalog(pack_id, operation_code),
  CHECK (leg_id IS NOT NULL OR schedule_task_id IS NOT NULL
         OR source_kind = 'manual')
);
COMMENT ON TABLE public.ottoq_service_detail_records IS
  'ServiceDetailRecord (OCPI CDR analogue for any operation, 2.6): one signed, '
  'tariffed, operator-attributed, asset-class-tagged record per completed '
  'operation. Issued at completion with operational facts (signed core); costs '
  'attach afterward from ottoq_visit_cost_attribution via a second signed event. '
  'sim rows purge with their run (engine class); production rows persist.';

CREATE INDEX IF NOT EXISTS idx_sdr_run       ON public.ottoq_service_detail_records (sim_run_id) WHERE sim_run_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sdr_operator  ON public.ottoq_service_detail_records (fleet_operator_id, ended_at);
CREATE INDEX IF NOT EXISTS idx_sdr_operation ON public.ottoq_service_detail_records (pack_id, operation_code, ended_at);

-- Event vocabulary registered properly (C7 discipline).
INSERT INTO public.ottoq_event_types_catalog (event_type, category, description, emitter, default_severity, introduced_in)
VALUES
 ('sdr_issued','business_event','A ServiceDetailRecord was issued for a completed operation.','0043 trigger','info','0043'),
 ('sdr_costs_attached','business_event','Cost attribution attached to an existing SDR.','0043 trigger','info','0043')
ON CONFLICT (event_type) DO NOTHING;

-- ============================================================================
-- §7  SDR MACHINERY — signing, emission, completion triggers, attribution attach
-- ============================================================================
-- 7.0 Signature: same key registry + HMAC as ottoq_sign_event, SDR-shaped canonical.
CREATE OR REPLACE FUNCTION public.ottoq_sign_sdr(
  p_sdr_id uuid, p_ended_at timestamptz, p_vehicle_id uuid,
  p_operation_code text, p_payload_hash text, p_key_id text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_secret text;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);
  v_secret := ottoq_resolve_signing_secret(p_key_id);
  IF v_secret IS NULL THEN RETURN NULL; END IF;
  RETURN encode(hmac(
    concat_ws('|',
      p_sdr_id::text,
      to_char(p_ended_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      COALESCE(p_vehicle_id::text, ''),
      p_operation_code,
      p_payload_hash),
    v_secret, 'sha256'), 'hex');
END;
$fn$;

-- 7.1 Core emitter. Every path (leg trigger, task trigger, backfill) lands here.
CREATE OR REPLACE FUNCTION public.ottoq_emit_sdr(
  p_source_kind text, p_operation_code text, p_pack_id text,
  p_vehicle_id uuid, p_sim_run_id uuid,
  p_leg_id uuid, p_schedule_task_id uuid, p_visit_id uuid, p_booking_id uuid,
  p_stall_id uuid, p_depot_id uuid,
  p_started_at timestamptz, p_ended_at timestamptz,
  p_energy_kwh numeric DEFAULT NULL, p_peak_kw numeric DEFAULT NULL,
  p_key_id text DEFAULT 'system:v1')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_sdr_id uuid := gen_random_uuid();
  v_class text; v_operator uuid; v_tariff uuid;
  v_payload jsonb; v_hash text; v_sig text; v_event uuid;
  v_data_source text := CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);

  -- idempotency: one SDR per anchor, quietly.
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

  -- tariff: most specific active row wins (operator+class > operator > class > house)
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
$fn$;

-- 7.2a Completion trigger, twin/tick path: an operation leg reaching 'done'.
CREATE OR REPLACE FUNCTION public.ottoq_trg_leg_done_sdr()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_op record; v_booking uuid; v_visit uuid; v_depot uuid;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);
  SELECT oc.pack_id, oc.operation_code INTO v_op
    FROM ottoq_operation_catalog oc
   WHERE oc.leg_type = NEW.leg_type AND oc.emits_sdr
   LIMIT 1;
  IF v_op IS NULL THEN RETURN NEW; END IF;   -- movement/staging or uncataloged: no SDR

  SELECT b.booking_id, b.visit_id INTO v_booking, v_visit
    FROM ottoq_stall_bookings b WHERE b.leg_id = NEW.leg_id LIMIT 1;
  SELECT i.depot_id INTO v_depot
    FROM ottoq_vehicle_itineraries i WHERE i.itinerary_id = NEW.itinerary_id;

  PERFORM ottoq_emit_sdr(
    'itinerary_leg', v_op.operation_code, v_op.pack_id,
    NEW.vehicle_id, NEW.sim_run_id,
    NEW.leg_id, NULL, v_visit, v_booking,
    NEW.to_stall_id, v_depot,
    NEW.actual_start_sim, COALESCE(NEW.actual_end_sim, now()));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_0043_leg_done_sdr ON public.ottoq_itinerary_legs;
CREATE TRIGGER trg_0043_leg_done_sdr
  AFTER UPDATE OF status ON public.ottoq_itinerary_legs
  FOR EACH ROW
  WHEN (NEW.status = 'done' AND OLD.status IS DISTINCT FROM 'done')
  EXECUTE FUNCTION public.ottoq_trg_leg_done_sdr();

-- 7.2b Completion trigger, production path: a schedule task reaching 'completed'.
CREATE OR REPLACE FUNCTION public.ottoq_trg_task_completed_sdr()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_op record;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);
  SELECT oc.pack_id, oc.operation_code INTO v_op
    FROM ottoq_operation_catalog oc
   WHERE oc.emits_sdr
     AND (oc.svc_code = NEW.service_code
          OR oc.svc_code = (SELECT sd.code FROM service_definitions sd
                             WHERE sd.id = NEW.service_definition_id))
   LIMIT 1;
  IF v_op IS NULL THEN
    SELECT oc.pack_id, oc.operation_code INTO v_op
      FROM ottoq_operation_catalog oc
     WHERE oc.operation_code = 'generic_service' AND oc.emits_sdr LIMIT 1;
  END IF;
  IF v_op IS NULL THEN RETURN NEW; END IF;

  PERFORM ottoq_emit_sdr(
    'schedule_task', v_op.operation_code, v_op.pack_id,
    NEW.vehicle_id, NULL,
    NULL, NEW.id, NULL, NULL,
    COALESCE(NEW.actual_stall_id, NEW.assigned_stall_id), NEW.depot_id,
    NEW.actual_start, COALESCE(NEW.actual_end, now()),
    NEW.energy_delivered_kwh, NEW.peak_charge_rate_kw);
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_0043_task_completed_sdr ON public.schedule_tasks;
CREATE TRIGGER trg_0043_task_completed_sdr
  AFTER UPDATE OF status ON public.schedule_tasks
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  EXECUTE FUNCTION public.ottoq_trg_task_completed_sdr();

-- 7.3 Cost attach: attribution lands after completion; link it to the SDRs of
--     that schedule and record a second signed event. The issued signature
--     covers the operational core and is not rewritten.
CREATE OR REPLACE FUNCTION public.ottoq_trg_attribution_attach()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_n int;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);
  UPDATE ottoq_service_detail_records r
     SET attribution_id      = NEW.attribution_id,
         cost_components     = COALESCE(NEW.cost_components, '{}'::jsonb),
         total_cost_usd      = NEW.total_cost_usd,
         billable_amount_usd = NEW.billable_amount_usd
   WHERE r.schedule_task_id IN
         (SELECT t.id FROM schedule_tasks t
           WHERE t.vehicle_schedule_id = NEW.schedule_id OR t.schedule_id = NEW.schedule_id)
     AND r.attribution_id IS DISTINCT FROM NEW.attribution_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN
    PERFORM ottoq_record_event(
      p_actor_type => 'system', p_event_type => 'sdr_costs_attached',
      p_entity_type => 'visit_cost_attribution', p_entity_id => NEW.attribution_id,
      p_payload => jsonb_build_object('schedule_id', NEW.schedule_id,
                                      'sdrs_updated', v_n,
                                      'total_cost_usd', NEW.total_cost_usd),
      p_actor_id => 'ottoq_trg_attribution_attach', p_actor_metadata => '{}'::jsonb,
      p_fleet_operator_id => NEW.fleet_operator_id, p_depot_id => NEW.depot_id,
      p_previous_state => NULL, p_new_state => NULL, p_severity => NULL,
      p_correlation_id => NULL, p_parent_event_id => NULL,
      p_related_task_id => NULL, p_related_schedule_id => NEW.schedule_id,
      p_related_decision_id => NULL, p_outcome => 'succeeded', p_latency_ms => NULL,
      p_ingest_source => 'kernel', p_signing_key_id => 'system:v1',
      p_data_source => 'production', p_sim_run_id => NULL);
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_0043_attribution_attach ON public.ottoq_visit_cost_attribution;
CREATE TRIGGER trg_0043_attribution_attach
  AFTER INSERT ON public.ottoq_visit_cost_attribution
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_trg_attribution_attach();

-- ============================================================================
-- §8  BACKFILL — operations completed before 0043 get their SDRs now, labeled.
-- ============================================================================
SELECT public.ottoq_emit_sdr(
         'backfill_leg', oc.operation_code, oc.pack_id,
         l.vehicle_id, l.sim_run_id, l.leg_id, NULL,
         b.visit_id, b.booking_id, l.to_stall_id, i.depot_id,
         l.actual_start_sim, COALESCE(l.actual_end_sim, l.created_at))
  FROM public.ottoq_itinerary_legs l
  JOIN public.ottoq_operation_catalog oc ON oc.leg_type = l.leg_type AND oc.emits_sdr
  JOIN public.ottoq_vehicle_itineraries i ON i.itinerary_id = l.itinerary_id
  LEFT JOIN public.ottoq_stall_bookings b ON b.leg_id = l.leg_id
 WHERE l.status = 'done'
   AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_detail_records r
                    WHERE r.leg_id = l.leg_id);

SELECT public.ottoq_emit_sdr(
         'backfill_task', oc.operation_code, oc.pack_id,
         t.vehicle_id, NULL, NULL, t.id, NULL, NULL,
         COALESCE(t.actual_stall_id, t.assigned_stall_id), t.depot_id,
         t.actual_start, COALESCE(t.actual_end, t.updated_at),
         t.energy_delivered_kwh, t.peak_charge_rate_kw)
  FROM public.schedule_tasks t
  JOIN public.service_definitions sd ON sd.id = t.service_definition_id
  JOIN public.ottoq_operation_catalog oc
    ON oc.emits_sdr AND (oc.svc_code = COALESCE(t.service_code, sd.code))
 WHERE t.status = 'completed'
   AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_detail_records r
                    WHERE r.schedule_task_id = t.id);

-- ============================================================================
-- §9  COVERAGE CHECK — the standing falsifier for "every completed operation
--     terminates in an SDR". Empty result = the claim holds.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_check_sdr_coverage(p_run uuid DEFAULT NULL)
RETURNS TABLE(source text, anchor_id uuid, operation text, completed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER AS $fn$
  SELECT 'itinerary_leg', l.leg_id, l.leg_type, COALESCE(l.actual_end_sim, l.created_at)
    FROM public.ottoq_itinerary_legs l
    JOIN public.ottoq_operation_catalog oc ON oc.leg_type = l.leg_type AND oc.emits_sdr
   WHERE l.status = 'done'
     AND (p_run IS NULL OR l.sim_run_id = p_run)
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_detail_records r
                      WHERE r.leg_id = l.leg_id)
  UNION ALL
  SELECT 'schedule_task', t.id, COALESCE(t.service_code, sd.code), COALESCE(t.actual_end, t.updated_at)
    FROM public.schedule_tasks t
    JOIN public.service_definitions sd ON sd.id = t.service_definition_id
    JOIN public.ottoq_operation_catalog oc
      ON oc.emits_sdr AND oc.svc_code = COALESCE(t.service_code, sd.code)
   WHERE t.status = 'completed'
     AND p_run IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_detail_records r
                      WHERE r.schedule_task_id = t.id);
$fn$;

-- ============================================================================
-- §10  RUN-SCOPE REGISTRY — the new run-scoped column, registered, engine class
--      (mirrors ottoq_events). FK to ottoq_sim_runs exists (§6), so the purge's
--      block-check passes and sim SDRs die with their runs; production rows
--      (sim_run_id NULL) are untouched by purge.
-- ============================================================================
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public','ottoq_service_detail_records','sim_run_id','engine',
        '0043: SDRs of a sim run die with the run; production SDRs (NULL sim_run_id) persist.')
ON CONFLICT (table_schema, table_name, column_name) DO NOTHING;

-- ============================================================================
-- §11  THE REMAINING SERVICE-OBJECT VIEWS (rename-level; no parallel storage)
-- ============================================================================
-- ServiceLocation <- OCPI Location analogue: the service point with its
-- (asset_class, operation) capability pairs. One row per point.
CREATE OR REPLACE VIEW public.service_locations
  WITH (security_invoker = true) AS
SELECT s.id                AS service_point_id,
       s.depot_id          AS site_id,
       d.name              AS site_name,
       s.stall_code        AS point_code,
       s.stall_type::text  AS point_kind,
       s.status            AS point_status,
       s.covered, s.zone,
       COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
                  'asset_class', c.asset_class_code,
                  'operation',   c.operation_code))
                FILTER (WHERE c.stall_id IS NOT NULL), '[]'::jsonb)
                           AS capabilities
  FROM public.stalls s
  JOIN public.depots d ON d.id = s.depot_id
  LEFT JOIN public.ottoq_service_point_capabilities c
         ON c.stall_id = s.id AND c.active
 GROUP BY s.id, s.depot_id, d.name, s.stall_code, s.stall_type, s.status, s.covered, s.zone;

-- ServiceSession <- OCPI Session analogue: an open/closed session for ANY
-- operation, energy or not. Unifies the booking calendar (twin/tick path) and
-- schedule tasks (production path). No new storage.
CREATE OR REPLACE VIEW public.service_sessions
  WITH (security_invoker = true) AS
SELECT b.booking_id        AS session_id,
       'booking'           AS session_source,
       b.sim_run_id,
       b.vehicle_id        AS asset_id,
       b.stall_id          AS service_point_id,
       COALESCE(oc.operation_code, b.purpose) AS operation_code,
       lower(b.during)     AS started_at,
       CASE WHEN b.state IN ('done','released','superseded','interrupted')
            THEN upper(b.during) END          AS ended_at,
       b.state             AS session_state,
       b.visit_id, b.leg_id,
       NULL::uuid          AS schedule_task_id
  FROM public.ottoq_stall_bookings b
  LEFT JOIN public.ottoq_operation_catalog oc
         ON oc.booking_purpose = b.purpose AND oc.pack_id = 'robotaxi'
UNION ALL
SELECT t.id, 'schedule_task', NULL::uuid, t.vehicle_id,
       COALESCE(t.actual_stall_id, t.assigned_stall_id),
       COALESCE(oc.operation_code, t.service_code, sd.code),
       COALESCE(t.actual_start, t.scheduled_start),
       t.actual_end,
       t.status::text, NULL::uuid, NULL::uuid, t.id
  FROM public.schedule_tasks t
  JOIN public.service_definitions sd ON sd.id = t.service_definition_id
  LEFT JOIN public.ottoq_operation_catalog oc
         ON oc.svc_code = COALESCE(t.service_code, sd.code) AND oc.pack_id = 'robotaxi'
 WHERE t.status::text IN ('in_progress','completed');

-- ServiceProfile <- OCPI ChargingProfile analogue extended to non-energy
-- resources: the published forward schedule. Site-power periods come from the
-- MPC plan (schedule-shaped, never a live setpoint command — the 2.5 power
-- publication boundary); service-point periods from forward bookings.
CREATE OR REPLACE VIEW public.service_profiles
  WITH (security_invoker = true) AS
SELECT 'site_power'        AS resource_kind,
       p.depot_id          AS site_id,
       NULL::uuid          AS service_point_id,
       p.sim_run_id,
       p.created_at        AS published_at,
       p.plan_start_clock  AS window_start,
       p.plan_start_clock
         + make_interval(mins => (p.tick_minutes * p.horizon_steps)::int)
                           AS window_end,
       jsonb_build_object(
         'tick_minutes',    p.tick_minutes,
         'bess_setpoint_kw', to_jsonb(p.bess_setpoint_kw),
         'grid_import_kw',   to_jsonb(p.grid_import_kw),
         'forecast_load_kw', to_jsonb(p.forecast_load_kw),
         'predicted_peak_kw', p.predicted_peak_kw,
         'solver', p.solver) AS periods,
       p.plan_state         AS profile_state
  FROM public.ottoq_energy_plan p
 WHERE p.plan_state IN ('ready','applied','pending')
UNION ALL
SELECT 'service_point', s.depot_id, b.stall_id, b.sim_run_id,
       b.booked_at, lower(b.during), upper(b.during),
       jsonb_build_object('operation', COALESCE(oc.operation_code, b.purpose),
                          'asset_id', b.vehicle_id,
                          'booking_state', b.state),
       b.state
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
  LEFT JOIN public.ottoq_operation_catalog oc
         ON oc.booking_purpose = b.purpose AND oc.pack_id = 'robotaxi'
 WHERE b.state IN ('held','active')
   AND upper(b.during) > now() - interval '1 hour';

-- Kernel naming views (rename-level; sector words stay in base tables only).
CREATE OR REPLACE VIEW public.kernel_asset_classes
  WITH (security_invoker = true) AS
SELECT vehicle_class_code AS asset_class_code, pack_id, oem_name AS operator_name,
       manufacturer, model, battery_capacity_kwh, max_charge_rate_kw, inlet_type,
       energy_curve, duty_cycle_profile, status
  FROM public.ottoq_vehicle_classes;

CREATE OR REPLACE VIEW public.kernel_assets
  WITH (security_invoker = true) AS
SELECT v.id AS asset_id, v.vehicle_class_code AS asset_class_code,
       v.category::text AS asset_category, v.fleet_operator_id AS operator_id,
       v.home_depot_id AS home_site_id, v.current_depot_id AS current_site_id,
       v.current_stall_id AS current_point_id, v.current_state::text AS state,
       v.current_soc, v.target_soc, v.is_active, v.owning_sim_run_id
  FROM public.vehicles v;

CREATE OR REPLACE VIEW public.kernel_service_points
  WITH (security_invoker = true) AS
SELECT s.id AS service_point_id, s.depot_id AS site_id, s.stall_code AS point_code,
       s.stall_type::text AS point_kind, s.status, s.connector_max_kw,
       s.supported_inlet_types, s.zone, s.covered
  FROM public.stalls s;

-- ============================================================================
-- §12  RLS — new tables deny-by-default (RLS on, no anon policies; the service
--      role and SECURITY DEFINER kernel functions are unaffected).
-- ============================================================================
ALTER TABLE public.ottoq_operation_catalog          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_service_point_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_service_tokens             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_service_tariffs            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_service_detail_records     ENABLE ROW LEVEL SECURITY;
