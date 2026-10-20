-- tests/fixtures/owner_ready_by_stub.sql: what the owner app reads to say when a car will be ready, for
-- tests/test_ready_promise_sql.py's 0741 tests. Loaded after tests/fixtures/ready_promise_stub.sql and 0736/0739.
--
-- The four functions are the LIVE bodies, read from the live catalog on 2026-10-17 (md5 of prosrc asserted by the test):
--   public.ottoq_owner_car(vehicles,uuid,numeric)              683bf45b15f8e68aa4ae64b67e5263d7
--   public.ottoq_owner_clock(timestamptz,boolean,boolean)      18f217209ef01e60d6583855a2a92f69
--   public.ottoq_owner_state_phrase(text)                       0d23bab3def7a5e8ce7c1bc1ee4fa387
--   public.ottoq_owner_state_group(text)                        ce2af49062888cf4ef99c3e43c8a80f4
-- with the live grants (EXECUTE for postgres only). The three tables carry only the columns those bodies read; the
-- miniature depot's vehicles, stalls and ottoq_visit_needs are the harness's own.

CREATE TABLE IF NOT EXISTS public.ottoq_itinerary_legs (
  leg_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), itinerary_id uuid, sim_run_id uuid, vehicle_id uuid, seq integer,
  leg_type text, planned_start_sim timestamptz, planned_end_sim timestamptz, status text,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.ottoq_owner_settings (
  setting_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid, vehicle_id uuid, kind text, status text,
  charge_limit_pct numeric, hold_until_sim timestamptz, service text, service_when text, command_id uuid);
CREATE TABLE IF NOT EXISTS public.service_cadence_policy (svc text PRIMARY KEY);
ALTER TABLE public.service_cadence_policy ADD COLUMN IF NOT EXISTS display_name text;

