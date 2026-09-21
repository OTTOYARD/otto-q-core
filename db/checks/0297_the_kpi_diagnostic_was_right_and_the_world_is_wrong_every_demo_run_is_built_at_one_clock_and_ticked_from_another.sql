-- 0297  G103 DIAGNOSED, AND THE DIAGNOSTIC WAS NEVER THE DEFECT. `hours_clipped_to_window` IS
--       REPORTING FAITHFULLY: **45 OF 87 DISPATCH ROWS ON THIS RUN WERE BORN WITH `dispatched_at`
--       SEVEN HOURS AND TWENTY-FIVE MINUTES IN THE SIM FUTURE**, BECAUSE `ottoq_start_demo_run`
--       BUILDS THE WORLD AT ONE CLOCK AND THEN REWRITES THE CLOCK THE TICK PATH ADVANCES FROM.
--       32 OF THOSE ROWS FINISHED THE RUN CARRYING A **NEGATIVE `actual_duration_min`**, STORED
--       WITHOUT A COMPLAINT FROM ANYTHING. **G107, AND IT IS UNDER EVERY DEMO-RUN KPI WE HAVE.**
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), run
-- `c9b0a87e-0d39-4bd8-9a91-12837b2995a3` — **completed**, tick 1335, `failure_reason` "run_governor:
-- reached the 540 sim-minute ceiling". Written while its `class='engine'` tables still exist, for the
-- reason `0395` exists.
--
-- **WHY THIS FILE EXISTS AT ALL, and it is a correction of my own framing.** G103 was filed in `0294`
-- §6 as *"either the clip is measuring something other than what its name says, or KPI 1's numerator
-- and this diagnostic disagree about their window."* **Both branches are wrong.** The clip measures
-- exactly what its name says, the numerator and the diagnostic agree completely, and the quantity
-- they agree on is a **data defect in `ottoq_vehicle_dispatches`**. I filed a suspicion against the
-- instrument because the instrument was the thing I had just built; the instrument was the only part
-- of this working correctly.
--
-- ══ 1. THE ARITHMETIC, WHICH ACCOUNTS FOR THE WHOLE NUMBER ═════════════════
--
-- KPI 1 publishes `hours_clipped_to_window` = **-227.36** on this run (-237.29 on `e8b8eb3e`). Its
-- definition in `ottoq_kpi_asset_hours_available_per_day` is, per first slice:
--
--     EXTRACT(epoch FROM COALESCE(claimed_end, win_to) - dispatched_at)
--   - GREATEST(EXTRACT(epoch FROM credit_to - credit_from), 0)
--
-- with `claimed_end = COALESCE(actual_return_at, scheduled_return_at)`. The second term is floored at
-- zero; the first is not. **So the whole quantity goes negative exactly when a dispatch's return
-- precedes its own dispatch.** Measured on this run's 87 dispatches:
--
--   dispatches                                            87
--   `claimed_end` < `dispatched_at`                      **32**
--   `claimed_end` IS NULL                                  0
--   `dispatched_at` before the run's window start          0
--   hours contributed by the 32 inverted rows        **-227.37**
--
-- **-227.37 against the published -227.36.** The inverted rows are not part of the explanation, they
-- are the entire explanation, to the rounding digit.
--
-- And the inversion is not marginal: the mean is **426 minutes** and the maximum **439.5 minutes**,
-- on a run whose whole life is 540 sim-minutes. `actual_return_at` is the inverted side — 32 of the
-- 85 rows that have one.

WITH d AS (
  SELECT v.dispatched_at,
         COALESCE(v.actual_return_at, v.scheduled_return_at) AS claimed_end,
         r.sim_clock_start AS win_from
    FROM public.ottoq_vehicle_dispatches v
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = v.sim_run_id
   WHERE v.sim_run_id = 'c9b0a87e-0d39-4bd8-9a91-12837b2995a3')
