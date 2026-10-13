-- tests/fixtures/asset_depth_stub.sql -- what 0717 meets. public.ottoq_agent_asset_depth is the live definition of
-- 2026-10-13 (pg_get_functiondef, byte for byte: md5 70f53e41698532607f5aa2aff0288265), so 0717's md5 premise and its
-- substitutions run against exactly what they will meet. The tables are minimal stand-ins with the columns it reads.
-- Used by tests/test_asset_depth_sql.py.
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS twin; CREATE SCHEMA IF NOT EXISTS ottoq; CREATE SCHEMA IF NOT EXISTS extensions;
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial, label text, object_kind text, schema_name text,
  object_name text, definition text, def_md5 text, captured_at timestamptz DEFAULT now());
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, display_name text, current_state text, current_soc numeric,
  home_depot_id uuid, category text DEFAULT 'autonomous', vehicle_class_code text);
CREATE TABLE public.vehicle_need_profile (vehicle_id uuid PRIMARY KEY, min_ready_soc_pct numeric, battery_soh_pct numeric,
  charge_accept_kw numeric, pack_temp_c numeric, dcfc_safe boolean, dcfc_block_reason text, sensor_health_pct numeric,
  tire_tread_mm numeric, brake_wear_pct numeric, worst_fault_severity smallint, open_fault_codes jsonb,
  next_deploy_at timestamptz, priority_class text, odometer_km numeric, pm_interval_km numeric, km_at_last_pm numeric,
  software_version text, sw_target_version text);
CREATE TABLE public.ottoq_vehicle_classes (vehicle_class_code text PRIMARY KEY, max_charge_rate_kw numeric);
CREATE TABLE public.ottoq_telemetry_packets (vehicle_id uuid, sim_run_id uuid, sim_clock_at timestamptz,
  packet_integrity text, dropped_reason text, signal_strength_pct numeric, battery_temp_c numeric, range_remaining_km numeric);

