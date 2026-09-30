-- Stub engine for 0574 (tests/test_energy_price_sql.py). The reader is the live body, byte for byte (source md5
-- 8f93e635552b6be131f7e54e8eb1f54b, which 0574 P2 pins). The twin's six windows are the ones measured on 2026-09-29
-- (fingerprint fa2b6da72a5eb00485257630d306180e); another depot carries the same six, which 0574 must not touch.

CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;

CREATE TYPE public.tariff_label AS ENUM ('super_off_peak', 'off_peak', 'mid_peak', 'on_peak');

CREATE TABLE public.ottoq_tariff_windows (
  tariff_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid NOT NULL, label text NOT NULL,
  rate_usd_per_kwh numeric NOT NULL, hour_start integer NOT NULL, hour_end integer NOT NULL,
  day_of_week_mask integer NOT NULL DEFAULT 127, season text NOT NULL DEFAULT 'all', active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now());

CREATE OR REPLACE FUNCTION twin.ottoq_sim_current_tariff(p_depot_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS TABLE(out_label text, out_rate_usd_kwh numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hour    INTEGER;
  v_dow     INTEGER;
  v_month   INTEGER;
  v_season  TEXT;
BEGIN
  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_dow  := EXTRACT(DOW  FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_month := EXTRACT(MONTH FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  v_season := CASE
    WHEN v_month BETWEEN 6 AND 9  THEN 'summer'
    WHEN v_month BETWEEN 12 AND 12 OR v_month BETWEEN 1 AND 2 THEN 'winter'
    ELSE 'shoulder' END;

  SELECT label, rate_usd_per_kwh
    INTO out_label, out_rate_usd_kwh
    FROM ottoq_tariff_windows
   WHERE depot_id = p_depot_id
     AND active
     AND v_hour >= hour_start AND v_hour < hour_end
     AND (season = v_season OR season = 'all')
   ORDER BY rate_usd_per_kwh DESC                       -- super-peak wins over peak
   LIMIT 1;
  IF NOT FOUND THEN
    out_label := 'unknown';
    out_rate_usd_kwh := 0.10;
  END IF;
  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false)
 RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$;

CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid, status text);

CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY, taken_at timestamptz NOT NULL DEFAULT now(), label text NOT NULL,
  object_kind text NOT NULL, schema_name text NOT NULL, object_name text NOT NULL, definition text NOT NULL,
  def_md5 text NOT NULL);

CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean, forces_dial_restart boolean, note text, classified_at timestamptz);

INSERT INTO public.ottoq_tariff_windows (depot_id, label, rate_usd_per_kwh, hour_start, hour_end, day_of_week_mask, season, active)
SELECT d::uuid, l, r, hs, he, 127, s, true
  FROM (VALUES ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222')) dd(d),
       (VALUES ('off_peak', 0.052, 0, 6, 'all'), ('mid_peak', 0.092, 6, 13, 'all'), ('peak', 0.158, 13, 20, 'summer'),
               ('super_peak', 0.235, 17, 19, 'summer'), ('peak', 0.115, 13, 20, 'winter'),
               ('mid_peak', 0.085, 20, 24, 'all')) w(l, r, hs, he, s);
