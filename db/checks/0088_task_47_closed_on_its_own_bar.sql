-- =====================================================================
-- 0088  Task #47 closed on its own bar, counted not estimated
-- =====================================================================
-- Task #47 has been open since round 5: "confirm the normal_day
-- 171717/12t intermittent deviation is closed", against a proposed bar
-- of EIGHT consecutive pairs reproducing the column's canon.
--
-- It stayed open through rounds 9, 10 and 11 - including a round in
-- which every one of six columns went green - because the honest count
-- kept coming up short and the bar was never lowered to meet it.
--
-- THE COUNT AT ROUND 11'S CLOSE
-- ---------------------------------------------------------------------
--   6 consecutive pairs on canon c36a99c1
--   bar: 8
--   -> NOT MET. Two pairs were fired (16:21, 16:41 UTC) to reach the bar
--      rather than round six up to it.
--
-- THE COUNT NOW
-- ---------------------------------------------------------------------
--   consecutive_pairs      8
--   bar                    8
--   bar_met                TRUE
--   streak began           2026-09-02 4:28 PM CT
--   non_passing in streak  0
--   distinct_full_canons   1     <- STRONGER THAN THE BAR ASKED
--
-- The last line is the one worth reading twice. The bar was stated in
-- terms of the canon reproducing; distinct_full_canons = 1 means all
-- FOUR hashes - h_cmd, h_dec, h_bkg, h_nrg - were byte-identical across
-- all eight pairs, not merely the one the bar named. The column's canon:
--
--   h_cmd 78ece09b  h_dec c36a99c1  h_bkg 2838c66c  h_nrg 5512b237
--
-- Eight pairs, spanning 2026-09-02 4:28 PM CT to 2026-09-03 11:41 AM CT,
-- across THREE engine states (0169, 0179, 0177 applied between them) and
-- three certification rounds. That is what closes it: not a quiet spell,
-- but reproduction across changes that could have moved it.
--
-- WHAT IT DOES NOT CLAIM
-- ---------------------------------------------------------------------
-- Eight pairs is the bar THIS TASK set, met exactly. It is not a proof
-- of determinism in general, and the column's 40 all-time pairs include
-- earlier canons that moved legitimately with engine migrations. The
-- claim is bounded: the intermittent deviation this task was opened for
-- has not recurred in eight consecutive pairs on the current engine.
WITH pairs AS (
  SELECT DISTINCT ON (r.validation_notes) r.started_at,
         left(r.validation_notes::jsonb->'arm_b'->>'h_cmd',8) AS h_cmd,
         left(r.validation_notes::jsonb->'arm_b'->>'h_dec',8) AS h_dec,
         left(r.validation_notes::jsonb->'arm_b'->>'h_bkg',8) AS h_bkg,
         left(r.validation_notes::jsonb->'arm_b'->>'h_nrg',8) AS h_nrg,
         r.validation_notes::jsonb->>'outcome' AS outcome
    FROM ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.scenario_code='normal_day'
     AND r.random_seed=171717 AND r.tick_count=12 AND r.validation_notes IS NOT NULL
   ORDER BY r.validation_notes, r.started_at),
ord AS (SELECT *, row_number() OVER (ORDER BY started_at DESC) AS rn FROM pairs),
brk AS (SELECT COALESCE(min(rn),999)-1 AS streak FROM ord WHERE h_dec <> 'c36a99c1')
SELECT (SELECT streak FROM brk) AS consecutive_pairs, 8 AS bar,
       (SELECT streak FROM brk) >= 8 AS bar_met,
       (SELECT min(started_at) AT TIME ZONE 'America/Chicago' FROM ord WHERE rn <= (SELECT streak FROM brk)) AS streak_began_ct,
       (SELECT count(*) FROM ord WHERE rn <= (SELECT streak FROM brk) AND outcome <> 'passed') AS non_passing,
       (SELECT count(DISTINCT h_cmd||h_dec||h_bkg||h_nrg) FROM ord WHERE rn <= (SELECT streak FROM brk)) AS distinct_full_canons;

-- The two closing pairs' jobs unscheduled themselves; nothing stranded.
SELECT COALESCE(string_agg(jobname, ','), '(none - all self-unscheduled)') AS survivors
  FROM cron.job WHERE jobname LIKE 't47%';

-- =====================================================================
-- SECOND-LANE READINESS, measured rather than assumed
-- =====================================================================
-- 0177 unblocked the two-lane cadence. Which depots can actually BE a
-- second lane is a separate question, and the answer is narrower than
-- the plan in task #55 assumed:
--
--   depot                          assets  points  active scenarios
--   Benchmark (2222...)              100     160   0   <- UNUSABLE
--   Grid fixture (aacd...)             4      10   1   (grid_smoke)
--   P2 proof rig (d200...)             1       1   0
--   Hardware Lab (d000...)             0       1   0
--
-- The Benchmark depot has the fleet and the points but NO SCENARIO BOUND
-- TO IT - exactly what 0153's header said failed it as a pair target,
-- still true. Since 0175, a pair aimed at it is REFUSED outright rather
-- than silently running the flagship, which is the improvement: the
-- failure is now loud.
--
-- So the only viable second lane today is the grid fixture (~10 s per
-- pair). Making Benchmark usable means binding a scenario to it - the
-- same thing twin.ottoq_grid_fixture_create does for fixtures - and is
-- its own piece of work, not a precondition of the probe.
SELECT d.name,
       (SELECT count(*) FROM public.ottoq_scenarios s WHERE s.depot_id=d.id AND s.status='active') AS active_scenarios,
       (SELECT count(*) FROM public.vehicles v WHERE v.home_depot_id=d.id AND v.category='autonomous') AS assets,
       (SELECT count(*) FROM public.stalls s WHERE s.depot_id=d.id) AS points
  FROM public.depots d WHERE d.id <> '11111111-1111-1111-1111-111111111111'
 ORDER BY assets DESC;
