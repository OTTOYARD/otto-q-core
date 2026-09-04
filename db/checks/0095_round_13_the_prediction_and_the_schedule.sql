-- =====================================================================
-- 0095  Round 13 — the prediction and the schedule, published first
-- =====================================================================
-- Committed BEFORE any round-13 pair reports. The prediction itself was
-- published earlier still, in 0181's header (commit 6e0d647, 22:58 UTC),
-- before round 13 existed at all.
--
-- THE PREDICTION
-- ---------------------------------------------------------------------
-- 0181 changed the run finalizer. 0182, 0183 and 0184 changed only KPI
-- views, which no engine path reads. So:
--
--   ALL SIX COLUMNS MUST REPRODUCE ROUND 12 EXACTLY.
--   A moved hash is 0181's and is a defect to REVERT, not a canon to
--   re-baseline.
--
-- Round 12 canons, the target (db/canons/round12.md):
--
--   | scenario   | seed   | t  | h_cmd    | h_dec    | h_bkg    | h_nrg    |
--   | busy_day   | 171717 | 12 | 04177a2a | 5328154a | 0bf42b3c | 8dcf8918 |
--   | busy_day   | 314159 | 12 | 773fd6dc | ad492891 | 4274369c | 2b271f2f |
--   | normal_day | 171717 | 12 | 78ece09b | c36a99c1 | 2838c66c | 5512b237 |
--   | busy_day   | 171717 | 24 | ec5c38aa | 8221f656 | 096b099e | da9c269c |
--   | busy_day   | 424242 | 12 | 16aabc27 | f1224a98 | 5a227276 | 0cac7e0b |
--   | busy_day   | 424242 | 24 | ac1dc757 | 3adcc2dc | 37ed2670 | c5ef0ab3 |
--
-- WHY IT SHOULD HOLD, and why that is not merely hope
-- ---------------------------------------------------------------------
-- endst DOES hash the column 0181 changed - ottoq_boot_state_fingerprint's
-- `dp` CTE hashes whole dispatch rows including status, return_trigger
-- and actual_return_at. If the teardown write landed before the
-- fingerprint, endst would carry a now() value and could not have
-- reproduced across rounds 11 and 12, which ran hours apart. It did
-- reproduce. Therefore the write lands after the fingerprint, and moving
-- it cannot move a canon. That is the argument this round tests.
--
-- WHAT WOULD FALSIFY IT
-- ---------------------------------------------------------------------
-- Any of the 24 hash comparisons differing from the table above. Not
-- "mostly held" - the prediction is exact, and a single moved hash sends
-- 0181 back, because the only honest reading of a moved hash is that the
-- fingerprint sees the teardown after all and my forces_recert=false
-- classification was wrong.
--
-- A pair that FAILS internally (arm_a <> arm_b) is a different finding
-- and would not falsify this prediction - it would say the engine is
-- nondeterministic within a run, which is round 12's claim, not 0181's.
--
-- THE SCHEDULE, and a correction to the plan it replaces
-- ---------------------------------------------------------------------
-- Six columns, ONE pair each. One pair per column is the falsification
-- test: a moved hash is decisive on a single pair. Round 12 ran two each,
-- which additionally tests intra-round stability - not what is in
-- question here.
--
-- Invocation is byte-identical to round 12's, recovered from
-- cron.job_run_details rather than reconstructed from memory:
--
--   SET statement_timeout = 0;
--   SELECT public.ottoq_determinism_pair(<seed>, <ticks>, '<scenario>',
--     '11111111-1111-1111-1111-111111111111'::uuid,
--     '2026-09-01 02:00:00+00', 1800);
--   SELECT cron.unschedule('<name>');
--
-- NOTE p_arm_budget_s = 1800, NOT the function default of 240. Reading
-- the default and assuming it was used would have changed a
-- determinism-relevant parameter and invalidated the comparison - a
-- 24-tick arm runs well past 240 s, so the budget would have bound and I
-- would have blamed 0181 for a hash I moved myself.
--
-- CADENCE — the planned figure was wrong and is corrected here. Task #55
-- and the round-12 notes carry "8 min for 12-tick pairs (actual
-- 296-400s), 14 min for 24-tick (actual 548-726s)". The MEASURED
-- round-12 durations, from cron.job_run_details:
--
--   12-tick pairs:  461, 570, 606, 614, 606, 452, 610, 621, 557 s
--                   -> 7.5 to 10.4 min, max 621 s
--   24-tick pairs:  947, 792, 1019, 924 s
--                   -> 13.2 to 17.0 min, max 1019 s
--
-- An 8-minute spacing would have OVERLAPPED 12-tick pairs, since the
-- longest ran 10.4 min. Round 12 did not actually use 8/14 - it used
-- 20-minute slots for 12-tick and 25-minute for 24-tick, and every pair
-- completed. Round 13 uses the same proven spacing. The 8/14 figure is
-- retired: it was drawn from an older, faster era of the engine and was
-- never what round 12 ran.
--
-- Slots (UTC), derived from now() inside the scheduling statement with
-- is_in_the_future asserted per row - round 11 lost 5 of 12 pairs to
-- slots computed from a remembered clock, which fails SILENTLY (status
-- null, no run rows):
--
--   r13a  23:16  busy_day   171717  12
--   r13b  23:36  busy_day   314159  12
--   r13c  23:56  normal_day 171717  12
--   r13d  00:16  busy_day   424242  12
--   r13e  00:36  busy_day   171717  24
--   r13f  01:01  busy_day   424242  24
--
-- Each job self-unschedules on success, so a dead session cannot strand
-- a daily-recurring pair; a FAILED pair rolls back its own unschedule
-- and stays visible.
-- =====================================================================

