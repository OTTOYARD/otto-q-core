-- 0328  **λ IS ANSWERED, and it needs no re-tuning — for a quantitative reason rather than a cautious
--       one. With one λ = 0.00088 per eligible vehicle-hour, the model predicts 1.12 faults/sim-day at
--       the certification scenario's measured exposure and 1.97 at the demo scenario's. Chase's operating
--       assumption is 1–2 per day. The two predictions very nearly span it exactly.**
--
--       The run that answered it arrived 2.5 hours before the check-in expected: `0420`'s
--       `forces_recert=TRUE` triggered the recert sweep, cron 746 ran all nine canons between 09:34 and
--       10:10 UTC, and the last is the 48-tick / 24-sim-hour `cert_harness` pair `0327` §7 predicted would
--       be the measurement vehicle. **All nine pairs PASSED, 14 of 14 atoms, which independently
--       validates `0420`.**
--
--       **AND §3 RETRACTS THE EXPOSURE FIGURES IN `0324`, `0327` AND THE FIRST DRAFT OF THIS FILE.** The
--       segment reconstruction they all use is non-deterministic on this data. No migration.
--
--       Measured 2026-09-22 ~12:15 UTC (07:15 CT) on arm `c32754de-a827-4eef-97e6-d4382a6e8513`
--       (busy_day, seed 171717, 48 ticks, twin depot, `run_by='cert_harness'`, fixed playback).
--
-- ══ §1 THE RECERT SWEEP DISCHARGED ITSELF AND VALIDATED `0420` ═════════════════
--
--     certified_at   scenario     seed     ticks   outcome   atoms   disagreeing
--     ------------   ----------   ------   -----   -------   -----   -----------
--     09:34:16       busy_day     314159      12   passed       14   {}
--     09:37:23       busy_day     424242      12   passed       14   {}
--     09:40:38       normal_day   171717      12   passed       14   {}
--     09:44:02       busy_day     171717      24   passed       14   {}
--     09:50:36       busy_day     424242      24   passed       14   {}
--     09:58:03       busy_day     171717   **48**   passed       14   {}
--
--     canons enabled 9 / satisfying floor **9** / still awaiting **0**
--
-- **This is load-bearing, not a formality.** `0420` raised the fixed-mode fault hazard **60x**, and its §4
-- predicted every downstream atom would move while determinism itself survived — because in fixed mode the
-- tick advance is a pure function of two stored run columns. **Nine pairs, zero disagreements,
-- `complete=true` throughout.** The prediction held.
--
-- **And the arm confirms `0420`'s premise from its own payload rather than by inference:**
-- `payload->>'tick_minutes_actual'` reads **exactly 30.0 minutes** over 48 ticks = 24.00 sim-hours. That
-- is the number `0413` divided by 3600 as though it were 30 *seconds*. The 60x is in the run's data.
--
-- ══ §2 THE VALUE CHECK, ON THE CORRECTED METHOD OF §3 ═════════════════════════
--
--     sim hours                                        24.00
--     total vehicle-hours                            2,784.0
--     116 vehicles x 24.00 sim-hours                 2,784.0    -> **100.0% of the truth, uncensored**
--     ELIGIBLE vehicle-hours                         1,269.5    (45.6% eligible share)
--     expected faults at λ = 0.00088                    1.117
--     OBSERVED                                              0
--     P(observing zero | λ)                             32.7%
--     95% upper bound on λ from zero events           0.00236
--
-- **Zero against 1.12 expected is a 33% outcome, not a deviation.** So the realised rate is **consistent
-- with λ**; one run with zero events can only bound a value, never confirm it. What the bound does exclude
-- matters: **0.00236 is below the 0.00334 the engine was effectively applying in live mode before
-- `0420`** (0.00088 x 3.80). So this run rules out the pre-fix effective rate at 95% while accommodating
-- the intended one — `0420` is validated in the direction that counts.
--
-- ══ §3 THE RETRACTION: THE EXPOSURE MEASUREMENT WAS NON-DETERMINISTIC ══════════
--
-- `0324` §1, `0327` §2–§3 and this file's first draft all reconstruct exposure the same way: order a
-- vehicle's `vehicle.state_changed` events by `sim_clock_at`, treat consecutive events as segment
-- boundaries, and sum the segments whose state is one of the seven eligible ones. **On this data that
-- ordering is not a total order, so the result is arbitrary.**
--
--     state-change events on the arm                 1,734
--     DISTINCT sim_clock_at values                      49   <- one per tick, as designed
--     events per clock value                          35.4
--     **same vehicle, same sim_clock, >1 event**       418
--
-- Every event in a tick carries that tick's sim clock, so `ORDER BY sim_clock_at` leaves 35 rows tied at
-- each of 49 timestamps, and **418 of those ties are the same vehicle changing state more than once inside
-- one tick.** `row_number()` then picks an arbitrary "first" state and `lead()` pairs arbitrary neighbours,
-- so which state a segment is credited to is decided by nothing.
--
-- **Measured: three readings of the same completed run gave 1,484.0, then 1,577.0, then 1,269.5 eligible
-- vehicle-hours** — a 24% spread with the data frozen. The first two were the unstable method; 1,269.5 is
-- the corrected one, and it is **lower than both**, so the old method **overstated exposure** and
-- therefore **understated** implied faults per day.
--
-- **The fix is semantic, not just a tiebreak.** A vehicle that goes A→B→C inside one tick spent **zero sim
-- time in B** — the tick is the world's time quantum. So collapse to one row per `(vehicle, sim_clock)`
-- taking the **last** state at that clock (`DISTINCT ON … ORDER BY event_seq DESC`, with the segment
-- before the first event taking the **first** `from` state), then segment between distinct clock values.
-- Re-run twice on frozen data: **1,269.50 both times.** Deterministic.
--
-- **This is the fifth exposure-denominator defect in this area and the first that was not a wrong unit but
-- a wrong ORDER** — after `0413` §2's `occurred_at`, `0324` §1's censoring, `0327` §1's tick-count ETA and
-- `0420`'s cadence-for-advance. The shape they share: *a denominator that looks measured and is not.*
--
-- **What survives unchanged:** every *ratio* and every *conclusion*. `0324` §1's discrimination between
-- the two dials (11.5 expected vs 0.021, P = 1e-5 under the old one) holds at any exposure in this range;
-- `0327` §2's 100.0%-of-truth result is a ratio of two sums computed the same way; `0327` §3's "neither λ
-- excluded" holds. **Only the absolute vehicle-hour figures move**, and only by tens of percent. Recorded
-- as a retraction rather than a silent edit because those figures were published.
--
-- ══ §4 THE FINDING THAT SETTLES THE RE-TUNE QUESTION: EXPOSURE IS NOT A CONSTANT ═
--
-- The check-in's step 4 anticipated re-deriving `0413`'s denominator, because `0413` took **1,706.9**
-- eligible vehicle-hours per sim-day from the *contaminated* baseline `d68d05bb`. Two clean measurements,
-- on the corrected method:
--
--     run                                     eligible share   eligible vh/sim-day   faults/day at λ
--     -------------------------------------   --------------   -------------------   ---------------
--     `c32754de` cert, busy_day/171717, fixed         45.6%                 1,269              1.12
--     `61cedc05` demo, busy_day/700001, live          80.4%                 2,239              1.97
--
-- **Same scenario code, same depot, same λ — and exposure differs by 76%.** How long vehicles dwell in the
-- seven eligible states depends on load, tick size and what the policy does with them. **So there is no
-- single "eligible vehicle-hours per sim-day" to calibrate against.** `0413`'s 1,706.9 was not merely
-- contaminated; it was the wrong *kind* of number — a scenario-dependent quantity used as a constant.
-- Replacing it with 1,269 would repeat the mistake on a cleaner input.
--
-- **AND THE MODEL IS ALREADY RIGHT, WHICH IS THE POINT.** `0413` chose the physically correct denominator:
-- a hazard **per eligible vehicle-hour**, because a vehicle sitting in a depot state accrues risk while it
-- sits. Under that model, faults per day is an **output** that varies with exposure, not an input to pin.
-- Evaluated at both exposures actually measured, one untuned λ gives **1.12 and 1.97 faults/day against a
-- stated range of 1–2.**
--
-- **THE SENTENCE TO QUOTE:** *"λ = 0.00088 per eligible vehicle-hour predicts 1.12 faults/sim-day at the
-- certification scenario's measured exposure and 1.97 at the demo scenario's, against an operating
-- assumption of 1–2 per day. Zero faults were observed on a 24-sim-hour certified run expecting 1.12
-- (P = 33%), which bounds λ at ≤ 0.00236 (95%) and excludes the 0.00334 the engine applied before
-- `db/migrations/0420`."*
--
-- ══ §5 WHAT IS STILL NOT SHOWN ════════════════════════════════════════════════
--
-- **The value is bounded, not confirmed.** All of §2 rests on zero events; a single 24-sim-hour run cannot
-- separate λ = 0.00088 from λ = 0.0015. The ladder, now three rungs:
--
--   1. `0324`: the unit fix validated as a **correction**.
--   2. `0420` + this file: the *conversion* validated, and the realised rate **consistent with λ and
--      bounded below the pre-fix effective rate**.
--   3. Open: λ validated as a **value**, needing ~5 pooled 48-tick arms (~5.6 expected faults). That is
--      cheap now — the sweep yields one per recert — so it should be **accumulated, not chased**.
--
-- **And do not read §1's nine passes as evidence the fault path was exercised.** At 1.12 expected per
-- 48-tick arm most arms see none, and the 12- and 24-tick arms expect 0.28 and 0.56. **A passing pair with
-- zero faults does not test the fault path**, so `0420`'s determinism claim is confirmed for the arms that
-- ran and **not yet on a run where a vehicle actually broke.** That is the blind spot to close next, and it
-- is 2.9a's doctrine applied to this fix: the interesting pair is the first that condemns a vehicle in both
-- arms and still agrees on fourteen atoms.
--
-- ══ §6 POOLED OVER ALL NINE CELLS: A MARGINAL SIGNAL, AND NO MORE EVIDENCE IS
--       COMING FROM RECERTS — WHICH RETRACTS §5's OWN PLAN ══════════════════════
--
-- §5 said to *"pool ~5 48-tick arms, which the sweep yields free."* **That is impossible and the reason is
-- determinism itself.** There is exactly ONE 48-tick canon (`busy_day` / seed 171717), and a deterministic
-- engine on a fixed seed reproduces the identical fault count at every recert. Repeated sweeps add no
-- information whatever. **The two arms of a pair are likewise one draw, not two** — that they agree is the
-- thing being certified.
--
-- **The independent evidence is the nine CANON CELLS, and they are all available now:**
--
--     scenario     seed     ticks   eligible_vh   expected   observed
--     ----------   ------   -----   -----------   --------   --------
--     busy_day     171717      48       1,269.5      1.117          0
--     busy_day     424242      24         787.5      0.693          0
--     busy_day     171717      24         648.0      0.570          0
--     busy_day     424242      12         378.5      0.333          0
--     busy_day     314159      12         337.0      0.297          0
--     busy_day     171717      12         327.5      0.288          0
--     normal_day   171717      12         305.0      0.268          0
--     grid_smoke   239001       6           2.0      0.002          0
--     grid_smoke   424242       6           1.0      0.001          0
--     ----------------------------------------------------------------
--     POOLED                              4,056.0    **3.569**      **0**
--
--     P(observing zero | λ) = exp(-3.569) = **2.8%**      95% upper bound = 3/4,056 = **0.00074**
--
-- **So the realised rate is below λ at the 5% level, and λ = 0.00088 sits above the bound.** Before
-- treating that as a calibration verdict, four things were checked and all four are correct:
--
--   1. **The handler runs.** Both depots are `feed_mode='sim'`, so the `IF v_feed_sim` gate passes, and
--      `production_live` runs have condemned vehicles — the path works.
--   2. **The hazard is right.** `ottoq_vehicle_fault_per_tick` returns **4.399e-4** on the cert arms,
--      exactly `1-exp(-0.00088 × 30/60)` for `0420`'s 30-minute fixed-mode tick, with
--      `ottoq_profile_rate_mult = 1` and λ = 0.00088 in force.
--   3. **The exposure matches the handler's own eligibility**, read from its source: `category='autonomous'`
--      (116 at the twin, and the 4 `retail` contribute nothing), `NOT jsonb_exists(config,'exception')`
--      (zero already-excepted), and exactly the seven states — whose vehicle-hours sum to **1,269.5**, the
--      figure §2 uses, against 1,514.5 in the excluded states for 2,784.0 total.
--   4. **The RNG is uniform.** 5,568 draws of `twin.ottoq_sim_seeded_random` over the real vehicle ids:
--      mean **0.50144** (0.5), stddev **0.28705** (0.28868), range 0.000250–0.999713, and **1** draw below
--      the cert hazard against 2.45 expected — ordinary Poisson noise, P = 29%.
--
-- **AND A NUMERATOR TRAP CAUGHT ON THE WAY, which nearly reversed this section.** An intermediate count
-- found **39 "fault events"** in the arms and I briefly concluded λ was vindicated. They are all
-- `charge.session_faulted` on `ocpp_session` entities — **charger faults from a different mechanism
-- entirely.** Vehicle faults are zero, confirmed three independent ways: no `tow_requested`, no vehicle
-- gaining `config.exception` (the diff shape was verified, not assumed), and **none of the handler's own
-- four event types** (`ottoq.bay_eviction`, `ottoq.bay_eviction_deferred`, `vehicle.technician_approved`,
-- `vehicle.tow_retrieved_staged`) appearing at all. Counting the wrong numerator is the same family as
-- counting the wrong denominator, and it was one query from publishing the opposite conclusion.
--
-- **WHAT TO DO: nothing yet, and specifically do not re-tune.** P = 2.8% is a one-in-thirty-five outcome
-- from a single sweep, the deviation is in the operationally safe direction, and §4's finding stands that
-- exposure varies enough between scenarios that a single λ cannot match every faults/day figure anyway.
-- **What it does mean is that more evidence requires NEW CANON CELLS — different seeds — not more
-- sweeps.** Adding two or three 48-tick cells at fresh seeds would roughly triple the pooled exposure per
-- sweep and settle this properly. That is a change to `ottoq_determinism_canon` and a recert cost, so it
-- is Chase's to authorise, not a thing to do quietly.

