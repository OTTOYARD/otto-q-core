-- =====================================================================
-- 0087  Round 11 — the 0177 prediction, written before the evidence
-- =====================================================================
-- 0177 applied 2026-09-03 ~4:55 AM CT. forces_recert, so it takes a full
-- round: 12 pairs, six columns, two passes each, 10:05-14:00 UTC
-- (5:05-9:00 AM CT), self-unscheduling, never overlapping.
--
-- WHAT 0177 CHANGED
-- ---------------------------------------------------------------------
-- twin.ottoq_sim_start_run decided whether a new run needs a cold start
-- by counting deployed vehicles across EVERY depot:
--
--   SELECT count(*) INTO v_deployed
--     FROM vehicles WHERE current_state = 'deployed'::vehicle_state;
--
-- Now scoped: AND home_depot_id = v_scenario.depot_id.
--
-- Verified applied, three ways rather than assumed:
--   guard_present                   true
--   scoped (home_depot_id clause)   true
--   old unscoped read still there   FALSE
--
-- THE PREDICTION
-- ---------------------------------------------------------------------
-- ottoq_determinism_pair primes every arm EXPLICITLY at 0.70 immediately
-- after starting it:
--
--   BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, p_sim_start, 0.70);
--   EXCEPTION WHEN OTHERS THEN RAISE WARNING ...; END;
--
-- so a cert arm is primed whether or not start_run's cold-start branch
-- fires. The branch 0177 changed is therefore NOT on the certification
-- path, and the prediction is the strongest kind available here:
--
--   ALL SIX COLUMNS MUST REPRODUCE ROUND 10 EXACTLY - all four hashes,
--   every column, including the two 424242 h_dec canons that 0179 newly
--   established. recorder_rows must stay 0 / 0 / 0 / 0 / 3 / 14.
--
--   ANY moved hash is 0177's, and is a defect to REVERT rather than a
--   canon to re-baseline. There is no "expected to move" column this
--   round - that is what makes it a real test rather than a formality.
--
-- Round 10 canons (db/canons/round10.md), the diff target:
--   busy_day   171717 12t  04177a2a / 5328154a / 0bf42b3c / 8dcf8918  rec 0
--   busy_day   314159 12t  773fd6dc / ad492891 / 4274369c / 2b271f2f  rec 0
--   normal_day 171717 12t  78ece09b / c36a99c1 / 2838c66c / 5512b237  rec 0
--   busy_day   171717 24t  ec5c38aa / 8221f656 / 096b099e / da9c269c  rec 0
--   busy_day   424242 12t  16aabc27 / f1224a98 / 5a227276 / 0cac7e0b  rec 3
--   busy_day   424242 24t  ac1dc757 / 3adcc2dc / 37ed2670 / c5ef0ab3  rec 14
--
-- WHAT THIS ROUND ALSO BUYS, beyond 0177
-- ---------------------------------------------------------------------
-- It is the SECOND round boundary for the four columns unchanged since
-- round 8, and the FIRST reproduction test for the two 424242 canons
-- that 0179 established. db/canons/round10.md says plainly that those
-- two were "a first observation, not a stable one"; this round is what
-- can make them stable, or refute them.
--
-- WHY THE PREDICTION IS WRITTEN DOWN FIRST
-- ---------------------------------------------------------------------
-- Because last night the practice paid twice. 0169's prediction named
-- the exact branch that turned out to be a latent crash, and 0179's
-- named h_bkg as the value that must not move - which is what proved the
-- CONTINUE changed no assignment. A prediction published after the run
-- is a description, not a test.
SELECT r.scenario_code, r.random_seed AS seed, r.tick_count AS ticks,
       to_char(r.started_at AT TIME ZONE 'America/Chicago','HH24:MI') AS ct,
       r.validation_notes::jsonb->>'outcome' AS outcome,
       r.validation_notes::jsonb->>'equal'   AS eq,
       r.validation_notes::jsonb->'arm_b'->>'h_cmd' AS h_cmd,
       r.validation_notes::jsonb->'arm_b'->>'h_dec' AS h_dec,
       r.validation_notes::jsonb->'arm_b'->>'h_bkg' AS h_bkg,
       r.validation_notes::jsonb->'arm_b'->>'h_nrg' AS h_nrg,
       (SELECT count(*) FROM ottoq_decisions d
         WHERE d.sim_run_id=r.sim_run_id AND d.outcome_status='deferred_tick_budget') AS rec
  FROM ottoq_sim_runs r
 WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 10:00:00+00'
 ORDER BY r.started_at;

