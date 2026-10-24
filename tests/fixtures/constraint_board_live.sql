-- tests/fixtures/constraint_board_live.sql — the live public.ottoq_agent_board(uuid), for
-- tests/test_depot_constraint_sql.py.
--
-- Its body is the live one, read from gxdrcyphqjzjsuhxuqtg on 2026-10-24 at 18:28:04 UTC (1:28 PM CT) and copied byte
-- for byte (prosrc md5 cc155a31209fd8e89260028d24a9715f); its header is pg_get_functiondef's. The test asserts the md5
-- against the pin db/migrations/0783's P1 reads. The miniature depot it is loaded into does not hold every function the
-- board reads, so the test runs the board with stand-ins for the sections it gates on.
CREATE OR REPLACE FUNCTION public.ottoq_agent_board(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fx0783$
DECLARE v_run RECORD; v_depot uuid; v_clock timestamptz; v_board jsonb;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count, scenario_code, random_seed
    INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.depot_id IS NULL THEN RETURN NULL; END IF;
  v_depot := v_run.depot_id; v_clock := v_run.sim_clock_current;

  SELECT jsonb_build_object(
    'sim_clock', v_clock, 'tick', v_run.tick_count, 'scenario', v_run.scenario_code,
    'fleet', (SELECT jsonb_object_agg(current_state, n) FROM (
        SELECT current_state, count(*) n FROM vehicles
        WHERE home_depot_id = v_depot AND category='autonomous' GROUP BY 1) f),
    'inbound_60m', (SELECT count(*) FROM vehicles v JOIN ottoq_vehicle_dispatches d ON d.vehicle_id = v.id
        WHERE v.home_depot_id = v_depot AND v.current_state='en_route_to_depot'
          AND d.actual_return_at IS NULL AND d.scheduled_return_at <= v_clock + interval '60 minutes'
          AND d.sim_run_id = p_sim_run_id),  --: 0709: this run's cars, not every run's
    'needs', jsonb_build_object(
      'open_visits_by_urgency', (SELECT jsonb_object_agg(urgency, n) FROM (
          SELECT urgency, count(*) n FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status IN ('open','in_progress') GROUP BY 1) u),
      'pending_atoms', (SELECT jsonb_object_agg(svc, n) FROM (
          SELECT a->>'svc' svc, count(*) n FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
          WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
            AND COALESCE(a->>'status','pending') = 'pending' GROUP BY 1 ORDER BY n DESC LIMIT 8) p),
      'carryovers', (SELECT count(*) FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status='carried_over' AND created_at > now() - interval '1 day')),
    'flow', jsonb_build_object(
      'legs', (SELECT jsonb_object_agg(status, n) FROM (
          SELECT status, count(*) n FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id GROUP BY 1) l),
      'avg_abs_deviation_min', (SELECT round(avg(abs(deviation_s))/60.0,1) FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id AND deviation_s IS NOT NULL),
      'amendments_recent', (SELECT count(*) FROM ottoq_decisions
          WHERE sim_run_id = p_sim_run_id AND resolved_action_context='itinerary_amended'
            AND sim_clock > v_clock - interval '2 hours')),
    'energy', jsonb_build_object(
      'site', (SELECT jsonb_build_object('grid_kw', round(COALESCE(building_load_kw,0)+COALESCE(total_ev_charging_kw,0)-COALESCE(solar_generation_kw,0)),
                       'ev_kw', round(COALESCE(total_ev_charging_kw,0)), 'solar_kw', round(COALESCE(solar_generation_kw,0)))
          FROM site_energy_snapshots WHERE depot_id = v_depot AND sim_run_id = p_sim_run_id
          ORDER BY timestamp DESC LIMIT 1),
      'bess', (SELECT jsonb_build_object('soc', current_soc_pct, 'power_kw', current_power_kw)
          FROM ottoq_bess_units WHERE depot_id = v_depot LIMIT 1),
      'bess_plan', (SELECT reason FROM ottoq_energy_commands
          WHERE COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
            AND depot_id = v_depot AND command_type='bess_setpoint_kw'
          ORDER BY issued_at DESC, tick_seq DESC NULLS LAST, command_id DESC LIMIT 1),
      'forecast_charge_kw_60m', (SELECT round(COALESCE(predicted_charge_kw,0))
          FROM public.ottoq_arrival_forecast(v_depot, v_clock, p_sim_run_id, 60))),  --: 0766 (G485): read, not recorded
    'approvals_pending', (SELECT jsonb_object_agg(approval_type, n) FROM (
        SELECT approval_type, count(*) n FROM ottoq_ops_approvals
        WHERE depot_id = v_depot AND status='pending' GROUP BY 1) a),
    'exceptions', (SELECT count(*) FROM vehicles
        WHERE home_depot_id = v_depot AND current_state IN ('tow_requested','emergency_staged')),
    'assignment_last_tick', (SELECT jsonb_object_agg(outcome_status, n) FROM (
        SELECT outcome_status, count(*) n FROM ottoq_decisions
        WHERE sim_run_id = p_sim_run_id AND tick_seq = v_run.tick_count
          AND action_context='stall_assignment' GROUP BY 1) o),
    'policy', jsonb_build_object(
      'deploy_peak_fraction', ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',  --: 0432: the dispatcher's own default
        COALESCE((SELECT (s.fleet_overrides->>'target_deployed_fraction')::numeric FROM ottoq_sim_scenarios s
                   WHERE s.scenario_code = COALESCE(v_run.scenario_code,'normal_day') LIMIT 1), 0.90)),
      'energy_demand_factor_peak', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_peak',0.50),
      'energy_demand_factor_expensive', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_expensive',0.35))
  ) INTO v_board;

  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_review_enabled',0),0) >= 1 THEN
    v_board := v_board || jsonb_build_object('review', public.ottoq_agent_review(p_sim_run_id, 3));
  END IF;

  --: 0350. THE PER-ASSET HALF, gated and concatenated for the identical reason
  --: 0342 gated the return leg: at the default of 0 the board is byte-identical
  --: to its pre-0350 self, so no certification arm moves (A1 asserts it).
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_asset_depth_enabled',0),0) >= 1 THEN
    v_board := v_board || public.ottoq_agent_asset_depth(p_sim_run_id, v_depot, v_clock, 10, 10);
  END IF;

  --: 0432. THE GROUNDING HALF -- what is true now, the agent's own last writes and changes, the
  --: service queue, resources, energy limits, recent flow, and the work side's demand as read-only.
  --: Gated and CONCATENATED like 0342/0350: at the default of 0 the key is absent, not present-and-null.
  --: ottoq_agentic_arm sets it to 1 on every armed run.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_board_grounding_enabled',0),0) >= 1 THEN
    v_board := v_board || jsonb_build_object('grounding',
                 public.ottoq_agent_board_grounding(p_sim_run_id, v_depot, v_clock));
  END IF;

  --: 0614. THE CHARGE LINE, so the agent can order it. Gated and concatenated like 0342/0350/0432: at the
  --: default of 0 the key is absent, and a baseline seat never carries it.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_charge_order',0),0) >= 1
     AND COALESCE(ottoq_policy_get(p_sim_run_id,'proposer_seat',0),0) = 0 THEN
    v_board := v_board || jsonb_build_object('charge_queue',
                 public.ottoq_agent_charge_queue_board(p_sim_run_id, v_depot, v_clock));
  END IF;

  --: 0629. A PRODUCTION SESSION SAYS SO. The agent is armed there and proposes; every write under its name to a setting
  --: the session reads is refused (ottoq_policy_set, production_never_self_tunes, CLAUDE.md rule 10). The board says it
  --: first, so the agent does not spend its moves on dials. Absent on every other run, so a twin board is unchanged.
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id AND r.run_by = 'production_live') THEN
    v_board := v_board || jsonb_build_object('production', jsonb_build_object(
      'live', true,
      'dials', 'read_only',
      'note', 'A production session with real vehicles. You propose; the kernel disposes. No set_policy or ops_action '
              'reaches this session: every write under your name is refused (production_never_self_tunes). Your charge '
              'order and your solver objective are proposals the kernel checks before it takes them.'));
  END IF;

  --: 0704. THE SCOUTS. What the deterministic per-vehicle scouts found on this run (ottoq_vehicle_scouts_digest).
  --: Gated on grounding like 0432, so an unarmed board (every certification arm) is byte-identical.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_board_grounding_enabled',0),0) >= 1
     AND COALESCE(ottoq_policy_get(p_sim_run_id,'agent_scouts_enabled',1),1) >= 1 THEN
    v_board := v_board || jsonb_build_object('scouts', public.ottoq_vehicle_scouts_digest(p_sim_run_id, 10));
  END IF;

  RETURN v_board;
END; $fx0783$;