-- The round-13 matrix. Compare every cell to the round-12 table above.
-- d_* > 1 means the two arms of that pair disagreed; a value differing
-- from round 12 means the CANON moved, which is the falsification.
SELECT r.scenario_code, r.random_seed AS seed, r.tick_count AS ticks,
       count(*)/2 AS pairs,
       (array_agg(DISTINCT left(r.validation_notes::jsonb->'arm_b'->>'h_cmd',8)))[1] AS h_cmd,
       (array_agg(DISTINCT left(r.validation_notes::jsonb->'arm_b'->>'h_dec',8)))[1] AS h_dec,
       (array_agg(DISTINCT left(r.validation_notes::jsonb->'arm_b'->>'h_bkg',8)))[1] AS h_bkg,
       (array_agg(DISTINCT left(r.validation_notes::jsonb->'arm_b'->>'h_nrg',8)))[1] AS h_nrg,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_cmd') AS d_cmd,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_dec') AS d_dec,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_bkg') AS d_bkg,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_nrg') AS d_nrg,
       count(*) FILTER (WHERE r.validation_notes::jsonb->>'outcome' <> 'passed') AS not_passed
  FROM public.ottoq_sim_runs r
 WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 23:16:00+00'
 GROUP BY 1,2,3 ORDER BY 1,2,3;

-- Did every scheduled pair actually fire? Read cron.job_run_details
-- JOIN-FREE: a self-unscheduling job deletes its own cron.job row, so an
-- inner join to cron.job silently drops exactly the runs being counted
-- (the 0062 / 0066 §6 / round-12 query-bug family).
SELECT jobid, status, start_time,
       round(EXTRACT(epoch FROM end_time - start_time))::int AS secs,
       substring(command from 'ottoq_determinism_pair\(([^,]*, [^,]*, ''[^'']*'')') AS pair_args
  FROM cron.job_run_details
 WHERE start_time >= '2026-09-03 23:16:00+00' AND command ILIKE '%determinism_pair%'
 ORDER BY start_time;

-- Any r13 job still scheduled after the round means it did not succeed.
SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE 'r13%' ORDER BY jobname;

-- The 0181 invariant must still hold on every run the round created.
SELECT count(*) AS past_horizon_rows_in_round_13
  FROM public.ottoq_vehicle_dispatches d
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
 WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 23:16:00+00'
   AND d.actual_return_at > r.sim_clock_current;
