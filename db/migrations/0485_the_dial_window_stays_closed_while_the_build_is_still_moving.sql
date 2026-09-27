-- migration-version: 20260926143555
-- migration-name:    the_dial_window_stays_closed_while_the_build_is_still_moving
--
-- 0485  **The dial window stays closed while the build is still moving.** Chase, 2026-09-26: hold off on major testing
--       until everything is built out, because constant changes invalidate earlier runs.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0482 opens the dial experiment runner's gate every night at 08:00 UTC (3:00 AM CDT) and closes it at 11:00 UTC.
--   With the gate open, the runner (cron 755) runs a determinism pair every 10 minutes for the active experiment, and
--   its promoter can change a depot dial on the result. Two things make that the wrong thing to run now:
--     - G219 is about to change busy_day itself. The battery will drain gradually while a car is out instead of in
--       one step at the gate, and the cert and A/B harnesses will run busy_day's own template. An experiment run on
--       tonight's world measures a world that is being replaced, and a promotion made from it would outlive its
--       evidence.
--     - Each pair blocks every other cron job while it runs (G141). That is three hours of pairs a night for results
--       the next build invalidates.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Deactivates `ottoq_dial_window_open` (cron 761), so the gate is not opened. The close job (762) stays: it only
--   ever writes 0. The runner and the registered experiment (0480's replication `82c5568b`) are left as they are, so
--   the loop resumes by reactivating one job. The recert runner (cron 746) is untouched: it re-certifies the canon
--   after a forcing change, which is the basic check that a change breaks nothing.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   Scheduling only. No function changes.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0485 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the open job is 0482's, active, and the gate is closed now ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 761 AND jobname = 'ottoq_dial_window_open' AND active
                    AND command ILIKE '%dial_experiment_runner_enabled'', 1, ''dial_window_cron:open'')%') THEN
    RAISE EXCEPTION '0485 P2: cron 761 is not 0482''s active window opener';
  END IF;
  IF public.ottoq_policy_get(NULL, 'dial_experiment_runner_enabled', 0) <> 0 THEN
    RAISE EXCEPTION '0485 P2: the dial runner''s gate is open right now';
  END IF;
END $premises$;

SELECT cron.alter_job(761, active := false);

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
BEGIN
  -- V1: the opener is inactive, the closer and the runner are as they were.
  IF (SELECT active FROM cron.job WHERE jobid = 761)
     OR NOT (SELECT active FROM cron.job WHERE jobid = 762 AND jobname = 'ottoq_dial_window_close')
     OR NOT (SELECT active FROM cron.job WHERE jobid = 755 AND command ILIKE '%ottoq_dial_experiment_runner()%') THEN
    RAISE EXCEPTION '0485 V1: the dial jobs are not what this file leaves';
  END IF;
  -- V2: the recert runner is untouched.
  IF NOT (SELECT active FROM cron.job WHERE jobid = 746 AND jobname = 'ottoq-recert-runner') THEN
    RAISE EXCEPTION '0485 V2: the recert runner is not active';
  END IF;
END $verify$;

-- Rollback: SELECT cron.alter_job(761, active := true);

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0485_the_dial_window_stays_closed_while_the_build_is_still_moving', false,
  'Scheduling only: cron 761 (the nightly dial window opener) is deactivated until the build settles.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
