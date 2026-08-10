-- MIGRATION: 0037_purge_orphans.sql
-- P2-10: The purge function only cleans children of runs that STILL EXIST
-- in ottoq_sim_runs. When a run is deleted (not purged), its children are
-- stranded forever: 4 commands + 113,474 events orphaned as of 2026-08-10.
--
-- This migration adds an orphan sweep that runs after the normal purge:
-- delete children whose parent sim_run_id no longer exists in ottoq_sim_runs.

CREATE OR REPLACE FUNCTION public.ottoq_purge_orphan_rows(
  p_max_rows int DEFAULT 10000,
  p_safety_days int DEFAULT 7  -- only purge orphans older than N days
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
DECLARE
  v_cutoff timestamptz := now() - (p_safety_days || ' days')::interval;
  v_deleted_events int := 0;
  v_deleted_commands int := 0;
  v_deleted_decisions int := 0;
BEGIN
  -- Delete orphan events (children of non-existent runs), oldest first
  WITH batch AS (
    SELECT id FROM ottoq_events e
    WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = e.sim_run_id)
      AND e.created_at < v_cutoff
    LIMIT p_max_rows
  )
  DELETE FROM ottoq_events WHERE id IN (SELECT id FROM batch);
  GET DIAGNOSTICS v_deleted_events = ROW_COUNT;

  -- Delete orphan commands, oldest first
  WITH batch AS (
    SELECT id FROM ottoq_vehicle_commands c
    WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = c.sim_run_id)
      AND c.issued_at < v_cutoff
    LIMIT p_max_rows
  )
  DELETE FROM ottoq_vehicle_commands WHERE id IN (SELECT id FROM batch);
  GET DIAGNOSTICS v_deleted_commands = ROW_COUNT;

  -- Delete orphan decisions
  WITH batch AS (
    SELECT id FROM ottoq_decisions d
    WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = d.sim_run_id)
    LIMIT p_max_rows
  )
  DELETE FROM ottoq_decisions WHERE id IN (SELECT id FROM batch);
  GET DIAGNOSTICS v_deleted_decisions = ROW_COUNT;

  RETURN jsonb_build_object(
    'deleted_events', v_deleted_events,
    'deleted_commands', v_deleted_commands,
    'deleted_decisions', v_deleted_decisions,
    'remaining_orphans', (
      SELECT count(*) FROM ottoq_events e
      WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = e.sim_run_id)
    )
  );
END;
$fn$;
