-- 0294  THE `0390` VERIFICATION: BOTH OF ITS MECHANICAL PREDICTIONS CONFIRMED, ITS ENACTED SHARE
--       **DOWN** RATHER THAN UP — AND THE CROSS-RUN PAIR IS **CONFOUNDED BY A SECOND VARIABLE I
--       CHANGED MYSELF**, SO THAT LAST NUMBER CANNOT BE ATTRIBUTED TO `0390` AT ALL. THE CLEAN
--       RESULT IS THE WITHIN-RUN SPLIT, AND IT IS STARKER THAN THE PAIR WOULD HAVE BEEN.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
--   POST-FIX  `e8b8eb3e-da9d-41ff-ab67-84b6998ba441`  busy_day, seed 100020, 1,041+ ticks
--   PRE-FIX   `c8f678fb-a04a-4c18-a937-9b93673f3fe9`  busy_day, seed 100020, 1,224 ticks
-- Identical seed AND identical `sim_clock_start` (2026-09-20T05:35:00+00), so the arrival stream
-- is reproducible by construction — the twin's RNG is stateless and content-addressed
-- (`twin.ottoq_sim_seeded_random`, hardened by `0052`), which is the whole reason a pair like this
-- is possible. Pre-fix figures are quoted from `0288`/`0290`; `c8f678fb` itself is `class='engine'`
-- and has been purged.
--
-- ══ 1. THE MEASUREMENT, ALL FOUR COMPARISONS ═══════════════════════════════
--
--                                    c8f678fb        e8b8eb3e
--                                    (pre-0390)      (post-0390)
--   forward_lex proposals                610             **973**
--   distinct vehicles                     56              **65**
--   proposals per vehicle              10.89           **14.97**
--   abstentions                     213 (35%)      **685 (70.4%)**
--   first-refusal holds armed              63              **81**
--   planning fires / total fires      76 / 364        **42 / 290**
--   enacted stall_assignments      240 / 98 veh    **263 / 93 veh**
--   **forward_lex enacted**         **12 (5.0%)**    **6 (2.3%)**
--   proposals per enactment             50.8           **162.2**
--
-- **`0390`'s TWO MECHANICAL PREDICTIONS BOTH VERIFIED.** The check-in that scheduled this
-- measurement stated them in advance, which is the only reason they count as predictions:
-- *"more first-refusal holds armed (abstentions no longer exclude vehicles from arming), and
-- forward_lex retrying vehicles it abstained on. It does NOT predict fewer proposals."* Holds
-- **63 → 81**; proposals per vehicle **10.89 → 14.97**. Both directions as stated.
--
-- ══ 2. AND THE ENACTED SHARE WENT **DOWN**, WHICH I CANNOT BLAME ON `0390` ══
--
-- 5.0% → 2.3%. The check-in also said what to do with that — judge on enacted share, and report a
-- null result as a null result. **But this is not a null result and it is not a regression either,
-- because I am not entitled to attribute it: I changed a second variable in the same window.**
--
-- Between the two runs I widened the CI loop's serviceable states to
-- `arrived_at_gate,staged_awaiting_service`, raised its fire cap 12 → 400, and cut its interval
-- 20s → 8s. So:
--
--   - the **world** is identical (same seed, same clock, verified reproducible by construction);
--   - the **proposer** is not the same proposer, at two levels: a different code version AND a
--     different population, cadence and budget.
--
-- **This is `0146`'s lesson committed by me, in the experiment built to honour it.** `0146` is the
-- finding that a policy comparison must not swap the constraint set along with the policy — *"the
-- L1 shield sits on the hold-constant side of the A/B, exactly as the seed does."* I held the seed
-- and the clock with real care and then moved three knobs on the instrument. **Seed discipline
-- without instrument discipline buys a reproducible world and an unreadable answer**, and no run
-- id can repair it. The `0290` §2 lesson reappears one level up: fix the instrument, THEN read it.
--
-- So the honest verdict on `0390`: **correct on its own terms and mechanically verified; its effect
-- on enacted share is UNMEASURED and this run cannot measure it.** `0390` stands as what it always
-- was — an abstention is not a claim, and two predicates counted it as one — which is a correctness
-- fix that needs no KPI to justify it.
--
-- **WHAT WOULD MEASURE IT:** one more run at seed 100020 with `0390` in and the loop configured
-- exactly as `c8f678fb`'s was (states `arrived_at_gate` only, fires 12, interval 20s). That is one
-- variable, and it is cheap. Recorded rather than run here, because the loop config is committed
-- and the next run is not this one.

