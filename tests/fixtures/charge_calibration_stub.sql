-- Stub engine for 0573 (tests/test_charge_calibration_sql.py). The three charge functions are the live bodies, byte for
-- byte (the rate function's source md5 is 20f2d98f41e34238497a5d28304e7004, which 0573 P2 pins); the planner is a stub
-- whose body carries the one line 0573 edits, so the edit's effect can be executed. The vehicles are the twin's and the
-- Benchmark's autonomous cars as measured on 2026-09-29, plus cars 0573 must not touch.

CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;

CREATE OR REPLACE FUNCTION twin.ottoq_sim_seeded_random(p_seed bigint, p_salt text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hash BIGINT;
BEGIN
  -- Combine seed + salt into a deterministic hash, normalize to [0,1)
  v_hash := abs(hashtextextended(p_seed::text || ':' || p_salt, p_seed));
  RETURN (v_hash % 1000000)::NUMERIC / 1000000.0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_sim_compute_charge_rate(p_soc_pct numeric, p_battery_temp_c numeric, p_ambient_temp_c numeric, p_charger_max_kw numeric, p_vehicle_max_kw numeric, p_battery_capacity_kwh numeric, p_battery_soh_pct numeric DEFAULT 100, p_noise_seed bigint DEFAULT 0, p_noise_salt text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_base_rate      NUMERIC;
  v_is_dcfc        BOOLEAN;
  v_curve_factor   NUMERIC := 1.0;
  v_thermal_factor NUMERIC := 1.0;
  v_soh_factor     NUMERIC;
  v_noise_factor   NUMERIC;
BEGIN
  v_base_rate := LEAST(p_charger_max_kw, p_vehicle_max_kw);
  IF v_base_rate <= 0 THEN RETURN 0; END IF;
  v_is_dcfc := p_charger_max_kw > 22;

  IF v_is_dcfc THEN
    -- DCFC: ramp to peak by 20%, NEAR-LINEAR decline 20->80% (1.0 -> 0.22),
    -- steeper CV tail 80->100% (0.22 -> 0.08). 20->80 on a 75kWh pack lands
    -- ~25-30 min at typical effective power — the measured reality.
    IF p_soc_pct < 20 THEN
      v_curve_factor := 0.85 + (p_soc_pct / 20.0) * 0.15;
    ELSIF p_soc_pct <= 80 THEN
      v_curve_factor := 1.0 - ((p_soc_pct - 20.0) / 60.0) * 0.78;
    ELSE
      v_curve_factor := GREATEST(0.08, 0.22 - ((p_soc_pct - 80.0) / 20.0) * 0.14);
    END IF;
  ELSE
    -- L2/AC: onboard-charger limited, flat with ~88% AC->DC efficiency;
    -- taper only near full.
    v_curve_factor := CASE WHEN p_soc_pct > 95 THEN 0.88 * 0.5 ELSE 0.88 END;
  END IF;

  -- thermal derate: INL-calibrated cold behavior; heat derate unchanged
  IF p_battery_temp_c > 35 THEN
    v_thermal_factor := GREATEST(0.30, 1.0 - (p_battery_temp_c - 35) * 0.020);
  ELSIF p_battery_temp_c < 0 THEN
    v_thermal_factor := GREATEST(0.20, 0.35 + p_battery_temp_c * 0.010);  -- <=0C: 0.35 and falling
  ELSIF p_battery_temp_c < 10 THEN
    v_thermal_factor := 0.65;                                             -- 0-10C: x0.65 (INL)
  ELSIF p_battery_temp_c < 15 THEN
    v_thermal_factor := 0.65 + (p_battery_temp_c - 10) * 0.07;            -- blend 10->15C
  END IF;

  v_soh_factor := 0.70 + (p_battery_soh_pct / 100.0) * 0.30;
  v_noise_factor := 0.97 + ottoq_sim_seeded_random(
    p_noise_seed, COALESCE(p_noise_salt, '') || ':' || p_soc_pct::text) * 0.06;

  RETURN ROUND((v_base_rate * v_curve_factor * v_thermal_factor * v_soh_factor * v_noise_factor)::NUMERIC, 3);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_estimate_charge_minutes(p_start_soc numeric, p_target_soc numeric, p_charger_max_kw numeric, p_vehicle_max_kw numeric, p_battery_capacity_kwh numeric, p_battery_temp_c numeric DEFAULT 25, p_battery_soh_pct numeric DEFAULT 95, p_rate_mult numeric DEFAULT 1.0)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc  numeric := p_start_soc;
  v_step numeric := 1.0;
  v_kw   numeric;
  v_min  numeric := 0;
BEGIN
  IF p_target_soc <= p_start_soc OR p_battery_capacity_kwh <= 0 THEN RETURN 0; END IF;
  WHILE v_soc < p_target_soc LOOP
    v_kw := public.ottoq_sim_compute_charge_rate(
      p_soc_pct := v_soc,
      p_battery_temp_c := p_battery_temp_c,
      p_ambient_temp_c := p_battery_temp_c,
      p_charger_max_kw := p_charger_max_kw,
      p_vehicle_max_kw := p_vehicle_max_kw,
      p_battery_capacity_kwh := p_battery_capacity_kwh,
      p_battery_soh_pct := p_battery_soh_pct,
      p_noise_seed := 0, p_noise_salt := 'plan');
    v_kw := v_kw / GREATEST(0.2, p_rate_mult);
    EXIT WHEN v_kw <= 0.5;
    v_min := v_min + (v_step / 100.0 * p_battery_capacity_kwh) / v_kw * 60.0;
    v_soc := v_soc + v_step;
  END LOOP;
  RETURN ROUND(v_min, 1);
END;
$function$;

-- The planner: the live signature and SECURITY DEFINER shape, a stub body around the one line 0573 edits.
CREATE OR REPLACE FUNCTION ottoq.ottoq_derive_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_clock timestamp with time zone, p_depot_id uuid, p_obs jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'ottoq', 'public', 'twin'
AS $function$
DECLARE
  v_svcspd numeric := COALESCE((p_obs->>'svcspd')::numeric, 1);
  v_calib_min int;
BEGIN
  v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;
  RETURN jsonb_build_object('calib_min', v_calib_min);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false)
 RETURNS integer LANGUAGE sql AS $$ SELECT COALESCE(current_setting('stub.in_flight', true), '0')::int $$;

CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid, status text);

CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY, category text, home_depot_id uuid, make text, model text,
  battery_capacity_kwh numeric(10,2), inlet_max_kw numeric(6,1));

