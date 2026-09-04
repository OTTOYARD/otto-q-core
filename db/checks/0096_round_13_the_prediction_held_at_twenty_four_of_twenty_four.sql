-- =====================================================================
-- 0096  Round 13 — the prediction held, 24 of 24
-- =====================================================================
-- The falsification test 0095 set up, run. Canons in db/canons/round13.md.
--
-- SECTION 1 — THE RESULT
-- ---------------------------------------------------------------------
-- Six columns, one pair each, engine as of 0184. Every one of the 24
-- hash cells is IDENTICAL to round 12. not_passed = 0 on every column;
-- all four hashes single-valued within each pair, so the arms agree too.
-- Six launches, twelve arm rows, every job self-unscheduled.
--
-- 0181's prediction, published in its header at 22:58 UTC before round 13
-- existed, was exact and it held. forces_recert = false was correct, and
-- the argument behind it is now tested rather than reasoned: endst hashes
-- the dispatch column 0181 changed, and it did not move, which is only
-- possible if the teardown write lands after the fingerprint.
--
-- SECTION 2 — A CORRECTION TO THE 00:15 CHECK-IN
-- ---------------------------------------------------------------------
-- At the mid-round check-in, with only the three 12-tick columns in,
-- aborted_rows was 0, and I recorded that round 13 would prove 0181
-- caused no regression WITHOUT exercising its new abort branch - that
-- the branch evidence came only from the grid fixture.
--
-- SUPERSEDED. The 24-tick columns produced them:
--
--   dispatches_r13    1404
--   aborted_r13          6     <- still out when the run stopped
--   past_horizon_r13     0     <- the 0181 invariant
--
-- Under the old finalizer each of those six would have been marked
-- 'completed' and stamped with the transaction's wall clock. They are
-- now 'aborted' with actual_return_at NULL, and not one row in the round
-- carries a return time past its run's horizon. The round proves BOTH
-- halves - the new branch fires at flagship scale, and nothing moved.
--
-- The mid-round reading was true when taken and wrong as a conclusion.
-- Recording it because the lesson generalises: a partial round is not a
-- small round, it is a biased one - the 12-tick columns systematically
-- lack the long-horizon behaviour the 24-tick columns carry.
--
-- SECTION 3 — THE CORRECTED KPIs AT FLAGSHIP SCALE
-- ---------------------------------------------------------------------
-- Not re-reads of historical rows. Every run below was CREATED after all
-- four migrations, on the flagship depot.
--
--   KPI 2 turns_completed          3,522   (pre-fix: 10,810 -> 3.07x)
--     of the excess, teardown-closed        1,492
--   KPI 1 asset-hours              1,910.9 (pre-fix:  2,894.0 -> 1.51x)
--   KPI 1 rows bounded by wall clock    0
--   KPI 4 touch_events_per_turn    0.1670
--
-- KPI 1's remaining 983.1 clipped hours are the legitimate horizon-and-
-- prime clamp, not a wall clock: horizon_source = 'run_horizon' on every
-- row. That is 0182 working, not 0181 residue.
--
-- 1,492 bookings in this round alone were closed by the teardown and
-- would have been counted as completed turns by the pre-0183 KPI 2. The
-- defect was not historical; it was live and producing wrong numbers on
-- every run until today.
--
-- SECTION 4 — HARNESS, AND THE TWO THINGS THAT WOULD HAVE VOIDED IT
-- ---------------------------------------------------------------------
-- p_arm_budget_s is 1800, NOT the function default of 240. Recovered
-- from cron.job_run_details rather than reconstructed. Taking the default
-- would have bound a 24-tick arm, moved a hash, and had me revert a
-- correct fix on my own evidence.
--
-- The 8-min/14-min cadence in task #55 is RETIRED. Measured round-12
-- 12-tick pairs ran 452-621 s; 8-minute spacing would have overlapped
-- them. Round 12 actually used 20/25. Round 13's own durations confirm:
--
--   23:16  608s   23:36  595s   23:56  585s
--   00:16  473s   00:36 1041s   01:01 1067s
--
-- The 24-tick pairs ran 1041 s and 1067 s - past round 12's 947-1019 s
-- range, inside a 25-minute slot, far outside a 14-minute one.
--
-- A pg_cron reporting artifact, resolved rather than assumed: a
-- multi-statement cron command logs an INTERMEDIATE job_run_details row
-- (succeeded, ~1 s, return_message 'SET') which is UPDATED to the true
-- duration and '1 row' on real completion. At 23:17 that row plus
-- arm_rows = 0 read exactly like a round that died on arrival. It had
-- not: one backend was active 156 s in, and arm_rows = 0 is EXPECTED
-- because the harness commits both arms in a single transaction.
--
-- SECTION 5 — WHAT IS STILL OPEN
-- ---------------------------------------------------------------------
-- - The 0182/0183/0184 diagnostics do not reach ottoq_kpi_five, which
--   projects only the headline columns. Four of five KPIs now carry an
--   audit trail invisible from the one command that ships the number.
-- - KPI 5's denominator over the 345 historical past-horizon dispatch
--   rows is not re-examined.
-- - KPI 2's points_used denominator is still every stall with any
--   booking that day - a definitional choice, deliberately not decided
--   inside a defect fix.
-- - KPI 4's turns filter is still an inline COPY of KPI 2's rather than
--   a read of it; they agree today only because both were corrected.
-- - The pg_cron stall mechanism (round 12) is still unnamed. Round 13
--   spaced its pairs far enough apart that it did not bite.
-- =====================================================================

