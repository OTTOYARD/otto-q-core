-- 0416  **The rolled-forward check (0620) measured in the twin against a fresh kernel arm on the same seed and world
--        day: it refused 107 of the agent's 109 orders, so the two arms ran nearly the same seats, and they still
--        differ by 1.4 points of uptime and 11 minutes of median turnaround. That is the floor a single paired run
--        cannot see under; the agent's order neither helped nor hurt measurably here.** Then what the new instruments
--        (0621's grader, 0622's clock, calibration and audit) say the check gets wrong. One paired run: single
--        readings, not ranges. (G318 updated; G351 partly closed; G353, G354, G355 new)
--
--       Written 2026-10-08, 11:50 AM CT. Read-only. Twin depot 11111111-…, scenario busy_day, seed 8950314943655796957,
--       sim 13:00 to 15:11:06.568569 UTC (8:00 to 10:11 AM CT sim time; 2.19 sim-hours, 116 cars), live playback x3.
--
--         baf29c05-4369-4891-bb0d-3fe8e92b1dd1  kernel order (agent_charge_order 0). Started 15:00:14 UTC (10:00 AM
--                                               CT); passed the cut about 15:44 UTC.
--         d9d49732-cf28-42c3-aac9-9c3f606a2c92  agent order through 0620's check (agent v25; v26 from 14:56 UTC, four
--                                               minutes before the run was superseded). 13:53 to 15:00 UTC.
--
--       **Why not the 2026-10-07 arms.** The boot draw keys the world day on the sim date: 81787ef9 and 089f46bd ran
--       on 2026-10-07 (arrival scalar 2.50, queue patience 12.6, LMP $47/MWh), d9d49732 and baf29c05 on 2026-10-08
--       (arrival 1.41, patience 5.9, LMP -$19.8/MWh), same seed. A kernel arm on 10-07 is not a control for an agent
--       arm on 10-08, which is why baf29c05 was started. Every agent dial but agent_charge_order is the same in both
--       (review, asset depth, solver chain, board grounding all 1).
--
-- ══ §1 THE KPI BOARD, CUT AT 15:11:06 ═══════════════════════════════════════════════════════════════════════════════
--
--   The windowed pg_temp copies of 0415 §6 (every input bounded by the horizon), run on the two arms:
--
--                                               baf29c05 kernel    d9d49732 agent, checked (0620)
--   uptime, % of fleet time                         41.2               39.8
--   on the road, %                                  37.0               35.7
--   revenue hours                                   93.7               90.5
--   departures (per hour)                           67 (30.7)          65 (29.7)
--   arrivals                                        80                 75
--   ready by the due time                           12 of 32 (37.5%)   12 of 30 (40.0%)
--   late / not ready at the cut                     9 / 11             8 / 10
--   p50 lateness of a late car, min                 39.5               23.2
--   charge wait, cars plugged: p50 / p95 min        15.2 / 93.0        17.6 / 100.8
--   still waiting for a charger at the cut          42 of 99           36 of 93
--   first service after arrival, p50 / p90 min      4.2 / 48.8         7.6 / 61.2
--   turnaround p50 / p90 min                        74.5 / 93.7        63.2 / 88.7
--   sessions started / completed / faulted          115 / 70 / 7       112 / 68 / 5
--   L2 / DCFC busy, %                               92.0 / 81.7        92.1 / 86.8
--   energy to cars, kWh                             1,618              1,676
--   grid import kWh / cost / 30-min peak kW         1,285 / $92.40 / 643   1,275 / $91.71 / 646
--   DCFC sessions from below 50%                    13                 16
--   DCFC hours from cars at 80%+ (G315)             25.8%              19.0%
--   battery at dispatch                             avg 100, min 99    avg 100, min 99
--
--   Rule 9 held in both: every car left at 99-100%.
--
-- ══ §2 WHY THE TWO ARMS ARE NEARLY ONE POLICY ═══════════════════════════════════════════════════════════════════════
--
--   (a) **The check took 2 of 109 orders.** 86 were `same_as_kernel` (the agent's ranking made the kernel's seats in
--       its window), 12 `worse_in_expected_future`, 9 `not_enough_futures_won` (mean 1.46 of 12 futures won), 2
--       `wins_most_futures`: #382 partial (10 of 12) at sim 13:45:40 and #385 accepted (11 of 12) at 13:50:48, each
--       for its ttl. 73 of the 109 fell inside the window. The agent answered on Nemotron Ultra (71) and Super (38).
--   (b) **So §1 is close to two runs of the kernel's order, and they still differ.** The tick grids differ: in the
--       window baf29c05 decided at 412 sim instants and d9d49732 at 385 (a mean tick of 0.32 against 0.34 sim
--       minutes), and d9d49732's first decision came at 13:02:12 against 13:00:34. Live playback ties sim time to
--       real time, so a tick's sim length follows the database's load; the twin's draws are keyed on (seed, entity,
--       sim seconds), so a different grid draws a different world after the first tick. The other agent paths (review,
--       solver chain) are model-driven and not seeded either: 469 model calls in baf29c05, 227 in d9d49732.
--   (c) **What that means for every paired number on this page and in 0415.** A single paired live run on one seed
--       does not resolve a difference of about 1.4 points of uptime, 2 departures, 2.5 points of on-time readiness or
--       11 minutes of median turnaround: two near-identical policies differed by that much here. 0415's 4.7-point
--       uptime gap (0618's checked order against the kernel's, 35.9 against 40.6) is three times this floor and stands
--       as a finding; its smaller figures do not. (G353)
--
-- ══ §3 WHAT THE GRADER SAYS ABOUT THE CHECK (0621) ══════════════════════════════════════════════════════════════════
--
--   61 of d9d49732's orders graded in hindsight: 29 no_decision, 14 no_decision_mattered (the agent's ranking was the
--   kernel's, and the line it would have changed mattered), 10 right_refusal, 6 missed_win (refused, and in what
--   actually happened the agent's order would have won), 1 right_take, 1 wrong_take. The check's win probability
--   (futures won over futures) predicts hindsight no better than the base rate: Brier 0.2581 against 0.2377
--   (`futures_uninformative`). Six missed wins against ten right refusals says the bar refuses some good orders; the
--   self-assessment ranks the reasons (§5), and the bar itself stays a person's dial (rule 10).
--
-- ══ §4 THE CHARGE CLOCK (0622) ══════════════════════════════════════════════════════════════════════════════════════
--
--   (a) **The gate, on d9d49732's own fast charges, out of sample** (the clock fitted through the run's start):
--       0619's clock had a bias of -0.476 (charges 38% shorter than it said), a mean absolute log error of 0.605 and
--       61% inside its 80% band; 0622's had -0.030, 0.131 and 74%. L2: 0.094 and 86% against 0.078 and 94%.
--   (b) **The first fit** (#1, 16:24:12 UTC): 3,274 fine-tick charges over 38 runs; 30 class cells, 14 make-and-model
--       cells, 232 car cells. Against the typical fast charge: Zoox x0.31, Waymo x1.02, Tesla x1.43; on L2 every class
--       within 1%. The spread it leaves on fast charges falls from 0.671 to 0.254 through its levels; a car's
--       consecutive fast charges in a run correlate at 0.91 after its class, model and cross-run offset are out.
--   (c) **0621's headline was mostly the window's survivorship.** 0621 reported fast charges running 34% short of the
--       check's clock by summing every completed charge in each order's window. 0622's calibration counts each charge
--       once (the check's last forecast before it began) and only when it could have finished inside the window at the
--       forecast's 90th percentile: on the same orders, 169 fast charges, the check's forecasts ran 9% LONG (z mean
--       0.23, 100% inside the band), and 115 L2 charges 6% short. The two figures are different populations: the
--       eligible set is mostly Teslas (164 of 169), because a Zoox's 133 kWh forecast on 0619's clock was too long to
--       finish inside 90 minutes; the cars whose forecasts were most wrong are the ones a window cannot grade, and the
--       ledger audit (d) grades them instead. (G354)
--   (d) **The audit, on the last day's 211 fine-tick fast charges (in sample):** 0619's clock -0.518 bias and 0.622
--       mean absolute log error, 0622's -0.040 and 0.086; inside the band 63% against 80%. It still flags its own
--       class and model levels as stale, and they are, by a little: right after the fit, Zoox fast charges ran 11%
--       shorter than the clock (median -0.096, 72 charges), Zoox VH6 18%, Tesla Cybercab 13% longer. The last day is
--       dominated by today's runs, which share one seed and so one draw of each car's condition; the run level absorbs
--       part of it inside a run, and the nightly refit the rest if it persists. The audit names two variables the
--       clock does not model on fast chargers: ambient temperature (8% of what it leaves) and sim hour (5%).
--
-- ══ §5 THE SELF-ASSESSMENT'S RANKED AREAS (0622, since 2026-10-07 16:30 UTC; findings for a person, rule 10) ═══════
--
--   arrival_spread        2510  the futures sample arrivals too narrowly: z sd 3.05 for the cars it saw coming
--   simulator_structure   1939  given what really happened, the simulator still places a plug-in 10.7 minutes off
--                               (no bays, holds, stall pick beyond the kind, or the next order taking over)
--   outflow_return_cycle   532  8.72 cars per order came home inside the window that the check never saw coming;
--                               all 532 had left after the order (467 at the battery reserve, 55 comms_stale, 10 rider
--                               flags), a mean of 78.6 minutes later. The simulator has no departures. (G355)
--   charge_clock_stale_*   26-90  §4(d)
--   chargers_left_out       61  chargers held, booked or faulted at the order served 3.13 charges per window
--   bar_stricter, futures_uninformative   18 each  §3
--   charge_clock_misses_ambient_c_dcfc 17, _sim_hour_dcfc 11  §4(d)
--
-- ══ §6 WHAT FOLLOWS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   1. The check's biggest blind spot is now the depot's own outflow: cars it seats leave, work down to the reserve and
--      come back inside the same window. A check that cannot see them prices an order by a line that is not the one
--      that comes. Next migration: the simulator's departures and returns at the learned reserve (0619 return_v1), and
--      an objective that counts a faster turnaround as uptime gained, not as more cars in the line.
--   2. A paired measurement needs either a deterministic replay of the twin (a fixed sim tick, not live playback) or
--      several replicates per arm. Until then a single pair resolves only differences well above §2(c)'s floor.
--   3. The bar (agent_charge_order_win_frac 0.8) is a person's dial; 6 missed wins against 10 right refusals is a
--      reason to look at it after the outflow is modelled, not before.
--
-- ══ §7 REPRODUCE ════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) The board: create 0415 §6's pg_temp functions, then:
--
-- SELECT x.arm, pg_temp.kw_board(x.run::uuid, x.h::timestamptz) AS board
--   FROM (VALUES ('kernel order',                       'baf29c05-4369-4891-bb0d-3fe8e92b1dd1', '2026-10-08 15:11:06.568569+00'),
--                ('agent order, rolled forward (0620)', 'd9d49732-cf28-42c3-aac9-9c3f606a2c92', '2026-10-08 15:11:06.568569+00')) x(arm, run, h);

-- (2) the orders and how the check answered them
SELECT COALESCE(o.projection ->> 'reason', o.status) AS reason, o.status, count(*) AS orders,
       count(*) FILTER (WHERE o.sim_clock <= '2026-10-08 15:11:06.568569+00') AS in_window,
       round(avg((o.projection ->> 'wins')::numeric), 2) AS mean_futures_won
  FROM public.ottoq_agent_charge_orders o
 WHERE o.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'
 GROUP BY 1, 2 ORDER BY 3 DESC;

-- (3) the tick grids
SELECT d.sim_run_id, count(DISTINCT d.sim_clock) AS decision_instants, min(d.sim_clock) AS first_decision
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id IN ('d9d49732-cf28-42c3-aac9-9c3f606a2c92', 'baf29c05-4369-4891-bb0d-3fe8e92b1dd1')
   AND d.sim_clock <= '2026-10-08 15:11:06.568569+00'
 GROUP BY 1;

-- (4) the grades
SELECT h.outcome, count(*) FROM public.ottoq_charge_order_hindsight h
 WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' GROUP BY 1 ORDER BY 2 DESC;

-- (5) the self-assessment (calibration, audit, outflow and the ranked areas); the figures above read it at
--     2026-10-08 16:30 UTC with p_since = now() - interval '1 day'
SELECT public.ottoq_arbiter_self_assessment_v2('11111111-1111-1111-1111-111111111111'::uuid, now() - interval '1 day');

-- (6) the clock's residual by class and model on the last day's fast charges, against the depot's clock
WITH m AS (SELECT public.ottoq_charge_clock_model('11111111-1111-1111-1111-111111111111'::uuid) AS j),
e AS (
  SELECT w.j ->> 'cls' AS cls, w.j ->> 'mdl' AS mdl,
         ln((l.duration_min / est.m)::numeric)
           - (public.ottoq_charge_clock(m.j, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                        l.vehicle_kw, NULL) ->> 'f')::numeric AS res
    FROM m, public.ottoq_charge_duration_ledger l
    JOIN public.vehicles v ON v.id = l.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                    l.vehicle_kw) AS m) est
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.recorded_at >= now() - interval '1 day'
     AND l.stopped_reason = 'completed' AND l.charger_type = 'dcfc' AND l.duration_min > 0 AND l.soc_end > l.soc_start
     AND est.m > 0 AND l.tick_minutes <= 1)
SELECT e.cls, e.mdl, count(*) AS n, round(avg(e.res), 3) AS mean_res,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY e.res)::numeric, 3) AS median_res
  FROM e GROUP BY ROLLUP (e.cls, e.mdl) ORDER BY 1 NULLS LAST, 2 NULLS FIRST;
