CREATE OR REPLACE FUNCTION twin.ottoq_sim_auto_dispatch_tick(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE; v_scenario ottoq_sim_scenarios%ROWTYPE;
  v_hour INTEGER; v_dispatch_mult NUMERIC := 1.0; v_target_deployed_pct NUMERIC := 0.90;
  v_total_fleet INTEGER; v_currently_deployed INTEGER; v_desired_deployed INTEGER;
  v_to_dispatch INTEGER; v_vehicle RECORD; v_count INTEGER := 0; v_seed BIGINT;
  v_recall_on boolean; v_win_start int; v_win_end int; v_hyst int; v_holdout_pct int;
  v_to_recall int; v_cap int; v_recalled int := 0;
  v_sec RECORD; v_eta numeric;
  v_release_cap int; v_valved int := 0; v_forced boolean;
  v_plan jsonb;
  -- 2026-08-11: the tick's OWN elapsed sim-minutes, resolved once and handed to BOTH
  -- phases of ottoq_plan_dispatch_tick. The recall phase already received it; the
  -- deploy phase did not, so the callee fell back to its 30-minute DEFAULT and any
  -- tick-length scaling on the release cap was inert by construction.
  v_tick_min numeric;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- Byte-for-byte the expression the recall call below already used. Kept as one
  -- variable so the two phases can never disagree about how long this tick was.
  v_tick_min := COALESCE((v_run.payload->>'tick_minutes_actual')::numeric,
                         (v_run.tick_interval_seconds::numeric * COALESCE(v_run.time_scale,1))/60.0,
                         30);

  -- ══════════════ 0019: THE IN-DEPOT PATH FOR A RIDER FLAG ══════════════
  -- A flag that comes due while the car is PARKED can never reach
  -- public.ottoq_evaluate_return_need, because that function reads an ACTIVE
  -- dispatch and returns should_return=false when there is none. A parked car
  -- does not need recalling -- it needs the atom put on the visit it is already
  -- having. This runs BEFORE the deploy cursor below, so a flag that matures
  -- this tick becomes must_do work this tick and the same tick's dispatcher
  -- then declines to send the car out. Self-silencing: it must never cost the
  -- depot a dispatch.
  BEGIN
    PERFORM ottoq.ottoq_rider_flag_indepot_sweep(p_sim_run_id, v_run.depot_id, p_sim_clock_now);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rider flag in-depot sweep failed safely: % %', SQLSTATE, SQLERRM;
  END;

  SELECT s.* INTO v_scenario FROM ottoq_sim_scenarios s
   WHERE s.scenario_code = COALESCE(v_run.scenario_code, 'normal_day') LIMIT 1;
  IF v_scenario.scenario_code IS NULL THEN
    SELECT * INTO v_scenario FROM ottoq_sim_scenarios WHERE scenario_code = 'normal_day';
  END IF;
  v_dispatch_mult       := COALESCE((v_scenario.fleet_overrides->>'dispatch_rate_multiplier')::numeric, 1.0);
  v_target_deployed_pct := COALESCE((v_scenario.fleet_overrides->>'target_deployed_fraction')::numeric, 0.90);

  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_seed := abs(hashtextextended(COALESCE(v_run.random_seed, 42)::text || p_sim_clock_now::text || 'disp', 7));

  SELECT COUNT(*) INTO v_total_fleet FROM vehicles
   WHERE category = 'autonomous' AND home_depot_id = v_run.depot_id;
  SELECT COUNT(*) INTO v_currently_deployed
    FROM ottoq_vehicle_dispatches
   WHERE sim_run_id = p_sim_run_id AND status IN ('active', 'returning');

  v_desired_deployed := FLOOR(v_total_fleet * ottoq_deploy_target_fraction(
      v_hour, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction', v_target_deployed_pct)) * v_dispatch_mult);

  v_to_dispatch := GREATEST(0, v_desired_deployed - v_currently_deployed);

  -- (1) DEPLOY toward the target. OTTO-Q ranks and paces; the twin departs them.
  IF v_to_dispatch > 0 THEN
    v_plan := ottoq_plan_dispatch_tick(
                'deploy_plan', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                p_hour := v_hour, p_seed := v_seed, p_to_dispatch := v_to_dispatch,
                p_tick_minutes_actual := v_tick_min);
    v_release_cap := COALESCE((v_plan->>'cap')::int, 1);
    v_forced      := COALESCE((v_plan->>'forced')::boolean, false);

    FOR v_vehicle IN
      SELECT t.value::uuid AS id
        FROM jsonb_array_elements_text(COALESCE(v_plan->'release','[]'::jsonb)) WITH ORDINALITY AS t(value, ord)
       ORDER BY t.ord
    LOOP
      -- 0019: count a dispatch only when one actually happened. The refusal in
      -- twin.ottoq_sim_dispatch_vehicle returns NULL, and an emit event that
      -- counted refusals as departures would be a false number.
      IF ottoq_sim_dispatch_vehicle(v_vehicle.id, p_sim_run_id, p_sim_clock_now) IS NOT NULL THEN
        v_count := v_count + 1;
      END IF;
    END LOOP;

    IF jsonb_array_length(COALESCE(v_plan->'hold','[]'::jsonb)) > 0 THEN
      v_valved := COALESCE((ottoq_plan_dispatch_tick(
                    'deploy_hold', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                    p_vehicles := v_plan->'hold', p_forced := v_forced)->>'held')::int, 0);
    END IF;

    IF v_valved > 0 THEN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'rush_valve',
        p_event_type := 'twin.rush_valve_hold', p_entity_type := 'system',
        p_payload := jsonb_build_object('held', v_valved, 'released', v_count,
          'cap', v_release_cap, 'forced', v_forced, 'hour_cst', v_hour),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := p_sim_run_id);
    END IF;

    IF v_count > 0 THEN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'twin_auto_dispatcher',
        p_event_type := 'twin.auto_dispatch_emit', p_entity_type := 'system',
        p_payload := jsonb_build_object('count', v_count, 'hour_cst', v_hour, 'scenario', v_scenario.scenario_code,
          'total_fleet', v_total_fleet, 'desired', v_desired_deployed, 'deployed', v_currently_deployed),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- (2) OVERNIGHT SURPLUS RECALL. Twin measures the surplus (a demand fact) and
  -- applies the world writes; OTTO-Q ranks it and secures the appointments.
  v_recall_on   := ottoq_policy_get(p_sim_run_id,'overnight_recall_enabled',1) > 0;
  v_win_start   := ottoq_policy_get(p_sim_run_id,'overnight_recall_start_hour',22)::int;
  v_win_end     := ottoq_policy_get(p_sim_run_id,'overnight_recall_end_hour',3)::int;
  v_hyst        := ottoq_policy_get(p_sim_run_id,'overnight_recall_hysteresis',2)::int;
  v_holdout_pct := ottoq_policy_get(p_sim_run_id,'overnight_holdout_pct',1)::int;

  IF v_recall_on AND (v_hour >= v_win_start OR v_hour < 6) THEN
    v_to_recall := GREATEST(0, v_currently_deployed - v_desired_deployed - v_hyst);
    IF v_to_recall > 0 THEN
      v_plan := ottoq_plan_dispatch_tick(
                  'recall', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                  p_hour := v_hour, p_to_recall := v_to_recall, p_holdout_pct := v_holdout_pct,
                  p_win_start := v_win_start, p_win_end := v_win_end,
                  p_tick_minutes_actual := v_tick_min);
      v_cap := COALESCE((v_plan->>'cap')::int, 0);

      FOR v_sec IN
        SELECT t.value AS d
          FROM jsonb_array_elements(COALESCE(v_plan->'secured','[]'::jsonb)) WITH ORDINALITY AS t(value, ord)
         ORDER BY t.ord
      LOOP
        v_eta := (v_sec.d->>'eta_minutes')::numeric;
        UPDATE ottoq_vehicle_dispatches
           SET status='returning', return_trigger='surplus_to_demand',
               returning_started_at = p_sim_clock_now,
               return_eta_minutes = v_eta,
               scheduled_return_at = p_sim_clock_now + (v_eta || ' minutes')::interval,
               return_evidence = jsonb_build_object('decided_at',p_sim_clock_now,
                 'soc_at_decision',(v_sec.d->>'soc_at_decision')::int,'hour_cst',v_hour,
                 'reason','overnight_surplus_to_demand','appointment',v_sec.d->'appointment',
                 'desired_deployed',v_desired_deployed,'currently_deployed',v_currently_deployed)
         WHERE dispatch_id = (v_sec.d->>'dispatch_id')::uuid;
        UPDATE vehicles SET current_state='en_route_to_depot'::vehicle_state, last_state_change=p_sim_clock_now
         WHERE id = (v_sec.d->>'vehicle_id')::uuid;
        v_recalled := v_recalled + 1;
      END LOOP;

      IF v_recalled > 0 THEN
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='overnight_recall',
          p_event_type:='twin.overnight_surplus_recall', p_entity_type:='system',
          p_payload:=jsonb_build_object('recalled',v_recalled,'hour_cst',v_hour,
            'desired',v_desired_deployed,'deployed_before',v_currently_deployed,'cap',v_cap,
            'holdout_active', NOT (v_hour >= v_win_end AND v_hour < v_win_start)),
          p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
      END IF;
    END IF;
  END IF;

  RETURN v_count;
END;
$function$
;
