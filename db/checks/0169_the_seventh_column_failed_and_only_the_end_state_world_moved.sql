-- ===========================================================================
-- 0169  THE SEVENTH COLUMN FAILED 0193'S BAR, AND ONLY endst.world MOVED
-- ===========================================================================
-- Judged 2026-09-12 03:35 UTC (2026-09-11 10:35 PM CT), read-only, from the two
-- verdicts themselves. The pairs fired 2026-09-09 at 15:45 and 16:10 UTC,
-- jobids 542 and 543. Naming the firing times, not a window.
--
-- THE HEADLINE, AND IT IS NOT THE ONE THE CHECK-IN EXPECTED
--
-- busy_day/171717/48t does NOT meet 0193's bar. The flagship matrix is SIX of
-- SEVEN. "The matrix is green" is still a sentence that needs a caveat, and the
-- caveat is this file.
--
-- Each pair passed INTERNALLY. Both: outcome=passed, equal=true, complete=true,
-- and zero of fourteen atoms differing between its own two arms. 0193's bar is
-- not internal agreement, it is two consecutive pairs that agree WITH EACH OTHER
-- above the recert floor. Measured across the two:
--
--   13 of 14 atoms agree:  fp h_cmd h_dec h_evt h_bkg h_nrg h_prop h_defr
--                          h_cal h_rule h_rcl h_sdr ticks
--   1 of 14 differs:       endst
--
-- AND endst IS AN OBJECT, SO IT NARROWS FURTHER. Six of its seven sub-keys agree
-- (bookings, calibration, chargers, dispatches, legs, visit_needs). Exactly one
-- moved:
--
--   endst.world   15:45  bff2b5d5486ea6cc92c8ba1c83f92761
--                 16:10  4ae38da2ddd951224e2cb8e3641bd252
--
-- WHAT MAKES THIS SHARP RATHER THAN ROUTINE
--
--   1. fp AGREED. Both pairs booted from the identical world,
--      9c28854e976c8572f2cc1bf4717f85b0 -- the same value the 12t and 24t
--      columns carry for this seed. Same start.
--   2. EVERY STREAM HASH AGREED. Commands, decisions, events, bookings, energy,
--      proposals, deferrals, rules, recalls and SDRs are byte-identical across
--      the two pairs. The engine made the same decisions and emitted the same
--      events, twice.
--   3. SAME PARAMETERS, INCLUDING THE CLOCK. Read from cron.job rather than
--      assumed -- jobids 542 and 543 are character-for-character identical
--      except the schedule:
--        ottoq_determinism_pair(171717, 48, 'busy_day',
--          '11111111-1111-1111-1111-111111111111', '2026-09-01 02:00:00+00', 1800)
--      so sim_start is FIXED and a differing sim clock is ruled out. That was the
--      first hypothesis and it is wrong.
--
-- Identical start, identical decisions, identical events -- different final
-- world. So the divergence is in state that the end world hash can see and that
-- none of the twelve stream hashes can.
--
-- WHY endst.world IS THE ONE PLACE THIS COULD HIDE
--
-- ottoq_boot_state_fingerprint run-scopes every CTE it owns: visit_needs,
-- bookings, legs and dispatches each filter sim_run_id = p_run or split
-- visible/foreign. One sub-key does not:
--
--   'world', ottoq.ottoq_world_fingerprint(p_depot)
--
-- DEPOT-SCOPED, NOT RUN-SCOPED -- by design (0244 added it precisely because the
-- rest of the function "hashes everything ABOUT the assets and never the assets
-- themselves"). It is the only part of the verdict that reads shared fleet state,
-- and it is the only part that moved.
--
-- RULED OUT BY READING THE CATALOG, NOT BY ASSUMING
--
-- ottoq_world_fingerprint hashes two absolute timestamps -- vehicles
-- .last_state_change and .robotic_tether_until -- so a wall-clock stamp inside
-- the run was the obvious suspect. It is not the cause. Every writer of
-- last_state_change on the run path assigns from a variable (the sim clock);
-- the only three that assign now() are reset/seed paths --
-- ottoq_benchmark_reset, ottoq_sim_release_depot, twin.ottoq_sim_seed_fleet --
-- and the cert boot goes through ottoq_cert_arm_start, which stamps from a
-- variable. Consistent with fp agreeing.
--
-- WHAT IS NOT ESTABLISHED, SAID PLAINLY
--
-- WHICH of the five sections moved. ottoq_world_fingerprint returns ONE md5 over
-- vehicles # stalls # chargers # vehicle_need_profile # bess. When it moves it
-- names nothing. The candidates are all still live:
--   * stalls.reserved_at / reservation_expires_at -- timestamps;
--   * bess lifetime_kwh_charged / _discharged / cycle_count -- CUMULATIVE across
--     runs, and 0133 added them because the battery "carried across runs and no
--     fingerprint section could see it";
--   * vehicle_need_profile, which excludes drawn_at/updated_at but little else.
--
-- THE INSTRUMENT IS THE BLOCKER, NOT THE HUNT. The two runs are 60 hours gone and
-- their end states are not reconstructible -- vehicles, stalls and bess hold
-- CURRENT state, not per-run history, so there is nothing left to diff. Another
-- pair of 48t pairs would cost ~80 minutes and, with today's hash, would tell me
-- exactly what this one did: "world moved."
--
-- So the next step is 0170: section-level world hashes, added MEASURED per the
-- blind-spot promotion doctrine (CLAUDE.md 2.9a), so the NEXT disagreement names
-- its own section. Then re-run the column. Building the instrument before the
-- experiment is the 0167 lesson applied forward instead of in hindsight.
--
-- ---------------------------------------------------------------------------
-- CORRECTION, same session, 03:52 UTC: ONE OF THE TWO END STATES IS NOT GONE
-- ---------------------------------------------------------------------------
--
-- Above I wrote that the two end states "are not reconstructible" and that the
-- delay "cost the only copy of the evidence." Half of that is wrong, and it was
-- found by dry-running 0254 rather than by thinking harder.
--
--   ottoq.ottoq_world_fingerprint('11111111-...')  RIGHT NOW, 60 hours later
--     = 4ae38da2ddd951224e2cb8e3641bd252
--   the 16:10 pair's endst.world
--     = 4ae38da2ddd951224e2cb8e3641bd252
--
-- Byte-identical. The flagship depot's fleet/stall/charger/need-profile/BESS state
-- has not moved since the 16:10 arm finished. So the SECOND pair's end state is
-- still live on disk and is now decomposed (0254 applied 03:49 UTC):
--
--   vehicles      d97316f9872b267b79e733a2728c88e4    116 rows
--   stalls        3e03db4aa74a4655b6bb10f20b450a48    158 rows
--   chargers      4895c66ad941383fbc0dff3b0db9ed57     40 rows
--   need_profile  b24639271b27f6a93f99c8886a57fd94    116 rows
--   bess          d06508b990e4780f947ca04afea56f5c      1 row
--   combined      4ae38da2ddd951224e2cb8e3641bd252   = the monolith, = 16:10
--
-- The 15:45 pair's end state IS gone -- the 16:10 arms overwrote the shared fleet
-- state -- so a direct A-vs-B section diff is still impossible and the experiment
-- is still required. What changed is that there is now a PINNED BASELINE: the next
-- 48t pair's wsec can be compared section by section against the five hashes
-- above, which is strictly more than comparing one hash against one hash.
--
-- AND IT KILLS A HYPOTHESIS I HAD NOT WRITTEN DOWN, which is the more valuable
-- half. "Something outside the certification mutates flagship fleet state between
-- pairs" is the obvious explanation for two pairs ending differently, and it is
-- now ruled out: ottoq-demo-metronome (every minute), ottoq-depot-tick and
-- ottoq-run-governor (every two minutes) ran a combined ~8,400 times across those
-- 60 hours, all succeeded, and moved not one byte of any of the five sections at
-- this depot. Whatever moved endst.world between 15:45 and 16:10 was inside the
-- run, not beside it.
--
-- Recorded as a correction rather than edited away: the original paragraph was
-- written from a true premise (per-run history is not kept) and a false inference
-- (therefore nothing is left to read). The premise still holds for 15:45.
--
-- ---------------------------------------------------------------------------
-- SECOND NARROWING, 03:58 UTC: PRIMING IS RULED OUT, AND THE BLIND SPOT IS NAMED
-- ---------------------------------------------------------------------------
--
-- The arm object carries `boot` as well as `fp` and `endst`, and the three are
-- captured at three different moments:
--
--   fp           r.payload->>'world_fingerprint', written by twin.ottoq_sim_start_run
--                -- i.e. AFTER ottoq_tick_invariance_reset_fleet but BEFORE
--                   twin.ottoq_sim_prime_deployment
--   boot         public.ottoq_boot_state_fingerprint(p_depot, v_run), AFTER priming
--                and before the first tick. 0125 labels it "Diagnostic, not verdict",
--                and it is indeed absent from v_equal's fourteen terms.
--   endst        the same function, after the last tick.
--
-- So `fp` cannot see a priming divergence and `boot` can. That made priming the
-- leading hypothesis -- prime_deployment deploys vehicles, so a divergence there
-- would leave fp equal and the end state different. MEASURED across the two pairs:
--
--   boot sub-key   pairs agree
--   -----------    -----------
--   bookings       yes         legs           yes
--   calibration    yes         visit_needs    yes
--   chargers       yes         world          yes   0348beb36dcc8bc51a2cb12b274c5d19
--   dispatches     yes
--
-- SEVEN OF SEVEN. Priming is ruled out. (Note in passing that boot.world
-- 0348beb3... is NOT fp 9c28854e..., which confirms the two are taken at different
-- moments and that neither is redundant.)
--
-- THE STATEMENT IS THEREFORE AS TIGHT AS THE EXISTING EVIDENCE ALLOWS:
--   identical post-prime world, identical 48 ticks of every stream the verdict
--   hashes, different final world.
--
-- AND THAT NAMES THE BLIND SPOT, which is the real result of this file. Two of the
-- five world sections are simply not covered by any stream atom:
--
--   * STALLS. h_bkg hashes ottoq_stall_bookings -- the calendar. The world hash
--     reads the stalls TABLE's own columns: status, current_vehicle_id,
--     reserved_by, reserved_at, reservation_expires_at. A reservation written
--     directly onto a stall row appears in the world hash and in NO stream hash.
--   * BESS. h_nrg hashes ottoq_energy_commands -- what was COMMANDED. The world
--     hash reads ottoq_bess_units state, including lifetime_kwh_charged,
--     lifetime_kwh_discharged and current_cycle_count, which are CUMULATIVE. 0133
--     added them precisely because "the battery carried across runs and no
--     fingerprint section could see it".
--
-- Identical commands do not entail identical battery state, and an identical
-- calendar does not entail identical stall rows. Those are the two places a
-- divergence can live while twelve stream hashes agree -- so they are the two
-- sections wsec will be read for first.
--
-- AND THE HONEST NOTE ABOUT TIMING. This should have been judged at 16:26 UTC on
-- 09-09. The session was stopped by a weekly usage limit until 03:31 UTC on
-- 09-12, so the finding sat for 59 hours. That delay cost the only copy of the
-- evidence: had this been read on the day, the two end states were still on disk.
-- ===========================================================================

-- The two verdicts, side by side. Re-runnable; the rows are immutable.
WITH p AS (
  SELECT DISTINCT ON (sr.started_at)
         to_char(sr.started_at,'MM-DD HH24:MI') AS fired,
         (sr.validation_notes::jsonb) AS vn
    FROM public.ottoq_sim_runs sr
   WHERE sr.run_by='cert_harness'
     AND sr.started_at >= '2026-09-09 15:40:00+00'
     AND sr.started_at <  '2026-09-09 17:00:00+00'
   ORDER BY sr.started_at
), atoms(k) AS (VALUES ('fp'),('h_cmd'),('h_dec'),('h_evt'),('h_bkg'),('h_nrg'),
                       ('h_prop'),('h_defr'),('h_cal'),('h_rule'),('h_rcl'),
                       ('h_sdr'),('ticks'),('endst')),
x AS (SELECT vn FROM p ORDER BY fired LIMIT 1),
y AS (SELECT vn FROM p ORDER BY fired DESC LIMIT 1)
SELECT a.k AS atom,
       ((SELECT vn->'arm_a'->a.k FROM x) IS NOT DISTINCT FROM
        (SELECT vn->'arm_a'->a.k FROM y)) AS pairs_agree
  FROM atoms a
 ORDER BY pairs_agree, a.k;

-- And the sub-key that moved.
WITH p AS (
  SELECT DISTINCT ON (sr.started_at) sr.started_at,
         (sr.validation_notes::jsonb)->'arm_a'->'endst' AS e
    FROM public.ottoq_sim_runs sr
   WHERE sr.run_by='cert_harness'
     AND sr.started_at >= '2026-09-09 15:40:00+00'
     AND sr.started_at <  '2026-09-09 17:00:00+00'
   ORDER BY sr.started_at
), x AS (SELECT e FROM p ORDER BY started_at LIMIT 1),
   y AS (SELECT e FROM p ORDER BY started_at DESC LIMIT 1)
SELECT k AS endst_subkey,
       (((SELECT e FROM x)->k) IS NOT DISTINCT FROM ((SELECT e FROM y)->k)) AS agrees
  FROM jsonb_object_keys((SELECT e FROM x)) k
 ORDER BY agrees, k;
