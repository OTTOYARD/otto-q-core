-- migration-version: 20260927111501
-- migration-name:    the_dial_window_closes_before_its_last_pair_could_outlast_it
--
-- 0522  **G247: the dial window's close and the dial runner fired in the same minute, so the runner could start a
--       pair as the window closed, and that pair ran into the morning. The close now comes at 10:41 UTC, after the
--       runner's last start at 10:40 and before its next at 10:50, so the last pair of a night ends by about 10:58.**
--       `db/checks/0389` §4.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   0482 closes the gate (`dial_experiment_runner_enabled` to 0) at `0 11 * * *`, and the runner (cron 755) fires at
--   `*/10 * * * *`, so both start at 11:00:00. On 2026-09-27 the close job started at 11:00:00.244 and committed by
--   .496, and the runner started at .252 and called the runner function at .262; it read the gate before the close
--   had committed, saw 1, and ran a pair from 11:00 while the gate read 0 -- one more pair, and one of the
--   charge-window experiment's runs 15-18 minutes. A pair holds the world lock and starves every other cron job while it runs (G141), so a morning run started
--   at 6 AM CT would sit frozen behind it. The window was meant to be over by 6 AM CT (0482 §2), and a race decided
--   whether it was.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Moves `ottoq_dial_window_close` from `0 11 * * *` to `41 10 * * *` (5:41 AM CDT, 4:41 AM CST). 41 is not a minute
--   the runner fires on, so the two can no longer race, and it follows the runner's last start of the night (10:40),
--   whose pair -- at most 18 minutes on the night's longest experiment -- ends by about 10:58, inside the window. The
--   command is unchanged: it only ever writes 0. The open job (761, inactive since 0485) is left as it is.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   Scheduling only. No function changes.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0522 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the two jobs as 0482 left them ──
DO $premises$
BEGIN
  IF (SELECT count(*) FROM cron.job WHERE jobname = 'ottoq_dial_window_close' AND schedule = '0 11 * * *' AND active
         AND command ILIKE '%dial_experiment_runner_enabled'', 0, ''dial_window_cron:close'')%') <> 1 THEN
    RAISE EXCEPTION '0522 P2: the close job is not the one 0482 scheduled at 0 11 * * *';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 755 AND active AND schedule = '*/10 * * * *'
                  AND command ILIKE '%ottoq_dial_experiment_runner()%') THEN
    RAISE EXCEPTION '0522 P2: cron 755 is not the dial runner firing every 10 minutes';
  END IF;
END $premises$;

SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'ottoq_dial_window_close'), schedule := '41 10 * * *');

DO $verify$
BEGIN
  -- V1: the close job on its new minute, active, its command unchanged; the runner untouched; and the close no longer
  --     on a minute the runner fires on.
  IF (SELECT count(*) FROM cron.job WHERE jobname = 'ottoq_dial_window_close' AND schedule = '41 10 * * *' AND active
         AND command ILIKE '%dial_experiment_runner_enabled'', 0, ''dial_window_cron:close'')%') <> 1
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 755 AND active AND schedule = '*/10 * * * *')
     OR 41 % 10 = 0 THEN
    RAISE EXCEPTION '0522 V1: the close job is not where this file puts it';
  END IF;
END $verify$;

-- Rollback: SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'ottoq_dial_window_close'), schedule := '0 11 * * *');

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0522_the_dial_window_closes_before_its_last_pair_could_outlast_it', false,
  'Scheduling only: the dial window close moves from 11:00 to 10:41 UTC, off the runner''s minutes, so no pair starts '
  'as the window closes and the last pair of a night ends inside it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