CREATE TABLE public.ottoq_vehicle_classes (
  vehicle_class_code text PRIMARY KEY, battery_capacity_kwh numeric, max_charge_rate_kw numeric);

CREATE TABLE public.service_cadence_policy (svc text PRIMARY KEY, est_min_default numeric, notes text);

CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY, taken_at timestamptz NOT NULL DEFAULT now(), label text NOT NULL,
  object_kind text NOT NULL, schema_name text NOT NULL, object_name text NOT NULL, definition text NOT NULL,
  def_md5 text NOT NULL);

CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean, forces_dial_restart boolean, note text, classified_at timestamptz);

CREATE TABLE public.ottoq_site_buildout_active (buildout_code text);

-- the twin (1111...) and the Benchmark (2222...) as measured 2026-09-29
INSERT INTO public.vehicles
SELECT gen_random_uuid(), 'autonomous', d::uuid, mk, md, kwh, kw
  FROM (VALUES
    ('11111111-1111-1111-1111-111111111111', 'Waymo',  'I-Pace',    75.00, 100.0, 40),
    ('11111111-1111-1111-1111-111111111111', 'Jaguar', 'I-PACE AV', 90.00, NULL,   4),
    ('11111111-1111-1111-1111-111111111111', 'Zeekr',  'RT AV',    100.00, NULL,   2),
    ('11111111-1111-1111-1111-111111111111', 'Tesla',  'Model Y',   75.00, 250.0, 32),
    ('11111111-1111-1111-1111-111111111111', 'Tesla',  'Cybercab',  75.00, NULL,   4),
    ('11111111-1111-1111-1111-111111111111', 'Zoox',   'Robotaxi', 135.00, 200.0, 30),
    ('11111111-1111-1111-1111-111111111111', 'Zoox',   'VH6',      133.00, NULL,   4),
    ('22222222-2222-2222-2222-222222222222', 'Waymo',  'I-Pace',    90.00, 100.0, 37),
    ('22222222-2222-2222-2222-222222222222', 'Jaguar', 'I-PACE AV', 90.00, NULL,   3),
    ('22222222-2222-2222-2222-222222222222', 'Zeekr',  'RT AV',    100.00, NULL,   2),
    ('22222222-2222-2222-2222-222222222222', 'Tesla',  'Model Y',   75.00, 250.0, 29),
    ('22222222-2222-2222-2222-222222222222', 'Zoox',   'Robotaxi', 135.00, 200.0, 29),
    -- not 0573's: another depot, and a retail car at the twin
    ('33333333-3333-3333-3333-333333333333', 'Waymo',  'I-Pace',    75.00, 100.0,  2)) x(d, mk, md, kwh, kw, n),
  generate_series(1, x.n);
INSERT INTO public.vehicles VALUES
  (gen_random_uuid(), 'retail', '11111111-1111-1111-1111-111111111111', 'Zoox', 'Robotaxi', 135.00, 200.0);

INSERT INTO public.ottoq_vehicle_classes VALUES
  ('waymo_jaguar_ipace_2024', 90, 100), ('zoox_robotaxi_2024', 135, 200), ('tesla_model_y_robotaxi_2024', 75, 250);

INSERT INTO public.service_cadence_policy VALUES
  ('sensor_calibration', 30, 'SERVICE_BAY STARVED (2 bays/116 vehicles, 1.7% cleared). Escalates only at critical.'),
  ('exterior_wash', 10, '3 wash bays, 10 min: ample headroom.');
