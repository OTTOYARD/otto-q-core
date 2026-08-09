-- MIGRATION: 0033_reservation_gc.sql
-- Garbage-collect stale stall reservations so capacity counting is accurate.
-- P1-9: 54 reservations from July 28 were still blocking stalls 13 days later.

CREATE OR REPLACE FUNCTION public.ottoq_gc_stale_reservations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_count int;
BEGIN
  WITH cleared AS (
    UPDATE stalls s
       SET reserved_by = NULL,
           reserved_at = NULL,
           reservation_expires_at = NULL
     WHERE s.reserved_by IS NOT NULL
       AND (
         (s.reservation_expires_at IS NOT NULL AND s.reservation_expires_at < now())
         OR NOT EXISTS (
           SELECT 1 FROM ottoq_sim_runs r
           WHERE r.depot_id = s.depot_id AND r.status = 'running'
         )
       )
     RETURNING id
  )
  SELECT count(*) INTO v_count FROM cleared;
  
  RETURN jsonb_build_object('cleared', v_count);
END;
$fn$;
