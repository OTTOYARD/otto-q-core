-- 0428  **0642 validated in the twin: one deterministic pair per key, run by hand because the window was closed.**
--        0642 put two keys into OTTO-Q's own charge line: a car that has waited 90 minutes goes first
--        (charge_wait_floor_min), and the rest are ordered by minutes of charge (charge_order_minutes). 0643 registered one
--        paired experiment per key. This runs each experiment's first pair now, reads them, and corrects 0643 on when its
--        pairs would have run.
--
--        Written 2026-10-09, 9:20 AM CT onward. Twin depot 11111111-…. One pair per key: a deterministic reading on one
--        seed each, not a range.
--
-- ══ §1 HOW THE PAIRS RAN, AND A CORRECTION TO 0643 (reproduce: (1)) ══
--
--   0643 §2 says the dial runner pairs its experiments "only in its nightly window". The window does not open: 0485
--   (2026-09-26, Chase: hold off on major testing while the build is still moving) deactivated its opener, cron 761,
--   and nothing has reactivated it. The last dial pair before today ran on 2026-09-28, in a one-time window (cron 763).
--   So the two experiments would have sat unpaired tonight, and the runner, opened, would first have taken an older
--   experiment (82c5568b, 0480's replication), not these two.
--
--   So the pairs were run directly, with each experiment's own first seed (ottoq_dial_experiment_seed(id, 1)), which is
--   the seed the runner would have used, so both count toward the experiments' looks: a one-shot pg_cron job (791, as
--   0399's cron 766) ran ottoq_dial_pair for the floor experiment at 14:22 UTC (9:22 AM CT) and, in the same command,
--   scheduled the minutes experiment's pair two minutes after the first ended. The window stays closed, by design.
--
--     experiment                                key                     control   treatment   seed
--     f2120031-04a2-4b14-adb9-4aaa61767dd8      charge_wait_floor_min       0          90       707482797723052107
--     04e101de-0e5e-4150-927c-8e5b5e912b4e      charge_order_minutes        0           1       236177543270465804
--
--   Each arm quiesces the agent, so the pairs measure the kernel's own order. busy_day at the twin depot, 90 ticks of
--   6 sim-minutes from 8:00 AM CT (to 5:00 PM), the world identical in both arms but for the one dial.
--
-- ══ §2 THE FLOOR: 0 AGAINST 90 (pair 119; reproduce: (2), (3)) ══
--
--   14:22:00-15:01:06 UTC (9:22-10:01 AM CT), 2,346 s: control 652 s, treatment 1,695 s. Valid on every test the
--   harness makes: complete, the world identical, both arms paid the shield, each arm read its own value of the dial,
--   and the arms differ (11 atoms moved). charge_order_minutes is 1 in both.
--
--     key                                          off (0)   on (90)    delta
--     charge_wait_p95_floor_min (primary, lower)    284.4     303.6    +19.2   worse
--     charge_wait_p95_min                           282.0     307.2    +25.2
--     charge_wait_p50_min                            42        42        0
--     charges_waiting_at_horizon                     48        52       +4
--     charge_sessions                               226       217       -9
--     trips_completed                               211       203       -8
--     deployed_car_hours                            101.5     100.8     -0.7
--     unmet_demand_car_hours                        338.5     339.2     +0.7
--     returns_unserved (safety floor: no more)       24        27       +3    fails
--     vehicles_turned_around                         70        75       +5
--     median_turnaround_min                         210       204       -6
--     KPI 1 asset_hours_available_per_day           137.20    135.11    -1.5%
--     KPI 2 service_point_turns_per_point_per_day     5.11      4.92    -3.7%  beyond the 2% guardrail
--     KPI 3 peak_site_kw                            937.7     937.7      0
--     KPI 4 touch_events_per_turn                     0.536     0.537   +0.2%
--     KPI 5 p95_time_to_service_min                 270       294      +8.9%  beyond the 2% guardrail
--     safety_critical_refused / _unprevented        5 / 0     5 / 0      0
--
--   By the wait each car had for its first charger, in the band its battery arrived in (a car never seated counted at
--   its wait at the day's end):
--
--     battery on arrival    arrivals      never seated     mean wait       95th pct        longest
--                           off   on      off   on         off    on       off    on       off    on
--     under 45%              20   20        0    0         13.5   13.5     24.3   24.3      30     30
--     45-80%                 92   91       22   16        132.7  127.1    336.0  300.0     474    336
--     80% and up            101   98       26   36        100.9  112.4    276.0  306.9     384    348
--
--   **The floor does what it was built to do at the extreme, and it costs throughput.** It cut the longest wait in the
--   depot from 474 minutes to 348 (mid batteries) and from 384 to 348 (top-offs), and seated 6 more mid-battery cars.
--   But busy_day at this demand is far over the depot's capacity in both arms (a mean wait near two hours for every
--   car above 45%, against a 30-minute contract wait), and seating the longest waiters first cost 9 charges, 8 trips,
--   10 more top-offs never seated and 360 more minutes past the contract wait in all (17,322 -> 17,682, +2.1%, (3)).
--   The returns count the experiment judges safety on rose by 3, which §4 shows is 1 car counted plainly. On the
--   experiment's own rules (0643 §1: the primary better, every guardrail within 2%, no more returns unserved) this
--   pair counts against the floor on all three. Low batteries are untouched by it: they wait the same 13.5 minutes in
--   both arms, so whatever answers G384's low-battery wait here is not the floor (§3 reads the minutes order).
--
-- ══ §3 THE MINUTES ORDER: 0 AGAINST 1 (pair 120; reproduce: (2), (3), (5)) ══
--
--   15:03:00-15:45:47 UTC (10:03-10:45 AM CT), 2,567 s: control 678 s, treatment 1,890 s. Valid on every test the
--   harness makes, as pair 119 was, 11 atoms moved. charge_wait_floor_min is 90 in both.
--
--     key                                          off (0)   on (1)     delta
--     deployed_car_hours (primary, higher)          104.7     105.3     +0.6    +0.6%, one seed
--     charge_wait_p95_floor_min                     286.2     324.0    +37.8
--     charge_wait_p50_min                            36        36        0
--     charges_waiting_at_horizon                     57        57        0
--     charge_sessions                               240       237       -3
--     trips_completed                               222       217       -5
--     unmet_demand_car_hours                        335.3     334.7     -0.6
--     returns_unserved (safety floor: no more)       29        42      +13    fails (§4: +3 counted plainly)
--     vehicles_turned_around                         84        78       -6
--     median_turnaround_min                         216       186      -30
--     energy_cost_usd                               385.48    373.78   -3.0%
--     KPI 1 asset_hours_available_per_day           150.4     148.0     -1.6%
--     KPI 2 service_point_turns_per_point_per_day     5.85      5.63    -3.8%  beyond the 2% guardrail
--     KPI 3 peak_site_kw                           1330.3    1283.9     -3.5%  better
--     KPI 4 touch_events_per_turn                     0.536     0.479  -10.6%  better
--     KPI 5 p95_time_to_service_min                 270       318      +17.8%  beyond the 2% guardrail
--     safety_critical_refused / _unprevented       12 / 0    15 / 0
--
--     battery on arrival    arrivals      never seated     mean wait       95th pct        longest    minutes past 30
--                           off   on      off   on         off    on       off    on       off    on      off     on
--     under 45%              17   16        0    0         30.7   16.9     86.4   36.0     288     36      264     12
--     45-80%                 89   92       16   14        121.1  129.7    276.0  324.0     300    372    8,514  9,612
--     80% and up            121  113       41   43         99.3  107.9    306.0  320.4     372    414    8,904  9,198
--
--   **The minutes order does what 0642 built it for, and the rest of the line pays for it.** No car under 45% waits
--   more than 36 minutes for its first charger, against 288 under the order in battery points (a nearly empty car
--   waiting nearly five hours), and the median turnaround falls 30 minutes with less peak power, energy cost and
--   touches. 0642's reason holds on the kernel's own model ((5)): on a 150 kW charger a point of top-off costs 1.00
--   minute against 0.50 for a point between 30% and 80%, so the order in points took a top-off for a short job; on an
--   L2 a point costs 4.1 minutes at any charge, so the change acts through the fast chargers. The rest pay: cars above
--   45% wait longer at the tail (95th percentile 276 -> 324 and 306 -> 320), the minutes past the 30-minute contract
--   wait rise 6.4% in all (17,682 -> 18,822; 131 -> 139 cars past it), and the depot turns its points 3.8% less. The
--   equal totals of pair 119's treatment and this control (17,682 each) are a coincidence: different seeds, arrivals
--   and battery splits.
--
-- ══ §4 THE VEHICLE-FIRST GATE: WHAT IT COUNTS AND HOW IT DECIDES (reproduce: (4), (6), (7), (8)) ══
--
--   Both experiments' verdicts already read terminal: "1 counted pair(s) leave more returns unserved under the
--   treatment; vehicle-first is inviolable" (outcome safety_regression). Two facts about that gate decide how to
--   read it.
--
--   (a) What it counts. returns_unserved (ottoq_kpi_p95_time_to_service) is a returned car whose first planned
--   operation was due before the day's end and never started. A returned car whose first operation was planned at or
--   after the end is counted apart, as deferred. So an order that plans a car's next operation sooner moves it from
--   deferred to unserved without serving one car fewer. Every admitted return in these four arms had work planned,
--   so unserved plus deferred is the plain count, returned cars with no operation started by the day's end:
--
--     pair  arm   admitted  served  unserved  deferred  not served
--     119   off      195     156       24        15        39   20.0%
--     119   on       187     147       27        13        40   21.4%
--     120   off      209     161       29        19        48   23.0%
--     120   on       204     153       42         9        51   25.0%
--
--   Pair 120's +13 is 3 more cars not served and 10 moved from deferred; pair 119's +3 is 1 more. The first
--   operation an unserved car waits on is mostly an inspection (12-24 an arm), then an L2 charge (5-11); in pair 120
--   the charge-owing cars still waiting at the end are 57 in both arms, and its extra unserved cars wait on
--   inspections (18 -> 24) and washes (1 -> 7).
--
--   (b) How it decides. The verdict is terminal the first time any one counted pair shows the treatment with more
--   (ottoq_dial_experiment_verdict: IF v_unserved_worse > 0). On a change to the charge order that count swings by
--   more than a dozen cars from seed to seed (7): the charge-kind experiment a4c7b7d0 read -5, -17, +3, nineteen
--   fewer returns unserved over its three pairs, and was concluded a safety regression on the third; the window
--   calibration 143a11c7 was concluded on its first counted pair, +18. A gate that ends an experiment on one pair
--   cannot tell a change that leaves cars unserved from a seed whose trajectories happened to part that way: if the
--   difference were symmetric noise with no ties, a change with no effect at all would come through the six pairs of
--   a first look about once in 64.
--
--   So the two verdicts are not yet evidence that either key leaves cars unserved: counted plainly the differences
--   are +1 and +3 on about 200 returns, inside the swing this count shows between seeds. A gate that can tell would
--   judge at the look over all counted pairs, on returned cars with no operation started by the end (unserved plus
--   deferred), with a one-sided paired test that the treatment is no worse, and stay terminal on any unprevented
--   safety-critical event in any one pair. That changes how the research wing enforces rule 9, so it is a decision for
--   a person, not this file (G392).
--
-- ══ §5 WHAT THIS DECIDES ══
--
--   - Neither key changes. 0642 shipped both on (floor 90, minutes 1). One pair each confirms the effect each was
--     built for, the minutes order ending the low-battery starvation G384 named (288 -> 36 minutes longest; 264 -> 12
--     minutes past the contract wait for cars under 45%) and the floor capping the longest single waits (474 -> 336
--     and 384 -> 348). What each cost the rest of the line on its seed (stall turns -3.7% and -3.8%, minutes past the
--     contract wait +2.1% and +6.4%, 1 and 3 more returns not served) is one seed each, against a count that swings by
--     a dozen cars between seeds.
--   - Whether the trade holds across seeds is the open question, and the experiments' first looks answer it: 5 more
--     pairs each, about 7 hours of twin time at 40 minutes a pair, every cron job blocked while a pair runs (G141).
--     The nights belong to the capacity sweep (cron 784 and 785, 11 PM-6 AM CT), and until the gate is fixed the
--     verdict function would end both experiments on these first pairs whatever the next ones read. So the pairs
--     follow the gate, in the next experiment round, which is Chase's standing rule for major testing (0485).
--   - If the window opens before the gate is fixed, the runner concludes both experiments on these pairs. Nothing in
--     production moves when it does: on any outcome but a treatment win, ottoq_promote_dial_experiment only concludes
--     the experiment and writes no dial (8).
--   - Wall time is not a cost of either key. The treatment is the second arm in the pair's one transaction and ran 2.6
--     and 2.8 times slower than the first in both pairs, with rule evaluations and decisions on a par between arms.

-- ══ queries ══

-- (1) The windows, and the two one-shot jobs (both unscheduled after their pair)
SELECT jobid, jobname, schedule, active FROM cron.job
 WHERE jobname IN ('ottoq_dial_window_open', 'ottoq_dial_window_close', 'ottoq_dial_window_open_once_20260928',
                   'ottoq_sweep_window_open', 'ottoq_sweep_window_close', 'ottoq-throughput-sweep-runner',
                   'ottoq_validate_0642_floor', 'ottoq_validate_0642_minutes')
 ORDER BY jobid;
SELECT max(ran_at) FILTER (WHERE ran_at < '2026-10-09') AS last_pair_before_today FROM public.ottoq_dial_pair_ledger;

-- (2) Each pair: validity, the scorecard arm against arm, and the verdicts
SELECT p.pair_id, left(p.experiment_id::text, 8) AS experiment, p.seed, p.ran_at, p.wall_s, p.complete, p.world_identical,
       p.both_paid_shield, p.dial_read_a, p.dial_read_b, p.differs, p.moved
  FROM public.ottoq_dial_pair_ledger p
 WHERE p.experiment_id IN ('f2120031-04a2-4b14-adb9-4aaa61767dd8', '04e101de-0e5e-4150-927c-8e5b5e912b4e') ORDER BY p.pair_id;
SELECT p.pair_id, k.key, p.metrics_a -> k.key AS control, p.metrics_b -> k.key AS treatment, p.delta -> k.key AS delta
  FROM public.ottoq_dial_pair_ledger p,
       unnest(ARRAY['charge_wait_p95_floor_min', 'charge_wait_p95_min', 'charge_wait_p50_min', 'charges_waiting_at_horizon',
                    'charge_sessions', 'trips_completed', 'deployed_car_hours', 'unmet_demand_car_hours', 'returns_unserved',
                    'vehicles_turned_around', 'median_turnaround_min', 'energy_cost_usd', 'asset_hours_available_per_day',
                    'service_point_turns_per_point_per_day', 'peak_site_kw', 'touch_events_per_turn', 'p95_time_to_service_min',
                    'safety_critical_refused', 'safety_critical_unprevented', 'wall_s']) AS k(key)
 WHERE p.experiment_id IN ('f2120031-04a2-4b14-adb9-4aaa61767dd8', '04e101de-0e5e-4150-927c-8e5b5e912b4e')
 ORDER BY p.pair_id, k.key;
SELECT x.experiment_id, public.ottoq_dial_experiment_verdict(x.experiment_id) - 'look_pairs' AS verdict
  FROM public.ottoq_dial_experiments x
 WHERE x.experiment_id IN ('f2120031-04a2-4b14-adb9-4aaa61767dd8', '04e101de-0e5e-4150-927c-8e5b5e912b4e');

-- (3) The wait for a first charger by the battery a car arrived with, in each arm of a pair (a car never seated counted at
--     its wait at the day's end), with the minutes past the 30-minute contract wait
WITH arms AS (
  SELECT p.pair_id, 'control' AS arm, p.run_a AS run FROM public.ottoq_dial_pair_ledger p
   WHERE p.experiment_id IN ('f2120031-04a2-4b14-adb9-4aaa61767dd8', '04e101de-0e5e-4150-927c-8e5b5e912b4e')
  UNION ALL
  SELECT p.pair_id, 'treatment', p.run_b FROM public.ottoq_dial_pair_ledger p
   WHERE p.experiment_id IN ('f2120031-04a2-4b14-adb9-4aaa61767dd8', '04e101de-0e5e-4150-927c-8e5b5e912b4e')
), v AS (
  SELECT a.pair_id, a.arm, a.run, r.sim_clock_current AS run_end, v.vehicle_id, v.arrived_at, (v.meta ->> 'soc_at_arrival')::numeric AS soc
    FROM arms a JOIN public.ottoq_sim_runs r ON r.sim_run_id = a.run
    JOIN public.ottoq_visit_needs v ON v.sim_run_id = a.run
   WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v.atoms) = 'array' THEN v.atoms ELSE '[]'::jsonb END) x
                  WHERE x ->> 'svc' = 'charge')
), w AS (
  SELECT DISTINCT ON (v.pair_id, v.arm, v.vehicle_id, v.arrived_at) v.*, c.started_at AS first_charge,
         extract(epoch FROM (COALESCE(c.started_at, v.run_end) - v.arrived_at)) / 60.0 AS wait_min
    FROM v LEFT JOIN LATERAL (
      SELECT l.started_at FROM public.ottoq_charge_duration_ledger l
       WHERE l.sim_run_id = v.run AND l.vehicle_id = v.vehicle_id AND l.started_at >= v.arrived_at
       ORDER BY l.started_at LIMIT 1) c ON true
   ORDER BY v.pair_id, v.arm, v.vehicle_id, v.arrived_at
)
SELECT pair_id, CASE WHEN soc < 45 THEN 'a under 45%' WHEN soc < 80 THEN 'b 45-80%' ELSE 'c 80%+' END AS battery, arm,
       count(*) AS arrivals, count(*) FILTER (WHERE first_charge IS NULL) AS never_seated,
       round(avg(wait_min)::numeric, 1) AS mean_wait_min,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY wait_min)::numeric, 1) AS p95_wait_min,
       round(max(wait_min)::numeric, 1) AS longest_min,
       count(*) FILTER (WHERE wait_min > 30) AS past_30,
       round(sum(GREATEST(0, wait_min - 30))::numeric) AS minutes_past_30
  FROM w GROUP BY GROUPING SETS ((1, 2, 3), (1, 3)) ORDER BY 1, 2 NULLS LAST, 3;