\echo '=== 0328 §1 — the recert sweep discharged itself, and every pair passed ==='
SELECT certified_at, scenario, seed, ticks, outcome, equal, complete,
       atoms_compared, disagreeing_atoms, null_atoms
  FROM public.ottoq_determinism_verdict_ledger
 WHERE certified_at >= '2026-09-22 09:00:00+00'
 ORDER BY certified_at;

\echo '=== 0328 §1 — the canon backlog 0420 created is empty again ==='
SELECT count(*) AS enabled,
       count(*) FILTER (WHERE satisfies_floor) AS satisfy_floor,
       count(*) FILTER (WHERE NOT satisfies_floor) AS still_awaiting
  FROM public.ottoq_determinism_canon WHERE enabled;

\echo '=== 0328 §1 — 0420s premise, from the arms own payload: 30 MINUTES, not 30 seconds ==='
SELECT run_by, tick_count,
       (payload->>'tick_minutes_actual')::numeric AS tick_minutes_actual,
       (payload->>'playback_mode')                AS playback_mode,
       tick_interval_seconds AS what_0413_read_as_seconds, time_scale,
       round(EXTRACT(epoch FROM (sim_clock_current - sim_clock_start))/3600.0, 2) AS sim_hours
  FROM public.ottoq_sim_runs WHERE sim_run_id='c32754de-a827-4eef-97e6-d4382a6e8513';

