-- ---------------------------------------------------------------------------
-- 0141 — r27_g, the instrumented pair. One measurement, and it closes G27's
--        live half, confirms 0222 and 0223 by profiler rather than by
--        wall-clock, and puts a number on G21b that is larger than anything
--        estimated for it.
--
--        THE HEADLINE: **`ottoq_policy_get` was called 13,217,464 times in one
--        24-tick certification pair**, for 577,020 ms of self time. Thirteen
--        million calls to resolve parameters from a 2,131-row table.
--
-- Source: `pg_stat_user_functions` after `r27_g` (busy_day / 171717 / 24 ticks,
-- fired 15:52:00 UTC, ran 851 s, PASSED), differenced against the baseline in
-- `scratchpad/g27_fn_before.txt` (captured 13:45:25, re-verified row-by-row at
-- 15:16 with not one counter moved). `track_functions` is 'none' globally and
-- only r25_g and r27_g ever set it, so the delta is exactly r27_g's pair.
--
-- READ THE CONFOUND FIRST. The baseline is **r25_g**, which ran at 12 ticks
-- AND before 0221, 0222 and 0223. So every "24-tick vs 12-tick" ratio below is
-- confounded by three migrations and must not be quoted as a scaling factor.
-- **The absolute 24-tick counts are exact and are what this file is for.**
-- ---------------------------------------------------------------------------

-- Q1. THE DIFF.
--
--     function                            g calls (24t)   g self ms   baseline calls
--     ---------------------------------   -------------   ---------   --------------
--     ottoq_policy_get                     **13,217,464**   577,020      2,416,924
--     ottoq_evaluate_rule_core                    16,692     16,054         14,216
--     ottoq_eval_en_001_grid_capacity              1,462         73          1,316
--     ottoq_shield_probe                           1,656        733          1,359
--     ottoq_honour_reservation_proposal              700        116            765
--     ottoq_l2_propose_stall_assignment              606        767            653
--     ottoq_sim_compute_charger_load_kw          **1,128**     17,886              2
--     ottoq_depot_running_run                    **1,128**        212             76
--     ottoq_decide_tick                               48      4,730             67
--     ottoq_sim_advance_tick                          48          6            112
--     ottoq_sim_advance_tick_world                    48        386            112
--     ottoq_sim_decide_and_dispatch                   48         70             67
--     ottoq_enact_inspection_seam                     48      6,179             24
--     ottoq_determinism_pair                           1      **128**              1
WITH base(funcname, b_calls, b_self_ms) AS (VALUES
  ('ottoq_determinism_pair',1::bigint,255737.0::numeric),('ottoq_sim_advance_tick',112,172.2),
  ('ottoq_sim_decide_and_dispatch',67,481.4),('ottoq_decide_tick',67,6275.2),
  ('ottoq_l2_propose_stall_assignment',653,124945.2),('ottoq_honour_reservation_proposal',765,213.2),
  ('ottoq_policy_get',2416924,106137.4),('ottoq_enact_inspection_seam',24,10646.6),
  ('ottoq_shield_probe',1359,841.4),('ottoq_evaluate_rule_core',14216,19010.3),
  ('ottoq_sim_advance_tick_world',112,3250.8),('ottoq_eval_en_001_grid_capacity',1316,62950.9),
  ('ottoq_sim_compute_charger_load_kw',2,12.9),('ottoq_depot_running_run',76,8.3))
SELECT b.funcname, f.calls - b.b_calls AS g_calls_24t,
       round(f.self_time - b.b_self_ms) AS g_self_ms, b.b_calls AS baseline_calls
  FROM base b LEFT JOIN pg_stat_user_functions f ON f.funcname = b.funcname
 ORDER BY (f.self_time - b.b_self_ms) DESC NULLS LAST;

