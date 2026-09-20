-- 0270  THE DETERMINISM PAIR PASSES AFTER THE SITE-POWER INSTRUMENT, AND
--       `live_rows = 0` WAS THE TRAP RATHER THAN THE RESULT.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- Validation for `0374` / `0375` / `0376`.
--
-- ══ 1. THE PAIR, RUN THE MOMENT 0374 WAS APPLIED ════════════════════════════
--
-- `0374` adds a per-tick call to `ottoq_sim_decide_and_dispatch` **above the policy
-- branch**, so it executes on every arm of every pair. If the fourteen-atom
-- byte-identical property did not survive that, the instrument would not be worth
-- having -- 2.9a calls reproducibility a product property, and R-12 established most
-- of this field cannot claim it at all.
--
--   ottoq_determinism_pair(171717, 12, 'busy_day', '11111111-…',
--                          '2026-09-01 02:00:00+00', 900)
--   fired 2026-09-20 12:41:37 UTC
--
--   arm A  5d3e2cd0-3022-4d67-b8f1-7fca72911e47  12 ticks  validation_status **passed**
--   arm B  552494b5-4fcc-4a7a-9b84-30db10be0233  12 ticks  validation_status **passed**
--   both `started_at` 12:41:37.855651 -- the same instant, because the pair runs both
--   arms in ONE transaction, which is the common-random-numbers engine `0145` named
--
--   ottoq_twin_determinism_verdict(A, B):
--     ticks_compared            12
--     ticks_identical           **12**
--     ticks_divergent            0
--     only_in_a / only_in_b      0 / 0
--     **deterministic          true**
--     first_divergence_sim_min   NULL
--
-- The detector is deterministic by construction -- it reads a stored snapshot and a
-- declared cap, and writes a row only on a threshold crossing -- but "by
-- construction" is what `0367` believed about `SKIP LOCKED` before `0371` had to take
-- it back out. This is the evidence, not the argument.

SELECT r.sim_run_id, r.tick_count, r.validation_status, r.started_at, r.status, r.random_seed
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 ORDER BY r.started_at DESC LIMIT 4;

-- ══ 2. THE LEDGER SURVIVED THE PAIR, WHICH IS THE EVIDENCE-CLASS POINT ══════
--
-- The pair resets the world. `0374`'s 16 backfilled readings -- the one excursion and
-- its 15 high_water neighbours -- were still there afterwards, at
-- `backfilled_rows = 16`, because the ledger is `class='evidence'` with no FK to
-- `ottoq_sim_runs`. Third demonstration of that property tonight after `0340`'s model
-- calls and `0364`'s proposal dispositions, and the second one observed rather than
-- argued.

SELECT * FROM public.ottoq_site_power_ledger;