CREATE OR REPLACE FUNCTION public.ottoq_agent_asset_depth(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone, p_attention_limit integer DEFAULT 10, p_telemetry_window_min integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_assets jsonb; v_telemetry jsonb; v_attention jsonb;
BEGIN
  WITH veh AS (
    SELECT v.id, v.display_name, v.current_state, v.current_soc,
           p.min_ready_soc_pct, p.battery_soh_pct, p.charge_accept_kw, p.pack_temp_c,
           p.dcfc_safe, p.dcfc_block_reason, p.sensor_health_pct,
           p.tire_tread_mm, p.brake_wear_pct, p.worst_fault_severity,
           p.open_fault_codes, p.next_deploy_at, p.priority_class,
           p.odometer_km, p.pm_interval_km, p.km_at_last_pm,
           p.software_version, p.sw_target_version, c.max_charge_rate_kw,
           (p.open_fault_codes IS NOT NULL
             AND p.open_fault_codes::text NOT IN ('null','[]','{}','')) AS has_fault,
           CASE WHEN p.next_deploy_at IS NOT NULL
                THEN EXTRACT(epoch FROM (p.next_deploy_at - p_clock))/60.0 END AS mins_to_deploy
      FROM vehicles v
      LEFT JOIN vehicle_need_profile p  ON p.vehicle_id = v.id
      LEFT JOIN ottoq_vehicle_classes c ON c.vehicle_class_code = v.vehicle_class_code
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'),
  soc AS (
    SELECT count(*) AS n, round(min(current_soc)) AS min,
           round(percentile_cont(0.10) WITHIN GROUP (ORDER BY current_soc)::numeric) AS p10,
           round(percentile_cont(0.50) WITHIN GROUP (ORDER BY current_soc)::numeric) AS p50,
           round(percentile_cont(0.90) WITHIN GROUP (ORDER BY current_soc)::numeric) AS p90,
           round(max(current_soc)) AS max,
           count(*) FILTER (WHERE current_soc < COALESCE(min_ready_soc_pct, 0)) AS below_min_ready
      FROM veh WHERE current_soc IS NOT NULL),
  blocks AS (
    SELECT count(*) FILTER (WHERE dcfc_safe IS FALSE) AS dcfc_blocked,
           count(*) FILTER (WHERE charge_accept_kw IS NOT NULL AND max_charge_rate_kw IS NOT NULL
                              AND charge_accept_kw < max_charge_rate_kw * 0.8) AS charge_derated,
           (SELECT jsonb_object_agg(reason, n) FROM (
              SELECT COALESCE(dcfc_block_reason,'unspecified') AS reason, count(*) n
                FROM veh WHERE dcfc_safe IS FALSE GROUP BY 1 ORDER BY n DESC LIMIT 6) r) AS dcfc_block_reasons
      FROM veh),
  health AS (
    SELECT count(*) FILTER (WHERE has_fault) AS open_faults,
           count(*) FILTER (WHERE sensor_health_pct < 90) AS sensor_below_90,
           count(*) FILTER (WHERE tire_tread_mm < 3.0) AS tread_below_3mm,
           count(*) FILTER (WHERE brake_wear_pct > 80) AS brake_above_80pct,
           count(*) FILTER (WHERE pm_interval_km IS NOT NULL AND odometer_km IS NOT NULL
                              AND odometer_km - COALESCE(km_at_last_pm,0) > pm_interval_km) AS pm_overdue,
           count(*) FILTER (WHERE sw_target_version IS NOT NULL
                              AND software_version IS DISTINCT FROM sw_target_version) AS sw_behind,
           -- worst_fault_severity is a smallint RANK where LOWER IS WORSE, and 99 is
           -- the "no fault" sentinel (195 of 220 profiles sit at 99). Reporting it raw
           -- would tell the agent 195 vehicles are at "severity 99", which reads as
           -- catastrophic and means the opposite. Sentinel excluded, rank labelled so
           -- it cannot be misread as a score. The first draft compared it to
           -- ('critical','high') -- wrong type AND wrong direction -- and only A2
           -- calling the function caught it, because plpgsql plans lazily.
           count(*) FILTER (WHERE worst_fault_severity IS NOT NULL
                              AND worst_fault_severity <= 2) AS severe_faults,
           (SELECT jsonb_object_agg('rank_'||sev::text, n) FROM (
              SELECT worst_fault_severity AS sev, count(*) n FROM veh
               WHERE worst_fault_severity IS NOT NULL AND worst_fault_severity < 99
               GROUP BY 1 ORDER BY 1 LIMIT 5) s) AS fault_severity_ranks,
           -- priority_class is the TEXT label operators actually sort by.
           (SELECT jsonb_object_agg(pc, n) FROM (
              SELECT COALESCE(priority_class,'unspecified') AS pc, count(*) n
                FROM veh GROUP BY 1 ORDER BY n DESC LIMIT 5) pcx) AS by_priority_class
      FROM veh),
  deadlines AS (
    SELECT count(*) FILTER (WHERE mins_to_deploy < 0) AS overdue,
           count(*) FILTER (WHERE mins_to_deploy BETWEEN 0 AND 30) AS due_30m,
           count(*) FILTER (WHERE mins_to_deploy > 30 AND mins_to_deploy <= 60) AS due_60m,
           count(*) FILTER (WHERE mins_to_deploy > 60 AND mins_to_deploy <= 120) AS due_120m,
           round(min(mins_to_deploy) FILTER (WHERE mins_to_deploy >= 0)) AS tightest_min
      FROM veh)
  SELECT jsonb_build_object(
    'n', (SELECT count(*) FROM veh),
    'soc', (SELECT to_jsonb(s) FROM soc s),
    'hard_constraints', (SELECT to_jsonb(b) FROM blocks b),
    'health', (SELECT to_jsonb(h) FROM health h),
    'deadlines', (SELECT to_jsonb(d) FROM deadlines d)) INTO v_assets;

  WITH veh AS (
    SELECT v.display_name, v.current_state, v.current_soc,
           p.min_ready_soc_pct, p.dcfc_safe, p.dcfc_block_reason,
           p.sensor_health_pct, p.tire_tread_mm, p.brake_wear_pct,
           p.worst_fault_severity, p.priority_class, p.next_deploy_at,
           (p.open_fault_codes IS NOT NULL
             AND p.open_fault_codes::text NOT IN ('null','[]','{}','')) AS has_fault,
           CASE WHEN p.next_deploy_at IS NOT NULL
                THEN EXTRACT(epoch FROM (p.next_deploy_at - p_clock))/60.0 END AS mins_to_deploy
      FROM vehicles v
      LEFT JOIN vehicle_need_profile p ON p.vehicle_id = v.id
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'),
  scored AS (
    SELECT display_name, current_state, round(current_soc) AS soc, mins_to_deploy, priority_class,
           (CASE WHEN mins_to_deploy < 0 THEN 100 ELSE 0 END
          + CASE WHEN worst_fault_severity IS NOT NULL AND worst_fault_severity <= 2 THEN 80 ELSE 0 END
          + CASE WHEN dcfc_safe IS FALSE AND current_soc < COALESCE(min_ready_soc_pct,30) THEN 70 ELSE 0 END
          + CASE WHEN current_soc < COALESCE(min_ready_soc_pct,30) THEN 50 ELSE 0 END
          + CASE WHEN mins_to_deploy BETWEEN 0 AND 30 THEN 40 ELSE 0 END
          + CASE WHEN has_fault THEN 20 ELSE 0 END
          + CASE WHEN sensor_health_pct < 90 THEN 15 ELSE 0 END
          + CASE WHEN tire_tread_mm < 3.0 THEN 10 ELSE 0 END
          + CASE WHEN brake_wear_pct > 80 THEN 10 ELSE 0 END
          + CASE WHEN priority_class = 'critical' THEN 25 WHEN priority_class = 'high' THEN 10 ELSE 0 END) AS score,
           (ARRAY[]::text[]
          || CASE WHEN mins_to_deploy < 0 THEN ARRAY['deploy deadline passed '||round(abs(mins_to_deploy))||'m ago'] ELSE ARRAY[]::text[] END
          || CASE WHEN mins_to_deploy BETWEEN 0 AND 30 THEN ARRAY['due out in '||round(mins_to_deploy)||'m'] ELSE ARRAY[]::text[] END
          || CASE WHEN current_soc < COALESCE(min_ready_soc_pct,30) THEN ARRAY['soc '||round(current_soc)||'% below ready floor '||round(COALESCE(min_ready_soc_pct,30))||'%'] ELSE ARRAY[]::text[] END
          || CASE WHEN dcfc_safe IS FALSE THEN ARRAY['dcfc blocked: '||COALESCE(dcfc_block_reason,'unspecified')] ELSE ARRAY[]::text[] END
          || CASE WHEN has_fault THEN ARRAY['open fault'||CASE WHEN worst_fault_severity IS NOT NULL AND worst_fault_severity < 99 THEN ' (severity rank '||worst_fault_severity::text||', lower is worse)' ELSE '' END] ELSE ARRAY[]::text[] END
          || CASE WHEN sensor_health_pct < 90 THEN ARRAY['sensor health '||round(sensor_health_pct)||'%'] ELSE ARRAY[]::text[] END
          || CASE WHEN tire_tread_mm < 3.0 THEN ARRAY['tread '||tire_tread_mm||'mm'] ELSE ARRAY[]::text[] END
          || CASE WHEN brake_wear_pct > 80 THEN ARRAY['brake wear '||round(brake_wear_pct)||'%'] ELSE ARRAY[]::text[] END) AS why
      FROM veh)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'asset', display_name, 'state', current_state, 'soc', soc,
           'mins_to_deploy', round(mins_to_deploy), 'priority', priority_class,
           'why', to_jsonb(why)) ORDER BY score DESC, display_name), '[]'::jsonb)
    INTO v_attention
    FROM (SELECT * FROM scored WHERE score > 0 ORDER BY score DESC, display_name
           LIMIT GREATEST(1, LEAST(p_attention_limit, 25))) top;

  v_assets := v_assets || jsonb_build_object('attention', v_attention);

  SELECT jsonb_build_object(
    'window_min', p_telemetry_window_min,
    'packets', count(*),
    'vehicles_reporting', count(DISTINCT vehicle_id),
    'integrity', (SELECT jsonb_object_agg(k, c) FROM (
        SELECT COALESCE(packet_integrity,'unspecified') k, count(*) c
          FROM ottoq_telemetry_packets WHERE sim_run_id = p_sim_run_id
           AND sim_clock_at > p_clock - make_interval(mins => p_telemetry_window_min)
         GROUP BY 1 ORDER BY c DESC LIMIT 5) i),
    'dropped_reasons', (SELECT jsonb_object_agg(k, c) FROM (
        SELECT COALESCE(dropped_reason,'none') k, count(*) c
          FROM ottoq_telemetry_packets WHERE sim_run_id = p_sim_run_id
           AND sim_clock_at > p_clock - make_interval(mins => p_telemetry_window_min)
           AND dropped_reason IS NOT NULL GROUP BY 1 ORDER BY c DESC LIMIT 5) d),
    'signal_below_50pct', count(*) FILTER (WHERE signal_strength_pct < 50),
    'max_battery_temp_c', round(max(battery_temp_c)::numeric, 1),
    'min_range_remaining_km', round(min(range_remaining_km)::numeric, 1)
  ) INTO v_telemetry
    FROM ottoq_telemetry_packets
   WHERE sim_run_id = p_sim_run_id
     AND sim_clock_at > p_clock - make_interval(mins => p_telemetry_window_min);

  v_telemetry := v_telemetry || jsonb_build_object(
    'silent_vehicles', (
      SELECT count(*) FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
         AND NOT EXISTS (SELECT 1 FROM ottoq_telemetry_packets t
            WHERE t.vehicle_id = v.id AND t.sim_run_id = p_sim_run_id
              AND t.sim_clock_at > p_clock - make_interval(mins => p_telemetry_window_min))));

  RETURN jsonb_build_object('assets', v_assets, 'telemetry', v_telemetry);
END $function$
;
