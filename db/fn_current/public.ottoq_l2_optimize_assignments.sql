-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: c99394c4cbd7436574e7a17b02dbc348
CREATE OR REPLACE FUNCTION public.ottoq_l2_optimize_assignments(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_n int := 0; v_veh RECORD; v_stall_id uuid; v_stall_type text; v_conn_max numeric;
  v_used uuid[] := ARRAY[]::uuid[];
BEGIN
  -- fresh start each tick: clear this run's prior local proposals (avoid stale accumulation)
  DELETE FROM ottoq_external_proposals
   WHERE sim_run_id = p_sim_run_id AND source = 'greedy_constrained' AND action_context = 'stall_assignment';

  FOR v_veh IN
    SELECT v.id, v.current_soc, v.target_soc, v.inlet_type, v.inlet_max_kw, v.fleet_operator_id
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate' AND v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 0.5
       -- FR-3: yield to a fresh cuOpt proposal for this vehicle (cuOpt owns it this tick)
       AND NOT EXISTS (
         SELECT 1 FROM ottoq_external_proposals p
          WHERE p.sim_run_id = p_sim_run_id AND p.action_context = 'stall_assignment'
            AND p.entity_type = 'vehicle' AND p.entity_id = v.id
            AND p.source = 'cuopt' AND p.status = 'pending'
            AND COALESCE(p.expires_at, p.created_at + interval '35 minutes') >= now())
     ORDER BY v.current_soc ASC, v.id              -- urgency: most depleted vehicle picks first
  LOOP
    SELECT s.id, s.stall_type, s.connector_max_kw
      INTO v_stall_id, v_stall_type, v_conn_max
      FROM stalls s
      JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type IN ('dcfc','l2')
       AND s.current_vehicle_id IS NULL
       AND NOT (s.id = ANY(v_used))
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= now())
       AND c.station_state = 'Available'
       AND c.last_heartbeat_at >= p_sim_clock - INTERVAL '90 seconds'
       AND ( v_veh.inlet_type IS NULL
          OR s.connector_type = v_veh.inlet_type
          OR (s.connector_type = 'Multi' AND v_veh.inlet_type = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
          OR (s.connector_type = 'NACS'  AND v_veh.inlet_type IN ('NACS','Tesla_Proprietary')) )
     ORDER BY
       -- DCFC FIRST, L2 OVERFLOW. Lower score wins. The fast plug scores 0 for
       -- every vehicle; L2 carries a penalty large enough that no amount of
       -- distance advantage can outbid a free fast plug. L2 is therefore only
       -- ever chosen when no DCFC stall survives the filters above.
       ( CASE WHEN s.stall_type = 'dcfc' THEN 0
              ELSE ottoq_policy_get(p_sim_run_id, 'l2_overflow_penalty', 100) END )
       + COALESCE(s.distance_from_entrance, 50) * 0.1
     ASC
     LIMIT 1;

    IF v_stall_id IS NULL THEN CONTINUE; END IF;
    v_used := array_append(v_used, v_stall_id);

    INSERT INTO ottoq_external_proposals
      (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal, source, status, created_at, expires_at)
    VALUES (p_sim_run_id, p_depot_id, 'stall_assignment', 'vehicle', v_veh.id,
      jsonb_build_object('abstain', false, 'resolved_action_context', 'stall_assignment', 'verb', 'assign_stall',
        'vehicle_id', v_veh.id, 'stall_id', v_stall_id, 'stall_type', v_stall_type,
        'requested_kw', ROUND((LEAST(COALESCE(v_conn_max,50), COALESCE(v_veh.inlet_max_kw,250))
            * CASE WHEN COALESCE(v_conn_max,50) <= 50 THEN 1.0
                   WHEN v_veh.current_soc < 55 THEN 0.85 WHEN v_veh.current_soc < 75 THEN 0.55 ELSE 0.30 END)::numeric, 1),
        'l2_engine', 'greedy_constrained',
        'rationale', jsonb_build_object('soc', v_veh.current_soc, 'optimizer', 'greedy_constrained', 'inlet', v_veh.inlet_type)),
      'greedy_constrained', 'pending', now(), now() + INTERVAL '120 seconds');
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$

