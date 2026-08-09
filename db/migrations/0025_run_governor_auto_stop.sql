-- migration-version: 20260809220000
-- migration-name:    run_governor_auto_stop
--
-- 0025_run_governor_auto_stop.sql
-- ============================================================================
-- RUN GOVERNOR: AUTO-STOP DEMO RUNS AT ≥139 SIM-MINUTES
-- ============================================================================
--
-- Demo runs at 60× speed generate heavy CPU load (rules engine, events,
-- telemetry). Once a run hits 139 sim-minutes (certification threshold),
-- continuing burns CPU for no value. This migration adds a database-level
-- auto-stop mechanism.
--
-- ══ DESIGN ══
-- Option B: a separate pg_cron job that polls for runs exceeding 139
-- sim-minutes and stops them. Cleanest separation — does not touch the
-- metronome (cron job 12 is the START engine and is sacred).
--
-- ══ WHAT THIS DOES ══
--   1. Creates public.ottoq_run_governor_auto_stop(): finds running demo
--      runs where sim_clock_current - sim_clock_start ≥ 139 minutes, sets
--      their status to 'aborted', and logs an ottoq_events row.
--   2. Creates a pg_cron job 'ottoq-run-governor' that calls it every
--      2 minutes.
--
-- ══ SAFETY POSTURE ══
--   * Only targets demo runs (COALESCE(run_by,'') NOT IN
--     ('production_live','cert_harness')) — same filter as the metronome.
--     Production and certification runs are never auto-stopped.
--   * Nothing dropped, nothing replaced. New function only.
--   * Cron job 12 is NOT read, written, altered, or disabled.
--   * The function returns the count of stopped runs (0 when idle) so the
--     cron log is informative without being noisy.

BEGIN;

-- ===========================================================================
-- (1) Create the governor function
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.ottoq_run_governor_auto_stop()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run      RECORD;
  v_stopped  integer := 0;
  v_dur_min  numeric;
BEGIN
  FOR v_run IN
    SELECT sim_run_id, sim_clock_start, sim_clock_current, depot_id,
           tick_count, scenario_code, run_by, status
      FROM public.ottoq_sim_runs
     WHERE status = 'running'
       AND COALESCE(run_by, '') NOT IN ('production_live', 'cert_harness')
       AND sim_clock_current - sim_clock_start >= interval '139 minutes'
  LOOP
    v_dur_min := EXTRACT(EPOCH FROM (v_run.sim_clock_current
                                     - v_run.sim_clock_start)) / 60.0;

    -- Stop the run
    UPDATE public.ottoq_sim_runs
       SET status    = 'aborted',
           ended_at  = now(),
           notes     = COALESCE(notes, '')
                       || format(' | auto-stopped by run_governor: %.1f sim-min (limit 139)',
                                 v_dur_min)
     WHERE sim_run_id = v_run.sim_run_id;

    -- Log the event through the canonical event recorder
    PERFORM public.ottoq_record_event(
      p_actor_type    := 'system',
      p_actor_id      := 'run_governor',
      p_event_type    := 'sim_run_auto_stopped',
      p_entity_type   := 'sim_run',
      p_entity_id     := v_run.sim_run_id,
      p_depot_id      := v_run.depot_id,
      p_payload       := jsonb_build_object(
                           'reason',               'run_governor_139_min_limit',
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

  RETURN v_stopped;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_run_governor_auto_stop() IS
  'Run governor: auto-stops demo runs that have reached ≥139 sim-minutes to prevent wasted CPU. Called by pg_cron job ottoq-run-governor every 2 minutes.';

-- ===========================================================================
-- (2) Create pg_cron job (idempotent — skip if already exists)
-- ===========================================================================
DO $cron$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-run-governor') THEN
    PERFORM cron.schedule(
      'ottoq-run-governor',
      '*/2 * * * *',
      $$SELECT public.ottoq_run_governor_auto_stop()$$
    );
  END IF;
END
$cron$;

COMMIT;