SELECT count(*)                                                        AS dispatches,
       count(*) FILTER (WHERE claimed_end < dispatched_at)             AS end_before_start,
       count(*) FILTER (WHERE claimed_end IS NULL)                     AS claimed_end_null,
       count(*) FILTER (WHERE dispatched_at < win_from)                AS dispatched_before_window,
       round((sum(CASE WHEN claimed_end < dispatched_at
                       THEN EXTRACT(epoch FROM claimed_end - dispatched_at) ELSE 0 END)
              / 3600.0)::numeric, 2)                                   AS negative_hours_accounted
  FROM d;

-- ══ 2. THE CAUSE, TRACED LINE BY LINE, AND IT IS A CLOCK SPLIT AT RUN START ══
--
-- Every one of the 45 rows created in the run-start transaction (`created_at` = the run's own
-- `started_at`, **2026-09-21 01:23:28.069351+00**, identical to the microsecond, so one statement)
-- carries `dispatched_at` between **12:03 and 12:59 sim**. The run's `sim_clock_start` is **05:35
-- sim**. A row cannot be dispatched seven hours after the clock it is created on.
--
--   1. `public.ottoq_start_demo_run` line 17 calls `ottoq_sim_run_scenario(scenario, seed,
--      'operator_demo')`.
--   2. Inside it, for `run_by = 'operator_demo'`:
--          v_start := ((date_trunc('day', now() AT TIME ZONE 'America/Chicago')
--                       + interval '8 hours') AT TIME ZONE 'America/Chicago')
--      = **08:00 Central = 2026-09-20T13:00:00+00**. It INSERTs that as `sim_clock_start`, sets
--      `v_start_hour := 8`, and then **builds the world against it**: `ottoq_sim_seed_fleet(depot,
--      seed, 8)`, `ottoq_deploy_target_fraction(8, 0.92)` -> the recorded `prime_fraction` 0.3960,
--      the need-profile draw (payload records `need_profiles.sim_clock` = **2026-09-20T13:00:00+00**),
--      and `ottoq_sim_prime_deployment(run, v_start, frac)` — which writes
--      `dispatched_at := p_sim_clock_now - elapsed`, i.e. back from **13:00**.
--   3. Back in `ottoq_start_demo_run`, lines 20-33, the clock is **REWRITTEN**:
--          v_offset_min := abs(hashtext(p_seed::text)) % 1440
--          sim_clock_start := date_trunc('day', sim_clock_start) + make_interval(mins => v_offset_min)
--      For seed 100020 that is **335**, and `date_trunc('day', ...)` in this UTC session gives
--      00:00 UTC, so `sim_clock_start` becomes **2026-09-20 05:35:00+00** — verified below, exactly
--      equal to the stored value.
--
-- **So the world is primed at 08:00 Central and the tick path then starts from 00:35 Central, and
-- nothing moves the world when the clock moves.** The 45 primed dispatches stay anchored to 13:00;
-- the twin ticks forward from 05:35; those vehicles return at **05:45–05:52** — ten to seventeen
-- minutes into the run — and the completion branch of `twin.ottoq_sim_advance_deployed_telemetry`
-- writes `actual_return_at = p_sim_clock_now` **and** `actual_duration_min = (p_sim_clock_now -
-- dispatched_at)/60`, from the same clock against a `dispatched_at` seven hours ahead of it.
--
-- **THE ROW STATES ITS OWN CONTRADICTION AND NOTHING READS IT.** Three sampled inverted rows carry
-- `actual_duration_min` of **-387.98, -407.73 and -414.43**. A trip of negative four hundred minutes
-- was computed, persisted, and passed every check this database has. That is the `0231` shape once
-- more: a value relied upon for a property nothing asserts.

