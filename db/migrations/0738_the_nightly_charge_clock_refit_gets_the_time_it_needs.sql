-- migration-version: PENDING
-- migration-name:    the_nightly_charge_clock_refit_gets_the_time_it_needs
--
-- 0738  **The nightly charge-clock refit gets the time it needs (G451).** Cron job 789 (ottoq-learn-charge-clock-nightly,
--       11:22 UTC) has failed three mornings running, 2026-10-15, -16 and -17, each cancelled at exactly two minutes by
--       the server's statement_timeout (120 s, from the configuration file; the job runs as postgres and sets none). It
--       took 96.7 s on 2026-10-13 and 115.4 s on 2026-10-14, then crossed the limit. So the depot's charge clock has stood
--       at fit 11 (2026-10-14 11:22 UTC) since, and every reader (the kernel's seating minutes, the agent's check, 0736's
--       promise) has used it. This gives the job its own statement_timeout of 15 minutes, as the sweep runner (783) and
--       the recert runner (746) carry theirs. Nothing else changes: the fit, its window and its schedule are as they were.
--
-- ══ APPLY AFTER ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Not before the comparison series that runs on fit 11 has finished: the arms of the windows of 2026-10-18 and
--   2026-10-19 (0733-0737's arms and 0732's seeds) pair with arms 82-88, which ran on fit 11, and the kernel's seating
--   reads the clock (G387), so a refit between them would put a second difference into every pair. The frozen clock has
--   cost nothing meanwhile: no charge at a tick of a minute or less, the only charges the fit learns from, has been
--   recorded at this depot since 2026-10-14, so a refit today would only reweight fit 11's own evidence. APPLY AT ONCE
--   instead if a live run records fine-tick charges before the series ends.
--
-- ══ WHY IT GREW (G451) ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_charge_time_v2_params_cut evaluates ottoq_charge_clock_who and ottoq_charge_minutes_estimate on every completed
--   charge in the 21-day window (about 40,000 on 2026-10-17) before it keeps the fine-tick ones (3,204 in fit 11). The
--   nightly sweeps add 1,000-4,500 coarse charges a night that the fit then sets aside, so its cost grows with the
--   research programme while its evidence does not. Measured read-only on the afternoon of 2026-10-17 (UTC), outside the
--   window and with no arm running: the params took between 68 s and about 90 s (the tool's 60 s limit cut the call; its
--   backend was still running at 68 s and gone at the next read). The longer fix, filtering coarse charges before the
--   clock functions run, changes the fit's code and
--   so its code_md5, and belongs in its own file with ottoq_charge_clock_trial run first.
--
-- ══ CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: job 789 is the job read on 2026-10-17 (command md5 f9c7a464, schedule '22 11 * * *',
--   active). P2: not already applied. V1: its command is the old one behind a statement_timeout of 15 minutes, its
--   schedule and its active flag unchanged.
--
-- ══ RECERT AND DIAL CLASSIFICATION ════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no engine body changes. The next fit it lets through is a new
--   fit_id, which the engine hash does not cover; G387 already names that a cross-day digest keys on the clock's fit.
--
-- ROLLBACK: SELECT cron.alter_job(789, command := 'SELECT public.ottoq_fit_charge_time_v2(''11111111-1111-1111-1111-111111111111''::uuid,
--   NULL, interval ''21 days'', 3, ''nightly'');'); DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0738_the_nightly_charge_clock_refit_gets_the_time_it_needs'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0738 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: job 789 as read on 2026-10-17 ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 789 AND jobname = 'ottoq-learn-charge-clock-nightly'
                    AND md5(command) = 'f9c7a464ea8ca2e0151ca4544c9fe1a9' AND schedule = '22 11 * * *' AND active) THEN
    RAISE EXCEPTION '0738 P1: cron job 789 is not the nightly charge-clock refit read on 2026-10-17 (command md5 f9c7a464)';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0738_the_nightly_charge_clock_refit_gets_the_time_it_needs') THEN
    RAISE EXCEPTION '0738 P2: already applied';
  END IF;
END $once$;

SELECT cron.alter_job(job_id := 789,
  command := 'SET statement_timeout = ''15min''; SELECT public.ottoq_fit_charge_time_v2(''11111111-1111-1111-1111-111111111111''::uuid, NULL, interval ''21 days'', 3, ''nightly'');');

-- ── V1: the old command behind its own timeout, the schedule and the active flag unchanged ──
DO $v1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 789 AND schedule = '22 11 * * *' AND active
                    AND command = 'SET statement_timeout = ''15min''; '
                                  || 'SELECT public.ottoq_fit_charge_time_v2(''11111111-1111-1111-1111-111111111111''::uuid, NULL, interval ''21 days'', 3, ''nightly'');') THEN
    RAISE EXCEPTION '0738 V1: job 789 is not the old command behind a 15-minute statement_timeout on its old schedule';
  END IF;
END $v1$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0738_the_nightly_charge_clock_refit_gets_the_time_it_needs', false, false,
  'Cron job 789 (the nightly charge-clock refit) runs behind its own statement_timeout of 15 minutes. No engine body '
  'changes.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