-- Any surviving k* job means its pair FAILED and rolled back its own
-- unschedule - the property that made last night's four crashes visible
-- instead of swept up.
SELECT COALESCE(string_agg(jobname, ','), '(none - all self-unscheduled)') AS survivors
  FROM cron.job WHERE jobname LIKE 'k_p_';

-- =====================================================================
-- RESULT — round 11 closed, 2026-09-03 11:20 AM CT
-- =====================================================================
-- THE PREDICTION HELD ON ALL 24 HASH COMPARISONS. Twelve pairs, six
-- columns, two each, every hash single-valued within its column, every
-- run passed, every cell identical to round 10. Table in
-- db/canons/round11.md.
--
-- Four columns are now stable across TWO round boundaries (8 -> 10 ->
-- 11) - the bar roadmap item A actually asks for, met for the first
-- time. The two 0179 canons reproduced, discharging round10.md's "a
-- first observation, not a stable one" by evidence.
--
-- TASK #47, COUNTED EXACTLY AND NOT CLOSED
-- ---------------------------------------------------------------------
--   6 consecutive pairs on canon c36a99c1, zero non-passing
--   streak began 2026-09-02 4:28 PM CT
--   40 pairs all-time on this column
-- The bar is EIGHT. Six is not eight. Two further pairs fired 16:21 and
-- 16:41 UTC to reach it honestly rather than round up to it.
WITH pairs AS (
  SELECT DISTINCT ON (r.validation_notes) r.started_at,
         left(r.validation_notes::jsonb->'arm_b'->>'h_dec',8) AS h_dec,
         r.validation_notes::jsonb->>'outcome' AS outcome
    FROM ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.scenario_code='normal_day'
     AND r.random_seed=171717 AND r.tick_count=12 AND r.validation_notes IS NOT NULL
   ORDER BY r.validation_notes, r.started_at),
ord AS (SELECT *, row_number() OVER (ORDER BY started_at DESC) AS rn FROM pairs)
SELECT count(*) FILTER (WHERE rn <= (SELECT COALESCE(min(rn),999)-1 FROM ord WHERE h_dec <> 'c36a99c1'))
         AS consecutive_pairs_on_canon,
       8 AS bar,
       count(*) FILTER (WHERE rn <= (SELECT COALESCE(min(rn),999)-1 FROM ord WHERE h_dec <> 'c36a99c1')) >= 8
         AS bar_met
  FROM ord;

-- PROCESS FINDING: NEVER COMPUTE A CRON SLOT FROM A REMEMBERED TIME
-- ---------------------------------------------------------------------
-- Five of this round's twelve pairs did not fire at all on the first
-- attempt. Their slots were computed from an ASSUMED clock (~09:55 UTC)
-- when the real time was ~11:40 UTC - PR #155 merged nearly two hours
-- after the last clock read and the clock was never re-read. The slots
-- were already in the past when created, so pg_cron queued them for the
-- next day.
--
-- The failure mode is quiet in a specific way: cron.job_run_details has
-- NO ROW AT ALL for such a job, and status = null is indistinguishable
-- at a glance from "scheduled, not yet fired". Nothing errors, nothing
-- is stranded; the round just comes up short, invisibly, unless the
-- missing columns are counted.
--
-- The re-schedule derives every slot from now() INSIDE the statement and
-- asserts fire_utc > now() per row, so the check is structural rather
-- than remembered. CLAUDE.md rule 7 already says pg_cron evaluates in
-- UTC; this is its companion - the UTC value must also be CURRENT.
--
-- Detector for the next time: a scheduled job with no run row whose slot
-- has already passed today.
SELECT j.jobname, j.schedule,
       (SELECT count(*) FROM cron.job_run_details d WHERE d.jobid = j.jobid) AS run_rows
  FROM cron.job j
 WHERE j.jobname ~ '^(k|t47|c|f)' 
 ORDER BY j.jobname;
