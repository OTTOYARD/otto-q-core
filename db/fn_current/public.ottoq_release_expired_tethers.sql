-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: e94a3f04180f68e02a456a0448fbbc1a
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

