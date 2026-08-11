-- MIGRATION: 0042_cleanup_orphan_data.sql
-- Clean up orphan data in the database that is not associated with existing simulation runs.
-- This migration targets:
-- 1. ottoq_events with sim_run_id IS NULL (117K+ rows)
-- 2. Orphaned rows in ottoq_rule_evaluations, ottoq_vehicle_commands, ottoq_stall_bookings 
--    where sim_run_id does not exist in ottoq_sim_runs
-- 3. Adds safeguard to prevent future NULL sim_run_id events through a CHECK constraint
--
-- This migration is safe: it only deletes rows with no run association and never touches 
-- data from existing sim_runs.

-- Verify the orphan counts before deletion
DO $$
DECLARE
  v_orphan_events_count int;
  v_orphan_evaluations_count int;
  v_orphan_commands_count int;
  v_orphan_bookings_count int;
BEGIN
  -- Count orphan events (sim_run_id IS NULL)
  SELECT count(*) INTO v_orphan_events_count FROM ottoq_events WHERE sim_run_id IS NULL;
  RAISE NOTICE 'Found % orphan events with sim_run_id IS NULL', v_orphan_events_count;
  
  -- Count orphan rule evaluations
  SELECT count(*) INTO v_orphan_evaluations_count 
  FROM ottoq_rule_evaluations e
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = e.sim_run_id);
  RAISE NOTICE 'Found % orphan rule evaluations', v_orphan_evaluations_count;
  
  -- Count orphan vehicle commands
  SELECT count(*) INTO v_orphan_commands_count 
  FROM ottoq_vehicle_commands c
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = c.sim_run_id);
  RAISE NOTICE 'Found % orphan vehicle commands', v_orphan_commands_count;
  
  -- Count orphan stall bookings
  SELECT count(*) INTO v_orphan_bookings_count 
  FROM ottoq_stall_bookings b
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = b.sim_run_id);
  RAISE NOTICE 'Found % orphan stall bookings', v_orphan_bookings_count;
END $$;

-- Delete orphan events (sim_run_id IS NULL)
DELETE FROM ottoq_events WHERE sim_run_id IS NULL;
RAISE NOTICE 'Deleted % orphan events with sim_run_id IS NULL', (SELECT count(*) FROM pg_notify('notice', 'events deleted') WHERE false);

-- Delete orphan rule evaluations (sim_run_id references non-existent run)
DELETE FROM ottoq_rule_evaluations 
WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = ottoq_rule_evaluations.sim_run_id);
RAISE NOTICE 'Deleted orphan rule evaluations with non-existent sim_run_id';

-- Delete orphan vehicle commands (sim_run_id references non-existent run)
DELETE FROM ottoq_vehicle_commands 
WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = ottoq_vehicle_commands.sim_run_id);
RAISE NOTICE 'Deleted orphan vehicle commands with non-existent sim_run_id';

-- Delete orphan stall bookings (sim_run_id references non-existent run)
DELETE FROM ottoq_stall_bookings 
WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = ottoq_stall_bookings.sim_run_id);
RAISE NOTICE 'Deleted orphan stall bookings with non-existent sim_run_id';

-- Add a CHECK constraint to prevent future NULL sim_run_id events
-- This ensures data integrity moving forward
ALTER TABLE ottoq_events 
ADD CONSTRAINT ottoq_events_sim_run_id_not_null_check 
CHECK (sim_run_id IS NOT NULL) NOT VALID;

-- Create an index on sim_run_id for better performance on future queries
-- This will help with the performance of queries that filter by sim_run_id
CREATE INDEX IF NOT EXISTS idx_ottoq_events_sim_run_id ON ottoq_events(sim_run_id);

-- Verify the cleanup results
DO $$
DECLARE
  v_remaining_orphan_events int;
  v_remaining_orphan_evaluations int;
  v_remaining_orphan_commands int;
  v_remaining_orphan_bookings int;
BEGIN
  -- Verify no more orphan events with NULL sim_run_id
  SELECT count(*) INTO v_remaining_orphan_events FROM ottoq_events WHERE sim_run_id IS NULL;
  RAISE NOTICE 'Remaining orphan events with sim_run_id IS NULL: %', v_remaining_orphan_events;
  
  -- Verify no more orphan rule evaluations
  SELECT count(*) INTO v_remaining_orphan_evaluations 
  FROM ottoq_rule_evaluations e
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = e.sim_run_id);
  RAISE NOTICE 'Remaining orphan rule evaluations: %', v_remaining_orphan_evaluations;
  
  -- Verify no more orphan vehicle commands
  SELECT count(*) INTO v_remaining_orphan_commands 
  FROM ottoq_vehicle_commands c
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = c.sim_run_id);
  RAISE NOTICE 'Remaining orphan vehicle commands: %', v_remaining_orphan_commands;
  
  -- Verify no more orphan stall bookings
  SELECT count(*) INTO v_remaining_orphan_bookings 
  FROM ottoq_stall_bookings b
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = b.sim_run_id);
  RAISE NOTICE 'Remaining orphan stall bookings: %', v_remaining_orphan_bookings;
  
  -- Final verification
  IF v_remaining_orphan_events = 0 AND v_remaining_orphan_evaluations = 0 
     AND v_remaining_orphan_commands = 0 AND v_remaining_orphan_bookings = 0 THEN
    RAISE NOTICE 'Orphan data cleanup completed successfully';
  ELSE
    RAISE WARNING 'Orphan data cleanup partially completed. Some orphaned records remain.';
  END IF;
END $$;