\echo '=== 0328 §3 — WHY the old exposure measure was arbitrary: 49 clocks, 418 same-vehicle ties ==='
SELECT count(*) AS state_change_events,
       count(DISTINCT sim_clock_at) AS distinct_sim_clocks,
       round(count(*)::numeric / NULLIF(count(DISTINCT sim_clock_at),0), 1) AS events_per_clock_value,
       count(*) - count(DISTINCT (entity_id, sim_clock_at)) AS same_vehicle_same_clock_ties
  FROM public.ottoq_events
 WHERE sim_run_id='c32754de-a827-4eef-97e6-d4382a6e8513'
   AND event_type='vehicle.state_changed' AND payload->'diff' ? 'current_state';
-- 1,734 events on 49 distinct clocks. ORDER BY sim_clock_at is not a total order here, and 418 of the
-- ties are one vehicle changing state twice inside a single tick -- where the intermediate state has
-- ZERO sim duration. The old measure credited segments to states by nothing at all.

\echo '=== 0328 §2+§4 — the corrected, DETERMINISTIC exposure, and lambda at both levels ==='
WITH runs(label, rid) AS (VALUES
  ('1 cert busy_day/171717 48t fixed', 'c32754de-a827-4eef-97e6-d4382a6e8513'::uuid),
  ('2 demo busy_day/700001 live',      '61cedc05-fa8a-44f0-8a31-5cd6404404ff'::uuid)
), r AS (
  SELECT runs.label, s.sim_run_id, s.sim_clock_start AS t0, s.sim_clock_current AS t1,
         EXTRACT(epoch FROM (s.sim_clock_current - s.sim_clock_start))/3600.0 AS sim_hours
    FROM runs JOIN public.ottoq_sim_runs s ON s.sim_run_id = runs.rid
), ev AS (
  -- §3's fix: one row per (vehicle, sim_clock), taking the LAST state at that clock. A state entered and
  -- left inside one tick held the vehicle for zero sim time, so it must not receive a segment.
  SELECT DISTINCT ON (r.label, e.entity_id, e.sim_clock_at)
         r.label, r.t0, r.t1, r.sim_hours, e.entity_id AS vid, e.sim_clock_at AS t,
         e.payload->'diff'->'current_state'->>'to' AS st_to,
         first_value(e.payload->'diff'->'current_state'->>'from')
           OVER (PARTITION BY r.label, e.entity_id, e.sim_clock_at ORDER BY e.event_seq) AS st_from_first
    FROM public.ottoq_events e JOIN r ON r.sim_run_id = e.sim_run_id
   WHERE e.event_type='vehicle.state_changed' AND e.payload->'diff' ? 'current_state'
   ORDER BY r.label, e.entity_id, e.sim_clock_at, e.event_seq DESC
), seg AS (
  SELECT label, sim_hours, vid, st_from_first AS st, t0 AS a, t AS b
    FROM (SELECT *, row_number() OVER (PARTITION BY label, vid ORDER BY t) rn FROM ev) q WHERE rn=1
  UNION ALL
  SELECT label, sim_hours, vid, st_to, t,
         COALESCE(lead(t) OVER (PARTITION BY label, vid ORDER BY t), t1) FROM ev
), agg AS (
  SELECT label, max(sim_hours) AS sim_hours,
         sum(EXTRACT(epoch FROM (b-a)))/3600.0 AS total_vh,
         sum(EXTRACT(epoch FROM (b-a))) FILTER (WHERE st IN
           ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay','in_service_bay',
            'charge_complete_holding','staged_awaiting_service'))/3600.0 AS eligible_vh
    FROM seg WHERE b>a GROUP BY label
)
SELECT a.label, round(a.sim_hours::numeric,2) AS sim_hours,
       round(a.total_vh::numeric,1) AS total_vh,
       round((100.0*a.total_vh/(116*a.sim_hours))::numeric,1) AS pct_of_truth,
       round(a.eligible_vh::numeric,1) AS eligible_vh,
       round((100.0*a.eligible_vh/a.total_vh)::numeric,1) AS eligible_share_pct,
       round((a.eligible_vh/a.sim_hours*24)::numeric,0) AS eligible_vh_per_sim_day,
       round((0.00088*a.eligible_vh/a.sim_hours*24)::numeric,2) AS faults_per_sim_day_at_lambda,
       round((0.00088*a.eligible_vh)::numeric,3) AS expected_faults_this_run,
       round(exp(-0.00088*a.eligible_vh)::numeric,3) AS p_of_zero,
       round((3.0/NULLIF(a.eligible_vh,0))::numeric,5) AS upper_95_bound_on_lambda
  FROM agg a ORDER BY a.label;