SELECT (abs(hashtext('100020')) % 1440)                                        AS seed_offset_min,
       date_trunc('day', '2026-09-20 13:00:00+00'::timestamptz)
         + make_interval(mins => (abs(hashtext('100020')) % 1440))             AS derived_clock_start,
       r.sim_clock_start                                                       AS stored_clock_start,
       (date_trunc('day', '2026-09-20 13:00:00+00'::timestamptz)
         + make_interval(mins => (abs(hashtext('100020')) % 1440)))
         = r.sim_clock_start                                                   AS derivation_matches,
       r.payload->'boot_prime'->>'start_hour_cst'                              AS world_built_for_hour_ct,
       r.payload->'boot_draw'->'need_profiles'->>'sim_clock'                   AS need_profiles_drawn_at,
       to_char(r.sim_clock_start AT TIME ZONE 'America/Chicago', 'HH24:MI')    AS tick_path_starts_at_ct
  FROM public.ottoq_sim_runs r
 WHERE r.sim_run_id = 'c9b0a87e-0d39-4bd8-9a91-12837b2995a3';

-- the three cohorts, separated: live dispatches, primed-active, primed-inbound
SELECT (d.created_at = r.started_at)                              AS created_in_run_start_txn,
       COALESCE(d.return_evidence->>'boot_prime', '-')            AS boot_prime,
       count(*)                                                   AS rows_,
       min(d.dispatched_at)                                       AS min_dispatched_at,
       max(d.dispatched_at)                                       AS max_dispatched_at,
       count(*) FILTER (WHERE d.actual_return_at < d.dispatched_at) AS inverted,
       count(*) FILTER (WHERE d.actual_duration_min < 0)          AS negative_duration_stored
  FROM public.ottoq_vehicle_dispatches d
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
 WHERE d.sim_run_id = 'c9b0a87e-0d39-4bd8-9a91-12837b2995a3'
 GROUP BY 1, 2 ORDER BY 1, 2;