CREATE OR REPLACE FUNCTION public.ottoq_owner_clock(p_ts timestamp with time zone, p_sim boolean, p_with_day boolean DEFAULT false)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT CASE WHEN p_ts IS NULL THEN NULL ELSE
    to_char(p_ts AT TIME ZONE 'America/Chicago', 'FMHH12:MI AM')
    || CASE WHEN p_with_day THEN to_char(p_ts AT TIME ZONE 'America/Chicago', ' "on" Dy FMMon FMDD') ELSE '' END
    || CASE WHEN p_sim THEN ' sim time' ELSE ' CT' END END
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_state_phrase(p_state text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT CASE p_state
    WHEN 'offline'                  THEN 'parked and offline'
    WHEN 'deployed'                 THEN 'out on the road'
    WHEN 'en_route_to_depot'        THEN 'on its way back to the depot'
    WHEN 'arrived_at_gate'          THEN 'at the depot gate'
    WHEN 'staged_awaiting_service'  THEN 'parked in staging, waiting for its next step'
    WHEN 'charging_dcfc'            THEN 'fast-charging'
    WHEN 'charging_l2'              THEN 'charging on a Level 2 charger'
    WHEN 'charge_complete_holding'  THEN 'done charging, waiting for its next step'
    WHEN 'in_wash_bay'              THEN 'in the wash bay'
    WHEN 'in_detail_bay'            THEN 'in the detail bay'
    WHEN 'in_service_bay'           THEN 'in the service bay'
    WHEN 'service_complete_holding' THEN 'done with its service, waiting for its next step'
    WHEN 'staged_for_departure'     THEN 'staged to leave'
    WHEN 'en_route_to_deployment'   THEN 'leaving for work'
    WHEN 'emergency_staged'         THEN 'held for an emergency'
    WHEN 'tow_requested'            THEN 'waiting for a tow'
    WHEN 'out_of_service'           THEN 'out of service'
    ELSE COALESCE(replace(p_state, '_', ' '), 'in an unknown state') END
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_state_group(p_state text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN p_state IN ('deployed', 'en_route_to_deployment') THEN 'on the road'
    WHEN p_state = 'en_route_to_depot' THEN 'heading back'
    WHEN p_state IN ('charging_dcfc', 'charging_l2') THEN 'charging'
    WHEN p_state IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay') THEN 'in a bay'
    WHEN p_state = 'staged_for_departure' THEN 'staged to leave'
    WHEN p_state IN ('arrived_at_gate', 'staged_awaiting_service', 'charge_complete_holding', 'service_complete_holding')
      THEN 'waiting at the depot'
    ELSE 'parked or offline' END
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_car(p_v vehicles, p_run uuid, p_ceiling numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_limit  numeric;
  v_hold   timestamptz;
  v_orders jsonb;
  v_open   jsonb;
  v_ready  timestamptz;
  v_stall  text;
BEGIN
  IF p_run IS NOT NULL THEN
    SELECT o.charge_limit_pct INTO v_limit FROM public.ottoq_owner_settings o
     WHERE o.sim_run_id = p_run AND o.vehicle_id = p_v.id AND o.kind = 'charge_limit' AND o.status = 'active';
    SELECT o.hold_until_sim INTO v_hold FROM public.ottoq_owner_settings o
     WHERE o.sim_run_id = p_run AND o.vehicle_id = p_v.id AND o.kind = 'hold' AND o.status = 'active';
    SELECT COALESCE(jsonb_agg(jsonb_build_object('service', o.service, 'name', c.display_name, 'when', o.service_when,
                                                 'setting_id', o.setting_id, 'command_id', o.command_id) ORDER BY o.service), '[]'::jsonb)
      INTO v_orders
      FROM public.ottoq_owner_settings o LEFT JOIN public.service_cadence_policy c ON c.svc = o.service
     WHERE o.sim_run_id = p_run AND o.vehicle_id = p_v.id AND o.kind = 'service' AND o.status = 'active';
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'service', a ->> 'svc', 'name', COALESCE(c.display_name, a ->> 'svc'),
             'status', COALESCE(a ->> 'status', 'pending'),
             'yours', COALESCE(jsonb_typeof(a -> 'owner_setting_ids') = 'array' AND jsonb_array_length(a -> 'owner_setting_ids') > 0, false))
             ORDER BY a ->> 'svc'), '[]'::jsonb)
      INTO v_open
      FROM (SELECT vn.atoms FROM public.ottoq_visit_needs vn
             WHERE vn.vehicle_id = p_v.id AND vn.sim_run_id = p_run AND vn.status IN ('open', 'in_progress')
             ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) w
      CROSS JOIN LATERAL jsonb_array_elements(w.atoms) a
      LEFT JOIN public.service_cadence_policy c ON c.svc = a ->> 'svc'
     WHERE COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled');
    SELECT max(l.planned_end_sim) INTO v_ready FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_run AND l.vehicle_id = p_v.id AND l.status IN ('planned', 'active');
  END IF;
  SELECT s.stall_code INTO v_stall FROM public.stalls s WHERE s.id = p_v.current_stall_id;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'vehicle_id', p_v.id, 'name', p_v.display_name, 'model', p_v.model,
    'state', p_v.current_state::text, 'state_phrase', public.ottoq_owner_state_phrase(p_v.current_state::text),
    'group', public.ottoq_owner_state_group(p_v.current_state::text),
    'stall', v_stall, 'soc', p_v.current_soc,
    'charge_target', LEAST(p_ceiling, COALESCE(v_limit, p_ceiling)),
    'open_services', COALESCE(v_open, '[]'::jsonb),
    'yours', jsonb_strip_nulls(jsonb_build_object(
               'charge_limit_pct', v_limit, 'hold_until_sim', v_hold,
               'hold_until_local', public.ottoq_owner_clock(v_hold, true, true),
               'orders', CASE WHEN jsonb_array_length(COALESCE(v_orders, '[]'::jsonb)) > 0 THEN v_orders END)),
    'ready_by_sim', v_ready, 'ready_by_local', public.ottoq_owner_clock(v_ready, true)));
END $function$;

REVOKE ALL ON FUNCTION public.ottoq_owner_car(vehicles, uuid, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_owner_clock(timestamptz, boolean, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_owner_state_phrase(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_owner_state_group(text) FROM PUBLIC;