-- 45.6% vs 80.4% eligible share on the same scenario code and depot -> 1,269 vs 2,239 eligible
-- vehicle-hours per sim-day -> 1.12 vs 1.97 faults/day at ONE untuned lambda, against a stated 1-2.
-- There is no single denominator to re-tune against, which is why 0413's 1,706.9 was the wrong KIND of
-- number rather than merely a contaminated one.

\echo '=== 0328 §6 — pooled over all nine canon cells: 4,056 eligible vh, 3.569 expected, 0 observed ==='
WITH pairs AS (
  SELECT scenario, seed, ticks, arm_a_run AS rid
    FROM public.ottoq_determinism_verdict_ledger
   WHERE certified_at >= '2026-09-22 09:00:00+00'
), r AS (
  SELECT p.scenario, p.seed, p.ticks, p.rid, s.sim_clock_start AS t0, s.sim_clock_current AS t1
    FROM pairs p JOIN public.ottoq_sim_runs s ON s.sim_run_id = p.rid
), ev AS (
  SELECT DISTINCT ON (r.rid, e.entity_id, e.sim_clock_at)
         r.rid, r.scenario, r.seed, r.ticks, r.t0, r.t1, e.entity_id AS vid, e.sim_clock_at AS t,
         e.payload->'diff'->'current_state'->>'to' AS st_to,
         first_value(e.payload->'diff'->'current_state'->>'from')
           OVER (PARTITION BY r.rid, e.entity_id, e.sim_clock_at ORDER BY e.event_seq) AS st_from_first
    FROM public.ottoq_events e JOIN r ON r.rid = e.sim_run_id
   WHERE e.event_type='vehicle.state_changed' AND e.payload->'diff' ? 'current_state'
   ORDER BY r.rid, e.entity_id, e.sim_clock_at, e.event_seq DESC
), seg AS (
  SELECT rid, scenario, seed, ticks, vid, st_from_first AS st, t0 AS a, t AS b
    FROM (SELECT *, row_number() OVER (PARTITION BY rid, vid ORDER BY t) rn FROM ev) q WHERE rn=1
  UNION ALL
  SELECT rid, scenario, seed, ticks, vid, st_to, t,
         COALESCE(lead(t) OVER (PARTITION BY rid, vid ORDER BY t), t1) FROM ev
), agg AS (
  SELECT rid, scenario, seed, ticks,
         sum(EXTRACT(epoch FROM (b-a))) FILTER (WHERE st IN
           ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay','in_service_bay',
            'charge_complete_holding','staged_awaiting_service'))/3600.0 AS eligible_vh
    FROM seg WHERE b>a GROUP BY rid, scenario, seed, ticks
)
SELECT round(sum(a.eligible_vh)::numeric,1)              AS pooled_eligible_vh,
       round(sum(0.00088*a.eligible_vh)::numeric,3)      AS pooled_expected_faults,
       sum((SELECT count(DISTINCT e2.entity_id) FROM public.ottoq_events e2
             WHERE e2.sim_run_id=a.rid AND e2.event_type='vehicle.state_changed'
               AND e2.payload->'diff'->'current_state'->>'to'='tow_requested')) AS observed_tows,
       (SELECT count(*) FROM public.ottoq_events e3
         JOIN pairs p3 ON p3.rid = e3.sim_run_id
        WHERE e3.event_type IN ('ottoq.bay_eviction','ottoq.bay_eviction_deferred',
                                'vehicle.technician_approved','vehicle.tow_retrieved_staged'))
                                                          AS observed_handler_events,
       round(exp(-sum(0.00088*a.eligible_vh))::numeric,4) AS p_of_zero,
       round((3.0/NULLIF(sum(a.eligible_vh),0))::numeric,5) AS upper_95_bound_on_lambda
  FROM agg a;
