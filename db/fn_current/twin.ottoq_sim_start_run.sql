-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: a8454174d97ad2466320c22ed341f8ae
CREATE OR REPLACE FUNCTION twin.ottoq_sim_start_run(p_scenario_code text, p_sim_clock_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_time_scale numeric DEFAULT NULL::numeric, p_random_seed bigint DEFAULT NULL::bigint, p_run_by text DEFAULT 'otto_twin'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_scenario   ottoq_scenarios%ROWTYPE;
  v_run_id     UUID := gen_random_uuid();
  v_clock_start TIMESTAMPTZ;
  v_clock_end  TIMESTAMPTZ;
  v_time_scale NUMERIC;
  v_seed       BIGINT;
  v_active_id  UUID;
  v_active_by  TEXT;
  v_deployed   INT;
  v_primed     INT := 0;
BEGIN
  SELECT * INTO v_scenario FROM ottoq_scenarios
   WHERE scenario_code = p_scenario_code AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OTTOQ_SCENARIO_NOT_FOUND: %', p_scenario_code USING ERRCODE = 'P0001';
  END IF;
  -- ONE WORLD, ONE MOVER. vehicles/stalls are global and unscoped, so a second
  -- ticking run would advance the same rows from a different clock. Checked
  -- before anything is written, so a refused start leaves no partial run behind.
  IF public.ottoq_policy_get(NULL, 'allow_concurrent_runs', 0) < 1 THEN
    SELECT sim_run_id, run_by INTO v_active_id, v_active_by
      FROM ottoq_sim_runs
     WHERE status = 'running'
       AND COALESCE(run_by, '') NOT IN ('production_live', 'cert_harness')
     ORDER BY started_at DESC LIMIT 1;
    IF v_active_id IS NOT NULL THEN
      RAISE EXCEPTION 'OTTOQ_RUN_ALREADY_ACTIVE: run % (started by %) is still moving this depot. The world is shared, so a second run would fight it for every vehicle. Watch the live run instead, or stop it first.', v_active_id, COALESCE(v_active_by,'unknown') USING ERRCODE = 'P0001';
    END IF;
  END IF;

  v_clock_start := COALESCE(p_sim_clock_start, date_trunc('day', NOW()) + INTERVAL '6 hours');
  v_clock_end   := v_clock_start + (v_scenario.sim_duration_minutes || ' minutes')::INTERVAL;
  v_time_scale  := COALESCE(p_time_scale, v_scenario.default_time_scale);
  v_seed        := COALESCE(p_random_seed, v_scenario.random_seed);

  INSERT INTO ottoq_sim_runs (
    sim_run_id, scenario_id, scenario_code, started_at, last_tick_at, next_tick_due_at,
    sim_clock_start, sim_clock_current, sim_clock_end,
    time_scale, tick_interval_seconds, depot_id, random_seed, status, run_by
  ) VALUES (
    v_run_id, v_scenario.scenario_id, v_scenario.scenario_code, NOW(), NULL, NOW(),
    v_clock_start, v_clock_start, v_clock_end,
    v_time_scale, v_scenario.tick_interval_seconds, v_scenario.depot_id, v_seed, 'running', p_run_by
  );

  -- COLD START. A torn-down world is all-offline, and nothing in the demo tick
  -- path deploys an offline vehicle, so without this the run can never move.
  -- Guarded on the whole fleet being parked: if anything is already deployed,
  -- this run is joining a world in motion and must not disturb it.
  SELECT count(*) INTO v_deployed FROM vehicles WHERE current_state = 'deployed'::vehicle_state;
  IF v_deployed = 0 THEN
    v_primed := twin.ottoq_sim_prime_deployment(
      v_run_id, v_clock_start,
      public.ottoq_policy_get(NULL, 'run_start_deployed_fraction', 0.55));
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type    := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type    := 'twin.sim_run_started', p_entity_type := 'sim_run', p_entity_id := v_run_id,
    p_depot_id      := v_scenario.depot_id,
    p_payload       := jsonb_build_object(
                        'scenario_code', p_scenario_code, 'category', v_scenario.category,
                        'sim_duration_minutes', v_scenario.sim_duration_minutes,
                        'time_scale', v_time_scale, 'random_seed', v_seed,
                        'sim_clock_start', v_clock_start, 'sim_clock_end', v_clock_end,
                        'cold_start', (v_deployed = 0), 'primed_vehicles', v_primed),
    p_severity      := 'info',
    p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := v_run_id
  );
  RETURN v_run_id;
END;
$function$