-- (4) Returned cars with no operation started by the day's end: unserved (first operation due before the end) and
--     deferred (due at or after it), with the operation an unserved car waits on first
WITH runs(pair_id, arm, sim_run_id) AS (
  SELECT p.pair_id, 'off', p.run_a FROM public.ottoq_dial_pair_ledger p WHERE p.pair_id IN (119, 120)
  UNION ALL SELECT p.pair_id, 'on', p.run_b FROM public.ottoq_dial_pair_ledger p WHERE p.pair_id IN (119, 120)),
pairs AS (
  SELECT ru.pair_id, ru.arm, d.dispatch_id, r.sim_clock_current AS run_reached,
         min(l.actual_start_sim) FILTER (WHERE l.actual_start_sim >= d.actual_return_at) AS first_op_active_at,
         min(l.planned_start_sim) FILTER (WHERE l.planned_start_sim >= d.actual_return_at) AS first_work_planned_at,
         (array_agg(l.leg_type ORDER BY l.planned_start_sim) FILTER (WHERE l.planned_start_sim >= d.actual_return_at))[1] AS first_leg
    FROM runs ru
    JOIN public.ottoq_vehicle_dispatches d ON d.sim_run_id = ru.sim_run_id
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
    LEFT JOIN public.ottoq_itinerary_legs l ON l.sim_run_id = d.sim_run_id AND l.vehicle_id = d.vehicle_id
                                           AND l.leg_type <> ALL (ARRAY['taxi', 'stage'])
   WHERE d.actual_return_at IS NOT NULL AND d.actual_return_at <= r.sim_clock_current
   GROUP BY ru.pair_id, ru.arm, d.dispatch_id, d.actual_return_at, r.sim_clock_current)
