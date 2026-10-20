-- tests/fixtures/release_expired_tethers_stub.sql -- the tether sweep's world, for tests/test_cabin_arm_keeps_its_stall_sql.py.
--
-- The tables public.ottoq_release_expired_tethers reads and writes, cut to the columns it and 0760 touch (types as live),
-- the two ledgers 0760 writes, a quiet ottoq_certification_in_flight, and the sweep itself AS LIVE: its definition as
-- pg_get_functiondef returned it on 2026-10-20, body byte for byte (prosrc md5 e93c55436dca059c95b6462873b704ba,
-- 2,033 bytes; the test asserts it). 0758's lineage row is present, as on live.

CREATE TABLE public.vehicles (
  id                       uuid PRIMARY KEY,
  current_stall_id         uuid,
  robotic_tether_until     timestamptz,
  robotic_tether_stall_id  uuid,
  robotic_tether_direction text,
  robotic_tether_phase     text
);

CREATE TABLE public.stalls (
  id                 uuid PRIMARY KEY,
  status             text NOT NULL DEFAULT 'available',
  current_vehicle_id uuid
);

CREATE TABLE public.ottoq_visit_needs (
  vehicle_id uuid NOT NULL,
  sim_run_id uuid,
  status     text NOT NULL DEFAULT 'open',
  atoms      jsonb NOT NULL DEFAULT '[]'::jsonb
);

CREATE TABLE public.ottoq_cert_lineage (
  name                text PRIMARY KEY,
  forces_recert       boolean NOT NULL,
  forces_dial_restart boolean NOT NULL,
  note                text,
  classified_at       timestamptz
);
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges', false, false, 'as live', now());

CREATE TABLE public.ottoq_schema_snapshots (
  label       text,
  object_kind text,
  schema_name text,
  object_name text,
  definition  text,
  def_md5     text
);

CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false) RETURNS integer
LANGUAGE sql AS $$ SELECT 0 $$;

CREATE OR REPLACE FUNCTION public.ottoq_release_expired_tethers(p_now timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_now timestamptz;
  v_n   integer := 0;
BEGIN
  v_now := COALESCE(p_now, now());

  WITH due AS (
    -- plain SELECT: captures robotic_tether_stall_id BEFORE anything nulls it
    SELECT v.id AS vehicle_id, v.robotic_tether_stall_id AS stall_id,
           COALESCE(v.robotic_tether_direction, 'demate') AS direction
      FROM public.vehicles v
     WHERE v.robotic_tether_until IS NOT NULL
       AND v.robotic_tether_until <= v_now
  ), cleared AS (
    UPDATE public.vehicles v
       SET robotic_tether_until = NULL,
           robotic_tether_stall_id = NULL,
           robotic_tether_direction = NULL,
           robotic_tether_phase = NULL,
           -- DEMATE ONLY, and only if the car is still pointing at the stall the
           -- arm was holding it in. An inbound tether ending means the car is
           -- arriving at that stall and must keep pointing at it.
           current_stall_id = CASE
             WHEN d.direction = 'demate'
              AND v.current_stall_id IS NOT DISTINCT FROM d.stall_id
             THEN NULL ELSE v.current_stall_id END
      FROM due d
     WHERE v.id = d.vehicle_id
    RETURNING v.id
  ), freed AS (
    -- DEMATE ONLY. An outbound tether ending means the car has left the plug and
    -- the stall is genuinely free. An inbound or charging tether ending means the
    -- car is still sitting in that stall — freeing it there would advertise an
    -- occupied stall as available and invite a second vehicle into it.
    -- COALESCE above treats a legacy NULL direction as 'demate', which is what
    -- every row written before this migration was.
    UPDATE public.stalls s
       SET current_vehicle_id = NULL,
           status = CASE WHEN s.status = 'occupied' THEN 'available' ELSE s.status END
      FROM due d
     WHERE s.id = d.stall_id
       AND d.direction = 'demate'
       AND s.current_vehicle_id = d.vehicle_id
    RETURNING s.id
  )
  SELECT count(*) INTO v_n FROM cleared;

  RETURN COALESCE(v_n, 0);
EXCEPTION WHEN OTHERS THEN
  RETURN 0;
END;
$function$
;