-- ══ 3. AND THEN `live_rows = 0`, WHICH I NEARLY REPORTED AS A PASS ══════════
--
-- The same reading said **`live_rows = 0`**. That is the CORRECT outcome and I checked
-- why before believing it: the pair's peak grid import was **1,050.1 kW** against a
-- 1,500 kW (60% of 2,500) warn threshold, so the detector had nothing to record.
-- Confirmed by calling it by hand on the pair's own run, where it returned
--
--   {"tier": null, "total_kw": 498.2, "cap_kw": 2500, "headroom_kw": 2001.8}
--
-- and wrote nothing. So the function executes correctly on live data.
--
-- **BUT `live_rows = 0` IS ALSO WHAT A DETECTOR THAT NEVER EXECUTED WOULD PRODUCE,
-- AND NOTHING IN THE LEDGER TOLD THE TWO APART.** That is `G82` precisely:
-- `ottoq_release_unusable_reservations` was correct, wired into a function the live
-- engine never called, and its silence read as "nothing to do" for two migrations.
-- `0367` closed that hole by making the unreportable state reportable. **`0374`
-- reopened it in the code that fixed it** -- I had proved the function works and
-- *inferred* that the tick runs it, from `prosrc` matching
-- `ottoq_detect_site_power_excursion(`. Stronger evidence than `0360` ever had. Still
-- inference, not observation.
--
-- **Seventh instance of BUILD_QUEUE's standing heuristic** -- *do not look for what is
-- missing, look for what exists and is never called* -- and the first where the thing
-- that might never be called is something I wrote hours after writing the heuristic
-- down. That is the argument for mechanising a heuristic (`scripts/coverage-guard.sql`)
-- rather than remembering it.
--
-- `0376` closes it with a third tier, `armed`: one row per run on first execution, so
-- a run absent from it was never covered. Three implementation points, each a bug
-- avoided rather than a preference:
--   (a) the `snapshot_id` unique index had to become **partial** (`WHERE severity_tier
--       <> 'armed'`), because an `armed` row carries the first snapshot it saw and
--       that same instant can later qualify as `high_water` or `excursion` -- at which
--       point `ON CONFLICT (snapshot_id) DO NOTHING` would have silently suppressed
--       **the real finding**;
--   (b) the beacon dedups on the run via the 0020/0124 zero-uuid idiom, because NULL
--       is not equal to NULL in a unique index and a production call would otherwise
--       write a beacon every tick forever;
--   (c) an EXISTS probe, not `INSERT … ON CONFLICT`, because `nextval` is
--       non-transactional and a per-tick insert would burn a `bigserial` value each
--       time -- the mechanism behind `db/checks/0231`'s 28,262 absent ids.
--
-- **`detector_armed_runs` read 0 immediately after `0376` applied, and that was honest
-- rather than faulty.** The two runs predating the beacon are deliberately NOT
-- backfilled: their liveness is inferred, and writing a liveness record for inferred
-- liveness would fabricate exactly the assurance the beacon exists to provide.
--
-- ══ 3a. THEN A SECOND PAIR RAN, AND THE INFERENCE BECAME AN OBSERVATION ═════
--
-- The same call, fired again at **2026-09-20 12:48:31 UTC** with `0376` live:
--
--   arm A  cf59a904-8a78-4575-a4a8-48c65c2a4a76  12 ticks  **passed**
--   arm B  778b47c5-19a6-4452-a6cb-d7e29aaf9a68  12 ticks  **passed**
--   ottoq_twin_determinism_verdict: 12 compared, **12 identical**, 0 divergent,
--     **deterministic true**, first_divergence NULL
--
-- and the ledger then held:
--
--   severity_tier  source_kind   rows  runs   min_kw   max_kw
--   **armed        live            2     2     39.7     39.7**
--   excursion      backfill        1     1   2,738.8  2,738.8
--   high_water     backfill       15     1   1,514.8  1,713.8
--
-- **Two `armed` rows, two runs, `source_kind='live'` -- one per arm, written from
-- inside the tick path.** That is the observation `0374` could not produce and that
-- §3 was written to complain about: the detector provably executes inside
-- `ottoq_sim_decide_and_dispatch` on the path the metronome drives, and its silence
-- when the site is quiet is now distinguishable from its absence. 39.7 kW is a
-- first-tick reading on a freshly reset world, which is what it should be.
--
-- Three secondary things that pair also proved, each of which was a way `0376` could
-- have been wrong:
--   * **the beacon does not break determinism** -- 12 of 12 with it writing on both
--     arms, so the per-run write is symmetric as intended;
--   * **the `unique_violation` handler does not misfire** -- two arms in ONE
--     transaction produced two rows rather than one, because they carry different
--     `sim_run_id`s and the partial unique index is on the run, not the pair;
--   * **the partial `snapshot_id` index did not suppress anything** -- `0374`'s 16
--     backfilled rows are all still present alongside the new `armed` rows.

