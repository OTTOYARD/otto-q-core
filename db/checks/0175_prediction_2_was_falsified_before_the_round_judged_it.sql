-- ===========================================================================
-- 0175  PREDICTION 2 WAS FALSIFIED BEFORE THE ROUND COULD JUDGE IT
-- ===========================================================================
-- Measured 2026-09-12 13:20-13:30 UTC (08:20-08:30 AM CT), read-only, while round 38
-- was still running. Nothing in flight was disturbed; no run was started.
--
-- db/checks/0174 committed three predictions at 13:09:17 UTC, before round 38's first
-- pair at 13:40. PREDICTION 2 IS WRONG, and it was wrong for a reason I could have
-- measured in one query before writing it instead of after.
--
-- ---------------------------------------------------------------------------
-- WHAT 0174 PREDICTED, AND WHAT THE DATA SAYS
-- ---------------------------------------------------------------------------
--
-- 0174 PREDICTION 2: "the two grid columns: endst WILL MOVE [from round 37], in
-- `world`, with wsec naming `vehicles` ... 180 sim minutes IS the grid scenario's end,
-- so these runs DID reach the teardown."
--
-- MEASURED -- grid endst.world, every cert pair on the grid depot since 09-08:
--
--   09-09 09:46  239001  4926be34f0e995a3
--   09-09 09:55  239001  4926be34f0e995a3
--   09-12 04:05  239001  4926be34f0e995a3   <- BEFORE 0255
--   09-12 13:40  239001  4926be34f0e995a3   <- AFTER 0255, round 38
--   09-12 04:08  424242  e51fb295975c3e8c   <- BEFORE 0255
--   09-12 13:43  424242  e51fb295975c3e8c   <- AFTER 0255, round 38
--
-- STABLE. Across three days, and across the fix. Round 38's grid pairs had already
-- landed when this was measured, so the prediction was falsified by data in hand
-- rather than by the judgement.
--
-- ---------------------------------------------------------------------------
-- THE PREMISE I DID NOT VERIFY
-- ---------------------------------------------------------------------------
--
-- One query settles it:
--
--   scenario      sim_duration_minutes
--   busy_day                  1440
--   normal_day                1440
--   grid_smoke                1440      <-- NOT 180
--
-- Every scenario's simulated day is 1,440 minutes. At the 30 sim-minutes per tick the
-- run data shows, reaching the end takes 48 ticks REGARDLESS OF SCENARIO. So:
--
--   busy_day/48t     1,440 min  REACHES the end  -> in-arm teardown  -> endst moves
--   busy_day/24t       720 min  does not         -> no teardown      -> endst stable
--   busy_day/12t       360 min  does not         -> no teardown      -> endst stable
--   normal_day/12t     360 min  does not         -> no teardown      -> endst stable
--   grid_smoke/6t      180 min  DOES NOT         -> no teardown      -> endst stable
--
-- I inferred "180 minutes is the grid scenario's end" from the fact that a 6-tick grid
-- run ENDS at 180 minutes. It ends there because it runs out of TICKS, not because the
-- world runs out of DAY -- which is the exact distinction 0173 already drew when it
-- killed the "natural completion is the discriminator" hypothesis:
--
--     "Running the requested ticks is not the same as the world running out of day."
--
-- I wrote that sentence on 09-12 at 07:20 UTC and then made the same conflation again
-- six hours later, in the other direction, about a different scenario. Knowing a
-- distinction is not the same as applying it.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS CHANGES, AND IT MATTERS FOR JUDGING ROUND 38
-- ---------------------------------------------------------------------------
--
-- 1. THE GRID COLUMNS ARE NOT A TEST OF 0255. They never reach the teardown, so the
--    function 0255 changed is never called on their path. Their endst holding steady is
--    the CORRECT and EXPECTED result, and it is evidence of nothing about the fix.
--    0174's "if grid endst does NOT move, 0255 did not reach this path and the
--    conviction is incomplete" is WRONG and must not be acted on -- grid endst not
--    moving means only that grid was never affected.
--
-- 2. BUSY_DAY/171717/48t IS THE ONLY TEST OF 0255 in round 38. Prediction 1 (the six
--    12t/24t columns must not move) stands unchanged and is still the control.
--    Prediction 3 (the two 48t pairs must agree with each other on all fourteen atoms
--    and on wsec.vehicles) stands unchanged and is the whole verdict.
--
-- 3. AND IT CORRECTS 0173 AND round37.md AGAIN, in the direction of their ORIGINAL
--    wording. Those files said the teardown "fires only at 1,440 sim minutes = exactly
--    tick 48". 0174 then "corrected" that to "when a run reaches its own scenario's
--    sim-clock end" and claimed grid's end was 180 minutes. The original wording was
--    right; my correction to it was the error. Every scenario's end IS 1,440 minutes,
--    so "exactly tick 48" is accurate for all of them. Recorded this way round because
--    a correction that un-corrects a correct statement is the most confusing thing to
--    leave in a record.
--
-- ---------------------------------------------------------------------------
-- A NEW OPEN QUESTION, NOT CHASED HERE
-- ---------------------------------------------------------------------------
--
-- The grid depot's four vehicles DO carry a wall-clock last_state_change --
-- 2026-09-12 04:08:00.145927, measured at 07:09 UTC, which is ~65 ms after the 04:08
-- pair's run row was created (04:08:00.080838). So something inside that transaction
-- stamped now() on them very early -- at arm start, not at a teardown.
--
-- IT IS NOT CURRENTLY A REPRODUCIBILITY DEFECT: endst is captured after the ticks and
-- has been stable for three days across six pairs, so whatever stamps it is not inside
-- anything endst can see. But "not currently visible" is exactly what was true of the
-- 48-tick carrier for months, so it is logged rather than dismissed. Candidates not yet
-- distinguished: a reset path in the arm start, or twin.ottoq_sim_seed_fleet's
-- `NOW() - stagger` reached by a route I have not traced. BUILD_QUEUE P0b-c.
--
-- NOT ESTABLISHED and deliberately not guessed: the exact writer, and whether the same
-- early stamp lands on flagship vehicles too (the flagship value measured at 07:09 was
-- 06:20:00.190665, ~110 ms after its own run row -- the same shape, which suggests the
-- answer is "yes, on both", and suggests it is NOT what 0255 fixed).
-- ===========================================================================

-- Re-runnable: every scenario's simulated day is 1,440 minutes.
SELECT scenario_code, sim_duration_minutes
  FROM public.ottoq_scenarios
 WHERE scenario_code IN ('grid_smoke','busy_day','normal_day') AND status='active'
 ORDER BY 1;

-- Re-runnable: grid endst.world across every pair since 09-08.
SELECT to_char(sr.started_at,'MM-DD HH24:MI') AS fired,
       (sr.validation_notes::jsonb->>'seed')   AS seed,
       (sr.validation_notes::jsonb->'arm_a'->'endst'->>'world') AS endst_world
  FROM public.ottoq_sim_runs sr
 WHERE sr.run_by='cert_harness'
   AND sr.depot_id = 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid
   AND jsonb_typeof(sr.validation_notes::jsonb->'arm_a') = 'object'
   AND sr.started_at > '2026-09-09 09:00:00+00'
 GROUP BY 1,2,3
 ORDER BY 1;
