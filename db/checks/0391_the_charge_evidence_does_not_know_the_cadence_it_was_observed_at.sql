-- 0391  **G248: the charge-duration evidence ledger does not record the cadence a charge was observed at, and its
--       reader does not ask. An operator run in fixed playback advances 30 sim-minutes a tick, so every charge on it
--       starts and ends on a half-hour and its length is known to 30 minutes, and the next fit of the charge window
--       would read it beside charges observed at half a minute.**
--
--       Written on 2026-09-27 (11:20 UTC, 6:20 AM CT). Read-only.
--
--       How it was found: the first attempt at this morning's validation run, 11f15672, was started with
--       `ottoq_sim_run_scenario` alone. A run started that way has no `playback_mode`, so the metronome ticks it at the
--       fixed 30 sim-minutes (`tick_interval_seconds` 30 x `time_scale` 60) instead of the live cadence the cockpit sets
--       with `ottoq_set_playback(run, 'live', 8)`. It was stopped after 7 ticks and restarted as 929e323c with both in one
--       transaction. The 7 ticks were enough for the capture trigger (0514) to file 6 charges from it.

-- ══ §1 THE LEDGER, RUN BY RUN: PLAYBACK, AND CHARGES WHOSE START AND END BOTH SIT ON A HALF-HOUR ═══════════════════

\echo '=== 0391 §1 — every run the charge-window evidence reads, its playback, and how many of its charges sit on the 30-minute grid ==='
WITH per_run AS (
  SELECT l.sim_run_id, l.run_by, l.source_kind, count(*) AS n,
         count(*) FILTER (WHERE extract(second FROM l.started_at) = 0 AND extract(minute FROM l.started_at)::int % 30 = 0
                            AND extract(second FROM l.ended_at) = 0 AND extract(minute FROM l.ended_at)::int % 30 = 0) AS on_30min_grid,
         min(l.started_at) AS first_start
    FROM public.ottoq_charge_duration_ledger l
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND (l.run_by IN ('operator_demo','production_live') OR l.sim_run_id IS NULL)
   GROUP BY 1, 2, 3)
SELECT left(p.sim_run_id::text, 8) AS run, p.run_by, p.source_kind, p.n, p.on_30min_grid,
       r.payload->>'playback_mode' AS mode, r.payload->>'speed_x' AS speed, r.tick_count,
       round(extract(epoch FROM r.sim_clock_current - r.sim_clock_start) / 60) AS sim_min
  FROM per_run p LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = p.sim_run_id
 ORDER BY p.first_start;
-- READ (2026-09-27 11:19 UTC): 16 (run, source) rows over 15 runs. Every operator run before this morning's was in
--   live playback (speed 5 on 689095e2, 8 on the rest), and 0 of their charges sit on the half-hour grid; the one
--   production run (e8a0ba01, 14 sim-minutes in 7 ticks) has no playback mode and 0 on the grid. 11f15672: 6 charges,
--   6 of 6 on the grid, no playback mode, 7 ticks over 210 sim-minutes -- 3 DCFC charges of exactly 30 minutes, 2 L2
--   of 60 and 90, and one DCFC cut by a connector fault, also 30. So kept fit 6 read clean evidence.
-- RE-READ (2026-09-27 11:23 UTC): 11f15672 now holds 39 rows, not 6. The other 33 were filed at 11:19:00, the first tick
--   of the next run, 929e323c: `stopped_reason = 'orphaned_run'`, every one with a NEGATIVE duration (-143.1 and -203.1
--   minutes), started on 11f15672's clock (15:30, 16:30) and ended at 13:06:52, 929e323c's clock after its first tick.
--   They are the first `orphaned_run` rows the ledger has ever held (§2(b)).

