-- migration-version: PENDING
-- migration-name:    the_demo_metronome_ticks_through_the_whole_minute
--
-- 0768  **The demo metronome ticks through the whole minute.** (G487)
--       Chase, 2026-10-23 at about 11:40 PM CT: "I need you to fix and give short answers why, if anything. Otherwise
--       just build to completion as needed."
--
-- ══ §1 WHY (db/checks/0461 §6 (b), run 78c0624c, read-only on live 03:28-04:17 UTC) ═════════════════════════════════
--
--   pg_cron starts public.ottoq_demo_metronome every minute (job ottoq-demo-metronome, `CALL ottoq_demo_metronome(50)`).
--   It ticks for its 50-second budget and returns, so every minute has a 10-12 s gap with no tick: 50 gaps over 8 s in
--   3,432 s of run 78c0624c, 564 s in all (16.4%). Live playback advances the next tick by the real time since the last,
--   so the run loses no sim time, only grain: the twin app stands still for those seconds, then that tick moves the world
--   35-54 sim-seconds at once instead of about 20. A 57-second budget leaves about 3 s.
--   A run that is still going when the next minute fires does not overlap it: pg_cron runs one instance of a job at a
--   time, and "if a second instance is triggered before the first finishes, it's queued and starts as soon as the first
--   one completes" (pg_cron README, https://github.com/citusdata/pg_cron, read 2026-10-24). Each tick commits on its own,
--   so nothing else waits longer than one tick for the run's row, as today.
--
-- ══ §2 WHAT CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The job's command, 50 -> 57. Nothing else: the metronome's body, its ceiling guard (statement_timeout), its stops and
--   its cadence floor are untouched. The metronome never ticks a production session or a certification arm (it skips
--   run_by 'production_live' and 'cert_harness').
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 exactly one job named ottoq-demo-metronome, every minute, `CALL
--   public.ottoq_demo_metronome(50)`. P2 not already applied. V1 the job reads `CALL public.ottoq_demo_metronome(57)`,
--   every minute, still active. Executed by tests/test_metronome_budget_sql.py.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═══════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE, forces_dial_restart FALSE: certification arms and dial pairs are run by their own harnesses,
--   which the metronome skips.
--
-- ROLLBACK: SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'ottoq-demo-metronome'),
--             command := 'CALL public.ottoq_demo_metronome(50)');
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0768_the_demo_metronome_ticks_through_the_whole_minute'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0768 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the job as read ──
DO $p1$
BEGIN
  IF (SELECT count(*) FROM cron.job WHERE jobname = 'ottoq-demo-metronome') <> 1
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-demo-metronome' AND schedule = '* * * * *'
                       AND command = 'CALL public.ottoq_demo_metronome(50)') THEN
    RAISE EXCEPTION '0768 P1: ottoq-demo-metronome is not the one job, every minute, CALL public.ottoq_demo_metronome(50)';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0768_the_demo_metronome_ticks_through_the_whole_minute') THEN
    RAISE EXCEPTION '0768 P2: already applied';
  END IF;
END $once$;

SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'ottoq-demo-metronome'),
                      command := 'CALL public.ottoq_demo_metronome(57)');

-- ── V1: the job as changed ──
DO $v1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-demo-metronome' AND schedule = '* * * * *'
                    AND command = 'CALL public.ottoq_demo_metronome(57)' AND active) THEN
    RAISE EXCEPTION '0768 V1 FAILED: ottoq-demo-metronome is not every minute, active, CALL public.ottoq_demo_metronome(57)';
  END IF;
END $v1$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0768_the_demo_metronome_ticks_through_the_whole_minute', false, false,
        'G487. The ottoq-demo-metronome job''s budget 50 -> 57 s, so a live twin run rests about 3 s a minute, not 10-12 '
        '(run 78c0624c: 564 s of 3,432 with no tick, 16.4%; the tick after each rest moved the world 35-54 sim-s). '
        'pg_cron queues a run that comes due while the last is going, so runs never overlap. The metronome skips '
        'certification arms and production sessions.',
        now());

COMMIT;
