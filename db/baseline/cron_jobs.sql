-- GENERATED / SNAPSHOT FILE — DO NOT EDIT. Changes go in db/migrations/.
-- ---------------------------------------------------------------------------
-- Snapshot of the live otto-q-core brain (Supabase gxdrcyphqjzjsuhxuqtg).
-- Nothing reads this file at runtime. Editing it changes NOTHING about the
-- running system. To change the brain: add a numbered file in db/migrations/,
-- apply it per scripts/APPLYING.md, then re-export this baseline.
-- Baseline date: 2026-08-04 (export captured 2026-08-03; verified live 2026-08-04).
-- ---------------------------------------------------------------------------

-- ============================================================================
-- OTTO-Q-CORE  |  Supabase project gxdrcyphqjzjsuhxuqtg
-- pg_cron SCHEDULED JOBS  (cron.job)  -- REFERENCE ONLY
-- ----------------------------------------------------------------------------
-- Read-only snapshot of cron.job at export time (2026-08-03). Extension pg_cron
-- 1.6.4, installed in schema pg_catalog. 5 jobs: 4 active, 1 inactive.
-- All jobs run as nodename=localhost, database=postgres, username=postgres.
-- To recreate a job:  SELECT cron.schedule('<jobname>', '<schedule>', $$<command>$$);
-- ============================================================================


-- jobid 2  | jobname: ottoq-twin-ingest-weekly | active: true
-- schedule: 0 4 * * 0   (04:00 every Sunday)
SELECT cron.schedule('ottoq-twin-ingest-weekly', '0 4 * * 0', $$SELECT ottoq_twin_ingest_refresh()$$);


-- jobid 10 | jobname: ottoq-depot-tick | active: true
-- schedule: */2 * * * *   (every 2 minutes -- the live world-advance heartbeat)
SELECT cron.schedule('ottoq-depot-tick', '*/2 * * * *', $$SELECT public.ottoq_cron_tick()$$);


-- jobid 11 | jobname: ottoq-retention-nightly | active: true
-- schedule: 0 8 * * *   (08:00 daily -- background purge of high-volume log tables)
SELECT cron.schedule('ottoq-retention-nightly', '0 8 * * *', $$CALL public.ottoq_retention_purge_worker(90, 2000, '48 hours', ARRAY['ottoq_events','ottoq_rule_evaluations','ottoq_incident_reports']);$$);


-- jobid 12 | jobname: ottoq-demo-metronome | active: true
-- schedule: * * * * *   (every minute -- server-side demo world clock)
-- NOTE: this job IS the START engine for the twin. Never disable it.
SELECT cron.schedule('ottoq-demo-metronome', '* * * * *', $$CALL public.ottoq_demo_metronome(50)$$);


-- jobid 13 | jobname: ottoq-cert-battery | active: FALSE   <-- NEW since 2026-07-13
-- schedule: * * * * *   (every minute when enabled -- steps the certification battery)
-- Currently INACTIVE (active=false); it is armed manually for a cert run.
SELECT cron.schedule('ottoq-cert-battery', '* * * * *', $$SET statement_timeout = 0; SELECT public.ottoq_cert_battery_step();$$);
-- SELECT cron.alter_job(13, active := false);   -- live state at export time