SELECT pair_id, arm, count(*) AS admitted,
       count(*) FILTER (WHERE first_op_active_at IS NOT NULL) AS served,
       count(*) FILTER (WHERE first_op_active_at IS NULL AND first_work_planned_at < run_reached) AS unserved,
       count(*) FILTER (WHERE first_op_active_at IS NULL AND first_work_planned_at >= run_reached) AS deferred,
       count(*) FILTER (WHERE first_op_active_at IS NULL AND first_work_planned_at IS NULL) AS no_work_planned,
       round(100.0 * count(*) FILTER (WHERE first_op_active_at IS NULL) / count(*), 1) AS not_served_pct,
       (SELECT string_agg(z.leg || ' ' || z.n, ', ' ORDER BY z.n DESC, z.leg) FROM (
          SELECT q.first_leg AS leg, count(*) AS n FROM pairs q
           WHERE q.pair_id = pairs.pair_id AND q.arm = pairs.arm AND q.first_op_active_at IS NULL
             AND q.first_work_planned_at < q.run_reached GROUP BY 1) z) AS unserved_wait_on_first
  FROM pairs GROUP BY pair_id, arm ORDER BY pair_id, arm DESC;

-- (5) Minutes per point on the kernel's own minutes model, a 75 kWh pack on a 250 kW inlet
SELECT kind, soc_from, soc_to, public.ottoq_charge_minutes_estimate(75, soc_from, soc_to, kw, 250) AS minutes,
       round(public.ottoq_charge_minutes_estimate(75, soc_from, soc_to, kw, 250) / (soc_to - soc_from), 2) AS min_per_point
  FROM (VALUES ('dcfc 150 kW', 30, 80, 150), ('dcfc 150 kW', 85, 100, 150),
               ('l2 11 kW', 30, 80, 11), ('l2 11 kW', 85, 100, 11)) v(kind, soc_from, soc_to, kw);

