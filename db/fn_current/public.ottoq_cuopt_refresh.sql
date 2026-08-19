-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 220ae5cf31f85929fd8dbf14e3be4537
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_refresh(p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run uuid; v_depot uuid; v_key text; v_req bigint; v_candidates int; v_last timestamptz; v_debounce int;
        v_t0 timestamptz := clock_timestamp();
        v_tick bigint; v_sim timestamptz; v_cand uuid[]; v_armed int := 0;
BEGIN
  IF current_setting('ottoq.dryrun', true) = 'on' THEN
    PERFORM public.cuopt_log_gate(p_sim_run_id, 'dryrun_mpc_fork', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;
  v_run := p_sim_run_id;
  IF v_run IS NULL THEN
    SELECT sim_run_id INTO v_run FROM ottoq_sim_runs
     WHERE status='running' AND COALESCE(run_by,'') <> 'production_live'
     ORDER BY started_at DESC LIMIT 1;
  END IF;
  IF v_run IS NULL THEN
    PERFORM public.cuopt_log_gate(NULL, 'no_running_run', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;

  -- DEBOUNCE (tunable). REAL domain on purpose: it throttles NVIDIA API spend,
  -- billed in real seconds, not sim seconds.
  v_debounce := GREATEST(1, ottoq_policy_get(v_run, 'cuopt_debounce_s', 2)::int);
  SELECT fired_at INTO v_last FROM ottoq_cuopt_fire_log WHERE sim_run_id = v_run;
  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => v_debounce) THEN
    PERFORM public.cuopt_log_gate(v_run, 'debounce', NULL,
      jsonb_build_object('debounce_s', v_debounce, 'last_fired_at', v_last), v_t0);
    RETURN NULL;
  END IF;

  SELECT depot_id, COALESCE(tick_count,0), COALESCE(sim_clock_current, now())
    INTO v_depot, v_tick, v_sim
    FROM ottoq_sim_runs WHERE sim_run_id = v_run;
  IF v_depot IS NULL THEN
    PERFORM public.cuopt_log_gate(v_run, 'no_depot', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;

  -- ==========================================================================
  -- CANDIDATE PREDICATE. This is the AUTHORITATIVE gate.
  -- Exclusions (a) reserved-by-greedy and (b) already-enacted-this-tick apply to
  -- the AT-GATE cohort only; the en-route cohort is DEFINED by holding a live
  -- non-DCFC reservation, so applying (a) to it would delete it entirely.
  -- CLOCK DOMAIN: reservation_expires_at is SIM-domain and MUST be compared to
  -- v_sim; tick_seq carries no clock at all.
  --
  -- P7 2026-08-03 — COHORT (2) TEMP STAGING, NEW. ottoq_decide_tick's own
  -- stall-assignment cursor assigns charge stalls to 'staged_awaiting_service'
  -- vehicles, and the edge function re-validates that exact state, but the gate
  -- never offered them, so cuOpt could not compete for a single one. Temp
  -- staging is the pressure valve for a decision that lands late -- precisely
  -- the population an optimiser should be re-planning. The predicate below is
  -- decide_tick's, unchanged: a free + healthy charge stall must exist, and the
  -- SoC envelope is the vehicle's own open visit target (else 85). This is
  -- PARITY, not a widening of eligibility: a vehicle outside decide_tick's
  -- envelope could never have had a cuOpt proposal enacted anyway.
  -- ==========================================================================
  SELECT COALESCE(array_agg(v.id), ARRAY[]::uuid[]), count(*)
    INTO v_cand, v_candidates
    FROM vehicles v
   WHERE v.home_depot_id = v_depot AND v.category='autonomous'
     AND ( (    v.current_state='arrived_at_gate' AND v.current_soc < 85
            AND NOT EXISTS (SELECT 1 FROM stalls s
                             WHERE s.reserved_by = v.id
                               AND s.stall_type::text IN ('dcfc','l2')
                               AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
            AND NOT EXISTS (SELECT 1 FROM ottoq_decisions dd
                             WHERE dd.sim_run_id      = v_run
                               AND dd.entity_type     = 'vehicle'
                               AND dd.entity_id       = v.id
                               AND dd.action_context  = 'stall_assignment'
                               AND dd.outcome_status  = 'enacted'
                               AND dd.tick_seq       >= v_tick) )
        OR (    v.current_state='staged_awaiting_service'
            AND v.current_stall_id IS NULL
            AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                                           WHERE vn.vehicle_id = v.id
                                             AND vn.status IN ('open','in_progress')
                                           ORDER BY vn.created_at DESC LIMIT 1), 85)
            AND EXISTS (SELECT 1 FROM stalls s2
                          JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                         WHERE s2.depot_id = v_depot
                           AND s2.stall_type::text IN ('dcfc','l2')
                           AND s2.current_vehicle_id IS NULL
                           AND c2.station_state = 'Available'
                           AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                                OR s2.reservation_expires_at <= v_sim))
            AND NOT EXISTS (SELECT 1 FROM ottoq_decisions dd
                             WHERE dd.sim_run_id      = v_run
                               AND dd.entity_type     = 'vehicle'
                               AND dd.entity_id       = v.id
                               AND dd.action_context  = 'stall_assignment'
                               AND dd.outcome_status  = 'enacted'
                               AND dd.tick_seq       >= v_tick) )
        OR ( v.current_state IN ('deployed','en_route_to_depot') AND v.current_soc < 45
             AND EXISTS (SELECT 1 FROM stalls s WHERE s.reserved_by = v.id
                           AND s.stall_type::text <> 'dcfc'
                           AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
             AND EXISTS (SELECT 1 FROM stalls s2
                           JOIN ottoq_ocpp_chargers ch ON ch.charger_id = s2.ocpp_charger_id
                          WHERE s2.depot_id = v_depot AND s2.stall_type::text='dcfc'
                            AND s2.status='available' AND s2.reserved_by IS NULL
                            AND ch.station_state='Available') ) );

  IF v_candidates = 0 THEN
    PERFORM public.cuopt_log_gate(v_run, 'sql_gate_no_candidates', 0, NULL, v_t0);
    RETURN NULL;
  END IF;

  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='ottoq_anon_key' LIMIT 1;
  IF v_key IS NULL THEN
    PERFORM public.cuopt_log_gate(v_run, 'no_anon_key_in_vault', v_candidates, NULL, v_t0);
    RETURN NULL;
  END IF;

  INSERT INTO ottoq_cuopt_fire_log (sim_run_id, fired_at) VALUES (v_run, now())
    ON CONFLICT (sim_run_id) DO UPDATE SET fired_at = now();

  -- SHIP THE INSTANCE. v_cand is the set just gated on and just armed a deferral
  -- for. The edge fn re-validates every id against the live world before posing
  -- it, so this pins IDENTITY, never eligibility.
  SELECT net.http_post(
    url := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-cuopt-propose',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key,'apikey',v_key),
    body := jsonb_build_object('sim_run_id', v_run,
                               'vehicle_ids', to_jsonb(v_cand),
                               'gate_tick', v_tick,
                               'gate_sim_clock', v_sim),
    timeout_milliseconds := 20000) INTO v_req;

  -- RIGHT OF FIRST REFUSAL. Armed only AFTER a solve was actually posted, so the
  -- greedy path is never held back for a call that never happened.
  BEGIN
    v_armed := public.ottoq_cuopt_defer_arm(v_run, v_tick, v_cand, v_req);
  EXCEPTION WHEN OTHERS THEN
    v_armed := -1;
    RAISE WARNING 'cuopt defer arm failed (non-fatal): %', SQLERRM;
  END;

  PERFORM public.cuopt_log_gate(v_run, NULL, v_candidates,
    jsonb_build_object('posted', true, 'net_request_id', v_req,
                       'gate_tick', v_tick, 'gate_sim_clock', v_sim,
                       'pinned_vehicle_ids', v_candidates,
                       'deferred_to_cuopt', v_armed), v_t0);
  RETURN v_req;
END;
$function$

