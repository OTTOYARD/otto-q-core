-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 3725c0c2ceb218ee9d124719c19238b5
CREATE OR REPLACE FUNCTION public.ottoq_run_governor_auto_stop()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run       RECORD;
  v_stopped   integer := 0;
  v_dur_min   numeric;
  v_stale_min numeric;
  v_ceiling   integer;
BEGIN
  ---------------------------------------------------------------------------
  -- 1. THE CEILING. How far a run may travel.
  ---------------------------------------------------------------------------
  FOR v_run IN
    SELECT sim_run_id, sim_clock_start, sim_clock_current, depot_id,
           tick_count, scenario_code, run_by, status
      FROM public.ottoq_sim_runs
     WHERE status = 'running'
       AND COALESCE(run_by, '') NOT IN ('production_live', 'cert_harness')
       -- ONE HOME FOR THE CEILING. This was a bare 139-minute interval literal --
       -- the hard limit on any cron-driven run, discoverable only by reading this
       -- body. NOTE: you cannot escape this by claiming the run_by exemption above,
       -- because the metronome that ticks runs exempts the SAME two values -- an
       -- exempt run never advances at all.
       AND sim_clock_current - sim_clock_start
           >= make_interval(mins => GREATEST(1, public.ottoq_policy_get(
                sim_run_id, 'run_governor_max_sim_minutes', 139))::int)
  LOOP
    v_dur_min := EXTRACT(EPOCH FROM (v_run.sim_clock_current
                                     - v_run.sim_clock_start)) / 60.0;
    v_ceiling := GREATEST(1, public.ottoq_policy_get(
                   v_run.sim_run_id, 'run_governor_max_sim_minutes', 139))::int;

    PERFORM public.ottoq_sim_stop_and_reset(v_run.sim_run_id,
             format('run_governor: reached the %s sim-minute ceiling', v_ceiling));

    PERFORM public.ottoq_record_event(
      p_actor_type    := 'system',
      p_actor_id      := 'run_governor',
      p_event_type    := 'sim_run_auto_stopped',
      p_entity_type   := 'sim_run',
      p_entity_id     := v_run.sim_run_id,
      p_depot_id      := v_run.depot_id,
      p_payload       := jsonb_build_object(
                           'reason',               'run_governor_sim_minute_ceiling',
                           'ceiling_sim_minutes',   v_ceiling,
                           'sim_clock_start',       v_run.sim_clock_start,
                           'sim_clock_current',     v_run.sim_clock_current,
                           'sim_duration_minutes',  round(v_dur_min, 1),
                           'tick_count',            v_run.tick_count,
                           'scenario_code',         v_run.scenario_code,
                           'run_by',                v_run.run_by
                         ),
      p_severity      := 'info',
      p_ingest_source := 'system',
      p_data_source   := 'twin',
      p_sim_run_id    := v_run.sim_run_id
    );

    v_stopped := v_stopped + 1;
  END LOOP;

  ---------------------------------------------------------------------------
  -- 2. THE STALL WATCHDOG. How long a run may fail to travel.
  --
  -- Deliberately measured against now() and NOT the sim clock. The sim clock is
  -- the thing that stops moving when a run dies, so testing it against itself
  -- can never detect the failure -- that is precisely how a deadlocked run
  -- stayed 'running' for eight hours. last_tick_at is wall-clock and keeps
  -- advancing in reality whether or not the world does.
  --
  -- COALESCE to started_at so a run that dies before its very first tick is
  -- caught too, rather than being immortal for want of a last_tick_at.
  ---------------------------------------------------------------------------
  FOR v_run IN
    SELECT sim_run_id, sim_clock_start, sim_clock_current, depot_id,
           tick_count, scenario_code, run_by, last_tick_at, started_at
      FROM public.ottoq_sim_runs
     WHERE status = 'running'
       AND COALESCE(run_by, '') NOT IN ('production_live', 'cert_harness')
       AND now() - COALESCE(last_tick_at, started_at)
           >= make_interval(mins => GREATEST(2, public.ottoq_policy_get(
                sim_run_id, 'run_stall_timeout_minutes', 10))::int)
  LOOP
    v_stale_min := EXTRACT(EPOCH FROM (now()
                     - COALESCE(v_run.last_tick_at, v_run.started_at))) / 60.0;

    PERFORM public.ottoq_sim_stop_and_reset(v_run.sim_run_id,
             format('run_governor: STALLED -- no tick for %s real minutes',
                    round(v_stale_min, 1)));

    PERFORM public.ottoq_record_event(
      p_actor_type    := 'system',
      p_actor_id      := 'run_governor',
      p_event_type    := 'sim_run_stalled',
      p_entity_type   := 'sim_run',
      p_entity_id     := v_run.sim_run_id,
      p_depot_id      := v_run.depot_id,
      p_payload       := jsonb_build_object(
                           'reason',                'run_governor_stall_timeout',
                           'stalled_real_minutes',   round(v_stale_min, 1),
                           'last_tick_at',           v_run.last_tick_at,
                           'sim_clock_current',      v_run.sim_clock_current,
                           'tick_count',             v_run.tick_count,
                           'scenario_code',          v_run.scenario_code,
                           'run_by',                 v_run.run_by
                         ),
      -- ERROR, not info. A run that hit its ceiling finished; this one broke.
      p_severity      := 'error',
      p_ingest_source := 'system',
      p_data_source   := 'twin',
      p_sim_run_id    := v_run.sim_run_id
    );

    v_stopped := v_stopped + 1;
  END LOOP;

  RETURN v_stopped;
END;
$function$