-- ══ 3. WHAT THIS DOES TO THE NUMBERS WE PUBLISH, STATED PLAINLY ════════════
--
--   (a) **KPI 1 is UNDERSTATED, not overstated.** The credited term is floored at zero, so each
--       inverted dispatch contributes **exactly zero** availability hours. `asset_hours_available_
--       per_day = 26.64` on this run is computed from **55 of 87 dispatches**; 37% of the fleet's
--       trips are invisible to it. That is the direction to be least comfortable with under rule 6's
--       posture — an error that flatters nothing is still an error, and here it makes the product
--       look worse than it is while making the KPI unusable either way.
--   (b) **The published headline remains reproducible from the run ID.** `horizon_source` reads
--       `run_horizon`, `not_reproducible` is `[]`, and the defect is deterministic (see (d)). A
--       reproducible number computed over the wrong world is still the wrong number: **`0146`'s
--       lesson exactly — a run ID makes a number reproducible, it does not make it meaningful.**
--   (c) **Everything hour-of-day shaped in a demo run is evaluated at a different hour than the
--       world was built for.** The fleet was seeded for hour 8, the deployed fraction chosen for
--       hour 8, the need profiles drawn at 13:00 — and the arrival curve, tariff windows, solar and
--       staffing then ran from 00:35 Central. This is not speculation about the tick path; it is the
--       same `v_start_hour` and `v_start` read in `ottoq_sim_run_scenario` at lines 17-20, 85 and
--       150-152.
--   (d) **IT IS INVISIBLE TO THE FOURTEEN ATOMS, BY CONSTRUCTION.** `v_offset_min` is
--       `abs(hashtext(seed)) % 1440` — seed-derived — so two runs of one seed split their clocks
--       IDENTICALLY, and every arm of every pair is wrong in precisely the same way. **A
--       byte-identical verdict cannot see a defect both arms share.** Third time this class has
--       appeared (`0137` hashed a write timestamp, `0216` hashed a minted uuid, and now this), and
--       the first time the shared error is in the WORLD rather than in the digest.
--   (e) **CERTIFICATION RUNS ARE NOT AFFECTED, and this is the one reassuring line.**
--       `ottoq_start_demo_run`'s own comment states that `run_by='cert_harness'` and
--       `production_live` never call it, and only this function rewrites `sim_clock_start` anywhere
--       in the database (one `UPDATE ... SET sim_clock_start` exists, and it is here). The pair rigs
--       — `ottoq_determinism_pair`, `ottoq_determinism_pair_replay`, `ottoq_ab_pair`,
--       `ottoq_tick_invariance_arm` — prime against the clock they were handed and never move it.
--       **So the reproducibility apparatus of 2.9a stands; what falls is the DEMO runs, which are
--       exactly the runs every KPI I measured tonight and on 09-20 came from.**
--
-- ══ 4. THE FIX, AND WHY IT IS NOT WRITTEN TONIGHT ══════════════════════════
--
-- The shape is not in doubt: **choose the clock before building the world, not after.** Either
--   (i)  `ottoq_start_demo_run` computes `v_offset_min` first and passes the resulting start clock
--        INTO `ottoq_sim_run_scenario`, so `v_start`, `v_start_hour`, the fleet seed, the deploy
--        fraction, the need-profile draw and the prime all use the one clock; or
--   (ii) the scenario path keeps ownership of the clock and the demo path stops rewriting it,
--        randomising the start via the scenario's own hour instead of a post-hoc UPDATE.
-- **(i) is the smaller change and the right one** — the randomised start is a demo feature and the
-- demo wrapper should own it, but it must own it *before* step 17 rather than after step 33.
--
-- **NOT BUILT HERE, for three reasons that are all about not compounding the error.**
--   - It changes `sim_clock_start` for every future demo run, so **every canon whose config_hash
--     keys on the clock is invalidated: `forces_recert TRUE`**, and that classification is a
--     deliberate decision, not a side effect of a bug fix.
--   - It moves the world every downstream number was measured against. The right order is to land
--     the fix and then re-measure the five KPIs on a fresh run, not to land it between a measurement
--     and its interpretation — which is `0294` §2's confound committed a second time.
--   - **And an assertion should land with it, not after it:** `actual_duration_min < 0` must be
--     impossible to store. A CHECK constraint is the honest form; the reason this defect survived is
--     that a negative trip duration was computed and nothing objected.
--
-- **THE HONEST SENTENCE ABOUT KPI 1 UNTIL THEN:** *"asset_hours_available_per_day is computed over
-- the 55 of 87 dispatches whose return follows their dispatch; the other 32 are primed rows anchored
-- seven hours ahead of the clock the twin ticks from, and they contribute zero. The number is
-- reproducible from its run ID and is not yet a measurement of availability."*

-- OPEN-ITEM: ottoq_start_demo_run builds the world via ottoq_sim_run_scenario at 08:00 Central (13:00 UTC) and then rewrites sim_clock_start to a seed-derived minute of the UTC day (05:35 for seed 100020), leaving 45 of 87 dispatch rows anchored seven hours twenty-five minutes in the sim future and everything hour-of-day shaped evaluated at the wrong hour. Fix is to choose the clock before step 17 and pass it in; forces_recert TRUE. Tracked as G107.
-- OPEN-ITEM: actual_duration_min is stored negative (-387.98 to -439.5 minutes observed) by the completion branch of twin.ottoq_sim_advance_deployed_telemetry, which computes it as (p_sim_clock_now - dispatched_at)/60 with no guard; a CHECK constraint forbidding a negative trip duration should land with the G107 fix, because a value nothing asserts is how this survived. Tracked as G107.
-- OPEN-ITEM: every demo-run KPI measured on 2026-09-20 and 2026-09-21 (runs c8f678fb, e8b8eb3e, c9b0a87e) was computed over a world with the G107 clock split; the five KPIs need re-measuring on a fresh run AFTER the fix lands, and not before, or the fix and the measurement confound each other as 0294 section 2 did. Tracked as G107.
