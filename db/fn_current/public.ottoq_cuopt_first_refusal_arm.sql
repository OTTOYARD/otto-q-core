-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 31bfaa66111ebdda51189cef543f709c
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_first_refusal_arm(p_sim_run_id uuid, p_tick bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_sim timestamptz; v_cap int; v_ids uuid[]; v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;

  -- STARVATION BOUND + OFF SWITCH, both policy-tunable per run.
  v_cap := GREATEST(0, ottoq_policy_get(p_sim_run_id, 'cuopt_first_refusal_max_defers', 1)::int);
  IF v_cap = 0 THEN RETURN 0; END IF;

  SELECT depot_id, COALESCE(sim_clock_current, now()) INTO v_depot, v_sim
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  SELECT COALESCE(array_agg(v.id), ARRAY[]::uuid[]) INTO v_ids
    FROM vehicles v
   WHERE v.home_depot_id = v_depot
     AND v.category = 'autonomous'
     -- Zone A/outside-the-walls only. Mirrors ottoq_cuopt_defer_arm's own guard.
     AND v.current_state = 'arrived_at_gate'
     AND v.current_stall_id IS NULL
     AND v.current_soc < 85
     -- greedy has already reserved a charge stall for it => nothing left to optimise
     AND NOT EXISTS (SELECT 1 FROM stalls s
                      WHERE s.reserved_by = v.id
                        AND s.stall_type::text IN ('dcfc','l2')
                        AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
     -- THE BOUND: never hold a vehicle that is already armed/spent, and never
     -- more than v_cap times in the whole run.
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_cuopt_deferrals d
                      WHERE d.sim_run_id = p_sim_run_id AND d.vehicle_id = v.id
                        AND (d.state <> 'clear' OR d.defer_count >= v_cap))
     -- cuOpt has already answered for this vehicle => let the cursor enact it now
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_external_proposals p
                      WHERE p.sim_run_id     = p_sim_run_id
                        AND p.action_context = 'stall_assignment'
                        AND p.entity_type    = 'vehicle'
                        AND p.entity_id      = v.id
                        AND p.status         = 'pending'
                        AND p.source IN ('cuopt','cuopt_fallback'));

  IF v_ids IS NULL OR array_length(v_ids,1) IS NULL THEN RETURN 0; END IF;

  v_n := public.ottoq_cuopt_defer_arm(p_sim_run_id, p_tick, v_ids, NULL);

  BEGIN
    PERFORM public.cuopt_log_gate(
      p_sim_run_id, 'first_refusal_arm', array_length(v_ids,1),
      jsonb_build_object('armed', v_n, 'offered', array_length(v_ids,1),
                         'tick', p_tick, 'max_defers', v_cap),
      clock_timestamp(), 'p7_first_refusal');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- Fail OPEN: a ledger hiccup must never change how the engine assigns.
  RAISE WARNING 'ottoq_cuopt_first_refusal_arm: % (run=%, tick=%)', SQLERRM, p_sim_run_id, p_tick;
  RETURN 0;
END;
$function$

