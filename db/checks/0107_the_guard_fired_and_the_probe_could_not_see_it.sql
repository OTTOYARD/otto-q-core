-- =====================================================================
-- 0107  The guard fired, and the probe could not have seen it
-- =====================================================================
-- 0192 shipped with five predictions published at its foot so they could
-- be falsified. This is the verdict on the first probe. Two predictions
-- held, one was UNTESTABLE BY CONSTRUCTION, and the reason it was
-- untestable is a mistake in how I designed the probe -- not a finding
-- about the engine.
--
-- Probe: pg_cron job 344, determinism pair, busy_day / seed 171717 /
-- 12 ticks / flagship depot, 15:20-15:28 UTC (10:20-10:28 AM CT),
-- 491 s wall. Arms 5dbc3de9 (A) and 867372c6 (B).
-- Comparison run: da5fc387, the round-13 pair at the identical
-- (scenario, seed, ticks, depot) coordinate.
--
-- =====================================================================
-- PREDICTION 2 — HELD. THIS IS THE ONE THAT MATTERED.
-- =====================================================================
-- "Both arms of every pair still agree. If any pair DISAGREES after
--  this, the guard introduced nondeterminism and must be reverted, not
--  tuned."
--
--   canon    arm A                             arm B                             equal
--   fp       92b02f8bb837f8ce6442bba60ab31bb4  92b02f8bb837f8ce6442bba60ab31bb4  yes
--   h_cmd    801836412bcc119bca648b9f1508fbf6  801836412bcc119bca648b9f1508fbf6  yes
--   h_dec    6e116d5b1e0f246dd06708f0f4bf270a  6e116d5b1e0f246dd06708f0f4bf270a  yes
--   h_bkg    b1d72a6207e33e99c8ffc6f5d30f9c79  b1d72a6207e33e99c8ffc6f5d30f9c79  yes
--   h_nrg    625014b7a09a481a3ccdf0a19bbfdee6  625014b7a09a481a3ccdf0a19bbfdee6  yes
--   endst    a3576bacb55c6244b6a8cf67c8550c11  a3576bacb55c6244b6a8cf67c8550c11  yes
--     (endst compared as md5 of the whole end-state object)
--
-- validation_status = 'passed' on both arms. 0192 is not reverted.
-- Expected: the guard is IMMUTABLE, reads no clock, no random source and
-- no row outside its argument. But "expected" is not "measured", and the
-- revert condition was published in advance precisely so this could not
-- be argued after the fact.
--
-- =====================================================================
-- PREDICTION 1 — HELD. THE COLUMN MOVED.
-- =====================================================================
-- busy_day/171717/12t against its round-13 canon:
--
--   canon    round 13                          after 0192                        moved
--   h_cmd    04177a2a5d686032aa1c54fcac43f958  801836412bcc119bca648b9f1508fbf6  YES
--   h_dec    5328154a5f72e9e1bb6b10d177def459  6e116d5b1e0f246dd06708f0f4bf270a  YES
--   h_bkg    0bf42b3cc1b2db78de9e91274d28b3df  b1d72a6207e33e99c8ffc6f5d30f9c79  YES
--   h_nrg    8dcf8918702a18b9f20022b80dd24513  625014b7a09a481a3ccdf0a19bbfdee6  YES
--   fp       92b02f8bb837f8ce6442bba60ab31bb4  92b02f8bb837f8ce6442bba60ab31bb4  no
--
-- fp NOT moving is correct and is worth stating rather than glossing:
-- it is the boot-prime fingerprint, computed before any manifest exists,
-- so a guard on manifest generation cannot reach it. Had fp moved, the
-- guard would be touching something it has no business touching.
--
-- The other five columns are not covered by this probe and remain
-- uncertified. forces_recert=true stands; this closes one column of six.
--
-- =====================================================================
-- THE GUARD DEMONSTRABLY FIRED
-- =====================================================================
--                                 round 13    after 0192
--   atoms stamped guard_demoted          0           111
--   must_do atoms outstanding          271           158   (-113)
--   visits                             116           116
--   service legs done                  274           275
--
-- 111 demotions, and outstanding must_do work falls by 113 -- the
-- walkarounds, and nothing else. Visit count is unchanged, so the guard
-- did not drop or duplicate work; it removed the power of unperformable
-- work to block.
--
-- =====================================================================
-- PREDICTION 3 — UNTESTABLE AT THIS HORIZON. MY ERROR.
-- =====================================================================
-- "dispatches in window rise from 7 toward the duty curve, and
--  deployed-at-08:00 rises from 0 toward its target of 76."
--
-- Measured:
--                                 round 13    after 0192
--   dispatched in window                 0             0
--   deployed at 08:00                    0             0
--
-- No rise. Before treating that as a failed prediction, the obvious
-- question: COULD this probe have shown a rise at all? It could not.
--
-- In the 48-tick run 0106 was written from (cd8e0796), the in-window
-- dispatches happened at these sim times:
--
--   09:00 x2   10:30 x1   19:00 x1   20:30 x1   21:30 x1
--   (plus 09-02 00:30 x1, and 6 more at the 09-02 02:00 boundary)
--
-- THE EARLIEST DISPATCH IN THE ENTIRE RUN IS 09:00. This probe covers
-- 02:00-08:00. It ends one sim-hour BEFORE the first dispatch that has
-- ever been observed at this coordinate, in either direction.
--
-- The duty curve is why: ottoq_deploy_target_fraction asks for 0.006 of
-- the fleet at 02:00, 0.045 at 04:00 and 0.360 at 06:00, while the boot
-- prime starts with 116 already deployed and draining. v_to_dispatch is
-- GREATEST(0, desired - currently_deployed), so it is pinned at zero for
-- the whole window regardless of what any guard does.
--
-- So prediction 3 is NEITHER confirmed NOR refuted. It is unmeasured,
-- and it was unmeasurable the moment I chose a 12-tick probe.
--
-- This is my mistake, and a repeat of a class already documented here
-- (0170 -> 0172 -> 0176 -> 0178 -> 0181 -> 0182 -> 0188): a run may only
-- be judged on what it had time to do. Worse, 0192's own prediction text
-- says "the depot can release at most 6 per tick and needs ~13 ticks to
-- reach the morning target from zero" -- I wrote the reason a 12-tick
-- probe could not answer the question INTO the prediction, and then ran
-- a 12-tick probe. Recording it plainly rather than quietly rerunning.
--
-- A 48-tick pair at the same coordinate is scheduled (job
-- r14_probe_0192_48t) to test predictions 3, 4 and 5 against the horizon
-- 0106's numbers were actually measured on.
--
-- =====================================================================
-- PREDICTIONS 4 AND 5 — NOT YET TESTED
-- =====================================================================
-- 4 (utilisation rises, time-to-service worsens) and 5 (0104's +7% does
-- not survive) both depend on the fleet cycling, which prediction 3 must
-- establish first. Untested, not assumed. 0104's +7% remains withdrawn
-- from use either way, per 0105.
--
-- =====================================================================
-- A SEPARATE DEFECT THE PROBE EXPOSED — SILENT UNTIL SOMETHING ELSE FAILED
-- =====================================================================
-- The first attempt (job 343) FAILED after exactly 120 s:
--
--   ERROR: canceling statement due to statement timeout
--   CONTEXT: SQL function "ottoq_depot_running_run" statement 1
--            SQL function "ottoq_sim_compute_charger_load_kw" statement 1
--            SQL function "ottoq_depot...
--
-- pg_cron sessions inherit a 120 s statement_timeout. The p_arm_budget_s
-- argument is the HARNESS's internal budget and does not raise it; a job
-- must SET statement_timeout itself as its first statement. Job 344 did,
-- and completed in 491 s.
--
-- Raising the timeout is a workaround, not a diagnosis. The call stack
-- names ottoq_sim_compute_charger_load_kw, which is the same shape as
-- the 0098 defect class: a hot path nobody has ever timed, invisible
-- until something else fails around it. 0098's lesson was that timing a
-- view in isolation and multiplying by its call count is not a
-- measurement of the caller. This one has not been profiled at all.
-- Recorded, not fixed, not guessed at.
--
-- =====================================================================
-- QUERIES
-- =====================================================================