SELECT l.severity_tier, l.source_kind, count(*) AS rows,
       count(DISTINCT l.sim_run_id) AS runs,
       round(min(l.total_import_kw),1) AS min_kw,
       round(max(l.total_import_kw),1) AS max_kw
  FROM public.ottoq_site_power_excursion_ledger l
 GROUP BY 1,2 ORDER BY 1,2;

-- The two partial unique indexes are the whole safety of 0376. Asserted in its P4 and
-- worth being able to re-read here.

SELECT i.indisunique, i.indpred IS NOT NULL AS is_partial,
       pg_get_indexdef(i.indexrelid) AS def
  FROM pg_index i
 WHERE i.indrelid = 'public.ottoq_site_power_excursion_ledger'::regclass
 ORDER BY 2 DESC, 3;

-- ══ 4. WHAT THIS PAIR DOES *NOT* SHOW ═══════════════════════════════════════
--
-- Twelve ticks on a freshly reset world at ~1,050 kW peak exercises the detector's
-- quiet path only. It does **not** exercise the excursion path in the tick loop --
-- that path has been exercised only by `0374`'s backfill and by a direct call. So the
-- honest statement of coverage is:
--
--   * the detector is **deterministic inside the certified path** -- 12 of 12, twice,
--     before and after the beacon;
--   * it **executes inside the live tick path**, observed via two `armed` rows rather
--     than inferred from `prosrc`, and declines when the site is quiet;
--   * its **excursion branch is proven on stored data, not yet in a live tick**, and
--     will not be until a busy_day run coincides a BESS charge with a charging wave
--     again -- which on the evidence so far happens about once in 8,050 snapshots.
--
-- The beacon is what makes that last gap visible instead of invisible, which is the
-- most that can honestly be claimed tonight.

-- ══ 5. THE `ON CONFLICT` INFERENCE HAD TO BE EXERCISED, AND THE TEST LITTERED ═
--
-- `0376` rewrote the detector's finding-INSERT to
-- `ON CONFLICT (snapshot_id) WHERE severity_tier <> 'armed' DO NOTHING`, because the
-- unique index became partial. **That inference resolves when the statement runs, not
-- when the function is created** -- so `0376` applying cleanly proved nothing about it,
-- and a wrong inference would have raised inside the detector, been swallowed by
-- `decide_and_dispatch`'s handler as a WARNING, and **silently lost an excursion.**
-- The exact failure mode this whole night has been about, one layer deeper.
--
-- Exercised by calling the detector with `p_warn_frac := 0.001` on run `cf59a904`,
-- twice:
--
--   first call   tier high_water · **written 1** · armed false · total 498.2 kW
--   second call  tier high_water · **written 0** · armed false · same snapshot
--
-- Insert correct, dedup correct, and `armed false` on both confirms the beacon does not
-- re-fire within a run.
--
-- **THE TEST WAS RIGHT AND THE METHOD WAS SLOPPY.** It should have run in a transaction
-- that rolled back; instead it wrote a **498.2 kW row tiered `high_water`** into an
-- append-only evidence table. `high_water` means "crossed 60% of the declared cap" --
-- 1,500 kW here -- and the tier exists precisely to characterise the tail after a purge,
-- so with that row present the tail read `min_kw = 498.2` and any reader would conclude
-- the site crossed 60% of a 2,500 kW contract at 498 kW. **The threshold that produced
-- it is not visible in the row** (`warn_kw` held 2.5, and nobody reads a row's
-- `warn_kw` before quoting its tier). A tier whose membership depends on an argument
-- nobody sees is worse than no tier.
--
-- Removed by `0377` under the append-only override, as that guard's own message
-- instructs -- deleted rather than annotated because append-only leaves no UPDATE to
-- mark it with. The ledger now reads, correctly:
--
--   armed        live        2    39.7 -    39.7
--   excursion    backfill    1  2,738.8 - 2,738.8
--   high_water   backfill   15  1,514.8 - 1,713.8