-- §1 — the matrix. Compare every cell to db/canons/round12.md.
SELECT r.scenario_code, r.random_seed AS seed, r.tick_count AS ticks,
       count(*)/2 AS pairs,
       (array_agg(DISTINCT left(r.validation_notes::jsonb->'arm_b'->>'h_cmd',8)))[1] AS h_cmd,
       (array_agg(DISTINCT left(r.validation_notes::jsonb->'arm_b'->>'h_dec',8)))[1] AS h_dec,
       (array_agg(DISTINCT left(r.validation_notes::jsonb->'arm_b'->>'h_bkg',8)))[1] AS h_bkg,
       (array_agg(DISTINCT left(r.validation_notes::jsonb->'arm_b'->>'h_nrg',8)))[1] AS h_nrg,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_cmd')
       + count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_dec')
       + count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_bkg')
       + count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_nrg') AS distinct_sum_expect_4,
       count(*) FILTER (WHERE r.validation_notes::jsonb->>'outcome' <> 'passed') AS not_passed
  FROM public.ottoq_sim_runs r
 WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 23:16:00+00'
 GROUP BY 1,2,3 ORDER BY min(r.started_at);

-- §2 — 0181's branch fired, and its invariant held. aborted > 0 is what
-- makes this round evidence ABOUT the branch and not merely around it.
SELECT
  (SELECT count(*) FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r USING (sim_run_id)
    WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 23:16:00+00')            AS dispatches_r13,
  (SELECT count(*) FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r USING (sim_run_id)
    WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 23:16:00+00'
      AND d.status='aborted')                                                              AS aborted_r13,
  (SELECT count(*) FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r USING (sim_run_id)
    WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 23:16:00+00'
      AND d.actual_return_at > r.sim_clock_current)                                        AS past_horizon_r13;

-- §3 — the corrected KPIs on runs created after every migration
WITH r13 AS (SELECT sim_run_id FROM public.ottoq_sim_runs
              WHERE run_by='cert_harness' AND started_at >= '2026-09-03 23:16:00+00')
SELECT
  (SELECT sum(turns_completed) FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id IN (SELECT sim_run_id FROM r13))                          AS kpi2_now,
  (SELECT sum(turns_completed + bookings_not_a_turn) FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id IN (SELECT sim_run_id FROM r13))    AS kpi2_before,
  (SELECT sum(released_by_teardown) FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id IN (SELECT sim_run_id FROM r13))                     AS kpi2_teardown_rows,
  (SELECT round(sum(asset_hours_available),1) FROM public.ottoq_kpi_asset_hours_available_per_day WHERE sim_run_id IN (SELECT sim_run_id FROM r13)) AS kpi1_now,
  (SELECT round(sum(asset_hours_available + hours_clipped_to_window),1) FROM public.ottoq_kpi_asset_hours_available_per_day WHERE sim_run_id IN (SELECT sim_run_id FROM r13)) AS kpi1_before,
  (SELECT count(*) FILTER (WHERE horizon_source <> 'run_horizon') FROM public.ottoq_kpi_asset_hours_available_per_day WHERE sim_run_id IN (SELECT sim_run_id FROM r13)) AS kpi1_wall_clock_rows,
  (SELECT round(avg(touch_events_per_turn),4) FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id IN (SELECT sim_run_id FROM r13))         AS kpi4_now;

-- §4 — every pair fired and cleaned up. JOIN-FREE: a self-unscheduling
-- job deletes its own cron.job row, so an inner join drops the runs.
SELECT to_char(start_time,'HH24:MI') AS slot, status,
       round(EXTRACT(epoch FROM end_time-start_time))::int AS secs, return_message
  FROM cron.job_run_details
 WHERE start_time >= '2026-09-03 23:16:00+00' AND command ILIKE '%determinism_pair%'
 ORDER BY start_time;

-- Must be empty. A leftover r13 job means its command did not reach the
-- self-unschedule, i.e. the pair did not succeed.
SELECT coalesce(string_agg(jobname,','),'(none)') AS leftover_jobs
  FROM cron.job WHERE jobname LIKE 'r13%';