-- Q1 — the pair verdict: both arms, every canon.
WITH n AS (SELECT validation_notes::jsonb AS j FROM ottoq_sim_runs
            WHERE sim_run_id='5dbc3de9-ce06-4f16-8d46-9b0724c7a186')
SELECT j->'arm_a'->>'fp'    AS a_fp,    j->'arm_b'->>'fp'    AS b_fp,
       j->'arm_a'->>'h_cmd' AS a_cmd,   j->'arm_b'->>'h_cmd' AS b_cmd,
       j->'arm_a'->>'h_dec' AS a_dec,   j->'arm_b'->>'h_dec' AS b_dec,
       j->'arm_a'->>'h_bkg' AS a_bkg,   j->'arm_b'->>'h_bkg' AS b_bkg,
       j->'arm_a'->>'h_nrg' AS a_nrg,   j->'arm_b'->>'h_nrg' AS b_nrg,
       md5((j->'arm_a'->'endst')::text) AS a_endst,
       md5((j->'arm_b'->'endst')::text) AS b_endst
  FROM n;

-- Q2 — the column moved: this pair against its round-13 canon.
SELECT sim_run_id, started_at,
       validation_notes::jsonb->'arm_a'->>'h_cmd' AS h_cmd,
       validation_notes::jsonb->'arm_a'->>'h_dec' AS h_dec,
       validation_notes::jsonb->'arm_a'->>'h_bkg' AS h_bkg,
       validation_notes::jsonb->'arm_a'->>'h_nrg' AS h_nrg,
       validation_notes::jsonb->'arm_a'->>'fp'    AS fp
  FROM ottoq_sim_runs
 WHERE scenario_code='busy_day' AND random_seed=171717 AND tick_count=12
   AND depot_id='11111111-1111-1111-1111-111111111111'
   AND validation_notes IS NOT NULL AND validation_notes::jsonb ? 'arm_a'
 ORDER BY started_at DESC LIMIT 4;