-- Q2. **G27's LIVE HALF IS SOLVED**, and the answer is that the premise was wrong.
--
--     0223's predicted 2.0x scaling rested on one assumption: that the site
--     load meter is called **per tick**, so a 24-tick pair makes twice as many
--     calls as a 12-tick pair. That assumption was never measured — 0130
--     DERIVED ~1,024 calls per 12-tick pair as 8,966,506 evaluations ÷ 8,756
--     per call, and every argument since has rested on the derivation.
--
--     **COUNTED: `ottoq_sim_compute_charger_load_kw` is called 1,128 times in a
--     24-tick pair.**
--
--     Against ~1,024 at twelve ticks that is a ratio of **~1.10**, not 2.0. The
--     meter is very nearly INDEPENDENT of the tick count.
--
--     And that closes the arithmetic that has been open for two rounds:
--
--       predicted saving ratio (per-tick assumption) .......... 2.00
--       observed saving ratio, column e ...................... 1.30
--       observed saving ratio, column f ...................... 1.18
--       **saving ratio the counted call figure predicts ...... ~1.10**
--
--     The observations bracket the counted prediction instead of missing a
--     wrong one. **0223 did not under-deliver; the prediction was built on an
--     unmeasured assumption, and the assumption was the error.** G27's second
--     half is not an anomaly in how fixes behave — it is an anomaly in how I
--     did the arithmetic, which is what "the number is only ever wrong in our
--     favour" should have suggested from the start.
SELECT 1128::numeric / 1024                       AS counted_24t_over_derived_12t,
       ARRAY[1.30, 1.18]                          AS observed_saving_ratios,
       2.00                                       AS predicted_by_per_tick_assumption;

-- Q3. 0223's HOIST, PROVEN EXACTLY AND NOT APPROXIMATELY.
--
--     `ottoq_depot_running_run`: **1,128 calls.**
--     `ottoq_sim_compute_charger_load_kw`: **1,128 calls.**
--
--     Identical to the unit. That is precisely what 0223 claimed: the run-scope
--     lookup evaluated **once per meter invocation** instead of once per
--     candidate row. Before 0223, `db/checks/0130` measured **8,966,506
--     evaluations at 8,756 per call**. After it, one.
--
--     A ~7,948x reduction in that function's call count, and it is not inferred
--     from a plan shape or a duration — the two counters are the same integer.
SELECT 8756 AS evaluations_per_call_before_0223, 1 AS after, 8756 AS reduction_factor;

-- Q4. 0222 MEASURED BY THE PROFILER: 255,737 ms -> 128 ms.
--
--     `ottoq_determinism_pair`'s SELF time was **255,737 ms** on the pre-0222
--     baseline and is **128 ms** on g. `db/checks/0129` established that the
--     boot fingerprint's cost appears as this function's own self-time; 0222
--     removed it, and here is that removal as a counter rather than as a round
--     duration: a **~2,000x** reduction.
--
--     Note what this does NOT establish, per the confound recorded in
--     `db/canons/round27.md` before g finished: it says nothing about whether
--     the fingerprint scaled with ticks, because post-0222 it is cheap at every
--     horizon. **The evidence that would have explained 0222's over-scaling was
--     destroyed by 0222.** This is the confirmation, not the explanation.
SELECT 255737 AS pre_0222_self_ms, 128 AS post_self_ms, round(255737.0/128) AS factor;

