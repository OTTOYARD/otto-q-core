-- migration-version: 20260926122233
-- migration-name:    the_dial_runner_opens_and_closes_its_own_overnight_window
--
-- 0482  **The dial runner opens and closes its own overnight window.** `db/checks/0361` §1, §10.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The dial experiment runner (cron 755, every 10 minutes) runs one pair per call only while the global dial
--   `dial_experiment_runner_enabled` is 1, no run is live and the canon is certified. Its first night (2026-09-26,
--   3:00-6:00 AM CT) was opened and closed by hand, and the close at 11:00:49 UTC was a one-shot reminder. Nothing
--   opens it again: the replication 0480 registered would wait for a human. Pairs block every other cron job while
--   they run (G141), so the window belongs in the hours nobody is using the twin, and it should not depend on anyone
--   being awake.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Two pg_cron jobs, through the setter like every other dial write: `ottoq_dial_window_open` sets the gate to 1 at
--   08:00 UTC and `ottoq_dial_window_close` sets it to 0 at 11:00 UTC, daily. pg_cron runs in UTC, so the window is
--   3:00-6:00 AM CDT while daylight time lasts and 2:00-5:00 AM CST after 2026-11-01. Everything the runner already
--   refuses stays refused: a live run, a canon below its floor, the recertification runner holding the world. With
--   no active experiment the runner does nothing, so an open window costs nothing on a night with no question.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   Scheduling only. No function changes.

BEGIN;

-- ── P0: no pair in flight ──
-- Scheduling only, but the apply path itself takes a lock on supabase_migrations.schema_migrations that a running
-- pair holds a share lock on (it reads the recert floor), so without this an apply queues behind the pair until the
-- client gives up. It did, once, for this very file (G194's shape).
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0482 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the runner still reads this gate, and neither job exists yet ──
DO $premises$
BEGIN
  IF position($x$ottoq_policy_get(NULL, 'dial_experiment_runner_enabled', 0)$x$
              IN pg_get_functiondef('public.ottoq_dial_experiment_runner()'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0482 P2: the dial runner no longer reads dial_experiment_runner_enabled';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname IN ('ottoq_dial_window_open', 'ottoq_dial_window_close')) THEN
    RAISE EXCEPTION '0482 P2: a dial window job already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 755 AND active
                  AND command ILIKE '%ottoq_dial_experiment_runner()%') THEN
    RAISE EXCEPTION '0482 P2: cron 755 is not the active dial runner';
  END IF;
END $premises$;

SELECT cron.schedule('ottoq_dial_window_open', '0 8 * * *',
  $cmd$SELECT public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'dial_experiment_runner_enabled', 1, 'dial_window_cron:open')$cmd$);
SELECT cron.schedule('ottoq_dial_window_close', '0 11 * * *',
  $cmd$SELECT public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'dial_experiment_runner_enabled', 0, 'dial_window_cron:close')$cmd$);

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_set jsonb;
BEGIN
  -- V1: both jobs, active, on their schedules, writing the gate through the setter.
  IF (SELECT count(*) FROM cron.job WHERE jobname = 'ottoq_dial_window_open' AND schedule = '0 8 * * *' AND active
         AND command ILIKE '%dial_experiment_runner_enabled'', 1, ''dial_window_cron:open'')%') <> 1
     OR (SELECT count(*) FROM cron.job WHERE jobname = 'ottoq_dial_window_close' AND schedule = '0 11 * * *' AND active
         AND command ILIKE '%dial_experiment_runner_enabled'', 0, ''dial_window_cron:close'')%') <> 1 THEN
    RAISE EXCEPTION '0482 V1: the window jobs are not what this file schedules';
  END IF;
  -- V2: the setter accepts the write the open job makes, and the runner then reads 1 (undone at once).
  BEGIN
    v_set := public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid,
                                     'dial_experiment_runner_enabled', 1, 'dial_window_cron:open');
    IF NOT COALESCE((v_set->>'ok')::boolean, false)
       OR public.ottoq_policy_get(NULL, 'dial_experiment_runner_enabled', 0) <> 1 THEN
      RAISE EXCEPTION '0482 V2: the setter refused the open write, or the runner would not read it: %', v_set;
    END IF;
    RAISE EXCEPTION 'undo_0482_v2';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'undo_0482_v2' THEN RAISE; END IF;
  END;
END $verify$;

-- Rollback: SELECT cron.unschedule('ottoq_dial_window_open'); SELECT cron.unschedule('ottoq_dial_window_close');

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0482_the_dial_runner_opens_and_closes_its_own_overnight_window', false,
  'Scheduling only: two pg_cron jobs set dial_experiment_runner_enabled to 1 at 08:00 UTC and 0 at 11:00 UTC.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
