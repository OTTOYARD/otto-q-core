-- 0339  **G136(b) is STILL OPEN, cleanly: across all 50 twin-depot arms certified since `0420`, not one
--       condemned a vehicle. The fault path has never been exercised inside a determinism pair.**
--
--       **And G136(a) MUST NOT be done the way my own check-in instructed.** That check-in said: *"if
--       further 48-tick arms have accumulated, pool their eligible vehicle-hours and observed faults with
--       the 1,269.5 / 0 already recorded. ~5 arms give ~5.6 expected faults, where an observed count
--       finally discriminates λ as a VALUE rather than a bound."*
--
--       Six 48-tick arms have accumulated. **Pooling them would report ~7,617 vehicle-hours against 0
--       observed faults — P = e^-6.7 = 0.12%, i.e. "the applied λ is rejected at 99.88%". That number
--       would be worthless, and it would look like the strongest result on this page.**
--
--       Measured 2026-09-22 ~15:2x UTC (10:2x CT).
--
-- ══ §1 WHY POOLING THEM IS COUNTING ONE OBSERVATION SIX TIMES ════════════════
--
-- All six 48-tick arms since `0420` are **the same (scenario, seed, ticks)**:
--
--     scenario_code   random_seed   tick_count   arms   pairs   pair times
--     -------------   -----------   ----------   ----   -----   ------------------
--     busy_day             171717           48      6       3   09:58, 13:26, 14:12
--
-- and `ottoq_determinism_canon` holds **exactly one** enabled 48-tick column. So the six arms are three
-- repetitions of one run, each run twice.
--
-- **Two independent reasons the exposure does not accumulate, and the second is the interesting one:**
--
--   (a) **Within a pair, the two arms are byte-identical BY CONSTRUCTION.** That is what a determinism
--       pair asserts. Arm B is not a second sample of the fault process; it is arm A recomputed. Pooling
--       A and B doubles the denominator and adds nothing to the numerator's information.
--   (b) **Across pairs, the repetitions are identical for the same reason — and this is the property
--       2.9a SELLS.** Same seed, same scenario, same depot, same engine hash, and a twin whose RNG is a
--       pure hash of `(seed, entity, sim-seconds-since-this-run's-start)` (`0052`). If this column drew
--       zero faults at 09:58 it is *required* to draw zero at 13:26 and 14:12. **A certified-reproducible
--       engine cannot generate independent samples by re-running a fixed seed.**
--
-- **So the honest figure for this column is unchanged from `0328` and cannot be improved by any number of
-- sweeps: 1,269.5 eligible vehicle-hours, 1.12 expected faults, 0 observed, P = 33%.**
--
-- ══ §2 THE TENSION IS REAL AND WORTH NAMING, BECAUSE IT IS STRUCTURAL ════════
--
-- Reproducibility and statistical accumulation pull in opposite directions, and this is the first place
-- in this build where they collide:
--
--   * **2.9a sells byte-identical output under a fixed seed** as a product property most of the field
--     cannot claim. Every sweep re-verifies it.
--   * **A hazard rate needs independent draws.** Under a fixed seed there are none. The determinism
--     apparatus is, for this purpose, an instrument that returns the same reading forever — which is
--     exactly right for certifying the engine and exactly useless for estimating λ.
--
-- **Neither is a defect. The error is only in treating repeated verification as accumulated evidence.**
--
-- ══ §3 WHAT DOES ACCUMULATE, AND WHERE THE EXISTING FIGURE COMES FROM ════════
--
-- **Distinct canon COLUMNS carry independent fault draws; repeats of one column do not.** The seven
-- enabled twin-depot columns are four at 12 ticks (`busy_day` 171717 / 314159 / 424242, `normal_day`
-- 171717), two at 24 (`busy_day` 171717 / 424242) and one at 48 (`busy_day` 171717) — different seeds
-- and different horizons, so different draws.
--
-- **That pool is already what G136's existing figure reports — a marginal low signal at P = 2.8%** — and
-- it is the correct construction. So G136(a) is not a pending measurement that more sweeps will discharge:
-- it is **already computed, and its precision is bounded by the number of distinct columns, not by the
-- number of arms.** The only thing that moves it is what G136 and task #21 already say and what this check
-- now has a mechanism for: **new canon cells at fresh seeds.** That is Chase's call, because it adds
-- permanent recert cost to every future sweep.
--
-- (Not recomputed here: the per-column eligible vehicle-hours. Older columns' runs are `class='engine'`
-- and several have been purged, so a fresh pooled arithmetic would be computed over a different
-- population than the one that produced 2.8%. Recomputing it needs `0328`'s corrected
-- `DISTINCT ON (vehicle, sim_clock)` method run per surviving column, and stating the surviving set.)
--
-- ══ §4 THE ERROR IS MINE, AND IT IS A NEW SHAPE FOR THIS PAGE ════════════════
--
-- Every instance so far was *a real measurement read as answering a question it was not about* — a
-- duration read as a wait (`0332`), a value read as an outcome (`0337`), a sim date against a real
-- calendar (`0337` §5), the wrong column entirely (`0338`).
--
-- **This one is a real measurement COUNTED MORE THAN ONCE, and the multiplier came from the very property
-- the system is built to guarantee.** Determinism made six readings look like six samples. Nothing in the
-- data marks them as duplicates: six distinct `sim_run_id`s, six `validation_status='passed'`, six
-- genuine `started_at`s, all on the twin depot, all within one working day. **Only the canon's
-- `(scenario, seed, ticks)` key reveals that they are one cell.**
--
-- **THE STANDING TEST: before pooling anything across runs, GROUP BY the key that defines an independent
-- observation — here `(scenario, seed, ticks, depot)` — and count DISTINCT keys, not rows.** If distinct
-- keys is 1, the pool has one observation in it however many rows it has.
--
-- **And the sharper warning, because of where the instruction came from:** the check-in that told me to
-- pool was written by me, hours earlier, carrying a worked arithmetic ("~5 arms give ~5.6 expected
-- faults") that was wrong in the direction of a dramatic result. A scheduled instruction from my own past
-- self gets no more trust than any other claim on this page, and this one asked for a 99.88% rejection
-- built on one run counted six times.

\echo '=== 0339 §1 — all six 48-tick arms are ONE canon cell: 6 rows, 1 observation ==='
SELECT scenario_code, random_seed, tick_count,
       count(*) AS arms, count(DISTINCT started_at) AS pairs,
       string_agg(DISTINCT to_char(started_at,'HH24:MI'), ', ') AS pair_times
  FROM public.ottoq_sim_runs
 WHERE started_at >= '2026-09-22 08:08:56+00' AND tick_count = 48
   AND depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1,2,3;
-- One row: busy_day / 171717 / 48, six arms, three pairs. Six sim_run_ids, six passes, six started_ats
-- -- and ONE independent observation. Pooling them reports ~7,617 vehicle-hours and P=0.12%; the honest
-- figure is 0328's unchanged 1,269.5 vh / 1.12 expected / 0 observed / P=33%.

SELECT scenario, seed, ticks FROM public.ottoq_determinism_canon
 WHERE enabled AND ticks = 48;
-- Exactly one enabled 48-tick column, which is what makes the six arms repetitions rather than samples.

\echo '=== 0339 §1b — the standing test: count DISTINCT KEYS, not rows ==='
SELECT count(*) AS arm_rows,
       count(DISTINCT (scenario_code, random_seed, tick_count, depot_id)) AS independent_observations
  FROM public.ottoq_sim_runs
 WHERE started_at >= '2026-09-22 08:08:56+00'
   AND depot_id='11111111-1111-1111-1111-111111111111';
-- **50 arm rows against 7 independent observations.** Any pooled statistic over the first number is wrong
-- by a factor it will not announce -- and the factor MOVES: this read 48 against 7 a few minutes earlier,
-- because the 0424 resweep is still running. The row count climbs with every sweep and the observation
-- count does not, so the overstatement grows the longer the engine is verified. That is the whole finding
-- in one line.

\echo '=== 0339 §2 — G136(b): the fault path has never fired inside a pair ==='
SELECT r.tick_count, count(*) AS arms,
       sum((SELECT count(*) FROM public.ottoq_state_transitions t
             WHERE t.entity_kind='vehicle'
               AND t.to_state IN ('out_of_service','tow_requested','emergency_staged')
               AND t.created_at BETWEEN r.started_at AND COALESCE(r.ended_at, now()))) AS condemn_transitions,
       count(*) FILTER (WHERE r.validation_status='passed') AS passed
  FROM public.ottoq_sim_runs r
 WHERE r.started_at >= '2026-09-22 08:08:56+00'
   AND r.depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 1 DESC;
-- Zero condemn transitions at every horizon (48t 6 arms, 24t 12, 12t 32), 50 of 50 arms passed. So the fourteen-atom verdict has
-- never once been tested against a run in which a vehicle was condemned. G136(b) STILL OPEN -- and
-- deliberately not forced: manufacturing a fault to exercise it would test the injector, not the engine.