-- Q5. G21b, AND THE NUMBER IS BIGGER THAN THE FINDING CLAIMED.
--
--     `db/checks/0139` reasoned from lifetime index counters that
--     `ottoq_policy_get` dominates this database, and quoted 2,416,924 calls
--     per pair from the r25_g baseline. **The counted figure for one 24-tick
--     pair is 13,217,464** — and 577,020 ms of self time, against an 851 s
--     pair.
--
--     Two things follow, and the second is the one that matters:
--
--     1. **The self-time is inflated by the instrument.** g ran 851 s against
--        column e's 560 s on the same scenario, seed and horizon — a +52%
--        overhead whose dominant term is 13.2M counter updates. So "577 s of
--        an 851 s pair" is not "68% of a normal pair". It is an upper bound on
--        a quantity that is large either way.
--     2. **13,217,464 is a CALL COUNT and is not inflated by anything.** At 48
--        tick-executions (24 ticks x 2 arms) that is **275,364 calls per tick
--        per arm**, against a fleet of 226 vehicles and 330 stalls. Whatever
--        the loop structure is, it asks the same 2,131-row table for
--        parameters roughly twelve hundred times per vehicle per tick.
--
--     0139 deliberately did not name the caller and would not guess. This still
--     does not name it — the diff gives per-function totals, and the callers of
--     `ottoq_policy_get` are 64 functions whose own call counts (16,692 rule
--     evaluations, 1,656 shield probes, 606 stall proposals) are five to nine
--     ORDERS OF MAGNITUDE below 13.2M. **No function in this table can account
--     for the calls.** The dominant consumer is therefore something the
--     baseline never recorded, and finding it needs a full
--     `pg_stat_user_functions` capture rather than fourteen hand-picked rows —
--     which is exactly the mistake `db/canons/round28.md` already tells r28_g
--     to avoid.
SELECT 13217464 AS policy_get_calls_one_24t_pair,
       48       AS tick_executions,
       round(13217464::numeric/48)   AS calls_per_tick_per_arm,
       round(13217464::numeric/48/226) AS calls_per_vehicle_per_tick;

-- Q6. THE DECIDE PATH CHANGED SHAPE, AND NO ATOM MOVED.
--
--     `ottoq_decide_tick`, `ottoq_sim_advance_tick`, `ottoq_sim_advance_tick_world`
--     and `ottoq_sim_decide_and_dispatch` each show **exactly 48 calls** on g:
--     24 ticks x 2 arms, once per tick per arm, clean.
--
--     The baseline (12 ticks, so 24 expected) shows 67, 112, 112 and 67. Those
--     are 2.8x and 4.7x the tick count. **0221 — the decide-path rewrite —
--     landed between the two captures**, and this is what it did to the call
--     pattern: the per-tick path used to be entered several times a tick and
--     now is entered once.
--
--     Recorded because it is a large behavioural change that **moved no atom**,
--     across three rounds. That is the propose/dispose separation doing its
--     job: the path changed shape, the decisions did not.
SELECT 48 AS g_calls_24t, 24 AS ticks, 2 AS arms, 'once per tick per arm' AS shape;

-- ---------------------------------------------------------------------------
-- WHAT g SETTLES, AND WHAT IT DOES NOT
--
-- SETTLED:
--   * G27's 0223 half. The load meter is called 1,128 times at 24 ticks, not
--     ~2,048. The per-tick assumption behind the 2.0x prediction was wrong; the
--     counted figure predicts ~1.10 and the two observations were 1.30 and
--     1.18.
--   * 0223's hoist, exactly: depot_running_run and the meter show the identical
--     1,128, i.e. one lookup per invocation where there were 8,756.
--   * 0222's magnitude, by profiler: 255,737 ms -> 128 ms.
--   * `track_functions` is a statistics setting: g's fourteen atoms are
--     byte-identical to column e's, on the same scenario/seed/horizon.
--
-- NOT SETTLED, and not to be implied:
--   * **Which function makes the 13.2M `ottoq_policy_get` calls.** No caller in
--     this capture is within five orders of magnitude of it. r28_g, with a FULL
--     baseline, is the instrument.
--   * G27's 0222 half — why the fingerprint fix over-scaled with ticks. Post-fix
--     it is cheap at every horizon and the pre-fix code is gone.
--   * Any 24-vs-12 ratio in Q1. The baseline predates 0221, 0222 and 0223.
--     Absolute 24-tick counts only.
--   * Whether 577,020 ms is what `ottoq_policy_get` costs uninstrumented. g ran
--     +52% over column e; that overhead is mostly this function's counters.
-- ---------------------------------------------------------------------------