-- Q3 — the guard fired; work was unblocked, not dropped.
WITH runs AS (
  SELECT '5dbc3de9-ce06-4f16-8d46-9b0724c7a186'::uuid AS id, 'AFTER 0192' AS lbl
  UNION ALL SELECT 'da5fc387-572b-46b5-9c5f-de13c0348be0'::uuid, 'BEFORE (round 13)')
SELECT r.lbl,
  (SELECT count(*) FROM ottoq_visit_needs v WHERE v.sim_run_id=r.id) AS visits,
  (SELECT count(*) FROM ottoq_visit_needs v, jsonb_array_elements(v.atoms) a
     WHERE v.sim_run_id=r.id AND COALESCE((a->>'guard_demoted')::boolean,false)) AS atoms_demoted,
  (SELECT count(*) FROM ottoq_visit_needs v, jsonb_array_elements(v.atoms) a
     WHERE v.sim_run_id=r.id AND COALESCE((a->>'must_do')::boolean,false)
       AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')) AS must_do_outstanding,
  (SELECT count(*) FROM ottoq_itinerary_legs l WHERE l.sim_run_id=r.id AND l.status='done'
     AND l.leg_type <> ALL(ARRAY['taxi','stage','depart'])) AS service_legs_done,
  (SELECT count(*) FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id=r.id
     AND d.dispatched_at >= '2026-09-01 02:00:00+00') AS dispatched_in_window
FROM runs r ORDER BY r.lbl DESC;

-- Q4 — THE PROBE COULD NOT HAVE SEEN IT: earliest dispatch is 09:00,
-- one sim-hour after a 12-tick window ends.
SELECT to_char(dispatched_at,'YYYY-MM-DD HH24:MI') AS sim_time_dispatched, count(*) AS n
  FROM ottoq_vehicle_dispatches
 WHERE sim_run_id='cd8e0796-8f5e-47e1-846a-c24ed72a4c42'
   AND dispatched_at >= '2026-09-01 02:00:00+00'
 GROUP BY 1 ORDER BY 1;

-- Q5 — and why: the duty curve is near zero across the whole window,
-- while the boot prime starts at 116 deployed and drains.
SELECT to_char(ts,'HH24:MI') AS sim_time,
       round(ottoq_deploy_target_fraction(EXTRACT(hour FROM ts)::int, 0.75)::numeric,3) AS target_frac,
       FLOOR(116 * ottoq_deploy_target_fraction(EXTRACT(hour FROM ts)::int, 0.75))::int AS desired_deployed
  FROM generate_series('2026-09-01 02:00:00+00'::timestamptz,
                       '2026-09-01 08:00:00+00'::timestamptz, interval '1 hour') ts;

-- Q6 — the harness defect: job 343's timeout, job 344's success.
SELECT jobid, status, start_time, end_time,
       round(EXTRACT(epoch FROM end_time - start_time)) AS secs,
       left(COALESCE(return_message,''),200) AS msg
  FROM cron.job_run_details WHERE jobid IN (343, 344) ORDER BY start_time;