-- Nine cells are the ENTIRE independent evidence base: one 48-tick canon exists, and a deterministic
-- engine on a fixed seed reproduces the same fault count at every recert, so repeated sweeps add nothing.
-- More evidence needs NEW SEEDS in ottoq_determinism_canon, which is a recert cost and Chase's call.

\echo '=== 0328 §6 — the RNG is uniform, so the zero is not a biased draw ==='
WITH vids AS (SELECT id FROM public.vehicles
               WHERE home_depot_id='11111111-1111-1111-1111-111111111111' AND category='autonomous'),
     ticks AS (SELECT generate_series(1,48) AS t),
     rolls AS (
  SELECT twin.ottoq_sim_seeded_random(
           abs(hashtextextended('11111111-1111-1111-1111-111111111111'||'salt'||t::text||'vexc', 17)),
           'roll:'||v.id::text) AS r
    FROM vids v CROSS JOIN ticks)
SELECT count(*) AS draws,
       round(avg(r)::numeric,5)    AS mean_expect_0_50000,
       round(stddev(r)::numeric,5) AS stddev_expect_0_28868,
       round(min(r)::numeric,6) AS min, round(max(r)::numeric,6) AS max,
       count(*) FILTER (WHERE r < 0.0004399) AS below_cert_hazard,
       round((count(*)*0.0004399)::numeric,2) AS expected_below_if_uniform
  FROM rolls;
-- A distributional test of the hash, not a replay of the actual rolls (the real salt is
-- twin.ottoq_sim_clock_salt(run, clock)). Uniformity is what it establishes, and that is what matters:
-- the zero is not an artefact of a skewed generator.
