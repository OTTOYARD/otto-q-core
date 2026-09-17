-- migration-version: 20260917122803
-- migration-name:    the_proposal_finalizer_accepts_the_kernel_tick_type
--
-- Live proof on Peak Turnover run 1ac6b6a4 showed 397 deterministic beats
-- aborted with SQLSTATE 42883. ottoq_decide_tick carries v_tick as bigint, but
-- 0333 created this helper with an integer tick argument. PostgreSQL does not
-- implicitly narrow bigint to integer during function resolution.

CREATE OR REPLACE FUNCTION public.ottoq_dispose_external_proposals(
  p_sim_run_id uuid,
  p_tick_seq bigint DEFAULT NULL,
  p_sim_clock timestamptz DEFAULT NULL,
  p_finalize boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_clock timestamptz;
  v_wall  timestamptz := clock_timestamp();
  v_n     integer := 0;
BEGIN
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, v_wall)
    INTO v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;
  v_clock := COALESCE(v_clock, p_sim_clock, v_wall);

  UPDATE public.ottoq_external_proposals p
     SET status = CASE
                    WHEN p_finalize THEN 'expired'
                    WHEN GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                                  p.created_at + interval '35 minutes') < v_wall THEN 'expired'
                    ELSE 'refused'
                  END,
         disposition_reason = CASE
           WHEN p_finalize THEN 'run_finalized'
           WHEN GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                         p.created_at + interval '35 minutes') < v_wall THEN 'ttl_elapsed'
           WHEN COALESCE(p.proposal->>'stall_id', '') !~
                '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
             THEN 'invalid_stall_id'
           WHEN NOT EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid)
             THEN 'stall_missing'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid
                AND s.current_vehicle_id IS NOT NULL)
             THEN 'stall_occupied'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid
                AND s.reserved_by IS NOT NULL
                AND s.reserved_by <> p.entity_id
                AND (s.reservation_expires_at IS NULL OR s.reservation_expires_at > v_clock))
             THEN 'stall_reserved'
           WHEN NOT EXISTS (
             SELECT 1 FROM public.stalls s
              JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.id = (p.proposal->>'stall_id')::uuid
                  AND c.station_state = 'Available')
             THEN 'charger_unavailable'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.id = (p.proposal->>'stall_id')::uuid
                  AND c.last_heartbeat_at < v_clock - interval '90 seconds')
             THEN 'charger_heartbeat_stale'
           ELSE 'target_no_longer_eligible'
         END,
         disposed_at = v_wall,
         disposed_tick = p_tick_seq
   WHERE p.sim_run_id = p_sim_run_id
     AND p.status = 'pending'
     AND (
       p_finalize
       OR GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                   p.created_at + interval '35 minutes') < v_wall
       OR (
         p.action_context = 'stall_assignment'
         AND (
           COALESCE(p.proposal->>'stall_id', '') !~
             '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
           OR NOT EXISTS (
             SELECT 1
               FROM public.stalls s
               JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
              WHERE s.id = CASE
                WHEN COALESCE(p.proposal->>'stall_id', '') ~
                     '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
                THEN (p.proposal->>'stall_id')::uuid
                ELSE NULL
              END
                AND s.current_vehicle_id IS NULL
                AND (s.reserved_by IS NULL OR s.reserved_by = p.entity_id
                     OR s.reservation_expires_at <= v_clock)
                AND c.station_state = 'Available'
                AND c.last_heartbeat_at >= v_clock - interval '90 seconds'
           )
         )
       )
     );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- Remove the bad overload after the correctly typed replacement exists. This
-- also keeps the stop path's NULL argument unambiguous at runtime.
DROP FUNCTION IF EXISTS public.ottoq_dispose_external_proposals(uuid,integer,timestamptz,boolean);

COMMENT ON FUNCTION public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean) IS
  '0336: closes pending proposals and accepts the bigint tick type used by ottoq_decide_tick.';

REVOKE ALL ON FUNCTION public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)
  TO service_role;

DO $assertions$
BEGIN
  IF to_regprocedure('public.ottoq_dispose_external_proposals(uuid,bigint,timestamp with time zone,boolean)') IS NULL THEN
    RAISE EXCEPTION '0336 A1: bigint finalizer is absent';
  END IF;
  IF to_regprocedure('public.ottoq_dispose_external_proposals(uuid,integer,timestamp with time zone,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION '0336 A2: narrowing integer overload remains';
  END IF;
  IF has_function_privilege('anon','public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)','EXECUTE')
     OR has_function_privilege('authenticated','public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)','EXECUTE') THEN
    RAISE EXCEPTION '0336 A3: finalizer privileges are not service-role-only';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name,forces_recert,note,classified_at)
VALUES ('0336_the_proposal_finalizer_accepts_the_kernel_tick_type',true,
  'Fixes a production-blocking function resolution failure that aborted every deterministic decision beat. Kernel output changes, so recertification is required.',now())
ON CONFLICT(name) DO NOTHING;