WITH fl AS (
  SELECT status, COALESCE(proposal->>'abstain','') IN ('true','t','1') AS abstained, entity_id
    FROM public.ottoq_external_proposals
   WHERE sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441' AND source = 'forward_lex')
SELECT count(*) AS proposals,
       count(DISTINCT entity_id) AS vehicles,
       round(count(*)::numeric / NULLIF(count(DISTINCT entity_id), 0), 2) AS per_vehicle,
       count(*) FILTER (WHERE abstained) AS abstentions,
       round(100.0 * count(*) FILTER (WHERE abstained) / NULLIF(count(*), 0), 1) AS pct_abstained,
       (SELECT count(*) FROM public.ottoq_cuopt_deferrals
         WHERE sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441') AS holds_armed
  FROM fl;

-- ══ 3. THE CLEAN RESULT IS THE WITHIN-RUN SPLIT, AND IT IS STARKER ═════════
--
-- A within-run split needs no cross-run comparison and therefore carries none of §2's confound:
-- one run, one seed, one proposer version, one loop configuration, split at tick 424 — the
-- boundary between the night tail and the return wave, which is when the CI loop was re-dispatched
-- into the arriving fleet.
--
--   enacted `stall_assignment`      night tail (<=424)    **wave (>424)**
--     deterministic_v1                      50              **141  (83%)**
--     reservation_honoured                  31                12
--     reservation_reopt                      3                 6
--     greedy_constrained                     1                 5
--     reservation_reassigned                 0                 3
--     cuopt                                  1                 2
--     **forward_lex**                      **6**             **0**
--
-- **CP-SAT submitted roughly 900 proposals into the wave and enacted ZERO.** All six of its wins
-- came from the night tail, when the depot was nearly idle. The local deterministic path took 83%
-- of the wave. At the wave's peak (07:08 CT, tick 877) the depot held **10 `arrived_at_gate` and
-- 36 `staged_awaiting_service`** — 46 vehicles wanting service against `c8f678fb`'s 5 and 19 at
-- the same point, so this run presented nearly twice the load and CP-SAT's contribution under it
-- was nil.
--
-- **AND THE MECHANISM IS FULLY ACCOUNTED FOR, in two parts that do not overlap:**
--
--   (a) **It declines.** **685 of 973 rows (70.4%) are abstentions**, and the reason each one
--       carries is *"planned to start at +N min ... beyond this tick's 30-min window; re-offered
--       when due"*. For seven vehicles in ten CP-SAT's answer is "not within thirty minutes."
--       **That is `0288`'s capacity wall seen from the solver's side** — same site, same run whose
--       `p95_time_to_service` went 2.7 → 39.6 min — and it is the solver being correct, not weak.
--   (b) **Of what it does claim, it loses the tie-break.** `0184`'s finding (a `forward_lex` row is
--       heard but loses to the local path's regenerated row by `created_at`), now at wave volume.
--
-- Note which of the two matters: (a) is a **capacity** statement about the depot, (b) is a
-- **precedence** statement about the engine. Only (b) is fixable by anything on this page, and
-- `0290` §4 ranks it SECOND on purpose — behind the instrument.

SELECT COALESCE(enacted_action->>'source', l2_engine, '(null)') AS src,
       count(*) FILTER (WHERE tick_seq <= 424) AS night_tail,
       count(*) FILTER (WHERE tick_seq  > 424) AS wave,
       count(*) AS total,
       count(DISTINCT entity_id) AS vehicles
  FROM public.ottoq_decisions
 WHERE sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441'
   AND action_context = 'stall_assignment' AND outcome_status = 'enacted'
 GROUP BY 1 ORDER BY 4 DESC;

-- ══ 4. G102 — THE CHURN'S ROOT CAUSE, FOUND AND FIXED ══════════════════════
--
-- `0290` §4 ranked cutting the churn first, and named it proposer-side. The mechanism is now exact.
--
-- `only_due_now`'s own docstring: a not-due row *"is re-offered by the next fire, whose plan will
-- have moved it forward."* **The loop fires every 8 seconds, and a plan 131 minutes out has not
-- moved forward in 8 seconds** — so the identical abstention goes through the door again, and
-- again. 685 of 973 rows. One payload read in full settles it:
--
--     {"abstain": true, "rationale": {"abstained_by": "bridge:not_due",
--      "planned_start_min": 131, "reason": "planned to start at +131 min on l2 ...,
--      beyond this tick's 30-min window; re-offered when due", ...}}
--
-- **The due time was in the row the whole time and nothing read it.** Fixed in
-- `bridge/proposer_bridge.py` by two pure helpers — `suppress_not_due` withholds a vehicle until
-- the sim clock reaches the moment its own abstention declared (planned start within
-- `start_within_min` of now), `remember_not_due` records it from the loop's own output. Six tests,
-- including the case where a later plan moves EARLIER and must shorten the suppression rather than
-- be trapped by the first answer.
--
-- **Fail-open in three independent ways** — no clock, no entry, or an unreadable
-- `planned_start_min` all mean "plan it", i.e. exactly today's behaviour — so the change can only
-- ever REMOVE a redundant row and never withhold a vehicle nobody has answered for. And
-- **deliberately forgetful between CI invocations**: withholding on the strength of a plan from a
-- previous loop would be the `G54` defect, asking a narrower question than the kernel asks. Both
-- counts are published on the fire record (`n_suppressed_not_due`, `n_not_due_remembered`) because
-- *absent because already answered* must be distinguishable from *absent because unseen* — the
-- discipline `n_vehicles_held` and `frame_facts_version` already carry.
--
-- **NOT DEPLOYED DURING THIS RUN, and that is the §2 lesson applied immediately**: it lands on the
-- next loop dispatch, so two proposer versions never share one run's ledger. Having just discovered
-- that I confounded a comparison by changing the instrument mid-window, the minimum is not to do it
-- again in the same hour.
--
-- ══ 5. WHAT MAY AND MAY NOT BE SAID FROM THIS RUN ══════════════════════════
--
-- **MAY:** *"On the twin depot under a return wave of 46 vehicles, CP-SAT submitted ~900 proposals
-- and enacted none; the deterministic path took 83% of the wave's 169 assignments. Seven of ten
-- CP-SAT rows declined on the grounds that no start was available within thirty minutes."* One run,
-- one seed, within-run split, no confound.
--
-- **MAY:** *"`0390`'s two mechanical predictions verified: first-refusal holds armed rose 63 → 81
-- and per-vehicle retries rose 10.89 → 14.97."*
--
-- **MAY NOT:** that `0390` moved, or failed to move, CP-SAT's enacted share. §2. The pair is
-- confounded and the honest word is *unmeasured*.
--
-- **MAY NOT:** that CP-SAT cannot help this depot. It was never given a churn-free instrument, a
-- precedence that yields to it, or a window longer than 30 minutes to plan against — and `0263` §1
-- means the shield it is measured beside cannot even judge a parking hold. **"Measured at 2.3%
-- under an instrument I have already found three defects in" is the whole claim.**
--
-- **MAY NOT:** that the absolute proposal counts compare. 973 against 610 is three configuration
-- changes as much as one code change; the abstention SHARE and per-vehicle ratio are the
-- comparable figures, and even they inherit §2's caveat.

-- ══ 6. THE FIVE KPIs FOR THE COMPLETED RUN, RECORDED BEFORE THEY ARE PURGED ══
--
-- Run `e8b8eb3e` completed at tick **1,189**, sim 09:47 CT, `failure_reason =
-- 'run_governor: reached the 540 sim-minute ceiling'` — the designed end, not a fault — and one
-- row in `ottoq_run_archives`. **`ottoq_kpi_five` reads `class='engine'` tables, so the next demo
-- run deletes every figure below.** The archive keys the run; it does not keep the KPIs. Recording
-- them here IS the "cite the run, not the table" discipline, applied to my own numbers.
--
--   run_key: pack robotaxi · scenario busy_day · seed 100020 · policy otto_q
--            config_hash 0053a045e66e029a238004b70746cc56
--            engine_hash 797d8dcef7db38efc22264308070737a
--
--                                        e8b8eb3e      c8f678fb (0288 §3)
--   1  asset_hours_available_per_day       **48.04**        57.89
--   2  service_point_turns_per_point_day    **3.40**         3.56
--   3  peak_site_kw                      **1,113.8**            —
--      peak_site_kw_demand               **1,105.3**            —
--   4  touch_events_per_turn               **0.140**        1.091  ← see below
--   5  p95_time_to_service_min              **58.1**         39.6
--      p50_time_to_service_min               **0.6**            —
--      returns_unserved                        **6**           11
--
--   `not_reproducible: []` — all eight published fields reproducible from this run id.
--
-- **KPI 4 IS `0391` WORKING, AND THE AUDIT BLOCK PROVES IT RATHER THAN ASSERTING IT.**
-- `touch_events 75`, `touch_events_operator 75`, `touch_events_override 0`, and
-- **`touch_events_override_flag_only 626`**. So the pre-`0391` headline would have been
-- (75 + 626) / 537 = **1.305**, and the published figure is **0.140** — a 9.3x correction on this
-- run, with the 626 excluded rows travelling beside it exactly as `0185`'s reversibility doctrine
-- requires. **The comparison against `c8f678fb`'s 1.091 is therefore across two definitions and
-- must not be read as an improvement in operations** — it is the same depot measured honestly.
--
-- **KPI 5 got WORSE and that is the expected direction.** p95 39.6 → 58.1 min on a run whose wave
-- presented 46 vehicles wanting service against 24 at the same point. `returns_unserved` fell 11 →
-- 6, so more vehicles were eventually served and the ones that waited waited longer — a queue
-- deepening, not a failure. Both belong to `0288` §3's capacity wall, now seen at higher load.
--
-- **AND ONE DIAGNOSTIC I CANNOT EXPLAIN, FLAGGED RATHER THAN QUIETLY PASSED OVER.** KPI 1's audit
-- block reads `hours_clipped_to_window = **-237.29**` with `dispatches_open_at_horizon = 1`.
-- `0185`'s own reversibility note says *"KPI 1 asset_hours + audit.hours_clipped_to_window is the
-- pre-0182 number"*, which here gives **-189.25 asset-hours** — a negative quantity of
-- availability, which is not a quantity. A single dispatch open at the horizon cannot account for
-- 237 hours (about ten days) on a nine-hour run in either direction, so **either the clip is
-- measuring something other than what its name says, or KPI 1's numerator and this diagnostic
-- disagree about their window.** `horizon_source` correctly reads `run_horizon`, so the bound is
-- not `now()` and the headline is reproducible; it is the diagnostic that does not add up.
-- **NOT INVESTIGATED HERE** — it is KPI 1's own machinery (`0182`), it does not affect the
-- published figure or any claim in this file, and chasing it now would mean starting a fourth
-- thread on a night that has already produced three self-retractions. Recorded so it cannot be
-- lost, and it is the next thing to measure.

SELECT jsonb_pretty(public.ottoq_kpi_five('e8b8eb3e-da9d-41ff-ab67-84b6998ba441')) AS kpis;