-- (6) The gate: terminal on the first counted pair with more returns unserved
SELECT m[1] AS line
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
       regexp_matches(p.prosrc, '([^\n]*(v_unserved_worse|inviolable)[^\n]*)', 'g') m
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_dial_experiment_verdict';

-- (7) How far returns_unserved moves between the arms of a pair, per experiment (treatment minus control, in pair order)
SELECT x.param_key, x.control_value, x.treatment_value, left(x.experiment_id::text, 8) AS experiment, x.status,
       x.verdict ->> 'outcome' AS concluded_as,
       string_agg(((p.metrics_b ->> 'returns_unserved')::numeric - (p.metrics_a ->> 'returns_unserved')::numeric)::int::text,
                  ', ' ORDER BY p.pair_id) AS treatment_minus_control
  FROM public.ottoq_dial_pair_ledger p JOIN public.ottoq_dial_experiments x USING (experiment_id)
 WHERE p.complete AND p.world_identical AND p.differs
   AND p.metrics_a ? 'returns_unserved' AND p.metrics_b ? 'returns_unserved'
 GROUP BY x.experiment_id, x.param_key, x.control_value, x.treatment_value, x.status, x.verdict
 ORDER BY min(p.pair_id);

-- (8) The promoter on any outcome but a treatment win: conclude, write no dial
SELECT m[1] AS line
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
       regexp_matches(p.prosrc, '([^\n]*(treatment_wins|verdict_|v_outcome = ''enacted'')[^\n]*)', 'g') m
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_promote_dial_experiment';
