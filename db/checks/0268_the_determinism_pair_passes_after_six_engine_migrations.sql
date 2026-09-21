-- 0268  THE DETERMINISM PAIR PASSES AFTER SIX ENGINE MIGRATIONS IN ONE NIGHT.
--
-- Read-only. The validation that mattered most, run the moment the twin depot was
-- free. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
--
-- Six migrations touched the decide path tonight, five of them `forces_recert TRUE`:
-- 0367 (the reclaimer, wired into the path the metronome actually calls), 0368 (the
-- reroute's stall-type inference), 0369 (the unbacked-orphan release class), 0370 (the
-- standing-contradiction detector, a per-tick write), 0371 (removing 0367's own
-- `SKIP LOCKED`), 0372 (charger health in the shared candidate source). Plus 0364's
-- capture trigger and 0373's comments.
--
-- **If the fourteen-atom byte-identical property did not survive that, everything
-- above it is worthless** — 2.9a calls reproducibility a product property and records
-- that R-12 established most of this field cannot claim it at all.
--
--   ottoq_determinism_pair(171717, 12, 'busy_day', '11111111-…', '2026-09-01 02:00:00+00', 900)
--   fired 2026-09-20 05:17:00 UTC, finished 05:18:50, **110.5 s**
--
--   arm A  c7cac134-d391-4c30-9632-d2130f365148  12 ticks  validation_status **passed**
--   arm B  73c51088-8949-4d62-a58a-62f8dc344b05  12 ticks  validation_status **passed**
--   both started_at 05:17:00.064792 — the same instant, because the pair runs both
--   arms in ONE transaction, which is the common-random-numbers engine 0145 identified
--
--   ottoq_twin_determinism_verdict(A, B):
--     ticks_compared            12
--     ticks_identical           **12**
--     ticks_divergent            0
--     only_in_a / only_in_b      0 / 0
--     **deterministic          true**
--     first_divergence_sim_min   NULL
--
-- **0371 IS THE ONE THIS TESTED.** 0367 introduced `FOR UPDATE … SKIP LOCKED` into a
-- function that runs inside `ottoq_sim_decide_and_dispatch` on every tick of every
-- arm, which makes the candidate set depend on who else held a row at that instant.
-- 0371 removed it and replaced it with an unlocked, deterministic selection in
-- ascending id order. This pair is the evidence that the replacement is both
-- deterministic (12 of 12) and deadlock-free — and the 1,260-tick demo run that
-- preceded it logged **zero** `ottoq.reservation_reclaim_blocked` events, which is the
-- other half: the alarm 0367 installed never fired, so the reclaimer neither
-- deadlocked nor fell silent across 1,260 ticks.
--
-- ONE NUMBER NOT TO OVER-READ: 110.5 s for a 12-tick pair, against the ~535 s
-- `scripts/schedule-round.sql` records post-0222 and ~755 s before it. The world was
-- freshly reset and the depot had just been purged, so this is not evidence that the
-- pair got four times faster — it is one timing on an unusually clean world. The
-- schedule-round lookback exists precisely because a single fast outlier must not be
-- allowed to tighten a round's slots.

SELECT r.sim_run_id::text, r.status, r.run_by, r.tick_count, r.validation_status,
       r.started_at::text
  FROM public.ottoq_sim_runs r
 WHERE r.run_by = 'cert_harness'
 ORDER BY r.started_at DESC LIMIT 4;

SELECT * FROM public.ottoq_twin_determinism_verdict(
  'c7cac134-d391-4c30-9632-d2130f365148',
  '73c51088-8949-4d62-a58a-62f8dc344b05');

-- The job row, kept because its shape is the trap that fooled my first watcher:
-- `status='succeeded'` with `return_message='SET'` and ~1 s appears while the job is
-- STILL RUNNING, because the command is two statements and the row reflects the first.
-- The real row reads 110.5 s and `return_message='1 row'`. `scripts/schedule-round.sql`
-- documents this and says to discard anything under 60 s; I read that header an hour
-- before writing a watcher that ignored it, saw succeeded/SET/0.7 s, and unscheduled
-- the job mid-flight. Nothing was lost — `cron.unschedule` removes the definition, not
-- the running backend — but the watcher would have reported a pass that had not
-- happened, which is the worst class of false report this repo can produce.
SELECT d.jobid, d.status, d.start_time::text, d.end_time::text,
       round(EXTRACT(epoch FROM (d.end_time - d.start_time))::numeric, 1) AS secs,
       left(COALESCE(d.return_message,''), 40) AS return_message
  FROM cron.job_run_details d
 WHERE d.jobid = 737
 ORDER BY d.start_time DESC LIMIT 2;