\echo '=== 0391 §1(b) — every orphaned_run row the ledger holds ==='
SELECT left(l.sim_run_id::text, 8) AS run, l.charger_type, count(*) AS n, count(*) FILTER (WHERE l.duration_min < 0) AS negative,
       min(l.duration_min) AS min_dur, max(l.duration_min) AS max_dur, min(l.recorded_at) AS first_recorded, max(l.recorded_at) AS last_recorded
  FROM public.ottoq_charge_duration_ledger l
 WHERE l.stopped_reason = 'orphaned_run'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 11:23 UTC): 11f15672 only, 33 rows (dcfc and l2), 33 negative, -203.128 to -143.128 minutes, all
--   recorded at 11:19:00.117 -- one statement, the reaper's.

-- ══ §2 WHAT THE READER KEEPS, AND WHY IT CANNOT TELL ═══════════════════════════════════════════════════════════════
--
--   `public.ottoq_charge_window_evidence` keeps a charge when its run is `operator_demo` or `production_live` (or has no
--   run) and the run spans at least `p_min_run_minutes`. The ledger records `tick_interval_seconds`, which is 30 on a
--   live run and a fixed one alike: the cadence lives in the run's playback (`payload.playback_mode`, `speed_x`) and in
--   `payload.tick_minutes_actual`, which world_advance writes every tick, and none of them is copied into the ledger. The
--   run row cannot be relied on to carry it later: the demo-run purge deletes prior runs (Part 3, 2026-09-20). So the
--   evidence has to carry its own resolution, and the reader has to use it.
--   (b) AND A SECOND DEFECT, which the first produced by accident. 11f15672 was stopped with `ottoq_sim_mark_stopped`,
--   which marks a run completed and closes nothing; the operator's door, `ottoq_sim_stop_and_reset`, also releases the
--   depot (`ottoq_sim_release_depot`), which closes the run's open sessions as `sim_reset` on the run's own clock -- the
--   censored observations 0516 counts. Left open, 11f15672's 33 sessions were reaped by the next run's first tick in
--   `twin.ottoq_sim_advance_charge_sessions`, whose orphan branch writes `ended_at = COALESCE(s.ended_at,
--   p_sim_clock_now)` -- the REAPING run's sim clock, which is not comparable with the orphan's (two runs, two
--   timelines). Hence ended-before-started sessions in `ocpp_sessions`, and the capture filed each one.
--
--   WHAT ANY FIT WOULD READ, measured rather than assumed: none of it. The reader keeps `stopped_reason IN ('completed',
--   'sim_reset')`, so the 33 reaped rows are dropped; and it keeps a run only if its kept charges span at least
--   `p_min_run_minutes` -- 120 for kept fit 6 -- while 11f15672's 5 completed charges span 90 (14:30-16:00 sim). So
--   today nothing is contaminated, by a margin of 30 minutes and a filter written for another reason.
--
--   THE FIX, filed and held until the validation run 929e323c ends so its captures are not split across two versions:
--   (1) the capture records the tick a charge was observed at (the run's `tick_minutes_actual` at the stop), and the
--   reader leaves out a charge observed at a tick coarser than the live cadence (0.3-1.5 sim-minutes, G161);
--   (2) the reaper closes an orphan on its own run's last clock (`sim_clock_current`), never the reaper's, and the
--   capture does not file a reap as a charge. Nothing refits the charge window on a schedule (no cron job, no function
--   calls the fit), so nothing is at risk before then.
--
--   APPLIED AS 0525, `20260927131932` (2026-09-27 13:19 UTC, 8:19 AM CT), after 0524, its dry run re-run clean on the
--   morning's data first. (1) as written: the ledger's new `tick_minutes` holds the run's sim-minutes per tick, capture
--   version 3 files it, and the reader keeps a charge only at 2 minutes a tick or finer (NULL, the rows filed before, kept;
--   V1 proved the filter drops none of the rows the reader returned before it). (2) NOT as written: the reaper is left
--   alone -- it is on the certified tick path -- and the capture simply files no `orphaned_run` session. And 11f15672's
--   path to the reaper is closed by 0524: a start now stops a live run through the stop door, and its seed closes any
--   leftover charge as `sim_reset` on the charge's own run's last clock, so a run started through the start door finds
--   no other run's open charge for its reaper to close on the wrong clock.
